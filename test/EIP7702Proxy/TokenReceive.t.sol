// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import {EIP7702Proxy} from "../../src/EIP7702Proxy.sol";

import {MockERC721} from "../mocks/MockERC721.sol";
import {MockERC1155} from "../mocks/MockERC1155.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {EIP7702ProxyBase} from "../base/EIP7702ProxyBase.sol";

contract TokenReceiveTest is EIP7702ProxyBase {
    MockERC721 public nft;
    MockERC1155 public multiToken;
    MockERC20 public token;
    uint256 constant TOKEN_ID = 1;
    uint256 constant AMOUNT = 1;
    uint256 constant TOKEN_AMOUNT = 1 ether;

    function setUp() public override {
        super.setUp();
        nft = new MockERC721();
        multiToken = new MockERC1155();
        token = new MockERC20();
    }

    function test_succeeds_ERC721Transfer_afterInitialization() public {
        nft.mint(address(this), TOKEN_ID);
        nft.safeTransferFrom(address(this), _eoa, TOKEN_ID);
        assertEq(nft.ownerOf(TOKEN_ID), _eoa);
    }

    function test_succeeds_ERC1155Transfer_afterInitialization() public {
        address regularAddress = makeAddr("regularHolder");
        multiToken.mint(regularAddress, TOKEN_ID, AMOUNT, "");

        vm.prank(regularAddress);
        multiToken.safeTransferFrom(regularAddress, _eoa, TOKEN_ID, AMOUNT, "");
        assertEq(multiToken.balanceOf(_eoa, TOKEN_ID), AMOUNT);
    }

    function test_succeeds_ERC20Transfer_afterInitialization() public {
        token.mint(address(this), TOKEN_AMOUNT);

        token.transfer(_eoa, TOKEN_AMOUNT);
        assertEq(token.balanceOf(_eoa), TOKEN_AMOUNT);
    }

    function test_succeeds_ERC721Transfer_beforeInitialization() public {
        // Deploy proxy without initializing
        address payable uninitProxy = payable(makeAddr("uninitProxy"));
        _deployProxy(uninitProxy);

        nft.mint(address(this), TOKEN_ID);
        nft.safeTransferFrom(address(this), uninitProxy, TOKEN_ID);
        assertEq(nft.ownerOf(TOKEN_ID), uninitProxy);
    }

    function test_succeeds_ERC1155Transfer_beforeInitialization() public {
        // Deploy proxy without initializing
        address payable uninitProxy = payable(makeAddr("uninitProxy"));
        _deployProxy(uninitProxy);

        address regularAddress = makeAddr("regularHolder");
        multiToken.mint(regularAddress, TOKEN_ID, AMOUNT, "");

        vm.prank(regularAddress);
        multiToken.safeTransferFrom(regularAddress, uninitProxy, TOKEN_ID, AMOUNT, "");
        assertEq(multiToken.balanceOf(uninitProxy, TOKEN_ID), AMOUNT);
    }

    function test_succeeds_ERC20Transfer_beforeInitialization() public {
        // Deploy proxy without initializing
        address payable uninitProxy = payable(makeAddr("uninitProxy"));
        _deployProxy(uninitProxy);

        token.mint(address(this), TOKEN_AMOUNT);
        token.transfer(uninitProxy, TOKEN_AMOUNT);
        assertEq(token.balanceOf(uninitProxy), TOKEN_AMOUNT);
    }

    function test_succeeds_ETHTransfer_afterInitialization() public {
        // Fund test contract
        vm.deal(address(this), 1 ether);

        // Send ETH to initialized wallet
        (bool success,) = _eoa.call{value: 1 ether}("");
        assertTrue(success);
        assertEq(_eoa.balance, 1 ether);
    }

    function test_succeeds_ETHTransfer_beforeInitialization() public {
        // Deploy proxy without initializing
        address payable uninitProxy = payable(makeAddr("uninitProxy"));
        _deployProxy(uninitProxy);

        // Fund test contract
        vm.deal(address(this), 1 ether);

        // Send ETH to uninitialized wallet
        (bool success,) = uninitProxy.call{value: 1 ether}("");
        assertTrue(success);
        assertEq(uninitProxy.balance, 1 ether);
    }
}
