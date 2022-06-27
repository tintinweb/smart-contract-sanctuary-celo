// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "./interface/IPriceOracle.sol";
import "./interface/ICreditManager.sol";
import "./interface/ICreditRoles.sol";
import "./interface/ICreditPool.sol";
import "../Network/interface/ICIP36.sol";

contract CreditManager is OwnableUpgradeable, PausableUpgradeable, ICreditManager {
    /* ========== CONSTANTS ========== */

    uint32 private constant MAX_PPM = 1000000;
    uint32 private constant MIN_PPT = 1000;

    /* ========== STATE VARIABLES ========== */

    IERC20 public collateralToken;
    ICreditRoles public creditRoles;
    IPriceOracle public oracle;
    uint256 public totalStakedCollateral;
    uint256 public minLTV;
    uint256 public creditLineExpiration;
    // network => member => creditline
    mapping(address => mapping(address => CreditLine)) public creditLines;
    // poolAddress => pool
    mapping(address => bool) public pools;

    /* ========== INITIALIZER ========== */

    function initialize(
        address collateralTokenAddress,
        address _creditRoles,
        address _oracle
    ) external virtual initializer {
        collateralToken = IERC20(collateralTokenAddress);
        creditRoles = ICreditRoles(_creditRoles);
        oracle = IPriceOracle(_oracle);
        _setMinLTV(200000);
        _setCreditLineExpirationDays(180 days);
        __Ownable_init();
        __Pausable_init();
    }

    /* ========== PUBLIC FUNCTIONS ========== */

    function createCreditLine(
        address _networkMember,
        address _pool,
        uint256 _creditLimit,
        address _network
    )
        external
        override
        onlyOperator
        onlyRegisteredNetwork(_network)
        onlyRegisteredPool(_pool)
        onlyNewCreditLine(_network, _networkMember)
    {
        creditLines[_network][_networkMember] = CreditLine(_pool, block.timestamp, _creditLimit);
        ICreditPool(_pool).increaseTotalCredit(_creditLimit);
        totalStakedCollateral += _creditLimit;
        ICIP36(_network).setCreditLimit(_networkMember, _creditLimit);
        emit CreditLineCreated(_network, _networkMember, _pool, _creditLimit, block.timestamp);
    }

    function registerCreditPool(address _pool) external onlyOperator {
        address underwriter = ICreditPool(_pool).getUnderwriter();
        require(
            creditRoles.isUnderwriter(underwriter),
            "CreditManager: pool underwriter is invalid"
        );
        pools[_pool] = true;
        emit CreditPoolAdded(_pool, underwriter);
    }

    function extendCreditLine(
        address _network,
        address _networkMember,
        uint256 _creditLimit
    ) external override onlyOperator creditLineExists(_network, _networkMember) {
        uint256 curCreditLimit = ICIP36(_network).creditLimitOf(_networkMember);
        require(curCreditLimit < _creditLimit, "CreditManager: Invalid credit limit");
        CreditLine storage creditLine = creditLines[_network][_networkMember];
        ICreditPool(creditLine.creditPool).increaseTotalCredit(_creditLimit - curCreditLimit);
        totalStakedCollateral += _creditLimit - curCreditLimit;
        creditLine.creditLimit = _creditLimit;
        ICIP36(_network).setCreditLimit(_networkMember, _creditLimit);
        emit CreditLineLimitUpdated(_network, _networkMember, _creditLimit);
    }

    function swapCreditLinePool(
        address _network,
        address _networkMember,
        address _pool
    )
        external
        override
        onlyOperator
        onlyRegisteredPool(_pool)
        creditLineExists(_network, _networkMember)
    {
        CreditLine storage creditLine = creditLines[_network][_networkMember];
        ICreditPool(creditLine.creditPool).reduceTotalCredit(creditLine.creditLimit);
        ICreditPool(_pool).increaseTotalCredit(creditLine.creditLimit);
        creditLine.creditPool = _pool;
        emit CreditLinePoolUpdated(_network, _networkMember, _pool);
    }

    function closeCreditLine(address _network, address _networkMember)
        external
        onlyExpiredCreditLine(_network, _networkMember)
        onlyZeroBalance(_network, _networkMember)
    {
        CreditLine memory creditLine = creditLines[_network][_networkMember];
        address underwriter = ICreditPool(creditLine.creditPool).getUnderwriter();
        require(
            underwriter == msg.sender || msg.sender == _networkMember,
            "CreditManager: caller is not underwriter or network member"
        );
        ICreditPool(creditLine.creditPool).reduceTotalCredit(
            ICIP36(_network).creditLimitOf(_networkMember)
        );
        ICIP36(_network).setCreditLimit(_networkMember, 0);
        ICreditPool(creditLine.creditPool).reduceTotalCredit(creditLine.creditLimit);
        totalStakedCollateral -= creditLine.creditLimit;
        delete creditLines[_network][_networkMember];
        emit CreditLineRemoved(_network, _networkMember);
    }

    function renewCreditLine(address _network, address _networkMember)
        external
        override
        onlyOperator
    {
        creditLines[_network][_networkMember].issueDate = block.timestamp;
        emit CreditLineRenewed(_network, _networkMember, block.timestamp);
    }

    /* ========== VIEWS ========== */

    function isPoolValidLTV(address _network, address _pool) public view override returns (bool) {
        uint256 LTV = calculatePoolLTV(_network, _pool);
        return LTV >= minLTV;
    }

    function calculatePoolLTV(address _network, address _pool) public view returns (uint256) {
        uint256 collateral = ICreditPool(_pool).totalSupply();
        if (collateral == 0) return 0;

        uint256 creditInCollateralUnits = convertNetworkToCollateral(
            _network,
            ICreditPool(_pool).getTotalCredit()
        );

        return ((collateral * MAX_PPM) / creditInCollateralUnits);
    }

    function calculatePercentInCollateral(
        address _networkToken,
        uint256 _percent,
        uint256 _amount
    ) public view override returns (uint256) {
        uint256 collateralAmount = convertNetworkToCollateral(_networkToken, _amount);
        return ((_percent * collateralAmount) / MAX_PPM);
    }

    function isCreditLineExpired(address _network, address _networkMember)
        public
        view
        override
        returns (bool)
    {
        CreditLine memory creditLine = creditLines[_network][_networkMember];
        return creditLine.issueDate + creditLineExpiration < block.timestamp;
    }

    function getCollateralToken() external view override returns (address) {
        return address(collateralToken);
    }

    function getMinLTV() external view override returns (uint256) {
        return minLTV;
    }

    function getCreditLine(address _network, address _networkMember)
        public
        view
        override
        returns (CreditLine memory)
    {
        return creditLines[_network][_networkMember];
    }

    function getCreditLineUnderwriter(address _network, address _networkMember)
        public
        view
        override
        returns (address)
    {
        address pool = creditLines[_network][_networkMember].creditPool;
        if (pool == address(0)) return pool;
        return ICreditPool(pool).getUnderwriter();
    }

    function getNeededCollateral(address _network, address _networkMember)
        external
        view
        override
        returns (uint256)
    {
        address pool = creditLines[_network][_networkMember].creditPool;
        if (isPoolValidLTV(_network, pool)) return 0;
        uint256 totalCredit = ICreditPool(pool).getTotalCredit();
        uint256 creditInCollateral = convertNetworkToCollateral(_network, totalCredit);
        uint256 minimumCollateral = (creditInCollateral * minLTV) / MAX_PPM;
        return minimumCollateral - ICreditPool(pool).totalSupply();
    }

    function convertNetworkToCollateral(address _network, uint256 _amount)
        public
        view
        override
        returns (uint256)
    {
        uint256 collateralDecimals = IERC20Metadata(address(collateralToken)).decimals();
        uint256 networkDecimals = IERC20Metadata(_network).decimals();
        if (networkDecimals < collateralDecimals) {
            uint256 delta = collateralDecimals - networkDecimals;
            return ((_amount * 10**delta) / oracle.getPriceInPPT()) * MIN_PPT;
        } else {
            uint256 delta = networkDecimals - collateralDecimals;
            return ((_amount / 10**delta) / oracle.getPriceInPPT()) * MIN_PPT;
        }
    }

    /* ========== PRIVATE FUNCTIONS ========== */

    function _setMinLTV(uint32 _percentage) private {
        require(_percentage <= MAX_PPM, ">percentage");
        minLTV = _percentage;
    }

    function _setCreditLineExpirationDays(uint32 _days) private {
        require(_days >= 1 days, "expiration day must be greater than 0");
        creditLineExpiration = _days;
    }

    /* ========== MODIFIERS ========== */

    modifier onlyOperator() {
        require(
            creditRoles.isCreditOperator(msg.sender),
            "CreditManager: Caller must be an operator"
        );
        _;
    }

    modifier onlyNewCreditLine(address _network, address _networkMember) {
        require(
            creditLines[_network][_networkMember].issueDate == 0,
            "CreditManager: Credit line already exists for network member"
        );
        _;
    }

    modifier creditLineExists(address _network, address _networkMember) {
        require(
            creditLines[_network][_networkMember].issueDate > 0,
            "CreditManager: Credit line does not exist for network member"
        );
        _;
    }

    modifier onlyExpiredCreditLine(address _network, address _networkMember) {
        require(
            isCreditLineExpired(_network, _networkMember),
            "CreditManager: Can't close active credit line"
        );
        _;
    }

    modifier onlyZeroBalance(address _network, address _networkMember) {
        require(
            ICIP36(_network).creditBalanceOf(_networkMember) == 0,
            "CreditManager: Line of Credit has outstanding balance"
        );
        _;
    }

    modifier onlyUnderwriter(address _underwriter) {
        require(
            creditRoles.isUnderwriter(_underwriter),
            "CreditManager: Underwriter address is not authorized"
        );
        _;
    }

    modifier onlyRegisteredNetwork(address _network) {
        require(
            creditRoles.isNetwork(_network),
            "CreditManager: Network token address is not registered"
        );
        _;
    }

    modifier onlyRegisteredPool(address _pool) {
        require(pools[_pool], "CreditManager: Pool is not registered");
        _;
    }
}


// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ICIP36 {
    function creditBalanceOf(address _member) external view returns (uint256);

    function creditLimitOf(address _member) external view returns (uint256);

    function creditLimitLeftOf(address _member) external view returns (uint256);

    function setCreditLimit(address _member, uint256 _limit) external;

    function canRequestCredit(address _requester, address _member) external returns (bool);
}


// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IPriceOracle {
    function getPriceInPPT() external view returns (uint256);
}


// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ICreditRoles {
    event UnderwriterAdded(address underwriter);

    event UnderwriterRemoved(address underwriter);

    function grantUnderwriter(address _underwriter) external;

    function revokeUnderwriter(address _underwriter) external;

    function grantNetwork(address _network) external;

    function revokeNetwork(address _network) external;

    function isUnderwriter(address _underwriter) external view returns (bool);

    function isNetwork(address _network) external view returns (bool);

    function isCreditOperator(address _operator) external view returns (bool);

    function isRequestOperator(address _operator) external returns (bool);

    function grantRequestOperator(address _requestOperator) external;

    function revokeRequestOperator(address _requestOperator) external;
}


// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ICreditPool {
    function notifyRewardAmount(address _rewardsToken, uint256 reward) external;

    function totalSupply() external view returns (uint256);

    function stakeFor(address _staker, uint256 _amount) external;

    function balanceOf(address _account) external view returns (uint256);

    function reduceTotalCredit(uint256 _amountToAdd) external;

    function increaseTotalCredit(uint256 _amountToRemove) external;

    function getUnderwriter() external view returns (address);

    function getTotalCredit() external view returns (uint256);
}


// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ICreditManager {
    struct CreditLine {
        address creditPool;
        uint256 issueDate;
        uint256 creditLimit;
    }

    event CreditLineCreated(
        address network,
        address networkMember,
        address pool,
        uint256 creditLimit,
        uint256 timestamp
    );

    event CreditPoolAdded(address pool, address underwriter);

    event CreditLineLimitUpdated(address network, address networkMember, uint256 creditLimit);

    event CreditLinePoolUpdated(address network, address networkMember, address pool);

    event CreditLineRemoved(address network, address networkMember);

    event CreditLineRenewed(address network, address networkMember, uint256 timestamp);

    function createCreditLine(
        address _networkMember,
        address _pool,
        uint256 _creditLimit,
        address _network
    ) external;

    function getCollateralToken() external returns (address);

    function getMinLTV() external returns (uint256);

    function getCreditLine(address _network, address _networkMember)
        external
        returns (CreditLine memory);

    function getCreditLineUnderwriter(address _network, address _networkMember)
        external
        returns (address);

    function isPoolValidLTV(address _network, address _networkMember) external returns (bool);

    function isCreditLineExpired(address _network, address _networkMember) external returns (bool);

    function swapCreditLinePool(
        address _network,
        address _networkMember,
        address _pool
    ) external;

    function extendCreditLine(
        address _network,
        address _networkMember,
        uint256 _creditLimit
    ) external;

    function convertNetworkToCollateral(address _network, uint256 _amount)
        external
        returns (uint256);

    function renewCreditLine(address _network, address _networkMember) external;

    function getNeededCollateral(address _network, address _networkMember)
        external
        returns (uint256);

    function calculatePercentInCollateral(
        address _networkToken,
        uint256 _percent,
        uint256 _amount
    ) external view returns (uint256);
}


// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts v4.4.1 (utils/Context.sol)

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
    function __Context_init() internal onlyInitializing {
    }

    function __Context_init_unchained() internal onlyInitializing {
    }
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        return msg.data;
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[50] private __gap;
}


// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v4.5.0) (utils/Address.sol)

pragma solidity ^0.8.1;

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
     *
     * [IMPORTANT]
     * ====
     * You shouldn't rely on `isContract` to protect against flash loan attacks!
     *
     * Preventing calls from contracts is highly discouraged. It breaks composability, breaks support for smart wallets
     * like Gnosis Safe, and does not provide security since it can be circumvented by calling from a contract
     * constructor.
     * ====
     */
    function isContract(address account) internal view returns (bool) {
        // This method relies on extcodesize/address.code.length, which returns 0
        // for contracts in construction, since the code is only stored at the end
        // of the constructor execution.

        return account.code.length > 0;
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
// OpenZeppelin Contracts v4.4.1 (security/Pausable.sol)

pragma solidity ^0.8.0;

import "../utils/ContextUpgradeable.sol";
import "../proxy/utils/Initializable.sol";

/**
 * @dev Contract module which allows children to implement an emergency stop
 * mechanism that can be triggered by an authorized account.
 *
 * This module is used through inheritance. It will make available the
 * modifiers `whenNotPaused` and `whenPaused`, which can be applied to
 * the functions of your contract. Note that they will not be pausable by
 * simply including this module, only once the modifiers are put in place.
 */
abstract contract PausableUpgradeable is Initializable, ContextUpgradeable {
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
    function __Pausable_init() internal onlyInitializing {
        __Pausable_init_unchained();
    }

    function __Pausable_init_unchained() internal onlyInitializing {
        _paused = false;
    }

    /**
     * @dev Returns true if the contract is paused, and false otherwise.
     */
    function paused() public view virtual returns (bool) {
        return _paused;
    }

    /**
     * @dev Modifier to make a function callable only when the contract is not paused.
     *
     * Requirements:
     *
     * - The contract must not be paused.
     */
    modifier whenNotPaused() {
        require(!paused(), "Pausable: paused");
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
        require(paused(), "Pausable: not paused");
        _;
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

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[49] private __gap;
}


// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v4.5.0) (proxy/utils/Initializable.sol)

pragma solidity ^0.8.0;

import "../../utils/AddressUpgradeable.sol";

/**
 * @dev This is a base contract to aid in writing upgradeable contracts, or any kind of contract that will be deployed
 * behind a proxy. Since proxied contracts do not make use of a constructor, it's common to move constructor logic to an
 * external initializer function, usually called `initialize`. It then becomes necessary to protect this initializer
 * function so it can only be called once. The {initializer} modifier provided by this contract will have this effect.
 *
 * TIP: To avoid leaving the proxy in an uninitialized state, the initializer function should be called as early as
 * possible by providing the encoded function call as the `_data` argument to {ERC1967Proxy-constructor}.
 *
 * CAUTION: When used with inheritance, manual care must be taken to not invoke a parent initializer twice, or to ensure
 * that all initializers are idempotent. This is not verified automatically as constructors are by Solidity.
 *
 * [CAUTION]
 * ====
 * Avoid leaving a contract uninitialized.
 *
 * An uninitialized contract can be taken over by an attacker. This applies to both a proxy and its implementation
 * contract, which may impact the proxy. To initialize the implementation contract, you can either invoke the
 * initializer manually, or you can include a constructor to automatically mark it as initialized when it is deployed:
 *
 * [.hljs-theme-light.nopadding]
 * ```
 * /// @custom:oz-upgrades-unsafe-allow constructor
 * constructor() initializer {}
 * ```
 * ====
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
        // If the contract is initializing we ignore whether _initialized is set in order to support multiple
        // inheritance patterns, but we only do this in the context of a constructor, because in other contexts the
        // contract may have been reentered.
        require(_initializing ? _isConstructor() : !_initialized, "Initializable: contract is already initialized");

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

    /**
     * @dev Modifier to protect an initialization function so that it can only be invoked by functions with the
     * {initializer} modifier, directly or indirectly.
     */
    modifier onlyInitializing() {
        require(_initializing, "Initializable: contract is not initializing");
        _;
    }

    function _isConstructor() private view returns (bool) {
        return !AddressUpgradeable.isContract(address(this));
    }
}


// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts v4.4.1 (access/Ownable.sol)

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
    function __Ownable_init() internal onlyInitializing {
        __Ownable_init_unchained();
    }

    function __Ownable_init_unchained() internal onlyInitializing {
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

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[49] private __gap;
}


// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts v4.4.1 (token/ERC20/extensions/IERC20Metadata.sol)

pragma solidity ^0.8.0;

import "../IERC20.sol";

/**
 * @dev Interface for the optional metadata functions from the ERC20 standard.
 *
 * _Available since v4.1._
 */
interface IERC20Metadata is IERC20 {
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
// OpenZeppelin Contracts (last updated v4.5.0) (token/ERC20/IERC20.sol)

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
     * @dev Moves `amount` tokens from the caller's account to `to`.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transfer(address to, uint256 amount) external returns (bool);

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
     * @dev Moves `amount` tokens from `from` to `to` using the
     * allowance mechanism. `amount` is then deducted from the caller's
     * allowance.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transferFrom(
        address from,
        address to,
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