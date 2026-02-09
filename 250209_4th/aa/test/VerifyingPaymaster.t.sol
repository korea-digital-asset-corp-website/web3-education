// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Test, console } from "forge-std/Test.sol";
import { VerifyingPaymaster } from "../src/VerifyingPaymaster.sol";
import { IPaymaster } from "@account-abstraction/interfaces/IPaymaster.sol";
import { IEntryPoint } from "@account-abstraction/interfaces/IEntryPoint.sol";

/**
 * @title VerifyingPaymaster 테스트
 * @notice Paymaster의 화이트리스트 관리 및 ETH 관리 기능 테스트
 *
 * 참고: validatePaymasterUserOp은 EntryPoint에서만 호출 가능하므로
 *       화이트리스트/관리 기능 위주로 테스트합니다.
 */
contract VerifyingPaymasterTest is Test {
    VerifyingPaymaster public paymaster;

    // EntryPoint v0.7
    address constant ENTRY_POINT = 0x0000000071727De22E5E9d8BAf0edAc6f37da032;

    address public deployer = makeAddr("deployer");
    address public verifier = makeAddr("verifier");
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");
    address public user3 = makeAddr("user3");

    function setUp() public {
        vm.deal(deployer, 100 ether);

        vm.prank(deployer);
        paymaster = new VerifyingPaymaster(
            IEntryPoint(ENTRY_POINT),
            verifier,
            deployer
        );
    }

    // =========================================================================
    // 초기 상태 테스트
    // =========================================================================

    function test_initialState() public view {
        assertEq(paymaster.owner(), deployer);
        assertEq(paymaster.verifier(), verifier);
        assertEq(address(paymaster.entryPoint()), ENTRY_POINT);
    }

    // =========================================================================
    // 화이트리스트 관리 테스트
    // =========================================================================

    function test_addToWhitelist() public {
        vm.prank(deployer);
        paymaster.addToWhitelist(user1);

        assertTrue(paymaster.isWhitelisted(user1));
        assertTrue(paymaster.whitelist(user1));
    }

    function test_addToWhitelist_revert_notOwner() public {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", user1));
        paymaster.addToWhitelist(user2);
    }

    function test_addToWhitelist_revert_zeroAddress() public {
        vm.prank(deployer);
        vm.expectRevert(VerifyingPaymaster.InvalidAddress.selector);
        paymaster.addToWhitelist(address(0));
    }

    function test_removeFromWhitelist() public {
        vm.prank(deployer);
        paymaster.addToWhitelist(user1);

        vm.prank(deployer);
        paymaster.removeFromWhitelist(user1);

        assertFalse(paymaster.isWhitelisted(user1));
    }

    function test_addBatchToWhitelist() public {
        address[] memory users = new address[](3);
        users[0] = user1;
        users[1] = user2;
        users[2] = user3;

        vm.prank(deployer);
        paymaster.addBatchToWhitelist(users);

        assertTrue(paymaster.isWhitelisted(user1));
        assertTrue(paymaster.isWhitelisted(user2));
        assertTrue(paymaster.isWhitelisted(user3));
    }

    // =========================================================================
    // 검증자 관리 테스트
    // =========================================================================

    function test_setVerifier() public {
        address newVerifier = makeAddr("newVerifier");

        vm.prank(deployer);
        paymaster.setVerifier(newVerifier);

        assertEq(paymaster.verifier(), newVerifier);
    }

    function test_setVerifier_revert_zeroAddress() public {
        vm.prank(deployer);
        vm.expectRevert(VerifyingPaymaster.InvalidAddress.selector);
        paymaster.setVerifier(address(0));
    }

    function test_setVerifier_revert_notOwner() public {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", user1));
        paymaster.setVerifier(makeAddr("newVerifier"));
    }

    // =========================================================================
    // ETH 수신 테스트
    // =========================================================================

    function test_receiveEth() public {
        vm.deal(user1, 1 ether);
        vm.prank(user1);
        (bool success,) = address(paymaster).call{ value: 1 ether }("");
        assertTrue(success);
        assertEq(address(paymaster).balance, 1 ether);
    }

    // =========================================================================
    // EntryPoint 전용 함수 테스트
    // =========================================================================

    function test_onlyEntryPoint_revert() public {
        // postOp은 EntryPoint만 호출 가능
        vm.prank(user1);
        vm.expectRevert(VerifyingPaymaster.OnlyEntryPoint.selector);
        paymaster.postOp(
            IPaymaster.PostOpMode.opSucceeded,
            abi.encode(user1, uint256(0)),
            0,
            0
        );
    }
}
