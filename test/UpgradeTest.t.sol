// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import {
  ProtocolV3TestBase,
  IPool,
  IPoolAddressesProvider,
  IERC20,
  DataTypes,
  SafeERC20,
  ReserveConfiguration
} from "aave-helpers/src/ProtocolV3TestBase.sol";
import {PercentageMath} from "aave-v3-origin/contracts/protocol/libraries/math/PercentageMath.sol";
import {ReentrancyGuardTransient} from "openzeppelin-contracts/contracts/utils/ReentrancyGuardTransient.sol";
import {PoolInstance} from "aave-v3-origin/contracts/instances/PoolInstance.sol";
import {
  IPoolAddressesProvider as IPoolAddressesProvider38
} from "aave-v3-origin/contracts/interfaces/IPoolAddressesProvider.sol";
import {IReserveInterestRateStrategy} from "aave-v3-origin/contracts/interfaces/IReserveInterestRateStrategy.sol";
import {UpgradePayload, IPoolRevision} from "../src/UpgradePayload.sol";

interface IIncentivizedToken {
  function getIncentivesController() external view returns (address);
}

interface MockExecute {
  function execute() external;
}

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

abstract contract UpgradeTest is ProtocolV3TestBase {
  using SafeERC20 for IERC20;
  using ReserveConfiguration for DataTypes.ReserveConfigurationMap;
  using PercentageMath for uint256;

  bytes32 internal constant ERC1967_IMPLEMENTATION_SLOT =
    0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

  string public NETWORK;
  string public NETWORK_SUB_NAME;
  uint256 public immutable BLOCK_NUMBER;
  address FLASH_RECEIVER;
  // payload `execute()` runs from inside the flashloan callback; zero for the control run
  address internal _flashPayload;

  constructor(string memory network, uint256 blocknumber) {
    NETWORK = network;
    BLOCK_NUMBER = blocknumber;
  }

  function setUp() public virtual {
    vm.createSelectFork(vm.rpcUrl(NETWORK), BLOCK_NUMBER);
    FLASH_RECEIVER = address(new MockFlashReceiver());
  }

  function test_execution() public virtual {
    executePayload(vm, _getTestPayload());
  }

  // function to be called from the flashloan
  function execute() external {
    if (_flashPayload != address(0)) executePayload(vm, _flashPayload);
  }

  /// forge-config: default.isolate = true
  function test_diff() external virtual {
    UpgradePayload _payload = UpgradePayload(_getTestPayload());

    IPoolAddressesProvider addressesProvider = IPoolAddressesProvider(address(_payload.POOL_ADDRESSES_PROVIDER()));
    IPool pool = IPool(addressesProvider.getPool());

    defaultTest(
      string(abi.encodePacked(vm.toString(block.chainid), "_", vm.toString(address(pool)))), pool, address(_payload)
    );
  }

  function test_upgrade() public virtual {
    UpgradePayload _payload = UpgradePayload(_getTestPayload());
    IPool pool = IPool(address(_payload.POOL()));
    address poolConfigurator = _payload.POOL_ADDRESSES_PROVIDER().getPoolConfigurator();

    address interestRateStrategyBefore = pool.RESERVE_INTEREST_RATE_STRATEGY();
    address poolConfiguratorImplBefore = _getImplementation(poolConfigurator);
    assertEq(IPoolRevision(address(pool)).POOL_REVISION(), _payload.PREVIOUS_POOL_REVISION());

    executePayload(vm, address(_payload));

    assertEq(_getImplementation(address(pool)), _payload.POOL_IMPL());
    assertEq(IPoolRevision(address(pool)).POOL_REVISION(), 12);
    assertEq(pool.RESERVE_INTEREST_RATE_STRATEGY(), interestRateStrategyBefore);
    assertEq(_getImplementation(poolConfigurator), poolConfiguratorImplBefore);
  }

  function test_execute_revertsWhenAlreadyUpgraded() external {
    UpgradePayload _payload = UpgradePayload(_getTestPayload());

    executePayload(vm, address(_payload));

    vm.expectRevert(UpgradePayload.WrongPoolRevision.selector);
    _payload.execute();
  }

  function test_constructor_revertsOnInterestRateStrategyMismatch() external {
    UpgradePayload _payload = UpgradePayload(_getTestPayload());
    IPoolAddressesProvider38 addressesProvider = _payload.POOL_ADDRESSES_PROVIDER();

    address poolImpl = address(new PoolInstance(addressesProvider, IReserveInterestRateStrategy(address(0xdead))));

    vm.expectRevert(UpgradePayload.WrongInterestRateStrategy.selector);
    new UpgradePayload(UpgradePayload.ConstructorParams({poolAddressesProvider: addressesProvider, poolImpl: poolImpl}));
  }

  function test_reentrancy_supplyFromFlashLoanCallback() external {
    UpgradePayload _payload = UpgradePayload(_getTestPayload());
    IPool pool = IPool(address(_payload.POOL()));
    executePayload(vm, address(_payload));

    (address asset, uint256 amount) = _findSuppliableReserve(pool, true);
    address receiver = address(new SupplyingFlashReceiver());
    // amount for the supply plus an upper bound for the premium
    deal(asset, receiver, 2 * amount);

    pool.flashLoanSimple(receiver, asset, amount, abi.encode(amount), 0);

    assertGe(IERC20(pool.getReserveAToken(asset)).balanceOf(receiver), amount - 1);
  }

  function test_reentrancy_guardedActionReentryReverts() external {
    UpgradePayload _payload = UpgradePayload(_getTestPayload());
    IPool pool = IPool(address(_payload.POOL()));
    executePayload(vm, address(_payload));

    (address asset, uint256 amount) = _findSuppliableReserve(pool, false);
    address rewardsController = IIncentivizedToken(pool.getReserveAToken(asset)).getIncentivesController();
    vm.etch(rewardsController, address(new ReentrantRewardsHook(pool)).code);

    deal(asset, address(this), amount);
    IERC20(asset).forceApprove(address(pool), amount);

    vm.expectRevert(ReentrancyGuardTransient.ReentrancyGuardReentrantCall.selector);
    pool.supply(asset, amount, address(this), 0);
  }

  function test_gas() external {
    executePayload(vm, address(_getPayload()));
    vm.snapshotGasLastCall("Execution", string.concat(NETWORK, NETWORK_SUB_NAME));
  }

  /**
   * Governance execution is permissionless once queued, so anyone can wrap it in a flashloan.
   * Executing the upgrade inside the callback must leave every reserve exactly as executing it after the flashloan.
   */
  function test_flashloan_upgradeInsideCallback() public {
    UpgradePayload _payload = UpgradePayload(_getTestPayload());
    IPool pool = IPool(address(_payload.POOL()));
    (address[] memory assets, uint256[] memory amounts) = _flashLoanAssets(pool);

    uint256 premiumTotal = pool.FLASHLOAN_PREMIUM_TOTAL();
    // premiums come out of the aToken: `deal` can't fund every asset (FXS via its whale)
    for (uint256 i = 0; i < assets.length; i++) {
      vm.prank(pool.getReserveAToken(assets[i]));
      IERC20(assets[i]).safeTransfer(FLASH_RECEIVER, amounts[i].percentMul(premiumTotal) + 1);
    }

    uint256 snapshot = vm.snapshotState();
    _flashLoan(pool, assets, amounts);
    executePayload(vm, address(_payload));
    bytes32[] memory expected = _reserveStates(pool);
    vm.revertToState(snapshot);

    _flashPayload = address(_payload);
    _flashLoan(pool, assets, amounts);

    assertEq(IPoolRevision(address(pool)).POOL_REVISION(), _payload.NEW_POOL_REVISION());
    bytes32[] memory actual = _reserveStates(pool);
    for (uint256 i = 0; i < actual.length; i++) {
      assertEq(actual[i], expected[i]);
    }
  }

  function _flashLoanAssets(IPool pool) internal returns (address[] memory assets, uint256[] memory amounts) {
    address[] memory reserves = pool.getReservesList();
    assets = new address[](reserves.length);
    amounts = new uint256[](reserves.length);
    uint256 length;
    for (uint256 i = 0; i < reserves.length; i++) {
      DataTypes.ReserveConfigurationMap memory configuration = pool.getConfiguration(reserves[i]);
      if (
        configuration.getPaused() || !configuration.getActive() || !configuration.getFlashLoanEnabled()
          || _isExcludedFromFlashLoan(reserves[i])
      ) {
        continue;
      }
      // half the virtual balance: the exact amount doesn't matter, it only has to be non-zero
      uint256 amount = pool.getVirtualUnderlyingBalance(reserves[i]) / 2;
      if (amount == 0) continue;
      assets[length] = reserves[i];
      amounts[length] = amount;
      ++length;
    }
    assembly {
      mstore(assets, length)
      mstore(amounts, length)
    }
  }

  function _flashLoan(IPool pool, address[] memory assets, uint256[] memory amounts) internal {
    pool.flashLoan({
      receiverAddress: FLASH_RECEIVER,
      assets: assets,
      amounts: amounts,
      interestRateModes: new uint256[](assets.length),
      onBehalfOf: address(this),
      params: "",
      referralCode: 0
    });
  }

  function _reserveStates(IPool pool) internal view returns (bytes32[] memory states) {
    address[] memory reserves = pool.getReservesList();
    states = new bytes32[](reserves.length);
    for (uint256 i = 0; i < reserves.length; i++) {
      states[i] = keccak256(abi.encode(pool.getReserveData(reserves[i]), pool.getVirtualUnderlyingBalance(reserves[i])));
    }
  }

  /// @dev Assets whose transfers revert at the fork block, which would fail the flashloan before its callback.
  function _isExcludedFromFlashLoan(address) internal view virtual returns (bool) {
    return false;
  }

  /// @dev External so `_findSuppliableReserve` can try it and roll back: `deal` and supply both fail on some assets.
  function supplyProbe(IPool pool, address asset, uint256 amount) external {
    deal(asset, address(this), amount);
    IERC20(asset).forceApprove(address(pool), amount);
    pool.supply(asset, amount, address(this), 0);
  }

  function _findSuppliableReserve(IPool pool, bool flashLoanable) internal returns (address, uint256) {
    address[] memory reserves = pool.getReservesList();
    for (uint256 i = 0; i < reserves.length; i++) {
      DataTypes.ReserveConfigurationMap memory configuration = pool.getConfiguration(reserves[i]);
      if (
        !configuration.getActive() || configuration.getPaused() || configuration.getFrozen()
          || (flashLoanable && !configuration.getFlashLoanEnabled())
      ) {
        continue;
      }
      if (IIncentivizedToken(pool.getReserveAToken(reserves[i])).getIncentivesController() == address(0)) continue;

      uint256 amount = 10 ** configuration.getDecimals();
      if (flashLoanable && pool.getVirtualUnderlyingBalance(reserves[i]) < amount) continue;

      uint256 snapshot = vm.snapshotState();
      bool ok;
      try this.supplyProbe(pool, reserves[i], amount) {
        ok = true;
      } catch {}
      vm.revertToState(snapshot);
      if (ok) return (reserves[i], amount);
    }
    revert("NO_SUPPLIABLE_RESERVE");
  }

  function _getImplementation(address proxy) internal view returns (address) {
    return address(uint160(uint256(vm.load(proxy, ERC1967_IMPLEMENTATION_SLOT))));
  }

  function _getTestPayload() internal returns (address) {
    address deployed = _getDeployedPayload();
    if (deployed == address(0)) return _getPayload();
    return deployed;
  }

  function _getPayload() internal virtual returns (address);

  function _getDeployedPayload() internal virtual returns (address);
}
