/**
 * 01-create-delegation.ts
 *
 * EIP-7702 위임 생성 + 초기화
 *
 * 동작:
 * 1. signAuthorization()으로 EOA가 EIP7702Account 컨트랙트에 코드 위임 서명
 * 2. sendTransaction(authorizationList)으로 위임 + initialize() 한 번에 실행
 * 3. 위임 후 EOA가 스마트 계정처럼 동작 (execute, batch, delegate 등)
 *
 * 사전 조건:
 * - Anvil 실행: anvil
 * - 컨트랙트 배포: forge script script/DeployEIP7702.s.sol --rpc-url http://localhost:8545 --broadcast
 * - .env에 EIP7702_ACCOUNT_IMPL 주소 설정
 */

import { encodeFunctionData, formatEther, type Address } from "viem";
import { getPublicClient, getWalletClient, shortenAddress, chain } from "../common/client.js";
import { OWNER_PRIVATE_KEY, EIP7702_ACCOUNT_IMPL } from "../common/config.js";
import { EIP7702_ACCOUNT_ABI } from "../common/abi.js";

async function main() {
  console.log("=== EIP-7702 위임 생성 ===\n");

  if (!EIP7702_ACCOUNT_IMPL) {
    throw new Error("EIP7702_ACCOUNT_IMPL이 설정되지 않았습니다. .env 파일을 확인해주세요.");
  }

  const publicClient = getPublicClient();
  const ownerClient = getWalletClient(OWNER_PRIVATE_KEY);
  const owner = ownerClient.account;

  console.log(`체인: ${chain.name} (ID: ${chain.id})`);
  console.log(`Owner: ${owner.address}`);
  console.log(`구현체: ${EIP7702_ACCOUNT_IMPL}`);

  // 잔액 확인
  const balance = await publicClient.getBalance({ address: owner.address });
  console.log(`잔액: ${formatEther(balance)} ETH\n`);

  // Step 1: 위임 서명 생성
  console.log("1. 위임 서명 생성 중...");
  const authorization = await ownerClient.signAuthorization({
    contractAddress: EIP7702_ACCOUNT_IMPL,
  });
  console.log("   서명 완료\n");

  // Step 2: 위임 + 초기화를 단일 type 4 트랜잭션으로 전송
  console.log("2. 위임 + 초기화 트랜잭션 전송 중...");
  const hash = await ownerClient.sendTransaction({
    authorizationList: [authorization],
    to: owner.address, // 자기 자신에게 (위임된 코드의 initialize 호출)
    data: encodeFunctionData({
      abi: EIP7702_ACCOUNT_ABI,
      functionName: "initialize",
    }),
  });
  console.log(`   TX: ${hash}\n`);

  // Step 3: 트랜잭션 완료 대기
  console.log("3. 트랜잭션 확인 대기 중...");
  const receipt = await publicClient.waitForTransactionReceipt({ hash });
  console.log(`   상태: ${receipt.status}`);
  console.log(`   Gas Used: ${receipt.gasUsed}\n`);

  // Step 4: 위임 상태 확인
  console.log("4. 위임 상태 확인...");
  try {
    const [master, initialized] = await Promise.all([
      publicClient.readContract({
        address: owner.address,
        abi: EIP7702_ACCOUNT_ABI,
        functionName: "masterAuthority",
      }),
      publicClient.readContract({
        address: owner.address,
        abi: EIP7702_ACCOUNT_ABI,
        functionName: "initialized",
      }),
    ]);
    console.log(`   Master: ${master}`);
    console.log(`   초기화: ${initialized}`);
  } catch {
    console.log("   RPC에서 위임 상태를 조회할 수 없습니다 (일부 체인에서 정상)");
  }

  console.log("\n=== 완료 ===");
  console.log(`${shortenAddress(owner.address)} EOA가 이제 스마트 계정으로 동작합니다.`);
}

main().catch(console.error);
