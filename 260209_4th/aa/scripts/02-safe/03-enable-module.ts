/**
 * 03-enable-module.ts
 *
 * Safe 모듈 활성화
 *
 * 동작:
 * 1. enableModule() 호출 데이터를 인코딩
 * 2. Safe가 자기 자신에게 트랜잭션 실행 (self-call)
 * 3. 모듈이 활성화되었는지 검증
 *
 * 핵심:
 * - Safe self-call: to 주소가 Safe 자신 → 자체 함수 호출
 * - enableModule()은 외부에서 직접 호출 불가 (onlySelf modifier)
 * - Safe의 execTransaction()을 통해서만 호출 가능
 * - 모듈: Safe에 추가 기능을 부여하는 확장 컨트랙트
 *
 * 사전 조건:
 * - 01-deploy-safe.ts 실행 완료
 * - SAFE_ADDRESS 환경변수 설정
 */

import { encodeFunctionData, type Address, type Hex } from "viem";
import { getPublicClient, getWalletClient, shortenAddress, chain } from "../common/client.js";
import { OWNER_PRIVATE_KEY } from "../common/config.js";
import { SAFE_ABI } from "../common/abi.js";

const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000" as Address;

// 예시 모듈 주소 (실제 배포된 모듈 주소로 교체)
// ERC-4337 모듈이나 소셜 리커버리 모듈 등
const MODULE_ADDRESS = (process.env.MODULE_ADDRESS ||
  "0x75cf11467937ce3F2f357CE24ffc3DBF8fD5c226") as Address;

async function main() {
  console.log("=== Safe 모듈 활성화 ===\n");

  const publicClient = getPublicClient();
  const ownerClient = getWalletClient(OWNER_PRIVATE_KEY);
  const owner = ownerClient.account;

  const safeAddress = (process.env.SAFE_ADDRESS || "") as Address;
  if (!safeAddress) {
    console.error("SAFE_ADDRESS 환경변수를 설정해주세요.");
    console.error("01-deploy-safe.ts를 먼저 실행하세요.");
    process.exit(1);
  }

  console.log(`체인: ${chain.name}`);
  console.log(`Safe:   ${shortenAddress(safeAddress)}`);
  console.log(`Owner:  ${shortenAddress(owner.address)}`);
  console.log(`Module: ${shortenAddress(MODULE_ADDRESS)}\n`);

  // Step 1: 모듈 현재 상태 확인
  const isEnabledBefore = await publicClient.readContract({
    address: safeAddress,
    abi: SAFE_ABI,
    functionName: "isModuleEnabled",
    args: [MODULE_ADDRESS],
  }) as boolean;
  console.log(`1. 모듈 활성화 상태 (전): ${isEnabledBefore}`);

  if (isEnabledBefore) {
    console.log("\n이미 활성화된 모듈입니다.");
    return;
  }

  // Step 2: enableModule() 호출 데이터 인코딩
  console.log("\n2. enableModule() 데이터 인코딩...");

  const enableModuleData = encodeFunctionData({
    abi: SAFE_ABI,
    functionName: "enableModule",
    args: [MODULE_ADDRESS],
  });
  console.log(`   data: ${enableModuleData.slice(0, 20)}...`);

  // Step 3: Safe 트랜잭션 해시 계산 (self-call)
  console.log("\n3. Safe self-call 트랜잭션 해시 계산...");

  const safeNonce = (await publicClient.readContract({
    address: safeAddress,
    abi: SAFE_ABI,
    functionName: "nonce",
  })) as bigint;

  const operation = 0; // CALL
  const safeTxGas = 0n;
  const baseGas = 0n;
  const gasPrice = 0n;
  const gasToken = ZERO_ADDRESS;
  const refundReceiver = ZERO_ADDRESS;

  const safeTxHash = (await publicClient.readContract({
    address: safeAddress,
    abi: SAFE_ABI,
    functionName: "getTransactionHash",
    args: [
      safeAddress,       // to: Safe 자기 자신! (self-call)
      0n,                // value: 0 ETH
      enableModuleData,  // data: enableModule() 호출
      operation,
      safeTxGas,
      baseGas,
      gasPrice,
      gasToken,
      refundReceiver,
      safeNonce,
    ],
  })) as Hex;
  console.log(`   safeTxHash: ${safeTxHash.slice(0, 20)}...`);
  console.log(`   nonce: ${safeNonce}`);

  // Step 4: 서명 (eth_sign + v+4)
  console.log("\n4. 서명 중...");

  const signature = await ownerClient.signMessage({
    message: { raw: safeTxHash as `0x${string}` },
  });

  const sigBytes = signature.slice(2);
  const r = sigBytes.slice(0, 64);
  const s = sigBytes.slice(64, 128);
  const v = parseInt(sigBytes.slice(128, 130), 16);
  const adjustedV = (v + 4).toString(16).padStart(2, "0");
  const adjustedSignature = `0x${r}${s}${adjustedV}` as Hex;
  console.log(`   v: ${v} → ${v + 4} (v+4)`);

  // Step 5: execTransaction() (self-call)
  console.log("\n5. execTransaction() 호출 (self-call)...");

  const hash = await ownerClient.writeContract({
    address: safeAddress,
    abi: SAFE_ABI,
    functionName: "execTransaction",
    args: [
      safeAddress,       // to: Safe 자기 자신
      0n,                // value: 0
      enableModuleData,  // data: enableModule()
      operation,
      safeTxGas,
      baseGas,
      gasPrice,
      gasToken,
      refundReceiver,
      adjustedSignature,
    ],
  });
  console.log(`   TX: ${hash}`);

  const receipt = await publicClient.waitForTransactionReceipt({ hash });
  console.log(`   상태: ${receipt.status}`);
  console.log(`   Gas Used: ${receipt.gasUsed}\n`);

  // Step 6: 검증
  const isEnabledAfter = await publicClient.readContract({
    address: safeAddress,
    abi: SAFE_ABI,
    functionName: "isModuleEnabled",
    args: [MODULE_ADDRESS],
  }) as boolean;
  console.log(`6. 모듈 활성화 상태 (후): ${isEnabledAfter}`);

  if (isEnabledAfter) {
    console.log(`\n${shortenAddress(MODULE_ADDRESS)} 모듈이 Safe에 활성화되었습니다.`);
    console.log(`이제 이 모듈은 Safe를 대신하여 트랜잭션을 실행할 수 있습니다.`);
  } else {
    console.log(`\n모듈 활성화에 실패했습니다.`);
  }
}

main().catch(console.error);
