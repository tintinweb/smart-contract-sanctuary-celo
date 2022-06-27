pragma solidity ^0.5.3;


contract Context {
    
    
    constructor () internal { }
    

    function _msgSender() internal view returns (address payable) {
        return msg.sender;
    }

    function _msgData() internal view returns (bytes memory) {
        this; 
        return msg.data;
    }
}

contract Ownable is Context {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    
    constructor () internal {
        address msgSender = _msgSender();
        _owner = msgSender;
        emit OwnershipTransferred(address(0), msgSender);
    }

    
    function owner() public view returns (address) {
        return _owner;
    }

    
    modifier onlyOwner() {
        require(isOwner(), "Ownable: caller is not the owner");
        _;
    }

    
    function isOwner() public view returns (bool) {
        return _msgSender() == _owner;
    }

    
    function renounceOwnership() public onlyOwner {
        emit OwnershipTransferred(_owner, address(0));
        _owner = address(0);
    }

    
    function transferOwnership(address newOwner) public onlyOwner {
        _transferOwnership(newOwner);
    }

    
    function _transferOwnership(address newOwner) internal {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}

contract Initializable {
  bool public initialized;

  modifier initializer() {
    require(!initialized, "contract already initialized");
    initialized = true;
    _;
  }
}

contract BlockchainParameters is Ownable, Initializable {
  struct ClientVersion {
    uint256 major;
    uint256 minor;
    uint256 patch;
  }

  ClientVersion private minimumClientVersion;
  uint256 public blockGasLimit;
  uint256 public intrinsicGasForAlternativeFeeCurrency;

  event MinimumClientVersionSet(uint256 major, uint256 minor, uint256 patch);
  event IntrinsicGasForAlternativeFeeCurrencySet(uint256 gas);
  event BlockGasLimitSet(uint256 limit);

  
  function initialize(
    uint256 major,
    uint256 minor,
    uint256 patch,
    uint256 _gasForNonGoldCurrencies,
    uint256 gasLimit
  ) external initializer {
    _transferOwnership(msg.sender);
    setMinimumClientVersion(major, minor, patch);
    setBlockGasLimit(gasLimit);
    setIntrinsicGasForAlternativeFeeCurrency(_gasForNonGoldCurrencies);
  }

  
  function setMinimumClientVersion(uint256 major, uint256 minor, uint256 patch) public onlyOwner {
    minimumClientVersion.major = major;
    minimumClientVersion.minor = minor;
    minimumClientVersion.patch = patch;
    emit MinimumClientVersionSet(major, minor, patch);
  }

  
  function setBlockGasLimit(uint256 gasLimit) public onlyOwner {
    blockGasLimit = gasLimit;
    emit BlockGasLimitSet(gasLimit);
  }

  
  function setIntrinsicGasForAlternativeFeeCurrency(uint256 gas) public onlyOwner {
    intrinsicGasForAlternativeFeeCurrency = gas;
    emit IntrinsicGasForAlternativeFeeCurrencySet(gas);
  }

  
  function getMinimumClientVersion()
    external
    view
    returns (uint256 major, uint256 minor, uint256 patch)
  {
    return (minimumClientVersion.major, minimumClientVersion.minor, minimumClientVersion.patch);
  }

}