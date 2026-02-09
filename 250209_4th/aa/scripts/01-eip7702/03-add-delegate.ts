/**
 * 03-add-delegate.ts
 *
 * Delegate 추가
 *
 * 동작:
 * 1. Owner가 addDelegate()로 다른 EOA를 delegate로 등록
 * 2. Delegate는 Owner 대신 execute() 호출 가능
 *
 * 사전 조건:
 * - 01-create-delegation.ts 실행 완료
 */

import { type Address } from "viem";
import { getPublicClient, getWalletClient, shortenAddress, chain } from "../common/client.js";
import { OWNER_PRIVATE_KEY, DELEGATE_PRIVATE_KEY } from "../common/config.js";
import { EIP7702_ACCOUNT_ABI } from "../common/abi.js";
import { privateKeyToAccount } from "viem/accounts";

async function main() {
  console.log("=== EIP-7702 Delegate 추가 ===\n");

  const publicClient = getPublicClient();
  const ownerClient = getWalletClient(OWNER_PRIVATE_KEY);
  const owner = ownerClient.account;

  // Delegate 주소
  const delegateAccount = privateKeyToAccount(DELEGATE_PRIVATE_KEY);
  const delegateAddress = delegateAccount.address;

  console.log(`체인: ${chain.name}`);
  console.log(`Owner:    ${shortenAddress(owner.address)}`);
  console.log(`Delegate: ${shortenAddress(delegateAddress)}\n`);

  // addDelegate 호출
  console.log("addDelegate() 호출 중...");
  const hash = await ownerClient.writeContract({
    address: owner.address,
    abi: EIP7702_ACCOUNT_ABI,
    functionName: "addDelegate",
    args: [delegateAddress],
  });
  console.log(`TX: ${hash}\n`);

  const receipt = await publicClient.waitForTransactionReceipt({ hash });
  console.log(`상태: ${receipt.status}`);
  console.log(`Gas Used: ${receipt.gasUsed}\n`);

  // 확인
  const isAuthorized = await publicClient.readContract({
    address: owner.address,
    abi: EIP7702_ACCOUNT_ABI,
    functionName: "isAuthorized",
    args: [delegateAddress],
  });
  console.log(`Delegate 권한 확인: ${isAuthorized}`);

  if (isAuthorized) {
    console.log(`\n${shortenAddress(delegateAddress)}가 이제 ${shortenAddress(owner.address)}의 트랜잭션을 실행할 수 있습니다.`);
  }
}

main().catch(console.error);
