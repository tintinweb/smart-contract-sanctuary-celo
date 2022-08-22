// SPDX-License-Identifier: Apache-2.0
// https://docs.soliditylang.org/en/v0.8.10/style-guide.html
pragma solidity ^0.8.10;

import "lib/forge-std/src/console.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {PausableUpgradeable} from "lib/openzeppelin-contracts-upgradeable/contracts/security/PausableUpgradeable.sol";
import {OwnableUpgradeable} from "lib/openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "lib/openzeppelin-contracts-upgradeable/contracts/security/ReentrancyGuardUpgradeable.sol";
import {ImpactVault} from "src/grants/ImpactVault.sol";
import {ImpactVaultManager} from "src/grants/ImpactVaultManager.sol";
import {SpiralsRegistry} from "src/grants/SpiralsRegistry.sol";
import {IRegistry} from "src/interfaces/IRegistry.sol";
import {IManager} from "src/interfaces/IManager.sol";
import {SafeERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

struct StakedGrant {
    ImpactVault ownerVault;
    ImpactVault beneficiaryVault;
    mapping(address => StakedGrantToken) tokens;
}

struct StakedGrantToken {
    uint256 allocated; // total approved for grantee
    uint256 disbursed;
}

/// @title StakedGrantManager
///
/// @author @douglasqian
contract StakedGrantManager is
    OwnableUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeERC20 for IERC20;

    /*
     * EVENTS
     */
    event StakedGrantCreated(
        bytes32 indexed id,
        address indexed ownerVault,
        address indexed beneficiaryVault,
        uint96 _externalGrantId
    );
    event StakedGrantFunded(
        bytes32 indexed id,
        address indexed token,
        uint256 amount
    );
    event StakedFundsDisbursed(
        bytes32 indexed id,
        address indexed token,
        uint256 amount
    );
    event DependenciesUpdated(address spiralsRegistry);

    /*
     * STATE VARIABLES
     */
    SpiralsRegistry public c_spiralsRegistry;
    // keccak256(ownerVault, beneficiaryVault) -> info
    mapping(bytes32 => StakedGrant) internal grants;

    /*
     * INITIALIZERS
     */
    constructor() {}

    function initialize(address _registryAddress) external initializer {
        __Ownable_init();
        __Pausable_init();
        __ReentrancyGuard_init();
        // Ensures that `_owner` is set.
        setDependencies(_registryAddress);
    }

    function setDependencies(address _registryAddress)
        public
        onlyOwner
        whenNotPaused
    {
        c_spiralsRegistry = SpiralsRegistry(_registryAddress);
        emit DependenciesUpdated(_registryAddress);
    }

    /*
     * CREATE
     */
    function createGrant(address _beneficiary, uint96 _externalGrantId)
        external
        whenNotPaused
        returns (bytes32 id)
    {
        // Get ImpactVault addresses for owner & beneficiary.
        // Create them if they don't exist yet.
        ImpactVaultManager vaultMgr = getImpactVaultManager();
        address _owner = msg.sender;

        bytes32 ownerVaultId = vaultMgr.getOwnerVaultId(_owner, _beneficiary);
        ImpactVault ownerVault = vaultMgr._getVault(ownerVaultId);

        if (address(ownerVault) == address(0)) {
            ownerVault = vaultMgr.createOwnerVault(_owner, _beneficiary);
        }
        bytes32 beneficiaryVaultId = vaultMgr.getBeneficiaryVaultId(
            _beneficiary
        );
        ImpactVault beneficiaryVault = vaultMgr._getVault(beneficiaryVaultId);
        if (address(beneficiaryVault) == address(0)) {
            beneficiaryVault = vaultMgr.createBeneficiaryVault(_beneficiary);
        }
        id = _getGrantId(address(ownerVault), address(beneficiaryVault));

        StakedGrant storage grant = grants[id];
        grant.ownerVault = ownerVault;
        grant.beneficiaryVault = beneficiaryVault;

        emit StakedGrantCreated(
            id,
            address(ownerVault),
            address(beneficiaryVault),
            _externalGrantId
        );
    }

    /*
     * FUND
     */
    function fundGrant(
        bytes32 _id,
        address _token,
        uint256 _amount
    ) external payable whenNotPaused {
        StakedGrant storage grant = grants[_id];
        require(
            address(grant.ownerVault) != address(0),
            "GRANT_NOT_CREATED_YET"
        );
        IERC20(_token).transferFrom(
            msg.sender,
            address(grant.ownerVault),
            _amount
        );
        grant.ownerVault.stake(_token, _amount);
        grant.tokens[_token].allocated += _amount;

        emit StakedGrantFunded(_id, _token, _amount);
    }

    function disburseFunds(
        bytes32 _id,
        address _token,
        uint256 _amount
    ) external whenNotPaused {
        StakedGrant storage grant = grants[_id];
        require(
            address(grant.ownerVault) != address(0),
            "GRANT_NOT_CREATED_YET"
        );
        require(msg.sender == grant.ownerVault.owner(), "NOT_VAULT_OWNER");
        (uint256 principalBalance, ) = grant.ownerVault.tokens(_token);
        require(_amount <= principalBalance, "NOT_ENOUGH_IN_OWNER_VAULT");

        grant.ownerVault.transferPrincipal(
            _token,
            _amount,
            address(grant.beneficiaryVault)
        );
        grant.beneficiaryVault.setPrincipalBalance(
            _token,
            grant.beneficiaryVault.getPrincipal(_token) + _amount
        );
        grant.tokens[_token].disbursed += _amount;

        emit StakedFundsDisbursed(_id, _token, _amount);
    }

    /*
     * HELPER
     */
    function getGrantTokenInfo(bytes32 _id, address _token)
        public
        view
        returns (uint256, uint256)
    {
        return (
            grants[_id].tokens[_token].allocated,
            grants[_id].tokens[_token].disbursed
        );
    }

    function getGrantId(address _owner, address _beneficiary)
        public
        view
        returns (bytes32)
    {
        ImpactVaultManager vaultMgr = getImpactVaultManager();
        ImpactVault ownerVault = vaultMgr.getOwnerVault(_owner, _beneficiary);
        ImpactVault beneficiaryVault = vaultMgr.getBeneficiaryVault(
            _beneficiary
        );
        return _getGrantId(address(ownerVault), address(beneficiaryVault));
    }

    function _getGrantId(address _ownerVault, address _beneficiaryVault)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(abi.encodePacked(_ownerVault, _beneficiaryVault));
    }

    function getImpactVaultManager() public view returns (ImpactVaultManager) {
        return
            ImpactVaultManager(
                c_spiralsRegistry.getAddressForStringOrDie(
                    "spirals.ImpactVaultManager"
                )
            );
    }

    function getStakedCeloManager() internal view returns (IManager) {
        return
            IManager(
                c_spiralsRegistry.getAddressForStringOrDie("stCELO.Manager")
            );
    }

    function getCeloRegistry() internal view returns (IRegistry) {
        return
            IRegistry(
                c_spiralsRegistry.getAddressForStringOrDie(
                    "celo.SpiralsRegistry"
                )
            );
    }

    function getGoldToken() internal view returns (IERC20) {
        return IERC20(getCeloRegistry().getAddressForStringOrDie("GoldToken"));
    }

    function getStableToken() internal view returns (IERC20) {
        return
            IERC20(getCeloRegistry().getAddressForStringOrDie("StableToken"));
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }
}