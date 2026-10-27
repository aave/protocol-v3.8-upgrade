// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {AaveV3OptimismAssets} from "aave-address-book/AaveV3Optimism.sol";

import {DeploymentLibrary} from "../script/Deploy.s.sol";

import {UpgradeTest} from "./UpgradeTest.t.sol";
import {Deployments} from "../src/Deployments.sol";

contract OptimismTest is UpgradeTest("optimism", 158756269) {
  function _getPayload() internal virtual override returns (address) {
    return DeploymentLibrary._deployOptimism();
  }

  function _getDeployedPayload() internal virtual override returns (address) {
    return Deployments.OPTIMISM;
  }

  // sUSD transfers revert with "sUSD retired"
  function _isExcludedFromFlashLoan(address asset) internal view override returns (bool) {
    return asset == AaveV3OptimismAssets.sUSD_UNDERLYING;
  }
}
