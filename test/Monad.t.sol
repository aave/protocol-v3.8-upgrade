// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {DeploymentLibrary} from "../script/Deploy.s.sol";

import {UpgradeTest} from "./UpgradeTest.t.sol";
import {Deployments} from "../src/Deployments.sol";

/// forge-config: default.networks.network = "monad"
contract MonadTest is UpgradeTest("monad", 117065308) {
  function _getPayload() internal virtual override returns (address) {
    return DeploymentLibrary._deployMonad();
  }

  function _getDeployedPayload() internal virtual override returns (address) {
    return Deployments.MONAD;
  }
}
