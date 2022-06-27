pragma solidity ^0.5.3;


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

contract SlasherUtil is Ownable, Initializable, UsingRegistry, UsingPrecompiles {
  using SafeMath for uint256;

  struct SlashingIncentives {
    
    uint256 penalty;
    
    uint256 reward;
  }

  SlashingIncentives public slashingIncentives;

  event SlashingIncentivesSet(uint256 penalty, uint256 reward);

  
  function setSlashingIncentives(uint256 penalty, uint256 reward) public onlyOwner {
    require(penalty > reward, "Penalty has to be larger than reward");
    slashingIncentives.penalty = penalty;
    slashingIncentives.reward = reward;
    emit SlashingIncentivesSet(penalty, reward);
  }

  
  function groupMembershipAtBlock(
    address validator,
    uint256 blockNumber,
    uint256 groupMembershipHistoryIndex
  ) public view returns (address) {
    uint256 epoch = getEpochNumberOfBlock(blockNumber);
    require(epoch != 0, "Cannot slash on epoch 0");
    
    return
      getValidators().groupMembershipInEpoch(validator, epoch.sub(1), groupMembershipHistoryIndex);
  }

  function performSlashing(
    address validator,
    address recipient,
    uint256 startBlock,
    uint256 groupMembershipHistoryIndex,
    address[] memory validatorElectionLessers,
    address[] memory validatorElectionGreaters,
    uint256[] memory validatorElectionIndices,
    address[] memory groupElectionLessers,
    address[] memory groupElectionGreaters,
    uint256[] memory groupElectionIndices
  ) internal {
    ILockedGold lockedGold = getLockedGold();
    lockedGold.slash(
      validator,
      slashingIncentives.penalty,
      recipient,
      slashingIncentives.reward,
      validatorElectionLessers,
      validatorElectionGreaters,
      validatorElectionIndices
    );
    address group = groupMembershipAtBlock(validator, startBlock, groupMembershipHistoryIndex);
    assert(group != address(0));
    lockedGold.slash(
      group,
      slashingIncentives.penalty,
      recipient,
      slashingIncentives.reward,
      groupElectionLessers,
      groupElectionGreaters,
      groupElectionIndices
    );
    IValidators validators = getValidators();
    validators.forceDeaffiliateIfValidator(validator);
    validators.halveSlashingMultiplier(group);
  }

}

contract DowntimeSlasher is SlasherUtil {
  using SafeMath for uint256;

  
  mapping(address => mapping(uint256 => uint256)) lastSlashedBlock;
  uint256 public slashableDowntime;

  event SlashableDowntimeSet(uint256 interval);
  event DowntimeSlashPerformed(address indexed validator, uint256 indexed startBlock);

  
  function initialize(
    address registryAddress,
    uint256 _penalty,
    uint256 _reward,
    uint256 _slashableDowntime
  ) external initializer {
    _transferOwnership(msg.sender);
    setRegistry(registryAddress);
    setSlashingIncentives(_penalty, _reward);
    setSlashableDowntime(_slashableDowntime);
  }

  
  function setSlashableDowntime(uint256 interval) public onlyOwner {
    require(interval != 0, "Slashable downtime cannot be zero");
    require(interval < getEpochSize(), "Slashable downtime must be smaller than epoch size");
    slashableDowntime = interval;
    emit SlashableDowntimeSet(interval);
  }

  
  function isDown(uint256 startBlock, uint256 startSignerIndex, uint256 endSignerIndex)
    public
    view
    returns (bool)
  {
    uint256 endBlock = getEndBlock(startBlock);
    require(endBlock < block.number.sub(1), "end block must be smaller than current block");
    require(
      startSignerIndex < numberValidatorsInSet(startBlock),
      "Bad validator index at start block"
    );
    require(endSignerIndex < numberValidatorsInSet(endBlock), "Bad validator index at end block");
    address startSigner = validatorSignerAddressFromSet(startSignerIndex, startBlock);
    address endSigner = validatorSignerAddressFromSet(endSignerIndex, endBlock);
    IAccounts accounts = getAccounts();
    require(
      accounts.signerToAccount(startSigner) == accounts.signerToAccount(endSigner),
      "Signers do not match"
    );
    uint256 sz = getEpochSize();
    uint256 startEpoch = epochNumberOfBlock(startBlock, sz);
    for (uint256 n = startBlock; n <= endBlock; n = n.add(1)) {
      uint256 signerIndex = epochNumberOfBlock(n, sz) == startEpoch
        ? startSignerIndex
        : endSignerIndex;
      
      
      if (uint256(getParentSealBitmap(n.add(1))) & (1 << signerIndex) != 0) return false;
    }
    return true;
  }

  
  function getEndBlock(uint256 startBlock) internal view returns (uint256) {
    return startBlock.add(slashableDowntime).sub(1);
  }

  function checkIfAlreadySlashed(address validator, uint256 startBlock) internal {
    uint256 endBlock = getEndBlock(startBlock);
    uint256 startEpoch = getEpochNumberOfBlock(startBlock);
    uint256 endEpoch = getEpochNumberOfBlock(endBlock);
    require(lastSlashedBlock[validator][startEpoch] < startBlock, "Already slashed");
    require(lastSlashedBlock[validator][endEpoch] < startBlock, "Already slashed");
    lastSlashedBlock[validator][startEpoch] = endBlock;
    lastSlashedBlock[validator][endEpoch] = endBlock;
  }

  
  function slash(
    uint256 startBlock,
    uint256 startSignerIndex,
    uint256 endSignerIndex,
    uint256 groupMembershipHistoryIndex,
    address[] memory validatorElectionLessers,
    address[] memory validatorElectionGreaters,
    uint256[] memory validatorElectionIndices,
    address[] memory groupElectionLessers,
    address[] memory groupElectionGreaters,
    uint256[] memory groupElectionIndices
  ) public {
    address validator = getAccounts().signerToAccount(
      validatorSignerAddressFromSet(startSignerIndex, startBlock)
    );
    checkIfAlreadySlashed(validator, startBlock);
    require(isDown(startBlock, startSignerIndex, endSignerIndex), "Not down");
    performSlashing(
      validator,
      msg.sender,
      startBlock,
      groupMembershipHistoryIndex,
      validatorElectionLessers,
      validatorElectionGreaters,
      validatorElectionIndices,
      groupElectionLessers,
      groupElectionGreaters,
      groupElectionIndices
    );
    emit DowntimeSlashPerformed(validator, startBlock);
  }
}