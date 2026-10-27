// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {DeploymentLibrary} from "../script/Deploy.s.sol";

import {UpgradeTest} from "./UpgradeTest.t.sol";
import {Deployments} from "../src/Deployments.sol";

contract MantleTest is UpgradeTest("mantle", 102490496) {
  function _getPayload() internal virtual override returns (address) {
    return DeploymentLibrary._deployMantle();
  }

  function _getDeployedPayload() internal virtual override returns (address) {
    return Deployments.MANTLE;
  }
}
