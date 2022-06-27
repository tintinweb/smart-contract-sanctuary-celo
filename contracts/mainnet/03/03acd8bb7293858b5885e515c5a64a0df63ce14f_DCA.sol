//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./IExchange.sol";

contract DCA {
    address cUSDAddress;
    IExchange cUSDExchange;

    struct Order {
        IERC20 sellToken;
        IERC20 buyToken;
        uint256 total;
        uint256 spent;
        uint256 amountPerPurchase;
        uint256 blocksBetweenPurchases;
        uint256 lastBlock;
    }

    mapping(address => Order[]) public orders;

    event OrderCreated(
        address indexed userAddress,
        uint256 index,
        uint256 total,
        IERC20 sellToken,
        IERC20 buyToken,
        uint256 amountPerPurchase,
        uint256 blocksBetweenPurchases
    );

    constructor(address _cUSDAddress, IExchange _cUSDExchange) {
        cUSDAddress = _cUSDAddress;
        cUSDExchange = _cUSDExchange;
    }

    function getUserOrders(address userAddress)
        external
        view
        returns (Order[] memory)
    {
        return orders[userAddress];
    }

    function getOrder(address userAddress, uint256 index)
        external
        view
        returns (Order memory)
    {
        return orders[userAddress][index];
    }

    function createOrder(
        IERC20 _sellToken,
        IERC20 _buyToken,
        uint256 _total,
        uint256 _amountPerPurchase,
        uint256 _blocksBetweenPurchases
    ) external returns (uint256 index) {
        require(
            _sellToken.transferFrom(msg.sender, address(this), _total),
            "DCA: Not enough funds"
        );

        Order memory newOrder = Order(
            _sellToken,
            _buyToken,
            _total,
            0,
            _amountPerPurchase,
            _blocksBetweenPurchases,
            0
        );

        index = orders[msg.sender].length;
        orders[msg.sender].push(newOrder);

        emit OrderCreated(
            msg.sender,
            index,
            _total,
            _sellToken,
            _buyToken,
            _amountPerPurchase,
            _blocksBetweenPurchases
        );
    }

    function executeOrder(address userAddress, uint256 index) external {
        Order storage order = orders[userAddress][index];

        require(
            order.lastBlock + order.blocksBetweenPurchases <= block.number,
            "DCA: Not enough time passed yet."
        );
        require(
            order.spent + order.amountPerPurchase <= order.total,
            "DCA: Order fully executed"
        );

        order.spent += order.amountPerPurchase;
        order.lastBlock = block.number;

        IExchange exchange = getMentoExchange(order.sellToken);

        order.sellToken.approve(address(exchange), order.amountPerPurchase);

        // TODO: Arreglar el 0, esto no puede subirse a ningún lado así.
        uint256 boughtAmount = exchange.sell(order.amountPerPurchase, 0, false);
        require(
            order.buyToken.transfer(userAddress, boughtAmount),
            "DCA: buyToken transfer failed"
        );
    }

    function withdraw(uint256 index) external {
        Order storage order = orders[msg.sender][index];

        uint256 amountToWithdraw = order.total - order.spent;
        order.spent = order.total;

        require(
            order.sellToken.transfer(msg.sender, amountToWithdraw),
            "DCA: Not enough funds to withdraw"
        );
    }

    function getMentoExchange(IERC20 token) internal view returns (IExchange) {
        if (address(token) == cUSDAddress) {
            return cUSDExchange;
        }
        revert("DCA: Exchange not found");
    }
}


//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

interface IExchange {
  // function buy(uint256, uint256, bool) external returns (uint256);
  function sell(uint256, uint256, bool) external returns (uint256);
  // function exchange(uint256, uint256, bool) external returns (uint256);
  // function setUpdateFrequency(uint256) external;
  // function getBuyTokenAmount(uint256, bool) external view returns (uint256);
  // function getSellTokenAmount(uint256, bool) external view returns (uint256);
  // function getBuyAndSellBuckets(bool) external view returns (uint256, uint256);
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