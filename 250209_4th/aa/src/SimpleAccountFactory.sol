// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Create2 } from "@openzeppelin/contracts/utils/Create2.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { IEntryPoint } from "@account-abstraction/interfaces/IEntryPoint.sol";
import { SimpleAccountWithRecovery } from "./SimpleAccountWithRecovery.sol";

/**
 * @title SimpleAccountFactory
 * @notice ERC-4337 스마트 계정 Factory
 *
 * @dev CREATE2를 사용하여 결정적 주소로 계정 배포
 * - 동일한 owner + salt → 항상 동일한 주소
 * - 배포 전에 주소 예측 가능 → 미리 자금 입금 가능
 */
contract SimpleAccountFactory {
    // =========================================================================
    // 상태 변수
    // =========================================================================

    /// @notice 구현 컨트랙트 주소
    SimpleAccountWithRecovery public immutable accountImplementation;

    /// @notice EntryPoint 주소
    IEntryPoint public immutable entryPoint;

    // =========================================================================
    // 이벤트
    // =========================================================================

    event AccountCreated(address indexed account, address indexed owner, uint256 salt);

    // =========================================================================
    // 생성자
    // =========================================================================

    constructor(IEntryPoint _entryPoint) {
        entryPoint = _entryPoint;
        accountImplementation = new SimpleAccountWithRecovery(_entryPoint);
    }

    // =========================================================================
    // 계정 생성
    // =========================================================================

    /**
     * @notice 스마트 계정 생성
     * @param owner 계정 소유자
     * @param salt 결정적 주소 생성용 salt
     * @return account 생성된 계정 주소
     */
    function createAccount(address owner, uint256 salt) external returns (address account) {
        address predicted = getAddress(owner, salt);

        // 이미 배포된 경우 기존 주소 반환
        if (predicted.code.length > 0) {
            return predicted;
        }

        // ERC1967Proxy로 배포
        bytes memory initData = abi.encodeCall(SimpleAccountWithRecovery.initialize, (owner));

        account = address(
            new ERC1967Proxy{ salt: bytes32(salt) }(address(accountImplementation), initData)
        );

        emit AccountCreated(account, owner, salt);
    }

    /**
     * @notice 스마트 계정 생성 (Guardian 포함)
     * @param owner 계정 소유자
     * @param guardians Guardian 목록
     * @param salt 결정적 주소 생성용 salt
     * @return account 생성된 계정 주소
     */
    function createAccountWithGuardians(
        address owner,
        address[] calldata guardians,
        uint256 salt
    ) external returns (address account) {
        address predicted = getAddressWithGuardians(owner, guardians, salt);

        // 이미 배포된 경우 기존 주소 반환
        if (predicted.code.length > 0) {
            return predicted;
        }

        // ERC1967Proxy로 배포
        bytes memory initData =
            abi.encodeCall(SimpleAccountWithRecovery.initializeWithGuardians, (owner, guardians));

        account = address(
            new ERC1967Proxy{ salt: bytes32(salt) }(address(accountImplementation), initData)
        );

        emit AccountCreated(account, owner, salt);
    }

    // =========================================================================
    // 주소 예측
    // =========================================================================

    /**
     * @notice 계정 주소 예측
     * @param owner 계정 소유자
     * @param salt 결정적 주소 생성용 salt
     * @return 예측된 계정 주소
     */
    function getAddress(address owner, uint256 salt) public view returns (address) {
        bytes memory initData = abi.encodeCall(SimpleAccountWithRecovery.initialize, (owner));

        bytes memory bytecode = abi.encodePacked(
            type(ERC1967Proxy).creationCode,
            abi.encode(address(accountImplementation), initData)
        );

        return Create2.computeAddress(bytes32(salt), keccak256(bytecode));
    }

    /**
     * @notice 계정 주소 예측 (Guardian 포함)
     * @param owner 계정 소유자
     * @param guardians Guardian 목록
     * @param salt 결정적 주소 생성용 salt
     * @return 예측된 계정 주소
     */
    function getAddressWithGuardians(
        address owner,
        address[] calldata guardians,
        uint256 salt
    ) public view returns (address) {
        bytes memory initData =
            abi.encodeCall(SimpleAccountWithRecovery.initializeWithGuardians, (owner, guardians));

        bytes memory bytecode = abi.encodePacked(
            type(ERC1967Proxy).creationCode,
            abi.encode(address(accountImplementation), initData)
        );

        return Create2.computeAddress(bytes32(salt), keccak256(bytecode));
    }
}
