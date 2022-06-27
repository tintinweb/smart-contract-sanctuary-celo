pragma solidity ^0.5.13;

import "./interfaces/IRandom.sol";
import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "openzeppelin-solidity/contracts/ownership/Ownable.sol";

import "../common/CalledByVm.sol";
import "../common/Initializable.sol";
import "../common/UsingPrecompiles.sol";
import "../common/interfaces/ICeloVersionedContract.sol";

/**
 * @title Provides randomness for verifier selection
 */
contract Random is
  IRandom,
  ICeloVersionedContract,
  Ownable,
  Initializable,
  UsingPrecompiles,
  CalledByVm
{
  using SafeMath for uint256;

  /* Stores most recent commitment per address */
  mapping(address => bytes32) public commitments;

  uint256 public randomnessBlockRetentionWindow;

  mapping(uint256 => bytes32) private history;
  uint256 private historyFirst;
  uint256 private historySize;
  uint256 private lastEpochBlock;

  event RandomnessBlockRetentionWindowSet(uint256 value);

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
   * @param _randomnessBlockRetentionWindow Number of old random blocks whose randomness
   * values can be queried.
   */
  function initialize(uint256 _randomnessBlockRetentionWindow) external initializer {
    _transferOwnership(msg.sender);
    setRandomnessBlockRetentionWindow(_randomnessBlockRetentionWindow);
  }

  /**
   * @notice Sets the number of old random blocks whose randomness values can be queried.
   * @param value Number of old random blocks whose randomness values can be queried.
   */
  function setRandomnessBlockRetentionWindow(uint256 value) public onlyOwner {
    require(value > 0, "randomnessBlockRetetionWindow cannot be zero");
    randomnessBlockRetentionWindow = value;
    emit RandomnessBlockRetentionWindowSet(value);
  }

  /**
   * @notice Implements step of the randomness protocol.
   * @param randomness Bytes that will be added to the entropy pool.
   * @param newCommitment The hash of randomness that will be revealed in the future.
   * @param proposer Address of the block proposer.
   * @dev If the Random contract is pointed to by the Registry, the first transaction in a block
   * should be a special transaction to address 0x0 with 64 bytes of data - the concatenated
   * `randomness` and `newCommitment`. Before running regular transactions, this function should be
   * called.
   */
  function revealAndCommit(bytes32 randomness, bytes32 newCommitment, address proposer)
    external
    onlyVm
  {
    _revealAndCommit(randomness, newCommitment, proposer);
  }

  /**
   * @notice Implements step of the randomness protocol.
   * @param randomness Bytes that will be added to the entropy pool.
   * @param newCommitment The hash of randomness that will be revealed in the future.
   * @param proposer Address of the block proposer.
   */
  function _revealAndCommit(bytes32 randomness, bytes32 newCommitment, address proposer) internal {
    require(newCommitment != computeCommitment(0), "cannot commit zero randomness");

    // ensure revealed randomness matches previous commitment
    if (commitments[proposer] != 0) {
      require(randomness != 0, "randomness cannot be zero if there is a previous commitment");
      bytes32 expectedCommitment = computeCommitment(randomness);
      require(
        expectedCommitment == commitments[proposer],
        "commitment didn't match the posted randomness"
      );
    } else {
      require(randomness == 0, "randomness should be zero if there is no previous commitment");
    }

    // add entropy
    uint256 blockNumber = block.number == 0 ? 0 : block.number.sub(1);
    addRandomness(block.number, keccak256(abi.encodePacked(history[blockNumber], randomness)));

    commitments[proposer] = newCommitment;
  }

  /**
   * @notice Add a value to the randomness history.
   * @param blockNumber Current block number.
   * @param randomness The new randomness added to history.
   * @dev The calls to this function should be made so that on the next call, blockNumber will
   * be the previous one, incremented by one.
   */
  function addRandomness(uint256 blockNumber, bytes32 randomness) internal {
    history[blockNumber] = randomness;
    if (blockNumber % getEpochSize() == 0) {
      if (lastEpochBlock < historyFirst) {
        delete history[lastEpochBlock];
      }
      lastEpochBlock = blockNumber;
    } else {
      if (historySize == 0) {
        historyFirst = blockNumber;
        historySize = 1;
      } else if (historySize > randomnessBlockRetentionWindow) {
        deleteHistoryIfNotLastEpochBlock(historyFirst);
        deleteHistoryIfNotLastEpochBlock(historyFirst.add(1));
        historyFirst = historyFirst.add(2);
        historySize = historySize.sub(1);
      } else if (historySize == randomnessBlockRetentionWindow) {
        deleteHistoryIfNotLastEpochBlock(historyFirst);
        historyFirst = historyFirst.add(1);
      } else {
        // historySize < randomnessBlockRetentionWindow
        historySize = historySize.add(1);
      }
    }
  }

  /**
   * @notice Compute the commitment hash for a given randomness value.
   * @param randomness The value for which the commitment hash is computed.
   * @return Commitment parameter.
   */
  function computeCommitment(bytes32 randomness) public pure returns (bytes32) {
    return keccak256(abi.encodePacked(randomness));
  }

  /**
   * @notice Querying the current randomness value.
   * @return Returns the current randomness value.
   */
  function random() external view returns (bytes32) {
    return _getBlockRandomness(block.number, block.number);
  }

  /**
   * @notice Get randomness values of previous blocks.
   * @param blockNumber The number of block whose randomness value we want to know.
   * @return The associated randomness value.
   */
  function getBlockRandomness(uint256 blockNumber) external view returns (bytes32) {
    return _getBlockRandomness(blockNumber, block.number);
  }

  /**
   * @notice Get randomness values of previous blocks.
   * @param blockNumber The number of block whose randomness value we want to know.
   * @param cur Number of the current block.
   * @return The associated randomness value.
   */
  function _getBlockRandomness(uint256 blockNumber, uint256 cur) internal view returns (bytes32) {
    require(blockNumber <= cur, "Cannot query randomness of future blocks");
    require(
      blockNumber == lastEpochBlock ||
        (blockNumber > cur.sub(historySize) &&
          (randomnessBlockRetentionWindow >= cur ||
            blockNumber > cur.sub(randomnessBlockRetentionWindow))),
      "Cannot query randomness older than the stored history"
    );
    return history[blockNumber];
  }

  function deleteHistoryIfNotLastEpochBlock(uint256 blockNumber) internal {
    if (blockNumber != lastEpochBlock) {
      delete history[blockNumber];
    }
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

import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "../common/interfaces/ICeloVersionedContract.sol";

contract UsingPrecompiles {
  using SafeMath for uint256;

  address constant TRANSFER = address(0xff - 2);
  address constant FRACTION_MUL = address(0xff - 3);
  address constant PROOF_OF_POSSESSION = address(0xff - 4);
  address constant GET_VALIDATOR = address(0xff - 5);
  address constant NUMBER_VALIDATORS = address(0xff - 6);
  address constant EPOCH_SIZE = address(0xff - 7);
  address constant BLOCK_NUMBER_FROM_HEADER = address(0xff - 8);
  address constant HASH_HEADER = address(0xff - 9);
  address constant GET_PARENT_SEAL_BITMAP = address(0xff - 10);
  address constant GET_VERIFIED_SEAL_BITMAP = address(0xff - 11);

  /**
   * @notice calculate a * b^x for fractions a, b to `decimals` precision
   * @param aNumerator Numerator of first fraction
   * @param aDenominator Denominator of first fraction
   * @param bNumerator Numerator of exponentiated fraction
   * @param bDenominator Denominator of exponentiated fraction
   * @param exponent exponent to raise b to
   * @param _decimals precision
   * @return numerator/denominator of the computed quantity (not reduced).
   */
  function fractionMulExp(
    uint256 aNumerator,
    uint256 aDenominator,
    uint256 bNumerator,
    uint256 bDenominator,
    uint256 exponent,
    uint256 _decimals
  ) public view returns (uint256, uint256) {
    require(aDenominator != 0 && bDenominator != 0, "a denominator is zero");
    uint256 returnNumerator;
    uint256 returnDenominator;
    bool success;
    bytes memory out;
    (success, out) = FRACTION_MUL.staticcall(
      abi.encodePacked(aNumerator, aDenominator, bNumerator, bDenominator, exponent, _decimals)
    );
    require(success, "error calling fractionMulExp precompile");
    returnNumerator = getUint256FromBytes(out, 0);
    returnDenominator = getUint256FromBytes(out, 32);
    return (returnNumerator, returnDenominator);
  }

  /**
   * @notice Returns the current epoch size in blocks.
   * @return The current epoch size in blocks.
   */
  function getEpochSize() public view returns (uint256) {
    bytes memory out;
    bool success;
    (success, out) = EPOCH_SIZE.staticcall(abi.encodePacked());
    require(success, "error calling getEpochSize precompile");
    return getUint256FromBytes(out, 0);
  }

  /**
   * @notice Returns the epoch number at a block.
   * @param blockNumber Block number where epoch number is calculated.
   * @return Epoch number.
   */
  function getEpochNumberOfBlock(uint256 blockNumber) public view returns (uint256) {
    return epochNumberOfBlock(blockNumber, getEpochSize());
  }

  /**
   * @notice Returns the epoch number at a block.
   * @return Current epoch number.
   */
  function getEpochNumber() public view returns (uint256) {
    return getEpochNumberOfBlock(block.number);
  }

  /**
   * @notice Returns the epoch number at a block.
   * @param blockNumber Block number where epoch number is calculated.
   * @param epochSize The epoch size in blocks.
   * @return Epoch number.
   */
  function epochNumberOfBlock(uint256 blockNumber, uint256 epochSize)
    internal
    pure
    returns (uint256)
  {
    // Follows GetEpochNumber from celo-blockchain/blob/master/consensus/istanbul/utils.go
    uint256 epochNumber = blockNumber / epochSize;
    if (blockNumber % epochSize == 0) {
      return epochNumber;
    } else {
      return epochNumber.add(1);
    }
  }

  /**
   * @notice Gets a validator address from the current validator set.
   * @param index Index of requested validator in the validator set.
   * @return Address of validator at the requested index.
   */
  function validatorSignerAddressFromCurrentSet(uint256 index) public view returns (address) {
    bytes memory out;
    bool success;
    (success, out) = GET_VALIDATOR.staticcall(abi.encodePacked(index, uint256(block.number)));
    require(success, "error calling validatorSignerAddressFromCurrentSet precompile");
    return address(getUint256FromBytes(out, 0));
  }

  /**
   * @notice Gets a validator address from the validator set at the given block number.
   * @param index Index of requested validator in the validator set.
   * @param blockNumber Block number to retrieve the validator set from.
   * @return Address of validator at the requested index.
   */
  function validatorSignerAddressFromSet(uint256 index, uint256 blockNumber)
    public
    view
    returns (address)
  {
    bytes memory out;
    bool success;
    (success, out) = GET_VALIDATOR.staticcall(abi.encodePacked(index, blockNumber));
    require(success, "error calling validatorSignerAddressFromSet precompile");
    return address(getUint256FromBytes(out, 0));
  }

  /**
   * @notice Gets the size of the current elected validator set.
   * @return Size of the current elected validator set.
   */
  function numberValidatorsInCurrentSet() public view returns (uint256) {
    bytes memory out;
    bool success;
    (success, out) = NUMBER_VALIDATORS.staticcall(abi.encodePacked(uint256(block.number)));
    require(success, "error calling numberValidatorsInCurrentSet precompile");
    return getUint256FromBytes(out, 0);
  }

  /**
   * @notice Gets the size of the validator set that must sign the given block number.
   * @param blockNumber Block number to retrieve the validator set from.
   * @return Size of the validator set.
   */
  function numberValidatorsInSet(uint256 blockNumber) public view returns (uint256) {
    bytes memory out;
    bool success;
    (success, out) = NUMBER_VALIDATORS.staticcall(abi.encodePacked(blockNumber));
    require(success, "error calling numberValidatorsInSet precompile");
    return getUint256FromBytes(out, 0);
  }

  /**
   * @notice Checks a BLS proof of possession.
   * @param sender The address signed by the BLS key to generate the proof of possession.
   * @param blsKey The BLS public key that the validator is using for consensus, should pass proof
   *   of possession. 48 bytes.
   * @param blsPop The BLS public key proof-of-possession, which consists of a signature on the
   *   account address. 96 bytes.
   * @return True upon success.
   */
  function checkProofOfPossession(address sender, bytes memory blsKey, bytes memory blsPop)
    public
    view
    returns (bool)
  {
    bool success;
    (success, ) = PROOF_OF_POSSESSION.staticcall(abi.encodePacked(sender, blsKey, blsPop));
    return success;
  }

  /**
   * @notice Parses block number out of header.
   * @param header RLP encoded header
   * @return Block number.
   */
  function getBlockNumberFromHeader(bytes memory header) public view returns (uint256) {
    bytes memory out;
    bool success;
    (success, out) = BLOCK_NUMBER_FROM_HEADER.staticcall(abi.encodePacked(header));
    require(success, "error calling getBlockNumberFromHeader precompile");
    return getUint256FromBytes(out, 0);
  }

  /**
   * @notice Computes hash of header.
   * @param header RLP encoded header
   * @return Header hash.
   */
  function hashHeader(bytes memory header) public view returns (bytes32) {
    bytes memory out;
    bool success;
    (success, out) = HASH_HEADER.staticcall(abi.encodePacked(header));
    require(success, "error calling hashHeader precompile");
    return getBytes32FromBytes(out, 0);
  }

  /**
   * @notice Gets the parent seal bitmap from the header at the given block number.
   * @param blockNumber Block number to retrieve. Must be within 4 epochs of the current number.
   * @return Bitmap parent seal with set bits at indices corresponding to signing validators.
   */
  function getParentSealBitmap(uint256 blockNumber) public view returns (bytes32) {
    bytes memory out;
    bool success;
    (success, out) = GET_PARENT_SEAL_BITMAP.staticcall(abi.encodePacked(blockNumber));
    require(success, "error calling getParentSealBitmap precompile");
    return getBytes32FromBytes(out, 0);
  }

  /**
   * @notice Verifies the BLS signature on the header and returns the seal bitmap.
   * The validator set used for verification is retrieved based on the parent hash field of the
   * header.  If the parent hash is not in the blockchain, verification fails.
   * @param header RLP encoded header
   * @return Bitmap parent seal with set bits at indices correspoinding to signing validators.
   */
  function getVerifiedSealBitmapFromHeader(bytes memory header) public view returns (bytes32) {
    bytes memory out;
    bool success;
    (success, out) = GET_VERIFIED_SEAL_BITMAP.staticcall(abi.encodePacked(header));
    require(success, "error calling getVerifiedSealBitmapFromHeader precompile");
    return getBytes32FromBytes(out, 0);
  }

  /**
   * @notice Converts bytes to uint256.
   * @param bs byte[] data
   * @param start offset into byte data to convert
   * @return uint256 data
   */
  function getUint256FromBytes(bytes memory bs, uint256 start) internal pure returns (uint256) {
    return uint256(getBytes32FromBytes(bs, start));
  }

  /**
   * @notice Converts bytes to bytes32.
   * @param bs byte[] data
   * @param start offset into byte data to convert
   * @return bytes32 data
   */
  function getBytes32FromBytes(bytes memory bs, uint256 start) internal pure returns (bytes32) {
    require(bs.length >= start.add(32), "slicing out of range");
    bytes32 x;
    assembly {
      x := mload(add(bs, add(start, 32)))
    }
    return x;
  }

  /**
   * @notice Returns the minimum number of required signers for a given block number.
   * @dev Computed in celo-blockchain as int(math.Ceil(float64(2*valSet.Size()) / 3))
   */
  function minQuorumSize(uint256 blockNumber) public view returns (uint256) {
    return numberValidatorsInSet(blockNumber).mul(2).add(2).div(3);
  }

  /**
   * @notice Computes byzantine quorum from current validator set size
   * @return Byzantine quorum of validators.
   */
  function minQuorumSizeInCurrentSet() public view returns (uint256) {
    return minQuorumSize(block.number);
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

contract CalledByVm {
  modifier onlyVm() {
    require(msg.sender == address(0), "Only VM can call");
    _;
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

interface IRandom {
  function revealAndCommit(bytes32, bytes32, address) external;
  function randomnessBlockRetentionWindow() external view returns (uint256);
  function random() external view returns (bytes32);
  function getBlockRandomness(uint256) external view returns (bytes32);
}