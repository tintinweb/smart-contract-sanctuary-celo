pragma solidity ^0.5.3;


interface IRandom {
  function revealAndCommit(bytes32, bytes32, address) external;
  function randomnessBlockRetentionWindow() external view returns (uint256);
  function random() external view returns (bytes32);
  function getBlockRandomness(uint256) external view returns (bytes32);
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

contract Random is IRandom, Ownable, Initializable, UsingPrecompiles, CalledByVm {
  using SafeMath for uint256;

  
  mapping(address => bytes32) public commitments;

  uint256 public randomnessBlockRetentionWindow;

  mapping(uint256 => bytes32) private history;
  uint256 private historyFirst;
  uint256 private historySize;
  uint256 private lastEpochBlock;

  event RandomnessBlockRetentionWindowSet(uint256 value);

  
  function initialize(uint256 _randomnessBlockRetentionWindow) external initializer {
    _transferOwnership(msg.sender);
    setRandomnessBlockRetentionWindow(_randomnessBlockRetentionWindow);
  }

  
  function setRandomnessBlockRetentionWindow(uint256 value) public onlyOwner {
    require(value > 0, "randomnessBlockRetetionWindow cannot be zero");
    randomnessBlockRetentionWindow = value;
    emit RandomnessBlockRetentionWindowSet(value);
  }

  
  function revealAndCommit(bytes32 randomness, bytes32 newCommitment, address proposer)
    external
    onlyVm
  {
    _revealAndCommit(randomness, newCommitment, proposer);
  }

  
  function _revealAndCommit(bytes32 randomness, bytes32 newCommitment, address proposer) internal {
    require(newCommitment != computeCommitment(0), "cannot commit zero randomness");

    
    if (commitments[proposer] != 0) {
      require(randomness != 0, "randomness cannot be zero if there is a previous commitment");
      bytes32 expectedCommitment = computeCommitment(randomness);
      require(
        expectedCommitment == commitments[proposer],
        "commitment didn't match the posted randomness"
      );
    } else {
      require(randomness == 0, "randomness should be zero if there is no previous commitment");
    }

    
    uint256 blockNumber = block.number == 0 ? 0 : block.number.sub(1);
    addRandomness(block.number, keccak256(abi.encodePacked(history[blockNumber], randomness)));

    commitments[proposer] = newCommitment;
  }

  
  function addRandomness(uint256 blockNumber, bytes32 randomness) internal {
    history[blockNumber] = randomness;
    if (blockNumber % getEpochSize() == 0) {
      if (lastEpochBlock < historyFirst) {
        delete history[lastEpochBlock];
      }
      lastEpochBlock = blockNumber;
    } else {
      if (historySize == 0) {
        historyFirst = blockNumber;
        historySize = 1;
      } else if (historySize > randomnessBlockRetentionWindow) {
        deleteHistoryIfNotLastEpochBlock(historyFirst);
        deleteHistoryIfNotLastEpochBlock(historyFirst.add(1));
        historyFirst = historyFirst.add(2);
        historySize = historySize.sub(1);
      } else if (historySize == randomnessBlockRetentionWindow) {
        deleteHistoryIfNotLastEpochBlock(historyFirst);
        historyFirst = historyFirst.add(1);
      } else {
        
        historySize = historySize.add(1);
      }
    }
  }

  
  function computeCommitment(bytes32 randomness) public pure returns (bytes32) {
    return keccak256(abi.encodePacked(randomness));
  }

  
  function random() external view returns (bytes32) {
    return _getBlockRandomness(block.number, block.number);
  }

  
  function getBlockRandomness(uint256 blockNumber) external view returns (bytes32) {
    return _getBlockRandomness(blockNumber, block.number);
  }

  
  function _getBlockRandomness(uint256 blockNumber, uint256 cur) internal view returns (bytes32) {
    require(blockNumber <= cur, "Cannot query randomness of future blocks");
    require(
      blockNumber == lastEpochBlock ||
        (blockNumber > cur.sub(historySize) &&
          (randomnessBlockRetentionWindow >= cur ||
            blockNumber > cur.sub(randomnessBlockRetentionWindow))),
      "Cannot query randomness older than the stored history"
    );
    return history[blockNumber];
  }

  function deleteHistoryIfNotLastEpochBlock(uint256 blockNumber) internal {
    if (blockNumber != lastEpochBlock) {
      delete history[blockNumber];
    }
  }
}