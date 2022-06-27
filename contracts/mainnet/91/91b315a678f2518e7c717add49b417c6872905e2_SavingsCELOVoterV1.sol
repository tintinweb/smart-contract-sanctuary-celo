//SPDX-License-Identifier: MIT
pragma solidity 0.6.8;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

import "./UsingRegistry.sol";
import "./interfaces/IElection.sol";
import "./interfaces/IVoterProxy.sol";

/// @title SavingsCELO voter contract.
/// @notice VoterV1 supports voting for only one group a time.
contract SavingsCELOVoterV1 is Ownable, UsingRegistry {
	using SafeMath for uint256;

	IVoterProxy public _proxy;
	address public votedGroup;

	constructor (address savingsCELO) public {
		_proxy = IVoterProxy(savingsCELO);
	}

	/// @dev Changes voted group. This call revokes all current votes for currently voted group.
	/// votedGroupIndex is the index of votedGroup in SavingsCELO votes. This is expected to be 0 since
	/// SavingsCELO is supposed to be voting only for one group.
	///
	/// lesser.../greater... parameters are needed to perform Election.revokePending and Election.revokeActive
	/// calls. See Election contract for more details.
	///
	/// NOTE: changeVotedGroup can be used to clear out all votes even if SavingsCELO is voting for multiple
	/// groups. This can be useful if SavingsCELO is in a weird voting state before VoterV1 contract is installed
	/// as the voter contract.
	function changeVotedGroup(
		address newGroup,
		uint256 votedGroupIndex,
		address lesserAfterPendingRevoke,
		address greaterAfterPendingRevoke,
		address lesserAfterActiveRevoke,
		address greaterAfterActiveRevoke) onlyOwner external {
		if (votedGroup != address(0)) {
			IElection _election = getElection();
			uint256 pendingVotes = _election.getPendingVotesForGroupByAccount(votedGroup, address(_proxy));
			uint256 activeVotes = _election.getActiveVotesForGroupByAccount(votedGroup, address(_proxy));
			if (pendingVotes > 0) {
				require(
					_proxy.proxyRevokePending(
						votedGroup, pendingVotes, lesserAfterPendingRevoke, greaterAfterPendingRevoke, votedGroupIndex),
					"revokePending for voted group failed");
			}
			if (activeVotes > 0) {
				require(
					_proxy.proxyRevokeActive(
						votedGroup, activeVotes, lesserAfterActiveRevoke, greaterAfterActiveRevoke, votedGroupIndex),
					"revokeActive for voted group failed");
			}
		}
		votedGroup = newGroup;
	}

	/// @dev Activates any activatable votes and also casts new votes if there is new locked CELO in
	/// SavingsCELO contract. Anyone can call this method, and it is expected to be called regularly to make
	/// sure all new locked CELO is deployed to earn rewards.
	function activateAndVote(
		address lesser,
		address greater
	) external {
		require(votedGroup != address(0), "voted group is not set");
		IElection _election = getElection();
		if (_election.hasActivatablePendingVotes(address(_proxy), votedGroup)) {
			require(
				_proxy.proxyActivate(votedGroup),
				"activate for voted group failed");
		}
		uint256 toVote = getLockedGold().getAccountNonvotingLockedGold(address(_proxy));
		if (toVote > 0) {
			uint256 maxVotes = _election.getNumVotesReceivable(votedGroup);
			uint256 totalVotes = _election.getTotalVotesForGroup(votedGroup);
			if (maxVotes <= totalVotes) {
				toVote = 0;
			} else if (maxVotes.sub(totalVotes) < toVote) {
				toVote = maxVotes.sub(totalVotes);
			}
			if (toVote > 0) {
				require(
					_proxy.proxyVote(votedGroup, toVote, lesser, greater),
					"casting votes for voted group failed");
			}
		}
	}
}


//SPDX-License-Identifier: MIT
pragma solidity 0.6.8;

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


//SPDX-License-Identifier: MIT
pragma solidity 0.6.8;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./interfaces/IRegistry.sol";
import "./interfaces/IAccounts.sol";
import "./interfaces/ILockedGold.sol";
import "./interfaces/IElection.sol";
import "./interfaces/IExchange.sol";
import "./interfaces/IGovernance.sol";

// This is a simplified version of Celo's: protocol/contracts/common/UsingRegistry.sol
contract UsingRegistry {

	IRegistry constant registry = IRegistry(address(0x000000000000000000000000000000000000ce10));

	bytes32 constant ACCOUNTS_REGISTRY_ID = keccak256(abi.encodePacked("Accounts"));
	bytes32 constant ELECTION_REGISTRY_ID = keccak256(abi.encodePacked("Election"));
	bytes32 constant EXCHANGE_REGISTRY_ID = keccak256(abi.encodePacked("Exchange"));
	bytes32 constant GOLD_TOKEN_REGISTRY_ID = keccak256(abi.encodePacked("GoldToken"));
	bytes32 constant GOVERNANCE_REGISTRY_ID = keccak256(abi.encodePacked("Governance"));
	bytes32 constant LOCKED_GOLD_REGISTRY_ID = keccak256(abi.encodePacked("LockedGold"));
	bytes32 constant STABLE_TOKEN_REGISTRY_ID = keccak256(abi.encodePacked("StableToken"));

	function getAccounts() internal view returns (IAccounts) {
		return IAccounts(registry.getAddressForOrDie(ACCOUNTS_REGISTRY_ID));
	}

	function getElection() internal view returns (IElection) {
		return IElection(registry.getAddressForOrDie(ELECTION_REGISTRY_ID));
	}

	function getExchange() internal view returns (IExchange) {
		return IExchange(registry.getAddressForOrDie(EXCHANGE_REGISTRY_ID));
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

	function getStableToken() internal view returns (IERC20) {
		return IERC20(registry.getAddressForOrDie(STABLE_TOKEN_REGISTRY_ID));
	}
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

/**
 * @dev Interface of the ERC20 standard as defined in the EIP.
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


// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

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
     *
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
     *
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
     *
     * - Subtraction cannot overflow.
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
     *
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
     *
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
     *
     * - The divisor cannot be zero.
     */
    function div(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
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
     *
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
     *
     * - The divisor cannot be zero.
     */
    function mod(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b != 0, errorMessage);
        return a % b;
    }
}


// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

import "../GSN/Context.sol";
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
        require(_owner == _msgSender(), "Ownable: caller is not the owner");
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
        emit OwnershipTransferred(_owner, address(0));
        _owner = address(0);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}


// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

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
abstract contract Context {
    function _msgSender() internal view virtual returns (address payable) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes memory) {
        this; // silence state mutability warning without generating bytecode - see https://github.com/ethereum/solidity/issues/2691
        return msg.data;
    }
}


//SPDX-License-Identifier: MIT
pragma solidity 0.6.8;

import "./IGovernance.sol";

interface IVoterProxy {
	function proxyVote(address, uint256, address, address) external returns (bool);
	function proxyActivate(address) external returns (bool);
	function proxyRevokeActive(address, uint256, address, address, uint256) external returns (bool);
	function proxyRevokePending(address, uint256, address, address, uint256) external returns (bool);

	function proxyGovernanceVote(uint256, uint256, Governance.VoteValue) external returns (bool);
	function proxyGovernanceUpvote(uint256, uint256, uint256) external returns (bool);
	function proxyGovernanceRevokeUpvote(uint256, uint256) external returns (bool);
}


//SPDX-License-Identifier: MIT
pragma solidity 0.6.8;

interface IRegistry {
	function getAddressForStringOrDie(string calldata identifier) external view returns (address);
	function getAddressForOrDie(bytes32) external view returns (address);
}


//SPDX-License-Identifier: MIT
pragma solidity 0.6.8;

interface ILockedGold {
	function incrementNonvotingAccountBalance(address, uint256) external;
	function decrementNonvotingAccountBalance(address, uint256) external;
	function getAccountTotalLockedGold(address) external view returns (uint256);
	function getAccountNonvotingLockedGold(address) external view returns (uint256);
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


//SPDX-License-Identifier: MIT
pragma solidity 0.6.8;

contract Governance {
	enum VoteValue { None, Abstain, No, Yes }
}

interface IGovernance {
	function vote(uint256 proposalId, uint256 index, Governance.VoteValue value) external returns (bool);
	function upvote(uint256 proposalId, uint256 lesser, uint256 greater) external returns (bool);
	function revokeUpvote(uint256 lesser, uint256 greater) external returns (bool);
}


//SPDX-License-Identifier: MIT
pragma solidity 0.6.8;

interface IExchange {
	function sell(uint256, uint256, bool) external returns (uint256);
}


//SPDX-License-Identifier: MIT
pragma solidity 0.6.8;

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