// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import {IWalletValidator} from "../../src/interfaces/IWalletValidator.sol";
import {MockImplementation} from "./MockImplementation.sol";

/**
 * @title MockValidator
 * @dev Mock validator that checks if the MockImplementation wallet is initialized
 */
contract MockValidator is IWalletValidator {
    error WalletNotInitialized();

    /**
     * @dev Validates that the wallet is initialized
     * @param wallet Address of the wallet to validate
     */
    function validateWalletState(address wallet) external view {
        bool isInitialized = MockImplementation(wallet).initialized();
        if (!isInitialized) revert WalletNotInitialized();
    }
}
