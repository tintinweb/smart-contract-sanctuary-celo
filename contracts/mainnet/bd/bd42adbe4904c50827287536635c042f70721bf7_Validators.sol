pragma solidity ^0.5.3;


library Math {
    
    function max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a >= b ? a : b;
    }

    
    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    
    function average(uint256 a, uint256 b) internal pure returns (uint256) {
        
        return (a / 2) + (b / 2) + ((a % 2 + b % 2) / 2);
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

library BytesLib {
    function concat(
        bytes memory _preBytes,
        bytes memory _postBytes
    )
        internal
        pure
        returns (bytes memory)
    {
        bytes memory tempBytes;

        assembly {
            
            
            tempBytes := mload(0x40)

            
            
            let length := mload(_preBytes)
            mstore(tempBytes, length)

            
            
            
            let mc := add(tempBytes, 0x20)
            
            
            let end := add(mc, length)

            for {
                
                
                let cc := add(_preBytes, 0x20)
            } lt(mc, end) {
                
                mc := add(mc, 0x20)
                cc := add(cc, 0x20)
            } {
                
                
                mstore(mc, mload(cc))
            }

            
            
            
            length := mload(_postBytes)
            mstore(tempBytes, add(length, mload(tempBytes)))

            
            
            mc := end
            
            
            end := add(mc, length)

            for {
                let cc := add(_postBytes, 0x20)
            } lt(mc, end) {
                mc := add(mc, 0x20)
                cc := add(cc, 0x20)
            } {
                mstore(mc, mload(cc))
            }

            
            
            
            
            
            mstore(0x40, and(
              add(add(end, iszero(add(length, mload(_preBytes)))), 31),
              not(31) 
            ))
        }

        return tempBytes;
    }

    function concatStorage(bytes storage _preBytes, bytes memory _postBytes) internal {
        assembly {
            
            
            
            let fslot := sload(_preBytes_slot)
            
            
            
            
            
            
            
            let slength := div(and(fslot, sub(mul(0x100, iszero(and(fslot, 1))), 1)), 2)
            let mlength := mload(_postBytes)
            let newlength := add(slength, mlength)
            
            
            
            switch add(lt(slength, 32), lt(newlength, 32))
            case 2 {
                
                
                
                sstore(
                    _preBytes_slot,
                    
                    
                    add(
                        
                        
                        fslot,
                        add(
                            mul(
                                div(
                                    
                                    mload(add(_postBytes, 0x20)),
                                    
                                    exp(0x100, sub(32, mlength))
                                ),
                                
                                
                                exp(0x100, sub(32, newlength))
                            ),
                            
                            
                            mul(mlength, 2)
                        )
                    )
                )
            }
            case 1 {
                
                
                
                mstore(0x0, _preBytes_slot)
                let sc := add(keccak256(0x0, 0x20), div(slength, 32))

                
                sstore(_preBytes_slot, add(mul(newlength, 2), 1))

                
                
                
                
                
                
                
                

                let submod := sub(32, slength)
                let mc := add(_postBytes, submod)
                let end := add(_postBytes, mlength)
                let mask := sub(exp(0x100, submod), 1)

                sstore(
                    sc,
                    add(
                        and(
                            fslot,
                            0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff00
                        ),
                        and(mload(mc), mask)
                    )
                )

                for {
                    mc := add(mc, 0x20)
                    sc := add(sc, 1)
                } lt(mc, end) {
                    sc := add(sc, 1)
                    mc := add(mc, 0x20)
                } {
                    sstore(sc, mload(mc))
                }

                mask := exp(0x100, sub(mc, end))

                sstore(sc, mul(div(mload(mc), mask), mask))
            }
            default {
                
                mstore(0x0, _preBytes_slot)
                
                let sc := add(keccak256(0x0, 0x20), div(slength, 32))

                
                sstore(_preBytes_slot, add(mul(newlength, 2), 1))

                
                
                let slengthmod := mod(slength, 32)
                let mlengthmod := mod(mlength, 32)
                let submod := sub(32, slengthmod)
                let mc := add(_postBytes, submod)
                let end := add(_postBytes, mlength)
                let mask := sub(exp(0x100, submod), 1)

                sstore(sc, add(sload(sc), and(mload(mc), mask)))
                
                for { 
                    sc := add(sc, 1)
                    mc := add(mc, 0x20)
                } lt(mc, end) {
                    sc := add(sc, 1)
                    mc := add(mc, 0x20)
                } {
                    sstore(sc, mload(mc))
                }

                mask := exp(0x100, sub(mc, end))

                sstore(sc, mul(div(mload(mc), mask), mask))
            }
        }
    }

    function slice(
        bytes memory _bytes,
        uint _start,
        uint _length
    )
        internal
        pure
        returns (bytes memory)
    {
        require(_bytes.length >= (_start + _length));

        bytes memory tempBytes;

        assembly {
            switch iszero(_length)
            case 0 {
                
                
                tempBytes := mload(0x40)

                
                
                
                
                
                
                
                
                let lengthmod := and(_length, 31)

                
                
                
                
                let mc := add(add(tempBytes, lengthmod), mul(0x20, iszero(lengthmod)))
                let end := add(mc, _length)

                for {
                    
                    
                    let cc := add(add(add(_bytes, lengthmod), mul(0x20, iszero(lengthmod))), _start)
                } lt(mc, end) {
                    mc := add(mc, 0x20)
                    cc := add(cc, 0x20)
                } {
                    mstore(mc, mload(cc))
                }

                mstore(tempBytes, _length)

                
                
                mstore(0x40, and(add(mc, 31), not(31)))
            }
            
            default {
                tempBytes := mload(0x40)

                mstore(0x40, add(tempBytes, 0x20))
            }
        }

        return tempBytes;
    }

    function toAddress(bytes memory _bytes, uint _start) internal  pure returns (address) {
        require(_bytes.length >= (_start + 20));
        address tempAddress;

        assembly {
            tempAddress := div(mload(add(add(_bytes, 0x20), _start)), 0x1000000000000000000000000)
        }

        return tempAddress;
    }

    function toUint8(bytes memory _bytes, uint _start) internal  pure returns (uint8) {
        require(_bytes.length >= (_start + 1));
        uint8 tempUint;

        assembly {
            tempUint := mload(add(add(_bytes, 0x1), _start))
        }

        return tempUint;
    }

    function toUint16(bytes memory _bytes, uint _start) internal  pure returns (uint16) {
        require(_bytes.length >= (_start + 2));
        uint16 tempUint;

        assembly {
            tempUint := mload(add(add(_bytes, 0x2), _start))
        }

        return tempUint;
    }

    function toUint32(bytes memory _bytes, uint _start) internal  pure returns (uint32) {
        require(_bytes.length >= (_start + 4));
        uint32 tempUint;

        assembly {
            tempUint := mload(add(add(_bytes, 0x4), _start))
        }

        return tempUint;
    }

    function toUint(bytes memory _bytes, uint _start) internal  pure returns (uint256) {
        require(_bytes.length >= (_start + 32));
        uint256 tempUint;

        assembly {
            tempUint := mload(add(add(_bytes, 0x20), _start))
        }

        return tempUint;
    }

    function toBytes32(bytes memory _bytes, uint _start) internal  pure returns (bytes32) {
        require(_bytes.length >= (_start + 32));
        bytes32 tempBytes32;

        assembly {
            tempBytes32 := mload(add(add(_bytes, 0x20), _start))
        }

        return tempBytes32;
    }

    function equal(bytes memory _preBytes, bytes memory _postBytes) internal pure returns (bool) {
        bool success = true;

        assembly {
            let length := mload(_preBytes)

            
            switch eq(length, mload(_postBytes))
            case 1 {
                
                
                
                
                let cb := 1

                let mc := add(_preBytes, 0x20)
                let end := add(mc, length)

                for {
                    let cc := add(_postBytes, 0x20)
                
                
                } eq(add(lt(mc, end), cb), 2) {
                    mc := add(mc, 0x20)
                    cc := add(cc, 0x20)
                } {
                    
                    if iszero(eq(mload(mc), mload(cc))) {
                        
                        success := 0
                        cb := 0
                    }
                }
            }
            default {
                
                success := 0
            }
        }

        return success;
    }

    function equalStorage(
        bytes storage _preBytes,
        bytes memory _postBytes
    )
        internal
        view
        returns (bool)
    {
        bool success = true;

        assembly {
            
            let fslot := sload(_preBytes_slot)
            
            let slength := div(and(fslot, sub(mul(0x100, iszero(and(fslot, 1))), 1)), 2)
            let mlength := mload(_postBytes)

            
            switch eq(slength, mlength)
            case 1 {
                
                
                
                if iszero(iszero(slength)) {
                    switch lt(slength, 32)
                    case 1 {
                        
                        fslot := mul(div(fslot, 0x100), 0x100)

                        if iszero(eq(fslot, mload(add(_postBytes, 0x20)))) {
                            
                            success := 0
                        }
                    }
                    default {
                        
                        
                        
                        
                        let cb := 1

                        
                        mstore(0x0, _preBytes_slot)
                        let sc := keccak256(0x0, 0x20)

                        let mc := add(_postBytes, 0x20)
                        let end := add(mc, mlength)

                        
                        
                        for {} eq(add(lt(mc, end), cb), 2) {
                            sc := add(sc, 1)
                            mc := add(mc, 0x20)
                        } {
                            if iszero(eq(sload(sc), mload(mc))) {
                                
                                success := 0
                                cb := 0
                            }
                        }
                    }
                }
            }
            default {
                
                success := 0
            }
        }

        return success;
    }
}

interface IValidators {
  function getAccountLockedGoldRequirement(address) external view returns (uint256);
  function meetsAccountLockedGoldRequirements(address) external view returns (bool);
  function getGroupNumMembers(address) external view returns (uint256);
  function getGroupsNumMembers(address[] calldata) external view returns (uint256[] memory);
  function getNumRegisteredValidators() external view returns (uint256);
  function getTopGroupValidators(address, uint256) external view returns (address[] memory);
  function updateEcdsaPublicKey(address, address, bytes calldata) external returns (bool);
  function updatePublicKeys(address, address, bytes calldata, bytes calldata, bytes calldata)
    external
    returns (bool);
  function isValidator(address) external view returns (bool);
  function isValidatorGroup(address) external view returns (bool);
  function calculateGroupEpochScore(uint256[] calldata uptimes) external view returns (uint256);
  function groupMembershipInEpoch(address account, uint256 epochNumber, uint256 index)
    external
    view
    returns (address);
  function halveSlashingMultiplier(address group) external;
  function forceDeaffiliateIfValidator(address validator) external;
  function getValidatorGroupSlashingMultiplier(address) external view returns (uint256);
  function affiliate(address group) external returns (bool);
}

interface IRandom {
  function revealAndCommit(bytes32, bytes32, address) external;
  function randomnessBlockRetentionWindow() external view returns (uint256);
  function random() external view returns (bytes32);
  function getBlockRandomness(uint256) external view returns (bytes32);
}

contract CalledByVm {
  modifier onlyVm() {
    require(msg.sender == address(0), "Only VM can call");
    _;
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

library FixidityLib {
  struct Fraction {
    uint256 value;
  }

  
  function digits() internal pure returns (uint8) {
    return 24;
  }

  uint256 private constant FIXED1_UINT = 1000000000000000000000000;

  
  function fixed1() internal pure returns (Fraction memory) {
    return Fraction(FIXED1_UINT);
  }

  
  function wrap(uint256 x) internal pure returns (Fraction memory) {
    return Fraction(x);
  }

  
  function unwrap(Fraction memory x) internal pure returns (uint256) {
    return x.value;
  }

  
  function mulPrecision() internal pure returns (uint256) {
    return 1000000000000;
  }

  
  function maxNewFixed() internal pure returns (uint256) {
    return 115792089237316195423570985008687907853269984665640564;
  }

  
  function newFixed(uint256 x) internal pure returns (Fraction memory) {
    require(x <= maxNewFixed(), "can't create fixidity number larger than maxNewFixed()");
    return Fraction(x * FIXED1_UINT);
  }

  
  function fromFixed(Fraction memory x) internal pure returns (uint256) {
    return x.value / FIXED1_UINT;
  }

  
  function newFixedFraction(uint256 numerator, uint256 denominator)
    internal
    pure
    returns (Fraction memory)
  {
    Fraction memory convertedNumerator = newFixed(numerator);
    Fraction memory convertedDenominator = newFixed(denominator);
    return divide(convertedNumerator, convertedDenominator);
  }

  
  function integer(Fraction memory x) internal pure returns (Fraction memory) {
    return Fraction((x.value / FIXED1_UINT) * FIXED1_UINT); 
  }

  
  function fractional(Fraction memory x) internal pure returns (Fraction memory) {
    return Fraction(x.value - (x.value / FIXED1_UINT) * FIXED1_UINT); 
  }

  
  function add(Fraction memory x, Fraction memory y) internal pure returns (Fraction memory) {
    uint256 z = x.value + y.value;
    require(z >= x.value, "add overflow detected");
    return Fraction(z);
  }

  
  function subtract(Fraction memory x, Fraction memory y) internal pure returns (Fraction memory) {
    require(x.value >= y.value, "substraction underflow detected");
    return Fraction(x.value - y.value);
  }

  
  function multiply(Fraction memory x, Fraction memory y) internal pure returns (Fraction memory) {
    if (x.value == 0 || y.value == 0) return Fraction(0);
    if (y.value == FIXED1_UINT) return x;
    if (x.value == FIXED1_UINT) return y;

    
    
    uint256 x1 = integer(x).value / FIXED1_UINT;
    uint256 x2 = fractional(x).value;
    uint256 y1 = integer(y).value / FIXED1_UINT;
    uint256 y2 = fractional(y).value;

    
    uint256 x1y1 = x1 * y1;
    if (x1 != 0) require(x1y1 / x1 == y1, "overflow x1y1 detected");

    
    
    uint256 fixed_x1y1 = x1y1 * FIXED1_UINT;
    if (x1y1 != 0) require(fixed_x1y1 / x1y1 == FIXED1_UINT, "overflow x1y1 * fixed1 detected");
    x1y1 = fixed_x1y1;

    uint256 x2y1 = x2 * y1;
    if (x2 != 0) require(x2y1 / x2 == y1, "overflow x2y1 detected");

    uint256 x1y2 = x1 * y2;
    if (x1 != 0) require(x1y2 / x1 == y2, "overflow x1y2 detected");

    x2 = x2 / mulPrecision();
    y2 = y2 / mulPrecision();
    uint256 x2y2 = x2 * y2;
    if (x2 != 0) require(x2y2 / x2 == y2, "overflow x2y2 detected");

    
    Fraction memory result = Fraction(x1y1);
    result = add(result, Fraction(x2y1)); 
    result = add(result, Fraction(x1y2)); 
    result = add(result, Fraction(x2y2)); 
    return result;
  }

  
  function reciprocal(Fraction memory x) internal pure returns (Fraction memory) {
    require(x.value != 0, "can't call reciprocal(0)");
    return Fraction((FIXED1_UINT * FIXED1_UINT) / x.value); 
  }

  
  function divide(Fraction memory x, Fraction memory y) internal pure returns (Fraction memory) {
    require(y.value != 0, "can't divide by 0");
    uint256 X = x.value * FIXED1_UINT;
    require(X / FIXED1_UINT == x.value, "overflow at divide");
    return Fraction(X / y.value);
  }

  
  function gt(Fraction memory x, Fraction memory y) internal pure returns (bool) {
    return x.value > y.value;
  }

  
  function gte(Fraction memory x, Fraction memory y) internal pure returns (bool) {
    return x.value >= y.value;
  }

  
  function lt(Fraction memory x, Fraction memory y) internal pure returns (bool) {
    return x.value < y.value;
  }

  
  function lte(Fraction memory x, Fraction memory y) internal pure returns (bool) {
    return x.value <= y.value;
  }

  
  function equals(Fraction memory x, Fraction memory y) internal pure returns (bool) {
    return x.value == y.value;
  }

  
  function isProperFraction(Fraction memory x) internal pure returns (bool) {
    return lte(x, fixed1());
  }
}

library LinkedList {
  using SafeMath for uint256;

  struct Element {
    bytes32 previousKey;
    bytes32 nextKey;
    bool exists;
  }

  struct List {
    bytes32 head;
    bytes32 tail;
    uint256 numElements;
    mapping(bytes32 => Element) elements;
  }

  
  function insert(List storage list, bytes32 key, bytes32 previousKey, bytes32 nextKey) public {
    require(key != bytes32(0), "Key must be defined");
    require(!contains(list, key), "Can't insert an existing element");
    require(
      previousKey != key && nextKey != key,
      "Key cannot be the same as previousKey or nextKey"
    );

    Element storage element = list.elements[key];
    element.exists = true;

    if (list.numElements == 0) {
      list.tail = key;
      list.head = key;
    } else {
      require(
        previousKey != bytes32(0) || nextKey != bytes32(0),
        "Either previousKey or nextKey must be defined"
      );

      element.previousKey = previousKey;
      element.nextKey = nextKey;

      if (previousKey != bytes32(0)) {
        require(
          contains(list, previousKey),
          "If previousKey is defined, it must exist in the list"
        );
        Element storage previousElement = list.elements[previousKey];
        require(previousElement.nextKey == nextKey, "previousKey must be adjacent to nextKey");
        previousElement.nextKey = key;
      } else {
        list.tail = key;
      }

      if (nextKey != bytes32(0)) {
        require(contains(list, nextKey), "If nextKey is defined, it must exist in the list");
        Element storage nextElement = list.elements[nextKey];
        require(nextElement.previousKey == previousKey, "previousKey must be adjacent to nextKey");
        nextElement.previousKey = key;
      } else {
        list.head = key;
      }
    }

    list.numElements = list.numElements.add(1);
  }

  
  function push(List storage list, bytes32 key) public {
    insert(list, key, bytes32(0), list.tail);
  }

  
  function remove(List storage list, bytes32 key) public {
    Element storage element = list.elements[key];
    require(key != bytes32(0) && contains(list, key), "key not in list");
    if (element.previousKey != bytes32(0)) {
      Element storage previousElement = list.elements[element.previousKey];
      previousElement.nextKey = element.nextKey;
    } else {
      list.tail = element.nextKey;
    }

    if (element.nextKey != bytes32(0)) {
      Element storage nextElement = list.elements[element.nextKey];
      nextElement.previousKey = element.previousKey;
    } else {
      list.head = element.previousKey;
    }

    delete list.elements[key];
    list.numElements = list.numElements.sub(1);
  }

  
  function update(List storage list, bytes32 key, bytes32 previousKey, bytes32 nextKey) public {
    require(
      key != bytes32(0) && key != previousKey && key != nextKey && contains(list, key),
      "key on in list"
    );
    remove(list, key);
    insert(list, key, previousKey, nextKey);
  }

  
  function contains(List storage list, bytes32 key) public view returns (bool) {
    return list.elements[key].exists;
  }

  
  function headN(List storage list, uint256 n) public view returns (bytes32[] memory) {
    require(n <= list.numElements, "not enough elements");
    bytes32[] memory keys = new bytes32[](n);
    bytes32 key = list.head;
    for (uint256 i = 0; i < n; i = i.add(1)) {
      keys[i] = key;
      key = list.elements[key].previousKey;
    }
    return keys;
  }

  
  function getKeys(List storage list) public view returns (bytes32[] memory) {
    return headN(list, list.numElements);
  }
}

library AddressLinkedList {
  using LinkedList for LinkedList.List;
  using SafeMath for uint256;

  function toBytes(address a) public pure returns (bytes32) {
    return bytes32(uint256(a) << 96);
  }

  function toAddress(bytes32 b) public pure returns (address) {
    return address(uint256(b) >> 96);
  }

  
  function insert(LinkedList.List storage list, address key, address previousKey, address nextKey)
    public
  {
    list.insert(toBytes(key), toBytes(previousKey), toBytes(nextKey));
  }

  
  function push(LinkedList.List storage list, address key) public {
    list.insert(toBytes(key), bytes32(0), list.tail);
  }

  
  function remove(LinkedList.List storage list, address key) public {
    list.remove(toBytes(key));
  }

  
  function update(LinkedList.List storage list, address key, address previousKey, address nextKey)
    public
  {
    list.update(toBytes(key), toBytes(previousKey), toBytes(nextKey));
  }

  
  function contains(LinkedList.List storage list, address key) public view returns (bool) {
    return list.elements[toBytes(key)].exists;
  }

  
  function headN(LinkedList.List storage list, uint256 n) public view returns (address[] memory) {
    bytes32[] memory byteKeys = list.headN(n);
    address[] memory keys = new address[](n);
    for (uint256 i = 0; i < n; i = i.add(1)) {
      keys[i] = toAddress(byteKeys[i]);
    }
    return keys;
  }

  
  function getKeys(LinkedList.List storage list) public view returns (address[] memory) {
    return headN(list, list.numElements);
  }
}

interface IERC20 {
    
    function totalSupply() external view returns (uint256);

    
    function balanceOf(address account) external view returns (uint256);

    
    function transfer(address recipient, uint256 amount) external returns (bool);

    
    function allowance(address owner, address spender) external view returns (uint256);

    
    function approve(address spender, uint256 amount) external returns (bool);

    
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);

    
    event Transfer(address indexed from, address indexed to, uint256 value);

    
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

interface IAccounts {
  function isAccount(address) external view returns (bool);
  function voteSignerToAccount(address) external view returns (address);
  function validatorSignerToAccount(address) external view returns (address);
  function attestationSignerToAccount(address) external view returns (address);
  function signerToAccount(address) external view returns (address);
  function getAttestationSigner(address) external view returns (address);
  function getValidatorSigner(address) external view returns (address);
  function getVoteSigner(address) external view returns (address);
  function hasAuthorizedVoteSigner(address) external view returns (bool);
  function hasAuthorizedValidatorSigner(address) external view returns (bool);
  function hasAuthorizedAttestationSigner(address) external view returns (bool);

  function setAccountDataEncryptionKey(bytes calldata) external;
  function setMetadataURL(string calldata) external;
  function setName(string calldata) external;
  function setWalletAddress(address, uint8, bytes32, bytes32) external;
  function setAccount(string calldata, bytes calldata, address, uint8, bytes32, bytes32) external;

  function getDataEncryptionKey(address) external view returns (bytes memory);
  function getWalletAddress(address) external view returns (address);
  function getMetadataURL(address) external view returns (string memory);
  function batchGetMetadataURL(address[] calldata)
    external
    view
    returns (uint256[] memory, bytes memory);
  function getName(address) external view returns (string memory);

  function authorizeVoteSigner(address, uint8, bytes32, bytes32) external;
  function authorizeValidatorSigner(address, uint8, bytes32, bytes32) external;
  function authorizeValidatorSignerWithPublicKey(address, uint8, bytes32, bytes32, bytes calldata)
    external;
  function authorizeValidatorSignerWithKeys(
    address,
    uint8,
    bytes32,
    bytes32,
    bytes calldata,
    bytes calldata,
    bytes calldata
  ) external;
  function authorizeAttestationSigner(address, uint8, bytes32, bytes32) external;
  function createAccount() external returns (bool);
}

interface IFeeCurrencyWhitelist {
  function addToken(address) external;
  function getWhitelist() external view returns (address[] memory);
}

interface IFreezer {
  function isFrozen(address) external view returns (bool);
}

interface IRegistry {
  function setAddressFor(string calldata, address) external;
  function getAddressForOrDie(bytes32) external view returns (address);
  function getAddressFor(bytes32) external view returns (address);
  function isOneOf(bytes32[] calldata, address) external view returns (bool);
}

interface IElection {
  function getTotalVotes() external view returns (uint256);
  function getActiveVotes() external view returns (uint256);
  function getTotalVotesByAccount(address) external view returns (uint256);
  function markGroupIneligible(address) external;
  function markGroupEligible(address, address, address) external;
  function electValidatorSigners() external view returns (address[] memory);
  function vote(address, uint256, address, address) external returns (bool);
  function activate(address) external returns (bool);
  function revokeActive(address, uint256, address, address, uint256) external returns (bool);
  function revokeAllActive(address, address, address, uint256) external returns (bool);
  function revokePending(address, uint256, address, address, uint256) external returns (bool);
  function forceDecrementVotes(
    address,
    uint256,
    address[] calldata,
    address[] calldata,
    uint256[] calldata
  ) external returns (uint256);
}

interface IGovernance {
  function isVoting(address) external view returns (bool);
}

interface ILockedGold {
  function incrementNonvotingAccountBalance(address, uint256) external;
  function decrementNonvotingAccountBalance(address, uint256) external;
  function getAccountTotalLockedGold(address) external view returns (uint256);
  function getTotalLockedGold() external view returns (uint256);
  function getPendingWithdrawals(address)
    external
    view
    returns (uint256[] memory, uint256[] memory);
  function getTotalPendingWithdrawals(address) external view returns (uint256);
  function lock() external payable;
  function unlock(uint256) external;
  function relock(uint256, uint256) external;
  function withdraw(uint256) external;
  function slash(
    address account,
    uint256 penalty,
    address reporter,
    uint256 reward,
    address[] calldata lessers,
    address[] calldata greaters,
    uint256[] calldata indices
  ) external;
  function isSlasher(address) external view returns (bool);
}

interface IAttestations {
  function setAttestationRequestFee(address, uint256) external;
  function request(bytes32, uint256, address) external;
  function selectIssuers(bytes32) external;
  function complete(bytes32, uint8, bytes32, bytes32) external;
  function revoke(bytes32, uint256) external;
  function withdraw(address) external;

  function setAttestationExpiryBlocks(uint256) external;

  function getMaxAttestations() external view returns (uint256);

  function getUnselectedRequest(bytes32, address) external view returns (uint32, uint32, address);
  function getAttestationRequestFee(address) external view returns (uint256);

  function lookupAccountsForIdentifier(bytes32) external view returns (address[] memory);

  function getAttestationStats(bytes32, address) external view returns (uint32, uint32);

  function getAttestationState(bytes32, address, address)
    external
    view
    returns (uint8, uint32, address);
  function getCompletableAttestations(bytes32, address)
    external
    view
    returns (uint32[] memory, address[] memory, uint256[] memory, bytes memory);
}

interface IExchange {
  function exchange(uint256, uint256, bool) external returns (uint256);
  function setUpdateFrequency(uint256) external;
  function getBuyTokenAmount(uint256, bool) external view returns (uint256);
  function getSellTokenAmount(uint256, bool) external view returns (uint256);
  function getBuyAndSellBuckets(bool) external view returns (uint256, uint256);
}

interface IReserve {
  function setTobinTaxStalenessThreshold(uint256) external;
  function addToken(address) external returns (bool);
  function removeToken(address, uint256) external returns (bool);
  function transferGold(address payable, uint256) external returns (bool);
  function transferExchangeGold(address payable, uint256) external returns (bool);
  function getReserveGoldBalance() external view returns (uint256);
  function getUnfrozenReserveGoldBalance() external view returns (uint256);
  function getOrComputeTobinTax() external returns (uint256, uint256);
  function getTokens() external view returns (address[] memory);
  function getReserveRatio() external view returns (uint256);
}

interface ISortedOracles {
  function addOracle(address, address) external;
  function removeOracle(address, address, uint256) external;
  function report(address, uint256, address, address) external;
  function removeExpiredReports(address, uint256) external;
  function isOldestReportExpired(address token) external view returns (bool, address);
  function numRates(address) external view returns (uint256);
  function medianRate(address) external view returns (uint256, uint256);
  function numTimestamps(address) external view returns (uint256);
  function medianTimestamp(address) external view returns (uint256);
}

interface IStableToken {
  function mint(address, uint256) external returns (bool);
  function burn(uint256) external returns (bool);
  function setInflationParameters(uint256, uint256) external;
  function valueToUnits(uint256) external view returns (uint256);
  function unitsToValue(uint256) external view returns (uint256);
  function getInflationParameters() external view returns (uint256, uint256, uint256, uint256);

  
  function balanceOf(address) external view returns (uint256);
}

contract UsingRegistry is Ownable {
  event RegistrySet(address indexed registryAddress);

  
  bytes32 constant ACCOUNTS_REGISTRY_ID = keccak256(abi.encodePacked("Accounts"));
  bytes32 constant ATTESTATIONS_REGISTRY_ID = keccak256(abi.encodePacked("Attestations"));
  bytes32 constant DOWNTIME_SLASHER_REGISTRY_ID = keccak256(abi.encodePacked("DowntimeSlasher"));
  bytes32 constant DOUBLE_SIGNING_SLASHER_REGISTRY_ID = keccak256(
    abi.encodePacked("DoubleSigningSlasher")
  );
  bytes32 constant ELECTION_REGISTRY_ID = keccak256(abi.encodePacked("Election"));
  bytes32 constant EXCHANGE_REGISTRY_ID = keccak256(abi.encodePacked("Exchange"));
  bytes32 constant FEE_CURRENCY_WHITELIST_REGISTRY_ID = keccak256(
    abi.encodePacked("FeeCurrencyWhitelist")
  );
  bytes32 constant FREEZER_REGISTRY_ID = keccak256(abi.encodePacked("Freezer"));
  bytes32 constant GOLD_TOKEN_REGISTRY_ID = keccak256(abi.encodePacked("GoldToken"));
  bytes32 constant GOVERNANCE_REGISTRY_ID = keccak256(abi.encodePacked("Governance"));
  bytes32 constant GOVERNANCE_SLASHER_REGISTRY_ID = keccak256(
    abi.encodePacked("GovernanceSlasher")
  );
  bytes32 constant LOCKED_GOLD_REGISTRY_ID = keccak256(abi.encodePacked("LockedGold"));
  bytes32 constant RESERVE_REGISTRY_ID = keccak256(abi.encodePacked("Reserve"));
  bytes32 constant RANDOM_REGISTRY_ID = keccak256(abi.encodePacked("Random"));
  bytes32 constant SORTED_ORACLES_REGISTRY_ID = keccak256(abi.encodePacked("SortedOracles"));
  bytes32 constant STABLE_TOKEN_REGISTRY_ID = keccak256(abi.encodePacked("StableToken"));
  bytes32 constant VALIDATORS_REGISTRY_ID = keccak256(abi.encodePacked("Validators"));
  

  IRegistry public registry;

  modifier onlyRegisteredContract(bytes32 identifierHash) {
    require(registry.getAddressForOrDie(identifierHash) == msg.sender, "only registered contract");
    _;
  }

  modifier onlyRegisteredContracts(bytes32[] memory identifierHashes) {
    require(registry.isOneOf(identifierHashes, msg.sender), "only registered contracts");
    _;
  }

  
  function setRegistry(address registryAddress) public onlyOwner {
    require(registryAddress != address(0), "Cannot register the null address");
    registry = IRegistry(registryAddress);
    emit RegistrySet(registryAddress);
  }

  function getAccounts() internal view returns (IAccounts) {
    return IAccounts(registry.getAddressForOrDie(ACCOUNTS_REGISTRY_ID));
  }

  function getAttestations() internal view returns (IAttestations) {
    return IAttestations(registry.getAddressForOrDie(ATTESTATIONS_REGISTRY_ID));
  }

  function getElection() internal view returns (IElection) {
    return IElection(registry.getAddressForOrDie(ELECTION_REGISTRY_ID));
  }

  function getExchange() internal view returns (IExchange) {
    return IExchange(registry.getAddressForOrDie(EXCHANGE_REGISTRY_ID));
  }

  function getFeeCurrencyWhitelistRegistry() internal view returns (IFeeCurrencyWhitelist) {
    return IFeeCurrencyWhitelist(registry.getAddressForOrDie(FEE_CURRENCY_WHITELIST_REGISTRY_ID));
  }

  function getFreezer() internal view returns (IFreezer) {
    return IFreezer(registry.getAddressForOrDie(FREEZER_REGISTRY_ID));
  }

  function getGoldToken() internal view returns (IERC20) {
    return IERC20(registry.getAddressForOrDie(GOLD_TOKEN_REGISTRY_ID));
  }

  function getGovernance() internal view returns (IGovernance) {
    return IGovernance(registry.getAddressForOrDie(GOVERNANCE_REGISTRY_ID));
  }

  function getLockedGold() internal view returns (ILockedGold) {
    return ILockedGold(registry.getAddressForOrDie(LOCKED_GOLD_REGISTRY_ID));
  }

  function getRandom() internal view returns (IRandom) {
    return IRandom(registry.getAddressForOrDie(RANDOM_REGISTRY_ID));
  }

  function getReserve() internal view returns (IReserve) {
    return IReserve(registry.getAddressForOrDie(RESERVE_REGISTRY_ID));
  }

  function getSortedOracles() internal view returns (ISortedOracles) {
    return ISortedOracles(registry.getAddressForOrDie(SORTED_ORACLES_REGISTRY_ID));
  }

  function getStableToken() internal view returns (IStableToken) {
    return IStableToken(registry.getAddressForOrDie(STABLE_TOKEN_REGISTRY_ID));
  }

  function getValidators() internal view returns (IValidators) {
    return IValidators(registry.getAddressForOrDie(VALIDATORS_REGISTRY_ID));
  }
}

contract UsingPrecompiles {
  using SafeMath for uint256;

  address constant TRANSFER = address(0xff - 2);
  address constant FRACTION_MUL = address(0xff - 3);
  address constant PROOF_OF_POSSESSION = address(0xff - 4);
  address constant GET_VALIDATOR = address(0xff - 5);
  address constant NUMBER_VALIDATORS = address(0xff - 6);
  address constant EPOCH_SIZE = address(0xff - 7);
  address constant BLOCK_NUMBER_FROM_HEADER = address(0xff - 8);
  address constant HASH_HEADER = address(0xff - 9);
  address constant GET_PARENT_SEAL_BITMAP = address(0xff - 10);
  address constant GET_VERIFIED_SEAL_BITMAP = address(0xff - 11);

  
  function fractionMulExp(
    uint256 aNumerator,
    uint256 aDenominator,
    uint256 bNumerator,
    uint256 bDenominator,
    uint256 exponent,
    uint256 _decimals
  ) public view returns (uint256, uint256) {
    require(aDenominator != 0 && bDenominator != 0, "a denominator is zero");
    uint256 returnNumerator;
    uint256 returnDenominator;
    bool success;
    bytes memory out;
    (success, out) = FRACTION_MUL.staticcall(
      abi.encodePacked(aNumerator, aDenominator, bNumerator, bDenominator, exponent, _decimals)
    );
    require(success, "error calling fractionMulExp precompile");
    returnNumerator = getUint256FromBytes(out, 0);
    returnDenominator = getUint256FromBytes(out, 32);
    return (returnNumerator, returnDenominator);
  }

  
  function getEpochSize() public view returns (uint256) {
    bytes memory out;
    bool success;
    (success, out) = EPOCH_SIZE.staticcall(abi.encodePacked());
    require(success, "error calling getEpochSize precompile");
    return getUint256FromBytes(out, 0);
  }

  
  function getEpochNumberOfBlock(uint256 blockNumber) public view returns (uint256) {
    return epochNumberOfBlock(blockNumber, getEpochSize());
  }

  
  function getEpochNumber() public view returns (uint256) {
    return getEpochNumberOfBlock(block.number);
  }

  
  function epochNumberOfBlock(uint256 blockNumber, uint256 epochSize)
    internal
    pure
    returns (uint256)
  {
    
    uint256 epochNumber = blockNumber / epochSize;
    if (blockNumber % epochSize == 0) {
      return epochNumber;
    } else {
      return epochNumber + 1;
    }
  }

  
  function validatorSignerAddressFromCurrentSet(uint256 index) public view returns (address) {
    bytes memory out;
    bool success;
    (success, out) = GET_VALIDATOR.staticcall(abi.encodePacked(index, uint256(block.number)));
    require(success, "error calling validatorSignerAddressFromCurrentSet precompile");
    return address(getUint256FromBytes(out, 0));
  }

  
  function validatorSignerAddressFromSet(uint256 index, uint256 blockNumber)
    public
    view
    returns (address)
  {
    bytes memory out;
    bool success;
    (success, out) = GET_VALIDATOR.staticcall(abi.encodePacked(index, blockNumber));
    require(success, "error calling validatorSignerAddressFromSet precompile");
    return address(getUint256FromBytes(out, 0));
  }

  
  function numberValidatorsInCurrentSet() public view returns (uint256) {
    bytes memory out;
    bool success;
    (success, out) = NUMBER_VALIDATORS.staticcall(abi.encodePacked(uint256(block.number)));
    require(success, "error calling numberValidatorsInCurrentSet precompile");
    return getUint256FromBytes(out, 0);
  }

  
  function numberValidatorsInSet(uint256 blockNumber) public view returns (uint256) {
    bytes memory out;
    bool success;
    (success, out) = NUMBER_VALIDATORS.staticcall(abi.encodePacked(blockNumber));
    require(success, "error calling numberValidatorsInSet precompile");
    return getUint256FromBytes(out, 0);
  }

  
  function checkProofOfPossession(address sender, bytes memory blsKey, bytes memory blsPop)
    public
    view
    returns (bool)
  {
    bool success;
    (success, ) = PROOF_OF_POSSESSION.staticcall(abi.encodePacked(sender, blsKey, blsPop));
    return success;
  }

  
  function getBlockNumberFromHeader(bytes memory header) public view returns (uint256) {
    bytes memory out;
    bool success;
    (success, out) = BLOCK_NUMBER_FROM_HEADER.staticcall(abi.encodePacked(header));
    require(success, "error calling getBlockNumberFromHeader precompile");
    return getUint256FromBytes(out, 0);
  }

  
  function hashHeader(bytes memory header) public view returns (bytes32) {
    bytes memory out;
    bool success;
    (success, out) = HASH_HEADER.staticcall(abi.encodePacked(header));
    require(success, "error calling hashHeader precompile");
    return getBytes32FromBytes(out, 0);
  }

  
  function getParentSealBitmap(uint256 blockNumber) public view returns (bytes32) {
    bytes memory out;
    bool success;
    (success, out) = GET_PARENT_SEAL_BITMAP.staticcall(abi.encodePacked(blockNumber));
    require(success, "error calling getParentSealBitmap precompile");
    return getBytes32FromBytes(out, 0);
  }

  
  function getVerifiedSealBitmapFromHeader(bytes memory header) public view returns (bytes32) {
    bytes memory out;
    bool success;
    (success, out) = GET_VERIFIED_SEAL_BITMAP.staticcall(abi.encodePacked(header));
    require(success, "error calling getVerifiedSealBitmapFromHeader precompile");
    return getBytes32FromBytes(out, 0);
  }

  
  function getUint256FromBytes(bytes memory bs, uint256 start) internal pure returns (uint256) {
    return uint256(getBytes32FromBytes(bs, start));
  }

  
  function getBytes32FromBytes(bytes memory bs, uint256 start) internal pure returns (bytes32) {
    require(bs.length >= start + 32, "slicing out of range");
    bytes32 x;
    assembly {
      x := mload(add(bs, add(start, 32)))
    }
    return x;
  }

  
  function minQuorumSize(uint256 blockNumber) public view returns (uint256) {
    return numberValidatorsInSet(blockNumber).mul(2).add(2).div(3);
  }

  
  function minQuorumSizeInCurrentSet() public view returns (uint256) {
    return minQuorumSize(block.number);
  }

}

contract ReentrancyGuard {
  
  uint256 private _guardCounter;

  constructor() internal {
    
    
    _guardCounter = 1;
  }

  
  modifier nonReentrant() {
    _guardCounter += 1;
    uint256 localCounter = _guardCounter;
    _;
    require(localCounter == _guardCounter, "reentrant call");
  }
}

contract Validators is
  IValidators,
  Ownable,
  ReentrancyGuard,
  Initializable,
  UsingRegistry,
  UsingPrecompiles,
  CalledByVm
{
  using FixidityLib for FixidityLib.Fraction;
  using AddressLinkedList for LinkedList.List;
  using SafeMath for uint256;
  using BytesLib for bytes;

  
  
  
  
  
  
  
  
  
  
  
  
  
  
  
  struct LockedGoldRequirements {
    uint256 value;
    
    uint256 duration;
  }

  struct ValidatorGroup {
    bool exists;
    LinkedList.List members;
    FixidityLib.Fraction commission;
    FixidityLib.Fraction nextCommission;
    uint256 nextCommissionBlock;
    
    uint256[] sizeHistory;
    SlashingInfo slashInfo;
  }

  
  struct MembershipHistoryEntry {
    uint256 epochNumber;
    address group;
  }

  
  
  
  
  struct MembershipHistory {
    
    uint256 tail;
    
    uint256 numEntries;
    mapping(uint256 => MembershipHistoryEntry) entries;
    uint256 lastRemovedFromGroupTimestamp;
  }

  struct SlashingInfo {
    FixidityLib.Fraction multiplier;
    uint256 lastSlashed;
  }

  struct PublicKeys {
    bytes ecdsa;
    bytes bls;
  }

  struct Validator {
    PublicKeys publicKeys;
    address affiliation;
    FixidityLib.Fraction score;
    MembershipHistory membershipHistory;
  }

  
  struct ValidatorScoreParameters {
    uint256 exponent;
    FixidityLib.Fraction adjustmentSpeed;
  }

  mapping(address => ValidatorGroup) private groups;
  mapping(address => Validator) private validators;
  address[] private registeredGroups;
  address[] private registeredValidators;
  LockedGoldRequirements public validatorLockedGoldRequirements;
  LockedGoldRequirements public groupLockedGoldRequirements;
  ValidatorScoreParameters private validatorScoreParameters;
  uint256 public membershipHistoryLength;
  uint256 public maxGroupSize;
  
  uint256 public commissionUpdateDelay;
  uint256 public slashingMultiplierResetPeriod;

  event MaxGroupSizeSet(uint256 size);
  event CommissionUpdateDelaySet(uint256 delay);
  event ValidatorScoreParametersSet(uint256 exponent, uint256 adjustmentSpeed);
  event GroupLockedGoldRequirementsSet(uint256 value, uint256 duration);
  event ValidatorLockedGoldRequirementsSet(uint256 value, uint256 duration);
  event MembershipHistoryLengthSet(uint256 length);
  event ValidatorRegistered(address indexed validator);
  event ValidatorDeregistered(address indexed validator);
  event ValidatorAffiliated(address indexed validator, address indexed group);
  event ValidatorDeaffiliated(address indexed validator, address indexed group);
  event ValidatorEcdsaPublicKeyUpdated(address indexed validator, bytes ecdsaPublicKey);
  event ValidatorBlsPublicKeyUpdated(address indexed validator, bytes blsPublicKey);
  event ValidatorScoreUpdated(address indexed validator, uint256 score, uint256 epochScore);
  event ValidatorGroupRegistered(address indexed group, uint256 commission);
  event ValidatorGroupDeregistered(address indexed group);
  event ValidatorGroupMemberAdded(address indexed group, address indexed validator);
  event ValidatorGroupMemberRemoved(address indexed group, address indexed validator);
  event ValidatorGroupMemberReordered(address indexed group, address indexed validator);
  event ValidatorGroupCommissionUpdateQueued(
    address indexed group,
    uint256 commission,
    uint256 activationBlock
  );
  event ValidatorGroupCommissionUpdated(address indexed group, uint256 commission);
  event ValidatorEpochPaymentDistributed(
    address indexed validator,
    uint256 validatorPayment,
    address indexed group,
    uint256 groupPayment
  );

  modifier onlySlasher() {
    require(getLockedGold().isSlasher(msg.sender), "Only registered slasher can call");
    _;
  }

  
  function initialize(
    address registryAddress,
    uint256 groupRequirementValue,
    uint256 groupRequirementDuration,
    uint256 validatorRequirementValue,
    uint256 validatorRequirementDuration,
    uint256 validatorScoreExponent,
    uint256 validatorScoreAdjustmentSpeed,
    uint256 _membershipHistoryLength,
    uint256 _slashingMultiplierResetPeriod,
    uint256 _maxGroupSize,
    uint256 _commissionUpdateDelay
  ) external initializer {
    _transferOwnership(msg.sender);
    setRegistry(registryAddress);
    setGroupLockedGoldRequirements(groupRequirementValue, groupRequirementDuration);
    setValidatorLockedGoldRequirements(validatorRequirementValue, validatorRequirementDuration);
    setValidatorScoreParameters(validatorScoreExponent, validatorScoreAdjustmentSpeed);
    setMaxGroupSize(_maxGroupSize);
    setCommissionUpdateDelay(_commissionUpdateDelay);
    setMembershipHistoryLength(_membershipHistoryLength);
    setSlashingMultiplierResetPeriod(_slashingMultiplierResetPeriod);
  }

  
  function setCommissionUpdateDelay(uint256 delay) public onlyOwner {
    require(delay != commissionUpdateDelay, "commission update delay not changed");
    commissionUpdateDelay = delay;
    emit CommissionUpdateDelaySet(delay);
  }

  
  function setMaxGroupSize(uint256 size) public onlyOwner returns (bool) {
    require(0 < size, "Max group size cannot be zero");
    require(size != maxGroupSize, "Max group size not changed");
    maxGroupSize = size;
    emit MaxGroupSizeSet(size);
    return true;
  }

  
  function setMembershipHistoryLength(uint256 length) public onlyOwner returns (bool) {
    require(0 < length, "Membership history length cannot be zero");
    require(length != membershipHistoryLength, "Membership history length not changed");
    membershipHistoryLength = length;
    emit MembershipHistoryLengthSet(length);
    return true;
  }

  
  function setValidatorScoreParameters(uint256 exponent, uint256 adjustmentSpeed)
    public
    onlyOwner
    returns (bool)
  {
    require(
      adjustmentSpeed <= FixidityLib.fixed1().unwrap(),
      "Adjustment speed cannot be larger than 1"
    );
    require(
      exponent != validatorScoreParameters.exponent ||
        !FixidityLib.wrap(adjustmentSpeed).equals(validatorScoreParameters.adjustmentSpeed),
      "Adjustment speed and exponent not changed"
    );
    validatorScoreParameters = ValidatorScoreParameters(
      exponent,
      FixidityLib.wrap(adjustmentSpeed)
    );
    emit ValidatorScoreParametersSet(exponent, adjustmentSpeed);
    return true;
  }

  
  function getMaxGroupSize() external view returns (uint256) {
    return maxGroupSize;
  }

  
  function getCommissionUpdateDelay() external view returns (uint256) {
    return commissionUpdateDelay;
  }

  
  function setGroupLockedGoldRequirements(uint256 value, uint256 duration)
    public
    onlyOwner
    returns (bool)
  {
    LockedGoldRequirements storage requirements = groupLockedGoldRequirements;
    require(
      value != requirements.value || duration != requirements.duration,
      "Group requirements not changed"
    );
    groupLockedGoldRequirements = LockedGoldRequirements(value, duration);
    emit GroupLockedGoldRequirementsSet(value, duration);
    return true;
  }

  
  function setValidatorLockedGoldRequirements(uint256 value, uint256 duration)
    public
    onlyOwner
    returns (bool)
  {
    LockedGoldRequirements storage requirements = validatorLockedGoldRequirements;
    require(
      value != requirements.value || duration != requirements.duration,
      "Validator requirements not changed"
    );
    validatorLockedGoldRequirements = LockedGoldRequirements(value, duration);
    emit ValidatorLockedGoldRequirementsSet(value, duration);
    return true;
  }

  
  function registerValidator(
    bytes calldata ecdsaPublicKey,
    bytes calldata blsPublicKey,
    bytes calldata blsPop
  ) external nonReentrant returns (bool) {
    address account = getAccounts().validatorSignerToAccount(msg.sender);
    require(!isValidator(account) && !isValidatorGroup(account), "Already registered");
    uint256 lockedGoldBalance = getLockedGold().getAccountTotalLockedGold(account);
    require(lockedGoldBalance >= validatorLockedGoldRequirements.value, "Deposit too small");
    Validator storage validator = validators[account];
    address signer = getAccounts().getValidatorSigner(account);
    _updateEcdsaPublicKey(validator, account, signer, ecdsaPublicKey);
    _updateBlsPublicKey(validator, account, blsPublicKey, blsPop);
    registeredValidators.push(account);
    updateMembershipHistory(account, address(0));
    emit ValidatorRegistered(account);
    return true;
  }

  
  function getValidatorScoreParameters() external view returns (uint256, uint256) {
    return (validatorScoreParameters.exponent, validatorScoreParameters.adjustmentSpeed.unwrap());
  }

  
  function getMembershipHistory(address account)
    external
    view
    returns (uint256[] memory, address[] memory, uint256, uint256)
  {
    MembershipHistory storage history = validators[account].membershipHistory;
    uint256[] memory epochs = new uint256[](history.numEntries);
    address[] memory membershipGroups = new address[](history.numEntries);
    for (uint256 i = 0; i < history.numEntries; i = i.add(1)) {
      uint256 index = history.tail.add(i);
      epochs[i] = history.entries[index].epochNumber;
      membershipGroups[i] = history.entries[index].group;
    }
    return (epochs, membershipGroups, history.lastRemovedFromGroupTimestamp, history.tail);
  }

  
  function calculateEpochScore(uint256 uptime) public view returns (uint256) {
    require(uptime <= FixidityLib.fixed1().unwrap(), "Uptime cannot be larger than one");
    uint256 numerator;
    uint256 denominator;
    (numerator, denominator) = fractionMulExp(
      FixidityLib.fixed1().unwrap(),
      FixidityLib.fixed1().unwrap(),
      uptime,
      FixidityLib.fixed1().unwrap(),
      validatorScoreParameters.exponent,
      18
    );
    return FixidityLib.newFixedFraction(numerator, denominator).unwrap();
  }

  
  function calculateGroupEpochScore(uint256[] calldata uptimes) external view returns (uint256) {
    require(uptimes.length > 0, "Uptime array empty");
    require(uptimes.length <= maxGroupSize, "Uptime array larger than maximum group size");
    FixidityLib.Fraction memory sum;
    for (uint256 i = 0; i < uptimes.length; i = i.add(1)) {
      sum = sum.add(FixidityLib.wrap(calculateEpochScore(uptimes[i])));
    }
    return sum.divide(FixidityLib.newFixed(uptimes.length)).unwrap();
  }

  
  function updateValidatorScoreFromSigner(address signer, uint256 uptime) external onlyVm() {
    _updateValidatorScoreFromSigner(signer, uptime);
  }

  
  function _updateValidatorScoreFromSigner(address signer, uint256 uptime) internal {
    address account = getAccounts().signerToAccount(signer);
    require(isValidator(account), "Not a validator");

    FixidityLib.Fraction memory epochScore = FixidityLib.wrap(calculateEpochScore(uptime));
    FixidityLib.Fraction memory newComponent = validatorScoreParameters.adjustmentSpeed.multiply(
      epochScore
    );

    FixidityLib.Fraction memory currentComponent = FixidityLib.fixed1().subtract(
      validatorScoreParameters.adjustmentSpeed
    );
    currentComponent = currentComponent.multiply(validators[account].score);
    validators[account].score = FixidityLib.wrap(
      Math.min(epochScore.unwrap(), newComponent.add(currentComponent).unwrap())
    );
    emit ValidatorScoreUpdated(account, validators[account].score.unwrap(), epochScore.unwrap());
  }

  
  function distributeEpochPaymentsFromSigner(address signer, uint256 maxPayment)
    external
    onlyVm()
    returns (uint256)
  {
    return _distributeEpochPaymentsFromSigner(signer, maxPayment);
  }

  
  function _distributeEpochPaymentsFromSigner(address signer, uint256 maxPayment)
    internal
    returns (uint256)
  {
    address account = getAccounts().signerToAccount(signer);
    require(isValidator(account), "Not a validator");
    
    
    address group = getMembershipInLastEpoch(account);
    require(group != address(0), "Validator not registered with a group");
    
    
    if (meetsAccountLockedGoldRequirements(account) && meetsAccountLockedGoldRequirements(group)) {
      FixidityLib.Fraction memory totalPayment = FixidityLib
        .newFixed(maxPayment)
        .multiply(validators[account].score)
        .multiply(groups[group].slashInfo.multiplier);
      uint256 groupPayment = totalPayment.multiply(groups[group].commission).fromFixed();
      uint256 validatorPayment = totalPayment.fromFixed().sub(groupPayment);
      getStableToken().mint(group, groupPayment);
      getStableToken().mint(account, validatorPayment);
      emit ValidatorEpochPaymentDistributed(account, validatorPayment, group, groupPayment);
      return totalPayment.fromFixed();
    } else {
      return 0;
    }
  }

  
  function deregisterValidator(uint256 index) external nonReentrant returns (bool) {
    address account = getAccounts().validatorSignerToAccount(msg.sender);
    require(isValidator(account), "Not a validator");

    
    
    Validator storage validator = validators[account];
    if (validator.affiliation != address(0)) {
      require(
        !groups[validator.affiliation].members.contains(account),
        "Has been group member recently"
      );
    }
    uint256 requirementEndTime = validator.membershipHistory.lastRemovedFromGroupTimestamp.add(
      validatorLockedGoldRequirements.duration
    );
    require(requirementEndTime < now, "Not yet requirement end time");

    
    deleteElement(registeredValidators, account, index);
    delete validators[account];
    emit ValidatorDeregistered(account);
    return true;
  }

  
  function affiliate(address group) external nonReentrant returns (bool) {
    address account = getAccounts().validatorSignerToAccount(msg.sender);
    require(isValidator(account), "Not a validator");
    require(isValidatorGroup(group), "Not a validator group");
    require(meetsAccountLockedGoldRequirements(account), "Validator doesn't meet requirements");
    require(meetsAccountLockedGoldRequirements(group), "Group doesn't meet requirements");
    Validator storage validator = validators[account];
    if (validator.affiliation != address(0)) {
      _deaffiliate(validator, account);
    }
    validator.affiliation = group;
    emit ValidatorAffiliated(account, group);
    return true;
  }

  
  function deaffiliate() external nonReentrant returns (bool) {
    address account = getAccounts().validatorSignerToAccount(msg.sender);
    require(isValidator(account), "Not a validator");
    Validator storage validator = validators[account];
    require(validator.affiliation != address(0), "deaffiliate: not affiliated");
    _deaffiliate(validator, account);
    return true;
  }

  
  function updateBlsPublicKey(bytes calldata blsPublicKey, bytes calldata blsPop)
    external
    returns (bool)
  {
    address account = getAccounts().validatorSignerToAccount(msg.sender);
    require(isValidator(account), "Not a validator");
    Validator storage validator = validators[account];
    require(
      _updateBlsPublicKey(validator, account, blsPublicKey, blsPop),
      "Error updating BLS public key"
    );
    return true;
  }

  
  function _updateBlsPublicKey(
    Validator storage validator,
    address account,
    bytes memory blsPublicKey,
    bytes memory blsPop
  ) private returns (bool) {
    require(blsPublicKey.length == 96, "Wrong BLS public key length");
    require(blsPop.length == 48, "Wrong BLS PoP length");
    require(checkProofOfPossession(account, blsPublicKey, blsPop), "Invalid BLS PoP");
    validator.publicKeys.bls = blsPublicKey;
    emit ValidatorBlsPublicKeyUpdated(account, blsPublicKey);
    return true;
  }

  
  function updateEcdsaPublicKey(address account, address signer, bytes calldata ecdsaPublicKey)
    external
    onlyRegisteredContract(ACCOUNTS_REGISTRY_ID)
    returns (bool)
  {
    require(isValidator(account), "Not a validator");
    Validator storage validator = validators[account];
    require(
      _updateEcdsaPublicKey(validator, account, signer, ecdsaPublicKey),
      "Error updating ECDSA public key"
    );
    return true;
  }

  
  function _updateEcdsaPublicKey(
    Validator storage validator,
    address account,
    address signer,
    bytes memory ecdsaPublicKey
  ) private returns (bool) {
    require(ecdsaPublicKey.length == 64, "Wrong ECDSA public key length");
    require(
      address(uint160(uint256(keccak256(ecdsaPublicKey)))) == signer,
      "ECDSA key does not match signer"
    );
    validator.publicKeys.ecdsa = ecdsaPublicKey;
    emit ValidatorEcdsaPublicKeyUpdated(account, ecdsaPublicKey);
    return true;
  }

  
  function updatePublicKeys(
    address account,
    address signer,
    bytes calldata ecdsaPublicKey,
    bytes calldata blsPublicKey,
    bytes calldata blsPop
  ) external onlyRegisteredContract(ACCOUNTS_REGISTRY_ID) returns (bool) {
    require(isValidator(account), "Not a validator");
    Validator storage validator = validators[account];
    require(
      _updateEcdsaPublicKey(validator, account, signer, ecdsaPublicKey),
      "Error updating ECDSA public key"
    );
    require(
      _updateBlsPublicKey(validator, account, blsPublicKey, blsPop),
      "Error updating BLS public key"
    );
    return true;
  }

  
  function registerValidatorGroup(uint256 commission) external nonReentrant returns (bool) {
    require(commission <= FixidityLib.fixed1().unwrap(), "Commission can't be greater than 100%");
    address account = getAccounts().validatorSignerToAccount(msg.sender);
    require(!isValidator(account), "Already registered as validator");
    require(!isValidatorGroup(account), "Already registered as group");
    uint256 lockedGoldBalance = getLockedGold().getAccountTotalLockedGold(account);
    require(lockedGoldBalance >= groupLockedGoldRequirements.value, "Not enough locked gold");
    ValidatorGroup storage group = groups[account];
    group.exists = true;
    group.commission = FixidityLib.wrap(commission);
    group.slashInfo = SlashingInfo(FixidityLib.fixed1(), 0);
    registeredGroups.push(account);
    emit ValidatorGroupRegistered(account, commission);
    return true;
  }

  
  function deregisterValidatorGroup(uint256 index) external nonReentrant returns (bool) {
    address account = getAccounts().validatorSignerToAccount(msg.sender);
    
    
    require(isValidatorGroup(account), "Not a validator group");
    require(groups[account].members.numElements == 0, "Validator group not empty");
    uint256[] storage sizeHistory = groups[account].sizeHistory;
    if (sizeHistory.length > 1) {
      require(
        sizeHistory[1].add(groupLockedGoldRequirements.duration) < now,
        "Hasn't been empty for long enough"
      );
    }
    delete groups[account];
    deleteElement(registeredGroups, account, index);
    emit ValidatorGroupDeregistered(account);
    return true;
  }

  
  function addMember(address validator) external nonReentrant returns (bool) {
    address account = getAccounts().validatorSignerToAccount(msg.sender);
    require(groups[account].members.numElements > 0, "Validator group empty");
    return _addMember(account, validator, address(0), address(0));
  }

  
  function addFirstMember(address validator, address lesser, address greater)
    external
    nonReentrant
    returns (bool)
  {
    address account = getAccounts().validatorSignerToAccount(msg.sender);
    require(groups[account].members.numElements == 0, "Validator group not empty");
    return _addMember(account, validator, lesser, greater);
  }

  
  function _addMember(address group, address validator, address lesser, address greater)
    private
    returns (bool)
  {
    require(isValidatorGroup(group) && isValidator(validator), "Not validator and group");
    ValidatorGroup storage _group = groups[group];
    require(_group.members.numElements < maxGroupSize, "group would exceed maximum size");
    require(validators[validator].affiliation == group, "Not affiliated to group");
    require(!_group.members.contains(validator), "Already in group");
    uint256 numMembers = _group.members.numElements.add(1);
    _group.members.push(validator);
    require(meetsAccountLockedGoldRequirements(group), "Group requirements not met");
    require(meetsAccountLockedGoldRequirements(validator), "Validator requirements not met");
    if (numMembers == 1) {
      getElection().markGroupEligible(group, lesser, greater);
    }
    updateMembershipHistory(validator, group);
    updateSizeHistory(group, numMembers.sub(1));
    emit ValidatorGroupMemberAdded(group, validator);
    return true;
  }

  
  function removeMember(address validator) external nonReentrant returns (bool) {
    address account = getAccounts().validatorSignerToAccount(msg.sender);
    require(isValidatorGroup(account) && isValidator(validator), "is not group and validator");
    return _removeMember(account, validator);
  }

  
  function reorderMember(address validator, address lesserMember, address greaterMember)
    external
    nonReentrant
    returns (bool)
  {
    address account = getAccounts().validatorSignerToAccount(msg.sender);
    require(isValidatorGroup(account), "Not a group");
    require(isValidator(validator), "Not a validator");
    ValidatorGroup storage group = groups[account];
    require(group.members.contains(validator), "Not a member of the group");
    group.members.update(validator, lesserMember, greaterMember);
    emit ValidatorGroupMemberReordered(account, validator);
    return true;
  }

  
  function setNextCommissionUpdate(uint256 commission) external {
    address account = getAccounts().validatorSignerToAccount(msg.sender);
    require(isValidatorGroup(account), "Not a validator group");
    ValidatorGroup storage group = groups[account];
    require(commission <= FixidityLib.fixed1().unwrap(), "Commission can't be greater than 100%");
    require(commission != group.commission.unwrap(), "Commission must be different");

    group.nextCommission = FixidityLib.wrap(commission);
    group.nextCommissionBlock = block.number.add(commissionUpdateDelay);
    emit ValidatorGroupCommissionUpdateQueued(account, commission, group.nextCommissionBlock);
  }
  
  function updateCommission() external {
    address account = getAccounts().validatorSignerToAccount(msg.sender);
    require(isValidatorGroup(account), "Not a validator group");
    ValidatorGroup storage group = groups[account];

    require(group.nextCommissionBlock != 0, "No commission update queued");
    require(group.nextCommissionBlock <= block.number, "Can't apply commission update yet");

    group.commission = group.nextCommission;
    delete group.nextCommission;
    delete group.nextCommissionBlock;
    emit ValidatorGroupCommissionUpdated(account, group.commission.unwrap());
  }

  
  function getAccountLockedGoldRequirement(address account) public view returns (uint256) {
    if (isValidator(account)) {
      return validatorLockedGoldRequirements.value;
    } else if (isValidatorGroup(account)) {
      uint256 multiplier = Math.max(1, groups[account].members.numElements);
      uint256[] storage sizeHistory = groups[account].sizeHistory;
      if (sizeHistory.length > 0) {
        for (uint256 i = sizeHistory.length.sub(1); i > 0; i = i.sub(1)) {
          if (sizeHistory[i].add(groupLockedGoldRequirements.duration) >= now) {
            multiplier = Math.max(i, multiplier);
            break;
          }
        }
      }
      return groupLockedGoldRequirements.value.mul(multiplier);
    }
    return 0;
  }

  
  function meetsAccountLockedGoldRequirements(address account) public view returns (bool) {
    uint256 balance = getLockedGold().getAccountTotalLockedGold(account);
    return balance >= getAccountLockedGoldRequirement(account);
  }

  
  function getValidatorBlsPublicKeyFromSigner(address signer)
    external
    view
    returns (bytes memory blsPublicKey)
  {
    address account = getAccounts().signerToAccount(signer);
    require(isValidator(account), "Not a validator");
    return validators[account].publicKeys.bls;
  }

  
  function getValidator(address account)
    public
    view
    returns (
      bytes memory ecdsaPublicKey,
      bytes memory blsPublicKey,
      address affiliation,
      uint256 score,
      address signer
    )
  {
    require(isValidator(account), "Not a validator");
    Validator storage validator = validators[account];
    return (
      validator.publicKeys.ecdsa,
      validator.publicKeys.bls,
      validator.affiliation,
      validator.score.unwrap(),
      getAccounts().getValidatorSigner(account)
    );
  }

  
  function getValidatorGroup(address account)
    external
    view
    returns (address[] memory, uint256, uint256, uint256, uint256[] memory, uint256, uint256)
  {
    require(isValidatorGroup(account), "Not a validator group");
    ValidatorGroup storage group = groups[account];
    return (
      group.members.getKeys(),
      group.commission.unwrap(),
      group.nextCommission.unwrap(),
      group.nextCommissionBlock,
      group.sizeHistory,
      group.slashInfo.multiplier.unwrap(),
      group.slashInfo.lastSlashed
    );
  }

  
  function getGroupNumMembers(address account) public view returns (uint256) {
    require(isValidatorGroup(account), "Not validator group");
    return groups[account].members.numElements;
  }

  
  function getTopGroupValidators(address account, uint256 n)
    external
    view
    returns (address[] memory)
  {
    address[] memory topAccounts = groups[account].members.headN(n);
    address[] memory topValidators = new address[](n);
    for (uint256 i = 0; i < n; i = i.add(1)) {
      topValidators[i] = getAccounts().getValidatorSigner(topAccounts[i]);
    }
    return topValidators;
  }

  
  function getGroupsNumMembers(address[] calldata accounts)
    external
    view
    returns (uint256[] memory)
  {
    uint256[] memory numMembers = new uint256[](accounts.length);
    for (uint256 i = 0; i < accounts.length; i = i.add(1)) {
      numMembers[i] = getGroupNumMembers(accounts[i]);
    }
    return numMembers;
  }

  
  function getNumRegisteredValidators() external view returns (uint256) {
    return registeredValidators.length;
  }

  
  function getValidatorLockedGoldRequirements() external view returns (uint256, uint256) {
    return (validatorLockedGoldRequirements.value, validatorLockedGoldRequirements.duration);
  }

  
  function getGroupLockedGoldRequirements() external view returns (uint256, uint256) {
    return (groupLockedGoldRequirements.value, groupLockedGoldRequirements.duration);
  }

  
  function getRegisteredValidators() external view returns (address[] memory) {
    return registeredValidators;
  }

  
  function getRegisteredValidatorSigners() external view returns (address[] memory) {
    IAccounts accounts = getAccounts();
    address[] memory signers = new address[](registeredValidators.length);
    for (uint256 i = 0; i < signers.length; i = i.add(1)) {
      signers[i] = accounts.getValidatorSigner(registeredValidators[i]);
    }
    return signers;
  }

  
  function getRegisteredValidatorGroups() external view returns (address[] memory) {
    return registeredGroups;
  }

  
  function isValidatorGroup(address account) public view returns (bool) {
    return groups[account].exists;
  }

  
  function isValidator(address account) public view returns (bool) {
    return validators[account].publicKeys.bls.length > 0;
  }

  
  function deleteElement(address[] storage list, address element, uint256 index) private {
    require(index < list.length && list[index] == element, "deleteElement: index out of range");
    uint256 lastIndex = list.length.sub(1);
    list[index] = list[lastIndex];
    delete list[lastIndex];
    list.length = lastIndex;
  }

  
  function _removeMember(address group, address validator) private returns (bool) {
    ValidatorGroup storage _group = groups[group];
    require(validators[validator].affiliation == group, "Not affiliated to group");
    require(_group.members.contains(validator), "Not a member of the group");
    _group.members.remove(validator);
    uint256 numMembers = _group.members.numElements;
    
    if (numMembers == 0) {
      getElection().markGroupIneligible(group);
    }
    updateMembershipHistory(validator, address(0));
    updateSizeHistory(group, numMembers.add(1));
    emit ValidatorGroupMemberRemoved(group, validator);
    return true;
  }

  
  function updateMembershipHistory(address account, address group) private returns (bool) {
    MembershipHistory storage history = validators[account].membershipHistory;
    uint256 epochNumber = getEpochNumber();
    uint256 head = history.numEntries == 0 ? 0 : history.tail.add(history.numEntries.sub(1));

    if (history.numEntries > 0 && group == address(0)) {
      history.lastRemovedFromGroupTimestamp = now;
    }

    if (history.entries[head].epochNumber == epochNumber) {
      
      
      history.entries[head] = MembershipHistoryEntry(epochNumber, group);
      return true;
    }

    
    uint256 index = history.numEntries == 0 ? 0 : head.add(1);
    history.entries[index] = MembershipHistoryEntry(epochNumber, group);
    if (history.numEntries < membershipHistoryLength) {
      
      history.numEntries = history.numEntries.add(1);
    } else if (history.numEntries == membershipHistoryLength) {
      
      delete history.entries[history.tail];
      history.tail = history.tail.add(1);
    } else {
      
      delete history.entries[history.tail];
      delete history.entries[history.tail.add(1)];
      history.numEntries = history.numEntries.sub(1);
      history.tail = history.tail.add(2);
    }
    return true;
  }

  
  function updateSizeHistory(address group, uint256 size) private {
    uint256[] storage sizeHistory = groups[group].sizeHistory;
    if (size == sizeHistory.length) {
      sizeHistory.push(now);
    } else if (size < sizeHistory.length) {
      sizeHistory[size] = now;
    } else {
      require(false, "Unable to update size history");
    }
  }

  
  function getMembershipInLastEpochFromSigner(address signer) external view returns (address) {
    address account = getAccounts().signerToAccount(signer);
    require(isValidator(account), "Not a validator");
    return getMembershipInLastEpoch(account);
  }

  
  function getMembershipInLastEpoch(address account) public view returns (address) {
    uint256 epochNumber = getEpochNumber();
    MembershipHistory storage history = validators[account].membershipHistory;
    uint256 head = history.numEntries == 0 ? 0 : history.tail.add(history.numEntries.sub(1));
    
    
    if (history.entries[head].epochNumber == epochNumber) {
      if (head > history.tail) {
        head = head.sub(1);
      }
    }
    return history.entries[head].group;
  }

  
  function _deaffiliate(Validator storage validator, address validatorAccount)
    private
    returns (bool)
  {
    address affiliation = validator.affiliation;
    ValidatorGroup storage group = groups[affiliation];
    if (group.members.contains(validatorAccount)) {
      _removeMember(affiliation, validatorAccount);
    }
    validator.affiliation = address(0);
    emit ValidatorDeaffiliated(validatorAccount, affiliation);
    return true;
  }

  
  function forceDeaffiliateIfValidator(address validatorAccount) external nonReentrant onlySlasher {
    if (isValidator(validatorAccount)) {
      Validator storage validator = validators[validatorAccount];
      if (validator.affiliation != address(0)) {
        _deaffiliate(validator, validatorAccount);
      }
    }
  }

  
  function setSlashingMultiplierResetPeriod(uint256 value) public nonReentrant onlyOwner {
    slashingMultiplierResetPeriod = value;
  }

  
  function resetSlashingMultiplier() external nonReentrant {
    address account = getAccounts().validatorSignerToAccount(msg.sender);
    require(isValidatorGroup(account), "Not a validator group");
    ValidatorGroup storage group = groups[account];
    require(
      now >= group.slashInfo.lastSlashed.add(slashingMultiplierResetPeriod),
      "`resetSlashingMultiplier` called before resetPeriod expired"
    );
    group.slashInfo.multiplier = FixidityLib.fixed1();
  }

  
  function halveSlashingMultiplier(address account) external nonReentrant onlySlasher {
    require(isValidatorGroup(account), "Not a validator group");
    ValidatorGroup storage group = groups[account];
    group.slashInfo.multiplier = FixidityLib.wrap(group.slashInfo.multiplier.unwrap().div(2));
    group.slashInfo.lastSlashed = now;
  }

  
  function getValidatorGroupSlashingMultiplier(address account) external view returns (uint256) {
    require(isValidatorGroup(account), "Not a validator group");
    ValidatorGroup storage group = groups[account];
    return group.slashInfo.multiplier.unwrap();
  }

  
  function groupMembershipInEpoch(address account, uint256 epochNumber, uint256 index)
    external
    view
    returns (address)
  {
    require(isValidator(account), "Not a validator");
    require(epochNumber <= getEpochNumber(), "Epoch cannot be larger than current");
    MembershipHistory storage history = validators[account].membershipHistory;
    require(index < history.tail.add(history.numEntries), "index out of bounds");
    require(index >= history.tail && history.numEntries > 0, "index out of bounds");
    bool isExactMatch = history.entries[index].epochNumber == epochNumber;
    bool isLastEntry = index.sub(history.tail) == history.numEntries.sub(1);
    bool isWithinRange = history.entries[index].epochNumber < epochNumber &&
      (history.entries[index.add(1)].epochNumber > epochNumber || isLastEntry);
    require(
      isExactMatch || isWithinRange,
      "provided index does not match provided epochNumber at index in history."
    );
    return history.entries[index].group;
  }

}