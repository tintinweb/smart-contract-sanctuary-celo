// SPDX-License-Identifier: MIT
pragma solidity ~0.6.8;
pragma experimental ABIEncoderV2;

contract RegistryHelperBalancer {

    struct TokenState {
        address token;
        uint balance;
        uint denormalizedWeight;
    }

    struct PoolInfo {
        IBPool pool;
        uint swapFee;
        TokenState[] tokenStates;
    }

    function findPools(
        IBRegistry registry,
        address[] calldata fromTokens,
        address[] calldata toTokens
    ) external view returns (PoolInfo[] memory result) {
        require(fromTokens.length == toTokens.length,
            "fromTokens and toTokens must be of equal length");

        IBPool[] memory foundPools = new IBPool[](fromTokens.length * 5);
        uint found = 0;

        for (uint i = 0; i < fromTokens.length; i++) {
            // only take up the best 5 pools for a particular pair
            address[] memory pools =
                registry.getBestPoolsWithLimit(fromTokens[i], toTokens[i], 5);
            for (uint j = 0; j < pools.length; j++) {
                IBPool pool = IBPool(pools[j]);
                if (!pool.isFinalized()) {
                    continue;
                }

                bool addPool = true;
                for (uint k = 0; k < found; k++) {
                    if (foundPools[k] == pool) {
                        // already seen this pool, skip
                        addPool = false;
                        break;
                    }
                }
                if (addPool) {
                    // add this newly found pool
                    foundPools[found++] = pool;
                }
            }
        }

        result = new PoolInfo[](found);
        for (uint i = 0; i < found; i++) {
            IBPool pool = foundPools[i];
            result[i] = this.getPoolInfo(pool);
        }
    }

    function refreshPools(
        IBPool[] calldata pools
    ) external view returns (PoolInfo[] memory result) {
        result = new PoolInfo[](pools.length);
        for (uint i = 0; i < pools.length; i++) {
            result[i] = this.getPoolInfo(pools[i]);
        }
    }

    function getPoolInfo(IBPool pool) external view returns (PoolInfo memory result) {
        address[] memory poolTokens = pool.getCurrentTokens();
        TokenState[] memory tokenStates = new TokenState[](poolTokens.length);
        // collect information about all of the tokens in the pool
        for (uint j = 0; j < poolTokens.length; j++) {
            address token = poolTokens[j];
            tokenStates[j] = TokenState(
                token,
                pool.getBalance(token),
                pool.getDenormalizedWeight(token)
            );
        }

        result = PoolInfo(
            pool,
            pool.getSwapFee(),
            tokenStates
        );
    }
}


interface IBPool {
    function getNumTokens() external view returns (uint);
    function getCurrentTokens() external view returns (address[] memory tokens);
    function swapExactAmountIn(
        address tokenIn,
        uint tokenAmountIn,
        address tokenOut,
        uint minAmountOut,
        uint maxPrice) external returns (uint tokenAmountOut, uint spotPriceAfter);
    function swapExactAmountOut(
        address tokenIn,
        uint maxAmountIn,
        address tokenOut,
        uint tokenAmountOut,
        uint maxPrice) external returns (uint tokenAmountIn, uint spotPriceAfter);
    function calcInGivenOut(
        uint tokenBalanceIn,
        uint tokenWeightIn,
        uint tokenBalanceOut,
        uint tokenWeightOut,
        uint tokenAmountOut,
        uint swapFee) external pure returns (uint tokenAmountIn);
    function calcOutGivenIn(
        uint tokenBalanceIn,
        uint tokenWeightIn,
        uint tokenBalanceOut,
        uint tokenWeightOut,
        uint tokenAmountIn,
        uint swapFee) external pure returns (uint tokenAmountOut);
    function getNormalizedWeight(address token) external view returns (uint);
    function getDenormalizedWeight(address token) external view returns (uint);
    function getTotalDenormalizedWeight() external view returns (uint);
    function isFinalized() external view returns (bool);
    function getBalance(address token) external view returns (uint);
    function getSwapFee() external view returns (uint);
}

interface IBRegistry {

    event PoolTokenPairAdded(
        address indexed pool,
        address indexed token1,
        address indexed token2
    );

    event IndicesUpdated(
        address indexed token1,
        address indexed token2,
        bytes32 oldIndices,
        bytes32 newIndices
    );

    function getPairInfo(address pool, address fromToken, address destToken)
        external view returns(uint256 weight1, uint256 weight2, uint256 swapFee);

    function getPoolsWithLimit(address fromToken, address destToken, uint256 offset, uint256 limit)
        external view returns(address[] memory result);

    function getBestPools(address fromToken, address destToken)
        external view returns(address[] memory pools);

    function getBestPoolsWithLimit(address fromToken, address destToken, uint256 limit)
        external view returns(address[] memory pools);

    // Add and update registry
    function addPoolPair(address pool, address token1, address token2) external returns(uint256 listed);

    function addPools(address[] calldata pools, address token1, address token2) external returns(uint256[] memory listed);

    function sortPools(address[] calldata tokens, uint256 lengthLimit) external;

    function sortPoolsWithPurge(address[] calldata tokens, uint256 lengthLimit) external;
}