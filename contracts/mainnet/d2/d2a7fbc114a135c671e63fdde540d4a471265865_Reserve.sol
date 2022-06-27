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

contract Initializable {
  bool public initialized;

  modifier initializer() {
    require(!initialized, "contract already initialized");
    initialized = true;
    _;
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

contract Reserve is IReserve, Ownable, Initializable, UsingRegistry, ReentrancyGuard {
  using SafeMath for uint256;
  using FixidityLib for FixidityLib.Fraction;

  struct TobinTaxCache {
    uint128 numerator;
    uint128 timestamp;
  }

  mapping(address => bool) public isToken;
  address[] private _tokens;
  TobinTaxCache public tobinTaxCache;
  uint256 public tobinTaxStalenessThreshold;
  uint256 public tobinTax;
  uint256 public tobinTaxReserveRatio;
  mapping(address => bool) public isSpender;

  mapping(address => bool) public isOtherReserveAddress;
  address[] public otherReserveAddresses;

  bytes32[] public assetAllocationSymbols;
  mapping(bytes32 => uint256) public assetAllocationWeights;

  uint256 public lastSpendingDay;
  uint256 public spendingLimit;
  FixidityLib.Fraction private spendingRatio;

  uint256 public frozenReserveGoldStartBalance;
  uint256 public frozenReserveGoldStartDay;
  uint256 public frozenReserveGoldDays;

  event TobinTaxStalenessThresholdSet(uint256 value);
  event DailySpendingRatioSet(uint256 ratio);
  event TokenAdded(address indexed token);
  event TokenRemoved(address indexed token, uint256 index);
  event SpenderAdded(address indexed spender);
  event SpenderRemoved(address indexed spender);
  event OtherReserveAddressAdded(address indexed otherReserveAddress);
  event OtherReserveAddressRemoved(address indexed otherReserveAddress, uint256 index);
  event AssetAllocationSet(bytes32[] symbols, uint256[] weights);
  event ReserveGoldTransferred(address indexed spender, address indexed to, uint256 value);
  event TobinTaxSet(uint256 value);
  event TobinTaxReserveRatioSet(uint256 value);

  modifier isStableToken(address token) {
    require(isToken[token], "token addr was never registered");
    _;
  }

  function() external payable {} 

  
  function initialize(
    address registryAddress,
    uint256 _tobinTaxStalenessThreshold,
    uint256 _spendingRatio,
    uint256 _frozenGold,
    uint256 _frozenDays,
    bytes32[] calldata _assetAllocationSymbols,
    uint256[] calldata _assetAllocationWeights,
    uint256 _tobinTax,
    uint256 _tobinTaxReserveRatio
  ) external initializer {
    _transferOwnership(msg.sender);
    setRegistry(registryAddress);
    setTobinTaxStalenessThreshold(_tobinTaxStalenessThreshold);
    setDailySpendingRatio(_spendingRatio);
    setFrozenGold(_frozenGold, _frozenDays);
    setAssetAllocations(_assetAllocationSymbols, _assetAllocationWeights);
    setTobinTax(_tobinTax);
    setTobinTaxReserveRatio(_tobinTaxReserveRatio);
  }

  
  function setTobinTaxStalenessThreshold(uint256 value) public onlyOwner {
    require(value > 0, "value was zero");
    tobinTaxStalenessThreshold = value;
    emit TobinTaxStalenessThresholdSet(value);
  }

  
  function setTobinTax(uint256 value) public onlyOwner {
    require(FixidityLib.wrap(value).lte(FixidityLib.fixed1()), "tobin tax cannot be larger than 1");
    tobinTax = value;
    emit TobinTaxSet(value);
  }

  
  function setTobinTaxReserveRatio(uint256 value) public onlyOwner {
    tobinTaxReserveRatio = value;
    emit TobinTaxReserveRatioSet(value);
  }

  
  function setDailySpendingRatio(uint256 ratio) public onlyOwner {
    spendingRatio = FixidityLib.wrap(ratio);
    require(spendingRatio.lte(FixidityLib.fixed1()), "spending ratio cannot be larger than 1");
    emit DailySpendingRatioSet(ratio);
  }

  
  function getDailySpendingRatio() public view returns (uint256) {
    return spendingRatio.unwrap();
  }

  
  function setFrozenGold(uint256 frozenGold, uint256 frozenDays) public onlyOwner {
    require(frozenGold <= address(this).balance, "Cannot freeze more than balance");
    frozenReserveGoldStartBalance = frozenGold;
    frozenReserveGoldStartDay = now / 1 days;
    frozenReserveGoldDays = frozenDays;
  }

  
  function setAssetAllocations(bytes32[] memory symbols, uint256[] memory weights)
    public
    onlyOwner
  {
    require(symbols.length == weights.length, "Array length mismatch");
    FixidityLib.Fraction memory sum = FixidityLib.wrap(0);
    for (uint256 i = 0; i < weights.length; i = i.add(1)) {
      sum = sum.add(FixidityLib.wrap(weights[i]));
    }
    require(sum.equals(FixidityLib.fixed1()), "Sum of asset allocation must be 1");
    for (uint256 i = 0; i < assetAllocationSymbols.length; i = i.add(1)) {
      delete assetAllocationWeights[assetAllocationSymbols[i]];
    }
    assetAllocationSymbols = symbols;
    for (uint256 i = 0; i < symbols.length; i = i.add(1)) {
      require(assetAllocationWeights[symbols[i]] == 0, "Cannot set weight twice");
      assetAllocationWeights[symbols[i]] = weights[i];
    }
    require(assetAllocationWeights["cGLD"] != 0, "Must set cGLD asset weight");
    emit AssetAllocationSet(symbols, weights);
  }

  
  function addToken(address token) external onlyOwner nonReentrant returns (bool) {
    require(!isToken[token], "token addr already registered");
    
    address sortedOraclesAddress = registry.getAddressForOrDie(SORTED_ORACLES_REGISTRY_ID);
    ISortedOracles sortedOracles = ISortedOracles(sortedOraclesAddress);
    uint256 tokenAmount;
    uint256 goldAmount;
    (tokenAmount, goldAmount) = sortedOracles.medianRate(token);
    require(goldAmount > 0, "median rate returned 0 gold");
    isToken[token] = true;
    _tokens.push(token);
    emit TokenAdded(token);
    return true;
  }

  
  function removeToken(address token, uint256 index)
    external
    onlyOwner
    isStableToken(token)
    returns (bool)
  {
    require(
      index < _tokens.length && _tokens[index] == token,
      "index into tokens list not mapped to token"
    );
    isToken[token] = false;
    address lastItem = _tokens[_tokens.length.sub(1)];
    _tokens[index] = lastItem;
    _tokens.length = _tokens.length.sub(1);
    emit TokenRemoved(token, index);
    return true;
  }

  
  function addOtherReserveAddress(address reserveAddress)
    external
    onlyOwner
    nonReentrant
    returns (bool)
  {
    require(!isOtherReserveAddress[reserveAddress], "reserve addr already added");
    isOtherReserveAddress[reserveAddress] = true;
    otherReserveAddresses.push(reserveAddress);
    emit OtherReserveAddressAdded(reserveAddress);
    return true;
  }

  
  function removeOtherReserveAddress(address reserveAddress, uint256 index)
    external
    onlyOwner
    returns (bool)
  {
    require(isOtherReserveAddress[reserveAddress], "reserve addr was never added");
    require(
      index < otherReserveAddresses.length && otherReserveAddresses[index] == reserveAddress,
      "index into reserve list not mapped to address"
    );
    isOtherReserveAddress[reserveAddress] = false;
    address lastItem = otherReserveAddresses[otherReserveAddresses.length.sub(1)];
    otherReserveAddresses[index] = lastItem;
    otherReserveAddresses.length = otherReserveAddresses.length.sub(1);
    emit OtherReserveAddressRemoved(reserveAddress, index);
    return true;
  }

  
  function addSpender(address spender) external onlyOwner {
    isSpender[spender] = true;
    emit SpenderAdded(spender);
  }

  
  function removeSpender(address spender) external onlyOwner {
    isSpender[spender] = false;
    emit SpenderRemoved(spender);
  }

  
  function transferGold(address payable to, uint256 value) external returns (bool) {
    require(isSpender[msg.sender], "sender not allowed to transfer Reserve funds");
    require(isOtherReserveAddress[to], "can only transfer to other reserve address");
    uint256 currentDay = now / 1 days;
    if (currentDay > lastSpendingDay) {
      uint256 balance = getUnfrozenReserveGoldBalance();
      lastSpendingDay = currentDay;
      spendingLimit = spendingRatio.multiply(FixidityLib.newFixed(balance)).fromFixed();
    }
    require(spendingLimit >= value, "Exceeding spending limit");
    spendingLimit = spendingLimit.sub(value);
    return _transferGold(to, value);
  }

  
  function _transferGold(address payable to, uint256 value) internal returns (bool) {
    require(value <= getUnfrozenBalance(), "Exceeding unfrozen reserves");
    to.transfer(value);
    emit ReserveGoldTransferred(msg.sender, to, value);
    return true;
  }

  
  function transferExchangeGold(address payable to, uint256 value)
    external
    onlyRegisteredContract(EXCHANGE_REGISTRY_ID)
    returns (bool)
  {
    return _transferGold(to, value);
  }

  
  function getOrComputeTobinTax() external nonReentrant returns (uint256, uint256) {
    
    if (now.sub(tobinTaxCache.timestamp) > tobinTaxStalenessThreshold) {
      tobinTaxCache.numerator = uint128(computeTobinTax().unwrap());
      tobinTaxCache.timestamp = uint128(now); 
    }
    return (uint256(tobinTaxCache.numerator), FixidityLib.fixed1().unwrap());
  }

  
  function getTokens() external view returns (address[] memory) {
    return _tokens;
  }

  
  function getOtherReserveAddresses() external view returns (address[] memory) {
    return otherReserveAddresses;
  }

  
  function getAssetAllocationSymbols() external view returns (bytes32[] memory) {
    return assetAllocationSymbols;
  }

  
  function getAssetAllocationWeights() external view returns (uint256[] memory) {
    uint256[] memory weights = new uint256[](assetAllocationSymbols.length);
    for (uint256 i = 0; i < assetAllocationSymbols.length; i = i.add(1)) {
      weights[i] = assetAllocationWeights[assetAllocationSymbols[i]];
    }
    return weights;
  }

  
  function getUnfrozenBalance() public view returns (uint256) {
    uint256 balance = address(this).balance;
    uint256 frozenReserveGold = getFrozenReserveGoldBalance();
    return balance > frozenReserveGold ? balance.sub(frozenReserveGold) : 0;
  }

  
  function getReserveGoldBalance() public view returns (uint256) {
    return address(this).balance.add(getOtherReserveAddressesGoldBalance());
  }

  
  function getOtherReserveAddressesGoldBalance() public view returns (uint256) {
    uint256 reserveGoldBalance = 0;
    for (uint256 i = 0; i < otherReserveAddresses.length; i = i.add(1)) {
      reserveGoldBalance = reserveGoldBalance.add(otherReserveAddresses[i].balance);
    }
    return reserveGoldBalance;
  }

  
  function getUnfrozenReserveGoldBalance() public view returns (uint256) {
    return getUnfrozenBalance().add(getOtherReserveAddressesGoldBalance());
  }

  
  function getFrozenReserveGoldBalance() public view returns (uint256) {
    uint256 currentDay = now / 1 days;
    uint256 frozenDays = currentDay.sub(frozenReserveGoldStartDay);
    if (frozenDays >= frozenReserveGoldDays) return 0;
    return
      frozenReserveGoldStartBalance.sub(
        frozenReserveGoldStartBalance.mul(frozenDays).div(frozenReserveGoldDays)
      );
  }

  
  function getReserveRatio() public view returns (uint256) {
    address sortedOraclesAddress = registry.getAddressForOrDie(SORTED_ORACLES_REGISTRY_ID);
    ISortedOracles sortedOracles = ISortedOracles(sortedOraclesAddress);
    uint256 reserveGoldBalance = getUnfrozenReserveGoldBalance();
    uint256 stableTokensValueInGold = 0;
    FixidityLib.Fraction memory cgldWeight = FixidityLib.wrap(assetAllocationWeights["cGLD"]);

    for (uint256 i = 0; i < _tokens.length; i = i.add(1)) {
      uint256 stableAmount;
      uint256 goldAmount;
      (stableAmount, goldAmount) = sortedOracles.medianRate(_tokens[i]);
      uint256 stableTokenSupply = IERC20(_tokens[i]).totalSupply();
      uint256 aStableTokenValueInGold = stableTokenSupply.mul(goldAmount).div(stableAmount);
      stableTokensValueInGold = stableTokensValueInGold.add(aStableTokenValueInGold);
    }
    return
      FixidityLib
        .newFixed(reserveGoldBalance)
        .divide(cgldWeight)
        .divide(FixidityLib.newFixed(stableTokensValueInGold))
        .unwrap();
  }

  

  
  function computeTobinTax() private view returns (FixidityLib.Fraction memory) {
    FixidityLib.Fraction memory ratio = FixidityLib.wrap(getReserveRatio());
    if (ratio.gte(FixidityLib.wrap(tobinTaxReserveRatio))) {
      return FixidityLib.wrap(0);
    } else {
      return FixidityLib.wrap(tobinTax);
    }
  }
}