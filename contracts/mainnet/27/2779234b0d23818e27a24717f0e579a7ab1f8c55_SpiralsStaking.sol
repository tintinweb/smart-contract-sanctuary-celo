// SPDX-License-Identifier: Apache-2.0
// https://docs.soliditylang.org/en/v0.8.10/style-guide.html
pragma solidity ^0.8.10;

import "./IAccounts.sol";
import "./ILockedGold.sol";
import "./IElection.sol";
import "./IRegistry.sol";
import "./IValidators.sol";

contract SpiralsStaking {
    address public validatorGroup;
    address public owner;
    uint256 public bufferPool;
    uint256 public totalPendingWithdrawal;
    IRegistry constant c_celoRegistry =
        IRegistry(0x000000000000000000000000000000000000ce10);

    struct StakerInfo {
        uint256 stakedValue;
        uint256 withdrawalValue;
        uint256 withdrawalTimestamp;
    }
    mapping(address => StakerInfo) stakers;

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

    function initialize(address _validatorGroup) public {
        validatorGroup = _validatorGroup;
        owner = msg.sender;
        require(getAccounts().createAccount(), "CREATE_ACCOUNT_FAILED");
    }

    receive() external payable {
        emit Deposit(msg.sender, msg.value, false);
    }

    /// @dev Modifier for checking whether function caller is `_owner`.
    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function!");
        _;
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

    /// @notice Main function for staking with Spirals protocol
    /// @dev
    function stake() external payable {
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
    /// Onus is on the protocol owners to activate to make sure CELO
    /// staked with protocol is staked on CELO L1.
    function activateForProtocol() external onlyOwner {
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

    /// @notice Withdraws CELO from any pending withdrawals that are available.
    /// Onus is on the protocol owners to withdraw CELO from LockedGold
    function withdrawForProtocol() external onlyOwner {
        (uint256[] memory values, uint256[] memory timestamps) = getLockedGold()
            .getPendingWithdrawals(address(this));

        // loop backwards so withdrawing at a single index doesn't shift indices
        uint256 withdrawnTotal;
        for (uint256 i = timestamps.length; i >= 0; i--) {
            if (block.timestamp >= timestamps[i]) {
                getLockedGold().withdraw(i);
                withdrawnTotal += values[i];
            }
        }
        emit ProtocolCeloWithdrawn(withdrawnTotal, block.timestamp);
    }

    /// @notice Convenience function for withdrawing the first
    /// pending withdrawal request from the protocol.
    function withdrawFirstRequestForProtocol() external onlyOwner {
        getLockedGold().withdraw(0);
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
    function setValidatorGroup(address _newValidatorGroup) external onlyOwner {
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