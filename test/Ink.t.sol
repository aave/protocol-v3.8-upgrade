// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {AaveV3InkWhitelabel, AaveV3InkWhitelabelAssets} from "aave-address-book/AaveV3InkWhitelabel.sol";
import {GovV3Helpers} from "aave-helpers/src/GovV3Helpers.sol";
import {IPermissionedPayloadsController} from "aave-helpers/src/dependencies/IPermissionedPayloadsController.sol";
import {GovernanceV3InkWhitelabel} from "aave-address-book/GovernanceV3InkWhitelabel.sol";
import {IPayloadsControllerCore} from "aave-address-book/GovernanceV3.sol";
import {DeploymentLibrary} from "../script/Deploy.s.sol";

import {UpgradeTest, UpgradePayload} from "./UpgradeTest.t.sol";
import {IPoolRevision} from "../src/interfaces/IPoolRevision.sol";
import {Deployments} from "../src/Deployments.sol";

contract InkTest is UpgradeTest("ink", 59624995) {
  // createPayload calldata handed to the Ink whitelabel Safe (aave-dao/aave-proposals-v3#1233)
  bytes internal constant PERMISSIONED_CREATE_PAYLOAD_CALLDATA =
    hex"e8733894000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000020000000000000000000000000fae0b8995367351a2c09192a82c85095f10945d200000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000c00000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000000965786563757465282900000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000";

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

  function test_permissionedCalldataUpgradesPool() external {
    IPayloadsControllerCore controller = GovernanceV3InkWhitelabel.PERMISSIONED_PAYLOADS_CONTROLLER;
    IPayloadsControllerCore.ExecutionAction[] memory actions = new IPayloadsControllerCore.ExecutionAction[](1);
    actions[0] = GovV3Helpers.buildAction(Deployments.INK);
    assertEq(PERMISSIONED_CREATE_PAYLOAD_CALLDATA, abi.encodeCall(IPayloadsControllerCore.createPayload, (actions)));

    vm.prank(IPermissionedPayloadsController(address(controller)).payloadsManager());
    (bool success, bytes memory returnData) = address(controller).call(PERMISSIONED_CREATE_PAYLOAD_CALLDATA);
    assertTrue(success);
    uint40 payloadId = abi.decode(returnData, (uint40));

    IPayloadsControllerCore.Payload memory payload = controller.getPayloadById(payloadId);
    vm.warp(payload.queuedAt + payload.delay + 1);
    controller.executePayload(payloadId);

    UpgradePayload upgradePayload = UpgradePayload(Deployments.INK);
    assertEq(IPoolRevision(address(upgradePayload.POOL())).POOL_REVISION(), upgradePayload.NEW_POOL_REVISION());
    assertEq(_getImplementation(address(upgradePayload.POOL())), upgradePayload.POOL_IMPL());
  }
}
