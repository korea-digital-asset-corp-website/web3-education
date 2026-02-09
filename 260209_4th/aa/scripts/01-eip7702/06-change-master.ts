/**
 * 06-change-master.ts
 *
 * 마스터 권한 이전
 *
 * 동작:
 * 1. setMasterAuthority()로 계정 소유권을 다른 주소로 이전
 * 2. 이전 후 기존 Owner는 더 이상 권한 없음
 * 3. 새 Master가 계정의 모든 자산 관리 가능
 *
 * 사용 시나리오:
 * - A EOA가 개인키 분실 위험 → B EOA로 마스터 이전
 * - B EOA가 A EOA(주소)의 자산을 계속 관리
 *
 * 사전 조건:
 * - 01-create-delegation.ts 실행 완료
 */

import { type Address } from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { getPublicClient, getWalletClient, shortenAddress, chain } from "../common/client.js";
import { OWNER_PRIVATE_KEY, DELEGATE_PRIVATE_KEY } from "../common/config.js";
import { EIP7702_ACCOUNT_ABI } from "../common/abi.js";

async function main() {
  console.log("=== EIP-7702 마스터 권한 이전 ===\n");

  const publicClient = getPublicClient();
  const ownerClient = getWalletClient(OWNER_PRIVATE_KEY);
  const owner = ownerClient.account;

  // 새 마스터 (Delegate 개인키 사용)
  const newMasterAccount = privateKeyToAccount(DELEGATE_PRIVATE_KEY);
  const newMaster = newMasterAccount.address;

  console.log(`체인: ${chain.name}`);
  console.log(`현재 Master: ${shortenAddress(owner.address)}`);
  console.log(`새 Master:   ${shortenAddress(newMaster)}\n`);

  // 현재 마스터 확인
  const currentMaster = await publicClient.readContract({
    address: owner.address,
    abi: EIP7702_ACCOUNT_ABI,
    functionName: "masterAuthority",
  });
  console.log(`[전] masterAuthority: ${currentMaster}`);

  // setMasterAuthority 호출
  console.log("\nsetMasterAuthority() 호출 중...");
  const hash = await ownerClient.writeContract({
    address: owner.address,
    abi: EIP7702_ACCOUNT_ABI,
    functionName: "setMasterAuthority",
    args: [newMaster],
  });
  console.log(`TX: ${hash}\n`);

  const receipt = await publicClient.waitForTransactionReceipt({ hash });
  console.log(`상태: ${receipt.status}`);
  console.log(`Gas Used: ${receipt.gasUsed}\n`);

  // 변경 확인
  const updatedMaster = await publicClient.readContract({
    address: owner.address,
    abi: EIP7702_ACCOUNT_ABI,
    functionName: "masterAuthority",
  });
  console.log(`[후] masterAuthority: ${updatedMaster}`);

  console.log(`\n${shortenAddress(newMaster)}가 이제 ${shortenAddress(owner.address)} 계정의 새 마스터입니다.`);
  console.log(`기존 Owner(${shortenAddress(owner.address)})는 더 이상 권한이 없습니다.`);
}

main().catch(console.error);
