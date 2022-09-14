// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "./DataStructure.sol";
import "./UnergyData.sol";


///@dev abstract ERC20 contract token definition (Stable & Project).
abstract contract ERC20 {
    function mint(address account, uint256 amount) public virtual;
    function transferFrom(address from, address to, uint256 amount) public virtual;
    function transfer(address to, uint256 amount) public virtual;
    function balanceOf(address account) public virtual returns(uint256);
    function totalSupply() public virtual returns(uint256);
}


contract UnergyLogic is AccessControl, Pausable, Ownable {


    ///@dev Roles definition.
    bytes32 public constant masterRole = keccak256("masterRole");
    bytes32 public constant projectRole = keccak256("projectTokenRole");
    bytes32 public constant userRole = keccak256("userRole");
    bytes32 public constant meterRole = keccak256("meterRole");


    ///@dev variables
    address public unergyDataAddr;
    UnergyData unergyData;


    ///@dev events
    event ProjectCreated(DataStructure.Project project);
    event ProfitReport(
        address projectAddr,
        uint256 paymentValue,
        uint256 energyDelta
    );
    event InvoiceReport(
        address projectAddr,
        uint256 energyDelta,
        uint256 paymentValue,
        uint256 rawPaymentValue
    );
    event HolderUpdated(
        address projectAddr,
        address holder
    );
    event UpdatedPendingBalance(
        address projectAddr,
        address from,
        address to,
        uint256 amount
    );
    event EnergyReport(
        address projectAddr,
        uint256 currentAccEnergy
    );



    ///@dev contract functions
    constructor() Ownable() {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }


    ///@dev modifiers
    modifier hasMasterRole() {
        require(
            hasRole(DEFAULT_ADMIN_ROLE, msg.sender) ||
            hasRole(masterRole, msg.sender),
            "Caller is not authorized"
        );
        _;
    }

    modifier hasProjectRole() {
        require(
            hasRole(DEFAULT_ADMIN_ROLE, msg.sender) ||
            hasRole(masterRole, msg.sender) ||
            hasRole(projectRole, msg.sender),
            "Caller is not authorized"
        );
        _;
    }

    modifier hasMeterRole(address _projectAddr) {
        unergyData = UnergyData(unergyDataAddr);
        require(
            hasRole(DEFAULT_ADMIN_ROLE, msg.sender) ||
            hasRole(masterRole, msg.sender) ||
            (hasRole(meterRole, msg.sender) && unergyData.getMeter(_projectAddr, msg.sender)),
            "Caller is not authorized"
        );
        _;
    }

    modifier isInstalled(address _projectAddr) {
        unergyData = UnergyData(unergyDataAddr);
        DataStructure.Project memory project = unergyData.getProject(_projectAddr);
        DataStructure.ProjectState state = project.state;
        require(state == DataStructure.ProjectState.INSTALLED);
        _;
    }

    modifier inProduction(address _projectAddr) {
        unergyData = UnergyData(unergyDataAddr);
        DataStructure.Project memory project = unergyData.getProject(_projectAddr);
        DataStructure.ProjectState state = project.state;
        require(state == DataStructure.ProjectState.PRODUCTION);
        _;
    }

    function setUnergyData(address _UnergyDataAddr)
        public
        whenNotPaused
        hasMasterRole
    {
        unergyDataAddr = _UnergyDataAddr;
    }

    function createProject(
        uint256 _energyTariff,
        uint256 _maintenanceTariff,
        uint256 _managementTariff,
        uint256 _contractTerm,
        uint256 _uwattCost,
        uint256 _totalUwatts,
        uint256 _averageInflationRate,
        address _projectAddr,
        address _stableAddr,
        address _adminAddr
    )
        public
        whenNotPaused
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        unergyData = UnergyData(unergyDataAddr);
        DataStructure.Project memory project = DataStructure.Project(
            0,
            _energyTariff, 
            _maintenanceTariff,
            _managementTariff,
            _contractTerm,
            _uwattCost,
            _totalUwatts,
            _averageInflationRate,
            DataStructure.ProjectState.FUNDING,
            _projectAddr,
            _stableAddr,
            _adminAddr,
            '',
            ''
        );
        unergyData.setProject(project);
        grantRole(projectRole, _projectAddr);
        ERC20 projectContract = ERC20(_projectAddr);
        projectContract.mint(_adminAddr, _totalUwatts);
        emit ProjectCreated(project);
    }

    function compensationReport(
        address _projectAddr,
        uint256 _amount
    )
        public
        whenNotPaused
        hasMasterRole
        isInstalled(_projectAddr)
    {
        unergyData = UnergyData(unergyDataAddr);
        address stableAddr = unergyData.getStableAddr(_projectAddr);
        ERC20 stableContract = ERC20(stableAddr);
        stableContract.mint(unergyData.getAdminAddr(_projectAddr), _amount);
        profit(_projectAddr, _amount, 0);
    }

    function invoiceReport(address _projectAddr, uint256 _energyDelta)
        public
        whenNotPaused
        hasMasterRole
        inProduction(_projectAddr)
    {
        (uint256 rawPaymentValue, uint256 paymentValue) = calculatePaymentValue(
            _projectAddr,
            _energyDelta
        );
        unergyData = UnergyData(unergyDataAddr);
        address stableAddr = unergyData.getStableAddr(_projectAddr);
        address adminAddr = unergyData.getAdminAddr(_projectAddr);
        ERC20 stableContract = ERC20(stableAddr);
        stableContract.mint(adminAddr, rawPaymentValue);
        profit(_projectAddr, paymentValue, _energyDelta);
        emit InvoiceReport(
            _projectAddr,
            _energyDelta,
            paymentValue,
            rawPaymentValue
        );
    }

    function profit(
        address _projectAddr,
        uint256 _paymentValue,
        uint256 _energyDelta
    )
        internal
        virtual
    {
        unergyData = UnergyData(unergyDataAddr);
        uint256 paidEnergy = unergyData.getEnergyPayed(_projectAddr);
        uint256 nonPaidEnergy = (
            unergyData.getProjectAddrToAccEnergy(_projectAddr, address(0))
            - paidEnergy
        );

        require(
            nonPaidEnergy >= _energyDelta,
            "Paid energy is greater than accumulated energy"
        );
        
        ERC20 p = ERC20(_projectAddr);
        ERC20 t = ERC20(unergyData.getStableAddr(_projectAddr));
        address[] memory holders;
        holders = unergyData.getHolders(_projectAddr);
        
        for (uint256 i; i < holders.length; i++) {

            address tmpHolder = holders[i];
            uint256 deltaBalance = DataStructure.div(
                _paymentValue * p.balanceOf(tmpHolder), 
                p.totalSupply()
            );

            if (_energyDelta == 0) {
                t.transferFrom(
                    unergyData.getAdminAddr(_projectAddr),
                    tmpHolder,
                    deltaBalance
                );
            } else {
                uint256 newPendingBalance = (
                    unergyData.getPendingBalance(_projectAddr, tmpHolder)
                    - deltaBalance
                );
                unergyData.setPendingBalance(
                    _projectAddr,
                    tmpHolder,
                    newPendingBalance
                );
                t.transferFrom(
                    unergyData.getAdminAddr(_projectAddr),
                    tmpHolder,
                    deltaBalance
                );
            }
        }
        if (_energyDelta > 0) {
            unergyData.setEnergyPayed(_projectAddr, paidEnergy + _energyDelta);
        }
        emit ProfitReport(_projectAddr, _paymentValue, _energyDelta);
    }

    function updateHolders(address _projectAddr, address _holder)
        public
        whenNotPaused
        hasProjectRole
    {
        unergyData = UnergyData(unergyDataAddr);
        address [] memory holders;
        holders = unergyData.getHolders(_projectAddr);
        bool found;
        for (uint256 i; i < holders.length; i++) {
            if (_holder == holders[i]) {
                found = true;
                break;
            }
        }
        if (!found) {
            unergyData.setHolders(_projectAddr, _holder);
        }
        emit HolderUpdated(_projectAddr, _holder);
    }

    function updatePendingBalance(
        address _projectAddr,
        address _from,
        address _to,
        uint256 _amount
    )
        public
        whenNotPaused
        hasProjectRole
    {
        unergyData = UnergyData(unergyDataAddr);

        if (_from != address(0)) {
            uint256 balance = ERC20(_projectAddr).balanceOf(_from) + _amount; // Balance before tx
            uint256 pendingBalanceFrom = unergyData.getPendingBalance(
                _projectAddr,
                _from
            );
            uint256 pendingBalanceTo = unergyData.getPendingBalance(
                _projectAddr,
                _to
            );
            uint256 transferredAmount = DataStructure.div(
                pendingBalanceFrom * _amount,
                balance
            );
            unergyData.setPendingBalance(
                _projectAddr,
                _to,
                pendingBalanceTo + transferredAmount
            );
            unergyData.setPendingBalanceAcc(
                _projectAddr,
                _to,
                unergyData.getPendingBalanceAcc(_projectAddr, _to) + transferredAmount
            );
            unergyData.setPendingBalance(
                _projectAddr,
                _from,
                pendingBalanceFrom - transferredAmount
            );
            unergyData.setPendingBalanceAcc(
                _projectAddr,
                _from,
                unergyData.getPendingBalanceAcc(_projectAddr, _from) - transferredAmount
            );
        }
        emit UpdatedPendingBalance(_projectAddr, _from, _to, _amount);
    }

    function energyReport(address _projectAddr, uint256 _currentAccEnergy)
        public
        whenNotPaused
        hasMeterRole(_projectAddr)
    {
        unergyData = UnergyData(unergyDataAddr);
        DataStructure.Project memory project = unergyData.getProject(_projectAddr);
        
        require(
            unergyData.getProjectAddrToAccEnergy(_projectAddr, msg.sender) <= _currentAccEnergy,
            "The accumulated energy must be greater than the registered energy"
        );
        
        require(project.state == DataStructure.ProjectState.PRODUCTION);
        
        if (unergyData.getProjectAddrToAccEnergy(_projectAddr, msg.sender) == 0) {
            unergyData.setProjectAddrToAccEnergy(
                _projectAddr,
                msg.sender,
                _currentAccEnergy
            );
        } else {
            address [] memory holders = unergyData.getHolders(_projectAddr);
            ERC20 p = ERC20(_projectAddr);
            uint256 lastAccEnergy = unergyData.getProjectAddrToAccEnergy(
                _projectAddr, 
                msg.sender
            );
            uint256 energyDelta = (
                _currentAccEnergy
                - lastAccEnergy
            );
            (,uint256 paymentValue) = calculatePaymentValue(_projectAddr, energyDelta);
            
            for (uint256 i; i < holders.length; i++) {
                uint256 deltaBalance = DataStructure.div(
                    paymentValue * p.balanceOf(holders[i]),
                    p.totalSupply()
                );
                uint256 newPendingBalance = (
                    deltaBalance
                    + unergyData.getPendingBalance(_projectAddr, holders[i])
                );
                unergyData.setPendingBalance(
                    _projectAddr,
                    holders[i],
                    newPendingBalance
                );
                uint256 newPendingBalanceAcc = (
                    unergyData.getPendingBalanceAcc(_projectAddr, holders[i])
                    + newPendingBalance
                );
                unergyData.setPendingBalanceAcc(
                    _projectAddr,
                    holders[i],
                    newPendingBalanceAcc
                );
            }
            unergyData.setProjectAddrToAccEnergy(
                _projectAddr,
                msg.sender,
                _currentAccEnergy
            );
            unergyData.setProjectAddrToAccEnergy(
                _projectAddr,
                address(0),
                unergyData.getProjectAddrToAccEnergy(_projectAddr, address(0)) + energyDelta
            );
        }
        emit EnergyReport(_projectAddr, _currentAccEnergy);
    }

    function calculatePaymentValue(address _projectAddr, uint256 _energyDelta)
        internal
        virtual
        returns(uint256 rawPaymentValue, uint256 paymentValue)
    {
        unergyData = UnergyData(unergyDataAddr);
        uint256 energyTariff = unergyData.getEnergyTariff(_projectAddr);
        uint256 maintenanceTariff = unergyData.getMaintenanceTariff(_projectAddr);
        uint256 managementTariff = unergyData.getManagementTariff(_projectAddr);
        rawPaymentValue = DataStructure.div(_energyDelta * (energyTariff), 100);
        paymentValue = DataStructure.div(
            _energyDelta * (energyTariff - maintenanceTariff - managementTariff),
            100
        );
    }

    function setEnergyTariff(address _projectAddr,uint256 _energyTariff)
        public
        whenNotPaused
        hasMasterRole
    { 
        unergyData = UnergyData(unergyDataAddr);
        DataStructure.Project memory project = unergyData.getProject(_projectAddr);
        project.energyTariff = _energyTariff;
        unergyData.updateProject(_projectAddr, project);
    }

   function setMaintenanceTariff(
        address _projectAddr,
        uint256 _maintenanceTariff
    )
        public
        whenNotPaused
        hasMasterRole
    {
        unergyData = UnergyData(unergyDataAddr);
        DataStructure.Project memory project = unergyData.getProject(_projectAddr);
        project.maintenanceTariff = _maintenanceTariff;
        unergyData.updateProject(_projectAddr, project);
    }

    function setManagementTariff(
        address _projectAddr,
        uint256 _managementTariff
    )
        public
        whenNotPaused
        hasMasterRole
    {
        unergyData = UnergyData(unergyDataAddr);
        DataStructure.Project memory project = unergyData.getProject(_projectAddr);
        project.managementTariff = _managementTariff;
        unergyData.updateProject(_projectAddr, project);
    }

    function setContractTerm(address _projectAddr, uint256 _contractTerm)
        public
        whenNotPaused
        hasMasterRole
    {
        unergyData = UnergyData(unergyDataAddr);
        DataStructure.Project memory project = unergyData.getProject(_projectAddr);
        project.contractTerm = _contractTerm;
        unergyData.updateProject(_projectAddr, project);
    }

    function setUwattCost(address _projectAddr, uint256 _uwattCost)
        public
        whenNotPaused
        hasMasterRole
    {
        unergyData = UnergyData(unergyDataAddr);
        DataStructure.Project memory project = unergyData.getProject(_projectAddr);
        project.uwattCost = _uwattCost;
        unergyData.updateProject(_projectAddr, project);
    }

    function setTotalUwatts(address _projectAddr, uint256 _totalUwatts)
        public
        whenNotPaused
        hasMasterRole
    { 
        unergyData = UnergyData(unergyDataAddr);
        DataStructure.Project memory project = unergyData.getProject(_projectAddr);
        project.totalUwatts = _totalUwatts;
        unergyData.updateProject(_projectAddr, project);
    }

     function setAvgInflationRate(address _projectAddr, uint256 _averageInflationRate)
        public
        whenNotPaused
        hasMasterRole
    { 
        unergyData = UnergyData(unergyDataAddr);
        DataStructure.Project memory project = unergyData.getProject(_projectAddr);
        project.averageInflationRate = _averageInflationRate;
        unergyData.updateProject(_projectAddr, project);
    }

    function setState(address _projectAddr, DataStructure.ProjectState _state)
        public
        whenNotPaused
        hasMasterRole
    {
        unergyData = UnergyData(unergyDataAddr);
        DataStructure.Project memory project = unergyData.getProject(_projectAddr);
        project.state = _state;
        unergyData.updateProject(_projectAddr, project);
    }
   
    function setProjectAddr (address _projectAddr, address _newProjectAddr)
        public
        whenNotPaused
        hasMasterRole
    {
        unergyData = UnergyData(unergyDataAddr);
        DataStructure.Project memory project = unergyData.getProject(_projectAddr);
        project.projectAddr = _newProjectAddr;
        unergyData.updateProject(_projectAddr, project);
        grantRole(projectRole, _newProjectAddr);
        ERC20 projectContract = ERC20(_newProjectAddr);
        projectContract.mint(project.adminAddr, project.totalUwatts);
    }

    function setExtraData1 (address _projectAddr, string memory _extraData1)
        public
        whenNotPaused
        hasMasterRole
    {
        unergyData = UnergyData(unergyDataAddr);
        DataStructure.Project memory project = unergyData.getProject(_projectAddr);
        project.extraData1 = _extraData1;
        unergyData.updateProject(_projectAddr, project);
    }

    function setExtraData2 (address _projectAddr, string memory _extraData2)
        public
        whenNotPaused
        hasMasterRole
    {
        unergyData = UnergyData(unergyDataAddr);
        DataStructure.Project memory project = unergyData.getProject(_projectAddr);
        project.extraData2 = _extraData2;
        unergyData.updateProject(_projectAddr, project);
    }

     ///@dev Ownable methods overridden
    function transferOwnership(address newOwner) public override onlyOwner {
        require(newOwner != address(0), "Ownable: new owner cannot be the zero address");
        _transferOwnership(newOwner);
        _setupRole(DEFAULT_ADMIN_ROLE, newOwner);
        renounceRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }
}

// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v4.7.0) (access/AccessControl.sol)

pragma solidity ^0.8.0;

import "./IAccessControl.sol";
import "../utils/Context.sol";
import "../utils/Strings.sol";
import "../utils/introspection/ERC165.sol";

/**
 * @dev Contract module that allows children to implement role-based access
 * control mechanisms. This is a lightweight version that doesn't allow enumerating role
 * members except through off-chain means by accessing the contract event logs. Some
 * applications may benefit from on-chain enumerability, for those cases see
 * {AccessControlEnumerable}.
 *
 * Roles are referred to by their `bytes32` identifier. These should be exposed
 * in the external API and be unique. The best way to achieve this is by
 * using `public constant` hash digests:
 *
 * ```
 * bytes32 public constant MY_ROLE = keccak256("MY_ROLE");
 * ```
 *
 * Roles can be used to represent a set of permissions. To restrict access to a
 * function call, use {hasRole}:
 *
 * ```
 * function foo() public {
 *     require(hasRole(MY_ROLE, msg.sender));
 *     ...
 * }
 * ```
 *
 * Roles can be granted and revoked dynamically via the {grantRole} and
 * {revokeRole} functions. Each role has an associated admin role, and only
 * accounts that have a role's admin role can call {grantRole} and {revokeRole}.
 *
 * By default, the admin role for all roles is `DEFAULT_ADMIN_ROLE`, which means
 * that only accounts with this role will be able to grant or revoke other
 * roles. More complex role relationships can be created by using
 * {_setRoleAdmin}.
 *
 * WARNING: The `DEFAULT_ADMIN_ROLE` is also its own admin: it has permission to
 * grant and revoke this role. Extra precautions should be taken to secure
 * accounts that have been granted it.
 */
abstract contract AccessControl is Context, IAccessControl, ERC165 {
    struct RoleData {
        mapping(address => bool) members;
        bytes32 adminRole;
    }

    mapping(bytes32 => RoleData) private _roles;

    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;

    /**
     * @dev Modifier that checks that an account has a specific role. Reverts
     * with a standardized message including the required role.
     *
     * The format of the revert reason is given by the following regular expression:
     *
     *  /^AccessControl: account (0x[0-9a-f]{40}) is missing role (0x[0-9a-f]{64})$/
     *
     * _Available since v4.1._
     */
    modifier onlyRole(bytes32 role) {
        _checkRole(role);
        _;
    }

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(IAccessControl).interfaceId || super.supportsInterface(interfaceId);
    }

    /**
     * @dev Returns `true` if `account` has been granted `role`.
     */
    function hasRole(bytes32 role, address account) public view virtual override returns (bool) {
        return _roles[role].members[account];
    }

    /**
     * @dev Revert with a standard message if `_msgSender()` is missing `role`.
     * Overriding this function changes the behavior of the {onlyRole} modifier.
     *
     * Format of the revert message is described in {_checkRole}.
     *
     * _Available since v4.6._
     */
    function _checkRole(bytes32 role) internal view virtual {
        _checkRole(role, _msgSender());
    }

    /**
     * @dev Revert with a standard message if `account` is missing `role`.
     *
     * The format of the revert reason is given by the following regular expression:
     *
     *  /^AccessControl: account (0x[0-9a-f]{40}) is missing role (0x[0-9a-f]{64})$/
     */
    function _checkRole(bytes32 role, address account) internal view virtual {
        if (!hasRole(role, account)) {
            revert(
                string(
                    abi.encodePacked(
                        "AccessControl: account ",
                        Strings.toHexString(uint160(account), 20),
                        " is missing role ",
                        Strings.toHexString(uint256(role), 32)
                    )
                )
            );
        }
    }

    /**
     * @dev Returns the admin role that controls `role`. See {grantRole} and
     * {revokeRole}.
     *
     * To change a role's admin, use {_setRoleAdmin}.
     */
    function getRoleAdmin(bytes32 role) public view virtual override returns (bytes32) {
        return _roles[role].adminRole;
    }

    /**
     * @dev Grants `role` to `account`.
     *
     * If `account` had not been already granted `role`, emits a {RoleGranted}
     * event.
     *
     * Requirements:
     *
     * - the caller must have ``role``'s admin role.
     *
     * May emit a {RoleGranted} event.
     */
    function grantRole(bytes32 role, address account) public virtual override onlyRole(getRoleAdmin(role)) {
        _grantRole(role, account);
    }

    /**
     * @dev Revokes `role` from `account`.
     *
     * If `account` had been granted `role`, emits a {RoleRevoked} event.
     *
     * Requirements:
     *
     * - the caller must have ``role``'s admin role.
     *
     * May emit a {RoleRevoked} event.
     */
    function revokeRole(bytes32 role, address account) public virtual override onlyRole(getRoleAdmin(role)) {
        _revokeRole(role, account);
    }

    /**
     * @dev Revokes `role` from the calling account.
     *
     * Roles are often managed via {grantRole} and {revokeRole}: this function's
     * purpose is to provide a mechanism for accounts to lose their privileges
     * if they are compromised (such as when a trusted device is misplaced).
     *
     * If the calling account had been revoked `role`, emits a {RoleRevoked}
     * event.
     *
     * Requirements:
     *
     * - the caller must be `account`.
     *
     * May emit a {RoleRevoked} event.
     */
    function renounceRole(bytes32 role, address account) public virtual override {
        require(account == _msgSender(), "AccessControl: can only renounce roles for self");

        _revokeRole(role, account);
    }

    /**
     * @dev Grants `role` to `account`.
     *
     * If `account` had not been already granted `role`, emits a {RoleGranted}
     * event. Note that unlike {grantRole}, this function doesn't perform any
     * checks on the calling account.
     *
     * May emit a {RoleGranted} event.
     *
     * [WARNING]
     * ====
     * This function should only be called from the constructor when setting
     * up the initial roles for the system.
     *
     * Using this function in any other way is effectively circumventing the admin
     * system imposed by {AccessControl}.
     * ====
     *
     * NOTE: This function is deprecated in favor of {_grantRole}.
     */
    function _setupRole(bytes32 role, address account) internal virtual {
        _grantRole(role, account);
    }

    /**
     * @dev Sets `adminRole` as ``role``'s admin role.
     *
     * Emits a {RoleAdminChanged} event.
     */
    function _setRoleAdmin(bytes32 role, bytes32 adminRole) internal virtual {
        bytes32 previousAdminRole = getRoleAdmin(role);
        _roles[role].adminRole = adminRole;
        emit RoleAdminChanged(role, previousAdminRole, adminRole);
    }

    /**
     * @dev Grants `role` to `account`.
     *
     * Internal function without access restriction.
     *
     * May emit a {RoleGranted} event.
     */
    function _grantRole(bytes32 role, address account) internal virtual {
        if (!hasRole(role, account)) {
            _roles[role].members[account] = true;
            emit RoleGranted(role, account, _msgSender());
        }
    }

    /**
     * @dev Revokes `role` from `account`.
     *
     * Internal function without access restriction.
     *
     * May emit a {RoleRevoked} event.
     */
    function _revokeRole(bytes32 role, address account) internal virtual {
        if (hasRole(role, account)) {
            _roles[role].members[account] = false;
            emit RoleRevoked(role, account, _msgSender());
        }
    }
}


// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts v4.4.1 (access/IAccessControl.sol)

pragma solidity ^0.8.0;

/**
 * @dev External interface of AccessControl declared to support ERC165 detection.
 */
interface IAccessControl {
    /**
     * @dev Emitted when `newAdminRole` is set as ``role``'s admin role, replacing `previousAdminRole`
     *
     * `DEFAULT_ADMIN_ROLE` is the starting admin for all roles, despite
     * {RoleAdminChanged} not being emitted signaling this.
     *
     * _Available since v3.1._
     */
    event RoleAdminChanged(bytes32 indexed role, bytes32 indexed previousAdminRole, bytes32 indexed newAdminRole);

    /**
     * @dev Emitted when `account` is granted `role`.
     *
     * `sender` is the account that originated the contract call, an admin role
     * bearer except when using {AccessControl-_setupRole}.
     */
    event RoleGranted(bytes32 indexed role, address indexed account, address indexed sender);

    /**
     * @dev Emitted when `account` is revoked `role`.
     *
     * `sender` is the account that originated the contract call:
     *   - if using `revokeRole`, it is the admin role bearer
     *   - if using `renounceRole`, it is the role bearer (i.e. `account`)
     */
    event RoleRevoked(bytes32 indexed role, address indexed account, address indexed sender);

    /**
     * @dev Returns `true` if `account` has been granted `role`.
     */
    function hasRole(bytes32 role, address account) external view returns (bool);

    /**
     * @dev Returns the admin role that controls `role`. See {grantRole} and
     * {revokeRole}.
     *
     * To change a role's admin, use {AccessControl-_setRoleAdmin}.
     */
    function getRoleAdmin(bytes32 role) external view returns (bytes32);

    /**
     * @dev Grants `role` to `account`.
     *
     * If `account` had not been already granted `role`, emits a {RoleGranted}
     * event.
     *
     * Requirements:
     *
     * - the caller must have ``role``'s admin role.
     */
    function grantRole(bytes32 role, address account) external;

    /**
     * @dev Revokes `role` from `account`.
     *
     * If `account` had been granted `role`, emits a {RoleRevoked} event.
     *
     * Requirements:
     *
     * - the caller must have ``role``'s admin role.
     */
    function revokeRole(bytes32 role, address account) external;

    /**
     * @dev Revokes `role` from the calling account.
     *
     * Roles are often managed via {grantRole} and {revokeRole}: this function's
     * purpose is to provide a mechanism for accounts to lose their privileges
     * if they are compromised (such as when a trusted device is misplaced).
     *
     * If the calling account had been granted `role`, emits a {RoleRevoked}
     * event.
     *
     * Requirements:
     *
     * - the caller must be `account`.
     */
    function renounceRole(bytes32 role, address account) external;
}


// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v4.7.0) (access/Ownable.sol)

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
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        _checkOwner();
        _;
    }

    /**
     * @dev Returns the address of the current owner.
     */
    function owner() public view virtual returns (address) {
        return _owner;
    }

    /**
     * @dev Throws if the sender is not the owner.
     */
    function _checkOwner() internal view virtual {
        require(owner() == _msgSender(), "Ownable: caller is not the owner");
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


// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v4.7.0) (security/Pausable.sol)

pragma solidity ^0.8.0;

import "../utils/Context.sol";

/**
 * @dev Contract module which allows children to implement an emergency stop
 * mechanism that can be triggered by an authorized account.
 *
 * This module is used through inheritance. It will make available the
 * modifiers `whenNotPaused` and `whenPaused`, which can be applied to
 * the functions of your contract. Note that they will not be pausable by
 * simply including this module, only once the modifiers are put in place.
 */
abstract contract Pausable is Context {
    /**
     * @dev Emitted when the pause is triggered by `account`.
     */
    event Paused(address account);

    /**
     * @dev Emitted when the pause is lifted by `account`.
     */
    event Unpaused(address account);

    bool private _paused;

    /**
     * @dev Initializes the contract in unpaused state.
     */
    constructor() {
        _paused = false;
    }

    /**
     * @dev Modifier to make a function callable only when the contract is not paused.
     *
     * Requirements:
     *
     * - The contract must not be paused.
     */
    modifier whenNotPaused() {
        _requireNotPaused();
        _;
    }

    /**
     * @dev Modifier to make a function callable only when the contract is paused.
     *
     * Requirements:
     *
     * - The contract must be paused.
     */
    modifier whenPaused() {
        _requirePaused();
        _;
    }

    /**
     * @dev Returns true if the contract is paused, and false otherwise.
     */
    function paused() public view virtual returns (bool) {
        return _paused;
    }

    /**
     * @dev Throws if the contract is paused.
     */
    function _requireNotPaused() internal view virtual {
        require(!paused(), "Pausable: paused");
    }

    /**
     * @dev Throws if the contract is not paused.
     */
    function _requirePaused() internal view virtual {
        require(paused(), "Pausable: not paused");
    }

    /**
     * @dev Triggers stopped state.
     *
     * Requirements:
     *
     * - The contract must not be paused.
     */
    function _pause() internal virtual whenNotPaused {
        _paused = true;
        emit Paused(_msgSender());
    }

    /**
     * @dev Returns to normal state.
     *
     * Requirements:
     *
     * - The contract must be paused.
     */
    function _unpause() internal virtual whenPaused {
        _paused = false;
        emit Unpaused(_msgSender());
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
// OpenZeppelin Contracts (last updated v4.7.0) (utils/Strings.sol)

pragma solidity ^0.8.0;

/**
 * @dev String operations.
 */
library Strings {
    bytes16 private constant _HEX_SYMBOLS = "0123456789abcdef";
    uint8 private constant _ADDRESS_LENGTH = 20;

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

    /**
     * @dev Converts an `address` with fixed length of 20 bytes to its not checksummed ASCII `string` hexadecimal representation.
     */
    function toHexString(address addr) internal pure returns (string memory) {
        return toHexString(uint256(uint160(addr)), _ADDRESS_LENGTH);
    }
}


// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts v4.4.1 (utils/introspection/ERC165.sol)

pragma solidity ^0.8.0;

import "./IERC165.sol";

/**
 * @dev Implementation of the {IERC165} interface.
 *
 * Contracts that want to implement ERC165 should inherit from this contract and override {supportsInterface} to check
 * for the additional interface id that will be supported. For example:
 *
 * ```solidity
 * function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
 *     return interfaceId == type(MyInterface).interfaceId || super.supportsInterface(interfaceId);
 * }
 * ```
 *
 * Alternatively, {ERC165Storage} provides an easier to use but more expensive implementation.
 */
abstract contract ERC165 is IERC165 {
    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(IERC165).interfaceId;
    }
}


// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts v4.4.1 (utils/introspection/IERC165.sol)

pragma solidity ^0.8.0;

/**
 * @dev Interface of the ERC165 standard, as defined in the
 * https://eips.ethereum.org/EIPS/eip-165[EIP].
 *
 * Implementers can declare support of contract interfaces, which can then be
 * queried by others ({ERC165Checker}).
 *
 * For an implementation, see {ERC165}.
 */
interface IERC165 {
    /**
     * @dev Returns true if this contract implements the interface defined by
     * `interfaceId`. See the corresponding
     * https://eips.ethereum.org/EIPS/eip-165#how-interfaces-are-identified[EIP section]
     * to learn more about how these ids are created.
     *
     * This function call must use less than 30 000 gas.
     */
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}


// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.4;

library DataStructure {

    

    enum ProjectState {
        FUNDING,
        INSTALLED,
        PRODUCTION,
        CLOSED,
        CANCELLED
    }

    struct Project {
        uint256 idProject;
        uint256 energyTariff;
        uint256 maintenanceTariff;
        uint256 managementTariff;
        uint256 contractTerm;
        uint256 uwattCost;
        uint256 totalUwatts;
        uint256 averageInflationRate;
        ProjectState state;
        address projectAddr;
        address stableAddr;
        address adminAddr;
        string extraData1;
        string extraData2;
    }

    function div(uint256 a, uint256 b) public pure returns(uint256) {
        uint256 value = 10 * a / b;
        unchecked {
            if (value % 10 >= 5) {
                return a / b + 1;
            } else {
                return a / b;
            }
        }
    } 
}


// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "./DataStructure.sol";


contract UnergyData is AccessControl, Pausable, Ownable {

    /// @dev Roles definition
    bytes32 public constant masterRole = keccak256("masterRole");
    bytes32 public constant projectRole = keccak256("projectTokenRole");
    bytes32 public constant userRole = keccak256("userRole");
    bytes32 public constant meterRole = keccak256("meterRole");
    
    /// @dev Variables
    uint256 id;

    /// @dev Mappings
    mapping(address => uint256) public projectAddrToProjectId;
    mapping(address => address[]) public projectHolders;
    mapping(address => bool )public isHolder;
    mapping(address => mapping(address => uint256[2])) public pendingBalances; // [projectAddr][holder][real, accumulate]
    mapping(address => mapping(address => uint256)) public projectAddrToAccEnergy; // [projectAddr][meterAddr]
    mapping(address => uint256) public projectAddrToEnergyPayed;
    mapping(address => bool) public identifiedUser; // Address holder to bool (Identified or not identified)
    mapping(bytes32 => bool) public isRole;
    mapping(address => mapping(address => bool)) public isMeter; // [projectAddr][meterAddr]

    /// @dev Structs
    DataStructure.Project [] public projects;

    
    ///@dev Contract functions
    
    constructor () Ownable() {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        id = 0;
    }

    modifier hasMasterRole(){
        require (
            hasRole (DEFAULT_ADMIN_ROLE, msg.sender) ||
            hasRole (masterRole, msg.sender),
            "Caller is not authorized"
        );
        _;
    }

    
    ///@dev Setter functions
    
    function setProject(DataStructure.Project memory project) 
        public 
        whenNotPaused
        hasMasterRole
        returns (uint256) 
    {
        project.idProject = id;
        projects.push(project);
        projectAddrToProjectId[project.projectAddr] = id;
        id += 1;
        return id;
    }

    function setHolders(address _projectAddr, address _holder)
        public
        whenNotPaused
        hasMasterRole
    {
        address [] storage holders;
        holders  = projectHolders[_projectAddr];
        holders.push(_holder);
    }

    function setPendingBalance(
        address _projectAddr,
        address _holder,
        uint256 _amount
    )
        public
        whenNotPaused
        hasMasterRole 
    {
        pendingBalances[_projectAddr][_holder][0] = _amount;
    }

    function setPendingBalanceAcc(
        address _projectAddr,
        address _holder,
        uint256 _amount
    )
        public
        whenNotPaused
        hasMasterRole
    {
        pendingBalances[_projectAddr][_holder][1] = _amount;
    }

    function setProjectAddrToAccEnergy(
        address _projectAddr,
        address _meterAddr,
        uint256 _accEnergy
    )
        public
        whenNotPaused
        hasMasterRole
    {
        projectAddrToAccEnergy[_projectAddr][_meterAddr] = _accEnergy;
    }

    function setEnergyPayed(address _projectAddr, uint256 _energyPayed) 
        public
        whenNotPaused
        hasMasterRole
    {
        projectAddrToEnergyPayed[_projectAddr] = _energyPayed;
    }

    function updateProject(
        address _projectAddr,
        DataStructure.Project memory project
    )
        public
        whenNotPaused
        hasMasterRole
    {
        uint256 projectId = projectAddrToProjectId[_projectAddr];
        projects[projectId] = project;
    }

    function addMeter(address _projectAddr, address _meterAddr)
        public 
        whenNotPaused
        hasMasterRole
    {
        isMeter[_projectAddr][_meterAddr] = true;
    }

    function deleteMeter(address _projectAddr, address _meterAddr)
        public
        whenNotPaused
        hasMasterRole
    {
        isMeter[_projectAddr][_meterAddr] = false;
    }

    
    ///@dev Getter functions
    
    function getProject(address _projectAddr)
        public
        view
        whenNotPaused
        returns (DataStructure.Project memory project)
    {
        uint256 projectId = projectAddrToProjectId[_projectAddr];
        project = projects[projectId];
    }

    function getProjectId(address _projectAddr)
        public
        view
        whenNotPaused
        returns (uint256 projectId)
    {
        projectId = projectAddrToProjectId[_projectAddr];
    }

    function getEnergyTariff(address _projectAddr)
        public
        view
        whenNotPaused
        returns (uint256 energyTariff)
    {
        uint256 projectId = projectAddrToProjectId[_projectAddr];
        energyTariff = projects[projectId].energyTariff;
    }

    function getMaintenanceTariff(address _projectAddr)
        public
        view
        whenNotPaused
        returns (uint256 maintenanceTariff)
    {
        uint256 projectId = projectAddrToProjectId[_projectAddr];
        maintenanceTariff = projects[projectId].maintenanceTariff;
    }

    function getManagementTariff(address _projectAddr)
        public
        view
        whenNotPaused
        returns (uint256 managementTariff)
    {
        uint256 projectId = projectAddrToProjectId[_projectAddr];
        managementTariff = projects[projectId].managementTariff;
    }

    function getTotalUwatts(address _projectAddr)
        public
        view
        whenNotPaused
        returns (uint256 totalUwatts)
    {
        uint256 projectId = projectAddrToProjectId[_projectAddr];
        totalUwatts = projects[projectId].totalUwatts;
    }

     function getAvgInflationRate(address _projectAddr)
        public
        view
        whenNotPaused
        returns (uint256 averageInflationRate)
    {
        uint256 projectId = projectAddrToProjectId[_projectAddr];
        averageInflationRate = projects[projectId].averageInflationRate;
    }

    function getProjectState(address _projectAddr)
        public
        view
        whenNotPaused
        returns (DataStructure.ProjectState state)
    {
        uint256 projectId = projectAddrToProjectId[_projectAddr];
        state = projects[projectId].state;
    }

    function getStableAddr(address _projectAddr)
        public
        view
        whenNotPaused
        returns (address stableAddr)
    {
        uint256 projectId = projectAddrToProjectId[_projectAddr];
        stableAddr = projects[projectId].stableAddr;
    }

    function getAdminAddr(address _projectAddr)
        public
        view
        whenNotPaused
        returns (address adminAddr)
    {
        uint256 projectId = projectAddrToProjectId[_projectAddr];
        adminAddr = projects[projectId].adminAddr;
    }

    function getExtraData1(address _projectAddr)
        public
        view
        whenNotPaused
        returns (string memory extraData1)
    {
        uint256 projectId = projectAddrToProjectId[_projectAddr];
        extraData1 = projects[projectId].extraData1;
    }

    function getExtraData2(address _projectAddr)
        public
        view
        whenNotPaused
        returns (string memory extraData2)
    {
        uint256 projectId = projectAddrToProjectId[_projectAddr];
        extraData2 = projects[projectId].extraData1;
    }

    function getHolders(address _projectAddr)
        public
        view
        whenNotPaused
        returns (address[] memory)
    {
        address [] memory holders;
        holders  = projectHolders[_projectAddr];
        return holders;
    }

    function getPendingBalance(address _projectAddr, address _holder)
        public
        view
        whenNotPaused
        returns (uint256)
    {
        return(pendingBalances[_projectAddr][_holder][0]);
    }

    function getPendingBalanceAcc(address _projectAddr, address _holder)
        public
        view
        whenNotPaused
        returns (uint256)
    {
        return(pendingBalances[_projectAddr][_holder][1]);
    }

    function getProjectAddrToAccEnergy(address _projectAddr, address _meterAddr)
        public
        view
        whenNotPaused
        returns (uint256)
    {
        return(projectAddrToAccEnergy[_projectAddr][_meterAddr]);
    }

    function getEnergyPayed(address _projectAddr)
        public
        view
        whenNotPaused
        returns (uint256)
    {
        return(projectAddrToEnergyPayed[_projectAddr]);
    }

    function getMeter(address _projectAddr, address _meterAddr)
        public
        view
        whenNotPaused
        returns (bool)
    {
        return(isMeter[_projectAddr][_meterAddr]);
    }


    /// @dev Ownable methods overridden
    function transferOwnership(address newOwner) public override onlyOwner {
        require(newOwner != address(0), "Ownable: new owner cannot be the zero address");
        _transferOwnership(newOwner);
        _setupRole(DEFAULT_ADMIN_ROLE, newOwner);
        renounceRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

}