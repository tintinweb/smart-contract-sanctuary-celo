// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "./interfaces/ISwapper.sol";
import "./interfaces/IOracle.sol";

/// @title DCA
/// This contract allows users to deposit one token and gradually swaps it for another one
/// every day at the price it's trading at, allowing user to buy the target token using a
/// Dollar-Cost Averaging (DCA) strategy.
/// @dev To perform the swaps, we aggregate the tokens for all the users and make one big
/// swap instead of many small ones.
contract DCA is Ownable {
    /// Number of blocks in a day assuming 5 seconds per block. Works for the Celo blockchain.
    uint256 public constant BLOCKS_PER_DAY = 17280;
    /// Upper limit of the fee that can be charged on swaps. Has to be divided by
    /// |FEE_DENOMINATOR|. Equivalent to 60bps.
    uint256 public constant MAX_FEE_NUMERATOR = 6_000;
    uint256 public constant FEE_DENOMINATOR = 1_000_000;

    event OrderCreated(
        address indexed userAddress,
        uint256 index,
        IERC20 indexed sellToken,
        IERC20 indexed buyToken,
        uint256 amountPerSwap,
        uint256 numberOfSwaps,
        uint256 startingPeriod
    );
    event SwapExecuted(
        address indexed sellToken,
        address indexed buyToken,
        uint256 sellAmount,
        uint256 buyAmount,
        uint256 indexed period
    );
    /// Emitted when a user withdraws the funds that were already swapped.
    event SwappedWithdrawal(
        address indexed userAddress,
        uint256 indexed index,
        address indexed token,
        uint256 amount
    );
    /// Emitted when a user withdraws their principal early. ie. before it was swapped.
    event RemainingWithdrawal(
        address indexed userAddress,
        uint256 indexed index,
        address indexed token,
        uint256 amount
    );
    event TokenPairInitialized(address sellToken, address buyToken);
    event EmergencyWithdrawal(address token, uint256 amount, address to);
    event OracleUpdaterChanged(address oracleUpdater);
    event OracleSet(address oracle);
    event BeneficiarySet(address newBeneficiary);
    event FeeNumeratorSet(uint256 feeNumerator);

    /// Contains information about one specific user order.
    /// A period is defined as a block number divided by |BLOCKS_PER_DAY|.
    struct UserOrder {
        IERC20 sellToken;
        IERC20 buyToken;
        uint256 amountPerSwap;
        uint256 numberOfSwaps;
        uint256 startingPeriod;
        uint256 lastPeriodWithdrawal;
    }

    /// Contains information about the swapping status of a token pair.
    struct SwapState {
        uint256 amountToSwap;
        uint256 lastSwapPeriod;
    }

    /// For a given (sellToken, buyToken, period) tuple it returns the exchange rate used (if
    /// the period is in the past), how many daily swap tokens have their last day on that period
    /// and the fee charged in the period if it's in the past.
    struct PeriodSwapState {
        /// For each past period, what exchange rate was used.
        uint256 exchangeRate;
        /// For each future period, how much to reduce to |amountToSwap| in its SwapState.
        uint256 amountToReduce;
        /// For past periods, the fee numerator used on the swap.
        uint256 feeNumerator;
    }

    /// Contains the state of a token pair swaps. For a given (sellToken, buyToken)
    /// it contains how much it should swap in the next period and when the last period was.
    mapping(address => mapping(address => SwapState)) public swapStates;
    /// Contains information related to swaps for a (sellToken, buyToken, period) tuple.
    /// See |PeriodSwapState| for more info.
    mapping(address => mapping(address => mapping(uint256 => PeriodSwapState)))
        public periodsSwapStates;
    /// A list of |UserOrder| for each user address.
    mapping(address => UserOrder[]) public orders;

    /// Active fee on swaps. To be used together with |FEE_DENOMINATOR|.
    uint256 public feeNumerator;
    /// Where to send the fees.
    address public beneficiary;
    /// Oracle to use to get the amount to receive on swaps.
    Oracle public oracle;
    /// If true, the owner can withdraw funds. Should be turned off after there is sufficient confidence
    /// in the code, for example after audits.
    bool public guardrailsOn;
    /// Address that can update the oracle. Matches the owner at first, but should be operated by the
    /// community after a while.
    address public oracleUpdater;

    /// @dev Throws if called by any account other than the oracle updater.
    modifier onlyOracleUpdater() {
        require(
            oracleUpdater == msg.sender,
            "DCA: caller is not the oracle updater"
        );
        _;
    }

    constructor(
        Oracle _oracle,
        address _beneficiary,
        uint256 initialFee
    ) {
        guardrailsOn = true;
        oracleUpdater = msg.sender;
        setOracle(_oracle);
        setBeneficiary(_beneficiary);
        setFeeNumerator(initialFee);
    }

    /// Starts a new DCA position for the |msg.sender|. When creating a new position, we
    /// add the |_amountPerSwap| to the |amountToSwap| variable on |SwapState| and to
    /// |amountToReduce| on the final period's |PeriodSwapState|. Thus, the amount to swap
    /// daily will increase between the current period and the final one.
    /// @param _sellToken token to sell on each period.
    /// @param _buyToken token to buy on each period.
    /// @param _amountPerSwap amount of _sellToken to sell each period.
    /// @param _numberOfSwaps number of periods to do the swapping.
    function createOrder(
        IERC20 _sellToken,
        IERC20 _buyToken,
        uint256 _amountPerSwap,
        uint256 _numberOfSwaps
    ) external returns (uint256 index) {
        require(
            _sellToken.transferFrom(
                msg.sender,
                address(this),
                _amountPerSwap * _numberOfSwaps
            ),
            "DCA: Not enough funds"
        );

        SwapState storage swapState = swapStates[address(_sellToken)][
            address(_buyToken)
        ];
        // If it's the first order for this pair, initialize it.
        if (swapState.lastSwapPeriod == 0) {
            swapState.lastSwapPeriod = getCurrentPeriod() - 1;
            emit TokenPairInitialized(address(_sellToken), address(_buyToken));
        }
        uint256 startingPeriod = swapState.lastSwapPeriod + 1;
        UserOrder memory newOrder = UserOrder(
            _sellToken,
            _buyToken,
            _amountPerSwap,
            _numberOfSwaps,
            startingPeriod,
            swapState.lastSwapPeriod
        );

        swapState.amountToSwap += _amountPerSwap;
        periodsSwapStates[address(_sellToken)][address(_buyToken)][
            startingPeriod + _numberOfSwaps - 1
        ].amountToReduce += _amountPerSwap;

        index = orders[msg.sender].length;
        orders[msg.sender].push(newOrder);

        emit OrderCreated(
            msg.sender,
            index,
            _sellToken,
            _buyToken,
            _amountPerSwap,
            _numberOfSwaps,
            startingPeriod
        );
    }

    /// Executes a swap between two tokens. The period must be the last executed + 1.
    /// The swapping is done by the |_swapper|. We calculate the required exchange rate using
    /// an oracle, send them the funds to swap and expect them to return the calculated return
    /// amount. This allows us to more easily add pairs since we just need the oracle support,
    /// not the exact routes to follow. Callers are incentivized to call this function for
    /// the arbitrage opportunity.
    ///
    /// In other words, the general logic followed here is:
    /// - Calculate and send the fee to the |beneficiary|.
    /// - Calculate the exchange rate using |oracle|.
    /// - Send the swap amount to |_swapper| can call its |swap| function.
    /// - Check that it returned the required funds taking the exchange rate into account.
    /// @param _sellToken token to sell on the swap.
    /// @param _buyToken token to buy on the swap.
    /// @param _period period to perform the swap for. It has only one possible valid
    /// value, so it is not strictly necessary.
    /// @param _swapper address that will perform the swap.
    /// @param _params params to send to |_swapper| for performing the swap.
    function executeOrder(
        address _sellToken,
        address _buyToken,
        uint256 _period,
        address _swapper,
        bytes memory _params
    ) external {
        SwapState storage swapState = swapStates[_sellToken][_buyToken];
        require(swapState.lastSwapPeriod + 1 == _period, "DCA: Invalid period");
        require(
            _period <= getCurrentPeriod(),
            "DCA: Period cannot be in the future"
        );
        uint256 fee = (swapState.amountToSwap * feeNumerator) / FEE_DENOMINATOR;
        uint256 swapAmount = swapState.amountToSwap - fee;

        uint256 requiredAmount = oracle.consult(
            _sellToken,
            swapAmount,
            _buyToken
        );
        require(requiredAmount > 0, "DCA: Oracle failure");

        PeriodSwapState storage periodSwapState = periodsSwapStates[_sellToken][
            _buyToken
        ][_period];

        swapState.lastSwapPeriod++;
        swapState.amountToSwap -= periodSwapState.amountToReduce;
        periodSwapState.exchangeRate = (requiredAmount * 1e27) / swapAmount;
        periodSwapState.feeNumerator = feeNumerator;

        require(
            IERC20(_sellToken).transfer(beneficiary, fee),
            "DCA: Fee transfer to beneficiary failed"
        );

        uint256 balanceBefore = IERC20(_buyToken).balanceOf(address(this));
        require(
            IERC20(_sellToken).transfer(_swapper, swapAmount),
            "DCA: Transfer to Swapper failed"
        );
        ISwapper(_swapper).swap(
            _sellToken,
            _buyToken,
            swapAmount,
            requiredAmount,
            _params
        );
        require(
            balanceBefore + requiredAmount <=
                IERC20(_buyToken).balanceOf(address(this)),
            "DCA: Not enough balance returned"
        );

        emit SwapExecuted(
            _sellToken,
            _buyToken,
            swapAmount,
            requiredAmount,
            _period
        );
    }

    /// Withdraw the funds that were already swapped for the caller user.
    /// @param index the index of the |orders| array for msg.sender.
    function withdrawSwapped(uint256 index) public {
        UserOrder storage order = orders[msg.sender][index];
        (
            uint256 amountToWithdraw,
            uint256 finalPeriod
        ) = calculateAmountToWithdraw(order);
        order.lastPeriodWithdrawal = finalPeriod;

        require(
            order.buyToken.transfer(msg.sender, amountToWithdraw),
            "DCA: Not enough funds to withdraw"
        );

        emit SwappedWithdrawal(
            msg.sender,
            index,
            address(order.buyToken),
            amountToWithdraw
        );
    }

    /// Withdraw the funds that were already swapped for the caller user AND the
    /// funds that were not swapped yet, effectively terminating the position.
    /// @param index the index of the |orders| array for msg.sender.
    function withdrawAll(uint256 index) external {
        withdrawSwapped(index);

        UserOrder storage order = orders[msg.sender][index];
        SwapState storage swapState = swapStates[address(order.sellToken)][
            address(order.buyToken)
        ];

        uint256 finalPeriod = order.startingPeriod + order.numberOfSwaps - 1;

        if (finalPeriod > swapState.lastSwapPeriod) {
            PeriodSwapState storage finalPeriodSwapState = periodsSwapStates[
                address(order.sellToken)
            ][address(order.buyToken)][finalPeriod];

            swapState.amountToSwap -= order.amountPerSwap;
            finalPeriodSwapState.amountToReduce -= order.amountPerSwap;
            uint256 amountToWithdraw = order.amountPerSwap *
                (finalPeriod - swapState.lastSwapPeriod);
            order.lastPeriodWithdrawal = finalPeriod;

            require(
                order.sellToken.transfer(msg.sender, amountToWithdraw),
                "DCA: Not enough funds to withdraw"
            );

            emit RemainingWithdrawal(
                msg.sender,
                index,
                address(order.sellToken),
                amountToWithdraw
            );
        }
    }

    function turnOffGuardrails() external onlyOwner {
        guardrailsOn = false;
    }

    /// In case of emergency, in the beginning the owner can remove the funds to return them to users.
    /// Should be turned off before receiving any meaningful deposits by calling |turnOffGuardrails|.
    function emergencyWithdrawal(IERC20 token, address to) external onlyOwner {
        require(guardrailsOn, "DCA: Guardrails are off");
        uint256 balance = token.balanceOf(address(this));
        require(token.transfer(to, balance), "DCA: Emergency transfer failed");
        emit EmergencyWithdrawal(address(token), balance, to);
    }

    /// Change the address that can update the oracle.
    function setOracleUpdater(address _newOracleUpdater)
        external
        onlyOracleUpdater
    {
        oracleUpdater = _newOracleUpdater;
        emit OracleUpdaterChanged(_newOracleUpdater);
    }

    /// Update the oracle
    function setOracle(Oracle _newOracle) public onlyOracleUpdater {
        oracle = _newOracle;
        emit OracleSet(address(oracle));
    }

    /// Update the beneficiary
    function setBeneficiary(address _beneficiary) public onlyOwner {
        beneficiary = _beneficiary;
        emit BeneficiarySet(_beneficiary);
    }

    /// Update the fee
    function setFeeNumerator(uint256 _feeNumerator) public onlyOwner {
        require(_feeNumerator <= MAX_FEE_NUMERATOR, "DCA: Fee too high");
        feeNumerator = _feeNumerator;
        emit FeeNumeratorSet(_feeNumerator);
    }

    // From here to the bottom of the file are the view calls.

    /// Calculates hoy much |buyToken| is available to withdraw for a user order.
    /// Takes into account previous withdrawals and fee taken.
    function calculateAmountToWithdraw(UserOrder memory order)
        public
        view
        returns (uint256 amountToWithdraw, uint256 finalPeriod)
    {
        SwapState memory swapState = swapStates[address(order.sellToken)][
            address(order.buyToken)
        ];
        finalPeriod = Math.min(
            swapState.lastSwapPeriod,
            order.startingPeriod + order.numberOfSwaps - 1
        );
        amountToWithdraw = 0;
        for (
            uint256 period = order.lastPeriodWithdrawal + 1;
            period <= finalPeriod;
            period++
        ) {
            PeriodSwapState memory periodSwapState = periodsSwapStates[
                address(order.sellToken)
            ][address(order.buyToken)][period];
            uint256 periodSwapAmount = (periodSwapState.exchangeRate *
                order.amountPerSwap) / 1e27;
            uint256 fee = (periodSwapAmount * periodSwapState.feeNumerator) /
                FEE_DENOMINATOR;
            amountToWithdraw += periodSwapAmount - fee;
        }
    }

    function getCurrentPeriod() public view returns (uint256 period) {
        period = block.number / BLOCKS_PER_DAY;
    }

    function getUserOrders(address userAddress)
        external
        view
        returns (UserOrder[] memory)
    {
        return orders[userAddress];
    }

    function getSwapState(address sellToken, address buyToken)
        external
        view
        returns (SwapState memory)
    {
        return swapStates[sellToken][buyToken];
    }

    function getPeriodSwapState(
        address sellToken,
        address buyToken,
        uint256 period
    ) external view returns (PeriodSwapState memory) {
        return periodsSwapStates[sellToken][buyToken][period];
    }
}


// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ISwapper {
    function swap(
        address _sellToken,
        address _buyToken,
        uint256 _inAmount,
        uint256 _outAmount,
        bytes calldata _params
    ) external;
}


// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface Oracle {
    function consult(
        address tokenIn,
        uint256 amountIn,
        address tokenOut
    ) external view returns (uint256 amountOut);
}


// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v4.5.0) (utils/math/Math.sol)

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
// OpenZeppelin Contracts v4.4.1 (utils/Context.sol)

pragma solidity ^0.8.0;

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
abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        return msg.data;
    }
}


// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v4.6.0) (token/ERC20/IERC20.sol)

pragma solidity ^0.8.0;

/**
 * @dev Interface of the ERC20 standard as defined in the EIP.
 */
interface IERC20 {
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

    /**
     * @dev Returns the amount of tokens in existence.
     */
    function totalSupply() external view returns (uint256);

    /**
     * @dev Returns the amount of tokens owned by `account`.
     */
    function balanceOf(address account) external view returns (uint256);

    /**
     * @dev Moves `amount` tokens from the caller's account to `to`.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transfer(address to, uint256 amount) external returns (bool);

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
     * @dev Moves `amount` tokens from `from` to `to` using the
     * allowance mechanism. `amount` is then deducted from the caller's
     * allowance.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external returns (bool);
}


// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts v4.4.1 (security/Pausable.sol)

pragma solidity ^0.8.0;

import "../utils/Context.sol";

/**
 * @dev Contract module which allows children to implement an emergency stop
 * mechanism that can be triggered by an authorized account.
 *
 * This module is used through inheritance. It will make available the
 * modifiers `whenNotPaused` and `whenPaused`, which can be applied to
 * the functions of your contract. Note that they will not be pausable by
 * simply including this module, only once the modifiers are put in place.
 */
abstract contract Pausable is Context {
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
    constructor() {
        _paused = false;
    }

    /**
     * @dev Returns true if the contract is paused, and false otherwise.
     */
    function paused() public view virtual returns (bool) {
        return _paused;
    }

    /**
     * @dev Modifier to make a function callable only when the contract is not paused.
     *
     * Requirements:
     *
     * - The contract must not be paused.
     */
    modifier whenNotPaused() {
        require(!paused(), "Pausable: paused");
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
        require(paused(), "Pausable: not paused");
        _;
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
}


// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts v4.4.1 (access/Ownable.sol)

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
    constructor() {
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
}