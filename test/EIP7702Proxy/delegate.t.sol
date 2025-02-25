// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import {EIP7702Proxy} from "../../src/EIP7702Proxy.sol";
import {DefaultReceiver} from "../../src/DefaultReceiver.sol";
import {EIP7702ProxyBase} from "../base/EIP7702ProxyBase.sol";
import {MockImplementation} from "../mocks/MockImplementation.sol";

contract DelegateTest is EIP7702ProxyBase {
    function setUp() public override {
        super.setUp();
        _initializeProxy();
    }

    function test_succeeds_whenReadingState() public {
        assertEq(MockImplementation(payable(_eoa)).owner(), _newOwner, "Delegated read call should succeed");
    }

    function test_succeeds_whenWritingState() public {
        vm.prank(_newOwner);
        MockImplementation(payable(_eoa)).mockFunction();
    }

    function test_preservesReturnData_whenReturningBytes(bytes memory testData) public {
        bytes memory returnedData = MockImplementation(payable(_eoa)).returnBytesData(testData);

        assertEq(returnedData, testData, "Complex return data should be correctly delegated");
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

        assertFalse(MockImplementation(payable(_eoa)).mockFunctionCalled(), "State should not change when write fails");
    }

    function test_continues_delegating_afterUpgrade() public {
        assertEq(MockImplementation(payable(_eoa)).owner(), _newOwner, "Owner should be set");

        // Deploy a new implementation
        MockImplementation newImplementation = new MockImplementation();

        // Create signature for upgrade
        bytes memory signature = _signSetImplementationData(
            _EOA_PRIVATE_KEY,
            address(newImplementation),
            0, // chainId 0 for cross-chain
            ""
        );

        // Upgrade to the new implementation
        EIP7702Proxy(_eoa).setImplementation(
            address(newImplementation),
            "", // no init data needed
            address(_validator),
            signature,
            true
        );

        // Verify the implementation was changed
        assertEq(_getERC1967Implementation(_eoa), address(newImplementation), "Implementation should be updated");

        // Try to make a call through the proxy
        vm.prank(_newOwner);
        MockImplementation(_eoa).mockFunction();

        // Verify the call succeeded (new implementation shares ownership state with original implementation)
        assertTrue(MockImplementation(_eoa).mockFunctionCalled(), "Should be able to call through proxy after upgrade");
    }

    function test_allows_ethTransfersBeforeInitialization() public {
        // Deploy a fresh proxy without initializing it
        address payable uninitProxy = payable(makeAddr("uninitProxy"));
        _deployProxy(uninitProxy);

        // Should succeed with empty calldata and ETH value
        (bool success,) = uninitProxy.call{value: 1 ether}("");
        assertTrue(success, "ETH transfer should succeed");
        assertEq(address(uninitProxy).balance, 1 ether);
    }

    function test_reverts_whenCallingWithArbitraryDataBeforeInitialization(bytes calldata data) public {
        // Skip empty calls or pure ETH transfers
        vm.assume(data.length > 0);

        // Deploy a fresh proxy without initializing it
        address payable uninitProxy = payable(makeAddr("uninitProxy"));
        _deployProxy(uninitProxy);

        // Try to make the call and capture the result
        (bool success,) = uninitProxy.call(data);

        // The call should fail since the proxy is uninitialized and the data is non-empty
        assertFalse(success, "Call with arbitrary data should fail on uninitialized proxy");

        vm.expectRevert();
        (success,) = uninitProxy.call(data);
    }
}
