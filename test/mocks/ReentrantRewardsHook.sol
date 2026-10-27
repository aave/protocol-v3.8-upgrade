// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IPool} from "aave-v3-origin/contracts/interfaces/IPool.sol";

/// @dev Etched over a rewards controller: re-enters the Pool from the aToken mint hook of a guarded action.
contract ReentrantRewardsHook {
  IPool public immutable POOL;

  constructor(IPool pool) {
    POOL = pool;
  }

  function handleAction(address, uint256, uint256) external {
    POOL.setUserEMode(0);
  }
}
