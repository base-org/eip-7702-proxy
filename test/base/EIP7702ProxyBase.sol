// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import {Test} from "forge-std/Test.sol";
import {EIP7702Proxy} from "../../src/EIP7702Proxy.sol";
import {CoinbaseSmartWallet} from "../../lib/smart-wallet/src/CoinbaseSmartWallet.sol";
import {ECDSA} from "openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";

/**
 * @title EIP7702ProxyBase
 * @dev Base contract containing shared setup and utilities for EIP7702Proxy tests.
 *      This contract should not contain any actual tests.
 */
abstract contract EIP7702ProxyBase is Test {
    // Test accounts
    uint256 internal constant _EOA_PRIVATE_KEY = 0xA11CE;
    address payable internal _eoa;
    
    uint256 internal constant _NEW_OWNER_PRIVATE_KEY = 0xB0B;
    address payable internal _newOwner;
    
    // Contracts
    EIP7702Proxy internal _proxy;
    CoinbaseSmartWallet internal _implementation;
    
    // Common test data
    bytes4 internal _initSelector;
    
    function setUp() public virtual {
        // Set up test accounts
        _eoa = payable(vm.addr(_EOA_PRIVATE_KEY));
        vm.deal(_eoa, 100 ether);
        
        _newOwner = payable(vm.addr(_NEW_OWNER_PRIVATE_KEY));
        vm.deal(_newOwner, 100 ether);
        
        // Deploy implementation
        _implementation = new CoinbaseSmartWallet();
        _initSelector = CoinbaseSmartWallet.initialize.selector;
        
        // Deploy proxy normally first to get the correct immutable values
        _proxy = new EIP7702Proxy(
            address(_implementation),
            _initSelector
        );
        
        // Get the proxy's runtime code
        bytes memory proxyCode = address(_proxy).code;
        
        // Etch the proxy code at the EOA's address to simulate EIP-7702 upgrade
        vm.etch(_eoa, proxyCode);
    }
    
    /**
     * @dev Helper to generate initialization signature
     * @param signerPk Private key of the signer
     * @param initArgs Initialization arguments to sign
     * @return Signature bytes
     */
    function _signInitData(
        uint256 signerPk,
        bytes memory initArgs
    ) internal view returns (bytes memory) {
        // Use the EOA address in the hash since that's where our proxy lives
        bytes32 initHash = keccak256(abi.encode(_proxy, initArgs));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, initHash);
        return abi.encodePacked(r, s, v);
    }
    
    /**
     * @dev Helper to create initialization args with a single owner
     * @param owner Address to set as owner
     * @return Encoded initialization arguments
     */
    function _createInitArgs(address owner) internal pure returns (bytes memory) {
        bytes[] memory owners = new bytes[](1);
        owners[0] = abi.encode(owner);
        return abi.encode(owners);
    }
} 