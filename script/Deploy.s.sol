// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {
  EthereumScript,
  PolygonScript,
  AvalancheScript,
  OptimismScript,
  ArbitrumScript,
  BaseScript,
  GnosisScript,
  BNBScript,
  LineaScript,
  CeloScript,
  InkScript,
  PlasmaScript,
  MantleScript,
  MegaEthScript,
  XLayerScript,
  MonadScript
} from "solidity-utils/contracts/utils/ScriptUtils.sol";

import {GovV3Helpers} from "aave-helpers/src/GovV3Helpers.sol";

import {Create2Utils} from "aave-v3-origin/deployments/contracts/utilities/Create2Utils.sol";
import {BorrowLogic} from "aave-v3-origin/contracts/protocol/libraries/logic/BorrowLogic.sol";
import {FlashLoanLogic} from "aave-v3-origin/contracts/protocol/libraries/logic/FlashLoanLogic.sol";
import {LiquidationLogic} from "aave-v3-origin/contracts/protocol/libraries/logic/LiquidationLogic.sol";
import {PoolLogic} from "aave-v3-origin/contracts/protocol/libraries/logic/PoolLogic.sol";
import {SupplyLogic} from "aave-v3-origin/contracts/protocol/libraries/logic/SupplyLogic.sol";

import {PoolInstance} from "aave-v3-origin/contracts/instances/PoolInstance.sol";
import {L2PoolInstance} from "aave-v3-origin/contracts/instances/L2PoolInstance.sol";

import {IPool} from "aave-v3-origin/contracts/interfaces/IPool.sol";
import {IPoolAddressesProvider} from "aave-v3-origin/contracts/interfaces/IPoolAddressesProvider.sol";

import {AaveV3Polygon} from "aave-address-book/AaveV3Polygon.sol";
import {AaveV3Avalanche} from "aave-address-book/AaveV3Avalanche.sol";
import {AaveV3Optimism} from "aave-address-book/AaveV3Optimism.sol";
import {AaveV3Arbitrum} from "aave-address-book/AaveV3Arbitrum.sol";
import {AaveV3Ethereum} from "aave-address-book/AaveV3Ethereum.sol";
import {AaveV3BNB} from "aave-address-book/AaveV3BNB.sol";
import {AaveV3Gnosis} from "aave-address-book/AaveV3Gnosis.sol";
import {AaveV3Base} from "aave-address-book/AaveV3Base.sol";
import {AaveV3EthereumLido} from "aave-address-book/AaveV3EthereumLido.sol";
import {AaveV3Linea} from "aave-address-book/AaveV3Linea.sol";
import {AaveV3Celo} from "aave-address-book/AaveV3Celo.sol";
import {AaveV3InkWhitelabel} from "aave-address-book/AaveV3InkWhitelabel.sol";
import {AaveV3Plasma} from "aave-address-book/AaveV3Plasma.sol";
import {AaveV3Mantle} from "aave-address-book/AaveV3Mantle.sol";
import {AaveV3MegaEth} from "aave-address-book/AaveV3MegaEth.sol";
import {AaveV3XLayer} from "aave-address-book/AaveV3XLayer.sol";
import {AaveV3Monad} from "aave-address-book/AaveV3Monad.sol";

import {UpgradePayload} from "../src/UpgradePayload.sol";

library DeploymentLibrary {
  // same salt as aave-v3-origin's LibraryPreCompile scripts, so the addresses match foundry.toml `libraries`
  bytes32 internal constant LIBRARIES_SALT = keccak256("AAVE_V3_LIBRARIES_BATCH");

  // L1s
  function _deployMainnetCore() internal returns (address) {
    return _deployL1(AaveV3Ethereum.POOL_ADDRESSES_PROVIDER);
  }

  function _deployMainnetLido() internal returns (address) {
    return _deployL1(AaveV3EthereumLido.POOL_ADDRESSES_PROVIDER);
  }

  function _deployPlasma() internal returns (address) {
    return _deployL1(AaveV3Plasma.POOL_ADDRESSES_PROVIDER);
  }

  function _deployAvalanche() internal returns (address) {
    return _deployL1(AaveV3Avalanche.POOL_ADDRESSES_PROVIDER);
  }

  function _deployBNB() internal returns (address) {
    return _deployL1(AaveV3BNB.POOL_ADDRESSES_PROVIDER);
  }

  function _deployMonad() internal returns (address) {
    return _deployL1(AaveV3Monad.POOL_ADDRESSES_PROVIDER);
  }

  function _deployPolygon() internal returns (address) {
    return _deployL1(AaveV3Polygon.POOL_ADDRESSES_PROVIDER);
  }

  function _deployGnosis() internal returns (address) {
    return _deployL1(AaveV3Gnosis.POOL_ADDRESSES_PROVIDER);
  }

  function _deployCelo() internal returns (address) {
    return _deployL1(AaveV3Celo.POOL_ADDRESSES_PROVIDER);
  }

  // rollups
  function _deployBase() internal returns (address) {
    return _deployL2(AaveV3Base.POOL_ADDRESSES_PROVIDER);
  }

  function _deployArbitrum() internal returns (address) {
    return _deployL2(AaveV3Arbitrum.POOL_ADDRESSES_PROVIDER);
  }

  function _deployOptimism() internal returns (address) {
    return _deployL2(AaveV3Optimism.POOL_ADDRESSES_PROVIDER);
  }

  function _deployMantle() internal returns (address) {
    return _deployL2(AaveV3Mantle.POOL_ADDRESSES_PROVIDER);
  }

  function _deployInk() internal returns (address) {
    return _deployL2(AaveV3InkWhitelabel.POOL_ADDRESSES_PROVIDER);
  }

  function _deployXLayer() internal returns (address) {
    return _deployL2(AaveV3XLayer.POOL_ADDRESSES_PROVIDER);
  }

  function _deployLinea() internal returns (address) {
    return _deployL2(AaveV3Linea.POOL_ADDRESSES_PROVIDER);
  }

  function _deployMegaEth() internal returns (address) {
    return _deployL2(AaveV3MegaEth.POOL_ADDRESSES_PROVIDER);
  }

  function _deployL1(IPoolAddressesProvider poolAddressesProvider) internal returns (address) {
    _deployLibraries();
    return _deployPayload(
      poolAddressesProvider,
      GovV3Helpers.deployDeterministic(type(PoolInstance).creationCode, _poolImplConstructorArgs(poolAddressesProvider))
    );
  }

  function _deployL2(IPoolAddressesProvider poolAddressesProvider) internal returns (address) {
    _deployLibraries();
    return _deployPayload(
      poolAddressesProvider,
      GovV3Helpers.deployDeterministic(
        type(L2PoolInstance).creationCode, _poolImplConstructorArgs(poolAddressesProvider)
      )
    );
  }

  // Skips libraries already deployed: only FlashLoanLogic differs from the v3.7 deployment.
  function _deployLibraries() internal {
    Create2Utils._create2Deploy(LIBRARIES_SALT, type(BorrowLogic).creationCode);
    Create2Utils._create2Deploy(LIBRARIES_SALT, type(FlashLoanLogic).creationCode);
    Create2Utils._create2Deploy(LIBRARIES_SALT, type(LiquidationLogic).creationCode);
    Create2Utils._create2Deploy(LIBRARIES_SALT, type(PoolLogic).creationCode);
    Create2Utils._create2Deploy(LIBRARIES_SALT, type(SupplyLogic).creationCode);
  }

  function _poolImplConstructorArgs(IPoolAddressesProvider poolAddressesProvider) private view returns (bytes memory) {
    return abi.encode(poolAddressesProvider, IPool(poolAddressesProvider.getPool()).RESERVE_INTEREST_RATE_STRATEGY());
  }

  function _deployPayload(IPoolAddressesProvider poolAddressesProvider, address poolImpl) private returns (address) {
    return GovV3Helpers.deployDeterministic(
      type(UpgradePayload).creationCode,
      abi.encode(UpgradePayload.ConstructorParams({poolAddressesProvider: poolAddressesProvider, poolImpl: poolImpl}))
    );
  }
}

contract Deploymainnet is EthereumScript {
  function run() external broadcast {
    DeploymentLibrary._deployMainnetCore();
  }
}

contract Deploylido is EthereumScript {
  function run() external broadcast {
    DeploymentLibrary._deployMainnetLido();
  }
}

contract Deployplasma is PlasmaScript {
  function run() external broadcast {
    DeploymentLibrary._deployPlasma();
  }
}

contract Deployavalanche is AvalancheScript {
  function run() external broadcast {
    DeploymentLibrary._deployAvalanche();
  }
}

contract Deploybnb is BNBScript {
  function run() external broadcast {
    DeploymentLibrary._deployBNB();
  }
}

contract Deploymonad is MonadScript {
  function run() external broadcast {
    DeploymentLibrary._deployMonad();
  }
}

contract Deploypolygon is PolygonScript {
  function run() external broadcast {
    DeploymentLibrary._deployPolygon();
  }
}

contract Deploygnosis is GnosisScript {
  function run() external broadcast {
    DeploymentLibrary._deployGnosis();
  }
}

contract Deploycelo is CeloScript {
  function run() external broadcast {
    DeploymentLibrary._deployCelo();
  }
}

contract Deploybase is BaseScript {
  function run() external broadcast {
    DeploymentLibrary._deployBase();
  }
}

contract Deployarbitrum is ArbitrumScript {
  function run() external broadcast {
    DeploymentLibrary._deployArbitrum();
  }
}

contract Deployoptimism is OptimismScript {
  function run() external broadcast {
    DeploymentLibrary._deployOptimism();
  }
}

contract Deploymantle is MantleScript {
  function run() external broadcast {
    DeploymentLibrary._deployMantle();
  }
}

contract Deployink is InkScript {
  function run() external broadcast {
    DeploymentLibrary._deployInk();
  }
}

contract DeployxLayer is XLayerScript {
  function run() external broadcast {
    DeploymentLibrary._deployXLayer();
  }
}

contract Deploylinea is LineaScript {
  function run() external broadcast {
    DeploymentLibrary._deployLinea();
  }
}

contract Deploymegaeth is MegaEthScript {
  function run() external broadcast {
    DeploymentLibrary._deployMegaEth();
  }
}
