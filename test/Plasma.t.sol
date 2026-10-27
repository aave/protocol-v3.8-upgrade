// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {DeploymentLibrary} from "../script/Deploy.s.sol";

import {UpgradeTest} from "./UpgradeTest.t.sol";
import {Deployments} from "../src/Deployments.sol";

contract PlasmaTest is UpgradeTest("plasma", 36169888) {
  function _getPayload() internal virtual override returns (address) {
    return DeploymentLibrary._deployPlasma();
  }

  function _getDeployedPayload() internal virtual override returns (address) {
    return Deployments.PLASMA;
  }
}
