// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import {Test} from "forge-std/Test.sol";
import {CoinbaseSmartWallet} from "../lib/smart-wallet/src/CoinbaseSmartWallet.sol";
import {EIP7702Proxy} from "../src/EIP7702Proxy.sol";
import {NonceTracker} from "../src/NonceTracker.sol";
import {DefaultReceiver} from "../src/DefaultReceiver.sol";
import {CoinbaseSmartWalletValidator} from "../src/validators/CoinbaseSmartWalletValidator.sol";

contract CoinbaseSmartWalletValidatorTest is Test {
    uint256 constant _EOA_PRIVATE_KEY = 0xA11CE;
    address payable _eoa;

    uint256 constant _NEW_OWNER_PRIVATE_KEY = 0xB0B;
    address payable _newOwner;

    // Core contracts
    EIP7702Proxy _proxy;
    CoinbaseSmartWallet _implementation;
    NonceTracker _nonceTracker;
    DefaultReceiver _receiver;
    CoinbaseSmartWalletValidator _validator;

    // Storage slot with the address of the current implementation (ERC1967)
    bytes32 internal constant _IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    bytes32 _IMPLEMENTATION_SET_TYPEHASH = keccak256(
        "EIP7702ProxyImplementationSet(uint256 chainId,address proxy,uint256 nonce,address currentImplementation,address newImplementation,bytes callData,address validator)"
    );

    function setUp() public {
        // Set up test accounts
        _eoa = payable(vm.addr(_EOA_PRIVATE_KEY));
        _newOwner = payable(vm.addr(_NEW_OWNER_PRIVATE_KEY));

        // Deploy core contracts
        _implementation = new CoinbaseSmartWallet();
        _nonceTracker = new NonceTracker();
        _receiver = new DefaultReceiver();
        _validator = new CoinbaseSmartWalletValidator();

        // Deploy proxy with receiver and nonce tracker
        _proxy = new EIP7702Proxy(_nonceTracker, _receiver);

        // Get the proxy's runtime code
        bytes memory proxyCode = address(_proxy).code;

        // Etch the proxy code at the target address
        vm.etch(_eoa, proxyCode);
    }

    function test_succeeds_whenWalletHasOwner() public {
        // Initialize proxy with an owner
        bytes memory initArgs = _createInitArgs(_newOwner);
        bytes memory signature = _signSetImplementationData(_EOA_PRIVATE_KEY, initArgs);

        // Should not revert
        EIP7702Proxy(_eoa).setImplementation(address(_implementation), initArgs, address(_validator), signature, true);
    }

    function test_succeeds_whenWalletHasMultipleOwners() public {
        // Initialize with multiple owners
        address[] memory owners = new address[](3);
        owners[0] = makeAddr("owner1");
        owners[1] = makeAddr("owner2");
        owners[2] = makeAddr("owner3");

        bytes memory initArgs = _createInitArgsMulti(owners);
        bytes memory signature = _signSetImplementationData(_EOA_PRIVATE_KEY, initArgs);

        // Should not revert
        EIP7702Proxy(_eoa).setImplementation(address(_implementation), initArgs, address(_validator), signature, true);
    }

    function test_reverts_whenWalletHasNoOwners() public {
        // Try to initialize with empty owners array
        bytes[] memory emptyOwners = new bytes[](0);
        bytes memory initArgs = abi.encodePacked(CoinbaseSmartWallet.initialize.selector, abi.encode(emptyOwners));
        bytes memory signature = _signSetImplementationData(_EOA_PRIVATE_KEY, initArgs);

        vm.expectRevert(CoinbaseSmartWalletValidator.Unintialized.selector);
        EIP7702Proxy(_eoa).setImplementation(address(_implementation), initArgs, address(_validator), signature, true);
    }

    function test_succeeds_whenWalletHadOwnersButLastOwnerRemoved() public {
        // First initialize the wallet with an owner
        bytes memory initArgs = _createInitArgs(_newOwner);
        bytes memory signature = _signSetImplementationData(_EOA_PRIVATE_KEY, initArgs);
        EIP7702Proxy(_eoa).setImplementation(address(_implementation), initArgs, address(_validator), signature, true);

        // Now remove the owner through the wallet interface
        vm.prank(_newOwner);
        CoinbaseSmartWallet(payable(_eoa)).removeLastOwner(
            0, // index of the owner to remove
            abi.encode(_newOwner) // encoded owner data
        );

        // Direct validation call should succeed since nextOwnerIndex is still non-zero
        _validator.validateWalletState(address(_eoa));

        // Verify that nextOwnerIndex is indeed still non-zero
        assertGt(CoinbaseSmartWallet(payable(_eoa)).nextOwnerIndex(), 0);
    }

    // Helper functions from coinbaseImplementation.t.sol
    function _createInitArgs(address owner) internal pure returns (bytes memory) {
        bytes[] memory owners = new bytes[](1);
        owners[0] = abi.encode(owner);
        bytes memory ownerArgs = abi.encode(owners);
        return abi.encodePacked(CoinbaseSmartWallet.initialize.selector, ownerArgs);
    }

    function _createInitArgsMulti(address[] memory owners) internal pure returns (bytes memory) {
        bytes[] memory encodedOwners = new bytes[](owners.length);
        for (uint256 i = 0; i < owners.length; i++) {
            encodedOwners[i] = abi.encode(owners[i]);
        }
        bytes memory ownerArgs = abi.encode(encodedOwners);
        return abi.encodePacked(CoinbaseSmartWallet.initialize.selector, ownerArgs);
    }

    function _signSetImplementationData(uint256 signerPk, bytes memory initArgs) internal view returns (bytes memory) {
        bytes32 initHash = keccak256(
            abi.encode(
                _IMPLEMENTATION_SET_TYPEHASH,
                0, // chainId 0 for cross-chain
                _proxy,
                _nonceTracker.nonces(_eoa),
                _getERC1967Implementation(address(_eoa)),
                address(_implementation),
                keccak256(initArgs),
                address(_validator)
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, initHash);
        return abi.encodePacked(r, s, v);
    }

    function _getERC1967Implementation(address proxy) internal view returns (address) {
        return address(uint160(uint256(vm.load(proxy, _IMPLEMENTATION_SLOT))));
    }
}
