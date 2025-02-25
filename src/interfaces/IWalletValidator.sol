// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

/// @title IWalletValidator
/// @notice Interface for wallet-specific validation logic
///
/// @dev This interface is used to validate the state of a wallet after an upgrade
///
/// @author Coinbase (https://github.com/base/eip-7702-proxy)
interface IWalletValidator {
    /// @notice Validates that a wallet is in a valid state
    /// @dev Should revert if wallet state is invalid
    /// @param wallet The address of the wallet to validate
    function validateWalletState(address wallet) external view;
}
