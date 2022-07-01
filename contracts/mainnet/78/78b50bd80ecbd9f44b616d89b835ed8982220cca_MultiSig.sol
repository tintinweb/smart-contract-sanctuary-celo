//SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";

import "../libraries/ExternalCall.sol";

/**
 * @title Multisignature wallet - Allows multiple parties to agree on proposals before
 * execution.
 * @author Stefan George - <[email protected]>
 * @dev NOTE: This contract has its limitations and is not viable for every
 * multi-signature setup. On a case by case basis, evaluate whether this is the
 * correct contract for your use case.
 * In particular, this contract doesn't have an atomic "add owners and increase
 * requirement" operation.
 * This can be tricky, for example, in a situation where a MultiSig starts out
 * owned by a single owner. Safely increasing the owner set and requirement at
 * the same time is not trivial. One way to work around this situation is to
 * first add a second address controlled by the original owner, increase the
 * requirement, and then replace the auxillary address with the intended second
 * owner.
 * Again, this is just one example, in general make sure to verify this contract
 * will support your intended usage. The goal of this contract is to offer a
 * simple, minimal multi-signature API that's easy to understand even for novice
 * Solidity users.
 * Forked from
 * github.com/celo-org/celo-monorepo/blob/master/packages/protocol/contracts/common/MultiSig.sol
 */
contract MultiSig is Initializable, UUPSUpgradeable {
    using EnumerableSet for EnumerableSet.AddressSet;

    /**
     * @notice The maximum number of multisig owners.
     */
    uint256 public constant MAX_OWNER_COUNT = 50;

    /**
     * @notice The minimum time in seconds that must elapse before a proposal is executable.
     */
    uint256 public immutable minDelay;

    /**
     * @notice The value used to mark a proposal as executed.
     */
    uint256 internal constant DONE_TIMESTAMP = uint256(1);

    /**
     * @notice Used to keep track of a proposal.
     * @param destinations The addresses at which the proposal is directed to.
     * @param values The amounts of CELO involved.
     * @param payloads The payloads of the proposal.
     * @param timestampExecutable The timestamp at which a proposal becomes executable.
     * @dev timestampExecutable is 0 if proposal is not yet scheduled or 1 if the proposal
     * is executed.
     * @param confirmations The list of confirmations. Keyed by the address that
     * confirmed the proposal, whether or not the proposal is confirmed.
     */
    struct Proposal {
        address[] destinations;
        uint256[] values;
        bytes[] payloads;
        uint256 timestampExecutable;
        mapping(address => bool) confirmations;
    }

    /**
     * @notice The delay that must elapse to be able to execute a proposal.
     */
    uint256 public delay;

    /**
     * @notice Keyed by proposal ID, the Proposal record.
     */
    mapping(uint256 => Proposal) public proposals;

    /**
     * @notice The set of addresses which are owners of the multisig.
     */
    EnumerableSet.AddressSet private owners;

    /**
     * @notice The amount of confirmations required
     * for a proposal to be fully confirmed.
     */
    uint256 public required;

    /**
     * @notice The total count of proposals.
     */
    uint256 public proposalCount;

    /**
     * @notice Used when a proposal is successfully confirmed.
     * @param sender The address of the sender.
     * @param proposalId The ID of the proposal.
     */
    event ProposalConfirmed(address indexed sender, uint256 indexed proposalId);

    /**
     * @notice Used when a confirmation is successfully revoked.
     * @param sender The address of the sender.
     * @param proposalId The ID of the proposal.
     */
    event ConfirmationRevoked(address indexed sender, uint256 indexed proposalId);

    /**
     * @notice Used when a proposal is successfully added.
     * @param proposalId The ID of the proposal that was added.
     */
    event ProposalAdded(uint256 indexed proposalId);

    /**
     * @notice Emitted when a confirmed proposal is successfully executed.
     * @param proposalId The ID of the proposal that was executed.
     * @param returnData The response that was recieved from the external call.
     */
    event ProposalExecuted(uint256 indexed proposalId, bytes returnData);

    /**
     * @notice Emitted when one of the transactions that make up a proposal is successfully
     * executed.
     * @param index The index of the transaction within the proposal.
     * @param proposalId The ID of the proposal.
     * @param returnData The response that was recieved from the external call.
     */
    event TransactionExecuted(uint256 index, uint256 indexed proposalId, bytes returnData);

    /**
     * @notice Emitted when CELO is sent to this contract.
     * @param sender The account which sent the CELO.
     * @param value The amount of CELO sent.
     */
    event CeloDeposited(address indexed sender, uint256 value);

    /**
     * @notice Emitted when an Owner is successfully added as part of the multisig.
     * @param owner The added owner.
     */
    event OwnerAdded(address indexed owner);

    /**
     * @notice Emitted when an Owner is successfully removed from the multisig.
     * @param owner The removed owner.
     */
    event OwnerRemoved(address indexed owner);

    /**
     * @notice Emitted when the minimum amount of required confirmations is
     * successfully changed.
     * @param required The new required amount.
     */
    event RequirementChanged(uint256 required);

    /**
     * @notice Emitted when a proposal is scheduled.
     * @param proposalId The ID of the proposal that is scheduled.
     */
    event ProposalScheduled(uint256 indexed proposalId);

    /**
     * @notice Used when `delay` is changed.
     * @param delay The current delay value.
     * @param newDelay The new delay value.
     */
    event DelayChanged(uint256 delay, uint256 newDelay);

    /**
     * @notice Used when sender is not this contract in an `onlyWallet` function.
     * @param account The sender which triggered the function.
     */
    error SenderMustBeMultisigWallet(address account);

    /**
     * @notice Used when attempting to add an already existing owner.
     * @param owner The address of the owner.
     */
    error OwnerAlreadyExists(address owner);

    /**
     * @notice Used when an owner does not exist.
     * @param owner The address of the owner.
     */
    error OwnerDoesNotExist(address owner);

    /**
     * @notice Used when a proposal does not exist.
     * @param proposalId The ID of the non-existent proposal.
     */
    error ProposalDoesNotExist(uint256 proposalId);

    /**
     * @notice Used when a proposal is not confirmed by a given owner.
     * @param proposalId The ID of the proposal that is not confirmed.
     * @param owner The address of the owner which did not confirm the proposal.
     */
    error ProposalNotConfirmed(uint256 proposalId, address owner);

    /**
     * @notice Used when a proposal is not fully confirmed.
     * @dev A proposal is fully confirmed when the `required` threshold
     * of confirmations has been met.
     * @param proposalId The ID of the proposal that is not fully confirmed.
     */
    error ProposalNotFullyConfirmed(uint256 proposalId);

    /**
     * @notice Used when a proposal is already confirmed by an owner.
     * @param proposalId The ID of the proposal that is already confirmed.
     * @param owner The address of the owner which confirmed the proposal.
     */
    error ProposalAlreadyConfirmed(uint256 proposalId, address owner);

    /**
     * @notice Used when a proposal has been executed.
     * @param proposalId The ID of the proposal that is already executed.
     */
    error ProposalAlreadyExecuted(uint256 proposalId);

    /**
     * @notice Used when a passed address is address(0).
     */
    error NullAddress();

    /**
     * @notice Used when the set threshold values for owner and minimum
     * required confirmations are not met.
     * @param ownerCount The count of owners.
     * @param required The number of required confirmations.
     */
    error InvalidRequirement(uint256 ownerCount, uint256 required);

    /**
     * @notice Used when attempting to remove the last owner.
     * @param owner The last owner.
     */
    error CannotRemoveLastOwner(address owner);

    /**
     * @notice Used when attempting to schedule an already scheduled proposal.
     * @param proposalId The ID of the proposal which is already scheduled.
     */
    error ProposalAlreadyScheduled(uint256 proposalId);

    /**
     * @notice Used when a proposal is not scheduled.
     * @param proposalId The ID of the proposal which is not scheduled.
     */
    error ProposalNotScheduled(uint256 proposalId);

    /**
     * @notice Used when a time lock delay is not reached.
     * @param proposalId The ID of the proposal whose time lock has not been reached yet.
     */
    error ProposalTimelockNotReached(uint256 proposalId);

    /**
     * @notice Used when a provided value is less than the minimum time lock delay.
     * @param delay The insufficient delay.
     */
    error InsufficientDelay(uint256 delay);

    /**
     * @notice Used when the sizes of the provided arrays params do not match
     * when submitting a proposal.
     */
    error ParamLengthsMismatch();

    /**
     * @notice Checks that only the multisig contract can execute a function.
     */
    modifier onlyWallet() {
        if (msg.sender != address(this)) {
            revert SenderMustBeMultisigWallet(msg.sender);
        }
        _;
    }

    /**
     * @notice Checks that an address is not a multisig owner.
     * @param owner The address to check.
     */
    modifier ownerDoesNotExist(address owner) {
        if (owners.contains(owner)) {
            revert OwnerAlreadyExists(owner);
        }
        _;
    }

    /**
     * @notice Checks that an address is a multisig owner.
     * @param owner The address to check.
     */
    modifier ownerExists(address owner) {
        if (!owners.contains(owner)) {
            revert OwnerDoesNotExist(owner);
        }
        _;
    }

    /**
     * @notice Checks that a proposal exists.
     * @param proposalId The proposal ID to check.
     */
    modifier proposalExists(uint256 proposalId) {
        if (proposals[proposalId].destinations.length == 0) {
            revert ProposalDoesNotExist(proposalId);
        }
        _;
    }

    /**
     * @notice Checks that a proposal has been confirmed by a multisig owner.
     * @param proposalId The proposal ID to check.
     * @param owner The owner to check.
     */
    modifier confirmed(uint256 proposalId, address owner) {
        if (!proposals[proposalId].confirmations[owner]) {
            revert ProposalNotConfirmed(proposalId, owner);
        }
        _;
    }

    /**
     * @notice Checks that a proposal has not been confirmed by a multisig owner.
     * @param proposalId The proposal ID to check.
     * @param owner The owner to check.
     */
    modifier notConfirmed(uint256 proposalId, address owner) {
        if (proposals[proposalId].confirmations[owner]) {
            revert ProposalAlreadyConfirmed(proposalId, owner);
        }
        _;
    }

    /**
     * @notice Checks that a proposal has not been executed.
     * @dev A proposal can only be executed after it is fully confirmed.
     * @param proposalId The proposal ID to check.
     */
    modifier notExecuted(uint256 proposalId) {
        if (proposals[proposalId].timestampExecutable == DONE_TIMESTAMP) {
            revert ProposalAlreadyExecuted(proposalId);
        }
        _;
    }

    /**
     * @notice Checks that an address is not address(0).
     * @param addr The address to check.
     */
    modifier notNull(address addr) {
        if (addr == address(0)) {
            revert NullAddress();
        }
        _;
    }

    /**
     * @notice Checks that each address in a batch of addresses are not address(0).
     * @param _addresses The addresses to check.
     */
    modifier notNullBatch(address[] memory _addresses) {
        for (uint256 i = 0; i < _addresses.length; i++) {
            if (_addresses[i] == address(0)) {
                revert NullAddress();
            }
        }
        _;
    }

    /**
     * @notice Checks that the values passed for number of multisig owners and required
     * confirmation are valid in comparison with the configured thresholds.
     * @param ownerCount The owners count to check.
     * @param requiredConfirmations The minimum number of confirmations required to consider
     * a proposal as fully confirmed.
     */
    modifier validRequirement(uint256 ownerCount, uint256 requiredConfirmations) {
        if (
            ownerCount > MAX_OWNER_COUNT ||
            requiredConfirmations > ownerCount ||
            requiredConfirmations == 0 ||
            ownerCount == 0
        ) {
            revert InvalidRequirement(ownerCount, requiredConfirmations);
        }
        _;
    }

    /**
     * @notice Checks that a proposal is scheduled.
     * @param proposalId The ID of the proposal to check.
     */
    modifier scheduled(uint256 proposalId) {
        if (!isScheduled(proposalId)) {
            revert ProposalNotScheduled(proposalId);
        }
        _;
    }

    /**
     * @notice Checks that a proposal is not scheduled.
     * @param proposalId The ID of the proposal to check.
     */
    modifier notScheduled(uint256 proposalId) {
        if (isScheduled(proposalId)) {
            revert ProposalAlreadyScheduled(proposalId);
        }
        _;
    }

    /**
     * @notice Checks that a proposal's time lock has elapsed.
     * @param proposalId The ID of the proposal to check.
     */
    modifier timeLockReached(uint256 proposalId) {
        if (!isProposalTimelockReached(proposalId)) {
            revert ProposalTimelockNotReached(proposalId);
        }
        _;
    }

    /**
     * @notice Checks that a proposal is fully confirmed.
     * @param proposalId The ID of the proposal to check.
     */
    modifier fullyConfirmed(uint256 proposalId) {
        if (!isFullyConfirmed(proposalId)) {
            revert ProposalNotFullyConfirmed(proposalId);
        }
        _;
    }

    /**
     * @notice Sets `initialized` to  true on implementation contracts.
     * @param _minDelay The minimum time in seconds that must elapse before a
     * proposal is executable.
     */
    // solhint-disable-next-line no-empty-blocks
    constructor(uint256 _minDelay) initializer {
        minDelay = _minDelay;
    }

    receive() external payable {
        if (msg.value > 0) {
            emit CeloDeposited(msg.sender, msg.value);
        }
    }

    /**
     * @notice Bootstraps this contract with initial data.
     * @dev This plays the role of a typical contract constructor. Sets initial owners and
     * required number of confirmations. The initializer modifier ensures that this function
     * is ONLY callable once.
     * @param initialOwners The list of initial owners.
     * @param requiredConfirmations The number of required confirmations for a proposal
     * to be fully confirmed.
     * @param _delay The delay that must elapse to be able to execute a proposal.
     */
    function initialize(
        address[] calldata initialOwners,
        uint256 requiredConfirmations,
        uint256 _delay
    ) external initializer validRequirement(initialOwners.length, requiredConfirmations) {
        for (uint256 i = 0; i < initialOwners.length; i++) {
            if (owners.contains(initialOwners[i])) {
                revert OwnerAlreadyExists(initialOwners[i]);
            }

            if (initialOwners[i] == address(0)) {
                revert NullAddress();
            }

            owners.add(initialOwners[i]);
            emit OwnerAdded(initialOwners[i]);
        }
        _changeRequirement(requiredConfirmations);
        _changeDelay(_delay);
    }

    /**
     * @notice Adds a new multisig owner.
     * @dev This call can only be made by this contract.
     * @param owner The owner to add.
     */
    function addOwner(address owner)
        external
        onlyWallet
        ownerDoesNotExist(owner)
        notNull(owner)
        validRequirement(owners.length() + 1, required)
    {
        owners.add(owner);
        emit OwnerAdded(owner);
    }

    /**
     * @notice Removes an existing owner.
     * @dev This call can only be made by this contract.
     * @param owner The owner to remove.
     */
    function removeOwner(address owner) external onlyWallet ownerExists(owner) {
        if (owners.length() == 1) {
            revert CannotRemoveLastOwner(owner);
        }

        owners.remove(owner);

        if (required > owners.length()) {
            // Readjust the required amount, since the list of total owners has reduced.
            changeRequirement(owners.length());
        }
        emit OwnerRemoved(owner);
    }

    /**
     * @notice Replaces an existing owner with a new owner.
     * @dev This call can only be made by this contract.
     * @param owner The owner to be replaced.
     */
    function replaceOwner(address owner, address newOwner)
        external
        onlyWallet
        ownerExists(owner)
        notNull(newOwner)
        ownerDoesNotExist(newOwner)
    {
        owners.remove(owner);
        owners.add(newOwner);
        emit OwnerRemoved(owner);
        emit OwnerAdded(newOwner);
    }

    /**
     * @notice Void a confirmation for a previously confirmed proposal.
     * @param proposalId The ID of the proposal to be revoked.
     */
    function revokeConfirmation(uint256 proposalId)
        external
        ownerExists(msg.sender)
        confirmed(proposalId, msg.sender)
        notExecuted(proposalId)
    {
        proposals[proposalId].confirmations[msg.sender] = false;
        emit ConfirmationRevoked(msg.sender, proposalId);
    }

    /**
     * @notice Creates a proposal and triggers the first confirmation on behalf of the
     * proposal creator.
     * @param destinations The addresses at which the proposal is target at.
     * @param values The CELO values involved in the proposal if any.
     * @param payloads The payloads of the proposal.
     * @return proposalId Returns the ID of the proposal that gets generated.
     */
    function submitProposal(
        address[] calldata destinations,
        uint256[] calldata values,
        bytes[] calldata payloads
    ) external returns (uint256 proposalId) {
        if (destinations.length != values.length) {
            revert ParamLengthsMismatch();
        }

        if (destinations.length != payloads.length) {
            revert ParamLengthsMismatch();
        }
        proposalId = addProposal(destinations, values, payloads);
        confirmProposal(proposalId);
    }

    /**
     * @notice Get the list of multisig owners.
     * @return The list of owner addresses.
     */
    function getOwners() external view returns (address[] memory) {
        return owners.values();
    }

    /**
     * @notice Gets the list of owners' addresses which have confirmed a given proposal.
     * @param proposalId The ID of the proposal.
     * @return The list of owner addresses.
     */
    function getConfirmations(uint256 proposalId) external view returns (address[] memory) {
        address[] memory confirmationsTemp = new address[](owners.length());
        uint256 count = 0;
        for (uint256 i = 0; i < owners.length(); i++) {
            if (proposals[proposalId].confirmations[owners.at(i)]) {
                confirmationsTemp[count] = owners.at(i);
                count++;
            }
        }
        address[] memory confirmingOwners = new address[](count);
        for (uint256 i = 0; i < count; i++) {
            confirmingOwners[i] = confirmationsTemp[i];
        }
        return confirmingOwners;
    }

    /**
     * @notice Gets the destinations, values and payloads of a proposal.
     * @param proposalId The ID of the proposal.
     * @param destinations The addresses at which the proposal is target at.
     * @param values The CELO values involved in the proposal if any.
     * @param payloads The payloads of the proposal.
     */
    function getProposal(uint256 proposalId)
        external
        view
        returns (
            address[] memory destinations,
            uint256[] memory values,
            bytes[] memory payloads
        )
    {
        Proposal storage proposal = proposals[proposalId];
        return (proposal.destinations, proposal.values, proposal.payloads);
    }

    /**
     * @notice Changes the number of confirmations required to consider a proposal
     * fully confirmed.
     * @dev Proposal has to be sent by wallet.
     * @param newRequired The new number of confirmations required.
     */
    function changeRequirement(uint256 newRequired)
        public
        onlyWallet
        validRequirement(owners.length(), newRequired)
    {
        _changeRequirement(newRequired);
    }

    /**
     * @notice Changes the value of the delay that must
     * elapse before a proposal can become executable.
     * @dev Proposal has to be sent by wallet.
     * @param newDelay The new delay value.
     */
    function changeDelay(uint256 newDelay) public onlyWallet {
        _changeDelay(newDelay);
    }

    /**
     * @notice Confirms a proposal. A proposal is executed if this confirmation
     * makes it fully confirmed.
     * @param proposalId The ID of the proposal to confirm.
     */
    function confirmProposal(uint256 proposalId)
        public
        ownerExists(msg.sender)
        proposalExists(proposalId)
        notConfirmed(proposalId, msg.sender)
    {
        proposals[proposalId].confirmations[msg.sender] = true;
        emit ProposalConfirmed(msg.sender, proposalId);
        if (isFullyConfirmed(proposalId)) {
            scheduleProposal(proposalId);
        }
    }

    /**
     * @notice Schedules a proposal with a time lock.
     * @param proposalId The ID of the proposal to confirm.
     */
    function scheduleProposal(uint256 proposalId)
        public
        ownerExists(msg.sender)
        notExecuted(proposalId)
    {
        schedule(proposalId);
        emit ProposalScheduled(proposalId);
    }

    /**
     * @notice Executes a proposal. A proposal is only executetable if it is fully confirmed,
     * scheduled and the set delay has elapsed.
     * @dev Any of the multisig owners can execute a given proposal, even though they may
     * not have participated in its confirmation process.
     */
    function executeProposal(uint256 proposalId)
        public
        ownerExists(msg.sender)
        scheduled(proposalId)
        notExecuted(proposalId)
        timeLockReached(proposalId)
    {
        Proposal storage proposal = proposals[proposalId];
        proposal.timestampExecutable = DONE_TIMESTAMP;

        for (uint256 i = 0; i < proposals[proposalId].destinations.length; i++) {
            bytes memory returnData = ExternalCall.execute(
                proposal.destinations[i],
                proposal.values[i],
                proposal.payloads[i]
            );
            emit TransactionExecuted(i, proposalId, returnData);
        }
    }

    /**
     * @notice Returns the timestamp at which a proposal becomes executable.
     * @param proposalId The ID of the proposal.
     * @return The timestamp at which the proposal becomes executable.
     */
    function getTimestamp(uint256 proposalId) public view returns (uint256) {
        return proposals[proposalId].timestampExecutable;
    }

    /**
     * @notice Returns whether a proposal is scheduled.
     * @param proposalId The ID of the proposal to check.
     * @return Whether or not the proposal is scheduled.
     */
    function isScheduled(uint256 proposalId) public view returns (bool) {
        return getTimestamp(proposalId) > DONE_TIMESTAMP;
    }

    /**
     * @notice Returns whether a proposal is executable or not.
     * A proposal is executable if it is scheduled, the delay has elapsed
     * and it is not yet executed.
     * @param proposalId The ID of the proposal to check.
     * @return Whether or not the time lock is reached.
     */
    function isProposalTimelockReached(uint256 proposalId) public view returns (bool) {
        uint256 timestamp = getTimestamp(proposalId);
        return
            timestamp <= block.timestamp &&
            proposals[proposalId].timestampExecutable > DONE_TIMESTAMP;
    }

    /**
     * @notice Checks that a proposal has been confirmed by at least the `required`
     * number of owners.
     * @param proposalId The ID of the proposal to check.
     * @return Whether or not the proposal is confirmed by the minimum set of owners.
     */
    function isFullyConfirmed(uint256 proposalId) public view returns (bool) {
        uint256 count = 0;
        for (uint256 i = 0; i < owners.length(); i++) {
            if (proposals[proposalId].confirmations[owners.at(i)]) {
                count++;
            }
            if (count == required) {
                return true;
            }
        }
        return false;
    }

    /**
     * @notice Checks that a proposal is confirmed by an owner.
     * @param proposalId The ID of the proposal to check.
     * @param owner The address to check.
     * @return Whether or not the proposal is confirmed by the given owner.
     */
    function isConfirmedBy(uint256 proposalId, address owner) public view returns (bool) {
        return proposals[proposalId].confirmations[owner];
    }

    /**
     * @notice Checks that an address is a multisig owner.
     * @param owner The address to check.
     * @return Whether or not the address is a multisig owner.
     */
    function isOwner(address owner) public view returns (bool) {
        return owners.contains(owner);
    }

    /**
     * @notice Adds a new proposal to the proposals list.
     * @param destinations The addresses at which the proposal is directed to.
     * @param values The CELO valuse involved in the proposal if any.
     * @param payloads The payloads of the proposal.
     * @return proposalId Returns the ID of the proposal that gets generated.
     */
    function addProposal(
        address[] memory destinations,
        uint256[] memory values,
        bytes[] memory payloads
    ) internal notNullBatch(destinations) returns (uint256 proposalId) {
        proposalId = proposalCount;
        Proposal storage proposal = proposals[proposalId];

        proposal.destinations = destinations;
        proposal.values = values;
        proposal.payloads = payloads;

        proposalCount++;
        emit ProposalAdded(proposalId);
    }

    /**
     * @notice Schedules a proposal with a time lock.
     * @param proposalId The ID of the proposal to schedule.
     */
    function schedule(uint256 proposalId)
        internal
        notScheduled(proposalId)
        fullyConfirmed(proposalId)
    {
        proposals[proposalId].timestampExecutable = block.timestamp + delay;
    }

    /**
     * @notice Changes the value of the delay that must
     * elapse before a proposal can become executable.
     * @param newDelay The new delay value.
     */
    function _changeDelay(uint256 newDelay) internal {
        if (newDelay < minDelay) {
            revert InsufficientDelay(newDelay);
        }

        delay = newDelay;
        emit DelayChanged(delay, newDelay);
    }

    /**
     * @notice Changes the number of confirmations required to consider a proposal
     * fully confirmed.
     * @dev This method does not do any validation, see `changeRequirement`
     * for how it is used with the requirement validation modifier.
     * @param newRequired The new number of confirmations required.
     */
    function _changeRequirement(uint256 newRequired) internal {
        required = newRequired;
        emit RequirementChanged(newRequired);
    }

    /**
     * @notice Guard method for UUPS (Universal Upgradable Proxy Standard)
     * See: https://docs.openzeppelin.com/contracts/4.x/api/proxy#transparent-vs-uups
     * @dev This methods overrides the virtual one in UUPSUpgradeable and
     * adds the onlyWallet modifer.
     */
    // solhint-disable-next-line no-empty-blocks
    function _authorizeUpgrade(address) internal override onlyWallet {}
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


//SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "@openzeppelin/contracts/utils/Address.sol";

library ExternalCall {
    /**
     * @notice Used when destination is not a contract.
     * @param destination The invalid destination address.
     */
    error InvalidContractAddress(address destination);

    /**
     * @notice Used when an execution fails.
     */
    error ExecutionFailed();

    /**
     * @notice Executes external call.
     * @param destination The address to call.
     * @param value The CELO value to be sent.
     * @param data The data to be sent.
     * @return The call return value.
     */
    function execute(
        address destination,
        uint256 value,
        bytes memory data
    ) internal returns (bytes memory) {
        if (data.length > 0) {
            if (!Address.isContract(destination)) {
                revert InvalidContractAddress(destination);
            }
        }

        bool success;
        bytes memory returnData;
        // solhint-disable-next-line avoid-low-level-calls
        (success, returnData) = destination.call{value: value}(data);
        if (!success) {
            revert ExecutionFailed();
        }

        return returnData;
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
// OpenZeppelin Contracts v4.4.1 (proxy/utils/Initializable.sol)

pragma solidity ^0.8.0;

import "../../utils/Address.sol";

/**
 * @dev This is a base contract to aid in writing upgradeable contracts, or any kind of contract that will be deployed
 * behind a proxy. Since a proxied contract can't have a constructor, it's common to move constructor logic to an
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
        return !Address.isContract(address(this));
    }
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