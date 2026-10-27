// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {MockExecute} from "../interfaces/MockExecute.sol";

contract MockFlashReceiver {
  using SafeERC20 for IERC20;

  function executeOperation(
    address[] calldata assets,
    uint256[] calldata amounts,
    uint256[] calldata premiums,
    address initiator, /* initiator */
    bytes calldata /* params */
  ) external returns (bool) {
    for (uint256 i = 0; i < assets.length; i++) {
      IERC20(assets[i]).forceApprove(msg.sender, amounts[i] + premiums[i]);
    }

    MockExecute(initiator).execute();

    return true;
  }
}
