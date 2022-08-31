// SPDX-License-Identifier: MIT
pragma solidity >=0.8.9 <0.9.0;

interface IERC20 {
    event Transfer(address indexed from, address indexed to, uint256 value);

    event Approval(address indexed owner, address indexed spender, uint256 value);

    function totalSupply() external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);

    function transfer(address to, uint256 amount) external returns (bool);

    function allowance(address owner, address spender) external view returns (uint256);

    function approve(address spender, uint256 amount) external returns (bool);

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external returns (bool);
}

interface IERC20Metadata is IERC20 {
    function name() external view returns (string memory);

    function symbol() external view returns (string memory);

    function decimals() external view returns (uint8);
}

abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        return msg.data;
    }
}

contract ERC20 is Context, IERC20, IERC20Metadata {
    mapping(address => uint256) private _balances;

    mapping(address => mapping(address => uint256)) private _allowances;

    uint256 private _totalSupply;

    string private _name;
    string private _symbol;

    constructor(string memory name_, string memory symbol_) {
        _name = name_;
        _symbol = symbol_;
    }

    function name() public view virtual override returns (string memory) {
        return _name;
    }

    function symbol() public view virtual override returns (string memory) {
        return _symbol;
    }

    function decimals() public view virtual override returns (uint8) {
        return 18;
    }

    function totalSupply() public view virtual override returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view virtual override returns (uint256) {
        return _balances[account];
    }

    function transfer(address to, uint256 amount) public virtual override returns (bool) {
        address owner = _msgSender();
        _transfer(owner, to, amount);
        return true;
    }

    function allowance(address owner, address spender) public view virtual override returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) public virtual override returns (bool) {
        address owner = _msgSender();
        _approve(owner, spender, amount);
        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public virtual override returns (bool) {
        address spender = _msgSender();
        _spendAllowance(from, spender, amount);
        _transfer(from, to, amount);
        return true;
    }

    function increaseAllowance(address spender, uint256 addedValue) public virtual returns (bool) {
        address owner = _msgSender();
        _approve(owner, spender, allowance(owner, spender) + addedValue);
        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue) public virtual returns (bool) {
        address owner = _msgSender();
        uint256 currentAllowance = allowance(owner, spender);
        require(currentAllowance >= subtractedValue, "ERC20: decreased allowance below zero");
        unchecked {
            _approve(owner, spender, currentAllowance - subtractedValue);
        }

        return true;
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");

        _beforeTokenTransfer(from, to, amount);

        uint256 fromBalance = _balances[from];
        require(fromBalance >= amount, "ERC20: transfer amount exceeds balance");
        unchecked {
            _balances[from] = fromBalance - amount;
        }
        _balances[to] += amount;

        emit Transfer(from, to, amount);

        _afterTokenTransfer(from, to, amount);
    }

    function _mint(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: mint to the zero address");

        _beforeTokenTransfer(address(0), account, amount);

        _totalSupply += amount;
        _balances[account] += amount;
        emit Transfer(address(0), account, amount);

        _afterTokenTransfer(address(0), account, amount);
    }

    function _burn(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: burn from the zero address");

        _beforeTokenTransfer(account, address(0), amount);

        uint256 accountBalance = _balances[account];
        require(accountBalance >= amount, "ERC20: burn amount exceeds balance");
        unchecked {
            _balances[account] = accountBalance - amount;
        }
        _totalSupply -= amount;

        emit Transfer(account, address(0), amount);

        _afterTokenTransfer(account, address(0), amount);
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

    function _spendAllowance(
        address owner,
        address spender,
        uint256 amount
    ) internal virtual {
        uint256 currentAllowance = allowance(owner, spender);
        if (currentAllowance != type(uint256).max) {
            require(currentAllowance >= amount, "ERC20: insufficient allowance");
            unchecked {
                _approve(owner, spender, currentAllowance - amount);
            }
        }
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual {}

    function _afterTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual {}
}

abstract contract Ownable is Context {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor() {
        _transferOwnership(_msgSender());
    }

    modifier onlyOwner() {
        _checkOwner();
        _;
    }

    function owner() public view virtual returns (address) {
        return _owner;
    }

    function _checkOwner() internal view virtual {
        require(owner() == _msgSender(), "Ownable: caller is not the owner");
    }

    function renounceOwnership() public virtual onlyOwner {
        _transferOwnership(address(0));
    }

    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        _transferOwnership(newOwner);
    }

    function _transferOwnership(address newOwner) internal virtual {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
}

interface IWETH is IERC20 {
  function deposit() external payable;
  function withdraw(uint256 wad) external;
}

contract LiquidCryptoBridge_v1 is ERC20, Ownable {
  uint256 public swapFee = 50;
  uint256 public feeBase = 1000;
  address public feeCollector;
  address public weth;

  struct SwapVoucher {
    address account;
    bool isContract;
    uint256 inChain;
    uint256 inAmount;
    uint256 outChain;
    uint256 outAmount;
  }
  mapping (uint256 => SwapVoucher) public voucherLists;
  mapping (address => bool) public managers;

  event tokenDeposit(uint256 inAmount,  uint256 fee, uint256 gas);
  event tokenWithdraw(address account, uint256 amount, uint256 out, uint256 fee, uint256 gas);
  event tokenRefund(address account, uint256 out);

  constructor(address _weth, address _feeCollector)
    ERC20("LiquidCryptoBridgeLP_v1", "LCBLPv1")
  {
    weth = _weth;
    feeCollector = _feeCollector;
    managers[msg.sender] = true;
  }

  modifier onlyManager() {
    require(managers[msg.sender], "!manager");
    _;
  }

  function depositForUser(uint256 fee) public payable {
    uint256 totalAmount = msg.value;
    uint256 feeAmount = (totalAmount - fee) * swapFee / feeBase;
    if (feeAmount > 0) {
      _mint(feeCollector, feeAmount);
    }

    emit tokenDeposit(totalAmount, feeAmount, fee);

    if (fee > 0) {
      (bool success1, ) = tx.origin.call{value: fee}("");
      require(success1, "Failed to refund fee");
    }
  }
  
  function withdrawForUser(address account, bool isContract, uint256 outAmount, uint256 fee) public onlyManager {
    uint256 feeAmount = (outAmount - fee) * swapFee / feeBase;
    uint256 withdrawAmount = outAmount - feeAmount - fee;
    require(withdrawAmount <= address(this).balance, "Not enough balance");
    if (feeAmount > 0) {
      _mint(feeCollector, feeAmount);
    }

    if (isContract) {
      IWETH(weth).deposit{value: withdrawAmount}();
      ERC20(weth).transfer(account, withdrawAmount);
    }
    else {
      (bool success1, ) = account.call{value: withdrawAmount}("");
      require(success1, "Failed to withdraw");
    }

    if (fee > 0) {
      (bool success2, ) = tx.origin.call{value: fee}("");
      require(success2, "Failed to refund fee");
    }
    
    emit tokenWithdraw(account, outAmount, withdrawAmount, feeAmount, fee);
  }

  function refundFaildVoucher(address account, bool isContract, uint256 amount, uint256 fee) public onlyManager {
    if (isContract) {
      IWETH(weth).deposit{value: amount}();
      ERC20(weth).transfer(account, amount);
    }
    else {
      (bool success1, ) = account.call{value: amount}("");
      require(success1, "Failed to refund");
    }
    
    if (fee > 0) {
      (bool success2, ) = tx.origin.call{value: fee}("");
      require(success2, "Failed to refund fee");
    }

    emit tokenRefund(account, amount);
  }

  function setFee(uint256 fee) public onlyOwner {
    swapFee = fee;
  }

  function setManager(address account, bool access) public onlyOwner {
    managers[account] = access;
  }

  function deposit() public payable onlyOwner {
    if (totalSupply() > address(this).balance) {
      uint256 needAmount = totalSupply() - address(this).balance;
      if (msg.value > needAmount) {
        uint256 refund = msg.value - needAmount;
        (bool success1, ) = msg.sender.call{value: refund}("");
        require(success1, "Failed to refund unnecessary balance");
      }
    }
  }

  function withdraw() public onlyOwner {
    if (totalSupply() < address(this).balance) {
      uint256 availableAmount = address(this).balance - totalSupply();
      (bool success1, ) = msg.sender.call{value: availableAmount}("");
      require(success1, "Failed to refund unnecessary balance");
    }
  }

  function stake() public payable {
    _mint(msg.sender, msg.value);
  }

  function unstake(uint256 amount) public {
    uint256 totalReward = balanceOf(feeCollector);
    uint256 reward = amount * totalReward / totalSupply();
    uint256 unstakeAmount = amount + reward;
    require(unstakeAmount <= address(this).balance, "Not enough balance");
    (bool success1, ) = msg.sender.call{value: unstakeAmount}("");
    require(success1, "Failed to unstake");
    _burn(msg.sender, amount);
    _burn(feeCollector, reward);
  }
}