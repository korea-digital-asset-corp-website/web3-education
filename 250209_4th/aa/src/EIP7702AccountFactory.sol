// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { EIP7702Account } from "./EIP7702Account.sol";

/**
 * @title EIP7702AccountFactory
 * @notice EIP-7702 계정 관리 팩토리
 *
 * @dev EIP-7702의 특성:
 * - 이 Factory는 컨트랙트를 "배포"하는 것이 아님
 * - EOA가 SET_CODE_TX로 구현 컨트랙트에 위임하면, 해당 EOA가 스마트 계정이 됨
 * - 스토리지는 각 EOA 주소에 독립적으로 저장됨
 *
 * Factory의 역할:
 * 1. 올바른 구현 컨트랙트 주소 제공 (implementation)
 * 2. EOA 등록 및 추적
 * 3. 초기화 지원
 * 4. 버전 관리
 *
 * 사용 흐름:
 * 1. Factory 배포 (구현 컨트랙트도 함께 배포)
 * 2. 고객 EOA가 SET_CODE_TX로 implementation에 위임
 * 3. Factory.registerAccount()로 등록
 * 4. 이후 EOA가 스마트 계정으로 동작
 */
contract EIP7702AccountFactory {
    // =========================================================================
    // 상태 변수
    // =========================================================================

    /// @notice EIP7702Account 구현 컨트랙트 주소
    /// @dev 모든 EOA가 이 주소의 코드를 위임받음
    address public immutable implementation;

    /// @notice Factory 소유자
    address public owner;

    /// @notice 등록된 계정 목록
    mapping(address => bool) public registeredAccounts;

    /// @notice 등록된 계정 배열 (조회용)
    address[] public accounts;

    /// @notice 계정별 등록 시간
    mapping(address => uint256) public accountRegisteredAt;

    // =========================================================================
    // 이벤트
    // =========================================================================

    /// @notice 계정 등록 이벤트
    event AccountRegistered(address indexed account, address indexed registeredBy);

    /// @notice 소유권 이전 이벤트
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    // =========================================================================
    // 에러
    // =========================================================================

    /// @notice 소유자만 호출 가능
    error OnlyOwner();

    /// @notice 잘못된 주소
    error InvalidAddress();

    /// @notice 이미 등록된 계정
    error AlreadyRegistered();

    /// @notice 위임되지 않은 계정
    error NotDelegated();

    // =========================================================================
    // Modifier
    // =========================================================================

    modifier onlyOwner() {
        if (msg.sender != owner) revert OnlyOwner();
        _;
    }

    // =========================================================================
    // 생성자
    // =========================================================================

    /**
     * @notice Factory 생성
     * @param _implementation 기존 구현 컨트랙트 주소 (address(0)이면 새로 배포)
     */
    constructor(address _implementation) {
        owner = msg.sender;
        if (_implementation == address(0)) {
            // 구현 컨트랙트 새로 배포
            implementation = address(new EIP7702Account());
        } else {
            // 기존 구현 컨트랙트 사용
            implementation = _implementation;
        }
    }

    // =========================================================================
    // 계정 관리
    // =========================================================================

    /**
     * @notice 계정 등록 (EOA가 위임 후 호출)
     * @dev EOA가 implementation에 위임된 상태에서 호출해야 함
     */
    function registerAccount() external {
        _registerAccount(msg.sender);
    }

    /**
     * @notice 계정 등록 (제3자가 대신 등록)
     * @param account 등록할 EOA 주소
     */
    function registerAccountFor(address account) external {
        _registerAccount(account);
    }

    /**
     * @notice 계정 등록 내부 함수
     */
    function _registerAccount(address account) internal {
        if (account == address(0)) revert InvalidAddress();
        if (registeredAccounts[account]) revert AlreadyRegistered();

        // 위임 상태 확인 (코드가 0xef0100 + implementation 주소인지)
        bytes memory code = account.code;
        if (code.length != 23) revert NotDelegated();

        // 0xef0100 접두사 확인
        if (code[0] != 0xef || code[1] != 0x01 || code[2] != 0x00) {
            revert NotDelegated();
        }

        // implementation 주소 확인
        // bytes memory 구조: [32바이트 길이] + [실제 데이터]
        // 실제 데이터: [3바이트 0xef0100] + [20바이트 주소]
        address delegatedTo;
        assembly {
            // code + 32 (길이 건너뜀) + 3 (접두사 건너뜀) = code + 35
            // 32바이트 로드 후 상위 160비트(20바이트)에 주소가 있음
            delegatedTo := shr(96, mload(add(code, 35)))
        }

        if (delegatedTo != implementation) revert NotDelegated();

        // 등록
        registeredAccounts[account] = true;
        accounts.push(account);
        accountRegisteredAt[account] = block.timestamp;

        emit AccountRegistered(account, msg.sender);
    }

    // =========================================================================
    // 조회 함수
    // =========================================================================

    /**
     * @notice 계정이 등록되어 있는지 확인
     * @param account 확인할 주소
     * @return 등록 여부
     */
    function isRegistered(address account) external view returns (bool) {
        return registeredAccounts[account];
    }

    /**
     * @notice 계정이 올바르게 위임되어 있는지 확인
     * @param account 확인할 주소
     * @return 위임 상태
     */
    function isDelegated(address account) external view returns (bool) {
        bytes memory code = account.code;
        if (code.length != 23) return false;

        // 0xef0100 접두사 확인
        if (code[0] != 0xef || code[1] != 0x01 || code[2] != 0x00) {
            return false;
        }

        // implementation 주소 확인
        address delegatedTo;
        assembly {
            // code + 32 (길이 건너뜀) + 3 (접두사 건너뜀) = code + 35
            delegatedTo := shr(96, mload(add(code, 35)))
        }

        return delegatedTo == implementation;
    }

    /**
     * @notice 등록된 계정 수 조회
     * @return 계정 수
     */
    function getAccountCount() external view returns (uint256) {
        return accounts.length;
    }

    /**
     * @notice 등록된 계정 목록 조회 (페이지네이션)
     * @param offset 시작 인덱스
     * @param limit 최대 개수
     * @return result 계정 주소 배열
     */
    function getAccounts(uint256 offset, uint256 limit)
        external
        view
        returns (address[] memory result)
    {
        uint256 total = accounts.length;
        if (offset >= total) {
            return new address[](0);
        }

        uint256 end = offset + limit;
        if (end > total) {
            end = total;
        }

        result = new address[](end - offset);
        for (uint256 i = offset; i < end; i++) {
            result[i - offset] = accounts[i];
        }
    }

    /**
     * @notice 계정 정보 조회
     * @param account 조회할 주소
     * @return isReg 등록 여부
     * @return isDel 위임 상태
     * @return registeredAt 등록 시간
     * @return master 마스터 권한자
     */
    function getAccountInfo(address account)
        external
        view
        returns (bool isReg, bool isDel, uint256 registeredAt, address master)
    {
        isReg = registeredAccounts[account];
        isDel = this.isDelegated(account);
        registeredAt = accountRegisteredAt[account];

        if (isDel) {
            // 마스터 권한자 조회 (위임된 경우에만)
            try EIP7702Account(payable(account)).masterAuthority() returns (address m) {
                master = m;
            } catch {
                master = address(0);
            }
        }
    }

    // =========================================================================
    // 관리 함수
    // =========================================================================

    /**
     * @notice 소유권 이전
     * @param newOwner 새 소유자
     */
    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert InvalidAddress();
        address previousOwner = owner;
        owner = newOwner;
        emit OwnershipTransferred(previousOwner, newOwner);
    }
}
