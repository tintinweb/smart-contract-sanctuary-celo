pragma solidity ^0.5.3;


library SafeMath {
    
    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a, "SafeMath: addition overflow");

        return c;
    }

    
    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        return sub(a, b, "SafeMath: subtraction overflow");
    }

    
    function sub(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b <= a, errorMessage);
        uint256 c = a - b;

        return c;
    }

    
    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        
        
        
        if (a == 0) {
            return 0;
        }

        uint256 c = a * b;
        require(c / a == b, "SafeMath: multiplication overflow");

        return c;
    }

    
    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        return div(a, b, "SafeMath: division by zero");
    }

    
    function div(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        
        require(b > 0, errorMessage);
        uint256 c = a / b;
        

        return c;
    }

    
    function mod(uint256 a, uint256 b) internal pure returns (uint256) {
        return mod(a, b, "SafeMath: modulo by zero");
    }

    
    function mod(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b != 0, errorMessage);
        return a % b;
    }
}

library Address {
    
    function isContract(address account) internal view returns (bool) {
        
        
        
        bytes32 codehash;
        bytes32 accountHash = 0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470;
        
        assembly { codehash := extcodehash(account) }
        return (codehash != accountHash && codehash != 0x0);
    }

    
    function toPayable(address account) internal pure returns (address payable) {
        return address(uint160(account));
    }

    
    function sendValue(address payable recipient, uint256 amount) internal {
        require(address(this).balance >= amount, "Address: insufficient balance");

        
        (bool success, ) = recipient.call.value(amount)("");
        require(success, "Address: unable to send value, recipient may have reverted");
    }
}

contract Initializable {
  bool public initialized;

  modifier initializer() {
    require(!initialized, "contract already initialized");
    initialized = true;
    _;
  }
}

contract MultiSig is Initializable {
  using SafeMath for uint256;
  
  event Confirmation(address indexed sender, uint256 indexed transactionId);
  event Revocation(address indexed sender, uint256 indexed transactionId);
  event Submission(uint256 indexed transactionId);
  event Execution(uint256 indexed transactionId, bytes returnData);
  event Deposit(address indexed sender, uint256 value);
  event OwnerAddition(address indexed owner);
  event OwnerRemoval(address indexed owner);
  event RequirementChange(uint256 required);
  event InternalRequirementChange(uint256 internalRequired);

  
  uint256 public constant MAX_OWNER_COUNT = 50;

  
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

  
  function() external payable {
    if (msg.value > 0) emit Deposit(msg.sender, msg.value);
  }

  
  
  
  
  
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

  
  
  
  function changeRequirement(uint256 _required)
    public
    onlyWallet
    validRequirement(owners.length, _required)
  {
    required = _required;
    emit RequirementChange(_required);
  }

  
  
  
  function changeInternalRequirement(uint256 _internalRequired)
    public
    onlyWallet
    validRequirement(owners.length, _internalRequired)
  {
    internalRequired = _internalRequired;
    emit InternalRequirementChange(_internalRequired);
  }

  
  
  
  
  
  function submitTransaction(address destination, uint256 value, bytes calldata data)
    external
    returns (uint256 transactionId)
  {
    transactionId = addTransaction(destination, value, data);
    confirmTransaction(transactionId);
  }

  
  
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

  
  
  function revokeConfirmation(uint256 transactionId)
    external
    ownerExists(msg.sender)
    confirmed(transactionId, msg.sender)
    notExecuted(transactionId)
  {
    confirmations[transactionId][msg.sender] = false;
    emit Revocation(msg.sender, transactionId);
  }

  
  
  function executeTransaction(uint256 transactionId)
    public
    ownerExists(msg.sender)
    confirmed(transactionId, msg.sender)
    notExecuted(transactionId)
  {
    require(isConfirmed(transactionId), "Transaction not confirmed.");
    Transaction storage txn = transactions[transactionId];
    txn.executed = true;
    bool success;
    bytes memory returnData;
    (success, returnData) = external_call(txn.destination, txn.value, txn.data);
    require(success, "Transaction execution failed.");
    emit Execution(transactionId, returnData);
  }

  
  
  function external_call(address destination, uint256 value, bytes memory data)
    private
    returns (bool, bytes memory)
  {
    if (data.length > 0) require(Address.isContract(destination), "Invalid contract address");
    bool success;
    bytes memory returnData;
    (success, returnData) = destination.call.value(value)(data);
    return (success, returnData);
  }

  
  
  
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

  
  
  
  
  function getConfirmationCount(uint256 transactionId) external view returns (uint256 count) {
    for (uint256 i = 0; i < owners.length; i = i.add(1))
      if (confirmations[transactionId][owners[i]]) count = count.add(1);
  }

  
  
  
  
  function getTransactionCount(bool pending, bool executed) external view returns (uint256 count) {
    for (uint256 i = 0; i < transactionCount; i = i.add(1))
      if ((pending && !transactions[i].executed) || (executed && transactions[i].executed))
        count = count.add(1);
  }

  
  
  function getOwners() external view returns (address[] memory) {
    return owners;
  }

  
  
  
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

contract ReserveSpenderMultiSig is MultiSig {}