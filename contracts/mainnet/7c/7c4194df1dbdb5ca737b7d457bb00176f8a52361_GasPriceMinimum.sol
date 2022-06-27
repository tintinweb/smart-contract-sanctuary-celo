pragma solidity ^0.5.13;

import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "openzeppelin-solidity/contracts/ownership/Ownable.sol";

import "./CalledByVm.sol";
import "./Initializable.sol";
import "./interfaces/ICeloVersionedContract.sol";
import "./FixidityLib.sol";
import "./UsingRegistry.sol";
import "../stability/interfaces/ISortedOracles.sol";

/**
 * @title Stores and provides gas price minimum for various currencies.
 */
contract GasPriceMinimum is
  ICeloVersionedContract,
  Ownable,
  Initializable,
  UsingRegistry,
  CalledByVm
{
  using FixidityLib for FixidityLib.Fraction;
  using SafeMath for uint256;

  event TargetDensitySet(uint256 targetDensity);
  event GasPriceMinimumFloorSet(uint256 gasPriceMinimumFloor);
  event AdjustmentSpeedSet(uint256 adjustmentSpeed);
  event GasPriceMinimumUpdated(uint256 gasPriceMinimum);

  uint256 public gasPriceMinimum;
  uint256 public gasPriceMinimumFloor;

  // Block congestion level targeted by the gas price minimum calculation.
  FixidityLib.Fraction public targetDensity;

  // Speed of gas price minimum adjustment due to congestion.
  FixidityLib.Fraction public adjustmentSpeed;

  /**
   * @notice Sets initialized == true on implementation contracts
   * @param test Set to true to skip implementation initialization
   */
  constructor(bool test) public Initializable(test) {}

  /**
   * @notice Returns the storage, major, minor, and patch version of the contract.
   * @return The storage, major, minor, and patch version of the contract.
   */
  function getVersionNumber() external pure returns (uint256, uint256, uint256, uint256) {
    return (1, 1, 1, 0);
  }

  /**
   * @notice Used in place of the constructor to allow the contract to be upgradable via proxy.
   * @param _registryAddress The address of the registry core smart contract.
   * @param _gasPriceMinimumFloor The lowest value the gas price minimum can be.
   * @param _targetDensity The target gas fullness of blocks, expressed as a fixidity fraction.
   * @param _adjustmentSpeed How quickly the minimum changes, expressed as a fixidity fraction.
   */
  function initialize(
    address _registryAddress,
    uint256 _gasPriceMinimumFloor,
    uint256 _targetDensity,
    uint256 _adjustmentSpeed
  ) external initializer {
    _transferOwnership(msg.sender);
    setRegistry(_registryAddress);
    gasPriceMinimum = _gasPriceMinimumFloor;
    setGasPriceMinimumFloor(_gasPriceMinimumFloor);
    setTargetDensity(_targetDensity);
    setAdjustmentSpeed(_adjustmentSpeed);
  }

  /**
   * @notice Set a multiplier that impacts how quickly gas price minimum is adjusted.
   * @param _adjustmentSpeed How quickly the minimum changes, expressed as a fixidity fraction.
   * @dev Value is expected to be < 1.
   */
  function setAdjustmentSpeed(uint256 _adjustmentSpeed) public onlyOwner {
    adjustmentSpeed = FixidityLib.wrap(_adjustmentSpeed);
    require(adjustmentSpeed.lt(FixidityLib.fixed1()), "adjustment speed must be smaller than 1");
    emit AdjustmentSpeedSet(_adjustmentSpeed);
  }

  /**
   * @notice Set the block density targeted by the gas price minimum algorithm.
   * @param _targetDensity The target gas fullness of blocks, expressed as a fixidity fraction.
   * @dev Value is expected to be < 1.
   */
  function setTargetDensity(uint256 _targetDensity) public onlyOwner {
    targetDensity = FixidityLib.wrap(_targetDensity);
    require(targetDensity.lt(FixidityLib.fixed1()), "target density must be smaller than 1");
    emit TargetDensitySet(_targetDensity);
  }

  /**
   * @notice Set the minimum gas price treshold.
   * @param _gasPriceMinimumFloor The lowest value the gas price minimum can be.
   * @dev Value is expected to be > 0.
   */
  function setGasPriceMinimumFloor(uint256 _gasPriceMinimumFloor) public onlyOwner {
    require(_gasPriceMinimumFloor > 0, "gas price minimum floor must be greater than zero");
    gasPriceMinimumFloor = _gasPriceMinimumFloor;
    emit GasPriceMinimumFloorSet(_gasPriceMinimumFloor);
  }

  /**
   * @notice Retrieve the current gas price minimum for a currency.
   * @param tokenAddress The currency the gas price should be in (defaults to gold).
   * @return current gas price minimum in the requested currency
   */
  function getGasPriceMinimum(address tokenAddress) external view returns (uint256) {
    if (
      tokenAddress == address(0) ||
      tokenAddress == registry.getAddressForOrDie(GOLD_TOKEN_REGISTRY_ID)
    ) {
      return gasPriceMinimum;
    } else {
      ISortedOracles sortedOracles = ISortedOracles(
        registry.getAddressForOrDie(SORTED_ORACLES_REGISTRY_ID)
      );
      uint256 rateNumerator;
      uint256 rateDenominator;
      (rateNumerator, rateDenominator) = sortedOracles.medianRate(tokenAddress);
      return (gasPriceMinimum.mul(rateNumerator).div(rateDenominator));
    }
  }

  /**
   * @notice Adjust the gas price minimum based on governable parameters
   * and block congestion.
   * @param blockGasTotal The amount of gas in the most recent block.
   * @param blockGasLimit The maxBlockGasLimit of the past block.
   * @return result of the calculation (new gas price minimum)
   */
  function updateGasPriceMinimum(uint256 blockGasTotal, uint256 blockGasLimit)
    external
    onlyVm
    returns (uint256)
  {
    gasPriceMinimum = getUpdatedGasPriceMinimum(blockGasTotal, blockGasLimit);
    emit GasPriceMinimumUpdated(gasPriceMinimum);
    return gasPriceMinimum;
  }

  /**
   * @notice Calculates the gas price minimum based on governable parameters
   * and block congestion.
   * @param blockGasTotal The amount of gas in the most recent block.
   * @param blockGasLimit The maxBlockGasLimit of the past block.
   * @return result of the calculation (new gas price minimum)
   * @dev Calculate using the following formula:
   * oldGasPriceMinimum * (1 + (adjustmentSpeed * (blockDensity - targetDensity))) + 1.
   */
  function getUpdatedGasPriceMinimum(uint256 blockGasTotal, uint256 blockGasLimit)
    public
    view
    returns (uint256)
  {
    FixidityLib.Fraction memory blockDensity = FixidityLib.newFixedFraction(
      blockGasTotal,
      blockGasLimit
    );
    bool densityGreaterThanTarget = blockDensity.gt(targetDensity);
    FixidityLib.Fraction memory densityDelta = densityGreaterThanTarget
      ? blockDensity.subtract(targetDensity)
      : targetDensity.subtract(blockDensity);
    FixidityLib.Fraction memory adjustment = densityGreaterThanTarget
      ? FixidityLib.fixed1().add(adjustmentSpeed.multiply(densityDelta))
      : FixidityLib.fixed1().subtract(adjustmentSpeed.multiply(densityDelta));

    uint256 newGasPriceMinimum = adjustment
      .multiply(FixidityLib.newFixed(gasPriceMinimum))
      .add(FixidityLib.fixed1())
      .fromFixed();

    return newGasPriceMinimum >= gasPriceMinimumFloor ? newGasPriceMinimum : gasPriceMinimumFloor;
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

interface ICeloVersionedContract {
  /**
   * @notice Returns the storage, major, minor, and patch version of the contract.
   * @return The storage, major, minor, and patch version of the contract.
   */
  function getVersionNumber() external pure returns (uint256, uint256, uint256, uint256);
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

interface IRandom {
  function revealAndCommit(bytes32, bytes32, address) external;
  function randomnessBlockRetentionWindow() external view returns (uint256);
  function random() external view returns (bytes32);
  function getBlockRandomness(uint256) external view returns (bytes32);
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


pragma solidity ^0.5.13;

contract CalledByVm {
  modifier onlyVm() {
    require(msg.sender == address(0), "Only VM can call");
    _;
  }
}