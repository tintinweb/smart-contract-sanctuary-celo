pragma solidity ^0.5.13;

import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "openzeppelin-solidity/contracts/ownership/Ownable.sol";

import "./interfaces/IAccounts.sol";

import "../common/Initializable.sol";
import "../common/interfaces/ICeloVersionedContract.sol";
import "../common/Signatures.sol";
import "../common/UsingRegistry.sol";
import "../common/libraries/ReentrancyGuard.sol";

contract Accounts is
  IAccounts,
  ICeloVersionedContract,
  Ownable,
  ReentrancyGuard,
  Initializable,
  UsingRegistry
{
  using SafeMath for uint256;

  struct Signers {
    // The address that is authorized to vote in governance and validator elections on behalf of the
    // account. The account can vote as well, whether or not a vote signing key has been specified.
    address vote;
    // The address that is authorized to manage a validator or validator group and sign consensus
    // messages on behalf of the account. The account can manage the validator, whether or not a
    // validator signing key has been specified. However, if a validator signing key has been
    // specified, only that key may actually participate in consensus.
    address validator;
    // The address of the key with which this account wants to sign attestations on the Attestations
    // contract
    address attestation;
  }

  struct SignerAuthorization {
    bool started;
    bool completed;
  }

  struct Account {
    bool exists;
    // [Deprecated] Each account may authorize signing keys to use for voting,
    // validating or attestation. These keys may not be keys of other accounts,
    // and may not be authorized by any other account for any purpose.
    Signers signers;
    // The address at which the account expects to receive transfers. If it's empty/0x0, the
    // account indicates that an address exchange should be initiated with the dataEncryptionKey
    address walletAddress;
    // An optional human readable identifier for the account
    string name;
    // The ECDSA public key used to encrypt and decrypt data for this account
    bytes dataEncryptionKey;
    // The URL under which an account adds metadata and claims
    string metadataURL;
  }

  mapping(address => Account) internal accounts;
  // Maps authorized signers to the account that provided the authorization.
  mapping(address => address) public authorizedBy;
  // Default signers by account (replaces the legacy Signers struct on Account)
  mapping(address => mapping(bytes32 => address)) defaultSigners;
  // All signers and their roles for a given account
  // solhint-disable-next-line max-line-length
  mapping(address => mapping(bytes32 => mapping(address => SignerAuthorization))) signerAuthorizations;

  bytes32 public constant EIP712_AUTHORIZE_SIGNER_TYPEHASH = keccak256(
    "AuthorizeSigner(address account,address signer,bytes32 role)"
  );
  bytes32 public eip712DomainSeparator;

  // A per-account list of CIP8 storage roots, bypassing CIP3.
  mapping(address => bytes[]) public offchainStorageRoots;

  bytes32 constant ValidatorSigner = keccak256(abi.encodePacked("celo.org/core/validator"));
  bytes32 constant AttestationSigner = keccak256(abi.encodePacked("celo.org/core/attestation"));
  bytes32 constant VoteSigner = keccak256(abi.encodePacked("celo.org/core/vote"));

  event AttestationSignerAuthorized(address indexed account, address signer);
  event VoteSignerAuthorized(address indexed account, address signer);
  event ValidatorSignerAuthorized(address indexed account, address signer);
  event SignerAuthorized(address indexed account, address signer, bytes32 indexed role);
  event SignerAuthorizationStarted(address indexed account, address signer, bytes32 indexed role);
  event SignerAuthorizationCompleted(address indexed account, address signer, bytes32 indexed role);
  event AttestationSignerRemoved(address indexed account, address oldSigner);
  event VoteSignerRemoved(address indexed account, address oldSigner);
  event ValidatorSignerRemoved(address indexed account, address oldSigner);
  event IndexedSignerSet(address indexed account, address signer, bytes32 role);
  event IndexedSignerRemoved(address indexed account, address oldSigner, bytes32 role);
  event DefaultSignerSet(address indexed account, address signer, bytes32 role);
  event DefaultSignerRemoved(address indexed account, address oldSigner, bytes32 role);
  event LegacySignerSet(address indexed account, address signer, bytes32 role);
  event LegacySignerRemoved(address indexed account, address oldSigner, bytes32 role);
  event SignerRemoved(address indexed account, address oldSigner, bytes32 indexed role);
  event AccountDataEncryptionKeySet(address indexed account, bytes dataEncryptionKey);
  event AccountNameSet(address indexed account, string name);
  event AccountMetadataURLSet(address indexed account, string metadataURL);
  event AccountWalletAddressSet(address indexed account, address walletAddress);
  event AccountCreated(address indexed account);
  event OffchainStorageRootAdded(address indexed account, bytes url);
  event OffchainStorageRootRemoved(address indexed account, bytes url, uint256 index);

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
    return (1, 1, 3, 0);
  }

  /**
   * @notice Used in place of the constructor to allow the contract to be upgradable via proxy.
   * @param registryAddress The address of the registry core smart contract.
   */
  function initialize(address registryAddress) external initializer {
    _transferOwnership(msg.sender);
    setRegistry(registryAddress);
    setEip712DomainSeparator();
  }

  /**
   * @notice Sets the EIP712 domain separator for the Celo Accounts abstraction.
   */
  function setEip712DomainSeparator() public {
    uint256 chainId;
    assembly {
      chainId := chainid
    }

    eip712DomainSeparator = keccak256(
      abi.encode(
        keccak256(
          "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
        ),
        keccak256(bytes("Celo Core Contracts")),
        keccak256("1.0"),
        chainId,
        address(this)
      )
    );
  }

  /**
   * @notice Convenience Setter for the dataEncryptionKey and wallet address for an account
   * @param name A string to set as the name of the account
   * @param dataEncryptionKey secp256k1 public key for data encryption. Preferably compressed.
   * @param walletAddress The wallet address to set for the account
   * @param v The recovery id of the incoming ECDSA signature.
   * @param r Output value r of the ECDSA signature.
   * @param s Output value s of the ECDSA signature.
   * @dev v, r, s constitute `signer`'s signature on `msg.sender` (unless the wallet address
   *      is 0x0 or msg.sender).
   */
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

  /**
   * @notice Creates an account.
   * @return True if account creation succeeded.
   */
  function createAccount() public returns (bool) {
    require(isNotAccount(msg.sender) && isNotAuthorizedSigner(msg.sender), "Account exists");
    Account storage account = accounts[msg.sender];
    account.exists = true;
    emit AccountCreated(msg.sender);
    return true;
  }

  /**
   * @notice Setter for the name of an account.
   * @param name The name to set.
   */
  function setName(string memory name) public {
    require(isAccount(msg.sender), "Unknown account");
    Account storage account = accounts[msg.sender];
    account.name = name;
    emit AccountNameSet(msg.sender, name);
  }

  /**
   * @notice Setter for the wallet address for an account
   * @param walletAddress The wallet address to set for the account
   * @param v The recovery id of the incoming ECDSA signature.
   * @param r Output value r of the ECDSA signature.
   * @param s Output value s of the ECDSA signature.
   * @dev Wallet address can be zero. This means that the owner of the wallet
   *  does not want to be paid directly without interaction, and instead wants users to
   * contact them, using the data encryption key, and arrange a payment.
   * @dev v, r, s constitute `signer`'s signature on `msg.sender` (unless the wallet address
   *      is 0x0 or msg.sender).
   */
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

  /**
   * @notice Setter for the data encryption key and version.
   * @param dataEncryptionKey secp256k1 public key for data encryption. Preferably compressed.
   */
  function setAccountDataEncryptionKey(bytes memory dataEncryptionKey) public {
    require(dataEncryptionKey.length >= 33, "data encryption key length <= 32");
    Account storage account = accounts[msg.sender];
    account.dataEncryptionKey = dataEncryptionKey;
    emit AccountDataEncryptionKeySet(msg.sender, dataEncryptionKey);
  }

  /**
   * @notice Setter for the metadata of an account.
   * @param metadataURL The URL to access the metadata.
   */
  function setMetadataURL(string calldata metadataURL) external {
    require(isAccount(msg.sender), "Unknown account");
    Account storage account = accounts[msg.sender];
    account.metadataURL = metadataURL;
    emit AccountMetadataURLSet(msg.sender, metadataURL);
  }

  /**
   * @notice Adds a new CIP8 storage root.
   * @param url The URL pointing to the offchain storage root.
   */
  function addStorageRoot(bytes calldata url) external {
    require(isAccount(msg.sender), "Unknown account");
    offchainStorageRoots[msg.sender].push(url);
    emit OffchainStorageRootAdded(msg.sender, url);
  }

  /**
   * @notice Removes a CIP8 storage root.
   * @param index The index of the storage root to be removed in the account's
   * list of storage roots.
   * @dev The order of storage roots may change after this operation (the last
   * storage root will be moved to `index`), be aware of this if removing
   * multiple storage roots at a time.
   */
  function removeStorageRoot(uint256 index) external {
    require(isAccount(msg.sender), "Unknown account");
    require(index < offchainStorageRoots[msg.sender].length, "Invalid storage root index");
    uint256 lastIndex = offchainStorageRoots[msg.sender].length - 1;
    bytes memory url = offchainStorageRoots[msg.sender][index];
    offchainStorageRoots[msg.sender][index] = offchainStorageRoots[msg.sender][lastIndex];
    offchainStorageRoots[msg.sender].length--;
    emit OffchainStorageRootRemoved(msg.sender, url, index);
  }

  /**
   * @notice Returns the full list of offchain storage roots for an account.
   * @param account The account whose storage roots to return.
   * @return List of storage root URLs.
   */
  function getOffchainStorageRoots(address account)
    external
    view
    returns (bytes memory, uint256[] memory)
  {
    require(isAccount(account), "Unknown account");
    uint256 numberRoots = offchainStorageRoots[account].length;
    uint256 totalLength = 0;
    for (uint256 i = 0; i < numberRoots; i++) {
      totalLength = totalLength.add(offchainStorageRoots[account][i].length);
    }

    bytes memory concatenated = new bytes(totalLength);
    uint256 lastIndex = 0;
    uint256[] memory lengths = new uint256[](numberRoots);
    for (uint256 i = 0; i < numberRoots; i++) {
      bytes storage root = offchainStorageRoots[account][i];
      lengths[i] = root.length;
      for (uint256 j = 0; j < lengths[i]; j++) {
        concatenated[lastIndex] = root[j];
        lastIndex++;
      }
    }

    return (concatenated, lengths);
  }

  /**
   * @notice Set the indexed signer for a specific role
   * @param signer the address to set as default
   * @param role the role to register a default signer for
   */
  function setIndexedSigner(address signer, bytes32 role) public {
    require(isAccount(msg.sender), "Not an account");
    require(isNotAccount(signer), "Cannot authorize account as signer");
    require(
      isNotAuthorizedSignerForAnotherAccount(msg.sender, signer),
      "Not a signer for this account"
    );
    require(isSigner(msg.sender, signer, role), "Must authorize signer before setting as default");

    Account storage account = accounts[msg.sender];
    if (isLegacyRole(role)) {
      if (role == VoteSigner) {
        account.signers.vote = signer;
      } else if (role == AttestationSigner) {
        account.signers.attestation = signer;
      } else if (role == ValidatorSigner) {
        account.signers.validator = signer;
      }
      emit LegacySignerSet(msg.sender, signer, role);
    } else {
      defaultSigners[msg.sender][role] = signer;
      emit DefaultSignerSet(msg.sender, signer, role);
    }

    emit IndexedSignerSet(msg.sender, signer, role);
  }

  /**
   * @notice Authorizes an address to act as a signer, for `role`, on behalf of the account.
   * @param signer The address of the signing key to authorize.
   * @param role The role to authorize signing for.
   * @param v The recovery id of the incoming ECDSA signature.
   * @param r Output value r of the ECDSA signature.
   * @param s Output value s of the ECDSA signature.
   * @dev v, r, s constitute `signer`'s EIP712 signature over `role`, `msg.sender`  
   *      and `signer`.
   */
  function authorizeSignerWithSignature(address signer, bytes32 role, uint8 v, bytes32 r, bytes32 s)
    public
  {
    authorizeAddressWithRole(signer, role, v, r, s);
    signerAuthorizations[msg.sender][role][signer] = SignerAuthorization({
      started: true,
      completed: true
    });

    emit SignerAuthorized(msg.sender, signer, role);
  }

  function legacyAuthorizeSignerWithSignature(
    address signer,
    bytes32 role,
    uint8 v,
    bytes32 r,
    bytes32 s
  ) private {
    authorizeAddress(signer, v, r, s);
    signerAuthorizations[msg.sender][role][signer] = SignerAuthorization({
      started: true,
      completed: true
    });

    emit SignerAuthorized(msg.sender, signer, role);
  }

  /**
   * @notice Authorizes an address to sign votes on behalf of the account.
   * @param signer The address of the signing key to authorize.
   * @param v The recovery id of the incoming ECDSA signature.
   * @param r Output value r of the ECDSA signature.
   * @param s Output value s of the ECDSA signature.
   * @dev v, r, s constitute `signer`'s signature on `msg.sender`.
   */
  function authorizeVoteSigner(address signer, uint8 v, bytes32 r, bytes32 s)
    external
    nonReentrant
  {
    legacyAuthorizeSignerWithSignature(signer, VoteSigner, v, r, s);
    setIndexedSigner(signer, VoteSigner);

    emit VoteSignerAuthorized(msg.sender, signer);
  }

  /**
   * @notice Authorizes an address to sign consensus messages on behalf of the account.
   * @param signer The address of the signing key to authorize.
   * @param v The recovery id of the incoming ECDSA signature.
   * @param r Output value r of the ECDSA signature.
   * @param s Output value s of the ECDSA signature.
   * @dev v, r, s constitute `signer`'s signature on `msg.sender`.
   */
  function authorizeValidatorSigner(address signer, uint8 v, bytes32 r, bytes32 s)
    external
    nonReentrant
  {
    legacyAuthorizeSignerWithSignature(signer, ValidatorSigner, v, r, s);
    setIndexedSigner(signer, ValidatorSigner);

    require(!getValidators().isValidator(msg.sender), "Cannot authorize validator signer");
    emit ValidatorSignerAuthorized(msg.sender, signer);
  }

  /**
   * @notice Authorizes an address to sign consensus messages on behalf of the account.
   * @param signer The address of the signing key to authorize.
   * @param v The recovery id of the incoming ECDSA signature.
   * @param r Output value r of the ECDSA signature.
   * @param s Output value s of the ECDSA signature.
   * @param ecdsaPublicKey The ECDSA public key corresponding to `signer`.
   * @dev v, r, s constitute `signer`'s signature on `msg.sender`.
   */
  function authorizeValidatorSignerWithPublicKey(
    address signer,
    uint8 v,
    bytes32 r,
    bytes32 s,
    bytes calldata ecdsaPublicKey
  ) external nonReentrant {
    legacyAuthorizeSignerWithSignature(signer, ValidatorSigner, v, r, s);
    setIndexedSigner(signer, ValidatorSigner);

    require(
      getValidators().updateEcdsaPublicKey(msg.sender, signer, ecdsaPublicKey),
      "Failed to update ECDSA public key"
    );
    emit ValidatorSignerAuthorized(msg.sender, signer);
  }

  /**
   * @notice Authorizes an address to sign consensus messages on behalf of the account.
   * @param signer The address of the signing key to authorize.
   * @param ecdsaPublicKey The ECDSA public key corresponding to `signer`.
   * @param blsPublicKey The BLS public key that the validator is using for consensus, should pass
   *   proof of possession. 96 bytes.
   * @param blsPop The BLS public key proof-of-possession, which consists of a signature on the
   *   account address. 48 bytes.
   * @param v The recovery id of the incoming ECDSA signature.
   * @param r Output value r of the ECDSA signature.
   * @param s Output value s of the ECDSA signature.
   * @dev v, r, s constitute `signer`'s signature on `msg.sender`.
   */
  function authorizeValidatorSignerWithKeys(
    address signer,
    uint8 v,
    bytes32 r,
    bytes32 s,
    bytes calldata ecdsaPublicKey,
    bytes calldata blsPublicKey,
    bytes calldata blsPop
  ) external nonReentrant {
    legacyAuthorizeSignerWithSignature(signer, ValidatorSigner, v, r, s);
    setIndexedSigner(signer, ValidatorSigner);

    require(
      getValidators().updatePublicKeys(msg.sender, signer, ecdsaPublicKey, blsPublicKey, blsPop),
      "Failed to update validator keys"
    );
    emit ValidatorSignerAuthorized(msg.sender, signer);
  }

  /**
   * @notice Authorizes an address to sign attestations on behalf of the account.
   * @param signer The address of the signing key to authorize.
   * @param v The recovery id of the incoming ECDSA signature.
   * @param r Output value r of the ECDSA signature.
   * @param s Output value s of the ECDSA signature.
   * @dev v, r, s constitute `signer`'s signature on `msg.sender`.
   */
  function authorizeAttestationSigner(address signer, uint8 v, bytes32 r, bytes32 s) public {
    legacyAuthorizeSignerWithSignature(signer, AttestationSigner, v, r, s);
    setIndexedSigner(signer, AttestationSigner);

    emit AttestationSignerAuthorized(msg.sender, signer);
  }

  /**
   * @notice Begin the process of authorizing an address to sign on behalf of the account
   * @param signer The address of the signing key to authorize.
   * @param role The role to authorize signing for.
   */
  function authorizeSigner(address signer, bytes32 role) public {
    require(isAccount(msg.sender), "Unknown account");
    require(
      isNotAccount(signer) && isNotAuthorizedSignerForAnotherAccount(msg.sender, signer),
      "Cannot re-authorize address signer"
    );

    signerAuthorizations[msg.sender][role][signer] = SignerAuthorization({
      started: true,
      completed: false
    });
    emit SignerAuthorizationStarted(msg.sender, signer, role);
  }

  /**
   * @notice Finish the process of authorizing an address to sign on behalf of the account. 
   * @param account The address of account that authorized signing.
   * @param role The role to finish authorizing for.
   */
  function completeSignerAuthorization(address account, bytes32 role) public {
    require(isAccount(account), "Unknown account");
    require(
      isNotAccount(msg.sender) && isNotAuthorizedSignerForAnotherAccount(account, msg.sender),
      "Cannot re-authorize address signer"
    );
    require(
      signerAuthorizations[account][role][msg.sender].started == true,
      "Signer authorization not started"
    );

    authorizedBy[msg.sender] = account;
    signerAuthorizations[account][role][msg.sender].completed = true;
    emit SignerAuthorizationCompleted(account, msg.sender, role);
  }

  /**
   * @notice Whether or not the signer has been registered as the legacy signer for role
   * @param _account The address of account that authorized signing.
   * @param signer The address of the signer.
   * @param role The role that has been authorized.
   */
  function isLegacySigner(address _account, address signer, bytes32 role)
    public
    view
    returns (bool)
  {
    Account storage account = accounts[_account];
    if (role == ValidatorSigner && account.signers.validator == signer) {
      return true;
    } else if (role == AttestationSigner && account.signers.attestation == signer) {
      return true;
    } else if (role == VoteSigner && account.signers.vote == signer) {
      return true;
    } else {
      return false;
    }
  }

  /**
   * @notice Whether or not the signer has been registered as the default signer for role
   * @param account The address of account that authorized signing.
   * @param signer The address of the signer.
   * @param role The role that has been authorized.
   */
  function isDefaultSigner(address account, address signer, bytes32 role)
    public
    view
    returns (bool)
  {
    return defaultSigners[account][role] == signer;
  }

  /**
   * @notice Whether or not the signer has been registered as an indexed signer for role
   * @param account The address of account that authorized signing.
   * @param signer The address of the signer.
   * @param role The role that has been authorized.
   */
  function isIndexedSigner(address account, address signer, bytes32 role)
    public
    view
    returns (bool)
  {
    return
      isLegacyRole(role)
        ? isLegacySigner(account, signer, role)
        : isDefaultSigner(account, signer, role);
  }

  /**
   * @notice Whether or not the signer has been registered as a signer for role
   * @param account The address of account that authorized signing.
   * @param signer The address of the signer.
   * @param role The role that has been authorized.
   */
  function isSigner(address account, address signer, bytes32 role) public view returns (bool) {
    return
      isLegacySigner(account, signer, role) ||
      (signerAuthorizations[account][role][signer].completed && authorizedBy[signer] == account);
  }

  /**
   * @notice Removes the signer for a default role.
   * @param role The role that has been authorized.
   */
  function removeDefaultSigner(bytes32 role) public {
    address signer = defaultSigners[msg.sender][role];
    defaultSigners[msg.sender][role] = address(0);
    emit DefaultSignerRemoved(msg.sender, signer, role);
  }

  /**
   * @notice Remove one of the Validator, Attestation or 
   * Vote signers from an account. Should only be called from
   * methods that check the role is a legacy signer.
   * @param role The role that has been authorized.
   */
  function removeLegacySigner(bytes32 role) private {
    Account storage account = accounts[msg.sender];

    address signer;
    if (role == ValidatorSigner) {
      signer = account.signers.validator;
      account.signers.validator = address(0);
    } else if (role == AttestationSigner) {
      signer = account.signers.attestation;
      account.signers.attestation = address(0);
    } else if (role == VoteSigner) {
      signer = account.signers.vote;
      account.signers.vote = address(0);
    }
    emit LegacySignerRemoved(msg.sender, signer, role);
  }

  /**
   * @notice Removes the currently authorized and indexed signer 
   * for a specific role
   * @param role The role of the signer.
   */
  function removeIndexedSigner(bytes32 role) public {
    address oldSigner = getIndexedSigner(msg.sender, role);
    isLegacyRole(role) ? removeLegacySigner(role) : removeDefaultSigner(role);

    emit IndexedSignerRemoved(msg.sender, oldSigner, role);
  }

  /**
   * @notice Removes the currently authorized signer for a specific role and 
   * if the signer is indexed, remove that as well.
   * @param signer The address of the signer.
   * @param role The role that has been authorized.
   */
  function removeSigner(address signer, bytes32 role) public {
    if (isIndexedSigner(msg.sender, signer, role)) {
      removeIndexedSigner(role);
    }

    delete signerAuthorizations[msg.sender][role][signer];
    emit SignerRemoved(msg.sender, signer, role);
  }

  /**
   * @notice Removes the currently authorized vote signer for the account.
   * Note that the signers cannot be reauthorized after they have been removed.
   */
  function removeVoteSigner() public {
    address signer = getLegacySigner(msg.sender, VoteSigner);
    removeSigner(signer, VoteSigner);
    emit VoteSignerRemoved(msg.sender, signer);
  }

  /**
   * @notice Removes the currently authorized validator signer for the account
   * Note that the signers cannot be reauthorized after they have been removed.
   */
  function removeValidatorSigner() public {
    address signer = getLegacySigner(msg.sender, ValidatorSigner);
    removeSigner(signer, ValidatorSigner);
    emit ValidatorSignerRemoved(msg.sender, signer);
  }

  /**
   * @notice Removes the currently authorized attestation signer for the account
   * Note that the signers cannot be reauthorized after they have been removed.
   */
  function removeAttestationSigner() public {
    address signer = getLegacySigner(msg.sender, AttestationSigner);
    removeSigner(signer, AttestationSigner);
    emit AttestationSignerRemoved(msg.sender, signer);
  }

  function signerToAccountWithRole(address signer, bytes32 role) internal view returns (address) {
    address account = authorizedBy[signer];
    if (account != address(0)) {
      require(isSigner(account, signer, role), "not active authorized signer for role");
      return account;
    }

    require(isAccount(signer), "not an account");
    return signer;
  }

  /**
   * @notice Returns the account associated with `signer`.
   * @param signer The address of the account or currently authorized attestation signer.
   * @dev Fails if the `signer` is not an account or currently authorized attestation signer.
   * @return The associated account.
   */
  function attestationSignerToAccount(address signer) external view returns (address) {
    return signerToAccountWithRole(signer, AttestationSigner);
  }

  /**
   * @notice Returns the account associated with `signer`.
   * @param signer The address of an account or currently authorized validator signer.
   * @dev Fails if the `signer` is not an account or currently authorized validator.
   * @return The associated account.
   */
  function validatorSignerToAccount(address signer) public view returns (address) {
    return signerToAccountWithRole(signer, ValidatorSigner);
  }

  /**
   * @notice Returns the account associated with `signer`.
   * @param signer The address of the account or currently authorized vote signer.
   * @dev Fails if the `signer` is not an account or currently authorized vote signer.
   * @return The associated account.
   */
  function voteSignerToAccount(address signer) external view returns (address) {
    return signerToAccountWithRole(signer, VoteSigner);
  }

  /**
   * @notice Returns the account associated with `signer`.
   * @param signer The address of the account or previously authorized signer.
   * @dev Fails if the `signer` is not an account or previously authorized signer.
   * @return The associated account.
   */
  function signerToAccount(address signer) external view returns (address) {
    address authorizingAccount = authorizedBy[signer];
    if (authorizingAccount != address(0)) {
      return authorizingAccount;
    } else {
      require(isAccount(signer), "Not an account");
      return signer;
    }
  }

  /**
   * @notice Checks whether the role is one of Vote, Validator or Attestation
   * @param role The role to check
   */
  function isLegacyRole(bytes32 role) public pure returns (bool) {
    return role == VoteSigner || role == ValidatorSigner || role == AttestationSigner;
  }

  /**
   * @notice Returns the legacy signer for the specified account and 
   * role. If no signer has been specified it will return the account itself.
   * @param _account The address of the account.
   * @param role The role of the signer.
   */
  function getLegacySigner(address _account, bytes32 role) public view returns (address) {
    require(isLegacyRole(role), "Role is not a legacy signer");

    Account storage account = accounts[_account];
    address signer;
    if (role == ValidatorSigner) {
      signer = account.signers.validator;
    } else if (role == AttestationSigner) {
      signer = account.signers.attestation;
    } else if (role == VoteSigner) {
      signer = account.signers.vote;
    }

    return signer == address(0) ? _account : signer;
  }

  /**
   * @notice Returns the default signer for the specified account and 
   * role. If no signer has been specified it will return the account itself.
   * @param account The address of the account.
   * @param role The role of the signer.
   */
  function getDefaultSigner(address account, bytes32 role) public view returns (address) {
    address defaultSigner = defaultSigners[account][role];
    return defaultSigner == address(0) ? account : defaultSigner;
  }

  /**
   * @notice Returns the indexed signer for the specified account and role. 
   * If no signer has been specified it will return the account itself.
   * @param account The address of the account.
   * @param role The role of the signer.
   */
  function getIndexedSigner(address account, bytes32 role) public view returns (address) {
    return isLegacyRole(role) ? getLegacySigner(account, role) : getDefaultSigner(account, role);
  }

  /**
   * @notice Returns the vote signer for the specified account.
   * @param account The address of the account.
   * @return The address with which the account can sign votes.
   */
  function getVoteSigner(address account) public view returns (address) {
    return getLegacySigner(account, VoteSigner);
  }

  /**
   * @notice Returns the validator signer for the specified account.
   * @param account The address of the account.
   * @return The address with which the account can register a validator or group.
   */
  function getValidatorSigner(address account) public view returns (address) {
    return getLegacySigner(account, ValidatorSigner);
  }

  /**
   * @notice Returns the attestation signer for the specified account.
   * @param account The address of the account.
   * @return The address with which the account can sign attestations.
   */
  function getAttestationSigner(address account) public view returns (address) {
    return getLegacySigner(account, AttestationSigner);
  }

  /**
   * @notice Checks whether or not the account has an indexed signer
   * registered for one of the legacy roles
   */
  function hasLegacySigner(address account, bytes32 role) public view returns (bool) {
    return getLegacySigner(account, role) != account;
  }

  /**
   * @notice Checks whether or not the account has an indexed signer
   * registered for a role
   */
  function hasDefaultSigner(address account, bytes32 role) public view returns (bool) {
    return getDefaultSigner(account, role) != account;
  }

  /**
   * @notice Checks whether or not the account has an indexed signer
   * registered for the role
   */
  function hasIndexedSigner(address account, bytes32 role) public view returns (bool) {
    return isLegacyRole(role) ? hasLegacySigner(account, role) : hasDefaultSigner(account, role);
  }

  /**
   * @notice Checks whether or not the account has a signer
   * registered for the plaintext role.
   * @dev See `hasIndexedSigner` for more gas efficient call.
   */
  function hasAuthorizedSigner(address account, string calldata role) external view returns (bool) {
    return hasIndexedSigner(account, keccak256(abi.encodePacked(role)));
  }

  /**
   * @notice Returns if account has specified a dedicated vote signer.
   * @param account The address of the account.
   * @return Whether the account has specified a dedicated vote signer.
   */
  function hasAuthorizedVoteSigner(address account) external view returns (bool) {
    return hasLegacySigner(account, VoteSigner);
  }

  /**
   * @notice Returns if account has specified a dedicated validator signer.
   * @param account The address of the account.
   * @return Whether the account has specified a dedicated validator signer.
   */
  function hasAuthorizedValidatorSigner(address account) external view returns (bool) {
    return hasLegacySigner(account, ValidatorSigner);
  }

  /**
   * @notice Returns if account has specified a dedicated attestation signer.
   * @param account The address of the account.
   * @return Whether the account has specified a dedicated attestation signer.
   */
  function hasAuthorizedAttestationSigner(address account) external view returns (bool) {
    return hasLegacySigner(account, AttestationSigner);
  }

  /**
   * @notice Getter for the name of an account.
   * @param account The address of the account to get the name for.
   * @return name The name of the account.
   */
  function getName(address account) external view returns (string memory) {
    return accounts[account].name;
  }

  /**
   * @notice Getter for the metadata of an account.
   * @param account The address of the account to get the metadata for.
   * @return metadataURL The URL to access the metadata.
   */
  function getMetadataURL(address account) external view returns (string memory) {
    return accounts[account].metadataURL;
  }

  /**
   * @notice Getter for the metadata of multiple accounts.
   * @param accountsToQuery The addresses of the accounts to get the metadata for.
   * @return (stringLengths[] - the length of each string in bytes
   *          data - all strings concatenated
   *         )
   */
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

  /**
   * @notice Getter for the data encryption key and version.
   * @param account The address of the account to get the key for
   * @return dataEncryptionKey secp256k1 public key for data encryption. Preferably compressed.
   */
  function getDataEncryptionKey(address account) external view returns (bytes memory) {
    return accounts[account].dataEncryptionKey;
  }

  /**
   * @notice Getter for the wallet address for an account
   * @param account The address of the account to get the wallet address for
   * @return Wallet address
   */
  function getWalletAddress(address account) external view returns (address) {
    return accounts[account].walletAddress;
  }

  /**
   * @notice Check if an account already exists.
   * @param account The address of the account
   * @return Returns `true` if account exists. Returns `false` otherwise.
   */
  function isAccount(address account) public view returns (bool) {
    return (accounts[account].exists);
  }

  /**
   * @notice Check if an account already exists.
   * @param account The address of the account
   * @return Returns `false` if account exists. Returns `true` otherwise.
   */
  function isNotAccount(address account) internal view returns (bool) {
    return (!accounts[account].exists);
  }

  /**
   * @notice Check if an address has been an authorized signer for an account.
   * @param signer The possibly authorized address.
   * @return Returns `true` if authorized. Returns `false` otherwise.
   */
  function isAuthorizedSigner(address signer) external view returns (bool) {
    return (authorizedBy[signer] != address(0));
  }

  /**
   * @notice Check if an address has not been an authorized signer for an account.
   * @param signer The possibly authorized address.
   * @return Returns `false` if authorized. Returns `true` otherwise.
   */
  function isNotAuthorizedSigner(address signer) internal view returns (bool) {
    return (authorizedBy[signer] == address(0));
  }

  /**
   * @notice Check if `signer` has not been authorized, and if it has been previously
   *         authorized that it was authorized by `account`.
   * @param account The authorizing account address.
   * @param signer The possibly authorized address.
   * @return Returns `false` if authorized. Returns `true` otherwise.
   */
  function isNotAuthorizedSignerForAnotherAccount(address account, address signer)
    internal
    view
    returns (bool)
  {
    return (authorizedBy[signer] == address(0) || authorizedBy[signer] == account);
  }

  /**
   * @notice Authorizes some role of `msg.sender`'s account to another address.
   * @param authorized The address to authorize.
   * @param v The recovery id of the incoming ECDSA signature.
   * @param r Output value r of the ECDSA signature.
   * @param s Output value s of the ECDSA signature.
   * @dev Fails if the address is already authorized to another account or is an account itself.
   * @dev Note that once an address is authorized, it may never be authorized again.
   * @dev v, r, s constitute `authorized`'s signature on `msg.sender`.
   */
  function authorizeAddress(address authorized, uint8 v, bytes32 r, bytes32 s) private {
    address signer = Signatures.getSignerOfAddress(msg.sender, v, r, s);
    require(signer == authorized, "Invalid signature");

    authorize(authorized);
  }

  /**
   * @notice Returns the address that signed the provided role authorization.
   * @param account The `account` property signed over in the EIP712 signature
   * @param signer The `signer` property signed over in the EIP712 signature
   * @param role The `role` property signed over in the EIP712 signature
   * @param v The recovery id of the incoming ECDSA signature.
   * @param r Output value r of the ECDSA signature.
   * @param s Output value s of the ECDSA signature.
   * @return The address that signed the provided role authorization.
   */
  function getRoleAuthorizationSigner(
    address account,
    address signer,
    bytes32 role,
    uint8 v,
    bytes32 r,
    bytes32 s
  ) public view returns (address) {
    bytes32 structHash = keccak256(
      abi.encode(EIP712_AUTHORIZE_SIGNER_TYPEHASH, account, signer, role)
    );
    return Signatures.getSignerOfTypedDataHash(eip712DomainSeparator, structHash, v, r, s);
  }

  /**
   * @notice Authorizes a role of `msg.sender`'s account to another address (`authorized`).
   * @param authorized The address to authorize.
   * @param role The role to authorize.
   * @param v The recovery id of the incoming ECDSA signature.
   * @param r Output value r of the ECDSA signature.
   * @param s Output value s of the ECDSA signature.
   * @dev Fails if the address is already authorized to another account or is an account itself.
   * @dev Note that this signature is EIP712 compliant over the authorizing `account` 
   * (`msg.sender`), `signer` (`authorized`) and `role`.
   */
  function authorizeAddressWithRole(address authorized, bytes32 role, uint8 v, bytes32 r, bytes32 s)
    private
  {
    address signer = getRoleAuthorizationSigner(msg.sender, authorized, role, v, r, s);
    require(signer == authorized, "Invalid signature");

    authorize(authorized);
  }

  /**
   * @notice Authorizes an address to `msg.sender`'s account
   * @param authorized The address to authorize.
   * @dev Fails if the address is already authorized for another account or is an account itself.
   */
  function authorize(address authorized) private {
    require(isAccount(msg.sender), "Unknown account");
    require(
      isNotAccount(authorized) && isNotAuthorizedSignerForAnotherAccount(msg.sender, authorized),
      "Cannot re-authorize address or locked gold account for another account"
    );

    authorizedBy[authorized] = msg.sender;
  }
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

/**
 * @dev Elliptic Curve Digital Signature Algorithm (ECDSA) operations.
 *
 * These functions can be used to verify that a message was signed by the holder
 * of the private keys of a given address.
 */
library ECDSA {
    /**
     * @dev Returns the address that signed a hashed message (`hash`) with
     * `signature`. This address can then be used for verification purposes.
     *
     * The `ecrecover` EVM opcode allows for malleable (non-unique) signatures:
     * this function rejects them by requiring the `s` value to be in the lower
     * half order, and the `v` value to be either 27 or 28.
     *
     * NOTE: This call _does not revert_ if the signature is invalid, or
     * if the signer is otherwise unable to be retrieved. In those scenarios,
     * the zero address is returned.
     *
     * IMPORTANT: `hash` _must_ be the result of a hash operation for the
     * verification to be secure: it is possible to craft signatures that
     * recover to arbitrary addresses for non-hashed data. A safe way to ensure
     * this is by receiving a hash of the original message (which may otherwise
     * be too long), and then calling {toEthSignedMessageHash} on it.
     */
    function recover(bytes32 hash, bytes memory signature) internal pure returns (address) {
        // Check the signature length
        if (signature.length != 65) {
            return (address(0));
        }

        // Divide the signature in r, s and v variables
        bytes32 r;
        bytes32 s;
        uint8 v;

        // ecrecover takes the signature parameters, and the only way to get them
        // currently is to use assembly.
        // solhint-disable-next-line no-inline-assembly
        assembly {
            r := mload(add(signature, 0x20))
            s := mload(add(signature, 0x40))
            v := byte(0, mload(add(signature, 0x60)))
        }

        // EIP-2 still allows signature malleability for ecrecover(). Remove this possibility and make the signature
        // unique. Appendix F in the Ethereum Yellow paper (https://ethereum.github.io/yellowpaper/paper.pdf), defines
        // the valid range for s in (281): 0 < s < secp256k1n ÷ 2 + 1, and for v in (282): v ∈ {27, 28}. Most
        // signatures from current libraries generate a unique signature with an s-value in the lower half order.
        //
        // If your library generates malleable signatures, such as s-values in the upper range, calculate a new s-value
        // with 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141 - s1 and flip v from 27 to 28 or
        // vice versa. If your library also generates signatures with 0/1 for v instead 27/28, add 27 to v to accept
        // these malleable signatures as well.
        if (uint256(s) > 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0) {
            return address(0);
        }

        if (v != 27 && v != 28) {
            return address(0);
        }

        // If the signature is valid (and not malleable), return the signer address
        return ecrecover(hash, v, r, s);
    }

    /**
     * @dev Returns an Ethereum Signed Message, created from a `hash`. This
     * replicates the behavior of the
     * https://github.com/ethereum/wiki/wiki/JSON-RPC#eth_sign[`eth_sign`]
     * JSON-RPC method.
     *
     * See {recover}.
     */
    function toEthSignedMessageHash(bytes32 hash) internal pure returns (bytes32) {
        // 32 is the length in bytes of hash,
        // enforced by the type signature above
        return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", hash));
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

/**
 * @title Helps contracts guard against reentrancy attacks.
 * @author Remco Bloemen <[email protected]π.com>, Eenae <[email protected]>
 * @dev If you mark a function `nonReentrant`, you should also
 * mark it `external`.
 */
contract ReentrancyGuard {
  /// @dev counter to allow mutex lock with only one SSTORE operation
  uint256 private _guardCounter;

  constructor() internal {
    // The counter starts at one to prevent changing it from zero to a non-zero
    // value, which is a more expensive operation.
    _guardCounter = 1;
  }

  /**
   * @dev Prevents a contract from calling itself, directly or indirectly.
   * Calling a `nonReentrant` function from another `nonReentrant`
   * function is not supported. It is possible to prevent this from happening
   * by making the `nonReentrant` function external, and make it call a
   * `private` function that does the actual work.
   */
  modifier nonReentrant() {
    _guardCounter += 1;
    uint256 localCounter = _guardCounter;
    _;
    require(localCounter == _guardCounter, "reentrant call");
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

import "openzeppelin-solidity/contracts/cryptography/ECDSA.sol";

library Signatures {
  /**
  * @notice Given a signed address, returns the signer of the address.
  * @param message The address that was signed.
  * @param v The recovery id of the incoming ECDSA signature.
  * @param r Output value r of the ECDSA signature.
  * @param s Output value s of the ECDSA signature.
  */
  function getSignerOfAddress(address message, uint8 v, bytes32 r, bytes32 s)
    public
    pure
    returns (address)
  {
    bytes32 hash = keccak256(abi.encodePacked(message));
    return getSignerOfMessageHash(hash, v, r, s);
  }

  /**
  * @notice Given a message hash, returns the signer of the address.
  * @param messageHash The hash of a message.
  * @param v The recovery id of the incoming ECDSA signature.
  * @param r Output value r of the ECDSA signature.
  * @param s Output value s of the ECDSA signature.
  */
  function getSignerOfMessageHash(bytes32 messageHash, uint8 v, bytes32 r, bytes32 s)
    public
    pure
    returns (address)
  {
    bytes memory signature = new bytes(65);
    // Concatenate (r, s, v) into signature.
    assembly {
      mstore(add(signature, 32), r)
      mstore(add(signature, 64), s)
      mstore8(add(signature, 96), v)
    }
    bytes32 prefixedHash = ECDSA.toEthSignedMessageHash(messageHash);
    return ECDSA.recover(prefixedHash, signature);
  }

  /**
  * @notice Given a domain separator and a structHash, construct the typed data hash
  * @param eip712DomainSeparator Context specific domain separator
  * @param structHash hash of the typed data struct
  * @return The EIP712 typed data hash
  */
  function toEthSignedTypedDataHash(bytes32 eip712DomainSeparator, bytes32 structHash)
    public
    pure
    returns (bytes32)
  {
    return keccak256(abi.encodePacked("\x19\x01", eip712DomainSeparator, structHash));
  }

  /**
  * @notice Given a domain separator and a structHash and a signature return the signer
  * @param eip712DomainSeparator Context specific domain separator
  * @param structHash hash of the typed data struct
  * @param v The recovery id of the incoming ECDSA signature.
  * @param r Output value r of the ECDSA signature.
  * @param s Output value s of the ECDSA signature.
  */
  function getSignerOfTypedDataHash(
    bytes32 eip712DomainSeparator,
    bytes32 structHash,
    uint8 v,
    bytes32 r,
    bytes32 s
  ) public pure returns (address) {
    bytes memory signature = new bytes(65);
    // Concatenate (r, s, v) into signature.
    assembly {
      mstore(add(signature, 32), r)
      mstore(add(signature, 64), s)
      mstore8(add(signature, 96), v)
    }
    bytes32 prefixedHash = toEthSignedTypedDataHash(eip712DomainSeparator, structHash);
    return ECDSA.recover(prefixedHash, signature);
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