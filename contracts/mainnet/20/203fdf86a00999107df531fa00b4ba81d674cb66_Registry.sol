pragma solidity ^0.5.3;


library SafeMath {
    
    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a, "SafeMath: addition overflow");

        return c;
    }

    
    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        return sub(a, b, "SafeMath: subtraction overflow");
    }

    
    function sub(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
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

    
    function div(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        
        require(b > 0, errorMessage);
        uint256 c = a / b;
        

        return c;
    }

    
    function mod(uint256 a, uint256 b) internal pure returns (uint256) {
        return mod(a, b, "SafeMath: modulo by zero");
    }

    
    function mod(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b != 0, errorMessage);
        return a % b;
    }
}

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

interface IRegistry {
  function setAddressFor(string calldata, address) external;
  function getAddressForOrDie(bytes32) external view returns (address);
  function getAddressFor(bytes32) external view returns (address);
  function isOneOf(bytes32[] calldata, address) external view returns (bool);
}

contract Initializable {
  bool public initialized;

  modifier initializer() {
    require(!initialized, "contract already initialized");
    initialized = true;
    _;
  }
}

contract Registry is IRegistry, Ownable, Initializable {
  using SafeMath for uint256;

  mapping(bytes32 => address) public registry;

  event RegistryUpdated(string identifier, bytes32 indexed identifierHash, address indexed addr);

  
  function initialize() external initializer {
    _transferOwnership(msg.sender);
  }

  
  function setAddressFor(string calldata identifier, address addr) external onlyOwner {
    bytes32 identifierHash = keccak256(abi.encodePacked(identifier));
    registry[identifierHash] = addr;
    emit RegistryUpdated(identifier, identifierHash, addr);
  }

  
  function getAddressForOrDie(bytes32 identifierHash) external view returns (address) {
    require(registry[identifierHash] != address(0), "identifier has no registry entry");
    return registry[identifierHash];
  }

  
  function getAddressFor(bytes32 identifierHash) external view returns (address) {
    return registry[identifierHash];
  }

  
  function getAddressForStringOrDie(string calldata identifier) external view returns (address) {
    bytes32 identifierHash = keccak256(abi.encodePacked(identifier));
    require(registry[identifierHash] != address(0), "identifier has no registry entry");
    return registry[identifierHash];
  }

  
  function getAddressForString(string calldata identifier) external view returns (address) {
    bytes32 identifierHash = keccak256(abi.encodePacked(identifier));
    return registry[identifierHash];
  }

  
  function isOneOf(bytes32[] calldata identifierHashes, address sender)
    external
    view
    returns (bool)
  {
    for (uint256 i = 0; i < identifierHashes.length; i = i.add(1)) {
      if (registry[identifierHashes[i]] == sender) {
        return true;
      }
    }
    return false;
  }
}