// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol';
import './ISlidingWindowOracle.sol';
import './IERC20.sol';


contract PriceFeed2Step {
    address public immutable tokenIn;
    address public immutable tokenMiddle1;
    address public immutable tokenMiddle2;
    address public immutable tokenOut;
    uint public immutable oneToken;
    ISlidingWindowOracle public immutable slidingWindowOracle;

    constructor(address _tokenIn, address _tokenMiddle1, address _tokenMiddle2, address _tokenOut, ISlidingWindowOracle _slidingWindowOracle) {
        tokenIn = _tokenIn;
        tokenMiddle1 = _tokenMiddle1;
        tokenMiddle2 = _tokenMiddle2;
        tokenOut = _tokenOut;
        slidingWindowOracle = _slidingWindowOracle;
        oneToken = uint(10)**(IERC20(tokenIn).decimals());
    }

    function consult() external view returns (uint) {
        uint priceMiddle = slidingWindowOracle.consult(tokenIn, oneToken, tokenMiddle1);
        return slidingWindowOracle.consult(tokenMiddle2, priceMiddle, tokenOut);
    }
}


// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;


interface ISlidingWindowOracle {
    function consult(address tokenIn, uint amountIn, address tokenOut) external view returns (uint amountOut);
    function update(address tokenA, address tokenB) external;
    function periodSize() external view returns (uint);
}


// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

interface IERC20 {
    function decimals() external view returns(uint8);
}


pragma solidity >=0.5.0;

interface IUniswapV2Pair {
    event Approval(address indexed owner, address indexed spender, uint value);
    event Transfer(address indexed from, address indexed to, uint value);

    function name() external pure returns (string memory);
    function symbol() external pure returns (string memory);
    function decimals() external pure returns (uint8);
    function totalSupply() external view returns (uint);
    function balanceOf(address owner) external view returns (uint);
    function allowance(address owner, address spender) external view returns (uint);

    function approve(address spender, uint value) external returns (bool);
    function transfer(address to, uint value) external returns (bool);
    function transferFrom(address from, address to, uint value) external returns (bool);

    function DOMAIN_SEPARATOR() external view returns (bytes32);
    function PERMIT_TYPEHASH() external pure returns (bytes32);
    function nonces(address owner) external view returns (uint);

    function permit(address owner, address spender, uint value, uint deadline, uint8 v, bytes32 r, bytes32 s) external;

    event Mint(address indexed sender, uint amount0, uint amount1);
    event Burn(address indexed sender, uint amount0, uint amount1, address indexed to);
    event Swap(
        address indexed sender,
        uint amount0In,
        uint amount1In,
        uint amount0Out,
        uint amount1Out,
        address indexed to
    );
    event Sync(uint112 reserve0, uint112 reserve1);

    function MINIMUM_LIQUIDITY() external pure returns (uint);
    function factory() external view returns (address);
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function price0CumulativeLast() external view returns (uint);
    function price1CumulativeLast() external view returns (uint);
    function kLast() external view returns (uint);

    function mint(address to) external returns (uint liquidity);
    function burn(address to) external returns (uint amount0, uint amount1);
    function swap(uint amount0Out, uint amount1Out, address to, bytes calldata data) external;
    function skim(address to) external;
    function sync() external;

    function initialize(address, address) external;
}