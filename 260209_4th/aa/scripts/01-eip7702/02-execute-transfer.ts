/**
 * 02-execute-transfer.ts
 *
 * EIP-7702 execute()로 ETH 전송
 *
 * 동작:
 * 1. 위임된 EOA의 execute(to, value, data)를 호출하여 ETH 전송
 * 2. 일반 EOA 전송과 달리, 스마트 계정 함수를 통해 실행
 *
 * 사전 조건:
 * - 01-create-delegation.ts 실행 완료 (위임 + 초기화 완료)
 */

import { parseEther, formatEther, type Address } from "viem";
import { getPublicClient, getWalletClient, shortenAddress, chain } from "../common/client.js";
import { OWNER_PRIVATE_KEY } from "../common/config.js";
import { EIP7702_ACCOUNT_ABI } from "../common/abi.js";

async function main() {
  console.log("=== EIP-7702 execute() ETH 전송 ===\n");

  const publicClient = getPublicClient();
  const ownerClient = getWalletClient(OWNER_PRIVATE_KEY);
  const owner = ownerClient.account;

  // 수신자 (Anvil 기본 계정 #9)
  const recipient = "0xa0Ee7A142d267C1f36714E4a8F75612F20a79720" as Address;
  const amount = parseEther("0.01");

  console.log(`체인: ${chain.name}`);
  console.log(`From: ${shortenAddress(owner.address)}`);
  console.log(`To:   ${shortenAddress(recipient)}`);
  console.log(`금액: ${formatEther(amount)} ETH\n`);

  // 잔액 확인 (전)
  const [senderBefore, recipientBefore] = await Promise.all([
    publicClient.getBalance({ address: owner.address }),
    publicClient.getBalance({ address: recipient }),
  ]);
  console.log(`[전] Sender:    ${formatEther(senderBefore)} ETH`);
  console.log(`[전] Recipient: ${formatEther(recipientBefore)} ETH\n`);

  // execute()로 ETH 전송
  console.log("execute() 호출 중...");
  const hash = await ownerClient.writeContract({
    address: owner.address, // 위임된 EOA 자신에게 호출
    abi: EIP7702_ACCOUNT_ABI,
    functionName: "execute",
    args: [recipient, amount, "0x"],
  });
  console.log(`TX: ${hash}\n`);

  // 확인 대기
  const receipt = await publicClient.waitForTransactionReceipt({ hash });
  console.log(`상태: ${receipt.status}`);
  console.log(`Gas Used: ${receipt.gasUsed}\n`);

  // 잔액 확인 (후)
  const [senderAfter, recipientAfter] = await Promise.all([
    publicClient.getBalance({ address: owner.address }),
    publicClient.getBalance({ address: recipient }),
  ]);
  console.log(`[후] Sender:    ${formatEther(senderAfter)} ETH`);
  console.log(`[후] Recipient: ${formatEther(recipientAfter)} ETH`);
  console.log(`\n수신자 잔액 변화: +${formatEther(recipientAfter - recipientBefore)} ETH`);
}

main().catch(console.error);
