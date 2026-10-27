// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.10;

import {IPool} from "aave-v3-origin/contracts/interfaces/IPool.sol";
import {IPoolAddressesProvider} from "aave-v3-origin/contracts/interfaces/IPoolAddressesProvider.sol";

interface IPoolRevision {
  function POOL_REVISION() external view returns (uint256);
}

/**
 * @title UpgradePayload
 * @notice Upgrade payload to upgrade the Aave v3.7 to v3.8
 * @author BGD Labs
 */
contract UpgradePayload {
  struct ConstructorParams {
    IPoolAddressesProvider poolAddressesProvider;
    address poolImpl;
  }

  error WrongAddresses();
  error WrongPoolRevision();
  error WrongInterestRateStrategy();

  uint256 public constant PREVIOUS_POOL_REVISION = 11;
  uint256 public constant NEW_POOL_REVISION = 12;

  IPoolAddressesProvider public immutable POOL_ADDRESSES_PROVIDER;
  IPool public immutable POOL;

  address public immutable POOL_IMPL;

  constructor(ConstructorParams memory params) {
    POOL_ADDRESSES_PROVIDER = params.poolAddressesProvider;

    IPool pool = IPool(params.poolAddressesProvider.getPool());
    POOL = pool;

    if (IPool(params.poolImpl).ADDRESSES_PROVIDER() != params.poolAddressesProvider) {
      revert WrongAddresses();
    }
    if (IPoolRevision(params.poolImpl).POOL_REVISION() != NEW_POOL_REVISION) {
      revert WrongPoolRevision();
    }
    // all reserves share the pool-level strategy, so a mismatch would silently swap every reserve's rate model
    if (IPool(params.poolImpl).RESERVE_INTEREST_RATE_STRATEGY() != pool.RESERVE_INTEREST_RATE_STRATEGY()) {
      revert WrongInterestRateStrategy();
    }
    POOL_IMPL = params.poolImpl;
  }

  function execute() external virtual {
    if (IPoolRevision(address(POOL)).POOL_REVISION() != PREVIOUS_POOL_REVISION) {
      revert WrongPoolRevision();
    }
    POOL_ADDRESSES_PROVIDER.setPoolImpl(POOL_IMPL);
    if (IPoolRevision(address(POOL)).POOL_REVISION() != NEW_POOL_REVISION) {
      revert WrongPoolRevision();
    }
  }
}
