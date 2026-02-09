// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IAccount } from "@account-abstraction/interfaces/IAccount.sol";
import { PackedUserOperation } from "@account-abstraction/interfaces/PackedUserOperation.sol";
import { Initializable } from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

/**
 * @title PasskeyAccount
 * @notice ERC-4337 호환 스마트 계정 - P-256 (PassKey) 서명 지원
 * @dev RIP-7212 precompile을 우선 사용하고, 미지원 시 라이브러리 fallback
 *
 * 주요 기능:
 * - P-256 서명 검증 (PassKey/WebAuthn)
 * - ERC-4337 UserOperation 처리
 * - 단일 또는 다중 서명자 지원 가능
 */
contract PasskeyAccount is IAccount, Initializable {
    // =========================================================================
    // 상수
    // =========================================================================

    /// @notice RIP-7212 P-256 verifier precompile 주소
    address constant P256_VERIFIER = 0x0000000000000000000000000000000000000100;

    /// @notice EntryPoint 주소 (v0.7)
    address constant ENTRY_POINT = 0x0000000071727De22E5E9d8BAf0edAc6f37da032;

    /// @notice 서명 검증 성공 반환값 (SIG_VALIDATION_SUCCESS)
    uint256 constant SIG_VALIDATION_SUCCESS = 0;

    /// @notice 서명 검증 실패 반환값 (SIG_VALIDATION_FAILED)
    uint256 constant SIG_VALIDATION_FAILED = 1;

    // =========================================================================
    // 상태 변수
    // =========================================================================

    /// @notice PassKey 공개키 X 좌표
    bytes32 public publicKeyX;

    /// @notice PassKey 공개키 Y 좌표
    bytes32 public publicKeyY;

    /// @notice 계정 소유자 식별자 (자격 증명 ID 해시)
    bytes32 public credentialIdHash;

    // =========================================================================
    // 이벤트
    // =========================================================================

    /// @notice 계정 초기화 이벤트
    event AccountInitialized(
        bytes32 indexed credentialIdHash, bytes32 publicKeyX, bytes32 publicKeyY
    );

    /// @notice 트랜잭션 실행 이벤트
    event TransactionExecuted(address indexed target, uint256 value, bytes data);

    // =========================================================================
    // 에러
    // =========================================================================

    /// @notice EntryPoint만 호출 가능
    error OnlyEntryPoint();

    /// @notice 이미 초기화됨
    error AlreadyInitialized();

    /// @notice 서명 검증 실패
    error InvalidSignature();

    /// @notice 트랜잭션 실행 실패
    error ExecutionFailed();

    // =========================================================================
    // Modifier
    // =========================================================================

    /// @notice EntryPoint에서만 호출 가능하도록 제한
    modifier onlyEntryPoint() {
        if (msg.sender != ENTRY_POINT) revert OnlyEntryPoint();
        _;
    }

    // =========================================================================
    // 초기화
    // =========================================================================

    /**
     * @notice 계정 초기화 (Factory에서 호출)
     * @param _credentialIdHash 자격 증명 ID의 keccak256 해시
     * @param _publicKeyX P-256 공개키 X 좌표
     * @param _publicKeyY P-256 공개키 Y 좌표
     */
    function initialize(bytes32 _credentialIdHash, bytes32 _publicKeyX, bytes32 _publicKeyY)
        external
        initializer
    {
        credentialIdHash = _credentialIdHash;
        publicKeyX = _publicKeyX;
        publicKeyY = _publicKeyY;

        emit AccountInitialized(_credentialIdHash, _publicKeyX, _publicKeyY);
    }

    // =========================================================================
    // ERC-4337 인터페이스
    // =========================================================================

    /**
     * @notice UserOperation 서명 검증 (ERC-4337)
     * @dev EntryPoint에서 호출됨
     * @param userOp UserOperation 데이터
     * @param userOpHash UserOperation 해시 (서명 대상)
     * @param missingAccountFunds 부족한 예치금 (선불 필요 시)
     * @return validationData 검증 결과 (0 = 성공, 1 = 실패)
     */
    function validateUserOp(
        PackedUserOperation calldata userOp,
        bytes32 userOpHash,
        uint256 missingAccountFunds
    ) external onlyEntryPoint returns (uint256 validationData) {
        // 서명 검증
        validationData = _validateSignature(userOpHash, userOp.signature);

        // 부족한 예치금 전송
        if (missingAccountFunds > 0) {
            (bool success,) = payable(msg.sender).call{ value: missingAccountFunds }("");
            // 실패해도 계속 진행 (EntryPoint에서 처리)
            (success);
        }
    }

    // =========================================================================
    // 실행 함수
    // =========================================================================

    /**
     * @notice 단일 트랜잭션 실행
     * @dev EntryPoint에서 callData를 통해 호출됨
     * @param target 대상 주소
     * @param value 전송할 ETH 양
     * @param data 호출 데이터
     */
    function execute(address target, uint256 value, bytes calldata data) external onlyEntryPoint {
        (bool success, bytes memory result) = target.call{ value: value }(data);
        if (!success) {
            // 실패 사유 전파
            assembly {
                revert(add(result, 32), mload(result))
            }
        }
        emit TransactionExecuted(target, value, data);
    }

    /**
     * @notice 다중 트랜잭션 배치 실행
     * @param targets 대상 주소 배열
     * @param values 전송할 ETH 양 배열
     * @param datas 호출 데이터 배열
     */
    function executeBatch(
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata datas
    ) external onlyEntryPoint {
        require(targets.length == values.length && values.length == datas.length, "Length mismatch");

        for (uint256 i = 0; i < targets.length; i++) {
            (bool success, bytes memory result) = targets[i].call{ value: values[i] }(datas[i]);
            if (!success) {
                assembly {
                    revert(add(result, 32), mload(result))
                }
            }
            emit TransactionExecuted(targets[i], values[i], datas[i]);
        }
    }

    // =========================================================================
    // 내부 함수
    // =========================================================================

    /**
     * @notice P-256 서명 검증
     * @dev RIP-7212 precompile 우선 사용, 실패 시 라이브러리 fallback
     * @param hash 서명할 메시지 해시
     * @param signature 서명 데이터 (r, s, authenticatorData, clientDataJSON)
     * @return 검증 결과 (0 = 성공, 1 = 실패)
     */
    function _validateSignature(bytes32 hash, bytes calldata signature)
        internal
        view
        returns (uint256)
    {
        // 서명 디코딩: [r(32) | s(32) | authenticatorData(dynamic) | clientDataJSON(dynamic)]
        if (signature.length < 64) return SIG_VALIDATION_FAILED;

        bytes32 r = bytes32(signature[0:32]);
        bytes32 s = bytes32(signature[32:64]);

        // WebAuthn 서명 검증을 위한 해시 재계산
        // 실제 구현에서는 authenticatorData와 clientDataJSON을 포함한 검증 필요
        bytes32 messageHash = _computeWebAuthnHash(hash, signature[64:]);

        // RIP-7212 precompile로 P-256 검증 시도
        (bool success, bytes memory result) =
            P256_VERIFIER.staticcall(abi.encode(messageHash, r, s, publicKeyX, publicKeyY));

        if (success && result.length == 32) {
            // precompile이 1을 반환하면 검증 성공
            if (abi.decode(result, (uint256)) == 1) {
                return SIG_VALIDATION_SUCCESS;
            }
        }

        // TODO: RIP-7212 미지원 체인을 위한 라이브러리 fallback 구현
        // return _verifyP256WithLibrary(messageHash, r, s) ? SIG_VALIDATION_SUCCESS : SIG_VALIDATION_FAILED;

        return SIG_VALIDATION_FAILED;
    }

    /**
     * @notice WebAuthn 서명 해시 계산
     * @dev SHA-256(authenticatorData || SHA-256(clientDataJSON))
     * @param userOpHash 원본 UserOp 해시
     * @param webauthnData authenticatorData + clientDataJSON
     * @return WebAuthn 형식의 메시지 해시
     */
    function _computeWebAuthnHash(bytes32 userOpHash, bytes calldata webauthnData)
        internal
        pure
        returns (bytes32)
    {
        // 간소화된 구현 - 실제로는 WebAuthn 스펙에 맞게 구현 필요
        // authenticatorData와 clientDataJSON을 파싱하여 해시 계산
        return keccak256(abi.encodePacked(userOpHash, webauthnData));
    }

    // =========================================================================
    // 유틸리티
    // =========================================================================

    /**
     * @notice ETH 수신 허용
     */
    receive() external payable { }

    /**
     * @notice 계정 정보 조회
     * @return x 공개키 X 좌표
     * @return y 공개키 Y 좌표
     * @return credHash 자격 증명 ID 해시
     */
    function getAccountInfo() external view returns (bytes32 x, bytes32 y, bytes32 credHash) {
        return (publicKeyX, publicKeyY, credentialIdHash);
    }
}
