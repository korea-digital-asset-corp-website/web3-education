// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Script, console } from "forge-std/Script.sol";
import { PasskeyAccount } from "../src/PasskeyAccount.sol";
import { PasskeyAccountFactory } from "../src/PasskeyAccountFactory.sol";

/**
 * @title Deploy
 * @notice PassKey 지갑 컨트랙트 배포 스크립트
 *
 * 사용법:
 * ```bash
 * # Dry run (배포 안함)
 * forge script script/Deploy.s.sol --rpc-url $RPC_URL
 *
 * # 실제 배포
 * forge script script/Deploy.s.sol --rpc-url $RPC_URL --broadcast --verify
 * ```
 */
contract Deploy is Script {
    function run() external {
        // 배포자 개인키 (환경변수 또는 --private-key 플래그)
        uint256 deployerPrivateKey = vm.envOr("DEPLOYER_PRIVATE_KEY", uint256(0));

        if (deployerPrivateKey != 0) {
            vm.startBroadcast(deployerPrivateKey);
        } else {
            vm.startBroadcast();
        }

        // Factory 배포 (내부적으로 구현체도 배포됨)
        PasskeyAccountFactory factory = new PasskeyAccountFactory();

        console.log("=== Deployment Complete ===");
        console.log("PasskeyAccountFactory:", address(factory));
        console.log("PasskeyAccount (impl):", factory.accountImplementation());

        vm.stopBroadcast();

        // Verification logs
        console.log("");
        console.log("=== Environment Info ===");
        console.log("Chain ID:", block.chainid);
        console.log("Block Number:", block.number);
    }
}
