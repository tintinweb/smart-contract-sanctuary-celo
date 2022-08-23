// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

library AddressUtils {
  function isContract(address _addr) internal view returns (bool addressCheck) {
    // This method relies in extcodesize, which returns 0 for contracts in
    // construction, since the code is only stored at the end of the
    // constructor execution.

    // According to EIP-1052, 0x0 is the value returned for not-yet created accounts
    // and 0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470 is returned
    // for accounts without code, i.e. `keccak256('')`
    bytes32 codehash;
    bytes32 accountHash = 0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470;
    assembly { codehash := extcodehash(_addr) } // solhint-disable-line
    addressCheck = (codehash != 0x0 && codehash != accountHash);
  }
}

contract NFToken   {
  using AddressUtils for address;

  /**
   * @dev List of revert message codes. Implementing dApp should handle showing the correct message.
   * Based on 0xcert framework error codes.
   */
  string constant ZERO_ADDRESS = "003001";
  string constant NOT_VALID_NFT = "003002";
  string constant NOT_OWNER_OR_OPERATOR = "003003";
  string constant NOT_OWNER_APPROVED_OR_OPERATOR = "003004";
  string constant NOT_ABLE_TO_RECEIVE_NFT = "003005";
  string constant NFT_ALREADY_EXISTS = "003006";
  string constant NOT_OWNER = "003007";
  string constant IS_OWNER = "003008";
  address contractOwner ;
  /**
   * @dev Magic value of a smart contract that can recieve NFT.
   * Equal to: bytes4(keccak256("onERC721Received(address,address,uint256,bytes)")).
   */
  bytes4 internal constant MAGIC_ON_ERC721_RECEIVED = 0x150b7a02;

    
  /**
   * @dev A mapping from NFT ID to the address that owns it.
   */
  mapping (uint256 => address) internal idToOwner;



   /**
   * @dev Mapping from owner address to count of his tokens.
   */
  mapping (address => uint256) private ownerToNFTokenCount;

 
  modifier validNFToken(uint256 _tokenId) {
    require(idToOwner[_tokenId] != address(0), NOT_VALID_NFT);
    _;
  }
  modifier onlyOwner() {
    require(contractOwner == msg.sender, NOT_OWNER_OR_OPERATOR);
    _;
  }

  mapping(bytes4 => bool) internal supportedInterfaces;
  constructor()  {
    supportedInterfaces[0x80ac58cd] = true; // ERC721
    supportedInterfaces[0x01ffc9a7] = true; // ERC165
    contractOwner= msg.sender;
  }


  function supportsInterface (bytes4 _interfaceID) external  view returns (bool) {
    return supportedInterfaces[_interfaceID];
  }

  function balanceOf(address _owner) external  view returns (uint256) {
    require(_owner != address(0), ZERO_ADDRESS);
    return _getOwnerNFTCount(_owner);
  }

  function ownerOf(uint256 _tokenId) external  view returns (address _owner) {
    _owner = idToOwner[_tokenId];
    require(_owner != address(0), NOT_VALID_NFT);
  }

  function _mint(address _to, uint256 _tokenId) internal  {
    require(_to != address(0), ZERO_ADDRESS);
    require(idToOwner[_tokenId] == address(0), NFT_ALREADY_EXISTS);
    _addNFToken(_to, _tokenId);
  }

  function _addNFToken(address _to, uint256 _tokenId) internal  {
    require(idToOwner[_tokenId] == address(0), NFT_ALREADY_EXISTS);
    idToOwner[_tokenId] = _to;
    ownerToNFTokenCount[_to] = ownerToNFTokenCount[_to] + 1;
    
  }

  function _getOwnerNFTCount(address _owner) internal  view returns (uint256) {
    return ownerToNFTokenCount[_owner];
  }

    

}

interface ERC721Metadata {
  function name() external view returns (string memory _name);
  function symbol() external view returns (string memory _symbol);
  function tokenURI(uint256 _tokenId) external view returns (string memory);
}

contract NFTokenMetadata is  NFToken{
  mapping (uint256 => string) internal idToUri;
  string internal  _baseURI; 
  constructor()  {
    supportedInterfaces[0x5b5e139f] = true; // ERC721Metadata
    _baseURI = "https://stamping.mypinata.cloud/ipfs/";
  }

  function tokenURI(uint256 _tokenId) external  view validNFToken(_tokenId) returns (string memory) {
        return bytes(_baseURI).length > 0
            ? string(abi.encodePacked(_baseURI, idToUri[_tokenId]))
            : '';

  }

  function baseURI() public view returns (string memory) {
        return _baseURI;
    }

  function setBaseURI(string calldata _uri) external onlyOwner {
    _baseURI = _uri;
  }

  function _setTokenUri(uint256 _tokenId, string  memory _uri) internal validNFToken(_tokenId) {
     idToUri[_tokenId] = _uri;
  } 


}

/**
 * @title SafeMath
 * @dev Unsigned math operations with safety checks that revert on error
 */
library SafeMath {
    /**
     * @dev Multiplies two unsigned integers, reverts on overflow.
     */
    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        // Gas optimization: this is cheaper than requiring 'a' not being zero, but the
        // benefit is lost if 'b' is also tested.
        // See: https://github.com/OpenZeppelin/openzeppelin-solidity/pull/522
        if (a == 0) {
            return 0;
        }

        uint256 c = a * b;
        require(c / a == b);

        return c;
    }

    /**
     * @dev Integer division of two unsigned integers truncating the quotient, reverts on division by zero.
     */
    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        // Solidity only automatically asserts when dividing by 0
        require(b > 0);
        uint256 c = a / b;
        // assert(a == b * c + a % b); // There is no case in which this doesn't hold

        return c;
    }

    /**
     * @dev Subtracts two unsigned integers, reverts on overflow (i.e. if subtrahend is greater than minuend).
     */
    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b <= a);
        uint256 c = a - b;

        return c;
    }

    /**
     * @dev Adds two unsigned integers, reverts on overflow.
     */
    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a);

        return c;
    }

    /**
     * @dev Divides two unsigned integers and returns the remainder (unsigned integer modulo),
     * reverts when dividing by zero.
     */
    function mod(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b != 0);
        return a % b;
    }
}
library Counters {
    using SafeMath for uint256;

    struct Counter {
        // This variable should never be directly accessed by users of the library: interactions must be restricted to
        // the library's function. As of Solidity v0.5.2, this cannot be enforced, though there is a proposal to add
        // this feature: see https://github.com/ethereum/solidity/issues/4637
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

contract POAVToken is NFTokenMetadata {
    using ECDSA for bytes32;
    bytes32 DOMAIN_SEPARATOR;
    bytes32 constant EIP712DOMAIN_TYPEHASH = keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 constant internal VERIFIABLE_CREDENTIAL_TYPEHASH = keccak256("VerifiableCredential(address issuer,address subject,bytes32 POAV,uint256 validFrom,uint256 validTo)");
    struct EIP712Domain {string name;string version;uint256 chainId;address verifyingContract;}
    enum Status {Undefined, Active, Inactive, Revoked, StandBy}
    using Counters for Counters.Counter;
    Counters.Counter private _tokenIds;
    address public owner;  
    mapping(string => address) private issuersOfPOAV;
    mapping(string => uint256) private validFromOfPOAV;
    mapping(string => mapping(address  => Status)) private statusOfPOAVSubject;
    uint256 private _POAVs;
    string public name;
    string public symbol;
    uint256 public decimals;
    event Transfer(address indexed _from, address indexed _to, uint256 indexed _tokenId);
    event POAVMinted(address indexed issuer, string indexed POAV, uint validFrom );
    event POAVSent(address indexed issuer, string indexed POAV, address indexed subject, uint256 validFrom);
    event POAVStatusChanged(string indexed POAV, address indexed subject, Status _status);

    constructor()  {
        owner = msg.sender;
        decimals = 0;
        name   = "Proof of Attendance Verified";
        symbol = "POAV";
        _POAVs = 0;
        DOMAIN_SEPARATOR = hashEIP712Domain(
            EIP712Domain({
                name : "EIP712Domain",
                version : "1",
                chainId : 100,
                verifyingContract : address(this) //¿Es la dirección de la instancia del contrato?
                }));
    }

    function isIssuerOfPOAV(string calldata _POAV) external view returns (address) {
      return (issuersOfPOAV[_POAV]);
    }
    function isValidFromOfPOAV(string calldata _POAV) external view returns (uint256) {
      return (validFromOfPOAV[_POAV]);
    }
    function getStatusOf(string calldata _POAV, address _subject) external view returns (Status) {
      return (statusOfPOAVSubject[_POAV][_subject]);
    }
    function hashEIP712Domain(EIP712Domain memory eip712Domain) internal pure returns (bytes32) {
        return keccak256(abi.encode(EIP712DOMAIN_TYPEHASH,keccak256(bytes(eip712Domain.name)),keccak256(bytes(eip712Domain.version)),eip712Domain.chainId,eip712Domain.verifyingContract));
    }

    function hashVerifiableCredential(address _issuer,address _subject,string memory _POAV,uint256 _validFrom,uint256 _validTo) internal pure returns (bytes32) {//0xAABBCC11223344....556677
        return keccak256(abi.encode(VERIFIABLE_CREDENTIAL_TYPEHASH,_issuer,_subject,_POAV,_validFrom,_validTo));
    }

    function hashForSigned(string memory _POAV, address _subject) public view returns (bytes32) {
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                DOMAIN_SEPARATOR,
                hashVerifiableCredential(issuersOfPOAV[_POAV], _subject, _POAV, validFromOfPOAV[_POAV], validFromOfPOAV[_POAV]+252478800)
            )
        );
        return (digest);
    }

    function validateSignature(string memory _POAV, address _subject,bytes32  _credentialHash, bytes memory _signature ) public view 
        returns (address, bytes32, bytes32) {
        return (_credentialHash.recover(_signature), hashForSigned(_POAV, _subject), 
        keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32",hashForSigned(_POAV, _subject))));
    }

    function close(string memory _POAV) public returns (bool) {
        require(issuersOfPOAV[_POAV]==msg.sender, "Does not have access");
        issuersOfPOAV[_POAV] = address(0);
        return true;
    }

    function changeStatus(string memory _POAV, address _subject, Status _status) public returns (bool) {
        require(issuersOfPOAV[_POAV]==msg.sender, "Does not have access");
        require(statusOfPOAVSubject[_POAV][_subject] != _status, "There is no change of state");
        statusOfPOAVSubject[_POAV][_subject] = _status;
        emit POAVStatusChanged(_POAV, _subject, _status);
        return true;
    }
    
    function mintEndorsed(string memory _POAV, bytes32  _credentialHash, bytes memory _signature) public returns (bool) {
        address  _issuer = _credentialHash.recover(_signature);
        require(keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32",hashForSigned(_POAV, _issuer)))==_credentialHash, "Rejected POAV");
        require(_issuer!=msg.sender,"You cannot endorse from the same wallet");
        _mintPOAV( _POAV, _issuer, block.timestamp);
        return true;
    }
    
    function mint(string memory _POAV) public returns (bool) {
       _mintPOAV( _POAV, msg.sender, block.timestamp);
        return true;
    }

    function _mintPOAV(string memory _POAV, address _issuer, uint256 _validFrom) private returns (bool) {
        require(issuersOfPOAV[_POAV] == address(0), "POAV already exists");
        issuersOfPOAV[_POAV] = _issuer;
        validFromOfPOAV[_POAV] = _validFrom;
        _POAVs++;
        emit POAVMinted(_issuer, _POAV, _validFrom);
        return true;
    } 

    function burn(string memory _POAV) public returns (bool) {
        require(issuersOfPOAV[_POAV]==msg.sender, "Does not have access");
        delete issuersOfPOAV[_POAV];
        delete validFromOfPOAV[_POAV] ;
        return true;
    }

    function sendToBatchEndorsed(string memory _POAV, address[] memory _subjects, bytes32  _credentialHash, bytes memory _signature) public returns (bool) {
        address  _issuer = _credentialHash.recover(_signature);
        require(keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32",hashForSigned(_POAV, _issuer)))==_credentialHash, "Rejected POAV");
        require(_issuer!=msg.sender,"You cannot endorse from the same wallet");
        
        require(issuersOfPOAV[_POAV]==_issuer, "Does not have access");
        for(uint256 indx = 0; indx < _subjects.length; indx++) {
            _claim(_POAV, _subjects[indx]);
        }
        return (true);
    }

    function sendToBatch(string memory _POAV, address[] memory _subjects) public returns (bool) {
        require(issuersOfPOAV[_POAV]==msg.sender, "Does not have access");
        for(uint256 indx = 0; indx < _subjects.length; indx++) {
            _claim(_POAV, _subjects[indx]);
        }
        return (true);
    }

    function sendToEndorsed(string memory _POAV, address _subject, bytes32  _credentialHash, bytes memory _signature) public returns (uint256) {
        address  _issuer = _credentialHash.recover(_signature);
        require(keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32",hashForSigned(_POAV, _subject)))==_credentialHash, "Rejected POAV");
        require(_issuer!=msg.sender,"You cannot endorse from the same wallet");
        require(issuersOfPOAV[_POAV]==_issuer, "Does not have access");
        
        return (_claim(_POAV, _subject));
    }

    function sendTo(string memory _POAV, address _subject) public returns (uint256) {
        require(issuersOfPOAV[_POAV]==msg.sender, "Does not have access");
        return (_claim(_POAV, _subject));
    }

    function claimFrom(string memory _POAV, bytes32  _credentialHash, bytes memory _signature ) public returns (uint256) {
        require((issuersOfPOAV[_POAV]!=address(0) && issuersOfPOAV[_POAV]==_credentialHash.recover(_signature)), "Does not have access");
        require(keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32",hashForSigned(_POAV, msg.sender)))==_credentialHash, "Rejected POAV");
        return (_claim(_POAV, msg.sender));
    }

    function _claim(string memory _POAV, address _subject) private returns (uint256) {
         require(issuersOfPOAV[_POAV]!=_subject, "Can't self-certify");
         require(statusOfPOAVSubject[_POAV][_subject]==Status.Undefined, "You can only get a POAV");
         
        _tokenIds.increment();
        uint256 newItemId = _tokenIds.current();
        _mint(_subject, newItemId);
        _setTokenUri(newItemId, _POAV);
        statusOfPOAVSubject[_POAV][_subject] = Status.Active;
        emit Transfer(issuersOfPOAV[_POAV], _subject, newItemId);
        emit POAVSent(issuersOfPOAV[_POAV], _POAV, _subject, validFromOfPOAV[_POAV]);
        return newItemId;
    }

    function totalSupply() external  view returns (uint256) {
      return _tokenIds.current();
    }
    function totalPOAVs() external  view returns (uint256) {
      return _POAVs;
    }
}