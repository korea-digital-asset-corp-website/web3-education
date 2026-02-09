/**
 * 컨트랙트 ABI 정의
 *
 * Solidity 소스: apps/aa/src/*.sol
 * 주요 함수 시그니처만 추출하여 정의합니다.
 */

// =============================================================================
// EIP7702Account ABI
// =============================================================================

export const EIP7702_ACCOUNT_ABI = [
  // 초기화
  {
    name: "initialize",
    type: "function",
    inputs: [],
    outputs: [],
    stateMutability: "nonpayable",
  },
  {
    name: "initializeWithMaster",
    type: "function",
    inputs: [{ name: "master", type: "address" }],
    outputs: [],
    stateMutability: "nonpayable",
  },
  // 실행
  {
    name: "execute",
    type: "function",
    inputs: [
      { name: "target", type: "address" },
      { name: "value", type: "uint256" },
      { name: "data", type: "bytes" },
    ],
    outputs: [{ name: "result", type: "bytes" }],
    stateMutability: "nonpayable",
  },
  {
    name: "executeBatch",
    type: "function",
    inputs: [
      { name: "targets", type: "address[]" },
      { name: "values", type: "uint256[]" },
      { name: "datas", type: "bytes[]" },
    ],
    outputs: [{ name: "results", type: "bytes[]" }],
    stateMutability: "nonpayable",
  },
  // 메타 트랜잭션
  {
    name: "executeWithSignature",
    type: "function",
    inputs: [
      { name: "signer", type: "address" },
      { name: "target", type: "address" },
      { name: "value", type: "uint256" },
      { name: "data", type: "bytes" },
      { name: "deadline", type: "uint256" },
      { name: "signature", type: "bytes" },
    ],
    outputs: [{ name: "result", type: "bytes" }],
    stateMutability: "nonpayable",
  },
  // 권한 관리
  {
    name: "setMasterAuthority",
    type: "function",
    inputs: [{ name: "newMaster", type: "address" }],
    outputs: [],
    stateMutability: "nonpayable",
  },
  {
    name: "addDelegate",
    type: "function",
    inputs: [{ name: "delegate", type: "address" }],
    outputs: [],
    stateMutability: "nonpayable",
  },
  {
    name: "removeDelegate",
    type: "function",
    inputs: [{ name: "delegate", type: "address" }],
    outputs: [],
    stateMutability: "nonpayable",
  },
  // 조회
  {
    name: "masterAuthority",
    type: "function",
    inputs: [],
    outputs: [{ name: "", type: "address" }],
    stateMutability: "view",
  },
  {
    name: "delegates",
    type: "function",
    inputs: [{ name: "", type: "address" }],
    outputs: [{ name: "", type: "bool" }],
    stateMutability: "view",
  },
  {
    name: "isAuthorized",
    type: "function",
    inputs: [{ name: "account", type: "address" }],
    outputs: [{ name: "", type: "bool" }],
    stateMutability: "view",
  },
  {
    name: "initialized",
    type: "function",
    inputs: [],
    outputs: [{ name: "", type: "bool" }],
    stateMutability: "view",
  },
  {
    name: "nonces",
    type: "function",
    inputs: [{ name: "", type: "address" }],
    outputs: [{ name: "", type: "uint256" }],
    stateMutability: "view",
  },
  {
    name: "getAccountInfo",
    type: "function",
    inputs: [],
    outputs: [
      { name: "master", type: "address" },
      { name: "isInit", type: "bool" },
    ],
    stateMutability: "view",
  },
  // 이벤트
  {
    name: "AccountInitialized",
    type: "event",
    inputs: [{ name: "master", type: "address", indexed: true }],
  },
  {
    name: "Executed",
    type: "event",
    inputs: [
      { name: "target", type: "address", indexed: true },
      { name: "value", type: "uint256", indexed: false },
      { name: "data", type: "bytes", indexed: false },
      { name: "success", type: "bool", indexed: false },
    ],
  },
  {
    name: "DelegateAdded",
    type: "event",
    inputs: [{ name: "delegate", type: "address", indexed: true }],
  },
  {
    name: "MasterAuthorityChanged",
    type: "event",
    inputs: [
      { name: "previousMaster", type: "address", indexed: true },
      { name: "newMaster", type: "address", indexed: true },
    ],
  },
] as const;

// =============================================================================
// Safe (Gnosis Safe) ABI
// =============================================================================

export const SAFE_PROXY_FACTORY_ABI = [
  {
    name: "createProxyWithNonce",
    type: "function",
    inputs: [
      { name: "_singleton", type: "address" },
      { name: "initializer", type: "bytes" },
      { name: "saltNonce", type: "uint256" },
    ],
    outputs: [{ name: "proxy", type: "address" }],
    stateMutability: "nonpayable",
  },
  {
    name: "proxyCreationCode",
    type: "function",
    inputs: [],
    outputs: [{ name: "", type: "bytes" }],
    stateMutability: "pure",
  },
  {
    name: "ProxyCreation",
    type: "event",
    inputs: [
      { name: "proxy", type: "address", indexed: true },
      { name: "singleton", type: "address", indexed: false },
    ],
  },
] as const;

export const SAFE_ABI = [
  // Setup
  {
    name: "setup",
    type: "function",
    inputs: [
      { name: "_owners", type: "address[]" },
      { name: "_threshold", type: "uint256" },
      { name: "to", type: "address" },
      { name: "data", type: "bytes" },
      { name: "fallbackHandler", type: "address" },
      { name: "paymentToken", type: "address" },
      { name: "payment", type: "uint256" },
      { name: "paymentReceiver", type: "address" },
    ],
    outputs: [],
    stateMutability: "nonpayable",
  },
  // Execute
  {
    name: "execTransaction",
    type: "function",
    inputs: [
      { name: "to", type: "address" },
      { name: "value", type: "uint256" },
      { name: "data", type: "bytes" },
      { name: "operation", type: "uint8" },
      { name: "safeTxGas", type: "uint256" },
      { name: "baseGas", type: "uint256" },
      { name: "gasPrice", type: "uint256" },
      { name: "gasToken", type: "address" },
      { name: "refundReceiver", type: "address" },
      { name: "signatures", type: "bytes" },
    ],
    outputs: [{ name: "success", type: "bool" }],
    stateMutability: "payable",
  },
  // 조회
  {
    name: "getOwners",
    type: "function",
    inputs: [],
    outputs: [{ name: "", type: "address[]" }],
    stateMutability: "view",
  },
  {
    name: "getThreshold",
    type: "function",
    inputs: [],
    outputs: [{ name: "", type: "uint256" }],
    stateMutability: "view",
  },
  {
    name: "nonce",
    type: "function",
    inputs: [],
    outputs: [{ name: "", type: "uint256" }],
    stateMutability: "view",
  },
  {
    name: "getTransactionHash",
    type: "function",
    inputs: [
      { name: "to", type: "address" },
      { name: "value", type: "uint256" },
      { name: "data", type: "bytes" },
      { name: "operation", type: "uint8" },
      { name: "safeTxGas", type: "uint256" },
      { name: "baseGas", type: "uint256" },
      { name: "gasPrice", type: "uint256" },
      { name: "gasToken", type: "address" },
      { name: "refundReceiver", type: "address" },
      { name: "_nonce", type: "uint256" },
    ],
    outputs: [{ name: "", type: "bytes32" }],
    stateMutability: "view",
  },
  // 모듈 관리
  {
    name: "enableModule",
    type: "function",
    inputs: [{ name: "module", type: "address" }],
    outputs: [],
    stateMutability: "nonpayable",
  },
  {
    name: "isModuleEnabled",
    type: "function",
    inputs: [{ name: "module", type: "address" }],
    outputs: [{ name: "", type: "bool" }],
    stateMutability: "view",
  },
  {
    name: "isOwner",
    type: "function",
    inputs: [{ name: "owner", type: "address" }],
    outputs: [{ name: "", type: "bool" }],
    stateMutability: "view",
  },
] as const;
