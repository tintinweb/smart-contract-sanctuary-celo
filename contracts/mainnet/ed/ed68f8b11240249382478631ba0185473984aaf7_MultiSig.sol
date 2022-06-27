pragma solidity ^0.5.13;
/* solhint-disable no-inline-assembly, avoid-low-level-calls, func-name-mixedcase, func-order */

import "openzeppelin-solidity/contracts/math/SafeMath.sol";

import "./ExternalCall.sol";
import "./Initializable.sol";

/**
 * @title Multisignature wallet - Allows multiple parties to agree on transactions before
 * execution.
 * @author Stefan George - <[email protected]>
 * @dev NOTE: This contract has its limitations and is not viable for every
 * multi-signature setup. On a case by case basis, evaluate whether this is the
 * correct contract for your use case.
 * In particular, this contract doesn't have an atomic "add owners and increase
 * requirement" operation.
 * This can be tricky, for example, in a situation where a MultiSig starts out
 * owned by a single owner. Safely increasing the owner set and requirement at
 * the same time is not trivial. One way to work around this situation is to
 * first add a second address controlled by the original owner, increase the
 * requirement, and then replace the auxillary address with the intended second
 * owner.
 * Again, this is just one example, in general make sure to verify this contract
 * will support your intended usage. The goal of this contract is to offer a
 * simple, minimal multi-signature API that's easy to understand even for novice
 * Solidity users.
 */
contract MultiSig is Initializable {
  using SafeMath for uint256;
  /*
   *  Events
   */
  event Confirmation(address indexed sender, uint256 indexed transactionId);
  event Revocation(address indexed sender, uint256 indexed transactionId);
  event Submission(uint256 indexed transactionId);
  event Execution(uint256 indexed transactionId, bytes returnData);
  event Deposit(address indexed sender, uint256 value);
  event OwnerAddition(address indexed owner);
  event OwnerRemoval(address indexed owner);
  event RequirementChange(uint256 required);
  event InternalRequirementChange(uint256 internalRequired);

  /*
   *  Constants
   */
  uint256 public constant MAX_OWNER_COUNT = 50;

  /*
   *  Storage
   */
  mapping(uint256 => Transaction) public transactions;
  mapping(uint256 => mapping(address => bool)) public confirmations;
  mapping(address => bool) public isOwner;
  address[] public owners;
  uint256 public required;
  uint256 public internalRequired;
  uint256 public transactionCount;

  struct Transaction {
    address destination;
    uint256 value;
    bytes data;
    bool executed;
  }

  /**
   * @notice Sets initialized == true on implementation contracts
   * @param test Set to true to skip implementation initialization
   */
  constructor(bool test) public Initializable(test) {}

  /*
   *  Modifiers
   */
  modifier onlyWallet() {
    require(msg.sender == address(this), "msg.sender was not multisig wallet");
    _;
  }

  modifier ownerDoesNotExist(address owner) {
    require(!isOwner[owner], "owner already existed");
    _;
  }

  modifier ownerExists(address owner) {
    require(isOwner[owner], "owner does not exist");
    _;
  }

  modifier transactionExists(uint256 transactionId) {
    require(transactions[transactionId].destination != address(0), "transaction does not exist");
    _;
  }

  modifier confirmed(uint256 transactionId, address owner) {
    require(confirmations[transactionId][owner], "transaction was not confirmed for owner");
    _;
  }

  modifier notConfirmed(uint256 transactionId, address owner) {
    require(!confirmations[transactionId][owner], "transaction was already confirmed for owner");
    _;
  }

  modifier notExecuted(uint256 transactionId) {
    require(!transactions[transactionId].executed, "transaction was executed already");
    _;
  }

  modifier notNull(address _address) {
    require(_address != address(0), "address was null");
    _;
  }

  modifier validRequirement(uint256 ownerCount, uint256 _required) {
    require(
      ownerCount <= MAX_OWNER_COUNT && _required <= ownerCount && _required != 0 && ownerCount != 0,
      "invalid requirement"
    );
    _;
  }

  /// @dev Fallback function allows to deposit ether.
  function() external payable {
    if (msg.value > 0) emit Deposit(msg.sender, msg.value);
  }

  /*
   * Public functions
   */
  /// @dev Contract constructor sets initial owners and required number of confirmations.
  /// @param _owners List of initial owners.
  /// @param _required Number of required confirmations for external transactions.
  /// @param _internalRequired Number of required confirmations for internal transactions.
  function initialize(address[] calldata _owners, uint256 _required, uint256 _internalRequired)
    external
    initializer
    validRequirement(_owners.length, _required)
    validRequirement(_owners.length, _internalRequired)
  {
    for (uint256 i = 0; i < _owners.length; i = i.add(1)) {
      require(
        !isOwner[_owners[i]] && _owners[i] != address(0),
        "owner was null or already given owner status"
      );
      isOwner[_owners[i]] = true;
    }
    owners = _owners;
    required = _required;
    internalRequired = _internalRequired;
  }

  /// @dev Allows to add a new owner. Transaction has to be sent by wallet.
  /// @param owner Address of new owner.
  function addOwner(address owner)
    external
    onlyWallet
    ownerDoesNotExist(owner)
    notNull(owner)
    validRequirement(owners.length.add(1), internalRequired)
  {
    isOwner[owner] = true;
    owners.push(owner);
    emit OwnerAddition(owner);
  }

  /// @dev Allows to remove an owner. Transaction has to be sent by wallet.
  /// @param owner Address of owner.
  function removeOwner(address owner) external onlyWallet ownerExists(owner) {
    isOwner[owner] = false;
    for (uint256 i = 0; i < owners.length.sub(1); i = i.add(1))
      if (owners[i] == owner) {
        owners[i] = owners[owners.length.sub(1)];
        break;
      }
    owners.length = owners.length.sub(1);
    if (required > owners.length) changeRequirement(owners.length);
    if (internalRequired > owners.length) changeInternalRequirement(owners.length);
    emit OwnerRemoval(owner);
  }

  /// @dev Allows to replace an owner with a new owner. Transaction has to be sent by wallet.
  /// @param owner Address of owner to be replaced.
  /// @param newOwner Address of new owner.
  function replaceOwner(address owner, address newOwner)
    external
    onlyWallet
    ownerExists(owner)
    notNull(newOwner)
    ownerDoesNotExist(newOwner)
  {
    for (uint256 i = 0; i < owners.length; i = i.add(1))
      if (owners[i] == owner) {
        owners[i] = newOwner;
        break;
      }
    isOwner[owner] = false;
    isOwner[newOwner] = true;
    emit OwnerRemoval(owner);
    emit OwnerAddition(newOwner);
  }

  /// @dev Allows to change the number of required confirmations. Transaction has to be sent by
  /// wallet.
  /// @param _required Number of required confirmations.
  function changeRequirement(uint256 _required)
    public
    onlyWallet
    validRequirement(owners.length, _required)
  {
    required = _required;
    emit RequirementChange(_required);
  }

  /// @dev Allows to change the number of required confirmations. Transaction has to be sent by
  /// wallet.
  /// @param _internalRequired Number of required confirmations for interal txs.
  function changeInternalRequirement(uint256 _internalRequired)
    public
    onlyWallet
    validRequirement(owners.length, _internalRequired)
  {
    internalRequired = _internalRequired;
    emit InternalRequirementChange(_internalRequired);
  }

  /// @dev Allows an owner to submit and confirm a transaction.
  /// @param destination Transaction target address.
  /// @param value Transaction ether value.
  /// @param data Transaction data payload.
  /// @return Returns transaction ID.
  function submitTransaction(address destination, uint256 value, bytes calldata data)
    external
    returns (uint256 transactionId)
  {
    transactionId = addTransaction(destination, value, data);
    confirmTransaction(transactionId);
  }

  /// @dev Allows an owner to confirm a transaction.
  /// @param transactionId Transaction ID.
  function confirmTransaction(uint256 transactionId)
    public
    ownerExists(msg.sender)
    transactionExists(transactionId)
    notConfirmed(transactionId, msg.sender)
  {
    confirmations[transactionId][msg.sender] = true;
    emit Confirmation(msg.sender, transactionId);
    if (isConfirmed(transactionId)) {
      executeTransaction(transactionId);
    }
  }

  /// @dev Allows an owner to revoke a confirmation for a transaction.
  /// @param transactionId Transaction ID.
  function revokeConfirmation(uint256 transactionId)
    external
    ownerExists(msg.sender)
    confirmed(transactionId, msg.sender)
    notExecuted(transactionId)
  {
    confirmations[transactionId][msg.sender] = false;
    emit Revocation(msg.sender, transactionId);
  }

  /// @dev Allows anyone to execute a confirmed transaction.
  /// @param transactionId Transaction ID.
  function executeTransaction(uint256 transactionId)
    public
    ownerExists(msg.sender)
    confirmed(transactionId, msg.sender)
    notExecuted(transactionId)
  {
    require(isConfirmed(transactionId), "Transaction not confirmed.");
    Transaction storage txn = transactions[transactionId];
    txn.executed = true;
    bytes memory returnData = ExternalCall.execute(txn.destination, txn.value, txn.data);
    emit Execution(transactionId, returnData);
  }

  /// @dev Returns the confirmation status of a transaction.
  /// @param transactionId Transaction ID.
  /// @return Confirmation status.
  function isConfirmed(uint256 transactionId) public view returns (bool) {
    uint256 count = 0;
    for (uint256 i = 0; i < owners.length; i = i.add(1)) {
      if (confirmations[transactionId][owners[i]]) count = count.add(1);
      bool isInternal = transactions[transactionId].destination == address(this);
      if ((isInternal && count == internalRequired) || (!isInternal && count == required))
        return true;
    }
    return false;
  }

  /*
   * Internal functions
   */
  /// @dev Adds a new transaction to the transaction mapping, if transaction does not exist yet.
  /// @param destination Transaction target address.
  /// @param value Transaction ether value.
  /// @param data Transaction data payload.
  /// @return Returns transaction ID.
  function addTransaction(address destination, uint256 value, bytes memory data)
    internal
    notNull(destination)
    returns (uint256 transactionId)
  {
    transactionId = transactionCount;
    transactions[transactionId] = Transaction({
      destination: destination,
      value: value,
      data: data,
      executed: false
    });
    transactionCount = transactionCount.add(1);
    emit Submission(transactionId);
  }

  /*
   * Web3 call functions
   */
  /// @dev Returns number of confirmations of a transaction.
  /// @param transactionId Transaction ID.
  /// @return Number of confirmations.
  function getConfirmationCount(uint256 transactionId) external view returns (uint256 count) {
    for (uint256 i = 0; i < owners.length; i = i.add(1))
      if (confirmations[transactionId][owners[i]]) count = count.add(1);
  }

  /// @dev Returns total number of transactions after filters are applied.
  /// @param pending Include pending transactions.
  /// @param executed Include executed transactions.
  /// @return Total number of transactions after filters are applied.
  function getTransactionCount(bool pending, bool executed) external view returns (uint256 count) {
    for (uint256 i = 0; i < transactionCount; i = i.add(1))
      if ((pending && !transactions[i].executed) || (executed && transactions[i].executed))
        count = count.add(1);
  }

  /// @dev Returns list of owners.
  /// @return List of owner addresses.
  function getOwners() external view returns (address[] memory) {
    return owners;
  }

  /// @dev Returns array with owner addresses, which confirmed transaction.
  /// @param transactionId Transaction ID.
  /// @return Returns array of owner addresses.
  function getConfirmations(uint256 transactionId)
    external
    view
    returns (address[] memory _confirmations)
  {
    address[] memory confirmationsTemp = new address[](owners.length);
    uint256 count = 0;
    uint256 i;
    for (i = 0; i < owners.length; i = i.add(1))
      if (confirmations[transactionId][owners[i]]) {
        confirmationsTemp[count] = owners[i];
        count = count.add(1);
      }
    _confirmations = new address[](count);
    for (i = 0; i < count; i = i.add(1)) _confirmations[i] = confirmationsTemp[i];
  }

  /// @dev Returns list of transaction IDs in defined range.
  /// @param from Index start position of transaction array.
  /// @param to Index end position of transaction array.
  /// @param pending Include pending transactions.
  /// @param executed Include executed transactions.
  /// @return Returns array of transaction IDs.
  function getTransactionIds(uint256 from, uint256 to, bool pending, bool executed)
    external
    view
    returns (uint256[] memory _transactionIds)
  {
    uint256[] memory transactionIdsTemp = new uint256[](transactionCount);
    uint256 count = 0;
    uint256 i;
    for (i = 0; i < transactionCount; i = i.add(1))
      if ((pending && !transactions[i].executed) || (executed && transactions[i].executed)) {
        transactionIdsTemp[count] = i;
        count = count.add(1);
      }
    _transactionIds = new uint256[](to.sub(from));
    for (i = from; i < to; i = i.add(1)) _transactionIds[i.sub(from)] = transactionIdsTemp[i];
  }
}


pragma solidity ^0.5.5;

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
        // According to EIP-1052, 0x0 is the value returned for not-yet created accounts
        // and 0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470 is returned
        // for accounts without code, i.e. `keccak256('')`
        bytes32 codehash;
        bytes32 accountHash = 0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470;
        // solhint-disable-next-line no-inline-assembly
        assembly { codehash := extcodehash(account) }
        return (codehash != accountHash && codehash != 0x0);
    }

    /**
     * @dev Converts an `address` into `address payable`. Note that this is
     * simply a type cast: the actual underlying value is not changed.
     *
     * _Available since v2.4.0._
     */
    function toPayable(address account) internal pure returns (address payable) {
        return address(uint160(account));
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
     *
     * _Available since v2.4.0._
     */
    function sendValue(address payable recipient, uint256 amount) internal {
        require(address(this).balance >= amount, "Address: insufficient balance");

        // solhint-disable-next-line avoid-call-value
        (bool success, ) = recipient.call.value(amount)("");
        require(success, "Address: unable to send value, recipient may have reverted");
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

import "openzeppelin-solidity/contracts/utils/Address.sol";

library ExternalCall {
  /**
   * @notice Executes external call.
   * @param destination The address to call.
   * @param value The CELO value to be sent.
   * @param data The data to be sent.
   * @return The call return value.
   */
  function execute(address destination, uint256 value, bytes memory data)
    internal
    returns (bytes memory)
  {
    if (data.length > 0) require(Address.isContract(destination), "Invalid contract address");
    bool success;
    bytes memory returnData;
    (success, returnData) = destination.call.value(value)(data);
    require(success, "Transaction execution failed.");
    return returnData;
  }
}