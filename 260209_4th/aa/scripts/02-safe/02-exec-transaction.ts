/**
 * 02-exec-transaction.ts
 *
 * Safe 트랜잭션 실행 (eth_sign + v+4)
 *
 * 동작:
 * 1. Safe의 getTransactionHash()로 서명할 해시 계산
 * 2. Owner가 eth_sign 방식으로 해시에 서명
 * 3. Safe 컨벤션: v 값에 +4 조정 (eth_sign 구분)
 * 4. execTransaction()으로 트랜잭션 실행
 *
 * 핵심:
 * - Safe는 자체 nonce 관리 (EOA nonce와 별도)
 * - eth_sign: 원본 해시에 직접 서명 (EIP-191 prefix 없음)
 * - v+4: Safe가 eth_sign vs EIP-191 서명을 구분하는 컨벤션
 * - 서명 순서: Owner 주소 오름차순 (다중서명 시)
 *
 * 사전 조건:
 * - 01-deploy-safe.ts 실행 완료
 * - SAFE_ADDRESS 환경변수 설정
 */

import { parseEther, formatEther, type Address, type Hex } from "viem";
import { getPublicClient, getWalletClient, shortenAddress, chain } from "../common/client.js";
import { OWNER_PRIVATE_KEY } from "../common/config.js";
import { SAFE_ABI } from "../common/abi.js";

const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000" as Address;

async function main() {
  console.log("=== Safe 트랜잭션 실행 ===\n");

  const publicClient = getPublicClient();
  const ownerClient = getWalletClient(OWNER_PRIVATE_KEY);
  const owner = ownerClient.account;

  // Safe 주소 (.env 또는 하드코딩)
  const safeAddress = (process.env.SAFE_ADDRESS || "") as Address;
  if (!safeAddress) {
    console.error("SAFE_ADDRESS 환경변수를 설정해주세요.");
    console.error("01-deploy-safe.ts를 먼저 실행하세요.");
    process.exit(1);
  }

  // 수신자 (Anvil 기본 계정 #9)
  const recipient = "0xa0Ee7A142d267C1f36714E4a8F75612F20a79720" as Address;
  const amount = parseEther("0.01");

  console.log(`체인: ${chain.name}`);
  console.log(`Safe:   ${shortenAddress(safeAddress)}`);
  console.log(`Owner:  ${shortenAddress(owner.address)}`);
  console.log(`수신자: ${shortenAddress(recipient)}`);
  console.log(`금액:   ${formatEther(amount)} ETH\n`);

  // Safe에 ETH 잔액 확인
  const safeBalance = await publicClient.getBalance({ address: safeAddress });
  console.log(`Safe 잔액: ${formatEther(safeBalance)} ETH`);

  if (safeBalance < amount) {
    console.log(`\n잔액 부족! Safe에 ETH를 보내는 중...`);
    const fundHash = await ownerClient.sendTransaction({
      to: safeAddress,
      value: parseEther("0.1"),
    });
    await publicClient.waitForTransactionReceipt({ hash: fundHash });
    console.log(`   Safe에 0.1 ETH 전송 완료\n`);
  }

  // Step 1: Safe nonce 조회
  const safeNonce = (await publicClient.readContract({
    address: safeAddress,
    abi: SAFE_ABI,
    functionName: "nonce",
  })) as bigint;
  console.log(`1. Safe nonce: ${safeNonce}`);

  // Step 2: Safe 트랜잭션 해시 계산
  console.log("2. getTransactionHash() 계산 중...");

  const operation = 0;           // CALL (0) vs DELEGATECALL (1)
  const safeTxGas = 0n;          // 내부 실행 가스 (0 = 자동)
  const baseGas = 0n;            // 오버헤드 가스
  const gasPrice = 0n;           // 가스 가격 (0 = 네트워크 기본)
  const gasToken = ZERO_ADDRESS; // ETH로 가스 지불
  const refundReceiver = ZERO_ADDRESS;

  const safeTxHash = (await publicClient.readContract({
    address: safeAddress,
    abi: SAFE_ABI,
    functionName: "getTransactionHash",
    args: [
      recipient,
      amount,
      "0x" as Hex,  // data (단순 ETH 전송)
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

  // Step 3: eth_sign 방식으로 서명 + v+4 조정
  console.log("\n3. eth_sign 서명 + v+4 조정...");

  // signMessage({ message: { raw } })는 eth_sign과 동일
  // 원본 해시에 직접 서명 (EIP-191 prefix 추가됨)
  const signature = await ownerClient.signMessage({
    message: { raw: safeTxHash as `0x${string}` },
  });

  // r, s, v 분리
  const sigBytes = signature.slice(2);
  const r = sigBytes.slice(0, 64);
  const s = sigBytes.slice(64, 128);
  const v = parseInt(sigBytes.slice(128, 130), 16);

  // Safe 컨벤션: v += 4 (eth_sign 사용 표시)
  const adjustedV = (v + 4).toString(16).padStart(2, "0");
  const adjustedSignature = `0x${r}${s}${adjustedV}` as Hex;

  console.log(`   원본 v: ${v}`);
  console.log(`   조정 v: ${v + 4} (v+4)`);
  console.log(`   서명: ${adjustedSignature.slice(0, 20)}...`);

  // Step 4: execTransaction() 실행
  console.log("\n4. execTransaction() 호출 중...");

  const recipientBefore = await publicClient.getBalance({ address: recipient });

  const hash = await ownerClient.writeContract({
    address: safeAddress,
    abi: SAFE_ABI,
    functionName: "execTransaction",
    args: [
      recipient,
      amount,
      "0x" as Hex,
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

  // 결과 확인
  const recipientAfter = await publicClient.getBalance({ address: recipient });
  console.log("=== 결과 ===");
  console.log(`수신자 잔액 변화: +${formatEther(recipientAfter - recipientBefore)} ETH`);

  const newNonce = (await publicClient.readContract({
    address: safeAddress,
    abi: SAFE_ABI,
    functionName: "nonce",
  })) as bigint;
  console.log(`Safe nonce: ${safeNonce} → ${newNonce}`);
}

main().catch(console.error);
