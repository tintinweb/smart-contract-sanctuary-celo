// SPDX-License-Identifier: ISC
pragma solidity ^0.8.0;

import "./MobiusBaseBurner.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MobiusEthBurner is MobiusBaseBurner {
  IERC20 constant WETH = IERC20(0x122013fd7dF1C6F636a5bb8f03108E876548b455);

  constructor(
    address _emergencyOwner,
    address _receiver,
    address _recoveryReceiver,
    IWrapper _mobiusWrapper,
    Minima _router
  )
    MobiusBaseBurner(
      _emergencyOwner,
      _receiver,
      _recoveryReceiver,
      _mobiusWrapper,
      _router,
      WETH
    )
  {}
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

  // 2^127.
  uint128 private constant TWO127 = 0x80000000000000000000000000000000;

  // 2^128 - 1
  uint128 private constant TWO128_1 = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;

  // ln(2) * 2^128
  uint128 private constant LN2 = 0xb17217f7d1cf79abc9e3b39803f2f6af;

  /**
   * Return index of most significant non-zero bit in given non-zero 256-bit
   * unsigned integer value.
   *
   * @param _x value to get index of most significant non-zero bit in
   * @return r index of most significant non-zero bit in given number
   */
  function mostSignificantBit(uint256 _x) internal pure returns (uint8 r) {
    require(_x > 0);

    uint256 x = _x;
    r = 0;
    if (x >= 0x100000000000000000000000000000000) {
      x >>= 128;
      r += 128;
    }
    if (x >= 0x10000000000000000) {
      x >>= 64;
      r += 64;
    }
    if (x >= 0x100000000) {
      x >>= 32;
      r += 32;
    }
    if (x >= 0x10000) {
      x >>= 16;
      r += 16;
    }
    if (x >= 0x100) {
      x >>= 8;
      r += 8;
    }
    if (x >= 0x10) {
      x >>= 4;
      r += 4;
    }
    if (x >= 0x4) {
      x >>= 2;
      r += 2;
    }
    if (x >= 0x2) r += 1; // No need to shift x anymore
  }

  /*
function mostSignificantBit (uint256 x) pure internal returns (uint8) {
  require (x > 0);

  uint8 l = 0;
  uint8 h = 255;

  while (h > l) {
    uint8 m = uint8 ((uint16 (l) + uint16 (h)) >> 1);
    uint256 t = x >> m;
    if (t == 0) h = m - 1;
    else if (t > 1) l = m + 1;
    else return m;
  }

  return h;
}
*/

  /**
   * Calculate log_2 (x / 2^128) * 2^128.
   *
   * @param _x parameter value
   * @return log_2 (x / 2^128) * 2^128
   */
  function log_2(uint256 _x) internal pure returns (int256) {
    require(_x > 0, "Must be a positive number");
    uint256 x = _x;
    uint8 msb = mostSignificantBit(x);
    if (msb > 128) x >>= msb - 128;
    else if (msb < 128) x <<= 128 - msb;

    x &= TWO128_1;

    int256 result = (int256(msb) - 128) << 128; // Integer part of log_2

    int256 bit = TWO127;
    for (uint8 i = 0; i < 128 && x > 0; i++) {
      x = (x << 1) + ((x * x + TWO127) >> 128);
      if (x > TWO128_1) {
        result |= bit;
        x = (x >> 1) - TWO127;
      }
      bit >>= 1;
    }

    return result;
  }

  // Returns exchange rate as a 59.18 decimal integer
  function exchangeRate(uint256 amountIn, uint256 amountOut)
    public
    pure
    returns (uint256 exchange)
  {
    exchange = (amountOut * DECIMALS_UINT) / amountIn;
  }
}


// SPDX-License-Identifier: ISC

pragma solidity ^0.8.0;

import "./AMMs/IWrapper.sol";
import "./Minima.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract MobiusBaseBurner is Ownable {
  using SafeERC20 for IERC20;

  IERC20 baseToken;
  IERC20 constant MOBI = IERC20(0x73a210637f6F6B7005512677Ba6B3C96bb4AA44B);
  uint256 constant MAX_UINT = 2**256 - 1;

  IWrapper public MobiusWrapper;
  Minima public MinimaRouter;
  mapping(address => mapping(address => bool)) isApproved;

  address public emergencyOwner;
  address public receiver;
  address public recoveryReceiver;
  bool public is_killed;

  constructor(
    address _emergencyOwner,
    address _receiver,
    address _recoveryReceiver,
    IWrapper _mobiusWrapper,
    Minima _router,
    IERC20 _baseToken
  ) Ownable() {
    emergencyOwner = _emergencyOwner;
    receiver = _receiver;
    recoveryReceiver = _recoveryReceiver;
    MobiusWrapper = _mobiusWrapper;
    MinimaRouter = _router;
    baseToken = _baseToken;

    // Set max approval to the Minima Router for baseToken
    baseToken.safeApprove(address(_router), MAX_UINT);
  }

  modifier isLive() {
    require(!is_killed, "Burner is paused");
    _;
  }

  modifier ownerOrEmergency() {
    require(
      msg.sender == owner() || msg.sender == emergencyOwner,
      "Only owner"
    );
    _;
  }

  function burn(IERC20 coin) external isLive returns (bool) {
    uint256 amount = coin.balanceOf(msg.sender);
    uint256 amountBase;
    if (amount == 0) return false;

    coin.safeTransferFrom(msg.sender, address(this), amount);

    // If the token is not baseToken, then first swap into baseToken through the Mobius pools
    if (address(coin) != address(baseToken)) {
      if (!isApproved[address(coin)][address(MobiusWrapper)]) {
        coin.safeApprove(address(MobiusWrapper), MAX_UINT);
        isApproved[address(coin)][address(MobiusWrapper)] = true;
      }
      MobiusWrapper.swap(address(coin), address(baseToken), amount, 0);
    }

    MinimaRouter.swapOnChain(
      address(baseToken),
      address(MOBI),
      baseToken.balanceOf(address(this)),
      0,
      address(this)
    );

    MOBI.safeTransfer(receiver, MOBI.balanceOf(address(this)));
    return true;
  }

  function setMobiusWrapper(address wrapper) external ownerOrEmergency {
    MobiusWrapper = IWrapper(wrapper);
  }

  function setMinima(address minimaAddress) external ownerOrEmergency {
    MinimaRouter = Minima(minimaAddress);
    baseToken.approve(minimaAddress, MAX_UINT);
  }

  function recover_balance(IERC20 coin)
    external
    ownerOrEmergency
    returns (bool)
  {
    coin.transfer(recoveryReceiver, coin.balanceOf(address(this)));
    return true;
  }

  function setRecovery(address newRecovery) external onlyOwner {
    recoveryReceiver = newRecovery;
  }

  function setReciever(address newReciever) external onlyOwner {
    receiver = newReciever;
  }

  function setKilled(bool isKilled) external ownerOrEmergency {
    is_killed = true;
  }

  function setEmergencyOwner(address newEmergencyOwner)
    external
    ownerOrEmergency
  {
    emergencyOwner = newEmergencyOwner;
  }
}


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
  address[] public dexs;
  address[] public supportedTokens;
  mapping(address => bool) public dexKnown;
  uint256 public numTokens;

  event TokenAdded(address token);
  event DexAdded(address dex, string name);
  event Swap(
    address tokenFrom,
    address tokenTo,
    uint256 amountIn,
    uint256 amountOut
  );

  constructor(address[] memory initialTokens, address[] memory initialDexes) {
    for (uint256 i = 0; i < initialTokens.length; i++) {
      supportedTokens.push(initialTokens[i]);
      numTokens++;
    }
    for (uint256 i = 0; i < initialDexes.length; i++) {
      dexKnown[initialDexes[i]] = true;
      dexs.push(initialDexes[i]);
    }
  }

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

  function getBestExchange(
    address tokenIn,
    address tokenOut,
    uint256 amountIn
  ) public view returns (uint256 rate, address exchange) {
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
    revert("Token not supported");
  }

  function getExpectedOutFromPath(
    address[] memory tokenPath,
    address[] memory exchangePath,
    uint256 amountIn
  ) public view returns (uint256 expectedOut) {
    require(tokenPath.length > 1, "Path must contain atleast two tokens");
    require(
      exchangePath.length == tokenPath.length - 1,
      "Exchange path incorrect length"
    );

    expectedOut = amountIn;
    uint256 i = 0;
    while (i < exchangePath.length && exchangePath[i] != address(0)) {
      expectedOut = IWrapper(exchangePath[i]).getQuote(
        tokenPath[i],
        tokenPath[++i],
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
      address[][] memory exchanges,
      uint256[] memory parents,
      bool arbExists
    ) = fillBoard(tokenFromIndex);
    (
      address[] memory _tokenPath,
      address[] memory _exchangePath
    ) = getPathFromBoard(tokenFromIndex, tokenOutIndex, exchanges, parents);
    tokenPath = _tokenPath;
    exchangePath = _exchangePath;
    amountOut = getExpectedOutFromPath(tokenPath, exchangePath, amountIn);
  }

  function fillBoard(uint256 tokenFromIndex)
    public
    view
    returns (
      address[][] memory exchanges,
      uint256[] memory parents,
      bool arbExists
    )
  {
    int256[][] memory exchangeRates = new int256[][](numTokens);
    int256[] memory pathTo = new int256[](numTokens);
    exchanges = new address[][](numTokens);
    parents = new uint256[](numTokens);

    for (uint256 i = 0; i < numTokens; i++) {
      pathTo[i] = OpenMath.MAX_INT;
      exchangeRates[i] = new int256[](numTokens);
      exchanges[i] = new address[](numTokens);
      if (i == tokenFromIndex) {
        pathTo[i] = 0;
      }
      ERC20 tokenIn = ERC20(supportedTokens[i]);
      uint256 decimals = 10**tokenIn.decimals();
      for (uint256 j = 0; j < numTokens; j++) {
        (uint256 rate, address exchange) = getBestExchange(
          supportedTokens[i],
          supportedTokens[j],
          100 * decimals
        );
        exchanges[i][j] = exchange;
        exchangeRates[i][j] = rate == 0
          ? OpenMath.MAX_INT
          : -1 * OpenMath.log_2(rate);
      }
    }

    uint256 iteration = 0;
    {
      bool improved = true;
      while (iteration < numTokens && improved) {
        improved = false;
        iteration++;
        for (uint256 i = 0; i < numTokens; i++) {
          int256 curCost = pathTo[i];
          if (curCost != OpenMath.MAX_INT) {
            for (uint256 j = 0; j < numTokens; j++) {
              if (
                exchangeRates[i][j] < OpenMath.MAX_INT &&
                curCost + exchangeRates[i][j] < pathTo[j]
              ) {
                pathTo[j] = curCost + exchangeRates[i][j];
                improved = true;
                parents[j] = i;
              }
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
    address[][] memory exchanges,
    uint256[] memory parents
  )
    public
    view
    returns (address[] memory tokenPath, address[] memory exchangePath)
  {
    address[] memory backPath = new address[](numTokens);
    address[] memory backExchPath = new address[](numTokens - 1);
    tokenPath = new address[](numTokens);
    exchangePath = new address[](numTokens - 1);
    uint256 curIndex = tokenOutIndex;
    uint256 iterations = 0;

    while (curIndex != tokenFromIndex) {
      require(iterations < numTokens, "No path exists");
      uint256 parent = parents[curIndex];
      backPath[iterations] = supportedTokens[curIndex];
      backExchPath[iterations++] = exchanges[parent][curIndex];
      curIndex = parent;
    }

    tokenPath[0] = supportedTokens[tokenFromIndex];
    for (uint256 i = 1; i <= iterations; i++) {
      tokenPath[i] = backPath[iterations - i];
      exchangePath[i - 1] = backExchPath[iterations - i];
    }
  }

  // To do - add check for 0x0 address in exchangePath
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
    uint256 i = 0;
    while (i < exchangePath.length && exchangePath[i] != address(0)) {
      address exchange = exchangePath[i];
      inputToken = IERC20(tokenPath[i]);
      IERC20 outToken = IERC20(tokenPath[++i]);
      uint256 startingBalance = outToken.balanceOf(address(this));
      require(inputToken.approve(exchange, actualAmountOut), "Approval failed");

      IWrapper(exchange).swap(
        address(inputToken),
        address(outToken),
        actualAmountOut,
        0
      );
      actualAmountOut = outToken.balanceOf(address(this)) - startingBalance;
    }

    require(actualAmountOut >= minAmountOut, "Slippage was too high");
    IERC20(tokenPath[i]).transfer(recipient, actualAmountOut);
    emit Swap(tokenPath[0], tokenPath[i], amountIn, actualAmountOut);
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

    (address[][] memory exchanges, uint256[] memory parents, ) = fillBoard(
      tokenFromIndex
    );

    (
      address[] memory tokenPath,
      address[] memory exchangePath
    ) = getPathFromBoard(tokenFromIndex, tokenOutIndex, exchanges, parents);
    return swap(tokenPath, exchangePath, amountIn, minAmountOut, recipient);
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
 * @dev Collection of functions related to the address type
 */
library Address {
    /**
     * @dev Returns true if `account` is a contract.
     *
     * [IMPORTANT]
     * ====
     * It is unsafe to assume that an address for which this function returns
     * false is an externally-owned account (EOA) and not a contract.
     *
     * Among others, `isContract` will return false for the following
     * types of addresses:
     *
     *  - an externally-owned account
     *  - a contract in construction
     *  - an address where a contract will be created
     *  - an address where a contract lived, but was destroyed
     * ====
     */
    function isContract(address account) internal view returns (bool) {
        // This method relies on extcodesize, which returns 0 for contracts in
        // construction, since the code is only stored at the end of the
        // constructor execution.

        uint256 size;
        assembly {
            size := extcodesize(account)
        }
        return size > 0;
    }

    /**
     * @dev Replacement for Solidity's `transfer`: sends `amount` wei to
     * `recipient`, forwarding all available gas and reverting on errors.
     *
     * https://eips.ethereum.org/EIPS/eip-1884[EIP1884] increases the gas cost
     * of certain opcodes, possibly making contracts go over the 2300 gas limit
     * imposed by `transfer`, making them unable to receive funds via
     * `transfer`. {sendValue} removes this limitation.
     *
     * https://diligence.consensys.net/posts/2019/09/stop-using-soliditys-transfer-now/[Learn more].
     *
     * IMPORTANT: because control is transferred to `recipient`, care must be
     * taken to not create reentrancy vulnerabilities. Consider using
     * {ReentrancyGuard} or the
     * https://solidity.readthedocs.io/en/v0.5.11/security-considerations.html#use-the-checks-effects-interactions-pattern[checks-effects-interactions pattern].
     */
    function sendValue(address payable recipient, uint256 amount) internal {
        require(address(this).balance >= amount, "Address: insufficient balance");

        (bool success, ) = recipient.call{value: amount}("");
        require(success, "Address: unable to send value, recipient may have reverted");
    }

    /**
     * @dev Performs a Solidity function call using a low level `call`. A
     * plain `call` is an unsafe replacement for a function call: use this
     * function instead.
     *
     * If `target` reverts with a revert reason, it is bubbled up by this
     * function (like regular Solidity function calls).
     *
     * Returns the raw returned data. To convert to the expected return value,
     * use https://solidity.readthedocs.io/en/latest/units-and-global-variables.html?highlight=abi.decode#abi-encoding-and-decoding-functions[`abi.decode`].
     *
     * Requirements:
     *
     * - `target` must be a contract.
     * - calling `target` with `data` must not revert.
     *
     * _Available since v3.1._
     */
    function functionCall(address target, bytes memory data) internal returns (bytes memory) {
        return functionCall(target, data, "Address: low-level call failed");
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`], but with
     * `errorMessage` as a fallback revert reason when `target` reverts.
     *
     * _Available since v3.1._
     */
    function functionCall(
        address target,
        bytes memory data,
        string memory errorMessage
    ) internal returns (bytes memory) {
        return functionCallWithValue(target, data, 0, errorMessage);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but also transferring `value` wei to `target`.
     *
     * Requirements:
     *
     * - the calling contract must have an ETH balance of at least `value`.
     * - the called Solidity function must be `payable`.
     *
     * _Available since v3.1._
     */
    function functionCallWithValue(
        address target,
        bytes memory data,
        uint256 value
    ) internal returns (bytes memory) {
        return functionCallWithValue(target, data, value, "Address: low-level call with value failed");
    }

    /**
     * @dev Same as {xref-Address-functionCallWithValue-address-bytes-uint256-}[`functionCallWithValue`], but
     * with `errorMessage` as a fallback revert reason when `target` reverts.
     *
     * _Available since v3.1._
     */
    function functionCallWithValue(
        address target,
        bytes memory data,
        uint256 value,
        string memory errorMessage
    ) internal returns (bytes memory) {
        require(address(this).balance >= value, "Address: insufficient balance for call");
        require(isContract(target), "Address: call to non-contract");

        (bool success, bytes memory returndata) = target.call{value: value}(data);
        return verifyCallResult(success, returndata, errorMessage);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but performing a static call.
     *
     * _Available since v3.3._
     */
    function functionStaticCall(address target, bytes memory data) internal view returns (bytes memory) {
        return functionStaticCall(target, data, "Address: low-level static call failed");
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-string-}[`functionCall`],
     * but performing a static call.
     *
     * _Available since v3.3._
     */
    function functionStaticCall(
        address target,
        bytes memory data,
        string memory errorMessage
    ) internal view returns (bytes memory) {
        require(isContract(target), "Address: static call to non-contract");

        (bool success, bytes memory returndata) = target.staticcall(data);
        return verifyCallResult(success, returndata, errorMessage);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but performing a delegate call.
     *
     * _Available since v3.4._
     */
    function functionDelegateCall(address target, bytes memory data) internal returns (bytes memory) {
        return functionDelegateCall(target, data, "Address: low-level delegate call failed");
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-string-}[`functionCall`],
     * but performing a delegate call.
     *
     * _Available since v3.4._
     */
    function functionDelegateCall(
        address target,
        bytes memory data,
        string memory errorMessage
    ) internal returns (bytes memory) {
        require(isContract(target), "Address: delegate call to non-contract");

        (bool success, bytes memory returndata) = target.delegatecall(data);
        return verifyCallResult(success, returndata, errorMessage);
    }

    /**
     * @dev Tool to verifies that a low level call was successful, and revert if it wasn't, either by bubbling the
     * revert reason using the provided one.
     *
     * _Available since v4.3._
     */
    function verifyCallResult(
        bool success,
        bytes memory returndata,
        string memory errorMessage
    ) internal pure returns (bytes memory) {
        if (success) {
            return returndata;
        } else {
            // Look for revert reason and bubble it up if present
            if (returndata.length > 0) {
                // The easiest way to bubble the revert reason is using memory via assembly

                assembly {
                    let returndata_size := mload(returndata)
                    revert(add(32, returndata), returndata_size)
                }
            } else {
                revert(errorMessage);
            }
        }
    }
}


// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../IERC20.sol";
import "../../../utils/Address.sol";

/**
 * @title SafeERC20
 * @dev Wrappers around ERC20 operations that throw on failure (when the token
 * contract returns false). Tokens that return no value (and instead revert or
 * throw on failure) are also supported, non-reverting calls are assumed to be
 * successful.
 * To use this library you can add a `using SafeERC20 for IERC20;` statement to your contract,
 * which allows you to call the safe operations as `token.safeTransfer(...)`, etc.
 */
library SafeERC20 {
    using Address for address;

    function safeTransfer(
        IERC20 token,
        address to,
        uint256 value
    ) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(token.transfer.selector, to, value));
    }

    function safeTransferFrom(
        IERC20 token,
        address from,
        address to,
        uint256 value
    ) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(token.transferFrom.selector, from, to, value));
    }

    /**
     * @dev Deprecated. This function has issues similar to the ones found in
     * {IERC20-approve}, and its usage is discouraged.
     *
     * Whenever possible, use {safeIncreaseAllowance} and
     * {safeDecreaseAllowance} instead.
     */
    function safeApprove(
        IERC20 token,
        address spender,
        uint256 value
    ) internal {
        // safeApprove should only be called when setting an initial allowance,
        // or when resetting it to zero. To increase and decrease it, use
        // 'safeIncreaseAllowance' and 'safeDecreaseAllowance'
        require(
            (value == 0) || (token.allowance(address(this), spender) == 0),
            "SafeERC20: approve from non-zero to non-zero allowance"
        );
        _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, value));
    }

    function safeIncreaseAllowance(
        IERC20 token,
        address spender,
        uint256 value
    ) internal {
        uint256 newAllowance = token.allowance(address(this), spender) + value;
        _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, newAllowance));
    }

    function safeDecreaseAllowance(
        IERC20 token,
        address spender,
        uint256 value
    ) internal {
        unchecked {
            uint256 oldAllowance = token.allowance(address(this), spender);
            require(oldAllowance >= value, "SafeERC20: decreased allowance below zero");
            uint256 newAllowance = oldAllowance - value;
            _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, newAllowance));
        }
    }

    /**
     * @dev Imitates a Solidity high-level call (i.e. a regular function call to a contract), relaxing the requirement
     * on the return value: the return value is optional (but if data is returned, it must not be false).
     * @param token The token targeted by the call.
     * @param data The call data (encoded using abi.encode or one of its variants).
     */
    function _callOptionalReturn(IERC20 token, bytes memory data) private {
        // We need to perform a low level call here, to bypass Solidity's return data size checking mechanism, since
        // we're implementing it ourselves. We use {Address.functionCall} to perform this call, which verifies that
        // the target address contains contract code and also asserts for success in the low-level call.

        bytes memory returndata = address(token).functionCall(data, "SafeERC20: low-level call failed");
        if (returndata.length > 0) {
            // Return data is optional
            require(abi.decode(returndata, (bool)), "SafeERC20: ERC20 operation did not succeed");
        }
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