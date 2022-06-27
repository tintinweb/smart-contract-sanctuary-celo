pragma solidity ^0.5.17;
pragma experimental ABIEncoderV2;

contract CloneFactory {

  function createClone(address target) internal returns (address result) {
    bytes20 targetBytes = bytes20(target);
    assembly {
      let clone := mload(0x40)
      mstore(clone, 0x3d602d80600a3d3981f3363d3d373d3d3d363d73000000000000000000000000)
      mstore(add(clone, 0x14), targetBytes)
      mstore(add(clone, 0x28), 0x5af43d82803e903d91602b57fd5bf30000000000000000000000000000000000)
      result := create(0, clone, 0x37)
    }
  }
}

/**
 * @dev Interface of the ERC20 standard as defined in the EIP. Does not include
 * the optional functions; to access them see {ERC20Detailed}.
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
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);

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


/**
 * @title SafeERC20
 * @dev Wrappers around ERC20 operations that throw on failure (when the token
 * contract returns false). Tokens that return no value (and instead revert or
 * throw on failure) are also supported, non-reverting calls are assumed to be
 * successful.
 * To use this library you can add a `using SafeERC20 for ERC20;` statement to your contract,
 * which allows you to call the safe operations as `token.safeTransfer(...)`, etc.
 */
library SafeERC20 {
    using SafeMath for uint256;
    using Address for address;

    function safeTransfer(IERC20 token, address to, uint256 value) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(token.transfer.selector, to, value));
    }

    function safeTransferFrom(IERC20 token, address from, address to, uint256 value) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(token.transferFrom.selector, from, to, value));
    }

    /**
     * @dev Deprecated. This function has issues similar to the ones found in
     * {IERC20-approve}, and its usage is discouraged.
     *
     * Whenever possible, use {safeIncreaseAllowance} and
     * {safeDecreaseAllowance} instead.
     */
    function safeApprove(IERC20 token, address spender, uint256 value) internal {
        // safeApprove should only be called when setting an initial allowance,
        // or when resetting it to zero. To increase and decrease it, use
        // 'safeIncreaseAllowance' and 'safeDecreaseAllowance'
        // solhint-disable-next-line max-line-length
        require((value == 0) || (token.allowance(address(this), spender) == 0),
            "SafeERC20: approve from non-zero to non-zero allowance"
        );
        _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, value));
    }

    function safeIncreaseAllowance(IERC20 token, address spender, uint256 value) internal {
        uint256 newAllowance = token.allowance(address(this), spender).add(value);
        _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, newAllowance));
    }

    function safeDecreaseAllowance(IERC20 token, address spender, uint256 value) internal {
        uint256 newAllowance = token.allowance(address(this), spender).sub(value);
        _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, newAllowance));
    }

    /**
     * @dev Imitates a Solidity high-level call (i.e. a regular function call to a contract), relaxing the requirement
     * on the return value: the return value is optional (but if data is returned, it must not be false).
     * @param token The token targeted by the call.
     * @param data The call data (encoded using abi.encode or one of its variants).
     */
    function _callOptionalReturn(IERC20 token, bytes memory data) private {
        // We need to perform a low level call here, to bypass Solidity's return data size checking mechanism, since
        // we're implementing it ourselves. We use {Address.functionCall} to perform this call, which verifies that
        // the target address contains contract code and also asserts for success in the low-level call.

        bytes memory returndata = address(token).functionCall(data, "SafeERC20: low-level call failed");
        if (returndata.length > 0) { // Return data is optional
            // solhint-disable-next-line max-line-length
            require(abi.decode(returndata, (bool)), "SafeERC20: ERC20 operation did not succeed");
        }
    }
}


/*
 * @dev Provides information about the current execution context, including the
 * sender of the transaction and its data. While these are generally available
 * via msg.sender and msg.data, they should not be accessed in such a direct
 * manner, since when dealing with GSN meta-transactions the account sending and
 * paying for execution may not be the actual sender (as far as an application
 * is concerned).
 *
 * This contract is only required for intermediate, library-like contracts.
 */
contract Context {
    // Empty internal constructor, to prevent people from mistakenly deploying
    // an instance of this contract, which should be used via inheritance.
    constructor () internal { }
    // solhint-disable-previous-line no-empty-blocks

    function _msgSender() internal view returns (address payable) {
        return msg.sender;
    }

    function _msgData() internal view returns (bytes memory) {
        this; // silence state mutability warning without generating bytecode - see https://github.com/ethereum/solidity/issues/2691
        return msg.data;
    }
}

/**
 * @dev Contract module which provides a basic access control mechanism, where
 * there is an account (an owner) that can be granted exclusive access to
 * specific functions.
 *
 * This module is used through inheritance. It will make available the modifier
 * `onlyOwner`, which can be applied to your functions to restrict their use to
 * the owner.
 */
contract Ownable is Context {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /**
     * @dev Initializes the contract setting the deployer as the initial owner.
     */
    constructor () internal {
        address msgSender = _msgSender();
        _owner = msgSender;
        emit OwnershipTransferred(address(0), msgSender);
    }
    
    function initOwnable() internal{
        address msgSender = _msgSender();
        _owner = msgSender;
        emit OwnershipTransferred(address(0), msgSender);
    }

    /**
     * @dev Returns the address of the current owner.
     */
    function owner() public view returns (address) {
        return _owner;
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        require(isOwner(), "Ownable: caller is not the owner");
        _;
    }

    /**
     * @dev Returns true if the caller is the current owner.
     */
    function isOwner() public view returns (bool) {
        return _msgSender() == _owner;
    }

    /**
     * @dev Leaves the contract without owner. It will not be possible to call
     * `onlyOwner` functions anymore. Can only be called by the current owner.
     *
     * NOTE: Renouncing ownership will leave the contract without an owner,
     * thereby removing any functionality that is only available to the owner.
     */
    function renounceOwnership() public onlyOwner {
        emit OwnershipTransferred(_owner, address(0));
        _owner = address(0);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) public onlyOwner {
        _transferOwnership(newOwner);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     */
    function _transferOwnership(address newOwner) internal {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}

/**
 * @title Roles
 * @dev Library for managing addresses assigned to a Role.
 */
library Roles {
    struct Role {
        mapping (address => bool) bearer;
    }

    /**
     * @dev Give an account access to this role.
     */
    function add(Role storage role, address account) internal {
        require(!has(role, account), "Roles: account already has role");
        role.bearer[account] = true;
    }

    /**
     * @dev Remove an account's access to this role.
     */
    function remove(Role storage role, address account) internal {
        require(has(role, account), "Roles: account does not have role");
        role.bearer[account] = false;
    }

    /**
     * @dev Check if an account has this role.
     * @return bool
     */
    function has(Role storage role, address account) internal view returns (bool) {
        require(account != address(0), "Roles: account is the zero address");
        return role.bearer[account];
    }
}

contract MinterRole is Context {
    using Roles for Roles.Role;

    event MinterAdded(address indexed account);
    event MinterRemoved(address indexed account);

    Roles.Role private _minters;

    function initMinter() internal{
        _addMinter(_msgSender());
    }

    constructor () internal {
        _addMinter(_msgSender());
    }

    modifier onlyMinter() {
        require(isMinter(_msgSender()), "MinterRole: caller does not have the Minter role");
        _;
    }

    function isMinter(address account) public view returns (bool) {
        return _minters.has(account);
    }

    function addMinter(address account) public onlyMinter {
        _addMinter(account);
    }

    function renounceMinter() public {
        _removeMinter(_msgSender());
    }

    function _addMinter(address account) internal {
        _minters.add(account);
        emit MinterAdded(account);
    }

    function _removeMinter(address account) internal {
        _minters.remove(account);
        emit MinterRemoved(account);
    }
}

/**
 * @title WhitelistAdminRole
 * @dev WhitelistAdmins are responsible for assigning and removing Whitelisted accounts.
 */
contract WhitelistAdminRole is Context {
    using Roles for Roles.Role;

    event WhitelistAdminAdded(address indexed account);
    event WhitelistAdminRemoved(address indexed account);

    Roles.Role private _whitelistAdmins;

    function initWhiteListAdmin() internal{
        _addWhitelistAdmin(_msgSender());
    }

    constructor () internal {
        _addWhitelistAdmin(_msgSender());
    }

    modifier onlyWhitelistAdmin() {
        require(isWhitelistAdmin(_msgSender()), "WhitelistAdminRole: caller does not have the WhitelistAdmin role");
        _;
    }

    function isWhitelistAdmin(address account) public view returns (bool) {
        return _whitelistAdmins.has(account);
    }

    function addWhitelistAdmin(address account) public onlyWhitelistAdmin {
        _addWhitelistAdmin(account);
    }

    function renounceWhitelistAdmin() public {
        _removeWhitelistAdmin(_msgSender());
    }

    function _addWhitelistAdmin(address account) internal {
        _whitelistAdmins.add(account);
        emit WhitelistAdminAdded(account);
    }

    function _removeWhitelistAdmin(address account) internal {
        _whitelistAdmins.remove(account);
        emit WhitelistAdminRemoved(account);
    }
}

/**
 * @title ERC165
 * @dev https://github.com/ethereum/EIPs/blob/master/EIPS/eip-165.md
 */
interface IERC165 {

    /**
     * @notice Query if a contract implements an interface
     * @dev Interface identification is specified in ERC-165. This function
     * uses less than 30,000 gas
     * @param _interfaceId The interface identifier, as specified in ERC-165
     */
    function supportsInterface(bytes4 _interfaceId)
    external
    view
    returns (bool);
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
    require(c / a == b, "SafeMath#mul: OVERFLOW");

    return c;
  }

  /**
   * @dev Integer division of two unsigned integers truncating the quotient, reverts on division by zero.
   */
  function div(uint256 a, uint256 b) internal pure returns (uint256) {
    // Solidity only automatically asserts when dividing by 0
    require(b > 0, "SafeMath#div: DIVISION_BY_ZERO");
    uint256 c = a / b;
    // assert(a == b * c + a % b); // There is no case in which this doesn't hold

    return c;
  }

  /**
   * @dev Subtracts two unsigned integers, reverts on overflow (i.e. if subtrahend is greater than minuend).
   */
  function sub(uint256 a, uint256 b) internal pure returns (uint256) {
    require(b <= a, "SafeMath#sub: UNDERFLOW");
    uint256 c = a - b;

    return c;
  }

  /**
   * @dev Adds two unsigned integers, reverts on overflow.
   */
  function add(uint256 a, uint256 b) internal pure returns (uint256) {
    uint256 c = a + b;
    require(c >= a, "SafeMath#add: OVERFLOW");

    return c; 
  }

  /**
   * @dev Divides two unsigned integers and returns the remainder (unsigned integer modulo),
   * reverts when dividing by zero.
   */
  function mod(uint256 a, uint256 b) internal pure returns (uint256) {
    require(b != 0, "SafeMath#mod: DIVISION_BY_ZERO");
    return a % b;
  }

}

/**
 * @dev ERC-1155 interface for accepting safe transfers.
 */
interface IERC1155TokenReceiver {

  /**
   * @notice Handle the receipt of a single ERC1155 token type
   * @dev An ERC1155-compliant smart contract MUST call this function on the token recipient contract, at the end of a `safeTransferFrom` after the balance has been updated
   * This function MAY throw to revert and reject the transfer
   * Return of other amount than the magic value MUST result in the transaction being reverted
   * Note: The token contract address is always the message sender
   * @param _operator  The address which called the `safeTransferFrom` function
   * @param _from      The address which previously owned the token
   * @param _id        The id of the token being transferred
   * @param _amount    The amount of tokens being transferred
   * @param _data      Additional data with no specified format
   * @return           `bytes4(keccak256("onERC1155Received(address,address,uint256,uint256,bytes)"))`
   */
  function onERC1155Received(address _operator, address _from, uint256 _id, uint256 _amount, bytes calldata _data) external returns(bytes4);

  /**
   * @notice Handle the receipt of multiple ERC1155 token types
   * @dev An ERC1155-compliant smart contract MUST call this function on the token recipient contract, at the end of a `safeBatchTransferFrom` after the balances have been updated
   * This function MAY throw to revert and reject the transfer
   * Return of other amount than the magic value WILL result in the transaction being reverted
   * Note: The token contract address is always the message sender
   * @param _operator  The address which called the `safeBatchTransferFrom` function
   * @param _from      The address which previously owned the token
   * @param _ids       An array containing ids of each token being transferred
   * @param _amounts   An array containing amounts of each token being transferred
   * @param _data      Additional data with no specified format
   * @return           `bytes4(keccak256("onERC1155BatchReceived(address,address,uint256[],uint256[],bytes)"))`
   */
  function onERC1155BatchReceived(address _operator, address _from, uint256[] calldata _ids, uint256[] calldata _amounts, bytes calldata _data) external returns(bytes4);

  /**
   * @notice Indicates whether a contract implements the `ERC1155TokenReceiver` functions and so can accept ERC1155 token types.
   * @param  interfaceID The ERC-165 interface ID that is queried for support.s
   * @dev This function MUST return true if it implements the ERC1155TokenReceiver interface and ERC-165 interface.
   *      This function MUST NOT consume more than 5,000 gas.
   * @return Wheter ERC-165 or ERC1155TokenReceiver interfaces are supported.
   */
  function supportsInterface(bytes4 interfaceID) external view returns (bool);

}

interface IERC1155 {
  // Events

  /**
   * @dev Either TransferSingle or TransferBatch MUST emit when tokens are transferred, including zero amount transfers as well as minting or burning
   *   Operator MUST be msg.sender
   *   When minting/creating tokens, the `_from` field MUST be set to `0x0`
   *   When burning/destroying tokens, the `_to` field MUST be set to `0x0`
   *   The total amount transferred from address 0x0 minus the total amount transferred to 0x0 may be used by clients and exchanges to be added to the "circulating supply" for a given token ID
   *   To broadcast the existence of a token ID with no initial balance, the contract SHOULD emit the TransferSingle event from `0x0` to `0x0`, with the token creator as `_operator`, and a `_amount` of 0
   */
  event TransferSingle(address indexed _operator, address indexed _from, address indexed _to, uint256 _id, uint256 _amount);

  /**
   * @dev Either TransferSingle or TransferBatch MUST emit when tokens are transferred, including zero amount transfers as well as minting or burning
   *   Operator MUST be msg.sender
   *   When minting/creating tokens, the `_from` field MUST be set to `0x0`
   *   When burning/destroying tokens, the `_to` field MUST be set to `0x0`
   *   The total amount transferred from address 0x0 minus the total amount transferred to 0x0 may be used by clients and exchanges to be added to the "circulating supply" for a given token ID
   *   To broadcast the existence of multiple token IDs with no initial balance, this SHOULD emit the TransferBatch event from `0x0` to `0x0`, with the token creator as `_operator`, and a `_amount` of 0
   */
  event TransferBatch(address indexed _operator, address indexed _from, address indexed _to, uint256[] _ids, uint256[] _amounts);

  /**
   * @dev MUST emit when an approval is updated
   */
  event ApprovalForAll(address indexed _owner, address indexed _operator, bool _approved);

  /**
   * @dev MUST emit when the URI is updated for a token ID
   *   URIs are defined in RFC 3986
   *   The URI MUST point a JSON file that conforms to the "ERC-1155 Metadata JSON Schema"
   */
  event URI(string _amount, uint256 indexed _id);

  /**
   * @notice Transfers amount of an _id from the _from address to the _to address specified
   * @dev MUST emit TransferSingle event on success
   * Caller must be approved to manage the _from account's tokens (see isApprovedForAll)
   * MUST throw if `_to` is the zero address
   * MUST throw if balance of sender for token `_id` is lower than the `_amount` sent
   * MUST throw on any other error
   * When transfer is complete, this function MUST check if `_to` is a smart contract (code size > 0). If so, it MUST call `onERC1155Received` on `_to` and revert if the return amount is not `bytes4(keccak256("onERC1155Received(address,address,uint256,uint256,bytes)"))`
   * @param _from    Source address
   * @param _to      Target address
   * @param _id      ID of the token type
   * @param _amount  Transfered amount
   * @param _data    Additional data with no specified format, sent in call to `_to`
   */
  function safeTransferFrom(address _from, address _to, uint256 _id, uint256 _amount, bytes calldata _data) external;

  /**
   * @notice Send multiple types of Tokens from the _from address to the _to address (with safety call)
   * @dev MUST emit TransferBatch event on success
   * Caller must be approved to manage the _from account's tokens (see isApprovedForAll)
   * MUST throw if `_to` is the zero address
   * MUST throw if length of `_ids` is not the same as length of `_amounts`
   * MUST throw if any of the balance of sender for token `_ids` is lower than the respective `_amounts` sent
   * MUST throw on any other error
   * When transfer is complete, this function MUST check if `_to` is a smart contract (code size > 0). If so, it MUST call `onERC1155BatchReceived` on `_to` and revert if the return amount is not `bytes4(keccak256("onERC1155BatchReceived(address,address,uint256[],uint256[],bytes)"))`
   * Transfers and events MUST occur in the array order they were submitted (_ids[0] before _ids[1], etc)
   * @param _from     Source addresses
   * @param _to       Target addresses
   * @param _ids      IDs of each token type
   * @param _amounts  Transfer amounts per token type
   * @param _data     Additional data with no specified format, sent in call to `_to`
  */
  function safeBatchTransferFrom(address _from, address _to, uint256[] calldata _ids, uint256[] calldata _amounts, bytes calldata _data) external;
  
  /**
   * @notice Get the balance of an account's Tokens
   * @param _owner  The address of the token holder
   * @param _id     ID of the Token
   * @return        The _owner's balance of the Token type requested
   */
  function balanceOf(address _owner, uint256 _id) external view returns (uint256);

  /**
   * @notice Get the balance of multiple account/token pairs
   * @param _owners The addresses of the token holders
   * @param _ids    ID of the Tokens
   * @return        The _owner's balance of the Token types requested (i.e. balance for each (owner, id) pair)
   */
  function balanceOfBatch(address[] calldata _owners, uint256[] calldata _ids) external view returns (uint256[] memory);

  /**
   * @notice Enable or disable approval for a third party ("operator") to manage all of caller's tokens
   * @dev MUST emit the ApprovalForAll event on success
   * @param _operator  Address to add to the set of authorized operators
   * @param _approved  True if the operator is approved, false to revoke approval
   */
  function setApprovalForAll(address _operator, bool _approved) external;

  /**
   * @notice Queries the approval status of an operator for a given owner
   * @param _owner     The owner of the Tokens
   * @param _operator  Address of authorized operator
   * @return           True if the operator is approved, false if not
   */
  function isApprovedForAll(address _owner, address _operator) external view returns (bool isOperator);

}

library Address {
    /**
     * @dev Returns true if `account` is a contract.
     *
     * [IMPORTANT]
     * ====
     * It is unsafe to assume that an address for which this function returns
     * false is an externally-owned account (EOA) and not a contract.
     *
     * Among others, `isContract` will return false for the following
     * types of addresses:
     *
     *  - an externally-owned account
     *  - a contract in construction
     *  - an address where a contract will be created
     *  - an address where a contract lived, but was destroyed
     * ====
     */
    function isContract(address account) internal view returns (bool) {
        // This method relies on extcodesize, which returns 0 for contracts in
        // construction, since the code is only stored at the end of the
        // constructor execution.

        uint256 size;
        // solhint-disable-next-line no-inline-assembly
        assembly { size := extcodesize(account) }
        return size > 0;
    }

    /**
     * @dev Replacement for Solidity's `transfer`: sends `amount` wei to
     * `recipient`, forwarding all available gas and reverting on errors.
     *
     * https://eips.ethereum.org/EIPS/eip-1884[EIP1884] increases the gas cost
     * of certain opcodes, possibly making contracts go over the 2300 gas limit
     * imposed by `transfer`, making them unable to receive funds via
     * `transfer`. {sendValue} removes this limitation.
     *
     * https://diligence.consensys.net/posts/2019/09/stop-using-soliditys-transfer-now/[Learn more].
     *
     * IMPORTANT: because control is transferred to `recipient`, care must be
     * taken to not create reentrancy vulnerabilities. Consider using
     * {ReentrancyGuard} or the
     * https://solidity.readthedocs.io/en/v0.5.11/security-considerations.html#use-the-checks-effects-interactions-pattern[checks-effects-interactions pattern].
     */
    function sendValue(address payable recipient, uint256 amount) internal {
        require(address(this).balance >= amount, "Address: insufficient balance");

        // solhint-disable-next-line avoid-low-level-calls, avoid-call-value
        (bool success, ) = recipient.call.value(amount)("");
        require(success, "Address: unable to send value, recipient may have reverted");
    }

    /**
     * @dev Performs a Solidity function call using a low level `call`. A
     * plain`call` is an unsafe replacement for a function call: use this
     * function instead.
     *
     * If `target` reverts with a revert reason, it is bubbled up by this
     * function (like regular Solidity function calls).
     *
     * Returns the raw returned data. To convert to the expected return value,
     * use https://solidity.readthedocs.io/en/latest/units-and-global-variables.html?highlight=abi.decode#abi-encoding-and-decoding-functions[`abi.decode`].
     *
     * Requirements:
     *
     * - `target` must be a contract.
     * - calling `target` with `data` must not revert.
     *
     * _Available since v3.1._
     */
    function functionCall(address target, bytes memory data) internal returns (bytes memory) {
      return functionCall(target, data, "Address: low-level call failed");
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`], but with
     * `errorMessage` as a fallback revert reason when `target` reverts.
     *
     * _Available since v3.1._
     */
    function functionCall(address target, bytes memory data, string memory errorMessage) internal returns (bytes memory) {
        return functionCallWithValue(target, data, 0, errorMessage);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but also transferring `value` wei to `target`.
     *
     * Requirements:
     *
     * - the calling contract must have an ETH balance of at least `value`.
     * - the called Solidity function must be `payable`.
     *
     * _Available since v3.1._
     */
    function functionCallWithValue(address target, bytes memory data, uint256 value) internal returns (bytes memory) {
        return functionCallWithValue(target, data, value, "Address: low-level call with value failed");
    }

    /**
     * @dev Same as {xref-Address-functionCallWithValue-address-bytes-uint256-}[`functionCallWithValue`], but
     * with `errorMessage` as a fallback revert reason when `target` reverts.
     *
     * _Available since v3.1._
     */
    function functionCallWithValue(address target, bytes memory data, uint256 value, string memory errorMessage) internal returns (bytes memory) {
        require(address(this).balance >= value, "Address: insufficient balance for call");
        require(isContract(target), "Address: call to non-contract");

        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory returndata) = target.call.value(value)(data);
        return _verifyCallResult(success, returndata, errorMessage);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but performing a static call.
     *
     * _Available since v3.3._
     */
    function functionStaticCall(address target, bytes memory data) internal view returns (bytes memory) {
        return functionStaticCall(target, data, "Address: low-level static call failed");
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-string-}[`functionCall`],
     * but performing a static call.
     *
     * _Available since v3.3._
     */
    function functionStaticCall(address target, bytes memory data, string memory errorMessage) internal view returns (bytes memory) {
        require(isContract(target), "Address: static call to non-contract");

        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory returndata) = target.staticcall(data);
        return _verifyCallResult(success, returndata, errorMessage);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but performing a delegate call.
     *
     * _Available since v3.3._
     */
    function functionDelegateCall(address target, bytes memory data) internal returns (bytes memory) {
        return functionDelegateCall(target, data, "Address: low-level delegate call failed");
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-string-}[`functionCall`],
     * but performing a delegate call.
     *
     * _Available since v3.3._
     */
    function functionDelegateCall(address target, bytes memory data, string memory errorMessage) internal returns (bytes memory) {
        require(isContract(target), "Address: delegate call to non-contract");

        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory returndata) = target.delegatecall(data);
        return _verifyCallResult(success, returndata, errorMessage);
    }

    function _verifyCallResult(bool success, bytes memory returndata, string memory errorMessage) private pure returns(bytes memory) {
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

/**
 * @dev Implementation of Multi-Token Standard contract
 */
contract ERC1155 is IERC165 {
  using SafeMath for uint256;
  using Address for address;


  /***********************************|
  |        Variables and Events       |
  |__________________________________*/

  // onReceive function signatures
  bytes4 constant internal ERC1155_RECEIVED_VALUE = 0xf23a6e61;
  bytes4 constant internal ERC1155_BATCH_RECEIVED_VALUE = 0xbc197c81;

  // Objects balances
  mapping (address => mapping(uint256 => uint256)) internal balances;

  // Operator Functions
  mapping (address => mapping(address => bool)) internal operators;

  // Events
  event TransferSingle(address indexed _operator, address indexed _from, address indexed _to, uint256 _id, uint256 _amount);
  event TransferBatch(address indexed _operator, address indexed _from, address indexed _to, uint256[] _ids, uint256[] _amounts);
  event ApprovalForAll(address indexed _owner, address indexed _operator, bool _approved);
  event URI(string _uri, uint256 indexed _id);


  /***********************************|
  |     Public Transfer Functions     |
  |__________________________________*/

  /**
   * @notice Transfers amount amount of an _id from the _from address to the _to address specified
   * @param _from    Source address
   * @param _to      Target address
   * @param _id      ID of the token type
   * @param _amount  Transfered amount
   * @param _data    Additional data with no specified format, sent in call to `_to`
   */
  function safeTransferFrom(address _from, address _to, uint256 _id, uint256 _amount, bytes memory _data)
    public
  {
    require((msg.sender == _from) || isApprovedForAll(_from, msg.sender), "ERC1155#safeTransferFrom: INVALID_OPERATOR");
    require(_to != address(0),"ERC1155#safeTransferFrom: INVALID_RECIPIENT");
    // require(_amount >= balances[_from][_id]) is not necessary since checked with safemath operations

    _safeTransferFrom(_from, _to, _id, _amount);
    _callonERC1155Received(_from, _to, _id, _amount, _data);
  }

  /**
   * @notice Send multiple types of Tokens from the _from address to the _to address (with safety call)
   * @param _from     Source addresses
   * @param _to       Target addresses
   * @param _ids      IDs of each token type
   * @param _amounts  Transfer amounts per token type
   * @param _data     Additional data with no specified format, sent in call to `_to`
   */
  function safeBatchTransferFrom(address _from, address _to, uint256[] memory _ids, uint256[] memory _amounts, bytes memory _data)
    public
  {
    // Requirements
    require((msg.sender == _from) || isApprovedForAll(_from, msg.sender), "ERC1155#safeBatchTransferFrom: INVALID_OPERATOR");
    require(_to != address(0), "ERC1155#safeBatchTransferFrom: INVALID_RECIPIENT");

    _safeBatchTransferFrom(_from, _to, _ids, _amounts);
    _callonERC1155BatchReceived(_from, _to, _ids, _amounts, _data);
  }


  /***********************************|
  |    Internal Transfer Functions    |
  |__________________________________*/

  /**
   * @notice Transfers amount amount of an _id from the _from address to the _to address specified
   * @param _from    Source address
   * @param _to      Target address
   * @param _id      ID of the token type
   * @param _amount  Transfered amount
   */
  function _safeTransferFrom(address _from, address _to, uint256 _id, uint256 _amount)
    internal
  {
    // Update balances
    balances[_from][_id] = balances[_from][_id].sub(_amount); // Subtract amount
    balances[_to][_id] = balances[_to][_id].add(_amount);     // Add amount

    // Emit event
    emit TransferSingle(msg.sender, _from, _to, _id, _amount);
  }

  /**
   * @notice Verifies if receiver is contract and if so, calls (_to).onERC1155Received(...)
   */
  function _callonERC1155Received(address _from, address _to, uint256 _id, uint256 _amount, bytes memory _data)
    internal
  {
    // Check if recipient is contract
    if (_to.isContract()) {
      bytes4 retval = IERC1155TokenReceiver(_to).onERC1155Received(msg.sender, _from, _id, _amount, _data);
      require(retval == ERC1155_RECEIVED_VALUE, "ERC1155#_callonERC1155Received: INVALID_ON_RECEIVE_MESSAGE");
    }
  }

  /**
   * @notice Send multiple types of Tokens from the _from address to the _to address (with safety call)
   * @param _from     Source addresses
   * @param _to       Target addresses
   * @param _ids      IDs of each token type
   * @param _amounts  Transfer amounts per token type
   */
  function _safeBatchTransferFrom(address _from, address _to, uint256[] memory _ids, uint256[] memory _amounts)
    internal
  {
    require(_ids.length == _amounts.length, "ERC1155#_safeBatchTransferFrom: INVALID_ARRAYS_LENGTH");

    // Number of transfer to execute
    uint256 nTransfer = _ids.length;

    // Executing all transfers
    for (uint256 i = 0; i < nTransfer; i++) {
      // Update storage balance of previous bin
      balances[_from][_ids[i]] = balances[_from][_ids[i]].sub(_amounts[i]);
      balances[_to][_ids[i]] = balances[_to][_ids[i]].add(_amounts[i]);
    }

    // Emit event
    emit TransferBatch(msg.sender, _from, _to, _ids, _amounts);
  }

  /**
   * @notice Verifies if receiver is contract and if so, calls (_to).onERC1155BatchReceived(...)
   */
  function _callonERC1155BatchReceived(address _from, address _to, uint256[] memory _ids, uint256[] memory _amounts, bytes memory _data)
    internal
  {
    // Pass data if recipient is contract
    if (_to.isContract()) {
      bytes4 retval = IERC1155TokenReceiver(_to).onERC1155BatchReceived(msg.sender, _from, _ids, _amounts, _data);
      require(retval == ERC1155_BATCH_RECEIVED_VALUE, "ERC1155#_callonERC1155BatchReceived: INVALID_ON_RECEIVE_MESSAGE");
    }
  }


  /***********************************|
  |         Operator Functions        |
  |__________________________________*/

  /**
   * @notice Enable or disable approval for a third party ("operator") to manage all of caller's tokens
   * @param _operator  Address to add to the set of authorized operators
   * @param _approved  True if the operator is approved, false to revoke approval
   */
  function setApprovalForAll(address _operator, bool _approved)
    external
  {
    // Update operator status
    operators[msg.sender][_operator] = _approved;
    emit ApprovalForAll(msg.sender, _operator, _approved);
  }

  /**
   * @notice Queries the approval status of an operator for a given owner
   * @param _owner     The owner of the Tokens
   * @param _operator  Address of authorized operator
   * @return True if the operator is approved, false if not
   */
  function isApprovedForAll(address _owner, address _operator)
    public view returns (bool isOperator)
  {
    return operators[_owner][_operator];
  }


  /***********************************|
  |         Balance Functions         |
  |__________________________________*/

  /**
   * @notice Get the balance of an account's Tokens
   * @param _owner  The address of the token holder
   * @param _id     ID of the Token
   * @return The _owner's balance of the Token type requested
   */
  function balanceOf(address _owner, uint256 _id)
    public view returns (uint256)
  {
    return balances[_owner][_id];
  }

  /**
   * @notice Get the balance of multiple account/token pairs
   * @param _owners The addresses of the token holders
   * @param _ids    ID of the Tokens
   * @return        The _owner's balance of the Token types requested (i.e. balance for each (owner, id) pair)
   */
  function balanceOfBatch(address[] memory _owners, uint256[] memory _ids)
    public view returns (uint256[] memory)
  {
    require(_owners.length == _ids.length, "ERC1155#balanceOfBatch: INVALID_ARRAY_LENGTH");

    // Variables
    uint256[] memory batchBalances = new uint256[](_owners.length);

    // Iterate over each owner and token ID
    for (uint256 i = 0; i < _owners.length; i++) {
      batchBalances[i] = balances[_owners[i]][_ids[i]];
    }

    return batchBalances;
  }


  /***********************************|
  |          ERC165 Functions         |
  |__________________________________*/

  /**
   * INTERFACE_SIGNATURE_ERC165 = bytes4(keccak256("supportsInterface(bytes4)"));
   */
  bytes4 constant private INTERFACE_SIGNATURE_ERC165 = 0x01ffc9a7;

  /**
   * INTERFACE_SIGNATURE_ERC1155 =
   * bytes4(keccak256("safeTransferFrom(address,address,uint256,uint256,bytes)")) ^
   * bytes4(keccak256("safeBatchTransferFrom(address,address,uint256[],uint256[],bytes)")) ^
   * bytes4(keccak256("balanceOf(address,uint256)")) ^
   * bytes4(keccak256("balanceOfBatch(address[],uint256[])")) ^
   * bytes4(keccak256("setApprovalForAll(address,bool)")) ^
   * bytes4(keccak256("isApprovedForAll(address,address)"));
   */
  bytes4 constant private INTERFACE_SIGNATURE_ERC1155 = 0xd9b67a26;

  /**
   * @notice Query if a contract implements an interface
   * @param _interfaceID  The interface identifier, as specified in ERC-165
   * @return `true` if the contract implements `_interfaceID` and
   */
  function supportsInterface(bytes4 _interfaceID) external view returns (bool) {
    if (_interfaceID == INTERFACE_SIGNATURE_ERC165 ||
        _interfaceID == INTERFACE_SIGNATURE_ERC1155) {
      return true;
    }
    return false;
  }

}

/**
 * @notice Contract that handles metadata related methods.
 * @dev Methods assume a deterministic generation of URI based on token IDs.
 *      Methods also assume that URI uses hex representation of token IDs.
 */
contract ERC1155Metadata {

  // URI's default URI prefix
  string internal baseMetadataURI;
  event URI(string _uri, uint256 indexed _id);


  /***********************************|
  |     Metadata Public Function s    |
  |__________________________________*/

  /**
   * @notice A distinct Uniform Resource Identifier (URI) for a given token.
   * @dev URIs are defined in RFC 3986.
   *      URIs are assumed to be deterministically generated based on token ID
   *      Token IDs are assumed to be represented in their hex format in URIs
   * @return URI string
   */
  function uri(uint256 _id) public view returns (string memory) {
    return string(abi.encodePacked(baseMetadataURI, _uint2str(_id), ".json"));
  }


  /***********************************|
  |    Metadata Internal Functions    |
  |__________________________________*/

  /**
   * @notice Will emit default URI log event for corresponding token _id
   * @param _tokenIDs Array of IDs of tokens to log default URI
   */
  function _logURIs(uint256[] memory _tokenIDs) internal {
    string memory baseURL = baseMetadataURI;
    string memory tokenURI;

    for (uint256 i = 0; i < _tokenIDs.length; i++) {
      tokenURI = string(abi.encodePacked(baseURL, _uint2str(_tokenIDs[i]), ".json"));
      emit URI(tokenURI, _tokenIDs[i]);
    }
  }

  /**
   * @notice Will emit a specific URI log event for corresponding token
   * @param _tokenIDs IDs of the token corresponding to the _uris logged
   * @param _URIs    The URIs of the specified _tokenIDs
   */
  function _logURIs(uint256[] memory _tokenIDs, string[] memory _URIs) internal {
    require(_tokenIDs.length == _URIs.length, "ERC1155Metadata#_logURIs: INVALID_ARRAYS_LENGTH");
    for (uint256 i = 0; i < _tokenIDs.length; i++) {
      emit URI(_URIs[i], _tokenIDs[i]);
    }
  }

  /**
   * @notice Will update the base URL of token's URI
   * @param _newBaseMetadataURI New base URL of token's URI
   */
  function _setBaseMetadataURI(string memory _newBaseMetadataURI) internal {
    baseMetadataURI = _newBaseMetadataURI;
  }


  /***********************************|
  |    Utility Internal Functions     |
  |__________________________________*/

  /**
   * @notice Convert uint256 to string
   * @param _i Unsigned integer to convert to string
   */
  function _uint2str(uint256 _i) internal pure returns (string memory _uintAsString) {
    if (_i == 0) {
      return "0";
    }

    uint256 j = _i;
    uint256 ii = _i;
    uint256 len;

    // Get number of bytes
    while (j != 0) {
      len++;
      j /= 10;
    }

    bytes memory bstr = new bytes(len);
    uint256 k = len - 1;

    // Get each individual ASCII
    while (ii != 0) {
      bstr[k--] = byte(uint8(48 + ii % 10));
      ii /= 10;
    }

    // Convert to string
    return string(bstr);
  }

}

/**
 * @dev Multi-Fungible Tokens with minting and burning methods. These methods assume
 *      a parent contract to be executed as they are `internal` functions
 */
contract ERC1155MintBurn is ERC1155 {


  /****************************************|
  |            Minting Functions           |
  |_______________________________________*/

  /**
   * @notice Mint _amount of tokens of a given id
   * @param _to      The address to mint tokens to
   * @param _id      Token id to mint
   * @param _amount  The amount to be minted
   * @param _data    Data to pass if receiver is contract
   */
  function _mint(address _to, uint256 _id, uint256 _amount, bytes memory _data)
    internal
  {
    // Add _amount
    balances[_to][_id] = balances[_to][_id].add(_amount);

    // Emit event
    emit TransferSingle(msg.sender, address(0x0), _to, _id, _amount);

    // Calling onReceive method if recipient is contract
    _callonERC1155Received(address(0x0), _to, _id, _amount, _data);
  }

  /**
   * @notice Mint tokens for each ids in _ids
   * @param _to       The address to mint tokens to
   * @param _ids      Array of ids to mint
   * @param _amounts  Array of amount of tokens to mint per id
   * @param _data    Data to pass if receiver is contract
   */
  function _batchMint(address _to, uint256[] memory _ids, uint256[] memory _amounts, bytes memory _data)
    internal
  {
    require(_ids.length == _amounts.length, "ERC1155MintBurn#batchMint: INVALID_ARRAYS_LENGTH");

    // Number of mints to execute
    uint256 nMint = _ids.length;

     // Executing all minting
    for (uint256 i = 0; i < nMint; i++) {
      // Update storage balance
      balances[_to][_ids[i]] = balances[_to][_ids[i]].add(_amounts[i]);
    }

    // Emit batch mint event
    emit TransferBatch(msg.sender, address(0x0), _to, _ids, _amounts);

    // Calling onReceive method if recipient is contract
    _callonERC1155BatchReceived(address(0x0), _to, _ids, _amounts, _data);
  }


  /****************************************|
  |            Burning Functions           |
  |_______________________________________*/

  /**
   * @notice Burn _amount of tokens of a given token id
   * @param _from    The address to burn tokens from
   * @param _id      Token id to burn
   * @param _amount  The amount to be burned
   */
  function _burn(address _from, uint256 _id, uint256 _amount)
    internal
  {
    //Substract _amount
    balances[_from][_id] = balances[_from][_id].sub(_amount);

    // Emit event
    emit TransferSingle(msg.sender, _from, address(0x0), _id, _amount);
  }

  /**
   * @notice Burn tokens of given token id for each (_ids[i], _amounts[i]) pair
   * @param _from     The address to burn tokens from
   * @param _ids      Array of token ids to burn
   * @param _amounts  Array of the amount to be burned
   */
  function _batchBurn(address _from, uint256[] memory _ids, uint256[] memory _amounts)
    internal
  {
    require(_ids.length == _amounts.length, "ERC1155MintBurn#batchBurn: INVALID_ARRAYS_LENGTH");

    // Number of mints to execute
    uint256 nBurn = _ids.length;

     // Executing all minting
    for (uint256 i = 0; i < nBurn; i++) {
      // Update storage balance
      balances[_from][_ids[i]] = balances[_from][_ids[i]].sub(_amounts[i]);
    }

    // Emit batch mint event
    emit TransferBatch(msg.sender, _from, address(0x0), _ids, _amounts);
  }

}

library Strings {
	// via https://github.com/oraclize/ethereum-api/blob/master/oraclizeAPI_0.5.sol
	function strConcat(
		string memory _a,
		string memory _b,
		string memory _c,
		string memory _d,
		string memory _e
	) internal pure returns (string memory) {
		bytes memory _ba = bytes(_a);
		bytes memory _bb = bytes(_b);
		bytes memory _bc = bytes(_c);
		bytes memory _bd = bytes(_d);
		bytes memory _be = bytes(_e);
		string memory abcde = new string(_ba.length + _bb.length + _bc.length + _bd.length + _be.length);
		bytes memory babcde = bytes(abcde);
		uint256 k = 0;
		for (uint256 i = 0; i < _ba.length; i++) babcde[k++] = _ba[i];
		for (uint256 i = 0; i < _bb.length; i++) babcde[k++] = _bb[i];
		for (uint256 i = 0; i < _bc.length; i++) babcde[k++] = _bc[i];
		for (uint256 i = 0; i < _bd.length; i++) babcde[k++] = _bd[i];
		for (uint256 i = 0; i < _be.length; i++) babcde[k++] = _be[i];
		return string(babcde);
	}

	function strConcat(
		string memory _a,
		string memory _b,
		string memory _c,
		string memory _d
	) internal pure returns (string memory) {
		return strConcat(_a, _b, _c, _d, "");
	}

	function strConcat(
		string memory _a,
		string memory _b,
		string memory _c
	) internal pure returns (string memory) {
		return strConcat(_a, _b, _c, "", "");
	}

	function strConcat(string memory _a, string memory _b) internal pure returns (string memory) {
		return strConcat(_a, _b, "", "", "");
	}

	function uint2str(uint256 _i) internal pure returns (string memory _uintAsString) {
		if (_i == 0) {
			return "0";
		}
		uint256 j = _i;
		uint256 len;
		while (j != 0) {
			len++;
			j /= 10;
		}
		bytes memory bstr = new bytes(len);
		uint256 k = len - 1;
		while (_i != 0) {
			bstr[k--] = bytes1(uint8(48 + (_i % 10)));
			_i /= 10;
		}
		return string(bstr);
	}
}

contract OwnableDelegateProxy {}

contract ProxyRegistry {
	mapping(address => OwnableDelegateProxy) public proxies;
}

/**
 * @title ERC1155Tradable
 * ERC1155Tradable - ERC1155 contract that whitelists an operator address, 
 * has create and mint functionality, and supports useful standards from OpenZeppelin,
  like _exists(), name(), symbol(), and totalSupply()
 */
contract ERC1155Tradable is ERC1155, ERC1155MintBurn, ERC1155Metadata, Ownable, MinterRole, WhitelistAdminRole {
	using Strings for string;

	address proxyRegistryAddress;
	uint256 private _currentTokenID = 0;
	mapping(uint256 => address) public creators;
	mapping(uint256 => uint256) public tokenSupply;
	mapping(uint256 => uint256) public tokenMaxSupply;
	// Contract name
	string public name;
	// Contract symbol
	string public symbol;

    mapping(uint256 => string) private uris;

    bool private constructed = false;

    function init(
		string memory _name,
		string memory _symbol,
		address _proxyRegistryAddress
	) public {
	    
	    require(!constructed, "ERC155 Tradeable must not be constructed yet");
	    
	    constructed = true;
	    
		name = _name;
		symbol = _symbol;
		proxyRegistryAddress = _proxyRegistryAddress;
		
		super.initOwnable();
		super.initMinter();
		super.initWhiteListAdmin();
	}

	constructor(
		string memory _name,
		string memory _symbol,
		address _proxyRegistryAddress
	) public {
	    constructed = true;
		name = _name;
		symbol = _symbol;
		proxyRegistryAddress = _proxyRegistryAddress;
	}

	function removeWhitelistAdmin(address account) public onlyOwner {
		_removeWhitelistAdmin(account);
	}

	function removeMinter(address account) public onlyOwner {
		_removeMinter(account);
	}

	function uri(uint256 _id) public view returns (string memory) {
		require(_exists(_id), "ERC721Tradable#uri: NONEXISTENT_TOKEN");
		//return super.uri(_id);
		
		if(bytes(uris[_id]).length > 0){
		    return uris[_id];
		}
		return Strings.strConcat(baseMetadataURI, Strings.uint2str(_id));
	}

	/**
	 * @dev Returns the total quantity for a token ID
	 * @param _id uint256 ID of the token to query
	 * @return amount of token in existence
	 */
	function totalSupply(uint256 _id) public view returns (uint256) {
		return tokenSupply[_id];
	}

	/**
	 * @dev Returns the max quantity for a token ID
	 * @param _id uint256 ID of the token to query
	 * @return amount of token in existence
	 */
	function maxSupply(uint256 _id) public view returns (uint256) {
		return tokenMaxSupply[_id];
	}

	/**
	 * @dev Will update the base URL of token's URI
	 * @param _newBaseMetadataURI New base URL of token's URI
	 */
	function setBaseMetadataURI(string memory _newBaseMetadataURI) public onlyWhitelistAdmin {
		_setBaseMetadataURI(_newBaseMetadataURI);
	}

	/**
	 * @dev Creates a new token type and assigns _initialSupply to an address
	 * @param _maxSupply max supply allowed
	 * @param _initialSupply Optional amount to supply the first owner
	 * @param _uri Optional URI for this token type
	 * @param _data Optional data to pass if receiver is contract
	 * @return The newly created token ID
	 */
	function create(
		uint256 _maxSupply,
		uint256 _initialSupply,
		string calldata _uri,
		bytes calldata _data
	) external onlyWhitelistAdmin returns (uint256 tokenId) {
		require(_initialSupply <= _maxSupply, "Initial supply cannot be more than max supply");
		uint256 _id = _getNextTokenID();
		_incrementTokenTypeId();
		creators[_id] = msg.sender;

		if (bytes(_uri).length > 0) {
		    uris[_id] = _uri;
			emit URI(_uri, _id);
		}
		else{
		    emit URI(string(abi.encodePacked(baseMetadataURI, _uint2str(_id), ".json")), _id);
		}

		if (_initialSupply != 0) _mint(msg.sender, _id, _initialSupply, _data);
		tokenSupply[_id] = _initialSupply;
		tokenMaxSupply[_id] = _maxSupply;
		return _id;
	}
	
	function updateUri(uint256 _id, string calldata _uri) external onlyWhitelistAdmin{
	    if (bytes(_uri).length > 0) {
		    uris[_id] = _uri;
			emit URI(_uri, _id);
		}
		else{
		    emit URI(string(abi.encodePacked(baseMetadataURI, _uint2str(_id), ".json")), _id);
		}
	}
	
	function burn(address _address, uint256 _id, uint256 _amount) external {
	    require((msg.sender == _address) || isApprovedForAll(_address, msg.sender), "ERC1155#burn: INVALID_OPERATOR");
	    require(balances[_address][_id] >= _amount, "Trying to burn more tokens than you own");
	    _burn(_address, _id, _amount);
	}
	
	function updateProxyRegistryAddress(address _proxyRegistryAddress) external onlyWhitelistAdmin{
	    require(_proxyRegistryAddress != address(0), "No zero address");
	    proxyRegistryAddress = _proxyRegistryAddress;
	}

	/**
	 * @dev Mints some amount of tokens to an address
	 * @param _id          Token ID to mint
	 * @param _quantity    Amount of tokens to mint
	 * @param _data        Data to pass if receiver is contract
	 */
	function mint(
		uint256 _id,
		uint256 _quantity,
		bytes memory _data
	) public onlyMinter {
		uint256 tokenId = _id;
		require(tokenSupply[tokenId].add(_quantity) <= tokenMaxSupply[tokenId], "Max supply reached");
		_mint(msg.sender, _id, _quantity, _data);
		tokenSupply[_id] = tokenSupply[_id].add(_quantity);
	}

	/**
	 * Override isApprovedForAll to whitelist user's OpenSea proxy accounts to enable gas-free listings.
	 */
	
	function isApprovedForAll(address _owner, address _operator) public view returns (bool isOperator) {
		// Whitelist OpenSea proxy contract for easy trading.
		ProxyRegistry proxyRegistry = ProxyRegistry(proxyRegistryAddress);
		if (address(proxyRegistry.proxies(_owner)) == _operator) {
			return true;
		}

		return ERC1155.isApprovedForAll(_owner, _operator);
	}

	/**
	 * @dev Returns whether the specified token exists by checking to see if it has a creator
	 * @param _id uint256 ID of the token to query the existence of
	 * @return bool whether the token exists
	 */
	function _exists(uint256 _id) internal view returns (bool) {
		return creators[_id] != address(0);
	}

	/**
	 * @dev calculates the next token ID based on value of _currentTokenID
	 * @return uint256 for the next token ID
	 */
	function _getNextTokenID() private view returns (uint256) {
		return _currentTokenID.add(1);
	}

	/**
	 * @dev increments the value of _currentTokenID
	 */
	function _incrementTokenTypeId() private {
		_currentTokenID++;
	}
}

/**
 * @title Unifty
 * Unifty - NFT Tools
 * 
 * Rinkeby Opensea: 0xf57b2c51ded3a29e6891aba85459d600256cf317 
 * Mainnet Opensea: 0xa5409ec958c83c3f309868babaca7c86dcb077c1
 */
contract Unifty is ERC1155Tradable {
    
    string private _contractURI = "https://unifty.io/meta/contract.json";
    
	constructor(address _proxyRegistryAddress) public ERC1155Tradable("Unifty", "UNIF", _proxyRegistryAddress) {
		_setBaseMetadataURI("https://unifty.io/meta/");
	}

	function contractURI() public view returns (string memory) {
		return _contractURI;
	}
	
	function setContractURI(string memory _uri) public onlyWhitelistAdmin{
	    _contractURI = _uri;
	}
	
	function version() external pure returns (uint256) {
		return 1;
	}
	
}

interface UniftyMarketPool {
    
    function update(address _tokenAddress, uint256 _amount) external;
}

interface DetailedERC20 {
    
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);
    function totalSupply() external view returns (uint256);
}


contract UniftyMarket is Ownable, WhitelistAdminRole {
    
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    
    struct Ask {
        address seller;
		uint256[] pricePerItem;
		address[] erc1155Address;
		uint256[] id;
		address tokenAddress;
		uint256[] amount;
		uint256 price;
		uint256 amounts;
		bool released;
		uint256 swapMode; // 0 = only sell, 1 = sell and swap, 2 = only swap
		uint256 updates;
		uint256[] royalties;
	}
    
    address public nifAddress = address(0xb93370D549A4351FA52b3f99Eb5c252506e5a21e);
    address public poolAddress = address(0x7069cBA396cD136dA91Ce966f189E16271094124);
    address public feeAddress = address(0x2989018B83436C6bBa00144A8277fd859cdafA7D);
    uint256 public fee = 200; // default 2.00%
    Ask[] public asks; // list of Ask
    uint256[] public publicAsks;
    mapping(bytes => uint256 ) public publicAsksRef; // used to determine where the public asks are located based on the asks
    mapping(address => uint256[] ) public userAsks; // referencing asks
    mapping(address => mapping ( bytes => uint256 ) ) public userAsksRef; // used to determine where the user asks are located based on the asks
    
    mapping(address => mapping ( address => uint256 ) ) public funds; // seller => tokenAddress => funds
    mapping(address => uint256 ) public controllerFunds; // tokenAddress => funds
    mapping(address => address ) public referrer; // buyer => referrer
    
    mapping(address => mapping ( bytes => uint256 ) ) public royalties;
    mapping(address => address ) public royaltyOwner;
    
    mapping(bytes => Ask ) public referencedAsk;
    
    bytes4 constant internal ERC1155_RECEIVED_VALUE = 0xf23a6e61;
    bytes4 constant internal ERC1155_BATCH_RECEIVED_VALUE = 0xbc197c81;
    bytes4 constant internal ERC1155_RECEIVED_ERR_VALUE = 0x0;
    
    event Sale(address indexed _seller, uint256 indexed _index, uint256 _amount, address indexed _erc20TokenAddress, uint256 _pricePerItem);
    event PriceUpdate(address indexed _seller, uint256 indexed _index, uint256 indexed _subIndex, address _erc20TokenAddress, uint256 _pricePerItem);
    event AmountUpdate(address indexed _seller, uint256 indexed _index, uint256 indexed _subIndex, uint256 _amount, bool _add);
    event Purchase(address indexed _seller, address indexed _buyer, uint256 indexed _index, uint256 _amount, address _erc20TokenAddress, uint256 _price, uint256 _fee);
    event WithdrawFunds(address indexed _account, address indexed _erc20TokenAddress, uint256 _funds);
    event Referral(address indexed _referrer, address indexed _buyer, uint256 _index, address indexed _erc20TokenAddress, uint256 _share);
    event Royalty(address indexed _seller, address indexed _buyer, address indexed _collectionOwner, address _erc1155Address, uint256 _id, uint256 _royalties, address _erc20TokenAddress);
    
    uint private unlocked = 1;
    modifier lock() {
        require(unlocked == 1, 'UniftyMarket: LOCKED');
        unlocked = 0;
        _;
        unlocked = 1;
    }
    
	constructor() public { }
	
	
	/**
	 * BYING / SELLING
	 * 
	 * */
	 
	function sell(address _sender, 
	           address _erc1155Address, 
	           uint256 _id, 
	           uint256 _amount, 
	           address _tokenAddress, 
	           uint256 _pricePerItem, 
	           uint256 _index, 
	           bool _released, 
	           uint256 _swapMode
       ) external lock onlyWhitelistAdmin returns (uint256) {
	    
	    require(_pricePerItem >= 10 ** 3, "UniftyMarket#sell: Invalid price.");
	    require(_amount != 0, "UniftyMarket#sell: Invalid amount.");
	    require(ERC1155Tradable(_erc1155Address).balanceOf(_sender, _id) >= _amount, "UniftyMarket#sell: Insufficient funds.");
        require( _index == 0 || ( _index != 0 && _index < asks.length ), "UniftyMarket#sell: Index out of bounds.");
        
        if(asks.length == 0){
            
            asks.push(referencedAsk[abi.encode(0)]);
        }
        
        if(_index == 0){
            
            _index = asks.length;
        }
        
	    bytes memory askId = abi.encode(_index);
	    Ask storage ask = referencedAsk[askId];
	    
	    require(address(ask.seller) == address(0) || address(ask.seller) == address(_sender), "UniftyMarket#sell: Access denied.");
	    
	    if(address(ask.seller) == address(0)){
	    
	        ask.seller = address(_sender);
	        ask.tokenAddress = _tokenAddress;
	        
	        ask.price = ask.price.add(_pricePerItem.mul(_amount));
    	    ask.erc1155Address.push(_erc1155Address);
    	    ask.id.push(_id);
    	    ask.amount.push(_amount);
    	    ask.pricePerItem.push(_pricePerItem);
    	    ask.royalties.push(royaltiesCalc(_erc1155Address, _id, _pricePerItem));
    	    ask.amounts = ask.amounts.add(_amount);
    	    ask.released = _released;
    	    ask.swapMode = _swapMode;
	    
    	    // adding to the public list
    	    asks.push( ask );
    	    
    	    if(_released){
    	    
        	    releaseAsk(_sender, _index);
    	    
    	    }
    	    
    	    uint256 balance = ERC1155Tradable(_erc1155Address).balanceOf(address(this), _id);
    	    
	        ERC1155Tradable(_erc1155Address).safeTransferFrom(_sender, address(this), _id, _amount, "");
	    
	        assert(ERC1155Tradable(_erc1155Address).balanceOf(address(this), _id) == balance.add(_amount));
	        
	        emit Sale(_sender, _index, _amount, _tokenAddress, _pricePerItem);
        
	    } else {
	        
	        require(asks[ _index ].erc1155Address.length <= 25, "UniftyMarket#sell: Ask exceeds max item limit.");
	        
	        if(_swapMode != 0){
	            
	            require(asks[ _index ].updates == 0, "UniftyMarket#sell: Swapping not allowed after release and updates.");
	        }
	    
	        if(asks[ _index ].released){
	            
	            asks[ _index ].updates = asks[ _index ].updates.add(1);
	        }
	        
	        if(!asks[ _index ].released && _released){
	            
	            releaseAsk(_sender, _index);
    	        asks[ _index ].released = true;
	        }
	    
        	asks[ _index ].swapMode = _swapMode;
	    
    	    uint256 subIndex = getSubIndex(_index, _erc1155Address, _id);
    	   
    	    if(subIndex == 0){
        	    
        	    asks[ _index ].price = asks[ _index ].price.add(_pricePerItem.mul(_amount));
        	    asks[ _index ].erc1155Address.push(_erc1155Address);
        	    asks[ _index ].id.push(_id);
        	    asks[ _index ].amount.push(_amount);
        	    asks[ _index ].pricePerItem.push(_pricePerItem);
        	    asks[ _index ].royalties.push(royaltiesCalc(_erc1155Address, _id, _pricePerItem));
        	    asks[ _index ].amounts = asks[ _index ].amounts.add(_amount);
        	    
        	    uint256 balance = ERC1155Tradable(_erc1155Address).balanceOf(address(this), _id);
    	    
    	        ERC1155Tradable(_erc1155Address).safeTransferFrom(_sender, address(this), _id, _amount, "");
    	    
    	        assert(ERC1155Tradable(_erc1155Address).balanceOf(address(this), _id) == balance.add(_amount));
    	    }
    	    else
    	    {
    	        unlocked = 1;
    	        updateAskAmount(_sender, _sender, _amount, true, _index, subIndex.sub(1));
    	        updateAskPricePerItem(_sender, _pricePerItem, _index, subIndex.sub(1));
    	        unlocked = 0;
    	        
    	    }
    	    
    	    referencedAsk[askId] = asks[ _index ];
	    }
	    
	    return _index;
	}
	
	
	function releaseAsk(address _sender, uint256 _index) internal {
	    
	     require(saleExists(_sender, _index), "UniftyMarket#releaseAsk: Access denied.");
	     
	     bytes memory askId = abi.encode(_index);
         
         // required to start with index 1
	     if(userAsks[_sender].length == 0){
	        userAsks[_sender].push(0);
	     }
	    
	     userAsks[_sender].push(_index);
	     userAsksRef[_sender][askId] = userAsks[_sender].length.sub(1);
	    
	     // required to start with index 1
	     if(publicAsks.length == 0){
	        publicAsks.push(0);
	     }
	    
	     publicAsks.push(_index);
	     publicAsksRef[askId] = publicAsks.length.sub(1);
	 }
	
	function buy(address _seller, uint256 _amount, address _referrer, uint256 _index) external lock{
	   
	    require(_referrer == address(0) || _referrer != msg.sender, "UniftyMarket#buy: You cannot be buyer and referrer at the same time.");
	    require(_seller != msg.sender, "UniftyMarket#buy: You cannot buy your own sale.");
	    require(saleExists(_seller, _index), "UniftyMarket#buy: Sale doesn't exist.");
	    require(asks[_index].released, "UniftyMarket#buy: Ask not released yet.");
	    require(asks[_index].swapMode == 0 || asks[_index].swapMode == 1, "UniftyMarket#buy: Swapping only.");
	    
	    uint256 price = 0;
	    address _tokenAddress = asks[ _index ].tokenAddress;
	    uint256 outgoingAmount = 0;
	    
	    // single sale? if yes, then individual amounts are allowed for sale
	    if( asks[ _index ].erc1155Address.length == 1 ){
	        
	        require(asks[ _index ].amount[0] >= _amount, "UniftyMarket#buy: Requested amount exceeds local balance.");
	        
	        outgoingAmount = _amount;
	        
	        price = asks[ _index ].pricePerItem[0].mul( _amount );
    	    
	    }
	    else
	    {
	        require(asks[ _index ].amounts > 0, "UniftyMarket#buy: Sold out.");
	        
	        price = asks[ _index ].price;
	        outgoingAmount = asks[ _index ].amounts;
	    }
	    
	    require(price > 0, "UniftyMarket#buy: Price cannot be zero.");
	    
	    uint256 newPrice = price;
	    
	    for(uint256 i = 0; i < asks[ _index ].erc1155Address.length; i++){
	     
	        if(asks[ _index ].royalties[i] != 0 && royaltyOwner[ asks[_index].erc1155Address[i] ] != address(0) && asks[_index].seller != royaltyOwner[ asks[_index].erc1155Address[i] ]){
	            
	            funds[ royaltyOwner[ asks[_index].erc1155Address[i] ] ][_tokenAddress] = funds[ royaltyOwner[ asks[ _index ].erc1155Address[i] ] ][_tokenAddress].add( asks[ _index ].royalties[i].mul( asks[ _index ].amount[i] ) );
	            newPrice = newPrice.sub( asks[ _index ].royalties[i].mul( asks[ _index ].amount[i] ) );
	            emit Royalty(_seller, msg.sender, royaltyOwner[ asks[_index].erc1155Address[i] ], asks[_index].erc1155Address[i], asks[_index].id[i], asks[ _index ].royalties[i].mul( asks[ _index ].amount[i] ), _tokenAddress);
	        }
	    }
	    
	    uint256 _fee = newPrice.mul(10**18).div(100).mul(fee).div(10**20); // default 2% fee
	    
	    // share for the seller
	    funds[_seller][_tokenAddress] = funds[_seller][_tokenAddress].add(newPrice.sub(_fee));
	    
	    // adding referrer if any
	    if(_referrer != address(0) && referrer[msg.sender] == address(0)){
	        
	        referrer[msg.sender] = _referrer;
	    }
	    
	    uint256 fullFee = _fee;
	    
	    // assigning the referrer's share if any and re-calculating the fee for the controller
	    if(referrer[msg.sender] != address(0)){
	        _fee = _fee.mul(10**18).div(2).div(10**18);
	        funds[ referrer[msg.sender] ][_tokenAddress] = funds[ referrer[msg.sender] ][_tokenAddress].add(_fee);
	        emit Referral(referrer[msg.sender], msg.sender, _index, _tokenAddress, _fee);
	    }
	    
	    // share for the controller
	    controllerFunds[_tokenAddress] = controllerFunds[_tokenAddress].add(_fee);
	    
	    uint256 balance = 0;
	   
	    if( asks[ _index ].erc1155Address.length == 1 ){
	        
	        unlocked = 1;
	        updateAskAmount(asks[ _index ].seller, msg.sender, _amount, false, _index, 0);
	        unlocked = 0;
	    }
	    else
	    {
	        
	        for(uint256 i = 0; i < asks[ _index ].erc1155Address.length; i++){
	            
	            unlocked = 1;
	            updateAskAmount(asks[ _index ].seller, msg.sender, asks[ _index ].amount[i], false, _index, i);
	            unlocked = 0;
	        }
	    }
	    
	    balance = IERC20(_tokenAddress).balanceOf(address(this));
	    
	    IERC20(_tokenAddress).safeTransferFrom(msg.sender, address(this), price);
	    
	    assert(IERC20(_tokenAddress).balanceOf(address(this)) == balance.add(price));
	    
	    emit Purchase(_seller, msg.sender, _index, outgoingAmount, _tokenAddress, price, fullFee);
	}
	
	function royaltiesCalc(address _erc1155Address, uint256 _id, uint256 _price) internal view returns(uint256){
	    return _price.mul(10**18).div(100).mul(royalties[_erc1155Address][abi.encode(_id)]).div(10**20);
	}
	
	function updateAskPricePerItem(address _sender,  uint256 _pricePerItem, uint256 _index, uint256 _subIndex) internal lock {
	    
	    bytes memory index = abi.encode(_index);
	    
	    require(_pricePerItem >= 10 ** 3, "UniftyMarket#updateAskPricePerItem: Invalid price.");
	    require(address(asks[_index].seller) == address(_sender), "UniftyMarket#updateAskPricePerItem: Access denied.");
	    require(saleExists(_sender, _index), "UniftyMarket#updateAskAmount: Sale doesn't exist.");
	   
	    if( asks[_index].pricePerItem[_subIndex] != _pricePerItem ){
	           
            asks[_index].price = asks[_index].price.sub( asks[_index].pricePerItem[_subIndex].mul( asks[_index].amount[_subIndex] ) );
           
            asks[_index].pricePerItem[_subIndex] = _pricePerItem;
            
            asks[_index].price = asks[_index].price.add( _pricePerItem.mul( asks[_index].amount[_subIndex] ) );
            
            asks[ _index ].royalties[_subIndex] = royaltiesCalc(asks[_index].erc1155Address[_subIndex], asks[_index].id[_subIndex], _pricePerItem);
            
            asks[ _index ].updates = asks[ _index ].updates.add(1);
            
            referencedAsk[index] = asks[ _index ];
            
            emit PriceUpdate(_sender, _index, _subIndex, asks[_index].tokenAddress, _pricePerItem);
            
        }
	}
	
	function updateAskAmount(address _sender, address _receiver, uint256 _amount, bool _add, uint256 _index, uint256 _subIndex) internal lock {
	    
	    bytes memory index = abi.encode(_index);

	    require(saleExists(_sender, _index), "UniftyMarket#updateAskAmount: Sale doesn't exist.");
	    
        if(_add){
	                
            asks[_index].amount[_subIndex] = asks[_index].amount[_subIndex].add(_amount);
            
            asks[_index].amounts = asks[_index].amounts.add( _amount );
       
            asks[_index].price = asks[_index].price.add( asks[_index].pricePerItem[_subIndex].mul( _amount ) );
            
        }else{
            
            asks[_index].amount[_subIndex] = asks[_index].amount[_subIndex].sub(_amount);
            
            asks[_index].amounts = asks[_index].amounts.sub( _amount );
            
            asks[_index].price = asks[_index].price.sub( asks[_index].pricePerItem[_subIndex].mul( _amount ) );
       
        }
        
        asks[ _index ].updates = asks[ _index ].updates.add(1);
        
        referencedAsk[index] = asks[ _index ];
        
	    uint256 balance = ERC1155Tradable(asks[_index].erc1155Address[_subIndex]).balanceOf(address(this), asks[_index].id[_subIndex]);
	    
	    if(_add)
	    {
	        ERC1155Tradable(asks[_index].erc1155Address[_subIndex]).safeTransferFrom(_sender, address(this), asks[_index].id[_subIndex], _amount, "");
            assert(ERC1155Tradable(asks[_index].erc1155Address[_subIndex]).balanceOf(address(this), asks[_index].id[_subIndex]) == balance.add(_amount));
	    }
	    else
	    {
	        ERC1155Tradable(asks[_index].erc1155Address[_subIndex]).safeTransferFrom(address(this), _receiver, asks[_index].id[_subIndex], _amount, "");
	        assert(ERC1155Tradable(asks[_index].erc1155Address[_subIndex]).balanceOf(address(this), asks[_index].id[_subIndex]) == balance.sub(_amount));
	    }
	    
        if(asks[_index].amounts == 0){
	                   
            removeAsk(_sender, _index);
        }
        
        emit AmountUpdate(_sender, _index, _subIndex, _amount, _add);
	}
	
	function removeAsk(address _owner, uint256 _index) internal{
	    
	    bytes memory index = abi.encode(_index);
	    
	    uint256 publicAskIndex = publicAsksRef[index]; 
                        
        if(publicAskIndex != 0){
                        
            uint256 p_lastIndex = publicAsks.length.sub(1);
    	    
    	    uint256 tmp = publicAsks[ p_lastIndex ];
    	    
    	    if(p_lastIndex > 0 && p_lastIndex != publicAskIndex){
    	        
        	    publicAsks[ publicAskIndex ] = tmp;
        	    publicAsksRef[abi.encode(tmp)] = publicAskIndex;
        	    
    	    }
    	    
    	    delete publicAsks[ p_lastIndex ];
    	    publicAsks.length--;
        }
	    
	    //////////////////////////////////////
	    
	    uint256 userAskIndex = userAsksRef[_owner][index]; 
	    
	    if(userAskIndex != 0){
	    
    	    uint256 u_lastIndex = userAsks[_owner].length.sub(1);
    	    
    	    uint256 u_tmp = userAsks[_owner][ u_lastIndex ];
    	    
    	    if(u_lastIndex > 0 && u_lastIndex != userAskIndex){
        	    userAsks[_owner][ userAskIndex ] = u_tmp;
        	    userAsksRef[_owner][abi.encode(u_tmp)] = userAskIndex;
        	    
    	    }
    	    
    	    delete userAsks[_owner][ u_lastIndex ];
    	    userAsks[_owner].length--;
	    }
	}

	
	/**
	 * User Admin
	 * 
	 * */
	 
	 function getSubIndexLength(uint256 _index) public view returns(uint256){
	    
	     return asks[_index].erc1155Address.length;
	 }
	 
	 function getSubIndex(uint256 _index, address _erc1155Address, uint256 _id) public view returns(uint256){
	    
	    for(uint256 i = 0; i < asks[_index].erc1155Address.length; i++){
	        
	        if( asks[_index].erc1155Address[i] == _erc1155Address && asks[_index].id[i] == _id ){
	            return i;
	        }
	    }
	    
	    return 0;
	}
	
	function saleExists(address _seller, uint256 _index) public view returns(bool){
	    return address(asks[_index].seller) != address(0) && address(asks[_index].seller) == address(_seller);
	}
	
	function getAsk(uint256 _index) external view returns(Ask memory){
	   
	    return asks[_index];
	}
	
	function getAsksLength() external view returns(uint256){
	   
	    return asks.length;
	}
	
	function getAsksLengths(address _seller) external view returns(uint256, uint256){
	   
	    return (publicAsks.length, userAsks[_seller].length);
	}
	
	
	function updateAskAmountAdmin(address _sender, address _receiver, uint256 _amount, bool _add, uint256 _index, uint256 _subIndex) public onlyWhitelistAdmin {
	    
	    updateAskAmount(_sender, _receiver, _amount, _add, _index, _subIndex);
    }
    
    function updateAskPricePerItemAdmin(address _sender,  uint256 _pricePerItem, uint256 _index, uint256 _subIndex) public onlyWhitelistAdmin {
	    
	    updateAskPricePerItem(_sender, _pricePerItem, _index, _subIndex);
    }
	
	/**
	 * To save the buyer from paying 3 ERC20 transfers, we leave withdrawals to the sellers and referrers.
	 * */
	function withdrawBalance(address _tokenAddress) external lock {
	    uint256 _funds = funds[msg.sender][_tokenAddress];
	    require(_funds > 0 && IERC20(_tokenAddress).balanceOf(address(this)) >= _funds, "UniftyMarket#withdrawBalance: Insufficient funds.");
	    funds[msg.sender][_tokenAddress] = 0;
	    IERC20(_tokenAddress).safeTransfer(msg.sender, _funds);
	    emit WithdrawFunds(msg.sender, _tokenAddress, _funds);
	}
	
	/**
	 * To save the buyer from paying 3 ERC20 transfers, we leave withdrawals to the admin or an API call.
	 * Upon withdraw, 50% of the fees are forcefully moved to the pool and the other 50% to the contract owner's fee address.
	 * */
	function withdrawFee(address _tokenAddress) external lock onlyWhitelistAdmin {
	    uint256 balance = controllerFunds[_tokenAddress];
	    require(balance > 0, "UniftyMarket#withdrawFee: Insufficient funds.");
	    uint256 share = balance.mul(10**18).div(2).div(10**18);
	    controllerFunds[_tokenAddress] = 0;
	    IERC20(_tokenAddress).safeTransfer(feeAddress, share);
	    IERC20(_tokenAddress).safeTransfer(poolAddress, share);
	    UniftyMarketPool(poolAddress).update(_tokenAddress, share);
	}
	
	function setup(uint256 _fee, address _feeAddress, address _nifAddress, address _poolAddress) external onlyWhitelistAdmin {
	    fee = _fee;
	    feeAddress = _feeAddress;
	    nifAddress = _nifAddress;
	    poolAddress = _poolAddress;
	}
	
	function setRoyalty(address _erc1155Address, uint256 _id, uint256 _royaltyPercent) external lock {
	    
	    require( Unifty(_erc1155Address).owner() == msg.sender, "UniftyMarketWrapper#setRoyalty: Not the collection owner. Access denied." );
	    require(_royaltyPercent <= 5000, "UniftyMarketWrapper#setRoyalty: Max. 50% royalties allowed.");
	    
	    royalties[_erc1155Address][abi.encode(_id)] = _royaltyPercent;
	    royaltyOwner[_erc1155Address] = msg.sender;
	}
	
	function onERC1155Received(address _operator, address _from, uint256 _id, uint256 _amount, bytes calldata _data) external returns(bytes4){
	    
	    if(ERC1155Tradable(_operator) == ERC1155Tradable(address(this))){
	    
	        return ERC1155_RECEIVED_VALUE;
	    
	    }
	    
	    return ERC1155_RECEIVED_ERR_VALUE;
	}
	
	function onERC1155BatchReceived(address _operator, address _from, uint256[] calldata _ids, uint256[] calldata _amounts, bytes calldata _data) external returns(bytes4){
	      
        if(ERC1155Tradable(_operator) == ERC1155Tradable(address(this))){
    
            return ERC1155_BATCH_RECEIVED_VALUE;
    
        }
    
        return ERC1155_RECEIVED_ERR_VALUE;
    }
}