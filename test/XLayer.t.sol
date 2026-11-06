// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {DeploymentLibrary} from "../script/Deploy.s.sol";

import {UpgradeTest} from "./UpgradeTest.t.sol";
import {Deployments} from "../src/Deployments.sol";

contract XLayerTest is UpgradeTest("xLayer", 74354367) {
  function _getPayload() internal virtual override returns (address) {
    return DeploymentLibrary._deployXLayer();
  }

  function _getDeployedPayload() internal virtual override returns (address) {
    return Deployments.XLAYER;
  }

  /// @dev `forge clone` does not support this chain's explorer, so the reference is the v3.7.0 release.
  function _buildReferenceImplementation(string memory dir, address) internal virtual override returns (string memory) {
    return _buildReleaseReference(dir);
  }
}
