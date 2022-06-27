pragma solidity ^0.5.13;

import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "openzeppelin-solidity/contracts/ownership/Ownable.sol";
import "openzeppelin-solidity/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-solidity/contracts/utils/SafeCast.sol";

import "./interfaces/IAttestations.sol";
import "../common/interfaces/IAccounts.sol";
import "../common/interfaces/ICeloVersionedContract.sol";

import "../common/Initializable.sol";
import "../common/UsingRegistry.sol";
import "../common/Signatures.sol";
import "../common/UsingPrecompiles.sol";
import "../common/libraries/ReentrancyGuard.sol";

/**
 * @title Contract mapping identifiers to accounts
 */
contract Attestations is
  IAttestations,
  ICeloVersionedContract,
  Ownable,
  Initializable,
  UsingRegistry,
  ReentrancyGuard,
  UsingPrecompiles
{
  using SafeMath for uint256;
  using SafeCast for uint256;

  enum AttestationStatus { None, Incomplete, Complete }

  struct Attestation {
    AttestationStatus status;
    // For outstanding attestations, this is the block number of the request.
    // For completed attestations, this is the block number of the attestation completion.
    uint32 blockNumber;
    // The token with which attestation request fees were paid.
    address attestationRequestFeeToken;
  }

  // Stores attestations state for a single (identifier, account address) pair.
  struct AttestedAddress {
    // Total number of requested attestations.
    uint32 requested;
    // Total number of completed attestations.
    uint32 completed;
    // List of selected issuers responsible for attestations. The length of this list
    // might be smaller than `requested` (which represents the total number of requested
    // attestations) if users are not calling `selectIssuers` on unselected requests.
    address[] selectedIssuers;
    // State of each attestation keyed by issuer.
    mapping(address => Attestation) issuedAttestations;
  }

  struct UnselectedRequest {
    // The block at which the attestations were requested.
    uint32 blockNumber;
    // The number of attestations that were requested.
    uint32 attestationsRequested;
    // The token with which attestation request fees were paid in this request.
    address attestationRequestFeeToken;
  }

  struct IdentifierState {
    // All account addresses associated with this identifier.
    address[] accounts;
    // Keeps the state of attestations for account addresses for this identifier.
    mapping(address => AttestedAddress) attestations;
    // Temporarily stores attestation requests for which issuers should be selected by the account.
    mapping(address => UnselectedRequest) unselectedRequests;
  }

  mapping(bytes32 => IdentifierState) identifiers;

  // The duration in blocks in which an attestation can be completed from the block in which the
  // attestation was requested.
  uint256 public attestationExpiryBlocks;

  // The duration to wait until selectIssuers can be called for an attestation request.
  uint256 public selectIssuersWaitBlocks;

  // Limit the maximum number of attestations that can be requested
  uint256 public maxAttestations;

  // The fees that are associated with attestations for a particular token.
  mapping(address => uint256) public attestationRequestFees;

  // Maps a token and attestation issuer to the amount that they're owed.
  mapping(address => mapping(address => uint256)) public pendingWithdrawals;

  // Attestation transfer approvals, keyed by user and keccak(identifier, from, to)
  mapping(address => mapping(bytes32 => bool)) public transferApprovals;

  event AttestationsRequested(
    bytes32 indexed identifier,
    address indexed account,
    uint256 attestationsRequested,
    address attestationRequestFeeToken
  );

  event AttestationIssuerSelected(
    bytes32 indexed identifier,
    address indexed account,
    address indexed issuer,
    address attestationRequestFeeToken
  );

  event AttestationCompleted(
    bytes32 indexed identifier,
    address indexed account,
    address indexed issuer
  );

  event Withdrawal(address indexed account, address indexed token, uint256 amount);
  event AttestationExpiryBlocksSet(uint256 value);
  event AttestationRequestFeeSet(address indexed token, uint256 value);
  event SelectIssuersWaitBlocksSet(uint256 value);
  event MaxAttestationsSet(uint256 value);
  event AttestationsTransferred(
    bytes32 indexed identifier,
    address indexed fromAccount,
    address indexed toAccount
  );
  event TransferApproval(
    address indexed approver,
    bytes32 indexed indentifier,
    address from,
    address to,
    bool approved
  );

  /**
   * @notice Sets initialized == true on implementation contracts
   * @param test Set to true to skip implementation initialization
   */
  constructor(bool test) public Initializable(test) {}

  /**
   * @notice Used in place of the constructor to allow the contract to be upgradable via proxy.
   * @param registryAddress The address of the registry core smart contract.
   * @param _attestationExpiryBlocks The new limit on blocks allowed to come between requesting
   * an attestation and completing it.
   * @param _selectIssuersWaitBlocks The wait period in blocks to call selectIssuers on attestation
   * requests.
   * @param attestationRequestFeeTokens The address of tokens that fees should be payable in.
   * @param attestationRequestFeeValues The corresponding fee values.
   */
  function initialize(
    address registryAddress,
    uint256 _attestationExpiryBlocks,
    uint256 _selectIssuersWaitBlocks,
    uint256 _maxAttestations,
    address[] calldata attestationRequestFeeTokens,
    uint256[] calldata attestationRequestFeeValues
  ) external initializer {
    _transferOwnership(msg.sender);
    setRegistry(registryAddress);
    setAttestationExpiryBlocks(_attestationExpiryBlocks);
    setSelectIssuersWaitBlocks(_selectIssuersWaitBlocks);
    setMaxAttestations(_maxAttestations);

    require(
      attestationRequestFeeTokens.length > 0 &&
        attestationRequestFeeTokens.length == attestationRequestFeeValues.length,
      "attestationRequestFeeTokens specification was invalid"
    );
    for (uint256 i = 0; i < attestationRequestFeeTokens.length; i = i.add(1)) {
      setAttestationRequestFee(attestationRequestFeeTokens[i], attestationRequestFeeValues[i]);
    }
  }

  /**
   * @notice Returns the storage, major, minor, and patch version of the contract.
   * @return The storage, major, minor, and patch version of the contract.
   */
  function getVersionNumber() external pure returns (uint256, uint256, uint256, uint256) {
    return (1, 1, 1, 1);
  }

  /**
   * @notice Commit to the attestation request of a hashed identifier.
   * @param identifier The hash of the identifier to be attested.
   * @param attestationsRequested The number of requested attestations for this request.
   * @param attestationRequestFeeToken The address of the token with which the attestation fee will
   * be paid.
   * @dev Note that if an attestation expires before it is completed, the fee is forfeited. This is
   * to prevent folks from attacking validators by requesting attestations that they do not
   * complete, and to increase the cost of validators attempting to manipulate the attestations
   * protocol.
   */
  function request(
    bytes32 identifier,
    uint256 attestationsRequested,
    address attestationRequestFeeToken
  ) external nonReentrant {
    require(
      attestationRequestFees[attestationRequestFeeToken] > 0,
      "Invalid attestationRequestFeeToken"
    );
    require(
      IERC20(attestationRequestFeeToken).transferFrom(
        msg.sender,
        address(this),
        attestationRequestFees[attestationRequestFeeToken].mul(attestationsRequested)
      ),
      "Transfer of attestation request fees failed"
    );

    require(attestationsRequested > 0, "You have to request at least 1 attestation");
    require(attestationsRequested <= maxAttestations, "Too many attestations requested");

    IdentifierState storage state = identifiers[identifier];

    require(
      state.unselectedRequests[msg.sender].blockNumber == 0 ||
        isAttestationExpired(state.unselectedRequests[msg.sender].blockNumber) ||
        !isAttestationRequestSelectable(state.unselectedRequests[msg.sender].blockNumber),
      "There exists an unexpired, unselected attestation request"
    );

    state.unselectedRequests[msg.sender].blockNumber = block.number.toUint32();
    state.unselectedRequests[msg.sender].attestationsRequested = attestationsRequested.toUint32();
    state.unselectedRequests[msg.sender].attestationRequestFeeToken = attestationRequestFeeToken;

    state.attestations[msg.sender].requested = uint256(state.attestations[msg.sender].requested)
      .add(attestationsRequested)
      .toUint32();

    emit AttestationsRequested(
      identifier,
      msg.sender,
      attestationsRequested,
      attestationRequestFeeToken
    );
  }

  /**
   * @notice Selects the issuers for the most recent attestation request.
   * @param identifier The hash of the identifier to be attested.
   */
  function selectIssuers(bytes32 identifier) external {
    IdentifierState storage state = identifiers[identifier];

    require(
      state.unselectedRequests[msg.sender].blockNumber > 0,
      "No unselected attestation request to select issuers for"
    );

    require(
      !isAttestationExpired(state.unselectedRequests[msg.sender].blockNumber),
      "The attestation request has expired"
    );

    addIncompleteAttestations(identifier);
    delete state.unselectedRequests[msg.sender];
  }

  /**
   * @notice Submit the secret message sent by the issuer to complete the attestation request.
   * @param identifier The hash of the identifier for this attestation.
   * @param v The recovery id of the incoming ECDSA signature.
   * @param r Output value r of the ECDSA signature.
   * @param s Output value s of the ECDSA signature.
   * @dev Throws if there is no matching outstanding attestation request.
   * @dev Throws if the attestation window has passed.
   */
  function complete(bytes32 identifier, uint8 v, bytes32 r, bytes32 s) external {
    address issuer = validateAttestationCode(identifier, msg.sender, v, r, s);

    Attestation storage attestation = identifiers[identifier].attestations[msg.sender]
      .issuedAttestations[issuer];

    address token = attestation.attestationRequestFeeToken;

    // solhint-disable-next-line not-rely-on-time
    attestation.blockNumber = block.number.toUint32();
    attestation.status = AttestationStatus.Complete;
    delete attestation.attestationRequestFeeToken;
    AttestedAddress storage attestedAddress = identifiers[identifier].attestations[msg.sender];
    require(
      attestedAddress.completed < attestedAddress.completed + 1,
      "SafeMath32 integer overflow"
    );
    attestedAddress.completed = attestedAddress.completed + 1;

    pendingWithdrawals[token][issuer] = pendingWithdrawals[token][issuer].add(
      attestationRequestFees[token]
    );

    IdentifierState storage state = identifiers[identifier];
    if (identifiers[identifier].attestations[msg.sender].completed == 1) {
      state.accounts.push(msg.sender);
    }

    emit AttestationCompleted(identifier, msg.sender, issuer);
  }

  /**
   * @notice Revokes an account for an identifier.
   * @param identifier The identifier for which to revoke.
   * @param index The index of the account in the accounts array.
   */
  function revoke(bytes32 identifier, uint256 index) external {
    uint256 numAccounts = identifiers[identifier].accounts.length;
    require(index < numAccounts, "Index is invalid");
    require(
      msg.sender == identifiers[identifier].accounts[index],
      "Index does not match msg.sender"
    );

    uint256 newNumAccounts = numAccounts.sub(1);
    if (index != newNumAccounts) {
      identifiers[identifier].accounts[index] = identifiers[identifier].accounts[newNumAccounts];
    }
    identifiers[identifier].accounts[newNumAccounts] = address(0x0);
    identifiers[identifier].accounts.length = identifiers[identifier].accounts.length.sub(1);
  }

  /**
   * @notice Allows issuers to withdraw accumulated attestation rewards.
   * @param token The address of the token that will be withdrawn.
   * @dev Throws if msg.sender does not have any rewards to withdraw.
   */
  function withdraw(address token) external {
    address issuer = getAccounts().attestationSignerToAccount(msg.sender);
    uint256 value = pendingWithdrawals[token][issuer];
    require(value > 0, "value was negative/zero");
    pendingWithdrawals[token][issuer] = 0;
    require(IERC20(token).transfer(issuer, value), "token transfer failed");
    emit Withdrawal(issuer, token, value);
  }

  /**
   * @notice Returns the unselected attestation request for an identifier/account pair, if any.
   * @param identifier Hash of the identifier.
   * @param account Address of the account.
   * @return [
   *           Block number at which was requested,
   *           Number of unselected requests,
   *           Address of the token with which this attestation request was paid for
   *         ]
   */
  function getUnselectedRequest(bytes32 identifier, address account)
    external
    view
    returns (uint32, uint32, address)
  {
    return (
      identifiers[identifier].unselectedRequests[account].blockNumber,
      identifiers[identifier].unselectedRequests[account].attestationsRequested,
      identifiers[identifier].unselectedRequests[account].attestationRequestFeeToken
    );
  }

  /**
   * @notice Returns selected attestation issuers for a identifier/account pair.
   * @param identifier Hash of the identifier.
   * @param account Address of the account.
   * @return Addresses of the selected attestation issuers.
   */
  function getAttestationIssuers(bytes32 identifier, address account)
    external
    view
    returns (address[] memory)
  {
    return identifiers[identifier].attestations[account].selectedIssuers;
  }

  /**
   * @notice Returns attestation stats for a identifier/account pair.
   * @param identifier Hash of the identifier.
   * @param account Address of the account.
   * @return [Number of completed attestations, Number of total requested attestations]
   */
  function getAttestationStats(bytes32 identifier, address account)
    external
    view
    returns (uint32, uint32)
  {
    return (
      identifiers[identifier].attestations[account].completed,
      identifiers[identifier].attestations[account].requested
    );
  }

  /**
   * @notice Batch lookup function to determine attestation stats for a list of identifiers.
   * @param identifiersToLookup Array of n identifiers.
   * @return [0] Array of number of matching accounts per identifier.
   * @return [1] Array of sum([0]) matching walletAddresses.
   * @return [2] Array of sum([0]) numbers indicating the completions for each account.
   * @return [3] Array of sum([0]) numbers indicating the total number of requested
                 attestations for each account.
   */
  function batchGetAttestationStats(bytes32[] calldata identifiersToLookup)
    external
    view
    returns (uint256[] memory, address[] memory, uint64[] memory, uint64[] memory)
  {
    require(identifiersToLookup.length > 0, "You have to pass at least one identifier");

    uint256[] memory matches;
    address[] memory addresses;

    (matches, addresses) = batchlookupAccountsForIdentifier(identifiersToLookup);

    uint64[] memory completed = new uint64[](addresses.length);
    uint64[] memory total = new uint64[](addresses.length);

    uint256 currentIndex = 0;
    for (uint256 i = 0; i < identifiersToLookup.length; i = i.add(1)) {
      address[] memory addrs = identifiers[identifiersToLookup[i]].accounts;
      for (uint256 matchIndex = 0; matchIndex < matches[i]; matchIndex = matchIndex.add(1)) {
        addresses[currentIndex] = getAccounts().getWalletAddress(addrs[matchIndex]);
        completed[currentIndex] = identifiers[identifiersToLookup[i]]
          .attestations[addrs[matchIndex]]
          .completed;
        total[currentIndex] = identifiers[identifiersToLookup[i]].attestations[addrs[matchIndex]]
          .requested;
        currentIndex = currentIndex.add(1);
      }
    }

    return (matches, addresses, completed, total);
  }

  /**
   * @notice Returns the state of a specific attestation.
   * @param identifier Hash of the identifier.
   * @param account Address of the account.
   * @param issuer Address of the issuer.
   * @return [
   *           Status of the attestation,
   *           Block number of request/completion the attestation,
   *           Address of the token with which this attestation request was paid for
   *         ]
   */
  function getAttestationState(bytes32 identifier, address account, address issuer)
    external
    view
    returns (uint8, uint32, address)
  {
    Attestation storage attestation = identifiers[identifier].attestations[account]
      .issuedAttestations[issuer];
    return (
      uint8(attestation.status),
      attestation.blockNumber,
      attestation.attestationRequestFeeToken
    );

  }

  /**
    * @notice Returns the state of all attestations that are completable
    * @param identifier Hash of the identifier.
    * @param account Address of the account.
    * @return ( blockNumbers[] - Block number of request/completion the attestation,
    *           issuers[] - Address of the issuer,
    *           stringLengths[] - The length of each metadataURL string for each issuer,
    *           stringData - All strings concatenated
    *         )
    */
  function getCompletableAttestations(bytes32 identifier, address account)
    external
    view
    returns (uint32[] memory, address[] memory, uint256[] memory, bytes memory)
  {
    AttestedAddress storage state = identifiers[identifier].attestations[account];
    address[] storage issuers = state.selectedIssuers;

    uint256 num = 0;
    for (uint256 i = 0; i < issuers.length; i = i.add(1)) {
      if (isAttestationCompletable(state.issuedAttestations[issuers[i]])) {
        num = num.add(1);
      }
    }

    uint32[] memory blockNumbers = new uint32[](num);
    address[] memory completableIssuers = new address[](num);

    uint256 pointer = 0;
    for (uint256 i = 0; i < issuers.length; i = i.add(1)) {
      if (isAttestationCompletable(state.issuedAttestations[issuers[i]])) {
        blockNumbers[pointer] = state.issuedAttestations[issuers[i]].blockNumber;
        completableIssuers[pointer] = issuers[i];
        pointer = pointer.add(1);
      }
    }

    uint256[] memory stringLengths;
    bytes memory stringData;
    (stringLengths, stringData) = getAccounts().batchGetMetadataURL(completableIssuers);
    return (blockNumbers, completableIssuers, stringLengths, stringData);
  }

  /**
   * @notice Returns the fee set for a particular token.
   * @param token Address of the attestationRequestFeeToken.
   * @return The fee.
   */
  function getAttestationRequestFee(address token) external view returns (uint256) {
    return attestationRequestFees[token];
  }

  /**
   * @notice Updates the fee  for a particular token.
   * @param token The address of the attestationRequestFeeToken.
   * @param fee The fee in 'token' that is required for each attestation.
   */
  function setAttestationRequestFee(address token, uint256 fee) public onlyOwner {
    require(fee > 0, "You have to specify a fee greater than 0");
    attestationRequestFees[token] = fee;
    emit AttestationRequestFeeSet(token, fee);
  }

  /**
   * @notice Updates 'attestationExpiryBlocks'.
   * @param _attestationExpiryBlocks The new limit on blocks allowed to come between requesting
   * an attestation and completing it.
   */
  function setAttestationExpiryBlocks(uint256 _attestationExpiryBlocks) public onlyOwner {
    require(_attestationExpiryBlocks > 0, "attestationExpiryBlocks has to be greater than 0");
    attestationExpiryBlocks = _attestationExpiryBlocks;
    emit AttestationExpiryBlocksSet(_attestationExpiryBlocks);
  }

  /**
   * @notice Updates 'selectIssuersWaitBlocks'.
   * @param _selectIssuersWaitBlocks The wait period in blocks to call selectIssuers on attestation
   *                                 requests.
   */
  function setSelectIssuersWaitBlocks(uint256 _selectIssuersWaitBlocks) public onlyOwner {
    require(_selectIssuersWaitBlocks > 0, "selectIssuersWaitBlocks has to be greater than 0");
    selectIssuersWaitBlocks = _selectIssuersWaitBlocks;
    emit SelectIssuersWaitBlocksSet(_selectIssuersWaitBlocks);
  }

  /**
   * @notice Updates 'maxAttestations'.
   * @param _maxAttestations Maximum number of attestations that can be requested.
   */
  function setMaxAttestations(uint256 _maxAttestations) public onlyOwner {
    require(_maxAttestations > 0, "maxAttestations has to be greater than 0");
    maxAttestations = _maxAttestations;
    emit MaxAttestationsSet(_maxAttestations);
  }

  /**
   * @notice Query 'maxAttestations'
   * @return Maximum number of attestations that can be requested.
   */
  function getMaxAttestations() external view returns (uint256) {
    return maxAttestations;
  }

  /**
   * @notice Validates the given attestation code.
   * @param identifier The hash of the identifier to be attested.
   * @param account Address of the account. 
   * @param v The recovery id of the incoming ECDSA signature.
   * @param r Output value r of the ECDSA signature.
   * @param s Output value s of the ECDSA signature.
   * @return The issuer of the corresponding attestation.
   * @dev Throws if there is no matching outstanding attestation request.
   * @dev Throws if the attestation window has passed.
   */
  function validateAttestationCode(
    bytes32 identifier,
    address account,
    uint8 v,
    bytes32 r,
    bytes32 s
  ) public view returns (address) {
    bytes32 codehash = keccak256(abi.encodePacked(identifier, account));
    address signer = Signatures.getSignerOfMessageHash(codehash, v, r, s);
    address issuer = getAccounts().attestationSignerToAccount(signer);

    Attestation storage attestation = identifiers[identifier].attestations[account]
      .issuedAttestations[issuer];

    require(
      attestation.status == AttestationStatus.Incomplete,
      "Attestation code does not match any outstanding attestation"
    );
    require(!isAttestationExpired(attestation.blockNumber), "Attestation timed out");

    return issuer;
  }

  function lookupAccountsForIdentifier(bytes32 identifier)
    external
    view
    returns (address[] memory)
  {
    return identifiers[identifier].accounts;
  }

  /**
   * @notice Require that a given identifier/address pair has
   * requested a specific number of attestations.
   * @param identifier Hash of the identifier.
   * @param account Address of the account.
   * @param expected Number of expected attestations
   * @dev It can be used when batching meta-transactions to validate
   * attestation are requested as expected in untrusted scenarios
   */
  function requireNAttestationsRequested(bytes32 identifier, address account, uint32 expected)
    external
    view
  {
    uint256 requested = identifiers[identifier].attestations[account].requested;
    require(requested == expected, "requested attestations does not match expected");
  }

  /**
   * @notice Helper function for batchGetAttestationStats to calculate the
             total number of addresses that have >0 complete attestations for the identifiers.
   * @param identifiersToLookup Array of n identifiers.
   * @return Array of n numbers that indicate the number of matching addresses per identifier
   *         and array of addresses preallocated for total number of matches.
   */
  function batchlookupAccountsForIdentifier(bytes32[] memory identifiersToLookup)
    internal
    view
    returns (uint256[] memory, address[] memory)
  {
    require(identifiersToLookup.length > 0, "You have to pass at least one identifier");
    uint256 totalAddresses = 0;
    uint256[] memory matches = new uint256[](identifiersToLookup.length);

    for (uint256 i = 0; i < identifiersToLookup.length; i = i.add(1)) {
      uint256 count = identifiers[identifiersToLookup[i]].accounts.length;

      totalAddresses = totalAddresses.add(count);
      matches[i] = count;
    }

    return (matches, new address[](totalAddresses));
  }

  /**
   * @notice Adds additional attestations given the current randomness.
   * @param identifier The hash of the identifier to be attested.
   */
  function addIncompleteAttestations(bytes32 identifier) internal {
    AttestedAddress storage state = identifiers[identifier].attestations[msg.sender];
    UnselectedRequest storage unselectedRequest = identifiers[identifier].unselectedRequests[msg
      .sender];

    bytes32 seed = getRandom().getBlockRandomness(
      uint256(unselectedRequest.blockNumber).add(selectIssuersWaitBlocks)
    );
    IAccounts accounts = getAccounts();
    uint256 issuersLength = numberValidatorsInCurrentSet();
    uint256[] memory issuers = new uint256[](issuersLength);
    for (uint256 i = 0; i < issuersLength; i = i.add(1)) issuers[i] = i;

    require(unselectedRequest.attestationsRequested <= issuersLength, "not enough issuers");

    uint256 currentIndex = 0;

    // The length of the list (variable issuersLength) is decremented in each round,
    // so the loop always terminates
    while (currentIndex < unselectedRequest.attestationsRequested) {
      require(issuersLength > 0, "not enough issuers");
      seed = keccak256(abi.encodePacked(seed));
      uint256 idx = uint256(seed) % issuersLength;
      address signer = validatorSignerAddressFromCurrentSet(issuers[idx]);
      address issuer = accounts.signerToAccount(signer);

      Attestation storage attestation = state.issuedAttestations[issuer];

      if (
        attestation.status == AttestationStatus.None &&
        accounts.hasAuthorizedAttestationSigner(issuer)
      ) {
        currentIndex = currentIndex.add(1);
        attestation.status = AttestationStatus.Incomplete;
        attestation.blockNumber = unselectedRequest.blockNumber;
        attestation.attestationRequestFeeToken = unselectedRequest.attestationRequestFeeToken;
        state.selectedIssuers.push(issuer);

        emit AttestationIssuerSelected(
          identifier,
          msg.sender,
          issuer,
          unselectedRequest.attestationRequestFeeToken
        );
      }

      // Remove the validator that was selected from the list,
      // by replacing it by the last element in the list
      issuersLength = issuersLength.sub(1);
      issuers[idx] = issuers[issuersLength];
    }
  }

  /**
   * @notice Update the approval status of allowing an attestation identifier
   * mapping to be transfered from an address to another.  The "to" or "from"
   * addresses must both approve.  If the other has already approved, then the transfer
   * is executed.
   * @param identifier The identifier for this attestation.
   * @param index The index of the account in the accounts array.
   * @param from The current attestation address to which the identifier is mapped.
   * @param to The new address to map to identifier.
   * @param status The approval status
   */
  function approveTransfer(bytes32 identifier, uint256 index, address from, address to, bool status)
    external
  {
    require(
      msg.sender == from || msg.sender == to,
      "Approver must be sender or recipient of transfer"
    );
    bytes32 key = keccak256(abi.encodePacked(identifier, from, to));
    address other = msg.sender == from ? to : from;
    if (status && transferApprovals[other][key]) {
      _transfer(identifier, index, from, to);
      transferApprovals[other][key] = false;
    } else {
      transferApprovals[msg.sender][key] = status;
      emit TransferApproval(msg.sender, identifier, from, to, status);
    }
  }

  /**
   * @notice Transfer an attestation identifier mapping from the sender address to a
   * replacement address.
   * @param identifier The identifier for this attestation.
   * @param index The index of the account in the accounts array.
   * @param from The current attestation address to which the identifier is mapped.
   * @param to The address to replace the sender address in the indentifier mapping.
   * @dev Throws if index is out of bound for account array.
   * @dev Throws if `from` is not in the account array at the given index.
   * @dev Throws if `to` already has attestations
   */
  function _transfer(bytes32 identifier, uint256 index, address from, address to) internal {
    uint256 numAccounts = identifiers[identifier].accounts.length;
    require(index < numAccounts, "Index is invalid");
    require(from == identifiers[identifier].accounts[index], "Index does not match from address");
    require(
      identifiers[identifier].attestations[to].requested == 0,
      "Address tranferring to has already requested attestations"
    );

    identifiers[identifier].accounts[index] = to;
    identifiers[identifier].attestations[to] = identifiers[identifier].attestations[from];
    identifiers[identifier].unselectedRequests[to] = identifiers[identifier]
      .unselectedRequests[from];
    delete identifiers[identifier].attestations[from];
    delete identifiers[identifier].unselectedRequests[from];
    emit AttestationsTransferred(identifier, from, to);
  }

  function isAttestationExpired(uint32 attestationRequestBlock) internal view returns (bool) {
    return block.number >= uint256(attestationRequestBlock).add(attestationExpiryBlocks);
  }

  function isAttestationCompletable(Attestation storage attestation) internal view returns (bool) {
    return (attestation.status == AttestationStatus.Incomplete &&
      !isAttestationExpired(attestation.blockNumber));
  }

  function isAttestationRequestSelectable(uint256 attestationRequestBlock)
    internal
    view
    returns (bool)
  {
    return block.number < attestationRequestBlock.add(getRandom().randomnessBlockRetentionWindow());
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

import "openzeppelin-solidity/contracts/cryptography/ECDSA.sol";

library Signatures {
  /**
   * @notice Returns the storage, major, minor, and patch version of the contract.
   * @return The storage, major, minor, and patch version of the contract.
   */
  function getVersionNumber() external pure returns (uint256, uint256, uint256, uint256) {
    return (1, 1, 2, 0);
  }

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