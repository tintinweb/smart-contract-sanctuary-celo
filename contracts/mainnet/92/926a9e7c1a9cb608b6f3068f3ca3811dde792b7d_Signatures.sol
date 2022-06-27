pragma solidity ^0.5.3;


library ECDSA {
    
    function recover(bytes32 hash, bytes memory signature) internal pure returns (address) {
        
        if (signature.length != 65) {
            return (address(0));
        }

        
        bytes32 r;
        bytes32 s;
        uint8 v;

        
        
        
        assembly {
            r := mload(add(signature, 0x20))
            s := mload(add(signature, 0x40))
            v := byte(0, mload(add(signature, 0x60)))
        }

        
        
        
        
        
        
        
        
        
        if (uint256(s) > 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0) {
            return address(0);
        }

        if (v != 27 && v != 28) {
            return address(0);
        }

        
        return ecrecover(hash, v, r, s);
    }

    
    function toEthSignedMessageHash(bytes32 hash) internal pure returns (bytes32) {
        
        
        return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", hash));
    }
}

library Signatures {
  
  function getSignerOfAddress(address message, uint8 v, bytes32 r, bytes32 s)
    public
    pure
    returns (address)
  {
    bytes32 hash = keccak256(abi.encodePacked(message));
    return getSignerOfMessageHash(hash, v, r, s);
  }

  
  function getSignerOfMessageHash(bytes32 messageHash, uint8 v, bytes32 r, bytes32 s)
    public
    pure
    returns (address)
  {
    bytes memory signature = new bytes(65);
    
    assembly {
      mstore(add(signature, 32), r)
      mstore(add(signature, 64), s)
      mstore8(add(signature, 96), v)
    }
    bytes32 prefixedHash = ECDSA.toEthSignedMessageHash(messageHash);
    return ECDSA.recover(prefixedHash, signature);
  }
}