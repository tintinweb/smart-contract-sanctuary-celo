pragma solidity ^0.5.3;


library Math {
    
    function max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a >= b ? a : b;
    }

    
    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    
    function average(uint256 a, uint256 b) internal pure returns (uint256) {
        
        return (a / 2) + (b / 2) + ((a % 2 + b % 2) / 2);
    }
}

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

contract Context {
    
    
    constructor () internal { }
    

    function _msgSender() internal view returns (address payable) {
        return msg.sender;
    }

    function _msgData() internal view returns (bytes memory) {
        this; 
        return msg.data;
    }
}

contract Ownable is Context {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    
    constructor () internal {
        address msgSender = _msgSender();
        _owner = msgSender;
        emit OwnershipTransferred(address(0), msgSender);
    }

    
    function owner() public view returns (address) {
        return _owner;
    }

    
    modifier onlyOwner() {
        require(isOwner(), "Ownable: caller is not the owner");
        _;
    }

    
    function isOwner() public view returns (bool) {
        return _msgSender() == _owner;
    }

    
    function renounceOwnership() public onlyOwner {
        emit OwnershipTransferred(_owner, address(0));
        _owner = address(0);
    }

    
    function transferOwnership(address newOwner) public onlyOwner {
        _transferOwnership(newOwner);
    }

    
    function _transferOwnership(address newOwner) internal {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}

interface IElection {
  function getTotalVotes() external view returns (uint256);
  function getActiveVotes() external view returns (uint256);
  function getTotalVotesByAccount(address) external view returns (uint256);
  function markGroupIneligible(address) external;
  function markGroupEligible(address, address, address) external;
  function electValidatorSigners() external view returns (address[] memory);
  function vote(address, uint256, address, address) external returns (bool);
  function activate(address) external returns (bool);
  function revokeActive(address, uint256, address, address, uint256) external returns (bool);
  function revokeAllActive(address, address, address, uint256) external returns (bool);
  function revokePending(address, uint256, address, address, uint256) external returns (bool);
  function forceDecrementVotes(
    address,
    uint256,
    address[] calldata,
    address[] calldata,
    uint256[] calldata
  ) external returns (uint256);
}

interface IValidators {
  function getAccountLockedGoldRequirement(address) external view returns (uint256);
  function meetsAccountLockedGoldRequirements(address) external view returns (bool);
  function getGroupNumMembers(address) external view returns (uint256);
  function getGroupsNumMembers(address[] calldata) external view returns (uint256[] memory);
  function getNumRegisteredValidators() external view returns (uint256);
  function getTopGroupValidators(address, uint256) external view returns (address[] memory);
  function updateEcdsaPublicKey(address, address, bytes calldata) external returns (bool);
  function updatePublicKeys(address, address, bytes calldata, bytes calldata, bytes calldata)
    external
    returns (bool);
  function isValidator(address) external view returns (bool);
  function isValidatorGroup(address) external view returns (bool);
  function calculateGroupEpochScore(uint256[] calldata uptimes) external view returns (uint256);
  function groupMembershipInEpoch(address account, uint256 epochNumber, uint256 index)
    external
    view
    returns (address);
  function halveSlashingMultiplier(address group) external;
  function forceDeaffiliateIfValidator(address validator) external;
  function getValidatorGroupSlashingMultiplier(address) external view returns (uint256);
  function affiliate(address group) external returns (bool);
}

contract CalledByVm {
  modifier onlyVm() {
    require(msg.sender == address(0), "Only VM can call");
    _;
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

library FixidityLib {
  struct Fraction {
    uint256 value;
  }

  
  function digits() internal pure returns (uint8) {
    return 24;
  }

  uint256 private constant FIXED1_UINT = 1000000000000000000000000;

  
  function fixed1() internal pure returns (Fraction memory) {
    return Fraction(FIXED1_UINT);
  }

  
  function wrap(uint256 x) internal pure returns (Fraction memory) {
    return Fraction(x);
  }

  
  function unwrap(Fraction memory x) internal pure returns (uint256) {
    return x.value;
  }

  
  function mulPrecision() internal pure returns (uint256) {
    return 1000000000000;
  }

  
  function maxNewFixed() internal pure returns (uint256) {
    return 115792089237316195423570985008687907853269984665640564;
  }

  
  function newFixed(uint256 x) internal pure returns (Fraction memory) {
    require(x <= maxNewFixed(), "can't create fixidity number larger than maxNewFixed()");
    return Fraction(x * FIXED1_UINT);
  }

  
  function fromFixed(Fraction memory x) internal pure returns (uint256) {
    return x.value / FIXED1_UINT;
  }

  
  function newFixedFraction(uint256 numerator, uint256 denominator)
    internal
    pure
    returns (Fraction memory)
  {
    Fraction memory convertedNumerator = newFixed(numerator);
    Fraction memory convertedDenominator = newFixed(denominator);
    return divide(convertedNumerator, convertedDenominator);
  }

  
  function integer(Fraction memory x) internal pure returns (Fraction memory) {
    return Fraction((x.value / FIXED1_UINT) * FIXED1_UINT); 
  }

  
  function fractional(Fraction memory x) internal pure returns (Fraction memory) {
    return Fraction(x.value - (x.value / FIXED1_UINT) * FIXED1_UINT); 
  }

  
  function add(Fraction memory x, Fraction memory y) internal pure returns (Fraction memory) {
    uint256 z = x.value + y.value;
    require(z >= x.value, "add overflow detected");
    return Fraction(z);
  }

  
  function subtract(Fraction memory x, Fraction memory y) internal pure returns (Fraction memory) {
    require(x.value >= y.value, "substraction underflow detected");
    return Fraction(x.value - y.value);
  }

  
  function multiply(Fraction memory x, Fraction memory y) internal pure returns (Fraction memory) {
    if (x.value == 0 || y.value == 0) return Fraction(0);
    if (y.value == FIXED1_UINT) return x;
    if (x.value == FIXED1_UINT) return y;

    
    
    uint256 x1 = integer(x).value / FIXED1_UINT;
    uint256 x2 = fractional(x).value;
    uint256 y1 = integer(y).value / FIXED1_UINT;
    uint256 y2 = fractional(y).value;

    
    uint256 x1y1 = x1 * y1;
    if (x1 != 0) require(x1y1 / x1 == y1, "overflow x1y1 detected");

    
    
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

    
    Fraction memory result = Fraction(x1y1);
    result = add(result, Fraction(x2y1)); 
    result = add(result, Fraction(x1y2)); 
    result = add(result, Fraction(x2y2)); 
    return result;
  }

  
  function reciprocal(Fraction memory x) internal pure returns (Fraction memory) {
    require(x.value != 0, "can't call reciprocal(0)");
    return Fraction((FIXED1_UINT * FIXED1_UINT) / x.value); 
  }

  
  function divide(Fraction memory x, Fraction memory y) internal pure returns (Fraction memory) {
    require(y.value != 0, "can't divide by 0");
    uint256 X = x.value * FIXED1_UINT;
    require(X / FIXED1_UINT == x.value, "overflow at divide");
    return Fraction(X / y.value);
  }

  
  function gt(Fraction memory x, Fraction memory y) internal pure returns (bool) {
    return x.value > y.value;
  }

  
  function gte(Fraction memory x, Fraction memory y) internal pure returns (bool) {
    return x.value >= y.value;
  }

  
  function lt(Fraction memory x, Fraction memory y) internal pure returns (bool) {
    return x.value < y.value;
  }

  
  function lte(Fraction memory x, Fraction memory y) internal pure returns (bool) {
    return x.value <= y.value;
  }

  
  function equals(Fraction memory x, Fraction memory y) internal pure returns (bool) {
    return x.value == y.value;
  }

  
  function isProperFraction(Fraction memory x) internal pure returns (bool) {
    return lte(x, fixed1());
  }
}

interface IERC20 {
    
    function totalSupply() external view returns (uint256);

    
    function balanceOf(address account) external view returns (uint256);

    
    function transfer(address recipient, uint256 amount) external returns (bool);

    
    function allowance(address owner, address spender) external view returns (uint256);

    
    function approve(address spender, uint256 amount) external returns (bool);

    
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);

    
    event Transfer(address indexed from, address indexed to, uint256 value);

    
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

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

interface IFeeCurrencyWhitelist {
  function addToken(address) external;
  function getWhitelist() external view returns (address[] memory);
}

interface IFreezer {
  function isFrozen(address) external view returns (bool);
}

interface IRegistry {
  function setAddressFor(string calldata, address) external;
  function getAddressForOrDie(bytes32) external view returns (address);
  function getAddressFor(bytes32) external view returns (address);
  function isOneOf(bytes32[] calldata, address) external view returns (bool);
}

interface IGovernance {
  function isVoting(address) external view returns (bool);
}

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

interface IRandom {
  function revealAndCommit(bytes32, bytes32, address) external;
  function randomnessBlockRetentionWindow() external view returns (uint256);
  function random() external view returns (bytes32);
  function getBlockRandomness(uint256) external view returns (bytes32);
}

interface IAttestations {
  function setAttestationRequestFee(address, uint256) external;
  function request(bytes32, uint256, address) external;
  function selectIssuers(bytes32) external;
  function complete(bytes32, uint8, bytes32, bytes32) external;
  function revoke(bytes32, uint256) external;
  function withdraw(address) external;

  function setAttestationExpiryBlocks(uint256) external;

  function getMaxAttestations() external view returns (uint256);

  function getUnselectedRequest(bytes32, address) external view returns (uint32, uint32, address);
  function getAttestationRequestFee(address) external view returns (uint256);

  function lookupAccountsForIdentifier(bytes32) external view returns (address[] memory);

  function getAttestationStats(bytes32, address) external view returns (uint32, uint32);

  function getAttestationState(bytes32, address, address)
    external
    view
    returns (uint8, uint32, address);
  function getCompletableAttestations(bytes32, address)
    external
    view
    returns (uint32[] memory, address[] memory, uint256[] memory, bytes memory);
}

interface IExchange {
  function exchange(uint256, uint256, bool) external returns (uint256);
  function setUpdateFrequency(uint256) external;
  function getBuyTokenAmount(uint256, bool) external view returns (uint256);
  function getSellTokenAmount(uint256, bool) external view returns (uint256);
  function getBuyAndSellBuckets(bool) external view returns (uint256, uint256);
}

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
}

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

interface IStableToken {
  function mint(address, uint256) external returns (bool);
  function burn(uint256) external returns (bool);
  function setInflationParameters(uint256, uint256) external;
  function valueToUnits(uint256) external view returns (uint256);
  function unitsToValue(uint256) external view returns (uint256);
  function getInflationParameters() external view returns (uint256, uint256, uint256, uint256);

  
  function balanceOf(address) external view returns (uint256);
}

contract UsingRegistry is Ownable {
  event RegistrySet(address indexed registryAddress);

  
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
  

  IRegistry public registry;

  modifier onlyRegisteredContract(bytes32 identifierHash) {
    require(registry.getAddressForOrDie(identifierHash) == msg.sender, "only registered contract");
    _;
  }

  modifier onlyRegisteredContracts(bytes32[] memory identifierHashes) {
    require(registry.isOneOf(identifierHashes, msg.sender), "only registered contracts");
    _;
  }

  
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

contract Freezable is UsingRegistry {
  
  
  modifier onlyWhenNotFrozen() {
    require(!getFreezer().isFrozen(address(this)), "can't call when contract is frozen");
    _;
  }
}

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

  
  function insert(List storage list, bytes32 key, bytes32 previousKey, bytes32 nextKey) public {
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

  
  function push(List storage list, bytes32 key) public {
    insert(list, key, bytes32(0), list.tail);
  }

  
  function remove(List storage list, bytes32 key) public {
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

  
  function update(List storage list, bytes32 key, bytes32 previousKey, bytes32 nextKey) public {
    require(
      key != bytes32(0) && key != previousKey && key != nextKey && contains(list, key),
      "key on in list"
    );
    remove(list, key);
    insert(list, key, previousKey, nextKey);
  }

  
  function contains(List storage list, bytes32 key) public view returns (bool) {
    return list.elements[key].exists;
  }

  
  function headN(List storage list, uint256 n) public view returns (bytes32[] memory) {
    require(n <= list.numElements, "not enough elements");
    bytes32[] memory keys = new bytes32[](n);
    bytes32 key = list.head;
    for (uint256 i = 0; i < n; i = i.add(1)) {
      keys[i] = key;
      key = list.elements[key].previousKey;
    }
    return keys;
  }

  
  function getKeys(List storage list) public view returns (bytes32[] memory) {
    return headN(list, list.numElements);
  }
}

library SortedLinkedList {
  using SafeMath for uint256;
  using LinkedList for LinkedList.List;

  struct List {
    LinkedList.List list;
    mapping(bytes32 => uint256) values;
  }

  
  function insert(
    List storage list,
    bytes32 key,
    uint256 value,
    bytes32 lesserKey,
    bytes32 greaterKey
  ) public {
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

  
  function remove(List storage list, bytes32 key) public {
    list.list.remove(key);
    list.values[key] = 0;
  }

  
  function update(
    List storage list,
    bytes32 key,
    uint256 value,
    bytes32 lesserKey,
    bytes32 greaterKey
  ) public {
    
    
    
    remove(list, key);
    insert(list, key, value, lesserKey, greaterKey);
  }

  
  function push(List storage list, bytes32 key) public {
    insert(list, key, 0, bytes32(0), list.list.tail);
  }

  
  function popN(List storage list, uint256 n) public returns (bytes32[] memory) {
    require(n <= list.list.numElements, "not enough elements");
    bytes32[] memory keys = new bytes32[](n);
    for (uint256 i = 0; i < n; i = i.add(1)) {
      bytes32 key = list.list.head;
      keys[i] = key;
      remove(list, key);
    }
    return keys;
  }

  
  function contains(List storage list, bytes32 key) public view returns (bool) {
    return list.list.contains(key);
  }

  
  function getValue(List storage list, bytes32 key) public view returns (uint256) {
    return list.values[key];
  }

  
  function getElements(List storage list) public view returns (bytes32[] memory, uint256[] memory) {
    bytes32[] memory keys = getKeys(list);
    uint256[] memory values = new uint256[](keys.length);
    for (uint256 i = 0; i < keys.length; i = i.add(1)) {
      values[i] = list.values[keys[i]];
    }
    return (keys, values);
  }

  
  function getKeys(List storage list) public view returns (bytes32[] memory) {
    return list.list.getKeys();
  }

  
  function headN(List storage list, uint256 n) public view returns (bytes32[] memory) {
    return list.list.headN(n);
  }

  
  
  function getLesserAndGreater(
    List storage list,
    uint256 value,
    bytes32 lesserKey,
    bytes32 greaterKey
  ) private view returns (bytes32, bytes32) {
    
    
    
    
    
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

library AddressSortedLinkedList {
  using SafeMath for uint256;
  using SortedLinkedList for SortedLinkedList.List;

  function toBytes(address a) public pure returns (bytes32) {
    return bytes32(uint256(a) << 96);
  }

  function toAddress(bytes32 b) public pure returns (address) {
    return address(uint256(b) >> 96);
  }

  
  function insert(
    SortedLinkedList.List storage list,
    address key,
    uint256 value,
    address lesserKey,
    address greaterKey
  ) public {
    list.insert(toBytes(key), value, toBytes(lesserKey), toBytes(greaterKey));
  }

  
  function remove(SortedLinkedList.List storage list, address key) public {
    list.remove(toBytes(key));
  }

  
  function update(
    SortedLinkedList.List storage list,
    address key,
    uint256 value,
    address lesserKey,
    address greaterKey
  ) public {
    list.update(toBytes(key), value, toBytes(lesserKey), toBytes(greaterKey));
  }

  
  function contains(SortedLinkedList.List storage list, address key) public view returns (bool) {
    return list.contains(toBytes(key));
  }

  
  function getValue(SortedLinkedList.List storage list, address key) public view returns (uint256) {
    return list.getValue(toBytes(key));
  }

  
  function getElements(SortedLinkedList.List storage list)
    public
    view
    returns (address[] memory, uint256[] memory)
  {
    bytes32[] memory byteKeys = list.getKeys();
    address[] memory keys = new address[](byteKeys.length);
    uint256[] memory values = new uint256[](byteKeys.length);
    for (uint256 i = 0; i < byteKeys.length; i = i.add(1)) {
      keys[i] = toAddress(byteKeys[i]);
      values[i] = list.values[byteKeys[i]];
    }
    return (keys, values);
  }

  
  function numElementsGreaterThan(
    SortedLinkedList.List storage list,
    uint256 threshold,
    uint256 max
  ) public view returns (uint256) {
    uint256 revisedMax = Math.min(max, list.list.numElements);
    bytes32 key = list.list.head;
    for (uint256 i = 0; i < revisedMax; i = i.add(1)) {
      if (list.getValue(key) < threshold) {
        return i;
      }
      key = list.list.elements[key].previousKey;
    }
    return revisedMax;
  }

  
  function headN(SortedLinkedList.List storage list, uint256 n)
    public
    view
    returns (address[] memory)
  {
    bytes32[] memory byteKeys = list.headN(n);
    address[] memory keys = new address[](n);
    for (uint256 i = 0; i < n; i = i.add(1)) {
      keys[i] = toAddress(byteKeys[i]);
    }
    return keys;
  }

  
  function getKeys(SortedLinkedList.List storage list) public view returns (address[] memory) {
    return headN(list, list.list.numElements);
  }
}

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

  
  function getEpochSize() public view returns (uint256) {
    bytes memory out;
    bool success;
    (success, out) = EPOCH_SIZE.staticcall(abi.encodePacked());
    require(success, "error calling getEpochSize precompile");
    return getUint256FromBytes(out, 0);
  }

  
  function getEpochNumberOfBlock(uint256 blockNumber) public view returns (uint256) {
    return epochNumberOfBlock(blockNumber, getEpochSize());
  }

  
  function getEpochNumber() public view returns (uint256) {
    return getEpochNumberOfBlock(block.number);
  }

  
  function epochNumberOfBlock(uint256 blockNumber, uint256 epochSize)
    internal
    pure
    returns (uint256)
  {
    
    uint256 epochNumber = blockNumber / epochSize;
    if (blockNumber % epochSize == 0) {
      return epochNumber;
    } else {
      return epochNumber + 1;
    }
  }

  
  function validatorSignerAddressFromCurrentSet(uint256 index) public view returns (address) {
    bytes memory out;
    bool success;
    (success, out) = GET_VALIDATOR.staticcall(abi.encodePacked(index, uint256(block.number)));
    require(success, "error calling validatorSignerAddressFromCurrentSet precompile");
    return address(getUint256FromBytes(out, 0));
  }

  
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

  
  function numberValidatorsInCurrentSet() public view returns (uint256) {
    bytes memory out;
    bool success;
    (success, out) = NUMBER_VALIDATORS.staticcall(abi.encodePacked(uint256(block.number)));
    require(success, "error calling numberValidatorsInCurrentSet precompile");
    return getUint256FromBytes(out, 0);
  }

  
  function numberValidatorsInSet(uint256 blockNumber) public view returns (uint256) {
    bytes memory out;
    bool success;
    (success, out) = NUMBER_VALIDATORS.staticcall(abi.encodePacked(blockNumber));
    require(success, "error calling numberValidatorsInSet precompile");
    return getUint256FromBytes(out, 0);
  }

  
  function checkProofOfPossession(address sender, bytes memory blsKey, bytes memory blsPop)
    public
    view
    returns (bool)
  {
    bool success;
    (success, ) = PROOF_OF_POSSESSION.staticcall(abi.encodePacked(sender, blsKey, blsPop));
    return success;
  }

  
  function getBlockNumberFromHeader(bytes memory header) public view returns (uint256) {
    bytes memory out;
    bool success;
    (success, out) = BLOCK_NUMBER_FROM_HEADER.staticcall(abi.encodePacked(header));
    require(success, "error calling getBlockNumberFromHeader precompile");
    return getUint256FromBytes(out, 0);
  }

  
  function hashHeader(bytes memory header) public view returns (bytes32) {
    bytes memory out;
    bool success;
    (success, out) = HASH_HEADER.staticcall(abi.encodePacked(header));
    require(success, "error calling hashHeader precompile");
    return getBytes32FromBytes(out, 0);
  }

  
  function getParentSealBitmap(uint256 blockNumber) public view returns (bytes32) {
    bytes memory out;
    bool success;
    (success, out) = GET_PARENT_SEAL_BITMAP.staticcall(abi.encodePacked(blockNumber));
    require(success, "error calling getParentSealBitmap precompile");
    return getBytes32FromBytes(out, 0);
  }

  
  function getVerifiedSealBitmapFromHeader(bytes memory header) public view returns (bytes32) {
    bytes memory out;
    bool success;
    (success, out) = GET_VERIFIED_SEAL_BITMAP.staticcall(abi.encodePacked(header));
    require(success, "error calling getVerifiedSealBitmapFromHeader precompile");
    return getBytes32FromBytes(out, 0);
  }

  
  function getUint256FromBytes(bytes memory bs, uint256 start) internal pure returns (uint256) {
    return uint256(getBytes32FromBytes(bs, start));
  }

  
  function getBytes32FromBytes(bytes memory bs, uint256 start) internal pure returns (bytes32) {
    require(bs.length >= start + 32, "slicing out of range");
    bytes32 x;
    assembly {
      x := mload(add(bs, add(start, 32)))
    }
    return x;
  }

  
  function minQuorumSize(uint256 blockNumber) public view returns (uint256) {
    return numberValidatorsInSet(blockNumber).mul(2).add(2).div(3);
  }

  
  function minQuorumSizeInCurrentSet() public view returns (uint256) {
    return minQuorumSize(block.number);
  }

}

library Heap {
  using FixidityLib for FixidityLib.Fraction;
  using SafeMath for uint256;

  
  function siftDown(
    uint256[] memory keys,
    FixidityLib.Fraction[] memory values,
    uint256 start,
    uint256 length
  ) internal pure {
    require(keys.length == values.length, "key and value array length mismatch");
    require(start < keys.length, "heap start index out of range");
    require(length <= keys.length, "heap length out of range");
    uint256 i = start;
    while (true) {
      uint256 leftChild = i.mul(2).add(1);
      uint256 rightChild = i.mul(2).add(2);
      uint256 maxIndex = i;
      if (leftChild < length && values[keys[leftChild]].gt(values[keys[maxIndex]])) {
        maxIndex = leftChild;
      }
      if (rightChild < length && values[keys[rightChild]].gt(values[keys[maxIndex]])) {
        maxIndex = rightChild;
      }
      if (maxIndex == i) break;
      uint256 tmpKey = keys[i];
      keys[i] = keys[maxIndex];
      keys[maxIndex] = tmpKey;
      i = maxIndex;
    }
  }

  
  function heapifyDown(uint256[] memory keys, FixidityLib.Fraction[] memory values) internal pure {
    siftDown(keys, values, 0, keys.length);
  }

}

contract ReentrancyGuard {
  
  uint256 private _guardCounter;

  constructor() internal {
    
    
    _guardCounter = 1;
  }

  
  modifier nonReentrant() {
    _guardCounter += 1;
    uint256 localCounter = _guardCounter;
    _;
    require(localCounter == _guardCounter, "reentrant call");
  }
}

contract Election is
  IElection,
  Ownable,
  ReentrancyGuard,
  Initializable,
  UsingRegistry,
  UsingPrecompiles,
  Freezable,
  CalledByVm
{
  using AddressSortedLinkedList for SortedLinkedList.List;
  using FixidityLib for FixidityLib.Fraction;
  using SafeMath for uint256;

  
  
  
  
  uint256 private constant UNIT_PRECISION_FACTOR = 100000000000000000000;

  struct PendingVote {
    
    uint256 value;
    
    uint256 epoch;
  }

  struct GroupPendingVotes {
    
    uint256 total;
    
    mapping(address => PendingVote) byAccount;
  }

  
  
  
  struct PendingVotes {
    
    uint256 total;
    mapping(address => GroupPendingVotes) forGroup;
  }

  struct GroupActiveVotes {
    
    uint256 total;
    
    
    
    uint256 totalUnits;
    mapping(address => uint256) unitsByAccount;
  }

  
  
  struct ActiveVotes {
    
    uint256 total;
    mapping(address => GroupActiveVotes) forGroup;
  }

  struct TotalVotes {
    
    
    
    SortedLinkedList.List eligible;
  }

  struct Votes {
    PendingVotes pending;
    ActiveVotes active;
    TotalVotes total;
    
    mapping(address => address[]) groupsVotedFor;
  }

  struct ElectableValidators {
    uint256 min;
    uint256 max;
  }

  Votes private votes;
  
  ElectableValidators public electableValidators;
  
  uint256 public maxNumGroupsVotedFor;
  
  
  FixidityLib.Fraction public electabilityThreshold;

  event ElectableValidatorsSet(uint256 min, uint256 max);
  event MaxNumGroupsVotedForSet(uint256 maxNumGroupsVotedFor);
  event ElectabilityThresholdSet(uint256 electabilityThreshold);
  event ValidatorGroupMarkedEligible(address indexed group);
  event ValidatorGroupMarkedIneligible(address indexed group);
  event ValidatorGroupVoteCast(address indexed account, address indexed group, uint256 value);
  event ValidatorGroupVoteActivated(
    address indexed account,
    address indexed group,
    uint256 value,
    uint256 units
  );
  event ValidatorGroupPendingVoteRevoked(
    address indexed account,
    address indexed group,
    uint256 value
  );
  event ValidatorGroupActiveVoteRevoked(
    address indexed account,
    address indexed group,
    uint256 value,
    uint256 units
  );
  event EpochRewardsDistributedToVoters(address indexed group, uint256 value);

  
  function initialize(
    address registryAddress,
    uint256 minElectableValidators,
    uint256 maxElectableValidators,
    uint256 _maxNumGroupsVotedFor,
    uint256 _electabilityThreshold
  ) external initializer {
    _transferOwnership(msg.sender);
    setRegistry(registryAddress);
    setElectableValidators(minElectableValidators, maxElectableValidators);
    setMaxNumGroupsVotedFor(_maxNumGroupsVotedFor);
    setElectabilityThreshold(_electabilityThreshold);
  }

  
  function setElectableValidators(uint256 min, uint256 max) public onlyOwner returns (bool) {
    require(0 < min, "Minimum electable validators cannot be zero");
    require(min <= max, "Maximum electable validators cannot be smaller than minimum");
    require(
      min != electableValidators.min || max != electableValidators.max,
      "Electable validators not changed"
    );
    electableValidators = ElectableValidators(min, max);
    emit ElectableValidatorsSet(min, max);
    return true;
  }

  
  function getElectableValidators() external view returns (uint256, uint256) {
    return (electableValidators.min, electableValidators.max);
  }

  
  function setMaxNumGroupsVotedFor(uint256 _maxNumGroupsVotedFor) public onlyOwner returns (bool) {
    require(_maxNumGroupsVotedFor != maxNumGroupsVotedFor, "Max groups voted for not changed");
    maxNumGroupsVotedFor = _maxNumGroupsVotedFor;
    emit MaxNumGroupsVotedForSet(_maxNumGroupsVotedFor);
    return true;
  }

  
  function setElectabilityThreshold(uint256 threshold) public onlyOwner returns (bool) {
    electabilityThreshold = FixidityLib.wrap(threshold);
    require(
      electabilityThreshold.lt(FixidityLib.fixed1()),
      "Electability threshold must be lower than 100%"
    );
    emit ElectabilityThresholdSet(threshold);
    return true;
  }

  
  function getElectabilityThreshold() external view returns (uint256) {
    return electabilityThreshold.unwrap();
  }

  
  function vote(address group, uint256 value, address lesser, address greater)
    external
    nonReentrant
    returns (bool)
  {
    require(votes.total.eligible.contains(group), "Group not eligible");
    require(0 < value, "Vote value cannot be zero");
    require(canReceiveVotes(group, value), "Group cannot receive votes");
    address account = getAccounts().voteSignerToAccount(msg.sender);

    
    bool alreadyVotedForGroup = false;
    address[] storage groups = votes.groupsVotedFor[account];
    for (uint256 i = 0; i < groups.length; i = i.add(1)) {
      alreadyVotedForGroup = alreadyVotedForGroup || groups[i] == group;
    }
    if (!alreadyVotedForGroup) {
      require(groups.length < maxNumGroupsVotedFor, "Voted for too many groups");
      groups.push(group);
    }

    incrementPendingVotes(group, account, value);
    incrementTotalVotes(group, value, lesser, greater);
    getLockedGold().decrementNonvotingAccountBalance(account, value);
    emit ValidatorGroupVoteCast(account, group, value);
    return true;
  }

  
  function activate(address group) external nonReentrant returns (bool) {
    address account = getAccounts().voteSignerToAccount(msg.sender);
    PendingVote storage pendingVote = votes.pending.forGroup[group].byAccount[account];
    require(pendingVote.epoch < getEpochNumber(), "Pending vote epoch not passed");
    uint256 value = pendingVote.value;
    require(value > 0, "Vote value cannot be zero");
    decrementPendingVotes(group, account, value);
    uint256 units = incrementActiveVotes(group, account, value);
    emit ValidatorGroupVoteActivated(account, group, value, units);
    return true;
  }

  
  function hasActivatablePendingVotes(address account, address group) external view returns (bool) {
    PendingVote storage pendingVote = votes.pending.forGroup[group].byAccount[account];
    return pendingVote.epoch < getEpochNumber() && pendingVote.value > 0;
  }

  
  function revokePending(
    address group,
    uint256 value,
    address lesser,
    address greater,
    uint256 index
  ) external nonReentrant returns (bool) {
    require(group != address(0), "Group address zero");
    address account = getAccounts().voteSignerToAccount(msg.sender);
    require(0 < value, "Vote value cannot be zero");
    require(
      value <= getPendingVotesForGroupByAccount(group, account),
      "Vote value larger than pending votes"
    );
    decrementPendingVotes(group, account, value);
    decrementTotalVotes(group, value, lesser, greater);
    getLockedGold().incrementNonvotingAccountBalance(account, value);
    if (getTotalVotesForGroupByAccount(group, account) == 0) {
      deleteElement(votes.groupsVotedFor[account], group, index);
    }
    emit ValidatorGroupPendingVoteRevoked(account, group, value);
    return true;
  }

  
  function revokeAllActive(address group, address lesser, address greater, uint256 index)
    external
    nonReentrant
    returns (bool)
  {
    address account = getAccounts().voteSignerToAccount(msg.sender);
    uint256 value = getActiveVotesForGroupByAccount(group, account);
    return revokeActive(group, value, lesser, greater, index);
  }

  
  function revokeActive(
    address group,
    uint256 value,
    address lesser,
    address greater,
    uint256 index
  ) public nonReentrant returns (bool) {
    
    require(group != address(0), "Group address zero");
    address account = getAccounts().voteSignerToAccount(msg.sender);
    require(0 < value, "Vote value cannot be zero");
    require(
      value <= getActiveVotesForGroupByAccount(group, account),
      "Vote value larger than active votes"
    );
    uint256 units = decrementActiveVotes(group, account, value);
    decrementTotalVotes(group, value, lesser, greater);
    getLockedGold().incrementNonvotingAccountBalance(account, value);
    if (getTotalVotesForGroupByAccount(group, account) == 0) {
      deleteElement(votes.groupsVotedFor[account], group, index);
    }
    emit ValidatorGroupActiveVoteRevoked(account, group, value, units);
    return true;
  }

  
  function _decrementVotes(
    address account,
    address group,
    uint256 maxValue,
    address lesser,
    address greater,
    uint256 index
  ) internal returns (uint256) {
    uint256 remainingValue = maxValue;
    uint256 pendingVotes = getPendingVotesForGroupByAccount(group, account);
    if (pendingVotes > 0) {
      uint256 decrementValue = Math.min(remainingValue, pendingVotes);
      decrementPendingVotes(group, account, decrementValue);
      emit ValidatorGroupPendingVoteRevoked(account, group, decrementValue);
      remainingValue = remainingValue.sub(decrementValue);
    }
    uint256 activeVotes = getActiveVotesForGroupByAccount(group, account);
    if (activeVotes > 0 && remainingValue > 0) {
      uint256 decrementValue = Math.min(remainingValue, activeVotes);
      uint256 units = decrementActiveVotes(group, account, decrementValue);
      emit ValidatorGroupActiveVoteRevoked(account, group, decrementValue, units);
      remainingValue = remainingValue.sub(decrementValue);
    }
    uint256 decrementedValue = maxValue.sub(remainingValue);
    if (decrementedValue > 0) {
      decrementTotalVotes(group, decrementedValue, lesser, greater);
      if (getTotalVotesForGroupByAccount(group, account) == 0) {
        deleteElement(votes.groupsVotedFor[account], group, index);
      }
    }
    return decrementedValue;
  }

  
  function getTotalVotesByAccount(address account) external view returns (uint256) {
    uint256 total = 0;
    address[] memory groups = votes.groupsVotedFor[account];
    for (uint256 i = 0; i < groups.length; i = i.add(1)) {
      total = total.add(getTotalVotesForGroupByAccount(groups[i], account));
    }
    return total;
  }

  
  function getPendingVotesForGroupByAccount(address group, address account)
    public
    view
    returns (uint256)
  {
    return votes.pending.forGroup[group].byAccount[account].value;
  }

  
  function getActiveVotesForGroupByAccount(address group, address account)
    public
    view
    returns (uint256)
  {
    return unitsToVotes(group, votes.active.forGroup[group].unitsByAccount[account]);
  }

  
  function getTotalVotesForGroupByAccount(address group, address account)
    public
    view
    returns (uint256)
  {
    uint256 pending = getPendingVotesForGroupByAccount(group, account);
    uint256 active = getActiveVotesForGroupByAccount(group, account);
    return pending.add(active);
  }

  
  function getActiveVoteUnitsForGroupByAccount(address group, address account)
    external
    view
    returns (uint256)
  {
    return votes.active.forGroup[group].unitsByAccount[account];
  }

  
  function getActiveVoteUnitsForGroup(address group) external view returns (uint256) {
    return votes.active.forGroup[group].totalUnits;
  }

  
  function getTotalVotesForGroup(address group) public view returns (uint256) {
    return votes.pending.forGroup[group].total.add(votes.active.forGroup[group].total);
  }

  
  function getActiveVotesForGroup(address group) public view returns (uint256) {
    return votes.active.forGroup[group].total;
  }

  
  function getPendingVotesForGroup(address group) public view returns (uint256) {
    return votes.pending.forGroup[group].total;
  }

  
  function getGroupEligibility(address group) external view returns (bool) {
    return votes.total.eligible.contains(group);
  }

  
  function getGroupEpochRewards(
    address group,
    uint256 totalEpochRewards,
    uint256[] calldata uptimes
  ) external view returns (uint256) {
    IValidators validators = getValidators();
    
    if (!validators.meetsAccountLockedGoldRequirements(group) || votes.active.total <= 0) {
      return 0;
    }

    FixidityLib.Fraction memory votePortion = FixidityLib.newFixedFraction(
      votes.active.forGroup[group].total,
      votes.active.total
    );
    FixidityLib.Fraction memory score = FixidityLib.wrap(
      validators.calculateGroupEpochScore(uptimes)
    );
    FixidityLib.Fraction memory slashingMultiplier = FixidityLib.wrap(
      validators.getValidatorGroupSlashingMultiplier(group)
    );
    return
      FixidityLib
        .newFixed(totalEpochRewards)
        .multiply(votePortion)
        .multiply(score)
        .multiply(slashingMultiplier)
        .fromFixed();
  }

  
  function distributeEpochRewards(address group, uint256 value, address lesser, address greater)
    external
    onlyVm
  {
    _distributeEpochRewards(group, value, lesser, greater);
  }

  
  function _distributeEpochRewards(address group, uint256 value, address lesser, address greater)
    internal
  {
    if (votes.total.eligible.contains(group)) {
      uint256 newVoteTotal = votes.total.eligible.getValue(group).add(value);
      votes.total.eligible.update(group, newVoteTotal, lesser, greater);
    }

    votes.active.forGroup[group].total = votes.active.forGroup[group].total.add(value);
    votes.active.total = votes.active.total.add(value);
    emit EpochRewardsDistributedToVoters(group, value);
  }

  
  function incrementTotalVotes(address group, uint256 value, address lesser, address greater)
    private
  {
    uint256 newVoteTotal = votes.total.eligible.getValue(group).add(value);
    votes.total.eligible.update(group, newVoteTotal, lesser, greater);
  }

  
  function decrementTotalVotes(address group, uint256 value, address lesser, address greater)
    private
  {
    if (votes.total.eligible.contains(group)) {
      uint256 newVoteTotal = votes.total.eligible.getValue(group).sub(value);
      votes.total.eligible.update(group, newVoteTotal, lesser, greater);
    }
  }

  
  function markGroupIneligible(address group)
    external
    onlyRegisteredContract(VALIDATORS_REGISTRY_ID)
  {
    votes.total.eligible.remove(group);
    emit ValidatorGroupMarkedIneligible(group);
  }

  
  function markGroupEligible(address group, address lesser, address greater)
    external
    onlyRegisteredContract(VALIDATORS_REGISTRY_ID)
  {
    uint256 value = getTotalVotesForGroup(group);
    votes.total.eligible.insert(group, value, lesser, greater);
    emit ValidatorGroupMarkedEligible(group);
  }

  
  function incrementPendingVotes(address group, address account, uint256 value) private {
    PendingVotes storage pending = votes.pending;
    pending.total = pending.total.add(value);

    GroupPendingVotes storage groupPending = pending.forGroup[group];
    groupPending.total = groupPending.total.add(value);

    PendingVote storage pendingVote = groupPending.byAccount[account];
    pendingVote.value = pendingVote.value.add(value);
    pendingVote.epoch = getEpochNumber();
  }

  
  function decrementPendingVotes(address group, address account, uint256 value) private {
    PendingVotes storage pending = votes.pending;
    pending.total = pending.total.sub(value);

    GroupPendingVotes storage groupPending = pending.forGroup[group];
    groupPending.total = groupPending.total.sub(value);

    PendingVote storage pendingVote = groupPending.byAccount[account];
    pendingVote.value = pendingVote.value.sub(value);
    if (pendingVote.value == 0) {
      pendingVote.epoch = 0;
    }
  }

  
  function incrementActiveVotes(address group, address account, uint256 value)
    private
    returns (uint256)
  {
    ActiveVotes storage active = votes.active;
    active.total = active.total.add(value);

    uint256 units = votesToUnits(group, value);

    GroupActiveVotes storage groupActive = active.forGroup[group];
    groupActive.total = groupActive.total.add(value);

    groupActive.totalUnits = groupActive.totalUnits.add(units);
    groupActive.unitsByAccount[account] = groupActive.unitsByAccount[account].add(units);
    return units;
  }

  
  function decrementActiveVotes(address group, address account, uint256 value)
    private
    returns (uint256)
  {
    ActiveVotes storage active = votes.active;
    active.total = active.total.sub(value);

    
    
    
    uint256 units = 0;
    uint256 activeVotes = getActiveVotesForGroupByAccount(group, account);
    GroupActiveVotes storage groupActive = active.forGroup[group];
    if (activeVotes == value) {
      units = groupActive.unitsByAccount[account];
    } else {
      units = votesToUnits(group, value);
    }

    groupActive.total = groupActive.total.sub(value);
    groupActive.totalUnits = groupActive.totalUnits.sub(units);
    groupActive.unitsByAccount[account] = groupActive.unitsByAccount[account].sub(units);
    return units;
  }

  
  function votesToUnits(address group, uint256 value) private view returns (uint256) {
    if (votes.active.forGroup[group].totalUnits == 0) {
      return value.mul(UNIT_PRECISION_FACTOR);
    } else {
      return
        value.mul(votes.active.forGroup[group].totalUnits).div(votes.active.forGroup[group].total);
    }
  }

  
  function unitsToVotes(address group, uint256 value) private view returns (uint256) {
    if (votes.active.forGroup[group].totalUnits == 0) {
      return 0;
    } else {
      return
        value.mul(votes.active.forGroup[group].total).div(votes.active.forGroup[group].totalUnits);
    }
  }

  
  function getGroupsVotedForByAccount(address account) external view returns (address[] memory) {
    return votes.groupsVotedFor[account];
  }

  
  function deleteElement(address[] storage list, address element, uint256 index) private {
    
    require(index < list.length && list[index] == element, "Bad index");
    uint256 lastIndex = list.length.sub(1);
    list[index] = list[lastIndex];
    list.length = lastIndex;
  }

  
  function canReceiveVotes(address group, uint256 value) public view returns (bool) {
    uint256 totalVotesForGroup = getTotalVotesForGroup(group).add(value);
    uint256 left = totalVotesForGroup.mul(
      Math.min(electableValidators.max, getValidators().getNumRegisteredValidators())
    );
    uint256 right = getValidators().getGroupNumMembers(group).add(1).mul(
      getLockedGold().getTotalLockedGold()
    );
    return left <= right;
  }

  
  function getNumVotesReceivable(address group) external view returns (uint256) {
    uint256 numerator = getValidators().getGroupNumMembers(group).add(1).mul(
      getLockedGold().getTotalLockedGold()
    );
    uint256 denominator = Math.min(
      electableValidators.max,
      getValidators().getNumRegisteredValidators()
    );
    return numerator.div(denominator);
  }

  
  function getTotalVotes() public view returns (uint256) {
    return votes.active.total.add(votes.pending.total);
  }

  
  function getActiveVotes() public view returns (uint256) {
    return votes.active.total;
  }

  
  function getEligibleValidatorGroups() external view returns (address[] memory) {
    return votes.total.eligible.getKeys();
  }

  
  function getTotalVotesForEligibleValidatorGroups()
    external
    view
    returns (address[] memory groups, uint256[] memory values)
  {
    return votes.total.eligible.getElements();
  }

  
  function electValidatorSigners() external view onlyWhenNotFrozen returns (address[] memory) {
    return electNValidatorSigners(electableValidators.min, electableValidators.max);
  }

  
  function electNValidatorSigners(uint256 minElectableValidators, uint256 maxElectableValidators)
    public
    view
    returns (address[] memory)
  {
    
    
    uint256 requiredVotes = electabilityThreshold
      .multiply(FixidityLib.newFixed(getTotalVotes()))
      .fromFixed();
    
    
    uint256 numElectionGroups = votes.total.eligible.numElementsGreaterThan(
      requiredVotes,
      maxElectableValidators
    );
    address[] memory electionGroups = votes.total.eligible.headN(numElectionGroups);
    uint256[] memory numMembers = getValidators().getGroupsNumMembers(electionGroups);
    
    uint256[] memory numMembersElected = new uint256[](electionGroups.length);
    uint256 totalNumMembersElected = 0;

    uint256[] memory keys = new uint256[](electionGroups.length);
    FixidityLib.Fraction[] memory votesForNextMember = new FixidityLib.Fraction[](
      electionGroups.length
    );
    for (uint256 i = 0; i < electionGroups.length; i++) {
      keys[i] = i;
      votesForNextMember[i] = FixidityLib.newFixed(
        votes.total.eligible.getValue(electionGroups[i])
      );
    }

    
    while (totalNumMembersElected < maxElectableValidators && electionGroups.length > 0) {
      uint256 groupIndex = keys[0];
      
      if (votesForNextMember[groupIndex].unwrap() == 0) break;
      
      if (numMembers[groupIndex] <= numMembersElected[groupIndex]) {
        votesForNextMember[groupIndex] = FixidityLib.wrap(0);
      } else {
        
        numMembersElected[groupIndex] = numMembersElected[groupIndex].add(1);
        totalNumMembersElected = totalNumMembersElected.add(1);
        
        
        votesForNextMember[groupIndex] = FixidityLib
          .newFixed(votes.total.eligible.getValue(electionGroups[groupIndex]))
          .divide(FixidityLib.newFixed(numMembersElected[groupIndex].add(1)));
      }
      Heap.heapifyDown(keys, votesForNextMember);
    }
    require(totalNumMembersElected >= minElectableValidators, "Not enough elected validators");
    
    address[] memory electedValidators = new address[](totalNumMembersElected);
    totalNumMembersElected = 0;
    for (uint256 i = 0; i < electionGroups.length; i = i.add(1)) {
      
      address[] memory electedGroupValidators = getValidators().getTopGroupValidators(
        electionGroups[i],
        numMembersElected[i]
      );
      for (uint256 j = 0; j < electedGroupValidators.length; j = j.add(1)) {
        electedValidators[totalNumMembersElected] = electedGroupValidators[j];
        totalNumMembersElected = totalNumMembersElected.add(1);
      }
    }
    return electedValidators;
  }

  
  function getCurrentValidatorSigners() public view returns (address[] memory) {
    uint256 n = numberValidatorsInCurrentSet();
    address[] memory res = new address[](n);
    for (uint256 i = 0; i < n; i = i.add(1)) {
      res[i] = validatorSignerAddressFromCurrentSet(i);
    }
    return res;
  }

  
  
  struct DecrementVotesInfo {
    address[] groups;
    uint256 remainingValue;
  }

  
  function forceDecrementVotes(
    address account,
    uint256 value,
    address[] calldata lessers,
    address[] calldata greaters,
    uint256[] calldata indices
  ) external nonReentrant onlyRegisteredContract(LOCKED_GOLD_REGISTRY_ID) returns (uint256) {
    require(value > 0, "Decrement value must be greater than 0.");
    DecrementVotesInfo memory info = DecrementVotesInfo(votes.groupsVotedFor[account], value);
    require(
      lessers.length <= info.groups.length &&
        lessers.length == greaters.length &&
        greaters.length == indices.length,
      "Input lengths must be correspond."
    );
    
    
    for (uint256 i = info.groups.length; i > 0; i = i.sub(1)) {
      info.remainingValue = info.remainingValue.sub(
        _decrementVotes(
          account,
          info.groups[i.sub(1)],
          info.remainingValue,
          lessers[i.sub(1)],
          greaters[i.sub(1)],
          indices[i.sub(1)]
        )
      );
      if (info.remainingValue == 0) {
        break;
      }
    }
    require(info.remainingValue == 0, "Failure to decrement all votes.");
    return value.sub(info.remainingValue);
  }
}