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

contract Initializable {
  bool public initialized;

  modifier initializer() {
    require(!initialized, "contract already initialized");
    initialized = true;
    _;
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

library SortedLinkedList {
  using SafeMath for uint256;
  using LinkedList for LinkedList.List;

  struct List {
    LinkedList.List list;
    mapping(bytes32 => uint256) values;
  }

  
  function insert(
    List storage list,
    bytes32 key,
    uint256 value,
    bytes32 lesserKey,
    bytes32 greaterKey
  ) public {
    require(
      key != bytes32(0) && key != lesserKey && key != greaterKey && !contains(list, key),
      "invalid key"
    );
    require(
      (lesserKey != bytes32(0) || greaterKey != bytes32(0)) || list.list.numElements == 0,
      "greater and lesser key zero"
    );
    require(contains(list, lesserKey) || lesserKey == bytes32(0), "invalid lesser key");
    require(contains(list, greaterKey) || greaterKey == bytes32(0), "invalid greater key");
    (lesserKey, greaterKey) = getLesserAndGreater(list, value, lesserKey, greaterKey);
    list.list.insert(key, lesserKey, greaterKey);
    list.values[key] = value;
  }

  
  function remove(List storage list, bytes32 key) public {
    list.list.remove(key);
    list.values[key] = 0;
  }

  
  function update(
    List storage list,
    bytes32 key,
    uint256 value,
    bytes32 lesserKey,
    bytes32 greaterKey
  ) public {
    
    
    
    remove(list, key);
    insert(list, key, value, lesserKey, greaterKey);
  }

  
  function push(List storage list, bytes32 key) public {
    insert(list, key, 0, bytes32(0), list.list.tail);
  }

  
  function popN(List storage list, uint256 n) public returns (bytes32[] memory) {
    require(n <= list.list.numElements, "not enough elements");
    bytes32[] memory keys = new bytes32[](n);
    for (uint256 i = 0; i < n; i = i.add(1)) {
      bytes32 key = list.list.head;
      keys[i] = key;
      remove(list, key);
    }
    return keys;
  }

  
  function contains(List storage list, bytes32 key) public view returns (bool) {
    return list.list.contains(key);
  }

  
  function getValue(List storage list, bytes32 key) public view returns (uint256) {
    return list.values[key];
  }

  
  function getElements(List storage list) public view returns (bytes32[] memory, uint256[] memory) {
    bytes32[] memory keys = getKeys(list);
    uint256[] memory values = new uint256[](keys.length);
    for (uint256 i = 0; i < keys.length; i = i.add(1)) {
      values[i] = list.values[keys[i]];
    }
    return (keys, values);
  }

  
  function getKeys(List storage list) public view returns (bytes32[] memory) {
    return list.list.getKeys();
  }

  
  function headN(List storage list, uint256 n) public view returns (bytes32[] memory) {
    return list.list.headN(n);
  }

  
  
  function getLesserAndGreater(
    List storage list,
    uint256 value,
    bytes32 lesserKey,
    bytes32 greaterKey
  ) private view returns (bytes32, bytes32) {
    
    
    
    
    
    if (lesserKey == bytes32(0) && isValueBetween(list, value, lesserKey, list.list.tail)) {
      return (lesserKey, list.list.tail);
    } else if (
      greaterKey == bytes32(0) && isValueBetween(list, value, list.list.head, greaterKey)
    ) {
      return (list.list.head, greaterKey);
    } else if (
      lesserKey != bytes32(0) &&
      isValueBetween(list, value, lesserKey, list.list.elements[lesserKey].nextKey)
    ) {
      return (lesserKey, list.list.elements[lesserKey].nextKey);
    } else if (
      greaterKey != bytes32(0) &&
      isValueBetween(list, value, list.list.elements[greaterKey].previousKey, greaterKey)
    ) {
      return (list.list.elements[greaterKey].previousKey, greaterKey);
    } else {
      require(false, "get lesser and greater failure");
    }
  }

  
  function isValueBetween(List storage list, uint256 value, bytes32 lesserKey, bytes32 greaterKey)
    private
    view
    returns (bool)
  {
    bool isLesser = lesserKey == bytes32(0) || list.values[lesserKey] <= value;
    bool isGreater = greaterKey == bytes32(0) || list.values[greaterKey] >= value;
    return isLesser && isGreater;
  }
}

library SortedLinkedListWithMedian {
  using SafeMath for uint256;
  using SortedLinkedList for SortedLinkedList.List;

  enum MedianAction { None, Lesser, Greater }

  enum MedianRelation { Undefined, Lesser, Greater, Equal }

  struct List {
    SortedLinkedList.List list;
    bytes32 median;
    mapping(bytes32 => MedianRelation) relation;
  }

  
  function insert(
    List storage list,
    bytes32 key,
    uint256 value,
    bytes32 lesserKey,
    bytes32 greaterKey
  ) public {
    list.list.insert(key, value, lesserKey, greaterKey);
    LinkedList.Element storage element = list.list.list.elements[key];

    MedianAction action = MedianAction.None;
    if (list.list.list.numElements == 1) {
      list.median = key;
      list.relation[key] = MedianRelation.Equal;
    } else if (list.list.list.numElements % 2 == 1) {
      
      
      
      if (
        element.previousKey == bytes32(0) ||
        list.relation[element.previousKey] == MedianRelation.Lesser
      ) {
        action = MedianAction.Lesser;
        list.relation[key] = MedianRelation.Lesser;
      } else {
        list.relation[key] = MedianRelation.Greater;
      }
    } else {
      
      
      
      if (
        element.nextKey == bytes32(0) || list.relation[element.nextKey] == MedianRelation.Greater
      ) {
        action = MedianAction.Greater;
        list.relation[key] = MedianRelation.Greater;
      } else {
        list.relation[key] = MedianRelation.Lesser;
      }
    }
    updateMedian(list, action);
  }

  
  function remove(List storage list, bytes32 key) public {
    MedianAction action = MedianAction.None;
    if (list.list.list.numElements == 0) {
      list.median = bytes32(0);
    } else if (list.list.list.numElements % 2 == 0) {
      
      
      
      if (
        list.relation[key] == MedianRelation.Greater || list.relation[key] == MedianRelation.Equal
      ) {
        action = MedianAction.Lesser;
      }
    } else {
      
      
      
      if (
        list.relation[key] == MedianRelation.Lesser || list.relation[key] == MedianRelation.Equal
      ) {
        action = MedianAction.Greater;
      }
    }
    updateMedian(list, action);

    list.list.remove(key);
  }

  
  function update(
    List storage list,
    bytes32 key,
    uint256 value,
    bytes32 lesserKey,
    bytes32 greaterKey
  ) public {
    
    
    
    remove(list, key);
    insert(list, key, value, lesserKey, greaterKey);
  }

  
  function push(List storage list, bytes32 key) public {
    insert(list, key, 0, bytes32(0), list.list.list.tail);
  }

  
  function popN(List storage list, uint256 n) public returns (bytes32[] memory) {
    require(n <= list.list.list.numElements, "not enough elements");
    bytes32[] memory keys = new bytes32[](n);
    for (uint256 i = 0; i < n; i = i.add(1)) {
      bytes32 key = list.list.list.head;
      keys[i] = key;
      remove(list, key);
    }
    return keys;
  }

  
  function contains(List storage list, bytes32 key) public view returns (bool) {
    return list.list.contains(key);
  }

  
  function getValue(List storage list, bytes32 key) public view returns (uint256) {
    return list.list.values[key];
  }

  
  function getMedianValue(List storage list) public view returns (uint256) {
    return getValue(list, list.median);
  }

  
  function getHead(List storage list) external view returns (bytes32) {
    return list.list.list.head;
  }

  
  function getMedian(List storage list) external view returns (bytes32) {
    return list.median;
  }

  
  function getTail(List storage list) external view returns (bytes32) {
    return list.list.list.tail;
  }

  
  function getNumElements(List storage list) external view returns (uint256) {
    return list.list.list.numElements;
  }

  
  function getElements(List storage list)
    public
    view
    returns (bytes32[] memory, uint256[] memory, MedianRelation[] memory)
  {
    bytes32[] memory keys = getKeys(list);
    uint256[] memory values = new uint256[](keys.length);
    MedianRelation[] memory relations = new MedianRelation[](keys.length);
    for (uint256 i = 0; i < keys.length; i = i.add(1)) {
      values[i] = list.list.values[keys[i]];
      relations[i] = list.relation[keys[i]];
    }
    return (keys, values, relations);
  }

  
  function getKeys(List storage list) public view returns (bytes32[] memory) {
    return list.list.getKeys();
  }

  
  function updateMedian(List storage list, MedianAction action) private {
    LinkedList.Element storage previousMedian = list.list.list.elements[list.median];
    if (action == MedianAction.Lesser) {
      list.relation[list.median] = MedianRelation.Greater;
      list.median = previousMedian.previousKey;
    } else if (action == MedianAction.Greater) {
      list.relation[list.median] = MedianRelation.Lesser;
      list.median = previousMedian.nextKey;
    }
    list.relation[list.median] = MedianRelation.Equal;
  }
}

library AddressSortedLinkedListWithMedian {
  using SafeMath for uint256;
  using SortedLinkedListWithMedian for SortedLinkedListWithMedian.List;

  function toBytes(address a) public pure returns (bytes32) {
    return bytes32(uint256(a) << 96);
  }

  function toAddress(bytes32 b) public pure returns (address) {
    return address(uint256(b) >> 96);
  }

  
  function insert(
    SortedLinkedListWithMedian.List storage list,
    address key,
    uint256 value,
    address lesserKey,
    address greaterKey
  ) public {
    list.insert(toBytes(key), value, toBytes(lesserKey), toBytes(greaterKey));
  }

  
  function remove(SortedLinkedListWithMedian.List storage list, address key) public {
    list.remove(toBytes(key));
  }

  
  function update(
    SortedLinkedListWithMedian.List storage list,
    address key,
    uint256 value,
    address lesserKey,
    address greaterKey
  ) public {
    list.update(toBytes(key), value, toBytes(lesserKey), toBytes(greaterKey));
  }

  
  function contains(SortedLinkedListWithMedian.List storage list, address key)
    public
    view
    returns (bool)
  {
    return list.contains(toBytes(key));
  }

  
  function getValue(SortedLinkedListWithMedian.List storage list, address key)
    public
    view
    returns (uint256)
  {
    return list.getValue(toBytes(key));
  }

  
  function getMedianValue(SortedLinkedListWithMedian.List storage list)
    public
    view
    returns (uint256)
  {
    return list.getValue(list.median);
  }

  
  function getHead(SortedLinkedListWithMedian.List storage list) external view returns (address) {
    return toAddress(list.getHead());
  }

  
  function getMedian(SortedLinkedListWithMedian.List storage list) external view returns (address) {
    return toAddress(list.getMedian());
  }

  
  function getTail(SortedLinkedListWithMedian.List storage list) external view returns (address) {
    return toAddress(list.getTail());
  }

  
  function getNumElements(SortedLinkedListWithMedian.List storage list)
    external
    view
    returns (uint256)
  {
    return list.getNumElements();
  }

  
  function getElements(SortedLinkedListWithMedian.List storage list)
    public
    view
    returns (address[] memory, uint256[] memory, SortedLinkedListWithMedian.MedianRelation[] memory)
  {
    bytes32[] memory byteKeys = list.getKeys();
    address[] memory keys = new address[](byteKeys.length);
    uint256[] memory values = new uint256[](byteKeys.length);
    
    SortedLinkedListWithMedian.MedianRelation[] memory relations =
      new SortedLinkedListWithMedian.MedianRelation[](keys.length);
    for (uint256 i = 0; i < byteKeys.length; i = i.add(1)) {
      keys[i] = toAddress(byteKeys[i]);
      values[i] = list.getValue(byteKeys[i]);
      relations[i] = list.relation[byteKeys[i]];
    }
    return (keys, values, relations);
  }
}

contract SortedOracles is ISortedOracles, Ownable, Initializable {
  using SafeMath for uint256;
  using AddressSortedLinkedListWithMedian for SortedLinkedListWithMedian.List;
  using FixidityLib for FixidityLib.Fraction;

  uint256 private constant FIXED1_UINT = 1000000000000000000000000;

  
  mapping(address => SortedLinkedListWithMedian.List) private rates;
  
  mapping(address => SortedLinkedListWithMedian.List) private timestamps;
  mapping(address => mapping(address => bool)) public isOracle;
  mapping(address => address[]) public oracles;

  uint256 public reportExpirySeconds;

  event OracleAdded(address indexed token, address indexed oracleAddress);
  event OracleRemoved(address indexed token, address indexed oracleAddress);
  event OracleReported(
    address indexed token,
    address indexed oracle,
    uint256 timestamp,
    uint256 value
  );
  event OracleReportRemoved(address indexed token, address indexed oracle);
  event MedianUpdated(address indexed token, uint256 value);
  event ReportExpirySet(uint256 reportExpiry);

  modifier onlyOracle(address token) {
    require(isOracle[token][msg.sender], "sender was not an oracle for token addr");
    _;
  }

  
  function initialize(uint256 _reportExpirySeconds) external initializer {
    _transferOwnership(msg.sender);
    setReportExpiry(_reportExpirySeconds);
  }

  
  function setReportExpiry(uint256 _reportExpirySeconds) public onlyOwner {
    require(_reportExpirySeconds > 0, "report expiry seconds must be > 0");
    require(_reportExpirySeconds != reportExpirySeconds, "reportExpirySeconds hasn't changed");
    reportExpirySeconds = _reportExpirySeconds;
    emit ReportExpirySet(_reportExpirySeconds);
  }

  
  function addOracle(address token, address oracleAddress) external onlyOwner {
    require(
      token != address(0) && oracleAddress != address(0) && !isOracle[token][oracleAddress],
      "token addr was null or oracle addr was null or oracle addr is not an oracle for token addr"
    );
    isOracle[token][oracleAddress] = true;
    oracles[token].push(oracleAddress);
    emit OracleAdded(token, oracleAddress);
  }

  
  function removeOracle(address token, address oracleAddress, uint256 index) external onlyOwner {
    require(
      token != address(0) &&
        oracleAddress != address(0) &&
        oracles[token].length > index &&
        oracles[token][index] == oracleAddress,
      "token addr null or oracle addr null or index of token oracle not mapped to oracle addr"
    );
    isOracle[token][oracleAddress] = false;
    oracles[token][index] = oracles[token][oracles[token].length.sub(1)];
    oracles[token].length = oracles[token].length.sub(1);
    if (reportExists(token, oracleAddress)) {
      removeReport(token, oracleAddress);
    }
    emit OracleRemoved(token, oracleAddress);
  }

  
  function removeExpiredReports(address token, uint256 n) external {
    require(
      token != address(0) && n < timestamps[token].getNumElements(),
      "token addr null or trying to remove too many reports"
    );
    for (uint256 i = 0; i < n; i = i.add(1)) {
      (bool isExpired, address oldestAddress) = isOldestReportExpired(token);
      if (isExpired) {
        removeReport(token, oldestAddress);
      } else {
        break;
      }
    }
  }

  
  function isOldestReportExpired(address token) public view returns (bool, address) {
    require(token != address(0));
    address oldest = timestamps[token].getTail();
    uint256 timestamp = timestamps[token].getValue(oldest);
    
    if (now.sub(timestamp) >= reportExpirySeconds) {
      return (true, oldest);
    }
    return (false, oldest);
  }

  
  function report(address token, uint256 value, address lesserKey, address greaterKey)
    external
    onlyOracle(token)
  {
    uint256 originalMedian = rates[token].getMedianValue();
    if (rates[token].contains(msg.sender)) {
      rates[token].update(msg.sender, value, lesserKey, greaterKey);

      
      
      
      
      
      
      
      
      
      
      timestamps[token].remove(msg.sender);
    } else {
      rates[token].insert(msg.sender, value, lesserKey, greaterKey);
    }
    timestamps[token].insert(
      msg.sender,
      
      now,
      timestamps[token].getHead(),
      address(0)
    );
    emit OracleReported(token, msg.sender, now, value);
    uint256 newMedian = rates[token].getMedianValue();
    if (newMedian != originalMedian) {
      emit MedianUpdated(token, newMedian);
    }
  }

  
  function numRates(address token) public view returns (uint256) {
    return rates[token].getNumElements();
  }

  
  function medianRate(address token) external view returns (uint256, uint256) {
    return (rates[token].getMedianValue(), numRates(token) == 0 ? 0 : FIXED1_UINT);
  }

  
  function getRates(address token)
    external
    view
    returns (address[] memory, uint256[] memory, SortedLinkedListWithMedian.MedianRelation[] memory)
  {
    return rates[token].getElements();
  }

  
  function numTimestamps(address token) public view returns (uint256) {
    return timestamps[token].getNumElements();
  }

  
  function medianTimestamp(address token) external view returns (uint256) {
    return timestamps[token].getMedianValue();
  }

  
  function getTimestamps(address token)
    external
    view
    returns (address[] memory, uint256[] memory, SortedLinkedListWithMedian.MedianRelation[] memory)
  {
    return timestamps[token].getElements();
  }

  
  function reportExists(address token, address oracle) internal view returns (bool) {
    return rates[token].contains(oracle) && timestamps[token].contains(oracle);
  }

  
  function getOracles(address token) external view returns (address[] memory) {
    return oracles[token];
  }

  
  function removeReport(address token, address oracle) private {
    if (numTimestamps(token) == 1 && reportExists(token, oracle)) return;
    uint256 originalMedian = rates[token].getMedianValue();
    rates[token].remove(oracle);
    timestamps[token].remove(oracle);
    emit OracleReportRemoved(token, oracle);
    uint256 newMedian = rates[token].getMedianValue();
    if (newMedian != originalMedian) {
      emit MedianUpdated(token, newMedian);
    }
  }
}