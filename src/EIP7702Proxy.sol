// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import {Proxy} from "openzeppelin-contracts/contracts/proxy/Proxy.sol";
import {ERC1967Utils} from "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Utils.sol";
import {ECDSA} from "openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";

import {NonceTracker} from "./NonceTracker.sol";

/// @title EIP7702Proxy
///
/// @notice Proxy contract designed for EIP-7702 smart accounts
///
/// @dev Implements ERC-1967 with an initial implementation address and guarded initializer function
///
/// @author Coinbase (https://github.com/base/eip-7702-proxy)
contract EIP7702Proxy is Proxy {
    /// @notice ERC-1271 interface constants
    bytes4 internal constant _ERC1271_MAGIC_VALUE = 0x1626ba7e;
    bytes4 internal constant _ERC1271_FAIL_VALUE = 0xffffffff;

    /// @notice Typehash for initialization signatures
    bytes32 internal constant _INITIALIZATION_TYPEHASH =
        keccak256(
            "EIP7702ProxyInitialization(uint256 chainId,address proxy,uint256 nonce,bytes args)"
        );

    /// @notice Typehash for resetting implementation, including chainId and current implementation
    bytes32 internal constant _IMPLEMENTATION_RESET_TYPEHASH =
        keccak256(
            "EIP7702ProxyImplementationReset(uint256 chainId,address proxy,uint256 nonce,address currentImplementation,address newImplementation)"
        );

    /// @notice Initial implementation address set during construction
    address public immutable INITIAL_IMPLEMENTATION;

    /// @notice Function selector on the implementation that is guarded from direct calls
    bytes4 public immutable GUARDED_INITIALIZER;

    /// @notice Address of the global nonce tracker for initialization
    NonceTracker public immutable NONCE_TRACKER;

    /// @notice Address of this proxy contract delegate
    address internal immutable _PROXY;

    /// @notice Constructor arguments are zero
    error ZeroValueConstructorArguments();

    /// @notice Initialization signature is invalid
    error InvalidSignature();

    /// @notice Call to `GUARDED_INITIALIZER` attempted
    error InvalidInitializer();

    /// @notice Initializes the proxy with an initial implementation and guarded initializer
    ///
    /// @param implementation The initial implementation address
    /// @param initializer The selector of the initializer function on `implementation` to guard
    /// @param nonceTracker The address of the nonce tracker contract
    constructor(
        address implementation,
        bytes4 initializer,
        NonceTracker nonceTracker
    ) {
        if (implementation == address(0))
            revert ZeroValueConstructorArguments();
        if (initializer == bytes4(0)) revert ZeroValueConstructorArguments();
        if (address(nonceTracker) == address(0))
            revert ZeroValueConstructorArguments();

        INITIAL_IMPLEMENTATION = implementation;
        GUARDED_INITIALIZER = initializer;
        NONCE_TRACKER = nonceTracker;
        _PROXY = address(this);
    }

    /// @notice Allow the account to receive ETH under any circumstances
    receive() external payable {}

    /// @notice Initializes the proxy and implementation with a signed payload
    ///
    /// @dev Signature must be from this contract's address
    ///
    /// @param args The initialization arguments for the implementation
    /// @param signature The signature authorizing initialization
    /// @param crossChainReplayable use a chain-agnostic or chain-specific hash
    function initialize(
        bytes calldata args,
        bytes calldata signature,
        bool crossChainReplayable
    ) external {
        // Construct hash using typehash to prevent signature collisions
        bytes32 initHash = keccak256(
            abi.encode(
                _INITIALIZATION_TYPEHASH,
                crossChainReplayable ? 0 : block.chainid,
                _PROXY,
                NONCE_TRACKER.useNonce(),
                keccak256(args)
            )
        );

        // Verify signature is from this address (the EOA)
        address signer = ECDSA.recover(initHash, signature);
        if (signer != address(this)) revert InvalidSignature();

        // Initialize the implementation
        ERC1967Utils.upgradeToAndCall(
            INITIAL_IMPLEMENTATION,
            abi.encodePacked(GUARDED_INITIALIZER, args)
        );
    }

    /// @notice Resets the ERC-1967 implementation slot after signature verification, allowing the account to
    ///         correct the implementation address if it's ever changed by an unknown delegate or implementation.
    ///
    /// @dev Signature must be from the EOA's address that is 7702-delegating to this proxy
    ///
    /// @param newImplementation The implementation address to set
    /// @param signature The EOA signature authorizing this change
    /// @param crossChainReplayable use a chain-agnostic or chain-specific hash
    function resetImplementation(
        address newImplementation,
        bytes calldata signature,
        bool crossChainReplayable
    ) external {
        // Construct hash using typehash to prevent signature collisions
        bytes32 resetHash = keccak256(
            abi.encode(
                _IMPLEMENTATION_RESET_TYPEHASH,
                crossChainReplayable ? 0 : block.chainid,
                _PROXY,
                NONCE_TRACKER.useNonce(),
                ERC1967Utils.getImplementation(),
                newImplementation
            )
        );

        // Verify signature is from this address (the EOA)
        address signer = ECDSA.recover(resetHash, signature);
        if (signer != address(this)) revert InvalidSignature();

        // Reset the implementation slot
        ERC1967Utils.upgradeToAndCall(newImplementation, "");
    }

    /// @notice Handles ERC-1271 signature validation by enforcing a final `ecrecover` check if signatures fail `isValidSignature` check
    ///
    /// @dev This ensures EOA signatures are considered valid regardless of the implementation's `isValidSignature` implementation
    ///
    /// @dev When calling `isValidSignature` from the implementation contract, note that calling `this.isValidSignature` will invoke this
    ///      function and make an `ecrecover` check, whereas calling a public `isValidSignature` directly from the implementation contract will not.
    ///
    /// @param hash The hash of the message being signed
    /// @param signature The signature of the message
    ///
    /// @return The result of the `isValidSignature` check
    function isValidSignature(
        bytes32 hash,
        bytes calldata signature
    ) external returns (bytes4) {
        // First try delegatecall to implementation
        (bool success, bytes memory result) = _implementation().delegatecall(
            msg.data
        );

        // If delegatecall succeeded and returned magic value, return that
        if (
            success &&
            result.length == 32 &&
            bytes4(result) == _ERC1271_MAGIC_VALUE
        ) {
            return _ERC1271_MAGIC_VALUE;
        }

        // Only return success if there was no error and the signer matches
        (address recovered, ECDSA.RecoverError error, ) = ECDSA.tryRecover(
            hash,
            signature
        );
        if (error == ECDSA.RecoverError.NoError && recovered == address(this)) {
            return _ERC1271_MAGIC_VALUE;
        }

        // If all checks fail, return failure value
        return _ERC1271_FAIL_VALUE;
    }

    /// @notice Returns the implementation address, falling back to the initial implementation if the ERC-1967 implementation slot is not set
    ///
    /// @return implementation The implementation address for this EOA
    function _implementation() internal view override returns (address) {
        address implementation = ERC1967Utils.getImplementation();
        return
            implementation == address(0)
                ? INITIAL_IMPLEMENTATION
                : implementation;
    }

    /// @inheritdoc Proxy
    /// @dev Guards a specified initializer function from being called directly
    function _fallback() internal override {
        // block guarded initializer from being called
        if (msg.sig == GUARDED_INITIALIZER) revert InvalidInitializer();

        _delegate(_implementation());
    }
}
