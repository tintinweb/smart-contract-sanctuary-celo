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

contract CalledByVm {
  modifier onlyVm() {
    require(msg.sender == address(0), "Only VM can call");
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

contract Initializable {
  bool public initialized;

  modifier initializer() {
    require(!initialized, "contract already initialized");
    initialized = true;
    _;
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

contract EpochRewards is
  Ownable,
  Initializable,
  UsingPrecompiles,
  UsingRegistry,
  Freezable,
  CalledByVm
{
  using FixidityLib for FixidityLib.Fraction;
  using SafeMath for uint256;

  uint256 constant GENESIS_GOLD_SUPPLY = 600000000 ether; 
  uint256 constant GOLD_SUPPLY_CAP = 1000000000 ether; 
  uint256 constant YEARS_LINEAR = 15;
  uint256 constant SECONDS_LINEAR = YEARS_LINEAR * 365 * 1 days;

  
  
  struct RewardsMultiplierAdjustmentFactors {
    FixidityLib.Fraction underspend;
    FixidityLib.Fraction overspend;
  }

  
  
  
  
  
  
  struct RewardsMultiplierParameters {
    RewardsMultiplierAdjustmentFactors adjustmentFactors;
    
    FixidityLib.Fraction max;
  }

  
  struct TargetVotingYieldParameters {
    
    FixidityLib.Fraction target;
    
    
    FixidityLib.Fraction adjustmentFactor;
    
    FixidityLib.Fraction max;
  }

  uint256 public startTime = 0;
  RewardsMultiplierParameters private rewardsMultiplierParams;
  TargetVotingYieldParameters private targetVotingYieldParams;
  FixidityLib.Fraction private targetVotingGoldFraction;
  FixidityLib.Fraction private communityRewardFraction;
  FixidityLib.Fraction private carbonOffsettingFraction;
  address public carbonOffsettingPartner;
  uint256 public targetValidatorEpochPayment;

  event TargetVotingGoldFractionSet(uint256 fraction);
  event CommunityRewardFractionSet(uint256 fraction);
  event CarbonOffsettingFundSet(address indexed partner, uint256 fraction);
  event TargetValidatorEpochPaymentSet(uint256 payment);
  event TargetVotingYieldParametersSet(uint256 max, uint256 adjustmentFactor);
  event TargetVotingYieldSet(uint256 target);
  event RewardsMultiplierParametersSet(
    uint256 max,
    uint256 underspendAdjustmentFactor,
    uint256 overspendAdjustmentFactor
  );

  event TargetVotingYieldUpdated(uint256 fraction);

  
  function initialize(
    address registryAddress,
    uint256 targetVotingYieldInitial,
    uint256 targetVotingYieldMax,
    uint256 targetVotingYieldAdjustmentFactor,
    uint256 rewardsMultiplierMax,
    uint256 rewardsMultiplierUnderspendAdjustmentFactor,
    uint256 rewardsMultiplierOverspendAdjustmentFactor,
    uint256 _targetVotingGoldFraction,
    uint256 _targetValidatorEpochPayment,
    uint256 _communityRewardFraction,
    address _carbonOffsettingPartner,
    uint256 _carbonOffsettingFraction
  ) external initializer {
    _transferOwnership(msg.sender);
    setRegistry(registryAddress);
    setTargetVotingYieldParameters(targetVotingYieldMax, targetVotingYieldAdjustmentFactor);
    setRewardsMultiplierParameters(
      rewardsMultiplierMax,
      rewardsMultiplierUnderspendAdjustmentFactor,
      rewardsMultiplierOverspendAdjustmentFactor
    );
    setTargetVotingGoldFraction(_targetVotingGoldFraction);
    setTargetValidatorEpochPayment(_targetValidatorEpochPayment);
    setCommunityRewardFraction(_communityRewardFraction);
    setCarbonOffsettingFund(_carbonOffsettingPartner, _carbonOffsettingFraction);
    setTargetVotingYield(targetVotingYieldInitial);
    startTime = now;
  }

  
  function getTargetVotingYieldParameters() external view returns (uint256, uint256, uint256) {
    TargetVotingYieldParameters storage params = targetVotingYieldParams;
    return (params.target.unwrap(), params.max.unwrap(), params.adjustmentFactor.unwrap());
  }

  
  function getRewardsMultiplierParameters() external view returns (uint256, uint256, uint256) {
    RewardsMultiplierParameters storage params = rewardsMultiplierParams;
    return (
      params.max.unwrap(),
      params.adjustmentFactors.underspend.unwrap(),
      params.adjustmentFactors.overspend.unwrap()
    );
  }

  
  function setCommunityRewardFraction(uint256 value) public onlyOwner returns (bool) {
    require(value != communityRewardFraction.unwrap() && value < FixidityLib.fixed1().unwrap());
    communityRewardFraction = FixidityLib.wrap(value);
    emit CommunityRewardFractionSet(value);
    return true;
  }

  
  function getCommunityRewardFraction() external view returns (uint256) {
    return communityRewardFraction.unwrap();
  }

  
  function setCarbonOffsettingFund(address partner, uint256 value) public onlyOwner returns (bool) {
    require(partner != carbonOffsettingPartner || value != carbonOffsettingFraction.unwrap());
    require(value < FixidityLib.fixed1().unwrap());
    carbonOffsettingPartner = partner;
    carbonOffsettingFraction = FixidityLib.wrap(value);
    emit CarbonOffsettingFundSet(partner, value);
    return true;
  }

  
  function getCarbonOffsettingFraction() external view returns (uint256) {
    return carbonOffsettingFraction.unwrap();
  }

  
  function setTargetVotingGoldFraction(uint256 value) public onlyOwner returns (bool) {
    require(value != targetVotingGoldFraction.unwrap(), "Target voting gold fraction unchanged");
    require(
      value < FixidityLib.fixed1().unwrap(),
      "Target voting gold fraction cannot be larger than 1"
    );
    targetVotingGoldFraction = FixidityLib.wrap(value);
    emit TargetVotingGoldFractionSet(value);
    return true;
  }

  
  function getTargetVotingGoldFraction() external view returns (uint256) {
    return targetVotingGoldFraction.unwrap();
  }

  
  function setTargetValidatorEpochPayment(uint256 value) public onlyOwner returns (bool) {
    require(value != targetValidatorEpochPayment, "Target validator epoch payment unchanged");
    targetValidatorEpochPayment = value;
    emit TargetValidatorEpochPaymentSet(value);
    return true;
  }

  
  function setRewardsMultiplierParameters(
    uint256 max,
    uint256 underspendAdjustmentFactor,
    uint256 overspendAdjustmentFactor
  ) public onlyOwner returns (bool) {
    require(
      max != rewardsMultiplierParams.max.unwrap() ||
        overspendAdjustmentFactor != rewardsMultiplierParams.adjustmentFactors.overspend.unwrap() ||
        underspendAdjustmentFactor != rewardsMultiplierParams.adjustmentFactors.underspend.unwrap(),
      "Bad rewards multiplier parameters"
    );
    rewardsMultiplierParams = RewardsMultiplierParameters(
      RewardsMultiplierAdjustmentFactors(
        FixidityLib.wrap(underspendAdjustmentFactor),
        FixidityLib.wrap(overspendAdjustmentFactor)
      ),
      FixidityLib.wrap(max)
    );
    emit RewardsMultiplierParametersSet(max, underspendAdjustmentFactor, overspendAdjustmentFactor);
    return true;
  }

  
  function setTargetVotingYieldParameters(uint256 max, uint256 adjustmentFactor)
    public
    onlyOwner
    returns (bool)
  {
    require(
      max != targetVotingYieldParams.max.unwrap() ||
        adjustmentFactor != targetVotingYieldParams.adjustmentFactor.unwrap(),
      "Bad target voting yield parameters"
    );
    targetVotingYieldParams.max = FixidityLib.wrap(max);
    targetVotingYieldParams.adjustmentFactor = FixidityLib.wrap(adjustmentFactor);
    require(
      targetVotingYieldParams.max.lt(FixidityLib.fixed1()),
      "Max target voting yield must be lower than 100%"
    );
    emit TargetVotingYieldParametersSet(max, adjustmentFactor);
    return true;
  }

  
  function setTargetVotingYield(uint256 targetVotingYield) public onlyOwner returns (bool) {
    FixidityLib.Fraction memory target = FixidityLib.wrap(targetVotingYield);
    require(
      target.lte(targetVotingYieldParams.max),
      "Target voting yield must be less than or equal to max"
    );
    targetVotingYieldParams.target = target;
    emit TargetVotingYieldSet(targetVotingYield);
    return true;
  }

  
  function getTargetGoldTotalSupply() public view returns (uint256) {
    uint256 timeSinceInitialization = now.sub(startTime);
    if (timeSinceInitialization < SECONDS_LINEAR) {
      
      uint256 linearRewards = GOLD_SUPPLY_CAP.sub(GENESIS_GOLD_SUPPLY).div(2);
      uint256 targetRewards = linearRewards.mul(timeSinceInitialization).div(SECONDS_LINEAR);
      return targetRewards.add(GENESIS_GOLD_SUPPLY);
    } else {
      
      require(false, "Implement block reward calculation for years 15-30");
      return 0;
    }
  }

  
  function _getRewardsMultiplier(uint256 targetGoldSupplyIncrease)
    internal
    view
    returns (FixidityLib.Fraction memory)
  {
    uint256 targetSupply = getTargetGoldTotalSupply();
    uint256 totalSupply = getGoldToken().totalSupply();
    uint256 remainingSupply = GOLD_SUPPLY_CAP.sub(totalSupply.add(targetGoldSupplyIncrease));
    uint256 targetRemainingSupply = GOLD_SUPPLY_CAP.sub(targetSupply);
    FixidityLib.Fraction memory remainingToTargetRatio = FixidityLib
      .newFixed(remainingSupply)
      .divide(FixidityLib.newFixed(targetRemainingSupply));
    if (remainingToTargetRatio.gt(FixidityLib.fixed1())) {
      FixidityLib.Fraction memory delta = remainingToTargetRatio
        .subtract(FixidityLib.fixed1())
        .multiply(rewardsMultiplierParams.adjustmentFactors.underspend);
      FixidityLib.Fraction memory multiplier = FixidityLib.fixed1().add(delta);
      if (multiplier.lt(rewardsMultiplierParams.max)) {
        return multiplier;
      } else {
        return rewardsMultiplierParams.max;
      }
    } else if (remainingToTargetRatio.lt(FixidityLib.fixed1())) {
      FixidityLib.Fraction memory delta = FixidityLib
        .fixed1()
        .subtract(remainingToTargetRatio)
        .multiply(rewardsMultiplierParams.adjustmentFactors.overspend);
      if (delta.lt(FixidityLib.fixed1())) {
        return FixidityLib.fixed1().subtract(delta);
      } else {
        return FixidityLib.wrap(0);
      }
    } else {
      return FixidityLib.fixed1();
    }
  }

  
  function getTargetVoterRewards() public view returns (uint256) {
    return
      FixidityLib
        .newFixed(getElection().getActiveVotes())
        .multiply(targetVotingYieldParams.target)
        .fromFixed();
  }

  
  function getTargetTotalEpochPaymentsInGold() public view returns (uint256) {
    address stableTokenAddress = registry.getAddressForOrDie(STABLE_TOKEN_REGISTRY_ID);
    (uint256 numerator, uint256 denominator) = getSortedOracles().medianRate(stableTokenAddress);
    return
      numberValidatorsInCurrentSet().mul(targetValidatorEpochPayment).mul(denominator).div(
        numerator
      );
  }

  
  function _getTargetGoldSupplyIncrease() internal view returns (uint256) {
    uint256 targetEpochRewards = getTargetVoterRewards();
    uint256 targetTotalEpochPaymentsInGold = getTargetTotalEpochPaymentsInGold();
    uint256 targetGoldSupplyIncrease = targetEpochRewards.add(targetTotalEpochPaymentsInGold);
    
    targetGoldSupplyIncrease = FixidityLib
      .newFixed(targetGoldSupplyIncrease)
      .divide(
      FixidityLib.newFixed(1).subtract(communityRewardFraction).subtract(carbonOffsettingFraction)
    )
      .fromFixed();
    return targetGoldSupplyIncrease;
  }

  
  function getRewardsMultiplier() external view returns (uint256) {
    return _getRewardsMultiplier(_getTargetGoldSupplyIncrease()).unwrap();
  }

  
  function getVotingGoldFraction() public view returns (uint256) {
    uint256 liquidGold = getGoldToken().totalSupply().sub(getReserve().getReserveGoldBalance());
    uint256 votingGold = getElection().getTotalVotes();
    return FixidityLib.newFixed(votingGold).divide(FixidityLib.newFixed(liquidGold)).unwrap();
  }

  
  function _updateTargetVotingYield() internal onlyWhenNotFrozen {
    FixidityLib.Fraction memory votingGoldFraction = FixidityLib.wrap(getVotingGoldFraction());
    if (votingGoldFraction.gt(targetVotingGoldFraction)) {
      FixidityLib.Fraction memory votingGoldFractionDelta = votingGoldFraction.subtract(
        targetVotingGoldFraction
      );
      FixidityLib.Fraction memory targetVotingYieldDelta = votingGoldFractionDelta.multiply(
        targetVotingYieldParams.adjustmentFactor
      );
      if (targetVotingYieldDelta.gte(targetVotingYieldParams.target)) {
        targetVotingYieldParams.target = FixidityLib.newFixed(0);
      } else {
        targetVotingYieldParams.target = targetVotingYieldParams.target.subtract(
          targetVotingYieldDelta
        );
      }
    } else if (votingGoldFraction.lt(targetVotingGoldFraction)) {
      FixidityLib.Fraction memory votingGoldFractionDelta = targetVotingGoldFraction.subtract(
        votingGoldFraction
      );
      FixidityLib.Fraction memory targetVotingYieldDelta = votingGoldFractionDelta.multiply(
        targetVotingYieldParams.adjustmentFactor
      );
      targetVotingYieldParams.target = targetVotingYieldParams.target.add(targetVotingYieldDelta);
      if (targetVotingYieldParams.target.gt(targetVotingYieldParams.max)) {
        targetVotingYieldParams.target = targetVotingYieldParams.max;
      }
    }
    emit TargetVotingYieldUpdated(targetVotingYieldParams.target.unwrap());
  }

  
  function updateTargetVotingYield() external onlyVm onlyWhenNotFrozen {
    _updateTargetVotingYield();
  }

  
  function isReserveLow() external view returns (bool) {
    
    FixidityLib.Fraction memory timeSinceInitialization = FixidityLib.newFixed(now.sub(startTime));
    FixidityLib.Fraction memory m = FixidityLib.newFixed(25 * 365 * 1 days);
    FixidityLib.Fraction memory b = FixidityLib.newFixed(2);
    FixidityLib.Fraction memory criticalRatio;
    
    if (timeSinceInitialization.gte(m)) {
      criticalRatio = FixidityLib.fixed1();
    } else {
      criticalRatio = b.subtract(timeSinceInitialization.divide(m));
    }
    FixidityLib.Fraction memory ratio = FixidityLib.wrap(getReserve().getReserveRatio());
    return ratio.lte(criticalRatio);
  }

  
  function calculateTargetEpochRewards()
    external
    view
    onlyWhenNotFrozen
    returns (uint256, uint256, uint256, uint256)
  {
    uint256 targetVoterReward = getTargetVoterRewards();
    uint256 targetGoldSupplyIncrease = _getTargetGoldSupplyIncrease();
    FixidityLib.Fraction memory rewardsMultiplier = _getRewardsMultiplier(targetGoldSupplyIncrease);
    return (
      FixidityLib.newFixed(targetValidatorEpochPayment).multiply(rewardsMultiplier).fromFixed(),
      FixidityLib.newFixed(targetVoterReward).multiply(rewardsMultiplier).fromFixed(),
      FixidityLib
        .newFixed(targetGoldSupplyIncrease)
        .multiply(communityRewardFraction)
        .multiply(rewardsMultiplier)
        .fromFixed(),
      FixidityLib
        .newFixed(targetGoldSupplyIncrease)
        .multiply(carbonOffsettingFraction)
        .multiply(rewardsMultiplier)
        .fromFixed()
    );
  }
}