// SPDX-License-Identifier: MIT

pragma solidity 0.8.6;

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
    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool);

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


/**
 * @title SafeERC20
 * @dev Wrappers around ERC20 operations that throw on failure (when the token
 * contract returns false). Tokens that return no value (and instead revert or
 * throw on failure) are also supported, non-reverting calls are assumed to be
 * successful.
 * To use this library you can add a `using SafeERC20 for IERC20;` statement to your contract,
 * which allows you to call the safe operations as `token.safeTransfer(...)`, etc.
 */
library SafeERC20 {
    using Address for address;

    function safeTransfer(
        IERC20 token,
        address to,
        uint256 value
    ) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(token.transfer.selector, to, value));
    }

    function safeTransferFrom(
        IERC20 token,
        address from,
        address to,
        uint256 value
    ) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(token.transferFrom.selector, from, to, value));
    }

    /**
     * @dev Deprecated. This function has issues similar to the ones found in
     * {IERC20-approve}, and its usage is discouraged.
     *
     * Whenever possible, use {safeIncreaseAllowance} and
     * {safeDecreaseAllowance} instead.
     */
    function safeApprove(
        IERC20 token,
        address spender,
        uint256 value
    ) internal {
        // safeApprove should only be called when setting an initial allowance,
        // or when resetting it to zero. To increase and decrease it, use
        // 'safeIncreaseAllowance' and 'safeDecreaseAllowance'
        require(
            (value == 0) || (token.allowance(address(this), spender) == 0),
            "SafeERC20: approve from non-zero to non-zero allowance"
        );
        _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, value));
    }

    function safeIncreaseAllowance(
        IERC20 token,
        address spender,
        uint256 value
    ) internal {
        uint256 newAllowance = token.allowance(address(this), spender) + value;
        _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, newAllowance));
    }

    function safeDecreaseAllowance(
        IERC20 token,
        address spender,
        uint256 value
    ) internal {
    unchecked {
        uint256 oldAllowance = token.allowance(address(this), spender);
        require(oldAllowance >= value, "SafeERC20: decreased allowance below zero");
        uint256 newAllowance = oldAllowance - value;
        _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, newAllowance));
    }
    }

    /**
     * @dev Imitates a Solidity high-level call (i.e. a regular function call to a contract), relaxing the requirement
     * on the return value: the return value is optional (but if data is returned, it must not be false).
     * @param token The token targeted by the call.
     * @param data The call data (encoded using abi.encode or one of its variants).
     */
    function _callOptionalReturn(IERC20 token, bytes memory data) private {
        // We need to perform a low level call here, to bypass Solidity's return data size checking mechanism, since
        // we're implementing it ourselves. We use {Address.functionCall} to perform this call, which verifies that
        // the target address contains contract code and also asserts for success in the low-level call.

        bytes memory returndata = address(token).functionCall(data, "SafeERC20: low-level call failed");
        if (returndata.length > 0) {
            // Return data is optional
            require(abi.decode(returndata, (bool)), "SafeERC20: ERC20 operation did not succeed");
        }
    }
}


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
abstract contract ReentrancyGuard {
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

    constructor() {
        _status = _NOT_ENTERED;
    }

    /**
     * @dev Prevents a contract from calling itself, directly or indirectly.
     * Calling a `nonReentrant` function from another `nonReentrant`
     * function is not supported. It is possible to prevent this from happening
     * by making the `nonReentrant` function external, and make it call a
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
}


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
        require(_initializing || !_initialized, "Initializable: contract is already initialized");

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
}


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
    function __Context_init() internal initializer {
        __Context_init_unchained();
    }

    function __Context_init_unchained() internal initializer {
    }
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        return msg.data;
    }
    uint256[50] private __gap;
}


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
    function __Ownable_init() internal initializer {
        __Context_init_unchained();
        __Ownable_init_unchained();
    }

    function __Ownable_init_unchained() internal initializer {
        _setOwner(_msgSender());
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
        _setOwner(address(0));
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        _setOwner(newOwner);
    }

    function _setOwner(address newOwner) private {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
    uint256[49] private __gap;
}


interface IReferral {
    function set(address from, address to) external;

    function refOf(address to) external view returns (address);

    function reward(address addr) external payable;

    function rewardToken(address token, address addr, uint256 amount) external;
}


interface ITokenLocker {
    function startReleaseTime() external view returns (uint256);

    function endReleaseTime() external view returns (uint256);

    function totalLock() external view returns (uint256);

    function totalReleased() external view returns (uint256);

    function lockOf(address _account) external view returns (uint256);

    function released(address _account) external view returns (uint256);

    function canUnlockAmount(address _account) external view returns (uint256);

    function lock(address _account, uint256 _amount) external;

    function unlock(uint256 _amount) external;

    function unlockAll() external;

    function claimUnlocked() external;
}


interface ICappedMintableBurnableERC20 {
    function decimals() external view returns (uint8);

    function cap() external view returns (uint256);

    function minter(address) external view returns (bool);

    function mint(address, uint256) external;

    function burn(uint256) external;

    function burnFrom(address, uint256) external;
}


contract ContractGuard {
    mapping(uint256 => mapping(address => bool)) private _status;

    function checkSameOriginReentranted() internal view returns (bool) {
        return _status[block.number][tx.origin];
    }

    function checkSameSenderReentranted() internal view returns (bool) {
        return _status[block.number][msg.sender];
    }

    modifier onlyOneBlock() {
        require(!checkSameOriginReentranted(), "ContractGuard: one block, one function");
        require(!checkSameSenderReentranted(), "ContractGuard: one block, one function");

        _status[block.number][tx.origin] = true;
        _status[block.number][msg.sender] = true;

        _;
    }
}


contract CeloDexChefLocked is OwnableUpgradeable, ReentrancyGuard, ContractGuard {
    using SafeERC20 for IERC20;

    // Info of each user.
    struct UserInfo {
        uint256 amount; // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
    }

    // Info of each pool.
    struct PoolInfo {
        IERC20 lpToken; // Address of LP token contract.
        uint256 allocPoint; // How many allocation points assigned to this pool. CLXs to distribute per block.
        uint256 lastRewardTime; // Last timestamp that CLXs distribution occurs.
        uint256 accClxPerShare; // Accumulated CLXs per share, times 1e18. See below.
        uint256 totalLpSupply;
        bool isStarted; // if lastRewardTime has passed
        uint256 startTime;
        uint16 depositFeeBP; // Deposit fee in basis points
        uint256 lockedTime;
        uint256 earlyWithdrawFee;
    }

    address public clx; // clx token

    uint256 public lockPercent;
    address public locker = address(0x0000000000000000000000000000000000000000);

    // Info of each pool.
    PoolInfo[] public poolInfo;

    // Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;

    // Total allocation poitns. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;
    uint256 public rewardPerSecond;
    uint256 public totalRewardPerSecond;

    address public treasuryFund;

    address public devFund;
    uint256 public devRate;
    uint256 public treasuryRate;
    uint256 public totalDevFundAdded;
    uint256 public totalTreasuryFundAdded;

    // The block number when CLX mining starts.
    uint256 public startTime;
    address public rewardReferral;
    uint256 public commissionPercent;

    uint256 public week;
    uint256 public nextHalvingTime;
    uint256 public rewardHalvingRate;
    bool public halvingChecked;

    mapping(uint256 => mapping(address => uint256)) public userLastDepositTime;
    mapping(address => bool) public whitelistedContract;

    address public timelock = address(0x0000000000000000000000000000000000000000);
    mapping(address => bool) public approvedStrategies;

    //   [Initial (+Airdrop)]       500,000
    //   TOTAL:                    99,500,000
    //   =============================================
    //   > LP Incentive (to Farm): 44,500,000 (44.50%)
    //   > Dev + MKT:              20,000,000 (20.00%)
    //   > Treasury (+Vaults + Reserve):     35,000,000 (35.00%)

    /* =================== Added variables (need to keep orders for proxy to work) =================== */

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event WithdrawFee(address indexed user, uint256 indexed pid, uint256 amount, uint256 fee);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event RewardPaid(address indexed user, uint256 amount);
    event LogRewardPerSecond(uint256 rewardPerSecond);
    event StrategyUpdated(uint256 indexed pid, address oldStrategy, address newStrategy);
    event TimelockUpdated(address newTimelock);
    event Commission(address account, address referrer, uint256 commission);

    modifier checkHalving() {
        if (halvingChecked) {
            halvingChecked = false;
            if (block.timestamp >= nextHalvingTime) {
                massUpdatePools();
                uint256 _totalRewardPerSecond = (totalRewardPerSecond * rewardHalvingRate) / 10000;
                totalRewardPerSecond = _totalRewardPerSecond;
                _updateRewardPerSecond();
                nextHalvingTime = nextHalvingTime + 7 days;
                ++week;
            }
            halvingChecked = true;
        }
        _;
    }

    modifier notContract() {
        if (!whitelistedContract[msg.sender]) {
            uint256 size;
            address addr = msg.sender;
            assembly {
                size := extcodesize(addr)
            }
            require(size == 0, "contract not allowed");
            require(tx.origin == msg.sender, "contract not allowed");
        }
        _;
    }

    modifier onlyTimelock() {
        require(msg.sender == timelock || (timelock == address(0) && msg.sender != owner()), "!timelock");
        _;
    }

    function _updateRewardPerSecond() internal {
        uint256 _totalRewardPerSecond = totalRewardPerSecond;
        uint256 _totalRate = devRate + treasuryRate;
        rewardPerSecond = _totalRewardPerSecond - (_totalRewardPerSecond * _totalRate / 10000);
        emit LogRewardPerSecond(rewardPerSecond);
    }

    function initialize(
        address _clx,
        address _locker,
        address _treasuryFund,
        uint256 _rewardPerSecond,
        uint256 _totalRewardPerSecond,
        uint256 _startTime
    ) external initializer {
        __Ownable_init();

        clx = _clx;
        locker = _locker;

        lockPercent = 7000; // lock 70% in 1 year, vest 1 year
        commissionPercent = 100; // 1%

        devRate = 2000;
        treasuryRate = 3500;

        treasuryFund = _treasuryFund;
        rewardPerSecond = _rewardPerSecond;
        totalRewardPerSecond = _totalRewardPerSecond;

        week = 0;
        startTime = _startTime;
        nextHalvingTime = _startTime + 7 days;

        rewardHalvingRate = 10000; // 100% - no halving
        halvingChecked = true;
    }

    function resetStartTime(uint256 _startTime) external onlyOwner {
        require(startTime > block.timestamp && _startTime > block.timestamp, "late");
        startTime = _startTime;
        nextHalvingTime = _startTime + 7 days;
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    function startReleaseTime() public view returns (uint256) {
        return ITokenLocker(locker).startReleaseTime();
    }

    function endReleaseTime() external view returns (uint256) {
        return ITokenLocker(locker).endReleaseTime();
    }

    function setHalvingChecked(bool _halvingChecked) external onlyOwner {
        halvingChecked = _halvingChecked;
    }

    function setRewardReferral(address _rewardReferral) external onlyOwner {
        rewardReferral = _rewardReferral;
    }

    function setLockPercent(uint256 _lockPercent) external onlyOwner {
        require(_lockPercent <= 9900, "exceed 99%");
        massUpdatePools();
        lockPercent = _lockPercent;
    }

    function setCommissionPercent(uint256 _commissionPercent) external onlyOwner {
        require(_commissionPercent <= 200, "exceed 2%");
        commissionPercent = _commissionPercent;
    }

    function setRewardHalvingRate(uint256 _rewardHalvingRate) external onlyOwner {
        require(_rewardHalvingRate >= 9000, "below 90%");
        massUpdatePools();
        rewardHalvingRate = _rewardHalvingRate;
    }

    function setWhitelistedContract(address _contract, bool _isWhitelisted) external onlyOwner {
        whitelistedContract[_contract] = _isWhitelisted;
    }

    function setTimelock(address _timelock) external onlyTimelock {
        require(_timelock != address(0), "invalidAddress");
        timelock = _timelock;
        emit TimelockUpdated(_timelock);
    }

    function setDevFund(address _devFund) external onlyOwner {
        require(_devFund != address(0), "invalidAddress");
        devFund = _devFund;
    }

    function setTreasuryFund(address _treasuryFund) external onlyOwner {
        require(_treasuryFund != address(0), "invalidAddress");
        treasuryFund = _treasuryFund;
    }

    function addPool(
        uint256 _allocPoint,
        IERC20 _lpToken,
        uint16 _depositFeeBP,
        uint256 _lastRewardTime,
        uint256 _lockedTime,
        uint256 _earlyWithdrawFee
    ) external onlyOwner {
        require(_allocPoint <= 100000, "too high allocation point"); // <= 100x
        require(_depositFeeBP <= 1000, "too high fee"); // <= 10%
        require(_lockedTime <= 180 days, "locked time is too long");
        require(_earlyWithdrawFee <= 8000, "early withdraw fee is too high"); // <= 50%
        massUpdatePools();
        if (block.timestamp < startTime) {
            // chef is sleeping
            if (_lastRewardTime == 0) {
                _lastRewardTime = startTime;
            } else {
                if (_lastRewardTime < startTime) {
                    _lastRewardTime = startTime;
                }
            }
        } else {
            // chef is cooking
            if (_lastRewardTime == 0 || _lastRewardTime < block.timestamp) {
                _lastRewardTime = block.timestamp;
            }
        }
        bool _isStarted = (_lastRewardTime <= startTime) || (_lastRewardTime <= block.timestamp);
        poolInfo.push(
            PoolInfo({
        lpToken : _lpToken,
        allocPoint : _allocPoint,
        lastRewardTime : _lastRewardTime,
        accClxPerShare : 0,
        totalLpSupply : 0,
        isStarted : _isStarted,
        depositFeeBP : _depositFeeBP,
        startTime : _lastRewardTime,
        lockedTime : _lockedTime,
        earlyWithdrawFee : _earlyWithdrawFee
        })
        );
        if (_isStarted) {
            totalAllocPoint = totalAllocPoint + _allocPoint;
        }
    }

    function replacePoolLpToken(uint256 _pid, IERC20 _lpToken) external onlyOwner {
        require(_lpToken.totalSupply() > 0, "Non-existing token");
        PoolInfo storage pool = poolInfo[_pid];
        require(pool.accClxPerShare == 0 && pool.totalLpSupply == 0, "Cant replace running pool");
        massUpdatePools();
        pool.lpToken = _lpToken;
    }

    function setPool(
        uint256 _pid,
        uint256 _allocPoint,
        uint16 _depositFeeBP,
        uint256 _lockedTime,
        uint256 _earlyWithdrawFee
    ) external onlyOwner {
        require(_allocPoint <= 100000, "too high allocation point");
        // <= 100x
        require(_depositFeeBP <= 1000, "too high fee");
        // <= 10%
        require(_lockedTime <= 180 days, "locked time is too long");
        require(_earlyWithdrawFee <= 8000, "early withdraw fee is too high");
        // <= 50%
        massUpdatePools();
        PoolInfo storage pool = poolInfo[_pid];
        if (pool.isStarted) {
            totalAllocPoint = totalAllocPoint - pool.allocPoint + _allocPoint;
        }
        pool.allocPoint = _allocPoint;
        pool.depositFeeBP = _depositFeeBP;
        pool.lockedTime = _lockedTime;
        pool.earlyWithdrawFee = _earlyWithdrawFee;
    }

    function setPoolStartTime(uint256 _pid, uint256 _lastRewardTime) external onlyOwner {
        require(_lastRewardTime > block.timestamp, "last reward time should not in past");
        massUpdatePools();
        PoolInfo storage pool = poolInfo[_pid];
        pool.lastRewardTime = _lastRewardTime;
    }

    function setTotalRewardPerSecond(uint256 _totalRewardPerSecond) external onlyOwner {
        require(_totalRewardPerSecond <= 10 ether, "insane high rate");
        massUpdatePools();
        totalRewardPerSecond = _totalRewardPerSecond;
        _updateRewardPerSecond();
    }

    function setDevRate(uint256 _devRate) external onlyOwner {
        require(_devRate <= 2500, "too high"); // <= 25%
        massUpdatePools();
        devRate = _devRate;
        _updateRewardPerSecond();
    }

    function setTreasuryRate(uint256 _treasuryRate) external onlyOwner {
        require(_treasuryRate <= 3500, "too high"); // <= 35%
        massUpdatePools();
        treasuryRate = _treasuryRate;
        _updateRewardPerSecond();
    }

    // View function to see pending CLXs on frontend.
    function pendingReward(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accClxPerShare = pool.accClxPerShare;
        uint256 lpSupply = pool.totalLpSupply;
        if (block.timestamp > pool.lastRewardTime && lpSupply != 0) {
            uint256 _seconds = block.timestamp - pool.lastRewardTime;
            if (totalAllocPoint > 0) {
                uint256 _clxReward = (_seconds * rewardPerSecond * pool.allocPoint) / totalAllocPoint;
                accClxPerShare += (_clxReward * 1e18) / lpSupply;
            }
        }
        uint256 _totalReward = (user.amount * accClxPerShare) / 1e18;
        uint256 _rewardDebt = user.rewardDebt;
        return (_totalReward > _rewardDebt) ? _totalReward - _rewardDebt : 0;
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.timestamp <= pool.lastRewardTime) {
            return;
        }
        uint256 lpSupply = pool.totalLpSupply;
        if (lpSupply == 0) {
            pool.lastRewardTime = block.timestamp;
            return;
        }
        if (!pool.isStarted) {
            pool.isStarted = true;
            totalAllocPoint = totalAllocPoint + pool.allocPoint;
        }
        if (totalAllocPoint > 0) {
            uint256 _seconds = block.timestamp - pool.lastRewardTime;
            uint256 _clxReward = (_seconds * rewardPerSecond * pool.allocPoint) / totalAllocPoint;
            pool.accClxPerShare += (_clxReward * 1e18) / lpSupply;
        }
        pool.lastRewardTime = block.timestamp;
    }

    function _harvestReward(uint256 _pid, address _account) internal {
        UserInfo storage user = userInfo[_pid][_account];
        uint256 _amount = user.amount;
        if (_amount > 0) {
            PoolInfo storage pool = poolInfo[_pid];
            uint256 _totalReward = (_amount * pool.accClxPerShare) / 1e18;
            uint256 _claimableAmount = 0;
            if (_totalReward < user.rewardDebt) {
                user.rewardDebt = _totalReward;
            } else {
                _claimableAmount = _totalReward - user.rewardDebt;
            }
            if (_claimableAmount > 0) {
                require(whitelistedContract[_account] || _claimableAmount * 100 <= IERC20(clx).totalSupply(), "Suspicious big reward amount!!"); // <= 1% total supply
                emit RewardPaid(_account, _claimableAmount);

                _topupFunds(_claimableAmount);

                uint256 beforeMint = IERC20(clx).balanceOf(address(this));
                _safeClxMint(address(this), _claimableAmount);
                uint256 afterMint = IERC20(clx).balanceOf(address(this));
                require(afterMint - beforeMint >= _claimableAmount, "Not mint enough reward!!");
                if (commissionPercent > 0) {
                    uint256 _commission = (_claimableAmount * commissionPercent) / 10000; // 1%
                    _sendCommission(msg.sender, _commission);
                    _claimableAmount = _claimableAmount - _commission;
                }

                if (block.timestamp < startReleaseTime()) {
                    uint256 _lockAmount = (_claimableAmount * lockPercent) / 10000;
                    _claimableAmount = _claimableAmount - _lockAmount;
                    IERC20(clx).safeIncreaseAllowance(address(locker), _lockAmount);
                    ITokenLocker(locker).lock(_account, _lockAmount);
                }

                _safeClxTransfer(_account, _claimableAmount);
            }
        }
    }

    function _sendCommission(address _account, uint256 _commission) internal {
        address _referrer = address(0);
        if (rewardReferral != address(0)) {
            _referrer = IReferral(rewardReferral).refOf(_account);
        }
        if (_referrer != address(0)) {
            // send commission to referrer
            _safeClxTransfer(_referrer, _commission);
            emit Commission(_account, _referrer, _commission);
        } else {
            // or to treasury
            _safeClxTransfer(treasuryFund, _commission);
            emit Commission(_account, treasuryFund, _commission);
        }
    }

    function deposit(uint256 _pid, uint256 _amount) public {
        depositWithRef(_pid, _amount, address(0));
    }

    function depositWithRef(uint256 _pid, uint256 _amount, address _referrer) public notContract onlyOneBlock nonReentrant checkHalving {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);
        if (user.amount > 0) {
            _harvestReward(_pid, msg.sender);
        }
        if (_amount > 0) {
            IERC20 _lpToken = pool.lpToken;
            uint256 _before = _lpToken.balanceOf(address(this));
            _lpToken.safeTransferFrom(msg.sender, address(this), _amount);
            uint256 _after = _lpToken.balanceOf(address(this));
            _amount = _after - _before;
            // fix issue of deflation token
            if (_amount > 0) {
                if (rewardReferral != address(0) && _referrer != address(0)) {
                    IReferral(rewardReferral).set(_referrer, msg.sender);
                }
                uint256 _depositFeeBP = pool.depositFeeBP;
                uint256 _userAmount = _amount;
                if (_depositFeeBP > 0) {
                    uint256 _fee = (_amount * _depositFeeBP) / 10000;
                    _lpToken.safeTransfer(treasuryFund, _fee);
                    _userAmount = _userAmount - _fee;
                }
                uint256 _totalLpSupply = pool.totalLpSupply;
                pool.totalLpSupply = _totalLpSupply + _userAmount;
                user.amount += _userAmount;
                userLastDepositTime[_pid][msg.sender] = block.timestamp;
            }
        }
        user.rewardDebt = (user.amount * pool.accClxPerShare) / 1e18;
        emit Deposit(msg.sender, _pid, _amount);
    }

    function unfrozenDepositTime(uint256 _pid, address _account) public view returns (uint256) {
        return (whitelistedContract[_account]) ? userLastDepositTime[_pid][_account] : userLastDepositTime[_pid][_account] + poolInfo[_pid].lockedTime;
    }

    function withdraw(uint256 _pid, uint256 _amount) public notContract nonReentrant checkHalving {
        _withdraw(msg.sender, _pid, _amount);
    }

    function _withdraw(
        address _account,
        uint256 _pid,
        uint256 _amount
    ) internal {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_account];
        require(user.amount >= _amount, "withdraw: not good");
        require(block.timestamp >= unfrozenDepositTime(_pid, _account), "locked time is not finished");
        updatePool(_pid);
        if (user.amount > 0) {
            _harvestReward(_pid, _account);
        }
        if (_amount > 0) {
            IERC20 _lpToken = pool.lpToken;
            uint256 _totalLpSupply = pool.totalLpSupply;

            uint256 _sentAmount = _amount;
            uint256 _earlyWithdrawFee = pool.earlyWithdrawFee;
            if (_earlyWithdrawFee > 0 && treasuryFund != address(0) && block.timestamp < unfrozenDepositTime(_pid, _account)) {
                _earlyWithdrawFee = (_amount * _earlyWithdrawFee) / 10000;
                _sentAmount = _sentAmount - _earlyWithdrawFee;
                _lpToken.safeTransfer(treasuryFund, _earlyWithdrawFee);
                emit WithdrawFee(_account, _pid, _amount, _earlyWithdrawFee);
            }

            pool.totalLpSupply = _totalLpSupply - _amount;
            user.amount -= _amount;
            _lpToken.safeTransfer(_account, _sentAmount);
        }
        user.rewardDebt = (user.amount * pool.accClxPerShare) / 1e18;
        emit Withdraw(_account, _pid, _amount);
    }

    function withdrawAll(uint256 _pid) external {
        _withdraw(msg.sender, _pid, userInfo[_pid][msg.sender].amount);
    }

    function harvestAllRewards() external {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            if (poolInfo[pid].lockedTime < 1 days && userInfo[pid][msg.sender].amount > 0) {
                _withdraw(msg.sender, pid, 0);
            }
        }
    }

    function _safeClxTransfer(address _to, uint256 _amount) internal {
        uint256 _clxBal = IERC20(clx).balanceOf(address(this));
        if (_clxBal > 0) {
            if (_amount > _clxBal) {
                IERC20(clx).safeTransfer(_to, _clxBal);
            } else {
                IERC20(clx).safeTransfer(_to, _amount);
            }
        }
    }

    function _safeClxMint(address _to, uint256 _amount) internal {
        address _clx = clx;
        if (ICappedMintableBurnableERC20(_clx).minter(address(this)) && _to != address(0)) {
            uint256 _totalSupply = IERC20(_clx).totalSupply();
            uint256 _cap = ICappedMintableBurnableERC20(_clx).cap();
            uint256 _mintAmount = (_totalSupply + _amount <= _cap) ? _amount : (_cap - _totalSupply);
            if (_mintAmount > 0) {
                ICappedMintableBurnableERC20(_clx).mint(_to, _mintAmount);
            }
        }
    }

    function _topupFunds(uint256 _claimableAmount) internal {
        address _clx = clx;
        uint256 _totalAmount = _claimableAmount * totalRewardPerSecond / rewardPerSecond;
        uint256 _devAmount = _totalAmount * devRate / 10000;
        uint256 _treasuryAmount = _totalAmount * treasuryRate / 10000;
        uint256 _totalMintAmount = _devAmount + _treasuryAmount;
        if (ICappedMintableBurnableERC20(_clx).minter(address(this)) &&
            IERC20(_clx).totalSupply() + _totalMintAmount <= ICappedMintableBurnableERC20(_clx).cap()) {
            ICappedMintableBurnableERC20(_clx).mint(devFund, _devAmount);
            ICappedMintableBurnableERC20(_clx).mint(treasuryFund, _treasuryAmount);
            totalDevFundAdded += _devAmount;
            totalTreasuryFundAdded += _treasuryAmount;
        }
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) external notContract onlyOneBlock nonReentrant {
        require(block.timestamp >= unfrozenDepositTime(_pid, msg.sender), "locked time is not finished");
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        IERC20 _lpToken = pool.lpToken;
        uint256 _amount = user.amount;
        uint256 _sentAmount = _amount;
        if (treasuryFund != address(0) && block.timestamp < unfrozenDepositTime(_pid, msg.sender)) {
            uint256 _earlyWithdrawFee = pool.earlyWithdrawFee;
            if (_earlyWithdrawFee > 0) {
                _earlyWithdrawFee = (_amount * _earlyWithdrawFee) / 10000;
                _sentAmount = _sentAmount - _earlyWithdrawFee;
                _lpToken.safeTransfer(treasuryFund, _earlyWithdrawFee);
                emit WithdrawFee(msg.sender, _pid, _amount, _earlyWithdrawFee);
            }
        }
        user.amount = 0;
        user.rewardDebt = 0;
        pool.totalLpSupply = pool.totalLpSupply - _amount;
        _lpToken.safeTransfer(address(msg.sender), _sentAmount);
        emit EmergencyWithdraw(msg.sender, _pid, _amount);
    }


    /* ========== EMERGENCY ========== */

    function rescueStuckErc20(address _token) external onlyOwner {
        // do not allow to drain lpToken
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            PoolInfo storage pool = poolInfo[pid];
            require(_token != address(pool.lpToken), "pool.lpToken");
        }
        IERC20(_token).transfer(owner(), IERC20(_token).balanceOf(address(this)));
    }
}