// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {AaveV3InkWhitelabel, AaveV3InkWhitelabelAssets} from "aave-address-book/AaveV3InkWhitelabel.sol";
import {GovV3Helpers} from "aave-helpers/src/GovV3Helpers.sol";
import {DeploymentLibrary} from "../script/Deploy.s.sol";

import {UpgradeTest} from "./UpgradeTest.t.sol";
import {Deployments} from "../src/Deployments.sol";

contract InkTest is UpgradeTest("ink", 59612896) {
  function executePayload(Vm vm, address payload) internal virtual override {
    GovV3Helpers.executePayload(
      vm, payload, address(GovV3Helpers.getPayloadsController(AaveV3InkWhitelabel.POOL, block.chainid))
    );
  }

  function _getPayload() internal virtual override returns (address) {
    return DeploymentLibrary._deployInk();
  }

  function _getDeployedPayload() internal virtual override returns (address) {
    return Deployments.INK;
  }
}
