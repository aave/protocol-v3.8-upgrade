// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {DeploymentLibrary} from "../script/Deploy.s.sol";

import {Deployments} from "../src/Deployments.sol";

import {UpgradeTest} from "./UpgradeTest.t.sol";

contract MainnetCoreTest is UpgradeTest("mainnet", 26284642) {
  function _getPayload() internal virtual override returns (address) {
    return DeploymentLibrary._deployMainnetCore();
  }

  function _getDeployedPayload() internal virtual override returns (address) {
    return Deployments.MAINNET_CORE;
  }
}
