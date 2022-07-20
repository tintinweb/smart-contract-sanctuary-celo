// SPDX-License-Identifier: Apache-2.0
// https://docs.soliditylang.org/en/v0.8.10/style-guide.html
pragma solidity ^0.8.10;

import "./SpiralsStaking.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

/// @title SpiralsStakingV2
/// @author @douglasqian
/// @notice This is a 2nd iteration of SpiralsStaking that inherits some
/// basic OpenZeppelin upgradeable contracts to enhance security on the
/// core staking logic.
///
/// @dev We inherit "SpiralsStaking" first so that existing state variables
/// preserve their slot assignments. New state variables introduced on this
/// smart contract occupy slots after all inherited contract variables
/// are assigned.
///
contract SpiralsStakingV2 is
    SpiralsStaking,
    OwnableUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable
{
    uint256 public totalStaked;
    uint256 public numStakers;

    /// @notice Initializes the Spirals staking smart contract. Should only be
    /// called once (stored in state variable).
    function initialize(address _validatorGroup) public override initializer {
        __Ownable_init();
        __Pausable_init();
        __ReentrancyGuard_init();
        _setValidatorGroup(validatorGroup);
        if (!getAccounts().isAccount(address(this))) {
            // Ensures "initialize" is idempotent.
            require(getAccounts().createAccount(), "CREATE_ACCOUNT_FAILED");
        }
    }

    /// @notice Pauses the smart contract. This is useful if a critical
    /// issue or vulnerability is discovered that requires patching or if
    /// the contract
    function stop() external onlyOwner {
        _pause();
    }

    /// @notice Resumes the smart contract.
    function resume() external onlyOwner {
        _unpause();
    }

    /// @notice See "stake" in SpiralsStaking.sol
    /// @dev Same implementation as original with 2 new modifiers.
    function stake() external payable override nonReentrant whenNotPaused {
        require(msg.value > 0, "STAKING_ZERO");
        lock(msg.value);
        vote(msg.value);

        if (stakers[msg.sender].stakedValue == 0) {
            // msg.sender is a new staker
            numStakers++;
        }
        stakers[msg.sender].stakedValue += msg.value;
        totalStaked += msg.value;
        emit UserCeloStaked(msg.sender, validatorGroup, msg.value);
    }

    /// @notice See "unstake" in SpiralsStaking.sol
    /// @dev Same implementation as original with 2 new modifiers.
    function unstake(uint256 _value)
        public
        override
        nonReentrant
        whenNotPaused
    {
        require(
            stakers[msg.sender].stakedValue >= _value,
            "EXCEEDS_USER_STAKE"
        );
        uint256 activeVotes = getActiveVotes();
        (uint256 pendingVotes, ) = getPendingVotes();
        require(activeVotes + pendingVotes >= _value, "EXCEEDS_PROTOCOL_STAKE");
        // Can only support 1 outstanding unstake request at a time (without
        // rebuilding all of how Celo unstaking works)
        require(
            stakers[msg.sender].withdrawalValue == 0,
            "OUTSTANDING_PENDING_WITHDRAWAL"
        );

        if (activeVotes >= _value) {
            revokeActive(_value);
        } else {
            revokePending(_value);
        }
        unlock(_value);

        StakerInfo memory newStaker = stakers[msg.sender];
        newStaker.stakedValue -= _value;
        newStaker.withdrawalValue = _value;
        newStaker.withdrawalTimestamp =
            block.timestamp +
            getLockedGold().unlockingPeriod();

        totalPendingWithdrawal += _value;
        totalStaked -= _value;
        if (newStaker.stakedValue == 0) {
            // msg.sender unstaked all CELO
            numStakers--;
        }

        stakers[msg.sender] = newStaker;
        emit UserCeloUnstaked(msg.sender, validatorGroup, _value);
    }

    /// @notice See "withdraw" in SpiralsStaking.sol
    /// @dev Same implementation as original with 2 new modifiers.
    function withdraw() public override nonReentrant whenNotPaused {
        StakerInfo memory s = stakers[msg.sender];
        require(s.withdrawalValue > 0, "NO_PENDING_WITHDRAWALS");
        require(userCanWithdraw(msg.sender), "WITHDRAWAL_NOT_READY");
        payable(msg.sender).transfer(s.withdrawalValue); // should fail if protocol doesn't have enough
        emit UserCeloWithdrawn(msg.sender, s.withdrawalValue);

        totalPendingWithdrawal -= s.withdrawalValue;

        s.withdrawalValue = 0;
        s.withdrawalTimestamp = 0;
        stakers[msg.sender] = s;
    }

    /// @notice See "setValidatorGroup" in SpiralsStaking.sol
    /// @dev Same implementation as original with 2 new modifiers.
    function setValidatorGroup(address _newValidatorGroup)
        external
        override
        onlyOwner
        whenNotPaused
    {
        _setValidatorGroup(_newValidatorGroup);
    }

    /// @notice Helper function for updating this value;
    // function setStakingStats(uint256 _totalStaked, uint256 _numStakers)
    //     external
    //     onlyOwner
    //     whenPaused
    // {
    //     totalStaked = _totalStaked;
    //     numStakers = _numStakers;
    // }

    /// @notice Implementation of "setValidatorGroup"
    function _setValidatorGroup(address _newValidatorGroup)
        internal
        onlyOwner
        whenNotPaused
    {
        require(
            getValidators().isValidatorGroup(_newValidatorGroup),
            "NOT_VALIDATOR_GROUP"
        );
        require(
            getElection().getGroupEligibility(_newValidatorGroup),
            "NOT_ELIGIBLE_VALIDATOR_GROUP"
        );
        validatorGroup = _newValidatorGroup;
    }
}


// SPDX-License-Identifier: Apache-2.0
// https://docs.soliditylang.org/en/v0.8.10/style-guide.html
pragma solidity ^0.8.10;

import "./IAccounts.sol";
import "./ILockedGold.sol";
import "./IElection.sol";
import "./IRegistry.sol";
import "./IValidators.sol";

///
///                ▐▌               ▛
///                                 █
/// ▗▛▀▀▌  ▗▛▀▀▀▙  ▐▌  ▟▀▀▘▗▛▀▀▀▙   ▙  ▟▀▀▀▖
/// ▝▙▄    ▛    ▝▌ ▐▌  ▌   ▛    ▝▌  ▛  ▐▄▖▖
///    ▀▙  █    ▐▌ ▐▌  ▛   █    ▐▌  █    ▝▀▌
/// ▐▄▄▄▛  █▚▄▄▄▀  ▐▌  ▛   ▝▙▄▄▄▀▙  ▙  ▜▄▄▄▘
///        ▙
///        ▌
///
///
/// @title SpiralsStaking
/// @author @douglasqian
/// @notice This smart contract implements a simple staking protocol that
/// plugs into Celo's L1 staking. On a high-level, the contract allows callers
/// to stake with a designated validator group and unstake from it as well.
/// The lockup period is the same as what's on the L1.
///
/// Staking through this contract sends value directly to Celo's
/// LockedGold contract so there should never be a large amount of
/// value accrued in this contract's balance. From a security perspective
/// it also means that we are leveraging the testing & auditing done on
/// Celo's smart contracts to ensure funds are secured.
///
/// Callers who staked through this contract can only redeem the original
/// staking amount which means the rewards from staking are managed by the
/// contract.
///
/// @dev This contract simplifies the staking experience for Spirals users
/// because it pushes the responsibility of activation & withdrawal to
/// the contract admin. For activation, this means that it's up to us to
/// activate the pending votes after the next epoch passes. Every call to
/// "stake" resets the timer on behalf of this contract in Celo's Election
/// smart contract.
///
/// On the other side, users looking to unstake are able to after the
/// same lockup period on the L1. This means that Spirals bears the
/// responsibility of withdrawing on behalf of the protocol in a timely
/// manner to ensure there's enough liquidity. Otherwise, users eligible to
/// withdraw from Spirals will not be able to. We also address this by
/// allowing deposits into a buffer pool. In the long-run though, building
/// some automation around this would be ideal.
///
contract SpiralsStaking {
    /*
     * Struct Definitions
     */
    struct StakerInfo {
        uint256 stakedValue;
        uint256 withdrawalValue;
        uint256 withdrawalTimestamp;
    }

    /*
     * State Variables
     */

    address public validatorGroup;
    address private ownerDeprecated; // don't remove this, will change slot assignments
    uint256 public bufferPool;
    uint256 public totalPendingWithdrawal;
    IRegistry constant c_celoRegistry =
        IRegistry(0x000000000000000000000000000000000000ce10);

    // TODO: change to nested mapping if we want to support multiple validator groups
    mapping(address => StakerInfo) stakers;

    /*
     * Events
     */

    event Deposit(
        address indexed sender,
        uint256 indexed amount,
        bool isBuffer
    );
    event UserCeloStaked(
        address indexed _address,
        address indexed _validatorGroup,
        uint256 indexed amount
    );
    event ProtocolCeloActivated(
        address indexed _validatorGroup,
        uint256 indexed amount
    );
    event UserCeloUnstaked(
        address indexed _address,
        address indexed _validatorGroup,
        uint256 indexed amount
    );
    event UserCeloWithdrawn(address indexed _address, uint256 indexed amount);
    event ProtocolCeloWithdrawn(
        uint256 indexed totalAmount,
        uint256 indexed timestamp
    );

    function initialize(address _validatorGroup) public virtual {
        validatorGroup = _validatorGroup;
        require(getAccounts().createAccount(), "CREATE_ACCOUNT_FAILED");
    }

    receive() external payable {
        emit Deposit(msg.sender, msg.value, false);
    }

    /// @notice Allows deposits into the protocol's buffer pool to facilitate
    /// unstaking.
    function depositBP() public payable {
        bufferPool += msg.value;
        emit Deposit(msg.sender, msg.value, true);
    }

    /*
     * STAKING
     */

    /// @notice Main function for staking with Spirals protocol.
    /// @dev Since contract call is atomic, staked Celo should never
    /// end up in this contract (goes straight to LockedGold).
    function stake() external payable virtual {
        require(msg.value > 0, "STAKING_ZERO");
        lock(msg.value);
        vote(msg.value);

        stakers[msg.sender].stakedValue += msg.value;
        emit UserCeloStaked(msg.sender, validatorGroup, msg.value);
    }

    /// @dev Helper function for locking CELO
    function lock(uint256 _value) internal {
        require(_value > 0, "LOCKING_ZERO");
        getLockedGold().lock{value: _value}();
    }

    /// @dev Helper function for casting votes with a given validator group
    function vote(uint256 _value) internal {
        (address lesser, address greater, ) = getLesserGreater();

        require(
            !(lesser == address(0) && greater == address(0)),
            "INVALID_LESSER_GREATER"
        ); // Can't both be null address
        require(
            getElection().vote(validatorGroup, _value, lesser, greater),
            "VOTE_FAILED"
        );
    }

    /// @dev Helper function for getting the 2 validator groups that
    /// our target validator group is sandwiched between.
    function getLesserGreater()
        internal
        view
        returns (
            address,
            address,
            uint256
        )
    {
        (address[] memory validatorGroups, ) = getElection()
            .getTotalVotesForEligibleValidatorGroups(); // sorted by votes desc

        address lesser = address(0);
        address greater = address(0);
        uint256 index = 0;

        for (uint256 i = 0; i < validatorGroups.length; i++) {
            if (validatorGroup == validatorGroups[i]) {
                if (i > 0) {
                    greater = validatorGroups[i - 1];
                }
                if (i < validatorGroups.length - 1) {
                    lesser = validatorGroups[i + 1];
                }
                index = i;
                break;
            }
        }
        return (lesser, greater, index);
    }

    /*
     * UNSTAKING
     */

    /// @notice Main function for unstaking from Spirals protocol
    /// @dev A particular user calling "unstake" adds a pending withdrawal
    /// for Spirals in the Celo smart contracts. After calling this function,
    /// a user officially unstakes but still needs to "withdraw" after
    /// the unlocking period is over.
    function unstake(uint256 _value) public virtual {
        require(
            stakers[msg.sender].stakedValue >= _value,
            "EXCEEDS_USER_STAKE"
        );
        uint256 activeVotes = getActiveVotes();
        (uint256 pendingVotes, ) = getPendingVotes();
        require(activeVotes + pendingVotes >= _value, "EXCEEDS_PROTOCOL_STAKE");
        // Can only support 1 outstanding unstake request at a time (without
        // rebuilding all of how Celo unstaking works)
        require(
            stakers[msg.sender].withdrawalValue == 0,
            "OUTSTANDING_PENDING_WITHDRAWAL"
        );

        if (activeVotes >= _value) {
            revokeActive(_value);
        } else {
            revokePending(_value);
        }
        unlock(_value);

        StakerInfo memory newStaker = stakers[msg.sender];
        newStaker.stakedValue -= _value;
        newStaker.withdrawalValue = _value;
        newStaker.withdrawalTimestamp =
            block.timestamp +
            getLockedGold().unlockingPeriod();

        totalPendingWithdrawal += _value;

        stakers[msg.sender] = newStaker;
        emit UserCeloUnstaked(msg.sender, validatorGroup, _value);
    }

    /// @notice Helper function for revoking active votes CELO
    function revokeActive(uint256 _value) internal {
        (address lesser, address greater, uint256 index) = getLesserGreater();
        require(
            getElection().revokeActive(
                validatorGroup,
                _value,
                lesser,
                greater,
                index
            )
        );
    }

    /// @notice Helper function for revoking pending votes CELO
    function revokePending(uint256 _value) internal {
        (address lesser, address greater, uint256 index) = getLesserGreater();
        require(
            getElection().revokePending(
                validatorGroup,
                _value,
                lesser,
                greater,
                index
            )
        );
    }

    /// @notice Helper function for unlocking CELO
    function unlock(uint256 _value) internal {
        getLockedGold().unlock(_value);
    }

    /// @notice Allow user to withdraw their stake back to wallet.
    /// @dev Withdraws from this contracts balance directly.
    function withdraw() public virtual {
        StakerInfo memory s = stakers[msg.sender];
        require(s.withdrawalValue > 0, "NO_PENDING_WITHDRAWALS");
        require(userCanWithdraw(msg.sender), "WITHDRAWAL_NOT_READY");
        payable(msg.sender).transfer(s.withdrawalValue); // should fail if protocol doesn't have enough
        emit UserCeloWithdrawn(msg.sender, s.withdrawalValue);

        totalPendingWithdrawal -= s.withdrawalValue;

        s.withdrawalValue = 0;
        s.withdrawalTimestamp = 0;
        stakers[msg.sender] = s;
    }

    /// @notice Helper function for checking whether protocol can support
    /// a user who wants to withdraw.
    function userCanWithdraw(address _address) public view returns (bool) {
        StakerInfo memory s = stakers[_address];
        return
            address(this).balance >= s.withdrawalValue &&
            s.withdrawalTimestamp <= block.timestamp;
    }

    /*
     * ADMIN
     */

    /// @notice Activates pending votes (if ready) with a given validator group.
    /// @dev  Onus is on the protocol owners to activate to make sure CELO
    /// staked with protocol is staked on CELO L1.
    function activateForProtocol() external {
        IElection c_election = getElection();
        require(
            c_election.hasActivatablePendingVotes(
                address(this),
                validatorGroup
            ),
            "NOT_READY_TO_ACTIVATE"
        );
        uint256 pendingVotes = getElection().getPendingVotesForGroupByAccount(
            validatorGroup,
            address(this)
        );
        require(c_election.activate(validatorGroup), "ACTIVATE_FAILED");

        // all pending -> active for this group
        emit ProtocolCeloActivated(validatorGroup, pendingVotes);
    }

    /// @notice Attemps to withdraw CELO for all pending withdrawals that are
    /// available for the proxy contract address.
    /// @dev Onus is on the protocol owners to withdraw CELO from LockedGold
    function withdrawForProtocol() external {
        (uint256[] memory values, uint256[] memory timestamps) = getLockedGold()
            .getPendingWithdrawals(address(this));

        // loop backwards so withdrawing at a single index doesn't shift indices
        uint256 withdrawnTotal;
        for (uint256 i = timestamps.length; i > 0; i--) {
            if (block.timestamp >= timestamps[i - 1]) {
                getLockedGold().withdraw(i - 1);
                withdrawnTotal += values[i - 1];
            }
        }
        if (withdrawnTotal > 0) {
            emit ProtocolCeloWithdrawn(withdrawnTotal, block.timestamp);
        }
    }

    /*
     * OTHER
     */

    /// @notice Returns all details relevant to an account staking with Spirals.
    function getAccount(address _address)
        public
        view
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        StakerInfo memory s = stakers[_address];
        return (s.stakedValue, s.withdrawalValue, s.withdrawalTimestamp);
    }

    /// @notice For updating with validator group we stake with. Performs
    /// some simple checks to make sure address given is an eligible
    /// validator group (limited to 1 for now).
    function setValidatorGroup(address _newValidatorGroup) external virtual {
        require(
            getValidators().isValidatorGroup(_newValidatorGroup),
            "NOT_VALIDATOR_GROUP"
        );
        require(
            getElection().getGroupEligibility(_newValidatorGroup),
            "NOT_ELIGIBLE_VALIDATOR_GROUP"
        );
        validatorGroup = _newValidatorGroup;
    }

    /// @notice Get pending votes for this smart contract.
    function getPendingVotes() public view returns (uint256, bool) {
        return (
            getElection().getPendingVotesForGroupByAccount(
                validatorGroup,
                address(this)
            ),
            getElection().hasActivatablePendingVotes(
                validatorGroup,
                address(this)
            )
        );
    }

    /// @notice Get active votes (staked + rewards) for this smart contract.
    function getActiveVotes() public view returns (uint256) {
        return
            getElection().getActiveVotesForGroupByAccount(
                validatorGroup,
                address(this)
            );
    }

    /*
     * CELO SMART CONTRACT HELPERS
     */

    /// @dev Returns a Accounts.sol interface for interacting with the smart contract.
    function getAccounts() internal view returns (IAccounts) {
        address accountsAddr = c_celoRegistry.getAddressForStringOrDie(
            "Accounts"
        );
        return IAccounts(accountsAddr);
    }

    /// @dev Returns an Election.sol interface for interacting with the smart contract.
    function getElection() internal view returns (IElection) {
        address electionAddr = c_celoRegistry.getAddressForStringOrDie(
            "Election"
        );
        return IElection(electionAddr);
    }

    /// @dev Returns a LockedGold.sol interface for interacting with the smart contract.
    function getLockedGold() internal view returns (ILockedGold) {
        address lockedGoldAddr = c_celoRegistry.getAddressForStringOrDie(
            "LockedGold"
        );
        return ILockedGold(lockedGoldAddr);
    }

    /// @dev Returns a Validators.sol interface for interacting with the smart contract.
    function getValidators() internal view returns (IValidators) {
        address validatorsAddr = c_celoRegistry.getAddressForStringOrDie(
            "Validators"
        );
        return IValidators(validatorsAddr);
    }
}


pragma solidity >=0.8.0;

interface IValidators {
    function registerValidator(
        bytes calldata,
        bytes calldata,
        bytes calldata
    ) external returns (bool);

    function deregisterValidator(uint256) external returns (bool);

    function affiliate(address) external returns (bool);

    function deaffiliate() external returns (bool);

    function updateBlsPublicKey(bytes calldata, bytes calldata)
        external
        returns (bool);

    function registerValidatorGroup(uint256) external returns (bool);

    function deregisterValidatorGroup(uint256) external returns (bool);

    function addMember(address) external returns (bool);

    function addFirstMember(
        address,
        address,
        address
    ) external returns (bool);

    function removeMember(address) external returns (bool);

    function reorderMember(
        address,
        address,
        address
    ) external returns (bool);

    function updateCommission() external;

    function setNextCommissionUpdate(uint256) external;

    function resetSlashingMultiplier() external;

    // only owner
    function setCommissionUpdateDelay(uint256) external;

    function setMaxGroupSize(uint256) external returns (bool);

    function setMembershipHistoryLength(uint256) external returns (bool);

    function setValidatorScoreParameters(uint256, uint256)
        external
        returns (bool);

    function setGroupLockedGoldRequirements(uint256, uint256)
        external
        returns (bool);

    function setValidatorLockedGoldRequirements(uint256, uint256)
        external
        returns (bool);

    function setSlashingMultiplierResetPeriod(uint256) external;

    // view functions
    function getMaxGroupSize() external view returns (uint256);

    function getCommissionUpdateDelay() external view returns (uint256);

    function getValidatorScoreParameters()
        external
        view
        returns (uint256, uint256);

    function getMembershipHistory(address)
        external
        view
        returns (
            uint256[] memory,
            address[] memory,
            uint256,
            uint256
        );

    function calculateEpochScore(uint256) external view returns (uint256);

    function calculateGroupEpochScore(uint256[] calldata)
        external
        view
        returns (uint256);

    function getAccountLockedGoldRequirement(address)
        external
        view
        returns (uint256);

    function meetsAccountLockedGoldRequirements(address)
        external
        view
        returns (bool);

    function getValidatorBlsPublicKeyFromSigner(address)
        external
        view
        returns (bytes memory);

    function getValidator(address account)
        external
        view
        returns (
            bytes memory,
            bytes memory,
            address,
            uint256,
            address
        );

    function getValidatorGroup(address)
        external
        view
        returns (
            address[] memory,
            uint256,
            uint256,
            uint256,
            uint256[] memory,
            uint256,
            uint256
        );

    function getGroupNumMembers(address) external view returns (uint256);

    function getTopGroupValidators(address, uint256)
        external
        view
        returns (address[] memory);

    function getGroupsNumMembers(address[] calldata accounts)
        external
        view
        returns (uint256[] memory);

    function getNumRegisteredValidators() external view returns (uint256);

    function groupMembershipInEpoch(
        address,
        uint256,
        uint256
    ) external view returns (address);

    // only registered contract
    function updateEcdsaPublicKey(
        address,
        address,
        bytes calldata
    ) external returns (bool);

    function updatePublicKeys(
        address,
        address,
        bytes calldata,
        bytes calldata,
        bytes calldata
    ) external returns (bool);

    function getValidatorLockedGoldRequirements()
        external
        view
        returns (uint256, uint256);

    function getGroupLockedGoldRequirements()
        external
        view
        returns (uint256, uint256);

    function getRegisteredValidators() external view returns (address[] memory);

    function getRegisteredValidatorSigners()
        external
        view
        returns (address[] memory);

    function getRegisteredValidatorGroups()
        external
        view
        returns (address[] memory);

    function isValidatorGroup(address) external view returns (bool);

    function isValidator(address) external view returns (bool);

    function getValidatorGroupSlashingMultiplier(address)
        external
        view
        returns (uint256);

    function getMembershipInLastEpoch(address) external view returns (address);

    function getMembershipInLastEpochFromSigner(address)
        external
        view
        returns (address);

    // only VM
    function updateValidatorScoreFromSigner(address, uint256) external;

    function distributeEpochPaymentsFromSigner(address, uint256)
        external
        returns (uint256);

    // only slasher
    function forceDeaffiliateIfValidator(address) external;

    function halveSlashingMultiplier(address) external;
}


// SPDX-License-Identifier: Apache-2.0
// https://docs.soliditylang.org/en/v0.8.10/style-guide.html
pragma solidity >=0.8.0;

interface IRegistry {
    function setAddressFor(string calldata, address) external;

    function getAddressForOrDie(bytes32) external view returns (address);

    function getAddressFor(bytes32) external view returns (address);

    function getAddressForStringOrDie(string calldata identifier)
        external
        view
        returns (address);

    function getAddressForString(string calldata identifier)
        external
        view
        returns (address);

    function isOneOf(bytes32[] calldata, address) external view returns (bool);
}


// SPDX-License-Identifier: Apache-2.0
// https://github.com/celo-org/celo-monorepo/tree/master/packages/protocol/contracts/governance/interfaces/ILockedGold.sol
pragma solidity >=0.5.13;

interface ILockedGold {
    function incrementNonvotingAccountBalance(address, uint256) external;

    function decrementNonvotingAccountBalance(address, uint256) external;

    function getAccountTotalLockedGold(address) external view returns (uint256);

    function getAccountNonvotingLockedGold(address)
        external
        view
        returns (uint256);

    function unlockingPeriod() external view returns (uint256);

    function getTotalLockedGold() external view returns (uint256);

    function getPendingWithdrawal(address, uint256)
        external
        view
        returns (uint256, uint256);

    function getPendingWithdrawals(address)
        external
        view
        returns (uint256[] memory, uint256[] memory);

    function getTotalPendingWithdrawals(address)
        external
        view
        returns (uint256);

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


// SPDX-License-Identifier: Apache-2.0
// https://github.com/celo-org/celo-monorepo/tree/master/packages/protocol/contracts/governance/interfaces/IElection.sol
pragma solidity >=0.5.13;

interface IElection {
    function electValidatorSigners() external view returns (address[] memory);

    function electNValidatorSigners(uint256, uint256)
        external
        view
        returns (address[] memory);

    function vote(
        address,
        uint256,
        address,
        address
    ) external returns (bool);

    function activate(address) external returns (bool);

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
    function getEpochNumber() external view returns (uint256);

    function getElectableValidators() external view returns (uint256, uint256);

    function getElectabilityThreshold() external view returns (uint256);

    function getNumVotesReceivable(address) external view returns (uint256);

    function getTotalVotes() external view returns (uint256);

    function getActiveVotes() external view returns (uint256);

    function getTotalVotesByAccount(address) external view returns (uint256);

    function getPendingVotesForGroupByAccount(address, address)
        external
        view
        returns (uint256);

    function getActiveVotesForGroupByAccount(address, address)
        external
        view
        returns (uint256);

    function getTotalVotesForGroupByAccount(address, address)
        external
        view
        returns (uint256);

    function getActiveVoteUnitsForGroupByAccount(address, address)
        external
        view
        returns (uint256);

    function getTotalVotesForGroup(address) external view returns (uint256);

    function getActiveVotesForGroup(address) external view returns (uint256);

    function getPendingVotesForGroup(address) external view returns (uint256);

    function getGroupEligibility(address) external view returns (bool);

    function getGroupEpochRewards(
        address,
        uint256,
        uint256[] calldata
    ) external view returns (uint256);

    function getGroupsVotedForByAccount(address)
        external
        view
        returns (address[] memory);

    function getEligibleValidatorGroups()
        external
        view
        returns (address[] memory);

    function getTotalVotesForEligibleValidatorGroups()
        external
        view
        returns (address[] memory, uint256[] memory);

    function getCurrentValidatorSigners()
        external
        view
        returns (address[] memory);

    function canReceiveVotes(address, uint256) external view returns (bool);

    function hasActivatablePendingVotes(address, address)
        external
        view
        returns (bool);

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

    event ElectableValidatorsSet(uint256 min, uint256 max);
    event MaxNumGroupsVotedForSet(uint256 maxNumGroupsVotedFor);
    event ElectabilityThresholdSet(uint256 electabilityThreshold);
    event ValidatorGroupMarkedEligible(address indexed group);
    event ValidatorGroupMarkedIneligible(address indexed group);
    event ValidatorGroupVoteCast(
        address indexed account,
        address indexed group,
        uint256 value
    );
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
}


// SPDX-License-Identifier: Apache-2.0
// https://github.com/celo-org/celo-monorepo/tree/master/packages/protocol/contracts/governance/interfaces/ILockedGold.sol
pragma solidity >=0.5.13;

interface IAccounts {
    function isAccount(address) external view returns (bool);

    function voteSignerToAccount(address) external view returns (address);

    function validatorSignerToAccount(address) external view returns (address);

    function attestationSignerToAccount(address)
        external
        view
        returns (address);

    function signerToAccount(address) external view returns (address);

    function getAttestationSigner(address) external view returns (address);

    function getValidatorSigner(address) external view returns (address);

    function getVoteSigner(address) external view returns (address);

    function hasAuthorizedVoteSigner(address) external view returns (bool);

    function hasAuthorizedValidatorSigner(address) external view returns (bool);

    function hasAuthorizedAttestationSigner(address)
        external
        view
        returns (bool);

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

    function setPaymentDelegation(address, uint256) external;

    function getPaymentDelegation(address)
        external
        view
        returns (address, uint256);
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
// OpenZeppelin Contracts (last updated v4.7.0) (utils/Address.sol)

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
                /// @solidity memory-safe-assembly
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
// OpenZeppelin Contracts v4.4.1 (security/ReentrancyGuard.sol)

pragma solidity ^0.8.0;
import "../proxy/utils/Initializable.sol";

/**
 * @dev Contract module that helps prevent reentrant calls to a function.
 *
 * Inheriting from `ReentrancyGuard` will make the {nonReentrant} modifier
 * available, which can be applied to functions to make sure there are no nested
 * (reentrant) calls to them.
 *
 * Note that because there is a single `nonReentrant` guard, functions marked as
 * `nonReentrant` may not call one another. This can be worked around by making
 * those functions `private`, and then adding `external` `nonReentrant` entry
 * points to them.
 *
 * TIP: If you would like to learn more about reentrancy and alternative ways
 * to protect against it, check out our blog post
 * https://blog.openzeppelin.com/reentrancy-after-istanbul/[Reentrancy After Istanbul].
 */
abstract contract ReentrancyGuardUpgradeable is Initializable {
    // Booleans are more expensive than uint256 or any type that takes up a full
    // word because each write operation emits an extra SLOAD to first read the
    // slot's contents, replace the bits taken up by the boolean, and then write
    // back. This is the compiler's defense against contract upgrades and
    // pointer aliasing, and it cannot be disabled.

    // The values being non-zero value makes deployment a bit more expensive,
    // but in exchange the refund on every call to nonReentrant will be lower in
    // amount. Since refunds are capped to a percentage of the total
    // transaction's gas, it is best to keep them low in cases like this one, to
    // increase the likelihood of the full refund coming into effect.
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;

    uint256 private _status;

    function __ReentrancyGuard_init() internal onlyInitializing {
        __ReentrancyGuard_init_unchained();
    }

    function __ReentrancyGuard_init_unchained() internal onlyInitializing {
        _status = _NOT_ENTERED;
    }

    /**
     * @dev Prevents a contract from calling itself, directly or indirectly.
     * Calling a `nonReentrant` function from another `nonReentrant`
     * function is not supported. It is possible to prevent this from happening
     * by making the `nonReentrant` function external, and making it call a
     * `private` function that does the actual work.
     */
    modifier nonReentrant() {
        // On the first call to nonReentrant, _notEntered will be true
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");

        // Any calls to nonReentrant after this point will fail
        _status = _ENTERED;

        _;

        // By storing the original value once again, a refund is triggered (see
        // https://eips.ethereum.org/EIPS/eip-2200)
        _status = _NOT_ENTERED;
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[49] private __gap;
}


// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v4.7.0) (security/Pausable.sol)

pragma solidity ^0.8.0;

import "../utils/ContextUpgradeable.sol";
import "../proxy/utils/Initializable.sol";

/**
 * @dev Contract module which allows children to implement an emergency stop
 * mechanism that can be triggered by an authorized account.
 *
 * This module is used through inheritance. It will make available the
 * modifiers `whenNotPaused` and `whenPaused`, which can be applied to
 * the functions of your contract. Note that they will not be pausable by
 * simply including this module, only once the modifiers are put in place.
 */
abstract contract PausableUpgradeable is Initializable, ContextUpgradeable {
    /**
     * @dev Emitted when the pause is triggered by `account`.
     */
    event Paused(address account);

    /**
     * @dev Emitted when the pause is lifted by `account`.
     */
    event Unpaused(address account);

    bool private _paused;

    /**
     * @dev Initializes the contract in unpaused state.
     */
    function __Pausable_init() internal onlyInitializing {
        __Pausable_init_unchained();
    }

    function __Pausable_init_unchained() internal onlyInitializing {
        _paused = false;
    }

    /**
     * @dev Modifier to make a function callable only when the contract is not paused.
     *
     * Requirements:
     *
     * - The contract must not be paused.
     */
    modifier whenNotPaused() {
        _requireNotPaused();
        _;
    }

    /**
     * @dev Modifier to make a function callable only when the contract is paused.
     *
     * Requirements:
     *
     * - The contract must be paused.
     */
    modifier whenPaused() {
        _requirePaused();
        _;
    }

    /**
     * @dev Returns true if the contract is paused, and false otherwise.
     */
    function paused() public view virtual returns (bool) {
        return _paused;
    }

    /**
     * @dev Throws if the contract is paused.
     */
    function _requireNotPaused() internal view virtual {
        require(!paused(), "Pausable: paused");
    }

    /**
     * @dev Throws if the contract is not paused.
     */
    function _requirePaused() internal view virtual {
        require(paused(), "Pausable: not paused");
    }

    /**
     * @dev Triggers stopped state.
     *
     * Requirements:
     *
     * - The contract must not be paused.
     */
    function _pause() internal virtual whenNotPaused {
        _paused = true;
        emit Paused(_msgSender());
    }

    /**
     * @dev Returns to normal state.
     *
     * Requirements:
     *
     * - The contract must be paused.
     */
    function _unpause() internal virtual whenPaused {
        _paused = false;
        emit Unpaused(_msgSender());
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[49] private __gap;
}


// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v4.7.0) (proxy/utils/Initializable.sol)

pragma solidity ^0.8.2;

import "../../utils/AddressUpgradeable.sol";

/**
 * @dev This is a base contract to aid in writing upgradeable contracts, or any kind of contract that will be deployed
 * behind a proxy. Since proxied contracts do not make use of a constructor, it's common to move constructor logic to an
 * external initializer function, usually called `initialize`. It then becomes necessary to protect this initializer
 * function so it can only be called once. The {initializer} modifier provided by this contract will have this effect.
 *
 * The initialization functions use a version number. Once a version number is used, it is consumed and cannot be
 * reused. This mechanism prevents re-execution of each "step" but allows the creation of new initialization steps in
 * case an upgrade adds a module that needs to be initialized.
 *
 * For example:
 *
 * [.hljs-theme-light.nopadding]
 * ```
 * contract MyToken is ERC20Upgradeable {
 *     function initialize() initializer public {
 *         __ERC20_init("MyToken", "MTK");
 *     }
 * }
 * contract MyTokenV2 is MyToken, ERC20PermitUpgradeable {
 *     function initializeV2() reinitializer(2) public {
 *         __ERC20Permit_init("MyToken");
 *     }
 * }
 * ```
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
 * contract, which may impact the proxy. To prevent the implementation contract from being used, you should invoke
 * the {_disableInitializers} function in the constructor to automatically lock it when it is deployed:
 *
 * [.hljs-theme-light.nopadding]
 * ```
 * /// @custom:oz-upgrades-unsafe-allow constructor
 * constructor() {
 *     _disableInitializers();
 * }
 * ```
 * ====
 */
abstract contract Initializable {
    /**
     * @dev Indicates that the contract has been initialized.
     * @custom:oz-retyped-from bool
     */
    uint8 private _initialized;

    /**
     * @dev Indicates that the contract is in the process of being initialized.
     */
    bool private _initializing;

    /**
     * @dev Triggered when the contract has been initialized or reinitialized.
     */
    event Initialized(uint8 version);

    /**
     * @dev A modifier that defines a protected initializer function that can be invoked at most once. In its scope,
     * `onlyInitializing` functions can be used to initialize parent contracts. Equivalent to `reinitializer(1)`.
     */
    modifier initializer() {
        bool isTopLevelCall = !_initializing;
        require(
            (isTopLevelCall && _initialized < 1) || (!AddressUpgradeable.isContract(address(this)) && _initialized == 1),
            "Initializable: contract is already initialized"
        );
        _initialized = 1;
        if (isTopLevelCall) {
            _initializing = true;
        }
        _;
        if (isTopLevelCall) {
            _initializing = false;
            emit Initialized(1);
        }
    }

    /**
     * @dev A modifier that defines a protected reinitializer function that can be invoked at most once, and only if the
     * contract hasn't been initialized to a greater version before. In its scope, `onlyInitializing` functions can be
     * used to initialize parent contracts.
     *
     * `initializer` is equivalent to `reinitializer(1)`, so a reinitializer may be used after the original
     * initialization step. This is essential to configure modules that are added through upgrades and that require
     * initialization.
     *
     * Note that versions can jump in increments greater than 1; this implies that if multiple reinitializers coexist in
     * a contract, executing them in the right order is up to the developer or operator.
     */
    modifier reinitializer(uint8 version) {
        require(!_initializing && _initialized < version, "Initializable: contract is already initialized");
        _initialized = version;
        _initializing = true;
        _;
        _initializing = false;
        emit Initialized(version);
    }

    /**
     * @dev Modifier to protect an initialization function so that it can only be invoked by functions with the
     * {initializer} and {reinitializer} modifiers, directly or indirectly.
     */
    modifier onlyInitializing() {
        require(_initializing, "Initializable: contract is not initializing");
        _;
    }

    /**
     * @dev Locks the contract, preventing any future reinitialization. This cannot be part of an initializer call.
     * Calling this in the constructor of a contract will prevent that contract from being initialized or reinitialized
     * to any version. It is recommended to use this to lock implementation contracts that are designed to be called
     * through proxies.
     */
    function _disableInitializers() internal virtual {
        require(!_initializing, "Initializable: contract is initializing");
        if (_initialized < type(uint8).max) {
            _initialized = type(uint8).max;
            emit Initialized(type(uint8).max);
        }
    }
}


// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v4.7.0) (access/Ownable.sol)

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
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        _checkOwner();
        _;
    }

    /**
     * @dev Returns the address of the current owner.
     */
    function owner() public view virtual returns (address) {
        return _owner;
    }

    /**
     * @dev Throws if the sender is not the owner.
     */
    function _checkOwner() internal view virtual {
        require(owner() == _msgSender(), "Ownable: caller is not the owner");
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