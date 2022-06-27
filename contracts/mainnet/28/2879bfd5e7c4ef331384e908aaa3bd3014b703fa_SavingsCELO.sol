//SPDX-License-Identifier: MIT
pragma solidity 0.6.8;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "./UsingRegistry.sol";
import "./interfaces/IRegistry.sol";
import "./interfaces/ILockedGold.sol";
import "./interfaces/IElection.sol";
import "./interfaces/IVoterProxy.sol";

/// @title SavingsCELO contract
contract SavingsCELO is ERC20, IVoterProxy, Ownable, UsingRegistry {
	using SafeMath for uint256;

	/// @dev authorized voter contract.
	address public _voter;

	/// @dev emitted when new voter contract is authorized.
	/// @param previousVoter previously authorized voter.
	/// @param newVoter newly authorized voter.
	event VoterAuthorized(address indexed previousVoter, address indexed newVoter);

	/// @dev PendingWithdrawal matches struct from core Celo LockedGold.sol.
	struct PendingWithdrawal {
		// The value of the pending withdrawal.
		uint256 value;
		// The timestamp at which the pending withdrawal becomes available.
		uint256 timestamp;
	}
	/// @dev Maps address to its initiated pending withdrawals.
	mapping(address => PendingWithdrawal[]) internal pendingByAddr;

	/// @dev emitted when CELO is deposited in SavingsCELO contract.
	/// @param from address that initiated the deposit.
	/// @param celoAmount amount of CELO deposited.
	/// @param savingsAmount amount of sCELO tokens received in exchange.
	event Deposited(address indexed from, uint256 celoAmount, uint256 savingsAmount);

	/// @dev emitted when CELO withdrawal process is initiated.
	/// @param from address that initiated the withdrawal.
	/// @param savingsAmount amount of sCELO tokens that were returned.
	/// @param celoAmount amount of CELO tokens that will be withdrawn.
	event WithdrawStarted(address indexed from, uint256 savingsAmount, uint256 celoAmount);

	/// @dev emitted when withdrawal process is finished.
	/// @param from address that finished the withdrawal process.
	/// @param celoAmount amount of CELO tokens that were withdrawn from SavingsCELO contract.
	event WithdrawFinished(address indexed from, uint256 celoAmount);

	/// @dev emitted when withdrawal process is cancelled.
	/// @param from address that canceled the withdrawal process.
	/// @param celoAmount amount of CELO tokens that were returned to SavingsCELO contract.
	/// @param savingsAmount amount of sCELO tokens that were returned to the caller.
	event WithdrawCanceled(address indexed from, uint256 celoAmount, uint256 savingsAmount);

	constructor () ERC20("Savings CELO", "sCELO") public {
		require(
			getAccounts().createAccount(),
			"createAccount failed");
	}

	/// @notice Authorizes new vote signer that can manage voting for all of contract's locked
	/// CELO. {v, r, s} constitutes proof-of-key-possession signature of signer for this
	/// contract address.
	/// @dev Vote Signer authorization exists only as a means of a potential escape-hatch if
	/// some sort of really unexpected issue occurs. By default, it is expected that there
	/// will be no authorized vote signer, and a voting contract will be configured using
	/// .authorizeVoterProxy call instead.
	/// @param signer address to authorize as a signer.
	/// @param v {v, r, s} proof-of-key possession signature.
	/// @param r {v, r, s} proof-of-key possession signature.
	/// @param s {v, r, s} proof-of-key possession signature.
	function authorizeVoteSigner(
		address signer,
		uint8 v,
		bytes32 r,
		bytes32 s) onlyOwner external {
		getAccounts().authorizeVoteSigner(signer, v, r, s);
	}

	/// @notice Authorizes another contract to perform voting on behalf of SavingsCELO.
	/// @param voter address of the voter contract to authorize.
	function authorizeVoterProxy(address voter) onlyOwner external {
		_voter = voter;
		emit VoterAuthorized(_voter, voter);
	}

	modifier voterOnly() {
		require(_voter == msg.sender, "caller must be the registered _voter");
		_;
	}

	// Proxy functions for validator election voting.
	function proxyVote(
		address group,
		uint256 value,
		address lesser,
		address greater) voterOnly external override returns (bool) {
		return getElection().vote(group, value, lesser, greater);
	}
	function proxyActivate(address group) voterOnly external override returns (bool) {
		return getElection().activate(group);
	}
	function proxyRevokeActive(
		address group,
		uint256 value,
		address lesser,
		address greater,
		uint256 index) voterOnly external override returns (bool) {
		return getElection().revokeActive(group, value, lesser, greater, index);
	}
	function proxyRevokePending(
		address group,
		uint256 value,
		address lesser,
		address greater,
		uint256 index) voterOnly external override returns (bool) {
		return getElection().revokePending(group, value, lesser, greater, index);
	}

	// Proxy functions for governance voting.
	function proxyGovernanceVote(
		uint256 proposalId,
		uint256 index,
		Governance.VoteValue value) voterOnly external override returns (bool) {
		return getGovernance().vote(proposalId, index, value);
	}
	function proxyGovernanceUpvote(
		uint256 proposalId,
		uint256 lesser,
		uint256 greater) voterOnly external override returns (bool) {
		return getGovernance().upvote(proposalId, lesser, greater);
	}
	function proxyGovernanceRevokeUpvote(
		uint256 lesser,
		uint256 greater) voterOnly external override returns (bool) {
		return getGovernance().revokeUpvote(lesser, greater);
	}

	/// @notice Deposits CELO to the contract in exchange of SavingsCELO (sCELO) tokens.
	/// @return toMint Amount of sCELO tokens minted.
	function deposit() external payable returns (uint256 toMint) {
		uint256 totalCELO = totalSupplyCELO().sub(msg.value);
		uint256 totalSavingsCELO = this.totalSupply();
		toMint = savingsToMint(totalSavingsCELO, totalCELO, msg.value);
		_mint(msg.sender, toMint);

		uint256 toLock = address(this).balance;
		assert(toLock >= msg.value);
		// It is safe to call _lockedGold.lock() with 0 value.
		getLockedGold().lock{value: toLock}();
		emit Deposited(msg.sender, msg.value, toMint);
		return toMint;
	}

	/// @notice Starts withdraw process for savingsAmount SavingsCELO tokens.
	/// @dev Since only nonvoting CELO can be unlocked, withdrawStart might have to call Election.revoke* calls to
	/// revoke currently cast votes. To keep this call simple, maximum amount of CELO that can be unlocked in single call is:
	/// `nonvoting locked CELO + total votes for last voted group`. This way, withdrawStart call will only
	/// revoke votes for a single group at most, making it simpler overall.
	///
	/// lesser.../greater... parameters are needed to perform Election.revokePending and Election.revokeActive
	/// calls. See Election contract for more details. lesser.../greater... arguments
	/// are for last voted group by this contract, since revoking only happens for the last voted group.
	///
	/// Note that it is possible for this call to fail due to accidental race conditions if lesser.../greater...
	/// parameters no longer match due to changes in overall voting ranking.
	/// @return toWithdraw amount of CELO tokens that will be withdrawn.
	function withdrawStart(
		uint256 savingsAmount,
		address lesserAfterPendingRevoke,
		address greaterAfterPendingRevoke,
		address lesserAfterActiveRevoke,
		address greaterAfterActiveRevoke
		) external returns (uint256 toWithdraw) {
		require(savingsAmount > 0, "withdraw amount must be positive");
		uint256 totalCELO = totalSupplyCELO();
		uint256 totalSavingsCELO = this.totalSupply();
		_burn(msg.sender, savingsAmount);
		// If there is any unlocked CELO, lock it to make rest of the logic always
		// consistent. There should never be unlocked CELO in the contract unless some
		// user explicitly donates it.
		ILockedGold _lockedGold = getLockedGold();
		if (address(this).balance > 0) {
			_lockedGold.lock{value: address(this).balance}();
		}
		// toUnlock formula comes from:
		// (supply / totalCELO) === (supply - savingsAmount) / (totalCELO - toUnlock)
		toWithdraw = savingsAmount.mul(totalCELO).div(totalSavingsCELO);
		uint256 nonvoting = _lockedGold.getAccountNonvotingLockedGold(address(this));
		if (toWithdraw > nonvoting) {
			revokeVotes(
				toWithdraw.sub(nonvoting),
				lesserAfterPendingRevoke,
				greaterAfterPendingRevoke,
				lesserAfterActiveRevoke,
				greaterAfterActiveRevoke
			);
		}
		_lockedGold.unlock(toWithdraw);

		(uint256[] memory pendingValues, uint256[] memory pendingTimestamps) = _lockedGold.getPendingWithdrawals(address(this));
		uint256 pendingValue = pendingValues[pendingValues.length - 1];
		assert(pendingValue == toWithdraw);
		pendingByAddr[msg.sender].push(PendingWithdrawal(pendingValue, pendingTimestamps[pendingTimestamps.length - 1]));
		emit WithdrawStarted(msg.sender, savingsAmount, pendingValue);
		return toWithdraw;
	}

	/// @dev Helper function to revoke cast votes. See documentation for .withdrawStart function for more
	/// information about the arguments.
	function revokeVotes(
		uint256 toRevoke,
		address lesserAfterPendingRevoke,
		address greaterAfterPendingRevoke,
		address lesserAfterActiveRevoke,
		address greaterAfterActiveRevoke
	) private {
		IElection _election = getElection();
		address[] memory votedGroups = _election.getGroupsVotedForByAccount(address(this));
		require(votedGroups.length > 0, "not enough votes to revoke");
		uint256 revokeIndex = votedGroups.length - 1;
		address revokeGroup = votedGroups[revokeIndex];
		uint256 pendingVotes = _election.getPendingVotesForGroupByAccount(revokeGroup, address(this));
		uint256 activeVotes = _election.getActiveVotesForGroupByAccount(revokeGroup, address(this));
		require(
			pendingVotes.add(activeVotes) >= toRevoke,
			"not enough unlocked CELO and revokable votes");

		uint256 toRevokePending = pendingVotes;
		if (toRevokePending > toRevoke) {
			toRevokePending = toRevoke;
		}
		uint256 toRevokeActive = toRevoke.sub(toRevokePending);
		if (toRevokePending > 0) {
			require(
				_election.revokePending(
				revokeGroup, toRevokePending, lesserAfterPendingRevoke, greaterAfterPendingRevoke, revokeIndex),
				"revokePending failed");
		}
		if (toRevokeActive > 0) {
			require(
				_election.revokeActive(
				revokeGroup, toRevokeActive, lesserAfterActiveRevoke, greaterAfterActiveRevoke, revokeIndex),
				"revokeActive failed");
		}
	}

	/// @notice Finishes withdraw process, transfering unlocked CELO back to the caller.
	/// @param index index of pending withdrawal to finish as returned by .pendingWithdrawals() call.
	/// @param indexGlobal index of matching pending withdrawal as returned by lockedGold.getPendingWithdrawals() call.
	/// @return amount of CELO tokens withdrawn.
	function withdrawFinish(uint256 index, uint256 indexGlobal) external returns (uint256) {
		PendingWithdrawal memory pending = popPendingWithdrawal(msg.sender, index, indexGlobal);
		getLockedGold().withdraw(indexGlobal);
		require(
			getGoldToken().transfer(msg.sender, pending.value),
			"unexpected failure: CELO transfer has failed");
		emit WithdrawFinished(msg.sender, pending.value);
		return pending.value;
	}

	/// @notice Cancels withdraw process, re-locking CELO back in the contract and returning SavingsCELO tokens back
	/// to the caller. At the time of re-locking, SavingsCELO can be more valuable compared to when .withdrawStart
	/// was called. Thus caller might receive less SavingsCELO compared to what was supplied to .withdrawStart.
	/// @param index index of pending withdrawal to finish as returned by .pendingWithdrawals() call.
	/// @param indexGlobal index of matching pending withdrawal as returned by lockedGold.getPendingWithdrawals() call.
	/// @return toMint amount of sCELO tokens returned to the caller.
	function withdrawCancel(uint256 index, uint256 indexGlobal) external returns (uint256 toMint) {
		PendingWithdrawal memory pending = popPendingWithdrawal(msg.sender, index, indexGlobal);
		uint256 totalCELO = totalSupplyCELO();
		uint256 totalSavingsCELO = this.totalSupply();
		getLockedGold().relock(indexGlobal, pending.value);
		toMint = savingsToMint(totalSavingsCELO, totalCELO, pending.value);
		_mint(msg.sender, toMint);
		emit WithdrawCanceled(msg.sender, pending.value, toMint);
		return toMint;
	}

	/// @dev Returns (values[], timestamps[]) of all pending withdrawals for given address.
	function pendingWithdrawals(address addr)
		external
		view
		returns (uint256[] memory, uint256[] memory) {
		PendingWithdrawal[] storage pending = pendingByAddr[addr];
		uint256 length = pending.length;
		uint256[] memory values = new uint256[](length);
		uint256[] memory timestamps = new uint256[](length);
		for (uint256 i = 0; i < length; i = i.add(1)) {
			values[i] = pending[i].value;
			timestamps[i] = pending[i].timestamp;
		}
		return (values, timestamps);
	}

	/// @dev Helper function to verify indexes and to pop specific PendingWithdrawal from the list.
	function popPendingWithdrawal(
		address addr,
		uint256 index,
		uint256 indexGlobal) private returns(PendingWithdrawal memory pending) {
		PendingWithdrawal[] storage pendings = pendingByAddr[addr];
		require(index < pendings.length, "bad pending withdrawal index");
		(uint256[] memory pendingValues, uint256[] memory pendingTimestamps) = getLockedGold().getPendingWithdrawals(address(this));
		require(indexGlobal < pendingValues.length, "bad pending withdrawal indexGlobal");
		require(pendings[index].value == pendingValues[indexGlobal], "mismatched value for index and indexGlobal");
		require(pendings[index].timestamp == pendingTimestamps[indexGlobal], "mismatched timestamp for index and indexGlobal");
		pending = pendings[index]; // This makes a copy.

		pendings[index] = pendings[pendings.length - 1];
		pendings.pop();
		return pending;
	}


	/// @notice Returns amount of CELO that can be claimed for savingsAmount SavingsCELO tokens.
	/// @param savingsAmount amount of sCELO tokens.
	/// @return amount of CELO tokens.
	function savingsToCELO(uint256 savingsAmount) external view returns (uint256) {
		uint256 totalSavingsCELO = this.totalSupply();
		if (totalSavingsCELO == 0) {
			return 0;
		}
		uint256 totalCELO = totalSupplyCELO();
		return savingsAmount.mul(totalCELO).div(totalSavingsCELO);
	}
	/// @notice Returns amount of SavingsCELO tokens that can be received for depositing celoAmount CELO tokens.
	/// @param celoAmount amount of CELO tokens.
	/// @return amount of sCELO tokens.
	function celoToSavings(uint256 celoAmount) external view returns (uint256) {
		uint256 totalSavingsCELO = this.totalSupply();
		uint256 totalCELO = totalSupplyCELO();
		return savingsToMint(totalSavingsCELO, totalCELO, celoAmount);
	}

	function totalSupplyCELO() internal view returns(uint256) {
		uint256 locked = getLockedGold().getAccountTotalLockedGold(address(this));
		uint256 unlocked = address(this).balance;
		return locked.add(unlocked);
	}

	function savingsToMint(
		uint256 totalSavingsCELO,
		uint256 totalCELO,
		uint256 celoToAdd) private pure returns (uint256) {
		if (totalSavingsCELO == 0 || totalCELO == 0) {
			// 2^16 is chosen arbitrarily. since maximum amount of CELO is capped at 1BLN, we can afford to
			// multiply it by 2^16 without running into any overflow issues. This also makes it clear that
			// SavingsCELO and CELO don't have 1:1 relationship to avoid confusion down the line.
			return celoToAdd.mul(65536);
		}
		return celoToAdd.mul(totalSavingsCELO).div(totalCELO);
	}

	receive() external payable {}
}


// SPDX-License-Identifier: MIT

pragma solidity ^0.6.2;

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
        // This method relies in extcodesize, which returns 0 for contracts in
        // construction, since the code is only stored at the end of the
        // constructor execution.

        uint256 size;
        // solhint-disable-next-line no-inline-assembly
        assembly { size := extcodesize(account) }
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

        // solhint-disable-next-line avoid-low-level-calls, avoid-call-value
        (bool success, ) = recipient.call{ value: amount }("");
        require(success, "Address: unable to send value, recipient may have reverted");
    }

    /**
     * @dev Performs a Solidity function call using a low level `call`. A
     * plain`call` is an unsafe replacement for a function call: use this
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
    function functionCall(address target, bytes memory data, string memory errorMessage) internal returns (bytes memory) {
        return _functionCallWithValue(target, data, 0, errorMessage);
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
    function functionCallWithValue(address target, bytes memory data, uint256 value) internal returns (bytes memory) {
        return functionCallWithValue(target, data, value, "Address: low-level call with value failed");
    }

    /**
     * @dev Same as {xref-Address-functionCallWithValue-address-bytes-uint256-}[`functionCallWithValue`], but
     * with `errorMessage` as a fallback revert reason when `target` reverts.
     *
     * _Available since v3.1._
     */
    function functionCallWithValue(address target, bytes memory data, uint256 value, string memory errorMessage) internal returns (bytes memory) {
        require(address(this).balance >= value, "Address: insufficient balance for call");
        return _functionCallWithValue(target, data, value, errorMessage);
    }

    function _functionCallWithValue(address target, bytes memory data, uint256 weiValue, string memory errorMessage) private returns (bytes memory) {
        require(isContract(target), "Address: call to non-contract");

        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory returndata) = target.call{ value: weiValue }(data);
        if (success) {
            return returndata;
        } else {
            // Look for revert reason and bubble it up if present
            if (returndata.length > 0) {
                // The easiest way to bubble the revert reason is using memory via assembly

                // solhint-disable-next-line no-inline-assembly
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

import "../../GSN/Context.sol";
import "./IERC20.sol";
import "../../math/SafeMath.sol";
import "../../utils/Address.sol";

/**
 * @dev Implementation of the {IERC20} interface.
 *
 * This implementation is agnostic to the way tokens are created. This means
 * that a supply mechanism has to be added in a derived contract using {_mint}.
 * For a generic mechanism see {ERC20PresetMinterPauser}.
 *
 * TIP: For a detailed writeup see our guide
 * https://forum.zeppelin.solutions/t/how-to-implement-erc20-supply-mechanisms/226[How
 * to implement supply mechanisms].
 *
 * We have followed general OpenZeppelin guidelines: functions revert instead
 * of returning `false` on failure. This behavior is nonetheless conventional
 * and does not conflict with the expectations of ERC20 applications.
 *
 * Additionally, an {Approval} event is emitted on calls to {transferFrom}.
 * This allows applications to reconstruct the allowance for all accounts just
 * by listening to said events. Other implementations of the EIP may not emit
 * these events, as it isn't required by the specification.
 *
 * Finally, the non-standard {decreaseAllowance} and {increaseAllowance}
 * functions have been added to mitigate the well-known issues around setting
 * allowances. See {IERC20-approve}.
 */
contract ERC20 is Context, IERC20 {
    using SafeMath for uint256;
    using Address for address;

    mapping (address => uint256) private _balances;

    mapping (address => mapping (address => uint256)) private _allowances;

    uint256 private _totalSupply;

    string private _name;
    string private _symbol;
    uint8 private _decimals;

    /**
     * @dev Sets the values for {name} and {symbol}, initializes {decimals} with
     * a default value of 18.
     *
     * To select a different value for {decimals}, use {_setupDecimals}.
     *
     * All three of these values are immutable: they can only be set once during
     * construction.
     */
    constructor (string memory name, string memory symbol) public {
        _name = name;
        _symbol = symbol;
        _decimals = 18;
    }

    /**
     * @dev Returns the name of the token.
     */
    function name() public view returns (string memory) {
        return _name;
    }

    /**
     * @dev Returns the symbol of the token, usually a shorter version of the
     * name.
     */
    function symbol() public view returns (string memory) {
        return _symbol;
    }

    /**
     * @dev Returns the number of decimals used to get its user representation.
     * For example, if `decimals` equals `2`, a balance of `505` tokens should
     * be displayed to a user as `5,05` (`505 / 10 ** 2`).
     *
     * Tokens usually opt for a value of 18, imitating the relationship between
     * Ether and Wei. This is the value {ERC20} uses, unless {_setupDecimals} is
     * called.
     *
     * NOTE: This information is only used for _display_ purposes: it in
     * no way affects any of the arithmetic of the contract, including
     * {IERC20-balanceOf} and {IERC20-transfer}.
     */
    function decimals() public view returns (uint8) {
        return _decimals;
    }

    /**
     * @dev See {IERC20-totalSupply}.
     */
    function totalSupply() public view override returns (uint256) {
        return _totalSupply;
    }

    /**
     * @dev See {IERC20-balanceOf}.
     */
    function balanceOf(address account) public view override returns (uint256) {
        return _balances[account];
    }

    /**
     * @dev See {IERC20-transfer}.
     *
     * Requirements:
     *
     * - `recipient` cannot be the zero address.
     * - the caller must have a balance of at least `amount`.
     */
    function transfer(address recipient, uint256 amount) public virtual override returns (bool) {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    /**
     * @dev See {IERC20-allowance}.
     */
    function allowance(address owner, address spender) public view virtual override returns (uint256) {
        return _allowances[owner][spender];
    }

    /**
     * @dev See {IERC20-approve}.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     */
    function approve(address spender, uint256 amount) public virtual override returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    /**
     * @dev See {IERC20-transferFrom}.
     *
     * Emits an {Approval} event indicating the updated allowance. This is not
     * required by the EIP. See the note at the beginning of {ERC20};
     *
     * Requirements:
     * - `sender` and `recipient` cannot be the zero address.
     * - `sender` must have a balance of at least `amount`.
     * - the caller must have allowance for ``sender``'s tokens of at least
     * `amount`.
     */
    function transferFrom(address sender, address recipient, uint256 amount) public virtual override returns (bool) {
        _transfer(sender, recipient, amount);
        _approve(sender, _msgSender(), _allowances[sender][_msgSender()].sub(amount, "ERC20: transfer amount exceeds allowance"));
        return true;
    }

    /**
     * @dev Atomically increases the allowance granted to `spender` by the caller.
     *
     * This is an alternative to {approve} that can be used as a mitigation for
     * problems described in {IERC20-approve}.
     *
     * Emits an {Approval} event indicating the updated allowance.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     */
    function increaseAllowance(address spender, uint256 addedValue) public virtual returns (bool) {
        _approve(_msgSender(), spender, _allowances[_msgSender()][spender].add(addedValue));
        return true;
    }

    /**
     * @dev Atomically decreases the allowance granted to `spender` by the caller.
     *
     * This is an alternative to {approve} that can be used as a mitigation for
     * problems described in {IERC20-approve}.
     *
     * Emits an {Approval} event indicating the updated allowance.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     * - `spender` must have allowance for the caller of at least
     * `subtractedValue`.
     */
    function decreaseAllowance(address spender, uint256 subtractedValue) public virtual returns (bool) {
        _approve(_msgSender(), spender, _allowances[_msgSender()][spender].sub(subtractedValue, "ERC20: decreased allowance below zero"));
        return true;
    }

    /**
     * @dev Moves tokens `amount` from `sender` to `recipient`.
     *
     * This is internal function is equivalent to {transfer}, and can be used to
     * e.g. implement automatic token fees, slashing mechanisms, etc.
     *
     * Emits a {Transfer} event.
     *
     * Requirements:
     *
     * - `sender` cannot be the zero address.
     * - `recipient` cannot be the zero address.
     * - `sender` must have a balance of at least `amount`.
     */
    function _transfer(address sender, address recipient, uint256 amount) internal virtual {
        require(sender != address(0), "ERC20: transfer from the zero address");
        require(recipient != address(0), "ERC20: transfer to the zero address");

        _beforeTokenTransfer(sender, recipient, amount);

        _balances[sender] = _balances[sender].sub(amount, "ERC20: transfer amount exceeds balance");
        _balances[recipient] = _balances[recipient].add(amount);
        emit Transfer(sender, recipient, amount);
    }

    /** @dev Creates `amount` tokens and assigns them to `account`, increasing
     * the total supply.
     *
     * Emits a {Transfer} event with `from` set to the zero address.
     *
     * Requirements
     *
     * - `to` cannot be the zero address.
     */
    function _mint(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: mint to the zero address");

        _beforeTokenTransfer(address(0), account, amount);

        _totalSupply = _totalSupply.add(amount);
        _balances[account] = _balances[account].add(amount);
        emit Transfer(address(0), account, amount);
    }

    /**
     * @dev Destroys `amount` tokens from `account`, reducing the
     * total supply.
     *
     * Emits a {Transfer} event with `to` set to the zero address.
     *
     * Requirements
     *
     * - `account` cannot be the zero address.
     * - `account` must have at least `amount` tokens.
     */
    function _burn(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: burn from the zero address");

        _beforeTokenTransfer(account, address(0), amount);

        _balances[account] = _balances[account].sub(amount, "ERC20: burn amount exceeds balance");
        _totalSupply = _totalSupply.sub(amount);
        emit Transfer(account, address(0), amount);
    }

    /**
     * @dev Sets `amount` as the allowance of `spender` over the `owner` s tokens.
     *
     * This internal function is equivalent to `approve`, and can be used to
     * e.g. set automatic allowances for certain subsystems, etc.
     *
     * Emits an {Approval} event.
     *
     * Requirements:
     *
     * - `owner` cannot be the zero address.
     * - `spender` cannot be the zero address.
     */
    function _approve(address owner, address spender, uint256 amount) internal virtual {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    /**
     * @dev Sets {decimals} to a value other than the default one of 18.
     *
     * WARNING: This function should only be called from the constructor. Most
     * applications that interact with token contracts will not expect
     * {decimals} to ever change, and may work incorrectly if it does.
     */
    function _setupDecimals(uint8 decimals_) internal {
        _decimals = decimals_;
    }

    /**
     * @dev Hook that is called before any transfer of tokens. This includes
     * minting and burning.
     *
     * Calling conditions:
     *
     * - when `from` and `to` are both non-zero, `amount` of ``from``'s tokens
     * will be to transferred to `to`.
     * - when `from` is zero, `amount` tokens will be minted for `to`.
     * - when `to` is zero, `amount` of ``from``'s tokens will be burned.
     * - `from` and `to` are never both zero.
     *
     * To learn more about hooks, head to xref:ROOT:extending-contracts.adoc#using-hooks[Using Hooks].
     */
    function _beforeTokenTransfer(address from, address to, uint256 amount) internal virtual { }
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