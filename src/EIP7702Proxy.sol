// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import {Proxy} from "openzeppelin-contracts/contracts/proxy/Proxy.sol";
import {ERC1967Utils} from "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Utils.sol";
import {ECDSA} from "openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";
import {Receiver} from "solady/accounts/Receiver.sol";

import {NonceTracker} from "./NonceTracker.sol";
import {DefaultReceiver} from "./DefaultReceiver.sol";
import {IWalletValidator} from "./interfaces/IWalletValidator.sol";

/// @title EIP7702Proxy
///
/// @notice Proxy contract designed for EIP-7702 smart accounts
///
/// @dev Implements ERC-1967 with a signature-based initialization process
///
/// @author Coinbase (https://github.com/base/eip-7702-proxy)
contract EIP7702Proxy is Proxy {
    /// @notice ERC-1271 interface constants
    bytes4 internal constant _ERC1271_MAGIC_VALUE = 0x1626ba7e;
    bytes4 internal constant _ERC1271_FAIL_VALUE = 0xffffffff;

    /// @notice Typehash for setting implementation
    bytes32 internal constant _IMPLEMENTATION_SET_TYPEHASH = keccak256(
        "EIP7702ProxyImplementationSet(uint256 chainId,address proxy,uint256 nonce,address currentImplementation,address newImplementation,bytes callData,address validator)"
    );

    /// @notice A default implementation that allows this address to receive tokens before initialization
    Receiver public immutable receiver;

    /// @notice Address of the global nonce tracker for initialization
    NonceTracker public immutable nonceTracker;

    /// @notice Address of this proxy contract delegate
    address internal immutable _proxy;

    /// @notice Constructor arguments are zero
    error ZeroValueConstructorArguments();

    /// @notice Initialization signature is invalid
    error InvalidSignature();

    /// @notice Initializes the proxy with a default receiver implementation and nonce tracker
    ///
    /// @param nonceTracker The address of the nonce tracker contract
    /// @param receiver The address of the receiver contract
    constructor(NonceTracker nonceTracker, Receiver receiver) {
        if (address(receiver) == address(0)) {
            revert ZeroValueConstructorArguments();
        }
        if (address(nonceTracker) == address(0)) {
            revert ZeroValueConstructorArguments();
        }

        nonceTracker = nonceTracker;
        receiver = receiver;
        _proxy = address(this);
    }

    /// @notice Sets the ERC-1967 implementation slot after signature verification and optionally executes `callData` on the `newImplementation`
    ///
    /// @dev Validates resulting wallet state after upgrade by calling `validateWalletState` on the supplied validator contract
    /// @dev Signature must be from the EOA's address
    ///
    /// @param newImplementation The implementation address to set
    /// @param callData Optional calldata to call on new implementation
    /// @param validator The address of the validator contract
    /// @param signature The EOA signature authorizing this change
    /// @param allowCrossChainReplay use a chain-agnostic or chain-specific hash
    function setImplementation(
        address newImplementation,
        bytes calldata callData,
        address validator,
        bytes calldata signature,
        bool allowCrossChainReplay
    ) external {
        // Construct hash using typehash to prevent signature collisions
        bytes32 hash = keccak256(
            abi.encode(
                _IMPLEMENTATION_SET_TYPEHASH,
                allowCrossChainReplay ? 0 : block.chainid,
                _proxy,
                nonceTracker.useNonce(),
                ERC1967Utils.getImplementation(),
                newImplementation,
                keccak256(callData),
                validator
            )
        );

        // Verify signature is from this address (the EOA)
        address signer = ECDSA.recover(hash, signature);
        if (signer != address(this)) revert InvalidSignature();

        // Reset the implementation slot and call initialization if provided
        ERC1967Utils.upgradeToAndCall(newImplementation, callData);

        // Validate wallet state after upgrade, reverting if invalid
        IWalletValidator(validator).validateWalletState(address(this));
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
        if (success && result.length == 32 && bytes4(result) == _ERC1271_MAGIC_VALUE) {
            return _ERC1271_MAGIC_VALUE;
        }

        // Only return success if there was no error and the signer matches
        (address recovered, ECDSA.RecoverError error,) = ECDSA.tryRecover(hash, signature);
        if (error == ECDSA.RecoverError.NoError && recovered == address(this)) {
            return _ERC1271_MAGIC_VALUE;
        }

        // If all checks fail, return failure value
        return _ERC1271_FAIL_VALUE;
    }

    /// @notice Returns the ERC-1967 implementation address, or the default receiver if
    ///         the implementation is not set
    ///
    /// @return implementation The implementation address for this proxy
    function _implementation() internal view override returns (address) {
        address implementation = ERC1967Utils.getImplementation();
        return implementation == address(0) ? address(receiver) : implementation;
    }
}
