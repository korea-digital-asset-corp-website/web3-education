// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Test, console } from "forge-std/Test.sol";
import { EIP7702Account } from "../src/EIP7702Account.sol";

/**
 * @title EIP7702Account 테스트
 * @notice EIP-7702 계정의 주요 기능을 테스트합니다.
 *
 * 테스트 시나리오:
 * 1. 초기화 (initialize, initializeWithMaster)
 * 2. 실행 (execute, executeBatch)
 * 3. 권한 관리 (delegate)
 * 4. 메타 트랜잭션 (EIP-712)
 */
contract EIP7702AccountTest is Test {
    EIP7702Account public account;

    address public owner = makeAddr("owner");
    address public delegate1 = makeAddr("delegate1");
    address public delegate2 = makeAddr("delegate2");
    address public recipient = makeAddr("recipient");
    address public newMaster = makeAddr("newMaster");

    function setUp() public {
        account = new EIP7702Account();
        // 테스트 계정에 ETH 지급
        vm.deal(address(account), 10 ether);
        vm.deal(owner, 10 ether);
        vm.deal(delegate1, 1 ether);
    }

    // =========================================================================
    // 초기화 테스트
    // =========================================================================

    function test_initialize() public {
        vm.prank(owner);
        account.initialize();

        assertEq(account.masterAuthority(), owner);
        assertTrue(account.initialized());
    }

    function test_initializeWithMaster() public {
        address master = makeAddr("customMaster");
        vm.prank(owner);
        account.initializeWithMaster(master);

        assertEq(account.masterAuthority(), master);
        assertTrue(account.initialized());
    }

    function test_initialize_revert_alreadyInitialized() public {
        vm.prank(owner);
        account.initialize();

        vm.prank(owner);
        vm.expectRevert(EIP7702Account.AlreadyInitialized.selector);
        account.initialize();
    }

    function test_initializeWithMaster_revert_zeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(EIP7702Account.InvalidAddress.selector);
        account.initializeWithMaster(address(0));
    }

    // =========================================================================
    // 실행 테스트
    // =========================================================================

    function test_execute_ethTransfer() public {
        vm.prank(owner);
        account.initialize();

        uint256 recipientBalanceBefore = recipient.balance;

        vm.prank(owner);
        account.execute(recipient, 1 ether, "");

        assertEq(recipient.balance, recipientBalanceBefore + 1 ether);
    }

    function test_execute_revert_unauthorized() public {
        vm.prank(owner);
        account.initialize();

        address attacker = makeAddr("attacker");
        vm.prank(attacker);
        vm.expectRevert(EIP7702Account.Unauthorized.selector);
        account.execute(recipient, 1 ether, "");
    }

    function test_execute_byDelegate() public {
        vm.prank(owner);
        account.initialize();

        vm.prank(owner);
        account.addDelegate(delegate1);

        vm.prank(delegate1);
        account.execute(recipient, 0.5 ether, "");

        assertEq(recipient.balance, 0.5 ether);
    }

    function test_executeBatch() public {
        vm.prank(owner);
        account.initialize();

        address recipient2 = makeAddr("recipient2");

        address[] memory targets = new address[](2);
        targets[0] = recipient;
        targets[1] = recipient2;

        uint256[] memory values = new uint256[](2);
        values[0] = 0.5 ether;
        values[1] = 0.3 ether;

        bytes[] memory datas = new bytes[](2);
        datas[0] = "";
        datas[1] = "";

        vm.prank(owner);
        account.executeBatch(targets, values, datas);

        assertEq(recipient.balance, 0.5 ether);
        assertEq(recipient2.balance, 0.3 ether);
    }

    function test_executeBatch_revert_lengthMismatch() public {
        vm.prank(owner);
        account.initialize();

        address[] memory targets = new address[](2);
        uint256[] memory values = new uint256[](1); // 길이 불일치
        bytes[] memory datas = new bytes[](2);

        vm.prank(owner);
        vm.expectRevert(EIP7702Account.LengthMismatch.selector);
        account.executeBatch(targets, values, datas);
    }

    // =========================================================================
    // Delegate 관리 테스트
    // =========================================================================

    function test_addDelegate() public {
        vm.prank(owner);
        account.initialize();

        vm.prank(owner);
        account.addDelegate(delegate1);

        assertTrue(account.delegates(delegate1));
        assertTrue(account.isAuthorized(delegate1));
    }

    function test_addDelegate_revert_notMaster() public {
        vm.prank(owner);
        account.initialize();

        vm.prank(delegate1);
        vm.expectRevert(EIP7702Account.Unauthorized.selector);
        account.addDelegate(delegate2);
    }

    function test_addDelegate_revert_alreadyDelegate() public {
        vm.prank(owner);
        account.initialize();

        vm.prank(owner);
        account.addDelegate(delegate1);

        vm.prank(owner);
        vm.expectRevert(EIP7702Account.AlreadyDelegate.selector);
        account.addDelegate(delegate1);
    }

    function test_removeDelegate() public {
        vm.prank(owner);
        account.initialize();

        vm.prank(owner);
        account.addDelegate(delegate1);

        vm.prank(owner);
        account.removeDelegate(delegate1);

        assertFalse(account.delegates(delegate1));
        assertFalse(account.isAuthorized(delegate1));
    }

    // =========================================================================
    // 마스터 권한 이전 테스트
    // =========================================================================

    function test_setMasterAuthority() public {
        vm.prank(owner);
        account.initialize();

        vm.prank(owner);
        account.setMasterAuthority(newMaster);

        assertEq(account.masterAuthority(), newMaster);

        // 기존 owner는 더 이상 권한 없음
        vm.prank(owner);
        vm.expectRevert(EIP7702Account.Unauthorized.selector);
        account.execute(recipient, 1 ether, "");
    }

    function test_setMasterAuthority_revert_zeroAddress() public {
        vm.prank(owner);
        account.initialize();

        vm.prank(owner);
        vm.expectRevert(EIP7702Account.InvalidAddress.selector);
        account.setMasterAuthority(address(0));
    }

    // =========================================================================
    // 자동 초기화 테스트
    // =========================================================================

    function test_autoInitialize_onExecuteWithSignature() public {
        // _ensureInitialized는 executeWithSignature 내부에서 호출됨
        // onlyAuthorized 체크 전이므로 자동 초기화 가능
        // 그러나 execute는 onlyAuthorized가 먼저 체크되어 미초기화 상태에서 실패
        // → initialize를 먼저 호출해야 함을 확인하는 테스트
        vm.prank(owner);
        vm.expectRevert(EIP7702Account.Unauthorized.selector);
        account.execute(recipient, 0, "");

        assertFalse(account.initialized());
    }

    // =========================================================================
    // 메타 트랜잭션 (EIP-712) 테스트
    // =========================================================================

    function test_executeWithSignature() public {
        // 초기화
        vm.prank(owner);
        account.initialize();

        // 서명에 사용할 개인키 (테스트용)
        uint256 signerPk = 0xA11CE;
        address signer = vm.addr(signerPk);

        // signer를 delegate로 추가
        vm.prank(owner);
        account.addDelegate(signer);

        // 메타 트랜잭션 파라미터
        address to = recipient;
        uint256 value = 0.1 ether;
        bytes memory data = "";
        uint256 nonce = account.nonces(signer);
        uint256 deadline = block.timestamp + 600;

        // EIP-712 도메인
        bytes32 domainSeparator = keccak256(
            abi.encode(
                account.DOMAIN_TYPEHASH(),
                keccak256(bytes(account.NAME())),
                keccak256(bytes(account.VERSION())),
                block.chainid,
                address(account)
            )
        );

        // 구조화된 데이터 해시
        bytes32 structHash = keccak256(
            abi.encode(
                account.EXECUTE_TYPEHASH(),
                to,
                value,
                keccak256(data),
                nonce,
                deadline
            )
        );

        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", domainSeparator, structHash)
        );

        // 서명
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        // Relayer가 실행
        address relayer = makeAddr("relayer");
        uint256 recipientBefore = recipient.balance;

        vm.prank(relayer);
        account.executeWithSignature(signer, to, value, data, deadline, signature);

        assertEq(recipient.balance, recipientBefore + 0.1 ether);
        assertEq(account.nonces(signer), nonce + 1);
    }

    // =========================================================================
    // 조회 함수 테스트
    // =========================================================================

    function test_getAccountInfo() public {
        vm.prank(owner);
        account.initialize();

        (address master, bool isInit) = account.getAccountInfo();
        assertEq(master, owner);
        assertTrue(isInit);
    }

    // =========================================================================
    // ETH 수신 테스트
    // =========================================================================

    function test_receiveEth() public {
        uint256 balanceBefore = address(account).balance;
        vm.deal(makeAddr("sender"), 1 ether);
        vm.prank(makeAddr("sender"));
        (bool success,) = address(account).call{ value: 1 ether }("");
        assertTrue(success);
        assertEq(address(account).balance, balanceBefore + 1 ether);
    }
}
