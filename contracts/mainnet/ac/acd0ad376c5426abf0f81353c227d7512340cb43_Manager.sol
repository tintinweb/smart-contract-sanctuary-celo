// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

import "./common/UsingRegistryUpgradeable.sol";
import "./common/UUPSOwnableUpgradeable.sol";
import "./interfaces/IAccount.sol";
import "./interfaces/IStakedCelo.sol";

/**
 * @title Manages the StakedCelo system, by controlling the minting and burning
 * of stCELO and implementing strategies for voting and unvoting of deposited or
 * withdrawn CELO.
 */
contract Manager is UUPSOwnableUpgradeable, UsingRegistryUpgradeable {
    using EnumerableSet for EnumerableSet.AddressSet;

    /**
     * @notice Holds a group's address and votes.
     * @param group The address of the group.
     * @param votes The votes assigned to the group.
     */
    struct GroupWithVotes {
        address group;
        uint256 votes;
    }

    /**
     * @notice An instance of the StakedCelo contract this Manager manages.
     */
    IStakedCelo internal stakedCelo;

    /**
     * @notice An instance of the Account contract this Manager manages.
     */
    IAccount internal account;

    /**
     * @notice The set of currently active groups that will be voted for with
     * new deposits.
     */
    EnumerableSet.AddressSet private activeGroups;

    /**
     * @notice The set of deprecated groups. These are groups that should no
     * longer receive new votes from deposits, but still need to be kept track
     * of because the Account contract is still voting for them.
     */
    EnumerableSet.AddressSet private deprecatedGroups;

    /**
     * @notice Emitted when a new group is activated for voting.
     * @param group The group's address.
     */
    event GroupActivated(address indexed group);
    /**
     * @notice Emitted when a group is deprecated.
     * @param group The group's address.
     */
    event GroupDeprecated(address indexed group);
    /**
     * @notice Emitted when a deprecated group is no longer being voted for and
     * the contract forgets about it entirely.
     * @param group The group's address.
     */
    event GroupRemoved(address indexed group);

    /**
     * @notice Used when attempting to activate a group that is already active.
     * @param group The group's address.
     */
    error GroupAlreadyAdded(address group);

    /**
     * @notice Used when attempting to deprecate a group that is not active.
     * @param group The group's address.
     */
    error GroupNotActive(address group);

    /**
     * @notice Used when an attempt to add an active group to the EnumerableSet
     * fails.
     * @param group The group's address.
     */
    error FailedToAddActiveGroup(address group);

    /**
     * @notice Used when an attempt to add a deprecated group to the
     * EnumerableSet fails.
     * @param group The group's address.
     */
    error FailedToAddDeprecatedGroup(address group);

    /**
     * @notice Used when an attempt to remove a deprecated group from the
     * EnumerableSet fails.
     * @param group The group's address.
     */
    error FailedToRemoveDeprecatedGroup(address group);

    /**
     * @notice Used when attempting to activate a group when the maximum number
     * of groups voted (as allowed by the Election contract) is already being
     * voted for.
     */
    error MaxGroupsVotedForReached();

    /**
     * @notice Used when attempting to deposit when there are not active groups
     * to vote for.
     */
    error NoActiveGroups();

    /**
     * @notice Used when attempting to deposit when the total deposit amount
     * would tip each active group over the voting limit as defined in
     * Election.sol.
     */
    error NoVotableGroups();

    /**
     * @notice Used when attempting to withdraw but there are no groups being
     * voted for.
     */
    error NoGroups();

    /**
     * @notice Used when attempting to withdraw 0 value.
     */
    error ZeroWithdrawal();

    /**
     * @notice Empty constructor for proxy implementation, `initializer` modifer ensures the
     * implementation gets initialized.
     */
    // solhint-disable-next-line no-empty-blocks
    constructor() initializer {}

    /**
     * @notice Initialize the contract with registry and owner.
     * @param _registry The address of the Celo registry.
     * @param _owner The address of the contract owner.
     */
    function initialize(address _registry, address _owner) external initializer {
        _transferOwnership(_owner);
        __UsingRegistry_init(_registry);
    }

    /**
     * @notice Set this contract's dependencies in the StakedCelo system.
     * @dev Manager, Account and StakedCelo all reference each other
     * so we need a way of setting these after all contracts are
     * deployed and initialized.
     * @param _stakedCelo the address of the StakedCelo contract.
     * @param _account The address of the Account contract.
     */
    function setDependencies(address _stakedCelo, address _account) external onlyOwner {
        stakedCelo = IStakedCelo(_stakedCelo);
        account = IAccount(_account);
    }

    /**
     * @notice Marks a group as votable.
     * @param group The address of the group to add to the set of votable
     * groups.
     * @dev Fails if the maximum number of groups are already being voted for by
     * the Account smart contract (as per the `maxNumGroupsVotedFor` in the
     * Election contract).
     */
    function activateGroup(address group) external onlyOwner {
        if (activeGroups.contains(group)) {
            revert GroupAlreadyAdded(group);
        }

        if (deprecatedGroups.contains(group)) {
            if (!deprecatedGroups.remove(group)) {
                revert FailedToRemoveDeprecatedGroup(group);
            }
        }

        if (
            activeGroups.length() + deprecatedGroups.length() >=
            getElection().maxNumGroupsVotedFor()
        ) {
            revert MaxGroupsVotedForReached();
        }

        if (!activeGroups.add(group)) {
            revert FailedToAddActiveGroup(group);
        }
        emit GroupActivated(group);
    }

    /**
     * @notice Returns the array of active groups.
     * @return The array of active groups.
     */
    function getGroups() external view returns (address[] memory) {
        return activeGroups.values();
    }

    /**
     * @notice Marks a group as deprecated.
     * @param group The group to deprecate.
     * @dev A deprecated group will remain in the `deprecatedGroups` array as
     * long as it is still being voted for by the Account contract. Deprecated
     * groups will be the first to have their votes withdrawn.
     */
    function deprecateGroup(address group) external onlyOwner {
        if (!activeGroups.remove(group)) {
            revert GroupNotActive(group);
        }

        emit GroupDeprecated(group);

        if (account.getCeloForGroup(group) > 0) {
            if (!deprecatedGroups.add(group)) {
                revert FailedToAddDeprecatedGroup(group);
            }
        } else {
            emit GroupRemoved(group);
        }
    }

    /**
     * @notice Returns the list of deprecated groups.
     * @return The list of deprecated groups.
     */
    function getDeprecatedGroups() external view returns (address[] memory) {
        return deprecatedGroups.values();
    }

    /**
     * @notice Used to deposit CELO into the StakedCelo system. The user will
     * receive an amount of stCELO proportional to their contribution. The CELO
     * will be scheduled to be voted for with the Account contract.
     */
    function deposit() external payable {
        if (activeGroups.length() == 0) {
            revert NoActiveGroups();
        }

        stakedCelo.mint(msg.sender, toStakedCelo(msg.value));

        distributeVotes(msg.value);
    }

    /**
     * @notice Used to withdraw CELO from the system, in exchange for burning
     * stCELO.
     * @param stakedCeloAmount The amount of stCELO to burn.
     * @dev Calculates the CELO amount based on the ratio of outstanding stCELO
     * and the total amount of CELO owned and used for voting by Account. See
     * `toCelo`.
     * @dev The funds need to be withdrawn using calls to `Account.withdraw` and
     * `Account.finishPendingWithdrawal`.
     */
    function withdraw(uint256 stakedCeloAmount) external {
        if (activeGroups.length() + deprecatedGroups.length() == 0) {
            revert NoGroups();
        }

        distributeWithdrawals(toCelo(stakedCeloAmount), msg.sender);

        stakedCelo.burn(msg.sender, stakedCeloAmount);
    }

    /**
     * @notice Computes the amount of stCELO that should be minted for a given
     * amount of CELO deposited.
     * @param celoAmount The amount of CELO deposited.
     * @return The amount of stCELO that should be minted.
     */
    function toStakedCelo(uint256 celoAmount) public view returns (uint256) {
        uint256 stCeloSupply = stakedCelo.totalSupply();
        uint256 celoBalance = account.getTotalCelo();

        if (stCeloSupply == 0 || celoBalance == 0) {
            return celoAmount;
        }

        return (celoAmount * stCeloSupply) / celoBalance;
    }

    /**
     * @notice Computes the amount of CELO that should be withdrawn for a given
     * amount of stCELO burned.
     * @param stCeloAmount The amount of stCELO burned.
     * @return The amount of CELO that should be withdrawn.
     */
    function toCelo(uint256 stCeloAmount) public view returns (uint256) {
        uint256 stCeloSupply = stakedCelo.totalSupply();
        uint256 celoBalance = account.getTotalCelo();

        if (stCeloSupply == 0 || celoBalance == 0) {
            return stCeloAmount;
        }

        return (stCeloAmount * celoBalance) / stCeloSupply;
    }

    /**
     * @notice Distributes votes by computing the number of votes each active
     * group should receive, then calling out to `Account.scheduleVotes`.
     * @param votes The amount of votes to distribute.
     * @dev The vote distribution strategy is to try and have each validator
     * group to be receiving the same amount of votes from the system. If a
     * group already has more votes than the average of the total available
     * votes it will not be voted for, and instead we'll try to evenly
     * distribute between the remaining groups.
     * @dev Election.sol sets a dynamic limit on the number of votes receivable
     * by a group, based on the group's size, the total amount of Locked
     * CELO, and the total number of electable validators. We don't want to
     * schedule votes for a group when the amount would exceed this threshold.
     * `getVotableGroups` below selects those groups that could receive the
     * entire `votes` amount, and filters out the rest. This is a heuristic:
     * when distributing votes evenly, the group might receive less than
     * `votes`, and the total amount could end up being under the limit.
     * However, doing an exact computation would be both complex and cost a lot
     * of additional gas, hence the heuristic. If indeed all groups are close to
     * their voting limit, causing a larger deposit to revert with
     * NoVotableGroups, despite there still being some room for deposits, this
     * can be worked around by sending a few smaller deposits.
     */
    function distributeVotes(uint256 votes) internal {
        /*
         * "Votable" groups are those that will currently fit under the voting
         * limit in Election.sol even if voted for with the entire `votes`
         * amount. Note that some might still not end up getting voted for given
         * the distribution logic below.
         */
        address[] memory votableGroups = getVotableGroups(votes);
        if (votableGroups.length == 0) {
            revert NoVotableGroups();
        }

        GroupWithVotes[] memory sortedGroups;
        uint256 availableVotes;
        (sortedGroups, availableVotes) = getSortedGroupsWithVotes(votableGroups);
        availableVotes += votes;

        uint256[] memory votesPerGroup = new uint256[](votableGroups.length);
        uint256 groupsVoted = votableGroups.length;
        uint256 targetVotes = availableVotes / groupsVoted;

        /*
         * This would normally be (i = votableGroups.length - 1; i >=0; i--),
         * but we can't i-- on the last iteration when i=0, since i is an
         * unsigned integer. So we iterate with the loop variable 1 greater than
         * expected, set index = i-1, and use index inside the loop.
         */
        for (uint256 i = votableGroups.length; i > 0; i--) {
            uint256 index = i - 1;
            if (sortedGroups[index].votes >= targetVotes) {
                groupsVoted--;
                availableVotes -= sortedGroups[index].votes;
                targetVotes = availableVotes / groupsVoted;
                votesPerGroup[index] = 0;
            } else {
                votesPerGroup[index] = targetVotes - sortedGroups[index].votes;

                if (availableVotes % groupsVoted > index) {
                    votesPerGroup[index]++;
                }
            }
        }

        address[] memory finalGroups = new address[](groupsVoted);
        uint256[] memory finalVotes = new uint256[](groupsVoted);

        for (uint256 i = 0; i < groupsVoted; i++) {
            finalGroups[i] = sortedGroups[i].group;
            finalVotes[i] = votesPerGroup[i];
        }

        account.scheduleVotes{value: votes}(finalGroups, finalVotes);
    }

    /**
     * @notice Distributes withdrawals by computing the number of votes that
     * should be withdrawn from each group, then calling out to
     * `Account.scheduleVotes`.
     * @param withdrawal The amount of votes to withdraw.
     * @param beneficiary The address that should end up receiving the withdrawn
     * CELO.
     * @dev The withdrawal distribution strategy is to:
     * 1. Withdraw as much as possible from any deprecated groups.
     * 2. If more votes still need to be withdrawn, try and have each validator
     * group end up receiving the same amount of votes from the system. If a
     * group already has less votes than the average of the total remaining
     * votes, it will not be withdrawn from, and instead we'll try to evenly
     * distribute between the remaining groups.
     */
    function distributeWithdrawals(uint256 withdrawal, address beneficiary) internal {
        if (withdrawal == 0) {
            revert ZeroWithdrawal();
        }

        address[] memory deprecatedGroupsWithdrawn;
        uint256[] memory deprecatedWithdrawalsPerGroup;
        uint256 numberDeprecatedGroupsWithdrawn;

        (
            deprecatedGroupsWithdrawn,
            deprecatedWithdrawalsPerGroup,
            numberDeprecatedGroupsWithdrawn,
            withdrawal
        ) = getDeprecatedGroupsWithdrawalDistribution(withdrawal);

        address[] memory groupsWithdrawn;
        uint256[] memory withdrawalsPerGroup;

        (groupsWithdrawn, withdrawalsPerGroup) = getActiveGroupWithdrawalDistribution(withdrawal);

        address[] memory finalGroups = new address[](
            groupsWithdrawn.length + numberDeprecatedGroupsWithdrawn
        );
        uint256[] memory finalVotes = new uint256[](
            groupsWithdrawn.length + numberDeprecatedGroupsWithdrawn
        );

        for (uint256 i = 0; i < numberDeprecatedGroupsWithdrawn; i++) {
            finalGroups[i] = deprecatedGroupsWithdrawn[i];
            finalVotes[i] = deprecatedWithdrawalsPerGroup[i];
        }

        for (uint256 i = 0; i < groupsWithdrawn.length; i++) {
            finalGroups[i + numberDeprecatedGroupsWithdrawn] = groupsWithdrawn[i];
            finalVotes[i + numberDeprecatedGroupsWithdrawn] = withdrawalsPerGroup[i];
        }

        account.scheduleWithdrawals(finalGroups, finalVotes, beneficiary);
    }

    /**
     * @notice Calculates how many votes should be withdrawn from each
     * deprecated group.
     * @param withdrawal The total amount of votes that needs to be withdrawn.
     * @return deprecatedGroupsWithdrawn The array of deprecated groups to be
     * withdrawn from.
     * @return deprecatedWithdrawalsPerGroup The amount of votes to withdraw
     * from the respective deprecated group in `deprecatedGroupsWithdrawn`.
     * @return numberDeprecatedGroupsWithdrawn The number of groups in
     * `deprecatedGroupsWithdrawn` that have a non zero withdrawal.
     * @return remainingWithdrawal The number of votes that still need to be
     * withdrawn after withdrawing from deprecated groups.
     * @dev Non zero entries of `deprecatedWithdrawalsPerGroup` will be exactly
     * a prefix of length `numberDeprecatedGroupsWithdrawn`.
     */
    function getDeprecatedGroupsWithdrawalDistribution(uint256 withdrawal)
        internal
        returns (
            address[] memory deprecatedGroupsWithdrawn,
            uint256[] memory deprecatedWithdrawalsPerGroup,
            uint256 numberDeprecatedGroupsWithdrawn,
            uint256 remainingWithdrawal
        )
    {
        remainingWithdrawal = withdrawal;
        uint256 numberDeprecatedGroups = deprecatedGroups.length();
        deprecatedGroupsWithdrawn = new address[](numberDeprecatedGroups);
        deprecatedWithdrawalsPerGroup = new uint256[](numberDeprecatedGroups);
        numberDeprecatedGroupsWithdrawn = 0;

        for (uint256 i = 0; i < numberDeprecatedGroups; i++) {
            numberDeprecatedGroupsWithdrawn++;
            deprecatedGroupsWithdrawn[i] = deprecatedGroups.at(i);
            uint256 currentVotes = account.getCeloForGroup(deprecatedGroupsWithdrawn[i]);
            deprecatedWithdrawalsPerGroup[i] = Math.min(remainingWithdrawal, currentVotes);
            remainingWithdrawal -= deprecatedWithdrawalsPerGroup[i];

            if (currentVotes == deprecatedWithdrawalsPerGroup[i]) {
                if (!deprecatedGroups.remove(deprecatedGroupsWithdrawn[i])) {
                    revert FailedToRemoveDeprecatedGroup(deprecatedGroupsWithdrawn[i]);
                }
                emit GroupRemoved(deprecatedGroupsWithdrawn[i]);
            }

            if (remainingWithdrawal == 0) {
                break;
            }
        }

        return (
            deprecatedGroupsWithdrawn,
            deprecatedWithdrawalsPerGroup,
            numberDeprecatedGroupsWithdrawn,
            remainingWithdrawal
        );
    }

    /**
     * @notice Calculates how votes should be withdrawn from each active group.
     * @param withdrawal The number of votes that need to be withdrawn.
     * @return The array of group addresses that should be withdrawn from.
     * @return The amount of votes to withdraw from the respective group in the
     * array of groups withdrawn from.
     */
    function getActiveGroupWithdrawalDistribution(uint256 withdrawal)
        internal
        view
        returns (address[] memory, uint256[] memory)
    {
        if (withdrawal == 0) {
            address[] memory noGroups = new address[](0);
            uint256[] memory noWithdrawals = new uint256[](0);
            return (noGroups, noWithdrawals);
        }

        uint256 numberGroups = activeGroups.length();
        GroupWithVotes[] memory sortedGroups;
        uint256 availableVotes;
        (sortedGroups, availableVotes) = getSortedGroupsWithVotes(activeGroups.values());
        availableVotes -= withdrawal;

        uint256 numberGroupsWithdrawn = numberGroups;
        uint256 targetVotes = availableVotes / numberGroupsWithdrawn;

        for (uint256 i = 0; i < numberGroups; i++) {
            if (sortedGroups[i].votes <= targetVotes) {
                numberGroupsWithdrawn--;
                availableVotes -= sortedGroups[i].votes;
                targetVotes = availableVotes / numberGroupsWithdrawn;
            } else {
                break;
            }
        }

        uint256[] memory withdrawalsPerGroup = new uint256[](numberGroupsWithdrawn);
        address[] memory groupsWithdrawn = new address[](numberGroupsWithdrawn);
        uint256 offset = numberGroups - numberGroupsWithdrawn;

        for (uint256 i = 0; i < numberGroupsWithdrawn; i++) {
            groupsWithdrawn[i] = sortedGroups[i + offset].group;
            withdrawalsPerGroup[i] = sortedGroups[i + offset].votes - targetVotes;
            if (availableVotes % numberGroupsWithdrawn > i) {
                withdrawalsPerGroup[i]--;
            }
        }

        return (groupsWithdrawn, withdrawalsPerGroup);
    }

    /**
     * @notice Returns a list of group addresses with their corresponding
     * current total votes, sorted by the number of votes, and the total number
     * of votes in the system.
     * @param groups The array of addresses of the groups to sort.
     * @return The array of GroupWithVotes structs, sorted by number of votes.
     * @return The total number of votes assigned to active groups.
     */
    function getSortedGroupsWithVotes(address[] memory groups)
        internal
        view
        returns (GroupWithVotes[] memory, uint256)
    {
        GroupWithVotes[] memory groupsWithVotes = new GroupWithVotes[](groups.length);
        uint256 totalVotes = 0;
        for (uint256 i = 0; i < groups.length; i++) {
            uint256 votes = account.getCeloForGroup(groups[i]);
            totalVotes += votes;
            groupsWithVotes[i] = GroupWithVotes(groups[i], votes);
        }

        sortGroupsWithVotes(groupsWithVotes);
        return (groupsWithVotes, totalVotes);
    }

    /**
     * @notice Returns the active groups that can receive the entire `votes`
     * amount based on their current receivable votes limit in Election.sol.
     * @param votes The number of votes that would potentially be added.
     * @return The list of votable active groups.
     */
    function getVotableGroups(uint256 votes) internal returns (address[] memory) {
        uint256 numberGroups = activeGroups.length();
        uint256 numberVotableGroups = 0;
        address[] memory votableGroups = new address[](numberGroups);

        for (uint256 i = 0; i < numberGroups; i++) {
            address group = activeGroups.at(i);
            uint256 scheduledVotes = account.scheduledVotes(group);
            if (getElection().canReceiveVotes(group, votes + scheduledVotes)) {
                votableGroups[numberVotableGroups] = group;
                numberVotableGroups++;
            }
        }

        address[] memory votableGroupsFinal = new address[](numberVotableGroups);
        for (uint256 i = 0; i < numberVotableGroups; i++) {
            votableGroupsFinal[i] = votableGroups[i];
        }

        return votableGroupsFinal;
    }

    /**
     * @notice Sorts an array of GroupWithVotes structs based on increasing
     * `votes` values.
     * @param groupsWithVotes The array to sort.
     * @dev This is an in-place insertion sort. In general in Solidity we should
     * be careful of algorithms on arrays, especially O(n^2) ones, but here
     * we're guaranteed to be working with a small array, its length is bounded
     * by the maximum number of groups that can be voted for in Elections.sol.
     */
    function sortGroupsWithVotes(GroupWithVotes[] memory groupsWithVotes) internal pure {
        for (uint256 i = 1; i < groupsWithVotes.length; i++) {
            uint256 j = i;
            while (j > 0 && groupsWithVotes[j].votes < groupsWithVotes[j - 1].votes) {
                (groupsWithVotes[j], groupsWithVotes[j - 1]) = (
                    groupsWithVotes[j - 1],
                    groupsWithVotes[j]
                );
                j--;
            }
        }
    }
}


//SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

interface IStakedCelo {
    function totalSupply() external view returns (uint256);

    function mint(address, uint256) external;

    function burn(address, uint256) external;

    function transfer(address, uint256) external returns (bool);

    function transferFrom(
        address,
        address,
        uint256
    ) external returns (bool);
}


//SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

interface IRegistry {
    function setAddressFor(string calldata, address) external;

    function getAddressForOrDie(bytes32) external view returns (address);

    function getAddressFor(bytes32) external view returns (address);

    function getAddressForStringOrDie(string calldata identifier) external view returns (address);

    function getAddressForString(string calldata identifier) external view returns (address);

    function isOneOf(bytes32[] calldata, address) external view returns (bool);
}


//SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

interface ILockedGold {
    function unlockingPeriod() external view returns (uint256);

    function incrementNonvotingAccountBalance(address, uint256) external;

    function decrementNonvotingAccountBalance(address, uint256) external;

    function getAccountTotalLockedGold(address) external view returns (uint256);

    function getTotalLockedGold() external view returns (uint256);

    function getPendingWithdrawal(address, uint256) external view returns (uint256, uint256);

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


// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

interface IGoldToken {
    function transfer(address to, uint256 value) external returns (bool);

    function transferWithComment(
        address to,
        uint256 value,
        string calldata comment
    ) external returns (bool);

    function approve(address spender, uint256 value) external returns (bool);

    function increaseAllowance(address spender, uint256 value) external returns (bool);

    function decreaseAllowance(address spender, uint256 value) external returns (bool);

    function transferFrom(
        address from,
        address to,
        uint256 value
    ) external returns (bool);

    function name() external view returns (string memory);

    function symbol() external view returns (string memory);

    function decimals() external view returns (uint8);

    function totalSupply() external view returns (uint256);

    function allowance(address owner, address spender) external view returns (uint256);

    function balanceOf(address owner) external view returns (uint256);
}


//SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

interface IElection {
    function electValidatorSigners() external view returns (address[] memory);

    function electNValidatorSigners(uint256, uint256) external view returns (address[] memory);

    function vote(
        address,
        uint256,
        address,
        address
    ) external returns (bool);

    function activate(address) external returns (bool);

    function activateForAccount(address, address) external returns (bool);

    function revokeActive(
        address,
        uint256,
        address,
        address,
        uint256
    ) external returns (bool);

    function revokeAllActive(
        address,
        address,
        address,
        uint256
    ) external returns (bool);

    function revokePending(
        address,
        uint256,
        address,
        address,
        uint256
    ) external returns (bool);

    function markGroupIneligible(address) external;

    function markGroupEligible(
        address,
        address,
        address
    ) external;

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

    function getGroupEpochRewards(
        address,
        uint256,
        uint256[] calldata
    ) external view returns (uint256);

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
    function distributeEpochRewards(
        address,
        uint256,
        address,
        address
    ) external;

    function maxNumGroupsVotedFor() external view returns (uint256);
}


//SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

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

    function setWalletAddress(
        address,
        uint8,
        bytes32,
        bytes32
    ) external;

    function setAccount(
        string calldata,
        bytes calldata,
        address,
        uint8,
        bytes32,
        bytes32
    ) external;

    function getDataEncryptionKey(address) external view returns (bytes memory);

    function getWalletAddress(address) external view returns (address);

    function getMetadataURL(address) external view returns (string memory);

    function batchGetMetadataURL(address[] calldata)
        external
        view
        returns (uint256[] memory, bytes memory);

    function getName(address) external view returns (string memory);

    function authorizeVoteSigner(
        address,
        uint8,
        bytes32,
        bytes32
    ) external;

    function authorizeValidatorSigner(
        address,
        uint8,
        bytes32,
        bytes32
    ) external;

    function authorizeValidatorSignerWithPublicKey(
        address,
        uint8,
        bytes32,
        bytes32,
        bytes calldata
    ) external;

    function authorizeValidatorSignerWithKeys(
        address,
        uint8,
        bytes32,
        bytes32,
        bytes calldata,
        bytes calldata,
        bytes calldata
    ) external;

    function authorizeAttestationSigner(
        address,
        uint8,
        bytes32,
        bytes32
    ) external;

    function createAccount() external returns (bool);
}


//SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

interface IAccount {
    function getTotalCelo() external view returns (uint256);

    function getCeloForGroup(address) external view returns (uint256);

    function scheduleVotes(address[] calldata group, uint256[] calldata votes) external payable;

    function scheduledVotes(address group) external returns (uint256);

    function scheduleWithdrawals(
        address[] calldata group,
        uint256[] calldata withdrawals,
        address beneficiary
    ) external;
}


//SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import "../interfaces/IAccounts.sol";
import "../interfaces/IElection.sol";
import "../interfaces/IGoldToken.sol";
import "../interfaces/ILockedGold.sol";
import "../interfaces/IRegistry.sol";

/**
 * @title A helper for getting Celo core contracts from the Registry.
 */
abstract contract UsingRegistryUpgradeable is Initializable {
    /**
     * @notice Initializes the UsingRegistryUpgradable contract in an upgradable scenario
     * @param _registry The address of the Registry. For convenience, if the zero address is
     * provided, the registry is set to the canonical Registry address, i.e. 0x0...ce10. This
     * parameter should only be a non-zero address when testing.
     */
    // solhint-disable-next-line func-name-mixedcase
    function __UsingRegistry_init(address _registry) internal onlyInitializing {
        if (_registry == address(0)) {
            registry = IRegistry(CANONICAL_REGISTRY);
        } else {
            registry = IRegistry(_registry);
        }
    }

    /// @notice The canonical address of the Registry.
    address internal constant CANONICAL_REGISTRY = 0x000000000000000000000000000000000000ce10;

    /// @notice The registry ID for the Accounts contract.
    bytes32 private constant ACCOUNTS_REGISTRY_ID = keccak256(abi.encodePacked("Accounts"));

    /// @notice The registry ID for the Election contract.
    bytes32 private constant ELECTION_REGISTRY_ID = keccak256(abi.encodePacked("Election"));

    /// @notice The registry ID for the GoldToken contract.
    bytes32 private constant GOLD_TOKEN_REGISTRY_ID = keccak256(abi.encodePacked("GoldToken"));

    /// @notice The registry ID for the LockedGold contract.
    bytes32 private constant LOCKED_GOLD_REGISTRY_ID = keccak256(abi.encodePacked("LockedGold"));

    /// @notice The Registry.
    IRegistry public registry;

    /**
     * @notice Gets the Accounts contract from the Registry.
     * @return The Accounts contract from the Registry.
     */
    function getAccounts() internal view returns (IAccounts) {
        return IAccounts(registry.getAddressForOrDie(ACCOUNTS_REGISTRY_ID));
    }

    /**
     * @notice Gets the Election contract from the Registry.
     * @return The Election contract from the Registry.
     */
    function getElection() internal view returns (IElection) {
        return IElection(registry.getAddressForOrDie(ELECTION_REGISTRY_ID));
    }

    /**
     * @notice Gets the GoldToken contract from the Registry.
     * @return The GoldToken contract from the Registry.
     */
    function getGoldToken() internal view returns (IGoldToken) {
        return IGoldToken(registry.getAddressForOrDie(GOLD_TOKEN_REGISTRY_ID));
    }

    /**
     * @notice Gets the LockedGold contract from the Registry.
     * @return The LockedGold contract from the Registry.
     */
    function getLockedGold() internal view returns (ILockedGold) {
        return ILockedGold(registry.getAddressForOrDie(LOCKED_GOLD_REGISTRY_ID));
    }
}


// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

/**
 * @title A contract that links UUPSUUpgradeable with OwanbleUpgradeable to gate upgrades.
 */
abstract contract UUPSOwnableUpgradeable is UUPSUpgradeable, OwnableUpgradeable {
    /**
     * @notice Guard method for UUPS (Universal Upgradable Proxy Standard)
     * See: https://docs.openzeppelin.com/contracts/4.x/api/proxy#transparent-vs-uups
     * @dev This methods overrides the virtual one in UUPSUpgradeable and
     * adds the onlyOwner modifer.
     */
    // solhint-disable-next-line no-empty-blocks
    function _authorizeUpgrade(address) internal override onlyOwner {}
}


// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts v4.4.1 (utils/Context.sol)

pragma solidity ^0.8.0;
import "../proxy/utils/Initializable.sol";

/**
 * @dev Provides information about the current execution context, including the
 * sender of the transaction and its data. While these are generally available
 * via msg.sender and msg.data, they should not be accessed in such a direct
 * manner, since when dealing with meta-transactions the account sending and
 * paying for execution may not be the actual sender (as far as an application
 * is concerned).
 *
 * This contract is only required for intermediate, library-like contracts.
 */
abstract contract ContextUpgradeable is Initializable {
    function __Context_init() internal onlyInitializing {
    }

    function __Context_init_unchained() internal onlyInitializing {
    }
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        return msg.data;
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[50] private __gap;
}


// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v4.5.0) (utils/Address.sol)

pragma solidity ^0.8.1;

/**
 * @dev Collection of functions related to the address type
 */
library AddressUpgradeable {
    /**
     * @dev Returns true if `account` is a contract.
     *
     * [IMPORTANT]
     * ====
     * It is unsafe to assume that an address for which this function returns
     * false is an externally-owned account (EOA) and not a contract.
     *
     * Among others, `isContract` will return false for the following
     * types of addresses:
     *
     *  - an externally-owned account
     *  - a contract in construction
     *  - an address where a contract will be created
     *  - an address where a contract lived, but was destroyed
     * ====
     *
     * [IMPORTANT]
     * ====
     * You shouldn't rely on `isContract` to protect against flash loan attacks!
     *
     * Preventing calls from contracts is highly discouraged. It breaks composability, breaks support for smart wallets
     * like Gnosis Safe, and does not provide security since it can be circumvented by calling from a contract
     * constructor.
     * ====
     */
    function isContract(address account) internal view returns (bool) {
        // This method relies on extcodesize/address.code.length, which returns 0
        // for contracts in construction, since the code is only stored at the end
        // of the constructor execution.

        return account.code.length > 0;
    }

    /**
     * @dev Replacement for Solidity's `transfer`: sends `amount` wei to
     * `recipient`, forwarding all available gas and reverting on errors.
     *
     * https://eips.ethereum.org/EIPS/eip-1884[EIP1884] increases the gas cost
     * of certain opcodes, possibly making contracts go over the 2300 gas limit
     * imposed by `transfer`, making them unable to receive funds via
     * `transfer`. {sendValue} removes this limitation.
     *
     * https://diligence.consensys.net/posts/2019/09/stop-using-soliditys-transfer-now/[Learn more].
     *
     * IMPORTANT: because control is transferred to `recipient`, care must be
     * taken to not create reentrancy vulnerabilities. Consider using
     * {ReentrancyGuard} or the
     * https://solidity.readthedocs.io/en/v0.5.11/security-considerations.html#use-the-checks-effects-interactions-pattern[checks-effects-interactions pattern].
     */
    function sendValue(address payable recipient, uint256 amount) internal {
        require(address(this).balance >= amount, "Address: insufficient balance");

        (bool success, ) = recipient.call{value: amount}("");
        require(success, "Address: unable to send value, recipient may have reverted");
    }

    /**
     * @dev Performs a Solidity function call using a low level `call`. A
     * plain `call` is an unsafe replacement for a function call: use this
     * function instead.
     *
     * If `target` reverts with a revert reason, it is bubbled up by this
     * function (like regular Solidity function calls).
     *
     * Returns the raw returned data. To convert to the expected return value,
     * use https://solidity.readthedocs.io/en/latest/units-and-global-variables.html?highlight=abi.decode#abi-encoding-and-decoding-functions[`abi.decode`].
     *
     * Requirements:
     *
     * - `target` must be a contract.
     * - calling `target` with `data` must not revert.
     *
     * _Available since v3.1._
     */
    function functionCall(address target, bytes memory data) internal returns (bytes memory) {
        return functionCall(target, data, "Address: low-level call failed");
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`], but with
     * `errorMessage` as a fallback revert reason when `target` reverts.
     *
     * _Available since v3.1._
     */
    function functionCall(
        address target,
        bytes memory data,
        string memory errorMessage
    ) internal returns (bytes memory) {
        return functionCallWithValue(target, data, 0, errorMessage);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but also transferring `value` wei to `target`.
     *
     * Requirements:
     *
     * - the calling contract must have an ETH balance of at least `value`.
     * - the called Solidity function must be `payable`.
     *
     * _Available since v3.1._
     */
    function functionCallWithValue(
        address target,
        bytes memory data,
        uint256 value
    ) internal returns (bytes memory) {
        return functionCallWithValue(target, data, value, "Address: low-level call with value failed");
    }

    /**
     * @dev Same as {xref-Address-functionCallWithValue-address-bytes-uint256-}[`functionCallWithValue`], but
     * with `errorMessage` as a fallback revert reason when `target` reverts.
     *
     * _Available since v3.1._
     */
    function functionCallWithValue(
        address target,
        bytes memory data,
        uint256 value,
        string memory errorMessage
    ) internal returns (bytes memory) {
        require(address(this).balance >= value, "Address: insufficient balance for call");
        require(isContract(target), "Address: call to non-contract");

        (bool success, bytes memory returndata) = target.call{value: value}(data);
        return verifyCallResult(success, returndata, errorMessage);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but performing a static call.
     *
     * _Available since v3.3._
     */
    function functionStaticCall(address target, bytes memory data) internal view returns (bytes memory) {
        return functionStaticCall(target, data, "Address: low-level static call failed");
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-string-}[`functionCall`],
     * but performing a static call.
     *
     * _Available since v3.3._
     */
    function functionStaticCall(
        address target,
        bytes memory data,
        string memory errorMessage
    ) internal view returns (bytes memory) {
        require(isContract(target), "Address: static call to non-contract");

        (bool success, bytes memory returndata) = target.staticcall(data);
        return verifyCallResult(success, returndata, errorMessage);
    }

    /**
     * @dev Tool to verifies that a low level call was successful, and revert if it wasn't, either by bubbling the
     * revert reason using the provided one.
     *
     * _Available since v4.3._
     */
    function verifyCallResult(
        bool success,
        bytes memory returndata,
        string memory errorMessage
    ) internal pure returns (bytes memory) {
        if (success) {
            return returndata;
        } else {
            // Look for revert reason and bubble it up if present
            if (returndata.length > 0) {
                // The easiest way to bubble the revert reason is using memory via assembly

                assembly {
                    let returndata_size := mload(returndata)
                    revert(add(32, returndata), returndata_size)
                }
            } else {
                revert(errorMessage);
            }
        }
    }
}


// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v4.5.0) (proxy/utils/Initializable.sol)

pragma solidity ^0.8.0;

import "../../utils/AddressUpgradeable.sol";

/**
 * @dev This is a base contract to aid in writing upgradeable contracts, or any kind of contract that will be deployed
 * behind a proxy. Since proxied contracts do not make use of a constructor, it's common to move constructor logic to an
 * external initializer function, usually called `initialize`. It then becomes necessary to protect this initializer
 * function so it can only be called once. The {initializer} modifier provided by this contract will have this effect.
 *
 * TIP: To avoid leaving the proxy in an uninitialized state, the initializer function should be called as early as
 * possible by providing the encoded function call as the `_data` argument to {ERC1967Proxy-constructor}.
 *
 * CAUTION: When used with inheritance, manual care must be taken to not invoke a parent initializer twice, or to ensure
 * that all initializers are idempotent. This is not verified automatically as constructors are by Solidity.
 *
 * [CAUTION]
 * ====
 * Avoid leaving a contract uninitialized.
 *
 * An uninitialized contract can be taken over by an attacker. This applies to both a proxy and its implementation
 * contract, which may impact the proxy. To initialize the implementation contract, you can either invoke the
 * initializer manually, or you can include a constructor to automatically mark it as initialized when it is deployed:
 *
 * [.hljs-theme-light.nopadding]
 * ```
 * /// @custom:oz-upgrades-unsafe-allow constructor
 * constructor() initializer {}
 * ```
 * ====
 */
abstract contract Initializable {
    /**
     * @dev Indicates that the contract has been initialized.
     */
    bool private _initialized;

    /**
     * @dev Indicates that the contract is in the process of being initialized.
     */
    bool private _initializing;

    /**
     * @dev Modifier to protect an initializer function from being invoked twice.
     */
    modifier initializer() {
        // If the contract is initializing we ignore whether _initialized is set in order to support multiple
        // inheritance patterns, but we only do this in the context of a constructor, because in other contexts the
        // contract may have been reentered.
        require(_initializing ? _isConstructor() : !_initialized, "Initializable: contract is already initialized");

        bool isTopLevelCall = !_initializing;
        if (isTopLevelCall) {
            _initializing = true;
            _initialized = true;
        }

        _;

        if (isTopLevelCall) {
            _initializing = false;
        }
    }

    /**
     * @dev Modifier to protect an initialization function so that it can only be invoked by functions with the
     * {initializer} modifier, directly or indirectly.
     */
    modifier onlyInitializing() {
        require(_initializing, "Initializable: contract is not initializing");
        _;
    }

    function _isConstructor() private view returns (bool) {
        return !AddressUpgradeable.isContract(address(this));
    }
}


// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts v4.4.1 (access/Ownable.sol)

pragma solidity ^0.8.0;

import "../utils/ContextUpgradeable.sol";
import "../proxy/utils/Initializable.sol";

/**
 * @dev Contract module which provides a basic access control mechanism, where
 * there is an account (an owner) that can be granted exclusive access to
 * specific functions.
 *
 * By default, the owner account will be the one that deploys the contract. This
 * can later be changed with {transferOwnership}.
 *
 * This module is used through inheritance. It will make available the modifier
 * `onlyOwner`, which can be applied to your functions to restrict their use to
 * the owner.
 */
abstract contract OwnableUpgradeable is Initializable, ContextUpgradeable {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /**
     * @dev Initializes the contract setting the deployer as the initial owner.
     */
    function __Ownable_init() internal onlyInitializing {
        __Ownable_init_unchained();
    }

    function __Ownable_init_unchained() internal onlyInitializing {
        _transferOwnership(_msgSender());
    }

    /**
     * @dev Returns the address of the current owner.
     */
    function owner() public view virtual returns (address) {
        return _owner;
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        require(owner() == _msgSender(), "Ownable: caller is not the owner");
        _;
    }

    /**
     * @dev Leaves the contract without owner. It will not be possible to call
     * `onlyOwner` functions anymore. Can only be called by the current owner.
     *
     * NOTE: Renouncing ownership will leave the contract without an owner,
     * thereby removing any functionality that is only available to the owner.
     */
    function renounceOwnership() public virtual onlyOwner {
        _transferOwnership(address(0));
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        _transferOwnership(newOwner);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Internal function without access restriction.
     */
    function _transferOwnership(address newOwner) internal virtual {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[49] private __gap;
}


// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts v4.4.1 (utils/structs/EnumerableSet.sol)

pragma solidity ^0.8.0;

/**
 * @dev Library for managing
 * https://en.wikipedia.org/wiki/Set_(abstract_data_type)[sets] of primitive
 * types.
 *
 * Sets have the following properties:
 *
 * - Elements are added, removed, and checked for existence in constant time
 * (O(1)).
 * - Elements are enumerated in O(n). No guarantees are made on the ordering.
 *
 * ```
 * contract Example {
 *     // Add the library methods
 *     using EnumerableSet for EnumerableSet.AddressSet;
 *
 *     // Declare a set state variable
 *     EnumerableSet.AddressSet private mySet;
 * }
 * ```
 *
 * As of v3.3.0, sets of type `bytes32` (`Bytes32Set`), `address` (`AddressSet`)
 * and `uint256` (`UintSet`) are supported.
 */
library EnumerableSet {
    // To implement this library for multiple types with as little code
    // repetition as possible, we write it in terms of a generic Set type with
    // bytes32 values.
    // The Set implementation uses private functions, and user-facing
    // implementations (such as AddressSet) are just wrappers around the
    // underlying Set.
    // This means that we can only create new EnumerableSets for types that fit
    // in bytes32.

    struct Set {
        // Storage of set values
        bytes32[] _values;
        // Position of the value in the `values` array, plus 1 because index 0
        // means a value is not in the set.
        mapping(bytes32 => uint256) _indexes;
    }

    /**
     * @dev Add a value to a set. O(1).
     *
     * Returns true if the value was added to the set, that is if it was not
     * already present.
     */
    function _add(Set storage set, bytes32 value) private returns (bool) {
        if (!_contains(set, value)) {
            set._values.push(value);
            // The value is stored at length-1, but we add 1 to all indexes
            // and use 0 as a sentinel value
            set._indexes[value] = set._values.length;
            return true;
        } else {
            return false;
        }
    }

    /**
     * @dev Removes a value from a set. O(1).
     *
     * Returns true if the value was removed from the set, that is if it was
     * present.
     */
    function _remove(Set storage set, bytes32 value) private returns (bool) {
        // We read and store the value's index to prevent multiple reads from the same storage slot
        uint256 valueIndex = set._indexes[value];

        if (valueIndex != 0) {
            // Equivalent to contains(set, value)
            // To delete an element from the _values array in O(1), we swap the element to delete with the last one in
            // the array, and then remove the last element (sometimes called as 'swap and pop').
            // This modifies the order of the array, as noted in {at}.

            uint256 toDeleteIndex = valueIndex - 1;
            uint256 lastIndex = set._values.length - 1;

            if (lastIndex != toDeleteIndex) {
                bytes32 lastvalue = set._values[lastIndex];

                // Move the last value to the index where the value to delete is
                set._values[toDeleteIndex] = lastvalue;
                // Update the index for the moved value
                set._indexes[lastvalue] = valueIndex; // Replace lastvalue's index to valueIndex
            }

            // Delete the slot where the moved value was stored
            set._values.pop();

            // Delete the index for the deleted slot
            delete set._indexes[value];

            return true;
        } else {
            return false;
        }
    }

    /**
     * @dev Returns true if the value is in the set. O(1).
     */
    function _contains(Set storage set, bytes32 value) private view returns (bool) {
        return set._indexes[value] != 0;
    }

    /**
     * @dev Returns the number of values on the set. O(1).
     */
    function _length(Set storage set) private view returns (uint256) {
        return set._values.length;
    }

    /**
     * @dev Returns the value stored at position `index` in the set. O(1).
     *
     * Note that there are no guarantees on the ordering of values inside the
     * array, and it may change when more values are added or removed.
     *
     * Requirements:
     *
     * - `index` must be strictly less than {length}.
     */
    function _at(Set storage set, uint256 index) private view returns (bytes32) {
        return set._values[index];
    }

    /**
     * @dev Return the entire set in an array
     *
     * WARNING: This operation will copy the entire storage to memory, which can be quite expensive. This is designed
     * to mostly be used by view accessors that are queried without any gas fees. Developers should keep in mind that
     * this function has an unbounded cost, and using it as part of a state-changing function may render the function
     * uncallable if the set grows to a point where copying to memory consumes too much gas to fit in a block.
     */
    function _values(Set storage set) private view returns (bytes32[] memory) {
        return set._values;
    }

    // Bytes32Set

    struct Bytes32Set {
        Set _inner;
    }

    /**
     * @dev Add a value to a set. O(1).
     *
     * Returns true if the value was added to the set, that is if it was not
     * already present.
     */
    function add(Bytes32Set storage set, bytes32 value) internal returns (bool) {
        return _add(set._inner, value);
    }

    /**
     * @dev Removes a value from a set. O(1).
     *
     * Returns true if the value was removed from the set, that is if it was
     * present.
     */
    function remove(Bytes32Set storage set, bytes32 value) internal returns (bool) {
        return _remove(set._inner, value);
    }

    /**
     * @dev Returns true if the value is in the set. O(1).
     */
    function contains(Bytes32Set storage set, bytes32 value) internal view returns (bool) {
        return _contains(set._inner, value);
    }

    /**
     * @dev Returns the number of values in the set. O(1).
     */
    function length(Bytes32Set storage set) internal view returns (uint256) {
        return _length(set._inner);
    }

    /**
     * @dev Returns the value stored at position `index` in the set. O(1).
     *
     * Note that there are no guarantees on the ordering of values inside the
     * array, and it may change when more values are added or removed.
     *
     * Requirements:
     *
     * - `index` must be strictly less than {length}.
     */
    function at(Bytes32Set storage set, uint256 index) internal view returns (bytes32) {
        return _at(set._inner, index);
    }

    /**
     * @dev Return the entire set in an array
     *
     * WARNING: This operation will copy the entire storage to memory, which can be quite expensive. This is designed
     * to mostly be used by view accessors that are queried without any gas fees. Developers should keep in mind that
     * this function has an unbounded cost, and using it as part of a state-changing function may render the function
     * uncallable if the set grows to a point where copying to memory consumes too much gas to fit in a block.
     */
    function values(Bytes32Set storage set) internal view returns (bytes32[] memory) {
        return _values(set._inner);
    }

    // AddressSet

    struct AddressSet {
        Set _inner;
    }

    /**
     * @dev Add a value to a set. O(1).
     *
     * Returns true if the value was added to the set, that is if it was not
     * already present.
     */
    function add(AddressSet storage set, address value) internal returns (bool) {
        return _add(set._inner, bytes32(uint256(uint160(value))));
    }

    /**
     * @dev Removes a value from a set. O(1).
     *
     * Returns true if the value was removed from the set, that is if it was
     * present.
     */
    function remove(AddressSet storage set, address value) internal returns (bool) {
        return _remove(set._inner, bytes32(uint256(uint160(value))));
    }

    /**
     * @dev Returns true if the value is in the set. O(1).
     */
    function contains(AddressSet storage set, address value) internal view returns (bool) {
        return _contains(set._inner, bytes32(uint256(uint160(value))));
    }

    /**
     * @dev Returns the number of values in the set. O(1).
     */
    function length(AddressSet storage set) internal view returns (uint256) {
        return _length(set._inner);
    }

    /**
     * @dev Returns the value stored at position `index` in the set. O(1).
     *
     * Note that there are no guarantees on the ordering of values inside the
     * array, and it may change when more values are added or removed.
     *
     * Requirements:
     *
     * - `index` must be strictly less than {length}.
     */
    function at(AddressSet storage set, uint256 index) internal view returns (address) {
        return address(uint160(uint256(_at(set._inner, index))));
    }

    /**
     * @dev Return the entire set in an array
     *
     * WARNING: This operation will copy the entire storage to memory, which can be quite expensive. This is designed
     * to mostly be used by view accessors that are queried without any gas fees. Developers should keep in mind that
     * this function has an unbounded cost, and using it as part of a state-changing function may render the function
     * uncallable if the set grows to a point where copying to memory consumes too much gas to fit in a block.
     */
    function values(AddressSet storage set) internal view returns (address[] memory) {
        bytes32[] memory store = _values(set._inner);
        address[] memory result;

        assembly {
            result := store
        }

        return result;
    }

    // UintSet

    struct UintSet {
        Set _inner;
    }

    /**
     * @dev Add a value to a set. O(1).
     *
     * Returns true if the value was added to the set, that is if it was not
     * already present.
     */
    function add(UintSet storage set, uint256 value) internal returns (bool) {
        return _add(set._inner, bytes32(value));
    }

    /**
     * @dev Removes a value from a set. O(1).
     *
     * Returns true if the value was removed from the set, that is if it was
     * present.
     */
    function remove(UintSet storage set, uint256 value) internal returns (bool) {
        return _remove(set._inner, bytes32(value));
    }

    /**
     * @dev Returns true if the value is in the set. O(1).
     */
    function contains(UintSet storage set, uint256 value) internal view returns (bool) {
        return _contains(set._inner, bytes32(value));
    }

    /**
     * @dev Returns the number of values on the set. O(1).
     */
    function length(UintSet storage set) internal view returns (uint256) {
        return _length(set._inner);
    }

    /**
     * @dev Returns the value stored at position `index` in the set. O(1).
     *
     * Note that there are no guarantees on the ordering of values inside the
     * array, and it may change when more values are added or removed.
     *
     * Requirements:
     *
     * - `index` must be strictly less than {length}.
     */
    function at(UintSet storage set, uint256 index) internal view returns (uint256) {
        return uint256(_at(set._inner, index));
    }

    /**
     * @dev Return the entire set in an array
     *
     * WARNING: This operation will copy the entire storage to memory, which can be quite expensive. This is designed
     * to mostly be used by view accessors that are queried without any gas fees. Developers should keep in mind that
     * this function has an unbounded cost, and using it as part of a state-changing function may render the function
     * uncallable if the set grows to a point where copying to memory consumes too much gas to fit in a block.
     */
    function values(UintSet storage set) internal view returns (uint256[] memory) {
        bytes32[] memory store = _values(set._inner);
        uint256[] memory result;

        assembly {
            result := store
        }

        return result;
    }
}


// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts v4.4.1 (utils/math/Math.sol)

pragma solidity ^0.8.0;

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
        // (a + b) / 2 can overflow.
        return (a & b) + (a ^ b) / 2;
    }

    /**
     * @dev Returns the ceiling of the division of two numbers.
     *
     * This differs from standard division with `/` in that it rounds up instead
     * of rounding down.
     */
    function ceilDiv(uint256 a, uint256 b) internal pure returns (uint256) {
        // (a + b - 1) / b can overflow on addition, so we distribute.
        return a / b + (a % b == 0 ? 0 : 1);
    }
}


// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts v4.4.1 (utils/StorageSlot.sol)

pragma solidity ^0.8.0;

/**
 * @dev Library for reading and writing primitive types to specific storage slots.
 *
 * Storage slots are often used to avoid storage conflict when dealing with upgradeable contracts.
 * This library helps with reading and writing to such slots without the need for inline assembly.
 *
 * The functions in this library return Slot structs that contain a `value` member that can be used to read or write.
 *
 * Example usage to set ERC1967 implementation slot:
 * ```
 * contract ERC1967 {
 *     bytes32 internal constant _IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
 *
 *     function _getImplementation() internal view returns (address) {
 *         return StorageSlot.getAddressSlot(_IMPLEMENTATION_SLOT).value;
 *     }
 *
 *     function _setImplementation(address newImplementation) internal {
 *         require(Address.isContract(newImplementation), "ERC1967: new implementation is not a contract");
 *         StorageSlot.getAddressSlot(_IMPLEMENTATION_SLOT).value = newImplementation;
 *     }
 * }
 * ```
 *
 * _Available since v4.1 for `address`, `bool`, `bytes32`, and `uint256`._
 */
library StorageSlot {
    struct AddressSlot {
        address value;
    }

    struct BooleanSlot {
        bool value;
    }

    struct Bytes32Slot {
        bytes32 value;
    }

    struct Uint256Slot {
        uint256 value;
    }

    /**
     * @dev Returns an `AddressSlot` with member `value` located at `slot`.
     */
    function getAddressSlot(bytes32 slot) internal pure returns (AddressSlot storage r) {
        assembly {
            r.slot := slot
        }
    }

    /**
     * @dev Returns an `BooleanSlot` with member `value` located at `slot`.
     */
    function getBooleanSlot(bytes32 slot) internal pure returns (BooleanSlot storage r) {
        assembly {
            r.slot := slot
        }
    }

    /**
     * @dev Returns an `Bytes32Slot` with member `value` located at `slot`.
     */
    function getBytes32Slot(bytes32 slot) internal pure returns (Bytes32Slot storage r) {
        assembly {
            r.slot := slot
        }
    }

    /**
     * @dev Returns an `Uint256Slot` with member `value` located at `slot`.
     */
    function getUint256Slot(bytes32 slot) internal pure returns (Uint256Slot storage r) {
        assembly {
            r.slot := slot
        }
    }
}


// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts v4.4.1 (utils/Address.sol)

pragma solidity ^0.8.0;

/**
 * @dev Collection of functions related to the address type
 */
library Address {
    /**
     * @dev Returns true if `account` is a contract.
     *
     * [IMPORTANT]
     * ====
     * It is unsafe to assume that an address for which this function returns
     * false is an externally-owned account (EOA) and not a contract.
     *
     * Among others, `isContract` will return false for the following
     * types of addresses:
     *
     *  - an externally-owned account
     *  - a contract in construction
     *  - an address where a contract will be created
     *  - an address where a contract lived, but was destroyed
     * ====
     */
    function isContract(address account) internal view returns (bool) {
        // This method relies on extcodesize, which returns 0 for contracts in
        // construction, since the code is only stored at the end of the
        // constructor execution.

        uint256 size;
        assembly {
            size := extcodesize(account)
        }
        return size > 0;
    }

    /**
     * @dev Replacement for Solidity's `transfer`: sends `amount` wei to
     * `recipient`, forwarding all available gas and reverting on errors.
     *
     * https://eips.ethereum.org/EIPS/eip-1884[EIP1884] increases the gas cost
     * of certain opcodes, possibly making contracts go over the 2300 gas limit
     * imposed by `transfer`, making them unable to receive funds via
     * `transfer`. {sendValue} removes this limitation.
     *
     * https://diligence.consensys.net/posts/2019/09/stop-using-soliditys-transfer-now/[Learn more].
     *
     * IMPORTANT: because control is transferred to `recipient`, care must be
     * taken to not create reentrancy vulnerabilities. Consider using
     * {ReentrancyGuard} or the
     * https://solidity.readthedocs.io/en/v0.5.11/security-considerations.html#use-the-checks-effects-interactions-pattern[checks-effects-interactions pattern].
     */
    function sendValue(address payable recipient, uint256 amount) internal {
        require(address(this).balance >= amount, "Address: insufficient balance");

        (bool success, ) = recipient.call{value: amount}("");
        require(success, "Address: unable to send value, recipient may have reverted");
    }

    /**
     * @dev Performs a Solidity function call using a low level `call`. A
     * plain `call` is an unsafe replacement for a function call: use this
     * function instead.
     *
     * If `target` reverts with a revert reason, it is bubbled up by this
     * function (like regular Solidity function calls).
     *
     * Returns the raw returned data. To convert to the expected return value,
     * use https://solidity.readthedocs.io/en/latest/units-and-global-variables.html?highlight=abi.decode#abi-encoding-and-decoding-functions[`abi.decode`].
     *
     * Requirements:
     *
     * - `target` must be a contract.
     * - calling `target` with `data` must not revert.
     *
     * _Available since v3.1._
     */
    function functionCall(address target, bytes memory data) internal returns (bytes memory) {
        return functionCall(target, data, "Address: low-level call failed");
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`], but with
     * `errorMessage` as a fallback revert reason when `target` reverts.
     *
     * _Available since v3.1._
     */
    function functionCall(
        address target,
        bytes memory data,
        string memory errorMessage
    ) internal returns (bytes memory) {
        return functionCallWithValue(target, data, 0, errorMessage);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but also transferring `value` wei to `target`.
     *
     * Requirements:
     *
     * - the calling contract must have an ETH balance of at least `value`.
     * - the called Solidity function must be `payable`.
     *
     * _Available since v3.1._
     */
    function functionCallWithValue(
        address target,
        bytes memory data,
        uint256 value
    ) internal returns (bytes memory) {
        return functionCallWithValue(target, data, value, "Address: low-level call with value failed");
    }

    /**
     * @dev Same as {xref-Address-functionCallWithValue-address-bytes-uint256-}[`functionCallWithValue`], but
     * with `errorMessage` as a fallback revert reason when `target` reverts.
     *
     * _Available since v3.1._
     */
    function functionCallWithValue(
        address target,
        bytes memory data,
        uint256 value,
        string memory errorMessage
    ) internal returns (bytes memory) {
        require(address(this).balance >= value, "Address: insufficient balance for call");
        require(isContract(target), "Address: call to non-contract");

        (bool success, bytes memory returndata) = target.call{value: value}(data);
        return verifyCallResult(success, returndata, errorMessage);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but performing a static call.
     *
     * _Available since v3.3._
     */
    function functionStaticCall(address target, bytes memory data) internal view returns (bytes memory) {
        return functionStaticCall(target, data, "Address: low-level static call failed");
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-string-}[`functionCall`],
     * but performing a static call.
     *
     * _Available since v3.3._
     */
    function functionStaticCall(
        address target,
        bytes memory data,
        string memory errorMessage
    ) internal view returns (bytes memory) {
        require(isContract(target), "Address: static call to non-contract");

        (bool success, bytes memory returndata) = target.staticcall(data);
        return verifyCallResult(success, returndata, errorMessage);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but performing a delegate call.
     *
     * _Available since v3.4._
     */
    function functionDelegateCall(address target, bytes memory data) internal returns (bytes memory) {
        return functionDelegateCall(target, data, "Address: low-level delegate call failed");
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-string-}[`functionCall`],
     * but performing a delegate call.
     *
     * _Available since v3.4._
     */
    function functionDelegateCall(
        address target,
        bytes memory data,
        string memory errorMessage
    ) internal returns (bytes memory) {
        require(isContract(target), "Address: delegate call to non-contract");

        (bool success, bytes memory returndata) = target.delegatecall(data);
        return verifyCallResult(success, returndata, errorMessage);
    }

    /**
     * @dev Tool to verifies that a low level call was successful, and revert if it wasn't, either by bubbling the
     * revert reason using the provided one.
     *
     * _Available since v4.3._
     */
    function verifyCallResult(
        bool success,
        bytes memory returndata,
        string memory errorMessage
    ) internal pure returns (bytes memory) {
        if (success) {
            return returndata;
        } else {
            // Look for revert reason and bubble it up if present
            if (returndata.length > 0) {
                // The easiest way to bubble the revert reason is using memory via assembly

                assembly {
                    let returndata_size := mload(returndata)
                    revert(add(32, returndata), returndata_size)
                }
            } else {
                revert(errorMessage);
            }
        }
    }
}


// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts v4.4.1 (proxy/utils/UUPSUpgradeable.sol)

pragma solidity ^0.8.0;

import "../ERC1967/ERC1967Upgrade.sol";

/**
 * @dev An upgradeability mechanism designed for UUPS proxies. The functions included here can perform an upgrade of an
 * {ERC1967Proxy}, when this contract is set as the implementation behind such a proxy.
 *
 * A security mechanism ensures that an upgrade does not turn off upgradeability accidentally, although this risk is
 * reinstated if the upgrade retains upgradeability but removes the security mechanism, e.g. by replacing
 * `UUPSUpgradeable` with a custom implementation of upgrades.
 *
 * The {_authorizeUpgrade} function must be overridden to include access restriction to the upgrade mechanism.
 *
 * _Available since v4.1._
 */
abstract contract UUPSUpgradeable is ERC1967Upgrade {
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable state-variable-assignment
    address private immutable __self = address(this);

    /**
     * @dev Check that the execution is being performed through a delegatecall call and that the execution context is
     * a proxy contract with an implementation (as defined in ERC1967) pointing to self. This should only be the case
     * for UUPS and transparent proxies that are using the current contract as their implementation. Execution of a
     * function through ERC1167 minimal proxies (clones) would not normally pass this test, but is not guaranteed to
     * fail.
     */
    modifier onlyProxy() {
        require(address(this) != __self, "Function must be called through delegatecall");
        require(_getImplementation() == __self, "Function must be called through active proxy");
        _;
    }

    /**
     * @dev Upgrade the implementation of the proxy to `newImplementation`.
     *
     * Calls {_authorizeUpgrade}.
     *
     * Emits an {Upgraded} event.
     */
    function upgradeTo(address newImplementation) external virtual onlyProxy {
        _authorizeUpgrade(newImplementation);
        _upgradeToAndCallSecure(newImplementation, new bytes(0), false);
    }

    /**
     * @dev Upgrade the implementation of the proxy to `newImplementation`, and subsequently execute the function call
     * encoded in `data`.
     *
     * Calls {_authorizeUpgrade}.
     *
     * Emits an {Upgraded} event.
     */
    function upgradeToAndCall(address newImplementation, bytes memory data) external payable virtual onlyProxy {
        _authorizeUpgrade(newImplementation);
        _upgradeToAndCallSecure(newImplementation, data, true);
    }

    /**
     * @dev Function that should revert when `msg.sender` is not authorized to upgrade the contract. Called by
     * {upgradeTo} and {upgradeToAndCall}.
     *
     * Normally, this function will use an xref:access.adoc[access control] modifier such as {Ownable-onlyOwner}.
     *
     * ```solidity
     * function _authorizeUpgrade(address) internal override onlyOwner {}
     * ```
     */
    function _authorizeUpgrade(address newImplementation) internal virtual;
}


// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts v4.4.1 (proxy/beacon/IBeacon.sol)

pragma solidity ^0.8.0;

/**
 * @dev This is the interface that {BeaconProxy} expects of its beacon.
 */
interface IBeacon {
    /**
     * @dev Must return an address that can be used as a delegate call target.
     *
     * {BeaconProxy} will check that this address is a contract.
     */
    function implementation() external view returns (address);
}


// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts v4.4.1 (proxy/ERC1967/ERC1967Upgrade.sol)

pragma solidity ^0.8.2;

import "../beacon/IBeacon.sol";
import "../../utils/Address.sol";
import "../../utils/StorageSlot.sol";

/**
 * @dev This abstract contract provides getters and event emitting update functions for
 * https://eips.ethereum.org/EIPS/eip-1967[EIP1967] slots.
 *
 * _Available since v4.1._
 *
 * @custom:oz-upgrades-unsafe-allow delegatecall
 */
abstract contract ERC1967Upgrade {
    // This is the keccak-256 hash of "eip1967.proxy.rollback" subtracted by 1
    bytes32 private constant _ROLLBACK_SLOT = 0x4910fdfa16fed3260ed0e7147f7cc6da11a60208b5b9406d12a635614ffd9143;

    /**
     * @dev Storage slot with the address of the current implementation.
     * This is the keccak-256 hash of "eip1967.proxy.implementation" subtracted by 1, and is
     * validated in the constructor.
     */
    bytes32 internal constant _IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    /**
     * @dev Emitted when the implementation is upgraded.
     */
    event Upgraded(address indexed implementation);

    /**
     * @dev Returns the current implementation address.
     */
    function _getImplementation() internal view returns (address) {
        return StorageSlot.getAddressSlot(_IMPLEMENTATION_SLOT).value;
    }

    /**
     * @dev Stores a new address in the EIP1967 implementation slot.
     */
    function _setImplementation(address newImplementation) private {
        require(Address.isContract(newImplementation), "ERC1967: new implementation is not a contract");
        StorageSlot.getAddressSlot(_IMPLEMENTATION_SLOT).value = newImplementation;
    }

    /**
     * @dev Perform implementation upgrade
     *
     * Emits an {Upgraded} event.
     */
    function _upgradeTo(address newImplementation) internal {
        _setImplementation(newImplementation);
        emit Upgraded(newImplementation);
    }

    /**
     * @dev Perform implementation upgrade with additional setup call.
     *
     * Emits an {Upgraded} event.
     */
    function _upgradeToAndCall(
        address newImplementation,
        bytes memory data,
        bool forceCall
    ) internal {
        _upgradeTo(newImplementation);
        if (data.length > 0 || forceCall) {
            Address.functionDelegateCall(newImplementation, data);
        }
    }

    /**
     * @dev Perform implementation upgrade with security checks for UUPS proxies, and additional setup call.
     *
     * Emits an {Upgraded} event.
     */
    function _upgradeToAndCallSecure(
        address newImplementation,
        bytes memory data,
        bool forceCall
    ) internal {
        address oldImplementation = _getImplementation();

        // Initial upgrade and setup call
        _setImplementation(newImplementation);
        if (data.length > 0 || forceCall) {
            Address.functionDelegateCall(newImplementation, data);
        }

        // Perform rollback test if not already in progress
        StorageSlot.BooleanSlot storage rollbackTesting = StorageSlot.getBooleanSlot(_ROLLBACK_SLOT);
        if (!rollbackTesting.value) {
            // Trigger rollback using upgradeTo from the new implementation
            rollbackTesting.value = true;
            Address.functionDelegateCall(
                newImplementation,
                abi.encodeWithSignature("upgradeTo(address)", oldImplementation)
            );
            rollbackTesting.value = false;
            // Check rollback was effective
            require(oldImplementation == _getImplementation(), "ERC1967Upgrade: upgrade breaks further upgrades");
            // Finally reset to the new implementation and log the upgrade
            _upgradeTo(newImplementation);
        }
    }

    /**
     * @dev Storage slot with the admin of the contract.
     * This is the keccak-256 hash of "eip1967.proxy.admin" subtracted by 1, and is
     * validated in the constructor.
     */
    bytes32 internal constant _ADMIN_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    /**
     * @dev Emitted when the admin account has changed.
     */
    event AdminChanged(address previousAdmin, address newAdmin);

    /**
     * @dev Returns the current admin.
     */
    function _getAdmin() internal view returns (address) {
        return StorageSlot.getAddressSlot(_ADMIN_SLOT).value;
    }

    /**
     * @dev Stores a new address in the EIP1967 admin slot.
     */
    function _setAdmin(address newAdmin) private {
        require(newAdmin != address(0), "ERC1967: new admin is the zero address");
        StorageSlot.getAddressSlot(_ADMIN_SLOT).value = newAdmin;
    }

    /**
     * @dev Changes the admin of the proxy.
     *
     * Emits an {AdminChanged} event.
     */
    function _changeAdmin(address newAdmin) internal {
        emit AdminChanged(_getAdmin(), newAdmin);
        _setAdmin(newAdmin);
    }

    /**
     * @dev The storage slot of the UpgradeableBeacon contract which defines the implementation for this proxy.
     * This is bytes32(uint256(keccak256('eip1967.proxy.beacon')) - 1)) and is validated in the constructor.
     */
    bytes32 internal constant _BEACON_SLOT = 0xa3f0ad74e5423aebfd80d3ef4346578335a9a72aeaee59ff6cb3582b35133d50;

    /**
     * @dev Emitted when the beacon is upgraded.
     */
    event BeaconUpgraded(address indexed beacon);

    /**
     * @dev Returns the current beacon.
     */
    function _getBeacon() internal view returns (address) {
        return StorageSlot.getAddressSlot(_BEACON_SLOT).value;
    }

    /**
     * @dev Stores a new beacon in the EIP1967 beacon slot.
     */
    function _setBeacon(address newBeacon) private {
        require(Address.isContract(newBeacon), "ERC1967: new beacon is not a contract");
        require(
            Address.isContract(IBeacon(newBeacon).implementation()),
            "ERC1967: beacon implementation is not a contract"
        );
        StorageSlot.getAddressSlot(_BEACON_SLOT).value = newBeacon;
    }

    /**
     * @dev Perform beacon upgrade with additional setup call. Note: This upgrades the address of the beacon, it does
     * not upgrade the implementation contained in the beacon (see {UpgradeableBeacon-_setImplementation} for that).
     *
     * Emits a {BeaconUpgraded} event.
     */
    function _upgradeBeaconToAndCall(
        address newBeacon,
        bytes memory data,
        bool forceCall
    ) internal {
        _setBeacon(newBeacon);
        emit BeaconUpgraded(newBeacon);
        if (data.length > 0 || forceCall) {
            Address.functionDelegateCall(IBeacon(newBeacon).implementation(), data);
        }
    }
}