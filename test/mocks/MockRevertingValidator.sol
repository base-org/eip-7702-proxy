// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import {IWalletValidator} from "../../src/interfaces/IWalletValidator.sol";
import {MockImplementation} from "./MockImplementation.sol";

/**
 * @title MockRevertingValidator
 * @dev Mock validator that always reverts
 */
contract MockRevertingValidator is IWalletValidator {
    error AlwaysReverts();

    /**
     * @dev Reverts
     * @param wallet Address of the wallet to validate
     */
    function validateWalletState(address wallet) external view {
        revert AlwaysReverts();
    }
}
