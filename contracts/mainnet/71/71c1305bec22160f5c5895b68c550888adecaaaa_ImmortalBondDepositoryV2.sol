// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.7.5;

interface IOwnable {
  function policy() external view returns (address);

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

  function policy() public view override returns (address) {
    return _owner;
  }

  modifier onlyPolicy() {
    require(_owner == msg.sender, "Ownable: caller is not the owner");
    _;
  }

  function renounceManagement() public virtual override onlyPolicy {
    emit OwnershipPushed(_owner, address(0));
    _owner = address(0);
  }

  function pushManagement(address newOwner_)
    public
    virtual
    override
    onlyPolicy
  {
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

  function sub32(uint32 a, uint32 b) internal pure returns (uint32) {
    return sub32(a, b, "SafeMath: subtraction overflow");
  }

  function sub32(
    uint32 a,
    uint32 b,
    string memory errorMessage
  ) internal pure returns (uint32) {
    require(b <= a, errorMessage);
    uint32 c = a - b;

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
    return c;
  }

  function mod(uint256 a, uint256 b) internal pure returns (uint256) {
    return mod(a, b, "SafeMath: modulo by zero");
  }

  function mod(
    uint256 a,
    uint256 b,
    string memory errorMessage
  ) internal pure returns (uint256) {
    require(b != 0, errorMessage);
    return a % b;
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

interface IERC20 {
  function decimals() external view returns (uint8);

  function totalSupply() external view returns (uint256);

  function balanceOf(address account) external view returns (uint256);

  function transfer(address recipient, uint256 amount) external returns (bool);

  function allowance(address owner, address spender)
    external
    view
    returns (uint256);

  function approve(address spender, uint256 amount) external returns (bool);

  function transferFrom(
    address sender,
    address recipient,
    uint256 amount
  ) external returns (bool);

  event Transfer(address indexed from, address indexed to, uint256 value);

  event Approval(address indexed owner, address indexed spender, uint256 value);
}

abstract contract ERC20 is IERC20 {
  using SafeMath for uint256;

  // TODO comment actual hash value.
  bytes32 private constant ERC20TOKEN_ERC1820_INTERFACE_ID =
    keccak256("ERC20Token");

  mapping(address => uint256) internal _balances;

  mapping(address => mapping(address => uint256)) internal _allowances;

  uint256 internal _totalSupply;

  string internal _name;

  string internal _symbol;

  uint8 internal _decimals;

  constructor(
    string memory name_,
    string memory symbol_,
    uint8 decimals_
  ) {
    _name = name_;
    _symbol = symbol_;
    _decimals = decimals_;
  }

  function name() public view returns (string memory) {
    return _name;
  }

  function symbol() public view returns (string memory) {
    return _symbol;
  }

  function decimals() public view override returns (uint8) {
    return _decimals;
  }

  function totalSupply() public view override returns (uint256) {
    return _totalSupply;
  }

  function balanceOf(address account)
    public
    view
    virtual
    override
    returns (uint256)
  {
    return _balances[account];
  }

  function transfer(address recipient, uint256 amount)
    public
    virtual
    override
    returns (bool)
  {
    _transfer(msg.sender, recipient, amount);
    return true;
  }

  function allowance(address owner, address spender)
    public
    view
    virtual
    override
    returns (uint256)
  {
    return _allowances[owner][spender];
  }

  function approve(address spender, uint256 amount)
    public
    virtual
    override
    returns (bool)
  {
    _approve(msg.sender, spender, amount);
    return true;
  }

  function transferFrom(
    address sender,
    address recipient,
    uint256 amount
  ) public virtual override returns (bool) {
    _transfer(sender, recipient, amount);
    _approve(
      sender,
      msg.sender,
      _allowances[sender][msg.sender].sub(
        amount,
        "ERC20: transfer amount exceeds allowance"
      )
    );
    return true;
  }

  function increaseAllowance(address spender, uint256 addedValue)
    public
    virtual
    returns (bool)
  {
    _approve(
      msg.sender,
      spender,
      _allowances[msg.sender][spender].add(addedValue)
    );
    return true;
  }

  function decreaseAllowance(address spender, uint256 subtractedValue)
    public
    virtual
    returns (bool)
  {
    _approve(
      msg.sender,
      spender,
      _allowances[msg.sender][spender].sub(
        subtractedValue,
        "ERC20: decreased allowance below zero"
      )
    );
    return true;
  }

  function _transfer(
    address sender,
    address recipient,
    uint256 amount
  ) internal virtual {
    require(sender != address(0), "ERC20: transfer from the zero address");
    require(recipient != address(0), "ERC20: transfer to the zero address");

    _beforeTokenTransfer(sender, recipient, amount);

    _balances[sender] = _balances[sender].sub(
      amount,
      "ERC20: transfer amount exceeds balance"
    );
    _balances[recipient] = _balances[recipient].add(amount);
    emit Transfer(sender, recipient, amount);
  }

  function _mint(address account_, uint256 ammount_) internal virtual {
    require(account_ != address(0), "ERC20: mint to the zero address");
    _beforeTokenTransfer(address(this), account_, ammount_);
    _totalSupply = _totalSupply.add(ammount_);
    _balances[account_] = _balances[account_].add(ammount_);
    emit Transfer(address(this), account_, ammount_);
  }

  function _burn(address account, uint256 amount) internal virtual {
    require(account != address(0), "ERC20: burn from the zero address");

    _beforeTokenTransfer(account, address(0), amount);

    _balances[account] = _balances[account].sub(
      amount,
      "ERC20: burn amount exceeds balance"
    );
    _totalSupply = _totalSupply.sub(amount);
    emit Transfer(account, address(0), amount);
  }

  function _approve(
    address owner,
    address spender,
    uint256 amount
  ) internal virtual {
    require(owner != address(0), "ERC20: approve from the zero address");
    require(spender != address(0), "ERC20: approve to the zero address");

    _allowances[owner][spender] = amount;
    emit Approval(owner, spender, amount);
  }

  function _beforeTokenTransfer(
    address from_,
    address to_,
    uint256 amount_
  ) internal virtual {}
}

interface IERC2612Permit {
  function permit(
    address owner,
    address spender,
    uint256 amount,
    uint256 deadline,
    uint8 v,
    bytes32 r,
    bytes32 s
  ) external;

  function nonces(address owner) external view returns (uint256);
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

abstract contract ERC20Permit is ERC20, IERC2612Permit {
  using Counters for Counters.Counter;

  mapping(address => Counters.Counter) private _nonces;

  // keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
  bytes32 public constant PERMIT_TYPEHASH =
    0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9;

  bytes32 public DOMAIN_SEPARATOR;

  constructor() {
    uint256 chainID;
    assembly {
      chainID := chainid()
    }

    DOMAIN_SEPARATOR = keccak256(
      abi.encode(
        keccak256(
          "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
        ),
        keccak256(bytes(name())),
        keccak256(bytes("1")), // Version
        chainID,
        address(this)
      )
    );
  }

  function permit(
    address owner,
    address spender,
    uint256 amount,
    uint256 deadline,
    uint8 v,
    bytes32 r,
    bytes32 s
  ) public virtual override {
    require(block.timestamp <= deadline, "Permit: expired deadline");

    bytes32 hashStruct = keccak256(
      abi.encode(
        PERMIT_TYPEHASH,
        owner,
        spender,
        amount,
        _nonces[owner].current(),
        deadline
      )
    );

    bytes32 _hash = keccak256(
      abi.encodePacked(uint16(0x1901), DOMAIN_SEPARATOR, hashStruct)
    );

    address signer = ecrecover(_hash, v, r, s);
    require(
      signer != address(0) && signer == owner,
      "ZeroSwapPermit: Invalid signature"
    );

    _nonces[owner].increment();
    _approve(owner, spender, amount);
  }

  function nonces(address owner) public view override returns (uint256) {
    return _nonces[owner].current();
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

library FullMath {
  function fullMul(uint256 x, uint256 y)
    private
    pure
    returns (uint256 l, uint256 h)
  {
    uint256 mm = mulmod(x, y, uint256(-1));
    l = x * y;
    h = mm - l;
    if (mm < l) h -= 1;
  }

  function fullDiv(
    uint256 l,
    uint256 h,
    uint256 d
  ) private pure returns (uint256) {
    uint256 pow2 = d & -d;
    d /= pow2;
    l /= pow2;
    l += h * ((-pow2) / pow2 + 1);
    uint256 r = 1;
    r *= 2 - d * r;
    r *= 2 - d * r;
    r *= 2 - d * r;
    r *= 2 - d * r;
    r *= 2 - d * r;
    r *= 2 - d * r;
    r *= 2 - d * r;
    r *= 2 - d * r;
    return l * r;
  }

  function mulDiv(
    uint256 x,
    uint256 y,
    uint256 d
  ) internal pure returns (uint256) {
    (uint256 l, uint256 h) = fullMul(x, y);
    uint256 mm = mulmod(x, y, d);
    if (mm > l) h -= 1;
    l -= mm;
    require(h < d, "FullMath::mulDiv: overflow");
    return fullDiv(l, h, d);
  }
}

library FixedPoint {
  struct uq112x112 {
    uint224 _x;
  }

  struct uq144x112 {
    uint256 _x;
  }

  uint8 private constant RESOLUTION = 112;
  uint256 private constant Q112 = 0x10000000000000000000000000000;
  uint256 private constant Q224 =
    0x100000000000000000000000000000000000000000000000000000000;
  uint256 private constant LOWER_MASK = 0xffffffffffffffffffffffffffff; // decimal of UQ*x112 (lower 112 bits)

  function decode(uq112x112 memory self) internal pure returns (uint112) {
    return uint112(self._x >> RESOLUTION);
  }

  function decode112with18(uq112x112 memory self)
    internal
    pure
    returns (uint256)
  {
    return uint256(self._x) / 5192296858534827;
  }

  function fraction(uint256 numerator, uint256 denominator)
    internal
    pure
    returns (uq112x112 memory)
  {
    require(denominator > 0, "FixedPoint::fraction: division by zero");
    if (numerator == 0) return FixedPoint.uq112x112(0);

    if (numerator <= uint144(-1)) {
      uint256 result = (numerator << RESOLUTION) / denominator;
      require(result <= uint224(-1), "FixedPoint::fraction: overflow");
      return uq112x112(uint224(result));
    } else {
      uint256 result = FullMath.mulDiv(numerator, Q112, denominator);
      require(result <= uint224(-1), "FixedPoint::fraction: overflow");
      return uq112x112(uint224(result));
    }
  }
}

interface ITreasury {
  function deposit(
    uint256 _amount,
    address _token,
    uint256 _profit
  ) external returns (bool);
}

interface IStakingHelper {
  function stake(uint256 _amount, address _recipient) external;
}

interface IsIMMO {
  function gonsForBalance(uint256 amount) external view returns (uint256);

  function balanceForGons(uint256 gons) external view returns (uint256);
}

interface IUniswapV2ERC20 {
  function totalSupply() external view returns (uint256);
}

interface IUniswapV2Pair is IUniswapV2ERC20 {
  function getReserves()
    external
    view
    returns (
      uint112 reserve0,
      uint112 reserve1,
      uint32 blockTimestampLast
    );

  function token0() external view returns (address);

  function token1() external view returns (address);
}

contract ImmortalBondDepositoryV2 is Ownable {
  using FixedPoint for *;
  using SafeERC20 for IERC20;
  using SafeMath for uint256;
  using SafeMath for uint32;

  /* ======== EVENTS ======== */

  event BondCreated(
    uint256 deposit,
    uint256 indexed payout,
    uint256 indexed expires,
    uint256 indexed priceInUSD
  );

  event BondRedeemed(
    address indexed recipient,
    uint256 payout,
    uint256 remaining
  );

  /* ======== STATE VARIABLES ======== */

  address public immutable IMMO;
  address public immutable sIMMO;
  address public immutable principle; // token used to create bond
  address public immutable treasury; // mints IMMO when receives principle
  address public immutable DAO; // receives profit share from bond
  address public immutable stakingHelper; // to stake and claim
  address public immutable liquidityPair; // to get latest price

  bool public immutable isLiquidityBond; // LP and Reserve bonds are treated slightly different

  uint256 public immutable bondInitTime; // timestamp for bond creation

  uint256 public epochLength; // duration of an epoch

  bool public isBondAvailable; // bond availability for buyers

  Terms public terms; // stores terms for new bonds

  mapping(uint256 => uint256) public bondSales; // stores bond sales for each epoch

  mapping(address => Bond) public bondInfo; // stores bond information for depositors

  /* ======== STRUCTS ======== */

  // Info for creating new bonds
  struct Terms {
    uint256 discount; // bond discount to market price
    uint256 minimumPrice; // minimum price which bond cannot falls below
    uint256 maxPayout; // in thousandths of a %. i.e. 500 = 0.5%
    uint256 fee; // as % of bond payout, in hundreths. ( 500 = 5% = 0.05 for every 1 paid)
    uint256 salesLimit; // maximum number of bonds can be sold per epoch
    uint32 vestingTerm; // in seconds
    bool isDiscountPositive; // direction of discount on market price
  }

  // Info for bond holder
  struct Bond {
    uint256 gonsPayout; // sIMMO gons remaining to be paid
    uint256 immoPayout; //IMMO amount at the moment of bond
    uint32 vesting; // Seconds left to vest
    uint32 lastTime; // Last interaction
    uint256 pricePaid; // In USD, for front end viewing
  }

  /* ======== INITIALIZATION ======== */

  constructor(
    address _IMMO,
    address _sIMMO,
    address _principle,
    address _treasury,
    address _DAO,
    address _stakingHelper,
    address _liquidityPair,
    bool _isLiquidityBond,
    uint256 _bondInitTime
  ) {
    require(_IMMO != address(0));
    IMMO = _IMMO;
    require(_sIMMO != address(0));
    sIMMO = _sIMMO;
    require(_principle != address(0));
    principle = _principle;
    require(_treasury != address(0));
    treasury = _treasury;
    require(_DAO != address(0));
    DAO = _DAO;
    require(_stakingHelper != address(0));
    stakingHelper = _stakingHelper;
    require(_liquidityPair != address(0));
    liquidityPair = _liquidityPair;

    isLiquidityBond = _isLiquidityBond;
    isBondAvailable = true;
    bondInitTime = _bondInitTime;
    epochLength = 28800; // 8 hours per epoch
  }

  /**
   *  @notice initializes bond parameters
   *  @param _discount uint
   *  @param _minimumPrice uint
   *  @param _maxPayout uint
   *  @param _fee uint
   *  @param _salesLimit uint
   *  @param _vestingTerm uint32
   *  @param _isDiscountPositive bool
   */
  function initializeBondTerms(
    uint256 _discount,
    uint256 _minimumPrice,
    uint256 _maxPayout,
    uint256 _fee,
    uint256 _salesLimit,
    uint32 _vestingTerm,
    bool _isDiscountPositive
  ) external onlyPolicy {
    terms = Terms({
      discount: _discount,
      minimumPrice: _minimumPrice,
      maxPayout: _maxPayout,
      fee: _fee,
      salesLimit: _salesLimit,
      vestingTerm: _vestingTerm,
      isDiscountPositive: _isDiscountPositive
    });
  }

  /* ======== POLICY FUNCTIONS ======== */

  enum PARAMETER {
    DISCOUNT,
    ISPOSITIVE,
    VESTING,
    PAYOUT,
    FEE,
    MINPRICE,
    ISBONDAVAILABLE,
    SALESLIMIT,
    EPOCHLENGTH
  }

  /**
   *  @notice change bond parameter
   *  @param _parameter PARAMETER
   *  @param _input uint
   */
  function setBondTerms(PARAMETER _parameter, uint256 _input)
    external
    onlyPolicy
  {
    if (_parameter == PARAMETER.DISCOUNT) {
      // 0
      terms.discount = _input;
    } else if (_parameter == PARAMETER.ISPOSITIVE) {
      // 1
      if (_input > 0) {
        terms.isDiscountPositive = true;
      } else {
        terms.isDiscountPositive = false;
      }
    } else if (_parameter == PARAMETER.VESTING) {
      // 2
      require(_input >= 129600, "Vesting must be longer than 36 hours");
      terms.vestingTerm = uint32(_input);
    } else if (_parameter == PARAMETER.PAYOUT) {
      // 3
      require(_input <= 1000, "Payout cannot be above 1 percent");
      terms.maxPayout = _input;
    } else if (_parameter == PARAMETER.FEE) {
      // 4
      require(_input <= 10000, "DAO fee cannot exceed payout");
      terms.fee = _input;
    } else if (_parameter == PARAMETER.MINPRICE) {
      // 5
      terms.minimumPrice = _input;
    } else if (_parameter == PARAMETER.ISBONDAVAILABLE) {
      // 6
      if (_input > 0) {
        isBondAvailable = true;
      } else {
        isBondAvailable = false;
      }
    } else if (_parameter == PARAMETER.SALESLIMIT) {
      // 7
      terms.salesLimit = _input;
    } else if (_parameter == PARAMETER.EPOCHLENGTH) {
      // 8
      require(_input >= 3600, "Epoch length cannot be lower than 1 hour");
      epochLength = _input;
    }
  }

  /* ======== USER FUNCTIONS ======== */

  /**
   *  @notice deposit bond
   *  @param _amount uint
   *  @param _maxPrice uint
   *  @param _depositor address
   *  @return uint
   */
  function deposit(
    uint256 _amount,
    uint256 _maxPrice,
    address _depositor
  ) external returns (uint256) {
    require(_depositor != address(0), "Invalid address");
    require(isBondAvailable, "Bond is closed");

    uint256 price = bondPrice(); // stored in bond info

    require(_maxPrice >= price, "Slippage limit: more than max price"); // slippage protection

    uint256 value;

    if (isLiquidityBond) {
      value = getLPValue(_amount);
    } else {
      value = _amount.mul(1e9);
    }

    uint256 payout = payoutFor(value); // payout to bonder is computed

    uint256 epochNum = (block.timestamp.sub(bondInitTime)).div(epochLength);

    require(
      payout >= 10000000,
      "Your bond payout cannot be less than 0.01 IMMO"
    ); // must be >= 0.01 IMMO ( underflow protection )
    require(
      payout <= terms.salesLimit.sub(bondSales[epochNum]),
      "Your bond payout cannot exceed the bonds remaining"
    );
    require(payout <= maxPayout(), "Bond too large"); // size protection because there is no slippage

    // profits are calculated
    uint256 fee = payout.mul(terms.fee).div(10000);
    uint256 profit = value.div(1e18).sub(payout).sub(fee);

    /**
      principle is transferred in,
      approved and
      deposited into the treasury, returning (_amount - profit) IMMO
         */
    IERC20(principle).safeTransferFrom(msg.sender, address(this), _amount);
    IERC20(principle).approve(address(treasury), _amount);
    ITreasury(treasury).deposit(_amount, principle, profit);

    if (fee != 0) {
      // fee is transferred to DAO
      IERC20(IMMO).safeTransfer(DAO, fee);
    }

    IERC20(IMMO).approve(stakingHelper, payout);

    IStakingHelper(stakingHelper).stake(payout, address(this));

    uint256 stakeGons = IsIMMO(sIMMO).gonsForBalance(payout);

    // depositor info is stored
    bondInfo[_depositor] = Bond({
      gonsPayout: bondInfo[_depositor].gonsPayout.add(stakeGons),
      immoPayout: bondInfo[_depositor].immoPayout.add(payout),
      vesting: terms.vestingTerm,
      lastTime: uint32(block.timestamp),
      pricePaid: price
    });

    bondSales[epochNum] = bondSales[epochNum].add(payout);

    // indexed events are emitted
    emit BondCreated(
      _amount,
      payout,
      block.timestamp.add(terms.vestingTerm),
      price
    );

    return payout;
  }

  /**
   *  @notice redeem bond for user
   *  @param _recipient address
   *  @return uint
   */
  function redeem(address _recipient) external returns (uint256) {
    Bond memory info = bondInfo[_recipient];
    uint256 percentVested = percentVestedFor(_recipient);

    require(percentVested >= 10000, "not yet fully vested");

    delete bondInfo[_recipient]; // delete user info
    uint256 _amount = IsIMMO(sIMMO).balanceForGons(info.gonsPayout);
    emit BondRedeemed(_recipient, _amount, 0); // emit bond data
    IERC20(sIMMO).transfer(_recipient, _amount); // pay user everything due
    return _amount;
  }

  /* ======== VIEW FUNCTIONS ======== */

  /**
   *  @notice determine maximum bond size
   *  @return uint
   */
  function maxPayout() public view returns (uint256) {
    return IERC20(IMMO).totalSupply().mul(terms.maxPayout).div(100000);
  }

  /**
   *  @notice calculate interest due for new bond
   *  @param _value uint
   *  @return uint
   */
  function payoutFor(uint256 _value) public view returns (uint256) {
    return _value.div(bondPrice()).div(1e9);
  }

  /**
   *  @notice calculate current bond price in mcUSD in 9 decimals
   *  @return price_ uint
   */
  function bondPrice() public view returns (uint256 price_) {
    uint256 denominator = 10000;
    if (terms.isDiscountPositive) {
      price_ = getMarketPrice().mul(denominator.sub(terms.discount)).div(
        denominator
      );
    } else {
      price_ = getMarketPrice().mul(denominator.add(terms.discount)).div(
        denominator
      );
    }

    if (price_ < terms.minimumPrice) {
      price_ = terms.minimumPrice;
    }
  }

  /**
   *  @notice calculate latest IMMO market price in mcUSD in 9 decimals
   *  @return price_ uint
   */
  function getMarketPrice() public view returns (uint256 price_) {
    (uint256 reserve0, uint256 reserve1, ) = IUniswapV2Pair(liquidityPair)
      .getReserves();
    price_ = reserve0.div(reserve1);
  }

  /**
   *  @notice calculate latest LP value in mcUSD in 27 decimals
   *  @return price_ uint
   */
  function getLPValue(uint256 _amount) public view returns (uint256 price_) {
    (uint256 reserve0, , ) = IUniswapV2Pair(liquidityPair).getReserves();
    uint256 totalLPSupply = IUniswapV2Pair(liquidityPair).totalSupply();
    price_ = FixedPoint
      .fraction(_amount, totalLPSupply)
      .decode112with18()
      .mul(reserve0)
      .mul(2)
      .div(1e9);
  }

  /**
   *  @notice calculate how far into vesting a depositor is
   *  @param _depositor address
   *  @return percentVested_ uint
   */
  function percentVestedFor(address _depositor)
    public
    view
    returns (uint256 percentVested_)
  {
    Bond memory bond = bondInfo[_depositor];
    uint256 secondsSinceLast = uint32(block.timestamp).sub(bond.lastTime);
    uint256 vesting = bond.vesting;

    if (vesting > 0) {
      percentVested_ = secondsSinceLast.mul(10000).div(vesting);
    } else {
      percentVested_ = 0;
    }
  }

  /**
   *  @notice calculate amount of sIMMO pending for depositor
   *  @param _depositor address
   *  @return pendingPayout_ uint
   */
  function pendingPayoutFor(address _depositor)
    external
    view
    returns (uint256 pendingPayout_)
  {
    pendingPayout_ = IsIMMO(sIMMO).balanceForGons(
      bondInfo[_depositor].gonsPayout
    );
  }

  /**
   *  @notice calculate amount of sIMMO claimable by depositor
   *  @param _depositor address
   *  @return claimablePayout_ uint
   */
  function claimablePayoutFor(address _depositor)
    external
    view
    returns (uint256 claimablePayout_)
  {
    uint256 percentVested = percentVestedFor(_depositor);

    if (percentVested >= 10000) {
      claimablePayout_ = IsIMMO(sIMMO).balanceForGons(
        bondInfo[_depositor].gonsPayout
      );
    } else {
      claimablePayout_ = 0;
    }
  }

  /**
   *  @notice get number of bonds sold for this epoch
   *  @return uint
   */
  function currentBondSales() public view returns (uint256) {
    uint256 epochNum = (block.timestamp.sub(bondInitTime)).div(epochLength);
    return bondSales[epochNum];
  }

  /**
   *  @notice get number of bonds left available to buy
   *  @return uint
   */
  function currentBondLeft() external view returns (uint256) {
    return terms.salesLimit.sub(currentBondSales());
  }

  /* ======= AUXILLIARY ======= */

  /**
   *  @notice send lost tokens to DAO
   *  @return bool
   */
  function recoverLostToken(address _token) external onlyPolicy returns (bool) {
    require(_token != IMMO);
    require(_token != sIMMO);
    require(_token != principle);
    IERC20(_token).safeTransfer(DAO, IERC20(_token).balanceOf(address(this)));
    return true;
  }
}