// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {IPool} from "aave-v3-origin/contracts/interfaces/IPool.sol";
import {IPoolAddressesProvider} from "aave-v3-origin/contracts/interfaces/IPoolAddressesProvider.sol";
import {IPoolRevision} from "./interfaces/IPoolRevision.sol";

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

    require(IPool(params.poolImpl).ADDRESSES_PROVIDER() == pool.ADDRESSES_PROVIDER(), WrongAddresses());
    require(IPoolRevision(params.poolImpl).POOL_REVISION() == NEW_POOL_REVISION, WrongPoolRevision());
    require(
      IPool(params.poolImpl).RESERVE_INTEREST_RATE_STRATEGY() == pool.RESERVE_INTEREST_RATE_STRATEGY(),
      WrongInterestRateStrategy()
    );
    POOL_IMPL = params.poolImpl;
  }

  function execute() external virtual {
    require(IPoolRevision(address(POOL)).POOL_REVISION() == PREVIOUS_POOL_REVISION, WrongPoolRevision());
    POOL_ADDRESSES_PROVIDER.setPoolImpl(POOL_IMPL);
    require(IPoolRevision(address(POOL)).POOL_REVISION() == NEW_POOL_REVISION, WrongPoolRevision());
  }
}
