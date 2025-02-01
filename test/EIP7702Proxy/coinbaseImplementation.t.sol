// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import {Test} from "forge-std/Test.sol";
import {EIP7702Proxy} from "../../src/EIP7702Proxy.sol";
import {CoinbaseSmartWallet} from "../../lib/smart-wallet/src/CoinbaseSmartWallet.sol";
import {ECDSA} from "openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";

contract CoinbaseImplementationTest is Test {
    uint256 constant _EOA_PRIVATE_KEY = 0xA11CE;
    address payable _eoa;

    uint256 constant _NEW_OWNER_PRIVATE_KEY = 0xB0B;
    address payable _newOwner;

    CoinbaseSmartWallet wallet;
    CoinbaseSmartWallet implementation;
    EIP7702Proxy proxy;
    bytes4 initSelector;

    bytes4 constant ERC1271_MAGIC_VALUE = 0x1626ba7e;
    bytes4 constant ERC1271_FAIL_VALUE = 0xffffffff;

    function setUp() public {
        // Set up test accounts
        _eoa = payable(vm.addr(_EOA_PRIVATE_KEY));
        _newOwner = payable(vm.addr(_NEW_OWNER_PRIVATE_KEY));

        // Deploy Coinbase implementation
        implementation = new CoinbaseSmartWallet();
        initSelector = CoinbaseSmartWallet.initialize.selector;

        // Deploy and setup proxy
        proxy = new EIP7702Proxy(address(implementation), initSelector);
        bytes memory proxyCode = address(proxy).code;
        vm.etch(_eoa, proxyCode);

        // Initialize with Coinbase implementation
        bytes memory initArgs = _createInitArgs(_newOwner);
        bytes memory signature = _signInitData(_EOA_PRIVATE_KEY, initArgs);
        EIP7702Proxy(_eoa).initialize(initArgs, signature);

        wallet = CoinbaseSmartWallet(payable(_eoa));
    }

    // ======== Utility Functions ========
    function _createInitArgs(
        address owner
    ) internal pure returns (bytes memory) {
        bytes[] memory owners = new bytes[](1);
        owners[0] = abi.encode(owner);
        return abi.encode(owners);
    }

    function _signInitData(
        uint256 signerPk,
        bytes memory initArgs
    ) internal view returns (bytes memory) {
        // Use the EOA address in the hash since that's where our proxy lives
        bytes32 initHash = keccak256(abi.encode(proxy, initArgs));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, initHash);
        return abi.encodePacked(r, s, v);
    }

    function testCoinbaseInitializeSetsOwner() public {
        assertTrue(
            wallet.isOwnerAddress(_newOwner),
            "New owner should be owner after initialization"
        );
    }

    function testCoinbaseOwnerSignatureValidation() public {
        bytes32 testHash = keccak256("test message");
        assertTrue(
            wallet.isOwnerAddress(_newOwner),
            "New owner should be set after initialization"
        );
        assertEq(
            wallet.ownerAtIndex(0),
            abi.encode(_newOwner),
            "Owner at index 0 should be new owner"
        );

        bytes memory signature = _createOwnerSignature(
            testHash,
            address(wallet),
            _NEW_OWNER_PRIVATE_KEY,
            0 // First owner
        );

        bytes4 result = wallet.isValidSignature(testHash, signature);
        assertEq(
            result,
            ERC1271_MAGIC_VALUE,
            "Should accept valid contract owner signature"
        );
    }

    function testCoinbaseExecuteFunction() public {
        address recipient = address(0xBEEF);
        uint256 amount = 1 ether;

        vm.deal(address(_eoa), amount);

        vm.prank(_newOwner);
        wallet.execute(
            payable(recipient),
            amount,
            "" // empty calldata for simple transfer
        );

        assertEq(
            recipient.balance,
            amount,
            "Coinbase wallet execute should transfer ETH"
        );
    }

    function testCoinbaseUpgradeAccess() public {
        address newImpl = address(new CoinbaseSmartWallet());

        vm.prank(address(0xBAD));
        vm.expectRevert(); // Coinbase wallet specific access control
        wallet.upgradeToAndCall(newImpl, "");
    }

    function testCanOnlyBeCalledOnce() public {
        bytes memory initArgs = _createInitArgs(_newOwner);
        bytes memory signature = _signInitData(_EOA_PRIVATE_KEY, initArgs);

        // Try to initialize again
        vm.expectRevert(CoinbaseSmartWallet.Initialized.selector);
        EIP7702Proxy(_eoa).initialize(initArgs, signature);
    }

    // ======== Utility Functions ========

    function _sign(
        uint256 pk,
        bytes32 hash
    ) internal pure returns (bytes memory signature) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, hash);
        return abi.encodePacked(r, s, v);
    }

    function _createOwnerSignature(
        bytes32 message,
        address smartWallet,
        uint256 ownerPk,
        uint256 ownerIndex
    ) internal view returns (bytes memory) {
        bytes32 replaySafeHash = CoinbaseSmartWallet(payable(smartWallet))
            .replaySafeHash(message);
        bytes memory signature = _sign(ownerPk, replaySafeHash);
        return _applySignatureWrapper(ownerIndex, signature);
    }

    function _applySignatureWrapper(
        uint256 ownerIndex,
        bytes memory signatureData
    ) internal pure returns (bytes memory) {
        return
            abi.encode(
                CoinbaseSmartWallet.SignatureWrapper(ownerIndex, signatureData)
            );
    }
}
