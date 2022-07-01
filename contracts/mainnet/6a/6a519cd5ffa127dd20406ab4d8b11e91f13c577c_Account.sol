// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "@openzeppelin/contracts/utils/math/Math.sol";

import "./Managed.sol";
import "./common/UUPSOwnableUpgradeable.sol";
import "./common/UsingRegistryUpgradeable.sol";
import "./interfaces/IAccount.sol";

/**
 * @title A contract that facilitates voting on behalf of StakedCelo.sol.
 * @notice This contract depends on the Manager to decide how to distribute votes and how to
 * keep track of ownership of CELO voted via this contract.
 */
contract Account is UUPSOwnableUpgradeable, UsingRegistryUpgradeable, Managed, IAccount {
    /**
     * @notice Used to keep track of a pending withdrawal. A similar data structure
     * exists within LockedGold.sol, but it only keeps track of pending withdrawals
     * by the msg.sender to the LockedGold contract.
     * Because this contract facilitates withdrawals for different beneficiaries,
     * this contract must keep track of which beneficiaries correspond to which
     * pending withdrawals to prevent someone from finalizing/taking a pending
     * withdrawal they did not create.
     * @param value The withdrawal amount.
     * @param timestamp The timestamp at which the withdrawal amount becomes available.
     */
    struct PendingWithdrawal {
        uint256 value;
        uint256 timestamp;
    }

    /**
     * @notice Used to keep track of CELO that is scheduled to be used for
     * voting or revoking for a validator group.
     * @param toVote Amount of CELO held by this contract intended to vote for a group.
     * @param toWithdraw Amount of CELO that's scheduled for withdrawal.
     * @param toWithdrawFor Amount of CELO that's scheduled for withdrawal grouped by beneficiary.
     */
    struct ScheduledVotes {
        uint256 toVote;
        uint256 toWithdraw;
        mapping(address => uint256) toWithdrawFor;
    }

    /**
     * @notice Keyed by beneficiary address, the related array of pending withdrawals.
     * See `PendingWithdrawal` for more info.
     */
    mapping(address => PendingWithdrawal[]) public pendingWithdrawals;

    /**
     * @notice Keyed by validator group address, the ScheduledVotes struct
     * which holds the amount of CELO that's scheduled to vote, the amount
     * of CELO scheduled to be withdrawn, and the amount of CELO to be
     * withdrawn for each beneficiary.
     */
    mapping(address => ScheduledVotes) private scheduledVotes;

    /**
     * @notice Total amount of CELO scheduled to be withdrawn from all groups
     * by all beneficiaries.
     */
    uint256 public totalScheduledWithdrawals;

    /**
     * @notice Emitted when CELO is scheduled for voting for a given group.
     * @param group The validator group the CELO is intended to vote for.
     * @param amount The amount of CELO scheduled.
     */
    event VotesScheduled(address indexed group, uint256 amount);

    /**
     * @notice Emitted when CELO withdrawal is scheduled for a group.
     * @param group The validator group the CELO is withdrawn from.
     * @param withdrawalAmount The amount of CELO requested for withdrawal.
     * @param beneficiary The user for whom the withdrawal amount is intended for.
     */
    event CeloWithdrawalScheduled(
        address indexed beneficiary,
        address indexed group,
        uint256 withdrawalAmount
    );

    /**
     * @notice Emitted when CELO withdrawal kicked off for group. Immediate withdrawals
     * are not included in this event, but can be identified by a GoldToken.sol transfer
     * from this contract.
     * @param group The validator group the CELO is withdrawn from.
     * @param withdrawalAmount The amount of CELO requested for withdrawal.
     * @param beneficiary The user for whom the withdrawal amount is intended for.
     */
    event CeloWithdrawalStarted(
        address indexed beneficiary,
        address indexed group,
        uint256 withdrawalAmount
    );

    /**
     * @notice Emitted when a CELO withdrawal completes for `beneficiary`.
     * @param beneficiary The user for whom the withdrawal amount is intended.
     * @param amount The amount of CELO requested for withdrawal.
     * @param timestamp The timestamp of the pending withdrawal.
     */
    event CeloWithdrawalFinished(address indexed beneficiary, uint256 amount, uint256 timestamp);

    /// @notice Used when the creation of an account with Accounts.sol fails.
    error AccountCreationFailed();

    /// @notice Used when arrays passed for scheduling votes don't have matching lengths.
    error GroupsAndVotesArrayLengthsMismatch();

    /**
     * @notice Used when the sum of votes per groups during vote scheduling
     * doesn't match the `msg.value` sent with the call.
     * @param sentValue The `msg.value` of the call.
     * @param expectedValue The expected sum of votes for groups.
     */
    error TotalVotesMismatch(uint256 sentValue, uint256 expectedValue);

    /// @notice Used when activating of pending votes via Election has failed.
    error ActivatePendingVotesFailed(address group);

    /// @notice Used when voting via Election has failed.
    error VoteFailed(address group, uint256 amount);

    /// @notice Used when call to Election.sol's `revokePendingVotes` fails.
    error RevokePendingFailed(address group, uint256 amount);

    /// @notice Used when call to Election.sol's `revokeActiveVotes` fails.
    error RevokeActiveFailed(address group, uint256 amount);

    /**
     * @notice Used when active + pending votes amount is unable to fulfil a
     * withdrawal request amount.
     */
    error InsufficientRevokableVotes(address group, uint256 amount);

    /// @notice Used when unable to transfer CELO.
    error CeloTransferFailed(address to, uint256 amount);

    /**
     * @notice Used when `pendingWithdrawalIndex` is too high for the
     * beneficiary's pending withdrawals array.
     */
    error PendingWithdrawalIndexTooHigh(
        uint256 pendingWithdrawalIndex,
        uint256 pendingWithdrawalsLength
    );

    /**
     * @notice Used when attempting to schedule more withdrawals
     * than CELO available to the contract.
     * @param group The offending group.
     * @param celoAvailable CELO available to the group across scheduled, pending and active votes.
     * @param celoToWindraw total amount of CELO that would be scheduled to be withdrawn.
     */
    error WithdrawalAmountTooHigh(address group, uint256 celoAvailable, uint256 celoToWindraw);

    /**
     * @notice Used when any of the resolved stakedCeloGroupVoter.pendingWithdrawal
     * values do not match the equivalent record in lockedGold.pendingWithdrawals.
     */
    error InconsistentPendingWithdrawalValues(
        uint256 localPendingWithdrawalValue,
        uint256 lockedGoldPendingWithdrawalValue
    );

    /**
     * @notice Used when any of the resolved stakedCeloGroupVoter.pendingWithdrawal
     * timestamps do not match the equivalent record in lockedGold.pendingWithdrawals.
     */
    error InconsistentPendingWithdrawalTimestamps(
        uint256 localPendingWithdrawalTimestamp,
        uint256 lockedGoldPendingWithdrawalTimestamp
    );

    /// @notice There's no amount of scheduled withdrawal for the given beneficiary and group.
    error NoScheduledWithdrawal(address beneficiary, address group);

    /**
     * @notice Empty constructor for proxy implementation, `initializer` modifer ensures the
     * implementation gets initialized.
     */
    // solhint-disable-next-line no-empty-blocks
    constructor() initializer {}

    /**
     * @param _registry The address of the Celo registry.
     * @param _manager The address of the Manager contract.
     * @param _owner The address of the contract owner.
     */
    function initialize(
        address _registry,
        address _manager,
        address _owner
    ) external initializer {
        __UsingRegistry_init(_registry);
        __Managed_init(_manager);
        _transferOwnership(_owner);

        // Create an account so this contract can vote.
        if (!getAccounts().createAccount()) {
            revert AccountCreationFailed();
        }
    }

    // solhint-disable-next-line no-empty-blocks
    receive() external payable {}

    /**
     * @notice Deposits CELO sent via msg.value as unlocked CELO intended as
     * votes for groups.
     * @dev Only callable by the Staked CELO contract, which must restrict which groups are valid.
     * @param groups The groups the deposited CELO is intended to vote for.
     * @param votes The amount of CELO to schedule for each respective group
     * from `groups`.
     */
    function scheduleVotes(address[] calldata groups, uint256[] calldata votes)
        external
        payable
        onlyManager
    {
        if (groups.length != votes.length) {
            revert GroupsAndVotesArrayLengthsMismatch();
        }

        uint256 totalVotes;
        for (uint256 i = 0; i < groups.length; i++) {
            scheduledVotes[groups[i]].toVote += votes[i];
            totalVotes += votes[i];
            emit VotesScheduled(groups[i], votes[i]);
        }

        if (totalVotes != uint256(msg.value)) {
            revert TotalVotesMismatch(msg.value, totalVotes);
        }
    }

    /**
     * @notice Schedule a list of withdrawals to be refunded to a beneficiary.
     * @param groups The groups the deposited CELO is intended to be withdrawn from.
     * @param withdrawals The amount of CELO to withdraw for each respective group.
     * @param beneficiary The account that will receive the CELO once it's withdrawn.
     * from `groups`.
     */
    function scheduleWithdrawals(
        address beneficiary,
        address[] calldata groups,
        uint256[] calldata withdrawals
    ) external onlyManager {
        if (groups.length != withdrawals.length) {
            revert GroupsAndVotesArrayLengthsMismatch();
        }

        uint256 totalWithdrawalsDelta;

        for (uint256 i = 0; i < withdrawals.length; i++) {
            uint256 celoAvailableForGroup = this.getCeloForGroup(groups[i]);
            if (celoAvailableForGroup < withdrawals[i]) {
                revert WithdrawalAmountTooHigh(groups[i], celoAvailableForGroup, withdrawals[i]);
            }

            scheduledVotes[groups[i]].toWithdraw += withdrawals[i];
            scheduledVotes[groups[i]].toWithdrawFor[beneficiary] += withdrawals[i];
            totalWithdrawalsDelta += withdrawals[i];

            emit CeloWithdrawalScheduled(beneficiary, groups[i], withdrawals[i]);
        }

        totalScheduledWithdrawals += totalWithdrawalsDelta;
    }

    /**
     * @notice Starts withdrawal of CELO from `group`. If there is any unlocked CELO for the group,
     * that CELO is used for immediate withdrawal. Otherwise, CELO is taken from pending and active
     * votes, which are subject to the unlock period of LockedGold.sol.
     * @dev Only callable by the Staked CELO contract, which must restrict which groups are valid.
     * @param group The group to withdraw CELO from.
     * @param beneficiary The recipient of the withdrawn CELO.
     * @param lesserAfterPendingRevoke Used by Election's `revokePending`. This is the group that
     * is before `group` within the validators sorted LinkedList, or address(0) if there isn't one,
     * after the revoke of pending votes has occurred.
     * @param greaterAfterPendingRevoke Used by Election's `revokePending`. This is the group that
     * is after `group` within the validators sorted LinkedList, or address(0) if there isn't one,
     * after the revoke of pending votes has occurred.
     * @param lesserAfterActiveRevoke Used by Election's `revokeActive`. This is the group that
     * is before `group` within the validators sorted LinkedList, or address(0) if there isn't one,
     * after the revoke of active votes has occurred.
     * @param greaterAfterActiveRevoke Used by Election's `revokeActive`. This is the group that
     * is after `group` within the validators sorted LinkedList, or address(0) if there isn't one,
     * after the revoke of active votes has occurred.
     * @param index Used by Election's `revokePending` and `revokeActive`. This is the index of
     * `group` in the this contract's array of groups it is voting for.
     * @return The amount of immediately withdrawn CELO that is obtained from scheduledVotes
     * for `group`.
     */
    function withdraw(
        address beneficiary,
        address group,
        address lesserAfterPendingRevoke,
        address greaterAfterPendingRevoke,
        address lesserAfterActiveRevoke,
        address greaterAfterActiveRevoke,
        uint256 index
    ) external returns (uint256) {
        uint256 withdrawalAmount = scheduledVotes[group].toWithdrawFor[beneficiary];
        if (withdrawalAmount == 0) {
            revert NoScheduledWithdrawal(beneficiary, group);
        }
        // Emit early to return without needing to emit in multiple places.
        emit CeloWithdrawalStarted(beneficiary, group, withdrawalAmount);
        // Subtract withdrawal amount from all bookkeeping
        scheduledVotes[group].toWithdrawFor[beneficiary] = 0;
        scheduledVotes[group].toWithdraw -= withdrawalAmount;
        totalScheduledWithdrawals -= withdrawalAmount;

        uint256 immediateWithdrawalAmount = scheduledVotes[group].toVote;

        if (immediateWithdrawalAmount > 0) {
            if (immediateWithdrawalAmount > withdrawalAmount) {
                immediateWithdrawalAmount = withdrawalAmount;
            }

            scheduledVotes[group].toVote -= immediateWithdrawalAmount;

            // The benefit of using getGoldToken().transfer() rather than transferring
            // using a message value is that the recepient's callback is not called, thus
            // removing concern that a malicious beneficiary would control code at this point.
            bool success = getGoldToken().transfer(beneficiary, immediateWithdrawalAmount);
            if (!success) {
                revert CeloTransferFailed(beneficiary, immediateWithdrawalAmount);
            }
            // If we've withdrawn the entire amount, return.
            if (immediateWithdrawalAmount == withdrawalAmount) {
                return immediateWithdrawalAmount;
            }
        }

        // We know that withdrawalAmount is >= immediateWithdrawalAmount.
        uint256 revokeAmount = withdrawalAmount - immediateWithdrawalAmount;

        ILockedGold lockedGold = getLockedGold();

        // Save the pending withdrawal for `beneficiary`.
        pendingWithdrawals[beneficiary].push(
            PendingWithdrawal(revokeAmount, block.timestamp + lockedGold.unlockingPeriod())
        );

        revokeVotes(
            group,
            revokeAmount,
            lesserAfterPendingRevoke,
            greaterAfterPendingRevoke,
            lesserAfterActiveRevoke,
            greaterAfterActiveRevoke,
            index
        );

        lockedGold.unlock(revokeAmount);

        return immediateWithdrawalAmount;
    }

    /**
     * @notice Activates any activatable pending votes for group, and locks & votes any
     * unlocked CELO for group.
     * @dev Callable by anyone. In practice, this is expected to be called near the end of each
     * epoch by an off-chain agent.
     * @param group The group to activate pending votes for and lock & vote any unlocked CELO for.
     * @param voteLesser Used by Election's `vote`. This is the group that will recieve fewer
     * votes than group after the votes are cast, or address(0) if no such group exists.
     * @param voteGreater Used by Election's `vote`. This is the group that will recieve greater
     * votes than group after the votes are cast, or address(0) if no such group exists.
     */
    function activateAndVote(
        address group,
        address voteLesser,
        address voteGreater
    ) external {
        IElection election = getElection();

        // The amount of unlocked CELO for group that we want to lock and vote with.
        uint256 unlockedCeloForGroup = scheduledVotes[group].toVote;

        // Reset the unlocked CELO amount for group.
        scheduledVotes[group].toVote = 0;

        // If there are activatable pending votes from this contract for group, activate them.
        if (election.hasActivatablePendingVotes(address(this), group)) {
            // Revert if the activation fails.
            if (!election.activate(group)) {
                revert ActivatePendingVotesFailed(group);
            }
        }

        // If there is no CELO to lock up and vote with, return.
        if (unlockedCeloForGroup == 0) {
            return;
        }

        // Lock up the unlockedCeloForGroup in LockedGold, which increments the
        // non-voting LockedGold balance for this contract.
        getLockedGold().lock{value: unlockedCeloForGroup}();

        // Vote for group using the newly locked CELO, reverting if it fails.
        if (!election.vote(group, unlockedCeloForGroup, voteLesser, voteGreater)) {
            revert VoteFailed(group, unlockedCeloForGroup);
        }
    }

    /**
     * @notice Finishes a pending withdrawal created as a result of a `withdrawCelo` call,
     * claiming CELO after the `unlockingPeriod` defined in LockedGold.sol.
     * @dev Callable by anyone, but ultimatly the withdrawal goes to `beneficiary`.
     * The pending withdrawal info found in both StakedCeloGroupVoter and LockedGold must match
     * to ensure that the beneficiary is claiming the appropriate pending withdrawal.
     * @param beneficiary The account that owns the pending withdrawal being processed.
     * @param localPendingWithdrawalIndex The index of the pending withdrawal to finish
     * in pendingWithdrawals[beneficiary] array.
     * @param lockedGoldPendingWithdrawalIndex The index of the pending withdrawal to finish
     * in LockedGold.
     * @return amount The amount of CELO sent to `beneficiary`.
     */
    function finishPendingWithdrawal(
        address beneficiary,
        uint256 localPendingWithdrawalIndex,
        uint256 lockedGoldPendingWithdrawalIndex
    ) external returns (uint256 amount) {
        (uint256 value, uint256 timestamp) = validatePendingWithdrawalRequest(
            beneficiary,
            localPendingWithdrawalIndex,
            lockedGoldPendingWithdrawalIndex
        );

        // Remove the pending withdrawal.
        PendingWithdrawal[] storage localPendingWithdrawals = pendingWithdrawals[beneficiary];
        localPendingWithdrawals[localPendingWithdrawalIndex] = localPendingWithdrawals[
            localPendingWithdrawals.length - 1
        ];
        localPendingWithdrawals.pop();

        // Process withdrawal.
        getLockedGold().withdraw(lockedGoldPendingWithdrawalIndex);

        /**
         * The benefit of using getGoldToken().transfer() is that the recepients callback
         * is not called thus removing concern that a malicious
         * caller would control code at this point.
         */
        bool success = getGoldToken().transfer(beneficiary, value);
        if (!success) {
            revert CeloTransferFailed(beneficiary, value);
        }

        emit CeloWithdrawalFinished(beneficiary, value, timestamp);
        return value;
    }

    /**
     * @notice Gets the total amount of CELO this contract controls. This is the
     * unlocked CELO balance of the contract plus the amount of LockedGold for this contract,
     * which included unvoting and voting LockedGold.
     * @return The total amount of CELO this contract controls, including LockedGold.
     */
    function getTotalCelo() external view returns (uint256) {
        // LockedGold's getAccountTotalLockedGold returns any non-voting locked gold +
        // voting locked gold for each group the account is voting for, which is an
        // O(# of groups voted for) operation.
        return
            address(this).balance +
            getLockedGold().getAccountTotalLockedGold(address(this)) -
            totalScheduledWithdrawals;
    }

    /**
     * @notice Returns the pending withdrawals for a beneficiary.
     * @param beneficiary The address of the beneficiary who initiated the pending withdrawal.
     * @return values The values of pending withdrawals.
     * @return timestamps The timestamps of pending withdrawals.
     */
    function getPendingWithdrawals(address beneficiary)
        external
        view
        returns (uint256[] memory values, uint256[] memory timestamps)
    {
        uint256 length = pendingWithdrawals[beneficiary].length;
        values = new uint256[](length);
        timestamps = new uint256[](length);

        for (uint256 i = 0; i < length; i++) {
            PendingWithdrawal memory p = pendingWithdrawals[beneficiary][i];
            values[i] = p.value;
            timestamps[i] = p.timestamp;
        }

        return (values, timestamps);
    }

    /**
     * @notice Returns the number of pending withdrawals for a beneficiary.
     * @param beneficiary The address of the beneficiary who initiated the pending withdrawal.
     * @return The numbers of pending withdrawals for `beneficiary`
     */
    function getNumberPendingWithdrawals(address beneficiary) external view returns (uint256) {
        return pendingWithdrawals[beneficiary].length;
    }

    /**
     * @notice Returns a pending withdrawals for a beneficiary.
     * @param beneficiary The address of the beneficiary who initiated the pending withdrawal.
     * @param index The index in `beneficiary`'s pendingWithdrawals array.
     * @return value The values of the pending withdrawal.
     * @return timestamp The timestamp of the pending withdrawal.
     */
    function getPendingWithdrawal(address beneficiary, uint256 index)
        external
        view
        returns (uint256 value, uint256 timestamp)
    {
        PendingWithdrawal memory withdrawal = pendingWithdrawals[beneficiary][index];

        return (withdrawal.value, withdrawal.timestamp);
    }

    /**
     * @notice Returns the total amount of CELO directed towards `group`. This is
     * the Unlocked CELO balance for `group` plus the combined amount in pending
     * and active votes made by this contract.
     * @param group The address of the validator group.
     * @return The total amount of CELO directed towards `group`.
     */
    function getCeloForGroup(address group) external view returns (uint256) {
        return
            getElection().getTotalVotesForGroupByAccount(group, address(this)) +
            scheduledVotes[group].toVote -
            scheduledVotes[group].toWithdraw;
    }

    /**
     * @notice Returns the total amount of CELO that's scheduled to vote for a group.
     * @param group The address of the validator group.
     * @return The total amount of CELO directed towards `group`.
     */
    function scheduledVotesForGroup(address group) external view returns (uint256) {
        return scheduledVotes[group].toVote;
    }

    /**
     * @notice Returns the total amount of CELO that's scheduled to be withdrawn for a group.
     * @param group The address of the validator group.
     * @return The total amount of CELO to be withdrawn for `group`.
     */
    function scheduledWithdrawalsForGroup(address group) external view returns (uint256) {
        return scheduledVotes[group].toWithdraw;
    }

    /**
     * @notice Returns the total amount of CELO that's scheduled to be withdrawn for a group
     * scoped by a beneficiary.
     * @param group The address of the validator group.
     * @param beneficiary The beneficiary of the withdrawal.
     * @return The total amount of CELO to be withdrawn for `group` by `beneficiary`.
     */
    function scheduledWithdrawalsForGroupAndBeneficiary(address group, address beneficiary)
        external
        view
        returns (uint256)
    {
        return scheduledVotes[group].toWithdrawFor[beneficiary];
    }

    /**
     * @notice Revokes votes from a validator group. It first attempts to revoke pending votes,
     * and then active votes if necessary.
     * @dev Reverts if `revokeAmount` exceeds the total number of pending and active votes for
     * the group from this contract.
     * @param group The group to withdraw CELO from.
     * @param revokeAmount The amount of votes to revoke.
     * @param lesserAfterPendingRevoke Used by Election's `revokePending`. This is the group that
     * is before `group` within the validators sorted LinkedList, or address(0) if there isn't one,
     * after the revoke of pending votes has occurred.
     * @param greaterAfterPendingRevoke Used by Election's `revokePending`. This is the group that
     * is after `group` within the validators sorted LinkedList, or address(0) if there isn't one,
     * after the revoke of pending votes has occurred.
     * @param lesserAfterActiveRevoke Used by Election's `revokeActive`. This is the group that
     * is before `group` within the validators sorted LinkedList, or address(0) if there isn't one,
     * after the revoke of active votes has occurred.
     * @param greaterAfterActiveRevoke Used by Election's `revokeActive`. This is the group that
     * is after `group` within the validators sorted LinkedList, or address(0) if there isn't one,
     * after the revoke of active votes has occurred.
     * @param index Used by Election's `revokePending` and `revokeActive`. This is the index of
     * `group` in the this contract's array of groups it is voting for.
     */
    function revokeVotes(
        address group,
        uint256 revokeAmount,
        address lesserAfterPendingRevoke,
        address greaterAfterPendingRevoke,
        address lesserAfterActiveRevoke,
        address greaterAfterActiveRevoke,
        uint256 index
    ) internal {
        IElection election = getElection();
        uint256 pendingVotesAmount = election.getPendingVotesForGroupByAccount(
            group,
            address(this)
        );

        uint256 toRevokeFromPending = Math.min(revokeAmount, pendingVotesAmount);
        if (toRevokeFromPending > 0) {
            if (
                !election.revokePending(
                    group,
                    toRevokeFromPending,
                    lesserAfterPendingRevoke,
                    greaterAfterPendingRevoke,
                    index
                )
            ) {
                revert RevokePendingFailed(group, revokeAmount);
            }
        }

        uint256 toRevokeFromActive = revokeAmount - toRevokeFromPending;
        if (toRevokeFromActive == 0) {
            return;
        }

        uint256 activeVotesAmount = election.getActiveVotesForGroupByAccount(group, address(this));

        if (activeVotesAmount < toRevokeFromActive) {
            revert InsufficientRevokableVotes(group, revokeAmount);
        }

        if (
            !election.revokeActive(
                group,
                toRevokeFromActive,
                lesserAfterActiveRevoke,
                greaterAfterActiveRevoke,
                index
            )
        ) {
            revert RevokeActiveFailed(group, revokeAmount);
        }
    }

    /**
     * @notice Validates a local pending withdrawal matches a given beneficiary and LockedGold
     * pending withdrawal.
     * @dev See finishPendingWithdrawal.
     * @param beneficiary The account that owns the pending withdrawal being processed.
     * @param localPendingWithdrawalIndex The index of the pending withdrawal to finish
     * in pendingWithdrawals[beneficiary] array.
     * @param lockedGoldPendingWithdrawalIndex The index of the pending withdrawal to finish
     * in LockedGold.
     * @return value The value of the pending withdrawal.
     * @return timestamp The timestamp of the pending withdrawal.
     */
    function validatePendingWithdrawalRequest(
        address beneficiary,
        uint256 localPendingWithdrawalIndex,
        uint256 lockedGoldPendingWithdrawalIndex
    ) internal view returns (uint256 value, uint256 timestamp) {
        if (localPendingWithdrawalIndex >= pendingWithdrawals[beneficiary].length) {
            revert PendingWithdrawalIndexTooHigh(
                localPendingWithdrawalIndex,
                pendingWithdrawals[beneficiary].length
            );
        }

        (
            uint256 lockedGoldPendingWithdrawalValue,
            uint256 lockedGoldPendingWithdrawalTimestamp
        ) = getLockedGold().getPendingWithdrawal(address(this), lockedGoldPendingWithdrawalIndex);

        PendingWithdrawal memory pendingWithdrawal = pendingWithdrawals[beneficiary][
            localPendingWithdrawalIndex
        ];

        if (pendingWithdrawal.value != lockedGoldPendingWithdrawalValue) {
            revert InconsistentPendingWithdrawalValues(
                pendingWithdrawal.value,
                lockedGoldPendingWithdrawalValue
            );
        }

        if (pendingWithdrawal.timestamp != lockedGoldPendingWithdrawalTimestamp) {
            revert InconsistentPendingWithdrawalTimestamps(
                pendingWithdrawal.timestamp,
                lockedGoldPendingWithdrawalTimestamp
            );
        }

        return (pendingWithdrawal.value, pendingWithdrawal.timestamp);
    }
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

    function scheduledVotesForGroup(address group) external returns (uint256);

    function scheduleWithdrawals(
        address beneficiary,
        address[] calldata group,
        uint256[] calldata withdrawals
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


// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/**
 * @title Used via inheritance to grant special access control to the Manager
 * contract.
 */
abstract contract Managed is Initializable, OwnableUpgradeable {
    address public manager;

    /**
     * @notice Emitted when the manager is initially set or later modified.
     * @param manager The new managing account address.
     */
    event ManagerSet(address indexed manager);

    /**
     *  @notice Used when an `onlyManager` function is called by a non-manager.
     *  @param caller `msg.sender` that called the function.
     */
    error CallerNotManager(address caller);

    /**
     * @notice Used when a passed address is address(0).
     */
    error NullAddress();

    /**
     * @dev Initializes the contract in an upgradable context.
     * @param _manager The initial managing address.
     */
    // solhint-disable-next-line func-name-mixedcase
    function __Managed_init(address _manager) internal onlyInitializing {
        _setManager(_manager);
    }

    /**
     * @dev Throws if called by any account other than the manager.
     */
    modifier onlyManager() {
        if (manager != msg.sender) {
            revert CallerNotManager(msg.sender);
        }
        _;
    }

    /**
     * @notice Sets the manager address.
     * @param _manager The new manager address.
     */
    function setManager(address _manager) external onlyOwner {
        _setManager(_manager);
    }

    /**
     * @notice Sets the manager address.
     * @param _manager The new manager address.
     */
    function _setManager(address _manager) internal {
        if (_manager == address(0)) {
            revert NullAddress();
        }
        manager = _manager;
        emit ManagerSet(_manager);
    }
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