// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import {IWalletValidator} from "../interfaces/IWalletValidator.sol";
import {MultiOwnable} from "smart-wallet/MultiOwnable.sol";

/// @title CoinbaseSmartWalletValidator
/// @notice Validates Coinbase Smart Wallet specific invariants
contract CoinbaseSmartWalletValidator is IWalletValidator {
    /// @notice Error thrown when a wallet has no owners
    error Unintialized();

    /// @notice Validates that a Coinbase Smart Wallet has at least one owner
    /// @param wallet The address of the wallet to validate
    function validateWalletState(address wallet) external view override {
        // Cast to MultiOwnable to check owner count
        MultiOwnable walletContract = MultiOwnable(wallet);

        // Ensure at least one owner exists
        if (walletContract.nextOwnerIndex() == 0) {
            revert Unintialized();
        }
    }
}
