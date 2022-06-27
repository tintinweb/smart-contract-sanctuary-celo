// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.7.5;
pragma abicoder v2;

import { BFactory, BPool, ConfigurableRightsPool, CRPFactory, ERC20, RightsManager } from "./BalancerContracts.sol";

/**
 * @title Balancer Pool Deployer
 * @author Tom French
 * @notice This contract allows single transaction deployment of Balancer pools (both standard and smart)
 * @dev Implementation is taken from the Balancer BActions contract, adding pool ownership transfer to msg.sender
 *      See: https://github.com/balancer-labs/bactions-proxy/blob/c4a2f6071bbe09388beae5a1256f116362f44395/contracts/BActions.sol
 */
contract BalancerPoolDeployer {
    function create(
        BFactory factory,
        address[] calldata tokens,
        uint256[] calldata balances,
        uint256[] calldata weights,
        uint256 swapFee,
        bool finalize
    ) external returns (BPool pool) {
        require(tokens.length == balances.length, "ERR_LENGTH_MISMATCH");
        require(tokens.length == weights.length, "ERR_LENGTH_MISMATCH");

        pool = factory.newBPool();
        pool.setSwapFee(swapFee);

        // Pull in initial balances of tokens and bind them to pool
        for (uint256 i = 0; i < tokens.length; i++) {
            ERC20 token = ERC20(tokens[i]);
            require(token.transferFrom(msg.sender, address(this), balances[i]), "ERR_TRANSFER_FAILED");
            token.approve(address(pool), balances[i]);
            pool.bind(tokens[i], balances[i], weights[i]);
        }

        // If public (finalized) pool then send BPT tokens to msg.sender
        if (finalize) {
            pool.finalize();
            require(pool.transfer(msg.sender, pool.balanceOf(address(this))), "ERR_TRANSFER_FAILED");
        } else {
            pool.setPublicSwap(true);
        }

        // Set msg.sender to be controller of newly created pool
        pool.setController(msg.sender);
    }

    function createSmartPool(
        CRPFactory factory,
        BFactory bFactory,
        ConfigurableRightsPool.PoolParams calldata poolParams,
        ConfigurableRightsPool.CrpParams calldata crpParams,
        RightsManager.Rights calldata rights
    ) external returns (ConfigurableRightsPool crp) {
        require(poolParams.constituentTokens.length == poolParams.tokenBalances.length, "ERR_LENGTH_MISMATCH");
        require(poolParams.constituentTokens.length == poolParams.tokenWeights.length, "ERR_LENGTH_MISMATCH");

        // Deploy the CRP controller contract
        crp = factory.newCrp(address(bFactory), poolParams, rights);

        // Pull in initial balances of tokens for CRP
        for (uint256 i = 0; i < poolParams.constituentTokens.length; i++) {
            ERC20 token = ERC20(poolParams.constituentTokens[i]);
            require(token.transferFrom(msg.sender, address(this), poolParams.tokenBalances[i]), "ERR_TRANSFER_FAILED");
            token.approve(address(crp), poolParams.tokenBalances[i]);
        }

        // Deploy the underlying BPool
        crp.createPool(
            crpParams.initialSupply,
            crpParams.minimumWeightChangeBlockPeriod,
            crpParams.addTokenTimeLockInBlocks
        );

        // Return BPT to msg.sender
        require(crp.transfer(msg.sender, crpParams.initialSupply), "ERR_TRANSFER_FAILED");

        // Set msg.sender to be controller of newly created pool
        crp.setController(msg.sender);
    }
}


// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.7.5;
pragma abicoder v2;

library RightsManager {
    struct Rights {
        bool canPauseSwapping;
        bool canChangeSwapFee;
        bool canChangeWeights;
        bool canAddRemoveTokens;
        bool canWhitelistLPs;
        bool canChangeCap;
    }
}

abstract contract ERC20 {
    function approve(address spender, uint256 amount) external virtual returns (bool);

    function transfer(address dst, uint256 amt) external virtual returns (bool);

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external virtual returns (bool);

    function balanceOf(address whom) external view virtual returns (uint256);

    function allowance(address, address) external view virtual returns (uint256);
}

abstract contract BalancerOwnable {
    function setController(address controller) external virtual;
}

abstract contract AbstractPool is ERC20, BalancerOwnable {
    function setSwapFee(uint256 swapFee) external virtual;

    function setPublicSwap(bool public_) external virtual;

    function joinPool(uint256 poolAmountOut, uint256[] calldata maxAmountsIn) external virtual;

    function joinswapExternAmountIn(
        address tokenIn,
        uint256 tokenAmountIn,
        uint256 minPoolAmountOut
    ) external virtual returns (uint256 poolAmountOut);
}

abstract contract BPool is AbstractPool {
    function finalize() external virtual;

    function bind(
        address token,
        uint256 balance,
        uint256 denorm
    ) external virtual;

    function rebind(
        address token,
        uint256 balance,
        uint256 denorm
    ) external virtual;

    function unbind(address token) external virtual;

    function isBound(address t) external view virtual returns (bool);

    function getCurrentTokens() external view virtual returns (address[] memory);

    function getFinalTokens() external view virtual returns (address[] memory);

    function getBalance(address token) external view virtual returns (uint256);
}

abstract contract BFactory {
    function newBPool() external virtual returns (BPool);
}

abstract contract ConfigurableRightsPool is AbstractPool {
    struct PoolParams {
        string poolTokenSymbol;
        string poolTokenName;
        address[] constituentTokens;
        uint256[] tokenBalances;
        uint256[] tokenWeights;
        uint256 swapFee;
    }

    struct CrpParams {
        uint256 initialSupply;
        uint256 minimumWeightChangeBlockPeriod;
        uint256 addTokenTimeLockInBlocks;
    }

    function createPool(
        uint256 initialSupply,
        uint256 minimumWeightChangeBlockPeriod,
        uint256 addTokenTimeLockInBlocks
    ) external virtual;

    function createPool(uint256 initialSupply) external virtual;

    function setCap(uint256 newCap) external virtual;

    function updateWeight(address token, uint256 newWeight) external virtual;

    function updateWeightsGradually(
        uint256[] calldata newWeights,
        uint256 startBlock,
        uint256 endBlock
    ) external virtual;

    function commitAddToken(
        address token,
        uint256 balance,
        uint256 denormalizedWeight
    ) external virtual;

    function applyAddToken() external virtual;

    function removeToken(address token) external virtual;

    function whitelistLiquidityProvider(address provider) external virtual;

    function removeWhitelistedLiquidityProvider(address provider) external virtual;

    function bPool() external view virtual returns (BPool);
}

abstract contract CRPFactory {
    function newCrp(
        address factoryAddress,
        ConfigurableRightsPool.PoolParams calldata params,
        RightsManager.Rights calldata rights
    ) external virtual returns (ConfigurableRightsPool);
}