/**
 * 05-meta-transaction.ts
 *
 * EIP-712 메타 트랜잭션 (가스 대납)
 *
 * 동작:
 * 1. Owner가 EIP-712 타입 데이터에 서명 (오프체인)
 * 2. Relayer가 executeWithSignature()를 호출하여 트랜잭션 실행
 * 3. Relayer가 가스비를 지불, Owner는 가스비 없이 트랜잭션 실행
 *
 * 핵심:
 * - Owner는 ETH가 없어도 트랜잭션 실행 가능 (Relayer가 대납)
 * - Relayer는 Owner의 서명 없이는 실행 불가 (보안)
 * - nonce로 replay 공격 방지
 *
 * 사전 조건:
 * - 01-create-delegation.ts 실행 완료
 */

import { parseEther, formatEther, type Address } from "viem";
import { getPublicClient, getWalletClient, shortenAddress, chain } from "../common/client.js";
import {
  OWNER_PRIVATE_KEY,
  RELAYER_PRIVATE_KEY,
} from "../common/config.js";
import { EIP7702_ACCOUNT_ABI } from "../common/abi.js";

async function main() {
  console.log("=== EIP-7702 메타 트랜잭션 (가스 대납) ===\n");

  const publicClient = getPublicClient();
  const ownerClient = getWalletClient(OWNER_PRIVATE_KEY);
  const relayerClient = getWalletClient(RELAYER_PRIVATE_KEY);
  const owner = ownerClient.account;
  const relayer = relayerClient.account;

  const recipient = "0xa0Ee7A142d267C1f36714E4a8F75612F20a79720" as Address;
  const amount = parseEther("0.005");

  console.log(`체인: ${chain.name}`);
  console.log(`Owner (서명):   ${shortenAddress(owner.address)}`);
  console.log(`Relayer (가스):  ${shortenAddress(relayer.address)}`);
  console.log(`수신자:          ${shortenAddress(recipient)}`);
  console.log(`금액:            ${formatEther(amount)} ETH\n`);

  // Step 1: Owner의 현재 nonce 조회
  const nonce = (await publicClient.readContract({
    address: owner.address,
    abi: EIP7702_ACCOUNT_ABI,
    functionName: "nonces",
    args: [owner.address],
  })) as bigint;
  console.log(`1. Owner nonce: ${nonce}`);

  // Step 2: deadline 설정 (현재 + 10분)
  const deadline = BigInt(Math.floor(Date.now() / 1000) + 600);
  console.log(`2. Deadline: ${new Date(Number(deadline) * 1000).toLocaleString()}`);

  // Step 3: EIP-712 서명
  console.log("\n3. Owner가 EIP-712 서명 중...");

  const domain = {
    name: "EIP7702Account",
    version: "1",
    chainId: chain.id,
    verifyingContract: owner.address as Address,
  };

  const types = {
    Execute: [
      { name: "to", type: "address" },
      { name: "value", type: "uint256" },
      { name: "data", type: "bytes" },
      { name: "nonce", type: "uint256" },
      { name: "deadline", type: "uint256" },
    ],
  };

  const message = {
    to: recipient,
    value: amount,
    data: "0x" as `0x${string}`,
    nonce,
    deadline,
  };

  const signature = await ownerClient.signTypedData({
    domain,
    types,
    primaryType: "Execute",
    message,
  });
  console.log(`   서명: ${signature.slice(0, 20)}...`);

  // Step 4: Relayer가 executeWithSignature() 호출
  console.log("\n4. Relayer가 서명된 트랜잭션 제출 중...");

  const recipientBefore = await publicClient.getBalance({ address: recipient });

  const hash = await relayerClient.writeContract({
    address: owner.address,
    abi: EIP7702_ACCOUNT_ABI,
    functionName: "executeWithSignature",
    args: [owner.address, recipient, amount, "0x", deadline, signature],
  });
  console.log(`   TX: ${hash}`);

  const receipt = await publicClient.waitForTransactionReceipt({ hash });
  console.log(`   상태: ${receipt.status}`);
  console.log(`   Gas Used: ${receipt.gasUsed}\n`);

  // 결과 확인
  const recipientAfter = await publicClient.getBalance({ address: recipient });
  console.log("=== 결과 ===");
  console.log(`수신자 잔액 변화: +${formatEther(recipientAfter - recipientBefore)} ETH`);
  console.log(`\nOwner는 가스비를 지불하지 않고 Relayer가 대신 지불했습니다.`);
}

main().catch(console.error);
