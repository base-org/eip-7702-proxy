// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import {Proxy} from "openzeppelin-contracts/contracts/proxy/Proxy.sol";
import {ERC1967Utils} from "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Utils.sol";
import {ECDSA} from "openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";
import {StorageSlot} from "openzeppelin-contracts/contracts/utils/StorageSlot.sol";

/// @title EIP7702Proxy
/// @notice Proxy contract designed for EIP-7702 smart accounts
/// @dev Implements ERC-1967 with an initial implementation address and guarded initializer function
/// @author Coinbase (https://github.com/base-org/eip-7702-proxy)
contract EIP7702Proxy is Proxy {
    /// @notice ERC1271 interface constants
    bytes4 internal constant ERC1271_MAGIC_VALUE = 0x1626ba7e;
    bytes4 internal constant ERC1271_FAIL_VALUE = 0xffffffff;

    /// @notice Typehash for initialization signatures
    bytes32 private constant INIT_TYPEHASH =
        keccak256("EIP7702ProxyInitialize(address proxy,bytes args)");

    /// @notice Address of this proxy contract delegate
    address immutable proxy;

    /// @notice Initial implementation address set during construction
    address immutable initialImplementation;

    /// @notice Function selector on the implementation that is guarded from direct calls
    bytes4 immutable guardedInitializer;

    /// @notice Emitted when the initialization signature is invalid
    error InvalidSignature();

    /// @notice Emitted when the `guardedInitializer` is called
    error InvalidInitializer();

    /// @notice Emitted when trying to delegate before initialization
    error ProxyNotInitialized();

    /// @notice Emitted when constructor arguments are zero
    error ZeroValueConstructorArguments();

    /// @notice Initializes the proxy with an initial implementation and guarded initializer
    /// @param implementation The initial implementation address
    /// @param initializer The selector of the `guardedInitializer` function
    constructor(address implementation, bytes4 initializer) {
        if (implementation == address(0))
            revert ZeroValueConstructorArguments();
        if (initializer == bytes4(0)) revert ZeroValueConstructorArguments();

        proxy = address(this);
        initialImplementation = implementation;
        guardedInitializer = initializer;
    }

    /// @notice Initializes the proxy and implementation with a signed payload
    ///
    /// @dev Signature must be from this contract's address
    ///
    /// @param args The initialization arguments for the implementation
    /// @param signature The signature authorizing initialization
    function initialize(
        bytes calldata args,
        bytes calldata signature
    ) external {
        // Construct hash using typehash to prevent signature collisions
        bytes32 hash = keccak256(
            abi.encode(INIT_TYPEHASH, proxy, keccak256(args))
        );
        address recovered = ECDSA.recover(hash, signature);
        if (recovered != address(this)) revert InvalidSignature();

        // Set the ERC-1967 implementation slot, emit Upgraded event, call the initializer
        ERC1967Utils.upgradeToAndCall(
            initialImplementation,
            abi.encodePacked(guardedInitializer, args)
        );
    }

    /// @notice Handles ERC-1271 signature validation by enforcing a final `ecrecover` check if signatures fail `isValidSignature` check
    ///
    /// @dev This ensures EOA signatures are considered valid regardless of the implementation's `isValidSignature` implementation
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
            abi.decode(result, (bytes4)) == ERC1271_MAGIC_VALUE
        ) {
            return ERC1271_MAGIC_VALUE;
        }

        // Only try ECDSA if signature is the right length (65 bytes)
        if (signature.length == 65) {
            address recovered = ECDSA.recover(hash, signature);
            if (recovered == address(this)) {
                return ERC1271_MAGIC_VALUE;
            }
        }

        // If all checks fail, return failure value
        return ERC1271_FAIL_VALUE;
    }

    /// @inheritdoc Proxy
    /// @dev Handles ERC-1271 signature validation by enforcing an ecrecover check if signatures fail `isValidSignature` check
    /// @dev Guards a specified initializer function from being called directly
    function _fallback() internal override {
        // block guarded initializer from being called
        if (msg.sig == guardedInitializer) revert InvalidInitializer();

        _delegate(_implementation());
    }

    /// @notice Returns the implementation address, falling back to the initial implementation if the ERC-1967 implementation slot is not set
    /// @return The implementation address
    function _implementation() internal view override returns (address) {
        if (ERC1967Utils.getImplementation() == address(0))
            return initialImplementation;
        return ERC1967Utils.getImplementation();
    }

    /// @notice Allow the account to receive ETH under any circumstances
    receive() external payable {}
}
