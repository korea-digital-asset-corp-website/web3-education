// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IAccount } from "@account-abstraction/interfaces/IAccount.sol";
import { PackedUserOperation } from "@account-abstraction/interfaces/PackedUserOperation.sol";
import { IEntryPoint } from "@account-abstraction/interfaces/IEntryPoint.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { MessageHashUtils } from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

/**
 * @title SimpleAccountWithRecovery
 * @notice ERC-4337 호환 스마트 계정 - Guardian 기반 완전한 키 교체 지원
 *
 * @dev ERC-4337의 핵심 특성:
 * - 자산이 Contract Address(CA)에 귀속됨
 * - 서명자(owner)를 완전히 교체 가능
 * - 기존 키는 교체 후 완전히 무효화됨
 *
 * VASP 복구 시나리오:
 * 1. 고객이 PassKey 분실
 * 2. Guardian(회사)이 리커버리 요청
 * 3. 새 PassKey의 공개키로 owner 교체
 * 4. 기존 PassKey는 완전히 무효 → 서명해도 거부됨
 */
contract SimpleAccountWithRecovery is IAccount {
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;

    // =========================================================================
    // 상태 변수
    // =========================================================================

    /// @notice EntryPoint 주소
    IEntryPoint public immutable entryPoint;

    /// @notice 계정 소유자 (서명 검증용)
    address public owner;

    /// @notice Guardian 목록
    mapping(address => bool) public guardians;

    /// @notice Guardian 수
    uint256 public guardianCount;

    /// @notice 리커버리 요청 정보
    struct RecoveryRequest {
        address newOwner;
        uint256 approvalCount;
        uint256 requestedAt;
        mapping(address => bool) approvals;
    }

    /// @notice 현재 진행 중인 리커버리 요청
    RecoveryRequest private _recoveryRequest;

    /// @notice 리커버리 대기 시간 (기본 48시간)
    uint256 public recoveryDelay = 48 hours;

    /// @notice 초기화 여부
    bool public initialized;

    // =========================================================================
    // 이벤트
    // =========================================================================

    event AccountInitialized(address indexed owner);
    event OwnerChanged(address indexed previousOwner, address indexed newOwner);
    event GuardianAdded(address indexed guardian);
    event GuardianRemoved(address indexed guardian);
    event RecoveryRequested(address indexed newOwner, address indexed requestedBy);
    event RecoveryApproved(address indexed guardian);
    event RecoveryExecuted(address indexed previousOwner, address indexed newOwner);
    event RecoveryCancelled();
    event Executed(address indexed target, uint256 value, bytes data, bool success);

    // =========================================================================
    // 에러
    // =========================================================================

    error OnlyEntryPoint();
    error OnlyOwner();
    error OnlyGuardian();
    error AlreadyInitialized();
    error InvalidAddress();
    error ExecutionFailed(bytes reason);
    error LengthMismatch();
    error AlreadyGuardian();
    error NotGuardian();
    error RecoveryInProgress();
    error NoRecoveryInProgress();
    error RecoveryDelayNotPassed();
    error AlreadyApproved();
    error InsufficientApprovals();

    // =========================================================================
    // Modifier
    // =========================================================================

    modifier onlyEntryPoint() {
        if (msg.sender != address(entryPoint)) revert OnlyEntryPoint();
        _;
    }

    modifier onlyOwner() {
        if (msg.sender != owner && msg.sender != address(this)) revert OnlyOwner();
        _;
    }

    modifier onlyGuardian() {
        if (!guardians[msg.sender]) revert NotGuardian();
        _;
    }

    // =========================================================================
    // 생성자
    // =========================================================================

    constructor(IEntryPoint _entryPoint) {
        entryPoint = _entryPoint;
    }

    // =========================================================================
    // 초기화
    // =========================================================================

    /**
     * @notice 계정 초기화
     * @param _owner 초기 소유자 주소
     */
    function initialize(address _owner) external {
        if (initialized) revert AlreadyInitialized();
        if (_owner == address(0)) revert InvalidAddress();

        initialized = true;
        owner = _owner;

        emit AccountInitialized(_owner);
    }

    /**
     * @notice 계정 초기화 (Guardian 포함)
     * @param _owner 초기 소유자 주소
     * @param _guardians 초기 Guardian 목록
     */
    function initializeWithGuardians(address _owner, address[] calldata _guardians) external {
        if (initialized) revert AlreadyInitialized();
        if (_owner == address(0)) revert InvalidAddress();

        initialized = true;
        owner = _owner;

        for (uint256 i = 0; i < _guardians.length; i++) {
            if (_guardians[i] != address(0) && !guardians[_guardians[i]]) {
                guardians[_guardians[i]] = true;
                guardianCount++;
                emit GuardianAdded(_guardians[i]);
            }
        }

        emit AccountInitialized(_owner);
    }

    // =========================================================================
    // IAccount 구현
    // =========================================================================

    /**
     * @notice UserOperation 검증
     * @dev EntryPoint에서 호출됨
     */
    function validateUserOp(
        PackedUserOperation calldata userOp,
        bytes32 userOpHash,
        uint256 missingAccountFunds
    ) external onlyEntryPoint returns (uint256 validationData) {
        // 서명 검증
        bytes32 hash = userOpHash.toEthSignedMessageHash();
        address signer = hash.recover(userOp.signature);

        if (signer != owner) {
            return 1; // 서명 실패
        }

        // 가스비 선지급
        if (missingAccountFunds > 0) {
            (bool success,) = payable(msg.sender).call{ value: missingAccountFunds }("");
            (success); // 무시 (EntryPoint가 처리)
        }

        return 0; // 성공
    }

    // =========================================================================
    // 실행 함수
    // =========================================================================

    /**
     * @notice 단일 트랜잭션 실행
     */
    function execute(address target, uint256 value, bytes calldata data)
        external
        onlyEntryPoint
        returns (bytes memory result)
    {
        bool success;
        (success, result) = target.call{ value: value }(data);

        if (!success) {
            revert ExecutionFailed(result);
        }

        emit Executed(target, value, data, success);
    }

    /**
     * @notice 배치 트랜잭션 실행
     */
    function executeBatch(
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata datas
    ) external onlyEntryPoint returns (bytes[] memory results) {
        uint256 length = targets.length;
        if (length != values.length || length != datas.length) {
            revert LengthMismatch();
        }

        results = new bytes[](length);

        for (uint256 i = 0; i < length; i++) {
            (bool success, bytes memory result) = targets[i].call{ value: values[i] }(datas[i]);

            if (!success) {
                revert ExecutionFailed(result);
            }

            results[i] = result;
            emit Executed(targets[i], values[i], datas[i], success);
        }
    }

    // =========================================================================
    // 소유자 관리 (핵심: 완전한 키 교체)
    // =========================================================================

    /**
     * @notice 소유자 변경 (직접)
     * @dev owner가 직접 변경 가능 (EntryPoint를 통해 execute로 호출)
     * @param newOwner 새 소유자 주소
     */
    function setOwner(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert InvalidAddress();

        address previousOwner = owner;
        owner = newOwner;

        emit OwnerChanged(previousOwner, newOwner);
    }

    // =========================================================================
    // Guardian 관리
    // =========================================================================

    /**
     * @notice Guardian 추가
     */
    function addGuardian(address guardian) external onlyOwner {
        if (guardian == address(0)) revert InvalidAddress();
        if (guardians[guardian]) revert AlreadyGuardian();

        guardians[guardian] = true;
        guardianCount++;

        emit GuardianAdded(guardian);
    }

    /**
     * @notice Guardian 제거
     */
    function removeGuardian(address guardian) external onlyOwner {
        if (!guardians[guardian]) revert NotGuardian();

        guardians[guardian] = false;
        guardianCount--;

        emit GuardianRemoved(guardian);
    }

    // =========================================================================
    // 소셜 리커버리 (VASP 복구 시나리오)
    // =========================================================================

    /**
     * @notice 리커버리 요청 (Guardian이 시작)
     * @param newOwner 새 소유자 주소 (새 PassKey의 공개키에서 파생된 주소)
     */
    function requestRecovery(address newOwner) external onlyGuardian {
        if (newOwner == address(0)) revert InvalidAddress();
        if (_recoveryRequest.requestedAt != 0) revert RecoveryInProgress();

        _recoveryRequest.newOwner = newOwner;
        _recoveryRequest.approvalCount = 1;
        _recoveryRequest.requestedAt = block.timestamp;
        _recoveryRequest.approvals[msg.sender] = true;

        emit RecoveryRequested(newOwner, msg.sender);
        emit RecoveryApproved(msg.sender);
    }

    /**
     * @notice 리커버리 승인
     */
    function approveRecovery() external onlyGuardian {
        if (_recoveryRequest.requestedAt == 0) revert NoRecoveryInProgress();
        if (_recoveryRequest.approvals[msg.sender]) revert AlreadyApproved();

        _recoveryRequest.approvals[msg.sender] = true;
        _recoveryRequest.approvalCount++;

        emit RecoveryApproved(msg.sender);
    }

    /**
     * @notice 리커버리 실행
     * @dev 과반수 승인 + 대기 시간 경과 후 실행 가능
     *
     * ⭐ 핵심: 이 함수 실행 후 기존 owner는 완전히 무효화됨
     *         기존 키로 서명해도 validateUserOp에서 거부됨
     */
    function executeRecovery() external {
        if (_recoveryRequest.requestedAt == 0) revert NoRecoveryInProgress();
        if (block.timestamp < _recoveryRequest.requestedAt + recoveryDelay) {
            revert RecoveryDelayNotPassed();
        }

        // 과반수 승인 필요 (최소 1명)
        uint256 requiredApprovals = (guardianCount / 2) + 1;
        if (_recoveryRequest.approvalCount < requiredApprovals) {
            revert InsufficientApprovals();
        }

        address previousOwner = owner;
        address newOwner = _recoveryRequest.newOwner;

        // 리커버리 요청 초기화
        _recoveryRequest.newOwner = address(0);
        _recoveryRequest.approvalCount = 0;
        _recoveryRequest.requestedAt = 0;

        // ⭐ 소유자 변경 → 기존 키 완전 무효화
        owner = newOwner;

        emit RecoveryExecuted(previousOwner, newOwner);
    }

    /**
     * @notice 리커버리 취소 (owner만 가능)
     */
    function cancelRecovery() external onlyOwner {
        if (_recoveryRequest.requestedAt == 0) revert NoRecoveryInProgress();

        _recoveryRequest.newOwner = address(0);
        _recoveryRequest.approvalCount = 0;
        _recoveryRequest.requestedAt = 0;

        emit RecoveryCancelled();
    }

    /**
     * @notice 리커버리 대기 시간 설정
     */
    function setRecoveryDelay(uint256 newDelay) external onlyOwner {
        recoveryDelay = newDelay;
    }

    // =========================================================================
    // 조회 함수
    // =========================================================================

    /**
     * @notice 계정 정보 조회
     */
    function getAccountInfo()
        external
        view
        returns (address _owner, bool _initialized, uint256 _guardianCount)
    {
        return (owner, initialized, guardianCount);
    }

    /**
     * @notice 리커버리 요청 정보 조회
     */
    function getRecoveryRequest()
        external
        view
        returns (address newOwner, uint256 approvalCount, uint256 requestedAt, bool canExecute)
    {
        uint256 requiredApprovals = guardianCount > 0 ? (guardianCount / 2) + 1 : 1;
        bool delayPassed = block.timestamp >= _recoveryRequest.requestedAt + recoveryDelay;
        bool hasEnoughApprovals = _recoveryRequest.approvalCount >= requiredApprovals;

        return (
            _recoveryRequest.newOwner,
            _recoveryRequest.approvalCount,
            _recoveryRequest.requestedAt,
            delayPassed && hasEnoughApprovals && _recoveryRequest.requestedAt != 0
        );
    }

    // =========================================================================
    // 유틸리티
    // =========================================================================

    /**
     * @notice ETH 수신 허용
     */
    receive() external payable { }

    /**
     * @notice EntryPoint에 예치된 잔액 조회
     */
    function getDeposit() public view returns (uint256) {
        return entryPoint.balanceOf(address(this));
    }

    /**
     * @notice EntryPoint에 예치
     */
    function addDeposit() public payable {
        entryPoint.depositTo{ value: msg.value }(address(this));
    }

    /**
     * @notice EntryPoint에서 인출
     */
    function withdrawDepositTo(address payable to, uint256 amount) external onlyOwner {
        entryPoint.withdrawTo(to, amount);
    }
}
