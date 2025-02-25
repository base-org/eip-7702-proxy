// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import {ECDSA} from "openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";

import {EIP7702Proxy} from "../../src/EIP7702Proxy.sol";
import {NonceTracker} from "../../src/NonceTracker.sol";
import {DefaultReceiver} from "../../src/DefaultReceiver.sol";

import {EIP7702ProxyBase} from "../base/EIP7702ProxyBase.sol";
import {
    MockImplementation,
    FailingSignatureImplementation,
    RevertingIsValidSignatureImplementation,
    MockImplementationWithExtraData
} from "../mocks/MockImplementation.sol";
import {MockValidator} from "../mocks/MockValidator.sol";

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
        super.setUp();

        testHash = keccak256("test message");
        wallet = _eoa;
    }

    function test_succeeds_withValidEOASignature(bytes32 message) public virtual {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_EOA_PRIVATE_KEY, message);
        bytes memory signature = abi.encodePacked(r, s, v);

        bytes4 result = MockImplementation(payable(wallet)).isValidSignature(message, signature);
        assertEq(result, ERC1271_MAGIC_VALUE, "Should accept valid EOA signature");
    }

    function test_returnsExpectedValue_withInvalidEOASignature(uint128 wrongPk, bytes32 message) public virtual {
        vm.assume(wrongPk != 0);
        vm.assume(wrongPk != _EOA_PRIVATE_KEY);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(wrongPk, testHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        bytes4 result = MockImplementation(payable(wallet)).isValidSignature(message, signature);
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
    function expectedInvalidSignatureResult() internal pure virtual returns (bytes4);
}

/**
 * @dev Tests isValidSignature behavior when returning failure value from implementation isValidSignature
 */
contract FailingImplementationTest is IsValidSignatureTestBase {
    function setUp() public override {
        // Deploy core contracts first
        _implementation = new FailingSignatureImplementation();
        _nonceTracker = new NonceTracker();
        _receiver = new DefaultReceiver();
        _validator = new MockValidator();

        _eoa = payable(vm.addr(_EOA_PRIVATE_KEY));
        _newOwner = payable(vm.addr(_NEW_OWNER_PRIVATE_KEY));

        // Deploy proxy with receiver and nonce tracker
        _proxy = new EIP7702Proxy(_nonceTracker, _receiver);
        bytes memory proxyCode = address(_proxy).code;
        vm.etch(_eoa, proxyCode);

        // Initialize with implementation
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

        super.setUp();
    }

    function expectedInvalidSignatureResult() internal pure override returns (bytes4) {
        return ERC1271_FAIL_VALUE;
    }

    function test_returnsFailureValue_withEmptySignature(bytes32 message) public {
        bytes4 result = MockImplementation(payable(wallet)).isValidSignature(message, "");
        assertEq(result, ERC1271_FAIL_VALUE, "Should reject empty signature");
    }

    function test_returnsFailureValue_withInvalidS(bytes32 message) public {
        // Create a signature with obviously invalid s value
        // Valid s values must be < n/2 where n is the curve order
        // Using max uint256 value which is clearly too large
        bytes32 r = bytes32(uint256(1));
        bytes32 s = bytes32(type(uint256).max); // 2^256 - 1, way above valid range
        uint8 v = 27;
        bytes memory signature = abi.encodePacked(r, s, v);

        // We can use tryRecover directly to verify the exact error
        (address recovered, ECDSA.RecoverError error, bytes32 errorArg) = ECDSA.tryRecover(message, signature);
        assertEq(recovered, address(0), "Recovered address should be zero for invalid signature");
        assertEq(uint8(error), uint8(ECDSA.RecoverError.InvalidSignatureS), "Should be InvalidSignatureS error");
        assertEq(errorArg, s, "Error arg should be the invalid s value");

        bytes4 result = MockImplementation(payable(wallet)).isValidSignature(message, signature);
        assertEq(result, ERC1271_FAIL_VALUE, "Should reject signature with invalid s value");
    }

    function test_returnsFailureValue_withInvalidV(bytes32 message) public {
        // Create signature with invalid v value (only 27 and 28 are valid)
        bytes32 r = bytes32(uint256(1));
        bytes32 s = bytes32(uint256(1));
        uint8 v = 26;
        bytes memory signature = abi.encodePacked(r, s, v);

        // Verify the exact error from tryRecover
        (address recovered, ECDSA.RecoverError error, bytes32 errorArg) = ECDSA.tryRecover(message, signature);
        assertEq(recovered, address(0), "Recovered address should be zero for invalid signature");
        assertEq(uint8(error), uint8(ECDSA.RecoverError.InvalidSignature), "Should be InvalidSignature error");
        assertEq(errorArg, bytes32(0), "Error arg should be zero for invalid signature");

        bytes4 result = MockImplementation(payable(wallet)).isValidSignature(message, signature);
        assertEq(result, ERC1271_FAIL_VALUE, "Should reject signature with invalid v value");
    }

    function test_returnsFailureValue_withInvalidR(bytes32 message) public {
        // Create signature with invalid r value (using max uint256 which is above the curve order)
        bytes32 r = bytes32(type(uint256).max);
        bytes32 s = bytes32(uint256(1));
        uint8 v = 27;
        bytes memory signature = abi.encodePacked(r, s, v);

        // Verify the exact error from tryRecover
        (address recovered, ECDSA.RecoverError error, bytes32 errorArg) = ECDSA.tryRecover(message, signature);
        assertEq(recovered, address(0), "Recovered address should be zero for invalid signature");
        assertEq(uint8(error), uint8(ECDSA.RecoverError.InvalidSignature), "Should be InvalidSignature error");
        assertEq(errorArg, bytes32(0), "Error arg should be zero for invalid signature");

        bytes4 result = MockImplementation(payable(wallet)).isValidSignature(message, signature);
        assertEq(result, ERC1271_FAIL_VALUE, "Should reject signature with invalid r value");
    }
}

/**
 * @dev Tests isValidSignature behavior when returning success value from implementation isValidSignature
 */
contract SucceedingImplementationTest is IsValidSignatureTestBase {
    function setUp() public override {
        // Deploy core contracts first
        _implementation = new MockImplementation();
        _nonceTracker = new NonceTracker();
        _receiver = new DefaultReceiver();
        _validator = new MockValidator();

        _eoa = payable(vm.addr(_EOA_PRIVATE_KEY));
        _newOwner = payable(vm.addr(_NEW_OWNER_PRIVATE_KEY));

        // Deploy proxy with receiver and nonce tracker
        _proxy = new EIP7702Proxy(_nonceTracker, _receiver);
        bytes memory proxyCode = address(_proxy).code;
        vm.etch(_eoa, proxyCode);

        // Initialize with implementation
        bytes memory initArgs = _createInitArgs(_newOwner);
        bytes memory signature = _signSetImplementationData(
            _EOA_PRIVATE_KEY,
            address(_implementation),
            0, // chainId 0 for cross-chain
            initArgs
        );

        EIP7702Proxy(_eoa).setImplementation(address(_implementation), initArgs, address(_validator), signature, true);

        super.setUp();
    }

    function expectedInvalidSignatureResult() internal pure override returns (bytes4) {
        return ERC1271_MAGIC_VALUE; // Implementation always returns success
    }

    function test_returnsSuccessValue_withEmptySignature(bytes32 message) public {
        bytes4 result = MockImplementation(payable(wallet)).isValidSignature(message, "");
        assertEq(result, ERC1271_MAGIC_VALUE, "Should return success for any EOA signature");
    }
}

/**
 * @dev Tests isValidSignature behavior when reverting in implementation isValidSignature
 */
contract RevertingImplementationTest is IsValidSignatureTestBase {
    function setUp() public override {
        // Deploy core contracts first
        _implementation = new RevertingIsValidSignatureImplementation();
        _nonceTracker = new NonceTracker();
        _receiver = new DefaultReceiver();
        _validator = new MockValidator();

        _eoa = payable(vm.addr(_EOA_PRIVATE_KEY));
        _newOwner = payable(vm.addr(_NEW_OWNER_PRIVATE_KEY));

        // Deploy proxy with receiver and nonce tracker
        _proxy = new EIP7702Proxy(_nonceTracker, _receiver);
        bytes memory proxyCode = address(_proxy).code;
        vm.etch(_eoa, proxyCode);

        // Initialize with implementation
        bytes memory initArgs = _createInitArgs(_newOwner);
        bytes memory signature = _signSetImplementationData(
            _EOA_PRIVATE_KEY,
            address(_implementation),
            0, // chainId 0 for cross-chain
            initArgs
        );

        EIP7702Proxy(_eoa).setImplementation(address(_implementation), initArgs, address(_validator), signature, true);

        super.setUp();
    }

    function expectedInvalidSignatureResult() internal pure override returns (bytes4) {
        return ERC1271_FAIL_VALUE;
    }
}

/**
 * @dev Tests isValidSignature behavior when implementation returns ERC1271_MAGIC_VALUE with extra data
 */
contract ExtraDataTest is IsValidSignatureTestBase {
    function test_mockReturnsExtraData() public {
        MockImplementationWithExtraData mock = new MockImplementationWithExtraData();

        // Call isValidSignature and capture the raw return data
        (bool success, bytes memory returnData) =
            address(mock).staticcall(abi.encodeWithSelector(mock.isValidSignature.selector, bytes32(0), new bytes(0)));

        require(success, "Call failed");
        require(returnData.length == 32, "Should return 32 bytes");

        // Log the full return data
        emit log_named_bytes("Return data", returnData);

        // Also log as bytes32 for easier reading
        bytes32 returnDataAs32 = abi.decode(returnData, (bytes32));
        emit log_named_bytes32("Return data as bytes32", returnDataAs32);
    }

    function setUp() public override {
        // Deploy core contracts first
        _implementation = new MockImplementationWithExtraData();
        _nonceTracker = new NonceTracker();
        _receiver = new DefaultReceiver();
        _validator = new MockValidator();

        _eoa = payable(vm.addr(_EOA_PRIVATE_KEY));
        _newOwner = payable(vm.addr(_NEW_OWNER_PRIVATE_KEY));

        // Deploy proxy with receiver and nonce tracker
        _proxy = new EIP7702Proxy(_nonceTracker, _receiver);
        bytes memory proxyCode = address(_proxy).code;
        vm.etch(_eoa, proxyCode);

        // Initialize with implementation
        bytes memory initArgs = _createInitArgs(_newOwner);
        bytes memory signature = _signSetImplementationData(
            _EOA_PRIVATE_KEY,
            address(_implementation),
            0, // chainId 0 for cross-chain
            initArgs
        );

        EIP7702Proxy(_eoa).setImplementation(address(_implementation), initArgs, address(_validator), signature, true);

        super.setUp();
    }

    function expectedInvalidSignatureResult() internal pure override returns (bytes4) {
        return ERC1271_MAGIC_VALUE; // Implementation always returns success (with extra data)
    }

    function test_succeeds_withExtraReturnData(bytes32 message) public {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_EOA_PRIVATE_KEY, message);
        bytes memory signature = abi.encodePacked(r, s, v);

        bytes4 result = MockImplementation(payable(wallet)).isValidSignature(message, signature);
        assertEq(result, ERC1271_MAGIC_VALUE, "Should accept signature even with extra return data");
    }
}
