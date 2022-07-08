// SPDX-License-Identifier: Apache-2.0
// https://docs.soliditylang.org/en/v0.8.10/style-guide.html
pragma solidity ^0.8.10;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "./IAccounts.sol";
import "./ILockedGold.sol";
import "./IElection.sol";
import "./IRegistry.sol";
import "./IValidators.sol";

contract SpiralsStaking {
    using SafeMath for uint256;

    address public validatorGroup;
    address public owner;
    uint256 public totalStaked;
    IRegistry constant c_celoRegistry =
        IRegistry(0x000000000000000000000000000000000000ce10);

    mapping(address => uint256) stakeByAccount;

    event VotesCast(
        address indexed _address,
        address indexed _validatorGroup,
        uint256 indexed amount
    );
    event VotesActivated(
        address indexed _validatorGroup,
        uint256 indexed amount
    );
    event Unstake(
        address indexed _address,
        address indexed _validatorGroup,
        uint256 indexed amount
    );

    constructor(address _validatorGroup) {
        validatorGroup = _validatorGroup;
        owner = msg.sender;
        require(getAccounts().createAccount(), "CREATE_ACCOUNT");
    }

    /// @dev Modifier for checking whether function caller is `_owner`.
    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function!");
        _;
    }

    /*
     * STAKING
     */

    /// @notice Main function for staking with Spirals protocol
    /// @dev
    function stake() external payable {
        require(msg.value != 0, "NO_VALUE_STAKED");
        lock(msg.value);
        vote(msg.value);

        stakeByAccount[msg.sender] = stakeByAccount[msg.sender].add(msg.value);
        totalStaked = totalStaked.add(msg.value);

        // all pending -> active for this group
        emit VotesCast(msg.sender, validatorGroup, msg.value);
    }

    /// @dev Helper function for locking CELO
    function lock(uint256 _value) internal {
        getLockedGold().lock{value: _value}();
    }

    /// @dev Helper function for casting votes with a given validator group
    function vote(uint256 _value) internal {
        (address lesser, address greater) = getLesserGreater();

        require(
            !(lesser == address(0) && greater == address(0)),
            "NO_LESSER_GREATER"
        ); // Can't both be null address
        require(
            getElection().vote(validatorGroup, _value, lesser, greater),
            "VOTE_FAILED"
        );
    }

    /// @dev Helper function for getting the 2 validator groups that
    /// our target validator group is sandwiched between.
    function getLesserGreater() internal view returns (address, address) {
        (address[] memory validatorGroups, ) = getElection()
            .getTotalVotesForEligibleValidatorGroups(); // sorted by votes desc

        address lesser = address(0);
        address greater = address(0);

        for (uint256 i = 0; i < validatorGroups.length; i++) {
            if (validatorGroup == validatorGroups[i]) {
                if (i > 0) {
                    greater = validatorGroups[i - 1];
                }
                if (i < validatorGroups.length - 1) {
                    lesser = validatorGroups[i + 1];
                }
                break;
            }
        }
        return (lesser, greater);
    }

    /// @dev Activates pending votes (if ready) with a given validator group.
    function activate() external onlyOwner {
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
        emit VotesActivated(validatorGroup, pendingVotes);
    }

    /*
     * UNSTAKING
     */

    // function unstake() public {}

    // function revoke() public {}

    // function unlock() public {}

    // function withdraw() public {}

    /*
     * OTHER
     */

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
            "NOT_ELIGIBLE_VG"
        );
        validatorGroup = _newValidatorGroup;
    }

    /// @notice Get active votes (staked + rewards) for this smart contract.
    function getRewards() public view returns (uint256) {
        uint256 activeVotes = getActiveVotes();
        (uint256 pendingVotes, ) = getPendingVotes();

        require(
            activeVotes.add(pendingVotes) >= totalStaked,
            "NEGATIVE_REWARDS"
        );

        return activeVotes.add(pendingVotes).sub(totalStaked);
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

    /// @notice Returns the amount a certain address is currently staking
    /// with Spirals.
    function getStakeForAccount(address _address)
        public
        view
        returns (uint256)
    {
        return stakeByAccount[_address];
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

    function getTotalLockedGold() external view returns (uint256);

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
// OpenZeppelin Contracts (last updated v4.6.0) (utils/math/SafeMath.sol)

pragma solidity ^0.8.0;

// CAUTION
// This version of SafeMath should only be used with Solidity 0.8 or later,
// because it relies on the compiler's built in overflow checks.

/**
 * @dev Wrappers over Solidity's arithmetic operations.
 *
 * NOTE: `SafeMath` is generally not needed starting with Solidity 0.8, since the compiler
 * now has built in overflow checking.
 */
library SafeMath {
    /**
     * @dev Returns the addition of two unsigned integers, with an overflow flag.
     *
     * _Available since v3.4._
     */
    function tryAdd(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        unchecked {
            uint256 c = a + b;
            if (c < a) return (false, 0);
            return (true, c);
        }
    }

    /**
     * @dev Returns the subtraction of two unsigned integers, with an overflow flag.
     *
     * _Available since v3.4._
     */
    function trySub(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        unchecked {
            if (b > a) return (false, 0);
            return (true, a - b);
        }
    }

    /**
     * @dev Returns the multiplication of two unsigned integers, with an overflow flag.
     *
     * _Available since v3.4._
     */
    function tryMul(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        unchecked {
            // Gas optimization: this is cheaper than requiring 'a' not being zero, but the
            // benefit is lost if 'b' is also tested.
            // See: https://github.com/OpenZeppelin/openzeppelin-contracts/pull/522
            if (a == 0) return (true, 0);
            uint256 c = a * b;
            if (c / a != b) return (false, 0);
            return (true, c);
        }
    }

    /**
     * @dev Returns the division of two unsigned integers, with a division by zero flag.
     *
     * _Available since v3.4._
     */
    function tryDiv(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        unchecked {
            if (b == 0) return (false, 0);
            return (true, a / b);
        }
    }

    /**
     * @dev Returns the remainder of dividing two unsigned integers, with a division by zero flag.
     *
     * _Available since v3.4._
     */
    function tryMod(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        unchecked {
            if (b == 0) return (false, 0);
            return (true, a % b);
        }
    }

    /**
     * @dev Returns the addition of two unsigned integers, reverting on
     * overflow.
     *
     * Counterpart to Solidity's `+` operator.
     *
     * Requirements:
     *
     * - Addition cannot overflow.
     */
    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        return a + b;
    }

    /**
     * @dev Returns the subtraction of two unsigned integers, reverting on
     * overflow (when the result is negative).
     *
     * Counterpart to Solidity's `-` operator.
     *
     * Requirements:
     *
     * - Subtraction cannot overflow.
     */
    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        return a - b;
    }

    /**
     * @dev Returns the multiplication of two unsigned integers, reverting on
     * overflow.
     *
     * Counterpart to Solidity's `*` operator.
     *
     * Requirements:
     *
     * - Multiplication cannot overflow.
     */
    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        return a * b;
    }

    /**
     * @dev Returns the integer division of two unsigned integers, reverting on
     * division by zero. The result is rounded towards zero.
     *
     * Counterpart to Solidity's `/` operator.
     *
     * Requirements:
     *
     * - The divisor cannot be zero.
     */
    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        return a / b;
    }

    /**
     * @dev Returns the remainder of dividing two unsigned integers. (unsigned integer modulo),
     * reverting when dividing by zero.
     *
     * Counterpart to Solidity's `%` operator. This function uses a `revert`
     * opcode (which leaves remaining gas untouched) while Solidity uses an
     * invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     *
     * - The divisor cannot be zero.
     */
    function mod(uint256 a, uint256 b) internal pure returns (uint256) {
        return a % b;
    }

    /**
     * @dev Returns the subtraction of two unsigned integers, reverting with custom message on
     * overflow (when the result is negative).
     *
     * CAUTION: This function is deprecated because it requires allocating memory for the error
     * message unnecessarily. For custom revert reasons use {trySub}.
     *
     * Counterpart to Solidity's `-` operator.
     *
     * Requirements:
     *
     * - Subtraction cannot overflow.
     */
    function sub(
        uint256 a,
        uint256 b,
        string memory errorMessage
    ) internal pure returns (uint256) {
        unchecked {
            require(b <= a, errorMessage);
            return a - b;
        }
    }

    /**
     * @dev Returns the integer division of two unsigned integers, reverting with custom message on
     * division by zero. The result is rounded towards zero.
     *
     * Counterpart to Solidity's `/` operator. Note: this function uses a
     * `revert` opcode (which leaves remaining gas untouched) while Solidity
     * uses an invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     *
     * - The divisor cannot be zero.
     */
    function div(
        uint256 a,
        uint256 b,
        string memory errorMessage
    ) internal pure returns (uint256) {
        unchecked {
            require(b > 0, errorMessage);
            return a / b;
        }
    }

    /**
     * @dev Returns the remainder of dividing two unsigned integers. (unsigned integer modulo),
     * reverting with custom message when dividing by zero.
     *
     * CAUTION: This function is deprecated because it requires allocating memory for the error
     * message unnecessarily. For custom revert reasons use {tryMod}.
     *
     * Counterpart to Solidity's `%` operator. This function uses a `revert`
     * opcode (which leaves remaining gas untouched) while Solidity uses an
     * invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     *
     * - The divisor cannot be zero.
     */
    function mod(
        uint256 a,
        uint256 b,
        string memory errorMessage
    ) internal pure returns (uint256) {
        unchecked {
            require(b > 0, errorMessage);
            return a % b;
        }
    }
}