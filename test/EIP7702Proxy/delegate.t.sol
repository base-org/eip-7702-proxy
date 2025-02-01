// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import {EIP7702ProxyBase} from "../base/EIP7702ProxyBase.sol";
import {EIP7702Proxy} from "../../src/EIP7702Proxy.sol";
import {MockImplementation} from "../mocks/MockImplementation.sol";

contract DelegateTest is EIP7702ProxyBase {
    function setUp() public override {
        super.setUp();

        // Initialize the proxy
        bytes memory initArgs = _createInitArgs(_newOwner);
        bytes memory signature = _signInitData(_EOA_PRIVATE_KEY, initArgs);
        EIP7702Proxy(_eoa).initialize(initArgs, signature);
    }

    function test_succeeds_whenReadingState() public {
        assertEq(
            MockImplementation(payable(_eoa)).owner(),
            _newOwner,
            "Delegated read call should succeed"
        );
    }

    function test_succeeds_whenWritingState() public {
        vm.prank(_newOwner);
        MockImplementation(payable(_eoa)).mockFunction();
    }

    function test_preservesReturnData_whenReturningBytes(
        bytes memory testData
    ) public {
        bytes memory returnedData = MockImplementation(payable(_eoa))
            .returnBytesData(testData);

        assertEq(
            returnedData,
            testData,
            "Complex return data should be correctly delegated"
        );
    }

    function test_guardedInitializer_reverts_whenCalledDirectly(
        bytes memory initData
    ) public {
        vm.assume(initData.length >= 4); // At least a function selector

        vm.expectRevert(EIP7702Proxy.InvalidInitializer.selector);
        address(_eoa).call(initData);
    }

    function test_reverts_whenReadReverts() public {
        vm.expectRevert("MockRevert");
        MockImplementation(payable(_eoa)).revertingFunction();
    }

    function test_reverts_whenWriteReverts(address unauthorized) public {
        vm.assume(unauthorized != address(0));
        vm.assume(unauthorized != _newOwner); // Not the owner

        vm.prank(unauthorized);
        vm.expectRevert(MockImplementation.Unauthorized.selector);
        MockImplementation(payable(_eoa)).mockFunction();

        assertFalse(
            MockImplementation(payable(_eoa)).mockFunctionCalled(),
            "State should not change when write fails"
        );
    }

    function test_reverts_whenCallingBeforeInitialization() public {
        // Deploy a fresh proxy without initializing it
        address payable uninitProxy = payable(makeAddr("uninitProxy"));
        _deployProxy(uninitProxy);

        vm.expectRevert(EIP7702Proxy.ProxyNotInitialized.selector);
        MockImplementation(payable(uninitProxy)).owner();
    }

    function test_reverts_whenCallingWithArbitraryDataBeforeInitialization(
        bytes memory arbitraryCalldata
    ) public {
        // Deploy a fresh proxy without initializing it
        address payable uninitProxy = payable(makeAddr("uninitProxy"));
        _deployProxy(uninitProxy);

        // Test that it reverts with the correct error
        vm.expectRevert(EIP7702Proxy.ProxyNotInitialized.selector);
        address(uninitProxy).call(arbitraryCalldata);

        // Also verify the low-level call fails
        (bool success, ) = address(uninitProxy).call(arbitraryCalldata);
        assertFalse(success, "Low-level call should fail");
    }
}
