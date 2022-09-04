// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;
pragma experimental ABIEncoderV2;
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
    // See: https://github.com/OpenZeppelin/openzeppelin-contracts/pull/522
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
    // Solidity only automatically asserts when dividing by 0
    require(b > 0, errorMessage);
    uint256 c = a / b;
    // assert(a == b * c + a % b); // There is no case in which this doesn't hold

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
contract Ownable {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /**
     * @dev The Ownable constructor sets the original `owner` of the contract to the sender
     * account.
     */
    constructor ()  {
        _owner = msg.sender;
        emit OwnershipTransferred(address(0), _owner);
    }

    /**
     * @return the address of the owner.
     */
    function owner() public view returns (address) {
        return _owner;
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        require(isOwner());
        _;
    }

    /**
     * @return true if `msg.sender` is the owner of the contract.
     */
    function isOwner() public view returns (bool) {
        return msg.sender == _owner;
    }

    /**
     * @dev Allows the current owner to relinquish control of the contract.
     * It will not be possible to call the functions with the `onlyOwner`
     * modifier anymore.
     * @notice Renouncing ownership will leave the contract without an owner,
     * thereby removing any functionality that is only available to the owner.
     */
    function renounceOwnership() public onlyOwner {
        emit OwnershipTransferred(_owner, address(0));
        _owner = address(0);
    }

    /**
     * @dev Allows the current owner to transfer control of the contract to a newOwner.
     * @param newOwner The address to transfer ownership to.
     */
    function transferOwnership(address newOwner) public onlyOwner {
        _transferOwnership(newOwner);
    }

    /**
     * @dev Transfers control of the contract to a newOwner.
     * @param newOwner The address to transfer ownership to.
     */
    function _transferOwnership(address newOwner) internal {
        require(newOwner != address(0));
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}

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

contract NFToken is Ownable {
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


  mapping(bytes4 => bool) internal supportedInterfaces;
  constructor()  {
    supportedInterfaces[0x80ac58cd] = true; // ERC721
    supportedInterfaces[0x01ffc9a7] = true; // ERC165
  }


  function supportsInterface (bytes4 _interfaceID) external  view returns (bool) {
    return supportedInterfaces[_interfaceID];
  }

  function balancePOAVOf(address subject) external  view returns (uint256) {
    require(subject != address(0), ZERO_ADDRESS);
    return _getOwnerNFTCount(subject);
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

contract NFTokenMetadata is  NFToken{
  mapping (uint256 => string) internal idToUri;
  string internal  _baseURI; 
  string public name;
  string public symbol;
  uint256 public decimals;
  event Transfer(address indexed _from, address indexed _to, uint256 indexed _tokenId);
  constructor()  {
    decimals = 0;
    
  
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

  function setBaseURI(string calldata _uri) external onlyOwner() {
    _baseURI = _uri;
  }

  function _setTokenUri(uint256 _tokenId, string  memory _uri) internal validNFToken(_tokenId) {
     idToUri[_tokenId] = _uri;
  } 


}

contract EIP712  {
  using ECDSA for bytes32;
  bytes32 DOMAIN_SEPARATOR;
  bytes32 constant EIP712DOMAIN_TYPEHASH = keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
  bytes32 constant internal VERIFIABLE_CREDENTIAL_TYPEHASH = keccak256("VerifiableCredential(address issuer,address subject,bytes32 POAV,uint256 validFrom,uint256 validTo)");
  struct EIP712Domain {string name;string version;uint256 chainId;address verifyingContract;}
  constructor()  {
        DOMAIN_SEPARATOR = hashEIP712Domain(
            EIP712Domain({
                name : "EIP712Domain",
                version : "1",
                chainId : 100,
                verifyingContract : address(this)
                }));
  }
  function hashEIP712Domain(EIP712Domain memory eip712Domain) internal pure returns (bytes32) {
        return keccak256(abi.encode(EIP712DOMAIN_TYPEHASH,keccak256(bytes(eip712Domain.name)),keccak256(bytes(eip712Domain.version)),eip712Domain.chainId,eip712Domain.verifyingContract));
    }

    function hashVerifiableCredential(address _issuer,address _subject,string memory POAVURI,uint256 _validFrom,uint256 _validTo) internal pure returns (bytes32) {//0xAABBCC11223344....556677
        return keccak256(abi.encode(VERIFIABLE_CREDENTIAL_TYPEHASH,_issuer,_subject,POAVURI,_validFrom,_validTo));
    }


    function _hashForSigned(string memory _credentialSubject, address _issuer, address _subject, uint validFrom, uint validTo) internal view returns (bytes32) {
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                DOMAIN_SEPARATOR,
                hashVerifiableCredential(_issuer, _subject, _credentialSubject, validFrom, validTo)
            )
        );
        return (digest);
    }
    

    function _validateSignature(string memory _credentialSubject, address _issuer, address _subject, uint validFrom, uint validTo,bytes32  _credentialHash, bytes memory _signature ) internal view 
        returns (address issuer, bytes32 hashSha256, bytes32 hashKeccak256) {
        return (_credentialHash.recover(_signature), _hashForSigned(_credentialSubject, _issuer, _subject, validFrom, validTo), 
        keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", _hashForSigned(_credentialSubject, _issuer, _subject, validFrom, validTo))));
    }
}
contract FANToken {
  using SafeMath for uint256;
  
  //address ==> Balance
  mapping(address => uint256) internal _balanceFANToken;
  //POAV ==> claims
  mapping(string => uint8) internal _claimFANToken;

  function balanceOf (address subject) external view returns(uint256) {
    return (_balanceFANToken[subject]);
  }

  function claimFANTokenOf (string memory POAVURI) external view returns(uint256) {
    return (_claimFANToken[POAVURI]);
  }

}
contract POAVToken is  EIP712, FANToken, NFTokenMetadata {
  using ECDSA for bytes32;
    using Counters for Counters.Counter;
    Counters.Counter private _tokenIds;
    enum Status {Undefined, Active, Inactive, Revoked, StandBy}
    mapping(string => address) private issuerOfPOAV;
    mapping(string => uint256) private validFromOfPOAV;
    
    mapping(string => uint256) public countPOAVOf;
    
    mapping(string => mapping(address  => Status)) private statusOfPOAVSubject;
    uint256 private POAVURIs;
    //address=>POAVs
    struct _POAV {
        address issuer;
        uint256 id;
        string uri;
        uint8 FANToken;
        uint timestamp;
        uint256 blockNumber;
    }
    struct _POAVMetadata {
        address issuer;
        string uri;
        uint8 FANToken;
        uint validFrom;
        uint timestamp;
        uint256 blockNumber;
        bool isFreeClaim;
    }
    mapping(address => _POAV[]) private _listPOAVFromAddress;
    event minted(address indexed issuer, string indexed POAV, uint validFrom );
    event sent(address indexed issuer, string indexed POAV, address indexed subject, uint256 validFrom);
    event statusChanged(string indexed POAV, address indexed subject, Status _status);
    
    string public DAOUri;
    address public coordinatorDAO;
    address[] private _attendeesOfDAO;
    _POAVMetadata[] private _listPOAV;
    
    mapping (address => uint8) public maxFANTokenIssuer;
    mapping (address => _POAVMetadata[]) internal _listPOAVOf;
    
    //Address of Issuer => FANTokens Total;
    mapping (address => uint256) private _balanceFANTokenEmissionsOf;

    //Address of Issuer => POAV Total;
    mapping (address => uint256) private _balancePOAVEmissions;
    
    //POAV , address of subject ==> true is auth or false not Auth 
    mapping (string => mapping (address => bool)) private _claimAuth;
    uint8 private maxFUNToken;
    //constructor(uint8 _maxFUN, string memory _DAOUri, string memory _symbol)  {
      constructor()  {
      POAVURIs = 0;
      DAOUri = "NFTicket.pe";//_DAOUri;
      maxFUNToken = 100;//_maxFUN;
      coordinatorDAO = msg.sender;
      maxFANTokenIssuer[msg.sender] = 100;//_maxFUN;
      name   = "Proof of Attendance Verified";
      symbol = "TICK";//_symbol;
    }
    function getAttendeesList() external view returns (address[] memory) {
        return _attendeesOfDAO;
    }
    function balanceFANTokenEmissionsOf(address _issuer) external view returns (uint256 FANTokens) {
        return (_balanceFANTokenEmissionsOf[_issuer]);
    }
    function balancePOAVEmissionsOf(address _issuer) external view returns (uint256 POAVs) {
        return (_balancePOAVEmissions[_issuer]);
    }
    function renounceCoordinatorship() external {
         require(coordinatorDAO==msg.sender , "Does not have access");
        coordinatorDAO=address(0);
    }
    function addIssuer(address newIssuer, uint8 _maxFUN) external {
        require(coordinatorDAO==msg.sender || coordinatorDAO==address(0), "Does not have access");
        if (maxFUNToken >= _maxFUN) {
           maxFANTokenIssuer[newIssuer] = _maxFUN;
        }
    }
    /**
    * @dev List of POAVs claims by address.
   */
    function getPOAVListOf(address subject) external view returns(_POAV[] memory){
        return (_listPOAVFromAddress[subject]);
    }
    /**
    * @dev List of POAVs claims by address.
   */
    function getAllPOAVListOf() external view returns(_POAVMetadata[] memory){
        return (_listPOAV);
    }

    function getPOAVListIssuedOf(address _issuer) external view returns(_POAVMetadata[] memory){
        return (_listPOAVOf[_issuer]);
    }

    function getIssuerPOAVOf(string memory POAVURI) external view returns (address) {
      return (issuerOfPOAV[POAVURI]);
    }
    function getValidFromPOAVOf(string memory POAVURI) external view returns (uint256) {
      return (validFromOfPOAV[POAVURI]);
    }
    function getStatusPOAVOf(string memory POAVURI, address _subject) external view returns (Status) {
      return (statusOfPOAVSubject[POAVURI][_subject]);
    }
    /**
    * @dev Mint of POAVs.
      #POAVUri: CID of POAV (IPFS)
   */
    function mint(string memory POAVUri, uint8 _FANToken, bool _freeClaim) public returns (bool) {
       _mintPOAV( POAVUri, msg.sender, block.timestamp, _FANToken, _freeClaim);
        return true;
    }

    function mintEndorsed(string memory POAVURI, bytes32  _credentialHash, bytes memory _signature, uint8 _FANToken, bool _freeClaim) public returns (bool) {
        address  _issuer = _credentialHash.recover(_signature);
        require(keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32",hashForSigned(POAVURI, _issuer)))==_credentialHash, "Rejected POAV");
        require(_issuer!=msg.sender,"You cannot endorse from the same wallet");
        _mintPOAV(POAVURI, _issuer, block.timestamp, _FANToken, _freeClaim);
        return true;
    }

    function _mintPOAV(string memory POAVURI, address _issuer, uint256 _validFrom, uint8 _FanToken,bool _freeClaim) private returns (bool) {
        require(issuerOfPOAV[POAVURI] == address(0), "POAV already exists");
        require(maxFANTokenIssuer[_issuer] >= _FanToken, "Exceeds the MAXFUN allowed in the DAO or the sender has no access");
        _balancePOAVEmissions[_issuer]++;
        issuerOfPOAV[POAVURI] = _issuer;
        _claimAuth[POAVURI][msg.sender]=_freeClaim;
        validFromOfPOAV[POAVURI] = _validFrom;
        POAVURIs++;
        _POAVMetadata memory _poavmetadata = _POAVMetadata(
            _issuer,
            POAVURI,
            _FanToken,
            _validFrom,
            block.timestamp,
            block.number,
            _freeClaim
        );
        _listPOAVOf[_issuer].push(_poavmetadata);
        _listPOAV.push(_poavmetadata);
        _claimFANToken[POAVURI] = _FanToken;
        emit minted(_issuer, POAVURI, _validFrom);
        return true;
    } 

    //EIP712    
    function hashForSigned(string memory POAVURI, address _subject) public view returns (bytes32) {
      return (_hashForSigned(POAVURI,issuerOfPOAV[POAVURI], _subject, validFromOfPOAV[POAVURI], validFromOfPOAV[POAVURI]+252478800 ));
    }

    
    function validateSignature(
      string memory POAVURI, 
      address _subject, 
      bytes32  _credentialHash, 
      bytes memory _signature ) external view 
        returns (address issuer, bytes32 hashKeccak256) {
        return (_credentialHash.recover(_signature), 
        keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", _hashForSigned(POAVURI, issuerOfPOAV[POAVURI], _subject,validFromOfPOAV[POAVURI], validFromOfPOAV[POAVURI]+252478800))));
    }

    function close(string memory POAVURI) public returns (bool) {
        require(issuerOfPOAV[POAVURI]==msg.sender, "Does not have access");
        issuerOfPOAV[POAVURI] = address(0);
        return true;
    }

    function changeStatus(string memory POAVURI, address _subject, Status _status) public returns (bool) {
        require(issuerOfPOAV[POAVURI]==msg.sender, "Does not have access");
        require(statusOfPOAVSubject[POAVURI][_subject] != _status, "There is no change of state");
        statusOfPOAVSubject[POAVURI][_subject] = _status;
        emit statusChanged(POAVURI, _subject, _status);
        return true;
    }
    
    function burn(string memory POAVURI) public returns (bool) {
        require(issuerOfPOAV[POAVURI]==msg.sender, "Does not have access");
        delete issuerOfPOAV[POAVURI];
        delete validFromOfPOAV[POAVURI] ;
        return true;
    }

    function sendToBatchEndorsed(string memory POAVURI, address[] memory _subjects, bytes32  _credentialHash, bytes memory _signature) public returns (bool) {
        address  _issuer = _credentialHash.recover(_signature);
        require(keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32",hashForSigned(POAVURI, _issuer)))==_credentialHash, "Rejected POAV");
        require(_issuer!=msg.sender,"You cannot endorse from the same wallet");
        
        require(issuerOfPOAV[POAVURI]==_issuer, "Does not have access");
        for(uint256 indx = 0; indx < _subjects.length; indx++) {
            _claim(POAVURI, _subjects[indx]);
        }
        return (true);
    }

    function sendToBatch(string memory POAVURI, address[] memory _subjects) public returns (bool) {
        require(issuerOfPOAV[POAVURI]==msg.sender, "Does not have access");
        for(uint256 indx = 0; indx < _subjects.length; indx++) {
            _claim(POAVURI, _subjects[indx]);
        }
        return (true);
    }

    function sendToEndorsed(string memory POAVURI, address _subject, bytes32  _credentialHash, bytes memory _signature) public returns (uint256) {
        address  _issuer = _credentialHash.recover(_signature);
        require(keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32",hashForSigned(POAVURI, _subject)))==_credentialHash, "Rejected POAV");
        require(_issuer!=msg.sender,"You cannot endorse from the same wallet");
        require(issuerOfPOAV[POAVURI]==_issuer, "Does not have access");
        
        return (_claim(POAVURI, _subject));
    }

    function sendTo(string memory POAVURI, address _subject) public returns (uint256) {
        require(issuerOfPOAV[POAVURI]==msg.sender, "Does not have access");
        return (_claim(POAVURI, _subject));
    }

  
    function claim(string memory POAVURI) public returns (uint256) {
        require(_claimAuth[POAVURI][issuerOfPOAV[POAVURI]]==true, "Subject: Does not have access");
        return (_claim(POAVURI, msg.sender));
    }
    
    function claimEndorsed(string memory POAVURI, address _ZPK, bytes32  _credentialHash, bytes memory _signature ) public returns (uint256) {
        require((issuerOfPOAV[POAVURI]!=address(0) && issuerOfPOAV[POAVURI]==_credentialHash.recover(_signature)), "Does not have access");
        require(keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32",hashForSigned(POAVURI, _ZPK)))==_credentialHash, "Rejected POAV");
        return (_claim(POAVURI, msg.sender));
    }

    function claimCodeEndorsed(string memory POAVURI,  bytes32 _credentialHash, bytes memory _signature ) public returns (uint256) {
        require((issuerOfPOAV[POAVURI]!=address(0) && issuerOfPOAV[POAVURI]==_credentialHash.recover(_signature)), "Does not have access");
        require(keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32",POAVURI))==_credentialHash, "Rejected POAV");
        return (_claim(POAVURI, msg.sender));
    }


 /*
    function claimCodeZKPEndorsed(string memory POAVURI, uint8 code , bytes32 _credentialHash, bytes memory _signature ) public returns (uint256) {
        require((issuerOfPOAV[POAVURI]!=address(0) && issuerOfPOAV[POAVURI]==_credentialHash.recover(_signature)), "Does not have access");
        require(keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32",POAVURI, code))==_credentialHash, "Rejected POAV");
        return (_claim(POAVURI, msg.sender));
    }*/

    function _claim(string memory POAVURI, address _subject) private returns (uint256) {
         require(issuerOfPOAV[POAVURI]!=_subject, "Can't self-certify");
         require(statusOfPOAVSubject[POAVURI][_subject]==Status.Undefined, "You can only get a POAV");
         
        countPOAVOf[POAVURI]++;

        _tokenIds.increment();
        uint256 newItemId = _tokenIds.current();
        _mint(_subject, newItemId);
        _balanceFANTokenEmissionsOf[issuerOfPOAV[POAVURI]]=_balanceFANTokenEmissionsOf[issuerOfPOAV[POAVURI]]+(_claimFANToken[POAVURI]);
        _setTokenUri(newItemId, POAVURI);
        statusOfPOAVSubject[POAVURI][_subject] = Status.Active;
        _POAV memory _poav=_POAV(issuerOfPOAV[POAVURI], newItemId, POAVURI, _claimFANToken[POAVURI], block.timestamp, block.number);
        _listPOAVFromAddress[_subject].push(_poav);

        //if (keccak256(abi.encode(DAOOf[POAVURI])) != keccak256(abi.encode("")) && !attendeeOfDAO[_subject][DAOOf[POAVURI]]) {
          //attendeeOfDAO[_subject][DAOOf[POAVURI]] = true; 
          //_balanceOfDAO[_subject]++;
        //}

        _addAttendees(_subject);
        _balanceFANToken [_subject] = _claimFANToken[POAVURI];
        emit Transfer(issuerOfPOAV[POAVURI], _subject, newItemId);
        emit sent(issuerOfPOAV[POAVURI], POAVURI, _subject, validFromOfPOAV[POAVURI]);
        return newItemId;
    }
    function _addAttendees(address _subject) internal {
      bool  notFound;
        notFound=true;
        
        for(uint256 indx = 0; indx < _attendeesOfDAO.length; indx++) {
            if (_attendeesOfDAO[indx]==_subject) {
              notFound=false;
              break;
            }
            
        }
        if (notFound) {
          _attendeesOfDAO.push(_subject);
        }
        
    }
    function totalSupply() external  view returns (uint256) {
      return _tokenIds.current();
    }
    function totalPOAVs() external  view returns (uint256) {
      return POAVURIs;
    }
    function totalAttendees() external  view returns (uint256) {
      return  _attendeesOfDAO.length;
    }

   
    

}