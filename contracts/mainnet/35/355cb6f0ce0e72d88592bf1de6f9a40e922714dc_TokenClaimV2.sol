// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "./IERC20SOUL.sol";

/// @title TokenClaimV2 - This contract enables the storage of
/// locked (specified by the ERC20SOUL standard) and unlocked
/// tokens by a beneficiary address. This implementation also
/// allows the owner to revoke a given claim in the case that
/// a beneficiary does not or is unable to claim.
/// @author Bridger Zoske - [email protected]
contract TokenClaimV2 is OwnableUpgradeable, ReentrancyGuardUpgradeable {
    struct Claim {
        uint256 unlockedAmount;
        IERC20SOUL.Lock lock;
        bool released;
    }

    // address of the ERC20 token
    IERC20SOUL private _token;
    mapping(address => Claim) public claims;
    uint256 public totalClaimable;

    event Released(Claim claim);
    event NewClaimAdded(Claim claim);
    event ClaimUpdated(Claim claim);

    /**
     * @dev Reverts if the address is null.
     */
    modifier notNull(address _address) {
        require(_address != address(0), "Invalid address");
        _;
    }

    /**
     * @dev Reverts if the claim does not exist or has been released.
     */
    modifier onlyIfClaimNotReleased(address beneficiary) {
        require(getClaimTotal(beneficiary) != 0, "TokenClaim: Claim does not exist");
        require(claims[beneficiary].released == false, "TokenClaim: Claim has been released");
        _;
    }

    /**
     * @dev Creates a claim contract.
     * @param token_ address of the ERC20 token contract

     */
    function initialize(address token_) external virtual initializer {
        require(token_ != address(0x0));
        __Ownable_init();
        _token = IERC20SOUL(token_);
    }

    /**
     * @dev Returns the address of the ERC20 token managed by the claim contract.
     */
    function getToken() external view returns (address) {
        return address(_token);
    }

    /**
     * @notice Creates a new claim for a beneficiary.
     * @param _beneficiary address of the beneficiary to whom vested tokens are transferred
     * @param _unlockedAmount total unlocked amount in claim
     * @param _lock lock structure for locked tokens in claim
     */
    function addClaim(
        address _beneficiary,
        uint256 _unlockedAmount,
        IERC20SOUL.Lock calldata _lock
    ) public notNull(_beneficiary) onlyOwner {
        uint256 totalAmount = _unlockedAmount + _lock.totalAmount;
        require(
            getWithdrawableAmount() >= totalAmount,
            "TokenClaim: cannot create claim because not sufficient tokens"
        );
        require(totalAmount > 0, "TokenClaim: amount must be > 0");

        if (_lock.totalAmount > 0) {
            validLock(_lock);
        }

        Claim storage _claim = claims[_beneficiary];

        if (getClaimTotal(_beneficiary) == 0) {
            _claim.lock = _lock;
            _claim.unlockedAmount = _unlockedAmount;
            emit NewClaimAdded(_claim);
        } else {
            _claim.lock.totalAmount += _lock.totalAmount;
            for (uint256 i = 0; i < _lock.schedules.length; i++) {
                _claim.lock.schedules.push(
                    IERC20SOUL.Schedule(
                        _lock.schedules[i].amount,
                        _lock.schedules[i].expirationBlock
                    )
                );
            }
            _claim.unlockedAmount += _unlockedAmount;
            emit ClaimUpdated(_claim);
        }
        _claim.released = false;
        totalClaimable += totalAmount;
    }

    function validLock(IERC20SOUL.Lock calldata _lock) internal view {
        require(_lock.totalAmount > 0, "Invalid Lock amount");
        uint256 lockTotal;
        for (uint256 i = 0; i < _lock.schedules.length; i++) {
            lockTotal += _lock.schedules[i].amount;
            require(
                _lock.schedules[i].expirationBlock > block.timestamp + _token.getMinLockTime(),
                "Lock schedule does not meet minimum"
            );
            require(
                _lock.schedules[i].expirationBlock < block.timestamp + _token.getMaxLockTime(),
                "Lock schedule does not meet maximum"
            );
        }
        require(lockTotal == _lock.totalAmount, "Invalid Lock");
    }

    /**
     * @notice Revokes the claim for given beneficiary
     * @param beneficiary address of claim owner
     */
    function revoke(address beneficiary) public onlyOwner onlyIfClaimNotReleased(beneficiary) {
        totalClaimable -= getClaimTotal(beneficiary);
        delete claims[beneficiary];
    }

    /**
     * @notice Withdraw the specified amount if possible.
     * @param amount the amount to withdraw
     */
    function withdraw(uint256 amount) public nonReentrant onlyOwner {
        require(getWithdrawableAmount() >= amount, "TokenClaim: not enough withdrawable funds");
        _token.transfer(owner(), amount);
    }

    /**
     * @notice claim tokens
     */
    function claim() public nonReentrant onlyIfClaimNotReleased(msg.sender) {
        Claim storage _claim = claims[msg.sender];
        uint256 deleteOffset;
        uint256 schedulesLength = _claim.lock.schedules.length;
        for (uint256 i = 0; i < schedulesLength; i++) {
            uint256 index = i - deleteOffset;
            // lock schedule is expired so add locked amount to unlocked amount and remove schedule
            if (_claim.lock.schedules[index].expirationBlock - 1 days < block.timestamp) {
                _claim.unlockedAmount += _claim.lock.schedules[index].amount;
                _claim.lock.totalAmount -= _claim.lock.schedules[index].amount;
                _claim.lock.schedules[index] = _claim.lock.schedules[
                    _claim.lock.schedules.length - 1
                ];
                _claim.lock.schedules.pop();
                deleteOffset++;
            }
        }
        if (_claim.unlockedAmount > 0) {
            _token.transfer(msg.sender, _claim.unlockedAmount);
        }
        if (_claim.lock.totalAmount > 0) {
            _token.transferWithLock(msg.sender, _claim.lock);
        }
        uint256 totalAmount = getClaimTotal(msg.sender);
        delete claims[msg.sender];
        _claim.released = true;
        totalClaimable -= totalAmount;
        emit Released(_claim);
    }

    /**
     * @dev Returns the amount of tokens that can be withdrawn by the owner.
     * @return the amount of tokens
     */
    function getWithdrawableAmount() public view returns (uint256) {
        return _token.balanceOf(address(this)) - totalClaimable;
    }

    /**
     * @dev Returns the amount of tokens that can be withdrawn by the owner.
     * @return the amount of tokens
     */
    function getClaimTotal(address beneficiary) public view returns (uint256) {
        Claim memory _claim = claims[beneficiary];
        return _claim.unlockedAmount + _claim.lock.totalAmount;
    }

    /**
     * @dev Returns the lock schedule of a given beneficiary.
     * @return the lock schedule object of a claim
     */
    function getClaimLockSchedule(address beneficiary)
        external
        view
        returns (IERC20SOUL.Schedule[] memory)
    {
        return claims[beneficiary].lock.schedules;
    }
}


// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

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


// SPDX-License-Identifier: MIT

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


// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

/// @title ERC20SOUL - An ERC20 extension that enables the transfer of
/// tokens alongside locking periods that can be applied to subsets of
/// the total transfer amount. This implementation also allows the owner
/// to specify staking contract addresses that locked addresses can 
/// interact with.
/// @author Bridger Zoske - <[email protected]>
interface IERC20SOUL {
    /*
     *  Events
     */
    event LockedTransfer(
        Lock lock,
        address sender,
        address recipient
    );

    event LockExpired(
        address owner,
        Lock lock
    );

    event LockScheduleExpired(
        address owner,
        Lock lock
    );

    struct Lock {
        uint256 totalAmount;
        uint256 amountStaked;
        Schedule[] schedules;
    }

    struct Schedule {
        uint256 amount;
        uint256 expirationBlock;
    }

    /// @dev external function to get minimum lock time
    function getMinLockTime() external view returns (uint256);

    /// @dev external function to get maximum lock time
    function getMaxLockTime() external view returns (uint256);

    /// @dev external function to get maximum number of schedules per lock
    function getMaxSchedules() external view returns (uint256);

    /// @dev Creates a valid recipient lock after transfering tokens
    /// @param _to address to send tokens to
    /// @param _lock valid lock data associated with transfer
    function transferWithLock(address _to, Lock calldata _lock) external;

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

// SPDX-License-Identifier: MIT

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


// SPDX-License-Identifier: MIT

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

    function __ReentrancyGuard_init() internal initializer {
        __ReentrancyGuard_init_unchained();
    }

    function __ReentrancyGuard_init_unchained() internal initializer {
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
    uint256[49] private __gap;
}