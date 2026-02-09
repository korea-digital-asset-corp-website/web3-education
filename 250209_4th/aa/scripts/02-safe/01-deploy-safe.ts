/**
 * 01-deploy-safe.ts
 *
 * Safe (Gnosis Safe) Proxy 배포
 *
 * 동작:
 * 1. setup() 초기화 데이터를 인코딩
 * 2. CREATE2로 배포될 주소를 미리 계산
 * 3. createProxyWithNonce()로 Safe Proxy 배포
 * 4. 배포된 Safe 상태 검증
 *
 * 핵심:
 * - CREATE2: 동일 파라미터 → 동일 주소 (체인에 관계없이)
 * - Safe Proxy: 최소 코드만 배포, 로직은 Singleton 참조
 * - setup(): Owner, threshold, fallback handler 초기화
 *
 * 사전 조건:
 * - Anvil 로컬 노드 실행 중 (또는 테스트넷 RPC)
 * - Safe Singleton, ProxyFactory가 체인에 배포되어 있어야 함
 *   (Anvil에서는 직접 배포 필요, 테스트넷은 이미 배포됨)
 */

import {
  encodeFunctionData,
  keccak256,
  concat,
  pad,
  toHex,
  type Address,
  type Hex,
  getAddress,
} from "viem";
import { getPublicClient, getWalletClient, shortenAddress, chain } from "../common/client.js";
import { OWNER_PRIVATE_KEY } from "../common/config.js";
import { SAFE_PROXY_FACTORY_ABI, SAFE_ABI } from "../common/abi.js";
import {
  SAFE_SINGLETON,
  SAFE_PROXY_FACTORY,
  SAFE_FALLBACK_HANDLER,
} from "../common/config.js";

const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000" as Address;

async function main() {
  console.log("=== Safe Proxy 배포 ===\n");

  const publicClient = getPublicClient();
  const ownerClient = getWalletClient(OWNER_PRIVATE_KEY);
  const owner = ownerClient.account;

  console.log(`체인: ${chain.name}`);
  console.log(`Owner: ${shortenAddress(owner.address)}`);
  console.log(`Singleton:    ${shortenAddress(SAFE_SINGLETON)}`);
  console.log(`ProxyFactory: ${shortenAddress(SAFE_PROXY_FACTORY)}\n`);

  // Step 1: setup() 초기화 데이터 인코딩
  console.log("1. Setup 데이터 인코딩...");

  const owners = [owner.address];
  const threshold = 1n;
  const saltNonce = BigInt(Date.now()); // 고유 nonce

  const setupData = encodeFunctionData({
    abi: SAFE_ABI,
    functionName: "setup",
    args: [
      owners,                // Owner 목록
      threshold,             // 서명 임계값
      ZERO_ADDRESS,          // to (delegatecall 대상 없음)
      "0x" as Hex,           // data (빈 데이터)
      SAFE_FALLBACK_HANDLER, // fallback handler
      ZERO_ADDRESS,          // paymentToken (ETH 사용)
      0n,                    // payment (없음)
      ZERO_ADDRESS,          // paymentReceiver
    ],
  });
  console.log(`   Owners: [${owners.map(shortenAddress).join(", ")}]`);
  console.log(`   Threshold: ${threshold}`);
  console.log(`   Salt Nonce: ${saltNonce}`);

  // Step 2: CREATE2 주소 예측
  console.log("\n2. CREATE2 주소 계산...");

  const proxyCreationCode = await publicClient.readContract({
    address: SAFE_PROXY_FACTORY,
    abi: SAFE_PROXY_FACTORY_ABI,
    functionName: "proxyCreationCode",
  }) as Hex;

  const deploymentData = concat([
    proxyCreationCode,
    pad(SAFE_SINGLETON, { size: 32 }),
  ]);

  const salt = keccak256(
    concat([
      keccak256(setupData),
      pad(toHex(saltNonce), { size: 32 }),
    ])
  );

  const hash = keccak256(
    concat([
      "0xff" as Hex,
      pad(SAFE_PROXY_FACTORY, { size: 20 }),
      salt,
      keccak256(deploymentData),
    ])
  );

  const predictedAddress = getAddress(`0x${hash.slice(-40)}`) as Address;
  console.log(`   예측 주소: ${predictedAddress}`);

  // Step 3: Proxy 배포
  console.log("\n3. createProxyWithNonce() 호출 중...");

  const txHash = await ownerClient.writeContract({
    address: SAFE_PROXY_FACTORY,
    abi: SAFE_PROXY_FACTORY_ABI,
    functionName: "createProxyWithNonce",
    args: [SAFE_SINGLETON, setupData, saltNonce],
  });
  console.log(`   TX: ${txHash}`);

  const receipt = await publicClient.waitForTransactionReceipt({ hash: txHash });
  console.log(`   상태: ${receipt.status}`);
  console.log(`   Gas Used: ${receipt.gasUsed}\n`);

  // 이벤트에서 실제 배포 주소 추출
  let deployedAddress: Address | null = null;
  for (const log of receipt.logs) {
    if (log.address.toLowerCase() === SAFE_PROXY_FACTORY.toLowerCase()) {
      // ProxyCreation(address indexed proxy, address singleton)
      if (log.topics[1]) {
        deployedAddress = getAddress(`0x${log.topics[1].slice(-40)}`);
      }
    }
  }

  // Step 4: 검증
  console.log("4. 배포 검증...");

  const safeAddress = deployedAddress ?? predictedAddress;
  console.log(`   Safe 주소: ${safeAddress}`);

  if (deployedAddress && deployedAddress === predictedAddress) {
    console.log(`   CREATE2 예측 일치!`);
  }

  // Owner 확인
  const safeOwners = await publicClient.readContract({
    address: safeAddress,
    abi: SAFE_ABI,
    functionName: "getOwners",
  }) as Address[];
  console.log(`   Owners: [${safeOwners.map(shortenAddress).join(", ")}]`);

  // Threshold 확인
  const safeThreshold = await publicClient.readContract({
    address: safeAddress,
    abi: SAFE_ABI,
    functionName: "getThreshold",
  }) as bigint;
  console.log(`   Threshold: ${safeThreshold}`);

  // Nonce 확인
  const safeNonce = await publicClient.readContract({
    address: safeAddress,
    abi: SAFE_ABI,
    functionName: "nonce",
  }) as bigint;
  console.log(`   Nonce: ${safeNonce}`);

  console.log(`\nSafe 배포 완료!`);
  console.log(`주소: ${safeAddress}`);
  console.log(`\n이 주소를 .env의 SAFE_ADDRESS에 설정하세요.`);
}

main().catch(console.error);
