// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./libs/SafeERC20.sol";
import "./libs/IERC20.sol";

contract OnChainEscrow {
  using SafeERC20 for IERC20;

  /***********************
    +       Globals        +
    ***********************/

  address public arbitrator;
  address public owner;
  address public relayer;

  struct Escrow {
    bool exists;
    uint128 relayerGasSpent;
    address tokenContract;
  }

  mapping(bytes32 => Escrow) public escrows;
  mapping(address => uint256) public collectedFees;

  /***********************
    +     Instructions     +
    ***********************/

  uint8 constant private RELEASE_ESCROW = 0x01;
  uint8 constant private BUYER_CANCELS = 0x02;
  uint8 constant private RESOLVE_DISPUTE = 0x03;

  /***********************
    +       Events        +
    ***********************/

  event Created(bytes32 tradeHash);
  event Cancelled(bytes32 tradeHash, uint128 relayerGasSpent);
  event Released(bytes32 tradeHash, uint128 relayerGasSpent);
  event DisputeResolved(bytes32 tradeHash, uint128 relayerGasSpent);

  /***********************
    +     Constructor      +
    ***********************/

  constructor(address initialAddress) {
    owner = initialAddress;
    arbitrator = initialAddress;
    relayer = initialAddress;
  }

  /***********************
    +     Open Escrow     +
    ***********************/

  function createEscrow(
    bytes32 _tradeHash,
    uint256 _value,
    uint8 _v, // Signature value
    bytes32 _r, // Signature value
    bytes32 _s // Signature value
  ) external payable {
    require(!escrows[_tradeHash].exists, "Trade already exists");
    require(_value > 1, "Escrow value too small");
    bytes32 _invitationHash = keccak256(abi.encodePacked(_tradeHash));
    require(
      recoverAddress(_invitationHash, _v, _r, _s) == relayer,
      "Signature not from relayer"
    );

    IERC20(relayer).safeTransferFrom(msg.sender, address(this), _value);

    escrows[_tradeHash] = Escrow(true, 0, relayer);
    emit Created(_tradeHash);
  }

  function relayEscrow(
    bytes32 _tradeHash,
    address _currency,
    uint256 _value,
    uint8 _v, // Signature value for trade invitation by LocalCoinSwap
    bytes32 _r, // Signature value for trade invitation by LocalCoinSwap
    bytes32 _s, // Signature value for trade invitation by LocalCoinSwp
    bytes32 _nonce, // Random nonce used for Gasless send
    uint8 _v_gasless, // Signature value for GasLess send
    bytes32 _r_gasless, // Signature value for GasLess send
    bytes32 _s_gasless // Signature value for GasLess send
  ) external payable {
    require(
      !escrows[_tradeHash].exists,
      "Trade already exists"
    );
    bytes32 _invitationHash = keccak256(abi.encodePacked(_tradeHash));
    require(_value > 1, "Escrow value too small"); // Check escrow value is greater than minimum value
    require(
      recoverAddress(_invitationHash, _v, _r, _s) == relayer,
      "Signature not from relayer"
    );

    // Perform gasless send from seller to contract
    IERC20(_currency).transferWithAuthorization(
      msg.sender,
      address(this),
      _value,
      0,
      2**256 - 1, // MAX INT
      _nonce,
      _v_gasless,
      _r_gasless,
      _s_gasless
    );

    escrows[_tradeHash] = Escrow(true, 0, _currency);
    emit Created(_tradeHash);
  }

  /***********************
    +   Complete Escrow    +
    ***********************/

  function release(
    bytes16 _tradeID,
    address payable _seller,
    address payable _buyer,
    uint256 _value,
    uint16 _fee
  ) external returns (bool) {
    require(msg.sender == _seller, "Must be seller");
    return doRelease(_tradeID, _seller, _buyer, _value, _fee);
  }

  uint16 constant GAS_doRelease = 3658;

  function doRelease(
    bytes16 _tradeID,
    address payable _seller,
    address payable _buyer,
    uint256 _value,
    uint16 _fee
  ) private returns (bool) {
    Escrow memory _escrow;
    bytes32 _tradeHash;
    (_escrow, _tradeHash) = getEscrowAndHash(
      _tradeID,
      _seller,
      _buyer,
      _value,
      _fee
    );
    if (!_escrow.exists) return false;
    uint128 _gasFees = _escrow.relayerGasSpent +
      (msg.sender == relayer ? GAS_doRelease * uint128(tx.gasprice) : 0);
    delete escrows[_tradeHash];
    emit Released(_tradeHash, _gasFees);
    transferMinusFees(_escrow.tokenContract, _buyer, _value, _fee);
    return true;
  }

  uint16 constant GAS_doResolveDispute = 14060;

  function resolveDispute(
    bytes16 _tradeID,
    address payable _seller,
    address payable _buyer,
    uint256 _value,
    uint16 _fee,
    uint8 _v,
    bytes32 _r,
    bytes32 _s,
    uint8 _buyerPercent
  ) external onlyArbitrator {
    address _signature = recoverAddress(
      keccak256(abi.encodePacked(_tradeID, RESOLVE_DISPUTE)),
      _v,
      _r,
      _s
    );
    require(
      _signature == _buyer || _signature == _seller,
      "Must be buyer or seller"
    );

    Escrow memory _escrow;
    bytes32 _tradeHash;
    (_escrow, _tradeHash) = getEscrowAndHash(
      _tradeID,
      _seller,
      _buyer,
      _value,
      _fee
    );
    require(_escrow.exists, "Escrow does not exist");
    require(_buyerPercent <= 100, "_buyerPercent must be 100 or lower");

    _escrow.relayerGasSpent += (GAS_doResolveDispute * uint128(tx.gasprice));

    delete escrows[_tradeHash];
    emit DisputeResolved(_tradeHash, _escrow.relayerGasSpent);
    if (_buyerPercent > 0) {
      // If dispute goes to buyer take the fee
      uint256 _totalFees = ((_value * _fee) / 10000);
      // Prevent underflow
      uint256 buyerAmount = (_value * _buyerPercent) / 100 - _totalFees;
      require(buyerAmount <= _value, "Overflow error");
      collectedFees[_escrow.tokenContract] += _totalFees;

      if (_escrow.tokenContract == 0x0000000000000000000000000000000000000000) {
        _buyer.transfer(buyerAmount);
      } else {
        IERC20(_escrow.tokenContract).safeTransfer(_buyer, buyerAmount);
      }
    }
    if (_buyerPercent < 100) {
      uint256 sellerAmount = (_value * (100 - _buyerPercent)) / 100;
      if (_escrow.tokenContract == 0x0000000000000000000000000000000000000000) {
        _seller.transfer(sellerAmount);
      } else {
        IERC20(_escrow.tokenContract).safeTransfer(_seller, sellerAmount);
      }
    }
  }

  function buyerCancel(
    bytes16 _tradeID,
    address payable _seller,
    address payable _buyer,
    uint256 _value,
    uint16 _fee
  ) external returns (bool) {
    require(msg.sender == _buyer, "Must be buyer");
    return doBuyerCancel(_tradeID, _seller, _buyer, _value, _fee);
  }

  function increaseGasSpent(bytes32 _tradeHash, uint128 _gas) private {
    escrows[_tradeHash].relayerGasSpent += _gas * uint128(tx.gasprice);
  }

  uint16 constant GAS_doBuyerCancel = 2367;

  function doBuyerCancel(
    bytes16 _tradeID,
    address payable _seller,
    address payable _buyer,
    uint256 _value,
    uint16 _fee
  ) private returns (bool) {
    Escrow memory _escrow;
    bytes32 _tradeHash;
    (_escrow, _tradeHash) = getEscrowAndHash(
      _tradeID,
      _seller,
      _buyer,
      _value,
      _fee
    );
    require(_escrow.exists, "Escrow does not exist");
    if (!_escrow.exists) {
      return false;
    }
    uint128 _gasFees = _escrow.relayerGasSpent +
      (msg.sender == relayer ? GAS_doBuyerCancel * uint128(tx.gasprice) : 0);
    delete escrows[_tradeHash];
    emit Cancelled(_tradeHash, _gasFees);
    transferMinusFees(_escrow.tokenContract, _seller, _value, 0);
    return true;
  }

  /***********************
    +        Relays        +
    ***********************/

  uint16 constant GAS_batchRelayBaseCost = 30000;

  function batchRelay(
    bytes16[] memory _tradeID,
    address payable[] memory _seller,
    address payable[] memory _buyer,
    uint256[] memory _value,
    uint16[] memory _fee,
    uint128[] memory _maximumGasPrice,
    uint8[] memory _v,
    bytes32[] memory _r,
    bytes32[] memory _s,
    uint8[] memory _instructionByte
  ) public returns (bool[] memory) {
    bool[] memory _results = new bool[](_tradeID.length);
    for (uint8 i = 0; i < _tradeID.length; i++) {
      _results[i] = relay(
        _tradeID[i],
        _seller[i],
        _buyer[i],
        _value[i],
        _fee[i],
        _maximumGasPrice[i],
        _v[i],
        _r[i],
        _s[i],
        _instructionByte[i]
      );
    }
    return _results;
  }

  function relay(
    bytes16 _tradeID,
    address payable _seller,
    address payable _buyer,
    uint256 _value,
    uint16 _fee,
    uint128 _maximumGasPrice,
    uint8 _v,
    bytes32 _r,
    bytes32 _s,
    uint8 _instructionByte
  ) public returns (bool result) {
    address _relayedSender = getRelayedSender(
      _tradeID,
      _instructionByte,
      _maximumGasPrice,
      _v,
      _r,
      _s
    );
    if (_relayedSender == _buyer) {
      if (_instructionByte == BUYER_CANCELS) {
        return doBuyerCancel(_tradeID, _seller, _buyer, _value, _fee);
      }
    } else if (_relayedSender == _seller) {
      if (_instructionByte == RELEASE_ESCROW) {
        return doRelease(_tradeID, _seller, _buyer, _value, _fee);
      }
    } else {
      require(msg.sender == _seller, "Unrecognised party");
      return false;
    }
  }

  /***********************
    +      Management      +
    ***********************/

  function setArbitrator(address _newArbitrator) external onlyOwner {
    arbitrator = _newArbitrator;
  }

  function setOwner(address _newOwner) external onlyOwner {
    owner = _newOwner;
  }

  function setRelayer(address _newRelayer) external onlyOwner {
    relayer = _newRelayer;
  }

  /***********************
    +   Helper Functions   +
    ***********************/

  function transferMinusFees(
    address _currency,
    address payable _to,
    uint256 _value,
    uint16 _fee
  ) private {
    uint256 _totalFees = ((_value * _fee) / 10000);

    // Add fees to the pot for localcoinswap to withdraw
    collectedFees[_currency] += _totalFees;
    IERC20(_currency).safeTransfer(_to, _value - _totalFees);
  }

  function withdrawFees(
    address payable _to,
    address _currency,
    uint256 _amount
  ) external onlyOwner {
    // This check also prevents underflow
    require(
      _amount <= collectedFees[_currency],
      "Amount is higher than amount available"
    );
    collectedFees[_currency] -= _amount;
    IERC20(_currency).safeTransfer(_to, _amount);
  }

  function getEscrowAndHash(
    bytes16 _tradeID,
    address _seller,
    address _buyer,
    uint256 _value,
    uint16 _fee
  ) private view returns (Escrow storage, bytes32) {
    bytes32 _tradeHash = keccak256(
      abi.encodePacked(_tradeID, _seller, _buyer, _value, _fee)
    );
    return (escrows[_tradeHash], _tradeHash);
  }

  function recoverAddress(
    bytes32 _h,
    uint8 _v,
    bytes32 _r,
    bytes32 _s
  ) private pure returns (address) {
    bytes memory _prefix = "\x19Ethereum Signed Message:\n32";
    bytes32 _prefixedHash = keccak256(abi.encodePacked(_prefix, _h));
    return ecrecover(_prefixedHash, _v, _r, _s);
  }

  function getRelayedSender(
    bytes16 _tradeID,
    uint8 _instructionByte,
    uint128 _maximumGasPrice,
    uint8 _v,
    bytes32 _r,
    bytes32 _s
  ) private view returns (address) {
    bytes32 _hash = keccak256(
      abi.encodePacked(_tradeID, _instructionByte, _maximumGasPrice)
    );
    require(
      tx.gasprice < _maximumGasPrice,
      "Gas price is higher than maximum gas price"
    );
    return recoverAddress(_hash, _v, _r, _s);
  }

  modifier onlyOwner() {
    require(msg.sender == owner, "Only the owner can do this");
    _;
  }

  modifier onlyArbitrator() {
    require(msg.sender == arbitrator, "Only the arbitrator can do this");
    _;
  }
}


// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./IERC20.sol";
import "./Address.sol";

library SafeERC20 {
  using Address for address;

  function safeTransfer(
    IERC20 token,
    address to,
    uint256 value
  ) internal {
    _callOptionalReturn(
      token,
      abi.encodeWithSelector(token.transfer.selector, to, value)
    );
  }

  function safeTransferFrom(
    IERC20 token,
    address from,
    address to,
    uint256 value
  ) internal {
    _callOptionalReturn(
      token,
      abi.encodeWithSelector(token.transferFrom.selector, from, to, value)
    );
  }

  function safeApprove(
    IERC20 token,
    address spender,
    uint256 value
  ) internal {
    // solhint-disable-next-line max-line-length
    require(
      (value == 0) || (token.allowance(address(this), spender) == 0),
      "SafeERC20: approve from non-zero to non-zero allowance"
    );
    _callOptionalReturn(
      token,
      abi.encodeWithSelector(token.approve.selector, spender, value)
    );
  }

  function safeIncreaseAllowance(
    IERC20 token,
    address spender,
    uint256 value
  ) internal {
    uint256 newAllowance = token.allowance(address(this), spender) + value;
    _callOptionalReturn(
      token,
      abi.encodeWithSelector(token.approve.selector, spender, newAllowance)
    );
  }

  function safeDecreaseAllowance(
    IERC20 token,
    address spender,
    uint256 value
  ) internal {
    uint256 newAllowance = token.allowance(address(this), spender) - value;
    _callOptionalReturn(
      token,
      abi.encodeWithSelector(token.approve.selector, spender, newAllowance)
    );
  }

  function _callOptionalReturn(IERC20 token, bytes memory data) private {
    bytes memory returndata = address(token).functionCall(
      data,
      "SafeERC20: low-level call failed"
    );
    if (returndata.length > 0) {
      // solhint-disable-next-line max-line-length
      require(
        abi.decode(returndata, (bool)),
        "SafeERC20: ERC20 operation did not succeed"
      );
    }
  }
}


// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IERC20 {
  function totalSupply() external view returns (uint256);

  function balanceOf(address account) external view returns (uint256);

  function transfer(address recipient, uint256 amount) external returns (bool);

  function allowance(address owner, address spender)
    external
    view
    returns (uint256);

  function approve(address spender, uint256 amount) external returns (bool);

  function transferFrom(
    address sender,
    address recipient,
    uint256 amount
  ) external returns (bool);

  event Transfer(address indexed from, address indexed to, uint256 value);
  event Approval(address indexed owner, address indexed spender, uint256 value);

  // USDC gasless send
  function transferWithAuthorization(
    address from,
    address to,
    uint256 value,
    uint256 validAfter,
    uint256 validBefore,
    bytes32 nonce,
    uint8 v,
    bytes32 r,
    bytes32 s
  ) external;
}


// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

library Address {
  function isContract(address account) internal view returns (bool) {
    // According to EIP-1052, 0x0 is the value returned for not-yet created accounts
    // and 0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470 is returned
    // for accounts without code, i.e. `keccak256('')`
    bytes32 codehash;
    bytes32 accountHash = 0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470;
    // solhint-disable-next-line no-inline-assembly
    assembly {
      codehash := extcodehash(account)
    }
    return (codehash != accountHash && codehash != 0x0);
  }

  function sendValue(address payable recipient, uint256 amount) internal {
    require(address(this).balance >= amount, "Address: insufficient balance");

    // solhint-disable-next-line avoid-low-level-calls, avoid-call-value
    (bool success, ) = recipient.call{ value: amount }("");
    require(
      success,
      "Address: unable to send value, recipient may have reverted"
    );
  }

  function functionCall(address target, bytes memory data)
    internal
    returns (bytes memory)
  {
    return functionCall(target, data, "Address: low-level call failed");
  }

  function functionCall(
    address target,
    bytes memory data,
    string memory errorMessage
  ) internal returns (bytes memory) {
    return _functionCallWithValue(target, data, 0, errorMessage);
  }

  function functionCallWithValue(
    address target,
    bytes memory data,
    uint256 value
  ) internal returns (bytes memory) {
    return
      functionCallWithValue(
        target,
        data,
        value,
        "Address: low-level call with value failed"
      );
  }

  function functionCallWithValue(
    address target,
    bytes memory data,
    uint256 value,
    string memory errorMessage
  ) internal returns (bytes memory) {
    require(
      address(this).balance >= value,
      "Address: insufficient balance for call"
    );
    return _functionCallWithValue(target, data, value, errorMessage);
  }

  function _functionCallWithValue(
    address target,
    bytes memory data,
    uint256 weiValue,
    string memory errorMessage
  ) private returns (bytes memory) {
    require(isContract(target), "Address: call to non-contract");

    // solhint-disable-next-line avoid-low-level-calls
    (bool success, bytes memory returndata) = target.call{ value: weiValue }(
      data
    );
    if (success) {
      return returndata;
    } else {
      // Look for revert reason and bubble it up if present
      if (returndata.length > 0) {
        // The easiest way to bubble the revert reason is using memory via assembly

        // solhint-disable-next-line no-inline-assembly
        assembly {
          let returndata_size := mload(returndata)
          revert(add(32, returndata), returndata_size)
        }
      } else {
        revert(errorMessage);
      }
    }
  }
}