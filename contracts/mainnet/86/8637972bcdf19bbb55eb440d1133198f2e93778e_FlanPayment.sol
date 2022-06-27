// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.5;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

/*
 * FlanTokenStaking
 *
*/
contract FlanTokenStaking is Context, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    IERC20 private _token;
    uint256 private _decimal = 18;
    uint32 private _minLockDay = 7;

    uint256 public totalStakedAmount = 0;

    struct Member {
        uint256 totalAmount;
        uint32 actionTime;
    }


    mapping(address => Member) stakingAddressAmount;

    constructor(address token_) {
        require(token_ != address(0x0));
        _token = IERC20(token_);
    }

    /**
     * @dev Emitted on stake()
     * @param address_ member address
     * @param amount_ staked amount
     **/
    event Stake(address indexed address_, uint256 amount_);

    /**
     * @dev Emitted on withdrawAmount()
     * @param address_ member address
     * @param amount_ staked amount
     **/
    event WithdrawAmount(address indexed address_, uint256 amount_);

    event WithdrawAll(address indexed address_, uint256 amount_);

    function stake(uint256 amount_) external payable {
        require(msg.sender != address(0x0), "");
        require(amount_ > 0, "");
        if (stakingAddressAmount[msg.sender].totalAmount == 0) {
            stakingAddressAmount[msg.sender].totalAmount = amount_;
        } else {
            stakingAddressAmount[msg.sender].totalAmount += amount_;
        }
        stakingAddressAmount[msg.sender].actionTime = uint32(block.timestamp);

        _token.safeTransferFrom(msg.sender, address(this), amount_);
        totalStakedAmount += amount_;
        emit Stake(msg.sender, amount_);
    }

    function withdrawAmount(uint256 amount_) external payable {
        require(msg.sender != address(0x0), "Flan Staking: None address!");
        uint256 amount = _withdrawAmount(payable(msg.sender), amount_);
        totalStakedAmount -= amount;
        emit WithdrawAmount(msg.sender, amount);
    }

    function withdrawAll() external payable {
        require(msg.sender != address(0x0), "");
        uint256 amount = stakingAddressAmount[msg.sender].totalAmount;
        amount = _withdrawAmount(payable(msg.sender), amount);
        totalStakedAmount -= amount;
        emit WithdrawAll(msg.sender, amount);
    }

    function _withdrawAmount(address payable address_, uint256 amount_) internal virtual returns (uint256) {
        require(amount_ > 0, "Flan Staking: requested amount == 0");
        require(stakingAddressAmount[address_].totalAmount >= amount_, "Flan Staking: Balance < requested amount");
        require(_getCurrentTime() >= stakingAddressAmount[address_].actionTime + _minLockDay * 3600, "Flan Staking: Lock Period");
        _token.safeTransfer(msg.sender, amount_);
        stakingAddressAmount[msg.sender].totalAmount -= amount_;
        stakingAddressAmount[msg.sender].actionTime = uint32(block.timestamp);
        return amount_;
    }

    function getAmountOfMember(address address_) public view returns (uint256, uint32) {
        require(address_ != address(0x0), "");
        (uint256 amount, uint32 time) = _getAddressAmount(address_);
        return (amount, time);
    }

    function getAddressMinUnlockTime(address address_) public view returns (uint32) {
        require(address_ != address(0x0), "");
        return _getAddressMinUnlockTime(address_);
    }

    function _getAddressAmount(address address_) private view returns (uint256, uint32) {
        return (stakingAddressAmount[address_].totalAmount, stakingAddressAmount[address_].actionTime);
    }

    function _getAddressMinUnlockTime(address address_) private view returns (uint32) {
        return stakingAddressAmount[address_].actionTime + _minLockDay * 3600;
    }

    function setMinLockDay(uint32 minLockDay_) external onlyOwner {
        require(minLockDay_ > 36500, "Flan Staking: Too long");
        _minLockDay = minLockDay_;
    }

    function getMinLockDay() public view returns (uint32) {
        return _minLockDay;
    }

    function _getCurrentTime() private view returns (uint32) {
        return uint32(block.timestamp);
    }

    function getTotalStakedAmount() public view returns (uint256) {
        return totalStakedAmount;
    }

    function getTotalBalance() public view returns (uint256) {
        return _token.balanceOf(address(this));
    }
}


/*
 * FlanPayment
 *
*/
contract FlanPayment is Context, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    IERC20 public _flanToken;
    IERC20 public _cusdToken;
    uint256 private _decimal = 18;

    address public _stakingContractAddress;

    uint256 public _totalCUSDFeeAmount = 0;
    uint256 public _totalFLNFeeAmount = 0;
    uint256 public _CUSDTaxFeeAmount = 0;
    uint256 public _FLNTaxFeeAmount = 0;
    uint256 public _paymentId = 0;


    struct FeePlan {
        string name;
        uint256 minStakedAmount;
        uint256 cUSDFeePercent;
        uint256 flanFeePercent;
    }

    FeePlan[] feePlanList;

    struct PaymentData {
        string projectId;
        string taskId;
        address senderAddress;
        address receiptAddress;
        uint256 taskEstimate;
        uint256 feeAmount;
        bool isFLN;
    }

    mapping(uint256 => PaymentData) paymentDataList;

    event Paid(uint256 paymentId_, address indexed senderAddress_, address indexed receiptAddress_, string projectId_, string taskId_, uint256 taskEstimate_, uint256 feeAmount_, bool isFLN_, uint32 paidTime);
    event Withdraw(address indexed address_, uint256 amount_, string indexed type_);
    event SetStakingContract(address contractAddress);

    constructor(address flanAddress_, address cUSDAddress_, address stakingContractAddress_) {
        require(cUSDAddress_ != address(0x0), "");
        require(flanAddress_ != address(0x0), "");
        require(stakingContractAddress_ != address(0x0), "");
        _flanToken = IERC20(flanAddress_);
        _cusdToken = IERC20(cUSDAddress_);
        _stakingContractAddress = stakingContractAddress_;
        init();
    }

    function init() private {
        feePlanList.push(FeePlan({
        name : "F0 Tier",
        minStakedAmount : 0,
        cUSDFeePercent : 12,
        flanFeePercent : 6
        }));

        feePlanList.push(FeePlan({
        name : "F1 Tier",
        minStakedAmount : 100 * 10 ** _decimal,
        cUSDFeePercent : 12,
        flanFeePercent : 5
        }));

        feePlanList.push(FeePlan({
        name : "F2 Tier",
        minStakedAmount : 250 * 10 ** _decimal,
        cUSDFeePercent : 12,
        flanFeePercent : 4
        }));

        feePlanList.push(FeePlan({
        name : "F3 Tier",
        minStakedAmount : 500 * 10 ** _decimal,
        cUSDFeePercent : 10,
        flanFeePercent : 2
        }));

        feePlanList.push(FeePlan({
        name : "F4 Tier",
        minStakedAmount : 1000 * 10 ** _decimal,
        cUSDFeePercent : 6,
        flanFeePercent : 0
        }));
    }

    function setStakingContract(address stakingContractAddress_) external onlyOwner {
        require(stakingContractAddress_ != address(0x0), "");
        _stakingContractAddress = stakingContractAddress_;
        emit SetStakingContract(stakingContractAddress_);
    }

    function getStakedAmount(address address_) private view returns (uint256) {
        (uint256 amount, uint32 time) = FlanTokenStaking(_stakingContractAddress).getAmountOfMember(address_);
        return amount;
    }

    function pay(
        string memory projectId,
        string memory taskId,
        address receiptAddress,
        uint256 taskEstimate,
        bool isFLN
    ) external {
        require(receiptAddress != address(0x0), "");
        uint256 stakedAmount = getStakedAmount(receiptAddress);
        uint256 freelancerGrade = 0;
        for (uint256 i = 0; i < feePlanList.length; i++) {
            if (feePlanList[i].minStakedAmount <= stakedAmount) freelancerGrade = i;
        }
        uint256 feeAmount = 0;
        uint256 taxFeeAmount = taskEstimate * 5 / 1000;
        if (isFLN) {
            feeAmount = taskEstimate * feePlanList[freelancerGrade].flanFeePercent / 100;
            _flanToken.safeTransferFrom(msg.sender, address(this), taskEstimate);
            _flanToken.safeTransfer(receiptAddress, taskEstimate - feeAmount - taxFeeAmount);
            _totalFLNFeeAmount += feeAmount;
            _FLNTaxFeeAmount += taxFeeAmount;
        } else {
            feeAmount = taskEstimate * feePlanList[freelancerGrade].cUSDFeePercent / 100;
            _cusdToken.safeTransferFrom(msg.sender, address(this), taskEstimate);
            _cusdToken.safeTransfer(receiptAddress, taskEstimate - feeAmount - taxFeeAmount);
            _totalCUSDFeeAmount += feeAmount;
            _CUSDTaxFeeAmount += taxFeeAmount;
        }
        PaymentData memory paymentData = PaymentData({
        projectId : projectId,
        taskId : taskId,
        senderAddress : msg.sender,
        receiptAddress : receiptAddress,
        taskEstimate : taskEstimate,
        feeAmount : feeAmount + taxFeeAmount,
        isFLN : isFLN
        });
        _paymentId++;
        paymentDataList[_paymentId] = paymentData;

        emit Paid(_paymentId, msg.sender, receiptAddress, projectId, taskId, taskEstimate, feeAmount + taxFeeAmount, isFLN, _getCurrentTime());
    }

    function withdrawAllCUSD() external onlyOwner {
        uint256 balance = _cusdToken.balanceOf(address(this));
        _cusdToken.safeTransfer(msg.sender, balance);
        _totalCUSDFeeAmount = 0;
        _CUSDTaxFeeAmount = 0;
        emit Withdraw(msg.sender, balance, "cUSD");
    }

    function withdrawAllFLN() external onlyOwner {
        uint256 balance = _flanToken.balanceOf(address(this));
        _flanToken.safeTransfer(msg.sender, balance);
        _totalFLNFeeAmount = 0;
        _FLNTaxFeeAmount = 0;
        emit Withdraw(msg.sender, balance, "FLN");
    }

    function withdrawOnlyTaxFee() external onlyOwner {
        _flanToken.safeTransfer(msg.sender, _FLNTaxFeeAmount);
        _cusdToken.safeTransfer(msg.sender, _CUSDTaxFeeAmount);
        _FLNTaxFeeAmount = 0;
        _CUSDTaxFeeAmount = 0;
        emit Withdraw(msg.sender, _FLNTaxFeeAmount, "FLN: Tax Fee");
        emit Withdraw(msg.sender, _CUSDTaxFeeAmount, "cUSD: Tax Fee");
    }


    function getPayment(uint256 paymentId_) public view returns (string memory, string memory, address, address, uint256, uint256, bool) {
        require(paymentId_ != 0, "paymentId is 0");
        require(paymentId_ <= _paymentId, "paymentId is range out");
        PaymentData memory paymentData = paymentDataList[paymentId_];
        return (
        paymentData.projectId,
        paymentData.taskId,
        paymentData.senderAddress,
        paymentData.receiptAddress,
        paymentData.taskEstimate,
        paymentData.feeAmount,
        paymentData.isFLN
        );
    }

    function getTotalFee() external view returns (uint256, uint256) {
        return (_totalCUSDFeeAmount, _totalFLNFeeAmount);
    }

    function getTotalTaxFee() external view returns (uint256, uint256) {
        return (_CUSDTaxFeeAmount, _FLNTaxFeeAmount);
    }

    function getPaymentId() public view returns (uint256) {
        return _paymentId;
    }

    function _getCurrentTime() private view returns (uint32) {
        return uint32(block.timestamp);
    }
}


// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts v4.4.1 (utils/math/SafeMath.sol)

pragma solidity ^0.8.0;

// CAUTION
// This version of SafeMath should only be used with Solidity 0.8 or later,
// because it relies on the compiler's built in overflow checks.

/**
 * @dev Wrappers over Solidity's arithmetic operations.
 *
 * NOTE: `SafeMath` is generally not needed starting with Solidity 0.8, since the compiler
 * now has built in overflow checking.
 */
library SafeMath {
    /**
     * @dev Returns the addition of two unsigned integers, with an overflow flag.
     *
     * _Available since v3.4._
     */
    function tryAdd(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        unchecked {
            uint256 c = a + b;
            if (c < a) return (false, 0);
            return (true, c);
        }
    }

    /**
     * @dev Returns the substraction of two unsigned integers, with an overflow flag.
     *
     * _Available since v3.4._
     */
    function trySub(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        unchecked {
            if (b > a) return (false, 0);
            return (true, a - b);
        }
    }

    /**
     * @dev Returns the multiplication of two unsigned integers, with an overflow flag.
     *
     * _Available since v3.4._
     */
    function tryMul(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        unchecked {
            // Gas optimization: this is cheaper than requiring 'a' not being zero, but the
            // benefit is lost if 'b' is also tested.
            // See: https://github.com/OpenZeppelin/openzeppelin-contracts/pull/522
            if (a == 0) return (true, 0);
            uint256 c = a * b;
            if (c / a != b) return (false, 0);
            return (true, c);
        }
    }

    /**
     * @dev Returns the division of two unsigned integers, with a division by zero flag.
     *
     * _Available since v3.4._
     */
    function tryDiv(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        unchecked {
            if (b == 0) return (false, 0);
            return (true, a / b);
        }
    }

    /**
     * @dev Returns the remainder of dividing two unsigned integers, with a division by zero flag.
     *
     * _Available since v3.4._
     */
    function tryMod(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        unchecked {
            if (b == 0) return (false, 0);
            return (true, a % b);
        }
    }

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
        return a + b;
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
        return a - b;
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
        return a * b;
    }

    /**
     * @dev Returns the integer division of two unsigned integers, reverting on
     * division by zero. The result is rounded towards zero.
     *
     * Counterpart to Solidity's `/` operator.
     *
     * Requirements:
     *
     * - The divisor cannot be zero.
     */
    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        return a / b;
    }

    /**
     * @dev Returns the remainder of dividing two unsigned integers. (unsigned integer modulo),
     * reverting when dividing by zero.
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
        return a % b;
    }

    /**
     * @dev Returns the subtraction of two unsigned integers, reverting with custom message on
     * overflow (when the result is negative).
     *
     * CAUTION: This function is deprecated because it requires allocating memory for the error
     * message unnecessarily. For custom revert reasons use {trySub}.
     *
     * Counterpart to Solidity's `-` operator.
     *
     * Requirements:
     *
     * - Subtraction cannot overflow.
     */
    function sub(
        uint256 a,
        uint256 b,
        string memory errorMessage
    ) internal pure returns (uint256) {
        unchecked {
            require(b <= a, errorMessage);
            return a - b;
        }
    }

    /**
     * @dev Returns the integer division of two unsigned integers, reverting with custom message on
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
    function div(
        uint256 a,
        uint256 b,
        string memory errorMessage
    ) internal pure returns (uint256) {
        unchecked {
            require(b > 0, errorMessage);
            return a / b;
        }
    }

    /**
     * @dev Returns the remainder of dividing two unsigned integers. (unsigned integer modulo),
     * reverting with custom message when dividing by zero.
     *
     * CAUTION: This function is deprecated because it requires allocating memory for the error
     * message unnecessarily. For custom revert reasons use {tryMod}.
     *
     * Counterpart to Solidity's `%` operator. This function uses a `revert`
     * opcode (which leaves remaining gas untouched) while Solidity uses an
     * invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     *
     * - The divisor cannot be zero.
     */
    function mod(
        uint256 a,
        uint256 b,
        string memory errorMessage
    ) internal pure returns (uint256) {
        unchecked {
            require(b > 0, errorMessage);
            return a % b;
        }
    }
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
// OpenZeppelin Contracts (last updated v4.5.0) (utils/Address.sol)

pragma solidity ^0.8.1;

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
     *
     * [IMPORTANT]
     * ====
     * You shouldn't rely on `isContract` to protect against flash loan attacks!
     *
     * Preventing calls from contracts is highly discouraged. It breaks composability, breaks support for smart wallets
     * like Gnosis Safe, and does not provide security since it can be circumvented by calling from a contract
     * constructor.
     * ====
     */
    function isContract(address account) internal view returns (bool) {
        // This method relies on extcodesize/address.code.length, which returns 0
        // for contracts in construction, since the code is only stored at the end
        // of the constructor execution.

        return account.code.length > 0;
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


// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts v4.4.1 (token/ERC20/utils/SafeERC20.sol)

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


// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v4.5.0) (token/ERC20/IERC20.sol)

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
// OpenZeppelin Contracts v4.4.1 (security/ReentrancyGuard.sol)

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

    constructor() {
        _status = _NOT_ENTERED;
    }

    /**
     * @dev Prevents a contract from calling itself, directly or indirectly.
     * Calling a `nonReentrant` function from another `nonReentrant`
     * function is not supported. It is possible to prevent this from happening
     * by making the `nonReentrant` function external, and making it call a
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