pragma solidity >=0.8.4;

import "@ensdomains/ens-contracts/contracts/registry/ENS.sol";
import "../metatx/RelayRecipient.sol";

/**
 * The ENS registry contract.
 */
contract ENSRegistryWithContext is RelayRecipient, ENS {
  struct Record {
    address owner;
    address resolver;
    uint64 ttl;
  }

  mapping(bytes32 => Record) records;
  mapping(address => mapping(address => bool)) operators;

  // Permits modifications only by the owner of the specified node.
  modifier authorised(bytes32 node) {
    address owner = records[node].owner;
    require(owner == _msgSender() || operators[owner][_msgSender()]);
    _;
  }

  /**
   * @dev Constructs a new ENS registrar.
   */
  constructor() public {
    records[0x0].owner = _msgSender();
  }

  /**
   * @dev Sets the record for a node.
   * @param node The node to update.
   * @param owner The address of the new owner.
   * @param resolver The address of the resolver.
   * @param ttl The TTL in seconds.
   */
  function setRecord(
    bytes32 node,
    address owner,
    address resolver,
    uint64 ttl
  ) external virtual override {
    setOwner(node, owner);
    _setResolverAndTTL(node, resolver, ttl);
  }

  /**
   * @dev Sets the record for a subnode.
   * @param node The parent node.
   * @param label The hash of the label specifying the subnode.
   * @param owner The address of the new owner.
   * @param resolver The address of the resolver.
   * @param ttl The TTL in seconds.
   */
  function setSubnodeRecord(
    bytes32 node,
    bytes32 label,
    address owner,
    address resolver,
    uint64 ttl
  ) external virtual override {
    bytes32 subnode = setSubnodeOwner(node, label, owner);
    _setResolverAndTTL(subnode, resolver, ttl);
  }

  /**
   * @dev Transfers ownership of a node to a new address. May only be called by the current owner of the node.
   * @param node The node to transfer ownership of.
   * @param owner The address of the new owner.
   */
  function setOwner(bytes32 node, address owner)
    public
    virtual
    override
    authorised(node)
  {
    _setOwner(node, owner);
    emit Transfer(node, owner);
  }

  /**
   * @dev Transfers ownership of a subnode keccak256(node, label) to a new address. May only be called by the owner of the parent node.
   * @param node The parent node.
   * @param label The hash of the label specifying the subnode.
   * @param owner The address of the new owner.
   */
  function setSubnodeOwner(
    bytes32 node,
    bytes32 label,
    address owner
  ) public virtual override authorised(node) returns (bytes32) {
    bytes32 subnode = keccak256(abi.encodePacked(node, label));
    _setOwner(subnode, owner);
    emit NewOwner(node, label, owner);
    return subnode;
  }

  /**
   * @dev Sets the resolver address for the specified node.
   * @param node The node to update.
   * @param resolver The address of the resolver.
   */
  function setResolver(bytes32 node, address resolver)
    external
    virtual
    override
    authorised(node)
  {
    emit NewResolver(node, resolver);
    records[node].resolver = resolver;
  }

  /**
   * @dev Sets the TTL for the specified node.
   * @param node The node to update.
   * @param ttl The TTL in seconds.
   */
  function setTTL(bytes32 node, uint64 ttl)
    external
    virtual
    override
    authorised(node)
  {
    emit NewTTL(node, ttl);
    records[node].ttl = ttl;
  }

  /**
   * @dev Enable or disable approval for a third party ("operator") to manage
   *  all of `_msgSender()`'s ENS records. Emits the ApprovalForAll event.
   * @param operator Address to add to the set of authorized operators.
   * @param approved True if the operator is approved, false to revoke approval.
   */
  function setApprovalForAll(address operator, bool approved)
    external
    virtual
    override
  {
    operators[_msgSender()][operator] = approved;
    emit ApprovalForAll(_msgSender(), operator, approved);
  }

  /**
   * @dev Returns the address that owns the specified node.
   * @param node The specified node.
   * @return address of the owner.
   */
  function owner(bytes32 node)
    external
    view
    virtual
    override
    returns (address)
  {
    address addr = records[node].owner;
    if (addr == address(this)) {
      return address(0x0);
    }

    return addr;
  }

  /**
   * @dev Returns the address of the resolver for the specified node.
   * @param node The specified node.
   * @return address of the resolver.
   */
  function resolver(bytes32 node)
    external
    view
    virtual
    override
    returns (address)
  {
    return records[node].resolver;
  }

  /**
   * @dev Returns the TTL of a node, and any records associated with it.
   * @param node The specified node.
   * @return ttl of the node.
   */
  function ttl(bytes32 node) external view virtual override returns (uint64) {
    return records[node].ttl;
  }

  /**
   * @dev Returns whether a record has been imported to the registry.
   * @param node The specified node.
   * @return Bool if record exists
   */
  function recordExists(bytes32 node)
    external
    view
    virtual
    override
    returns (bool)
  {
    return records[node].owner != address(0x0);
  }

  /**
   * @dev Query if an address is an authorized operator for another address.
   * @param owner The address that owns the records.
   * @param operator The address that acts on behalf of the owner.
   * @return True if `operator` is an approved operator for `owner`, false otherwise.
   */
  function isApprovedForAll(address owner, address operator)
    external
    view
    virtual
    override
    returns (bool)
  {
    return operators[owner][operator];
  }

  function _setOwner(bytes32 node, address owner) internal virtual {
    records[node].owner = owner;
  }

  function _setResolverAndTTL(
    bytes32 node,
    address resolver,
    uint64 ttl
  ) internal {
    if (resolver != records[node].resolver) {
      records[node].resolver = resolver;
      emit NewResolver(node, resolver);
    }

    if (ttl != records[node].ttl) {
      records[node].ttl = ttl;
      emit NewTTL(node, ttl);
    }
  }
}


// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/metatx/ERC2771Context.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

abstract contract RelayRecipient is ERC2771Context, Ownable {
  mapping(address => bool) trustedForwarder;

  event SetTrustedForwarder(address indexed user, bool allowed);

  constructor() ERC2771Context(msg.sender) {}

  function isTrustedForwarder(address forwarder)
    public
    view
    override
    returns (bool)
  {
    return trustedForwarder[forwarder];
  }

  function _msgSender()
    internal
    view
    virtual
    override(ERC2771Context, Context)
    returns (address sender)
  {
    return super._msgSender();
  }

  function _msgData()
    internal
    view
    virtual
    override(ERC2771Context, Context)
    returns (bytes calldata)
  {
    return super._msgData();
  }

  function setTrustedForwarder(address _user, bool _allowed)
    external
    onlyOwner
  {
    trustedForwarder[_user] = _allowed;
    emit SetTrustedForwarder(_user, _allowed);
  }
}


// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts v4.4.1 (utils/Context.sol)

pragma solidity ^0.8.0;

/**
 * @dev Provides information about the current execution context, including the
 * sender of the transaction and its data. While these are generally available
 * via msg.sender and msg.data, they should not be accessed in such a direct
 * manner, since when dealing with meta-transactions the account sending and
 * paying for execution may not be the actual sender (as far as an application
 * is concerned).
 *
 * This contract is only required for intermediate, library-like contracts.
 */
abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        return msg.data;
    }
}


// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts v4.4.1 (metatx/ERC2771Context.sol)

pragma solidity ^0.8.0;

import "../utils/Context.sol";

/**
 * @dev Context variant with ERC2771 support.
 */
abstract contract ERC2771Context is Context {
    address private _trustedForwarder;

    constructor(address trustedForwarder) {
        _trustedForwarder = trustedForwarder;
    }

    function isTrustedForwarder(address forwarder) public view virtual returns (bool) {
        return forwarder == _trustedForwarder;
    }

    function _msgSender() internal view virtual override returns (address sender) {
        if (isTrustedForwarder(msg.sender)) {
            // The assembly code is more direct than the Solidity version using `abi.decode`.
            assembly {
                sender := shr(96, calldataload(sub(calldatasize(), 20)))
            }
        } else {
            return super._msgSender();
        }
    }

    function _msgData() internal view virtual override returns (bytes calldata) {
        if (isTrustedForwarder(msg.sender)) {
            return msg.data[:msg.data.length - 20];
        } else {
            return super._msgData();
        }
    }
}


// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts v4.4.1 (access/Ownable.sol)

pragma solidity ^0.8.0;

import "../utils/Context.sol";

/**
 * @dev Contract module which provides a basic access control mechanism, where
 * there is an account (an owner) that can be granted exclusive access to
 * specific functions.
 *
 * By default, the owner account will be the one that deploys the contract. This
 * can later be changed with {transferOwnership}.
 *
 * This module is used through inheritance. It will make available the modifier
 * `onlyOwner`, which can be applied to your functions to restrict their use to
 * the owner.
 */
abstract contract Ownable is Context {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /**
     * @dev Initializes the contract setting the deployer as the initial owner.
     */
    constructor() {
        _transferOwnership(_msgSender());
    }

    /**
     * @dev Returns the address of the current owner.
     */
    function owner() public view virtual returns (address) {
        return _owner;
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        require(owner() == _msgSender(), "Ownable: caller is not the owner");
        _;
    }

    /**
     * @dev Leaves the contract without owner. It will not be possible to call
     * `onlyOwner` functions anymore. Can only be called by the current owner.
     *
     * NOTE: Renouncing ownership will leave the contract without an owner,
     * thereby removing any functionality that is only available to the owner.
     */
    function renounceOwnership() public virtual onlyOwner {
        _transferOwnership(address(0));
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        _transferOwnership(newOwner);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Internal function without access restriction.
     */
    function _transferOwnership(address newOwner) internal virtual {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
}


pragma solidity >=0.8.4;

interface ENS {

    // Logged when the owner of a node assigns a new owner to a subnode.
    event NewOwner(bytes32 indexed node, bytes32 indexed label, address owner);

    // Logged when the owner of a node transfers ownership to a new account.
    event Transfer(bytes32 indexed node, address owner);

    // Logged when the resolver for a node changes.
    event NewResolver(bytes32 indexed node, address resolver);

    // Logged when the TTL of a node changes
    event NewTTL(bytes32 indexed node, uint64 ttl);

    // Logged when an operator is added or removed.
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

    function setRecord(bytes32 node, address owner, address resolver, uint64 ttl) external virtual;
    function setSubnodeRecord(bytes32 node, bytes32 label, address owner, address resolver, uint64 ttl) external virtual;
    function setSubnodeOwner(bytes32 node, bytes32 label, address owner) external virtual returns(bytes32);
    function setResolver(bytes32 node, address resolver) external virtual;
    function setOwner(bytes32 node, address owner) external virtual;
    function setTTL(bytes32 node, uint64 ttl) external virtual;
    function setApprovalForAll(address operator, bool approved) external virtual;
    function owner(bytes32 node) external virtual view returns (address);
    function resolver(bytes32 node) external virtual view returns (address);
    function ttl(bytes32 node) external virtual view returns (uint64);
    function recordExists(bytes32 node) external virtual view returns (bool);
    function isApprovedForAll(address owner, address operator) external virtual view returns (bool);
}