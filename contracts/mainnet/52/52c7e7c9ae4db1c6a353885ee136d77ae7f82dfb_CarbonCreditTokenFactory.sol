// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.13;

import '@openzeppelin/contracts-upgradeable/proxy/ClonesUpgradeable.sol';
import "./abstracts/AbstractTokenFactory.sol";
import './CarbonCreditToken.sol';
import "./CarbonCreditPermissionList.sol";

/// @author FlowCarbon LLC
/// @title A Carbon Credit Token Factory
contract CarbonCreditTokenFactory is AbstractTokenFactory {

  using ClonesUpgradeable for address;

  /// @param implementationContract_ - the contract that is used a implementation base for new tokens
  constructor (CarbonCreditToken implementationContract_, address owner_) {
    swapImplementationContract(implementationContract_);
    transferOwnership(owner_);
  }

  /// @notice Deploy a new carbon credit token
  /// @param name_ - the name of the new token, should be unique within the Flow Carbon Ecosystem
  /// @param symbol_ - the token symbol of the ERC-20, should be unique within the Flow Carbon Ecosystem
  /// @param details_ - token details to define the fungibillity characteristics of this token
  /// @param owner_ - the owner of the new token, able to mint and finalize offsets
  /// @return the address of the newly created token
  function createCarbonCreditToken(
      string memory name_,
      string memory symbol_,
      CarbonCreditToken.TokenDetails memory details_,
      ICarbonCreditPermissionList permissionList_,
      address owner_)
    onlyOwner external returns (address)
  {
    CarbonCreditToken token = CarbonCreditToken(implementationContract.clone());
    token.initialize(name_, symbol_, details_, permissionList_, owner_);
    finalizeCreation(address(token));
    return address(token);
  }

}


// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.13;


import '@openzeppelin/contracts/access/Ownable.sol';
import "../interfaces/ICarbonCreditTokenInterface.sol";

/// @author FlowCarbon LLC
/// @title A Carbon Credit Token Factory
abstract contract AbstractTokenFactory is Ownable {

    /// @notice Emitted after the implementation contract has been swapped
    /// @param contractAddress - the address of the new implementation contract
    event SwappedImplementationContract(address contractAddress);

    /// @notice Emitted after a new token has been created by this factory
    /// @param tokenAddress - the address of the freshly deployed contract
    event TokenCreated(address tokenAddress);

    /// @notice The implementation contract used to create new tokens
    address public implementationContract;

    /// @dev Discoverable contracts that have been deployed by this factory
    address[] public deployedContracts;

    /// @notice The owner is able to swap out the underlying token implementation
    /// @param implementationContract_ - the contract to be used from now on
    function swapImplementationContract(ICarbonCreditTokenInterface implementationContract_) onlyOwner public returns (bool) {
        address contractAddress = address(implementationContract_);
        require(contractAddress != address(0), "null address given as implementation contract");
        implementationContract = contractAddress;
        emit SwappedImplementationContract(contractAddress);
        return true;
    }

    /// @notice The number of contracts deployed by this factory
    function deployedContractsCount() external view returns (uint256) {
        return deployedContracts.length;
    }

    /// @dev Internal function that should be called after each clone
    /// @param address_ - a freshly created token address
    function finalizeCreation(address address_) internal {
        deployedContracts.push(address_);
        emit TokenCreated(address_);
    }

}


// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.13;

/// @author FlowCarbon LLC
/// @title The common interface of carbon credit tokens
interface ICarbonCreditTokenInterface {

    /// @notice Emitted when someone offsets carbon tokens
    /// @param account - the account credited with offsetting
    /// @param amount - the amount of carbon that was offset
    event Offset(address account, uint256 amount);

    /// @notice Offset on behalf of the user
    /// @dev This will only offset tokens send by msg.sender, increases tokens awaiting finalization
    /// @param amount_ - the number of tokens to be offset
    function offset(uint256 amount_) external;

    /// @notice Offsets on behalf of the given address
    /// @dev This will offset tokens on behalf of account, increases tokens awaiting finalization
    /// @param account_ - the address off the account to offset on behalf of
    /// @param amount_ - the number of tokens to be offset
    function offsetOnBehalfOf(address account_, uint256 amount_) external;

    /// @notice Return the balance of tokens offsetted by the given address
    /// @param account_ - the account for which to check the number of tokens that were offset
    /// @return the number of tokens offsetted by the given account
    function offsetBalanceOf(address account_) external view returns (uint256);

    /// @notice Return the balance of tokens offsetted by an address that match the given checksum
    /// @param checksum_ - the checksum of the associated offset event of the underlying token
    /// @return the number of tokens that have been offsetted with this checksum
    function amountOffsettedWithChecksum(bytes32 checksum_) external view returns (uint256);

    /// @notice Returns the number of offsets for the given address
    /// @dev This is a pattern to discover all offsets and their occurrences for a user
    /// @param address_ - address of the user that offsetted the tokens
    function offsetCountOf(address address_) external view returns(uint256);

    /// @notice Returns amount of offsetted tokens for the given address and index
    /// @param address_ - address of the user who did the offsets
    /// @param index_ - index into the list
    function offsetAmountAtIndex(address address_, uint256 index_) external view returns(uint256);

    /// @notice Returns the timestamp of an offset for the given address and index
    /// @param address_ - address of the user who did the offsets
    /// @param index_ - index into the list
    function offsetTimeAtIndex(address address_, uint256 index_) external view returns(uint256);
}


// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.13;

/// @author FlowCarbon LLC
/// @title The common interface of carbon credit permission lists
interface ICarbonCreditPermissionList {

    /// @notice Emitted when the list state changes
    /// @param account - the account for which permissions have changed
    /// @param hasPermission - flag indicating wether permissions were granted or revoked
    event PermissionChanged(address account, bool hasPermission);

    // @notice Return the name of the list
    function name() external view returns (string memory);

    // @notice Grant or revoke permissions of an account
    // @param account_ - the address to which to grant or revoke permissions
    // @param hasPermission_ - flag indicating wether to grant or revoke permissions
    function setPermission(address account_, bool hasPermission_) external;

    // @notice Return the current permissions of an account
    // @param account_ - the address to check
    // @return flag indicating wether this account has permission or not
    function hasPermission(address account_) external view returns (bool);

    // @notice Return the address at the given list index
    // @param index_ - the index into the list
    // @return address at the given index
    function at(uint256 index_) external view returns (address);

    // @notice Get the number of accounts that have been granted permission
    // @return number of accounts that have been granted permission
    function length() external view returns (uint256);
}


// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.13;

import '@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol';
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import '@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol';
import "../interfaces/ICarbonCreditTokenInterface.sol";

/// @author FlowCarbon LLC
/// @title An Abstract Carbon Credit Token
abstract contract AbstractToken is ICarbonCreditTokenInterface, Initializable, OwnableUpgradeable, ERC20Upgradeable {

    struct OffsetEntry {
        uint time;
        uint amount;
    }

    /// @notice Emitted when the underlying token is offset
    /// @param amount - the amount of tokens offset
    /// @param checksum - the checksum associated with the offset event
    event FinalizeOffset(uint256 amount, bytes32 checksum);

    /// @notice User mapping to the amount of offset tokens
    mapping (address => uint256) internal _offsetBalances;

    /// @notice Number of tokens offset by the protocol that have not been finalized yet
    uint256 public pendingBalance;

    /// @notice Number of tokens fully offset
    uint256 public offsetBalance;

    /// @dev Mapping of user to offsets to make them discoverable
    mapping(address => OffsetEntry[]) private _offsets;

    function __AbstractToken_init(string memory name_, string memory symbol_, address owner_) internal initializer {
        __ERC20_init(name_, symbol_);
        __Ownable_init();
        transferOwnership(owner_);
    }

    /// @dev See ICarbonCreditTokenInterface
    function offsetCountOf(address address_) external view returns(uint256) {
        return _offsets[address_].length;
    }

    /// @dev See ICarbonCreditTokenInterface
    function offsetAmountAtIndex(address address_, uint256 index_) external view returns(uint256) {
        return _offsets[address_][index_].amount;
    }

    /// @dev See ICarbonCreditTokenInterface
    function offsetTimeAtIndex(address address_, uint256 index_) external view returns(uint256) {
        return _offsets[address_][index_].time;
    }

    //// @dev See ICarbonCreditTokenInterface
    function offsetBalanceOf(address account_) external view returns (uint256) {
        return _offsetBalances[account_];
    }

    /// @dev Common functionality of the two offset functions
    function _offset(address account_, uint256 amount_) internal {
        _burn(_msgSender(), amount_);
        _offsetBalances[account_] += amount_;
        pendingBalance += amount_;
        _offsets[account_].push(OffsetEntry(block.timestamp, amount_));

        emit Offset(account_, amount_);
    }

    /// @dev See ICarbonCreditTokenInterface
    function offsetOnBehalfOf(address account_, uint256 amount_) public {
        _offset(account_, amount_);
    }

    /// @dev See ICarbonCreditTokenInterface
    function offset(uint256 amount_) external {
        _offset(_msgSender(), amount_);
    }
}


// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.13;

import "./abstracts/AbstractToken.sol";
import "./interfaces/ICarbonCreditPermissionList.sol";

/// @author FlowCarbon LLC
/// @title A Carbon Credit Token Reference Implementation
contract CarbonCreditToken is AbstractToken {

    struct TokenDetails {
        string methodology;
        string creditType;
        uint16 vintage;
    }

    /// @notice Token metadata
    TokenDetails private _details;

    /// @notice The permissionlist associated with this token
    ICarbonCreditPermissionList public permissionList;

    /// @notice Emitted when the contract owner mints new tokens
    /// @dev The account is already in the Transfer Event and thus omitted here
    /// @param amount - the amount of tokens that were minted
    /// @param checksum - a checksum associated with the underlying purchase event
    event Mint(uint256 amount, bytes32 checksum);

    /// @notice Checksums associated with the underlying mapped to the number of minted tokens
    mapping (bytes32 => uint256) private _checksums;

    /// @notice Checksums associated with the underlying offset event mapped to the number of finally offsetted tokens
    mapping (bytes32 => uint256) private _offsetChecksums;

    /// @notice Number of tokens removed from chain
    uint256 public movedOffChain;

    function initialize(
        string memory name_,
        string memory symbol_,
        TokenDetails memory details_,
        ICarbonCreditPermissionList permissionList_,
        address owner_
    ) external initializer {
        require(details_.vintage > 2000, 'vintage out of bounds');
        require(details_.vintage < 2100, 'vintage out of bounds');
        __AbstractToken_init(name_, symbol_, owner_);
        _details = details_;
        permissionList = permissionList_;
    }

    /// @notice Mints new tokens, a checksum representing purchase of the underlying with the minting event
    /// @param account_ - the account that will receive the new tokens
    /// @param amount_ - the amount of new tokens to be minted
    /// @param checksum_ - a checksum associated with the underlying purchase event
    function mint(address account_, uint256 amount_, bytes32 checksum_) external onlyOwner returns (bool) {
        require(_checksums[checksum_] == 0, "checksum was already used");
        _mint(account_, amount_);
        _checksums[checksum_] = amount_;
        emit Mint(amount_, checksum_);
        return true;
    }

    /// @param checksum_ - the checksum associated with a minting event
    /// @return the amount minted with the associated checksum
    function amountMintedWithChecksum(bytes32 checksum_) external view returns (uint256) {
        return _checksums[checksum_];
    }

    /// @notice The contract owner can finalize the offsetting process once the underlying tokens have been offset
    /// @param amount_ - the number of token to finalize offsetting
    /// @param checksum_ - the checksum associated with the underlying offset event
    function finalizeOffset(uint256 amount_, bytes32 checksum_) external onlyOwner returns (bool) {
        require(_offsetChecksums[checksum_] == 0, "checksum was already used");
        require(amount_ <= pendingBalance, "offset exceeds pending balance");
        _offsetChecksums[checksum_] = amount_;
        pendingBalance -= amount_;
        offsetBalance += amount_;
        emit FinalizeOffset(amount_, checksum_);
        return true;
    }

     /// @dev Destroys `amount` tokens from the caller
    function burn(uint256 amount) public virtual {
        _burn(_msgSender(), amount);
        if (owner() == _msgSender()) {
            movedOffChain += amount;
        }
    }

    /// @dev See ICarbonCreditTokenInterface
    function amountOffsettedWithChecksum(bytes32 checksum_) external view returns (uint256) {
        return _offsetChecksums[checksum_];
    }

     /// @notice The methodology of this token (e.g. verra or goldstandard)
    function methodology() external view returns (string memory) {
        return _details.methodology;
    }

    /// @notice The creditType of this token (e.g. enum like "WETLAND_RESTORATION", or "REFORESTATION")
    function creditType() external view returns (string memory) {
        return _details.creditType;
    }

    /// @notice The guaranteed vintage of this year - newer is possible because new is always better :-)
    function vintage() external view returns (uint16) {
        return _details.vintage;
    }

    /// @notice Renounce the permission list, rendering this token non-permissioned
    /// NOTE: This operation is irreversible, it will leave the token permanently non-permissioned!
    function renouncePermissionList() onlyOwner external {
        permissionList = ICarbonCreditPermissionList(address(0));
    }

    function setPermissionList(ICarbonCreditPermissionList permissionList_) onlyOwner external {
        require(address(permissionList) != address(0), "this operation is not allowed for non-permissioned tokens");
        require(address(permissionList_) != address(0), "invalid attempt at renouncing the permission list - use renouncePermissionList() instead");
        permissionList = permissionList_;
    }

    /// @notice Override ERC20.transfer to respect permission lists
    function _transfer(address from_, address to_, uint256 amount_) internal virtual override {
        if (address(permissionList) != address(0)) {
            require(permissionList.hasPermission(from_), "the sender is not permitted to transfer this token");
            require(permissionList.hasPermission(to_), "the recipient is not permitted to receive this token");
        }
        return super._transfer(from_, to_, amount_);
    }
}


// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.13;

import '@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol';
import "@openzeppelin/contracts-upgradeable/utils/structs/EnumerableSetUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import './interfaces/ICarbonCreditPermissionList.sol';
import './CarbonCreditPermissionList.sol';

/// @author FlowCarbon LLC
/// @title List of accounts permitted to transfer or receive carbon credit tokens
contract CarbonCreditPermissionList is ICarbonCreditPermissionList, OwnableUpgradeable {

    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;

    EnumerableSetUpgradeable.AddressSet private _permissionList;

    string private _name;

    /// @param name_ the name of the permission list
    /// @param owner_ the owner of the permission list, allowed manage it's entries
    function initialize(string memory name_, address owner_) external initializer {
        __Ownable_init();
        _name = name_;
        transferOwnership(owner_);
    }

    // @notice Return the name of the list
    function name() external view returns (string memory) {
        return _name;
    }

    // @notice Batch update to grant or revoke permissions of an account
    // @param []accounts_ - the address to which to grant or revoke permissions
    // @param []permissions_ - flag indicating wether to grant or revoke permissions
    function setPermissions(address[] memory accounts_, bool[] memory permissions_) onlyOwner external {
        require(accounts_.length == permissions_.length, "accounts and permissions must have the same length");
        for (uint256 i=0; i < accounts_.length; i++) {
            setPermission(accounts_[i], permissions_[i]);
        }
    }

    // @notice Grant or revoke permissions of an account
    // @param account_ - the address to which to grant or revoke permissions
    // @param hasPermission_ - flag indicating wether to grant or revoke permissions
    function setPermission(address account_, bool hasPermission_) onlyOwner public {
        if (_permissionList.contains(account_) != hasPermission_) {
            if (hasPermission_) {
                _permissionList.add(account_);
            } else {
                _permissionList.remove(account_);
            }
            emit PermissionChanged(account_, hasPermission_);
        }
    }

    // @notice Return the current permissions of an account
    // @param account_ - the address to check
    // @return flag indicating wether this account has permission or not
    function hasPermission(address account_) external view returns (bool) {
        return _permissionList.contains(account_);
    }

    // @notice Return the address at the given list index
    // @param index_ - the index into the list
    // @return address at the given index
    function at(uint256 index_) external view returns (address) {
        return _permissionList.at(index_);
    }

    // @notice Get the number of accounts that have been granted permission
    // @return number of accounts that have been granted permission
    function length() external view returns (uint256) {
        return _permissionList.length();
    }
}


// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/**
 * @dev Library for managing
 * https://en.wikipedia.org/wiki/Set_(abstract_data_type)[sets] of primitive
 * types.
 *
 * Sets have the following properties:
 *
 * - Elements are added, removed, and checked for existence in constant time
 * (O(1)).
 * - Elements are enumerated in O(n). No guarantees are made on the ordering.
 *
 * ```
 * contract Example {
 *     // Add the library methods
 *     using EnumerableSet for EnumerableSet.AddressSet;
 *
 *     // Declare a set state variable
 *     EnumerableSet.AddressSet private mySet;
 * }
 * ```
 *
 * As of v3.3.0, sets of type `bytes32` (`Bytes32Set`), `address` (`AddressSet`)
 * and `uint256` (`UintSet`) are supported.
 */
library EnumerableSetUpgradeable {
    // To implement this library for multiple types with as little code
    // repetition as possible, we write it in terms of a generic Set type with
    // bytes32 values.
    // The Set implementation uses private functions, and user-facing
    // implementations (such as AddressSet) are just wrappers around the
    // underlying Set.
    // This means that we can only create new EnumerableSets for types that fit
    // in bytes32.

    struct Set {
        // Storage of set values
        bytes32[] _values;
        // Position of the value in the `values` array, plus 1 because index 0
        // means a value is not in the set.
        mapping(bytes32 => uint256) _indexes;
    }

    /**
     * @dev Add a value to a set. O(1).
     *
     * Returns true if the value was added to the set, that is if it was not
     * already present.
     */
    function _add(Set storage set, bytes32 value) private returns (bool) {
        if (!_contains(set, value)) {
            set._values.push(value);
            // The value is stored at length-1, but we add 1 to all indexes
            // and use 0 as a sentinel value
            set._indexes[value] = set._values.length;
            return true;
        } else {
            return false;
        }
    }

    /**
     * @dev Removes a value from a set. O(1).
     *
     * Returns true if the value was removed from the set, that is if it was
     * present.
     */
    function _remove(Set storage set, bytes32 value) private returns (bool) {
        // We read and store the value's index to prevent multiple reads from the same storage slot
        uint256 valueIndex = set._indexes[value];

        if (valueIndex != 0) {
            // Equivalent to contains(set, value)
            // To delete an element from the _values array in O(1), we swap the element to delete with the last one in
            // the array, and then remove the last element (sometimes called as 'swap and pop').
            // This modifies the order of the array, as noted in {at}.

            uint256 toDeleteIndex = valueIndex - 1;
            uint256 lastIndex = set._values.length - 1;

            if (lastIndex != toDeleteIndex) {
                bytes32 lastvalue = set._values[lastIndex];

                // Move the last value to the index where the value to delete is
                set._values[toDeleteIndex] = lastvalue;
                // Update the index for the moved value
                set._indexes[lastvalue] = valueIndex; // Replace lastvalue's index to valueIndex
            }

            // Delete the slot where the moved value was stored
            set._values.pop();

            // Delete the index for the deleted slot
            delete set._indexes[value];

            return true;
        } else {
            return false;
        }
    }

    /**
     * @dev Returns true if the value is in the set. O(1).
     */
    function _contains(Set storage set, bytes32 value) private view returns (bool) {
        return set._indexes[value] != 0;
    }

    /**
     * @dev Returns the number of values on the set. O(1).
     */
    function _length(Set storage set) private view returns (uint256) {
        return set._values.length;
    }

    /**
     * @dev Returns the value stored at position `index` in the set. O(1).
     *
     * Note that there are no guarantees on the ordering of values inside the
     * array, and it may change when more values are added or removed.
     *
     * Requirements:
     *
     * - `index` must be strictly less than {length}.
     */
    function _at(Set storage set, uint256 index) private view returns (bytes32) {
        return set._values[index];
    }

    /**
     * @dev Return the entire set in an array
     *
     * WARNING: This operation will copy the entire storage to memory, which can be quite expensive. This is designed
     * to mostly be used by view accessors that are queried without any gas fees. Developers should keep in mind that
     * this function has an unbounded cost, and using it as part of a state-changing function may render the function
     * uncallable if the set grows to a point where copying to memory consumes too much gas to fit in a block.
     */
    function _values(Set storage set) private view returns (bytes32[] memory) {
        return set._values;
    }

    // Bytes32Set

    struct Bytes32Set {
        Set _inner;
    }

    /**
     * @dev Add a value to a set. O(1).
     *
     * Returns true if the value was added to the set, that is if it was not
     * already present.
     */
    function add(Bytes32Set storage set, bytes32 value) internal returns (bool) {
        return _add(set._inner, value);
    }

    /**
     * @dev Removes a value from a set. O(1).
     *
     * Returns true if the value was removed from the set, that is if it was
     * present.
     */
    function remove(Bytes32Set storage set, bytes32 value) internal returns (bool) {
        return _remove(set._inner, value);
    }

    /**
     * @dev Returns true if the value is in the set. O(1).
     */
    function contains(Bytes32Set storage set, bytes32 value) internal view returns (bool) {
        return _contains(set._inner, value);
    }

    /**
     * @dev Returns the number of values in the set. O(1).
     */
    function length(Bytes32Set storage set) internal view returns (uint256) {
        return _length(set._inner);
    }

    /**
     * @dev Returns the value stored at position `index` in the set. O(1).
     *
     * Note that there are no guarantees on the ordering of values inside the
     * array, and it may change when more values are added or removed.
     *
     * Requirements:
     *
     * - `index` must be strictly less than {length}.
     */
    function at(Bytes32Set storage set, uint256 index) internal view returns (bytes32) {
        return _at(set._inner, index);
    }

    /**
     * @dev Return the entire set in an array
     *
     * WARNING: This operation will copy the entire storage to memory, which can be quite expensive. This is designed
     * to mostly be used by view accessors that are queried without any gas fees. Developers should keep in mind that
     * this function has an unbounded cost, and using it as part of a state-changing function may render the function
     * uncallable if the set grows to a point where copying to memory consumes too much gas to fit in a block.
     */
    function values(Bytes32Set storage set) internal view returns (bytes32[] memory) {
        return _values(set._inner);
    }

    // AddressSet

    struct AddressSet {
        Set _inner;
    }

    /**
     * @dev Add a value to a set. O(1).
     *
     * Returns true if the value was added to the set, that is if it was not
     * already present.
     */
    function add(AddressSet storage set, address value) internal returns (bool) {
        return _add(set._inner, bytes32(uint256(uint160(value))));
    }

    /**
     * @dev Removes a value from a set. O(1).
     *
     * Returns true if the value was removed from the set, that is if it was
     * present.
     */
    function remove(AddressSet storage set, address value) internal returns (bool) {
        return _remove(set._inner, bytes32(uint256(uint160(value))));
    }

    /**
     * @dev Returns true if the value is in the set. O(1).
     */
    function contains(AddressSet storage set, address value) internal view returns (bool) {
        return _contains(set._inner, bytes32(uint256(uint160(value))));
    }

    /**
     * @dev Returns the number of values in the set. O(1).
     */
    function length(AddressSet storage set) internal view returns (uint256) {
        return _length(set._inner);
    }

    /**
     * @dev Returns the value stored at position `index` in the set. O(1).
     *
     * Note that there are no guarantees on the ordering of values inside the
     * array, and it may change when more values are added or removed.
     *
     * Requirements:
     *
     * - `index` must be strictly less than {length}.
     */
    function at(AddressSet storage set, uint256 index) internal view returns (address) {
        return address(uint160(uint256(_at(set._inner, index))));
    }

    /**
     * @dev Return the entire set in an array
     *
     * WARNING: This operation will copy the entire storage to memory, which can be quite expensive. This is designed
     * to mostly be used by view accessors that are queried without any gas fees. Developers should keep in mind that
     * this function has an unbounded cost, and using it as part of a state-changing function may render the function
     * uncallable if the set grows to a point where copying to memory consumes too much gas to fit in a block.
     */
    function values(AddressSet storage set) internal view returns (address[] memory) {
        bytes32[] memory store = _values(set._inner);
        address[] memory result;

        assembly {
            result := store
        }

        return result;
    }

    // UintSet

    struct UintSet {
        Set _inner;
    }

    /**
     * @dev Add a value to a set. O(1).
     *
     * Returns true if the value was added to the set, that is if it was not
     * already present.
     */
    function add(UintSet storage set, uint256 value) internal returns (bool) {
        return _add(set._inner, bytes32(value));
    }

    /**
     * @dev Removes a value from a set. O(1).
     *
     * Returns true if the value was removed from the set, that is if it was
     * present.
     */
    function remove(UintSet storage set, uint256 value) internal returns (bool) {
        return _remove(set._inner, bytes32(value));
    }

    /**
     * @dev Returns true if the value is in the set. O(1).
     */
    function contains(UintSet storage set, uint256 value) internal view returns (bool) {
        return _contains(set._inner, bytes32(value));
    }

    /**
     * @dev Returns the number of values on the set. O(1).
     */
    function length(UintSet storage set) internal view returns (uint256) {
        return _length(set._inner);
    }

    /**
     * @dev Returns the value stored at position `index` in the set. O(1).
     *
     * Note that there are no guarantees on the ordering of values inside the
     * array, and it may change when more values are added or removed.
     *
     * Requirements:
     *
     * - `index` must be strictly less than {length}.
     */
    function at(UintSet storage set, uint256 index) internal view returns (uint256) {
        return uint256(_at(set._inner, index));
    }

    /**
     * @dev Return the entire set in an array
     *
     * WARNING: This operation will copy the entire storage to memory, which can be quite expensive. This is designed
     * to mostly be used by view accessors that are queried without any gas fees. Developers should keep in mind that
     * this function has an unbounded cost, and using it as part of a state-changing function may render the function
     * uncallable if the set grows to a point where copying to memory consumes too much gas to fit in a block.
     */
    function values(UintSet storage set) internal view returns (uint256[] memory) {
        bytes32[] memory store = _values(set._inner);
        uint256[] memory result;

        assembly {
            result := store
        }

        return result;
    }
}


// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
import "../proxy/utils/Initializable.sol";

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
abstract contract ContextUpgradeable is Initializable {
    function __Context_init() internal initializer {
        __Context_init_unchained();
    }

    function __Context_init_unchained() internal initializer {
    }
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        return msg.data;
    }
    uint256[50] private __gap;
}


// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../IERC20Upgradeable.sol";

/**
 * @dev Interface for the optional metadata functions from the ERC20 standard.
 *
 * _Available since v4.1._
 */
interface IERC20MetadataUpgradeable is IERC20Upgradeable {
    /**
     * @dev Returns the name of the token.
     */
    function name() external view returns (string memory);

    /**
     * @dev Returns the symbol of the token.
     */
    function symbol() external view returns (string memory);

    /**
     * @dev Returns the decimals places of the token.
     */
    function decimals() external view returns (uint8);
}


// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/**
 * @dev Interface of the ERC20 standard as defined in the EIP.
 */
interface IERC20Upgradeable {
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

pragma solidity ^0.8.0;

import "./IERC20Upgradeable.sol";
import "./extensions/IERC20MetadataUpgradeable.sol";
import "../../utils/ContextUpgradeable.sol";
import "../../proxy/utils/Initializable.sol";

/**
 * @dev Implementation of the {IERC20} interface.
 *
 * This implementation is agnostic to the way tokens are created. This means
 * that a supply mechanism has to be added in a derived contract using {_mint}.
 * For a generic mechanism see {ERC20PresetMinterPauser}.
 *
 * TIP: For a detailed writeup see our guide
 * https://forum.zeppelin.solutions/t/how-to-implement-erc20-supply-mechanisms/226[How
 * to implement supply mechanisms].
 *
 * We have followed general OpenZeppelin Contracts guidelines: functions revert
 * instead returning `false` on failure. This behavior is nonetheless
 * conventional and does not conflict with the expectations of ERC20
 * applications.
 *
 * Additionally, an {Approval} event is emitted on calls to {transferFrom}.
 * This allows applications to reconstruct the allowance for all accounts just
 * by listening to said events. Other implementations of the EIP may not emit
 * these events, as it isn't required by the specification.
 *
 * Finally, the non-standard {decreaseAllowance} and {increaseAllowance}
 * functions have been added to mitigate the well-known issues around setting
 * allowances. See {IERC20-approve}.
 */
contract ERC20Upgradeable is Initializable, ContextUpgradeable, IERC20Upgradeable, IERC20MetadataUpgradeable {
    mapping(address => uint256) private _balances;

    mapping(address => mapping(address => uint256)) private _allowances;

    uint256 private _totalSupply;

    string private _name;
    string private _symbol;

    /**
     * @dev Sets the values for {name} and {symbol}.
     *
     * The default value of {decimals} is 18. To select a different value for
     * {decimals} you should overload it.
     *
     * All two of these values are immutable: they can only be set once during
     * construction.
     */
    function __ERC20_init(string memory name_, string memory symbol_) internal initializer {
        __Context_init_unchained();
        __ERC20_init_unchained(name_, symbol_);
    }

    function __ERC20_init_unchained(string memory name_, string memory symbol_) internal initializer {
        _name = name_;
        _symbol = symbol_;
    }

    /**
     * @dev Returns the name of the token.
     */
    function name() public view virtual override returns (string memory) {
        return _name;
    }

    /**
     * @dev Returns the symbol of the token, usually a shorter version of the
     * name.
     */
    function symbol() public view virtual override returns (string memory) {
        return _symbol;
    }

    /**
     * @dev Returns the number of decimals used to get its user representation.
     * For example, if `decimals` equals `2`, a balance of `505` tokens should
     * be displayed to a user as `5.05` (`505 / 10 ** 2`).
     *
     * Tokens usually opt for a value of 18, imitating the relationship between
     * Ether and Wei. This is the value {ERC20} uses, unless this function is
     * overridden;
     *
     * NOTE: This information is only used for _display_ purposes: it in
     * no way affects any of the arithmetic of the contract, including
     * {IERC20-balanceOf} and {IERC20-transfer}.
     */
    function decimals() public view virtual override returns (uint8) {
        return 18;
    }

    /**
     * @dev See {IERC20-totalSupply}.
     */
    function totalSupply() public view virtual override returns (uint256) {
        return _totalSupply;
    }

    /**
     * @dev See {IERC20-balanceOf}.
     */
    function balanceOf(address account) public view virtual override returns (uint256) {
        return _balances[account];
    }

    /**
     * @dev See {IERC20-transfer}.
     *
     * Requirements:
     *
     * - `recipient` cannot be the zero address.
     * - the caller must have a balance of at least `amount`.
     */
    function transfer(address recipient, uint256 amount) public virtual override returns (bool) {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    /**
     * @dev See {IERC20-allowance}.
     */
    function allowance(address owner, address spender) public view virtual override returns (uint256) {
        return _allowances[owner][spender];
    }

    /**
     * @dev See {IERC20-approve}.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     */
    function approve(address spender, uint256 amount) public virtual override returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    /**
     * @dev See {IERC20-transferFrom}.
     *
     * Emits an {Approval} event indicating the updated allowance. This is not
     * required by the EIP. See the note at the beginning of {ERC20}.
     *
     * Requirements:
     *
     * - `sender` and `recipient` cannot be the zero address.
     * - `sender` must have a balance of at least `amount`.
     * - the caller must have allowance for ``sender``'s tokens of at least
     * `amount`.
     */
    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public virtual override returns (bool) {
        _transfer(sender, recipient, amount);

        uint256 currentAllowance = _allowances[sender][_msgSender()];
        require(currentAllowance >= amount, "ERC20: transfer amount exceeds allowance");
        unchecked {
            _approve(sender, _msgSender(), currentAllowance - amount);
        }

        return true;
    }

    /**
     * @dev Atomically increases the allowance granted to `spender` by the caller.
     *
     * This is an alternative to {approve} that can be used as a mitigation for
     * problems described in {IERC20-approve}.
     *
     * Emits an {Approval} event indicating the updated allowance.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     */
    function increaseAllowance(address spender, uint256 addedValue) public virtual returns (bool) {
        _approve(_msgSender(), spender, _allowances[_msgSender()][spender] + addedValue);
        return true;
    }

    /**
     * @dev Atomically decreases the allowance granted to `spender` by the caller.
     *
     * This is an alternative to {approve} that can be used as a mitigation for
     * problems described in {IERC20-approve}.
     *
     * Emits an {Approval} event indicating the updated allowance.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     * - `spender` must have allowance for the caller of at least
     * `subtractedValue`.
     */
    function decreaseAllowance(address spender, uint256 subtractedValue) public virtual returns (bool) {
        uint256 currentAllowance = _allowances[_msgSender()][spender];
        require(currentAllowance >= subtractedValue, "ERC20: decreased allowance below zero");
        unchecked {
            _approve(_msgSender(), spender, currentAllowance - subtractedValue);
        }

        return true;
    }

    /**
     * @dev Moves `amount` of tokens from `sender` to `recipient`.
     *
     * This internal function is equivalent to {transfer}, and can be used to
     * e.g. implement automatic token fees, slashing mechanisms, etc.
     *
     * Emits a {Transfer} event.
     *
     * Requirements:
     *
     * - `sender` cannot be the zero address.
     * - `recipient` cannot be the zero address.
     * - `sender` must have a balance of at least `amount`.
     */
    function _transfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal virtual {
        require(sender != address(0), "ERC20: transfer from the zero address");
        require(recipient != address(0), "ERC20: transfer to the zero address");

        _beforeTokenTransfer(sender, recipient, amount);

        uint256 senderBalance = _balances[sender];
        require(senderBalance >= amount, "ERC20: transfer amount exceeds balance");
        unchecked {
            _balances[sender] = senderBalance - amount;
        }
        _balances[recipient] += amount;

        emit Transfer(sender, recipient, amount);

        _afterTokenTransfer(sender, recipient, amount);
    }

    /** @dev Creates `amount` tokens and assigns them to `account`, increasing
     * the total supply.
     *
     * Emits a {Transfer} event with `from` set to the zero address.
     *
     * Requirements:
     *
     * - `account` cannot be the zero address.
     */
    function _mint(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: mint to the zero address");

        _beforeTokenTransfer(address(0), account, amount);

        _totalSupply += amount;
        _balances[account] += amount;
        emit Transfer(address(0), account, amount);

        _afterTokenTransfer(address(0), account, amount);
    }

    /**
     * @dev Destroys `amount` tokens from `account`, reducing the
     * total supply.
     *
     * Emits a {Transfer} event with `to` set to the zero address.
     *
     * Requirements:
     *
     * - `account` cannot be the zero address.
     * - `account` must have at least `amount` tokens.
     */
    function _burn(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: burn from the zero address");

        _beforeTokenTransfer(account, address(0), amount);

        uint256 accountBalance = _balances[account];
        require(accountBalance >= amount, "ERC20: burn amount exceeds balance");
        unchecked {
            _balances[account] = accountBalance - amount;
        }
        _totalSupply -= amount;

        emit Transfer(account, address(0), amount);

        _afterTokenTransfer(account, address(0), amount);
    }

    /**
     * @dev Sets `amount` as the allowance of `spender` over the `owner` s tokens.
     *
     * This internal function is equivalent to `approve`, and can be used to
     * e.g. set automatic allowances for certain subsystems, etc.
     *
     * Emits an {Approval} event.
     *
     * Requirements:
     *
     * - `owner` cannot be the zero address.
     * - `spender` cannot be the zero address.
     */
    function _approve(
        address owner,
        address spender,
        uint256 amount
    ) internal virtual {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    /**
     * @dev Hook that is called before any transfer of tokens. This includes
     * minting and burning.
     *
     * Calling conditions:
     *
     * - when `from` and `to` are both non-zero, `amount` of ``from``'s tokens
     * will be transferred to `to`.
     * - when `from` is zero, `amount` tokens will be minted for `to`.
     * - when `to` is zero, `amount` of ``from``'s tokens will be burned.
     * - `from` and `to` are never both zero.
     *
     * To learn more about hooks, head to xref:ROOT:extending-contracts.adoc#using-hooks[Using Hooks].
     */
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual {}

    /**
     * @dev Hook that is called after any transfer of tokens. This includes
     * minting and burning.
     *
     * Calling conditions:
     *
     * - when `from` and `to` are both non-zero, `amount` of ``from``'s tokens
     * has been transferred to `to`.
     * - when `from` is zero, `amount` tokens have been minted for `to`.
     * - when `to` is zero, `amount` of ``from``'s tokens have been burned.
     * - `from` and `to` are never both zero.
     *
     * To learn more about hooks, head to xref:ROOT:extending-contracts.adoc#using-hooks[Using Hooks].
     */
    function _afterTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual {}
    uint256[45] private __gap;
}


// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/**
 * @dev This is a base contract to aid in writing upgradeable contracts, or any kind of contract that will be deployed
 * behind a proxy. Since a proxied contract can't have a constructor, it's common to move constructor logic to an
 * external initializer function, usually called `initialize`. It then becomes necessary to protect this initializer
 * function so it can only be called once. The {initializer} modifier provided by this contract will have this effect.
 *
 * TIP: To avoid leaving the proxy in an uninitialized state, the initializer function should be called as early as
 * possible by providing the encoded function call as the `_data` argument to {ERC1967Proxy-constructor}.
 *
 * CAUTION: When used with inheritance, manual care must be taken to not invoke a parent initializer twice, or to ensure
 * that all initializers are idempotent. This is not verified automatically as constructors are by Solidity.
 */
abstract contract Initializable {
    /**
     * @dev Indicates that the contract has been initialized.
     */
    bool private _initialized;

    /**
     * @dev Indicates that the contract is in the process of being initialized.
     */
    bool private _initializing;

    /**
     * @dev Modifier to protect an initializer function from being invoked twice.
     */
    modifier initializer() {
        require(_initializing || !_initialized, "Initializable: contract is already initialized");

        bool isTopLevelCall = !_initializing;
        if (isTopLevelCall) {
            _initializing = true;
            _initialized = true;
        }

        _;

        if (isTopLevelCall) {
            _initializing = false;
        }
    }
}


// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/**
 * @dev https://eips.ethereum.org/EIPS/eip-1167[EIP 1167] is a standard for
 * deploying minimal proxy contracts, also known as "clones".
 *
 * > To simply and cheaply clone contract functionality in an immutable way, this standard specifies
 * > a minimal bytecode implementation that delegates all calls to a known, fixed address.
 *
 * The library includes functions to deploy a proxy using either `create` (traditional deployment) or `create2`
 * (salted deterministic deployment). It also includes functions to predict the addresses of clones deployed using the
 * deterministic method.
 *
 * _Available since v3.4._
 */
library ClonesUpgradeable {
    /**
     * @dev Deploys and returns the address of a clone that mimics the behaviour of `implementation`.
     *
     * This function uses the create opcode, which should never revert.
     */
    function clone(address implementation) internal returns (address instance) {
        assembly {
            let ptr := mload(0x40)
            mstore(ptr, 0x3d602d80600a3d3981f3363d3d373d3d3d363d73000000000000000000000000)
            mstore(add(ptr, 0x14), shl(0x60, implementation))
            mstore(add(ptr, 0x28), 0x5af43d82803e903d91602b57fd5bf30000000000000000000000000000000000)
            instance := create(0, ptr, 0x37)
        }
        require(instance != address(0), "ERC1167: create failed");
    }

    /**
     * @dev Deploys and returns the address of a clone that mimics the behaviour of `implementation`.
     *
     * This function uses the create2 opcode and a `salt` to deterministically deploy
     * the clone. Using the same `implementation` and `salt` multiple time will revert, since
     * the clones cannot be deployed twice at the same address.
     */
    function cloneDeterministic(address implementation, bytes32 salt) internal returns (address instance) {
        assembly {
            let ptr := mload(0x40)
            mstore(ptr, 0x3d602d80600a3d3981f3363d3d373d3d3d363d73000000000000000000000000)
            mstore(add(ptr, 0x14), shl(0x60, implementation))
            mstore(add(ptr, 0x28), 0x5af43d82803e903d91602b57fd5bf30000000000000000000000000000000000)
            instance := create2(0, ptr, 0x37, salt)
        }
        require(instance != address(0), "ERC1167: create2 failed");
    }

    /**
     * @dev Computes the address of a clone deployed using {Clones-cloneDeterministic}.
     */
    function predictDeterministicAddress(
        address implementation,
        bytes32 salt,
        address deployer
    ) internal pure returns (address predicted) {
        assembly {
            let ptr := mload(0x40)
            mstore(ptr, 0x3d602d80600a3d3981f3363d3d373d3d3d363d73000000000000000000000000)
            mstore(add(ptr, 0x14), shl(0x60, implementation))
            mstore(add(ptr, 0x28), 0x5af43d82803e903d91602b57fd5bf3ff00000000000000000000000000000000)
            mstore(add(ptr, 0x38), shl(0x60, deployer))
            mstore(add(ptr, 0x4c), salt)
            mstore(add(ptr, 0x6c), keccak256(ptr, 0x37))
            predicted := keccak256(add(ptr, 0x37), 0x55)
        }
    }

    /**
     * @dev Computes the address of a clone deployed using {Clones-cloneDeterministic}.
     */
    function predictDeterministicAddress(address implementation, bytes32 salt)
        internal
        view
        returns (address predicted)
    {
        return predictDeterministicAddress(implementation, salt, address(this));
    }
}


// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../utils/ContextUpgradeable.sol";
import "../proxy/utils/Initializable.sol";

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
abstract contract OwnableUpgradeable is Initializable, ContextUpgradeable {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /**
     * @dev Initializes the contract setting the deployer as the initial owner.
     */
    function __Ownable_init() internal initializer {
        __Context_init_unchained();
        __Ownable_init_unchained();
    }

    function __Ownable_init_unchained() internal initializer {
        _setOwner(_msgSender());
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
        _setOwner(address(0));
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        _setOwner(newOwner);
    }

    function _setOwner(address newOwner) private {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
    uint256[49] private __gap;
}


// SPDX-License-Identifier: MIT

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
        _setOwner(_msgSender());
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
        _setOwner(address(0));
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        _setOwner(newOwner);
    }

    function _setOwner(address newOwner) private {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
}