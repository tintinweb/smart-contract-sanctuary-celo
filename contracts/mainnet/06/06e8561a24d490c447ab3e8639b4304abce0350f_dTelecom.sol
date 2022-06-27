// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

contract dTelecom {
    event CreateCall(
         address indexed _from,
         string _number,
         uint256 _node_id,
         uint256 _call_id,
         uint256 _price
    );

    event EndCall(
        address indexed _from,
        string _number,
        uint256 _node_id,
        uint256 _call_id,
        uint256 _price,
        uint256 _status,
        uint256 _duration
    );

    struct Node{
        string ip;
        string pattern;
        uint256 price;
        address owner;
        uint256 id;
    }

    struct Call{
        address from;
        string number;
        uint256 node_id;
        uint256 id;
        uint256 state;
        uint256 createdAt;
        uint256 endAt;
        uint256 price;
        uint256 duration;
    }

    using Counters for Counters.Counter;

    Counters.Counter private _nodeSeqCounter;
    Counters.Counter private _callSeqCounter;

    IERC20 public usd_token;
    uint256 public minimal_duration;

    mapping(address => uint256) public prepay_values;
    mapping(uint256 => Node) public nodes;
    mapping(uint256 => Call) public calls;

    constructor(address _usd_token_address, uint256 _minimal_duration) {
        usd_token = IERC20(_usd_token_address);
        minimal_duration = _minimal_duration;
        _nodeSeqCounter.increment();
        _callSeqCounter.increment();
    }
    
    function prepay(uint256 value) public {
        require(usd_token.balanceOf(msg.sender) >= value, "Not enough balance");
        usd_token.transferFrom(msg.sender, address(this), value);

        prepay_values[msg.sender] += value;
    }
    
    function redeemPrepay() public {
        uint256 amount = prepay_values[msg.sender];
        require(amount > 0, "Nothing to redeem");

        usd_token.transfer(msg.sender, amount);

        prepay_values[msg.sender] = 0;
    }

    function addNode(string memory ip, string memory pattern, uint256 price) public {
        uint256 id = _nodeSeqCounter.current();
        nodes[id] = Node(
            ip,
            pattern,
            price,
            msg.sender,
            id
        );
        _nodeSeqCounter.increment();
    }

    function myBalance() public view returns (uint256) {
        return prepay_values[msg.sender];
    }

    function getNodes() public view returns(Node[] memory) {
        Node[] memory _toReturn;
        uint256 lastNodeId = _nodeSeqCounter.current();
        if (lastNodeId > 0) {
            _toReturn = new Node[](lastNodeId);
            for (uint i = 0; i < lastNodeId; i++) {
                _toReturn[i] = nodes[i];
            }
        }
        return _toReturn;
    }

    function createCall(string memory number, uint256 node_id, address _from) public {
        Node memory node = nodes[node_id];
        require(node.id == node_id, "Node not found");
        require(node.owner == msg.sender, "Only node owner allowed");

        uint256 amount = prepay_values[_from];
        uint256 min_amount = node.price * minimal_duration;
        require(amount >= min_amount, "Not enough balance");

        uint256 call_id = _callSeqCounter.current();
        _callSeqCounter.increment();

        calls[call_id] = Call(
            _from,
            number,
            node_id,
            call_id,
            1,
            block.timestamp,
            0,
            node.price,
            0
        );

        emit CreateCall(_from, number, node_id, call_id, node.price);
    }

    function endCall(uint256 call_id, uint256 duration, uint256 state, bytes memory signature) public {
        Call memory call = calls[call_id];
        require(call.state == 1, "Available only for 1 state");

        Node memory node = nodes[call.node_id];
        require(node.owner == msg.sender, "Only node owner allowed");

        address recovered = verify(getEthSignedHash(Strings.toString(call_id)), signature);
        require(recovered == call.from, "Signature mismatch");

        if (duration > 0) {
            uint256 checkAmount = block.timestamp - call.createdAt;
            if (duration > checkAmount) {
                duration = checkAmount;
            }

            uint256 amount = duration * node.price;
            if (prepay_values[call.from] < amount) {
                amount = prepay_values[call.from];
            }
            prepay_values[msg.sender] += amount;
            prepay_values[call.from] -= amount;
        }

        calls[call_id].endAt = block.timestamp;
        if (state > 1) {
            calls[call_id].state = state;
        } else {
            calls[call_id].state = 99;
        }

        emit EndCall(call.from, call.number, call.node_id, call.id, call.price, calls[call_id].state, duration);
    }

    function getEthSignedHash(string memory str) public pure returns (bytes32) {
        return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n", Strings.toString(bytes(str).length), str));
    }
    
    function verify(bytes32 _ethSignedMessageHash, bytes memory _signature) public pure returns (address) {
        (bytes32 r, bytes32 s, uint8 v) = splitSignature(_signature);
        return ecrecover(_ethSignedMessageHash, v, r, s);
    }

    function splitSignature(bytes memory sig)
        public
        pure
        returns (
            bytes32 r,
            bytes32 s,
            uint8 v
        )
    {
        require(sig.length == 65, "invalid signature length");

        assembly {
            /*
            First 32 bytes stores the length of the signature

            add(sig, 32) = pointer of sig + 32
            effectively, skips first 32 bytes of signature

            mload(p) loads next 32 bytes starting at the memory address p into memory
            */

            // first 32 bytes, after the length prefix
            r := mload(add(sig, 32))
            // second 32 bytes
            s := mload(add(sig, 64))
            // final byte (first byte of the next 32 bytes)
            v := byte(0, mload(add(sig, 96)))
        }

        // implicitly return (r, s, v)
    }
}


// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts v4.4.1 (utils/Strings.sol)

pragma solidity ^0.8.0;

/**
 * @dev String operations.
 */
library Strings {
    bytes16 private constant _HEX_SYMBOLS = "0123456789abcdef";

    /**
     * @dev Converts a `uint256` to its ASCII `string` decimal representation.
     */
    function toString(uint256 value) internal pure returns (string memory) {
        // Inspired by OraclizeAPI's implementation - MIT licence
        // https://github.com/oraclize/ethereum-api/blob/b42146b063c7d6ee1358846c198246239e9360e8/oraclizeAPI_0.4.25.sol

        if (value == 0) {
            return "0";
        }
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }

    /**
     * @dev Converts a `uint256` to its ASCII `string` hexadecimal representation.
     */
    function toHexString(uint256 value) internal pure returns (string memory) {
        if (value == 0) {
            return "0x00";
        }
        uint256 temp = value;
        uint256 length = 0;
        while (temp != 0) {
            length++;
            temp >>= 8;
        }
        return toHexString(value, length);
    }

    /**
     * @dev Converts a `uint256` to its ASCII `string` hexadecimal representation with fixed length.
     */
    function toHexString(uint256 value, uint256 length) internal pure returns (string memory) {
        bytes memory buffer = new bytes(2 * length + 2);
        buffer[0] = "0";
        buffer[1] = "x";
        for (uint256 i = 2 * length + 1; i > 1; --i) {
            buffer[i] = _HEX_SYMBOLS[value & 0xf];
            value >>= 4;
        }
        require(value == 0, "Strings: hex length insufficient");
        return string(buffer);
    }
}


// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts v4.4.1 (utils/Counters.sol)

pragma solidity ^0.8.0;

/**
 * @title Counters
 * @author Matt Condon (@shrugs)
 * @dev Provides counters that can only be incremented, decremented or reset. This can be used e.g. to track the number
 * of elements in a mapping, issuing ERC721 ids, or counting request ids.
 *
 * Include with `using Counters for Counters.Counter;`
 */
library Counters {
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
        unchecked {
            counter._value += 1;
        }
    }

    function decrement(Counter storage counter) internal {
        uint256 value = counter._value;
        require(value > 0, "Counter: decrement overflow");
        unchecked {
            counter._value = value - 1;
        }
    }

    function reset(Counter storage counter) internal {
        counter._value = 0;
    }
}


// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts v4.4.1 (token/ERC20/IERC20.sol)

pragma solidity ^0.8.0;

/**
 * @dev Interface of the ERC20 standard as defined in the EIP.
 */
interface IERC20 {
    /**
     * @dev Returns the amount of tokens in existence.
     */
    function totalSupply() external view returns (uint256);

    /**
     * @dev Returns the amount of tokens owned by `account`.
     */
    function balanceOf(address account) external view returns (uint256);

    /**
     * @dev Moves `amount` tokens from the caller's account to `recipient`.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transfer(address recipient, uint256 amount) external returns (bool);

    /**
     * @dev Returns the remaining number of tokens that `spender` will be
     * allowed to spend on behalf of `owner` through {transferFrom}. This is
     * zero by default.
     *
     * This value changes when {approve} or {transferFrom} are called.
     */
    function allowance(address owner, address spender) external view returns (uint256);

    /**
     * @dev Sets `amount` as the allowance of `spender` over the caller's tokens.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * IMPORTANT: Beware that changing an allowance with this method brings the risk
     * that someone may use both the old and the new allowance by unfortunate
     * transaction ordering. One possible solution to mitigate this race
     * condition is to first reduce the spender's allowance to 0 and set the
     * desired value afterwards:
     * https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
     *
     * Emits an {Approval} event.
     */
    function approve(address spender, uint256 amount) external returns (bool);

    /**
     * @dev Moves `amount` tokens from `sender` to `recipient` using the
     * allowance mechanism. `amount` is then deducted from the caller's
     * allowance.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool);

    /**
     * @dev Emitted when `value` tokens are moved from one account (`from`) to
     * another (`to`).
     *
     * Note that `value` may be zero.
     */
    event Transfer(address indexed from, address indexed to, uint256 value);

    /**
     * @dev Emitted when the allowance of a `spender` for an `owner` is set by
     * a call to {approve}. `value` is the new allowance.
     */
    event Approval(address indexed owner, address indexed spender, uint256 value);
}


// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts v4.4.1 (interfaces/IERC20.sol)

pragma solidity ^0.8.0;

import "../token/ERC20/IERC20.sol";