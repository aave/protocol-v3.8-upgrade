// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IPool} from "aave-v3-origin/contracts/interfaces/IPool.sol";

/// @dev Supplies from inside a flashLoanSimple callback, which v3.8 must keep allowing.
contract SupplyingFlashReceiver {
  using SafeERC20 for IERC20;

  function executeOperation(
    address asset,
    uint256 amount,
    uint256 premium,
    address, /* initiator */
    bytes calldata params
  )
    external
    returns (bool)
  {
    uint256 supplyAmount = abi.decode(params, (uint256));
    IERC20(asset).forceApprove(msg.sender, supplyAmount + amount + premium);
    IPool(msg.sender).supply(asset, supplyAmount, address(this), 0);
    return true;
  }
}
