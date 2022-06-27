//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "./interfaces/ISwapper.sol";
import "./interfaces/IOracle.sol";

contract DCA is Ownable {
    uint256 public constant BLOCKS_PER_DAY = 17280;
    uint256 public constant MAX_FEE_NUMERATOR = 6_000; // max 60 bps.
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
    event SwappedWithdrawal(
        address indexed userAddress,
        uint256 indexed index,
        address indexed token,
        uint256 amount
    );
    event RemainingWithdrawal(
        address indexed userAddress,
        uint256 indexed index,
        address indexed token,
        uint256 amount
    );
    event TokenPairInitialized(address sellToken, address buyToken);
    event EmergencyWithdrawal(address token, uint256 amount, address to);
    event OracleSet(address oracle);
    event OracleAddressMappingSet(address from, address to);
    event BeneficiarySet(address newBeneficiary);
    event FeeNumeratorSet(uint256 feeNumerator);

    struct UserOrder {
        IERC20 sellToken;
        IERC20 buyToken;
        uint256 amountPerSwap;
        uint256 numberOfSwaps;
        uint256 startingPeriod;
        uint256 lastPeriodWithdrawal;
    }

    struct SwapOrder {
        uint256 amountToSwap;
        uint256 lastPeriod;
        // For each past period, what exchange rate was used.
        mapping(uint256 => uint256) swapExchangeRates;
        // For each future period, how much to reduce to |amountToSwap|.
        mapping(uint256 => uint256) amountsToReduce;
        // The fee numerator used on each period's swap.
        mapping(uint256 => uint256) feeOnPeriod;
    }

    // sellToken => buyToken => SwapOrder
    mapping(address => mapping(address => SwapOrder)) public swapOrders;
    // userAddress => UserOrder list
    mapping(address => UserOrder[]) public orders;
    // For cUSD, we need to use mcUSD in the oracle because of Ubeswap liquidity. Same with cEUR/cREAL.
    mapping(address => address) public oracleAddresses;

    uint256 public feeNumerator;
    address public beneficiary;
    Oracle public oracle;

    constructor(
        Oracle _oracle,
        address _beneficiary,
        uint256 initialFee
    ) {
        setOracle(_oracle);
        setBeneficiary(_beneficiary);
        setFeeNumerator(initialFee);
    }

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

        SwapOrder storage swapOrder = swapOrders[address(_sellToken)][
            address(_buyToken)
        ];
        if (swapOrder.lastPeriod == 0) {
            swapOrder.lastPeriod = getCurrentPeriod() - 1;
            emit TokenPairInitialized(address(_sellToken), address(_buyToken));
        }
        uint256 startingPeriod = swapOrder.lastPeriod + 1;
        UserOrder memory newOrder = UserOrder(
            _sellToken,
            _buyToken,
            _amountPerSwap,
            _numberOfSwaps,
            startingPeriod,
            swapOrder.lastPeriod
        );

        swapOrder.amountToSwap += _amountPerSwap;
        swapOrder.amountsToReduce[
            startingPeriod + _numberOfSwaps - 1
        ] += _amountPerSwap;

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

    function executeOrder(
        address _sellToken,
        address _buyToken,
        uint256 _period,
        address _swapper,
        bytes memory _params
    ) external {
        SwapOrder storage swapOrder = swapOrders[_sellToken][_buyToken];
        require(swapOrder.lastPeriod + 1 == _period, "DCA: Invalid period");
        require(
            _period <= getCurrentPeriod(),
            "DCA: Period cannot be in the future"
        );
        uint256 fee = (swapOrder.amountToSwap * feeNumerator) / FEE_DENOMINATOR;
        uint256 swapAmount = swapOrder.amountToSwap - fee;

        uint256 requiredAmount = oracle.consult(
            getOracleTokenAddress(_sellToken),
            swapAmount,
            getOracleTokenAddress(_buyToken)
        );
        require(requiredAmount > 0, "DCA: Oracle failure");

        swapOrder.lastPeriod++;
        swapOrder.swapExchangeRates[_period] =
            (requiredAmount * 1e18) /
            swapAmount;
        swapOrder.amountToSwap -= swapOrder.amountsToReduce[_period];
        swapOrder.feeOnPeriod[_period] = feeNumerator;

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

    function withdrawAll(uint256 index) external {
        withdrawSwapped(index);

        UserOrder storage order = orders[msg.sender][index];
        SwapOrder storage swapOrder = swapOrders[address(order.sellToken)][
            address(order.buyToken)
        ];

        uint256 finalPeriod = order.startingPeriod + order.numberOfSwaps - 1;

        if (finalPeriod > swapOrder.lastPeriod) {
            swapOrder.amountToSwap -= order.amountPerSwap;
            swapOrder.amountsToReduce[finalPeriod] -= order.amountPerSwap;
            uint256 amountToWithdraw = order.amountPerSwap *
                (finalPeriod - swapOrder.lastPeriod);
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

    function emergencyWithdrawal(IERC20 token, address to) external onlyOwner {
        uint256 balance = token.balanceOf(address(this));
        require(token.transfer(to, balance), "DCA: Emergency transfer failed");
        emit EmergencyWithdrawal(address(token), balance, to);
    }

    // Parameter setters

    function setOracle(Oracle _newOracle) public onlyOwner {
        oracle = _newOracle;
        emit OracleSet(address(oracle));
    }

    function setBeneficiary(address _beneficiary) public onlyOwner {
        beneficiary = _beneficiary;
        emit BeneficiarySet(_beneficiary);
    }

    function setFeeNumerator(uint256 _feeNumerator) public onlyOwner {
        feeNumerator = _feeNumerator;
        emit FeeNumeratorSet(_feeNumerator);
    }

    function addAddressMapping(address _from, address _to) external onlyOwner {
        oracleAddresses[_from] = _to;
        emit OracleAddressMappingSet(_from, _to);
    }

    // Views

    function calculateAmountToWithdraw(UserOrder memory order)
        public
        view
        returns (uint256 amountToWithdraw, uint256 finalPeriod)
    {
        SwapOrder storage swapOrder = swapOrders[address(order.sellToken)][
            address(order.buyToken)
        ];
        finalPeriod = Math.min(
            swapOrder.lastPeriod,
            order.startingPeriod + order.numberOfSwaps - 1
        );
        amountToWithdraw = 0;
        for (
            uint256 period = order.lastPeriodWithdrawal + 1;
            period <= finalPeriod;
            period++
        ) {
            uint256 periodSwapAmount = (swapOrder.swapExchangeRates[period] *
                order.amountPerSwap) / 1e18;
            uint256 fee = (periodSwapAmount * feeNumerator) / FEE_DENOMINATOR;
            amountToWithdraw += periodSwapAmount - fee;
        }
    }

    function calculateAmountWithdrawn(UserOrder memory order)
        public
        view
        returns (uint256 amountWithdrawn)
    {
        SwapOrder storage swapOrder = swapOrders[address(order.sellToken)][
            address(order.buyToken)
        ];

        amountWithdrawn = 0;
        for (
            uint256 period = order.startingPeriod;
            period <= order.lastPeriodWithdrawal;
            period++
        ) {
            uint256 periodWithdrawAmount = (swapOrder.swapExchangeRates[
                period
            ] * order.amountPerSwap) / 1e18;
            uint256 fee = (periodWithdrawAmount * feeNumerator) /
                FEE_DENOMINATOR;
            amountWithdrawn += periodWithdrawAmount - fee;
        }
    }

    function getUserOrders(address userAddress)
        external
        view
        returns (UserOrder[] memory)
    {
        return orders[userAddress];
    }

    function getUserOrdersWithExtras(address userAddress)
        external
        view
        returns (
            UserOrder[] memory,
            uint256[] memory,
            uint256[] memory,
            uint256[] memory,
            uint256
        )
    {
        UserOrder[] memory userOrders = orders[userAddress];
        uint256[] memory ordersLastPeriod = new uint256[](userOrders.length);
        uint256[] memory amountsToWithdraw = new uint256[](userOrders.length);
        uint256[] memory amountsWithdrawn = new uint256[](userOrders.length);

        for (uint256 i = 0; i < userOrders.length; i++) {
            UserOrder memory order = userOrders[i];
            (
                uint256 amountToWithdraw,
                uint256 finalPeriod
            ) = calculateAmountToWithdraw(order);
            ordersLastPeriod[i] = finalPeriod;
            amountsToWithdraw[i] = amountToWithdraw;
            amountsWithdrawn[i] = calculateAmountWithdrawn(order);
        }

        return (
            userOrders,
            ordersLastPeriod,
            amountsToWithdraw,
            amountsWithdrawn,
            getCurrentPeriod()
        );
    }

    function getOrder(address userAddress, uint256 index)
        external
        view
        returns (UserOrder memory)
    {
        return orders[userAddress][index];
    }

    function getSwapOrderAmountToReduce(
        address _sellToken,
        address _buyToken,
        uint256 _period
    ) external view returns (uint256) {
        return swapOrders[_sellToken][_buyToken].amountsToReduce[_period];
    }

    function getSwapOrderExchangeRate(
        address _sellToken,
        address _buyToken,
        uint256 _period
    ) external view returns (uint256) {
        return swapOrders[_sellToken][_buyToken].swapExchangeRates[_period];
    }

    function getOracleTokenAddress(address token)
        public
        view
        returns (address)
    {
        address mappedToken = oracleAddresses[token];
        if (mappedToken != address(0)) {
            return mappedToken;
        } else {
            return token;
        }
    }

    function getCurrentPeriod() public view returns (uint256 period) {
        period = block.number / BLOCKS_PER_DAY;
    }
}


pragma solidity ^0.8.0;

interface Oracle {
    function consult(
        address tokenIn,
        uint256 amountIn,
        address tokenOut
    ) external view returns (uint256 amountOut);
}


//SPDX-License-Identifier: Unlicense
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