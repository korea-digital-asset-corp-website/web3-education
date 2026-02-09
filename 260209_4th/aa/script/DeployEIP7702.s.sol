// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Script, console } from "forge-std/Script.sol";
import { EIP7702AccountFactory } from "../src/EIP7702AccountFactory.sol";
import { VerifyingPaymaster } from "../src/VerifyingPaymaster.sol";
import { IEntryPoint } from "@account-abstraction/interfaces/IEntryPoint.sol";

/**
 * @title DeployEIP7702
 * @notice EIP-7702 데모용 컨트랙트 배포 스크립트
 *
 * 사용법:
 * ```bash
 * # 환경변수 설정
 * export DEPLOYER_PRIVATE_KEY=0x...  # 배포자 개인키
 * export BASE_SEPOLIA_RPC=https://sepolia.base.org
 *
 * # Dry run (배포 안함, 시뮬레이션만)
 * forge script script/DeployEIP7702.s.sol --rpc-url $BASE_SEPOLIA_RPC -vvvv
 *
 * # 실제 배포 (Base Sepolia)
 * forge script script/DeployEIP7702.s.sol \
 *   --rpc-url $BASE_SEPOLIA_RPC \
 *   --broadcast \
 *   --verify \
 *   --etherscan-api-key $BASESCAN_API_KEY
 *
 * # Anvil 로컬 배포 (테스트용)
 * forge script script/DeployEIP7702.s.sol \
 *   --rpc-url http://localhost:8545 \
 *   --broadcast
 * ```
 *
 * 배포 후:
 * 1. 출력된 주소를 apps/smart-account/src/lib/constants.ts에 업데이트
 * 2. VerifyingPaymaster에 ETH deposit 필요 (가스비 대납용)
 */
contract DeployEIP7702 is Script {
    // EntryPoint v0.7 (모든 체인 동일)
    address constant ENTRY_POINT = 0x0000000071727De22E5E9d8BAf0edAc6f37da032;

    function run() external {
        // 배포자 개인키
        uint256 deployerPrivateKey = vm.envOr("DEPLOYER_PRIVATE_KEY", uint256(0));

        address deployer;
        if (deployerPrivateKey != 0) {
            deployer = vm.addr(deployerPrivateKey);
            vm.startBroadcast(deployerPrivateKey);
        } else {
            // Anvil 기본 계정 사용
            vm.startBroadcast();
            deployer = msg.sender;
        }

        console.log("=== EIP-7702 Demo Deployment ===");
        console.log("Deployer:", deployer);
        console.log("Chain ID:", block.chainid);
        console.log("");

        // 1. EIP7702AccountFactory 배포 (내부적으로 구현체도 배포)
        // address(0)을 넘기면 새 EIP7702Account도 배포됨
        EIP7702AccountFactory factory = new EIP7702AccountFactory(address(0));
        address accountImpl = factory.implementation();

        console.log("EIP7702AccountFactory:", address(factory));
        console.log("EIP7702Account (impl):", accountImpl);

        // 2. VerifyingPaymaster 배포
        // verifier = deployer, owner = deployer (demo)
        VerifyingPaymaster paymaster = new VerifyingPaymaster(
            IEntryPoint(ENTRY_POINT),
            deployer,  // verifier
            deployer   // owner
        );
        console.log("VerifyingPaymaster:", address(paymaster));

        vm.stopBroadcast();

        // Summary output
        console.log("");
        console.log("=== Copy to constants.ts ===");
        console.log("");

        // Chain ID specific P-256 precompile address
        string memory p256Addr;
        if (block.chainid == 84532 || block.chainid == 421614 || block.chainid == 31337) {
            p256Addr = "0x0000000000000000000000000000000000000100";
        } else {
            p256Addr = "0x0000000000000000000000000000000000000000";
        }

        console.log("// Chain ID:", block.chainid);
        console.log("%s: {", block.chainid);
        console.log('  eip7702Account: "%s" as Address,', accountImpl);
        console.log('  verifyingPaymaster: "%s" as Address,', address(paymaster));
        console.log('  entryPoint: "0x0000000071727De22E5E9d8BAf0edAc6f37da032" as Address,');
        console.log('  p256Precompile: "%s" as Address,', p256Addr);
        console.log("},");

        console.log("");
        console.log("=== Next Steps ===");
        console.log("1. Copy above to apps/smart-account/src/lib/constants.ts");
        console.log("");
        console.log("2. Deposit ETH to Paymaster (for gas sponsorship):");
        console.log("   cast send %s \"deposit()\" --value 0.1ether --rpc-url $RPC_URL --private-key $DEPLOYER_PRIVATE_KEY", address(paymaster));
        console.log("");
        console.log("3. Whitelist test accounts:");
        console.log("   cast send %s \"addToWhitelist(address)\" <USER_ADDRESS> --rpc-url $RPC_URL --private-key $DEPLOYER_PRIVATE_KEY", address(paymaster));
    }
}
