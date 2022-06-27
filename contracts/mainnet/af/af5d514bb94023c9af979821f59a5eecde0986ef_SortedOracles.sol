pragma solidity ^0.5.13;

import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "openzeppelin-solidity/contracts/ownership/Ownable.sol";

import "./interfaces/ISortedOracles.sol";
import "../common/interfaces/ICeloVersionedContract.sol";

import "../common/FixidityLib.sol";
import "../common/Initializable.sol";
import "../common/linkedlists/AddressSortedLinkedListWithMedian.sol";
import "../common/linkedlists/SortedLinkedListWithMedian.sol";

/**
 * @title Maintains a sorted list of oracle exchange rates between CELO and other currencies.
 */
contract SortedOracles is ISortedOracles, ICeloVersionedContract, Ownable, Initializable {
  using SafeMath for uint256;
  using AddressSortedLinkedListWithMedian for SortedLinkedListWithMedian.List;
  using FixidityLib for FixidityLib.Fraction;

  uint256 private constant FIXED1_UINT = 1000000000000000000000000;

  // Maps a token address to a sorted list of report values.
  mapping(address => SortedLinkedListWithMedian.List) private rates;
  // Maps a token address to a sorted list of report timestamps.
  mapping(address => SortedLinkedListWithMedian.List) private timestamps;
  mapping(address => mapping(address => bool)) public isOracle;
  mapping(address => address[]) public oracles;

  // `reportExpirySeconds` is the fallback value used to determine reporting
  // frequency. Initially it was the _only_ value but we later introduced
  // the per token mapping in `tokenReportExpirySeconds`. If a token
  // doesn't have a value in the mapping (i.e. it's 0), the fallback is used.
  // See: #getTokenReportExpirySeconds
  uint256 public reportExpirySeconds;
  mapping(address => uint256) public tokenReportExpirySeconds;

  event OracleAdded(address indexed token, address indexed oracleAddress);
  event OracleRemoved(address indexed token, address indexed oracleAddress);
  event OracleReported(
    address indexed token,
    address indexed oracle,
    uint256 timestamp,
    uint256 value
  );
  event OracleReportRemoved(address indexed token, address indexed oracle);
  event MedianUpdated(address indexed token, uint256 value);
  event ReportExpirySet(uint256 reportExpiry);
  event TokenReportExpirySet(address token, uint256 reportExpiry);

  modifier onlyOracle(address token) {
    require(isOracle[token][msg.sender], "sender was not an oracle for token addr");
    _;
  }

  /**
   * @notice Returns the storage, major, minor, and patch version of the contract.
   * @return The storage, major, minor, and patch version of the contract.
   */
  function getVersionNumber() external pure returns (uint256, uint256, uint256, uint256) {
    return (1, 1, 2, 1);
  }

  /**
   * @notice Sets initialized == true on implementation contracts
   * @param test Set to true to skip implementation initialization
   */
  constructor(bool test) public Initializable(test) {}

  /**
   * @notice Used in place of the constructor to allow the contract to be upgradable via proxy.
   * @param _reportExpirySeconds The number of seconds before a report is considered expired.
   */
  function initialize(uint256 _reportExpirySeconds) external initializer {
    _transferOwnership(msg.sender);
    setReportExpiry(_reportExpirySeconds);
  }

  /**
   * @notice Sets the report expiry parameter.
   * @param _reportExpirySeconds The number of seconds before a report is considered expired.
   */
  function setReportExpiry(uint256 _reportExpirySeconds) public onlyOwner {
    require(_reportExpirySeconds > 0, "report expiry seconds must be > 0");
    require(_reportExpirySeconds != reportExpirySeconds, "reportExpirySeconds hasn't changed");
    reportExpirySeconds = _reportExpirySeconds;
    emit ReportExpirySet(_reportExpirySeconds);
  }

  /**
   * @notice Sets the report expiry parameter for a token.
   * @param _token The address of the token to set expiry for.
   * @param _reportExpirySeconds The number of seconds before a report is considered expired.
   */
  function setTokenReportExpiry(address _token, uint256 _reportExpirySeconds) external onlyOwner {
    require(_reportExpirySeconds > 0, "report expiry seconds must be > 0");
    require(
      _reportExpirySeconds != tokenReportExpirySeconds[_token],
      "token reportExpirySeconds hasn't changed"
    );
    tokenReportExpirySeconds[_token] = _reportExpirySeconds;
    emit TokenReportExpirySet(_token, _reportExpirySeconds);
  }

  /**
   * @notice Adds a new Oracle.
   * @param token The address of the token.
   * @param oracleAddress The address of the oracle.
   */
  function addOracle(address token, address oracleAddress) external onlyOwner {
    require(
      token != address(0) && oracleAddress != address(0) && !isOracle[token][oracleAddress],
      "token addr was null or oracle addr was null or oracle addr is not an oracle for token addr"
    );
    isOracle[token][oracleAddress] = true;
    oracles[token].push(oracleAddress);
    emit OracleAdded(token, oracleAddress);
  }

  /**
   * @notice Removes an Oracle.
   * @param token The address of the token.
   * @param oracleAddress The address of the oracle.
   * @param index The index of `oracleAddress` in the list of oracles.
   */
  function removeOracle(address token, address oracleAddress, uint256 index) external onlyOwner {
    require(
      token != address(0) &&
        oracleAddress != address(0) &&
        oracles[token].length > index &&
        oracles[token][index] == oracleAddress,
      "token addr null or oracle addr null or index of token oracle not mapped to oracle addr"
    );
    isOracle[token][oracleAddress] = false;
    oracles[token][index] = oracles[token][oracles[token].length.sub(1)];
    oracles[token].length = oracles[token].length.sub(1);
    if (reportExists(token, oracleAddress)) {
      removeReport(token, oracleAddress);
    }
    emit OracleRemoved(token, oracleAddress);
  }

  /**
   * @notice Removes a report that is expired.
   * @param token The address of the token for which the CELO exchange rate is being reported.
   * @param n The number of expired reports to remove, at most (deterministic upper gas bound).
   */
  function removeExpiredReports(address token, uint256 n) external {
    require(
      token != address(0) && n < timestamps[token].getNumElements(),
      "token addr null or trying to remove too many reports"
    );
    for (uint256 i = 0; i < n; i = i.add(1)) {
      (bool isExpired, address oldestAddress) = isOldestReportExpired(token);
      if (isExpired) {
        removeReport(token, oldestAddress);
      } else {
        break;
      }
    }
  }

  /**
   * @notice Check if last report is expired.
   * @param token The address of the token for which the CELO exchange rate is being reported.
   * @return bool isExpired and the address of the last report
   */
  function isOldestReportExpired(address token) public view returns (bool, address) {
    require(token != address(0));
    address oldest = timestamps[token].getTail();
    uint256 timestamp = timestamps[token].getValue(oldest);
    // solhint-disable-next-line not-rely-on-time
    if (now.sub(timestamp) >= getTokenReportExpirySeconds(token)) {
      return (true, oldest);
    }
    return (false, oldest);
  }

  /**
   * @notice Updates an oracle value and the median.
   * @param token The address of the token for which the CELO exchange rate is being reported.
   * @param value The amount of `token` equal to one CELO, expressed as a fixidity value.
   * @param lesserKey The element which should be just left of the new oracle value.
   * @param greaterKey The element which should be just right of the new oracle value.
   * @dev Note that only one of `lesserKey` or `greaterKey` needs to be correct to reduce friction.
   */
  function report(address token, uint256 value, address lesserKey, address greaterKey)
    external
    onlyOracle(token)
  {
    uint256 originalMedian = rates[token].getMedianValue();
    if (rates[token].contains(msg.sender)) {
      rates[token].update(msg.sender, value, lesserKey, greaterKey);

      // Rather than update the timestamp, we remove it and re-add it at the
      // head of the list later. The reason for this is that we need to handle
      // a few different cases:
      //   1. This oracle is the only one to report so far. lesserKey = address(0)
      //   2. Other oracles have reported since this one's last report. lesserKey = getHead()
      //   3. Other oracles have reported, but the most recent is this one.
      //      lesserKey = key immediately after getHead()
      //
      // However, if we just remove this timestamp, timestamps[token].getHead()
      // does the right thing in all cases.
      timestamps[token].remove(msg.sender);
    } else {
      rates[token].insert(msg.sender, value, lesserKey, greaterKey);
    }
    timestamps[token].insert(
      msg.sender,
      // solhint-disable-next-line not-rely-on-time
      now,
      timestamps[token].getHead(),
      address(0)
    );
    emit OracleReported(token, msg.sender, now, value);
    uint256 newMedian = rates[token].getMedianValue();
    if (newMedian != originalMedian) {
      emit MedianUpdated(token, newMedian);
    }
  }

  /**
   * @notice Returns the number of rates.
   * @param token The address of the token for which the CELO exchange rate is being reported.
   * @return The number of reported oracle rates for `token`.
   */
  function numRates(address token) public view returns (uint256) {
    return rates[token].getNumElements();
  }

  /**
   * @notice Returns the median rate.
   * @param token The address of the token for which the CELO exchange rate is being reported.
   * @return The median exchange rate for `token`.
   */
  function medianRate(address token) external view returns (uint256, uint256) {
    return (rates[token].getMedianValue(), numRates(token) == 0 ? 0 : FIXED1_UINT);
  }

  /**
   * @notice Gets all elements from the doubly linked list.
   * @param token The address of the token for which the CELO exchange rate is being reported.
   * @return An unpacked list of elements from largest to smallest.
   */
  function getRates(address token)
    external
    view
    returns (address[] memory, uint256[] memory, SortedLinkedListWithMedian.MedianRelation[] memory)
  {
    return rates[token].getElements();
  }

  /**
   * @notice Returns the number of timestamps.
   * @param token The address of the token for which the CELO exchange rate is being reported.
   * @return The number of oracle report timestamps for `token`.
   */
  function numTimestamps(address token) public view returns (uint256) {
    return timestamps[token].getNumElements();
  }

  /**
   * @notice Returns the median timestamp.
   * @param token The address of the token for which the CELO exchange rate is being reported.
   * @return The median report timestamp for `token`.
   */
  function medianTimestamp(address token) external view returns (uint256) {
    return timestamps[token].getMedianValue();
  }

  /**
   * @notice Gets all elements from the doubly linked list.
   * @param token The address of the token for which the CELO exchange rate is being reported.
   * @return An unpacked list of elements from largest to smallest.
   */
  function getTimestamps(address token)
    external
    view
    returns (address[] memory, uint256[] memory, SortedLinkedListWithMedian.MedianRelation[] memory)
  {
    return timestamps[token].getElements();
  }

  /**
   * @notice Returns whether a report exists on token from oracle.
   * @param token The address of the token for which the CELO exchange rate is being reported.
   * @param oracle The oracle whose report should be checked.
   */
  function reportExists(address token, address oracle) internal view returns (bool) {
    return rates[token].contains(oracle) && timestamps[token].contains(oracle);
  }

  /**
   * @notice Returns the list of oracles for a particular token.
   * @param token The address of the token whose oracles should be returned.
   * @return The list of oracles for a particular token.
   */
  function getOracles(address token) external view returns (address[] memory) {
    return oracles[token];
  }

  /**
   * @notice Returns the expiry for the token if exists, if not the default.
   * @param token The address of the token.
   * @return The report expiry in seconds.
   */
  function getTokenReportExpirySeconds(address token) public view returns (uint256) {
    if (tokenReportExpirySeconds[token] == 0) {
      return reportExpirySeconds;
    }

    return tokenReportExpirySeconds[token];
  }

  /**
   * @notice Removes an oracle value and updates the median.
   * @param token The address of the token for which the CELO exchange rate is being reported.
   * @param oracle The oracle whose value should be removed.
   * @dev This can be used to delete elements for oracles that have been removed.
   * However, a > 1 elements reports list should always be maintained
   */
  function removeReport(address token, address oracle) private {
    if (numTimestamps(token) == 1 && reportExists(token, oracle)) return;
    uint256 originalMedian = rates[token].getMedianValue();
    rates[token].remove(oracle);
    timestamps[token].remove(oracle);
    emit OracleReportRemoved(token, oracle);
    uint256 newMedian = rates[token].getMedianValue();
    if (newMedian != originalMedian) {
      emit MedianUpdated(token, newMedian);
    }
  }
}


pragma solidity ^0.5.13;

import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "./LinkedList.sol";

/**
 * @title Maintains a sorted list of unsigned ints keyed by bytes32.
 */
library SortedLinkedList {
  using SafeMath for uint256;
  using LinkedList for LinkedList.List;

  struct List {
    LinkedList.List list;
    mapping(bytes32 => uint256) values;
  }

  /**
   * @notice Inserts an element into a doubly linked list.
   * @param list A storage pointer to the underlying list.
   * @param key The key of the element to insert.
   * @param value The element value.
   * @param lesserKey The key of the element less than the element to insert.
   * @param greaterKey The key of the element greater than the element to insert.
   */
  function insert(
    List storage list,
    bytes32 key,
    uint256 value,
    bytes32 lesserKey,
    bytes32 greaterKey
  ) internal {
    require(
      key != bytes32(0) && key != lesserKey && key != greaterKey && !contains(list, key),
      "invalid key"
    );
    require(
      (lesserKey != bytes32(0) || greaterKey != bytes32(0)) || list.list.numElements == 0,
      "greater and lesser key zero"
    );
    require(contains(list, lesserKey) || lesserKey == bytes32(0), "invalid lesser key");
    require(contains(list, greaterKey) || greaterKey == bytes32(0), "invalid greater key");
    (lesserKey, greaterKey) = getLesserAndGreater(list, value, lesserKey, greaterKey);
    list.list.insert(key, lesserKey, greaterKey);
    list.values[key] = value;
  }

  /**
   * @notice Removes an element from the doubly linked list.
   * @param list A storage pointer to the underlying list.
   * @param key The key of the element to remove.
   */
  function remove(List storage list, bytes32 key) internal {
    list.list.remove(key);
    list.values[key] = 0;
  }

  /**
   * @notice Updates an element in the list.
   * @param list A storage pointer to the underlying list.
   * @param key The element key.
   * @param value The element value.
   * @param lesserKey The key of the element will be just left of `key` after the update.
   * @param greaterKey The key of the element will be just right of `key` after the update.
   * @dev Note that only one of "lesserKey" or "greaterKey" needs to be correct to reduce friction.
   */
  function update(
    List storage list,
    bytes32 key,
    uint256 value,
    bytes32 lesserKey,
    bytes32 greaterKey
  ) internal {
    remove(list, key);
    insert(list, key, value, lesserKey, greaterKey);
  }

  /**
   * @notice Inserts an element at the tail of the doubly linked list.
   * @param list A storage pointer to the underlying list.
   * @param key The key of the element to insert.
   */
  function push(List storage list, bytes32 key) internal {
    insert(list, key, 0, bytes32(0), list.list.tail);
  }

  /**
   * @notice Removes N elements from the head of the list and returns their keys.
   * @param list A storage pointer to the underlying list.
   * @param n The number of elements to pop.
   * @return The keys of the popped elements.
   */
  function popN(List storage list, uint256 n) internal returns (bytes32[] memory) {
    require(n <= list.list.numElements, "not enough elements");
    bytes32[] memory keys = new bytes32[](n);
    for (uint256 i = 0; i < n; i = i.add(1)) {
      bytes32 key = list.list.head;
      keys[i] = key;
      remove(list, key);
    }
    return keys;
  }

  /**
   * @notice Returns whether or not a particular key is present in the sorted list.
   * @param list A storage pointer to the underlying list.
   * @param key The element key.
   * @return Whether or not the key is in the sorted list.
   */
  function contains(List storage list, bytes32 key) internal view returns (bool) {
    return list.list.contains(key);
  }

  /**
   * @notice Returns the value for a particular key in the sorted list.
   * @param list A storage pointer to the underlying list.
   * @param key The element key.
   * @return The element value.
   */
  function getValue(List storage list, bytes32 key) internal view returns (uint256) {
    return list.values[key];
  }

  /**
   * @notice Gets all elements from the doubly linked list.
   * @param list A storage pointer to the underlying list.
   * @return An unpacked list of elements from largest to smallest.
   */
  function getElements(List storage list)
    internal
    view
    returns (bytes32[] memory, uint256[] memory)
  {
    bytes32[] memory keys = getKeys(list);
    uint256[] memory values = new uint256[](keys.length);
    for (uint256 i = 0; i < keys.length; i = i.add(1)) {
      values[i] = list.values[keys[i]];
    }
    return (keys, values);
  }

  /**
   * @notice Gets all element keys from the doubly linked list.
   * @param list A storage pointer to the underlying list.
   * @return All element keys from head to tail.
   */
  function getKeys(List storage list) internal view returns (bytes32[] memory) {
    return list.list.getKeys();
  }

  /**
   * @notice Returns first N greatest elements of the list.
   * @param list A storage pointer to the underlying list.
   * @param n The number of elements to return.
   * @return The keys of the first n elements.
   * @dev Reverts if n is greater than the number of elements in the list.
   */
  function headN(List storage list, uint256 n) internal view returns (bytes32[] memory) {
    return list.list.headN(n);
  }

  /**
   * @notice Returns the keys of the elements greaterKey than and less than the provided value.
   * @param list A storage pointer to the underlying list.
   * @param value The element value.
   * @param lesserKey The key of the element which could be just left of the new value.
   * @param greaterKey The key of the element which could be just right of the new value.
   * @return The correct lesserKey/greaterKey keys.
   */
  function getLesserAndGreater(
    List storage list,
    uint256 value,
    bytes32 lesserKey,
    bytes32 greaterKey
  ) private view returns (bytes32, bytes32) {
    // Check for one of the following conditions and fail if none are met:
    //   1. The value is less than the current lowest value
    //   2. The value is greater than the current greatest value
    //   3. The value is just greater than the value for `lesserKey`
    //   4. The value is just less than the value for `greaterKey`
    if (lesserKey == bytes32(0) && isValueBetween(list, value, lesserKey, list.list.tail)) {
      return (lesserKey, list.list.tail);
    } else if (
      greaterKey == bytes32(0) && isValueBetween(list, value, list.list.head, greaterKey)
    ) {
      return (list.list.head, greaterKey);
    } else if (
      lesserKey != bytes32(0) &&
      isValueBetween(list, value, lesserKey, list.list.elements[lesserKey].nextKey)
    ) {
      return (lesserKey, list.list.elements[lesserKey].nextKey);
    } else if (
      greaterKey != bytes32(0) &&
      isValueBetween(list, value, list.list.elements[greaterKey].previousKey, greaterKey)
    ) {
      return (list.list.elements[greaterKey].previousKey, greaterKey);
    } else {
      require(false, "get lesser and greater failure");
    }
  }

  /**
   * @notice Returns whether or not a given element is between two other elements.
   * @param list A storage pointer to the underlying list.
   * @param value The element value.
   * @param lesserKey The key of the element whose value should be lesserKey.
   * @param greaterKey The key of the element whose value should be greaterKey.
   * @return True if the given element is between the two other elements.
   */
  function isValueBetween(List storage list, uint256 value, bytes32 lesserKey, bytes32 greaterKey)
    private
    view
    returns (bool)
  {
    bool isLesser = lesserKey == bytes32(0) || list.values[lesserKey] <= value;
    bool isGreater = greaterKey == bytes32(0) || list.values[greaterKey] >= value;
    return isLesser && isGreater;
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

import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "./LinkedList.sol";
import "./SortedLinkedList.sol";

/**
 * @title Maintains a sorted list of unsigned ints keyed by bytes32.
 */
library SortedLinkedListWithMedian {
  using SafeMath for uint256;
  using SortedLinkedList for SortedLinkedList.List;

  enum MedianAction { None, Lesser, Greater }

  enum MedianRelation { Undefined, Lesser, Greater, Equal }

  struct List {
    SortedLinkedList.List list;
    bytes32 median;
    mapping(bytes32 => MedianRelation) relation;
  }

  /**
   * @notice Inserts an element into a doubly linked list.
   * @param list A storage pointer to the underlying list.
   * @param key The key of the element to insert.
   * @param value The element value.
   * @param lesserKey The key of the element less than the element to insert.
   * @param greaterKey The key of the element greater than the element to insert.
   */
  function insert(
    List storage list,
    bytes32 key,
    uint256 value,
    bytes32 lesserKey,
    bytes32 greaterKey
  ) internal {
    list.list.insert(key, value, lesserKey, greaterKey);
    LinkedList.Element storage element = list.list.list.elements[key];

    MedianAction action = MedianAction.None;
    if (list.list.list.numElements == 1) {
      list.median = key;
      list.relation[key] = MedianRelation.Equal;
    } else if (list.list.list.numElements % 2 == 1) {
      // When we have an odd number of elements, and the element that we inserted is less than
      // the previous median, we need to slide the median down one element, since we had previously
      // selected the greater of the two middle elements.
      if (
        element.previousKey == bytes32(0) ||
        list.relation[element.previousKey] == MedianRelation.Lesser
      ) {
        action = MedianAction.Lesser;
        list.relation[key] = MedianRelation.Lesser;
      } else {
        list.relation[key] = MedianRelation.Greater;
      }
    } else {
      // When we have an even number of elements, and the element that we inserted is greater than
      // the previous median, we need to slide the median up one element, since we always select
      // the greater of the two middle elements.
      if (
        element.nextKey == bytes32(0) || list.relation[element.nextKey] == MedianRelation.Greater
      ) {
        action = MedianAction.Greater;
        list.relation[key] = MedianRelation.Greater;
      } else {
        list.relation[key] = MedianRelation.Lesser;
      }
    }
    updateMedian(list, action);
  }

  /**
   * @notice Removes an element from the doubly linked list.
   * @param list A storage pointer to the underlying list.
   * @param key The key of the element to remove.
   */
  function remove(List storage list, bytes32 key) internal {
    MedianAction action = MedianAction.None;
    if (list.list.list.numElements == 0) {
      list.median = bytes32(0);
    } else if (list.list.list.numElements % 2 == 0) {
      // When we have an even number of elements, we always choose the higher of the two medians.
      // Thus, if the element we're removing is greaterKey than or equal to the median we need to
      // slide the median left by one.
      if (
        list.relation[key] == MedianRelation.Greater || list.relation[key] == MedianRelation.Equal
      ) {
        action = MedianAction.Lesser;
      }
    } else {
      // When we don't have an even number of elements, we just choose the median value.
      // Thus, if the element we're removing is less than or equal to the median, we need to slide
      // median right by one.
      if (
        list.relation[key] == MedianRelation.Lesser || list.relation[key] == MedianRelation.Equal
      ) {
        action = MedianAction.Greater;
      }
    }
    updateMedian(list, action);

    list.list.remove(key);
  }

  /**
   * @notice Updates an element in the list.
   * @param list A storage pointer to the underlying list.
   * @param key The element key.
   * @param value The element value.
   * @param lesserKey The key of the element will be just left of `key` after the update.
   * @param greaterKey The key of the element will be just right of `key` after the update.
   * @dev Note that only one of "lesserKey" or "greaterKey" needs to be correct to reduce friction.
   */
  function update(
    List storage list,
    bytes32 key,
    uint256 value,
    bytes32 lesserKey,
    bytes32 greaterKey
  ) internal {
    remove(list, key);
    insert(list, key, value, lesserKey, greaterKey);
  }

  /**
   * @notice Inserts an element at the tail of the doubly linked list.
   * @param list A storage pointer to the underlying list.
   * @param key The key of the element to insert.
   */
  function push(List storage list, bytes32 key) internal {
    insert(list, key, 0, bytes32(0), list.list.list.tail);
  }

  /**
   * @notice Removes N elements from the head of the list and returns their keys.
   * @param list A storage pointer to the underlying list.
   * @param n The number of elements to pop.
   * @return The keys of the popped elements.
   */
  function popN(List storage list, uint256 n) internal returns (bytes32[] memory) {
    require(n <= list.list.list.numElements, "not enough elements");
    bytes32[] memory keys = new bytes32[](n);
    for (uint256 i = 0; i < n; i = i.add(1)) {
      bytes32 key = list.list.list.head;
      keys[i] = key;
      remove(list, key);
    }
    return keys;
  }

  /**
   * @notice Returns whether or not a particular key is present in the sorted list.
   * @param list A storage pointer to the underlying list.
   * @param key The element key.
   * @return Whether or not the key is in the sorted list.
   */
  function contains(List storage list, bytes32 key) internal view returns (bool) {
    return list.list.contains(key);
  }

  /**
   * @notice Returns the value for a particular key in the sorted list.
   * @param list A storage pointer to the underlying list.
   * @param key The element key.
   * @return The element value.
   */
  function getValue(List storage list, bytes32 key) internal view returns (uint256) {
    return list.list.values[key];
  }

  /**
   * @notice Returns the median value of the sorted list.
   * @param list A storage pointer to the underlying list.
   * @return The median value.
   */
  function getMedianValue(List storage list) internal view returns (uint256) {
    return getValue(list, list.median);
  }

  /**
   * @notice Returns the key of the first element in the list.
   * @param list A storage pointer to the underlying list.
   * @return The key of the first element in the list.
   */
  function getHead(List storage list) internal view returns (bytes32) {
    return list.list.list.head;
  }

  /**
   * @notice Returns the key of the median element in the list.
   * @param list A storage pointer to the underlying list.
   * @return The key of the median element in the list.
   */
  function getMedian(List storage list) internal view returns (bytes32) {
    return list.median;
  }

  /**
   * @notice Returns the key of the last element in the list.
   * @param list A storage pointer to the underlying list.
   * @return The key of the last element in the list.
   */
  function getTail(List storage list) internal view returns (bytes32) {
    return list.list.list.tail;
  }

  /**
   * @notice Returns the number of elements in the list.
   * @param list A storage pointer to the underlying list.
   * @return The number of elements in the list.
   */
  function getNumElements(List storage list) internal view returns (uint256) {
    return list.list.list.numElements;
  }

  /**
   * @notice Gets all elements from the doubly linked list.
   * @param list A storage pointer to the underlying list.
   * @return An unpacked list of elements from largest to smallest.
   */
  function getElements(List storage list)
    internal
    view
    returns (bytes32[] memory, uint256[] memory, MedianRelation[] memory)
  {
    bytes32[] memory keys = getKeys(list);
    uint256[] memory values = new uint256[](keys.length);
    MedianRelation[] memory relations = new MedianRelation[](keys.length);
    for (uint256 i = 0; i < keys.length; i = i.add(1)) {
      values[i] = list.list.values[keys[i]];
      relations[i] = list.relation[keys[i]];
    }
    return (keys, values, relations);
  }

  /**
   * @notice Gets all element keys from the doubly linked list.
   * @param list A storage pointer to the underlying list.
   * @return All element keys from head to tail.
   */
  function getKeys(List storage list) internal view returns (bytes32[] memory) {
    return list.list.getKeys();
  }

  /**
   * @notice Moves the median pointer right or left of its current value.
   * @param list A storage pointer to the underlying list.
   * @param action Which direction to move the median pointer.
   */
  function updateMedian(List storage list, MedianAction action) private {
    LinkedList.Element storage previousMedian = list.list.list.elements[list.median];
    if (action == MedianAction.Lesser) {
      list.relation[list.median] = MedianRelation.Greater;
      list.median = previousMedian.previousKey;
    } else if (action == MedianAction.Greater) {
      list.relation[list.median] = MedianRelation.Lesser;
      list.median = previousMedian.nextKey;
    }
    list.relation[list.median] = MedianRelation.Equal;
  }
}


pragma solidity ^0.5.13;

import "openzeppelin-solidity/contracts/math/SafeMath.sol";

/**
 * @title Maintains a doubly linked list keyed by bytes32.
 * @dev Following the `next` pointers will lead you to the head, rather than the tail.
 */
library LinkedList {
  using SafeMath for uint256;

  struct Element {
    bytes32 previousKey;
    bytes32 nextKey;
    bool exists;
  }

  struct List {
    bytes32 head;
    bytes32 tail;
    uint256 numElements;
    mapping(bytes32 => Element) elements;
  }

  /**
   * @notice Inserts an element into a doubly linked list.
   * @param list A storage pointer to the underlying list.
   * @param key The key of the element to insert.
   * @param previousKey The key of the element that comes before the element to insert.
   * @param nextKey The key of the element that comes after the element to insert.
   */
  function insert(List storage list, bytes32 key, bytes32 previousKey, bytes32 nextKey) internal {
    require(key != bytes32(0), "Key must be defined");
    require(!contains(list, key), "Can't insert an existing element");
    require(
      previousKey != key && nextKey != key,
      "Key cannot be the same as previousKey or nextKey"
    );

    Element storage element = list.elements[key];
    element.exists = true;

    if (list.numElements == 0) {
      list.tail = key;
      list.head = key;
    } else {
      require(
        previousKey != bytes32(0) || nextKey != bytes32(0),
        "Either previousKey or nextKey must be defined"
      );

      element.previousKey = previousKey;
      element.nextKey = nextKey;

      if (previousKey != bytes32(0)) {
        require(
          contains(list, previousKey),
          "If previousKey is defined, it must exist in the list"
        );
        Element storage previousElement = list.elements[previousKey];
        require(previousElement.nextKey == nextKey, "previousKey must be adjacent to nextKey");
        previousElement.nextKey = key;
      } else {
        list.tail = key;
      }

      if (nextKey != bytes32(0)) {
        require(contains(list, nextKey), "If nextKey is defined, it must exist in the list");
        Element storage nextElement = list.elements[nextKey];
        require(nextElement.previousKey == previousKey, "previousKey must be adjacent to nextKey");
        nextElement.previousKey = key;
      } else {
        list.head = key;
      }
    }

    list.numElements = list.numElements.add(1);
  }

  /**
   * @notice Inserts an element at the tail of the doubly linked list.
   * @param list A storage pointer to the underlying list.
   * @param key The key of the element to insert.
   */
  function push(List storage list, bytes32 key) internal {
    insert(list, key, bytes32(0), list.tail);
  }

  /**
   * @notice Removes an element from the doubly linked list.
   * @param list A storage pointer to the underlying list.
   * @param key The key of the element to remove.
   */
  function remove(List storage list, bytes32 key) internal {
    Element storage element = list.elements[key];
    require(key != bytes32(0) && contains(list, key), "key not in list");
    if (element.previousKey != bytes32(0)) {
      Element storage previousElement = list.elements[element.previousKey];
      previousElement.nextKey = element.nextKey;
    } else {
      list.tail = element.nextKey;
    }

    if (element.nextKey != bytes32(0)) {
      Element storage nextElement = list.elements[element.nextKey];
      nextElement.previousKey = element.previousKey;
    } else {
      list.head = element.previousKey;
    }

    delete list.elements[key];
    list.numElements = list.numElements.sub(1);
  }

  /**
   * @notice Updates an element in the list.
   * @param list A storage pointer to the underlying list.
   * @param key The element key.
   * @param previousKey The key of the element that comes before the updated element.
   * @param nextKey The key of the element that comes after the updated element.
   */
  function update(List storage list, bytes32 key, bytes32 previousKey, bytes32 nextKey) internal {
    require(
      key != bytes32(0) && key != previousKey && key != nextKey && contains(list, key),
      "key on in list"
    );
    remove(list, key);
    insert(list, key, previousKey, nextKey);
  }

  /**
   * @notice Returns whether or not a particular key is present in the sorted list.
   * @param list A storage pointer to the underlying list.
   * @param key The element key.
   * @return Whether or not the key is in the sorted list.
   */
  function contains(List storage list, bytes32 key) internal view returns (bool) {
    return list.elements[key].exists;
  }

  /**
   * @notice Returns the keys of the N elements at the head of the list.
   * @param list A storage pointer to the underlying list.
   * @param n The number of elements to return.
   * @return The keys of the N elements at the head of the list.
   * @dev Reverts if n is greater than the number of elements in the list.
   */
  function headN(List storage list, uint256 n) internal view returns (bytes32[] memory) {
    require(n <= list.numElements, "not enough elements");
    bytes32[] memory keys = new bytes32[](n);
    bytes32 key = list.head;
    for (uint256 i = 0; i < n; i = i.add(1)) {
      keys[i] = key;
      key = list.elements[key].previousKey;
    }
    return keys;
  }

  /**
   * @notice Gets all element keys from the doubly linked list.
   * @param list A storage pointer to the underlying list.
   * @return All element keys from head to tail.
   */
  function getKeys(List storage list) internal view returns (bytes32[] memory) {
    return headN(list, list.numElements);
  }
}


pragma solidity ^0.5.13;

import "openzeppelin-solidity/contracts/math/SafeMath.sol";

import "./SortedLinkedListWithMedian.sol";

/**
 * @title Maintains a sorted list of unsigned ints keyed by address.
 */
library AddressSortedLinkedListWithMedian {
  using SafeMath for uint256;
  using SortedLinkedListWithMedian for SortedLinkedListWithMedian.List;

  function toBytes(address a) public pure returns (bytes32) {
    return bytes32(uint256(a) << 96);
  }

  function toAddress(bytes32 b) public pure returns (address) {
    return address(uint256(b) >> 96);
  }

  /**
   * @notice Inserts an element into a doubly linked list.
   * @param list A storage pointer to the underlying list.
   * @param key The key of the element to insert.
   * @param value The element value.
   * @param lesserKey The key of the element less than the element to insert.
   * @param greaterKey The key of the element greater than the element to insert.
   */
  function insert(
    SortedLinkedListWithMedian.List storage list,
    address key,
    uint256 value,
    address lesserKey,
    address greaterKey
  ) public {
    list.insert(toBytes(key), value, toBytes(lesserKey), toBytes(greaterKey));
  }

  /**
   * @notice Removes an element from the doubly linked list.
   * @param list A storage pointer to the underlying list.
   * @param key The key of the element to remove.
   */
  function remove(SortedLinkedListWithMedian.List storage list, address key) public {
    list.remove(toBytes(key));
  }

  /**
   * @notice Updates an element in the list.
   * @param list A storage pointer to the underlying list.
   * @param key The element key.
   * @param value The element value.
   * @param lesserKey The key of the element will be just left of `key` after the update.
   * @param greaterKey The key of the element will be just right of `key` after the update.
   * @dev Note that only one of "lesserKey" or "greaterKey" needs to be correct to reduce friction.
   */
  function update(
    SortedLinkedListWithMedian.List storage list,
    address key,
    uint256 value,
    address lesserKey,
    address greaterKey
  ) public {
    list.update(toBytes(key), value, toBytes(lesserKey), toBytes(greaterKey));
  }

  /**
   * @notice Returns whether or not a particular key is present in the sorted list.
   * @param list A storage pointer to the underlying list.
   * @param key The element key.
   * @return Whether or not the key is in the sorted list.
   */
  function contains(SortedLinkedListWithMedian.List storage list, address key)
    public
    view
    returns (bool)
  {
    return list.contains(toBytes(key));
  }

  /**
   * @notice Returns the value for a particular key in the sorted list.
   * @param list A storage pointer to the underlying list.
   * @param key The element key.
   * @return The element value.
   */
  function getValue(SortedLinkedListWithMedian.List storage list, address key)
    public
    view
    returns (uint256)
  {
    return list.getValue(toBytes(key));
  }

  /**
   * @notice Returns the median value of the sorted list.
   * @param list A storage pointer to the underlying list.
   * @return The median value.
   */
  function getMedianValue(SortedLinkedListWithMedian.List storage list)
    public
    view
    returns (uint256)
  {
    return list.getValue(list.median);
  }

  /**
   * @notice Returns the key of the first element in the list.
   * @param list A storage pointer to the underlying list.
   * @return The key of the first element in the list.
   */
  function getHead(SortedLinkedListWithMedian.List storage list) external view returns (address) {
    return toAddress(list.getHead());
  }

  /**
   * @notice Returns the key of the median element in the list.
   * @param list A storage pointer to the underlying list.
   * @return The key of the median element in the list.
   */
  function getMedian(SortedLinkedListWithMedian.List storage list) external view returns (address) {
    return toAddress(list.getMedian());
  }

  /**
   * @notice Returns the key of the last element in the list.
   * @param list A storage pointer to the underlying list.
   * @return The key of the last element in the list.
   */
  function getTail(SortedLinkedListWithMedian.List storage list) external view returns (address) {
    return toAddress(list.getTail());
  }

  /**
   * @notice Returns the number of elements in the list.
   * @param list A storage pointer to the underlying list.
   * @return The number of elements in the list.
   */
  function getNumElements(SortedLinkedListWithMedian.List storage list)
    external
    view
    returns (uint256)
  {
    return list.getNumElements();
  }

  /**
   * @notice Gets all elements from the doubly linked list.
   * @param list A storage pointer to the underlying list.
   * @return An unpacked list of elements from largest to smallest.
   */
  function getElements(SortedLinkedListWithMedian.List storage list)
    public
    view
    returns (address[] memory, uint256[] memory, SortedLinkedListWithMedian.MedianRelation[] memory)
  {
    bytes32[] memory byteKeys = list.getKeys();
    address[] memory keys = new address[](byteKeys.length);
    uint256[] memory values = new uint256[](byteKeys.length);
    // prettier-ignore
    SortedLinkedListWithMedian.MedianRelation[] memory relations =
      new SortedLinkedListWithMedian.MedianRelation[](keys.length);
    for (uint256 i = 0; i < byteKeys.length; i = i.add(1)) {
      keys[i] = toAddress(byteKeys[i]);
      values[i] = list.getValue(byteKeys[i]);
      relations[i] = list.relation[byteKeys[i]];
    }
    return (keys, values, relations);
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