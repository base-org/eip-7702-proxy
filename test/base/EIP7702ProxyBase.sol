// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import {Test} from "forge-std/Test.sol";
import {EIP7702Proxy} from "../../src/EIP7702Proxy.sol";
import {MockImplementation} from "../mocks/MockImplementation.sol";
import {ECDSA} from "openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";

/**
 * @title EIP7702ProxyBase
 * @dev Base contract containing shared setup and utilities for EIP7702Proxy tests.
 *      This contract should not contain any actual tests.
 */
abstract contract EIP7702ProxyBase is Test {
    // Add ERC1967 implementation slot constant
    bytes32 internal constant IMPLEMENTATION_SLOT =
        0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    // Test accounts
    uint256 internal constant _EOA_PRIVATE_KEY = 0xA11CE;
    address payable internal _eoa;

    uint256 internal constant _NEW_OWNER_PRIVATE_KEY = 0xB0B;
    address payable internal _newOwner;

    // Contracts
    EIP7702Proxy internal _proxy;
    MockImplementation internal _implementation;

    // Common test data
    bytes4 internal _initSelector;

    function setUp() public virtual {
        // Set up test accounts
        _eoa = payable(vm.addr(_EOA_PRIVATE_KEY));
        vm.deal(_eoa, 100 ether);

        _newOwner = payable(vm.addr(_NEW_OWNER_PRIVATE_KEY));
        vm.deal(_newOwner, 100 ether);

        // Deploy implementation
        _implementation = new MockImplementation();
        _initSelector = MockImplementation.initialize.selector;

        // Deploy proxy normally first to get the correct immutable values
        _proxy = new EIP7702Proxy(address(_implementation), _initSelector);

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
    function _createInitArgs(
        address owner
    ) internal pure returns (bytes memory) {
        return abi.encode(owner);
    }

    /**
     * @dev Helper to read the implementation address from ERC1967 storage slot
     * @param proxy Address of the proxy contract to read from
     * @return The implementation address stored in the ERC1967 slot
     */
    function _getERC1967Implementation(
        address proxy
    ) internal view returns (address) {
        return address(uint160(uint256(vm.load(proxy, IMPLEMENTATION_SLOT))));
    }

    /**
     * @dev Helper to deploy a proxy and etch its code at a target address
     * @param target The address where the proxy code should be etched
     * @return The target address (for convenience)
     */
    function _deployProxy(address target) internal returns (address) {
        // Deploy proxy normally first to get the correct immutable values
        EIP7702Proxy proxy = new EIP7702Proxy(
            address(_implementation),
            _initSelector
        );

        // Get the proxy's runtime code
        bytes memory proxyCode = address(proxy).code;

        // Etch the proxy code at the target address
        vm.etch(target, proxyCode);

        return target;
    }
}
