// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import {Test} from "forge-std/Test.sol";
import {NonceTracker} from "../src/NonceTracker.sol";

contract NonceTrackerTest is Test {
    NonceTracker public nonceTracker;
    address public account;
    uint256 constant ACCOUNT_PK = 0xA11CE;

    event NonceUsed(address indexed account, uint256 nonce);

    function setUp() public {
        nonceTracker = new NonceTracker();
        account = vm.addr(ACCOUNT_PK);
    }

    function test_nonces_initialNonceIsZero() public {
        assertEq(nonceTracker.nonces(account), 0, "Initial nonce should be zero");
    }

    function test_useNonce_incrementsNonce_afterVerification() public {
        uint256 nonce = nonceTracker.nonces(account);

        vm.prank(account);
        nonceTracker.useNonce();
        assertEq(nonceTracker.nonces(account), nonce + 1, "Nonce should increment after use");
    }

    function test_useNonce_emitsEvent_whenNonceUsed() public {
        uint256 nonce = nonceTracker.nonces(account);

        vm.expectEmit(true, false, false, true);
        emit NonceUsed(account, nonce);
        vm.prank(account);
        nonceTracker.useNonce();
    }

    function test_nonces_maintainsCorrectNonce_afterMultipleIncrements(uint8 incrementCount) public {
        uint256 expectedNonce = 0;

        for (uint256 i = 0; i < incrementCount; i++) {
            assertEq(nonceTracker.nonces(account), expectedNonce, "Incorrect nonce before increment");

            vm.prank(account);
            nonceTracker.useNonce();

            expectedNonce++;
        }

        assertEq(nonceTracker.nonces(account), expectedNonce, "Final nonce incorrect");
    }

    function test_nonces_tracksNoncesIndependently_forDifferentAccounts(address otherAccount) public {
        vm.assume(otherAccount != account);

        // Use account's nonce
        uint256 accountNonce = nonceTracker.nonces(account);
        vm.prank(account);
        nonceTracker.useNonce();

        // Other account's nonce should still be 0
        assertEq(nonceTracker.nonces(otherAccount), 0, "Other account's nonce should be independent");
    }
}
