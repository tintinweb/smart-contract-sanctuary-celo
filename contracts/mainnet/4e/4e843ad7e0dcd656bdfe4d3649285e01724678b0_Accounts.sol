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

contract Initializable {
  bool public initialized;

  modifier initializer() {
    require(!initialized, "contract already initialized");
    initialized = true;
    _;
  }
}

library ECDSA {
    
    function recover(bytes32 hash, bytes memory signature) internal pure returns (address) {
        
        if (signature.length != 65) {
            return (address(0));
        }

        
        bytes32 r;
        bytes32 s;
        uint8 v;

        
        
        
        assembly {
            r := mload(add(signature, 0x20))
            s := mload(add(signature, 0x40))
            v := byte(0, mload(add(signature, 0x60)))
        }

        
        
        
        
        
        
        
        
        
        if (uint256(s) > 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0) {
            return address(0);
        }

        if (v != 27 && v != 28) {
            return address(0);
        }

        
        return ecrecover(hash, v, r, s);
    }

    
    function toEthSignedMessageHash(bytes32 hash) internal pure returns (bytes32) {
        
        
        return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", hash));
    }
}

library Signatures {
  
  function getSignerOfAddress(address message, uint8 v, bytes32 r, bytes32 s)
    public
    pure
    returns (address)
  {
    bytes32 hash = keccak256(abi.encodePacked(message));
    return getSignerOfMessageHash(hash, v, r, s);
  }

  
  function getSignerOfMessageHash(bytes32 messageHash, uint8 v, bytes32 r, bytes32 s)
    public
    pure
    returns (address)
  {
    bytes memory signature = new bytes(65);
    
    assembly {
      mstore(add(signature, 32), r)
      mstore(add(signature, 64), s)
      mstore8(add(signature, 96), v)
    }
    bytes32 prefixedHash = ECDSA.toEthSignedMessageHash(messageHash);
    return ECDSA.recover(prefixedHash, signature);
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

contract Accounts is IAccounts, Ownable, ReentrancyGuard, Initializable, UsingRegistry {
  using SafeMath for uint256;

  struct Signers {
    
    
    address vote;
    
    
    
    
    address validator;
    
    
    address attestation;
  }

  struct Account {
    bool exists;
    
    
    
    Signers signers;
    
    
    address walletAddress;
    
    string name;
    
    bytes dataEncryptionKey;
    
    string metadataURL;
  }

  mapping(address => Account) private accounts;
  
  mapping(address => address) public authorizedBy;

  event AttestationSignerAuthorized(address indexed account, address signer);
  event VoteSignerAuthorized(address indexed account, address signer);
  event ValidatorSignerAuthorized(address indexed account, address signer);
  event AttestationSignerRemoved(address indexed account, address oldSigner);
  event VoteSignerRemoved(address indexed account, address oldSigner);
  event ValidatorSignerRemoved(address indexed account, address oldSigner);
  event AccountDataEncryptionKeySet(address indexed account, bytes dataEncryptionKey);
  event AccountNameSet(address indexed account, string name);
  event AccountMetadataURLSet(address indexed account, string metadataURL);
  event AccountWalletAddressSet(address indexed account, address walletAddress);
  event AccountCreated(address indexed account);

  
  function initialize(address registryAddress) external initializer {
    _transferOwnership(msg.sender);
    setRegistry(registryAddress);
  }

  
  function setAccount(
    string calldata name,
    bytes calldata dataEncryptionKey,
    address walletAddress,
    uint8 v,
    bytes32 r,
    bytes32 s
  ) external {
    if (!isAccount(msg.sender)) {
      createAccount();
    }
    setName(name);
    setAccountDataEncryptionKey(dataEncryptionKey);
    setWalletAddress(walletAddress, v, r, s);
  }

  
  function createAccount() public returns (bool) {
    require(isNotAccount(msg.sender) && isNotAuthorizedSigner(msg.sender), "Account exists");
    Account storage account = accounts[msg.sender];
    account.exists = true;
    emit AccountCreated(msg.sender);
    return true;
  }

  
  function setName(string memory name) public {
    require(isAccount(msg.sender), "Unknown account");
    Account storage account = accounts[msg.sender];
    account.name = name;
    emit AccountNameSet(msg.sender, name);
  }

  
  function setWalletAddress(address walletAddress, uint8 v, bytes32 r, bytes32 s) public {
    require(isAccount(msg.sender), "Unknown account");
    if (!(walletAddress == msg.sender || walletAddress == address(0x0))) {
      address signer = Signatures.getSignerOfAddress(msg.sender, v, r, s);
      require(signer == walletAddress, "Invalid signature");
    }
    Account storage account = accounts[msg.sender];
    account.walletAddress = walletAddress;
    emit AccountWalletAddressSet(msg.sender, walletAddress);
  }

  
  function setAccountDataEncryptionKey(bytes memory dataEncryptionKey) public {
    require(dataEncryptionKey.length >= 33, "data encryption key length <= 32");
    Account storage account = accounts[msg.sender];
    account.dataEncryptionKey = dataEncryptionKey;
    emit AccountDataEncryptionKeySet(msg.sender, dataEncryptionKey);
  }

  
  function setMetadataURL(string calldata metadataURL) external {
    require(isAccount(msg.sender), "Unknown account");
    Account storage account = accounts[msg.sender];
    account.metadataURL = metadataURL;
    emit AccountMetadataURLSet(msg.sender, metadataURL);
  }

  
  function authorizeVoteSigner(address signer, uint8 v, bytes32 r, bytes32 s)
    external
    nonReentrant
  {
    Account storage account = accounts[msg.sender];
    authorize(signer, v, r, s);
    account.signers.vote = signer;
    emit VoteSignerAuthorized(msg.sender, signer);
  }

  
  function authorizeValidatorSigner(address signer, uint8 v, bytes32 r, bytes32 s)
    external
    nonReentrant
  {
    Account storage account = accounts[msg.sender];
    authorize(signer, v, r, s);
    account.signers.validator = signer;
    require(!getValidators().isValidator(msg.sender), "Cannot authorize validator signer");
    emit ValidatorSignerAuthorized(msg.sender, signer);
  }

  
  function authorizeValidatorSignerWithPublicKey(
    address signer,
    uint8 v,
    bytes32 r,
    bytes32 s,
    bytes calldata ecdsaPublicKey
  ) external nonReentrant {
    Account storage account = accounts[msg.sender];
    authorize(signer, v, r, s);
    account.signers.validator = signer;
    require(
      getValidators().updateEcdsaPublicKey(msg.sender, signer, ecdsaPublicKey),
      "Failed to update ECDSA public key"
    );
    emit ValidatorSignerAuthorized(msg.sender, signer);
  }

  
  function authorizeValidatorSignerWithKeys(
    address signer,
    uint8 v,
    bytes32 r,
    bytes32 s,
    bytes calldata ecdsaPublicKey,
    bytes calldata blsPublicKey,
    bytes calldata blsPop
  ) external nonReentrant {
    Account storage account = accounts[msg.sender];
    authorize(signer, v, r, s);
    account.signers.validator = signer;
    require(
      getValidators().updatePublicKeys(msg.sender, signer, ecdsaPublicKey, blsPublicKey, blsPop),
      "Failed to update validator keys"
    );
    emit ValidatorSignerAuthorized(msg.sender, signer);
  }

  
  function authorizeAttestationSigner(address signer, uint8 v, bytes32 r, bytes32 s) public {
    Account storage account = accounts[msg.sender];
    authorize(signer, v, r, s);
    account.signers.attestation = signer;
    emit AttestationSignerAuthorized(msg.sender, signer);
  }

  
  function removeVoteSigner() public {
    Account storage account = accounts[msg.sender];
    emit VoteSignerRemoved(msg.sender, account.signers.vote);
    account.signers.vote = address(0);
  }

  
  function removeValidatorSigner() public {
    Account storage account = accounts[msg.sender];
    emit ValidatorSignerRemoved(msg.sender, account.signers.validator);
    account.signers.validator = address(0);
  }

  
  function removeAttestationSigner() public {
    Account storage account = accounts[msg.sender];
    emit AttestationSignerRemoved(msg.sender, account.signers.attestation);
    account.signers.attestation = address(0);
  }

  
  function attestationSignerToAccount(address signer) external view returns (address) {
    address authorizingAccount = authorizedBy[signer];
    if (authorizingAccount != address(0)) {
      require(
        accounts[authorizingAccount].signers.attestation == signer,
        "not active authorized attestation signer"
      );
      return authorizingAccount;
    } else {
      require(isAccount(signer), "not an account");
      return signer;
    }
  }

  
  function validatorSignerToAccount(address signer) public view returns (address) {
    address authorizingAccount = authorizedBy[signer];
    if (authorizingAccount != address(0)) {
      require(
        accounts[authorizingAccount].signers.validator == signer,
        "not active authorized validator signer"
      );
      return authorizingAccount;
    } else {
      require(isAccount(signer), "not an account");
      return signer;
    }
  }

  
  function voteSignerToAccount(address signer) external view returns (address) {
    address authorizingAccount = authorizedBy[signer];
    if (authorizingAccount != address(0)) {
      require(
        accounts[authorizingAccount].signers.vote == signer,
        "not active authorized vote signer"
      );
      return authorizingAccount;
    } else {
      require(isAccount(signer), "not an account");
      return signer;
    }
  }

  
  function signerToAccount(address signer) external view returns (address) {
    address authorizingAccount = authorizedBy[signer];
    if (authorizingAccount != address(0)) {
      return authorizingAccount;
    } else {
      require(isAccount(signer), "Not an account");
      return signer;
    }
  }

  
  function getVoteSigner(address account) public view returns (address) {
    require(isAccount(account), "Unknown account");
    address signer = accounts[account].signers.vote;
    return signer == address(0) ? account : signer;
  }

  
  function getValidatorSigner(address account) public view returns (address) {
    require(isAccount(account), "Unknown account");
    address signer = accounts[account].signers.validator;
    return signer == address(0) ? account : signer;
  }

  
  function getAttestationSigner(address account) public view returns (address) {
    require(isAccount(account), "Unknown account");
    address signer = accounts[account].signers.attestation;
    return signer == address(0) ? account : signer;
  }

  
  function hasAuthorizedVoteSigner(address account) external view returns (bool) {
    require(isAccount(account));
    address signer = accounts[account].signers.vote;
    return signer != address(0);
  }

  
  function hasAuthorizedValidatorSigner(address account) external view returns (bool) {
    require(isAccount(account));
    address signer = accounts[account].signers.validator;
    return signer != address(0);
  }

  
  function hasAuthorizedAttestationSigner(address account) external view returns (bool) {
    require(isAccount(account));
    address signer = accounts[account].signers.attestation;
    return signer != address(0);
  }

  
  function getName(address account) external view returns (string memory) {
    return accounts[account].name;
  }

  
  function getMetadataURL(address account) external view returns (string memory) {
    return accounts[account].metadataURL;
  }

  
  function batchGetMetadataURL(address[] calldata accountsToQuery)
    external
    view
    returns (uint256[] memory, bytes memory)
  {
    uint256 totalSize = 0;
    uint256[] memory sizes = new uint256[](accountsToQuery.length);
    for (uint256 i = 0; i < accountsToQuery.length; i = i.add(1)) {
      sizes[i] = bytes(accounts[accountsToQuery[i]].metadataURL).length;
      totalSize = totalSize.add(sizes[i]);
    }

    bytes memory data = new bytes(totalSize);
    uint256 pointer = 0;
    for (uint256 i = 0; i < accountsToQuery.length; i = i.add(1)) {
      for (uint256 j = 0; j < sizes[i]; j = j.add(1)) {
        data[pointer] = bytes(accounts[accountsToQuery[i]].metadataURL)[j];
        pointer = pointer.add(1);
      }
    }
    return (sizes, data);
  }

  
  function getDataEncryptionKey(address account) external view returns (bytes memory) {
    return accounts[account].dataEncryptionKey;
  }

  
  function getWalletAddress(address account) external view returns (address) {
    return accounts[account].walletAddress;
  }

  
  function isAccount(address account) public view returns (bool) {
    return (accounts[account].exists);
  }

  
  function isNotAccount(address account) internal view returns (bool) {
    return (!accounts[account].exists);
  }

  
  function isAuthorizedSigner(address signer) external view returns (bool) {
    return (authorizedBy[signer] != address(0));
  }

  
  function isNotAuthorizedSigner(address signer) internal view returns (bool) {
    return (authorizedBy[signer] == address(0));
  }

  
  function authorize(address authorized, uint8 v, bytes32 r, bytes32 s) private {
    require(isAccount(msg.sender), "Unknown account");
    require(
      isNotAccount(authorized) && isNotAuthorizedSigner(authorized),
      "Cannot re-authorize address or locked gold account."
    );

    address signer = Signatures.getSignerOfAddress(msg.sender, v, r, s);
    require(signer == authorized, "Invalid signature");

    authorizedBy[authorized] = msg.sender;
  }
}