// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title EIP7702Account
 * @notice EIP-7702 호환 스마트 계정 - EOA에 위임되어 스마트 계정 기능 제공
 *
 * @dev EIP-7702의 핵심 특성:
 * - EOA가 SET_CODE_TX (0x04)로 이 컨트랙트에 코드를 위임
 * - 코드는 이 컨트랙트에서 가져오지만, 스토리지는 EOA 주소에 저장됨
 * - 따라서 여러 EOA가 같은 컨트랙트를 위임받아도 각자의 스토리지는 독립적
 * - Factory 없이도 고객별 독립적인 스마트 계정 운영 가능
 *
 * 주요 사용 시나리오:
 * 1. A EOA가 이 컨트랙트에 위임 → A EOA가 스마트 계정처럼 동작
 * 2. A EOA의 마스터 권한을 B EOA로 자발적 이전
 * 3. B EOA가 A EOA(주소)의 자산을 계속 관리 가능
 *
 * ⚠️ 주의: EOA 개인키를 분실하면 복구 불가능
 * - EOA 개인키 소유자는 컨트랙트 로직을 우회하여 직접 트랜잭션 가능
 * - Guardian으로는 EOA 개인키를 무력화할 수 없음
 * - 키 복구가 필요한 경우 ERC-4337 (Safe) 사용 권장
 *
 * 주요 기능:
 * - 단일/배치 트랜잭션 실행
 * - 마스터 권한 관리 (자발적 소유권 이전)
 * - Delegate EOA 추가/제거 (권한 위임)
 * - 메타 트랜잭션 (EIP-712 가스 대납)
 */
contract EIP7702Account {
    // =========================================================================
    // 상태 변수 (각 EOA의 스토리지에 독립적으로 저장됨)
    // =========================================================================

    /// @notice 마스터 권한자 (계정 소유자)
    /// @dev 초기값은 address(0)이며, 첫 트랜잭션 시 msg.sender로 설정됨
    address public masterAuthority;

    /// @notice 허용된 delegate 목록
    /// @dev delegate는 마스터 대신 트랜잭션을 실행할 수 있음
    mapping(address => bool) public delegates;

    /// @notice 위임 설정 여부
    bool public initialized;

    /// @notice 메타 트랜잭션 nonce (주소별)
    /// @dev replay 공격 방지용
    mapping(address => uint256) public nonces;

    // =========================================================================
    // EIP-712 상수
    // =========================================================================

    /// @notice EIP-712 도메인 타입 해시
    bytes32 public constant DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

    /// @notice Execute 메시지 타입 해시
    bytes32 public constant EXECUTE_TYPEHASH =
        keccak256("Execute(address to,uint256 value,bytes data,uint256 nonce,uint256 deadline)");

    /// @notice ExecuteBatch 메시지 타입 해시
    bytes32 public constant EXECUTE_BATCH_TYPEHASH =
        keccak256("ExecuteBatch(address[] targets,uint256[] values,bytes[] datas,uint256 nonce,uint256 deadline)");

    /// @notice 도메인 이름
    string public constant NAME = "EIP7702Account";

    /// @notice 버전
    string public constant VERSION = "1";

    // =========================================================================
    // 이벤트
    // =========================================================================

    /// @notice 계정 초기화 이벤트
    event AccountInitialized(address indexed master);

    /// @notice 마스터 권한 변경 이벤트
    event MasterAuthorityChanged(address indexed previousMaster, address indexed newMaster);

    /// @notice Delegate 추가 이벤트
    event DelegateAdded(address indexed delegate);

    /// @notice Delegate 제거 이벤트
    event DelegateRemoved(address indexed delegate);

    /// @notice 트랜잭션 실행 이벤트
    event Executed(address indexed target, uint256 value, bytes data, bool success);

    /// @notice 배치 트랜잭션 실행 이벤트
    event BatchExecuted(uint256 count, bool allSuccess);

    // =========================================================================
    // 에러
    // =========================================================================

    /// @notice 권한 없음
    error Unauthorized();

    /// @notice 이미 초기화됨
    error AlreadyInitialized();

    /// @notice 잘못된 주소
    error InvalidAddress();

    /// @notice 트랜잭션 실행 실패
    error ExecutionFailed(bytes reason);

    /// @notice 배열 길이 불일치
    error LengthMismatch();

    /// @notice 이미 delegate로 등록됨
    error AlreadyDelegate();

    /// @notice delegate로 등록되지 않음
    error NotDelegate();

    // =========================================================================
    // Modifier
    // =========================================================================

    /// @notice 마스터 또는 delegate만 호출 가능
    modifier onlyAuthorized() {
        _checkAuthorized();
        _;
    }

    /// @notice 마스터만 호출 가능
    modifier onlyMaster() {
        if (msg.sender != masterAuthority) revert Unauthorized();
        _;
    }

    // =========================================================================
    // 초기화
    // =========================================================================

    /**
     * @notice 계정 초기화 (첫 트랜잭션 시 자동 호출)
     * @dev EIP-7702에서는 EOA가 직접 트랜잭션을 보내므로,
     *      첫 execute 호출 시 msg.sender를 마스터로 설정
     */
    function initialize() external {
        if (initialized) revert AlreadyInitialized();
        initialized = true;
        masterAuthority = msg.sender;
        emit AccountInitialized(msg.sender);
    }

    /**
     * @notice 계정 초기화 (마스터 지정)
     * @param master 마스터 권한자 주소
     */
    function initializeWithMaster(address master) external {
        if (initialized) revert AlreadyInitialized();
        if (master == address(0)) revert InvalidAddress();
        initialized = true;
        masterAuthority = master;
        emit AccountInitialized(master);
    }

    // =========================================================================
    // 실행 함수
    // =========================================================================

    /**
     * @notice 단일 트랜잭션 실행
     * @param target 대상 주소
     * @param value 전송할 ETH 양
     * @param data 호출 데이터
     * @return result 반환 데이터
     */
    function execute(address target, uint256 value, bytes calldata data)
        external
        onlyAuthorized
        returns (bytes memory result)
    {
        _ensureInitialized();

        bool success;
        (success, result) = target.call{ value: value }(data);

        if (!success) {
            revert ExecutionFailed(result);
        }

        emit Executed(target, value, data, success);
    }

    /**
     * @notice 다중 트랜잭션 배치 실행
     * @param targets 대상 주소 배열
     * @param values 전송할 ETH 양 배열
     * @param datas 호출 데이터 배열
     * @return results 반환 데이터 배열
     */
    function executeBatch(
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata datas
    ) external onlyAuthorized returns (bytes[] memory results) {
        _ensureInitialized();

        uint256 length = targets.length;
        if (length != values.length || length != datas.length) {
            revert LengthMismatch();
        }

        results = new bytes[](length);
        bool allSuccess = true;

        for (uint256 i = 0; i < length; i++) {
            (bool success, bytes memory result) = targets[i].call{ value: values[i] }(datas[i]);

            if (!success) {
                allSuccess = false;
                revert ExecutionFailed(result);
            }

            results[i] = result;
            emit Executed(targets[i], values[i], datas[i], success);
        }

        emit BatchExecuted(length, allSuccess);
    }

    /**
     * @notice 메타 트랜잭션 실행 (EIP-712 서명 검증)
     * @dev Owner가 오프체인에서 서명한 트랜잭션을 Relayer가 대신 제출
     * @param signer 서명자 주소 (Owner 또는 Delegate)
     * @param target 대상 주소
     * @param value 전송할 ETH 양
     * @param data 호출 데이터
     * @param deadline 서명 만료 시간
     * @param signature Owner의 EIP-712 서명 (65 bytes: r(32) + s(32) + v(1))
     * @return result 반환 데이터
     */
    function executeWithSignature(
        address signer,
        address target,
        uint256 value,
        bytes calldata data,
        uint256 deadline,
        bytes calldata signature
    ) external returns (bytes memory result) {
        _ensureInitialized();

        // 1. 서명자가 authorized인지 확인
        require(
            signer == masterAuthority || delegates[signer],
            "Signer not authorized"
        );

        // 2. deadline 확인
        require(block.timestamp <= deadline, "Signature expired");

        // 3. 서명 파싱 (r, s, v)
        require(signature.length == 65, "Invalid signature length");
        bytes32 r;
        bytes32 s;
        uint8 v;
        assembly {
            r := calldataload(signature.offset)
            s := calldataload(add(signature.offset, 32))
            v := byte(0, calldataload(add(signature.offset, 64)))
        }

        // 4. 현재 서명자의 nonce 가져오기
        uint256 currentNonce = nonces[signer];

        // 5. EIP-712 도메인 separator 계산
        bytes32 domainSeparator = keccak256(
            abi.encode(
                DOMAIN_TYPEHASH,
                keccak256(bytes(NAME)),
                keccak256(bytes(VERSION)),
                block.chainid,
                address(this)
            )
        );

        // 6. 구조화된 데이터 해시 계산
        bytes32 structHash = keccak256(
            abi.encode(
                EXECUTE_TYPEHASH,
                target,
                value,
                keccak256(data),
                currentNonce,
                deadline
            )
        );

        // 7. EIP-712 digest 계산
        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", domainSeparator, structHash)
        );

        // 8. ecrecover로 서명자 복구 및 검증
        address recoveredSigner = ecrecover(digest, v, r, s);
        require(recoveredSigner == signer, "Invalid signature");

        // 9. nonce 증가 (replay 공격 방지)
        nonces[signer]++;

        // 10. 트랜잭션 실행
        bool success;
        (success, result) = target.call{ value: value }(data);

        if (!success) {
            revert ExecutionFailed(result);
        }

        emit Executed(target, value, data, success);
    }

    /**
     * @notice 배치 메타 트랜잭션 실행 (EIP-712 서명 검증)
     * @dev Owner가 오프체인에서 서명한 배치 트랜잭션을 Relayer가 대신 제출
     * @param signer 서명자 주소 (Owner 또는 Delegate)
     * @param targets 대상 주소 배열
     * @param values 전송할 ETH 양 배열
     * @param datas 호출 데이터 배열
     * @param deadline 서명 만료 시간
     * @param signature Owner의 EIP-712 서명 (65 bytes: r(32) + s(32) + v(1))
     * @return results 반환 데이터 배열
     */
    function executeBatchWithSignature(
        address signer,
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata datas,
        uint256 deadline,
        bytes calldata signature
    ) external returns (bytes[] memory results) {
        _ensureInitialized();

        // 1. 배열 길이 검증
        uint256 length = targets.length;
        if (length != values.length || length != datas.length) {
            revert LengthMismatch();
        }

        // 2. 서명자가 authorized인지 확인
        require(
            signer == masterAuthority || delegates[signer],
            "Signer not authorized"
        );

        // 3. deadline 확인
        require(block.timestamp <= deadline, "Signature expired");

        // 4. 서명 파싱 (r, s, v)
        require(signature.length == 65, "Invalid signature length");
        bytes32 r;
        bytes32 s;
        uint8 v;
        assembly {
            r := calldataload(signature.offset)
            s := calldataload(add(signature.offset, 32))
            v := byte(0, calldataload(add(signature.offset, 64)))
        }

        // 5. 현재 서명자의 nonce 가져오기
        uint256 currentNonce = nonces[signer];

        // 6. EIP-712 도메인 separator 계산
        bytes32 domainSeparator = keccak256(
            abi.encode(
                DOMAIN_TYPEHASH,
                keccak256(bytes(NAME)),
                keccak256(bytes(VERSION)),
                block.chainid,
                address(this)
            )
        );

        // 7. 배치 데이터 해시 계산
        // targets, values, datas 각각을 해시
        bytes32 targetsHash = keccak256(abi.encodePacked(targets));
        bytes32 valuesHash = keccak256(abi.encodePacked(values));

        // datas 배열의 각 요소를 해시한 후 전체 배열 해시
        bytes32[] memory dataHashes = new bytes32[](length);
        for (uint256 i = 0; i < length; i++) {
            dataHashes[i] = keccak256(datas[i]);
        }
        bytes32 datasHash = keccak256(abi.encodePacked(dataHashes));

        // 8. 구조화된 데이터 해시 계산
        bytes32 structHash = keccak256(
            abi.encode(
                EXECUTE_BATCH_TYPEHASH,
                targetsHash,
                valuesHash,
                datasHash,
                currentNonce,
                deadline
            )
        );

        // 9. EIP-712 digest 계산
        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", domainSeparator, structHash)
        );

        // 10. ecrecover로 서명자 복구 및 검증
        address recoveredSigner = ecrecover(digest, v, r, s);
        require(recoveredSigner == signer, "Invalid signature");

        // 11. nonce 증가 (replay 공격 방지)
        nonces[signer]++;

        // 12. 배치 트랜잭션 실행
        results = new bytes[](length);
        bool allSuccess = true;

        for (uint256 i = 0; i < length; i++) {
            (bool success, bytes memory result) = targets[i].call{ value: values[i] }(datas[i]);

            if (!success) {
                allSuccess = false;
                revert ExecutionFailed(result);
            }

            results[i] = result;
            emit Executed(targets[i], values[i], datas[i], success);
        }

        emit BatchExecuted(length, allSuccess);
    }

    // =========================================================================
    // 권한 관리
    // =========================================================================

    /**
     * @notice 마스터 권한 변경 (소유권 이전)
     * @dev A EOA의 자산을 B EOA가 관리하도록 권한 이전
     * @param newMaster 새 마스터 주소
     */
    function setMasterAuthority(address newMaster) external onlyMaster {
        if (newMaster == address(0)) revert InvalidAddress();

        address previousMaster = masterAuthority;
        masterAuthority = newMaster;

        emit MasterAuthorityChanged(previousMaster, newMaster);
    }

    /**
     * @notice Delegate 추가
     * @param delegate 추가할 delegate 주소
     */
    function addDelegate(address delegate) external onlyMaster {
        if (delegate == address(0)) revert InvalidAddress();
        if (delegates[delegate]) revert AlreadyDelegate();

        delegates[delegate] = true;
        emit DelegateAdded(delegate);
    }

    /**
     * @notice Delegate 제거
     * @param delegate 제거할 delegate 주소
     */
    function removeDelegate(address delegate) external onlyMaster {
        if (!delegates[delegate]) revert NotDelegate();

        delegates[delegate] = false;
        emit DelegateRemoved(delegate);
    }

    // =========================================================================
    // 조회 함수
    // =========================================================================

    /**
     * @notice 주소가 권한이 있는지 확인
     * @param account 확인할 주소
     * @return 권한 여부
     */
    function isAuthorized(address account) external view returns (bool) {
        return account == masterAuthority || delegates[account];
    }

    /**
     * @notice 계정 정보 조회
     * @return master 마스터 주소
     * @return isInit 초기화 여부
     */
    function getAccountInfo()
        external
        view
        returns (address master, bool isInit)
    {
        return (masterAuthority, initialized);
    }

    // =========================================================================
    // 내부 함수
    // =========================================================================

    /**
     * @dev 권한 확인
     */
    function _checkAuthorized() internal view {
        if (msg.sender != masterAuthority && !delegates[msg.sender]) {
            revert Unauthorized();
        }
    }

    /**
     * @dev 초기화 확인 및 자동 초기화
     */
    function _ensureInitialized() internal {
        if (!initialized) {
            initialized = true;
            masterAuthority = msg.sender;
            emit AccountInitialized(msg.sender);
        }
    }

    // =========================================================================
    // 유틸리티
    // =========================================================================

    /**
     * @notice ETH 수신 허용
     */
    receive() external payable { }

    /**
     * @notice Fallback 함수
     */
    fallback() external payable { }
}
