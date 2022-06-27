pragma solidity ^0.5.13;

import "./Exchange.sol";

contract ExchangeEUR is Exchange {
  /**
   * @notice Sets initialized == true on implementation contracts
   * @param test Set to true to skip implementation initialization
   */
  constructor(bool test) public Exchange(test) {}

  /**
  * @notice Returns the storage, major, minor, and patch version of the contract.
  * @dev This function is overloaded to maintain a distinct version from Exchange.sol.
  * @return The storage, major, minor, and patch version of the contract.
  */
  function getVersionNumber() external pure returns (uint256, uint256, uint256, uint256) {
    return (1, 1, 0, 0);
  }
}


pragma solidity ^0.5.0;

import "../GSN/Context.sol";
/**
 * @dev Contract module which provides a basic access control mechanism, where
 * there is an account (an owner) that can be granted exclusive access to
 * specific functions.
 *
 * This module is used through inheritance. It will make available the modifier
 * `onlyOwner`, which can be applied to your functions to restrict their use to
 * the owner.
 */
contract Ownable is Context {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /**
     * @dev Initializes the contract setting the deployer as the initial owner.
     */
    constructor () internal {
        address msgSender = _msgSender();
        _owner = msgSender;
        emit OwnershipTransferred(address(0), msgSender);
    }

    /**
     * @dev Returns the address of the current owner.
     */
    function owner() public view returns (address) {
        return _owner;
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        require(isOwner(), "Ownable: caller is not the owner");
        _;
    }

    /**
     * @dev Returns true if the caller is the current owner.
     */
    function isOwner() public view returns (bool) {
        return _msgSender() == _owner;
    }

    /**
     * @dev Leaves the contract without owner. It will not be possible to call
     * `onlyOwner` functions anymore. Can only be called by the current owner.
     *
     * NOTE: Renouncing ownership will leave the contract without an owner,
     * thereby removing any functionality that is only available to the owner.
     */
    function renounceOwnership() public onlyOwner {
        emit OwnershipTransferred(_owner, address(0));
        _owner = address(0);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) public onlyOwner {
        _transferOwnership(newOwner);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     */
    function _transferOwnership(address newOwner) internal {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}


pragma solidity ^0.5.13;

interface ICeloVersionedContract {
  /**
   * @notice Returns the storage, major, minor, and patch version of the contract.
   * @return The storage, major, minor, and patch version of the contract.
   */
  function getVersionNumber() external pure returns (uint256, uint256, uint256, uint256);
}


pragma solidity ^0.5.0;

/**
 * @dev Interface of the ERC20 standard as defined in the EIP. Does not include
 * the optional functions; to access them see {ERC20Detailed}.
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


pragma solidity ^0.5.0;

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
     * - Subtraction cannot overflow.
     *
     * _Available since v2.4.0._
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
     * - The divisor cannot be zero.
     *
     * _Available since v2.4.0._
     */
    function div(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        // Solidity only automatically asserts when dividing by 0
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
     * - The divisor cannot be zero.
     *
     * _Available since v2.4.0._
     */
    function mod(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b != 0, errorMessage);
        return a % b;
    }
}


pragma solidity ^0.5.0;

/*
 * @dev Provides information about the current execution context, including the
 * sender of the transaction and its data. While these are generally available
 * via msg.sender and msg.data, they should not be accessed in such a direct
 * manner, since when dealing with GSN meta-transactions the account sending and
 * paying for execution may not be the actual sender (as far as an application
 * is concerned).
 *
 * This contract is only required for intermediate, library-like contracts.
 */
contract Context {
    // Empty internal constructor, to prevent people from mistakenly deploying
    // an instance of this contract, which should be used via inheritance.
    constructor () internal { }
    // solhint-disable-previous-line no-empty-blocks

    function _msgSender() internal view returns (address payable) {
        return msg.sender;
    }

    function _msgData() internal view returns (bytes memory) {
        this; // silence state mutability warning without generating bytecode - see https://github.com/ethereum/solidity/issues/2691
        return msg.data;
    }
}


pragma solidity ^0.5.13;

/**
 * @title This interface describes the functions specific to Celo Stable Tokens, and in the
 * absence of interface inheritance is intended as a companion to IERC20.sol and ICeloToken.sol.
 */
interface IStableToken {
  function mint(address, uint256) external returns (bool);
  function burn(uint256) external returns (bool);
  function setInflationParameters(uint256, uint256) external;
  function valueToUnits(uint256) external view returns (uint256);
  function unitsToValue(uint256) external view returns (uint256);
  function getInflationParameters() external view returns (uint256, uint256, uint256, uint256);

  // NOTE: duplicated with IERC20.sol, remove once interface inheritance is supported.
  function balanceOf(address) external view returns (uint256);
}


pragma solidity ^0.5.13;

interface ISortedOracles {
  function addOracle(address, address) external;
  function removeOracle(address, address, uint256) external;
  function report(address, uint256, address, address) external;
  function removeExpiredReports(address, uint256) external;
  function isOldestReportExpired(address token) external view returns (bool, address);
  function numRates(address) external view returns (uint256);
  function medianRate(address) external view returns (uint256, uint256);
  function numTimestamps(address) external view returns (uint256);
  function medianTimestamp(address) external view returns (uint256);
}


pragma solidity ^0.5.13;

interface IReserve {
  function setTobinTaxStalenessThreshold(uint256) external;
  function addToken(address) external returns (bool);
  function removeToken(address, uint256) external returns (bool);
  function transferGold(address payable, uint256) external returns (bool);
  function transferExchangeGold(address payable, uint256) external returns (bool);
  function getReserveGoldBalance() external view returns (uint256);
  function getUnfrozenReserveGoldBalance() external view returns (uint256);
  function getOrComputeTobinTax() external returns (uint256, uint256);
  function getTokens() external view returns (address[] memory);
  function getReserveRatio() external view returns (uint256);
  function addExchangeSpender(address) external;
  function removeExchangeSpender(address, uint256) external;
  function addSpender(address) external;
  function removeSpender(address) external;
}


pragma solidity ^0.5.13;

interface IExchange {
  function buy(uint256, uint256, bool) external returns (uint256);
  function sell(uint256, uint256, bool) external returns (uint256);
  function exchange(uint256, uint256, bool) external returns (uint256);
  function setUpdateFrequency(uint256) external;
  function getBuyTokenAmount(uint256, bool) external view returns (uint256);
  function getSellTokenAmount(uint256, bool) external view returns (uint256);
  function getBuyAndSellBuckets(bool) external view returns (uint256, uint256);
}


pragma solidity ^0.5.13;

import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "openzeppelin-solidity/contracts/ownership/Ownable.sol";
import "./interfaces/IExchange.sol";
import "./interfaces/ISortedOracles.sol";
import "./interfaces/IReserve.sol";
import "./interfaces/IStableToken.sol";
import "../common/Initializable.sol";
import "../common/FixidityLib.sol";
import "../common/Freezable.sol";
import "../common/UsingRegistry.sol";
import "../common/interfaces/ICeloVersionedContract.sol";
import "../common/libraries/ReentrancyGuard.sol";

/**
 * @title Contract that allows to exchange StableToken for GoldToken and vice versa
 * using a Constant Product Market Maker Model
 */
contract Exchange is
  IExchange,
  ICeloVersionedContract,
  Initializable,
  Ownable,
  UsingRegistry,
  ReentrancyGuard,
  Freezable
{
  using SafeMath for uint256;
  using FixidityLib for FixidityLib.Fraction;

  event Exchanged(address indexed exchanger, uint256 sellAmount, uint256 buyAmount, bool soldGold);
  event UpdateFrequencySet(uint256 updateFrequency);
  event MinimumReportsSet(uint256 minimumReports);
  event StableTokenSet(address indexed stable);
  event SpreadSet(uint256 spread);
  event ReserveFractionSet(uint256 reserveFraction);
  event BucketsUpdated(uint256 goldBucket, uint256 stableBucket);

  FixidityLib.Fraction public spread;

  // Fraction of the Reserve that is committed to the gold bucket when updating
  // buckets.
  FixidityLib.Fraction public reserveFraction;

  address public stable;

  // Size of the Uniswap gold bucket
  uint256 public goldBucket;
  // Size of the Uniswap stable token bucket
  uint256 public stableBucket;

  uint256 public lastBucketUpdate = 0;
  uint256 public updateFrequency;
  uint256 public minimumReports;

  modifier updateBucketsIfNecessary() {
    _updateBucketsIfNecessary();
    _;
  }

  /**
   * @notice Returns the storage, major, minor, and patch version of the contract.
   * @return The storage, major, minor, and patch version of the contract.
   */
  function getVersionNumber() external pure returns (uint256, uint256, uint256, uint256) {
    return (1, 1, 1, 0);
  }

  /**
   * @notice Sets initialized == true on implementation contracts
   * @param test Set to true to skip implementation initialization
   */
  constructor(bool test) public Initializable(test) {}

  /**
   * @notice Used in place of the constructor to allow the contract to be upgradable via proxy.
   * @param registryAddress The address of the registry core smart contract.
   * @param stableToken Address of the stable token
   * @param _spread Spread charged on exchanges
   * @param _reserveFraction Fraction to commit to the gold bucket
   * @param _updateFrequency The time period that needs to elapse between bucket
   * updates
   * @param _minimumReports The minimum number of fresh reports that need to be
   * present in the oracle to update buckets
   * commit to the gold bucket
   */
  function initialize(
    address registryAddress,
    address stableToken,
    uint256 _spread,
    uint256 _reserveFraction,
    uint256 _updateFrequency,
    uint256 _minimumReports
  ) external initializer {
    _transferOwnership(msg.sender);
    setRegistry(registryAddress);
    setStableToken(stableToken);
    setSpread(_spread);
    setReserveFraction(_reserveFraction);
    setUpdateFrequency(_updateFrequency);
    setMinimumReports(_minimumReports);
    _updateBucketsIfNecessary();
  }

  /**
   * @notice Exchanges a specific amount of one token for an unspecified amount
   * (greater than a threshold) of another.
   * @param sellAmount The number of tokens to send to the exchange.
   * @param minBuyAmount The minimum number of tokens for the exchange to send in return.
   * @param sellGold True if the caller is sending CELO to the exchange, false otherwise.
   * @return The number of tokens sent by the exchange.
   * @dev The caller must first have approved `sellAmount` to the exchange.
   * @dev This function can be frozen via the Freezable interface.
   */
  function sell(uint256 sellAmount, uint256 minBuyAmount, bool sellGold)
    public
    onlyWhenNotFrozen
    updateBucketsIfNecessary
    nonReentrant
    returns (uint256)
  {
    (uint256 buyTokenBucket, uint256 sellTokenBucket) = _getBuyAndSellBuckets(sellGold);
    uint256 buyAmount = _getBuyTokenAmount(buyTokenBucket, sellTokenBucket, sellAmount);

    require(buyAmount >= minBuyAmount, "Calculated buyAmount was less than specified minBuyAmount");

    _exchange(sellAmount, buyAmount, sellGold);
    return buyAmount;
  }

  /**
   * @dev DEPRECATED - Use `buy` or `sell`.
   * @notice Exchanges a specific amount of one token for an unspecified amount
   * (greater than a threshold) of another.
   * @param sellAmount The number of tokens to send to the exchange.
   * @param minBuyAmount The minimum number of tokens for the exchange to send in return.
   * @param sellGold True if the caller is sending CELO to the exchange, false otherwise.
   * @return The number of tokens sent by the exchange.
   * @dev The caller must first have approved `sellAmount` to the exchange.
   * @dev This function can be frozen via the Freezable interface.
   */
  function exchange(uint256 sellAmount, uint256 minBuyAmount, bool sellGold)
    external
    returns (uint256)
  {
    return sell(sellAmount, minBuyAmount, sellGold);
  }

  /**
   * @notice Exchanges an unspecified amount (up to a threshold) of one token for
   * a specific amount of another.
   * @param buyAmount The number of tokens for the exchange to send in return.
   * @param maxSellAmount The maximum number of tokens to send to the exchange.
   * @param buyGold True if the exchange is sending CELO to the caller, false otherwise.
   * @return The number of tokens sent to the exchange.
   * @dev The caller must first have approved `maxSellAmount` to the exchange.
   * @dev This function can be frozen via the Freezable interface.
   */
  function buy(uint256 buyAmount, uint256 maxSellAmount, bool buyGold)
    external
    onlyWhenNotFrozen
    updateBucketsIfNecessary
    nonReentrant
    returns (uint256)
  {
    bool sellGold = !buyGold;
    (uint256 buyTokenBucket, uint256 sellTokenBucket) = _getBuyAndSellBuckets(sellGold);
    uint256 sellAmount = _getSellTokenAmount(buyTokenBucket, sellTokenBucket, buyAmount);

    require(
      sellAmount <= maxSellAmount,
      "Calculated sellAmount was greater than specified maxSellAmount"
    );

    _exchange(sellAmount, buyAmount, sellGold);
    return sellAmount;
  }

  /**
   * @notice Exchanges a specific amount of one token for a specific amount of another.
   * @param sellAmount The number of tokens to send to the exchange.
   * @param buyAmount The number of tokens for the exchange to send in return.
   * @param sellGold True if the msg.sender is sending CELO to the exchange, false otherwise.
   */
  function _exchange(uint256 sellAmount, uint256 buyAmount, bool sellGold) private {
    IReserve reserve = IReserve(registry.getAddressForOrDie(RESERVE_REGISTRY_ID));

    if (sellGold) {
      goldBucket = goldBucket.add(sellAmount);
      stableBucket = stableBucket.sub(buyAmount);
      require(
        getGoldToken().transferFrom(msg.sender, address(reserve), sellAmount),
        "Transfer of sell token failed"
      );
      require(IStableToken(stable).mint(msg.sender, buyAmount), "Mint of stable token failed");
    } else {
      stableBucket = stableBucket.add(sellAmount);
      goldBucket = goldBucket.sub(buyAmount);
      require(
        IERC20(stable).transferFrom(msg.sender, address(this), sellAmount),
        "Transfer of sell token failed"
      );
      IStableToken(stable).burn(sellAmount);

      require(reserve.transferExchangeGold(msg.sender, buyAmount), "Transfer of buyToken failed");
    }

    emit Exchanged(msg.sender, sellAmount, buyAmount, sellGold);
  }

  /**
   * @notice Returns the amount of buy tokens a user would get for sellAmount of the sell token.
   * @param sellAmount The amount of sellToken the user is selling to the exchange.
   * @param sellGold `true` if gold is the sell token.
   * @return The corresponding buyToken amount.
   */
  function getBuyTokenAmount(uint256 sellAmount, bool sellGold) external view returns (uint256) {
    (uint256 buyTokenBucket, uint256 sellTokenBucket) = getBuyAndSellBuckets(sellGold);
    return _getBuyTokenAmount(buyTokenBucket, sellTokenBucket, sellAmount);
  }

  /**
   * @notice Returns the amount of sell tokens a user would need to exchange to receive buyAmount of
   * buy tokens.
   * @param buyAmount The amount of buyToken the user would like to purchase.
   * @param sellGold `true` if gold is the sell token.
   * @return The corresponding sellToken amount.
   */
  function getSellTokenAmount(uint256 buyAmount, bool sellGold) external view returns (uint256) {
    (uint256 buyTokenBucket, uint256 sellTokenBucket) = getBuyAndSellBuckets(sellGold);
    return _getSellTokenAmount(buyTokenBucket, sellTokenBucket, buyAmount);
  }

  /**
   * @notice Returns the buy token and sell token bucket sizes, in order. The ratio of
   * the two also represents the exchange rate between the two.
   * @param sellGold `true` if gold is the sell token.
   * @return (buyTokenBucket, sellTokenBucket)
   */
  function getBuyAndSellBuckets(bool sellGold) public view returns (uint256, uint256) {
    uint256 currentGoldBucket = goldBucket;
    uint256 currentStableBucket = stableBucket;

    if (shouldUpdateBuckets()) {
      (currentGoldBucket, currentStableBucket) = getUpdatedBuckets();
    }

    if (sellGold) {
      return (currentStableBucket, currentGoldBucket);
    } else {
      return (currentGoldBucket, currentStableBucket);
    }
  }

  /**
    * @notice Allows owner to set the update frequency
    * @param newUpdateFrequency The new update frequency
    */
  function setUpdateFrequency(uint256 newUpdateFrequency) public onlyOwner {
    updateFrequency = newUpdateFrequency;
    emit UpdateFrequencySet(newUpdateFrequency);
  }

  /**
    * @notice Allows owner to set the minimum number of reports required
    * @param newMininumReports The new update minimum number of reports required
    */
  function setMinimumReports(uint256 newMininumReports) public onlyOwner {
    minimumReports = newMininumReports;
    emit MinimumReportsSet(newMininumReports);
  }

  /**
    * @notice Allows owner to set the Stable Token address
    * @param newStableToken The new address for Stable Token
    */
  function setStableToken(address newStableToken) public onlyOwner {
    stable = newStableToken;
    emit StableTokenSet(newStableToken);
  }

  /**
    * @notice Allows owner to set the spread
    * @param newSpread The new value for the spread
    */
  function setSpread(uint256 newSpread) public onlyOwner {
    spread = FixidityLib.wrap(newSpread);
    emit SpreadSet(newSpread);
  }

  /**
    * @notice Allows owner to set the Reserve Fraction
    * @param newReserveFraction The new value for the reserve fraction
    */
  function setReserveFraction(uint256 newReserveFraction) public onlyOwner {
    reserveFraction = FixidityLib.wrap(newReserveFraction);
    require(reserveFraction.lt(FixidityLib.fixed1()), "reserve fraction must be smaller than 1");
    emit ReserveFractionSet(newReserveFraction);
  }

  /**
   * @notice Returns the buy token and sell token bucket sizes, in order. The ratio of
   * the two also represents the exchange rate between the two.
   * @param sellGold `true` if gold is the sell token.
   * @return (buyTokenBucket, sellTokenBucket)
   */
  function _getBuyAndSellBuckets(bool sellGold) private view returns (uint256, uint256) {
    if (sellGold) {
      return (stableBucket, goldBucket);
    } else {
      return (goldBucket, stableBucket);
    }
  }

  /**
   * @dev Returns the amount of buy tokens a user would get for sellAmount of the sell.
   * @param buyTokenBucket The buy token bucket size.
   * @param sellTokenBucket The sell token bucket size.
   * @param sellAmount The amount the user is selling to the exchange.
   * @return The corresponding buy amount.
   */
  function _getBuyTokenAmount(uint256 buyTokenBucket, uint256 sellTokenBucket, uint256 sellAmount)
    private
    view
    returns (uint256)
  {
    if (sellAmount == 0) return 0;

    FixidityLib.Fraction memory reducedSellAmount = getReducedSellAmount(sellAmount);
    FixidityLib.Fraction memory numerator = reducedSellAmount.multiply(
      FixidityLib.newFixed(buyTokenBucket)
    );
    FixidityLib.Fraction memory denominator = FixidityLib.newFixed(sellTokenBucket).add(
      reducedSellAmount
    );

    // Can't use FixidityLib.divide because denominator can easily be greater
    // than maxFixedDivisor.
    // Fortunately, we expect an integer result, so integer division gives us as
    // much precision as we could hope for.
    return numerator.unwrap().div(denominator.unwrap());
  }

  /**
   * @notice Returns the amount of sell tokens a user would need to exchange to receive buyAmount of
   * buy tokens.
   * @param buyTokenBucket The buy token bucket size.
   * @param sellTokenBucket The sell token bucket size.
   * @param buyAmount The amount the user is buying from the exchange.
   * @return The corresponding sell amount.
   */
  function _getSellTokenAmount(uint256 buyTokenBucket, uint256 sellTokenBucket, uint256 buyAmount)
    private
    view
    returns (uint256)
  {
    if (buyAmount == 0) return 0;

    FixidityLib.Fraction memory numerator = FixidityLib.newFixed(buyAmount.mul(sellTokenBucket));
    FixidityLib.Fraction memory denominator = FixidityLib
      .newFixed(buyTokenBucket.sub(buyAmount))
      .multiply(FixidityLib.fixed1().subtract(spread));

    // See comment in _getBuyTokenAmount
    return numerator.unwrap().div(denominator.unwrap());
  }

  function getUpdatedBuckets() private view returns (uint256, uint256) {
    uint256 updatedGoldBucket = getUpdatedGoldBucket();
    uint256 exchangeRateNumerator;
    uint256 exchangeRateDenominator;
    (exchangeRateNumerator, exchangeRateDenominator) = getOracleExchangeRate();
    uint256 updatedStableBucket = exchangeRateNumerator.mul(updatedGoldBucket).div(
      exchangeRateDenominator
    );
    return (updatedGoldBucket, updatedStableBucket);
  }

  function getUpdatedGoldBucket() private view returns (uint256) {
    uint256 reserveGoldBalance = getReserve().getUnfrozenReserveGoldBalance();
    return reserveFraction.multiply(FixidityLib.newFixed(reserveGoldBalance)).fromFixed();
  }

  /**
   * @notice If conditions are met, updates the Uniswap bucket sizes to track
   * the price reported by the Oracle.
   */
  function _updateBucketsIfNecessary() private {
    if (shouldUpdateBuckets()) {
      // solhint-disable-next-line not-rely-on-time
      lastBucketUpdate = now;

      (goldBucket, stableBucket) = getUpdatedBuckets();
      emit BucketsUpdated(goldBucket, stableBucket);
    }
  }

  /**
   * @notice Calculates the sell amount reduced by the spread.
   * @param sellAmount The original sell amount.
   * @return The reduced sell amount, computed as (1 - spread) * sellAmount
   */
  function getReducedSellAmount(uint256 sellAmount)
    private
    view
    returns (FixidityLib.Fraction memory)
  {
    return FixidityLib.fixed1().subtract(spread).multiply(FixidityLib.newFixed(sellAmount));
  }

  /*
   * @notice Checks conditions required for bucket updates.
   * @return Whether or not buckets should be updated.
   */
  function shouldUpdateBuckets() private view returns (bool) {
    ISortedOracles sortedOracles = ISortedOracles(
      registry.getAddressForOrDie(SORTED_ORACLES_REGISTRY_ID)
    );
    (bool isReportExpired, ) = sortedOracles.isOldestReportExpired(stable);
    // solhint-disable-next-line not-rely-on-time
    bool timePassed = now >= lastBucketUpdate.add(updateFrequency);
    bool enoughReports = sortedOracles.numRates(stable) >= minimumReports;
    // solhint-disable-next-line not-rely-on-time
    bool medianReportRecent = sortedOracles.medianTimestamp(stable) > now.sub(updateFrequency);
    return timePassed && enoughReports && medianReportRecent && !isReportExpired;
  }

  function getOracleExchangeRate() private view returns (uint256, uint256) {
    uint256 rateNumerator;
    uint256 rateDenominator;
    (rateNumerator, rateDenominator) = ISortedOracles(
      registry.getAddressForOrDie(SORTED_ORACLES_REGISTRY_ID)
    )
      .medianRate(stable);
    require(rateDenominator > 0, "exchange rate denominator must be greater than 0");
    return (rateNumerator, rateDenominator);
  }
}


pragma solidity ^0.5.13;

interface IRandom {
  function revealAndCommit(bytes32, bytes32, address) external;
  function randomnessBlockRetentionWindow() external view returns (uint256);
  function random() external view returns (bytes32);
  function getBlockRandomness(uint256) external view returns (bytes32);
}


pragma solidity ^0.5.13;

interface IAccounts {
  function isAccount(address) external view returns (bool);
  function voteSignerToAccount(address) external view returns (address);
  function validatorSignerToAccount(address) external view returns (address);
  function attestationSignerToAccount(address) external view returns (address);
  function signerToAccount(address) external view returns (address);
  function getAttestationSigner(address) external view returns (address);
  function getValidatorSigner(address) external view returns (address);
  function getVoteSigner(address) external view returns (address);
  function hasAuthorizedVoteSigner(address) external view returns (bool);
  function hasAuthorizedValidatorSigner(address) external view returns (bool);
  function hasAuthorizedAttestationSigner(address) external view returns (bool);

  function setAccountDataEncryptionKey(bytes calldata) external;
  function setMetadataURL(string calldata) external;
  function setName(string calldata) external;
  function setWalletAddress(address, uint8, bytes32, bytes32) external;
  function setAccount(string calldata, bytes calldata, address, uint8, bytes32, bytes32) external;

  function getDataEncryptionKey(address) external view returns (bytes memory);
  function getWalletAddress(address) external view returns (address);
  function getMetadataURL(address) external view returns (string memory);
  function batchGetMetadataURL(address[] calldata)
    external
    view
    returns (uint256[] memory, bytes memory);
  function getName(address) external view returns (string memory);

  function authorizeVoteSigner(address, uint8, bytes32, bytes32) external;
  function authorizeValidatorSigner(address, uint8, bytes32, bytes32) external;
  function authorizeValidatorSignerWithPublicKey(address, uint8, bytes32, bytes32, bytes calldata)
    external;
  function authorizeValidatorSignerWithKeys(
    address,
    uint8,
    bytes32,
    bytes32,
    bytes calldata,
    bytes calldata,
    bytes calldata
  ) external;
  function authorizeAttestationSigner(address, uint8, bytes32, bytes32) external;
  function createAccount() external returns (bool);
}


pragma solidity ^0.5.13;

interface IAttestations {
  function request(bytes32, uint256, address) external;
  function selectIssuers(bytes32) external;
  function complete(bytes32, uint8, bytes32, bytes32) external;
  function revoke(bytes32, uint256) external;
  function withdraw(address) external;
  function approveTransfer(bytes32, uint256, address, address, bool) external;

  // view functions
  function getUnselectedRequest(bytes32, address) external view returns (uint32, uint32, address);
  function getAttestationIssuers(bytes32, address) external view returns (address[] memory);
  function getAttestationStats(bytes32, address) external view returns (uint32, uint32);
  function batchGetAttestationStats(bytes32[] calldata)
    external
    view
    returns (uint256[] memory, address[] memory, uint64[] memory, uint64[] memory);
  function getAttestationState(bytes32, address, address)
    external
    view
    returns (uint8, uint32, address);
  function getCompletableAttestations(bytes32, address)
    external
    view
    returns (uint32[] memory, address[] memory, uint256[] memory, bytes memory);
  function getAttestationRequestFee(address) external view returns (uint256);
  function getMaxAttestations() external view returns (uint256);
  function validateAttestationCode(bytes32, address, uint8, bytes32, bytes32)
    external
    view
    returns (address);
  function lookupAccountsForIdentifier(bytes32) external view returns (address[] memory);
  function requireNAttestationsRequested(bytes32, address, uint32) external view;

  // only owner
  function setAttestationRequestFee(address, uint256) external;
  function setAttestationExpiryBlocks(uint256) external;
  function setSelectIssuersWaitBlocks(uint256) external;
  function setMaxAttestations(uint256) external;
}


pragma solidity ^0.5.13;

interface IValidators {
  function registerValidator(bytes calldata, bytes calldata, bytes calldata)
    external
    returns (bool);
  function deregisterValidator(uint256) external returns (bool);
  function affiliate(address) external returns (bool);
  function deaffiliate() external returns (bool);
  function updateBlsPublicKey(bytes calldata, bytes calldata) external returns (bool);
  function registerValidatorGroup(uint256) external returns (bool);
  function deregisterValidatorGroup(uint256) external returns (bool);
  function addMember(address) external returns (bool);
  function addFirstMember(address, address, address) external returns (bool);
  function removeMember(address) external returns (bool);
  function reorderMember(address, address, address) external returns (bool);
  function updateCommission() external;
  function setNextCommissionUpdate(uint256) external;
  function resetSlashingMultiplier() external;

  // only owner
  function setCommissionUpdateDelay(uint256) external;
  function setMaxGroupSize(uint256) external returns (bool);
  function setMembershipHistoryLength(uint256) external returns (bool);
  function setValidatorScoreParameters(uint256, uint256) external returns (bool);
  function setGroupLockedGoldRequirements(uint256, uint256) external returns (bool);
  function setValidatorLockedGoldRequirements(uint256, uint256) external returns (bool);
  function setSlashingMultiplierResetPeriod(uint256) external;

  // view functions
  function getMaxGroupSize() external view returns (uint256);
  function getCommissionUpdateDelay() external view returns (uint256);
  function getValidatorScoreParameters() external view returns (uint256, uint256);
  function getMembershipHistory(address)
    external
    view
    returns (uint256[] memory, address[] memory, uint256, uint256);
  function calculateEpochScore(uint256) external view returns (uint256);
  function calculateGroupEpochScore(uint256[] calldata) external view returns (uint256);
  function getAccountLockedGoldRequirement(address) external view returns (uint256);
  function meetsAccountLockedGoldRequirements(address) external view returns (bool);
  function getValidatorBlsPublicKeyFromSigner(address) external view returns (bytes memory);
  function getValidator(address account)
    external
    view
    returns (bytes memory, bytes memory, address, uint256, address);
  function getValidatorGroup(address)
    external
    view
    returns (address[] memory, uint256, uint256, uint256, uint256[] memory, uint256, uint256);
  function getGroupNumMembers(address) external view returns (uint256);
  function getTopGroupValidators(address, uint256) external view returns (address[] memory);
  function getGroupsNumMembers(address[] calldata accounts)
    external
    view
    returns (uint256[] memory);
  function getNumRegisteredValidators() external view returns (uint256);
  function groupMembershipInEpoch(address, uint256, uint256) external view returns (address);

  // only registered contract
  function updateEcdsaPublicKey(address, address, bytes calldata) external returns (bool);
  function updatePublicKeys(address, address, bytes calldata, bytes calldata, bytes calldata)
    external
    returns (bool);
  function getValidatorLockedGoldRequirements() external view returns (uint256, uint256);
  function getGroupLockedGoldRequirements() external view returns (uint256, uint256);
  function getRegisteredValidators() external view returns (address[] memory);
  function getRegisteredValidatorSigners() external view returns (address[] memory);
  function getRegisteredValidatorGroups() external view returns (address[] memory);
  function isValidatorGroup(address) external view returns (bool);
  function isValidator(address) external view returns (bool);
  function getValidatorGroupSlashingMultiplier(address) external view returns (uint256);
  function getMembershipInLastEpoch(address) external view returns (address);
  function getMembershipInLastEpochFromSigner(address) external view returns (address);

  // only VM
  function updateValidatorScoreFromSigner(address, uint256) external;
  function distributeEpochPaymentsFromSigner(address, uint256) external returns (uint256);

  // only slasher
  function forceDeaffiliateIfValidator(address) external;
  function halveSlashingMultiplier(address) external;

}


pragma solidity ^0.5.13;

interface ILockedGold {
  function incrementNonvotingAccountBalance(address, uint256) external;
  function decrementNonvotingAccountBalance(address, uint256) external;
  function getAccountTotalLockedGold(address) external view returns (uint256);
  function getTotalLockedGold() external view returns (uint256);
  function getPendingWithdrawals(address)
    external
    view
    returns (uint256[] memory, uint256[] memory);
  function getTotalPendingWithdrawals(address) external view returns (uint256);
  function lock() external payable;
  function unlock(uint256) external;
  function relock(uint256, uint256) external;
  function withdraw(uint256) external;
  function slash(
    address account,
    uint256 penalty,
    address reporter,
    uint256 reward,
    address[] calldata lessers,
    address[] calldata greaters,
    uint256[] calldata indices
  ) external;
  function isSlasher(address) external view returns (bool);
}


pragma solidity ^0.5.13;

interface IGovernance {
  function isVoting(address) external view returns (bool);
}


pragma solidity ^0.5.13;

interface IElection {
  function electValidatorSigners() external view returns (address[] memory);
  function electNValidatorSigners(uint256, uint256) external view returns (address[] memory);
  function vote(address, uint256, address, address) external returns (bool);
  function activate(address) external returns (bool);
  function revokeActive(address, uint256, address, address, uint256) external returns (bool);
  function revokeAllActive(address, address, address, uint256) external returns (bool);
  function revokePending(address, uint256, address, address, uint256) external returns (bool);
  function markGroupIneligible(address) external;
  function markGroupEligible(address, address, address) external;
  function forceDecrementVotes(
    address,
    uint256,
    address[] calldata,
    address[] calldata,
    uint256[] calldata
  ) external returns (uint256);

  // view functions
  function getElectableValidators() external view returns (uint256, uint256);
  function getElectabilityThreshold() external view returns (uint256);
  function getNumVotesReceivable(address) external view returns (uint256);
  function getTotalVotes() external view returns (uint256);
  function getActiveVotes() external view returns (uint256);
  function getTotalVotesByAccount(address) external view returns (uint256);
  function getPendingVotesForGroupByAccount(address, address) external view returns (uint256);
  function getActiveVotesForGroupByAccount(address, address) external view returns (uint256);
  function getTotalVotesForGroupByAccount(address, address) external view returns (uint256);
  function getActiveVoteUnitsForGroupByAccount(address, address) external view returns (uint256);
  function getTotalVotesForGroup(address) external view returns (uint256);
  function getActiveVotesForGroup(address) external view returns (uint256);
  function getPendingVotesForGroup(address) external view returns (uint256);
  function getGroupEligibility(address) external view returns (bool);
  function getGroupEpochRewards(address, uint256, uint256[] calldata)
    external
    view
    returns (uint256);
  function getGroupsVotedForByAccount(address) external view returns (address[] memory);
  function getEligibleValidatorGroups() external view returns (address[] memory);
  function getTotalVotesForEligibleValidatorGroups()
    external
    view
    returns (address[] memory, uint256[] memory);
  function getCurrentValidatorSigners() external view returns (address[] memory);
  function canReceiveVotes(address, uint256) external view returns (bool);
  function hasActivatablePendingVotes(address, address) external view returns (bool);

  // only owner
  function setElectableValidators(uint256, uint256) external returns (bool);
  function setMaxNumGroupsVotedFor(uint256) external returns (bool);
  function setElectabilityThreshold(uint256) external returns (bool);

  // only VM
  function distributeEpochRewards(address, uint256, address, address) external;
}


pragma solidity ^0.5.13;

/**
 * @title Helps contracts guard against reentrancy attacks.
 * @author Remco Bloemen <[email protected]π.com>, Eenae <[email protected]>
 * @dev If you mark a function `nonReentrant`, you should also
 * mark it `external`.
 */
contract ReentrancyGuard {
  /// @dev counter to allow mutex lock with only one SSTORE operation
  uint256 private _guardCounter;

  constructor() internal {
    // The counter starts at one to prevent changing it from zero to a non-zero
    // value, which is a more expensive operation.
    _guardCounter = 1;
  }

  /**
   * @dev Prevents a contract from calling itself, directly or indirectly.
   * Calling a `nonReentrant` function from another `nonReentrant`
   * function is not supported. It is possible to prevent this from happening
   * by making the `nonReentrant` function external, and make it call a
   * `private` function that does the actual work.
   */
  modifier nonReentrant() {
    _guardCounter += 1;
    uint256 localCounter = _guardCounter;
    _;
    require(localCounter == _guardCounter, "reentrant call");
  }
}


pragma solidity ^0.5.13;

interface IRegistry {
  function setAddressFor(string calldata, address) external;
  function getAddressForOrDie(bytes32) external view returns (address);
  function getAddressFor(bytes32) external view returns (address);
  function getAddressForStringOrDie(string calldata identifier) external view returns (address);
  function getAddressForString(string calldata identifier) external view returns (address);
  function isOneOf(bytes32[] calldata, address) external view returns (bool);
}


pragma solidity ^0.5.13;

interface IFreezer {
  function isFrozen(address) external view returns (bool);
}


pragma solidity ^0.5.13;

interface IFeeCurrencyWhitelist {
  function addToken(address) external;
  function getWhitelist() external view returns (address[] memory);
}


pragma solidity ^0.5.13;

import "openzeppelin-solidity/contracts/ownership/Ownable.sol";
import "openzeppelin-solidity/contracts/token/ERC20/IERC20.sol";

import "./interfaces/IAccounts.sol";
import "./interfaces/IFeeCurrencyWhitelist.sol";
import "./interfaces/IFreezer.sol";
import "./interfaces/IRegistry.sol";

import "../governance/interfaces/IElection.sol";
import "../governance/interfaces/IGovernance.sol";
import "../governance/interfaces/ILockedGold.sol";
import "../governance/interfaces/IValidators.sol";

import "../identity/interfaces/IRandom.sol";
import "../identity/interfaces/IAttestations.sol";

import "../stability/interfaces/IExchange.sol";
import "../stability/interfaces/IReserve.sol";
import "../stability/interfaces/ISortedOracles.sol";
import "../stability/interfaces/IStableToken.sol";

contract UsingRegistry is Ownable {
  event RegistrySet(address indexed registryAddress);

  // solhint-disable state-visibility
  bytes32 constant ACCOUNTS_REGISTRY_ID = keccak256(abi.encodePacked("Accounts"));
  bytes32 constant ATTESTATIONS_REGISTRY_ID = keccak256(abi.encodePacked("Attestations"));
  bytes32 constant DOWNTIME_SLASHER_REGISTRY_ID = keccak256(abi.encodePacked("DowntimeSlasher"));
  bytes32 constant DOUBLE_SIGNING_SLASHER_REGISTRY_ID = keccak256(
    abi.encodePacked("DoubleSigningSlasher")
  );
  bytes32 constant ELECTION_REGISTRY_ID = keccak256(abi.encodePacked("Election"));
  bytes32 constant EXCHANGE_REGISTRY_ID = keccak256(abi.encodePacked("Exchange"));
  bytes32 constant FEE_CURRENCY_WHITELIST_REGISTRY_ID = keccak256(
    abi.encodePacked("FeeCurrencyWhitelist")
  );
  bytes32 constant FREEZER_REGISTRY_ID = keccak256(abi.encodePacked("Freezer"));
  bytes32 constant GOLD_TOKEN_REGISTRY_ID = keccak256(abi.encodePacked("GoldToken"));
  bytes32 constant GOVERNANCE_REGISTRY_ID = keccak256(abi.encodePacked("Governance"));
  bytes32 constant GOVERNANCE_SLASHER_REGISTRY_ID = keccak256(
    abi.encodePacked("GovernanceSlasher")
  );
  bytes32 constant LOCKED_GOLD_REGISTRY_ID = keccak256(abi.encodePacked("LockedGold"));
  bytes32 constant RESERVE_REGISTRY_ID = keccak256(abi.encodePacked("Reserve"));
  bytes32 constant RANDOM_REGISTRY_ID = keccak256(abi.encodePacked("Random"));
  bytes32 constant SORTED_ORACLES_REGISTRY_ID = keccak256(abi.encodePacked("SortedOracles"));
  bytes32 constant STABLE_TOKEN_REGISTRY_ID = keccak256(abi.encodePacked("StableToken"));
  bytes32 constant VALIDATORS_REGISTRY_ID = keccak256(abi.encodePacked("Validators"));
  // solhint-enable state-visibility

  IRegistry public registry;

  modifier onlyRegisteredContract(bytes32 identifierHash) {
    require(registry.getAddressForOrDie(identifierHash) == msg.sender, "only registered contract");
    _;
  }

  modifier onlyRegisteredContracts(bytes32[] memory identifierHashes) {
    require(registry.isOneOf(identifierHashes, msg.sender), "only registered contracts");
    _;
  }

  /**
   * @notice Updates the address pointing to a Registry contract.
   * @param registryAddress The address of a registry contract for routing to other contracts.
   */
  function setRegistry(address registryAddress) public onlyOwner {
    require(registryAddress != address(0), "Cannot register the null address");
    registry = IRegistry(registryAddress);
    emit RegistrySet(registryAddress);
  }

  function getAccounts() internal view returns (IAccounts) {
    return IAccounts(registry.getAddressForOrDie(ACCOUNTS_REGISTRY_ID));
  }

  function getAttestations() internal view returns (IAttestations) {
    return IAttestations(registry.getAddressForOrDie(ATTESTATIONS_REGISTRY_ID));
  }

  function getElection() internal view returns (IElection) {
    return IElection(registry.getAddressForOrDie(ELECTION_REGISTRY_ID));
  }

  function getExchange() internal view returns (IExchange) {
    return IExchange(registry.getAddressForOrDie(EXCHANGE_REGISTRY_ID));
  }

  function getFeeCurrencyWhitelistRegistry() internal view returns (IFeeCurrencyWhitelist) {
    return IFeeCurrencyWhitelist(registry.getAddressForOrDie(FEE_CURRENCY_WHITELIST_REGISTRY_ID));
  }

  function getFreezer() internal view returns (IFreezer) {
    return IFreezer(registry.getAddressForOrDie(FREEZER_REGISTRY_ID));
  }

  function getGoldToken() internal view returns (IERC20) {
    return IERC20(registry.getAddressForOrDie(GOLD_TOKEN_REGISTRY_ID));
  }

  function getGovernance() internal view returns (IGovernance) {
    return IGovernance(registry.getAddressForOrDie(GOVERNANCE_REGISTRY_ID));
  }

  function getLockedGold() internal view returns (ILockedGold) {
    return ILockedGold(registry.getAddressForOrDie(LOCKED_GOLD_REGISTRY_ID));
  }

  function getRandom() internal view returns (IRandom) {
    return IRandom(registry.getAddressForOrDie(RANDOM_REGISTRY_ID));
  }

  function getReserve() internal view returns (IReserve) {
    return IReserve(registry.getAddressForOrDie(RESERVE_REGISTRY_ID));
  }

  function getSortedOracles() internal view returns (ISortedOracles) {
    return ISortedOracles(registry.getAddressForOrDie(SORTED_ORACLES_REGISTRY_ID));
  }

  function getStableToken() internal view returns (IStableToken) {
    return IStableToken(registry.getAddressForOrDie(STABLE_TOKEN_REGISTRY_ID));
  }

  function getValidators() internal view returns (IValidators) {
    return IValidators(registry.getAddressForOrDie(VALIDATORS_REGISTRY_ID));
  }
}


pragma solidity ^0.5.13;

contract Initializable {
  bool public initialized;

  constructor(bool testingDeployment) public {
    if (!testingDeployment) {
      initialized = true;
    }
  }

  modifier initializer() {
    require(!initialized, "contract already initialized");
    initialized = true;
    _;
  }
}


pragma solidity ^0.5.13;

import "./UsingRegistry.sol";

contract Freezable is UsingRegistry {
  // onlyWhenNotFrozen functions can only be called when `frozen` is false, otherwise they will
  // revert.
  modifier onlyWhenNotFrozen() {
    require(!getFreezer().isFrozen(address(this)), "can't call when contract is frozen");
    _;
  }
}


pragma solidity ^0.5.13;

/**
 * @title FixidityLib
 * @author Gadi Guy, Alberto Cuesta Canada
 * @notice This library provides fixed point arithmetic with protection against
 * overflow.
 * All operations are done with uint256 and the operands must have been created
 * with any of the newFrom* functions, which shift the comma digits() to the
 * right and check for limits, or with wrap() which expects a number already
 * in the internal representation of a fraction.
 * When using this library be sure to use maxNewFixed() as the upper limit for
 * creation of fixed point numbers.
 * @dev All contained functions are pure and thus marked internal to be inlined
 * on consuming contracts at compile time for gas efficiency.
 */
library FixidityLib {
  struct Fraction {
    uint256 value;
  }

  /**
   * @notice Number of positions that the comma is shifted to the right.
   */
  function digits() internal pure returns (uint8) {
    return 24;
  }

  uint256 private constant FIXED1_UINT = 1000000000000000000000000;

  /**
   * @notice This is 1 in the fixed point units used in this library.
   * @dev Test fixed1() equals 10^digits()
   * Hardcoded to 24 digits.
   */
  function fixed1() internal pure returns (Fraction memory) {
    return Fraction(FIXED1_UINT);
  }

  /**
   * @notice Wrap a uint256 that represents a 24-decimal fraction in a Fraction
   * struct.
   * @param x Number that already represents a 24-decimal fraction.
   * @return A Fraction struct with contents x.
   */
  function wrap(uint256 x) internal pure returns (Fraction memory) {
    return Fraction(x);
  }

  /**
   * @notice Unwraps the uint256 inside of a Fraction struct.
   */
  function unwrap(Fraction memory x) internal pure returns (uint256) {
    return x.value;
  }

  /**
   * @notice The amount of decimals lost on each multiplication operand.
   * @dev Test mulPrecision() equals sqrt(fixed1)
   */
  function mulPrecision() internal pure returns (uint256) {
    return 1000000000000;
  }

  /**
   * @notice Maximum value that can be converted to fixed point. Optimize for deployment.
   * @dev
   * Test maxNewFixed() equals maxUint256() / fixed1()
   */
  function maxNewFixed() internal pure returns (uint256) {
    return 115792089237316195423570985008687907853269984665640564;
  }

  /**
   * @notice Converts a uint256 to fixed point Fraction
   * @dev Test newFixed(0) returns 0
   * Test newFixed(1) returns fixed1()
   * Test newFixed(maxNewFixed()) returns maxNewFixed() * fixed1()
   * Test newFixed(maxNewFixed()+1) fails
   */
  function newFixed(uint256 x) internal pure returns (Fraction memory) {
    require(x <= maxNewFixed(), "can't create fixidity number larger than maxNewFixed()");
    return Fraction(x * FIXED1_UINT);
  }

  /**
   * @notice Converts a uint256 in the fixed point representation of this
   * library to a non decimal. All decimal digits will be truncated.
   */
  function fromFixed(Fraction memory x) internal pure returns (uint256) {
    return x.value / FIXED1_UINT;
  }

  /**
   * @notice Converts two uint256 representing a fraction to fixed point units,
   * equivalent to multiplying dividend and divisor by 10^digits().
   * @param numerator numerator must be <= maxNewFixed()
   * @param denominator denominator must be <= maxNewFixed() and denominator can't be 0
   * @dev
   * Test newFixedFraction(1,0) fails
   * Test newFixedFraction(0,1) returns 0
   * Test newFixedFraction(1,1) returns fixed1()
   * Test newFixedFraction(1,fixed1()) returns 1
   */
  function newFixedFraction(uint256 numerator, uint256 denominator)
    internal
    pure
    returns (Fraction memory)
  {
    Fraction memory convertedNumerator = newFixed(numerator);
    Fraction memory convertedDenominator = newFixed(denominator);
    return divide(convertedNumerator, convertedDenominator);
  }

  /**
   * @notice Returns the integer part of a fixed point number.
   * @dev
   * Test integer(0) returns 0
   * Test integer(fixed1()) returns fixed1()
   * Test integer(newFixed(maxNewFixed())) returns maxNewFixed()*fixed1()
   */
  function integer(Fraction memory x) internal pure returns (Fraction memory) {
    return Fraction((x.value / FIXED1_UINT) * FIXED1_UINT); // Can't overflow
  }

  /**
   * @notice Returns the fractional part of a fixed point number.
   * In the case of a negative number the fractional is also negative.
   * @dev
   * Test fractional(0) returns 0
   * Test fractional(fixed1()) returns 0
   * Test fractional(fixed1()-1) returns 10^24-1
   */
  function fractional(Fraction memory x) internal pure returns (Fraction memory) {
    return Fraction(x.value - (x.value / FIXED1_UINT) * FIXED1_UINT); // Can't overflow
  }

  /**
   * @notice x+y.
   * @dev The maximum value that can be safely used as an addition operator is defined as
   * maxFixedAdd = maxUint256()-1 / 2, or
   * 57896044618658097711785492504343953926634992332820282019728792003956564819967.
   * Test add(maxFixedAdd,maxFixedAdd) equals maxFixedAdd + maxFixedAdd
   * Test add(maxFixedAdd+1,maxFixedAdd+1) throws
   */
  function add(Fraction memory x, Fraction memory y) internal pure returns (Fraction memory) {
    uint256 z = x.value + y.value;
    require(z >= x.value, "add overflow detected");
    return Fraction(z);
  }

  /**
   * @notice x-y.
   * @dev
   * Test subtract(6, 10) fails
   */
  function subtract(Fraction memory x, Fraction memory y) internal pure returns (Fraction memory) {
    require(x.value >= y.value, "substraction underflow detected");
    return Fraction(x.value - y.value);
  }

  /**
   * @notice x*y. If any of the operators is higher than the max multiplier value it
   * might overflow.
   * @dev The maximum value that can be safely used as a multiplication operator
   * (maxFixedMul) is calculated as sqrt(maxUint256()*fixed1()),
   * or 340282366920938463463374607431768211455999999999999
   * Test multiply(0,0) returns 0
   * Test multiply(maxFixedMul,0) returns 0
   * Test multiply(0,maxFixedMul) returns 0
   * Test multiply(fixed1()/mulPrecision(),fixed1()*mulPrecision()) returns fixed1()
   * Test multiply(maxFixedMul,maxFixedMul) is around maxUint256()
   * Test multiply(maxFixedMul+1,maxFixedMul+1) fails
   */
  function multiply(Fraction memory x, Fraction memory y) internal pure returns (Fraction memory) {
    if (x.value == 0 || y.value == 0) return Fraction(0);
    if (y.value == FIXED1_UINT) return x;
    if (x.value == FIXED1_UINT) return y;

    // Separate into integer and fractional parts
    // x = x1 + x2, y = y1 + y2
    uint256 x1 = integer(x).value / FIXED1_UINT;
    uint256 x2 = fractional(x).value;
    uint256 y1 = integer(y).value / FIXED1_UINT;
    uint256 y2 = fractional(y).value;

    // (x1 + x2) * (y1 + y2) = (x1 * y1) + (x1 * y2) + (x2 * y1) + (x2 * y2)
    uint256 x1y1 = x1 * y1;
    if (x1 != 0) require(x1y1 / x1 == y1, "overflow x1y1 detected");

    // x1y1 needs to be multiplied back by fixed1
    // solium-disable-next-line mixedcase
    uint256 fixed_x1y1 = x1y1 * FIXED1_UINT;
    if (x1y1 != 0) require(fixed_x1y1 / x1y1 == FIXED1_UINT, "overflow x1y1 * fixed1 detected");
    x1y1 = fixed_x1y1;

    uint256 x2y1 = x2 * y1;
    if (x2 != 0) require(x2y1 / x2 == y1, "overflow x2y1 detected");

    uint256 x1y2 = x1 * y2;
    if (x1 != 0) require(x1y2 / x1 == y2, "overflow x1y2 detected");

    x2 = x2 / mulPrecision();
    y2 = y2 / mulPrecision();
    uint256 x2y2 = x2 * y2;
    if (x2 != 0) require(x2y2 / x2 == y2, "overflow x2y2 detected");

    // result = fixed1() * x1 * y1 + x1 * y2 + x2 * y1 + x2 * y2 / fixed1();
    Fraction memory result = Fraction(x1y1);
    result = add(result, Fraction(x2y1)); // Add checks for overflow
    result = add(result, Fraction(x1y2)); // Add checks for overflow
    result = add(result, Fraction(x2y2)); // Add checks for overflow
    return result;
  }

  /**
   * @notice 1/x
   * @dev
   * Test reciprocal(0) fails
   * Test reciprocal(fixed1()) returns fixed1()
   * Test reciprocal(fixed1()*fixed1()) returns 1 // Testing how the fractional is truncated
   * Test reciprocal(1+fixed1()*fixed1()) returns 0 // Testing how the fractional is truncated
   * Test reciprocal(newFixedFraction(1, 1e24)) returns newFixed(1e24)
   */
  function reciprocal(Fraction memory x) internal pure returns (Fraction memory) {
    require(x.value != 0, "can't call reciprocal(0)");
    return Fraction((FIXED1_UINT * FIXED1_UINT) / x.value); // Can't overflow
  }

  /**
   * @notice x/y. If the dividend is higher than the max dividend value, it
   * might overflow. You can use multiply(x,reciprocal(y)) instead.
   * @dev The maximum value that can be safely used as a dividend (maxNewFixed) is defined as
   * divide(maxNewFixed,newFixedFraction(1,fixed1())) is around maxUint256().
   * This yields the value 115792089237316195423570985008687907853269984665640564.
   * Test maxNewFixed equals maxUint256()/fixed1()
   * Test divide(maxNewFixed,1) equals maxNewFixed*(fixed1)
   * Test divide(maxNewFixed+1,multiply(mulPrecision(),mulPrecision())) throws
   * Test divide(fixed1(),0) fails
   * Test divide(maxNewFixed,1) = maxNewFixed*(10^digits())
   * Test divide(maxNewFixed+1,1) throws
   */
  function divide(Fraction memory x, Fraction memory y) internal pure returns (Fraction memory) {
    require(y.value != 0, "can't divide by 0");
    uint256 X = x.value * FIXED1_UINT;
    require(X / FIXED1_UINT == x.value, "overflow at divide");
    return Fraction(X / y.value);
  }

  /**
   * @notice x > y
   */
  function gt(Fraction memory x, Fraction memory y) internal pure returns (bool) {
    return x.value > y.value;
  }

  /**
   * @notice x >= y
   */
  function gte(Fraction memory x, Fraction memory y) internal pure returns (bool) {
    return x.value >= y.value;
  }

  /**
   * @notice x < y
   */
  function lt(Fraction memory x, Fraction memory y) internal pure returns (bool) {
    return x.value < y.value;
  }

  /**
   * @notice x <= y
   */
  function lte(Fraction memory x, Fraction memory y) internal pure returns (bool) {
    return x.value <= y.value;
  }

  /**
   * @notice x == y
   */
  function equals(Fraction memory x, Fraction memory y) internal pure returns (bool) {
    return x.value == y.value;
  }

  /**
   * @notice x <= 1
   */
  function isProperFraction(Fraction memory x) internal pure returns (bool) {
    return lte(x, fixed1());
  }
}