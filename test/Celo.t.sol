// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {AaveV3CeloAssets} from "aave-address-book/AaveV3Celo.sol";

import {DeploymentLibrary} from "../script/Deploy.s.sol";

import {UpgradeTest} from "./UpgradeTest.t.sol";
import {Deployments} from "../src/Deployments.sol";

contract CeloTest is UpgradeTest("celo", 81210567) {
  function _getPayload() internal virtual override returns (address) {
    return DeploymentLibrary._deployCelo();
  }

  function _getDeployedPayload() internal virtual override returns (address) {
    return Deployments.CELO;
  }

  // CELO moves native balance through a Celo precompile that forge only runs with `--celo`
  function _isExcludedFromFlashLoan(address asset) internal pure override returns (bool) {
    return asset == AaveV3CeloAssets.CELO_UNDERLYING;
  }
}
