// SPDX-License-Identifier: MIT

pragma solidity ^0.8.3;

import "openzeppelin-solidity/contracts/access/Ownable.sol";
import "./UbeswapMoolaRouterBase.sol";

/// @notice Router for allowing conversion to/from Moola before swapping.
contract UbeswapMoolaRouter is UbeswapMoolaRouterBase, Ownable {
    using SafeERC20 for IERC20;

    /// @notice Emitted when tokens that were stuck in the router contract were recovered
    event Recovered(address indexed token, uint256 amount);

    /// @notice Referral code for the default Moola router
    uint16 public constant MOOLA_ROUTER_REFERRAL_CODE = 0x0420;

    constructor(address router_, address owner_)
        UbeswapMoolaRouterBase(router_, MOOLA_ROUTER_REFERRAL_CODE)
    {
        transferOwnership(owner_);
    }

    /// @notice Added to support recovering tokens stuck in the contract
    /// This is to ensure that tokens can't get lost
    function recoverERC20(address tokenAddress, uint256 tokenAmount)
        external
        onlyOwner
    {
        IERC20(tokenAddress).safeTransfer(msg.sender, tokenAmount);
        emit Recovered(tokenAddress, tokenAmount);
    }
}


// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/*
 * @dev Provides information about the current execution context, including the
 * sender of the transaction and its data. While these are generally available
 * via msg.sender and msg.data, they should not be accessed in such a direct
 * manner, since when dealing with meta-transactions the account sending and
 * paying for execution may not be the actual sender (as far as an application
 * is concerned).
 *
 * This contract is only required for intermediate, library-like contracts.
 */
abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        this; // silence state mutability warning without generating bytecode - see https://github.com/ethereum/solidity/issues/2691
        return msg.data;
    }
}


// SPDX-License-Identifier: MIT

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
        require(isContract(target), "Address: call to non-contract");

        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory returndata) = target.call{ value: value }(data);
        return _verifyCallResult(success, returndata, errorMessage);
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
    function functionStaticCall(address target, bytes memory data, string memory errorMessage) internal view returns (bytes memory) {
        require(isContract(target), "Address: static call to non-contract");

        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory returndata) = target.staticcall(data);
        return _verifyCallResult(success, returndata, errorMessage);
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
    function functionDelegateCall(address target, bytes memory data, string memory errorMessage) internal returns (bytes memory) {
        require(isContract(target), "Address: delegate call to non-contract");

        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory returndata) = target.delegatecall(data);
        return _verifyCallResult(success, returndata, errorMessage);
    }

    function _verifyCallResult(bool success, bytes memory returndata, string memory errorMessage) private pure returns(bytes memory) {
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

pragma solidity ^0.8.0;

import "../IERC20.sol";
import "../../../utils/Address.sol";

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

    function safeTransfer(IERC20 token, address to, uint256 value) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(token.transfer.selector, to, value));
    }

    function safeTransferFrom(IERC20 token, address from, address to, uint256 value) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(token.transferFrom.selector, from, to, value));
    }

    /**
     * @dev Deprecated. This function has issues similar to the ones found in
     * {IERC20-approve}, and its usage is discouraged.
     *
     * Whenever possible, use {safeIncreaseAllowance} and
     * {safeDecreaseAllowance} instead.
     */
    function safeApprove(IERC20 token, address spender, uint256 value) internal {
        // safeApprove should only be called when setting an initial allowance,
        // or when resetting it to zero. To increase and decrease it, use
        // 'safeIncreaseAllowance' and 'safeDecreaseAllowance'
        // solhint-disable-next-line max-line-length
        require((value == 0) || (token.allowance(address(this), spender) == 0),
            "SafeERC20: approve from non-zero to non-zero allowance"
        );
        _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, value));
    }

    function safeIncreaseAllowance(IERC20 token, address spender, uint256 value) internal {
        uint256 newAllowance = token.allowance(address(this), spender) + value;
        _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, newAllowance));
    }

    function safeDecreaseAllowance(IERC20 token, address spender, uint256 value) internal {
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
        if (returndata.length > 0) { // Return data is optional
            // solhint-disable-next-line max-line-length
            require(abi.decode(returndata, (bool)), "SafeERC20: ERC20 operation did not succeed");
        }
    }
}


// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

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

pragma solidity ^0.8.0;

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

    constructor () {
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


// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../utils/Context.sol";
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
abstract contract Ownable is Context {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /**
     * @dev Initializes the contract setting the deployer as the initial owner.
     */
    constructor () {
        address msgSender = _msgSender();
        _owner = msgSender;
        emit OwnershipTransferred(address(0), msgSender);
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

pragma solidity ^0.8.3;

import "../interfaces/IUbeswapRouter.sol";
import "../interfaces/IMoola.sol";
import "../lending/MoolaLibrary.sol";

/// @notice Library for computing various router functions
library UbeswapMoolaRouterLibrary {
    /// @notice Plan for executing a swap on the router.
    struct SwapPlan {
        address reserveIn;
        address reserveOut;
        bool depositIn;
        bool depositOut;
        address[] nextPath;
    }

    /// @notice Computes the swap that will take place based on the path
    function computeSwap(ILendingPoolCore _core, address[] calldata _path)
        internal
        view
        returns (SwapPlan memory _plan)
    {
        uint256 startIndex;
        uint256 endIndex = _path.length;

        // cAsset -> mcAsset (deposit)
        if (
            _core.getReserveATokenAddress(
                MoolaLibrary.getMoolaReserveToken(_path[0])
            ) == _path[1]
        ) {
            _plan.reserveIn = _path[0];
            _plan.depositIn = true;
            startIndex += 1;
        }
        // mcAsset -> cAsset (withdraw)
        else if (
            _path[0] ==
            _core.getReserveATokenAddress(
                MoolaLibrary.getMoolaReserveToken(_path[1])
            )
        ) {
            _plan.reserveIn = _path[1];
            _plan.depositIn = false;
            startIndex += 1;
        }

        // only handle out path swap if the path is long enough
        if (
            _path.length >= 3 &&
            // if we already did a conversion and path length is 3, skip.
            !(_path.length == 3 && startIndex > 0)
        ) {
            // cAsset -> mcAsset (deposit)
            if (
                _core.getReserveATokenAddress(
                    MoolaLibrary.getMoolaReserveToken(_path[_path.length - 2])
                ) == _path[_path.length - 1]
            ) {
                _plan.reserveOut = _path[_path.length - 2];
                _plan.depositOut = true;
                endIndex -= 1;
            }
            // mcAsset -> cAsset (withdraw)
            else if (
                _path[_path.length - 2] ==
                _core.getReserveATokenAddress(
                    MoolaLibrary.getMoolaReserveToken(_path[_path.length - 1])
                )
            ) {
                _plan.reserveOut = _path[_path.length - 1];
                endIndex -= 1;
                // not needed
                // _depositOut = false;
            }
        }

        _plan.nextPath = _path[startIndex:endIndex];
    }

    /// @notice Computes the amounts given the amounts returned by the router
    function computeAmountsFromRouterAmounts(
        uint256[] memory _routerAmounts,
        address _reserveIn,
        address _reserveOut
    ) internal pure returns (uint256[] memory amounts) {
        uint256 startOffset = _reserveIn != address(0) ? 1 : 0;
        uint256 endOffset = _reserveOut != address(0) ? 1 : 0;
        uint256 length = _routerAmounts.length + startOffset + endOffset;

        amounts = new uint256[](length);
        if (startOffset > 0) {
            amounts[0] = _routerAmounts[0];
        }
        if (endOffset > 0) {
            amounts[length - 1] = _routerAmounts[_routerAmounts.length - 1];
        }
        for (uint256 i = 0; i < _routerAmounts.length; i++) {
            amounts[i + startOffset] = _routerAmounts[i];
        }
    }

    function getAmountsOut(
        ILendingPoolCore core,
        IUbeswapRouter router,
        uint256 amountIn,
        address[] calldata path
    ) internal view returns (uint256[] memory amounts) {
        SwapPlan memory plan = computeSwap(core, path);
        amounts = computeAmountsFromRouterAmounts(
            router.getAmountsOut(amountIn, plan.nextPath),
            plan.reserveIn,
            plan.reserveOut
        );
    }

    function getAmountsIn(
        ILendingPoolCore core,
        IUbeswapRouter router,
        uint256 amountOut,
        address[] calldata path
    ) internal view returns (uint256[] memory amounts) {
        SwapPlan memory plan = computeSwap(core, path);
        amounts = computeAmountsFromRouterAmounts(
            router.getAmountsIn(amountOut, plan.nextPath),
            plan.reserveIn,
            plan.reserveOut
        );
    }
}


// SPDX-License-Identifier: MIT

pragma solidity ^0.8.3;

import "../lending/LendingPoolWrapper.sol";
import "../interfaces/IUbeswapRouter.sol";
import "./UbeswapMoolaRouterLibrary.sol";

/**
 * Router for allowing conversion to/from Moola before swapping.
 */
abstract contract UbeswapMoolaRouterBase is LendingPoolWrapper, IUbeswapRouter {
    using SafeERC20 for IERC20;

    /// @notice Ubeswap router
    IUbeswapRouter public immutable router;

    /// @notice Emitted when tokens are swapped
    event TokensSwapped(
        address indexed account,
        address[] indexed path,
        address indexed to,
        uint256 amountIn,
        uint256 amountOut
    );

    constructor(address router_, uint16 moolaReferralCode_)
        LendingPoolWrapper(moolaReferralCode_)
    {
        router = IUbeswapRouter(router_);
    }

    function _initSwap(
        address[] calldata _path,
        uint256 _inAmount,
        uint256 _outAmount
    ) internal returns (UbeswapMoolaRouterLibrary.SwapPlan memory _plan) {
        _plan = UbeswapMoolaRouterLibrary.computeSwap(core, _path);

        // if we have a path, approve the router to be able to trade
        if (_plan.nextPath.length > 0) {
            // if out amount is specified, compute the in amount from it
            if (_outAmount != 0) {
                _inAmount = router.getAmountsIn(_outAmount, _plan.nextPath)[0];
            }
            IERC20(_plan.nextPath[0]).safeApprove(address(router), _inAmount);
        }

        // Handle pulling the initial amount from the contract caller
        IERC20(_path[0]).safeTransferFrom(msg.sender, address(this), _inAmount);

        // If in reserve is specified, we must convert
        if (_plan.reserveIn != address(0)) {
            _convert(
                _plan.reserveIn,
                _inAmount,
                _plan.depositIn,
                Reason.CONVERT_IN
            );
        }
    }

    /// @dev Ensures that the ERC20 token balances of this contract before and after
    /// the swap are equal
    /// TODO(igm): remove this once we get an audit
    /// This should NEVER get triggered, but it's better to be safe than sorry
    modifier balanceUnchanged(address[] calldata _path, address _to) {
        // Populate initial balances for comparison later
        uint256[] memory _initialBalances = new uint256[](_path.length);
        for (uint256 i = 0; i < _path.length; i++) {
            _initialBalances[i] = IERC20(_path[i]).balanceOf(address(this));
        }
        _;
        for (uint256 i = 0; i < _path.length - 1; i++) {
            uint256 newBalance = IERC20(_path[i]).balanceOf(address(this));
            require(
                // if triangular arb, ignore
                _path[i] == _path[0] ||
                    _path[i] == _path[_path.length - 1] ||
                    // ensure tokens balances haven't changed
                    newBalance == _initialBalances[i],
                "UbeswapMoolaRouter: tokens left over after swap"
            );
        }
        // sends the final tokens to `_to` address
        address lastAddress = _path[_path.length - 1];
        IERC20(lastAddress).safeTransfer(
            _to,
            // subtract the initial balance from this token
            IERC20(lastAddress).balanceOf(address(this)) -
                _initialBalances[_initialBalances.length - 1]
        );
    }

    /// @dev Handles the swap after the plan is executed
    function _swapConvertOut(
        UbeswapMoolaRouterLibrary.SwapPlan memory _plan,
        uint256[] memory _routerAmounts,
        address[] calldata _path,
        address _to
    ) internal returns (uint256[] memory amounts) {
        amounts = UbeswapMoolaRouterLibrary.computeAmountsFromRouterAmounts(
            _routerAmounts,
            _plan.reserveIn,
            _plan.reserveOut
        );
        if (_plan.reserveOut != address(0)) {
            _convert(
                _plan.reserveOut,
                amounts[amounts.length - 1],
                _plan.depositOut,
                Reason.CONVERT_OUT
            );
        }
        emit TokensSwapped(
            msg.sender,
            _path,
            _to,
            amounts[0],
            amounts[amounts.length - 1]
        );
    }

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    )
        external
        override
        balanceUnchanged(path, to)
        returns (uint256[] memory amounts)
    {
        UbeswapMoolaRouterLibrary.SwapPlan memory plan =
            _initSwap(path, amountIn, 0);
        if (plan.nextPath.length > 0) {
            amounts = router.swapExactTokensForTokens(
                amountIn,
                amountOutMin,
                plan.nextPath,
                address(this),
                deadline
            );
        }
        amounts = _swapConvertOut(plan, amounts, path, to);
    }

    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    )
        external
        override
        balanceUnchanged(path, to)
        returns (uint256[] memory amounts)
    {
        UbeswapMoolaRouterLibrary.SwapPlan memory plan =
            _initSwap(path, 0, amountOut);
        if (plan.nextPath.length > 0) {
            amounts = router.swapTokensForExactTokens(
                amountOut,
                amountInMax,
                plan.nextPath,
                address(this),
                deadline
            );
        }
        amounts = _swapConvertOut(plan, amounts, path, to);
    }

    function getAmountsOut(uint256 _amountIn, address[] calldata _path)
        external
        view
        override
        returns (uint256[] memory)
    {
        return
            UbeswapMoolaRouterLibrary.getAmountsOut(
                core,
                router,
                _amountIn,
                _path
            );
    }

    function getAmountsIn(uint256 _amountOut, address[] calldata _path)
        external
        view
        override
        returns (uint256[] memory)
    {
        return
            UbeswapMoolaRouterLibrary.getAmountsIn(
                core,
                router,
                _amountOut,
                _path
            );
    }

    function computeSwap(address[] calldata _path)
        external
        view
        returns (UbeswapMoolaRouterLibrary.SwapPlan memory)
    {
        return UbeswapMoolaRouterLibrary.computeSwap(core, _path);
    }

    function computeAmountsFromRouterAmounts(
        uint256[] memory _routerAmounts,
        address _reserveIn,
        address _reserveOut
    ) external pure returns (uint256[] memory) {
        return
            UbeswapMoolaRouterLibrary.computeAmountsFromRouterAmounts(
                _routerAmounts,
                _reserveIn,
                _reserveOut
            );
    }
}


// SPDX-License-Identifier: MIT

pragma solidity ^0.8.3;

import "openzeppelin-solidity/contracts/token/ERC20/utils/SafeERC20.sol";

interface IRegistry {
    function getAddressForOrDie(bytes32) external view returns (address);
}

/**
 * Library for interacting with Moola.
 */
library MoolaLibrary {
    /// @dev Mock CELO address to represent raw CELO tokens
    address internal constant CELO_MAGIC_ADDRESS =
        0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    /// @dev Address of the Celo registry
    address internal constant CELO_REGISTRY =
        0x000000000000000000000000000000000000ce10;

    bytes32 internal constant GOLD_TOKEN_REGISTRY_ID =
        keccak256(abi.encodePacked("GoldToken"));

    /// @notice Gets the address of CGLD
    function getGoldToken() internal view returns (address) {
        if (block.chainid == 31337) {
            // deployed via create2 in tests
            return
                IRegistry(0xCde5a0dC96d0ecEaee6fFfA84a6d9a6343f2c8E2)
                    .getAddressForOrDie(GOLD_TOKEN_REGISTRY_ID);
        }
        return
            IRegistry(CELO_REGISTRY).getAddressForOrDie(GOLD_TOKEN_REGISTRY_ID);
    }

    /// @notice Gets the token that Moola requests, supporting the gold token.
    function getMoolaReserveToken(address _reserve)
        internal
        view
        returns (address)
    {
        if (_reserve == getGoldToken()) {
            _reserve = CELO_MAGIC_ADDRESS;
        }
        return _reserve;
    }
}


// SPDX-License-Identifier: MIT

pragma solidity ^0.8.3;

import "openzeppelin-solidity/contracts/security/ReentrancyGuard.sol";
import "openzeppelin-solidity/contracts/token/ERC20/utils/SafeERC20.sol";

import "../interfaces/ILendingPoolWrapper.sol";
import "../interfaces/IMoola.sol";
import "./MoolaLibrary.sol";

interface IWrappedTestingGold {
    function unwrapTestingOnly(uint256 _amount) external;

    function wrap() external payable;
}

/**
 * @notice Wrapper to deposit and withdraw into a lending pool.
 */
contract LendingPoolWrapper is ILendingPoolWrapper, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @notice Lending pool
    ILendingPool public pool;

    /// @notice Lending core
    ILendingPoolCore public core;

    /// @notice Referral code to allow tracking Moola volume originating from Ubeswap.
    uint16 public immutable moolaReferralCode;

    /// @notice Celo Gold token
    address public immutable goldToken = MoolaLibrary.getGoldToken();

    constructor(uint16 moolaReferralCode_) {
        moolaReferralCode = moolaReferralCode_;
    }

    /// @notice initializes the pool (only used for deployment)
    function initialize(address _pool, address _core) external {
        require(
            address(pool) == address(0),
            "LendingPoolWrapper: pool already set"
        );
        require(
            address(core) == address(0),
            "LendingPoolWrapper: core already set"
        );
        pool = ILendingPool(_pool);
        core = ILendingPoolCore(_core);
    }

    function deposit(address _reserve, uint256 _amount) external override {
        IERC20(_reserve).safeTransferFrom(msg.sender, address(this), _amount);
        _convert(_reserve, _amount, true, Reason.DIRECT);
        IERC20(
            core.getReserveATokenAddress(
                MoolaLibrary.getMoolaReserveToken(_reserve)
            )
        )
            .safeTransfer(msg.sender, _amount);
    }

    function withdraw(address _reserve, uint256 _amount) external override {
        IERC20(
            core.getReserveATokenAddress(
                MoolaLibrary.getMoolaReserveToken(_reserve)
            )
        )
            .safeTransferFrom(msg.sender, address(this), _amount);
        _convert(_reserve, _amount, false, Reason.DIRECT);
        IERC20(_reserve).safeTransfer(msg.sender, _amount);
    }

    /**
     * @notice Converts tokens to/from their Moola representation.
     * @param _reserve The token to deposit or withdraw.
     * @param _amount The total amount of tokens to deposit or withdraw.
     * @param _deposit If true, deposit the token for aTokens. Otherwise, withdraw aTokens to tokens.
     * @param _reason Reason for why the conversion happened.
     */
    function _convert(
        address _reserve,
        uint256 _amount,
        bool _deposit,
        Reason _reason
    ) internal nonReentrant {
        if (_deposit) {
            if (
                MoolaLibrary.getMoolaReserveToken(_reserve) ==
                MoolaLibrary.CELO_MAGIC_ADDRESS
            ) {
                // hardhat -- doesn't have celo erc20 so we need to handle it differently
                if (block.chainid == 31337) {
                    IWrappedTestingGold(goldToken).unwrapTestingOnly(_amount);
                }
                pool.deposit{value: _amount}(
                    MoolaLibrary.CELO_MAGIC_ADDRESS,
                    _amount,
                    moolaReferralCode
                );
            } else {
                IERC20(_reserve).safeApprove(address(core), _amount);
                pool.deposit(_reserve, _amount, moolaReferralCode);
            }
            emit Deposited(_reserve, msg.sender, _reason, _amount);
        } else {
            IAToken(
                core.getReserveATokenAddress(
                    MoolaLibrary.getMoolaReserveToken(_reserve)
                )
            )
                .redeem(_amount);
            emit Withdrawn(_reserve, msg.sender, _reason, _amount);
        }
    }

    /// @notice This is used to receive CELO direct payments
    receive() external payable {
        // mock gold token can send tokens here on Hardhat
        if (block.chainid == 31337 && msg.sender == address(goldToken)) {
            return;
        }
        require(
            msg.sender == address(core),
            "LendingPoolWrapper: Must be LendingPoolCore to send CELO"
        );

        // if hardhat, wrap the token so we can send it back to the user
        if (block.chainid == 31337) {
            IWrappedTestingGold(goldToken).wrap{value: msg.value}();
        }
    }
}


// SPDX-License-Identifier: MIT

pragma solidity ^0.8.3;

/// @notice Swaps tokens
interface IUbeswapRouter {
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    function getAmountsOut(uint256 amountIn, address[] memory path)
        external
        view
        returns (uint256[] memory amounts);

    function getAmountsIn(uint256 amountOut, address[] memory path)
        external
        view
        returns (uint256[] memory amounts);
}


// SPDX-License-Identifier: MIT

pragma solidity ^0.8.3;

// Interfaces in this file come from Moola.

interface IAToken {
    function redeem(uint256 _amount) external;
}

interface ILendingPoolCore {
    function getReserveATokenAddress(address _reserve)
        external
        view
        returns (address);
}

interface ILendingPool {
    function deposit(
        address _reserve,
        uint256 _amount,
        uint16 _referralCode
    ) external payable;
}


// SPDX-License-Identifier: MIT

pragma solidity ^0.8.3;

/// @notice Wraps the Moola lending pool
interface ILendingPoolWrapper {
    enum Reason {DIRECT, CONVERT_IN, CONVERT_OUT}

    event Deposited(
        address indexed reserve,
        address indexed account,
        Reason indexed reason,
        uint256 amount
    );

    event Withdrawn(
        address indexed reserve,
        address indexed account,
        Reason indexed reason,
        uint256 amount
    );

    /**
     * @notice Deposits tokens into the lending pool.
     * @param _reserve The token to deposit.
     * @param _amount The total amount of tokens to deposit.
     */
    function deposit(address _reserve, uint256 _amount) external;

    /**
     * @notice Withdraws tokens from the lending pool.
     * @param _reserve The token to withdraw.
     * @param _amount The total amount of tokens to withdraw.
     */
    function withdraw(address _reserve, uint256 _amount) external;
}