import "dotenv/config";
import { type Address, type Hex } from "viem";

/**
 * 환경 변수에서 설정 로드
 *
 * 사용법:
 *   1. .env.example을 .env로 복사
 *   2. 값 채우기
 *   3. 스크립트 실행: pnpm eip7702:delegate
 */

function requireEnv(key: string): string {
  const value = process.env[key];
  if (!value) {
    throw new Error(`환경 변수 ${key}가 설정되지 않았습니다. .env 파일을 확인해주세요.`);
  }
  return value;
}

function optionalEnv(key: string, defaultValue: string = ""): string {
  return process.env[key] || defaultValue;
}

// RPC
export const RPC_URL = optionalEnv("RPC_URL", "http://localhost:8545");

// 개인키
export const OWNER_PRIVATE_KEY = requireEnv("OWNER_PRIVATE_KEY") as Hex;
export const DELEGATE_PRIVATE_KEY = optionalEnv(
  "DELEGATE_PRIVATE_KEY",
  "0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d"
) as Hex;
export const RELAYER_PRIVATE_KEY = optionalEnv(
  "RELAYER_PRIVATE_KEY",
  "0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a"
) as Hex;

// 배포된 컨트랙트 주소
export const EIP7702_ACCOUNT_IMPL = optionalEnv("EIP7702_ACCOUNT_IMPL") as Address;
export const EIP7702_FACTORY = optionalEnv("EIP7702_FACTORY") as Address;
export const VERIFYING_PAYMASTER = optionalEnv("VERIFYING_PAYMASTER") as Address;

// Safe 주소 (모든 EVM 체인에서 동일)
export const SAFE_SINGLETON = optionalEnv(
  "SAFE_SINGLETON",
  "0xd9Db270c1B5E3Bd161E8c8503c55cEABeE709552"
) as Address;
export const SAFE_PROXY_FACTORY = optionalEnv(
  "SAFE_PROXY_FACTORY",
  "0xa6B71E26C5e0845f74c812102Ca7114b6a896AB2"
) as Address;
export const SAFE_FALLBACK_HANDLER = optionalEnv(
  "SAFE_FALLBACK_HANDLER",
  "0xf48f2B2d2a534e402487b3ee7C18c33Aec0Fe5e4"
) as Address;
