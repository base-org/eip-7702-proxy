// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import {EIP7702Proxy} from "../../src/EIP7702Proxy.sol";
import {NonceTracker} from "../../src/NonceTracker.sol";
import {DefaultReceiver} from "../../src/DefaultReceiver.sol";
import {MockValidator} from "../mocks/MockValidator.sol";

import {ECDSA} from "openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";
import {Test} from "forge-std/Test.sol";
import {MockImplementation} from "../mocks/MockImplementation.sol";

/**
 * @title EIP7702ProxyBase
 * @dev Base contract containing shared setup and utilities for EIP7702Proxy tests.
 */
abstract contract EIP7702ProxyBase is Test {
    /// @dev Storage slot with the address of the current implementation (ERC1967)
    bytes32 internal constant IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    bytes32 internal constant _IMPLEMENTATION_SET_TYPEHASH = keccak256(
        "EIP7702ProxyImplementationSet(uint256 chainId,address proxy,uint256 nonce,address currentImplementation,address newImplementation,bytes callData,address validator)"
    );

    /// @dev Test account private keys and addresses
    uint256 internal constant _EOA_PRIVATE_KEY = 0xA11CE;
    address payable internal _eoa;

    uint256 internal constant _NEW_OWNER_PRIVATE_KEY = 0xB0B;
    address payable internal _newOwner;

    /// @dev Core contract instances
    EIP7702Proxy internal _proxy;
    MockImplementation internal _implementation;
    NonceTracker internal _nonceTracker;
    DefaultReceiver internal _receiver;
    MockValidator internal _validator;

    /// @dev "deploy" the proxy at the EOA but don't initialize
    function setUp() public virtual {
        // Set up test accounts
        _eoa = payable(vm.addr(_EOA_PRIVATE_KEY));
        _newOwner = payable(vm.addr(_NEW_OWNER_PRIVATE_KEY));

        // Deploy core contracts
        _implementation = new MockImplementation();
        _nonceTracker = new NonceTracker();
        _receiver = new DefaultReceiver();
        _validator = new MockValidator();

        // Deploy proxy with receiver and nonce tracker
        _proxy = new EIP7702Proxy(_nonceTracker, _receiver);

        // Get the proxy's runtime code
        bytes memory proxyCode = address(_proxy).code;

        // Etch the proxy code at the EOA's address to simulate EIP-7702 upgrade
        vm.etch(_eoa, proxyCode);
    }

    /// @dev Initialize the proxy with the new owner
    function _initializeProxy() internal {
        bytes memory initArgs = _createInitArgs(_newOwner);
        bytes memory signature = _signSetImplementationData(
            _EOA_PRIVATE_KEY,
            address(_implementation),
            0, // chainId 0 for cross-chain
            initArgs
        );

        EIP7702Proxy(_eoa).setImplementation(
            address(_implementation),
            initArgs,
            address(_validator),
            signature,
            true // Allow cross-chain replay for tests
        );
    }

    /**
     * @dev Helper to generate initialization signature
     * @param signerPk Private key of the signer
     * @param newImplementationAddress New implementation contract address
     * @param chainId Chain ID for the signature
     * @param callData Initialization data for the implementation
     * @return Signature bytes
     */
    function _signSetImplementationData(
        uint256 signerPk,
        address newImplementationAddress,
        uint256 chainId,
        bytes memory callData
    ) internal view returns (bytes memory) {
        uint256 nonce = _nonceTracker.nonces(_eoa);
        address currentImpl = _getERC1967Implementation(_eoa);

        bytes32 initHash = keccak256(
            abi.encode(
                _IMPLEMENTATION_SET_TYPEHASH,
                chainId,
                _proxy,
                nonce,
                currentImpl,
                newImplementationAddress,
                keccak256(callData),
                address(_validator)
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, initHash);
        return abi.encodePacked(r, s, v);
    }

    /**
     * @dev Helper to create initialization args with a single owner
     * @param owner Address to set as owner
     * @return Encoded initialization arguments
     */
    function _createInitArgs(address owner) internal pure returns (bytes memory) {
        // Encode the complete function call: initialize(address)
        return abi.encodeWithSelector(MockImplementation.initialize.selector, owner);
    }

    /**
     * @dev Helper to read the implementation address from ERC1967 storage slot
     * @param proxy Address of the proxy contract to read from
     * @return The implementation address stored in the ERC1967 slot
     */
    function _getERC1967Implementation(address proxy) internal view returns (address) {
        return address(uint160(uint256(vm.load(proxy, IMPLEMENTATION_SLOT))));
    }

    /**
     * @dev Helper to deploy a proxy and etch its code at a target address
     * @param target The address where the proxy code should be etched
     * @return The target address (for convenience)
     */
    function _deployProxy(address target) internal returns (address) {
        // Get the proxy's runtime code
        bytes memory proxyCode = address(_proxy).code;

        // Etch the proxy code at the target address
        vm.etch(target, proxyCode);

        return target;
    }
}
