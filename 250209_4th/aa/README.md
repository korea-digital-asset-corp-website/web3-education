# Account Abstraction 실습 프로젝트

EIP-7702, Safe (Gnosis Safe) 스마트 계정 패턴을 Foundry + viem으로 직접 빌드/배포/상호작용하는 독립 실습 프로젝트입니다.

## 사전 요구사항

- [Foundry](https://getfoundry.sh/) (forge, anvil)
- [Node.js](https://nodejs.org/) >= 20
- [pnpm](https://pnpm.io/)

## 시작하기

### 1. 환경 설정

```bash
cd apps/aa
cp .env.example .env
pnpm install
```

### 2. Foundry 빌드 & 테스트

```bash
# Solidity 컴파일
forge build

# 테스트 실행 (30개)
forge test -vvv
```

### 3. 로컬 Anvil 노드 실행

```bash
# 터미널 1: Anvil 실행
anvil
```

### 4. 컨트랙트 배포

```bash
# 터미널 2: EIP-7702 컨트랙트 배포
forge script script/DeployEIP7702.s.sol \
  --rpc-url http://localhost:8545 \
  --broadcast

# 배포된 주소를 .env에 업데이트
```

## 디렉토리 구조

```
apps/aa/
├── src/                          # Solidity 컨트랙트
│   ├── EIP7702Account.sol        # EIP-7702 스마트 계정
│   ├── EIP7702AccountFactory.sol # 계정 팩토리
│   ├── VerifyingPaymaster.sol    # ERC-4337 Paymaster
│   ├── SimpleAccountWithRecovery.sol
│   ├── SimpleAccountFactory.sol
│   ├── PasskeyAccount.sol
│   └── PasskeyAccountFactory.sol
│
├── test/                         # Forge 테스트
│   ├── EIP7702Account.t.sol      # 19개 테스트
│   └── VerifyingPaymaster.t.sol  # 11개 테스트
│
├── script/                       # 배포 스크립트
│   ├── DeployEIP7702.s.sol
│   └── Deploy.s.sol
│
└── scripts/                      # TypeScript 상호작용 스크립트
    ├── common/
    │   ├── config.ts             # 환경 변수 설정
    │   ├── client.ts             # viem 클라이언트
    │   └── abi.ts                # ABI 정의
    │
    ├── 01-eip7702/               # EIP-7702 실습 (6단계)
    │   ├── 01-create-delegation.ts
    │   ├── 02-execute-transfer.ts
    │   ├── 03-add-delegate.ts
    │   ├── 04-batch-execute.ts
    │   ├── 05-meta-transaction.ts
    │   └── 06-change-master.ts
    │
    └── 02-safe/                  # Safe 실습 (3단계)
        ├── 01-deploy-safe.ts
        ├── 02-exec-transaction.ts
        └── 03-enable-module.ts
```

## 실습 1: EIP-7702

EIP-7702는 일반 EOA(외부 소유 계정)에 스마트 컨트랙트 기능을 위임하는 표준입니다.

### 핵심 개념

- **위임(Delegation)**: EOA가 스마트 컨트랙트의 코드를 빌려서 실행
- **Type 4 트랜잭션**: `authorizationList`로 위임 설정
- **EOA 주소 유지**: 위임 후에도 원래 EOA 주소 그대로 사용

### 단계별 실행

```bash
# 1단계: EIP-7702 위임 생성 + 초기화
pnpm eip7702:delegate

# 2단계: execute()로 ETH 전송
pnpm eip7702:transfer

# 3단계: Delegate 추가 (대리인 등록)
pnpm eip7702:add-delegate

# 4단계: 배치 트랜잭션 (한 번에 여러 전송)
pnpm eip7702:batch

# 5단계: 메타 트랜잭션 (가스 대납)
pnpm eip7702:meta-tx

# 6단계: 마스터 권한 이전
pnpm eip7702:change-master
```

### EIP-7702 흐름

```
[1단계: 위임]
Owner EOA ──signAuthorization()──→ 구현 컨트랙트 주소 서명
         ──sendTransaction(authorizationList)──→ 체인에 위임 등록
         ──initialize()──→ Owner를 마스터로 설정

[2단계: 실행]
Owner ──execute(to, value, data)──→ 위임된 EOA가 스마트 계정으로 동작

[3단계: 대리인]
Owner ──addDelegate(address)──→ 다른 EOA도 실행 가능

[4단계: 배치]
Owner ──executeBatch([to1,to2], [v1,v2], [d1,d2])──→ 한 TX로 여러 실행

[5단계: 메타TX]
Owner ──signTypedData(EIP-712)──→ 오프체인 서명
Relayer ──executeWithSignature(sig)──→ Relayer가 가스 지불

[6단계: 마스터 이전]
Owner ──setMasterAuthority(newMaster)──→ 소유권 이전
```

## 실습 2: Safe (Gnosis Safe)

Safe는 가장 널리 사용되는 다중서명 지갑입니다.

### 핵심 개념

- **Proxy 패턴**: 최소 코드만 배포, 로직은 Singleton 참조
- **CREATE2**: 동일 파라미터 → 어떤 체인에서든 동일 주소
- **eth_sign + v+4**: Safe의 서명 컨벤션
- **Self-call**: Safe가 자기 자신을 호출하여 설정 변경

### 단계별 실행

```bash
# 1단계: Safe Proxy 배포
pnpm safe:deploy
# 출력된 Safe 주소를 .env에 SAFE_ADDRESS로 설정

# 2단계: Safe 트랜잭션 실행 (ETH 전송)
pnpm safe:exec

# 3단계: 모듈 활성화
pnpm safe:module
```

### Safe 트랜잭션 흐름

```
[1단계: 배포]
ProxyFactory ──createProxyWithNonce(singleton, setupData, salt)──→ Safe Proxy 생성
             ──setup(owners, threshold, ...)──→ 초기화

[2단계: 트랜잭션]
getTransactionHash(to, value, data, ..., nonce)
  → safeTxHash 계산
  → signMessage({ raw: safeTxHash })  // eth_sign
  → v += 4  // Safe 컨벤션
  → execTransaction(..., adjustedSignature)

[3단계: 모듈]
encodeFunctionData("enableModule", [moduleAddr])
  → execTransaction(safeAddress, 0, data, ...)  // Safe self-call
```

## Forge 테스트

### EIP7702Account 테스트 (19개)

| 카테고리 | 테스트 |
|---------|--------|
| 초기화 | initialize, initializeWithMaster |
| 실행 | execute ETH 전송, 권한 없는 실행 revert |
| Delegate | 추가, 삭제, 중복 추가 revert, Delegate 실행 |
| 배치 | executeBatch 다중 전송 |
| 마스터 관리 | setMasterAuthority |
| 메타 TX | EIP-712 서명 + executeWithSignature |
| 기타 | getAccountInfo, ETH receive |

### VerifyingPaymaster 테스트 (11개)

| 카테고리 | 테스트 |
|---------|--------|
| 초기 상태 | owner, entryPoint 확인 |
| 화이트리스트 | 추가, 삭제, 일괄 추가, 권한 revert |
| Verifier | 설정, 권한 revert |
| 기타 | ETH receive, onlyEntryPoint revert |

```bash
# 전체 테스트
forge test -vvv

# 특정 테스트만
forge test --match-test test_execute_ethTransfer -vvv

# 가스 리포트
forge test --gas-report
```

## 환경 변수

| 변수 | 설명 | 기본값 |
|------|------|--------|
| `RPC_URL` | RPC 엔드포인트 | `http://localhost:8545` |
| `OWNER_PRIVATE_KEY` | Owner 개인키 | Anvil 계정 #0 |
| `DELEGATE_PRIVATE_KEY` | Delegate 개인키 | Anvil 계정 #1 |
| `RELAYER_PRIVATE_KEY` | Relayer 개인키 | Anvil 계정 #2 |
| `EIP7702_ACCOUNT_IMPL` | 구현 컨트랙트 주소 | - |
| `SAFE_SINGLETON` | Safe Singleton 주소 | 표준 주소 |
| `SAFE_PROXY_FACTORY` | Safe ProxyFactory 주소 | 표준 주소 |
| `SAFE_ADDRESS` | 배포된 Safe 주소 | - |

## 주요 명령어

```bash
# Foundry
forge build          # 컴파일
forge test -vvv      # 테스트
forge test --gas-report  # 가스 분석

# TypeScript
pnpm typecheck       # 타입 체크
pnpm eip7702:*       # EIP-7702 스크립트
pnpm safe:*          # Safe 스크립트
```

## 참고 자료

- [EIP-7702](https://eips.ethereum.org/EIPS/eip-7702) - EOA 코드 위임
- [EIP-712](https://eips.ethereum.org/EIPS/eip-712) - 타입 구조화 데이터 서명
- [ERC-4337](https://eips.ethereum.org/EIPS/eip-4337) - Account Abstraction
- [Safe Docs](https://docs.safe.global/) - Safe 공식 문서
- [viem Docs](https://viem.sh/) - TypeScript 블록체인 라이브러리
- [Foundry Book](https://book.getfoundry.sh/) - Foundry 공식 문서
