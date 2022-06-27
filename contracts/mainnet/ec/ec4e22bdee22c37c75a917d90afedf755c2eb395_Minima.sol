// SPDX-License-Identifier: ISC

//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "./AMMs/IWrapper.sol";
import "./OpenMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract Minima is Ownable {
  using OpenMath for *;
  address[] dexs;
  address[] supportedTokens;
  mapping(address => bool) dexKnown;
  uint256 numTokens;
  uint256 fee = 5 * (10**7);
  uint256 FEE_DENOM = 10**10;

  event FeeUpdated(address owner, uint256 oldFee, uint256 newFee);
  event FeesClaimed(address owner);
  event TokenAdded(address token);
  event DexAdded(address dex, string name);
  event Swap(
    address tokenFrom,
    address tokenTo,
    uint256 amountIn,
    uint256 amountOut
  );

  function addDex(address dexAddress, string calldata name) external onlyOwner {
    require(!dexKnown[dexAddress], "DEX has alread been added");
    dexKnown[dexAddress] = true;
    dexs.push(dexAddress);
    emit DexAdded(dexAddress, name);
  }

  function addToken(address newToken) external onlyOwner {
    for (uint256 i = 0; i < supportedTokens.length; i++) {
      require(supportedTokens[i] != newToken, "Token already added");
    }
    supportedTokens.push(newToken);
    numTokens++;
    emit TokenAdded(newToken);
  }

  function updateFee(uint256 _fee) external onlyOwner {
    emit FeeUpdated(owner(), fee, _fee);
    fee = _fee;
  }

  function getFees() external onlyOwner {
    for (uint256 i = 0; i < numTokens; i++) {
      IERC20 token = IERC20(supportedTokens[i]);
      token.transfer(owner(), token.balanceOf(address(this)));
    }
    emit FeesClaimed(owner());
  }

  function getBestExchange(
    address tokenIn,
    address tokenOut,
    uint256 amountIn
  ) public view returns (int256 rate, address exchange) {
    uint256 amountOut = 0;
    for (uint256 i = 0; i < dexs.length; i++) {
      uint256 quote = IWrapper(dexs[i]).getQuote(tokenIn, tokenOut, amountIn);
      if (quote > amountOut) {
        amountOut = quote;
        exchange = dexs[i];
      }
    }
    rate = OpenMath.exchangeRate(amountIn, amountOut);
  }

  function getTokenIndex(address token) internal view returns (uint256) {
    for (uint256 i = 0; i < numTokens; i++) {
      if (address(supportedTokens[i]) == token) {
        return i;
      }
    }
    revert("Token is not supported");
  }

  function getExpectedOutFromPath(
    address[] memory tokenPath,
    address[] memory exchangePath,
    uint256 amountIn
  ) internal view returns (uint256 expectedOut) {
    require(tokenPath.length > 1, "Path must contain atleast two tokens");
    require(
      exchangePath.length == tokenPath.length - 1,
      "Exchange path incorrect length"
    );

    expectedOut = amountIn;
    for (uint256 i = 0; i < exchangePath.length; i++) {
      expectedOut = IWrapper(exchangePath[i]).getQuote(
        tokenPath[i],
        tokenPath[i + 1],
        expectedOut
      );
    }
  }

  function getExpectedOut(
    address tokenIn,
    address tokenOut,
    uint256 amountIn
  )
    external
    view
    returns (
      uint256 amountOut,
      address[] memory tokenPath,
      address[] memory exchangePath
    )
  {
    uint256 tokenFromIndex = getTokenIndex(tokenIn);
    uint256 tokenOutIndex = getTokenIndex(tokenOut);

    (
      int256[][] memory exchangeRates,
      address[][] memory exchanges,
      int256[] memory pathTo,
      uint256[] memory parents,
      bool arbExists
    ) = fillBoard(tokenFromIndex);

    (
      address[] memory tokenPath,
      address[] memory exchangePath
    ) = getPathFromBoard(
        tokenFromIndex,
        tokenOutIndex,
        exchangeRates,
        exchanges,
        pathTo,
        parents
      );
    amountOut = getExpectedOutFromPath(tokenPath, exchangePath, amountIn);
  }

  function fillBoard(uint256 tokenFromIndex)
    public
    view
    returns (
      int256[][] memory exchangeRates,
      address[][] memory exchanges,
      int256[] memory pathTo,
      uint256[] memory parents,
      bool arbExists
    )
  {
    exchangeRates = new int256[][](numTokens);
    exchanges = new address[][](numTokens);
    pathTo = new int256[](numTokens);
    parents = new uint256[](numTokens);

    for (uint256 i = 0; i < numTokens; i++) {
      pathTo[i] = OpenMath.MAX_INT;
      exchangeRates[i] = new int256[](numTokens);
      exchanges[i] = new address[](numTokens);
      if (i == tokenFromIndex) {
        pathTo[i] = 0;
      }
      for (uint256 i = 0; i < numTokens; i++) {
        ERC20 tokenIn = ERC20(supportedTokens[i]);
        for (uint256 j = 0; j < numTokens; j++) {
          (int256 rate, address exchange) = getBestExchange(
            address(tokenIn),
            supportedTokens[j],
            10**tokenIn.decimals()
          );
          exchanges[i][j] = exchange;
          exchangeRates[i][j] = OpenMath.log2(-1 * rate);
        }
      }
    }

    {
      bool improved = true;
      uint256 iteration = 0;
      while (iteration < numTokens && improved) {
        improved = false;
        iteration++;
        for (uint256 i = 0; i < numTokens; i++) {
          int256 curCost = pathTo[i];
          for (uint256 j = 0; j < numTokens; j++) {
            if (curCost + exchangeRates[i][j] < pathTo[j]) {
              pathTo[j] = curCost + exchangeRates[i][j];
              improved = true;
              parents[j] = i;
            }
          }
        }
        if (iteration == numTokens) {
          arbExists = improved;
        }
      }
    }
  }

  function getPathFromBoard(
    uint256 tokenFromIndex,
    uint256 tokenOutIndex,
    int256[][] memory exchangeRates,
    address[][] memory exchanges,
    int256[] memory pathTo,
    uint256[] memory parents
  )
    public
    view
    returns (address[] memory tokenPath, address[] memory exchangePath)
  {
    tokenPath = new address[](numTokens);
    exchangePath = new address[](numTokens);
    uint256 curIndex = tokenOutIndex;
    uint256 iterations = 0;

    while (curIndex != tokenFromIndex) {
      require(iterations < numTokens, "No path exists");
      uint256 parent = parents[curIndex];
      tokenPath[iterations] = supportedTokens[curIndex];
      exchangePath[iterations++] = exchanges[parent][curIndex];
      curIndex = parent;
    }
    tokenPath[iterations++] = supportedTokens[tokenFromIndex];
    for (uint256 i = 0; i <= iterations / 2; i++) {
      address tmp = tokenPath[i];
      tokenPath[i] = tokenPath[tokenPath.length - i];
      tokenPath[tokenPath.length - i] = tmp;
      if (i <= exchangePath.length / 2) {
        tmp = exchangePath[i];
        exchangePath[i] = exchangePath[exchangePath.length - i];
        exchangePath[exchangePath.length - i] = tmp;
      }
    }
  }

  function swap(
    address[] memory tokenPath,
    address[] memory exchangePath,
    uint256 amountIn,
    uint256 minAmountOut,
    address recipient
  ) public returns (uint256 actualAmountOut) {
    require(tokenPath.length > 1, "Path must contain atleast two tokens");
    require(
      exchangePath.length == tokenPath.length - 1,
      "Exchange path incorrect length"
    );
    IERC20 inputToken = IERC20(tokenPath[0]);
    require(
      inputToken.transferFrom(msg.sender, address(this), amountIn),
      "Transfer failed"
    );
    actualAmountOut = amountIn;
    for (uint256 i = 0; i < exchangePath.length; i++) {
      inputToken = IERC20(tokenPath[i]);
      IERC20 outToken = IERC20(tokenPath[i + 1]);
      uint256 startingBalance = outToken.balanceOf(address(this));
      address exchange = exchangePath[i];
      require(inputToken.approve(exchange, actualAmountOut), "Approval failed");

      IWrapper(exchange).swap(
        address(inputToken),
        address(outToken),
        actualAmountOut,
        0
      );
      actualAmountOut = outToken.balanceOf(address(this)) - startingBalance;
    }
    uint256 swapFee = (actualAmountOut * fee) / FEE_DENOM;
    actualAmountOut -= swapFee;

    require(actualAmountOut >= minAmountOut, "Slippage was too high");
    IERC20(tokenPath[tokenPath.length - 1]).transfer(
      recipient,
      actualAmountOut
    );
    emit Swap(
      tokenPath[0],
      tokenPath[tokenPath.length - 1],
      amountIn,
      actualAmountOut
    );
  }

  function swapOnChain(
    address tokenIn,
    address tokenOut,
    uint256 amountIn,
    uint256 minAmountOut,
    address recipient
  ) external returns (uint256) {
    uint256 tokenFromIndex = getTokenIndex(tokenIn);
    uint256 tokenOutIndex = getTokenIndex(tokenOut);

    (
      int256[][] memory exchangeRates,
      address[][] memory exchanges,
      int256[] memory pathTo,
      uint256[] memory parents,

    ) = fillBoard(tokenFromIndex);

    (
      address[] memory tokenPath,
      address[] memory exchangePath
    ) = getPathFromBoard(
        tokenFromIndex,
        tokenOutIndex,
        exchangeRates,
        exchanges,
        pathTo,
        parents
      );
    return swap(tokenPath, exchangePath, amountIn, minAmountOut, recipient);
  }
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

import "../IERC20.sol";

/**
 * @dev Interface for the optional metadata functions from the ERC20 standard.
 *
 * _Available since v4.1._
 */
interface IERC20Metadata is IERC20 {
    /**
     * @dev Returns the name of the token.
     */
    function name() external view returns (string memory);

    /**
     * @dev Returns the symbol of the token.
     */
    function symbol() external view returns (string memory);

    /**
     * @dev Returns the decimals places of the token.
     */
    function decimals() external view returns (uint8);
}


// SPDX-License-Identifier: ISC

//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

library OpenMath {
  uint256 constant MAX_UINT = 2**256 - 1;
  uint256 constant DECIMALS_UINT = 10**18;
  int256 constant DECIMALS_SIGNED = 10**18;
  int256 constant MAX_INT = 2**255 - 1;
  uint256 internal constant HALF_SCALE = 5e17;

  /// @dev How many trailing decimals can be represented.
  int256 internal constant SCALE = 1e18;

  /// @notice Finds the zero-based index of the first one in the binary representation of x.
  /// @dev See the note on msb in the "Find First Set" Wikipedia article https://en.wikipedia.org/wiki/Find_first_set
  /// @param x The uint256 number for which to find the index of the most significant bit.
  /// @return msb The index of the most significant bit as an uint256.
  function mostSignificantBit(uint256 x) internal pure returns (uint256 msb) {
    if (x >= 2**128) {
      x >>= 128;
      msb += 128;
    }
    if (x >= 2**64) {
      x >>= 64;
      msb += 64;
    }
    if (x >= 2**32) {
      x >>= 32;
      msb += 32;
    }
    if (x >= 2**16) {
      x >>= 16;
      msb += 16;
    }
    if (x >= 2**8) {
      x >>= 8;
      msb += 8;
    }
    if (x >= 2**4) {
      x >>= 4;
      msb += 4;
    }
    if (x >= 2**2) {
      x >>= 2;
      msb += 2;
    }
    if (x >= 2**1) {
      // No need to shift x any more.
      msb += 1;
    }
  }

  /// @notice Calculates the binary logarithm of x.
  ///
  /// @dev Based on the iterative approximation algorithm.
  /// https://en.wikipedia.org/wiki/Binary_logarithm#Iterative_approximation
  ///
  /// Requirements:
  /// - x must be greater than zero.
  ///
  /// Caveats:
  /// - The results are nor perfectly accurate to the last digit, due to the lossy precision of the iterative approximation.
  ///
  /// @param x The signed 59.18-decimal fixed-point number for which to calculate the binary logarithm.
  /// @return result The binary logarithm as a signed 59.18-decimal fixed-point number.
  function log2(int256 x) internal pure returns (int256 result) {
    require(x > 0);
    unchecked {
      // This works because log2(x) = -log2(1/x).
      int256 sign;
      if (x >= SCALE) {
        sign = 1;
      } else {
        sign = -1;
        // Do the fixed-point inversion inline to save gas. The numerator is SCALE * SCALE.
        assembly {
          x := div(1000000000000000000000000000000000000, x)
        }
      }

      // Calculate the integer part of the logarithm and add it to the result and finally calculate y = x * 2^(-n).
      uint256 n = mostSignificantBit(uint256(x / SCALE));

      // The integer part of the logarithm as a signed 59.18-decimal fixed-point number. The operation can't overflow
      // because n is maximum 255, SCALE is 1e18 and sign is either 1 or -1.
      result = int256(n) * SCALE;

      // This is y = x * 2^(-n).
      int256 y = x >> n;

      // If y = 1, the fractional part is zero.
      if (y == SCALE) {
        return result * sign;
      }

      // Calculate the fractional part via the iterative approximation.
      // The "delta >>= 1" part is equivalent to "delta /= 2", but shifting bits is faster.
      for (int256 delta = int256(HALF_SCALE); delta > 0; delta >>= 1) {
        y = (y * y) / SCALE;

        // Is y^2 > 2 and so in the range [2,4)?
        if (y >= 2 * SCALE) {
          // Add the 2^(-m) factor to the logarithm.
          result += delta;

          // Corresponds to z/2 on Wikipedia.
          y >>= 1;
        }
      }
      result *= sign;
    }
  }

  function safeUnsignedToSigned(uint256 unsigned) public pure returns (int256) {
    require(
      unsigned < uint256(2**256 - 1),
      "Unsigned integer is too large, conversion will result in a negative number"
    );
    return int256(unsigned);
  }

  // Returns exchange rate as a 59.18 decimal integer
  function exchangeRate(uint256 amountIn, uint256 amountOut)
    public
    pure
    returns (int256 exchange)
  {
    int256 numerator = safeUnsignedToSigned(amountIn);
    int256 denominator = safeUnsignedToSigned(amountOut);

    exchange = (numerator * DECIMALS_SIGNED) / denominator;
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

import "./IERC20.sol";
import "./extensions/IERC20Metadata.sol";
import "../../utils/Context.sol";

/**
 * @dev Implementation of the {IERC20} interface.
 *
 * This implementation is agnostic to the way tokens are created. This means
 * that a supply mechanism has to be added in a derived contract using {_mint}.
 * For a generic mechanism see {ERC20PresetMinterPauser}.
 *
 * TIP: For a detailed writeup see our guide
 * https://forum.zeppelin.solutions/t/how-to-implement-erc20-supply-mechanisms/226[How
 * to implement supply mechanisms].
 *
 * We have followed general OpenZeppelin Contracts guidelines: functions revert
 * instead returning `false` on failure. This behavior is nonetheless
 * conventional and does not conflict with the expectations of ERC20
 * applications.
 *
 * Additionally, an {Approval} event is emitted on calls to {transferFrom}.
 * This allows applications to reconstruct the allowance for all accounts just
 * by listening to said events. Other implementations of the EIP may not emit
 * these events, as it isn't required by the specification.
 *
 * Finally, the non-standard {decreaseAllowance} and {increaseAllowance}
 * functions have been added to mitigate the well-known issues around setting
 * allowances. See {IERC20-approve}.
 */
contract ERC20 is Context, IERC20, IERC20Metadata {
    mapping(address => uint256) private _balances;

    mapping(address => mapping(address => uint256)) private _allowances;

    uint256 private _totalSupply;

    string private _name;
    string private _symbol;

    /**
     * @dev Sets the values for {name} and {symbol}.
     *
     * The default value of {decimals} is 18. To select a different value for
     * {decimals} you should overload it.
     *
     * All two of these values are immutable: they can only be set once during
     * construction.
     */
    constructor(string memory name_, string memory symbol_) {
        _name = name_;
        _symbol = symbol_;
    }

    /**
     * @dev Returns the name of the token.
     */
    function name() public view virtual override returns (string memory) {
        return _name;
    }

    /**
     * @dev Returns the symbol of the token, usually a shorter version of the
     * name.
     */
    function symbol() public view virtual override returns (string memory) {
        return _symbol;
    }

    /**
     * @dev Returns the number of decimals used to get its user representation.
     * For example, if `decimals` equals `2`, a balance of `505` tokens should
     * be displayed to a user as `5.05` (`505 / 10 ** 2`).
     *
     * Tokens usually opt for a value of 18, imitating the relationship between
     * Ether and Wei. This is the value {ERC20} uses, unless this function is
     * overridden;
     *
     * NOTE: This information is only used for _display_ purposes: it in
     * no way affects any of the arithmetic of the contract, including
     * {IERC20-balanceOf} and {IERC20-transfer}.
     */
    function decimals() public view virtual override returns (uint8) {
        return 18;
    }

    /**
     * @dev See {IERC20-totalSupply}.
     */
    function totalSupply() public view virtual override returns (uint256) {
        return _totalSupply;
    }

    /**
     * @dev See {IERC20-balanceOf}.
     */
    function balanceOf(address account) public view virtual override returns (uint256) {
        return _balances[account];
    }

    /**
     * @dev See {IERC20-transfer}.
     *
     * Requirements:
     *
     * - `recipient` cannot be the zero address.
     * - the caller must have a balance of at least `amount`.
     */
    function transfer(address recipient, uint256 amount) public virtual override returns (bool) {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    /**
     * @dev See {IERC20-allowance}.
     */
    function allowance(address owner, address spender) public view virtual override returns (uint256) {
        return _allowances[owner][spender];
    }

    /**
     * @dev See {IERC20-approve}.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     */
    function approve(address spender, uint256 amount) public virtual override returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    /**
     * @dev See {IERC20-transferFrom}.
     *
     * Emits an {Approval} event indicating the updated allowance. This is not
     * required by the EIP. See the note at the beginning of {ERC20}.
     *
     * Requirements:
     *
     * - `sender` and `recipient` cannot be the zero address.
     * - `sender` must have a balance of at least `amount`.
     * - the caller must have allowance for ``sender``'s tokens of at least
     * `amount`.
     */
    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public virtual override returns (bool) {
        _transfer(sender, recipient, amount);

        uint256 currentAllowance = _allowances[sender][_msgSender()];
        require(currentAllowance >= amount, "ERC20: transfer amount exceeds allowance");
        unchecked {
            _approve(sender, _msgSender(), currentAllowance - amount);
        }

        return true;
    }

    /**
     * @dev Atomically increases the allowance granted to `spender` by the caller.
     *
     * This is an alternative to {approve} that can be used as a mitigation for
     * problems described in {IERC20-approve}.
     *
     * Emits an {Approval} event indicating the updated allowance.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     */
    function increaseAllowance(address spender, uint256 addedValue) public virtual returns (bool) {
        _approve(_msgSender(), spender, _allowances[_msgSender()][spender] + addedValue);
        return true;
    }

    /**
     * @dev Atomically decreases the allowance granted to `spender` by the caller.
     *
     * This is an alternative to {approve} that can be used as a mitigation for
     * problems described in {IERC20-approve}.
     *
     * Emits an {Approval} event indicating the updated allowance.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     * - `spender` must have allowance for the caller of at least
     * `subtractedValue`.
     */
    function decreaseAllowance(address spender, uint256 subtractedValue) public virtual returns (bool) {
        uint256 currentAllowance = _allowances[_msgSender()][spender];
        require(currentAllowance >= subtractedValue, "ERC20: decreased allowance below zero");
        unchecked {
            _approve(_msgSender(), spender, currentAllowance - subtractedValue);
        }

        return true;
    }

    /**
     * @dev Moves `amount` of tokens from `sender` to `recipient`.
     *
     * This internal function is equivalent to {transfer}, and can be used to
     * e.g. implement automatic token fees, slashing mechanisms, etc.
     *
     * Emits a {Transfer} event.
     *
     * Requirements:
     *
     * - `sender` cannot be the zero address.
     * - `recipient` cannot be the zero address.
     * - `sender` must have a balance of at least `amount`.
     */
    function _transfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal virtual {
        require(sender != address(0), "ERC20: transfer from the zero address");
        require(recipient != address(0), "ERC20: transfer to the zero address");

        _beforeTokenTransfer(sender, recipient, amount);

        uint256 senderBalance = _balances[sender];
        require(senderBalance >= amount, "ERC20: transfer amount exceeds balance");
        unchecked {
            _balances[sender] = senderBalance - amount;
        }
        _balances[recipient] += amount;

        emit Transfer(sender, recipient, amount);

        _afterTokenTransfer(sender, recipient, amount);
    }

    /** @dev Creates `amount` tokens and assigns them to `account`, increasing
     * the total supply.
     *
     * Emits a {Transfer} event with `from` set to the zero address.
     *
     * Requirements:
     *
     * - `account` cannot be the zero address.
     */
    function _mint(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: mint to the zero address");

        _beforeTokenTransfer(address(0), account, amount);

        _totalSupply += amount;
        _balances[account] += amount;
        emit Transfer(address(0), account, amount);

        _afterTokenTransfer(address(0), account, amount);
    }

    /**
     * @dev Destroys `amount` tokens from `account`, reducing the
     * total supply.
     *
     * Emits a {Transfer} event with `to` set to the zero address.
     *
     * Requirements:
     *
     * - `account` cannot be the zero address.
     * - `account` must have at least `amount` tokens.
     */
    function _burn(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: burn from the zero address");

        _beforeTokenTransfer(account, address(0), amount);

        uint256 accountBalance = _balances[account];
        require(accountBalance >= amount, "ERC20: burn amount exceeds balance");
        unchecked {
            _balances[account] = accountBalance - amount;
        }
        _totalSupply -= amount;

        emit Transfer(account, address(0), amount);

        _afterTokenTransfer(account, address(0), amount);
    }

    /**
     * @dev Sets `amount` as the allowance of `spender` over the `owner` s tokens.
     *
     * This internal function is equivalent to `approve`, and can be used to
     * e.g. set automatic allowances for certain subsystems, etc.
     *
     * Emits an {Approval} event.
     *
     * Requirements:
     *
     * - `owner` cannot be the zero address.
     * - `spender` cannot be the zero address.
     */
    function _approve(
        address owner,
        address spender,
        uint256 amount
    ) internal virtual {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    /**
     * @dev Hook that is called before any transfer of tokens. This includes
     * minting and burning.
     *
     * Calling conditions:
     *
     * - when `from` and `to` are both non-zero, `amount` of ``from``'s tokens
     * will be transferred to `to`.
     * - when `from` is zero, `amount` tokens will be minted for `to`.
     * - when `to` is zero, `amount` of ``from``'s tokens will be burned.
     * - `from` and `to` are never both zero.
     *
     * To learn more about hooks, head to xref:ROOT:extending-contracts.adoc#using-hooks[Using Hooks].
     */
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual {}

    /**
     * @dev Hook that is called after any transfer of tokens. This includes
     * minting and burning.
     *
     * Calling conditions:
     *
     * - when `from` and `to` are both non-zero, `amount` of ``from``'s tokens
     * has been transferred to `to`.
     * - when `from` is zero, `amount` tokens have been minted for `to`.
     * - when `to` is zero, `amount` of ``from``'s tokens have been burned.
     * - `from` and `to` are never both zero.
     *
     * To learn more about hooks, head to xref:ROOT:extending-contracts.adoc#using-hooks[Using Hooks].
     */
    function _afterTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual {}
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