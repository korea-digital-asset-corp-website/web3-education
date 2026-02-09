// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Create2 } from "@openzeppelin/contracts/utils/Create2.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { PasskeyAccount } from "./PasskeyAccount.sol";

/**
 * @title PasskeyAccountFactory
 * @notice PasskeyAccount 배포를 위한 팩토리 컨트랙트
 * @dev CREATE2를 사용하여 결정론적 주소 생성
 *
 * 주요 기능:
 * - 배포 전 주소 예측 (counterfactual address)
 * - ERC1967 프록시 패턴 사용 (업그레이드 가능)
 * - 동일한 자격 증명으로 동일한 주소 생성
 */
contract PasskeyAccountFactory {
    // =========================================================================
    // 상태 변수
    // =========================================================================

    /// @notice PasskeyAccount 구현체 주소
    address public immutable accountImplementation;

    // =========================================================================
    // 이벤트
    // =========================================================================

    /// @notice 새 계정 생성 이벤트
    event AccountCreated(
        address indexed account,
        bytes32 indexed credentialIdHash,
        bytes32 publicKeyX,
        bytes32 publicKeyY
    );

    // =========================================================================
    // 생성자
    // =========================================================================

    /**
     * @notice 팩토리 배포 및 구현체 생성
     */
    constructor() {
        accountImplementation = address(new PasskeyAccount());
    }

    // =========================================================================
    // 계정 생성
    // =========================================================================

    /**
     * @notice 새 PasskeyAccount 생성 또는 기존 계정 주소 반환
     * @dev 이미 배포된 경우 기존 주소 반환 (멱등성)
     * @param credentialIdHash 자격 증명 ID의 keccak256 해시
     * @param publicKeyX P-256 공개키 X 좌표
     * @param publicKeyY P-256 공개키 Y 좌표
     * @param salt 추가 salt (동일 자격 증명으로 여러 계정 생성 시 사용)
     * @return account 생성된 계정 주소
     */
    function createAccount(
        bytes32 credentialIdHash,
        bytes32 publicKeyX,
        bytes32 publicKeyY,
        uint256 salt
    ) external returns (address account) {
        // 주소 계산
        address predicted = getAddress(credentialIdHash, publicKeyX, publicKeyY, salt);

        // 이미 배포된 경우 기존 주소 반환
        if (predicted.code.length > 0) {
            return predicted;
        }

        // 초기화 데이터 생성
        bytes memory initData = abi.encodeWithSelector(
            PasskeyAccount.initialize.selector, credentialIdHash, publicKeyX, publicKeyY
        );

        // CREATE2로 프록시 배포
        bytes32 create2Salt = _computeSalt(credentialIdHash, publicKeyX, publicKeyY, salt);
        account = address(new ERC1967Proxy{ salt: create2Salt }(accountImplementation, initData));

        emit AccountCreated(account, credentialIdHash, publicKeyX, publicKeyY);
    }

    // =========================================================================
    // 주소 예측
    // =========================================================================

    /**
     * @notice 배포 전 계정 주소 예측 (counterfactual address)
     * @dev CREATE2 주소 계산 공식 사용
     * @param credentialIdHash 자격 증명 ID의 keccak256 해시
     * @param publicKeyX P-256 공개키 X 좌표
     * @param publicKeyY P-256 공개키 Y 좌표
     * @param salt 추가 salt
     * @return 예측된 계정 주소
     */
    function getAddress(
        bytes32 credentialIdHash,
        bytes32 publicKeyX,
        bytes32 publicKeyY,
        uint256 salt
    ) public view returns (address) {
        // 초기화 데이터 생성
        bytes memory initData = abi.encodeWithSelector(
            PasskeyAccount.initialize.selector, credentialIdHash, publicKeyX, publicKeyY
        );

        // 프록시 생성 코드
        bytes memory proxyCreationCode = abi.encodePacked(
            type(ERC1967Proxy).creationCode, abi.encode(accountImplementation, initData)
        );

        // CREATE2 주소 계산
        bytes32 create2Salt = _computeSalt(credentialIdHash, publicKeyX, publicKeyY, salt);
        return Create2.computeAddress(create2Salt, keccak256(proxyCreationCode));
    }

    // =========================================================================
    // 내부 함수
    // =========================================================================

    /**
     * @notice CREATE2 salt 계산
     * @param credentialIdHash 자격 증명 ID 해시
     * @param publicKeyX 공개키 X
     * @param publicKeyY 공개키 Y
     * @param salt 추가 salt
     * @return 계산된 salt
     */
    function _computeSalt(
        bytes32 credentialIdHash,
        bytes32 publicKeyX,
        bytes32 publicKeyY,
        uint256 salt
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(credentialIdHash, publicKeyX, publicKeyY, salt));
    }
}
