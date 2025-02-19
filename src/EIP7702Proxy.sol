// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import {Proxy} from "openzeppelin-contracts/contracts/proxy/Proxy.sol";
import {ERC1967Utils} from "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Utils.sol";
import {ECDSA} from "openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";
import {StorageSlot} from "openzeppelin-contracts/contracts/utils/StorageSlot.sol";

import {NonceTracker} from "./NonceTracker.sol";

/// @title EIP7702Proxy
///
/// @notice Proxy contract designed for EIP-7702 smart accounts
///
/// @dev Implements ERC-1967 with an initial implementation address and guarded initializer function
///
/// @author Coinbase (https://github.com/base/eip-7702-proxy)
contract EIP7702Proxy is Proxy {
    /// @notice ERC1271 interface constants
    bytes4 internal constant ERC1271_MAGIC_VALUE = 0x1626ba7e;
    bytes4 internal constant ERC1271_FAIL_VALUE = 0xffffffff;

    /// @notice Typehash for initialization signatures
    bytes32 private constant INIT_TYPEHASH =
        keccak256("EIP7702ProxyInitialization(uint256 chainId,address proxy,bytes32 args,uint256 nonce)");

    /// @notice Typehash for resetting implementation, including chainId and current implementation
    bytes32 private constant RESET_IMPLEMENTATION_TYPEHASH = keccak256(
        "EIP7702ProxyImplementationReset(uint256 chainId,address proxy,uint256 nonce,address currentImplementation,address newImplementation)"
    );

    /// @notice Address of this proxy contract delegate
    address immutable PROXY;

    /// @notice Initial implementation address set during construction
    address immutable INITIAL_IMPLEMENTATION;

    /// @notice Function selector on the implementation that is guarded from direct calls
    bytes4 immutable GUARDED_INITIALIZER;

    /// @notice Address of the global nonce tracker for initialization
    NonceTracker public immutable NONCE_TRACKER;

    /// @notice Emitted when the initialization signature is invalid
    error InvalidSignature();

    /// @notice Emitted when the `guardedInitializer` is called
    error InvalidInitializer();

    /// @notice Emitted when trying to delegate before initialization
    error ProxyNotInitialized();

    /// @notice Emitted when constructor arguments are zero
    error ZeroValueConstructorArguments();

    /// @notice Error when nonce verification fails
    error InvalidNonce(uint256 expected, uint256 actual);

    /// @notice Emitted when the chain ID is invalid
    error InvalidChainId();

    /// @notice Initializes the proxy with an initial implementation and guarded initializer
    ///
    /// @param implementation The initial implementation address
    /// @param initializer The selector of the `guardedInitializer` function
    /// @param _nonceTracker The address of the nonce tracker contract
    constructor(address implementation, bytes4 initializer, NonceTracker _nonceTracker) {
        if (implementation == address(0)) {
            revert ZeroValueConstructorArguments();
        }
        if (initializer == bytes4(0)) revert ZeroValueConstructorArguments();
        if (address(_nonceTracker) == address(0)) {
            revert ZeroValueConstructorArguments();
        }

        PROXY = address(this);
        INITIAL_IMPLEMENTATION = implementation;
        GUARDED_INITIALIZER = initializer;
        NONCE_TRACKER = _nonceTracker;
    }

    /// @notice Allow the account to receive ETH under any circumstances
    receive() external payable {}

    /// @notice Initializes the proxy and implementation with a signed payload
    ///
    /// @dev Signature must be from this contract's address
    ///
    /// @param args The initialization arguments for the implementation
    /// @param signature The signature authorizing initialization
    /// @param chainId Optional: if 0, allows cross-chain signatures
    function initialize(bytes calldata args, bytes calldata signature, uint256 chainId) external {
        uint256 expectedNonce = NONCE_TRACKER.getNextNonce(address(this));

        // Verify chain ID if specified (revert if non-zero and doesn't match)
        uint256 currentChainId = block.chainid;
        if (chainId != 0 && chainId != currentChainId) {
            revert InvalidChainId();
        }

        // Construct hash using typehash to prevent signature collisions
        bytes32 initHash = keccak256(
            abi.encode(INIT_TYPEHASH, chainId == 0 ? 0 : currentChainId, PROXY, keccak256(args), expectedNonce)
        );

        // Verify signature is from the EOA
        address signer = ECDSA.recover(initHash, signature);
        if (signer != address(this)) revert InvalidSignature();

        // Verify and consume the nonce, reverts if invalid
        NONCE_TRACKER.verifyAndUseNonce(expectedNonce);

        // Initialize the implementation
        ERC1967Utils.upgradeToAndCall(INITIAL_IMPLEMENTATION, abi.encodePacked(GUARDED_INITIALIZER, args));
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
    function isValidSignature(bytes32 hash, bytes calldata signature) external returns (bytes4) {
        // First try delegatecall to implementation
        (bool success, bytes memory result) = _implementation().delegatecall(msg.data);

        // If delegatecall succeeded and returned magic value, return that
        if (success && result.length == 32 && bytes4(result) == ERC1271_MAGIC_VALUE) {
            return ERC1271_MAGIC_VALUE;
        }

        // Try ECDSA recovery with error checking
        (address recovered, ECDSA.RecoverError error,) = ECDSA.tryRecover(hash, signature);
        // Only return success if there was no error and the signer matches
        if (error == ECDSA.RecoverError.NoError && recovered == address(this)) {
            return ERC1271_MAGIC_VALUE;
        }

        // If all checks fail, return failure value
        return ERC1271_FAIL_VALUE;
    }

    /// @notice Resets the ERC-1967 implementation slot after signature verification, allowing the account to
    ///         correct the implementation address if it's ever changed by an unknown delegate or implementation.
    ///
    /// @dev Signature must be from the EOA's address that is 7702-delegating to this proxy
    ///
    /// @param newImplementation The implementation address to set
    /// @param signature The EOA signature authorizing this change
    /// @param chainId Optional: if 0, allows cross-chain signatures
    function resetImplementation(address newImplementation, bytes calldata signature, uint256 chainId) external {
        // Get expected nonce from tracker
        uint256 expectedNonce = NONCE_TRACKER.getNextNonce(address(this));

        // Get current chain ID and implementation
        uint256 currentChainId = block.chainid;
        address currentImplementation = ERC1967Utils.getImplementation();

        // Verify chain ID if specified (revert if non-zero and doesn't match)
        if (chainId != 0 && chainId != currentChainId) {
            revert InvalidChainId();
        }

        // Construct hash using typehash to prevent signature collisions
        bytes32 resetHash = keccak256(
            abi.encode(
                RESET_IMPLEMENTATION_TYPEHASH,
                PROXY,
                currentImplementation,
                newImplementation,
                chainId == 0 ? 0 : currentChainId,
                expectedNonce
            )
        );

        // Verify signature is from this address (the EOA)
        address signer = ECDSA.recover(resetHash, signature);
        if (signer != address(this)) revert InvalidSignature();

        // Verify and consume the nonce, reverts if invalid
        NONCE_TRACKER.verifyAndUseNonce(expectedNonce);

        // Reset the implementation slot
        ERC1967Utils.upgradeToAndCall(newImplementation, "");
    }

    /// @notice Returns the implementation address, falling back to the initial implementation if the ERC-1967 implementation slot is not set
    ///
    /// @return The implementation address
    function _implementation() internal view override returns (address) {
        address implementation = ERC1967Utils.getImplementation();
        if (implementation == address(0)) return INITIAL_IMPLEMENTATION;
        return implementation;
    }

    /// @inheritdoc Proxy
    /// @dev Handles ERC-1271 signature validation by enforcing an ecrecover check if signatures fail `isValidSignature` check
    /// @dev Guards a specified initializer function from being called directly
    function _fallback() internal override {
        // block guarded initializer from being called
        if (msg.sig == GUARDED_INITIALIZER) revert InvalidInitializer();

        _delegate(_implementation());
    }
}
