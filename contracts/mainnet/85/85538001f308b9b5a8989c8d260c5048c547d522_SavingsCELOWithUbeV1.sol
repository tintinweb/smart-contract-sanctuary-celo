//SPDX-License-Identifier: MIT
pragma solidity 0.6.8;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./interfaces/ISavingsCELO.sol";
import "./interfaces/IUniswapV2.sol";

// @title SavingsCELOWithUbeV1
// @notice This contract implements useful atomic wrappers to interact with the
// SavingsCELO and the Ubeswap CELO<->sCELO pool contracts. This contract doesn't hold
// any state or user funds, it only exists to implement helpful atomic wrappers.
// Contract itself is un-upgradable, but since it holds no state, it can be easily replaced or
// extended by a new version.
contract SavingsCELOWithUbeV1 {
	using SafeMath for uint256;

	/// @dev SavingsCELO contract,
	ISavingsCELO public savingsCELO;
	/// @dev Ubeswap Router contract.
	IUniswapV2Router public ubeRouter;
	/// @dev Ubeswap CELO<->sCELO pool contract.
	IUniswapV2Pair public ubePair;
	/// @dev Core GoldToken contract.
	IERC20 public CELO;

	/// @dev emitted when deposit succeeds.
	/// @param from address that initiated the deposit.
	/// @param celoAmount amount of CELO that was deposited.
	/// @param savingsAmount amount of sCELO that was returned in exchange.
	/// @param direct if True, then deposit was done through SavingsCELO contract directly.
	/// If false, deposit was completed through an Ubeswap trade.
	event Deposited(address indexed from, uint256 celoAmount, uint256 savingsAmount, bool direct);

	/// @dev emitted when user adds liquidity to the CELO<->sCELO Ubeswap pool.
	/// @param from address that added the liquidity.
	/// @param celoAmount amount of CELO that the user provided.
	/// @param savingsAmount amount of sCELO that the user provided.
	/// @param liquidity amount of Ubeswap Pool liquidity tokens returned to the user.
	event AddedLiquidity(address indexed from, uint256 celoAmount, uint256 savingsAmount, uint256 liquidity);

	constructor (
		address _savingsCELO,
		address _CELO,
		address _ubeRouter) public {
		savingsCELO = ISavingsCELO(_savingsCELO);
		CELO = IERC20(_CELO);

		ubeRouter = IUniswapV2Router(_ubeRouter);
		IUniswapV2Factory factory = IUniswapV2Factory(ubeRouter.factory());
		address _pair = factory.getPair(_savingsCELO, _CELO);
		if (_pair == address(0)) {
			_pair = factory.createPair(_savingsCELO, _CELO);
		}
		require(_pair != address(0), "Ubeswap pair must exist!");
		ubePair = IUniswapV2Pair(_pair);
	}

	/// @notice Converts CELO to sCELO tokens. Automatically chooses the best rate between
	/// a direct deposit in SavingsCELO contract or a trade in Ubeswap CELO<->sCELO pool.
	/// @return received_sCELO amount of sCELO tokens returned to the caller.
	function deposit() external payable returns (uint256 received_sCELO) {
		(uint256 reserve_CELO, uint256 reserve_sCELO) = ubeGetReserves();
		uint256 fromUbe_sCELO = (reserve_CELO == 0 || reserve_sCELO == 0) ? 0 :
			ubeGetAmountOut(msg.value, reserve_CELO, reserve_sCELO);
		uint256 fromDirect_sCELO = savingsCELO.celoToSavings(msg.value);

		bool direct;
		if (fromDirect_sCELO >= fromUbe_sCELO) {
			direct = true;
			received_sCELO = savingsCELO.deposit{value: msg.value}();
			assert(received_sCELO >= fromDirect_sCELO);
		} else {
			direct = false;
			address[] memory path = new address[](2);
			path[0] = address(CELO);
			path[1] = address(savingsCELO);
			require(
				CELO.approve(address(ubeRouter), msg.value),
				"CELO approve failed for ubeRouter!");
			received_sCELO = ubeRouter.swapExactTokensForTokens(
				msg.value, fromUbe_sCELO, path, address(this), block.timestamp)[1];
			assert(received_sCELO >= fromUbe_sCELO);
		}
		require(
			savingsCELO.transfer(msg.sender, received_sCELO),
			"sCELO transfer failed!");
		emit Deposited(msg.sender, msg.value, received_sCELO, direct);
		return received_sCELO;
	}

	/// @notice Adds liquidity in proportioned way to Ubeswap CELO<->sCELO pool. Will convert
	/// necessary amount of CELO to sCELO tokens before adding liquidity too.
	/// @param amount_CELO amount of CELO to take from caller.
	/// @param amount_sCELO amount of sCELO to take from caller.
	/// @param maxReserveRatio maximum allowed reserve ratio. maxReserveRatio is multiplied by 1e18 to
	/// represent a float value as an integer.
	/// @dev maxReserveRatio protects the caller from adding liquidity when pool is not balanced.
	/// @return addedLiquidity amount of Ubeswap pool liquidity tokens that got added and sent to the caller.
	function addLiquidity(
		uint256 amount_CELO,
		uint256 amount_sCELO,
		uint256 maxReserveRatio
	) external returns (uint256 addedLiquidity) {
		(uint256 _amount_CELO, uint256 _amount_sCELO) = (amount_CELO, amount_sCELO);
		uint256 toConvert_CELO = calculateToConvertCELO(amount_CELO, amount_sCELO, maxReserveRatio);
		uint256 converted_sCELO = 0;
		if (amount_CELO > 0) {
			require(
				CELO.transferFrom(msg.sender, address(this), amount_CELO),
				"CELO transferFrom failed!");
		}
		if (amount_sCELO > 0) {
			require(
				savingsCELO.transferFrom(msg.sender, address(this), amount_sCELO),
				"sCELO transferFrom failed!");
		}
		if (toConvert_CELO > 0) {
			converted_sCELO = savingsCELO.deposit{value: toConvert_CELO}();
			amount_sCELO = amount_sCELO.add(converted_sCELO);
			amount_CELO = amount_CELO.sub(toConvert_CELO);
		}
		if (amount_CELO > 0) {
			require(
				CELO.approve(address(ubeRouter), amount_CELO),
				"CELO approve failed for ubeRouter!");
		}
		if (amount_sCELO > 0) {
			require(
				savingsCELO.approve(address(ubeRouter), amount_sCELO),
				"sCELO approve failed for ubeRouter!");
		}
		// NOTE: amount_CELO might be few WEI more than needed, however there is no point
		// to try to return that back to the caller since GAS costs associated with dealing 1 or 2 WEI would be
		// multiple orders of magnitude more costly.
		(, , addedLiquidity) = ubeRouter.addLiquidity(
			address(CELO), address(savingsCELO),
			amount_CELO, amount_sCELO,
			amount_CELO.sub(5), amount_sCELO,
			msg.sender, block.timestamp);

		emit AddedLiquidity(msg.sender, _amount_CELO, _amount_sCELO, addedLiquidity);
		return (addedLiquidity);
	}

	/// @dev helper function to calculate amount of CELO that needs to be converted to sCELO
	/// to add liquidity in proportional way.
	function calculateToConvertCELO(
		uint256 amount_CELO,
		uint256 amount_sCELO,
		uint256 maxReserveRatio
	) internal view returns (uint256 toConvert_CELO) {
		(uint256 reserve_CELO, uint256 reserve_sCELO) = ubeGetReserves();
		if (reserve_CELO == 0 && reserve_sCELO == 0) {
			// If pool is empty, we can safely assume that the reserve ratio is just the ideal 1:1.
			reserve_CELO = 1;
			reserve_sCELO = savingsCELO.celoToSavings(1);
		}
		uint256 reserve_CELO_as_sCELO = savingsCELO.celoToSavings(reserve_CELO);
		// Reserve ratio is: max(reserve_sCELO/reserve_CELO_as_sCELO, reserve_CELO_as_sCELO/reserve_sCELO)
		// We perform comparisons without using division to keep things as safe and correct as possible.
		require(
			reserve_sCELO.mul(maxReserveRatio) >= reserve_CELO_as_sCELO.mul(1e18),
			"Too little sCELO in the liqudity pool. Adding liquidity is not safe!");
		require(
			reserve_CELO_as_sCELO.mul(maxReserveRatio) >= reserve_sCELO.mul(1e18),
			"Too little CELO in the liqudity pool. Adding liquidity is not safe!");

		// matched_CELO and amount_sCELO can be added proportionally.
		uint256 matched_CELO = amount_sCELO.mul(reserve_CELO).add(reserve_sCELO.sub(1)).div(reserve_sCELO);
		require(
			matched_CELO <= amount_CELO,
			"Too much sCELO. Can not add proportional liquidity!");
		// from rest of the CELO (i.e. amount_CELO-matched_CELO), we need to convert some amount to
		// sCELO to keep it proportion to reserve_CELO / reserve_sCELO.
		// NOTE: calculations and conversions are done in such a way that all sCELO will always be consumed
		// and rounding errors will apply to CELO itself. It is possible that we will have to throw out 1 or 2
		// WEI at most to meet the proportionality.
		toConvert_CELO = amount_CELO.sub(matched_CELO)
			.mul(reserve_sCELO)
			.div(reserve_sCELO.add(reserve_CELO_as_sCELO));
		// Prefer to under-convert, vs to over-convert. This way we make sure that all sCELO is always
		// consumed when we add liquidity and there can be only 1 or 2 celoWEI left over.
		return toConvert_CELO > 0 ? toConvert_CELO.sub(1) : 0;
	}

	/// @notice returns Ubeswap CELO<->sCELO pool reserves.
	/// @return reserve_CELO amount of CELO in the pool.
	/// @return reserve_sCELO amount of sCELO in the pool.
	function ubeGetReserves() public view returns (uint256 reserve_CELO, uint256 reserve_sCELO) {
		(uint256 reserve0, uint256 reserve1, ) = ubePair.getReserves();
		return (ubePair.token0() == address(CELO)) ? (reserve0, reserve1) : (reserve1, reserve0);
	}

	/// @dev copied from UniswapV2Library code.
	function ubeGetAmountOut(
		uint amountIn,
		uint reserveIn,
		uint reserveOut) internal pure returns (uint amountOut) {
		require(amountIn > 0, 'GetAmount: INSUFFICIENT_INPUT_AMOUNT');
		require(reserveIn > 0 && reserveOut > 0, 'GetAmount: INSUFFICIENT_LIQUIDITY');
		uint amountInWithFee = amountIn.mul(997);
		uint numerator = amountInWithFee.mul(reserveOut);
		uint denominator = reserveIn.mul(1000).add(amountInWithFee);
		amountOut = numerator / denominator;
	}
}


//SPDX-License-Identifier: MIT
pragma solidity 0.6.8;

interface IUniswapV2Factory {
	event PairCreated(address indexed token0, address indexed token1, address pair, uint);

	function feeTo() external view returns (address);
	function feeToSetter() external view returns (address);

	function getPair(address tokenA, address tokenB) external view returns (address pair);
	function allPairs(uint) external view returns (address pair);
	function allPairsLength() external view returns (uint);

	function createPair(address tokenA, address tokenB) external returns (address pair);

	function setFeeTo(address) external;
	function setFeeToSetter(address) external;
}

interface IUniswapV2Router {
	function factory() external pure returns (address);

	function addLiquidity(
			address tokenA,
			address tokenB,
			uint amountADesired,
			uint amountBDesired,
			uint amountAMin,
			uint amountBMin,
			address to,
			uint deadline
	) external returns (uint amountA, uint amountB, uint liquidity);
	function removeLiquidity(
			address tokenA,
			address tokenB,
			uint liquidity,
			uint amountAMin,
			uint amountBMin,
			address to,
			uint deadline
	) external returns (uint amountA, uint amountB);
	function removeLiquidityWithPermit(
			address tokenA,
			address tokenB,
			uint liquidity,
			uint amountAMin,
			uint amountBMin,
			address to,
			uint deadline,
			bool approveMax, uint8 v, bytes32 r, bytes32 s
	) external returns (uint amountA, uint amountB);
	function swapExactTokensForTokens(
			uint amountIn,
			uint amountOutMin,
			address[] calldata path,
			address to,
			uint deadline
	) external returns (uint[] memory amounts);
	function swapTokensForExactTokens(
			uint amountOut,
			uint amountInMax,
			address[] calldata path,
			address to,
			uint deadline
	) external returns (uint[] memory amounts);

	function quote(uint amountA, uint reserveA, uint reserveB) external pure returns (uint amountB);
	function getAmountOut(uint amountIn, uint reserveIn, uint reserveOut) external pure returns (uint amountOut);
	function getAmountIn(uint amountOut, uint reserveIn, uint reserveOut) external pure returns (uint amountIn);
	function getAmountsOut(uint amountIn, address[] calldata path) external view returns (uint[] memory amounts);
	function getAmountsIn(uint amountOut, address[] calldata path) external view returns (uint[] memory amounts);
	function swapExactTokensForTokensSupportingFeeOnTransferTokens(
			uint amountIn,
			uint amountOutMin,
			address[] calldata path,
			address to,
			uint deadline
	) external;

	function pairFor(address tokenA, address tokenB) external view returns (address);
}

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

// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

/**
 * @dev Interface of the ERC20 standard as defined in the EIP.
 */
interface IERC20 {
    /**
     * @dev Returns the amount of tokens in existence.
     */
    function totalSupply() external view returns (uint256);

    /**
     * @dev Returns the amount of tokens owned by `account`.
     */
    function balanceOf(address account) external view returns (uint256);

    /**
     * @dev Moves `amount` tokens from the caller's account to `recipient`.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transfer(address recipient, uint256 amount) external returns (bool);

    /**
     * @dev Returns the remaining number of tokens that `spender` will be
     * allowed to spend on behalf of `owner` through {transferFrom}. This is
     * zero by default.
     *
     * This value changes when {approve} or {transferFrom} are called.
     */
    function allowance(address owner, address spender) external view returns (uint256);

    /**
     * @dev Sets `amount` as the allowance of `spender` over the caller's tokens.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * IMPORTANT: Beware that changing an allowance with this method brings the risk
     * that someone may use both the old and the new allowance by unfortunate
     * transaction ordering. One possible solution to mitigate this race
     * condition is to first reduce the spender's allowance to 0 and set the
     * desired value afterwards:
     * https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
     *
     * Emits an {Approval} event.
     */
    function approve(address spender, uint256 amount) external returns (bool);

    /**
     * @dev Moves `amount` tokens from `sender` to `recipient` using the
     * allowance mechanism. `amount` is then deducted from the caller's
     * allowance.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);

    /**
     * @dev Emitted when `value` tokens are moved from one account (`from`) to
     * another (`to`).
     *
     * Note that `value` may be zero.
     */
    event Transfer(address indexed from, address indexed to, uint256 value);

    /**
     * @dev Emitted when the allowance of a `spender` for an `owner` is set by
     * a call to {approve}. `value` is the new allowance.
     */
    event Approval(address indexed owner, address indexed spender, uint256 value);
}


// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

/**
 * @dev Wrappers over Solidity's arithmetic operations with added overflow
 * checks.
 *
 * Arithmetic operations in Solidity wrap on overflow. This can easily result
 * in bugs, because programmers usually assume that an overflow raises an
 * error, which is the standard behavior in high level programming languages.
 * `SafeMath` restores this intuition by reverting the transaction when an
 * operation overflows.
 *
 * Using this library instead of the unchecked operations eliminates an entire
 * class of bugs, so it's recommended to use it always.
 */
library SafeMath {
    /**
     * @dev Returns the addition of two unsigned integers, reverting on
     * overflow.
     *
     * Counterpart to Solidity's `+` operator.
     *
     * Requirements:
     *
     * - Addition cannot overflow.
     */
    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a, "SafeMath: addition overflow");

        return c;
    }

    /**
     * @dev Returns the subtraction of two unsigned integers, reverting on
     * overflow (when the result is negative).
     *
     * Counterpart to Solidity's `-` operator.
     *
     * Requirements:
     *
     * - Subtraction cannot overflow.
     */
    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        return sub(a, b, "SafeMath: subtraction overflow");
    }

    /**
     * @dev Returns the subtraction of two unsigned integers, reverting with custom message on
     * overflow (when the result is negative).
     *
     * Counterpart to Solidity's `-` operator.
     *
     * Requirements:
     *
     * - Subtraction cannot overflow.
     */
    function sub(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b <= a, errorMessage);
        uint256 c = a - b;

        return c;
    }

    /**
     * @dev Returns the multiplication of two unsigned integers, reverting on
     * overflow.
     *
     * Counterpart to Solidity's `*` operator.
     *
     * Requirements:
     *
     * - Multiplication cannot overflow.
     */
    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        // Gas optimization: this is cheaper than requiring 'a' not being zero, but the
        // benefit is lost if 'b' is also tested.
        // See: https://github.com/OpenZeppelin/openzeppelin-contracts/pull/522
        if (a == 0) {
            return 0;
        }

        uint256 c = a * b;
        require(c / a == b, "SafeMath: multiplication overflow");

        return c;
    }

    /**
     * @dev Returns the integer division of two unsigned integers. Reverts on
     * division by zero. The result is rounded towards zero.
     *
     * Counterpart to Solidity's `/` operator. Note: this function uses a
     * `revert` opcode (which leaves remaining gas untouched) while Solidity
     * uses an invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     *
     * - The divisor cannot be zero.
     */
    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        return div(a, b, "SafeMath: division by zero");
    }

    /**
     * @dev Returns the integer division of two unsigned integers. Reverts with custom message on
     * division by zero. The result is rounded towards zero.
     *
     * Counterpart to Solidity's `/` operator. Note: this function uses a
     * `revert` opcode (which leaves remaining gas untouched) while Solidity
     * uses an invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     *
     * - The divisor cannot be zero.
     */
    function div(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b > 0, errorMessage);
        uint256 c = a / b;
        // assert(a == b * c + a % b); // There is no case in which this doesn't hold

        return c;
    }

    /**
     * @dev Returns the remainder of dividing two unsigned integers. (unsigned integer modulo),
     * Reverts when dividing by zero.
     *
     * Counterpart to Solidity's `%` operator. This function uses a `revert`
     * opcode (which leaves remaining gas untouched) while Solidity uses an
     * invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     *
     * - The divisor cannot be zero.
     */
    function mod(uint256 a, uint256 b) internal pure returns (uint256) {
        return mod(a, b, "SafeMath: modulo by zero");
    }

    /**
     * @dev Returns the remainder of dividing two unsigned integers. (unsigned integer modulo),
     * Reverts with custom message when dividing by zero.
     *
     * Counterpart to Solidity's `%` operator. This function uses a `revert`
     * opcode (which leaves remaining gas untouched) while Solidity uses an
     * invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     *
     * - The divisor cannot be zero.
     */
    function mod(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b != 0, errorMessage);
        return a % b;
    }
}


//SPDX-License-Identifier: MIT
pragma solidity 0.6.8;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface ISavingsCELO is IERC20 {
	function deposit() external payable returns (uint256);
	function savingsToCELO(uint256 savingsAmount) external view returns (uint256);
	function celoToSavings(uint256 celoAmount) external view returns (uint256);
}