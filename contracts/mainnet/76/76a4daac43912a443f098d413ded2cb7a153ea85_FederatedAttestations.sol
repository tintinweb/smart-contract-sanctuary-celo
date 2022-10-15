pragma solidity ^0.5.13;

import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "openzeppelin-solidity/contracts/ownership/Ownable.sol";
import "openzeppelin-solidity/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-solidity/contracts/utils/SafeCast.sol";

import "./interfaces/IFederatedAttestations.sol";
import "../common/interfaces/IAccounts.sol";
import "../common/interfaces/ICeloVersionedContract.sol";

import "../common/Initializable.sol";
import "../common/UsingRegistryV2.sol";
import "../common/Signatures.sol";

/**
 * @title Contract mapping identifiers to accounts
 */
contract FederatedAttestations is
  IFederatedAttestations,
  ICeloVersionedContract,
  Ownable,
  Initializable,
  UsingRegistryV2
{
  using SafeMath for uint256;
  using SafeCast for uint256;

  struct OwnershipAttestation {
    address account;
    address signer;
    uint64 issuedOn;
    uint64 publishedOn;
    // using uint64 to allow for extra space to add parameters
  }

  // Mappings from identifier <-> attestation are separated by issuer,
  // *requiring* users to specify issuers when retrieving attestations.
  // Maintaining bidirectional mappings (vs. in Attestations.sol) makes it possible
  // to perform lookups by identifier or account without indexing event data.

  // identifier -> issuer -> attestations
  mapping(bytes32 => mapping(address => OwnershipAttestation[])) public identifierToAttestations;
  // account -> issuer -> identifiers
  mapping(address => mapping(address => bytes32[])) public addressToIdentifiers;

  // unique attestation hash -> isRevoked
  mapping(bytes32 => bool) public revokedAttestations;

  bytes32 public eip712DomainSeparator;
  bytes32 public constant EIP712_OWNERSHIP_ATTESTATION_TYPEHASH = keccak256(
    abi.encodePacked(
      "OwnershipAttestation(bytes32 identifier,address issuer,",
      "address account,address signer,uint64 issuedOn)"
    )
  );

  // Changing any of these constraints will require re-benchmarking
  // and checking assumptions for batch revocation.
  // These can only be modified by releasing a new version of this contract.
  uint256 public constant MAX_ATTESTATIONS_PER_IDENTIFIER = 20;
  uint256 public constant MAX_IDENTIFIERS_PER_ADDRESS = 20;

  event EIP712DomainSeparatorSet(bytes32 eip712DomainSeparator);
  event AttestationRegistered(
    bytes32 indexed identifier,
    address indexed issuer,
    address indexed account,
    address signer,
    uint64 issuedOn,
    uint64 publishedOn
  );
  event AttestationRevoked(
    bytes32 indexed identifier,
    address indexed issuer,
    address indexed account,
    address signer,
    uint64 issuedOn,
    uint64 publishedOn
  );

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
    return (1, 1, 0, 0);
  }

  /**
   * @notice Used in place of the constructor to allow the contract to be upgradable via proxy.
   */
  function initialize() external initializer {
    _transferOwnership(msg.sender);
    setEip712DomainSeparator();
  }

  /**
   * @notice Registers an attestation directly from the issuer
   * @param identifier Hash of the identifier to be attested
   * @param account Address of the account being mapped to the identifier
   * @param issuedOn Time at which the issuer issued the attestation in Unix time 
   * @dev Attestation signer and issuer in storage is set to msg.sender
   * @dev Throws if an attestation with the same (identifier, issuer, account) already exists
   */
  function registerAttestationAsIssuer(bytes32 identifier, address account, uint64 issuedOn)
    external
  {
    _registerAttestation(identifier, msg.sender, account, msg.sender, issuedOn);
  }

  /**
   * @notice Registers an attestation with a valid signature
   * @param identifier Hash of the identifier to be attested
   * @param issuer Address of the attestation issuer
   * @param account Address of the account being mapped to the identifier
   * @param issuedOn Time at which the issuer issued the attestation in Unix time 
   * @param signer Address of the signer of the attestation
   * @param v The recovery id of the incoming ECDSA signature
   * @param r Output value r of the ECDSA signature
   * @param s Output value s of the ECDSA signature
   * @dev Throws if an attestation with the same (identifier, issuer, account) already exists
   */
  function registerAttestation(
    bytes32 identifier,
    address issuer,
    address account,
    address signer,
    uint64 issuedOn,
    uint8 v,
    bytes32 r,
    bytes32 s
  ) external {
    validateAttestationSig(identifier, issuer, account, signer, issuedOn, v, r, s);
    _registerAttestation(identifier, issuer, account, signer, issuedOn);
  }

  /**
   * @notice Revokes an attestation 
   * @param identifier Hash of the identifier to be revoked
   * @param issuer Address of the attestation issuer
   * @param account Address of the account mapped to the identifier
   * @dev Throws if sender is not the issuer, signer, or account
   */
  function revokeAttestation(bytes32 identifier, address issuer, address account) external {
    require(
      account == msg.sender ||
        // Minor gas optimization to prevent storage lookup in Accounts.sol if issuer == msg.sender
        issuer == msg.sender ||
        getAccounts().attestationSignerToAccount(msg.sender) == issuer,
      "Sender does not have permission to revoke this attestation"
    );
    _revokeAttestation(identifier, issuer, account);
  }

  /**
   * @notice Revokes attestations [identifiers <-> accounts] from issuer
   * @param issuer Address of the issuer of all attestations to be revoked
   * @param identifiers Hash of the identifiers
   * @param accounts Addresses of the accounts mapped to the identifiers
   *   at the same indices
   * @dev Throws if the number of identifiers and accounts is not the same
   * @dev Throws if sender is not the issuer or currently registered signer of issuer
   * @dev Throws if an attestation is not found for identifiers[i] <-> accounts[i]
   */
  function batchRevokeAttestations(
    address issuer,
    bytes32[] calldata identifiers,
    address[] calldata accounts
  ) external {
    require(identifiers.length == accounts.length, "Unequal number of identifiers and accounts");
    require(
      issuer == msg.sender || getAccounts().attestationSignerToAccount(msg.sender) == issuer,
      "Sender does not have permission to revoke attestations from this issuer"
    );

    for (uint256 i = 0; i < identifiers.length; i = i.add(1)) {
      _revokeAttestation(identifiers[i], issuer, accounts[i]);
    }
  }

  /**
   * @notice Returns info about attestations for `identifier` produced by 
   *    signers of `trustedIssuers`
   * @param identifier Hash of the identifier
   * @param trustedIssuers Array of n issuers whose attestations will be included
   * @return countsPerIssuer Array of number of attestations returned per issuer
   *          For m (== sum([0])) found attestations: 
   * @return accounts Array of m accounts 
   * @return signers Array of m signers
   * @return issuedOns Array of m issuedOns
   * @return publishedOns Array of m publishedOns
   * @dev Adds attestation info to the arrays in order of provided trustedIssuers
   * @dev Expectation that only one attestation exists per (identifier, issuer, account)
   */
  function lookupAttestations(bytes32 identifier, address[] calldata trustedIssuers)
    external
    view
    returns (
      uint256[] memory countsPerIssuer,
      address[] memory accounts,
      address[] memory signers,
      uint64[] memory issuedOns,
      uint64[] memory publishedOns
    )
  {
    uint256 totalAttestations;
    (totalAttestations, countsPerIssuer) = getNumAttestations(identifier, trustedIssuers);

    accounts = new address[](totalAttestations);
    signers = new address[](totalAttestations);
    issuedOns = new uint64[](totalAttestations);
    publishedOns = new uint64[](totalAttestations);

    totalAttestations = 0;
    OwnershipAttestation[] memory attestationsPerIssuer;

    for (uint256 i = 0; i < trustedIssuers.length; i = i.add(1)) {
      attestationsPerIssuer = identifierToAttestations[identifier][trustedIssuers[i]];
      for (uint256 j = 0; j < attestationsPerIssuer.length; j = j.add(1)) {
        accounts[totalAttestations] = attestationsPerIssuer[j].account;
        signers[totalAttestations] = attestationsPerIssuer[j].signer;
        issuedOns[totalAttestations] = attestationsPerIssuer[j].issuedOn;
        publishedOns[totalAttestations] = attestationsPerIssuer[j].publishedOn;
        totalAttestations = totalAttestations.add(1);
      }
    }
    return (countsPerIssuer, accounts, signers, issuedOns, publishedOns);
  }

  /**
   * @notice Returns identifiers mapped to `account` by signers of `trustedIssuers`
   * @param account Address of the account
   * @param trustedIssuers Array of n issuers whose identifier mappings will be used
   * @return countsPerIssuer Array of number of identifiers returned per issuer
   * @return identifiers Array (length == sum([0])) of identifiers
   * @dev Adds identifier info to the arrays in order of provided trustedIssuers
   * @dev Expectation that only one attestation exists per (identifier, issuer, account)
   */
  function lookupIdentifiers(address account, address[] calldata trustedIssuers)
    external
    view
    returns (uint256[] memory countsPerIssuer, bytes32[] memory identifiers)
  {
    uint256 totalIdentifiers;
    (totalIdentifiers, countsPerIssuer) = getNumIdentifiers(account, trustedIssuers);

    identifiers = new bytes32[](totalIdentifiers);
    bytes32[] memory identifiersPerIssuer;

    uint256 currIndex = 0;

    for (uint256 i = 0; i < trustedIssuers.length; i = i.add(1)) {
      identifiersPerIssuer = addressToIdentifiers[account][trustedIssuers[i]];
      for (uint256 j = 0; j < identifiersPerIssuer.length; j = j.add(1)) {
        identifiers[currIndex] = identifiersPerIssuer[j];
        currIndex = currIndex.add(1);
      }
    }
    return (countsPerIssuer, identifiers);
  }

  /**
   * @notice Validates the given attestation and signature
   * @param identifier Hash of the identifier to be attested
   * @param issuer Address of the attestation issuer
   * @param account Address of the account being mapped to the identifier
   * @param issuedOn Time at which the issuer issued the attestation in Unix time 
   * @param signer Address of the signer of the attestation
   * @param v The recovery id of the incoming ECDSA signature
   * @param r Output value r of the ECDSA signature
   * @param s Output value s of the ECDSA signature
   * @dev Throws if attestation has been revoked
   * @dev Throws if signer is not an authorized AttestationSigner of the issuer
   */
  function validateAttestationSig(
    bytes32 identifier,
    address issuer,
    address account,
    address signer,
    uint64 issuedOn,
    uint8 v,
    bytes32 r,
    bytes32 s
  ) public view {
    // attestationSignerToAccount instead of isSigner allows the issuer to act as its own signer
    require(
      getAccounts().attestationSignerToAccount(signer) == issuer,
      "Signer is not a currently authorized AttestationSigner for the issuer"
    );
    bytes32 structHash = getUniqueAttestationHash(identifier, issuer, account, signer, issuedOn);
    address guessedSigner = Signatures.getSignerOfTypedDataHash(
      eip712DomainSeparator,
      structHash,
      v,
      r,
      s
    );
    require(guessedSigner == signer, "Signature is invalid");
  }

  function getUniqueAttestationHash(
    bytes32 identifier,
    address issuer,
    address account,
    address signer,
    uint64 issuedOn
  ) public pure returns (bytes32) {
    return
      keccak256(
        abi.encode(
          EIP712_OWNERSHIP_ATTESTATION_TYPEHASH,
          identifier,
          issuer,
          account,
          signer,
          issuedOn
        )
      );
  }

  /**
   * @notice Sets the EIP712 domain separator for the Celo FederatedAttestations abstraction.
   */
  function setEip712DomainSeparator() internal {
    uint256 chainId;
    assembly {
      chainId := chainid
    }

    eip712DomainSeparator = keccak256(
      abi.encode(
        keccak256(
          "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
        ),
        keccak256(bytes("FederatedAttestations")),
        keccak256("1.0"),
        chainId,
        address(this)
      )
    );
    emit EIP712DomainSeparatorSet(eip712DomainSeparator);
  }

  /**
   * @notice Helper function for lookupAttestations to calculate the
             total number of attestations completed for an identifier
             by each trusted issuer
   * @param identifier Hash of the identifier
   * @param trustedIssuers Array of n issuers whose attestations will be included
   * @return totalAttestations Sum total of attestations found
   * @return countsPerIssuer Array of number of attestations found per issuer
   */
  function getNumAttestations(bytes32 identifier, address[] memory trustedIssuers)
    internal
    view
    returns (uint256 totalAttestations, uint256[] memory countsPerIssuer)
  {
    totalAttestations = 0;
    uint256 numAttestationsForIssuer;
    countsPerIssuer = new uint256[](trustedIssuers.length);

    for (uint256 i = 0; i < trustedIssuers.length; i = i.add(1)) {
      numAttestationsForIssuer = identifierToAttestations[identifier][trustedIssuers[i]].length;
      totalAttestations = totalAttestations.add(numAttestationsForIssuer);
      countsPerIssuer[i] = numAttestationsForIssuer;
    }
    return (totalAttestations, countsPerIssuer);
  }

  /**
   * @notice Helper function for lookupIdentifiers to calculate the
             total number of identifiers completed for an identifier
             by each trusted issuer
   * @param account Address of the account
   * @param trustedIssuers Array of n issuers whose identifiers will be included
   * @return totalIdentifiers Sum total of identifiers found
   * @return countsPerIssuer Array of number of identifiers found per issuer
   */
  function getNumIdentifiers(address account, address[] memory trustedIssuers)
    internal
    view
    returns (uint256 totalIdentifiers, uint256[] memory countsPerIssuer)
  {
    totalIdentifiers = 0;
    uint256 numIdentifiersForIssuer;
    countsPerIssuer = new uint256[](trustedIssuers.length);

    for (uint256 i = 0; i < trustedIssuers.length; i = i.add(1)) {
      numIdentifiersForIssuer = addressToIdentifiers[account][trustedIssuers[i]].length;
      totalIdentifiers = totalIdentifiers.add(numIdentifiersForIssuer);
      countsPerIssuer[i] = numIdentifiersForIssuer;
    }
    return (totalIdentifiers, countsPerIssuer);
  }

  /**
   * @notice Registers an attestation
   * @param identifier Hash of the identifier to be attested
   * @param issuer Address of the attestation issuer
   * @param account Address of the account being mapped to the identifier
   * @param issuedOn Time at which the issuer issued the attestation in Unix time 
   * @param signer Address of the signer of the attestation
   */
  function _registerAttestation(
    bytes32 identifier,
    address issuer,
    address account,
    address signer,
    uint64 issuedOn
  ) private {
    require(
      !revokedAttestations[getUniqueAttestationHash(identifier, issuer, account, signer, issuedOn)],
      "Attestation has been revoked"
    );
    uint256 numExistingAttestations = identifierToAttestations[identifier][issuer].length;
    require(
      numExistingAttestations.add(1) <= MAX_ATTESTATIONS_PER_IDENTIFIER,
      "Max attestations already registered for identifier"
    );
    require(
      addressToIdentifiers[account][issuer].length.add(1) <= MAX_IDENTIFIERS_PER_ADDRESS,
      "Max identifiers already registered for account"
    );

    for (uint256 i = 0; i < numExistingAttestations; i = i.add(1)) {
      // This enforces only one attestation to be uploaded
      // for a given set of (identifier, issuer, account)
      // Editing/upgrading an attestation requires that it be revoked before a new one is registered
      require(
        identifierToAttestations[identifier][issuer][i].account != account,
        "Attestation for this account already exists"
      );
    }
    uint64 publishedOn = uint64(block.timestamp);
    OwnershipAttestation memory attestation = OwnershipAttestation(
      account,
      signer,
      issuedOn,
      publishedOn
    );
    identifierToAttestations[identifier][issuer].push(attestation);
    addressToIdentifiers[account][issuer].push(identifier);
    emit AttestationRegistered(identifier, issuer, account, signer, issuedOn, publishedOn);
  }

  /**
   * @notice Revokes an attestation:
   *  helper function for revokeAttestation and batchRevokeAttestations
   * @param identifier Hash of the identifier to be revoked
   * @param issuer Address of the attestation issuer
   * @param account Address of the account mapped to the identifier
   * @dev Reverts if attestation is not found mapping identifier <-> account
   */
  function _revokeAttestation(bytes32 identifier, address issuer, address account) private {
    OwnershipAttestation[] storage attestations = identifierToAttestations[identifier][issuer];
    uint256 lenAttestations = attestations.length;
    for (uint256 i = 0; i < lenAttestations; i = i.add(1)) {
      if (attestations[i].account != account) {
        continue;
      }

      OwnershipAttestation memory attestation = attestations[i];
      // This is meant to delete the attestations in the array
      // and then move the last element in the array to that empty spot,
      // to avoid having empty elements in the array
      if (i != lenAttestations - 1) {
        attestations[i] = attestations[lenAttestations - 1];
      }
      attestations.pop();

      bool deletedIdentifier = false;
      bytes32[] storage identifiers = addressToIdentifiers[account][issuer];
      uint256 lenIdentifiers = identifiers.length;

      for (uint256 j = 0; j < lenIdentifiers; j = j.add(1)) {
        if (identifiers[j] != identifier) {
          continue;
        }
        if (j != lenIdentifiers - 1) {
          identifiers[j] = identifiers[lenIdentifiers - 1];
        }
        identifiers.pop();
        deletedIdentifier = true;
        break;
      }
      // Should never be false - both mappings should always be updated in unison
      assert(deletedIdentifier);

      bytes32 attestationHash = getUniqueAttestationHash(
        identifier,
        issuer,
        account,
        attestation.signer,
        attestation.issuedOn
      );
      revokedAttestations[attestationHash] = true;

      emit AttestationRevoked(
        identifier,
        issuer,
        account,
        attestation.signer,
        attestation.issuedOn,
        attestation.publishedOn
      );
      return;
    }
    revert("Attestation to be revoked does not exist");
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
import "../identity/interfaces/IFederatedAttestations.sol";

import "../stability/interfaces/IExchange.sol";
import "../stability/interfaces/IReserve.sol";
import "../stability/interfaces/ISortedOracles.sol";
import "../stability/interfaces/IStableToken.sol";

contract UsingRegistryV2 {
  address internal constant registryAddress = 0x000000000000000000000000000000000000ce10;
  IRegistry public constant registryContract = IRegistry(registryAddress);

  bytes32 internal constant ACCOUNTS_REGISTRY_ID = keccak256(abi.encodePacked("Accounts"));
  bytes32 internal constant ATTESTATIONS_REGISTRY_ID = keccak256(abi.encodePacked("Attestations"));
  bytes32 internal constant DOWNTIME_SLASHER_REGISTRY_ID = keccak256(
    abi.encodePacked("DowntimeSlasher")
  );
  bytes32 internal constant DOUBLE_SIGNING_SLASHER_REGISTRY_ID = keccak256(
    abi.encodePacked("DoubleSigningSlasher")
  );
  bytes32 internal constant ELECTION_REGISTRY_ID = keccak256(abi.encodePacked("Election"));
  bytes32 internal constant EXCHANGE_REGISTRY_ID = keccak256(abi.encodePacked("Exchange"));
  bytes32 internal constant EXCHANGE_EURO_REGISTRY_ID = keccak256(abi.encodePacked("ExchangeEUR"));
  bytes32 internal constant EXCHANGE_REAL_REGISTRY_ID = keccak256(abi.encodePacked("ExchangeBRL"));

  bytes32 internal constant FEE_CURRENCY_WHITELIST_REGISTRY_ID = keccak256(
    abi.encodePacked("FeeCurrencyWhitelist")
  );
  bytes32 internal constant FEDERATED_ATTESTATIONS_REGISTRY_ID = keccak256(
    abi.encodePacked("FederatedAttestations")
  );
  bytes32 internal constant FREEZER_REGISTRY_ID = keccak256(abi.encodePacked("Freezer"));
  bytes32 internal constant GOLD_TOKEN_REGISTRY_ID = keccak256(abi.encodePacked("GoldToken"));
  bytes32 internal constant GOVERNANCE_REGISTRY_ID = keccak256(abi.encodePacked("Governance"));
  bytes32 internal constant GOVERNANCE_SLASHER_REGISTRY_ID = keccak256(
    abi.encodePacked("GovernanceSlasher")
  );
  bytes32 internal constant LOCKED_GOLD_REGISTRY_ID = keccak256(abi.encodePacked("LockedGold"));
  bytes32 internal constant RESERVE_REGISTRY_ID = keccak256(abi.encodePacked("Reserve"));
  bytes32 internal constant RANDOM_REGISTRY_ID = keccak256(abi.encodePacked("Random"));
  bytes32 internal constant SORTED_ORACLES_REGISTRY_ID = keccak256(
    abi.encodePacked("SortedOracles")
  );
  bytes32 internal constant STABLE_TOKEN_REGISTRY_ID = keccak256(abi.encodePacked("StableToken"));
  bytes32 internal constant STABLE_EURO_TOKEN_REGISTRY_ID = keccak256(
    abi.encodePacked("StableTokenEUR")
  );
  bytes32 internal constant STABLE_REAL_TOKEN_REGISTRY_ID = keccak256(
    abi.encodePacked("StableTokenBRL")
  );
  bytes32 internal constant VALIDATORS_REGISTRY_ID = keccak256(abi.encodePacked("Validators"));

  modifier onlyRegisteredContract(bytes32 identifierHash) {
    require(
      registryContract.getAddressForOrDie(identifierHash) == msg.sender,
      "only registered contract"
    );
    _;
  }

  modifier onlyRegisteredContracts(bytes32[] memory identifierHashes) {
    require(registryContract.isOneOf(identifierHashes, msg.sender), "only registered contracts");
    _;
  }

  function getAccounts() internal view returns (IAccounts) {
    return IAccounts(registryContract.getAddressForOrDie(ACCOUNTS_REGISTRY_ID));
  }

  function getAttestations() internal view returns (IAttestations) {
    return IAttestations(registryContract.getAddressForOrDie(ATTESTATIONS_REGISTRY_ID));
  }

  function getElection() internal view returns (IElection) {
    return IElection(registryContract.getAddressForOrDie(ELECTION_REGISTRY_ID));
  }

  function getExchange() internal view returns (IExchange) {
    return IExchange(registryContract.getAddressForOrDie(EXCHANGE_REGISTRY_ID));
  }

  function getExchangeDollar() internal view returns (IExchange) {
    return getExchange();
  }

  function getExchangeEuro() internal view returns (IExchange) {
    return IExchange(registryContract.getAddressForOrDie(EXCHANGE_EURO_REGISTRY_ID));
  }

  function getExchangeREAL() internal view returns (IExchange) {
    return IExchange(registryContract.getAddressForOrDie(EXCHANGE_REAL_REGISTRY_ID));
  }

  function getFeeCurrencyWhitelistRegistry() internal view returns (IFeeCurrencyWhitelist) {
    return
      IFeeCurrencyWhitelist(
        registryContract.getAddressForOrDie(FEE_CURRENCY_WHITELIST_REGISTRY_ID)
      );
  }

  function getFederatedAttestations() internal view returns (IFederatedAttestations) {
    return
      IFederatedAttestations(
        registryContract.getAddressForOrDie(FEDERATED_ATTESTATIONS_REGISTRY_ID)
      );
  }

  function getFreezer() internal view returns (IFreezer) {
    return IFreezer(registryContract.getAddressForOrDie(FREEZER_REGISTRY_ID));
  }

  function getGoldToken() internal view returns (IERC20) {
    return IERC20(registryContract.getAddressForOrDie(GOLD_TOKEN_REGISTRY_ID));
  }

  function getGovernance() internal view returns (IGovernance) {
    return IGovernance(registryContract.getAddressForOrDie(GOVERNANCE_REGISTRY_ID));
  }

  function getLockedGold() internal view returns (ILockedGold) {
    return ILockedGold(registryContract.getAddressForOrDie(LOCKED_GOLD_REGISTRY_ID));
  }

  function getRandom() internal view returns (IRandom) {
    return IRandom(registryContract.getAddressForOrDie(RANDOM_REGISTRY_ID));
  }

  function getReserve() internal view returns (IReserve) {
    return IReserve(registryContract.getAddressForOrDie(RESERVE_REGISTRY_ID));
  }

  function getSortedOracles() internal view returns (ISortedOracles) {
    return ISortedOracles(registryContract.getAddressForOrDie(SORTED_ORACLES_REGISTRY_ID));
  }

  function getStableToken() internal view returns (IStableToken) {
    return IStableToken(registryContract.getAddressForOrDie(STABLE_TOKEN_REGISTRY_ID));
  }

  function getStableDollarToken() internal view returns (IStableToken) {
    return getStableToken();
  }

  function getStableEuroToken() internal view returns (IStableToken) {
    return IStableToken(registryContract.getAddressForOrDie(STABLE_EURO_TOKEN_REGISTRY_ID));
  }

  function getStableRealToken() internal view returns (IStableToken) {
    return IStableToken(registryContract.getAddressForOrDie(STABLE_REAL_TOKEN_REGISTRY_ID));
  }

  function getValidators() internal view returns (IValidators) {
    return IValidators(registryContract.getAddressForOrDie(VALIDATORS_REGISTRY_ID));
  }
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

  function setPaymentDelegation(address, uint256) external;
  function getPaymentDelegation(address) external view returns (address, uint256);
  function isSigner(address, address, bytes32) external view returns (bool);
}


pragma solidity ^0.5.13;

interface ICeloVersionedContract {
  /**
   * @notice Returns the storage, major, minor, and patch version of the contract.
    * @return Storage version of the contract.
    * @return Major version of the contract.
    * @return Minor version of the contract.
    * @return Patch version of the contract.
   */
  function getVersionNumber() external pure returns (uint256, uint256, uint256, uint256);
}


pragma solidity ^0.5.13;

interface IFeeCurrencyWhitelist {
  function addToken(address) external;
  function getWhitelist() external view returns (address[] memory);
}


pragma solidity ^0.5.13;

interface IFreezer {
  function isFrozen(address) external view returns (bool);
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

interface IGovernance {
  function isVoting(address) external view returns (bool);
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

interface IFederatedAttestations {
  function registerAttestationAsIssuer(bytes32 identifier, address account, uint64 issuedOn)
    external;
  function registerAttestation(
    bytes32 identifier,
    address issuer,
    address account,
    address signer,
    uint64 issuedOn,
    uint8 v,
    bytes32 r,
    bytes32 s
  ) external;
  function revokeAttestation(bytes32 identifier, address issuer, address account) external;
  function batchRevokeAttestations(
    address issuer,
    bytes32[] calldata identifiers,
    address[] calldata accounts
  ) external;

  // view functions
  function lookupAttestations(bytes32 identifier, address[] calldata trustedIssuers)
    external
    view
    returns (
      uint256[] memory,
      address[] memory,
      address[] memory,
      uint64[] memory,
      uint64[] memory
    );
  function lookupIdentifiers(address account, address[] calldata trustedIssuers)
    external
    view
    returns (uint256[] memory, bytes32[] memory);
  function validateAttestationSig(
    bytes32 identifier,
    address issuer,
    address account,
    address signer,
    uint64 issuedOn,
    uint8 v,
    bytes32 r,
    bytes32 s
  ) external view;
  function getUniqueAttestationHash(
    bytes32 identifier,
    address issuer,
    address account,
    address signer,
    uint64 issuedOn
  ) external pure returns (bytes32);
}


pragma solidity ^0.5.13;

interface IRandom {
  function revealAndCommit(bytes32, bytes32, address) external;
  function randomnessBlockRetentionWindow() external view returns (uint256);
  function random() external view returns (bytes32);
  function getBlockRandomness(uint256) external view returns (bytes32);
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
  function getStableBucketCap() external view returns (uint256);
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


/**
 * @dev Wrappers over Solidity's uintXX casting operators with added overflow
 * checks.
 *
 * Downcasting from uint256 in Solidity does not revert on overflow. This can
 * easily result in undesired exploitation or bugs, since developers usually
 * assume that overflows raise errors. `SafeCast` restores this intuition by
 * reverting the transaction when such an operation overflows.
 *
 * Using this library instead of the unchecked operations eliminates an entire
 * class of bugs, so it's recommended to use it always.
 *
 * Can be combined with {SafeMath} to extend it to smaller types, by performing
 * all math on `uint256` and then downcasting.
 *
 * _Available since v2.5.0._
 */
library SafeCast {

    /**
     * @dev Returns the downcasted uint128 from uint256, reverting on
     * overflow (when the input is greater than largest uint128).
     *
     * Counterpart to Solidity's `uint128` operator.
     *
     * Requirements:
     *
     * - input must fit into 128 bits
     */
    function toUint128(uint256 value) internal pure returns (uint128) {
        require(value < 2**128, "SafeCast: value doesn\'t fit in 128 bits");
        return uint128(value);
    }

    /**
     * @dev Returns the downcasted uint64 from uint256, reverting on
     * overflow (when the input is greater than largest uint64).
     *
     * Counterpart to Solidity's `uint64` operator.
     *
     * Requirements:
     *
     * - input must fit into 64 bits
     */
    function toUint64(uint256 value) internal pure returns (uint64) {
        require(value < 2**64, "SafeCast: value doesn\'t fit in 64 bits");
        return uint64(value);
    }

    /**
     * @dev Returns the downcasted uint32 from uint256, reverting on
     * overflow (when the input is greater than largest uint32).
     *
     * Counterpart to Solidity's `uint32` operator.
     *
     * Requirements:
     *
     * - input must fit into 32 bits
     */
    function toUint32(uint256 value) internal pure returns (uint32) {
        require(value < 2**32, "SafeCast: value doesn\'t fit in 32 bits");
        return uint32(value);
    }

    /**
     * @dev Returns the downcasted uint16 from uint256, reverting on
     * overflow (when the input is greater than largest uint16).
     *
     * Counterpart to Solidity's `uint16` operator.
     *
     * Requirements:
     *
     * - input must fit into 16 bits
     */
    function toUint16(uint256 value) internal pure returns (uint16) {
        require(value < 2**16, "SafeCast: value doesn\'t fit in 16 bits");
        return uint16(value);
    }

    /**
     * @dev Returns the downcasted uint8 from uint256, reverting on
     * overflow (when the input is greater than largest uint8).
     *
     * Counterpart to Solidity's `uint8` operator.
     *
     * Requirements:
     *
     * - input must fit into 8 bits.
     */
    function toUint8(uint256 value) internal pure returns (uint8) {
        require(value < 2**8, "SafeCast: value doesn\'t fit in 8 bits");
        return uint8(value);
    }
}