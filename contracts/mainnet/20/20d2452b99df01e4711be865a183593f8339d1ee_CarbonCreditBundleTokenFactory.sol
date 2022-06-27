// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.13;

import '@openzeppelin/contracts-upgradeable/proxy/ClonesUpgradeable.sol';
import './abstracts/AbstractFactory.sol';
import './CarbonCreditBundleToken.sol';
import './CarbonCreditToken.sol';
import './CarbonCreditTokenFactory.sol';
import './abstracts/AbstractToken.sol';

/// @author FlowCarbon LLC
/// @title A Carbon Credit Bundle Token Factory
contract CarbonCreditBundleTokenFactory is AbstractFactory {

    using ClonesUpgradeable for address;

    /// @notice The token factory for carbon credit tokens
    CarbonCreditTokenFactory public carbonCreditTokenFactory;

    /// @param implementationContract_ - The contract to be used as implementation base for new tokens
    /// @param owner_ - The owner of the contract
    /// @param carbonCreditTokenFactory_ - The factory used to deploy carbon credits tokens
    constructor (CarbonCreditBundleToken implementationContract_, address owner_, CarbonCreditTokenFactory carbonCreditTokenFactory_) {
        require(address(carbonCreditTokenFactory_) != address(0), 'carbonCreditTokenFactory_ may not be zero address');
        swapImplementationContract(address(implementationContract_));
        carbonCreditTokenFactory = carbonCreditTokenFactory_;
        transferOwnership(owner_);
    }

    /// @notice Deploy a new carbon credit token
    /// @param name_ - The name of the new token, should be unique within the Flow Carbon Ecosystem
    /// @param symbol_ - The token symbol of the ERC-20, should be unique within the Flow Carbon Ecosystem
    /// @param vintage_ - The minimum vintage of this bundle
    /// @param tokens_ - Initial set of tokens
    /// @param owner_ - The owner of the bundle token, eligible for fees and able to finalize offsets
    /// @param feeDivisor_ - The fee divisor that should be taken upon unbundling
    /// @return The address of the newly created token
    function createCarbonCreditBundleToken(
        string memory name_,
        string memory symbol_,
        uint16 vintage_,
        CarbonCreditToken[] memory tokens_,
        address owner_,
        uint256 feeDivisor_
    ) onlyOwner external returns (address) {
        CarbonCreditBundleToken token = CarbonCreditBundleToken(implementationContract.clone());
        token.initialize(name_, symbol_, vintage_, tokens_, owner_, feeDivisor_, carbonCreditTokenFactory);
        finalizeCreation(address(token));
        return address(token);
    }
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


// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.13;

/// @author FlowCarbon LLC
/// @title The common interface of carbon credit tokens
interface ICarbonCreditTokenInterface {

    /// @notice Emitted when someone offsets carbon tokens
    /// @param account - The account credited with offsetting
    /// @param amount - The amount of carbon that was offset
    event Offset(address account, uint256 amount);

    /// @notice Offset on behalf of the user
    /// @dev This will only offset tokens send by msg.sender, increases tokens awaiting finalization
    /// @param amount_ - The number of tokens to be offset
    function offset(uint256 amount_) external;

    /// @notice Offsets on behalf of the given address
    /// @dev This will offset tokens on behalf of account, increases tokens awaiting finalization
    /// @param account_ - The address of the account to offset on behalf of
    /// @param amount_ - The number of tokens to be offset
    function offsetOnBehalfOf(address account_, uint256 amount_) external;

    /// @notice Return the balance of tokens offsetted by the given address
    /// @param account_ - The account for which to check the number of tokens that were offset
    /// @return The number of tokens offsetted by the given account
    function offsetBalanceOf(address account_) external view returns (uint256);

    /// @notice Returns the number of offsets for the given address
    /// @dev This is a pattern to discover all offsets and their occurrences for a user
    /// @param address_ - Address of the user that offsetted the tokens
    function offsetCountOf(address address_) external view returns(uint256);

    /// @notice Returns amount of offsetted tokens for the given address and index
    /// @param address_ - Address of the user who did the offsets
    /// @param index_ - Index into the list
    function offsetAmountAtIndex(address address_, uint256 index_) external view returns(uint256);

    /// @notice Returns the timestamp of an offset for the given address and index
    /// @param address_ - Address of the user who did the offsets
    /// @param index_ - Index into the list
    function offsetTimeAtIndex(address address_, uint256 index_) external view returns(uint256);
}


// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.13;

/// @author FlowCarbon LLC
/// @title The common interface of carbon credit permission lists
interface ICarbonCreditPermissionList {

    /// @notice Emitted when the list state changes
    /// @param account - The account for which permissions have changed
    /// @param hasPermission - Flag indicating whether permissions were granted or revoked
    event PermissionChanged(address account, bool hasPermission);

    // @notice Return the name of the list
    function name() external view returns (string memory);

    // @notice Grant or revoke permissions of an account
    // @param account_ - The address to which to grant or revoke permissions
    // @param hasPermission_ - Flag indicating whether to grant or revoke permissions
    function setPermission(address account_, bool hasPermission_) external;

    // @notice Return the current permissions of an account
    // @param account_ - The address to check
    // @return Flag indicating whether this account has permission or not
    function hasPermission(address account_) external view returns (bool);

    // @notice Return the address at the given list index
    // @param index_ - The index into the list
    // @return Address at the given index
    function at(uint256 index_) external view returns (address);

    // @notice Get the number of accounts that have been granted permission
    // @return Number of accounts that have been granted permission
    function length() external view returns (uint256);
}


// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.13;

import '@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import '@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol';
import '../interfaces/ICarbonCreditTokenInterface.sol';

/// @author FlowCarbon LLC
/// @title An Abstract Carbon Credit Token
abstract contract AbstractToken is ICarbonCreditTokenInterface, Initializable, OwnableUpgradeable, ERC20Upgradeable {

    /// @notice the time and amount of a specific offset
    struct OffsetEntry {
        uint time;
        uint amount;
    }

    /// @notice Emitted when the underlying token is offset
    /// @param amount - The amount of tokens offset
    /// @param checksum - The checksum associated with the offset event
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
        require(bytes(name_).length > 0, 'name is required');
        require(bytes(symbol_).length > 0, 'symbol is required');
        __ERC20_init(name_, symbol_);
        __Ownable_init();
        transferOwnership(owner_);
    }

    /// @dev See ICarbonCreditTokenInterface
    function offsetCountOf(address address_) external view returns (uint256) {
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
    function offsetOnBehalfOf(address account_, uint256 amount_) external {
        _offset(account_, amount_);
    }

    /// @dev See ICarbonCreditTokenInterface
    function offset(uint256 amount_) external {
        _offset(_msgSender(), amount_);
    }

    /// @dev Overridden to disable renouncing ownership
    function renounceOwnership() public virtual override onlyOwner {
        revert('renouncing ownership is disabled');
    }
}


// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.13;


import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts-upgradeable/utils/structs/EnumerableSetUpgradeable.sol';

/// @author FlowCarbon LLC
/// @title A Carbon Credit Token Factory
abstract contract AbstractFactory is Ownable {

    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;

    /// @notice Emitted after the implementation contract has been swapped
    /// @param contractAddress - The address of the new implementation contract
    event SwappedImplementationContract(address contractAddress);

    /// @notice Emitted after a new token has been created by this factory
    /// @param instanceAddress - The address of the freshly deployed contract
    event InstanceCreated(address instanceAddress);

    /// @notice The implementation contract used to create new instances
    address public implementationContract;

    /// @dev Discoverable contracts that have been deployed by this factory
    EnumerableSetUpgradeable.AddressSet private _deployedContracts;

    /// @notice The owner is able to swap out the underlying token implementation
    /// @param implementationContract_ - The contract to be used from now on
    function swapImplementationContract(address implementationContract_) onlyOwner public returns (bool) {
        require(implementationContract_ != address(0), 'null address given as implementation contract');
        implementationContract = implementationContract_;
        emit SwappedImplementationContract(implementationContract_);
        return true;
    }

    /// @notice Check if a contract as been released by this factory
    /// @param address_ - The address of the contract
    /// @return Whether this contract has been deployed by this factory
    function hasContractDeployedAt(address address_) external view returns (bool) {
        return _deployedContracts.contains(address_);
    }

    /// @notice The number of contracts deployed by this factory
    function deployedContractsCount() external view returns (uint256) {
        return _deployedContracts.length();
    }

    /// @notice The contract deployed at a specific index
    /// @dev The ordering may change upon adding / removing
    /// @param index_ - The index into the set
    function deployedContractAt(uint256 index_) external view returns (address) {
        return _deployedContracts.at(index_);
    }

    /// @dev Internal function that should be called after each clone
    /// @param address_ - A freshly created token address
    function finalizeCreation(address address_) internal {
        _deployedContracts.add(address_);
        emit InstanceCreated(address_);
    }

    /// @dev Overridden to disable renouncing ownership
    function renounceOwnership() public virtual override onlyOwner {
        revert('renouncing ownership is disabled');
    }
}


// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.13;

import '@openzeppelin/contracts-upgradeable/proxy/ClonesUpgradeable.sol';
import './abstracts/AbstractFactory.sol';
import './CarbonCreditToken.sol';
import './CarbonCreditPermissionList.sol';
import './CarbonCreditBundleTokenFactory.sol';

/// @author FlowCarbon LLC
/// @title A Carbon Credit Token Factory
contract CarbonCreditTokenFactory is AbstractFactory {

    using ClonesUpgradeable for address;

    CarbonCreditBundleTokenFactory public carbonCreditBundleTokenFactory;

    /// @param implementationContract_ - the contract that is used a implementation base for new tokens
    constructor (CarbonCreditToken implementationContract_, address owner_) {
        swapImplementationContract(address(implementationContract_));
        transferOwnership(owner_);
    }

    /// @notice Set the carbon credit bundle token factory which is passed to token instances
    /// @param carbonCreditBundleTokenFactory_ - The factory instance associated with new tokens
    function setCarbonCreditBundleTokenFactory(CarbonCreditBundleTokenFactory carbonCreditBundleTokenFactory_) external onlyOwner {
        carbonCreditBundleTokenFactory = carbonCreditBundleTokenFactory_;
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
        require(address(carbonCreditBundleTokenFactory) != address(0), 'bundle token factory is not set');
        CarbonCreditToken token = CarbonCreditToken(implementationContract.clone());
        token.initialize(name_, symbol_, details_, permissionList_, owner_, carbonCreditBundleTokenFactory);
        finalizeCreation(address(token));
        return address(token);
    }
}


// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.13;

import './abstracts/AbstractToken.sol';
import './interfaces/ICarbonCreditPermissionList.sol';
import './CarbonCreditBundleTokenFactory.sol';

/// @author FlowCarbon LLC
/// @title A Carbon Credit Token Reference Implementation
contract CarbonCreditToken is AbstractToken {

    /// @notice Emitted when a token renounces its permission list
    /// @param renouncedPermissionListAddress - The address of the renounced permission list
    event PermissionListRenounced(address renouncedPermissionListAddress);

    /// @notice Emitted when the used permission list changes
    /// @param oldPermissionListAddress - The address of the old permission list
    /// @param newPermissionListAddress - The address of the new permission list
    event PermissionListChanged(address oldPermissionListAddress, address newPermissionListAddress);

    /// @notice The details of a token
    struct TokenDetails {
        /// The methodology of the token (e.g. VERRA)
        string methodology;
        /// The credit type of the token (e.g. FORESTRY)
        string creditType;
        /// The year in which the offset took place
        uint16 vintage;
    }

    /// @notice Token metadata
    TokenDetails private _details;

    /// @notice The permissionlist associated with this token
    ICarbonCreditPermissionList public permissionList;

    /// @notice The bundle token factory associated with this token
    CarbonCreditBundleTokenFactory public carbonCreditBundleTokenFactory;

    /// @notice Emitted when the contract owner mints new tokens
    /// @dev The account is already in the Transfer Event and thus omitted here
    /// @param amount - The amount of tokens that were minted
    /// @param checksum - A checksum associated with the underlying purchase event
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
        address owner_,
        CarbonCreditBundleTokenFactory carbonCreditBundleTokenFactory_
    ) external initializer {
        require(details_.vintage > 2000, 'vintage out of bounds');
        require(details_.vintage < 2100, 'vintage out of bounds');
        require(bytes(details_.methodology).length > 0, 'methodology is required');
        require(bytes(details_.creditType).length > 0, 'credit type is required');
        require(address(carbonCreditBundleTokenFactory_) != address(0), 'bundle token factory is required');
        __AbstractToken_init(name_, symbol_, owner_);
        _details = details_;
        permissionList = permissionList_;
        carbonCreditBundleTokenFactory = carbonCreditBundleTokenFactory_;
    }

    /// @notice Mints new tokens, a checksum representing purchase of the underlying with the minting event
    /// @param account_ - The account that will receive the new tokens
    /// @param amount_ - The amount of new tokens to be minted
    /// @param checksum_ - A checksum associated with the underlying purchase event
    function mint(address account_, uint256 amount_, bytes32 checksum_) external onlyOwner returns (bool) {
        require(checksum_ > 0, 'checksum is required');
        require(_checksums[checksum_] == 0, 'checksum was already used');
        _mint(account_, amount_);
        _checksums[checksum_] = amount_;
        emit Mint(amount_, checksum_);
        return true;
    }

    /// @notice Get the amount of tokens minted with the given checksum
    /// @param checksum_ - The checksum associated with a minting event
    /// @return The amount minted with the associated checksum
    function amountMintedWithChecksum(bytes32 checksum_) external view returns (uint256) {
        return _checksums[checksum_];
    }

    /// @notice The contract owner can finalize the offsetting process once the underlying tokens have been offset
    /// @param amount_ - The number of token to finalize offsetting
    /// @param checksum_ - The checksum associated with the underlying offset event
    function finalizeOffset(uint256 amount_, bytes32 checksum_) external onlyOwner returns (bool) {
        require(checksum_ > 0, 'checksum is required');
        require(_offsetChecksums[checksum_] == 0, 'checksum was already used');
        require(amount_ <= pendingBalance, 'offset exceeds pending balance');
        _offsetChecksums[checksum_] = amount_;
        pendingBalance -= amount_;
        offsetBalance += amount_;
        emit FinalizeOffset(amount_, checksum_);
        return true;
    }

    /// @dev Allow only privileged users to burn the given amount of tokens
    /// @param amount_ - The amount of tokens to burn
    function burn(uint256 amount_) public virtual {
        require(
            _msgSender() == owner() || carbonCreditBundleTokenFactory.hasContractDeployedAt(_msgSender()),
            'sender does not have permission to burn'
        );
        _burn(_msgSender(), amount_);
        if (owner() == _msgSender()) {
            movedOffChain += amount_;
        }
    }

    /// @notice Return the balance of tokens offsetted by an address that match the given checksum
    /// @param checksum_ - The checksum of the associated offset event of the underlying token
    /// @return The number of tokens that have been offsetted with this checksum
    function amountOffsettedWithChecksum(bytes32 checksum_) external view returns (uint256) {
        return _offsetChecksums[checksum_];
    }

     /// @notice The methodology of this token (e.g. VERRA or GOLDSTANDARD)
    function methodology() external view returns (string memory) {
        return _details.methodology;
    }

    /// @notice The creditType of this token (e.g. 'WETLAND_RESTORATION', or 'REFORESTATION')
    function creditType() external view returns (string memory) {
        return _details.creditType;
    }

    /// @notice The guaranteed vintage of this year - newer is possible because new is always better :-)
    function vintage() external view returns (uint16) {
        return _details.vintage;
    }

    /// @notice Renounce the permission list, making this token accessible to everyone
    /// NOTE: This operation is *irreversible* and will leave the token permanently non-permissioned!
    function renouncePermissionList() onlyOwner external {
        permissionList = ICarbonCreditPermissionList(address(0));
        emit PermissionListRenounced(address(this));
    }

    /// @notice Set the permission list
    /// @param permissionList_ - The permission list to use
    function setPermissionList(ICarbonCreditPermissionList permissionList_) onlyOwner external {
        require(address(permissionList) != address(0), 'this operation is not allowed for non-permissioned tokens');
        require(address(permissionList_) != address(0), 'invalid attempt at renouncing the permission list - use renouncePermissionList() instead');
        address oldPermissionListAddress = address(permissionList);
        permissionList = permissionList_;
        emit PermissionListChanged(oldPermissionListAddress, address(permissionList_));
    }

    /// @notice Override ERC20.transfer to respect permission lists
    /// @param from_ - The senders address
    /// @param to_ - The recipients address
    /// @param amount_ - The amount of tokens to send
    function _transfer(address from_, address to_, uint256 amount_) internal virtual override {
        if (address(permissionList) != address(0)) {
            require(permissionList.hasPermission(from_), 'the sender is not permitted to transfer this token');
            require(permissionList.hasPermission(to_), 'the recipient is not permitted to receive this token');
        }
        return super._transfer(from_, to_, amount_);
    }
}


// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.13;

import '@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/utils/structs/EnumerableSetUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import './interfaces/ICarbonCreditPermissionList.sol';
import './CarbonCreditPermissionList.sol';

/// @author FlowCarbon LLC
/// @title List of accounts permitted to transfer or receive carbon credit tokens
contract CarbonCreditPermissionList is ICarbonCreditPermissionList, OwnableUpgradeable {

    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;

    EnumerableSetUpgradeable.AddressSet private _permissionList;

    /// @dev The ecosystem-internal name given to the permission list
    string private _name;

    /// @param name_ - The name of the permission list
    /// @param owner_ - The owner of the permission list, allowed manage it's entries
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
    // @param []accounts_ - The address to which to grant or revoke permissions
    // @param []permissions_ - Flags indicating whether to grant or revoke permissions
    function setPermissions(address[] memory accounts_, bool[] memory permissions_) onlyOwner external {
        require(accounts_.length == permissions_.length, 'accounts and permissions must have the same length');
        for (uint256 i=0; i < accounts_.length; i++) {
            setPermission(accounts_[i], permissions_[i]);
        }
    }

    // @notice Grant or revoke permissions of an account
    // @param account_ - The address to which to grant or revoke permissions
    // @param hasPermission_ - Flag indicating whether to grant or revoke permissions
    function setPermission(address account_, bool hasPermission_) onlyOwner public {
        require(account_ != address(0), 'account is required');
        bool changed;
        if (hasPermission_) {
            changed = _permissionList.add(account_);
        } else {
            changed = _permissionList.remove(account_);
        }
        if (changed) {
            emit PermissionChanged(account_, hasPermission_);
        }
    }

    // @notice Return the current permissions of an account
    // @param account_ - The address to check
    // @return Flag indicating whether this account has permission or not
    function hasPermission(address account_) external view returns (bool) {
        return _permissionList.contains(account_);
    }

    // @notice Return the address at the given list index
    // @dev The ordering may change upon adding / removing
    // @param index_ - The index into the list
    // @return Address at the given index
    function at(uint256 index_) external view returns (address) {
        return _permissionList.at(index_);
    }

    // @notice Get the number of accounts that have been granted permission
    // @return Number of accounts that have been granted permission
    function length() external view returns (uint256) {
        return _permissionList.length();
    }

    /// @dev Overridden to disable renouncing ownership
    function renounceOwnership() public virtual override onlyOwner {
        revert('renouncing ownership is disabled');
    }
}


// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.13;

import '@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol';
import '@openzeppelin/contracts-upgradeable/utils/structs/EnumerableSetUpgradeable.sol';
import './abstracts/AbstractToken.sol';
import './CarbonCreditToken.sol';
import './CarbonCreditTokenFactory.sol';

/// @author FlowCarbon LLC
/// @title A Carbon Credit Bundle Token Reference Implementation
contract CarbonCreditBundleToken is AbstractToken {

    /// @notice The token address and amount of an offset event
    /// @dev The struct is stored for each checksum
    struct TokenChecksum {
        address _tokenAddress;
        uint256 _amount;
    }

    /// @notice Emitted when someone bundles tokens into the bundle token
    /// @param account - The token sender
    /// @param amount - The amount of tokens to bundle
    /// @param tokenAddress - The address of the vanilla underlying
    event Bundle(address account, uint256 amount, address tokenAddress);

    /// @notice Emitted when someone unbundles tokens from the bundle
    /// @param account - The token recipient
    /// @param amount - The amount of unbundled tokens
    /// @param tokenAddress - The address of the vanilla underlying
    event Unbundle(address account, uint256 amount, address tokenAddress);

    /// @notice Emitted when a new token is added to the bundle
    /// @param tokenAddress - The new token that is added
    event TokenAdded(address tokenAddress);

    /// @notice Emitted when a new token is removed from the bundle
    /// @param tokenAddress - The token that has been removed
    event TokenRemoved(address tokenAddress);

    /// @notice Emitted when a token is paused for deposited or removed
    /// @param token - the token paused for deposits
    /// @param paused - whether the token was paused (true) or reactivated (false)
    event TokenPaused(address token, bool paused);

    /// @notice Emitted when the minimum vintage requirements change
    /// @param vintage - The new vintage after the update
    event VintageIncremented(uint16 vintage);

    /// @notice The token factory for carbon credit tokens
    CarbonCreditTokenFactory public carbonCreditTokenFactory;

    /// @notice The fee divisor taken upon unbundling
    /// @dev 1/feeDivisor is the fee in %
    uint256 public feeDivisor;

    /// @notice The minimal vintage
    uint16 public vintage;

    /// @notice The CarbonCreditTokens that form this bundle
    EnumerableSetUpgradeable.AddressSet private _tokenAddresses;

    /// @notice Tokens disabled for deposit
    EnumerableSetUpgradeable.AddressSet private _pausedForDepositTokenAddresses;

    /// @notice The bookkeeping method on the bundled tokens
    /// @dev This could differ from the balance if someone sends raw tokens to the contract
    mapping (CarbonCreditToken => uint256) public bundledAmount;

    /// @notice Keeps track of checksums, amounts and underlying tokens
    mapping (bytes32 => TokenChecksum) private _offsetChecksums;

    uint16 constant MIN_VINTAGE_YEAR = 2000;
    uint16 constant MAX_VINTAGE_YEAR = 2100;
    uint8 constant MAX_VINTAGE_INCREMENT = 10;

    function initialize(
        string memory name_,
        string memory symbol_,
        uint16 vintage_,
        CarbonCreditToken[] memory tokens_,
        address owner_,
        uint256 feeDivisor_,
        CarbonCreditTokenFactory carbonCreditTokenFactory_
    ) external initializer {
        require(vintage_ > MIN_VINTAGE_YEAR, 'vintage out of bounds');
        require(vintage_ < MAX_VINTAGE_YEAR, 'vintage out of bounds');
        require(address(carbonCreditTokenFactory_) != address(0), 'token factory is required');

        __AbstractToken_init(name_, symbol_, owner_);

        vintage = vintage_;
        feeDivisor = feeDivisor_;
        carbonCreditTokenFactory = carbonCreditTokenFactory_;

        for (uint256 i = 0; i < tokens_.length; i++) {
            _addToken(tokens_[i]);
        }
    }

    /// @notice Increasing the vintage
    /// @dev Existing tokens can no longer be bundled, new tokens require the new vintage
    /// @param years_ - Number of years to increment the vintage, needs to be smaller than MAX_VINTAGE_INCREMENT
    function incrementVintage(uint16 years_) external onlyOwner returns (uint16) {
        require(years_ <= MAX_VINTAGE_INCREMENT, 'vintage increment is too large');
        require(vintage + years_ < MAX_VINTAGE_YEAR, 'vintage too high');

        vintage += years_;
        emit VintageIncremented(vintage);
        return vintage;
    }

    /// @notice Check if a token is paused for deposits
    /// @param token_ - The token to check
    /// @return Whether the token is paused or not
    function pausedForDeposits(CarbonCreditToken token_) public view returns (bool) {
        return EnumerableSetUpgradeable.contains(_pausedForDepositTokenAddresses, address(token_));
    }

    /// @notice Pauses or reactivates deposits for carbon credits
    /// @param token_ - The token to pause or reactivate
    /// @return Whether the action had an effect (the token was not already flagged for the respective action) or not
    function pauseOrReactivateForDeposits(CarbonCreditToken token_, bool pause_) external onlyOwner returns(bool) {
        require(hasToken(token_), 'token not part of the bundle');

        bool actionHadEffect;
        if (pause_) {
            actionHadEffect = EnumerableSetUpgradeable.add(_pausedForDepositTokenAddresses, address(token_));
        } else {
            actionHadEffect = EnumerableSetUpgradeable.remove(_pausedForDepositTokenAddresses, address(token_));
        }

        if (actionHadEffect) {
            emit TokenPaused(address(token_), pause_);
        }

        return actionHadEffect;
    }

    /// @notice Withdraws tokens that have been transferred to the contract
    /// @dev This may happen if people accidentally transfer tokens to the bundle instead of using the bundle function
    /// @param token_ - The token to withdraw orphans for
    /// @return The amount withdrawn to the owner
    function withdrawOrphanToken(CarbonCreditToken token_) public returns (uint256) {
        uint256 _orphanTokens = token_.balanceOf(address(this)) - bundledAmount[token_];

        if (_orphanTokens > 0) {
            SafeERC20Upgradeable.safeTransfer(token_, owner(), _orphanTokens);
        }
        return _orphanTokens;
    }

    /// @notice Checks if a token exists
    /// @param token_ - A carbon credit token
    function hasToken(CarbonCreditToken token_) public view returns (bool) {
        return EnumerableSetUpgradeable.contains(_tokenAddresses, address(token_));
    }

    /// @notice Number of tokens in this bundle
    function tokenCount() external view returns (uint256) {
        return EnumerableSetUpgradeable.length(_tokenAddresses);
    }

    /// @notice A token from the bundle
    /// @dev The ordering may change upon adding / removing
    /// @param index_ - The index position taken from tokenCount()
    function tokenAtIndex(uint256 index_) external view returns (address) {
        return EnumerableSetUpgradeable.at(_tokenAddresses, index_);
    }

    /// @notice Adds a new token to the bundle. The token has to match the TokenDetails signature of the bundle
    /// @param token_ - A carbon credit token that is added to the bundle.
    /// @return True if token was added, false it if did already exist
    function addToken(CarbonCreditToken token_) external onlyOwner returns (bool) {
        return _addToken(token_);
    }

    /// @dev Private function to execute addToken so it can be used in the initializer
    /// @return True if token was added, false it if did already exist
    function _addToken(CarbonCreditToken token_) private returns (bool) {
        require(!hasToken(token_), 'token already added to bundle');
        require(
            carbonCreditTokenFactory.hasContractDeployedAt(address(token_)),
            'token is not a carbon credit token'
        );
        require(token_.vintage() >= vintage, 'vintage mismatch');

        if (EnumerableSetUpgradeable.length(_tokenAddresses) > 0) {
            address existingBundleFactoryAddress = address(
                CarbonCreditToken(EnumerableSetUpgradeable.at(_tokenAddresses, 0)).carbonCreditBundleTokenFactory()
            );
            require(
                existingBundleFactoryAddress == address(token_.carbonCreditBundleTokenFactory()),
                'all tokens must share the same bundle token factory'
            );
        }

        bool isAdded = EnumerableSetUpgradeable.add(_tokenAddresses, address(token_));
        emit TokenAdded(address(token_));
        return isAdded;
    }

    /// @notice Removes a token from the bundle
    /// @param token_ - The carbon credit token to remove
    function removeToken(CarbonCreditToken token_) external onlyOwner {
        address tokenAddress = address(token_);
        require(EnumerableSetUpgradeable.contains(_tokenAddresses, tokenAddress), 'token is not part of bundle');

        withdrawOrphanToken(token_);
        require(token_.balanceOf(address(this)) == 0, 'token has remaining balance');

        EnumerableSetUpgradeable.remove(_tokenAddresses, tokenAddress);
        emit TokenRemoved(tokenAddress);
    }

    /// @notice Bundles an underlying into the bundle, bundle need to be approved beforehand
    /// @param token_ - The carbon credit token to bundle
    /// @param amount_ - The amount one wants to bundle
    function bundle(CarbonCreditToken token_, uint256 amount_) external returns (bool) {
        address tokenAddress = address(token_);
        require(EnumerableSetUpgradeable.contains(_tokenAddresses, tokenAddress), 'token is not part of bundle');
        require(token_.vintage() >= vintage, 'token outdated');
        require(amount_ > 0, 'amount may not be zero');
        require(!pausedForDeposits(token_), 'token is paused for bundling');

        _mint(_msgSender(), amount_);
        bundledAmount[token_] += amount_;
        SafeERC20Upgradeable.safeTransferFrom(token_, _msgSender(), address(this), amount_);

        emit Bundle(_msgSender(), amount_, tokenAddress);
        return true;
    }

    /// @notice Unbundles an underlying from the bundle, note that a fee may apply
    /// @param token_ - The carbon credit token to undbundle
    /// @param amount_ - The amount one wants to unbundle (including fee)
    /// @return The amount of tokens after fees
    function unbundle(CarbonCreditToken token_, uint256 amount_) external returns (uint256) {
        address tokenAddress = address(token_);
        require(EnumerableSetUpgradeable.contains(_tokenAddresses, tokenAddress), 'token is not part of bundle');
        require(token_.balanceOf(address(this)) >= amount_, 'amount exceeds the token balance');
        require(amount_ > 0, 'amount may not be zero');
        require(amount_ >= feeDivisor, 'fee divisor exceeds amount');

        _burn(_msgSender(), amount_);

        uint256 amountToUnbundle = amount_;
        if (feeDivisor > 0) {
            uint256 feeAmount = amount_ / feeDivisor;
            amountToUnbundle = amount_ - feeAmount;
            SafeERC20Upgradeable.safeTransfer(token_, owner(), feeAmount);
        }

        bundledAmount[token_] -= amount_;
        SafeERC20Upgradeable.safeTransfer(token_, _msgSender(), amountToUnbundle);

        emit Unbundle(_msgSender(), amountToUnbundle, tokenAddress);
        return amountToUnbundle;
    }

    /// @notice The contract owner can finalize the offsetting process once the underlying tokens have been offset
    /// @param token_ - The carbon credit token to finalize the offsetting process for
    /// @param amount_ - The number of token to finalize offsetting process for
    /// @param checksum_ - The checksum associated with the underlying offset event
    function finalizeOffset(CarbonCreditToken token_, uint256 amount_, bytes32 checksum_) external onlyOwner returns (bool) {
        address tokenAddress = address(token_);

        require(EnumerableSetUpgradeable.contains(_tokenAddresses, tokenAddress), 'token is not part of bundle');
        require(checksum_ > 0, 'checksum is required');
        require(_offsetChecksums[checksum_]._amount == 0, 'checksum was already used');
        require(amount_ <= pendingBalance, 'offset exceeds pending balance');
        require(token_.balanceOf(address(this)) >= amount_, 'amount exceeds the token balance');

        pendingBalance -= amount_;
        _offsetChecksums[checksum_] = TokenChecksum(tokenAddress, amount_);
        offsetBalance += amount_;
        bundledAmount[token_] -= amount_;

        token_.burn(amount_);
        emit FinalizeOffset(amount_, checksum_);
        return true;
    }

    /// @notice Return the balance of tokens offsetted by an address that match the given checksum
    /// @param checksum_ - The checksum of the associated offset event of the underlying token
    /// @return The number of tokens that have been offsetted with this checksum
    function amountOffsettedWithChecksum(bytes32 checksum_) external view returns (uint256) {
        return _offsetChecksums[checksum_]._amount;
    }

    /// @param checksum_ - The checksum of the associated offset event of the underlying
    /// @return The address of the CarbonCreditToken that has been offset with this checksum
    function tokenAddressOffsettedWithChecksum(bytes32 checksum_) external view returns (address) {
        return _offsetChecksums[checksum_]._tokenAddress;
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

/**
 * @dev Collection of functions related to the address type
 */
library AddressUpgradeable {
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
        assembly {
            size := extcodesize(account)
        }
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

        (bool success, ) = recipient.call{value: amount}("");
        require(success, "Address: unable to send value, recipient may have reverted");
    }

    /**
     * @dev Performs a Solidity function call using a low level `call`. A
     * plain `call` is an unsafe replacement for a function call: use this
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
    function functionCall(
        address target,
        bytes memory data,
        string memory errorMessage
    ) internal returns (bytes memory) {
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
    function functionCallWithValue(
        address target,
        bytes memory data,
        uint256 value
    ) internal returns (bytes memory) {
        return functionCallWithValue(target, data, value, "Address: low-level call with value failed");
    }

    /**
     * @dev Same as {xref-Address-functionCallWithValue-address-bytes-uint256-}[`functionCallWithValue`], but
     * with `errorMessage` as a fallback revert reason when `target` reverts.
     *
     * _Available since v3.1._
     */
    function functionCallWithValue(
        address target,
        bytes memory data,
        uint256 value,
        string memory errorMessage
    ) internal returns (bytes memory) {
        require(address(this).balance >= value, "Address: insufficient balance for call");
        require(isContract(target), "Address: call to non-contract");

        (bool success, bytes memory returndata) = target.call{value: value}(data);
        return verifyCallResult(success, returndata, errorMessage);
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
    function functionStaticCall(
        address target,
        bytes memory data,
        string memory errorMessage
    ) internal view returns (bytes memory) {
        require(isContract(target), "Address: static call to non-contract");

        (bool success, bytes memory returndata) = target.staticcall(data);
        return verifyCallResult(success, returndata, errorMessage);
    }

    /**
     * @dev Tool to verifies that a low level call was successful, and revert if it wasn't, either by bubbling the
     * revert reason using the provided one.
     *
     * _Available since v4.3._
     */
    function verifyCallResult(
        bool success,
        bytes memory returndata,
        string memory errorMessage
    ) internal pure returns (bytes memory) {
        if (success) {
            return returndata;
        } else {
            // Look for revert reason and bubble it up if present
            if (returndata.length > 0) {
                // The easiest way to bubble the revert reason is using memory via assembly

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


// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../IERC20Upgradeable.sol";
import "../../../utils/AddressUpgradeable.sol";

/**
 * @title SafeERC20
 * @dev Wrappers around ERC20 operations that throw on failure (when the token
 * contract returns false). Tokens that return no value (and instead revert or
 * throw on failure) are also supported, non-reverting calls are assumed to be
 * successful.
 * To use this library you can add a `using SafeERC20 for IERC20;` statement to your contract,
 * which allows you to call the safe operations as `token.safeTransfer(...)`, etc.
 */
library SafeERC20Upgradeable {
    using AddressUpgradeable for address;

    function safeTransfer(
        IERC20Upgradeable token,
        address to,
        uint256 value
    ) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(token.transfer.selector, to, value));
    }

    function safeTransferFrom(
        IERC20Upgradeable token,
        address from,
        address to,
        uint256 value
    ) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(token.transferFrom.selector, from, to, value));
    }

    /**
     * @dev Deprecated. This function has issues similar to the ones found in
     * {IERC20-approve}, and its usage is discouraged.
     *
     * Whenever possible, use {safeIncreaseAllowance} and
     * {safeDecreaseAllowance} instead.
     */
    function safeApprove(
        IERC20Upgradeable token,
        address spender,
        uint256 value
    ) internal {
        // safeApprove should only be called when setting an initial allowance,
        // or when resetting it to zero. To increase and decrease it, use
        // 'safeIncreaseAllowance' and 'safeDecreaseAllowance'
        require(
            (value == 0) || (token.allowance(address(this), spender) == 0),
            "SafeERC20: approve from non-zero to non-zero allowance"
        );
        _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, value));
    }

    function safeIncreaseAllowance(
        IERC20Upgradeable token,
        address spender,
        uint256 value
    ) internal {
        uint256 newAllowance = token.allowance(address(this), spender) + value;
        _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, newAllowance));
    }

    function safeDecreaseAllowance(
        IERC20Upgradeable token,
        address spender,
        uint256 value
    ) internal {
        unchecked {
            uint256 oldAllowance = token.allowance(address(this), spender);
            require(oldAllowance >= value, "SafeERC20: decreased allowance below zero");
            uint256 newAllowance = oldAllowance - value;
            _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, newAllowance));
        }
    }

    /**
     * @dev Imitates a Solidity high-level call (i.e. a regular function call to a contract), relaxing the requirement
     * on the return value: the return value is optional (but if data is returned, it must not be false).
     * @param token The token targeted by the call.
     * @param data The call data (encoded using abi.encode or one of its variants).
     */
    function _callOptionalReturn(IERC20Upgradeable token, bytes memory data) private {
        // We need to perform a low level call here, to bypass Solidity's return data size checking mechanism, since
        // we're implementing it ourselves. We use {Address.functionCall} to perform this call, which verifies that
        // the target address contains contract code and also asserts for success in the low-level call.

        bytes memory returndata = address(token).functionCall(data, "SafeERC20: low-level call failed");
        if (returndata.length > 0) {
            // Return data is optional
            require(abi.decode(returndata, (bool)), "SafeERC20: ERC20 operation did not succeed");
        }
    }
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