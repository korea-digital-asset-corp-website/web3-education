/**
 * 04-batch-execute.ts
 *
 * 배치 트랜잭션 실행
 *
 * 동작:
 * 1. executeBatch()로 여러 트랜잭션을 한 번에 실행
 * 2. 단일 트랜잭션으로 여러 수신자에게 ETH 전송
 *
 * 사전 조건:
 * - 01-create-delegation.ts 실행 완료
 */

import { parseEther, formatEther, type Address } from "viem";
import { getPublicClient, getWalletClient, shortenAddress, chain } from "../common/client.js";
import { OWNER_PRIVATE_KEY } from "../common/config.js";
import { EIP7702_ACCOUNT_ABI } from "../common/abi.js";

async function main() {
  console.log("=== EIP-7702 배치 트랜잭션 ===\n");

  const publicClient = getPublicClient();
  const ownerClient = getWalletClient(OWNER_PRIVATE_KEY);
  const owner = ownerClient.account;

  // 수신자 목록 (Anvil 기본 계정들)
  const recipients: Address[] = [
    "0x70997970C51812dc3A010C7d01b50e0d17dc79C8",
    "0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC",
    "0x90F79bf6EB2c4f870365E785982E1f101E93b906",
  ];

  const amounts = [parseEther("0.001"), parseEther("0.002"), parseEther("0.003")];
  const datas: `0x${string}`[] = ["0x", "0x", "0x"];

  console.log(`체인: ${chain.name}`);
  console.log(`From: ${shortenAddress(owner.address)}\n`);
  console.log("배치 내용:");
  recipients.forEach((r, i) => {
    console.log(`  ${i + 1}. ${shortenAddress(r)} ← ${formatEther(amounts[i])} ETH`);
  });
  console.log();

  // executeBatch 호출
  console.log("executeBatch() 호출 중...");
  const hash = await ownerClient.writeContract({
    address: owner.address,
    abi: EIP7702_ACCOUNT_ABI,
    functionName: "executeBatch",
    args: [recipients, amounts, datas],
  });
  console.log(`TX: ${hash}\n`);

  const receipt = await publicClient.waitForTransactionReceipt({ hash });
  console.log(`상태: ${receipt.status}`);
  console.log(`Gas Used: ${receipt.gasUsed}\n`);

  // 잔액 확인
  console.log("수신자 잔액:");
  for (const r of recipients) {
    const bal = await publicClient.getBalance({ address: r });
    console.log(`  ${shortenAddress(r)}: ${formatEther(bal)} ETH`);
  }

  console.log(`\n3개 전송을 단일 트랜잭션으로 실행 완료!`);
}

main().catch(console.error);
