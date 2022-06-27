// SPDX-License-Identifier: ISC

//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "./IWrapper.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface ISwap {
  function getTokenIndex(address tokenAddress) external view returns (uint8);

  function getToken(uint8 index) external view returns (address);

  function calculateSwap(
    uint8 tokenIndexFrom,
    uint8 tokenIndexTo,
    uint256 dx
  ) external view returns (uint256);

  function swap(
    uint8 tokenIndexFrom,
    uint8 tokenIndexTo,
    uint256 dx,
    uint256 minDy,
    uint256 deadline
  ) external returns (uint256);
}

contract MobiusWrapper is IWrapper, Ownable {
  mapping(address => mapping(address => address)) public tokenRoute; // token in => token out => swap address
  mapping(address => bool) public swapContained;

  function addSwapContract(address swapAddress, uint256 numTokens)
    public
    onlyOwner
    returns (bool)
  {
    if (swapContained[swapAddress]) return false;

    swapContained[swapAddress] = true;

    ISwap swap = ISwap(swapAddress);
    address[] memory tokens = new address[](numTokens);
    for (uint256 i = 0; i < numTokens; i++) {
      tokens[i] = swap.getToken(uint8(i));
    }

    // This is technically quadratic, but the number of tokens for a swap contract will *hopefully*
    // be around 2 or 3
    for (uint256 i = 0; i < numTokens; i++) {
      address token_i = tokens[i];
      for (uint256 j = 0; j < numTokens; j++) {
        if (j != i) {
          address token_j = tokens[j];
          tokenRoute[token_i][token_j] = swapAddress;
        }
      }
    }
    return true;
  }

  function addMultipleSwapContracts(
    address[] calldata contracts,
    uint256[] calldata numTokens
  ) external onlyOwner {
    require(contracts.length == numTokens.length, "Array lengths vary");
    for (uint256 i = 0; i < contracts.length; i++) {
      addSwapContract(contracts[i], numTokens[i]);
    }
  }

  function getTradeIndices(address tokenFrom, address tokenTo)
    public
    view
    returns (
      uint256 tokenIndexFrom,
      uint256 tokenIndexTo,
      address swapAddress
    )
  {
    swapAddress = tokenRoute[tokenFrom][tokenTo];
    tokenIndexFrom = 0;
    tokenIndexTo = 0;
    if (swapAddress != address(0)) {
      ISwap swap = ISwap(swapAddress);
      tokenIndexFrom = swap.getTokenIndex(tokenFrom);
      tokenIndexTo = swap.getTokenIndex(tokenTo);
    }
  }

  function _getQuote(
    uint256 tokenIndexFrom,
    uint256 tokenIndexTo,
    uint256 amountIn,
    address swapAddress
  ) internal view returns (uint256) {
    ISwap swap = ISwap(swapAddress);
    return
      swap.calculateSwap(uint8(tokenIndexFrom), uint8(tokenIndexTo), amountIn);
  }

  function getQuote(
    address tokenIn,
    address tokenOut,
    uint256 amountIn
  ) external view override returns (uint256) {
    (
      uint256 tokenIndexFrom,
      uint256 tokenIndexTo,
      address swapAddress
    ) = getTradeIndices(tokenIn, tokenOut);
    if (swapAddress == address(0)) {
      return 0; // Or => OpenMath.MAX_UINT;
    }
    return _getQuote(tokenIndexFrom, tokenIndexTo, amountIn, swapAddress);
  }

  function swap(
    address tokenIn,
    address tokenOut,
    uint256 amountIn,
    uint256 minAmountOut
  ) external override returns (uint256) {
    (
      uint256 tokenIndexFrom,
      uint256 tokenIndexTo,
      address swapAddress
    ) = getTradeIndices(tokenIn, tokenOut);
    require(swapAddress != address(0), "Swap contract does not exist");
    ISwap swap = ISwap(swapAddress);
    uint256 time = block.timestamp;

    IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);
    require(IERC20(tokenIn).approve(swapAddress, amountIn), "Approval failed");

    uint256 actualAmountOut = swap.swap(
      uint8(tokenIndexFrom),
      uint8(tokenIndexTo),
      amountIn,
      minAmountOut,
      time + 30
    );
    IERC20(tokenOut).transfer(msg.sender, actualAmountOut);
    return actualAmountOut;
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