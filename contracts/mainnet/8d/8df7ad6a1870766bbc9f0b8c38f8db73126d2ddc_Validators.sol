pragma solidity ^0.5.13;

import "openzeppelin-solidity/contracts/math/Math.sol";
import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "openzeppelin-solidity/contracts/ownership/Ownable.sol";
import "solidity-bytes-utils/contracts/BytesLib.sol";

import "./interfaces/IValidators.sol";

import "../common/CalledByVm.sol";
import "../common/Initializable.sol";
import "../common/FixidityLib.sol";
import "../common/linkedlists/AddressLinkedList.sol";
import "../common/UsingRegistry.sol";
import "../common/UsingPrecompiles.sol";
import "../common/interfaces/ICeloVersionedContract.sol";
import "../common/libraries/ReentrancyGuard.sol";

/**
 * @title A contract for registering and electing Validator Groups and Validators.
 */
contract Validators is
  IValidators,
  ICeloVersionedContract,
  Ownable,
  ReentrancyGuard,
  Initializable,
  UsingRegistry,
  UsingPrecompiles,
  CalledByVm
{
  using FixidityLib for FixidityLib.Fraction;
  using AddressLinkedList for LinkedList.List;
  using SafeMath for uint256;
  using BytesLib for bytes;

  // For Validators, these requirements must be met in order to:
  //   1. Register a validator
  //   2. Affiliate with and be added to a group
  //   3. Receive epoch payments (note that the group must meet the group requirements as well)
  // Accounts may de-register their Validator `duration` seconds after they were last a member of a
  // group, after which no restrictions on Locked Gold will apply to the account.
  //
  // For Validator Groups, these requirements must be met in order to:
  //   1. Register a group
  //   2. Add a member to a group
  //   3. Receive epoch payments
  // Note that for groups, the requirement value is multiplied by the number of members, and is
  // enforced for `duration` seconds after the group last had that number of members.
  // Accounts may de-register their Group `duration` seconds after they were last non-empty, after
  // which no restrictions on Locked Gold will apply to the account.
  struct LockedGoldRequirements {
    uint256 value;
    // In seconds.
    uint256 duration;
  }

  struct ValidatorGroup {
    bool exists;
    LinkedList.List members;
    FixidityLib.Fraction commission;
    FixidityLib.Fraction nextCommission;
    uint256 nextCommissionBlock;
    // sizeHistory[i] contains the last time the group contained i members.
    uint256[] sizeHistory;
    SlashingInfo slashInfo;
  }

  // Stores the epoch number at which a validator joined a particular group.
  struct MembershipHistoryEntry {
    uint256 epochNumber;
    address group;
  }

  // Stores the per-epoch membership history of a validator, used to determine which group
  // commission should be paid to at the end of an epoch.
  // Stores a timestamp of the last time the validator was removed from a group, used to determine
  // whether or not a group can de-register.
  struct MembershipHistory {
    // The key to the most recent entry in the entries mapping.
    uint256 tail;
    // The number of entries in this validators membership history.
    uint256 numEntries;
    mapping(uint256 => MembershipHistoryEntry) entries;
    uint256 lastRemovedFromGroupTimestamp;
  }

  struct SlashingInfo {
    FixidityLib.Fraction multiplier;
    uint256 lastSlashed;
  }

  struct PublicKeys {
    bytes ecdsa;
    bytes bls;
  }

  struct Validator {
    PublicKeys publicKeys;
    address affiliation;
    FixidityLib.Fraction score;
    MembershipHistory membershipHistory;
  }

  // Parameters that govern the calculation of validator's score.
  struct ValidatorScoreParameters {
    uint256 exponent;
    FixidityLib.Fraction adjustmentSpeed;
  }

  mapping(address => ValidatorGroup) private groups;
  mapping(address => Validator) private validators;
  address[] private registeredGroups;
  address[] private registeredValidators;
  LockedGoldRequirements public validatorLockedGoldRequirements;
  LockedGoldRequirements public groupLockedGoldRequirements;
  ValidatorScoreParameters private validatorScoreParameters;
  uint256 public membershipHistoryLength;
  uint256 public maxGroupSize;
  // The number of blocks to delay a ValidatorGroup's commission update
  uint256 public commissionUpdateDelay;
  uint256 public slashingMultiplierResetPeriod;
  uint256 public downtimeGracePeriod;

  event MaxGroupSizeSet(uint256 size);
  event CommissionUpdateDelaySet(uint256 delay);
  event ValidatorScoreParametersSet(uint256 exponent, uint256 adjustmentSpeed);
  event GroupLockedGoldRequirementsSet(uint256 value, uint256 duration);
  event ValidatorLockedGoldRequirementsSet(uint256 value, uint256 duration);
  event MembershipHistoryLengthSet(uint256 length);
  event ValidatorRegistered(address indexed validator);
  event ValidatorDeregistered(address indexed validator);
  event ValidatorAffiliated(address indexed validator, address indexed group);
  event ValidatorDeaffiliated(address indexed validator, address indexed group);
  event ValidatorEcdsaPublicKeyUpdated(address indexed validator, bytes ecdsaPublicKey);
  event ValidatorBlsPublicKeyUpdated(address indexed validator, bytes blsPublicKey);
  event ValidatorScoreUpdated(address indexed validator, uint256 score, uint256 epochScore);
  event ValidatorGroupRegistered(address indexed group, uint256 commission);
  event ValidatorGroupDeregistered(address indexed group);
  event ValidatorGroupMemberAdded(address indexed group, address indexed validator);
  event ValidatorGroupMemberRemoved(address indexed group, address indexed validator);
  event ValidatorGroupMemberReordered(address indexed group, address indexed validator);
  event ValidatorGroupCommissionUpdateQueued(
    address indexed group,
    uint256 commission,
    uint256 activationBlock
  );
  event ValidatorGroupCommissionUpdated(address indexed group, uint256 commission);
  event ValidatorEpochPaymentDistributed(
    address indexed validator,
    uint256 validatorPayment,
    address indexed group,
    uint256 groupPayment
  );

  modifier onlySlasher() {
    require(getLockedGold().isSlasher(msg.sender), "Only registered slasher can call");
    _;
  }

  /**
   * @notice Returns the storage, major, minor, and patch version of the contract.
   * @return The storage, major, minor, and patch version of the contract.
   */
  function getVersionNumber() external pure returns (uint256, uint256, uint256, uint256) {
    return (1, 2, 0, 2);
  }

  /**
   * @notice Sets initialized == true on implementation contracts
   * @param test Set to true to skip implementation initialization
   */
  constructor(bool test) public Initializable(test) {}

  /**
   * @notice Used in place of the constructor to allow the contract to be upgradable via proxy.
   * @param registryAddress The address of the registry core smart contract.
   * @param groupRequirementValue The Locked Gold requirement amount for groups.
   * @param groupRequirementDuration The Locked Gold requirement duration for groups.
   * @param validatorRequirementValue The Locked Gold requirement amount for validators.
   * @param validatorRequirementDuration The Locked Gold requirement duration for validators.
   * @param validatorScoreExponent The exponent used in calculating validator scores.
   * @param validatorScoreAdjustmentSpeed The speed at which validator scores are adjusted.
   * @param _membershipHistoryLength The max number of entries for validator membership history.
   * @param _maxGroupSize The maximum group size.
   * @param _commissionUpdateDelay The number of blocks to delay a ValidatorGroup's commission
   * update.
   * @dev Should be called only once.
   */
  function initialize(
    address registryAddress,
    uint256 groupRequirementValue,
    uint256 groupRequirementDuration,
    uint256 validatorRequirementValue,
    uint256 validatorRequirementDuration,
    uint256 validatorScoreExponent,
    uint256 validatorScoreAdjustmentSpeed,
    uint256 _membershipHistoryLength,
    uint256 _slashingMultiplierResetPeriod,
    uint256 _maxGroupSize,
    uint256 _commissionUpdateDelay,
    uint256 _downtimeGracePeriod
  ) external initializer {
    _transferOwnership(msg.sender);
    setRegistry(registryAddress);
    setGroupLockedGoldRequirements(groupRequirementValue, groupRequirementDuration);
    setValidatorLockedGoldRequirements(validatorRequirementValue, validatorRequirementDuration);
    setValidatorScoreParameters(validatorScoreExponent, validatorScoreAdjustmentSpeed);
    setMaxGroupSize(_maxGroupSize);
    setCommissionUpdateDelay(_commissionUpdateDelay);
    setMembershipHistoryLength(_membershipHistoryLength);
    setSlashingMultiplierResetPeriod(_slashingMultiplierResetPeriod);
    setDowntimeGracePeriod(_downtimeGracePeriod);
  }

  /**
   * @notice Updates the block delay for a ValidatorGroup's commission udpdate
   * @param delay Number of blocks to delay the update
   */
  function setCommissionUpdateDelay(uint256 delay) public onlyOwner {
    require(delay != commissionUpdateDelay, "commission update delay not changed");
    commissionUpdateDelay = delay;
    emit CommissionUpdateDelaySet(delay);
  }

  /**
   * @notice Updates the maximum number of members a group can have.
   * @param size The maximum group size.
   * @return True upon success.
   */
  function setMaxGroupSize(uint256 size) public onlyOwner returns (bool) {
    require(0 < size, "Max group size cannot be zero");
    require(size != maxGroupSize, "Max group size not changed");
    maxGroupSize = size;
    emit MaxGroupSizeSet(size);
    return true;
  }

  /**
   * @notice Updates the number of validator group membership entries to store.
   * @param length The number of validator group membership entries to store.
   * @return True upon success.
   */
  function setMembershipHistoryLength(uint256 length) public onlyOwner returns (bool) {
    require(0 < length, "Membership history length cannot be zero");
    require(length != membershipHistoryLength, "Membership history length not changed");
    membershipHistoryLength = length;
    emit MembershipHistoryLengthSet(length);
    return true;
  }

  /**
   * @notice Updates the validator score parameters.
   * @param exponent The exponent used in calculating the score.
   * @param adjustmentSpeed The speed at which the score is adjusted.
   * @return True upon success.
   */
  function setValidatorScoreParameters(uint256 exponent, uint256 adjustmentSpeed)
    public
    onlyOwner
    returns (bool)
  {
    require(
      adjustmentSpeed <= FixidityLib.fixed1().unwrap(),
      "Adjustment speed cannot be larger than 1"
    );
    require(
      exponent != validatorScoreParameters.exponent ||
        !FixidityLib.wrap(adjustmentSpeed).equals(validatorScoreParameters.adjustmentSpeed),
      "Adjustment speed and exponent not changed"
    );
    validatorScoreParameters = ValidatorScoreParameters(
      exponent,
      FixidityLib.wrap(adjustmentSpeed)
    );
    emit ValidatorScoreParametersSet(exponent, adjustmentSpeed);
    return true;
  }

  /**
   * @notice Returns the maximum number of members a group can add.
   * @return The maximum number of members a group can add.
   */
  function getMaxGroupSize() external view returns (uint256) {
    return maxGroupSize;
  }

  /**
   * @notice Returns the block delay for a ValidatorGroup's commission udpdate.
   * @return The block delay for a ValidatorGroup's commission udpdate.
   */
  function getCommissionUpdateDelay() external view returns (uint256) {
    return commissionUpdateDelay;
  }

  /**
   * @notice Updates the Locked Gold requirements for Validator Groups.
   * @param value The per-member amount of Locked Gold required.
   * @param duration The time (in seconds) that these requirements persist for.
   * @return True upon success.
   */
  function setGroupLockedGoldRequirements(uint256 value, uint256 duration)
    public
    onlyOwner
    returns (bool)
  {
    LockedGoldRequirements storage requirements = groupLockedGoldRequirements;
    require(
      value != requirements.value || duration != requirements.duration,
      "Group requirements not changed"
    );
    groupLockedGoldRequirements = LockedGoldRequirements(value, duration);
    emit GroupLockedGoldRequirementsSet(value, duration);
    return true;
  }

  /**
   * @notice Updates the Locked Gold requirements for Validators.
   * @param value The amount of Locked Gold required.
   * @param duration The time (in seconds) that these requirements persist for.
   * @return True upon success.
   */
  function setValidatorLockedGoldRequirements(uint256 value, uint256 duration)
    public
    onlyOwner
    returns (bool)
  {
    LockedGoldRequirements storage requirements = validatorLockedGoldRequirements;
    require(
      value != requirements.value || duration != requirements.duration,
      "Validator requirements not changed"
    );
    validatorLockedGoldRequirements = LockedGoldRequirements(value, duration);
    emit ValidatorLockedGoldRequirementsSet(value, duration);
    return true;
  }

  /**
   * @notice Registers a validator unaffiliated with any validator group.
   * @param ecdsaPublicKey The ECDSA public key that the validator is using for consensus, should
   *   match the validator signer. 64 bytes.
   * @param blsPublicKey The BLS public key that the validator is using for consensus, should pass
   *   proof of possession. 96 bytes.
   * @param blsPop The BLS public key proof-of-possession, which consists of a signature on the
   *   account address. 48 bytes.
   * @return True upon success.
   * @dev Fails if the account is already a validator or validator group.
   * @dev Fails if the account does not have sufficient Locked Gold.
   */
  function registerValidator(
    bytes calldata ecdsaPublicKey,
    bytes calldata blsPublicKey,
    bytes calldata blsPop
  ) external nonReentrant returns (bool) {
    address account = getAccounts().validatorSignerToAccount(msg.sender);
    require(!isValidator(account) && !isValidatorGroup(account), "Already registered");
    uint256 lockedGoldBalance = getLockedGold().getAccountTotalLockedGold(account);
    require(lockedGoldBalance >= validatorLockedGoldRequirements.value, "Deposit too small");
    Validator storage validator = validators[account];
    address signer = getAccounts().getValidatorSigner(account);
    require(
      _updateEcdsaPublicKey(validator, account, signer, ecdsaPublicKey),
      "Error updating ECDSA public key"
    );
    require(
      _updateBlsPublicKey(validator, account, blsPublicKey, blsPop),
      "Error updating BLS public key"
    );
    registeredValidators.push(account);
    updateMembershipHistory(account, address(0));
    emit ValidatorRegistered(account);
    return true;
  }

  /**
   * @notice Returns the parameters that govern how a validator's score is calculated.
   * @return The parameters that goven how a validator's score is calculated.
   */
  function getValidatorScoreParameters() external view returns (uint256, uint256) {
    return (validatorScoreParameters.exponent, validatorScoreParameters.adjustmentSpeed.unwrap());
  }

  /**
   * @notice Returns the group membership history of a validator.
   * @param account The validator whose membership history to return.
   * @return The group membership history of a validator.
   */
  function getMembershipHistory(address account)
    external
    view
    returns (uint256[] memory, address[] memory, uint256, uint256)
  {
    MembershipHistory storage history = validators[account].membershipHistory;
    uint256[] memory epochs = new uint256[](history.numEntries);
    address[] memory membershipGroups = new address[](history.numEntries);
    for (uint256 i = 0; i < history.numEntries; i = i.add(1)) {
      uint256 index = history.tail.add(i);
      epochs[i] = history.entries[index].epochNumber;
      membershipGroups[i] = history.entries[index].group;
    }
    return (epochs, membershipGroups, history.lastRemovedFromGroupTimestamp, history.tail);
  }

  /**
   * @notice Calculates the validator score for an epoch from the uptime value for the epoch.
   * @param uptime The Fixidity representation of the validator's uptime, between 0 and 1.
   * @dev epoch_score = uptime ** exponent
   * @return Fixidity representation of the epoch score between 0 and 1.
   */
  function calculateEpochScore(uint256 uptime) public view returns (uint256) {
    require(uptime <= FixidityLib.fixed1().unwrap(), "Uptime cannot be larger than one");
    uint256 numerator;
    uint256 denominator;
    uptime = Math.min(uptime.add(downtimeGracePeriod), FixidityLib.fixed1().unwrap());
    (numerator, denominator) = fractionMulExp(
      FixidityLib.fixed1().unwrap(),
      FixidityLib.fixed1().unwrap(),
      uptime,
      FixidityLib.fixed1().unwrap(),
      validatorScoreParameters.exponent,
      18
    );
    return FixidityLib.newFixedFraction(numerator, denominator).unwrap();
  }

  /**
   * @notice Calculates the aggregate score of a group for an epoch from individual uptimes.
   * @param uptimes Array of Fixidity representations of the validators' uptimes, between 0 and 1.
   * @dev group_score = average(uptimes ** exponent)
   * @return Fixidity representation of the group epoch score between 0 and 1.
   */
  function calculateGroupEpochScore(uint256[] calldata uptimes) external view returns (uint256) {
    require(uptimes.length > 0, "Uptime array empty");
    require(uptimes.length <= maxGroupSize, "Uptime array larger than maximum group size");
    FixidityLib.Fraction memory sum;
    for (uint256 i = 0; i < uptimes.length; i = i.add(1)) {
      sum = sum.add(FixidityLib.wrap(calculateEpochScore(uptimes[i])));
    }
    return sum.divide(FixidityLib.newFixed(uptimes.length)).unwrap();
  }

  /**
   * @notice Updates a validator's score based on its uptime for the epoch.
   * @param signer The validator signer of the validator account whose score needs updating.
   * @param uptime The Fixidity representation of the validator's uptime, between 0 and 1.
   * @return True upon success.
   */
  function updateValidatorScoreFromSigner(address signer, uint256 uptime) external onlyVm() {
    _updateValidatorScoreFromSigner(signer, uptime);
  }

  /**
   * @notice Updates a validator's score based on its uptime for the epoch.
   * @param signer The validator signer of the validator whose score needs updating.
   * @param uptime The Fixidity representation of the validator's uptime, between 0 and 1.
   * @dev new_score = uptime ** exponent * adjustmentSpeed + old_score * (1 - adjustmentSpeed)
   * @return True upon success.
   */
  function _updateValidatorScoreFromSigner(address signer, uint256 uptime) internal {
    address account = getAccounts().signerToAccount(signer);
    require(isValidator(account), "Not a validator");

    FixidityLib.Fraction memory epochScore = FixidityLib.wrap(calculateEpochScore(uptime));
    FixidityLib.Fraction memory newComponent = validatorScoreParameters.adjustmentSpeed.multiply(
      epochScore
    );

    FixidityLib.Fraction memory currentComponent = FixidityLib.fixed1().subtract(
      validatorScoreParameters.adjustmentSpeed
    );
    currentComponent = currentComponent.multiply(validators[account].score);
    validators[account].score = FixidityLib.wrap(
      Math.min(epochScore.unwrap(), newComponent.add(currentComponent).unwrap())
    );
    emit ValidatorScoreUpdated(account, validators[account].score.unwrap(), epochScore.unwrap());
  }

  /**
   * @notice Distributes epoch payments to the account associated with `signer` and its group.
   * @param signer The validator signer of the account to distribute the epoch payment to.
   * @param maxPayment The maximum payment to the validator. Actual payment is based on score and
   *   group commission.
   * @return The total payment paid to the validator and their group.
   */
  function distributeEpochPaymentsFromSigner(address signer, uint256 maxPayment)
    external
    onlyVm()
    returns (uint256)
  {
    return _distributeEpochPaymentsFromSigner(signer, maxPayment);
  }

  /**
   * @notice Distributes epoch payments to the account associated with `signer` and its group.
   * @param signer The validator signer of the validator to distribute the epoch payment to.
   * @param maxPayment The maximum payment to the validator. Actual payment is based on score and
   *   group commission.
   * @return The total payment paid to the validator and their group.
   */
  function _distributeEpochPaymentsFromSigner(address signer, uint256 maxPayment)
    internal
    returns (uint256)
  {
    address account = getAccounts().signerToAccount(signer);
    require(isValidator(account), "Not a validator");
    // The group that should be paid is the group that the validator was a member of at the
    // time it was elected.
    address group = getMembershipInLastEpoch(account);
    require(group != address(0), "Validator not registered with a group");
    // Both the validator and the group must maintain the minimum locked gold balance in order to
    // receive epoch payments.
    if (meetsAccountLockedGoldRequirements(account) && meetsAccountLockedGoldRequirements(group)) {
      FixidityLib.Fraction memory totalPayment = FixidityLib
        .newFixed(maxPayment)
        .multiply(validators[account].score)
        .multiply(groups[group].slashInfo.multiplier);
      uint256 groupPayment = totalPayment.multiply(groups[group].commission).fromFixed();
      uint256 validatorPayment = totalPayment.fromFixed().sub(groupPayment);
      IStableToken stableToken = getStableToken();
      require(stableToken.mint(group, groupPayment), "mint failed to validator group");
      require(stableToken.mint(account, validatorPayment), "mint failed to validator account");
      emit ValidatorEpochPaymentDistributed(account, validatorPayment, group, groupPayment);
      return totalPayment.fromFixed();
    } else {
      return 0;
    }
  }

  /**
   * @notice De-registers a validator.
   * @param index The index of this validator in the list of all registered validators.
   * @return True upon success.
   * @dev Fails if the account is not a validator.
   * @dev Fails if the validator has been a member of a group too recently.
   */
  function deregisterValidator(uint256 index) external nonReentrant returns (bool) {
    address account = getAccounts().validatorSignerToAccount(msg.sender);
    require(isValidator(account), "Not a validator");

    // Require that the validator has not been a member of a validator group for
    // `validatorLockedGoldRequirements.duration` seconds.
    Validator storage validator = validators[account];
    if (validator.affiliation != address(0)) {
      require(
        !groups[validator.affiliation].members.contains(account),
        "Has been group member recently"
      );
    }
    uint256 requirementEndTime = validator.membershipHistory.lastRemovedFromGroupTimestamp.add(
      validatorLockedGoldRequirements.duration
    );
    require(requirementEndTime < now, "Not yet requirement end time");

    // Remove the validator.
    deleteElement(registeredValidators, account, index);
    delete validators[account];
    emit ValidatorDeregistered(account);
    return true;
  }

  /**
   * @notice Affiliates a validator with a group, allowing it to be added as a member.
   * @param group The validator group with which to affiliate.
   * @return True upon success.
   * @dev De-affiliates with the previously affiliated group if present.
   */
  function affiliate(address group) external nonReentrant returns (bool) {
    address account = getAccounts().validatorSignerToAccount(msg.sender);
    require(isValidator(account), "Not a validator");
    require(isValidatorGroup(group), "Not a validator group");
    require(meetsAccountLockedGoldRequirements(account), "Validator doesn't meet requirements");
    require(meetsAccountLockedGoldRequirements(group), "Group doesn't meet requirements");
    Validator storage validator = validators[account];
    if (validator.affiliation != address(0)) {
      _deaffiliate(validator, account);
    }
    validator.affiliation = group;
    emit ValidatorAffiliated(account, group);
    return true;
  }

  /**
   * @notice De-affiliates a validator, removing it from the group for which it is a member.
   * @return True upon success.
   * @dev Fails if the account is not a validator with non-zero affiliation.
   */
  function deaffiliate() external nonReentrant returns (bool) {
    address account = getAccounts().validatorSignerToAccount(msg.sender);
    require(isValidator(account), "Not a validator");
    Validator storage validator = validators[account];
    require(validator.affiliation != address(0), "deaffiliate: not affiliated");
    _deaffiliate(validator, account);
    return true;
  }

  /**
   * @notice Updates a validator's BLS key.
   * @param blsPublicKey The BLS public key that the validator is using for consensus, should pass
   *   proof of possession. 48 bytes.
   * @param blsPop The BLS public key proof-of-possession, which consists of a signature on the
   *   account address. 48 bytes.
   * @return True upon success.
   */
  function updateBlsPublicKey(bytes calldata blsPublicKey, bytes calldata blsPop)
    external
    returns (bool)
  {
    address account = getAccounts().validatorSignerToAccount(msg.sender);
    require(isValidator(account), "Not a validator");
    Validator storage validator = validators[account];
    require(
      _updateBlsPublicKey(validator, account, blsPublicKey, blsPop),
      "Error updating BLS public key"
    );
    return true;
  }

  /**
   * @notice Updates a validator's BLS key.
   * @param validator The validator whose BLS public key should be updated.
   * @param account The address under which the validator is registered.
   * @param blsPublicKey The BLS public key that the validator is using for consensus, should pass
   *   proof of possession. 96 bytes.
   * @param blsPop The BLS public key proof-of-possession, which consists of a signature on the
   *   account address. 48 bytes.
   * @return True upon success.
   */
  function _updateBlsPublicKey(
    Validator storage validator,
    address account,
    bytes memory blsPublicKey,
    bytes memory blsPop
  ) private returns (bool) {
    require(blsPublicKey.length == 96, "Wrong BLS public key length");
    require(blsPop.length == 48, "Wrong BLS PoP length");
    require(checkProofOfPossession(account, blsPublicKey, blsPop), "Invalid BLS PoP");
    validator.publicKeys.bls = blsPublicKey;
    emit ValidatorBlsPublicKeyUpdated(account, blsPublicKey);
    return true;
  }

  /**
   * @notice Updates a validator's ECDSA key.
   * @param account The address under which the validator is registered.
   * @param signer The address which the validator is using to sign consensus messages.
   * @param ecdsaPublicKey The ECDSA public key corresponding to `signer`.
   * @return True upon success.
   */
  function updateEcdsaPublicKey(address account, address signer, bytes calldata ecdsaPublicKey)
    external
    onlyRegisteredContract(ACCOUNTS_REGISTRY_ID)
    returns (bool)
  {
    require(isValidator(account), "Not a validator");
    Validator storage validator = validators[account];
    require(
      _updateEcdsaPublicKey(validator, account, signer, ecdsaPublicKey),
      "Error updating ECDSA public key"
    );
    return true;
  }

  /**
   * @notice Updates a validator's ECDSA key.
   * @param validator The validator whose ECDSA public key should be updated.
   * @param signer The address with which the validator is signing consensus messages.
   * @param ecdsaPublicKey The ECDSA public key that the validator is using for consensus. Should
   *   match `signer`. 64 bytes.
   * @return True upon success.
   */
  function _updateEcdsaPublicKey(
    Validator storage validator,
    address account,
    address signer,
    bytes memory ecdsaPublicKey
  ) private returns (bool) {
    require(ecdsaPublicKey.length == 64, "Wrong ECDSA public key length");
    require(
      address(uint160(uint256(keccak256(ecdsaPublicKey)))) == signer,
      "ECDSA key does not match signer"
    );
    validator.publicKeys.ecdsa = ecdsaPublicKey;
    emit ValidatorEcdsaPublicKeyUpdated(account, ecdsaPublicKey);
    return true;
  }

  /**
   * @notice Updates a validator's ECDSA and BLS keys.
   * @param account The address under which the validator is registered.
   * @param signer The address which the validator is using to sign consensus messages.
   * @param ecdsaPublicKey The ECDSA public key corresponding to `signer`.
   * @param blsPublicKey The BLS public key that the validator is using for consensus, should pass
   *   proof of possession. 96 bytes.
   * @param blsPop The BLS public key proof-of-possession, which consists of a signature on the
   *   account address. 48 bytes.
   * @return True upon success.
   */
  function updatePublicKeys(
    address account,
    address signer,
    bytes calldata ecdsaPublicKey,
    bytes calldata blsPublicKey,
    bytes calldata blsPop
  ) external onlyRegisteredContract(ACCOUNTS_REGISTRY_ID) returns (bool) {
    require(isValidator(account), "Not a validator");
    Validator storage validator = validators[account];
    require(
      _updateEcdsaPublicKey(validator, account, signer, ecdsaPublicKey),
      "Error updating ECDSA public key"
    );
    require(
      _updateBlsPublicKey(validator, account, blsPublicKey, blsPop),
      "Error updating BLS public key"
    );
    return true;
  }

  /**
   * @notice Registers a validator group with no member validators.
   * @param commission Fixidity representation of the commission this group receives on epoch
   *   payments made to its members.
   * @return True upon success.
   * @dev Fails if the account is already a validator or validator group.
   * @dev Fails if the account does not have sufficient weight.
   */
  function registerValidatorGroup(uint256 commission) external nonReentrant returns (bool) {
    require(commission <= FixidityLib.fixed1().unwrap(), "Commission can't be greater than 100%");
    address account = getAccounts().validatorSignerToAccount(msg.sender);
    require(!isValidator(account), "Already registered as validator");
    require(!isValidatorGroup(account), "Already registered as group");
    uint256 lockedGoldBalance = getLockedGold().getAccountTotalLockedGold(account);
    require(lockedGoldBalance >= groupLockedGoldRequirements.value, "Not enough locked gold");
    ValidatorGroup storage group = groups[account];
    group.exists = true;
    group.commission = FixidityLib.wrap(commission);
    group.slashInfo = SlashingInfo(FixidityLib.fixed1(), 0);
    registeredGroups.push(account);
    emit ValidatorGroupRegistered(account, commission);
    return true;
  }

  /**
   * @notice De-registers a validator group.
   * @param index The index of this validator group in the list of all validator groups.
   * @return True upon success.
   * @dev Fails if the account is not a validator group with no members.
   * @dev Fails if the group has had members too recently.
   */
  function deregisterValidatorGroup(uint256 index) external nonReentrant returns (bool) {
    address account = getAccounts().validatorSignerToAccount(msg.sender);
    // Only Validator Groups that have never had members or have been empty for at least
    // `groupLockedGoldRequirements.duration` seconds can be deregistered.
    require(isValidatorGroup(account), "Not a validator group");
    require(groups[account].members.numElements == 0, "Validator group not empty");
    uint256[] storage sizeHistory = groups[account].sizeHistory;
    if (sizeHistory.length > 1) {
      require(
        sizeHistory[1].add(groupLockedGoldRequirements.duration) < now,
        "Hasn't been empty for long enough"
      );
    }
    delete groups[account];
    deleteElement(registeredGroups, account, index);
    emit ValidatorGroupDeregistered(account);
    return true;
  }

  /**
   * @notice Adds a member to the end of a validator group's list of members.
   * @param validator The validator to add to the group
   * @return True upon success.
   * @dev Fails if `validator` has not set their affiliation to this account.
   * @dev Fails if the group has zero members.
   */
  function addMember(address validator) external nonReentrant returns (bool) {
    address account = getAccounts().validatorSignerToAccount(msg.sender);
    require(groups[account].members.numElements > 0, "Validator group empty");
    return _addMember(account, validator, address(0), address(0));
  }

  /**
   * @notice Adds the first member to a group's list of members and marks it eligible for election.
   * @param validator The validator to add to the group
   * @param lesser The address of the group that has received fewer votes than this group.
   * @param greater The address of the group that has received more votes than this group.
   * @return True upon success.
   * @dev Fails if `validator` has not set their affiliation to this account.
   * @dev Fails if the group has > 0 members.
   */
  function addFirstMember(address validator, address lesser, address greater)
    external
    nonReentrant
    returns (bool)
  {
    address account = getAccounts().validatorSignerToAccount(msg.sender);
    require(groups[account].members.numElements == 0, "Validator group not empty");
    return _addMember(account, validator, lesser, greater);
  }

  /**
   * @notice Adds a member to the end of a validator group's list of members.
   * @param group The address of the validator group.
   * @param validator The validator to add to the group.
   * @param lesser The address of the group that has received fewer votes than this group.
   * @param greater The address of the group that has received more votes than this group.
   * @return True upon success.
   * @dev Fails if `validator` has not set their affiliation to this account.
   * @dev Fails if the group has > 0 members.
   */
  function _addMember(address group, address validator, address lesser, address greater)
    private
    returns (bool)
  {
    require(isValidatorGroup(group) && isValidator(validator), "Not validator and group");
    ValidatorGroup storage _group = groups[group];
    require(_group.members.numElements < maxGroupSize, "group would exceed maximum size");
    require(validators[validator].affiliation == group, "Not affiliated to group");
    require(!_group.members.contains(validator), "Already in group");
    uint256 numMembers = _group.members.numElements.add(1);
    _group.members.push(validator);
    require(meetsAccountLockedGoldRequirements(group), "Group requirements not met");
    require(meetsAccountLockedGoldRequirements(validator), "Validator requirements not met");
    if (numMembers == 1) {
      getElection().markGroupEligible(group, lesser, greater);
    }
    updateMembershipHistory(validator, group);
    updateSizeHistory(group, numMembers.sub(1));
    emit ValidatorGroupMemberAdded(group, validator);
    return true;
  }

  /**
   * @notice Removes a member from a validator group.
   * @param validator The validator to remove from the group
   * @return True upon success.
   * @dev Fails if `validator` is not a member of the account's group.
   */
  function removeMember(address validator) external nonReentrant returns (bool) {
    address account = getAccounts().validatorSignerToAccount(msg.sender);
    require(isValidatorGroup(account) && isValidator(validator), "is not group and validator");
    return _removeMember(account, validator);
  }

  /**
   * @notice Reorders a member within a validator group.
   * @param validator The validator to reorder.
   * @param lesserMember The member who will be behind `validator`, or 0 if `validator` will be the
   *   last member.
   * @param greaterMember The member who will be ahead of `validator`, or 0 if `validator` will be
   *   the first member.
   * @return True upon success.
   * @dev Fails if `validator` is not a member of the account's validator group.
   */
  function reorderMember(address validator, address lesserMember, address greaterMember)
    external
    nonReentrant
    returns (bool)
  {
    address account = getAccounts().validatorSignerToAccount(msg.sender);
    require(isValidatorGroup(account), "Not a group");
    require(isValidator(validator), "Not a validator");
    ValidatorGroup storage group = groups[account];
    require(group.members.contains(validator), "Not a member of the group");
    group.members.update(validator, lesserMember, greaterMember);
    emit ValidatorGroupMemberReordered(account, validator);
    return true;
  }

  /**
   * @notice Queues an update to a validator group's commission.
   * If there was a previously scheduled update, that is overwritten.
   * @param commission Fixidity representation of the commission this group receives on epoch
   *   payments made to its members. Must be in the range [0, 1.0].
   */
  function setNextCommissionUpdate(uint256 commission) external {
    address account = getAccounts().validatorSignerToAccount(msg.sender);
    require(isValidatorGroup(account), "Not a validator group");
    ValidatorGroup storage group = groups[account];
    require(commission <= FixidityLib.fixed1().unwrap(), "Commission can't be greater than 100%");
    require(commission != group.commission.unwrap(), "Commission must be different");

    group.nextCommission = FixidityLib.wrap(commission);
    group.nextCommissionBlock = block.number.add(commissionUpdateDelay);
    emit ValidatorGroupCommissionUpdateQueued(account, commission, group.nextCommissionBlock);
  }
  /**
   * @notice Updates a validator group's commission based on the previously queued update
   */
  function updateCommission() external {
    address account = getAccounts().validatorSignerToAccount(msg.sender);
    require(isValidatorGroup(account), "Not a validator group");
    ValidatorGroup storage group = groups[account];

    require(group.nextCommissionBlock != 0, "No commission update queued");
    require(group.nextCommissionBlock <= block.number, "Can't apply commission update yet");

    group.commission = group.nextCommission;
    delete group.nextCommission;
    delete group.nextCommissionBlock;
    emit ValidatorGroupCommissionUpdated(account, group.commission.unwrap());
  }

  /**
   * @notice Returns the current locked gold balance requirement for the supplied account.
   * @param account The account that may have to meet locked gold balance requirements.
   * @return The current locked gold balance requirement for the supplied account.
   */
  function getAccountLockedGoldRequirement(address account) public view returns (uint256) {
    if (isValidator(account)) {
      return validatorLockedGoldRequirements.value;
    } else if (isValidatorGroup(account)) {
      uint256 multiplier = Math.max(1, groups[account].members.numElements);
      uint256[] storage sizeHistory = groups[account].sizeHistory;
      if (sizeHistory.length > 0) {
        for (uint256 i = sizeHistory.length.sub(1); i > 0; i = i.sub(1)) {
          if (sizeHistory[i].add(groupLockedGoldRequirements.duration) >= now) {
            multiplier = Math.max(i, multiplier);
            break;
          }
        }
      }
      return groupLockedGoldRequirements.value.mul(multiplier);
    }
    return 0;
  }

  /**
   * @notice Returns whether or not an account meets its Locked Gold requirements.
   * @param account The address of the account.
   * @return Whether or not an account meets its Locked Gold requirements.
   */
  function meetsAccountLockedGoldRequirements(address account) public view returns (bool) {
    uint256 balance = getLockedGold().getAccountTotalLockedGold(account);
    // Add a bit of "wiggle room" to accommodate the fact that vote activation can result in ~1
    // wei rounding errors. Using 10 as an additional margin of safety.
    return balance.add(10) >= getAccountLockedGoldRequirement(account);
  }

  /**
   * @notice Returns the validator BLS key.
   * @param signer The account that registered the validator or its authorized signing address.
   * @return The validator BLS key.
   */
  function getValidatorBlsPublicKeyFromSigner(address signer)
    external
    view
    returns (bytes memory blsPublicKey)
  {
    address account = getAccounts().signerToAccount(signer);
    require(isValidator(account), "Not a validator");
    return validators[account].publicKeys.bls;
  }

  /**
   * @notice Returns validator information.
   * @param account The account that registered the validator.
   * @return The unpacked validator struct.
   */
  function getValidator(address account)
    public
    view
    returns (
      bytes memory ecdsaPublicKey,
      bytes memory blsPublicKey,
      address affiliation,
      uint256 score,
      address signer
    )
  {
    require(isValidator(account), "Not a validator");
    Validator storage validator = validators[account];
    return (
      validator.publicKeys.ecdsa,
      validator.publicKeys.bls,
      validator.affiliation,
      validator.score.unwrap(),
      getAccounts().getValidatorSigner(account)
    );
  }

  /**
   * @notice Returns validator group information.
   * @param account The account that registered the validator group.
   * @return The unpacked validator group struct.
   */
  function getValidatorGroup(address account)
    external
    view
    returns (address[] memory, uint256, uint256, uint256, uint256[] memory, uint256, uint256)
  {
    require(isValidatorGroup(account), "Not a validator group");
    ValidatorGroup storage group = groups[account];
    return (
      group.members.getKeys(),
      group.commission.unwrap(),
      group.nextCommission.unwrap(),
      group.nextCommissionBlock,
      group.sizeHistory,
      group.slashInfo.multiplier.unwrap(),
      group.slashInfo.lastSlashed
    );
  }

  /**
   * @notice Returns the number of members in a validator group.
   * @param account The address of the validator group.
   * @return The number of members in a validator group.
   */
  function getGroupNumMembers(address account) public view returns (uint256) {
    require(isValidatorGroup(account), "Not validator group");
    return groups[account].members.numElements;
  }

  /**
   * @notice Returns the top n group members for a particular group.
   * @param account The address of the validator group.
   * @param n The number of members to return.
   * @return The top n group members for a particular group.
   */
  function getTopGroupValidators(address account, uint256 n)
    external
    view
    returns (address[] memory)
  {
    address[] memory topAccounts = groups[account].members.headN(n);
    address[] memory topValidators = new address[](n);
    for (uint256 i = 0; i < n; i = i.add(1)) {
      topValidators[i] = getAccounts().getValidatorSigner(topAccounts[i]);
    }
    return topValidators;
  }

  /**
   * @notice Returns the number of members in the provided validator groups.
   * @param accounts The addresses of the validator groups.
   * @return The number of members in the provided validator groups.
   */
  function getGroupsNumMembers(address[] calldata accounts)
    external
    view
    returns (uint256[] memory)
  {
    uint256[] memory numMembers = new uint256[](accounts.length);
    for (uint256 i = 0; i < accounts.length; i = i.add(1)) {
      numMembers[i] = getGroupNumMembers(accounts[i]);
    }
    return numMembers;
  }

  /**
   * @notice Returns the number of registered validators.
   * @return The number of registered validators.
   */
  function getNumRegisteredValidators() external view returns (uint256) {
    return registeredValidators.length;
  }

  /**
   * @notice Returns the Locked Gold requirements for validators.
   * @return The Locked Gold requirements for validators.
   */
  function getValidatorLockedGoldRequirements() external view returns (uint256, uint256) {
    return (validatorLockedGoldRequirements.value, validatorLockedGoldRequirements.duration);
  }

  /**
   * @notice Returns the Locked Gold requirements for validator groups.
   * @return The Locked Gold requirements for validator groups.
   */
  function getGroupLockedGoldRequirements() external view returns (uint256, uint256) {
    return (groupLockedGoldRequirements.value, groupLockedGoldRequirements.duration);
  }

  /**
   * @notice Returns the list of registered validator accounts.
   * @return The list of registered validator accounts.
   */
  function getRegisteredValidators() external view returns (address[] memory) {
    return registeredValidators;
  }

  /**
   * @notice Returns the list of signers for the registered validator accounts.
   * @return The list of signers for registered validator accounts.
   */
  function getRegisteredValidatorSigners() external view returns (address[] memory) {
    IAccounts accounts = getAccounts();
    address[] memory signers = new address[](registeredValidators.length);
    for (uint256 i = 0; i < signers.length; i = i.add(1)) {
      signers[i] = accounts.getValidatorSigner(registeredValidators[i]);
    }
    return signers;
  }

  /**
   * @notice Returns the list of registered validator group accounts.
   * @return The list of registered validator group addresses.
   */
  function getRegisteredValidatorGroups() external view returns (address[] memory) {
    return registeredGroups;
  }

  /**
   * @notice Returns whether a particular account has a registered validator group.
   * @param account The account.
   * @return Whether a particular address is a registered validator group.
   */
  function isValidatorGroup(address account) public view returns (bool) {
    return groups[account].exists;
  }

  /**
   * @notice Returns whether a particular account has a registered validator.
   * @param account The account.
   * @return Whether a particular address is a registered validator.
   */
  function isValidator(address account) public view returns (bool) {
    return validators[account].publicKeys.bls.length > 0;
  }

  /**
   * @notice Deletes an element from a list of addresses.
   * @param list The list of addresses.
   * @param element The address to delete.
   * @param index The index of `element` in the list.
   */
  function deleteElement(address[] storage list, address element, uint256 index) private {
    require(index < list.length && list[index] == element, "deleteElement: index out of range");
    uint256 lastIndex = list.length.sub(1);
    list[index] = list[lastIndex];
    delete list[lastIndex];
    list.length = lastIndex;
  }

  /**
   * @notice Removes a member from a validator group.
   * @param group The group from which the member should be removed.
   * @param validator The validator to remove from the group.
   * @return True upon success.
   * @dev If `validator` was the only member of `group`, `group` becomes unelectable.
   * @dev Fails if `validator` is not a member of `group`.
   */
  function _removeMember(address group, address validator) private returns (bool) {
    ValidatorGroup storage _group = groups[group];
    require(validators[validator].affiliation == group, "Not affiliated to group");
    require(_group.members.contains(validator), "Not a member of the group");
    _group.members.remove(validator);
    uint256 numMembers = _group.members.numElements;
    // Empty validator groups are not electable.
    if (numMembers == 0) {
      getElection().markGroupIneligible(group);
    }
    updateMembershipHistory(validator, address(0));
    updateSizeHistory(group, numMembers.add(1));
    emit ValidatorGroupMemberRemoved(group, validator);
    return true;
  }

  /**
   * @notice Updates the group membership history of a particular account.
   * @param account The account whose group membership has changed.
   * @param group The group that the account is now a member of.
   * @return True upon success.
   * @dev Note that this is used to determine a validator's membership at the time of an election,
   *   and so group changes within an epoch will overwrite eachother.
   */
  function updateMembershipHistory(address account, address group) private returns (bool) {
    MembershipHistory storage history = validators[account].membershipHistory;
    uint256 epochNumber = getEpochNumber();
    uint256 head = history.numEntries == 0 ? 0 : history.tail.add(history.numEntries.sub(1));

    if (history.numEntries > 0 && group == address(0)) {
      history.lastRemovedFromGroupTimestamp = now;
    }

    if (history.numEntries > 0 && history.entries[head].epochNumber == epochNumber) {
      // There have been no elections since the validator last changed membership, overwrite the
      // previous entry.
      history.entries[head] = MembershipHistoryEntry(epochNumber, group);
      return true;
    }

    // There have been elections since the validator last changed membership, create a new entry.
    uint256 index = history.numEntries == 0 ? 0 : head.add(1);
    history.entries[index] = MembershipHistoryEntry(epochNumber, group);
    if (history.numEntries < membershipHistoryLength) {
      // Not enough entries, don't remove any.
      history.numEntries = history.numEntries.add(1);
    } else if (history.numEntries == membershipHistoryLength) {
      // Exactly enough entries, delete the oldest one to account for the one we added.
      delete history.entries[history.tail];
      history.tail = history.tail.add(1);
    } else {
      // Too many entries, delete the oldest two to account for the one we added.
      delete history.entries[history.tail];
      delete history.entries[history.tail.add(1)];
      history.numEntries = history.numEntries.sub(1);
      history.tail = history.tail.add(2);
    }
    return true;
  }

  /**
   * @notice Updates the size history of a validator group.
   * @param group The account whose group size has changed.
   * @param size The new size of the group.
   * @dev Used to determine how much gold an account needs to keep locked.
   */
  function updateSizeHistory(address group, uint256 size) private {
    uint256[] storage sizeHistory = groups[group].sizeHistory;
    if (size == sizeHistory.length) {
      sizeHistory.push(now);
    } else if (size < sizeHistory.length) {
      sizeHistory[size] = now;
    } else {
      require(false, "Unable to update size history");
    }
  }

  /**
   * @notice Returns the group that `account` was a member of at the end of the last epoch.
   * @param signer The signer of the account whose group membership should be returned.
   * @return The group that `account` was a member of at the end of the last epoch.
   */
  function getMembershipInLastEpochFromSigner(address signer) external view returns (address) {
    address account = getAccounts().signerToAccount(signer);
    require(isValidator(account), "Not a validator");
    return getMembershipInLastEpoch(account);
  }

  /**
   * @notice Returns the group that `account` was a member of at the end of the last epoch.
   * @param account The account whose group membership should be returned.
   * @return The group that `account` was a member of at the end of the last epoch.
   */
  function getMembershipInLastEpoch(address account) public view returns (address) {
    uint256 epochNumber = getEpochNumber();
    MembershipHistory storage history = validators[account].membershipHistory;
    uint256 head = history.numEntries == 0 ? 0 : history.tail.add(history.numEntries.sub(1));
    // If the most recent entry in the membership history is for the current epoch number, we need
    // to look at the previous entry.
    if (history.entries[head].epochNumber == epochNumber) {
      if (head > history.tail) {
        head = head.sub(1);
      }
    }
    return history.entries[head].group;
  }

  /**
   * @notice De-affiliates a validator, removing it from the group for which it is a member.
   * @param validator The validator to deaffiliate from their affiliated validator group.
   * @param validatorAccount The LockedGold account of the validator.
   * @return True upon success.
   */
  function _deaffiliate(Validator storage validator, address validatorAccount)
    private
    returns (bool)
  {
    address affiliation = validator.affiliation;
    ValidatorGroup storage group = groups[affiliation];
    if (group.members.contains(validatorAccount)) {
      _removeMember(affiliation, validatorAccount);
    }
    validator.affiliation = address(0);
    emit ValidatorDeaffiliated(validatorAccount, affiliation);
    return true;
  }

  /**
   * @notice Removes a validator from the group for which it is a member.
   * @param validatorAccount The validator to deaffiliate from their affiliated validator group.
   */
  function forceDeaffiliateIfValidator(address validatorAccount) external nonReentrant onlySlasher {
    if (isValidator(validatorAccount)) {
      Validator storage validator = validators[validatorAccount];
      if (validator.affiliation != address(0)) {
        _deaffiliate(validator, validatorAccount);
      }
    }
  }

  /**
   * @notice Sets the slashingMultiplierRestPeriod property if called by owner.
   * @param value New reset period for slashing multiplier.
   */
  function setSlashingMultiplierResetPeriod(uint256 value) public nonReentrant onlyOwner {
    slashingMultiplierResetPeriod = value;
  }

  /**
   * @notice Sets the downtimeGracePeriod property if called by owner.
   * @param value New downtime grace period for calculating epoch scores.
   */
  function setDowntimeGracePeriod(uint256 value) public nonReentrant onlyOwner {
    downtimeGracePeriod = value;
  }

  /**
   * @notice Resets a group's slashing multiplier if it has been >= the reset period since
   *         the last time the group was slashed.
   */
  function resetSlashingMultiplier() external nonReentrant {
    address account = getAccounts().validatorSignerToAccount(msg.sender);
    require(isValidatorGroup(account), "Not a validator group");
    ValidatorGroup storage group = groups[account];
    require(
      now >= group.slashInfo.lastSlashed.add(slashingMultiplierResetPeriod),
      "`resetSlashingMultiplier` called before resetPeriod expired"
    );
    group.slashInfo.multiplier = FixidityLib.fixed1();
  }

  /**
   * @notice Halves the group's slashing multiplier.
   * @param account The group being slashed.
   */
  function halveSlashingMultiplier(address account) external nonReentrant onlySlasher {
    require(isValidatorGroup(account), "Not a validator group");
    ValidatorGroup storage group = groups[account];
    group.slashInfo.multiplier = FixidityLib.wrap(group.slashInfo.multiplier.unwrap().div(2));
    group.slashInfo.lastSlashed = now;
  }

  /**
   * @notice Getter for a group's slashing multiplier.
   * @param account The group to fetch slashing multiplier for.
   */
  function getValidatorGroupSlashingMultiplier(address account) external view returns (uint256) {
    require(isValidatorGroup(account), "Not a validator group");
    ValidatorGroup storage group = groups[account];
    return group.slashInfo.multiplier.unwrap();
  }

  /**
   * @notice Returns the group that `account` was a member of during `epochNumber`.
   * @param account The account whose group membership should be returned.
   * @param epochNumber The epoch number we are querying this account's membership at.
   * @param index The index into the validator's history struct for their history at `epochNumber`.
   * @return The group that `account` was a member of during `epochNumber`.
   */
  function groupMembershipInEpoch(address account, uint256 epochNumber, uint256 index)
    external
    view
    returns (address)
  {
    require(isValidator(account), "Not a validator");
    require(epochNumber <= getEpochNumber(), "Epoch cannot be larger than current");
    MembershipHistory storage history = validators[account].membershipHistory;
    require(index < history.tail.add(history.numEntries), "index out of bounds");
    require(index >= history.tail && history.numEntries > 0, "index out of bounds");
    bool isExactMatch = history.entries[index].epochNumber == epochNumber;
    bool isLastEntry = index.sub(history.tail) == history.numEntries.sub(1);
    bool isWithinRange = history.entries[index].epochNumber < epochNumber &&
      (history.entries[index.add(1)].epochNumber > epochNumber || isLastEntry);
    require(
      isExactMatch || isWithinRange,
      "provided index does not match provided epochNumber at index in history."
    );
    return history.entries[index].group;
  }

}


/*
 * @title Solidity Bytes Arrays Utils
 * @author Gonçalo Sá <[email protected]>
 *
 * @dev Bytes tightly packed arrays utility library for ethereum contracts written in Solidity.
 *      The library lets you concatenate, slice and type cast bytes arrays both in memory and storage.
 */

pragma solidity ^0.5.0;


library BytesLib {
    function concat(
        bytes memory _preBytes,
        bytes memory _postBytes
    )
        internal
        pure
        returns (bytes memory)
    {
        bytes memory tempBytes;

        assembly {
            // Get a location of some free memory and store it in tempBytes as
            // Solidity does for memory variables.
            tempBytes := mload(0x40)

            // Store the length of the first bytes array at the beginning of
            // the memory for tempBytes.
            let length := mload(_preBytes)
            mstore(tempBytes, length)

            // Maintain a memory counter for the current write location in the
            // temp bytes array by adding the 32 bytes for the array length to
            // the starting location.
            let mc := add(tempBytes, 0x20)
            // Stop copying when the memory counter reaches the length of the
            // first bytes array.
            let end := add(mc, length)

            for {
                // Initialize a copy counter to the start of the _preBytes data,
                // 32 bytes into its memory.
                let cc := add(_preBytes, 0x20)
            } lt(mc, end) {
                // Increase both counters by 32 bytes each iteration.
                mc := add(mc, 0x20)
                cc := add(cc, 0x20)
            } {
                // Write the _preBytes data into the tempBytes memory 32 bytes
                // at a time.
                mstore(mc, mload(cc))
            }

            // Add the length of _postBytes to the current length of tempBytes
            // and store it as the new length in the first 32 bytes of the
            // tempBytes memory.
            length := mload(_postBytes)
            mstore(tempBytes, add(length, mload(tempBytes)))

            // Move the memory counter back from a multiple of 0x20 to the
            // actual end of the _preBytes data.
            mc := end
            // Stop copying when the memory counter reaches the new combined
            // length of the arrays.
            end := add(mc, length)

            for {
                let cc := add(_postBytes, 0x20)
            } lt(mc, end) {
                mc := add(mc, 0x20)
                cc := add(cc, 0x20)
            } {
                mstore(mc, mload(cc))
            }

            // Update the free-memory pointer by padding our last write location
            // to 32 bytes: add 31 bytes to the end of tempBytes to move to the
            // next 32 byte block, then round down to the nearest multiple of
            // 32. If the sum of the length of the two arrays is zero then add 
            // one before rounding down to leave a blank 32 bytes (the length block with 0).
            mstore(0x40, and(
              add(add(end, iszero(add(length, mload(_preBytes)))), 31),
              not(31) // Round down to the nearest 32 bytes.
            ))
        }

        return tempBytes;
    }

    function concatStorage(bytes storage _preBytes, bytes memory _postBytes) internal {
        assembly {
            // Read the first 32 bytes of _preBytes storage, which is the length
            // of the array. (We don't need to use the offset into the slot
            // because arrays use the entire slot.)
            let fslot := sload(_preBytes_slot)
            // Arrays of 31 bytes or less have an even value in their slot,
            // while longer arrays have an odd value. The actual length is
            // the slot divided by two for odd values, and the lowest order
            // byte divided by two for even values.
            // If the slot is even, bitwise and the slot with 255 and divide by
            // two to get the length. If the slot is odd, bitwise and the slot
            // with -1 and divide by two.
            let slength := div(and(fslot, sub(mul(0x100, iszero(and(fslot, 1))), 1)), 2)
            let mlength := mload(_postBytes)
            let newlength := add(slength, mlength)
            // slength can contain both the length and contents of the array
            // if length < 32 bytes so let's prepare for that
            // v. http://solidity.readthedocs.io/en/latest/miscellaneous.html#layout-of-state-variables-in-storage
            switch add(lt(slength, 32), lt(newlength, 32))
            case 2 {
                // Since the new array still fits in the slot, we just need to
                // update the contents of the slot.
                // uint256(bytes_storage) = uint256(bytes_storage) + uint256(bytes_memory) + new_length
                sstore(
                    _preBytes_slot,
                    // all the modifications to the slot are inside this
                    // next block
                    add(
                        // we can just add to the slot contents because the
                        // bytes we want to change are the LSBs
                        fslot,
                        add(
                            mul(
                                div(
                                    // load the bytes from memory
                                    mload(add(_postBytes, 0x20)),
                                    // zero all bytes to the right
                                    exp(0x100, sub(32, mlength))
                                ),
                                // and now shift left the number of bytes to
                                // leave space for the length in the slot
                                exp(0x100, sub(32, newlength))
                            ),
                            // increase length by the double of the memory
                            // bytes length
                            mul(mlength, 2)
                        )
                    )
                )
            }
            case 1 {
                // The stored value fits in the slot, but the combined value
                // will exceed it.
                // get the keccak hash to get the contents of the array
                mstore(0x0, _preBytes_slot)
                let sc := add(keccak256(0x0, 0x20), div(slength, 32))

                // save new length
                sstore(_preBytes_slot, add(mul(newlength, 2), 1))

                // The contents of the _postBytes array start 32 bytes into
                // the structure. Our first read should obtain the `submod`
                // bytes that can fit into the unused space in the last word
                // of the stored array. To get this, we read 32 bytes starting
                // from `submod`, so the data we read overlaps with the array
                // contents by `submod` bytes. Masking the lowest-order
                // `submod` bytes allows us to add that value directly to the
                // stored value.

                let submod := sub(32, slength)
                let mc := add(_postBytes, submod)
                let end := add(_postBytes, mlength)
                let mask := sub(exp(0x100, submod), 1)

                sstore(
                    sc,
                    add(
                        and(
                            fslot,
                            0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff00
                        ),
                        and(mload(mc), mask)
                    )
                )

                for {
                    mc := add(mc, 0x20)
                    sc := add(sc, 1)
                } lt(mc, end) {
                    sc := add(sc, 1)
                    mc := add(mc, 0x20)
                } {
                    sstore(sc, mload(mc))
                }

                mask := exp(0x100, sub(mc, end))

                sstore(sc, mul(div(mload(mc), mask), mask))
            }
            default {
                // get the keccak hash to get the contents of the array
                mstore(0x0, _preBytes_slot)
                // Start copying to the last used word of the stored array.
                let sc := add(keccak256(0x0, 0x20), div(slength, 32))

                // save new length
                sstore(_preBytes_slot, add(mul(newlength, 2), 1))

                // Copy over the first `submod` bytes of the new data as in
                // case 1 above.
                let slengthmod := mod(slength, 32)
                let mlengthmod := mod(mlength, 32)
                let submod := sub(32, slengthmod)
                let mc := add(_postBytes, submod)
                let end := add(_postBytes, mlength)
                let mask := sub(exp(0x100, submod), 1)

                sstore(sc, add(sload(sc), and(mload(mc), mask)))
                
                for { 
                    sc := add(sc, 1)
                    mc := add(mc, 0x20)
                } lt(mc, end) {
                    sc := add(sc, 1)
                    mc := add(mc, 0x20)
                } {
                    sstore(sc, mload(mc))
                }

                mask := exp(0x100, sub(mc, end))

                sstore(sc, mul(div(mload(mc), mask), mask))
            }
        }
    }

    function slice(
        bytes memory _bytes,
        uint _start,
        uint _length
    )
        internal
        pure
        returns (bytes memory)
    {
        require(_bytes.length >= (_start + _length));

        bytes memory tempBytes;

        assembly {
            switch iszero(_length)
            case 0 {
                // Get a location of some free memory and store it in tempBytes as
                // Solidity does for memory variables.
                tempBytes := mload(0x40)

                // The first word of the slice result is potentially a partial
                // word read from the original array. To read it, we calculate
                // the length of that partial word and start copying that many
                // bytes into the array. The first word we copy will start with
                // data we don't care about, but the last `lengthmod` bytes will
                // land at the beginning of the contents of the new array. When
                // we're done copying, we overwrite the full first word with
                // the actual length of the slice.
                let lengthmod := and(_length, 31)

                // The multiplication in the next line is necessary
                // because when slicing multiples of 32 bytes (lengthmod == 0)
                // the following copy loop was copying the origin's length
                // and then ending prematurely not copying everything it should.
                let mc := add(add(tempBytes, lengthmod), mul(0x20, iszero(lengthmod)))
                let end := add(mc, _length)

                for {
                    // The multiplication in the next line has the same exact purpose
                    // as the one above.
                    let cc := add(add(add(_bytes, lengthmod), mul(0x20, iszero(lengthmod))), _start)
                } lt(mc, end) {
                    mc := add(mc, 0x20)
                    cc := add(cc, 0x20)
                } {
                    mstore(mc, mload(cc))
                }

                mstore(tempBytes, _length)

                //update free-memory pointer
                //allocating the array padded to 32 bytes like the compiler does now
                mstore(0x40, and(add(mc, 31), not(31)))
            }
            //if we want a zero-length slice let's just return a zero-length array
            default {
                tempBytes := mload(0x40)

                mstore(0x40, add(tempBytes, 0x20))
            }
        }

        return tempBytes;
    }

    function toAddress(bytes memory _bytes, uint _start) internal  pure returns (address) {
        require(_bytes.length >= (_start + 20));
        address tempAddress;

        assembly {
            tempAddress := div(mload(add(add(_bytes, 0x20), _start)), 0x1000000000000000000000000)
        }

        return tempAddress;
    }

    function toUint8(bytes memory _bytes, uint _start) internal  pure returns (uint8) {
        require(_bytes.length >= (_start + 1));
        uint8 tempUint;

        assembly {
            tempUint := mload(add(add(_bytes, 0x1), _start))
        }

        return tempUint;
    }

    function toUint16(bytes memory _bytes, uint _start) internal  pure returns (uint16) {
        require(_bytes.length >= (_start + 2));
        uint16 tempUint;

        assembly {
            tempUint := mload(add(add(_bytes, 0x2), _start))
        }

        return tempUint;
    }

    function toUint32(bytes memory _bytes, uint _start) internal  pure returns (uint32) {
        require(_bytes.length >= (_start + 4));
        uint32 tempUint;

        assembly {
            tempUint := mload(add(add(_bytes, 0x4), _start))
        }

        return tempUint;
    }

    function toUint(bytes memory _bytes, uint _start) internal  pure returns (uint256) {
        require(_bytes.length >= (_start + 32));
        uint256 tempUint;

        assembly {
            tempUint := mload(add(add(_bytes, 0x20), _start))
        }

        return tempUint;
    }

    function toBytes32(bytes memory _bytes, uint _start) internal  pure returns (bytes32) {
        require(_bytes.length >= (_start + 32));
        bytes32 tempBytes32;

        assembly {
            tempBytes32 := mload(add(add(_bytes, 0x20), _start))
        }

        return tempBytes32;
    }

    function equal(bytes memory _preBytes, bytes memory _postBytes) internal pure returns (bool) {
        bool success = true;

        assembly {
            let length := mload(_preBytes)

            // if lengths don't match the arrays are not equal
            switch eq(length, mload(_postBytes))
            case 1 {
                // cb is a circuit breaker in the for loop since there's
                //  no said feature for inline assembly loops
                // cb = 1 - don't breaker
                // cb = 0 - break
                let cb := 1

                let mc := add(_preBytes, 0x20)
                let end := add(mc, length)

                for {
                    let cc := add(_postBytes, 0x20)
                // the next line is the loop condition:
                // while(uint(mc < end) + cb == 2)
                } eq(add(lt(mc, end), cb), 2) {
                    mc := add(mc, 0x20)
                    cc := add(cc, 0x20)
                } {
                    // if any of these checks fails then arrays are not equal
                    if iszero(eq(mload(mc), mload(cc))) {
                        // unsuccess:
                        success := 0
                        cb := 0
                    }
                }
            }
            default {
                // unsuccess:
                success := 0
            }
        }

        return success;
    }

    function equalStorage(
        bytes storage _preBytes,
        bytes memory _postBytes
    )
        internal
        view
        returns (bool)
    {
        bool success = true;

        assembly {
            // we know _preBytes_offset is 0
            let fslot := sload(_preBytes_slot)
            // Decode the length of the stored array like in concatStorage().
            let slength := div(and(fslot, sub(mul(0x100, iszero(and(fslot, 1))), 1)), 2)
            let mlength := mload(_postBytes)

            // if lengths don't match the arrays are not equal
            switch eq(slength, mlength)
            case 1 {
                // slength can contain both the length and contents of the array
                // if length < 32 bytes so let's prepare for that
                // v. http://solidity.readthedocs.io/en/latest/miscellaneous.html#layout-of-state-variables-in-storage
                if iszero(iszero(slength)) {
                    switch lt(slength, 32)
                    case 1 {
                        // blank the last byte which is the length
                        fslot := mul(div(fslot, 0x100), 0x100)

                        if iszero(eq(fslot, mload(add(_postBytes, 0x20)))) {
                            // unsuccess:
                            success := 0
                        }
                    }
                    default {
                        // cb is a circuit breaker in the for loop since there's
                        //  no said feature for inline assembly loops
                        // cb = 1 - don't breaker
                        // cb = 0 - break
                        let cb := 1

                        // get the keccak hash to get the contents of the array
                        mstore(0x0, _preBytes_slot)
                        let sc := keccak256(0x0, 0x20)

                        let mc := add(_postBytes, 0x20)
                        let end := add(mc, mlength)

                        // the next line is the loop condition:
                        // while(uint(mc < end) + cb == 2)
                        for {} eq(add(lt(mc, end), cb), 2) {
                            sc := add(sc, 1)
                            mc := add(mc, 0x20)
                        } {
                            if iszero(eq(sload(sc), mload(mc))) {
                                // unsuccess:
                                success := 0
                                cb := 0
                            }
                        }
                    }
                }
            }
            default {
                // unsuccess:
                success := 0
            }
        }

        return success;
    }
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
 * @dev Standard math utilities missing in the Solidity language.
 */
library Math {
    /**
     * @dev Returns the largest of two numbers.
     */
    function max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a >= b ? a : b;
    }

    /**
     * @dev Returns the smallest of two numbers.
     */
    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    /**
     * @dev Returns the average of two numbers. The result is rounded towards
     * zero.
     */
    function average(uint256 a, uint256 b) internal pure returns (uint256) {
        // (a + b) / 2 can overflow, so we distribute
        return (a / 2) + (b / 2) + ((a % 2 + b % 2) / 2);
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

import "openzeppelin-solidity/contracts/math/SafeMath.sol";

/**
 * @title Maintains a doubly linked list keyed by bytes32.
 * @dev Following the `next` pointers will lead you to the head, rather than the tail.
 */
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

  /**
   * @notice Inserts an element into a doubly linked list.
   * @param list A storage pointer to the underlying list.
   * @param key The key of the element to insert.
   * @param previousKey The key of the element that comes before the element to insert.
   * @param nextKey The key of the element that comes after the element to insert.
   */
  function insert(List storage list, bytes32 key, bytes32 previousKey, bytes32 nextKey) internal {
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

  /**
   * @notice Inserts an element at the tail of the doubly linked list.
   * @param list A storage pointer to the underlying list.
   * @param key The key of the element to insert.
   */
  function push(List storage list, bytes32 key) internal {
    insert(list, key, bytes32(0), list.tail);
  }

  /**
   * @notice Removes an element from the doubly linked list.
   * @param list A storage pointer to the underlying list.
   * @param key The key of the element to remove.
   */
  function remove(List storage list, bytes32 key) internal {
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

  /**
   * @notice Updates an element in the list.
   * @param list A storage pointer to the underlying list.
   * @param key The element key.
   * @param previousKey The key of the element that comes before the updated element.
   * @param nextKey The key of the element that comes after the updated element.
   */
  function update(List storage list, bytes32 key, bytes32 previousKey, bytes32 nextKey) internal {
    require(
      key != bytes32(0) && key != previousKey && key != nextKey && contains(list, key),
      "key on in list"
    );
    remove(list, key);
    insert(list, key, previousKey, nextKey);
  }

  /**
   * @notice Returns whether or not a particular key is present in the sorted list.
   * @param list A storage pointer to the underlying list.
   * @param key The element key.
   * @return Whether or not the key is in the sorted list.
   */
  function contains(List storage list, bytes32 key) internal view returns (bool) {
    return list.elements[key].exists;
  }

  /**
   * @notice Returns the keys of the N elements at the head of the list.
   * @param list A storage pointer to the underlying list.
   * @param n The number of elements to return.
   * @return The keys of the N elements at the head of the list.
   * @dev Reverts if n is greater than the number of elements in the list.
   */
  function headN(List storage list, uint256 n) internal view returns (bytes32[] memory) {
    require(n <= list.numElements, "not enough elements");
    bytes32[] memory keys = new bytes32[](n);
    bytes32 key = list.head;
    for (uint256 i = 0; i < n; i = i.add(1)) {
      keys[i] = key;
      key = list.elements[key].previousKey;
    }
    return keys;
  }

  /**
   * @notice Gets all element keys from the doubly linked list.
   * @param list A storage pointer to the underlying list.
   * @return All element keys from head to tail.
   */
  function getKeys(List storage list) internal view returns (bytes32[] memory) {
    return headN(list, list.numElements);
  }
}


pragma solidity ^0.5.13;

import "openzeppelin-solidity/contracts/math/SafeMath.sol";

import "./LinkedList.sol";

/**
 * @title Maintains a doubly linked list keyed by address.
 * @dev Following the `next` pointers will lead you to the head, rather than the tail.
 */
library AddressLinkedList {
  using LinkedList for LinkedList.List;
  using SafeMath for uint256;

  function toBytes(address a) public pure returns (bytes32) {
    return bytes32(uint256(a) << 96);
  }

  function toAddress(bytes32 b) public pure returns (address) {
    return address(uint256(b) >> 96);
  }

  /**
   * @notice Inserts an element into a doubly linked list.
   * @param list A storage pointer to the underlying list.
   * @param key The key of the element to insert.
   * @param previousKey The key of the element that comes before the element to insert.
   * @param nextKey The key of the element that comes after the element to insert.
   */
  function insert(LinkedList.List storage list, address key, address previousKey, address nextKey)
    public
  {
    list.insert(toBytes(key), toBytes(previousKey), toBytes(nextKey));
  }

  /**
   * @notice Inserts an element at the end of the doubly linked list.
   * @param list A storage pointer to the underlying list.
   * @param key The key of the element to insert.
   */
  function push(LinkedList.List storage list, address key) public {
    list.insert(toBytes(key), bytes32(0), list.tail);
  }

  /**
   * @notice Removes an element from the doubly linked list.
   * @param list A storage pointer to the underlying list.
   * @param key The key of the element to remove.
   */
  function remove(LinkedList.List storage list, address key) public {
    list.remove(toBytes(key));
  }

  /**
   * @notice Updates an element in the list.
   * @param list A storage pointer to the underlying list.
   * @param key The element key.
   * @param previousKey The key of the element that comes before the updated element.
   * @param nextKey The key of the element that comes after the updated element.
   */
  function update(LinkedList.List storage list, address key, address previousKey, address nextKey)
    public
  {
    list.update(toBytes(key), toBytes(previousKey), toBytes(nextKey));
  }

  /**
   * @notice Returns whether or not a particular key is present in the sorted list.
   * @param list A storage pointer to the underlying list.
   * @param key The element key.
   * @return Whether or not the key is in the sorted list.
   */
  function contains(LinkedList.List storage list, address key) public view returns (bool) {
    return list.elements[toBytes(key)].exists;
  }

  /**
   * @notice Returns the N greatest elements of the list.
   * @param list A storage pointer to the underlying list.
   * @param n The number of elements to return.
   * @return The keys of the greatest elements.
   * @dev Reverts if n is greater than the number of elements in the list.
   */
  function headN(LinkedList.List storage list, uint256 n) public view returns (address[] memory) {
    bytes32[] memory byteKeys = list.headN(n);
    address[] memory keys = new address[](n);
    for (uint256 i = 0; i < n; i = i.add(1)) {
      keys[i] = toAddress(byteKeys[i]);
    }
    return keys;
  }

  /**
   * @notice Gets all element keys from the doubly linked list.
   * @param list A storage pointer to the underlying list.
   * @return All element keys from head to tail.
   */
  function getKeys(LinkedList.List storage list) public view returns (address[] memory) {
    return headN(list, list.numElements);
  }
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

/**
 * @title FixidityLib
 * @author Gadi Guy, Alberto Cuesta Canada
 * @notice This library provides fixed point arithmetic with protection against
 * overflow.
 * All operations are done with uint256 and the operands must have been created
 * with any of the newFrom* functions, which shift the comma digits() to the
 * right and check for limits, or with wrap() which expects a number already
 * in the internal representation of a fraction.
 * When using this library be sure to use maxNewFixed() as the upper limit for
 * creation of fixed point numbers.
 * @dev All contained functions are pure and thus marked internal to be inlined
 * on consuming contracts at compile time for gas efficiency.
 */
library FixidityLib {
  struct Fraction {
    uint256 value;
  }

  /**
   * @notice Number of positions that the comma is shifted to the right.
   */
  function digits() internal pure returns (uint8) {
    return 24;
  }

  uint256 private constant FIXED1_UINT = 1000000000000000000000000;

  /**
   * @notice This is 1 in the fixed point units used in this library.
   * @dev Test fixed1() equals 10^digits()
   * Hardcoded to 24 digits.
   */
  function fixed1() internal pure returns (Fraction memory) {
    return Fraction(FIXED1_UINT);
  }

  /**
   * @notice Wrap a uint256 that represents a 24-decimal fraction in a Fraction
   * struct.
   * @param x Number that already represents a 24-decimal fraction.
   * @return A Fraction struct with contents x.
   */
  function wrap(uint256 x) internal pure returns (Fraction memory) {
    return Fraction(x);
  }

  /**
   * @notice Unwraps the uint256 inside of a Fraction struct.
   */
  function unwrap(Fraction memory x) internal pure returns (uint256) {
    return x.value;
  }

  /**
   * @notice The amount of decimals lost on each multiplication operand.
   * @dev Test mulPrecision() equals sqrt(fixed1)
   */
  function mulPrecision() internal pure returns (uint256) {
    return 1000000000000;
  }

  /**
   * @notice Maximum value that can be converted to fixed point. Optimize for deployment.
   * @dev
   * Test maxNewFixed() equals maxUint256() / fixed1()
   */
  function maxNewFixed() internal pure returns (uint256) {
    return 115792089237316195423570985008687907853269984665640564;
  }

  /**
   * @notice Converts a uint256 to fixed point Fraction
   * @dev Test newFixed(0) returns 0
   * Test newFixed(1) returns fixed1()
   * Test newFixed(maxNewFixed()) returns maxNewFixed() * fixed1()
   * Test newFixed(maxNewFixed()+1) fails
   */
  function newFixed(uint256 x) internal pure returns (Fraction memory) {
    require(x <= maxNewFixed(), "can't create fixidity number larger than maxNewFixed()");
    return Fraction(x * FIXED1_UINT);
  }

  /**
   * @notice Converts a uint256 in the fixed point representation of this
   * library to a non decimal. All decimal digits will be truncated.
   */
  function fromFixed(Fraction memory x) internal pure returns (uint256) {
    return x.value / FIXED1_UINT;
  }

  /**
   * @notice Converts two uint256 representing a fraction to fixed point units,
   * equivalent to multiplying dividend and divisor by 10^digits().
   * @param numerator numerator must be <= maxNewFixed()
   * @param denominator denominator must be <= maxNewFixed() and denominator can't be 0
   * @dev
   * Test newFixedFraction(1,0) fails
   * Test newFixedFraction(0,1) returns 0
   * Test newFixedFraction(1,1) returns fixed1()
   * Test newFixedFraction(1,fixed1()) returns 1
   */
  function newFixedFraction(uint256 numerator, uint256 denominator)
    internal
    pure
    returns (Fraction memory)
  {
    Fraction memory convertedNumerator = newFixed(numerator);
    Fraction memory convertedDenominator = newFixed(denominator);
    return divide(convertedNumerator, convertedDenominator);
  }

  /**
   * @notice Returns the integer part of a fixed point number.
   * @dev
   * Test integer(0) returns 0
   * Test integer(fixed1()) returns fixed1()
   * Test integer(newFixed(maxNewFixed())) returns maxNewFixed()*fixed1()
   */
  function integer(Fraction memory x) internal pure returns (Fraction memory) {
    return Fraction((x.value / FIXED1_UINT) * FIXED1_UINT); // Can't overflow
  }

  /**
   * @notice Returns the fractional part of a fixed point number.
   * In the case of a negative number the fractional is also negative.
   * @dev
   * Test fractional(0) returns 0
   * Test fractional(fixed1()) returns 0
   * Test fractional(fixed1()-1) returns 10^24-1
   */
  function fractional(Fraction memory x) internal pure returns (Fraction memory) {
    return Fraction(x.value - (x.value / FIXED1_UINT) * FIXED1_UINT); // Can't overflow
  }

  /**
   * @notice x+y.
   * @dev The maximum value that can be safely used as an addition operator is defined as
   * maxFixedAdd = maxUint256()-1 / 2, or
   * 57896044618658097711785492504343953926634992332820282019728792003956564819967.
   * Test add(maxFixedAdd,maxFixedAdd) equals maxFixedAdd + maxFixedAdd
   * Test add(maxFixedAdd+1,maxFixedAdd+1) throws
   */
  function add(Fraction memory x, Fraction memory y) internal pure returns (Fraction memory) {
    uint256 z = x.value + y.value;
    require(z >= x.value, "add overflow detected");
    return Fraction(z);
  }

  /**
   * @notice x-y.
   * @dev
   * Test subtract(6, 10) fails
   */
  function subtract(Fraction memory x, Fraction memory y) internal pure returns (Fraction memory) {
    require(x.value >= y.value, "substraction underflow detected");
    return Fraction(x.value - y.value);
  }

  /**
   * @notice x*y. If any of the operators is higher than the max multiplier value it
   * might overflow.
   * @dev The maximum value that can be safely used as a multiplication operator
   * (maxFixedMul) is calculated as sqrt(maxUint256()*fixed1()),
   * or 340282366920938463463374607431768211455999999999999
   * Test multiply(0,0) returns 0
   * Test multiply(maxFixedMul,0) returns 0
   * Test multiply(0,maxFixedMul) returns 0
   * Test multiply(fixed1()/mulPrecision(),fixed1()*mulPrecision()) returns fixed1()
   * Test multiply(maxFixedMul,maxFixedMul) is around maxUint256()
   * Test multiply(maxFixedMul+1,maxFixedMul+1) fails
   */
  function multiply(Fraction memory x, Fraction memory y) internal pure returns (Fraction memory) {
    if (x.value == 0 || y.value == 0) return Fraction(0);
    if (y.value == FIXED1_UINT) return x;
    if (x.value == FIXED1_UINT) return y;

    // Separate into integer and fractional parts
    // x = x1 + x2, y = y1 + y2
    uint256 x1 = integer(x).value / FIXED1_UINT;
    uint256 x2 = fractional(x).value;
    uint256 y1 = integer(y).value / FIXED1_UINT;
    uint256 y2 = fractional(y).value;

    // (x1 + x2) * (y1 + y2) = (x1 * y1) + (x1 * y2) + (x2 * y1) + (x2 * y2)
    uint256 x1y1 = x1 * y1;
    if (x1 != 0) require(x1y1 / x1 == y1, "overflow x1y1 detected");

    // x1y1 needs to be multiplied back by fixed1
    // solium-disable-next-line mixedcase
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

    // result = fixed1() * x1 * y1 + x1 * y2 + x2 * y1 + x2 * y2 / fixed1();
    Fraction memory result = Fraction(x1y1);
    result = add(result, Fraction(x2y1)); // Add checks for overflow
    result = add(result, Fraction(x1y2)); // Add checks for overflow
    result = add(result, Fraction(x2y2)); // Add checks for overflow
    return result;
  }

  /**
   * @notice 1/x
   * @dev
   * Test reciprocal(0) fails
   * Test reciprocal(fixed1()) returns fixed1()
   * Test reciprocal(fixed1()*fixed1()) returns 1 // Testing how the fractional is truncated
   * Test reciprocal(1+fixed1()*fixed1()) returns 0 // Testing how the fractional is truncated
   * Test reciprocal(newFixedFraction(1, 1e24)) returns newFixed(1e24)
   */
  function reciprocal(Fraction memory x) internal pure returns (Fraction memory) {
    require(x.value != 0, "can't call reciprocal(0)");
    return Fraction((FIXED1_UINT * FIXED1_UINT) / x.value); // Can't overflow
  }

  /**
   * @notice x/y. If the dividend is higher than the max dividend value, it
   * might overflow. You can use multiply(x,reciprocal(y)) instead.
   * @dev The maximum value that can be safely used as a dividend (maxNewFixed) is defined as
   * divide(maxNewFixed,newFixedFraction(1,fixed1())) is around maxUint256().
   * This yields the value 115792089237316195423570985008687907853269984665640564.
   * Test maxNewFixed equals maxUint256()/fixed1()
   * Test divide(maxNewFixed,1) equals maxNewFixed*(fixed1)
   * Test divide(maxNewFixed+1,multiply(mulPrecision(),mulPrecision())) throws
   * Test divide(fixed1(),0) fails
   * Test divide(maxNewFixed,1) = maxNewFixed*(10^digits())
   * Test divide(maxNewFixed+1,1) throws
   */
  function divide(Fraction memory x, Fraction memory y) internal pure returns (Fraction memory) {
    require(y.value != 0, "can't divide by 0");
    uint256 X = x.value * FIXED1_UINT;
    require(X / FIXED1_UINT == x.value, "overflow at divide");
    return Fraction(X / y.value);
  }

  /**
   * @notice x > y
   */
  function gt(Fraction memory x, Fraction memory y) internal pure returns (bool) {
    return x.value > y.value;
  }

  /**
   * @notice x >= y
   */
  function gte(Fraction memory x, Fraction memory y) internal pure returns (bool) {
    return x.value >= y.value;
  }

  /**
   * @notice x < y
   */
  function lt(Fraction memory x, Fraction memory y) internal pure returns (bool) {
    return x.value < y.value;
  }

  /**
   * @notice x <= y
   */
  function lte(Fraction memory x, Fraction memory y) internal pure returns (bool) {
    return x.value <= y.value;
  }

  /**
   * @notice x == y
   */
  function equals(Fraction memory x, Fraction memory y) internal pure returns (bool) {
    return x.value == y.value;
  }

  /**
   * @notice x <= 1
   */
  function isProperFraction(Fraction memory x) internal pure returns (bool) {
    return lte(x, fixed1());
  }
}


pragma solidity ^0.5.13;

contract CalledByVm {
  modifier onlyVm() {
    require(msg.sender == address(0), "Only VM can call");
    _;
  }
}