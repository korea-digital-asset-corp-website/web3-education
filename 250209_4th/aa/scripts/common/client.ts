import {
  createPublicClient,
  createWalletClient,
  http,
  type PublicClient,
  type WalletClient,
  type Chain,
  type Transport,
  type Account,
} from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { foundry, baseSepolia, sepolia } from "viem/chains";
import { RPC_URL } from "./config.js";

/**
 * RPC URL에서 체인 감지
 */
function detectChain(): Chain {
  if (RPC_URL.includes("localhost") || RPC_URL.includes("127.0.0.1")) {
    return foundry;
  }
  if (RPC_URL.includes("base") && RPC_URL.includes("sepolia")) {
    return baseSepolia;
  }
  if (RPC_URL.includes("sepolia")) {
    return sepolia;
  }
  // 기본값: Anvil (로컬)
  return foundry;
}

export const chain = detectChain();

/**
 * PublicClient 생성 (읽기 전용)
 */
export function getPublicClient(): PublicClient {
  return createPublicClient({
    chain,
    transport: http(RPC_URL),
  });
}

/**
 * WalletClient 생성 (개인키 기반)
 */
export function getWalletClient(
  privateKey: `0x${string}`
): WalletClient<Transport, Chain, Account> {
  const account = privateKeyToAccount(privateKey);
  return createWalletClient({
    account,
    chain,
    transport: http(RPC_URL),
  });
}

/**
 * 주소 줄여서 표시
 */
export function shortenAddress(address: string): string {
  return `${address.slice(0, 6)}...${address.slice(-4)}`;
}
