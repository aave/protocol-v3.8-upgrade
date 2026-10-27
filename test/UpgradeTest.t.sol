// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import {
  ProtocolV3TestBase,
  ReserveConfig,
  IPool,
  IPoolAddressesProvider,
  IERC20,
  SafeERC20
} from "aave-helpers/src/ProtocolV3TestBase.sol";
import {PercentageMath} from "aave-v3-origin/contracts/protocol/libraries/math/PercentageMath.sol";
import {TokenMath} from "aave-v3-origin/contracts/protocol/libraries/helpers/TokenMath.sol";
import {IScaledBalanceToken} from "aave-v3-origin/contracts/interfaces/IScaledBalanceToken.sol";
import {ReentrancyGuardTransient} from "openzeppelin-contracts/contracts/utils/ReentrancyGuardTransient.sol";
import {PoolInstance} from "aave-v3-origin/contracts/instances/PoolInstance.sol";
import {
  IPoolAddressesProvider as IPoolAddressesProvider38
} from "aave-v3-origin/contracts/interfaces/IPoolAddressesProvider.sol";
import {IReserveInterestRateStrategy} from "aave-v3-origin/contracts/interfaces/IReserveInterestRateStrategy.sol";
import {IPool as IPool38} from "aave-v3-origin/contracts/interfaces/IPool.sol";
import {IPoolConfigurator} from "aave-v3-origin/contracts/interfaces/IPoolConfigurator.sol";
import {DataTypes as DataTypes38} from "aave-v3-origin/contracts/protocol/libraries/types/DataTypes.sol";
import {UpgradePayload} from "../src/UpgradePayload.sol";
import {IPoolRevision} from "../src/interfaces/IPoolRevision.sol";

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
  using PercentageMath for uint256;
  using TokenMath for uint256;

  struct FlashBorrow {
    ReserveConfig collateral;
    ReserveConfig asset;
    uint8 eModeCategory;
  }

  struct PoolWiring {
    address[] addressesProviderEntries;
    string marketId;
    address poolConfiguratorImpl;
    address addressesProvider;
    address interestRateStrategy;
    uint128 flashLoanPremiumTotal;
    uint128 flashLoanPremiumToProtocol;
    uint16 maxNumberReserves;
    uint256 reservesCount;
    address[5] libraries;
  }

  bytes32 internal constant ERC1967_IMPLEMENTATION_SLOT =
    0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

  string public NETWORK;
  string public NETWORK_SUB_NAME;
  uint256 public immutable BLOCK_NUMBER;
  address FLASH_RECEIVER;
  // payload `execute()` runs from inside the flashloan callback; zero for the control run
  address internal _flashPayload;

  bytes32[8] internal ADDRESSES_PROVIDER_IDS = [
    bytes32("POOL"),
    "POOL_CONFIGURATOR",
    "PRICE_ORACLE",
    "ACL_MANAGER",
    "ACL_ADMIN",
    "PRICE_ORACLE_SENTINEL",
    "DATA_PROVIDER",
    "UMBRELLA"
  ];

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
    assertEq(IPoolRevision(address(pool)).POOL_REVISION(), _payload.PREVIOUS_POOL_REVISION());

    executePayload(vm, address(_payload));

    assertEq(_getImplementation(address(pool)), _payload.POOL_IMPL());
    assertEq(IPoolRevision(address(pool)).POOL_REVISION(), 12);
  }

  function test_config_reservesUnchanged() external {
    UpgradePayload _payload = UpgradePayload(_getTestPayload());
    IPool pool = IPool(address(_payload.POOL()));
    ReserveConfig[] memory configsBefore = _getReservesConfigs(pool);

    executePayload(vm, address(_payload));

    ReserveConfig[] memory configsAfter = _getReservesConfigs(pool);
    _validateCountOfListings(0, configsBefore, configsAfter);
    _noReservesConfigsChangesApartNewListings(configsBefore, configsAfter);
  }

  function test_config_reserveDataUnchanged() external {
    UpgradePayload _payload = UpgradePayload(_getTestPayload());
    IPool pool = IPool(address(_payload.POOL()));
    address[] memory reservesBefore = pool.getReservesList();
    bytes32[] memory statesBefore = _reserveStates(pool);

    executePayload(vm, address(_payload));

    assertEq(pool.getReservesList(), reservesBefore);
    bytes32[] memory statesAfter = _reserveStates(pool);
    for (uint256 i = 0; i < statesAfter.length; i++) {
      assertEq(statesAfter[i], statesBefore[i]);
    }
  }

  function test_config_eModesUnchanged() external {
    UpgradePayload _payload = UpgradePayload(_getTestPayload());
    IPool38 pool = _payload.POOL();
    uint8[] memory idsBefore = _getEModeCategoryIds(pool);
    DataTypes38.EModeCategory[] memory categoriesBefore = new DataTypes38.EModeCategory[](idsBefore.length);
    for (uint256 i = 0; i < idsBefore.length; i++) {
      categoriesBefore[i] = _getEModeCategory(pool, idsBefore[i]);
    }

    executePayload(vm, address(_payload));

    uint8[] memory idsAfter = _getEModeCategoryIds(pool);
    assertEq(idsAfter.length, idsBefore.length);
    for (uint256 i = 0; i < idsBefore.length; i++) {
      assertEq(idsAfter[i], idsBefore[i]);
      _validateEmodeCategory(_payload.POOL_ADDRESSES_PROVIDER(), idsBefore[i], categoriesBefore[i]);
      assertEq(pool.getEModeCategoryLtvzeroBitmap(idsBefore[i]), categoriesBefore[i].ltvzeroBitmap);
      assertEq(pool.getIsEModeCategoryIsolated(idsBefore[i]), categoriesBefore[i].isolated);
    }
  }

  function test_config_poolWiringUnchanged() external {
    UpgradePayload _payload = UpgradePayload(_getTestPayload());
    PoolWiring memory wiringBefore = _getPoolWiring(_payload);

    executePayload(vm, address(_payload));

    PoolWiring memory wiringAfter = _getPoolWiring(_payload);
    assertEq(wiringAfter.addressesProviderEntries, wiringBefore.addressesProviderEntries);
    assertEq(wiringAfter.marketId, wiringBefore.marketId);
    assertEq(wiringAfter.poolConfiguratorImpl, wiringBefore.poolConfiguratorImpl);
    assertEq(wiringAfter.addressesProvider, wiringBefore.addressesProvider);
    assertEq(wiringAfter.interestRateStrategy, wiringBefore.interestRateStrategy);
    assertEq(wiringAfter.flashLoanPremiumTotal, wiringBefore.flashLoanPremiumTotal);
    assertEq(wiringAfter.flashLoanPremiumToProtocol, wiringBefore.flashLoanPremiumToProtocol);
    assertEq(wiringAfter.maxNumberReserves, wiringBefore.maxNumberReserves);
    assertEq(wiringAfter.reservesCount, wiringBefore.reservesCount);
    // only FlashLoanLogic is redeployed (index 1); every linked library must have code
    for (uint256 i = 0; i < 5; i++) {
      if (i != 1) assertEq(wiringAfter.libraries[i], wiringBefore.libraries[i]);
      assertGt(wiringAfter.libraries[i].code.length, 0);
    }
  }

  function test_execute_revertsWhenAlreadyUpgraded() external {
    UpgradePayload _payload = UpgradePayload(_getTestPayload());

    executePayload(vm, address(_payload));

    vm.expectRevert(UpgradePayload.WrongPoolRevision.selector);
    _payload.execute();
  }

  function test_constructor_revertsOnAddressesProviderMismatch() external {
    UpgradePayload _payload = UpgradePayload(_getTestPayload());
    IPoolAddressesProvider38 addressesProvider = _payload.POOL_ADDRESSES_PROVIDER();

    address poolImpl = address(
      new PoolInstance(
        IPoolAddressesProvider38(address(0xdead)),
        IReserveInterestRateStrategy(_payload.POOL().RESERVE_INTEREST_RATE_STRATEGY())
      )
    );

    vm.expectRevert(UpgradePayload.WrongAddresses.selector);
    new UpgradePayload(UpgradePayload.ConstructorParams({poolAddressesProvider: addressesProvider, poolImpl: poolImpl}));
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

    ReserveConfig memory config = _getE2eReserve(pool, true);
    _removeCaps(pool, config);
    uint256 amount = _getTokenAmountByDollarValue(pool, config, 1_000);
    address receiver = address(new SupplyingFlashReceiver());
    // amount for the supply plus an upper bound for the premium
    deal2(config.underlying, receiver, 2 * amount);

    pool.flashLoanSimple(receiver, config.underlying, amount, abi.encode(amount), 0);

    assertEq(
      IScaledBalanceToken(config.aToken).scaledBalanceOf(receiver),
      amount.getATokenMintScaledAmount(pool.getReserveNormalizedIncome(config.underlying))
    );
  }

  function test_reentrancy_guardedActionReentryReverts() external {
    UpgradePayload _payload = UpgradePayload(_getTestPayload());
    IPool pool = IPool(address(_payload.POOL()));
    executePayload(vm, address(_payload));

    ReserveConfig memory config = _getE2eReserve(pool, false);
    _removeCaps(pool, config);
    uint256 amount = _getTokenAmountByDollarValue(pool, config, 1_000);
    address rewardsController = IIncentivizedToken(config.aToken).getIncentivesController();
    assertNotEq(rewardsController, address(0));
    vm.etch(rewardsController, address(new ReentrantRewardsHook(pool)).code);

    deal2(config.underlying, address(this), amount);
    IERC20(config.underlying).forceApprove(address(pool), amount);

    vm.expectRevert(ReentrancyGuardTransient.ReentrancyGuardReentrantCall.selector);
    pool.supply(config.underlying, amount, address(this), 0);
  }

  function test_gas() external {
    executePayload(vm, _getTestPayload());
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

  /// @dev Same as above with a debt-opening (mode 2) flashloan, where the v3.7 frame runs the borrow after the upgrade.
  function test_flashloan_upgradeInsideDebtOpeningCallback() public {
    UpgradePayload _payload = UpgradePayload(_getTestPayload());
    IPool pool = IPool(address(_payload.POOL()));
    FlashBorrow memory flashBorrow = _getFlashBorrow(pool);
    _removeCaps(pool, flashBorrow.collateral);
    _removeCaps(pool, flashBorrow.asset);

    uint256 snapshot = vm.snapshotState();
    _openDebtWithFlashLoan(pool, flashBorrow);
    executePayload(vm, address(_payload));
    bytes32[] memory expected = _reserveStates(pool);
    bytes32 expectedUser = _userState(pool, flashBorrow);
    vm.revertToState(snapshot);

    _flashPayload = address(_payload);
    _openDebtWithFlashLoan(pool, flashBorrow);

    assertEq(IPoolRevision(address(pool)).POOL_REVISION(), _payload.NEW_POOL_REVISION());
    assertGt(IERC20(flashBorrow.asset.variableDebtToken).balanceOf(address(this)), 0);
    assertEq(_userState(pool, flashBorrow), expectedUser);
    bytes32[] memory actual = _reserveStates(pool);
    for (uint256 i = 0; i < actual.length; i++) {
      assertEq(actual[i], expected[i]);
    }
  }

  function _openDebtWithFlashLoan(IPool pool, FlashBorrow memory flashBorrow) internal {
    // e-mode first, so a collateral with LTV 0 outside e-mode is enabled on deposit
    if (flashBorrow.eModeCategory != 0) pool.setUserEMode(flashBorrow.eModeCategory);
    _deposit(
      flashBorrow.collateral, pool, address(this), _getTokenAmountByDollarValue(pool, flashBorrow.collateral, 100_000)
    );
    address[] memory assets = new address[](1);
    assets[0] = flashBorrow.asset.underlying;
    uint256[] memory amounts = new uint256[](1);
    amounts[0] = _getTokenAmountByDollarValue(pool, flashBorrow.asset, 1_000);
    uint256[] memory interestRateModes = new uint256[](1);
    interestRateModes[0] = 2;
    pool.flashLoan({
      receiverAddress: FLASH_RECEIVER,
      assets: assets,
      amounts: amounts,
      interestRateModes: interestRateModes,
      onBehalfOf: address(this),
      params: "",
      referralCode: 0
    });
  }

  /**
   * @dev Picks the pair the same way `e2eTest` does: the first collateral with LTV > 0 and the first other borrowable
   * asset, else the first asset borrowable in an e-mode together with a collateral sharing that e-mode.
   */
  function _getFlashBorrow(IPool pool) internal view returns (FlashBorrow memory flashBorrow) {
    ReserveConfig[] memory configs = _getReservesConfigs(pool);
    for (uint256 i = 0; i < configs.length; i++) {
      if (!_includeInE2e(configs[i]) || !configs[i].usageAsCollateralEnabled || configs[i].ltv == 0) continue;
      for (uint256 j = 0; j < configs.length; j++) {
        if (i != j && _isFlashBorrowable(configs[j]) && configs[j].borrowingEnabled) {
          return FlashBorrow({collateral: configs[i], asset: configs[j], eModeCategory: 0});
        }
      }
      break;
    }
    for (uint256 j = 0; j < configs.length; j++) {
      if (!_isFlashBorrowable(configs[j]) || !_isBorrowableInAnyEMode(pool, configs[j].underlying)) continue;
      for (uint256 i = 0; i < configs.length; i++) {
        if (i == j || !_includeInE2e(configs[i])) continue;
        uint8 eModeCategory = _getSharedEModeCategory(pool, configs[i].underlying, configs[j].underlying);
        if (eModeCategory != 0) {
          return FlashBorrow({collateral: configs[i], asset: configs[j], eModeCategory: eModeCategory});
        }
      }
    }
    revert("NO_FLASH_BORROW_PAIR");
  }

  function _isFlashBorrowable(ReserveConfig memory config) internal pure returns (bool) {
    return _includeInE2e(config) && config.isFlashloanable;
  }

  function _userState(IPool pool, FlashBorrow memory flashBorrow) internal view returns (bytes32) {
    return keccak256(
      abi.encode(
        _accountData(pool),
        pool.getUserConfiguration(address(this)).data,
        IERC20(flashBorrow.collateral.aToken).balanceOf(address(this)),
        IERC20(flashBorrow.asset.variableDebtToken).balanceOf(address(this))
      )
    );
  }

  function _accountData(IPool pool) internal view returns (bytes32) {
    (uint256 a, uint256 b, uint256 c, uint256 d, uint256 e, uint256 f) = pool.getUserAccountData(address(this));
    return keccak256(abi.encode(a, b, c, d, e, f));
  }

  function _flashLoanAssets(IPool pool) internal view returns (address[] memory assets, uint256[] memory amounts) {
    ReserveConfig[] memory configs = _getReservesConfigs(pool);
    assets = new address[](configs.length);
    amounts = new uint256[](configs.length);
    uint256 length;
    for (uint256 i = 0; i < configs.length; i++) {
      if (
        configs[i].isPaused || !configs[i].isActive || !configs[i].isFlashloanable
          || _isExcludedFromFlashLoan(configs[i].underlying)
      ) {
        continue;
      }
      // half the virtual balance: the exact amount doesn't matter, it only has to be non-zero
      uint256 amount = configs[i].virtualBalance / 2;
      if (amount == 0) continue;
      assets[length] = configs[i].underlying;
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
      states[i] = keccak256(
        abi.encode(
          pool.getReserveData(reserves[i]),
          pool.getVirtualUnderlyingBalance(reserves[i]),
          pool.getReserveDeficit(reserves[i]),
          pool.getLiquidationGracePeriod(reserves[i])
        )
      );
    }
  }

  /// @dev Assets whose transfers revert at the fork block, which would fail the flashloan before its callback.
  function _isExcludedFromFlashLoan(address) internal pure virtual returns (bool) {
    return false;
  }

  /// @dev First reserve `e2eTest` would include, optionally flashloanable with enough virtual balance for $1k.
  function _getE2eReserve(IPool pool, bool flashLoanable) internal view returns (ReserveConfig memory) {
    ReserveConfig[] memory configs = _getReservesConfigs(pool);
    for (uint256 i = 0; i < configs.length; i++) {
      if (!_includeInE2e(configs[i])) continue;
      if (
        flashLoanable
          && (!configs[i].isFlashloanable
            || configs[i].virtualBalance < _getTokenAmountByDollarValue(pool, configs[i], 1_000))
      ) continue;
      return configs[i];
    }
    revert("NO_E2E_RESERVE");
  }

  /// @dev Same as `e2eTestAsset`: caps should not prevent testing.
  function _removeCaps(IPool pool, ReserveConfig memory config) internal {
    IPoolAddressesProvider addressesProvider = IPoolAddressesProvider(pool.ADDRESSES_PROVIDER());
    IPoolConfigurator poolConfigurator = IPoolConfigurator(addressesProvider.getPoolConfigurator());
    vm.startPrank(addressesProvider.getACLAdmin());
    if (config.supplyCap != 0) poolConfigurator.setSupplyCap(config.underlying, 0);
    if (config.borrowCap != 0) poolConfigurator.setBorrowCap(config.underlying, 0);
    vm.stopPrank();
  }

  /// @dev Configured categories, enumerated like aave-helpers `_writeEModeConfigs`: stops after three empty ids in a row.
  function _getEModeCategoryIds(IPool38 pool) internal view returns (uint8[] memory ids) {
    ids = new uint8[](256);
    uint256 length;
    uint8 emptyCounter;
    for (uint256 id = 0; id <= type(uint8).max; id++) {
      if (pool.getEModeCategoryCollateralConfig(uint8(id)).liquidationThreshold == 0) {
        if (++emptyCounter > 2) break;
        continue;
      }
      emptyCounter = 0;
      ids[length++] = uint8(id);
    }
    assembly {
      mstore(ids, length)
    }
  }

  function _getEModeCategory(IPool38 pool, uint8 id) internal view returns (DataTypes38.EModeCategory memory category) {
    DataTypes38.CollateralConfig memory collateralConfig = pool.getEModeCategoryCollateralConfig(id);
    category.ltv = collateralConfig.ltv;
    category.liquidationThreshold = collateralConfig.liquidationThreshold;
    category.liquidationBonus = collateralConfig.liquidationBonus;
    category.collateralBitmap = pool.getEModeCategoryCollateralBitmap(id);
    category.isolated = pool.getIsEModeCategoryIsolated(id);
    category.label = pool.getEModeCategoryLabel(id);
    category.borrowableBitmap = pool.getEModeCategoryBorrowableBitmap(id);
    category.ltvzeroBitmap = pool.getEModeCategoryLtvzeroBitmap(id);
  }

  function _getPoolWiring(UpgradePayload _payload) internal view returns (PoolWiring memory wiring) {
    IPoolAddressesProvider38 addressesProvider = _payload.POOL_ADDRESSES_PROVIDER();
    IPool38 pool = _payload.POOL();
    wiring.addressesProviderEntries = new address[](ADDRESSES_PROVIDER_IDS.length);
    for (uint256 i = 0; i < ADDRESSES_PROVIDER_IDS.length; i++) {
      wiring.addressesProviderEntries[i] = addressesProvider.getAddress(ADDRESSES_PROVIDER_IDS[i]);
    }
    wiring.marketId = addressesProvider.getMarketId();
    wiring.poolConfiguratorImpl = _getImplementation(addressesProvider.getPoolConfigurator());
    wiring.addressesProvider = address(pool.ADDRESSES_PROVIDER());
    wiring.interestRateStrategy = pool.RESERVE_INTEREST_RATE_STRATEGY();
    wiring.flashLoanPremiumTotal = pool.FLASHLOAN_PREMIUM_TOTAL();
    wiring.flashLoanPremiumToProtocol = pool.FLASHLOAN_PREMIUM_TO_PROTOCOL();
    wiring.maxNumberReserves = pool.MAX_NUMBER_RESERVES();
    wiring.reservesCount = pool.getReservesCount();
    wiring.libraries = [
      pool.getBorrowLogic(),
      pool.getFlashLoanLogic(),
      pool.getLiquidationLogic(),
      pool.getPoolLogic(),
      pool.getSupplyLogic()
    ];
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
