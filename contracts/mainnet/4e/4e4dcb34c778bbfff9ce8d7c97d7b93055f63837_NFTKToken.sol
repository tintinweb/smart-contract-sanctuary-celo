pragma solidity 0.8.2;

interface BIP20 {
  function totalSupply() external view returns (uint24);
  function decimals() external view returns (uint8);
  function symbol() external view returns (string memory);
  function name() external view returns (string memory);
  function getOwner() external view returns (address);
  function balanceOf(address account) external view returns (uint24);
  function transfer(address recipient, uint24 amount) external returns (bool);
  function allowance(address _owner, address spender) external view returns (uint24);
  function approve(address spender, uint24 amount) external returns (bool);
  function transferFrom(address sender, address recipient, uint24 amount) external returns (bool);
  event Transfer(address indexed from, address indexed to, uint24 value);
  event Approval(address indexed owner, address indexed spender, uint24 value);
} 

library ECDSA {
    function recover(bytes32 hash, bytes memory signature) internal pure returns (address) {
        // Divide the signature in r, s and v variables
        bytes32 r;
        bytes32 s;
        uint8 v;
        if (signature.length == 65) {
            assembly {
                r := mload(add(signature, 0x20))
                s := mload(add(signature, 0x40))
                v := byte(0, mload(add(signature, 0x60)))
            }
        } else if (signature.length == 64) {
            // ecrecover takes the signature parameters, and the only way to get them
            // currently is to use assembly.
            // solhint-disable-next-line no-inline-assembly
            assembly {
                let vs := mload(add(signature, 0x40))
                r := mload(add(signature, 0x20))
                s := and(vs, 0x7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff)
                v := add(shr(255, vs), 27)
            }
        } else {
            revert("ECDSA: invalid signature length");
        }

        return recover(hash, v, r, s);
    }
    function recover(bytes32 hash, uint8 v, bytes32 r, bytes32 s) internal pure returns (address) {
        require(uint256(s) <= 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0, "ECDSA: invalid signature 's' value");
        require(v == 27 || v == 28, "ECDSA: invalid signature 'v' value");
        address signer = ecrecover(hash, v, r, s);
        require(signer != address(0), "ECDSA: invalid signature");
        return signer;
    }
    function toEthSignedMessageHash(bytes32 hash) internal pure returns (bytes32) {
        // 32 is the length in bytes of hash,
        // enforced by the type signature above
        return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", hash));
    }
    function toTypedDataHash(bytes32 domainSeparator, bytes32 structHash) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
    }
}
contract Context {
  constructor ()  { }

  function _msgSender() internal view returns (address ) {
    return msg.sender;
  }

  function _msgData() internal view returns (bytes memory) {
    this; 
    return msg.data;
  }
}

library SafeMath {
  function add(uint24 a, uint24 b) internal pure returns (uint24) {
    uint24 c = a + b;
    require(c >= a, "SafeMath: addition overflow");
    return c;
  }
  function sub(uint24 a, uint24 b) internal pure returns (uint24) {
    return sub(a, b, "SafeMath: subtraction overflow");
  }

  function sub(uint24 a, uint24 b, string memory errorMessage) internal pure returns (uint24) {
    require(b <= a, errorMessage);
    uint24 c = a - b;

    return c;
  }
  function mul(uint24 a, uint24 b) internal pure returns (uint24) {
    // See: https://github.com/OpenZeppelin/openzeppelin-contracts/pull/522
    if (a == 0) {
      return 0;
    }

    uint24 c = a * b;
    require(c / a == b, "SafeMath: multiplication overflow");

    return c;
  }

  function div(uint24 a, uint24 b) internal pure returns (uint24) {
    return div(a, b, "SafeMath: division by zero");
  }

  function div(uint24 a, uint24 b, string memory errorMessage) internal pure returns (uint24) {
    // Solidity only automatically asserts when dividing by 0
    require(b > 0, errorMessage);
    uint24 c = a / b;
    // assert(a == b * c + a % b); // There is no case in which this doesn't hold

    return c;
  }

  function mod(uint24 a, uint24 b) internal pure returns (uint24) {
    return mod(a, b, "SafeMath: modulo by zero");
  }

  function mod(uint24 a, uint24 b, string memory errorMessage) internal pure returns (uint24) {
    require(b != 0, errorMessage);
    return a % b;
  }
}

contract Ownable is Context {
  address private _owner;

  event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

  constructor ()  {
    address msgSender = _msgSender();
    _owner = msgSender;
    emit OwnershipTransferred(address(0), msgSender);
  }

  function owner() public view returns (address) {
    return _owner;
  }

  modifier onlyOwner() {
    require(_owner == _msgSender(), "Ownable: caller is not the owner");
    _;
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

contract NFTKToken is Context, BIP20, Ownable {
  using SafeMath for uint24;

  mapping (address => uint24) private _balances;

  mapping (address => mapping (address => uint24)) private _allowances;

  uint24 private _totalSupply;
  uint8 private _decimals;
  string private _symbol;
  string private _name;
  string private _ico;
  string private _baseURI;
 
  constructor() public {
    _name = "NFTicket Pay Token";
    _symbol = "NFTK";
    _decimals = 0;
    _ico = "QmPNAJEacA9FRnkirZxqm1xav4QizRhrNPNuSiX9yS3Vp2";
    _totalSupply = 400000;
    _balances[msg.sender] = _totalSupply;
    _baseURI="https://ipfs.io/ipfs/";
    DOMAIN_SEPARATOR = hashEIP712Domain(
    EIP712Domain({
                name : "EIP712Domain",
                version : "1",
                chainId : 100,
                verifyingContract : address(this)
                }));
    emit Transfer(address(0), msg.sender, _totalSupply);
  }

  function setBaseURI(string calldata _uri) external  returns (bool) {
    require(owner()==msg.sender,"Only owner");
    _baseURI = _uri;
    return true;
  }

  function getOwner() override external view returns (address) {
    return owner();
  }

  function getIconCID() external view returns (string memory) {
    return _ico;
  }
  function getBaseURI() external view returns (string memory) {
    return _baseURI;
  }

  function decimals() override external view returns (uint8) {
    return _decimals;
  }
  function symbol() override external view returns (string memory) {
    return _symbol;
  }
  function ico() external view returns (string memory) {
    return string(abi.encodePacked(_baseURI, _ico));
  }
  function icon() external view returns (string memory) {
    return string(abi.encodePacked(_baseURI, _ico));
  }

  /**
  * @dev Returns the token name.
  */
  function name() override external view returns (string memory) {
    return _name;
  }

  function totalSupply() override external view returns (uint24) {
    return _totalSupply;
  }

  function balanceOf(address account) override external view returns (uint24) {
    return _balances[account];
  }

  function transfer(address recipient, uint24 amount) override external returns (bool) {
    _transfer(_msgSender(), recipient, amount);
    return true;
  }

  function allowance(address owner, address spender) override external view returns (uint24) {
    return _allowances[owner][spender];
  }
  function approve(address spender, uint24 amount) override external returns (bool) {
    _approve(_msgSender(), spender, amount);
    return true;
  }

  function transferFrom(address sender, address recipient, uint24 amount) override external returns (bool) {
    _transfer(sender, recipient, amount);
    _approve(sender, _msgSender(), _allowances[sender][_msgSender()].sub(amount, "NFTicket: transfer amount exceeds allowance"));
    return true;
  }

  function increaseAllowance(address spender, uint24 addedValue) public returns (bool) {
    _approve(_msgSender(), spender, _allowances[_msgSender()][spender].add(addedValue));
    return true;
  }

  function decreaseAllowance(address spender, uint24 subtractedValue) public returns (bool) {
    _approve(_msgSender(), spender, _allowances[_msgSender()][spender].sub(subtractedValue, "NFTicket: decreased allowance below zero"));
    return true;
  }

  function mint(uint24 amount) public onlyOwner returns (bool) {
    _mint(_msgSender(), amount);
    return true;
  }

  function _transfer(address sender, address recipient, uint24 amount) internal {
    require(sender != address(0), "NFTicket: transfer from the zero address");
    require(recipient != address(0), "NFTicket: transfer to the zero address");

    _balances[sender] = _balances[sender].sub(amount, "NFTicket: transfer amount exceeds balance");
    _balances[recipient] = _balances[recipient].add(amount);
    emit Transfer(sender, recipient, amount);
  }

  function _mint(address account, uint24 amount) internal {
    require(account != address(0), "NFTicket: mint to the zero address");

    _totalSupply = _totalSupply.add(amount);
    _balances[account] = _balances[account].add(amount);
    emit Transfer(address(0), account, amount);
  }

  function _burn(address account, uint24 amount) internal {
    require(account != address(0), "NFTicket: burn from the zero address");

    _balances[account] = _balances[account].sub(amount, "NFTicket: burn amount exceeds balance");
    _totalSupply = _totalSupply.sub(amount);
    emit Transfer(account, address(0), amount);
  }

  function _approve(address owner, address spender, uint24 amount) internal {
    require(owner != address(0), "NFTicket: approve from the zero address");
    require(spender != address(0), "NFTicket: approve to the zero address");

    _allowances[owner][spender] = amount;
    emit Approval(owner, spender, amount);
  }

  function _burnFrom(address account, uint24 amount) internal {
    _burn(account, amount);
    _approve(account, _msgSender(), _allowances[account][_msgSender()].sub(amount, "NFTicket: burn amount exceeds allowance"));
  }

  /*SenderApprove*/
    using ECDSA for bytes32;
    bytes32 DOMAIN_SEPARATOR;
    bytes32 constant EIP712DOMAIN_TYPEHASH = keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 constant internal VERIFIABLE_CREDENTIAL_TYPEHASH = keccak256("VerifiableCredential(address _from,address _to,string memory _nonce,uint24 _amount)");
    struct EIP712Domain {string name;string version;uint256 chainId;address verifyingContract;}
  
    function hashEIP712Domain(EIP712Domain memory eip712Domain) internal pure returns (bytes32) {
        return keccak256(abi.encode(EIP712DOMAIN_TYPEHASH,keccak256(bytes(eip712Domain.name)),keccak256(bytes(eip712Domain.version)),eip712Domain.chainId,eip712Domain.verifyingContract));
    }

    function hashForSigned(address _from, address _to, string memory nonce, uint24 amount) public view returns (bytes32) {
        return (_hashForSigned(nonce, _from, _to, amount));
    }

    function hashVerifiableCredential(address _from,address _to,string memory _nonce,uint24 _amount) private pure returns (bytes32) {//0xAABBCC11223344....556677
        return keccak256(abi.encode(VERIFIABLE_CREDENTIAL_TYPEHASH, _from, _to, _nonce,_amount));
    }

    function _hashForSigned(string memory _nonce, address _from, address _to, uint24 _amount) internal view returns (bytes32) {
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                DOMAIN_SEPARATOR,
                hashVerifiableCredential(_from, _to, _nonce, _amount)
            )
        );
        return (digest);
    }
    struct metadata {
        address from;
        address to;
        uint24 amount;
        uint256 timestamp;
    } 
    mapping (string=>metadata) public nonces;
    
    function transferEndorsed(address _to, uint24 _amount, string calldata nonce, bytes32 _credentialHash, bytes memory _signature ) external  {
        address _from = _credentialHash.recover(_signature);
        require(nonces[nonce].timestamp==0, "nonce has been used");
        
        require(keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32",hashForSigned(_from, _to, nonce, _amount)))==_credentialHash, "Rejected Signed");
        nonces[nonce] = metadata(_from, _to, _amount, block.timestamp);
        _transfer(_from, _to, _amount);
    }
}