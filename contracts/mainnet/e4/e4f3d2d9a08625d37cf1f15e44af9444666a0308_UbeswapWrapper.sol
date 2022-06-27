// SPDX-License-Identifier: ISC

//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "./IWrapper.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IUbeswapRouter {
  function swapExactTokensForTokens(
    uint256 amountIn,
    uint256 amountOutMin,
    address[] calldata path,
    address to,
    uint256 deadline
  ) external returns (uint256[] memory amounts);

  function getAmountOut(
    uint256 amountIn,
    uint256 reserveIn,
    uint256 reserveOut
  ) external pure returns (uint256 amountOut);

  function getAmountsOut(uint256 amountIn, address[] memory path)
    external
    view
    returns (uint256[] memory amounts);

  function pairFor(address tokenA, address tokenB)
    external
    view
    returns (address);
}

interface IPair {
  function token0() external view returns (address);

  function token1() external view returns (address);

  function getReserves()
    external
    view
    returns (
      uint112 _reserve0,
      uint112 _reserve1,
      uint32 _blockTimestampLast
    );
}

contract UbeswapWrapper is IWrapper, Ownable {
  IUbeswapRouter public constant ubeswap =
    IUbeswapRouter(address(0xE3D8bd6Aed4F159bc8000a9cD47CffDb95F96121));
  mapping(address => mapping(address => bool)) supportedPair;

  function _getQuote(
    address tokenIn,
    address tokenOut,
    uint256 amountIn
  ) internal view returns (uint256) {
    if (!supportedPair[tokenIn][tokenOut]) {
      return 0;
    }
    IPair pair = IPair(ubeswap.pairFor(tokenIn, tokenOut));
    (uint256 reserveIn, uint256 reserveOut, ) = pair.getReserves();
    if (tokenIn != pair.token0()) {
      uint256 temp = reserveIn;
      reserveIn = reserveOut;
      reserveOut = temp;
    }
    return ubeswap.getAmountOut(amountIn, reserveIn, reserveOut);
  }

  function getQuote(
    address tokenIn,
    address tokenOut,
    uint256 amountIn
  ) external view override returns (uint256) {
    return _getQuote(tokenIn, tokenOut, amountIn);
  }

  // function getQuotes(address tokenIn, uint256 amountIn)
  //   external
  //   view
  //   returns (uint256[] memory expectedOut, address[] memory tokensOut)
  // {
  //   tokensOut = supportedTokens;
  //   expectedOut = new uint256[](supportedTokens.length);

  //   for (uint256 i = 0; i < supportedTokens.length; i++) {
  //     address tokenOut = supportedTokens[i];
  //     if (tokenOut == tokenIn) {
  //       expectedOut[i] = 0;
  //     } else {
  //       expectedOut[i] = _getQuote(tokenIn, tokenOut, amountIn);
  //     }
  //   }
  // }

  function addTokenPair(address token1, address token2) external onlyOwner {
    supportedPair[token1][token2] = true;
    supportedPair[token2][token1] = true;
  }

  function removeTokenPair(address token1, address token2) external onlyOwner {
    supportedPair[token1][token2] = false;
    supportedPair[token2][token1] = false;
  }

  function swap(
    address tokenIn,
    address tokenOut,
    uint256 amountIn,
    uint256 minAmountOut
  ) external override returns (uint256) {
    address[] memory path = new address[](2);
    path[0] = tokenIn;
    path[1] = tokenOut;
    uint256 time = block.timestamp;
    IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);
    require(
      IERC20(tokenIn).approve(address(ubeswap), amountIn),
      "Approval failed"
    );
    uint256[] memory amounts = ubeswap.swapExactTokensForTokens(
      amountIn,
      minAmountOut,
      path,
      msg.sender,
      time + 30
    );
    return amounts[amounts.length - 1];
  }
}


// SPDX-License-Identifier: ISC

//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

interface IWrapper {
  // function getQuotes(address tokenIn, uint256 amountIn)
  //   external
  //   view
  //   returns (uint256[] memory expectedOut, address[] memory tokensOut);

  function getQuote(
    address tokenIn,
    address tokenOut,
    uint256 amountIn
  ) external view returns (uint256);

  function swap(
    address tokenIn,
    address tokenOut,
    uint256 amountIn,
    uint256 minAmountOut
  ) external returns (uint256);
}


// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/**
 * @dev Provides information about the current execution context, including the
 * sender of the transaction and its data. While these are generally available
 * via msg.sender and msg.data, they should not be accessed in such a direct
 * manner, since when dealing with meta-transactions the account sending and
 * paying for execution may not be the actual sender (as far as an application
 * is concerned).
 *
 * This contract is only required for intermediate, library-like contracts.
 */
abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        return msg.data;
    }
}


// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

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
    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool);

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

pragma solidity ^0.8.0;

import "../utils/Context.sol";

/**
 * @dev Contract module which provides a basic access control mechanism, where
 * there is an account (an owner) that can be granted exclusive access to
 * specific functions.
 *
 * By default, the owner account will be the one that deploys the contract. This
 * can later be changed with {transferOwnership}.
 *
 * This module is used through inheritance. It will make available the modifier
 * `onlyOwner`, which can be applied to your functions to restrict their use to
 * the owner.
 */
abstract contract Ownable is Context {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /**
     * @dev Initializes the contract setting the deployer as the initial owner.
     */
    constructor() {
        _setOwner(_msgSender());
    }

    /**
     * @dev Returns the address of the current owner.
     */
    function owner() public view virtual returns (address) {
        return _owner;
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        require(owner() == _msgSender(), "Ownable: caller is not the owner");
        _;
    }

    /**
     * @dev Leaves the contract without owner. It will not be possible to call
     * `onlyOwner` functions anymore. Can only be called by the current owner.
     *
     * NOTE: Renouncing ownership will leave the contract without an owner,
     * thereby removing any functionality that is only available to the owner.
     */
    function renounceOwnership() public virtual onlyOwner {
        _setOwner(address(0));
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        _setOwner(newOwner);
    }

    function _setOwner(address newOwner) private {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
}