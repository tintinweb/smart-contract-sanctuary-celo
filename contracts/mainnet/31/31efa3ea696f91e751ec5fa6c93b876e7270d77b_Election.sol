pragma solidity ^0.5.13;

import "openzeppelin-solidity/contracts/math/Math.sol";
import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "openzeppelin-solidity/contracts/ownership/Ownable.sol";

import "./interfaces/IElection.sol";
import "./interfaces/IValidators.sol";
import "../common/CalledByVm.sol";
import "../common/Initializable.sol";
import "../common/FixidityLib.sol";
import "../common/linkedlists/AddressSortedLinkedList.sol";
import "../common/UsingPrecompiles.sol";
import "../common/UsingRegistry.sol";
import "../common/interfaces/ICeloVersionedContract.sol";
import "../common/libraries/Heap.sol";
import "../common/libraries/ReentrancyGuard.sol";

contract Election is
  IElection,
  ICeloVersionedContract,
  Ownable,
  ReentrancyGuard,
  Initializable,
  UsingRegistry,
  UsingPrecompiles,
  CalledByVm
{
  using AddressSortedLinkedList for SortedLinkedList.List;
  using FixidityLib for FixidityLib.Fraction;
  using SafeMath for uint256;

  // 1e20 ensures that units can be represented as precisely as possible to avoid rounding errors
  // when translating to votes, without risking integer overflow.
  // A maximum of 1,000,000,000 CELO (1e27) yields a maximum of 1e47 units, whose product is at
  // most 1e74, which is less than 2^256.
  uint256 private constant UNIT_PRECISION_FACTOR = 100000000000000000000;

  struct PendingVote {
    // The value of the vote, in gold.
    uint256 value;
    // The epoch at which the vote was cast.
    uint256 epoch;
  }

  struct GroupPendingVotes {
    // The total number of pending votes that have been cast for this group.
    uint256 total;
    // Pending votes cast per voter.
    mapping(address => PendingVote) byAccount;
  }

  // Pending votes are those for which no following elections have been held.
  // These votes have yet to contribute to the election of validators and thus do not accrue
  // rewards.
  struct PendingVotes {
    // The total number of pending votes cast across all groups.
    uint256 total;
    mapping(address => GroupPendingVotes) forGroup;
  }

  struct GroupActiveVotes {
    // The total number of active votes that have been cast for this group.
    uint256 total;
    // The total number of active votes by a voter is equal to the number of active vote units for
    // that voter times the total number of active votes divided by the total number of active
    // vote units.
    uint256 totalUnits;
    mapping(address => uint256) unitsByAccount;
  }

  // Active votes are those for which at least one following election has been held.
  // These votes have contributed to the election of validators and thus accrue rewards.
  struct ActiveVotes {
    // The total number of active votes cast across all groups.
    uint256 total;
    mapping(address => GroupActiveVotes) forGroup;
  }

  struct TotalVotes {
    // A list of eligible ValidatorGroups sorted by total (pending+active) votes.
    // Note that this list will omit ineligible ValidatorGroups, including those that may have > 0
    // total votes.
    SortedLinkedList.List eligible;
  }

  struct Votes {
    PendingVotes pending;
    ActiveVotes active;
    TotalVotes total;
    // Maps an account to the list of groups it's voting for.
    mapping(address => address[]) groupsVotedFor;
  }

  struct ElectableValidators {
    uint256 min;
    uint256 max;
  }

  Votes private votes;
  // Governs the minimum and maximum number of validators that can be elected.
  ElectableValidators public electableValidators;
  // Governs how many validator groups a single account can vote for.
  uint256 public maxNumGroupsVotedFor;
  // Groups must receive at least this fraction of the total votes in order to be considered in
  // elections.
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

  /**
   * @notice Returns the storage, major, minor, and patch version of the contract.
   * @return The storage, major, minor, and patch version of the contract.
   */
  function getVersionNumber() external pure returns (uint256, uint256, uint256, uint256) {
    return (1, 1, 2, 0);
  }

  /**
   * @notice Used in place of the constructor to allow the contract to be upgradable via proxy.
   * @param registryAddress The address of the registry core smart contract.
   * @param minElectableValidators The minimum number of validators that can be elected.
   * @param _maxNumGroupsVotedFor The maximum number of groups that an account can vote for at once.
   * @param _electabilityThreshold The minimum ratio of votes a group needs before its members can
   *   be elected.
   * @dev Should be called only once.
   */
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

  /**
   * @notice Sets initialized == true on implementation contracts
   * @param test Set to true to skip implementation initialization
   */
  constructor(bool test) public Initializable(test) {}

  /**
   * @notice Updates the minimum and maximum number of validators that can be elected.
   * @param min The minimum number of validators that can be elected.
   * @param max The maximum number of validators that can be elected.
   * @return True upon success.
   */
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

  /**
   * @notice Returns the minimum and maximum number of validators that can be elected.
   * @return The minimum and maximum number of validators that can be elected.
   */
  function getElectableValidators() external view returns (uint256, uint256) {
    return (electableValidators.min, electableValidators.max);
  }

  /**
   * @notice Updates the maximum number of groups an account can be voting for at once.
   * @param _maxNumGroupsVotedFor The maximum number of groups an account can vote for.
   * @return True upon success.
   */
  function setMaxNumGroupsVotedFor(uint256 _maxNumGroupsVotedFor) public onlyOwner returns (bool) {
    require(_maxNumGroupsVotedFor != maxNumGroupsVotedFor, "Max groups voted for not changed");
    maxNumGroupsVotedFor = _maxNumGroupsVotedFor;
    emit MaxNumGroupsVotedForSet(_maxNumGroupsVotedFor);
    return true;
  }

  /**
   * @notice Sets the electability threshold.
   * @param threshold Electability threshold as unwrapped Fraction.
   * @return True upon success.
   */
  function setElectabilityThreshold(uint256 threshold) public onlyOwner returns (bool) {
    electabilityThreshold = FixidityLib.wrap(threshold);
    require(
      electabilityThreshold.lt(FixidityLib.fixed1()),
      "Electability threshold must be lower than 100%"
    );
    emit ElectabilityThresholdSet(threshold);
    return true;
  }

  /**
   * @notice Gets the election threshold.
   * @return Threshold value as unwrapped fraction.
   */
  function getElectabilityThreshold() external view returns (uint256) {
    return electabilityThreshold.unwrap();
  }

  /**
   * @notice Increments the number of total and pending votes for `group`.
   * @param group The validator group to vote for.
   * @param value The amount of gold to use to vote.
   * @param lesser The group receiving fewer votes than `group`, or 0 if `group` has the
   *   fewest votes of any validator group.
   * @param greater The group receiving more votes than `group`, or 0 if `group` has the
   *   most votes of any validator group.
   * @return True upon success.
   * @dev Fails if `group` is empty or not a validator group.
   */
  function vote(address group, uint256 value, address lesser, address greater)
    external
    nonReentrant
    returns (bool)
  {
    require(votes.total.eligible.contains(group), "Group not eligible");
    require(0 < value, "Vote value cannot be zero");
    require(canReceiveVotes(group, value), "Group cannot receive votes");
    address account = getAccounts().voteSignerToAccount(msg.sender);

    // Add group to the groups voted for by the account.
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

  /**
   * @notice Converts `account`'s pending votes for `group` to active votes.
   * @param group The validator group to vote for.
   * @return True upon success.
   * @dev Pending votes cannot be activated until an election has been held.
   */
  function activate(address group) external nonReentrant returns (bool) {
    address account = getAccounts().voteSignerToAccount(msg.sender);
    return _activate(group, account);
  }

  /**
   * @notice Converts `account`'s pending votes for `group` to active votes.
   * @param group The validator group to vote for.
   * @param account The validateor group account's pending votes to active votes
   * @return True upon success.
   * @dev Pending votes cannot be activated until an election has been held.
   */
  function activateForAccount(address group, address account) external nonReentrant returns (bool) {
    return _activate(group, account);
  }

  function _activate(address group, address account) internal returns (bool) {
    PendingVote storage pendingVote = votes.pending.forGroup[group].byAccount[account];
    require(pendingVote.epoch < getEpochNumber(), "Pending vote epoch not passed");
    uint256 value = pendingVote.value;
    require(value > 0, "Vote value cannot be zero");
    decrementPendingVotes(group, account, value);
    uint256 units = incrementActiveVotes(group, account, value);
    emit ValidatorGroupVoteActivated(account, group, value, units);
    return true;
  }

  /**
   * @notice Returns whether or not an account's votes for the specified group can be activated.
   * @param account The account with pending votes.
   * @param group The validator group that `account` has pending votes for.
   * @return Whether or not `account` has activatable votes for `group`.
   * @dev Pending votes cannot be activated until an election has been held.
   */
  function hasActivatablePendingVotes(address account, address group) external view returns (bool) {
    PendingVote storage pendingVote = votes.pending.forGroup[group].byAccount[account];
    return pendingVote.epoch < getEpochNumber() && pendingVote.value > 0;
  }

  /**
   * @notice Revokes `value` pending votes for `group`
   * @param group The validator group to revoke votes from.
   * @param value The number of votes to revoke.
   * @param lesser The group receiving fewer votes than the group for which the vote was revoked,
   *   or 0 if that group has the fewest votes of any validator group.
   * @param greater The group receiving more votes than the group for which the vote was revoked,
   *   or 0 if that group has the most votes of any validator group.
   * @param index The index of the group in the account's voting list.
   * @return True upon success.
   * @dev Fails if the account has not voted on a validator group.
   */
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

  /**
   * @notice Revokes all active votes for `group`
   * @param group The validator group to revoke votes from.
   * @param lesser The group receiving fewer votes than the group for which the vote was revoked,
   *   or 0 if that group has the fewest votes of any validator group.
   * @param greater The group receiving more votes than the group for which the vote was revoked,
   *   or 0 if that group has the most votes of any validator group.
   * @param index The index of the group in the account's voting list.
   * @return True upon success.
   * @dev Fails if the account has not voted on a validator group.
   */
  function revokeAllActive(address group, address lesser, address greater, uint256 index)
    external
    nonReentrant
    returns (bool)
  {
    address account = getAccounts().voteSignerToAccount(msg.sender);
    uint256 value = getActiveVotesForGroupByAccount(group, account);
    return _revokeActive(group, value, lesser, greater, index);
  }

  /**
   * @notice Revokes `value` active votes for `group`
   * @param group The validator group to revoke votes from.
   * @param value The number of votes to revoke.
   * @param lesser The group receiving fewer votes than the group for which the vote was revoked,
   *   or 0 if that group has the fewest votes of any validator group.
   * @param greater The group receiving more votes than the group for which the vote was revoked,
   *   or 0 if that group has the most votes of any validator group.
   * @param index The index of the group in the account's voting list.
   * @return True upon success.
   * @dev Fails if the account has not voted on a validator group.
   */
  function revokeActive(
    address group,
    uint256 value,
    address lesser,
    address greater,
    uint256 index
  ) external nonReentrant returns (bool) {
    return _revokeActive(group, value, lesser, greater, index);
  }

  function _revokeActive(
    address group,
    uint256 value,
    address lesser,
    address greater,
    uint256 index
  ) internal returns (bool) {
    // TODO(asa): Dedup with revokePending.
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

  /**
   * @notice Decrements `value` pending or active votes for `group` from `account`.
   *         First revokes all pending votes and then, if `value` votes haven't
   *         been revoked yet, revokes additional active votes.
   *         Fundamentally calls `revokePending` and `revokeActive` but only resorts groups once.
   * @param account The account whose votes to `group` should be decremented.
   * @param group The validator group to decrement votes from.
   * @param maxValue The maxinum number of votes to decrement and revoke.
   * @param lesser The group receiving fewer votes than the group for which the vote was revoked,
   *               or 0 if that group has the fewest votes of any validator group.
   * @param greater The group receiving more votes than the group for which the vote was revoked,
   *                or 0 if that group has the most votes of any validator group.
   * @param index The index of the group in the account's voting list.
   * @return uint256 Number of votes successfully decremented and revoked, with a max of `value`.
   */
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

  /**
   * @notice Returns the total number of votes cast by an account.
   * @param account The address of the account.
   * @return The total number of votes cast by an account.
   */
  function getTotalVotesByAccount(address account) external view returns (uint256) {
    uint256 total = 0;
    address[] memory groups = votes.groupsVotedFor[account];
    for (uint256 i = 0; i < groups.length; i = i.add(1)) {
      total = total.add(getTotalVotesForGroupByAccount(groups[i], account));
    }
    return total;
  }

  /**
   * @notice Returns the pending votes for `group` made by `account`.
   * @param group The address of the validator group.
   * @param account The address of the voting account.
   * @return The pending votes for `group` made by `account`.
   */
  function getPendingVotesForGroupByAccount(address group, address account)
    public
    view
    returns (uint256)
  {
    return votes.pending.forGroup[group].byAccount[account].value;
  }

  /**
   * @notice Returns the active votes for `group` made by `account`.
   * @param group The address of the validator group.
   * @param account The address of the voting account.
   * @return The active votes for `group` made by `account`.
   */
  function getActiveVotesForGroupByAccount(address group, address account)
    public
    view
    returns (uint256)
  {
    return unitsToVotes(group, votes.active.forGroup[group].unitsByAccount[account]);
  }

  /**
   * @notice Returns the total votes for `group` made by `account`.
   * @param group The address of the validator group.
   * @param account The address of the voting account.
   * @return The total votes for `group` made by `account`.
   */
  function getTotalVotesForGroupByAccount(address group, address account)
    public
    view
    returns (uint256)
  {
    uint256 pending = getPendingVotesForGroupByAccount(group, account);
    uint256 active = getActiveVotesForGroupByAccount(group, account);
    return pending.add(active);
  }

  /**
   * @notice Returns the active vote units for `group` made by `account`.
   * @param group The address of the validator group.
   * @param account The address of the voting account.
   * @return The active vote units for `group` made by `account`.
   */
  function getActiveVoteUnitsForGroupByAccount(address group, address account)
    external
    view
    returns (uint256)
  {
    return votes.active.forGroup[group].unitsByAccount[account];
  }

  /**
   * @notice Returns the total active vote units made for `group`.
   * @param group The address of the validator group.
   * @return The total active vote units made for `group`.
   */
  function getActiveVoteUnitsForGroup(address group) external view returns (uint256) {
    return votes.active.forGroup[group].totalUnits;
  }

  /**
   * @notice Returns the total votes made for `group`.
   * @param group The address of the validator group.
   * @return The total votes made for `group`.
   */
  function getTotalVotesForGroup(address group) public view returns (uint256) {
    return votes.pending.forGroup[group].total.add(votes.active.forGroup[group].total);
  }

  /**
   * @notice Returns the active votes made for `group`.
   * @param group The address of the validator group.
   * @return The active votes made for `group`.
   */
  function getActiveVotesForGroup(address group) public view returns (uint256) {
    return votes.active.forGroup[group].total;
  }

  /**
   * @notice Returns the pending votes made for `group`.
   * @param group The address of the validator group.
   * @return The pending votes made for `group`.
   */
  function getPendingVotesForGroup(address group) public view returns (uint256) {
    return votes.pending.forGroup[group].total;
  }

  /**
   * @notice Returns whether or not a group is eligible to receive votes.
   * @return Whether or not a group is eligible to receive votes.
   * @dev Eligible groups that have received their maximum number of votes cannot receive more.
   */
  function getGroupEligibility(address group) external view returns (bool) {
    return votes.total.eligible.contains(group);
  }

  /**
   * @notice Returns the amount of rewards that voters for `group` are due at the end of an epoch.
   * @param group The group to calculate epoch rewards for.
   * @param totalEpochRewards The total amount of rewards going to all voters.
   * @param uptimes Array of Fixidity representations of the validators' uptimes, between 0 and 1.
   * @return The amount of rewards that voters for `group` are due at the end of an epoch.
   * @dev Eligible groups that have received their maximum number of votes cannot receive more.
   */
  function getGroupEpochRewards(
    address group,
    uint256 totalEpochRewards,
    uint256[] calldata uptimes
  ) external view returns (uint256) {
    IValidators validators = getValidators();
    // The group must meet the balance requirements for their voters to receive epoch rewards.
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

  /**
   * @notice Distributes epoch rewards to voters for `group` in the form of active votes.
   * @param group The group whose voters will receive rewards.
   * @param value The amount of rewards to distribute to voters for the group.
   * @param lesser The group receiving fewer votes than `group` after the rewards are added.
   * @param greater The group receiving more votes than `group` after the rewards are added.
   * @dev Can only be called directly by the protocol.
   */
  function distributeEpochRewards(address group, uint256 value, address lesser, address greater)
    external
    onlyVm
  {
    _distributeEpochRewards(group, value, lesser, greater);
  }

  /**
   * @notice Distributes epoch rewards to voters for `group` in the form of active votes.
   * @param group The group whose voters will receive rewards.
   * @param value The amount of rewards to distribute to voters for the group.
   * @param lesser The group receiving fewer votes than `group` after the rewards are added.
   * @param greater The group receiving more votes than `group` after the rewards are added.
   */
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

  /**
   * @notice Increments the number of total votes for `group` by `value`.
   * @param group The validator group whose vote total should be incremented.
   * @param value The number of votes to increment.
   * @param lesser The group receiving fewer votes than the group for which the vote was cast,
   *   or 0 if that group has the fewest votes of any validator group.
   * @param greater The group receiving more votes than the group for which the vote was cast,
   *   or 0 if that group has the most votes of any validator group.
   */
  function incrementTotalVotes(address group, uint256 value, address lesser, address greater)
    private
  {
    uint256 newVoteTotal = votes.total.eligible.getValue(group).add(value);
    votes.total.eligible.update(group, newVoteTotal, lesser, greater);
  }

  /**
   * @notice Decrements the number of total votes for `group` by `value`.
   * @param group The validator group whose vote total should be decremented.
   * @param value The number of votes to decrement.
   * @param lesser The group receiving fewer votes than the group for which the vote was revoked,
   *   or 0 if that group has the fewest votes of any validator group.
   * @param greater The group receiving more votes than the group for which the vote was revoked,
   *   or 0 if that group has the most votes of any validator group.
   */
  function decrementTotalVotes(address group, uint256 value, address lesser, address greater)
    private
  {
    if (votes.total.eligible.contains(group)) {
      uint256 newVoteTotal = votes.total.eligible.getValue(group).sub(value);
      votes.total.eligible.update(group, newVoteTotal, lesser, greater);
    }
  }

  /**
   * @notice Marks a group ineligible for electing validators.
   * @param group The address of the validator group.
   * @dev Can only be called by the registered "Validators" contract.
   */
  function markGroupIneligible(address group)
    external
    onlyRegisteredContract(VALIDATORS_REGISTRY_ID)
  {
    votes.total.eligible.remove(group);
    emit ValidatorGroupMarkedIneligible(group);
  }

  /**
   * @notice Marks a group eligible for electing validators.
   * @param group The address of the validator group.
   * @param lesser The address of the group that has received fewer votes than this group.
   * @param greater The address of the group that has received more votes than this group.
   */
  function markGroupEligible(address group, address lesser, address greater)
    external
    onlyRegisteredContract(VALIDATORS_REGISTRY_ID)
  {
    uint256 value = getTotalVotesForGroup(group);
    votes.total.eligible.insert(group, value, lesser, greater);
    emit ValidatorGroupMarkedEligible(group);
  }

  /**
   * @notice Increments the number of pending votes for `group` made by `account`.
   * @param group The address of the validator group.
   * @param account The address of the voting account.
   * @param value The number of votes.
   */
  function incrementPendingVotes(address group, address account, uint256 value) private {
    PendingVotes storage pending = votes.pending;
    pending.total = pending.total.add(value);

    GroupPendingVotes storage groupPending = pending.forGroup[group];
    groupPending.total = groupPending.total.add(value);

    PendingVote storage pendingVote = groupPending.byAccount[account];
    pendingVote.value = pendingVote.value.add(value);
    pendingVote.epoch = getEpochNumber();
  }

  /**
   * @notice Decrements the number of pending votes for `group` made by `account`.
   * @param group The address of the validator group.
   * @param account The address of the voting account.
   * @param value The number of votes.
   */
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

  /**
   * @notice Increments the number of active votes for `group` made by `account`.
   * @param group The address of the validator group.
   * @param account The address of the voting account.
   * @param value The number of votes.
   */
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

  /**
   * @notice Decrements the number of active votes for `group` made by `account`.
   * @param group The address of the validator group.
   * @param account The address of the voting account.
   * @param value The number of votes.
   */
  function decrementActiveVotes(address group, address account, uint256 value)
    private
    returns (uint256)
  {
    ActiveVotes storage active = votes.active;
    active.total = active.total.sub(value);

    // Rounding may cause votesToUnits to return 0 for value != 0, preventing users
    // from revoking the last of their votes. The case where value == votes is special cased
    // to prevent this.
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

  /**
   * @notice Returns the number of units corresponding to `value` active votes.
   * @param group The address of the validator group.
   * @param value The number of active votes.
   * @return The corresponding number of units.
   */
  function votesToUnits(address group, uint256 value) private view returns (uint256) {
    if (votes.active.forGroup[group].totalUnits == 0) {
      return value.mul(UNIT_PRECISION_FACTOR);
    } else {
      return
        value.mul(votes.active.forGroup[group].totalUnits).div(votes.active.forGroup[group].total);
    }
  }

  /**
   * @notice Returns the number of active votes corresponding to `value` units.
   * @param group The address of the validator group.
   * @param value The number of units.
   * @return The corresponding number of active votes.
   */
  function unitsToVotes(address group, uint256 value) private view returns (uint256) {
    if (votes.active.forGroup[group].totalUnits == 0) {
      return 0;
    } else {
      return
        value.mul(votes.active.forGroup[group].total).div(votes.active.forGroup[group].totalUnits);
    }
  }

  /**
   * @notice Returns the groups that `account` has voted for.
   * @param account The address of the account casting votes.
   * @return The groups that `account` has voted for.
   */
  function getGroupsVotedForByAccount(address account) external view returns (address[] memory) {
    return votes.groupsVotedFor[account];
  }

  /**
   * @notice Deletes an element from a list of addresses.
   * @param list The list of addresses.
   * @param element The address to delete.
   * @param index The index of `element` in the list.
   */
  function deleteElement(address[] storage list, address element, uint256 index) private {
    require(index < list.length && list[index] == element, "Bad index");
    uint256 lastIndex = list.length.sub(1);
    list[index] = list[lastIndex];
    list.length = lastIndex;
  }

  /**
   * @notice Returns whether or not a group can receive the specified number of votes.
   * @param group The address of the group.
   * @param value The number of votes.
   * @return Whether or not a group can receive the specified number of votes.
   * @dev Votes are not allowed to be cast that would increase a group's proportion of locked gold
   *   voting for it to greater than
   *   (numGroupMembers + 1) / min(maxElectableValidators, numRegisteredValidators)
   * @dev Note that groups may still receive additional votes via rewards even if this function
   *   returns false.
   */
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

  /**
   * @notice Returns the number of votes that a group can receive.
   * @param group The address of the group.
   * @return The number of votes that a group can receive.
   * @dev Votes are not allowed to be cast that would increase a group's proportion of locked gold
   *   voting for it to greater than
   *   (numGroupMembers + 1) / min(maxElectableValidators, numRegisteredValidators)
   * @dev Note that a group's vote total may exceed this number through rewards or config changes.
   */
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

  /**
   * @notice Returns the total votes received across all groups.
   * @return The total votes received across all groups.
   */
  function getTotalVotes() public view returns (uint256) {
    return votes.active.total.add(votes.pending.total);
  }

  /**
   * @notice Returns the active votes received across all groups.
   * @return The active votes received across all groups.
   */
  function getActiveVotes() public view returns (uint256) {
    return votes.active.total;
  }

  /**
   * @notice Returns the list of validator groups eligible to elect validators.
   * @return The list of validator groups eligible to elect validators.
   */
  function getEligibleValidatorGroups() external view returns (address[] memory) {
    return votes.total.eligible.getKeys();
  }

  /**
   * @notice Returns lists of all validator groups and the number of votes they've received.
   * @return Lists of all validator groups and the number of votes they've received.
   */
  function getTotalVotesForEligibleValidatorGroups()
    external
    view
    returns (address[] memory groups, uint256[] memory values)
  {
    return votes.total.eligible.getElements();
  }

  /**
   * @notice Returns a list of elected validators with seats allocated to groups via the D'Hondt
   *   method.
   * @return The list of elected validators.
   */
  function electValidatorSigners() external view returns (address[] memory) {
    return electNValidatorSigners(electableValidators.min, electableValidators.max);
  }

  /**
   * @notice Returns a list of elected validators with seats allocated to groups via the D'Hondt
   *   method.
   * @return The list of elected validators.
   * @dev See https://en.wikipedia.org/wiki/D%27Hondt_method#Allocation for more information.
   */
  function electNValidatorSigners(uint256 minElectableValidators, uint256 maxElectableValidators)
    public
    view
    returns (address[] memory)
  {
    // Groups must have at least `electabilityThreshold` proportion of the total votes to be
    // considered for the election.
    uint256 requiredVotes = electabilityThreshold
      .multiply(FixidityLib.newFixed(getTotalVotes()))
      .fromFixed();
    // Only consider groups with at least `requiredVotes` but do not consider more groups than the
    // max number of electable validators.
    uint256 numElectionGroups = votes.total.eligible.numElementsGreaterThan(
      requiredVotes,
      maxElectableValidators
    );
    address[] memory electionGroups = votes.total.eligible.headN(numElectionGroups);
    uint256[] memory numMembers = getValidators().getGroupsNumMembers(electionGroups);
    // Holds the number of members elected for each of the eligible validator groups.
    uint256[] memory numMembersElected = new uint256[](electionGroups.length);
    uint256 totalNumMembersElected = 0;

    uint256[] memory keys = new uint256[](electionGroups.length);
    FixidityLib.Fraction[] memory votesForNextMember = new FixidityLib.Fraction[](
      electionGroups.length
    );
    for (uint256 i = 0; i < electionGroups.length; i = i.add(1)) {
      keys[i] = i;
      votesForNextMember[i] = FixidityLib.newFixed(
        votes.total.eligible.getValue(electionGroups[i])
      );
    }

    // Assign a number of seats to each validator group.
    while (totalNumMembersElected < maxElectableValidators && electionGroups.length > 0) {
      uint256 groupIndex = keys[0];
      // All electable validators have been elected.
      if (votesForNextMember[groupIndex].unwrap() == 0) break;
      // All members of the group have been elected
      if (numMembers[groupIndex] <= numMembersElected[groupIndex]) {
        votesForNextMember[groupIndex] = FixidityLib.wrap(0);
      } else {
        // Elect the next member from the validator group
        numMembersElected[groupIndex] = numMembersElected[groupIndex].add(1);
        totalNumMembersElected = totalNumMembersElected.add(1);
        // If there are already n elected members in a group, the votes for the next member
        // are total votes of group divided by n+1
        votesForNextMember[groupIndex] = FixidityLib
          .newFixed(votes.total.eligible.getValue(electionGroups[groupIndex]))
          .divide(FixidityLib.newFixed(numMembersElected[groupIndex].add(1)));
      }
      Heap.heapifyDown(keys, votesForNextMember);
    }
    require(totalNumMembersElected >= minElectableValidators, "Not enough elected validators");
    // Grab the top validators from each group that won seats.
    address[] memory electedValidators = new address[](totalNumMembersElected);
    totalNumMembersElected = 0;
    for (uint256 i = 0; i < electionGroups.length; i = i.add(1)) {
      // We use the validating delegate if one is set.
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

  /**
   * @notice Returns get current validator signers using the precompiles.
   * @return List of current validator signers.
   */
  function getCurrentValidatorSigners() public view returns (address[] memory) {
    uint256 n = numberValidatorsInCurrentSet();
    address[] memory res = new address[](n);
    for (uint256 i = 0; i < n; i = i.add(1)) {
      res[i] = validatorSignerAddressFromCurrentSet(i);
    }
    return res;
  }

  // Struct to hold local variables for `forceDecrementVotes`.
  // Needed to prevent solc error of "stack too deep" from too many local vars.
  struct DecrementVotesInfo {
    address[] groups;
    uint256 remainingValue;
  }

  /**
   * @notice Reduces the total amount of `account`'s voting gold by `value` by
   *         iterating over all groups voted for by account.
   * @param account Address to revoke votes from.
   * @param value Maximum amount of votes to revoke.
   * @param lessers The groups receiving fewer votes than the i'th `group`, or 0 if
   *                the i'th `group` has the fewest votes of any validator group.
   * @param greaters The groups receivier more votes than the i'th `group`, or 0 if
   *                the i'th `group` has the most votes of any validator group.
   * @param indices The indices of the i'th group in the account's voting list.
   * @return Number of votes successfully decremented.
   */
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
    // Iterate in reverse order to hopefully optimize removing pending votes before active votes
    // And to attempt to preserve `account`'s earliest votes (assuming earliest = prefered)
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
    return value;
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

import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "./LinkedList.sol";

/**
 * @title Maintains a sorted list of unsigned ints keyed by bytes32.
 */
library SortedLinkedList {
  using SafeMath for uint256;
  using LinkedList for LinkedList.List;

  struct List {
    LinkedList.List list;
    mapping(bytes32 => uint256) values;
  }

  /**
   * @notice Inserts an element into a doubly linked list.
   * @param list A storage pointer to the underlying list.
   * @param key The key of the element to insert.
   * @param value The element value.
   * @param lesserKey The key of the element less than the element to insert.
   * @param greaterKey The key of the element greater than the element to insert.
   */
  function insert(
    List storage list,
    bytes32 key,
    uint256 value,
    bytes32 lesserKey,
    bytes32 greaterKey
  ) internal {
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

  /**
   * @notice Removes an element from the doubly linked list.
   * @param list A storage pointer to the underlying list.
   * @param key The key of the element to remove.
   */
  function remove(List storage list, bytes32 key) internal {
    list.list.remove(key);
    list.values[key] = 0;
  }

  /**
   * @notice Updates an element in the list.
   * @param list A storage pointer to the underlying list.
   * @param key The element key.
   * @param value The element value.
   * @param lesserKey The key of the element will be just left of `key` after the update.
   * @param greaterKey The key of the element will be just right of `key` after the update.
   * @dev Note that only one of "lesserKey" or "greaterKey" needs to be correct to reduce friction.
   */
  function update(
    List storage list,
    bytes32 key,
    uint256 value,
    bytes32 lesserKey,
    bytes32 greaterKey
  ) internal {
    remove(list, key);
    insert(list, key, value, lesserKey, greaterKey);
  }

  /**
   * @notice Inserts an element at the tail of the doubly linked list.
   * @param list A storage pointer to the underlying list.
   * @param key The key of the element to insert.
   */
  function push(List storage list, bytes32 key) internal {
    insert(list, key, 0, bytes32(0), list.list.tail);
  }

  /**
   * @notice Removes N elements from the head of the list and returns their keys.
   * @param list A storage pointer to the underlying list.
   * @param n The number of elements to pop.
   * @return The keys of the popped elements.
   */
  function popN(List storage list, uint256 n) internal returns (bytes32[] memory) {
    require(n <= list.list.numElements, "not enough elements");
    bytes32[] memory keys = new bytes32[](n);
    for (uint256 i = 0; i < n; i = i.add(1)) {
      bytes32 key = list.list.head;
      keys[i] = key;
      remove(list, key);
    }
    return keys;
  }

  /**
   * @notice Returns whether or not a particular key is present in the sorted list.
   * @param list A storage pointer to the underlying list.
   * @param key The element key.
   * @return Whether or not the key is in the sorted list.
   */
  function contains(List storage list, bytes32 key) internal view returns (bool) {
    return list.list.contains(key);
  }

  /**
   * @notice Returns the value for a particular key in the sorted list.
   * @param list A storage pointer to the underlying list.
   * @param key The element key.
   * @return The element value.
   */
  function getValue(List storage list, bytes32 key) internal view returns (uint256) {
    return list.values[key];
  }

  /**
   * @notice Gets all elements from the doubly linked list.
   * @param list A storage pointer to the underlying list.
   * @return An unpacked list of elements from largest to smallest.
   */
  function getElements(List storage list)
    internal
    view
    returns (bytes32[] memory, uint256[] memory)
  {
    bytes32[] memory keys = getKeys(list);
    uint256[] memory values = new uint256[](keys.length);
    for (uint256 i = 0; i < keys.length; i = i.add(1)) {
      values[i] = list.values[keys[i]];
    }
    return (keys, values);
  }

  /**
   * @notice Gets all element keys from the doubly linked list.
   * @param list A storage pointer to the underlying list.
   * @return All element keys from head to tail.
   */
  function getKeys(List storage list) internal view returns (bytes32[] memory) {
    return list.list.getKeys();
  }

  /**
   * @notice Returns first N greatest elements of the list.
   * @param list A storage pointer to the underlying list.
   * @param n The number of elements to return.
   * @return The keys of the first n elements.
   * @dev Reverts if n is greater than the number of elements in the list.
   */
  function headN(List storage list, uint256 n) internal view returns (bytes32[] memory) {
    return list.list.headN(n);
  }

  /**
   * @notice Returns the keys of the elements greaterKey than and less than the provided value.
   * @param list A storage pointer to the underlying list.
   * @param value The element value.
   * @param lesserKey The key of the element which could be just left of the new value.
   * @param greaterKey The key of the element which could be just right of the new value.
   * @return The correct lesserKey/greaterKey keys.
   */
  function getLesserAndGreater(
    List storage list,
    uint256 value,
    bytes32 lesserKey,
    bytes32 greaterKey
  ) private view returns (bytes32, bytes32) {
    // Check for one of the following conditions and fail if none are met:
    //   1. The value is less than the current lowest value
    //   2. The value is greater than the current greatest value
    //   3. The value is just greater than the value for `lesserKey`
    //   4. The value is just less than the value for `greaterKey`
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

  /**
   * @notice Returns whether or not a given element is between two other elements.
   * @param list A storage pointer to the underlying list.
   * @param value The element value.
   * @param lesserKey The key of the element whose value should be lesserKey.
   * @param greaterKey The key of the element whose value should be greaterKey.
   * @return True if the given element is between the two other elements.
   */
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

import "openzeppelin-solidity/contracts/math/Math.sol";
import "openzeppelin-solidity/contracts/math/SafeMath.sol";

import "./SortedLinkedList.sol";

/**
 * @title Maintains a sorted list of unsigned ints keyed by address.
 */
library AddressSortedLinkedList {
  using SafeMath for uint256;
  using SortedLinkedList for SortedLinkedList.List;

  /**
   * @notice Returns the storage, major, minor, and patch version of the contract.
   * @return The storage, major, minor, and patch version of the contract.
   */
  function getVersionNumber() external pure returns (uint256, uint256, uint256, uint256) {
    return (1, 1, 1, 0);
  }

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
   * @param value The element value.
   * @param lesserKey The key of the element less than the element to insert.
   * @param greaterKey The key of the element greater than the element to insert.
   */
  function insert(
    SortedLinkedList.List storage list,
    address key,
    uint256 value,
    address lesserKey,
    address greaterKey
  ) public {
    list.insert(toBytes(key), value, toBytes(lesserKey), toBytes(greaterKey));
  }

  /**
   * @notice Removes an element from the doubly linked list.
   * @param list A storage pointer to the underlying list.
   * @param key The key of the element to remove.
   */
  function remove(SortedLinkedList.List storage list, address key) public {
    list.remove(toBytes(key));
  }

  /**
   * @notice Updates an element in the list.
   * @param list A storage pointer to the underlying list.
   * @param key The element key.
   * @param value The element value.
   * @param lesserKey The key of the element will be just left of `key` after the update.
   * @param greaterKey The key of the element will be just right of `key` after the update.
   * @dev Note that only one of "lesserKey" or "greaterKey" needs to be correct to reduce friction.
   */
  function update(
    SortedLinkedList.List storage list,
    address key,
    uint256 value,
    address lesserKey,
    address greaterKey
  ) public {
    list.update(toBytes(key), value, toBytes(lesserKey), toBytes(greaterKey));
  }

  /**
   * @notice Returns whether or not a particular key is present in the sorted list.
   * @param list A storage pointer to the underlying list.
   * @param key The element key.
   * @return Whether or not the key is in the sorted list.
   */
  function contains(SortedLinkedList.List storage list, address key) public view returns (bool) {
    return list.contains(toBytes(key));
  }

  /**
   * @notice Returns the value for a particular key in the sorted list.
   * @param list A storage pointer to the underlying list.
   * @param key The element key.
   * @return The element value.
   */
  function getValue(SortedLinkedList.List storage list, address key) public view returns (uint256) {
    return list.getValue(toBytes(key));
  }

  /**
   * @notice Gets all elements from the doubly linked list.
   * @return An unpacked list of elements from largest to smallest.
   */
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

  /**
   * @notice Returns the minimum of `max` and the  number of elements in the list > threshold.
   * @param list A storage pointer to the underlying list.
   * @param threshold The number that the element must exceed to be included.
   * @param max The maximum number returned by this function.
   * @return The minimum of `max` and the  number of elements in the list > threshold.
   */
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

  /**
   * @notice Returns the N greatest elements of the list.
   * @param list A storage pointer to the underlying list.
   * @param n The number of elements to return.
   * @return The keys of the greatest elements.
   */
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

  /**
   * @notice Gets all element keys from the doubly linked list.
   * @param list A storage pointer to the underlying list.
   * @return All element keys from head to tail.
   */
  function getKeys(SortedLinkedList.List storage list) public view returns (address[] memory) {
    return headN(list, list.list.numElements);
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

import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "../FixidityLib.sol";

/**
 * @title Simple heap implementation
 */
library Heap {
  using FixidityLib for FixidityLib.Fraction;
  using SafeMath for uint256;

  /**
   * @notice Fixes the heap invariant.
   * @param keys Pointers to values
   * @param values Values that are compared, only the pointers are changed by this method.
   * @param start Node for which the invariant might have changed.
   * @param length Size of the heap.
   */
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

  /**
   * @notice Fixes the heap invariant if top has been changed.
   * @param keys Pointers to values
   * @param values Values that are compared, only the pointers are changed by this method.
   */
  function heapifyDown(uint256[] memory keys, FixidityLib.Fraction[] memory values) internal pure {
    siftDown(keys, values, 0, keys.length);
  }

}


pragma solidity ^0.5.13;

interface IRegistry {
  function setAddressFor(string calldata, address) external;
  function getAddressForOrDie(bytes32) external view returns (address);
  function getAddressFor(bytes32) external view returns (address);
  function isOneOf(bytes32[] calldata, address) external view returns (bool);
}


pragma solidity ^0.5.13;

interface IFreezer {
  function isFrozen(address) external view returns (bool);
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