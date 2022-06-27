// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.7.5;

interface IERC20 {
  event Approval(address indexed owner, address indexed spender, uint256 value);
  event Transfer(address indexed from, address indexed to, uint256 value);

  function name() external view returns (string memory);

  function symbol() external view returns (string memory);

  function decimals() external view returns (uint8);

  function totalSupply() external view returns (uint256);

  function balanceOf(address owner) external view returns (uint256);

  function allowance(address owner, address spender)
    external
    view
    returns (uint256);

  function approve(address spender, uint256 value) external returns (bool);

  function transfer(address to, uint256 value) external returns (bool);

  function transferFrom(
    address from,
    address to,
    uint256 value
  ) external returns (bool);
}

interface IERC20Mintable {
  function mint(uint256 amount_) external;

  function mint(address account_, uint256 ammount_) external;
}

interface IOwnable {
  function owner() external view returns (address);

  function renounceManagement() external;

  function pushManagement(address newOwner_) external;

  function pullManagement() external;
}

contract Ownable is IOwnable {
  address internal _owner;
  address internal _newOwner;

  event OwnershipPushed(
    address indexed previousOwner,
    address indexed newOwner
  );
  event OwnershipPulled(
    address indexed previousOwner,
    address indexed newOwner
  );

  constructor() {
    _owner = msg.sender;
    emit OwnershipPushed(address(0), _owner);
  }

  function owner() public view override returns (address) {
    return _owner;
  }

  modifier onlyOwner() {
    require(_owner == msg.sender, "Ownable: caller is not the owner");
    _;
  }

  function renounceManagement() public virtual override onlyOwner {
    emit OwnershipPushed(_owner, address(0));
    _owner = address(0);
  }

  function pushManagement(address newOwner_) public virtual override onlyOwner {
    require(newOwner_ != address(0), "Ownable: new owner is the zero address");
    emit OwnershipPushed(_owner, newOwner_);
    _newOwner = newOwner_;
  }

  function pullManagement() public virtual override {
    require(msg.sender == _newOwner, "Ownable: must be new owner to pull");
    emit OwnershipPulled(_owner, _newOwner);
    _owner = _newOwner;
  }
}

library SafeMath {
  function add(uint256 a, uint256 b) internal pure returns (uint256) {
    uint256 c = a + b;
    require(c >= a, "SafeMath: addition overflow");

    return c;
  }

  function sub(uint256 a, uint256 b) internal pure returns (uint256) {
    return sub(a, b, "SafeMath: subtraction overflow");
  }

  function sub(
    uint256 a,
    uint256 b,
    string memory errorMessage
  ) internal pure returns (uint256) {
    require(b <= a, errorMessage);
    uint256 c = a - b;

    return c;
  }

  function mul(uint256 a, uint256 b) internal pure returns (uint256) {
    if (a == 0) {
      return 0;
    }

    uint256 c = a * b;
    require(c / a == b, "SafeMath: multiplication overflow");

    return c;
  }

  function div(uint256 a, uint256 b) internal pure returns (uint256) {
    return div(a, b, "SafeMath: division by zero");
  }

  function div(
    uint256 a,
    uint256 b,
    string memory errorMessage
  ) internal pure returns (uint256) {
    require(b > 0, errorMessage);
    uint256 c = a / b;
    // assert(a == b * c + a % b); // There is no case in which this doesn't hold

    return c;
  }

  function sqrrt(uint256 a) internal pure returns (uint256 c) {
    if (a > 3) {
      c = a;
      uint256 b = add(div(a, 2), 1);
      while (b < c) {
        c = b;
        b = div(add(div(a, b), b), 2);
      }
    } else if (a != 0) {
      c = 1;
    }
  }
}

library Counters {
  using SafeMath for uint256;

  struct Counter {
    uint256 _value; // default: 0
  }

  function current(Counter storage counter) internal view returns (uint256) {
    return counter._value;
  }

  function increment(Counter storage counter) internal {
    counter._value += 1;
  }

  function decrement(Counter storage counter) internal {
    counter._value = counter._value.sub(1);
  }
}

library Address {
  function isContract(address account) internal view returns (bool) {
    uint256 size;
    // solhint-disable-next-line no-inline-assembly
    assembly {
      size := extcodesize(account)
    }
    return size > 0;
  }

  function sendValue(address payable recipient, uint256 amount) internal {
    require(address(this).balance >= amount, "Address: insufficient balance");

    // solhint-disable-next-line avoid-low-level-calls, avoid-call-value
    (bool success, ) = recipient.call{ value: amount }("");
    require(
      success,
      "Address: unable to send value, recipient may have reverted"
    );
  }

  function functionCall(address target, bytes memory data)
    internal
    returns (bytes memory)
  {
    return functionCall(target, data, "Address: low-level call failed");
  }

  function functionCall(
    address target,
    bytes memory data,
    string memory errorMessage
  ) internal returns (bytes memory) {
    return _functionCallWithValue(target, data, 0, errorMessage);
  }

  function functionCallWithValue(
    address target,
    bytes memory data,
    uint256 value
  ) internal returns (bytes memory) {
    return
      functionCallWithValue(
        target,
        data,
        value,
        "Address: low-level call with value failed"
      );
  }

  function functionCallWithValue(
    address target,
    bytes memory data,
    uint256 value,
    string memory errorMessage
  ) internal returns (bytes memory) {
    require(
      address(this).balance >= value,
      "Address: insufficient balance for call"
    );
    require(isContract(target), "Address: call to non-contract");

    // solhint-disable-next-line avoid-low-level-calls
    (bool success, bytes memory returndata) = target.call{ value: value }(data);
    return _verifyCallResult(success, returndata, errorMessage);
  }

  function _functionCallWithValue(
    address target,
    bytes memory data,
    uint256 weiValue,
    string memory errorMessage
  ) private returns (bytes memory) {
    require(isContract(target), "Address: call to non-contract");

    // solhint-disable-next-line avoid-low-level-calls
    (bool success, bytes memory returndata) = target.call{ value: weiValue }(
      data
    );
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

  function functionStaticCall(address target, bytes memory data)
    internal
    view
    returns (bytes memory)
  {
    return
      functionStaticCall(target, data, "Address: low-level static call failed");
  }

  function functionStaticCall(
    address target,
    bytes memory data,
    string memory errorMessage
  ) internal view returns (bytes memory) {
    require(isContract(target), "Address: static call to non-contract");

    // solhint-disable-next-line avoid-low-level-calls
    (bool success, bytes memory returndata) = target.staticcall(data);
    return _verifyCallResult(success, returndata, errorMessage);
  }

  function functionDelegateCall(address target, bytes memory data)
    internal
    returns (bytes memory)
  {
    return
      functionDelegateCall(
        target,
        data,
        "Address: low-level delegate call failed"
      );
  }

  function functionDelegateCall(
    address target,
    bytes memory data,
    string memory errorMessage
  ) internal returns (bytes memory) {
    require(isContract(target), "Address: delegate call to non-contract");

    // solhint-disable-next-line avoid-low-level-calls
    (bool success, bytes memory returndata) = target.delegatecall(data);
    return _verifyCallResult(success, returndata, errorMessage);
  }

  function _verifyCallResult(
    bool success,
    bytes memory returndata,
    string memory errorMessage
  ) private pure returns (bytes memory) {
    if (success) {
      return returndata;
    } else {
      if (returndata.length > 0) {
        assembly {
          let returndata_size := mload(returndata)
          revert(add(32, returndata), returndata_size)
        }
      } else {
        revert(errorMessage);
      }
    }
  }

  function addressToString(address _address)
    internal
    pure
    returns (string memory)
  {
    bytes32 _bytes = bytes32(uint256(_address));
    bytes memory HEX = "0123456789abcdef";
    bytes memory _addr = new bytes(42);

    _addr[0] = "0";
    _addr[1] = "x";

    for (uint256 i = 0; i < 20; i++) {
      _addr[2 + i * 2] = HEX[uint8(_bytes[i + 12] >> 4)];
      _addr[3 + i * 2] = HEX[uint8(_bytes[i + 12] & 0x0f)];
    }

    return string(_addr);
  }
}

library SafeERC20 {
  using SafeMath for uint256;
  using Address for address;

  function safeTransfer(
    IERC20 token,
    address to,
    uint256 value
  ) internal {
    _callOptionalReturn(
      token,
      abi.encodeWithSelector(token.transfer.selector, to, value)
    );
  }

  function safeTransferFrom(
    IERC20 token,
    address from,
    address to,
    uint256 value
  ) internal {
    _callOptionalReturn(
      token,
      abi.encodeWithSelector(token.transferFrom.selector, from, to, value)
    );
  }

  function safeApprove(
    IERC20 token,
    address spender,
    uint256 value
  ) internal {
    require(
      (value == 0) || (token.allowance(address(this), spender) == 0),
      "SafeERC20: approve from non-zero to non-zero allowance"
    );
    _callOptionalReturn(
      token,
      abi.encodeWithSelector(token.approve.selector, spender, value)
    );
  }

  function safeIncreaseAllowance(
    IERC20 token,
    address spender,
    uint256 value
  ) internal {
    uint256 newAllowance = token.allowance(address(this), spender).add(value);
    _callOptionalReturn(
      token,
      abi.encodeWithSelector(token.approve.selector, spender, newAllowance)
    );
  }

  function safeDecreaseAllowance(
    IERC20 token,
    address spender,
    uint256 value
  ) internal {
    uint256 newAllowance = token.allowance(address(this), spender).sub(
      value,
      "SafeERC20: decreased allowance below zero"
    );
    _callOptionalReturn(
      token,
      abi.encodeWithSelector(token.approve.selector, spender, newAllowance)
    );
  }

  function _callOptionalReturn(IERC20 token, bytes memory data) private {
    bytes memory returndata = address(token).functionCall(
      data,
      "SafeERC20: low-level call failed"
    );
    if (returndata.length > 0) {
      // Return data is optional
      // solhint-disable-next-line max-line-length
      require(
        abi.decode(returndata, (bool)),
        "SafeERC20: ERC20 operation did not succeed"
      );
    }
  }
}

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
    // (a + b) / 2 can overflow, so we distribute
    return (a / 2) + (b / 2) + (((a % 2) + (b % 2)) / 2);
  }
}

interface ITreasury {
  function deposit(
    uint256 _amount,
    address _token,
    uint256 _profit
  ) external returns (uint256 send_);
}

interface IStakingHelper {
  function stake(uint256 _amount, address _recipient) external;
}

contract ImmortalPresale is Ownable {
  using SafeMath for uint256;
  using SafeERC20 for IERC20;

  address public IMMO;
  address public mcUSD; //0x918146359264C492BD6934071c6Bd31C854EDBc3
  address public treasury;
  address public stakingHelper;

  uint256 public totalWhiteListed;
  uint256 public totalIMMObought;
  uint256 public IMMOMinted;
  uint256 public treasuryAllocation;
  uint256 public salePrice;
  uint256 public immutable startOfSale;
  uint256 public immutable endOfSale;
  uint256 public immutable redeemTime;
  uint256 public constant initialVested = 5000; //50%
  uint256 public constant completeVested = 10000;
  uint256 public vestingPeriod = 1209600; //2 weeks
  uint256 decimal_mcUSD;
  uint256 decimal_IMMO;

  bool public cancelled;
  bool public finalized;

  mapping(address => bool) public hasBought;
  mapping(address => bool) public whitelisted;
  mapping(address => bool) public whitelistAdmin;

  mapping(address => uint256) public purchasedAmounts;
  mapping(address => uint256) public amountClaimed;

  constructor(
    address _IMMO,
    address _mcUSD,
    address _treasury,
    address _stakingHelper,
    uint256 _startOfSale,
    uint256 _endOfSale,
    uint256 _redeemTime
  ) {
    require(_IMMO != address(0));
    require(_mcUSD != address(0));
    require(_treasury != address(0));
    require(_stakingHelper != address(0));

    IMMO = _IMMO;
    mcUSD = _mcUSD;
    treasury = _treasury;
    stakingHelper = _stakingHelper;

    startOfSale = _startOfSale;
    endOfSale = _endOfSale;
    redeemTime = _redeemTime;

    decimal_mcUSD = 10**(IERC20(mcUSD).decimals());
    decimal_IMMO = 10**(IERC20(IMMO).decimals());
    salePrice = 20 * decimal_mcUSD;
  }

  function saleStarted() public view returns (bool) {
    return startOfSale <= block.timestamp;
  }

  function addToWhitelist(address[] memory _buyers) external {
    require(whitelistAdmin[msg.sender] == true, "not admin");

    for (uint256 i = 0; i < _buyers.length; i++) {
      if (!whitelisted[_buyers[i]]) {
        whitelisted[_buyers[i]] = true;
        totalWhiteListed = totalWhiteListed.add(1);
      }
    }
  }

  function toggleAdmin(address _admin) external onlyOwner {
    whitelistAdmin[_admin] = !whitelistAdmin[_admin];
  }

  function purchaseIMMO(uint256 _amount) external returns (uint256) {
    require(whitelisted[msg.sender] == true, "Not whitelisted");
    require(saleStarted() == true, "Not started");
    require(block.timestamp < endOfSale, "Sales has ended");
    require(cancelled == false, "Sales cancelled");
    require(hasBought[msg.sender] == false, "Already participated");
    require(_amount >= 1, "At least 1 IMMO");
    require(_amount <= 25, "Max 25 IMMO");

    hasBought[msg.sender] = true;

    totalWhiteListed = totalWhiteListed.sub(1);

    purchasedAmounts[msg.sender] = _amount;

    totalIMMObought = totalIMMObought.add(_amount);

    IERC20(mcUSD).safeTransferFrom(
      msg.sender,
      address(this),
      _amount * salePrice
    );

    return _amount;
  }

  function claim(bool _stake) public {
    require(block.timestamp >= redeemTime);
    require(finalized, "only can claim after finalized");
    require(purchasedAmounts[msg.sender] > 0, "not purchased");
    uint256 amountAbleToRedeem = (
      percentAbleToRedeem().mul(purchasedAmounts[msg.sender]).mul(decimal_IMMO)
    ).div(completeVested);
    uint256 amountRedeemed = amountAbleToRedeem.sub(amountClaimed[msg.sender]);
    amountClaimed[msg.sender] = amountClaimed[msg.sender].add(amountRedeemed);
    stakeOrSend(msg.sender, _stake, amountRedeemed);
  }

  function stakeOrSend(
    address _recipient,
    bool _stake,
    uint256 _amount
  ) internal {
    if (!_stake) {
      // if user does not want to stake
      IERC20(IMMO).safeTransfer(_recipient, _amount); // send payout
    } else {
      // if user wants to stake
      IERC20(IMMO).approve(stakingHelper, _amount);
      IStakingHelper(stakingHelper).stake(_amount, _recipient);
    }
  }

  //50% unlocked at launch, other 50% linearly vested
  function percentAbleToRedeem() public view returns (uint256 percentVested) {
    if (block.timestamp >= redeemTime) {
      uint256 timePassed = block.timestamp.sub(redeemTime);
      if (timePassed >= vestingPeriod) {
        percentVested = completeVested;
      } else {
        percentVested = initialVested.add(
          (timePassed.mul(completeVested.sub(initialVested))).div(vestingPeriod)
        );
      }
    } else {
      percentVested = 0;
    }
  }

  function withdraw() external onlyOwner {
    require(cancelled == false, "Presale cancelled");
    require(finalized == false, "Presale is finalized");

    uint256 mcUSDInTreasury = treasuryAllocation * decimal_mcUSD;
    uint256 bal = IERC20(mcUSD).balanceOf(address(this));
    require(bal >= mcUSDInTreasury, "Insufficient balance");

    IERC20(mcUSD).approve(treasury, mcUSDInTreasury);
    IMMOMinted = ITreasury(treasury).deposit(
      mcUSDInTreasury,
      mcUSD,
      (treasuryAllocation - totalIMMObought) * decimal_IMMO
    );

    bal = IERC20(mcUSD).balanceOf(address(this));
    IERC20(mcUSD).safeTransfer(msg.sender, bal);

    finalized = true;
  }

  function setTreasuryAllocation(uint256 _treasuryAllocation)
    external
    onlyOwner
  {
    treasuryAllocation = _treasuryAllocation;
  }

  function balanceIMMO(address recipient) public view returns (uint256) {
    if (
      amountClaimed[recipient] < (purchasedAmounts[recipient].mul(decimal_IMMO))
    ) {
      return
        (purchasedAmounts[recipient].mul(decimal_IMMO)).sub(
          amountClaimed[recipient]
        );
    } else {
      return 0;
    }
  }

  // Emergency use: Cancel the presale and refund
  function cancel() external onlyOwner {
    cancelled = true;
  }

  function refund() external {
    require(cancelled, "Presale is not cancelled");
    uint256 amount = purchasedAmounts[msg.sender];
    require(amount > 0, "Not purchased");
    purchasedAmounts[msg.sender] = 0;
    IERC20(mcUSD).safeTransfer(msg.sender, amount * salePrice);
  }
}