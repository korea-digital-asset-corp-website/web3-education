// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IPaymaster } from "@account-abstraction/interfaces/IPaymaster.sol";
import { PackedUserOperation } from "@account-abstraction/interfaces/PackedUserOperation.sol";
import { IEntryPoint } from "@account-abstraction/interfaces/IEntryPoint.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { MessageHashUtils } from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title VerifyingPaymaster
 * @notice ERC-4337 호환 가스 대납 Paymaster
 * @dev 화이트리스트에 등록된 계정의 가스비를 대신 지불합니다.
 *
 * 주요 기능:
 * - 화이트리스트 기반 가스 대납
 * - 서명 기반 검증 (verifier 서명 필요)
 * - ETH 예치/인출 관리
 *
 * 교육용 데모를 위해 간소화된 구현입니다.
 */
contract VerifyingPaymaster is IPaymaster, Ownable {
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;

    // =========================================================================
    // 상수
    // =========================================================================

    /// @notice EntryPoint 주소 (v0.7)
    IEntryPoint public immutable entryPoint;

    /// @notice 검증 서명 유효 기간 (초)
    uint256 public constant SIGNATURE_VALIDITY = 300; // 5분

    // =========================================================================
    // 상태 변수
    // =========================================================================

    /// @notice 서명 검증자 주소
    address public verifier;

    /// @notice 화이트리스트된 계정
    mapping(address => bool) public whitelist;

    /// @notice 사용된 nonce (재사용 방지)
    mapping(bytes32 => bool) public usedNonces;

    // =========================================================================
    // 이벤트
    // =========================================================================

    /// @notice 화이트리스트 추가
    event AddedToWhitelist(address indexed account);

    /// @notice 화이트리스트 제거
    event RemovedFromWhitelist(address indexed account);

    /// @notice 검증자 변경
    event VerifierChanged(address indexed previousVerifier, address indexed newVerifier);

    /// @notice ETH 예치
    event Deposited(address indexed from, uint256 amount);

    /// @notice ETH 인출
    event Withdrawn(address indexed to, uint256 amount);

    /// @notice 가스 대납 실행
    event GasSponsored(address indexed sender, uint256 actualGasCost);

    // =========================================================================
    // 에러
    // =========================================================================

    /// @notice EntryPoint만 호출 가능
    error OnlyEntryPoint();

    /// @notice 화이트리스트에 없음
    error NotWhitelisted();

    /// @notice 잘못된 서명
    error InvalidSignature();

    /// @notice 서명 만료
    error SignatureExpired();

    /// @notice Nonce 이미 사용됨
    error NonceAlreadyUsed();

    /// @notice 잘못된 주소
    error InvalidAddress();

    /// @notice 잔액 부족
    error InsufficientBalance();

    // =========================================================================
    // Modifier
    // =========================================================================

    /// @notice EntryPoint에서만 호출 가능
    modifier onlyEntryPoint() {
        if (msg.sender != address(entryPoint)) revert OnlyEntryPoint();
        _;
    }

    // =========================================================================
    // 생성자
    // =========================================================================

    /**
     * @notice Paymaster 생성
     * @param _entryPoint EntryPoint 컨트랙트 주소
     * @param _verifier 서명 검증자 주소
     * @param _owner 소유자 주소
     */
    constructor(IEntryPoint _entryPoint, address _verifier, address _owner) Ownable(_owner) {
        entryPoint = _entryPoint;
        verifier = _verifier;
    }

    // =========================================================================
    // IPaymaster 구현
    // =========================================================================

    /**
     * @notice UserOperation 검증
     * @dev EntryPoint에서 호출됨
     * @param userOp UserOperation 데이터
     * @param maxCost 최대 비용
     * @return context 후처리에 전달할 컨텍스트
     * @return validationData 검증 결과 (0 = 성공)
     */
    function validatePaymasterUserOp(
        PackedUserOperation calldata userOp,
        bytes32,
        uint256 maxCost
    ) external view onlyEntryPoint returns (bytes memory context, uint256 validationData) {
        // paymasterData 디코딩: [validUntil(6) | validAfter(6) | signature(65)]
        bytes calldata paymasterData = userOp.paymasterAndData[52:]; // 20(address) + 16(gasLimits) + 16(gasLimits) = 52

        // 최소 길이 확인 (12 + 65 = 77)
        if (paymasterData.length < 77) {
            return ("", _packValidationData(true, 0, 0));
        }

        // 시간 범위 추출
        uint48 validUntil = uint48(bytes6(paymasterData[0:6]));
        uint48 validAfter = uint48(bytes6(paymasterData[6:12]));

        // 서명 추출
        bytes calldata signature = paymasterData[12:77];

        // 화이트리스트 확인 (간소화된 모드에서는 서명 검증 스킵 가능)
        if (!whitelist[userOp.sender]) {
            // 서명 검증
            bytes32 hash = _getHash(userOp, validUntil, validAfter);
            address signer = hash.toEthSignedMessageHash().recover(signature);

            if (signer != verifier) {
                return ("", _packValidationData(true, 0, 0));
            }
        }

        // 컨텍스트: sender 주소 (후처리용)
        context = abi.encode(userOp.sender, maxCost);

        // 검증 성공
        validationData = _packValidationData(false, validUntil, validAfter);
    }

    /**
     * @notice 후처리
     * @dev 트랜잭션 완료 후 호출됨
     * @param mode 실행 모드 (0: 성공, 1: 실패, 2: 후처리만)
     * @param context validatePaymasterUserOp에서 반환한 컨텍스트
     * @param actualGasCost 실제 가스 비용
     * @param actualUserOpFeePerGas 실제 가스 가격
     */
    function postOp(
        PostOpMode mode,
        bytes calldata context,
        uint256 actualGasCost,
        uint256 actualUserOpFeePerGas
    ) external onlyEntryPoint {
        (address sender,) = abi.decode(context, (address, uint256));

        // 가스 대납 로깅
        emit GasSponsored(sender, actualGasCost);

        // mode가 postOpReverted면 revert로 전체 롤백
        // 현재는 별도 처리 없음
        (mode, actualUserOpFeePerGas); // unused
    }

    // =========================================================================
    // 화이트리스트 관리
    // =========================================================================

    /**
     * @notice 화이트리스트에 추가
     * @param account 추가할 계정
     */
    function addToWhitelist(address account) external onlyOwner {
        if (account == address(0)) revert InvalidAddress();
        whitelist[account] = true;
        emit AddedToWhitelist(account);
    }

    /**
     * @notice 화이트리스트에서 제거
     * @param account 제거할 계정
     */
    function removeFromWhitelist(address account) external onlyOwner {
        whitelist[account] = false;
        emit RemovedFromWhitelist(account);
    }

    /**
     * @notice 여러 계정을 화이트리스트에 추가
     * @param accounts 추가할 계정 배열
     */
    function addBatchToWhitelist(address[] calldata accounts) external onlyOwner {
        for (uint256 i = 0; i < accounts.length; i++) {
            if (accounts[i] != address(0)) {
                whitelist[accounts[i]] = true;
                emit AddedToWhitelist(accounts[i]);
            }
        }
    }

    // =========================================================================
    // 검증자 관리
    // =========================================================================

    /**
     * @notice 검증자 변경
     * @param newVerifier 새 검증자 주소
     */
    function setVerifier(address newVerifier) external onlyOwner {
        if (newVerifier == address(0)) revert InvalidAddress();

        address previousVerifier = verifier;
        verifier = newVerifier;

        emit VerifierChanged(previousVerifier, newVerifier);
    }

    // =========================================================================
    // ETH 관리
    // =========================================================================

    /**
     * @notice EntryPoint에 ETH 예치
     */
    function deposit() external payable onlyOwner {
        entryPoint.depositTo{ value: msg.value }(address(this));
        emit Deposited(msg.sender, msg.value);
    }

    /**
     * @notice EntryPoint에서 ETH 인출
     * @param to 수신 주소
     * @param amount 인출 금액
     */
    function withdrawTo(address payable to, uint256 amount) external onlyOwner {
        entryPoint.withdrawTo(to, amount);
        emit Withdrawn(to, amount);
    }

    /**
     * @notice 스테이크 추가
     * @param unstakeDelaySec 언스테이크 지연 시간
     */
    function addStake(uint32 unstakeDelaySec) external payable onlyOwner {
        entryPoint.addStake{ value: msg.value }(unstakeDelaySec);
    }

    /**
     * @notice 언스테이크
     */
    function unlockStake() external onlyOwner {
        entryPoint.unlockStake();
    }

    /**
     * @notice 스테이크 인출
     * @param to 수신 주소
     */
    function withdrawStake(address payable to) external onlyOwner {
        entryPoint.withdrawStake(to);
    }

    // =========================================================================
    // 조회 함수
    // =========================================================================

    /**
     * @notice 예치 잔액 조회
     * @return 예치된 ETH 양
     */
    function getDeposit() external view returns (uint256) {
        return entryPoint.balanceOf(address(this));
    }

    /**
     * @notice 화이트리스트 여부 확인
     * @param account 확인할 계정
     * @return 화이트리스트 여부
     */
    function isWhitelisted(address account) external view returns (bool) {
        return whitelist[account];
    }

    // =========================================================================
    // 내부 함수
    // =========================================================================

    /**
     * @dev 검증 데이터 패킹
     * @param sigFailed 서명 실패 여부
     * @param validUntil 유효 종료 시간
     * @param validAfter 유효 시작 시간
     * @return packed 패킹된 데이터
     */
    function _packValidationData(bool sigFailed, uint48 validUntil, uint48 validAfter)
        internal
        pure
        returns (uint256)
    {
        return (sigFailed ? 1 : 0) | (uint256(validUntil) << 160) | (uint256(validAfter) << 208);
    }

    /**
     * @dev 서명용 해시 생성
     * @param userOp UserOperation
     * @param validUntil 유효 종료 시간
     * @param validAfter 유효 시작 시간
     * @return 해시 값
     */
    function _getHash(PackedUserOperation calldata userOp, uint48 validUntil, uint48 validAfter)
        internal
        view
        returns (bytes32)
    {
        return keccak256(
            abi.encode(
                userOp.sender,
                userOp.nonce,
                keccak256(userOp.initCode),
                keccak256(userOp.callData),
                userOp.accountGasLimits,
                userOp.preVerificationGas,
                userOp.gasFees,
                keccak256(userOp.paymasterAndData[:52]), // address + gasLimits만
                block.chainid,
                address(this),
                validUntil,
                validAfter
            )
        );
    }

    // =========================================================================
    // 유틸리티
    // =========================================================================

    /**
     * @notice ETH 직접 수신 허용
     */
    receive() external payable {
        emit Deposited(msg.sender, msg.value);
    }
}
