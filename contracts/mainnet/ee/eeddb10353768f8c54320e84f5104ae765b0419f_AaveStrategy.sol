// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.7;

import "./IStrategy.sol";
import "../aave/ILendingPoolAddressesProvider.sol";
import "../aave/ILendingPool.sol";
import "../aave/AToken.sol";
import "../aave/IWETHGateway.sol";
import "../aave/IncentiveController.sol";
import "../polygon/WrappedToken.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

//*********************************************************************//
// --------------------------- custom errors ------------------------- //
//*********************************************************************//
error INVALID_DATA_PROVIDER();
error INVALID_LENDING_POOL_ADDRESS_PROVIDER();
error INVALID_TRANSACTIONAL_TOKEN_SENDER();
error TOKEN_TRANSFER_FAILURE();
error TRANSACTIONAL_TOKEN_TRANSFER_FAILURE();

/**
  @notice
  Interacts with Aave V2 protocol (or forks) to generate interest for the pool.
  This contract it's responsible for deposits and withdrawals to the external pool
  as well as getting the generated rewards and sending them back to the pool.
  @author Francis Odisi & Viraz Malhotra.
*/
contract AaveStrategy is Ownable, IStrategy {
    /// @notice Aave referral code
    uint16 constant REFERRAL_CODE = 155;

    /// @notice Address of the Aave V2 incentive controller contract
    IncentiveController public immutable incentiveController;

    /// @notice Address of the Aave V2 weth gateway contract
    IWETHGateway public immutable wethGateway;

    /// @notice Which Aave instance we use to swap Inbound Token to interest bearing aDAI
    ILendingPoolAddressesProvider public immutable lendingPoolAddressProvider;

    /// @notice Lending pool address
    ILendingPool public immutable lendingPool;

    /// @notice Atoken address
    AToken public immutable aToken;

    /// @notice AaveProtocolDataProvider address
    AaveProtocolDataProvider public dataProvider;

    /// @notice reward token address for eg wmatic in case of polygon deployment
    IERC20 public rewardToken;

    //*********************************************************************//
    // ------------------------- external views -------------------------- //
    //*********************************************************************//

    /** 
    @notice
    Get strategy owner address.
    @return Strategy owner.
    */
    function strategyOwner() external view override returns (address) {
        return super.owner();
    }

    /** 
    @notice
    Returns the total accumulated amount (i.e., principal + interest) stored in curve.
    Intended for usage by external clients and in case of variable deposit pools.
    @return Total accumulated amount.
    */
    function getTotalAmount() external view override returns (uint256) {
        return aToken.balanceOf(address(this));
    }

    /** 
    @notice
    Get the expected net deposit amount (amount minus slippage) for a given amount. Used only for AMM strategies.
    @return net amount.
    */
    function getNetDepositAmount(uint256 _amount) external pure override returns (uint256) {
        return _amount;
    }

    /** 
    @notice
    Returns the underlying inbound (deposit) token address.
    @return Underlying token address.
    */
    function getUnderlyingAsset() external view override returns (address) {
        return aToken.UNDERLYING_ASSET_ADDRESS();
    }

    /** 
    @notice
    Returns the instances of the reward tokens
    */
    function getRewardTokens() external view override returns (IERC20[] memory) {
        IERC20[] memory tokens = new IERC20[](1);
        tokens[0] = rewardToken;
        return tokens;
    }

    //*********************************************************************//
    // -------------------------- constructor ---------------------------- //
    //*********************************************************************//

    /** 
    @param _lendingPoolAddressProvider A contract which is used as a registry on aave.
    @param _wethGateway A contract which is used to make deposits/withdrawals on transaction token pool on aave.
    @param _dataProvider A contract which mints ERC-721's that represent project ownership and transfers.
    @param _incentiveController A contract which acts as a registry for reserve tokens on aave.
    @param _rewardToken A contract which acts as the reward token for this strategy.
    @param _inboundCurrency inbound currency address.
  */
    constructor(
        ILendingPoolAddressesProvider _lendingPoolAddressProvider,
        IWETHGateway _wethGateway,
        address _dataProvider,
        address _incentiveController,
        IERC20 _rewardToken,
        address _inboundCurrency
    ) {
        if (address(_lendingPoolAddressProvider) == address(0)) {
            revert INVALID_LENDING_POOL_ADDRESS_PROVIDER();
        }

        if (address(_dataProvider) == address(0)) {
            revert INVALID_DATA_PROVIDER();
        }

        lendingPoolAddressProvider = _lendingPoolAddressProvider;
        // address(0) for non-polygon deployment
        incentiveController = IncentiveController(_incentiveController);
        dataProvider = AaveProtocolDataProvider(_dataProvider);
        // lending pool needs to be approved in v2 since it is the core contract in v2 and not lending pool core
        lendingPool = ILendingPool(_lendingPoolAddressProvider.getLendingPool());
        wethGateway = _wethGateway;
        rewardToken = _rewardToken;
        address aTokenAddress;
        if (_inboundCurrency == address(0)) {
            (aTokenAddress, , ) = dataProvider.getReserveTokensAddresses(address(rewardToken));
        } else {
            (aTokenAddress, , ) = dataProvider.getReserveTokensAddresses(_inboundCurrency);
        }
        aToken = AToken(aTokenAddress);
    }

    /**
    @notice
    Deposits funds into aave.
    @param _inboundCurrency Address of the inbound token.
    @param _minAmount Used for aam strategies, since every strategy overrides from the same strategy interface hence it is defined here.
    _minAmount isn't needed in this strategy but since all strategies override from the same interface and the amm strategies need it hence it is used here.
    */
    function invest(address _inboundCurrency, uint256 _minAmount) external payable override onlyOwner {
        if (_inboundCurrency == address(0) || _inboundCurrency == address(rewardToken)) {
            if (_inboundCurrency == address(rewardToken)) {
                // unwraps WrappedToken back into Native Token
                // UPDATE - A6 Audit Report
                WrappedToken(address(rewardToken)).withdraw(IERC20(_inboundCurrency).balanceOf(address(this)));
            }
            // Deposits MATIC into the pool
            wethGateway.depositETH{ value: address(this).balance }(address(lendingPool), address(this), REFERRAL_CODE);
        } else {
            uint256 balance = IERC20(_inboundCurrency).balanceOf(address(this));
            IERC20(_inboundCurrency).approve(address(lendingPool), balance);
            lendingPool.deposit(_inboundCurrency, balance, address(this), REFERRAL_CODE);
        }
    }

    /**
    @notice
    Withdraws funds from aave in case of an early withdrawal.
    @param _inboundCurrency Address of the inbound token.
    @param _amount Amount to withdraw.
    @param _minAmount Used for aam strategies, since every strategy overrides from the same strategy interface hence it is defined here.
    _minAmount isn't needed in this strategy but since all strategies override from the same interface and the amm strategies need it hence it is used here.
    */
    function earlyWithdraw(
        address _inboundCurrency,
        uint256 _amount,
        uint256 _minAmount
    ) external override onlyOwner {
        if (_inboundCurrency == address(0) || _inboundCurrency == address(rewardToken)) {
            aToken.approve(address(wethGateway), _amount);

            wethGateway.withdrawETH(address(lendingPool), _amount, address(this));
            if (_inboundCurrency == address(rewardToken)) {
                // Wraps MATIC back into WMATIC
                WrappedToken(address(rewardToken)).deposit{ value: _amount }();
            }
        } else {
            lendingPool.withdraw(_inboundCurrency, _amount, address(this));
        }
        if (_inboundCurrency == address(0)) {
            (bool success, ) = msg.sender.call{ value: _amount }("");
            if (!success) {
                revert TRANSACTIONAL_TOKEN_TRANSFER_FAILURE();
            }
        } else {
            bool success = IERC20(_inboundCurrency).transfer(msg.sender, _amount);
            if (!success) {
                revert TOKEN_TRANSFER_FAILURE();
            }
        }
    }

    /**
    @notice
    Redeems funds from aave when the waiting round for the good ghosting pool is over.
    @param _inboundCurrency Address of the inbound token.
    @param _amount Amount to withdraw.
    @param _minAmount Used for aam strategies, since every strategy overrides from the same strategy interface hence it is defined here.
    _minAmount isn't needed in this strategy but since all strategies override from the same interface and the amm strategies need it hence it is used here.
    @param disableRewardTokenClaim Reward claim disable flag.
    */
    function redeem(
        address _inboundCurrency,
        uint256 _amount,
        uint256 _minAmount,
        bool disableRewardTokenClaim
    ) external override onlyOwner {
        // Withdraws funds (principal + interest + rewards) from external pool
        if (_inboundCurrency == address(0) || _inboundCurrency == address(rewardToken)) {
            aToken.approve(address(wethGateway), _amount);

            wethGateway.withdrawETH(address(lendingPool), _amount, address(this));
            if (_inboundCurrency == address(rewardToken)) {
                // Wraps MATIC back into WMATIC
                WrappedToken(address(rewardToken)).deposit{ value: address(this).balance }();
            }
        } else {
            lendingPool.withdraw(_inboundCurrency, _amount, address(this));
        }
        if (!disableRewardTokenClaim) {
            // Claims the rewards from the external pool
            address[] memory assets = new address[](1);
            assets[0] = address(aToken);

            if (address(rewardToken) != address(0)) {
                // safety check for external services calling this function.
                // Aave forks like Moola may not have an incentive controller (it is set to address(0)).
                uint256 claimableRewards = incentiveController.getRewardsBalance(assets, address(this));
                // moola the celo version of aave does not have the incentive controller logic
                if (claimableRewards != 0) {
                    incentiveController.claimRewards(assets, claimableRewards, address(this));
                }
                // moola the celo version of aave does not have the incentive controller logic
                if (rewardToken.balanceOf(address(this)) != 0) {
                    bool success = rewardToken.transfer(msg.sender, rewardToken.balanceOf(address(this)));
                    if (!success) {
                        revert TOKEN_TRANSFER_FAILURE();
                    }
                }
            }
        }

        if (_inboundCurrency == address(0)) {
            (bool txTokenTransferSuccessful, ) = msg.sender.call{ value: address(this).balance }("");
            if (!txTokenTransferSuccessful) {
                revert TRANSACTIONAL_TOKEN_TRANSFER_FAILURE();
            }
        } else {
            bool success = IERC20(_inboundCurrency).transfer(
                msg.sender,
                IERC20(_inboundCurrency).balanceOf(address(this))
            );
            if (!success) {
                revert TOKEN_TRANSFER_FAILURE();
            }
        }
    }

    /**
    @notice
    Returns total accumulated reward token amount.
    @param disableRewardTokenClaim Reward claim disable flag.
    */
    function getAccumulatedRewardTokenAmounts(bool disableRewardTokenClaim)
        external
        view
        override
        returns (uint256[] memory)
    {
        uint256 amount = 0;
        // safety check for external services calling this function.
        // Aave forks like Moola may not have an incentive controller (it is set to address(0)).
        if (!disableRewardTokenClaim && address(incentiveController) != address(0)) {
            // atoken address in v2 is fetched from data provider contract
            // Claims the rewards from the external pool
            address[] memory assets = new address[](1);
            assets[0] = address(aToken);
            amount = incentiveController.getRewardsBalance(assets, address(this));
        }
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;
        return amounts;
    }

    // Fallback Functions for calldata and reciever for handling only ether transfer
    // UPDATE - A7 Audit Report
    receive() external payable {
        if (msg.sender != address(rewardToken) && msg.sender != address(wethGateway)) {
            revert INVALID_TRANSACTIONAL_TOKEN_SENDER();
        }
    }
}


pragma solidity 0.8.7;

interface WrappedToken {
    function deposit() external payable;

    function withdraw(uint256 wad) external;

    function totalSupply() external view returns (uint256);

    function approve(address guy, uint256 wad) external returns (bool);

    function transfer(address dst, uint256 wad) external returns (bool);

    function transferFrom(
        address src,
        address dst,
        uint256 wad
    ) external returns (bool);
}


// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.7;

interface IncentiveController {
    function getRewardsBalance(address[] calldata assets, address user) external view returns (uint256);

    function claimRewards(
        address[] calldata assets,
        uint256 amount,
        address to
    ) external returns (uint256);
}


// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.7;

interface IWETHGateway {
    function depositETH(
        address lendingPool,
        address onBehalfOf,
        uint16 referralCode
    ) external payable;

    function withdrawETH(
        address lendingPool,
        uint256 amount,
        address to
    ) external;
}


// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.7;

abstract contract ILendingPoolAddressesProvider {
    function getLendingPool() public view virtual returns (address);

    function setLendingPoolImpl(address _pool) public virtual;

    function getAddress(bytes32 id) public view virtual returns (address);

    function getLendingPoolCore() public view virtual returns (address payable);

    function setLendingPoolCoreImpl(address _lendingPoolCore) public virtual;

    function getLendingPoolConfigurator() public view virtual returns (address);

    function setLendingPoolConfiguratorImpl(address _configurator) public virtual;

    function getLendingPoolDataProvider() public view virtual returns (address);

    function setLendingPoolDataProviderImpl(address _provider) public virtual;

    function getLendingPoolParametersProvider() public view virtual returns (address);

    function setLendingPoolParametersProviderImpl(address _parametersProvider) public virtual;

    function getTokenDistributor() public view virtual returns (address);

    function setTokenDistributor(address _tokenDistributor) public virtual;

    function getFeeProvider() public view virtual returns (address);

    function setFeeProviderImpl(address _feeProvider) public virtual;

    function getLendingPoolLiquidationManager() public view virtual returns (address);

    function setLendingPoolLiquidationManager(address _manager) public virtual;

    function getLendingPoolManager() public view virtual returns (address);

    function setLendingPoolManager(address _lendingPoolManager) public virtual;

    function getPriceOracle() public view virtual returns (address);

    function setPriceOracle(address _priceOracle) public virtual;

    function getLendingRateOracle() public view virtual returns (address);

    function setLendingRateOracle(address _lendingRateOracle) public virtual;
}


// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.7;

interface ILendingPool {
    function deposit(
        address _reserve,
        uint256 _amount,
        address onBehalfOf,
        uint16 _referralCode
    ) external;

    function withdraw(
        address asset,
        uint256 amount,
        address to
    ) external;
}

interface AaveProtocolDataProvider {
    function getReserveTokensAddresses(address asset)
        external
        view
        returns (
            address,
            address,
            address
        );
}


// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.7;

interface AToken {
    /**
     * @dev Returns the amount of tokens owned by `account`.
     */
    function balanceOf(address account) external view returns (uint256);

    function approve(address spender, uint256 amount) external returns (bool);

    function UNDERLYING_ASSET_ADDRESS() external view returns (address);
}


pragma solidity 0.8.7;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IStrategy {
    function invest(address _inboundCurrency, uint256 _minAmount) external payable;

    function earlyWithdraw(
        address _inboundCurrency,
        uint256 _amount,
        uint256 _minAmount
    ) external;

    function redeem(
        address _inboundCurrency,
        uint256 _amount,
        uint256 _minAmount,
        bool disableRewardTokenClaim
    ) external;

    function getTotalAmount() external view returns (uint256);

    function getNetDepositAmount(uint256 _amount) external view returns (uint256);

    function getAccumulatedRewardTokenAmounts(bool disableRewardTokenClaim) external returns (uint256[] memory);

    function getRewardTokens() external view returns (IERC20[] memory);

    function getUnderlyingAsset() external view returns (address);

    function strategyOwner() external view returns (address);
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