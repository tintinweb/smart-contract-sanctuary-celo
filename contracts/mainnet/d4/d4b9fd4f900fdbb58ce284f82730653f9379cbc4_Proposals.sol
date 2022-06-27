pragma solidity ^0.5.8;


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

library Address {
    
    function isContract(address account) internal view returns (bool) {
        
        
        
        bytes32 codehash;
        bytes32 accountHash = 0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470;
        
        assembly { codehash := extcodehash(account) }
        return (codehash != accountHash && codehash != 0x0);
    }

    
    function toPayable(address account) internal pure returns (address payable) {
        return address(uint160(account));
    }

    
    function sendValue(address payable recipient, uint256 amount) internal {
        require(address(this).balance >= amount, "Address: insufficient balance");

        
        (bool success, ) = recipient.call.value(amount)("");
        require(success, "Address: unable to send value, recipient may have reverted");
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

library Proposals {
  using FixidityLib for FixidityLib.Fraction;
  using SafeMath for uint256;
  using BytesLib for bytes;

  enum Stage { None, Queued, Approval, Referendum, Execution, Expiration }

  enum VoteValue { None, Abstain, No, Yes }

  struct StageDurations {
    uint256 approval;
    uint256 referendum;
    uint256 execution;
  }

  
  struct VoteTotals {
    uint256 yes;
    uint256 no;
    uint256 abstain;
  }

  struct Transaction {
    uint256 value;
    address destination;
    bytes data;
  }

  struct Proposal {
    address proposer;
    uint256 deposit;
    uint256 timestamp;
    VoteTotals votes;
    Transaction[] transactions;
    bool approved;
    uint256 networkWeight;
    string descriptionUrl;
  }

  
  function make(
    Proposal storage proposal,
    uint256[] memory values,
    address[] memory destinations,
    bytes memory data,
    uint256[] memory dataLengths,
    address proposer,
    uint256 deposit
  ) public {
    require(
      values.length == destinations.length && destinations.length == dataLengths.length,
      "Array length mismatch"
    );
    uint256 transactionCount = values.length;

    proposal.proposer = proposer;
    proposal.deposit = deposit;
    
    proposal.timestamp = now;

    uint256 dataPosition = 0;
    delete proposal.transactions;
    for (uint256 i = 0; i < transactionCount; i = i.add(1)) {
      proposal.transactions.push(
        Transaction(values[i], destinations[i], data.slice(dataPosition, dataLengths[i]))
      );
      dataPosition = dataPosition.add(dataLengths[i]);
    }
  }

  function setDescriptionUrl(Proposal storage proposal, string memory descriptionUrl) internal {
    require(bytes(descriptionUrl).length != 0, "Description url must have non-zero length");
    proposal.descriptionUrl = descriptionUrl;
  }

  
  function makeMem(
    uint256[] memory values,
    address[] memory destinations,
    bytes memory data,
    uint256[] memory dataLengths,
    address proposer,
    uint256 deposit
  ) internal view returns (Proposal memory) {
    require(
      values.length == destinations.length && destinations.length == dataLengths.length,
      "Array length mismatch"
    );
    uint256 transactionCount = values.length;

    Proposal memory proposal;
    proposal.proposer = proposer;
    proposal.deposit = deposit;
    
    proposal.timestamp = now;

    uint256 dataPosition = 0;
    proposal.transactions = new Transaction[](transactionCount);
    for (uint256 i = 0; i < transactionCount; i = i.add(1)) {
      proposal.transactions[i] = Transaction(
        values[i],
        destinations[i],
        data.slice(dataPosition, dataLengths[i])
      );
      dataPosition = dataPosition.add(dataLengths[i]);
    }
    return proposal;
  }

  
  function updateVote(
    Proposal storage proposal,
    uint256 previousWeight,
    uint256 currentWeight,
    VoteValue previousVote,
    VoteValue currentVote
  ) public {
    
    if (previousVote == VoteValue.Abstain) {
      proposal.votes.abstain = proposal.votes.abstain.sub(previousWeight);
    } else if (previousVote == VoteValue.Yes) {
      proposal.votes.yes = proposal.votes.yes.sub(previousWeight);
    } else if (previousVote == VoteValue.No) {
      proposal.votes.no = proposal.votes.no.sub(previousWeight);
    }

    
    if (currentVote == VoteValue.Abstain) {
      proposal.votes.abstain = proposal.votes.abstain.add(currentWeight);
    } else if (currentVote == VoteValue.Yes) {
      proposal.votes.yes = proposal.votes.yes.add(currentWeight);
    } else if (currentVote == VoteValue.No) {
      proposal.votes.no = proposal.votes.no.add(currentWeight);
    }
  }

  
  function execute(Proposal storage proposal) public {
    executeTransactions(proposal.transactions);
  }

  
  function executeMem(Proposal memory proposal) internal {
    executeTransactions(proposal.transactions);
  }

  function executeTransactions(Transaction[] memory transactions) internal {
    for (uint256 i = 0; i < transactions.length; i = i.add(1)) {
      require(
        externalCall(
          transactions[i].destination,
          transactions[i].value,
          transactions[i].data.length,
          transactions[i].data
        ),
        "Proposal execution failed"
      );
    }
  }

  
  function getSupportWithQuorumPadding(
    Proposal storage proposal,
    FixidityLib.Fraction memory quorum
  ) internal view returns (FixidityLib.Fraction memory) {
    uint256 yesVotes = proposal.votes.yes;
    if (yesVotes == 0) {
      return FixidityLib.newFixed(0);
    }
    uint256 noVotes = proposal.votes.no;
    uint256 totalVotes = yesVotes.add(noVotes).add(proposal.votes.abstain);
    uint256 requiredVotes = quorum
      .multiply(FixidityLib.newFixed(proposal.networkWeight))
      .fromFixed();
    if (requiredVotes > totalVotes) {
      noVotes = noVotes.add(requiredVotes.sub(totalVotes));
    }
    return FixidityLib.newFixedFraction(yesVotes, yesVotes.add(noVotes));
  }

  
  function getDequeuedStage(Proposal storage proposal, StageDurations storage stageDurations)
    internal
    view
    returns (Stage)
  {
    uint256 stageStartTime = proposal
      .timestamp
      .add(stageDurations.approval)
      .add(stageDurations.referendum)
      .add(stageDurations.execution);
    
    if (now >= stageStartTime) {
      return Stage.Expiration;
    }
    stageStartTime = stageStartTime.sub(stageDurations.execution);
    
    if (now >= stageStartTime) {
      return Stage.Execution;
    }
    stageStartTime = stageStartTime.sub(stageDurations.referendum);
    
    if (now >= stageStartTime) {
      return Stage.Referendum;
    }
    return Stage.Approval;
  }

  
  function getParticipation(Proposal storage proposal)
    internal
    view
    returns (FixidityLib.Fraction memory)
  {
    uint256 totalVotes = proposal.votes.yes.add(proposal.votes.no).add(proposal.votes.abstain);
    return FixidityLib.newFixedFraction(totalVotes, proposal.networkWeight);
  }

  
  function getTransaction(Proposal storage proposal, uint256 index)
    public
    view
    returns (uint256, address, bytes memory)
  {
    require(index < proposal.transactions.length, "getTransaction: bad index");
    Transaction storage transaction = proposal.transactions[index];
    return (transaction.value, transaction.destination, transaction.data);
  }

  
  function unpack(Proposal storage proposal)
    internal
    view
    returns (address, uint256, uint256, uint256, string storage)
  {
    return (
      proposal.proposer,
      proposal.deposit,
      proposal.timestamp,
      proposal.transactions.length,
      proposal.descriptionUrl
    );
  }

  
  function getVoteTotals(Proposal storage proposal)
    internal
    view
    returns (uint256, uint256, uint256)
  {
    return (proposal.votes.yes, proposal.votes.no, proposal.votes.abstain);
  }

  
  function isApproved(Proposal storage proposal) internal view returns (bool) {
    return proposal.approved;
  }

  
  function exists(Proposal storage proposal) internal view returns (bool) {
    return proposal.timestamp > 0;
  }

  
  
  
  function externalCall(address destination, uint256 value, uint256 dataLength, bytes memory data)
    private
    returns (bool)
  {
    bool result;

    if (dataLength > 0) require(Address.isContract(destination), "Invalid contract address");

    
    assembly {
      
      let x := mload(0x40) 
      let d := add(data, 32) 
      result := call(
        sub(gas, 34710), 
        
        
        destination,
        value,
        d,
        dataLength, 
        x,
        0 
      )
      
    }
    
    return result;
  }
}