// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import {EIP7702ProxyBase} from "../base/EIP7702ProxyBase.sol";
import {EIP7702Proxy} from "../../src/EIP7702Proxy.sol";
import {MockImplementation, FailingSignatureImplementation} from "../mocks/MockImplementation.sol";
import {ECDSA} from "openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";

/**
 * @title IsValidSignatureTestBase
 * @dev Base contract for testing ERC-1271 isValidSignature behavior
 */
abstract contract IsValidSignatureTestBase is EIP7702ProxyBase {
    bytes4 constant ERC1271_MAGIC_VALUE = 0x1626ba7e;
    bytes4 constant ERC1271_FAIL_VALUE = 0xffffffff;

    bytes32 testHash;
    address wallet;

    function setUp() public virtual override {
        testHash = keccak256("test message");
        wallet = _eoa;
    }

    function testValidEOASignature() public virtual {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_EOA_PRIVATE_KEY, testHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        bytes4 result = MockImplementation(payable(wallet)).isValidSignature(
            testHash,
            signature
        );
        assertEq(
            result,
            ERC1271_MAGIC_VALUE,
            "Should accept valid EOA signature"
        );
    }

    function testInvalidEOASignature() public virtual {
        uint256 wrongPk = 0xB0B;
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(wrongPk, testHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        bytes4 result = MockImplementation(payable(wallet)).isValidSignature(
            testHash,
            signature
        );
        assertEq(
            result,
            expectedInvalidSignatureResult(),
            "Should handle invalid signature according to whether `isValidSignature` succeeds or fails"
        );
    }

    /**
     * @dev Abstract function that each implementation test must define
     * @return Expected result for invalid signature tests
     */
    function expectedInvalidSignatureResult()
        internal
        pure
        virtual
        returns (bytes4);
}

/**
 * @dev Tests isValidSignature behavior with failing implementation
 */
contract FailingImplementationTest is IsValidSignatureTestBase {
    function setUp() public override {
        // Override base setup to use FailingSignatureImplementation
        _implementation = new FailingSignatureImplementation();
        _initSelector = MockImplementation.initialize.selector;

        _eoa = payable(vm.addr(_EOA_PRIVATE_KEY));
        _newOwner = payable(vm.addr(_NEW_OWNER_PRIVATE_KEY));

        // Deploy and setup proxy
        _proxy = new EIP7702Proxy(address(_implementation), _initSelector);
        bytes memory proxyCode = address(_proxy).code;
        vm.etch(_eoa, proxyCode);

        // Initialize
        bytes memory initArgs = _createInitArgs(_newOwner);
        bytes memory signature = _signInitData(_EOA_PRIVATE_KEY, initArgs);
        EIP7702Proxy(_eoa).initialize(initArgs, signature);

        super.setUp();
    }

    function expectedInvalidSignatureResult()
        internal
        pure
        override
        returns (bytes4)
    {
        return ERC1271_FAIL_VALUE;
    }

    function testEmptySignature() public {
        bytes memory emptySignature = "";

        bytes4 result = MockImplementation(payable(wallet)).isValidSignature(
            testHash,
            emptySignature
        );
        assertEq(result, ERC1271_FAIL_VALUE, "Should reject empty signature");
    }
}

/**
 * @dev Tests isValidSignature behavior with succeeding implementation
 */
contract SucceedingImplementationTest is IsValidSignatureTestBase {
    function setUp() public override {
        // Override base implementation with standard MockImplementation (always succeeds)
        _implementation = new MockImplementation();
        _initSelector = MockImplementation.initialize.selector;

        _eoa = payable(vm.addr(_EOA_PRIVATE_KEY));
        _newOwner = payable(vm.addr(_NEW_OWNER_PRIVATE_KEY));

        // Deploy and setup proxy
        _proxy = new EIP7702Proxy(address(_implementation), _initSelector);
        bytes memory proxyCode = address(_proxy).code;
        vm.etch(_eoa, proxyCode);

        // Initialize
        bytes memory initArgs = _createInitArgs(_newOwner);
        bytes memory signature = _signInitData(_EOA_PRIVATE_KEY, initArgs);
        EIP7702Proxy(_eoa).initialize(initArgs, signature);

        super.setUp();
    }

    function expectedInvalidSignatureResult()
        internal
        pure
        override
        returns (bytes4)
    {
        return ERC1271_MAGIC_VALUE; // Implementation always returns success
    }

    function testEmptySignature() public {
        bytes memory emptySignature = "";

        bytes4 result = MockImplementation(payable(wallet)).isValidSignature(
            testHash,
            emptySignature
        );
        assertEq(
            result,
            ERC1271_MAGIC_VALUE,
            "Should return success for any EOA signature if implementation since `isValidSignature` always succeeds"
        );
    }
}
