//SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "./ubeswap-farming/contracts/Owned.sol";
import "./IRevoFees.sol";

contract RevoFees is Owned, IRevoFees {
    // compounder fee: a performance fee (taken from farming rewards) to compensate someone who calls 'compound' method
    //  on a Revo Farm Bot. This is necessary because compounders incur gas costs and help users get compound interest
    //  (since the 'compound' method re-invests their farming rewards into the farm)
    uint256 public compounderFeeNumerator;
    uint256 public compounderFeeDenominator;

    // reserve fee: a performance fee (taken from farming rewards) sent to Revo reserves, to fund future development
    uint256 public reserveFeeNumerator;
    uint256 public reserveFeeDenominator;

    event CompounderFeeUpdated(
        address indexed by,
        uint256 compounderFeeNumerator,
        uint256 compounderFeeDenominator
    );
    event ReserveFeeUpdated(
        address indexed by,
        uint256 reserveFeeNumerator,
        uint256 reserveFeeDenominator
    );

    constructor(
        address _owner,
        uint256 _compounderFeeNumerator,
        uint256 _compounderFeeDenominator,
        uint256 _reserveFeeNumerator,
        uint256 _reserveFeeDenominator
    ) Owned(_owner) {
        compounderFeeNumerator = _compounderFeeNumerator;
        compounderFeeDenominator = _compounderFeeDenominator;
        reserveFeeNumerator = _reserveFeeNumerator;
        reserveFeeDenominator = _reserveFeeDenominator;
    }

    function updateCompounderFee(
        uint256 _compounderFeeNumerator,
        uint256 _compounderFeeDenominator
    ) external onlyOwner {
        compounderFeeNumerator = _compounderFeeNumerator;
        compounderFeeDenominator = _compounderFeeDenominator;
        emit CompounderFeeUpdated(
            msg.sender,
            _compounderFeeNumerator,
            _compounderFeeDenominator
        );
    }

    function updateReserveFee(
        uint256 _reserveFeeNumerator,
        uint256 _reserveFeeDenominator
    ) external onlyOwner {
        reserveFeeNumerator = _reserveFeeNumerator;
        reserveFeeDenominator = _reserveFeeDenominator;
        emit ReserveFeeUpdated(
            msg.sender,
            _reserveFeeNumerator,
            _reserveFeeDenominator
        );
    }

    /*
     * Check what the bonus will be for calling 'compound' on a Revo Farm Bot.
     *
     * In the future, bonuses may be issued to compounders that are not taken as performance fees. (Could be governance
     *   tokens, or issued from a community fund.) This may help us lower or eliminate the compounder fee.
     */
    function compounderBonus(TokenAmount memory _interestAccrued)
        external
        pure
        override
        returns (TokenAmount[] memory output)
    {
        return new TokenAmount[](0); // intentionally returns empty list
    }

    function compounderFee(uint256 _interestAccrued)
        external
        view
        override
        returns (uint256)
    {
        return
            (_interestAccrued * compounderFeeNumerator) /
            compounderFeeDenominator;
    }

    function reserveFee(uint256 _interestAccrued)
        external
        view
        override
        returns (uint256)
    {
        return (_interestAccrued * reserveFeeNumerator) / reserveFeeDenominator;
    }

    /*
     * Issue the bonus for calling 'compound' on a Revo Farm Bot.
     */
    function issueCompounderBonus(address recipient) external pure override {
        return; // intentionally does nothing
    }

    /*
     * Check the fee for withdrawing funds from a Revo Farm Bot.
     *
     * Withdrawal fees are used to prevent bad actors from depositing right before 'compound' is called, then withdrawing
     *   right after and taking some of the rewards. (Withdrawal fee should be >= the interest gained from the last time
     *   'compound' was called.)
     *
     * Takes the interest earned the last time 'compound' was called as a parameter. This makes it possible to have dynamic
     *   withdrawal fees.
     *
     * (Note that there is a maximum fee set in the Farm Bot contract to protect
     *   users from unreasonably high withdrawal fees.)
     */
    function withdrawalFee(
        uint256 interestEarnedNumerator,
        uint256 interestEarnedDenominator
    )
        external
        pure
        override
        returns (uint256 feeNumerator, uint256 feeDenominator)
    {
        // 0.25% (ignores interest earned for simplicity)
        feeNumerator = 25;
        feeDenominator = 10000;
    }
}


// SPDX-License-Identifier: MIT

pragma solidity ^0.8.3;


// https://docs.synthetix.io/contracts/source/contracts/owned
contract Owned {
    address public owner;
    address public nominatedOwner;

    constructor(address _owner) {
        require(_owner != address(0), "Owner address cannot be 0");
        owner = _owner;
        emit OwnerChanged(address(0), _owner);
    }

    function nominateNewOwner(address _owner) external onlyOwner {
        nominatedOwner = _owner;
        emit OwnerNominated(_owner);
    }

    function acceptOwnership() external {
        require(msg.sender == nominatedOwner, "You must be nominated before you can accept ownership");
        emit OwnerChanged(owner, nominatedOwner);
        owner = nominatedOwner;
        nominatedOwner = address(0);
    }

    modifier onlyOwner {
        _onlyOwner();
        _;
    }

    function _onlyOwner() private view {
        require(msg.sender == owner, "Only the contract owner may perform this action");
    }

    event OwnerNominated(address newOwner);
    event OwnerChanged(address oldOwner, address newOwner);
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
    function transfer(address recipient, uint256 amount)
        external
        returns (bool);

    /**
     * @dev Returns the remaining number of tokens that `spender` will be
     * allowed to spend on behalf of `owner` through {transferFrom}. This is
     * zero by default.
     *
     * This value changes when {approve} or {transferFrom} are called.
     */
    function allowance(address owner, address spender)
        external
        view
        returns (uint256);

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
    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );
}


//SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "./openzeppelin-solidity/contracts/IERC20.sol";

struct TokenAmount {
    IERC20 token;
    uint256 amount;
}

interface IRevoFees {
    function compounderFee(uint256 _interestAccrued)
        external
        view
        returns (uint256);

    function compounderBonus(TokenAmount calldata interestAccrued)
        external
        view
        returns (TokenAmount[] memory);

    function reserveFee(uint256 _interestAccrued)
        external
        view
        returns (uint256);

    function withdrawalFee(
        uint256 interestEarnedNumerator,
        uint256 interestEarnedDenominator
    ) external view returns (uint256 feeNumerator, uint256 feeDenominator);

    function issueCompounderBonus(address recipient) external;
}