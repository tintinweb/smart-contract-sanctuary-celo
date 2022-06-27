pragma solidity ^0.5.13;

import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "openzeppelin-solidity/contracts/ownership/Ownable.sol";

import "../common/FixidityLib.sol";
import "../common/Initializable.sol";
import "../common/UsingRegistry.sol";
import "../common/interfaces/ICeloVersionedContract.sol";
import "../common/libraries/ReentrancyGuard.sol";
import "../stability/interfaces/IStableToken.sol";

/**
 * @title Facilitates large exchanges between CELO stable tokens.
 */
contract GrandaMento is
  ICeloVersionedContract,
  Ownable,
  Initializable,
  UsingRegistry,
  ReentrancyGuard
{
  using FixidityLib for FixidityLib.Fraction;
  using SafeMath for uint256;

  // Emitted when a new exchange proposal is created.
  event ExchangeProposalCreated(
    uint256 indexed proposalId,
    address indexed exchanger,
    string stableTokenRegistryId,
    uint256 sellAmount,
    uint256 buyAmount,
    bool sellCelo
  );

  // Emitted when an exchange proposal is approved by the approver.
  event ExchangeProposalApproved(uint256 indexed proposalId);

  // Emitted when an exchange proposal is cancelled.
  event ExchangeProposalCancelled(uint256 indexed proposalId);

  // Emitted when an exchange proposal is executed.
  event ExchangeProposalExecuted(uint256 indexed proposalId);

  // Emitted when the approver is set.
  event ApproverSet(address approver);

  // Emitted when maxApprovalExchangeRateChange is set.
  event MaxApprovalExchangeRateChangeSet(uint256 maxApprovalExchangeRateChange);

  // Emitted when the spread is set.
  event SpreadSet(uint256 spread);

  // Emitted when the veto period in seconds is set.
  event VetoPeriodSecondsSet(uint256 vetoPeriodSeconds);

  // Emitted when the exchange limits for a stable token are set.
  event StableTokenExchangeLimitsSet(
    string stableTokenRegistryId,
    uint256 minExchangeAmount,
    uint256 maxExchangeAmount
  );

  enum ExchangeProposalState { None, Proposed, Approved, Executed, Cancelled }

  struct ExchangeLimits {
    // The minimum amount of an asset that can be exchanged in a single proposal.
    uint256 minExchangeAmount;
    // The maximum amount of an asset that can be exchanged in a single proposal.
    uint256 maxExchangeAmount;
  }

  struct ExchangeProposal {
    // The exchanger/proposer of the exchange proposal.
    address payable exchanger;
    // The stable token involved in this proposal. This is stored rather than
    // the stable token's registry ID in case the contract address is changed
    // after a proposal is created, which could affect refunding or burning the
    // stable token.
    address stableToken;
    // The state of the exchange proposal.
    ExchangeProposalState state;
    // Whether the exchanger is selling CELO and buying stableToken.
    bool sellCelo;
    // The amount of the sell token being sold. If a stable token is being sold,
    // the amount of stable token in "units" is stored rather than the "value."
    // This is because stable tokens may experience demurrage/inflation, where
    // the amount of stable token "units" doesn't change with time, but the "value"
    // does. This is important to ensure the correct inflation-adjusted amount
    // of the stable token is transferred out of this contract when a deposit is
    // refunded or an exchange selling the stable token is executed.
    // See StableToken.sol for more details on what "units" vs "values" are.
    uint256 sellAmount;
    // The amount of the buy token being bought. For stable tokens, this is
    // kept track of as the value, not units.
    uint256 buyAmount;
    // The price of CELO quoted in stableToken at the time of the exchange proposal
    // creation. This is the price used to calculate the buyAmount. Used for a
    // safety check when an approval is being made that the price isn't wildly
    // different. Recalculating buyAmount is not sufficient because if a stable token
    // is being sold that has demurrage enabled, the original value when the stable
    // tokens were deposited cannot be calculated.
    uint256 celoStableTokenExchangeRate;
    // The veto period in seconds at the time the proposal was created. This is kept
    // track of on a per-proposal basis to lock-in the veto period for a proposal so
    // that changes to the contract's vetoPeriodSeconds do not affect existing
    // proposals.
    uint256 vetoPeriodSeconds;
    // The timestamp (`block.timestamp`) at which the exchange proposal was approved
    // in seconds. If the exchange proposal has not ever been approved, is 0.
    uint256 approvalTimestamp;
  }

  // The address with the authority to approve exchange proposals.
  address public approver;

  // The maximum allowed change in the CELO/stable token price when an exchange proposal
  // is being approved relative to the rate when the exchange proposal was created.
  FixidityLib.Fraction public maxApprovalExchangeRateChange;

  // The percent fee imposed upon an exchange execution.
  FixidityLib.Fraction public spread;

  // The period in seconds after an approval during which an exchange proposal can be vetoed.
  uint256 public vetoPeriodSeconds;

  // The minimum and maximum amount of the stable token that can be minted or
  // burned in a single exchange. Indexed by the stable token registry identifier string.
  mapping(string => ExchangeLimits) public stableTokenExchangeLimits;

  // State for all exchange proposals. Indexed by the exchange proposal ID.
  mapping(uint256 => ExchangeProposal) public exchangeProposals;

  // An array containing a superset of the IDs of exchange proposals that are currently
  // in the Proposed or Approved state. Intended to allow easy viewing of all active
  // exchange proposals. It's possible for a proposal ID in this array to no longer be
  // active, so filtering is required to find the true set of active proposal IDs.
  // A superset is kept because exchange proposal vetoes, intended to be done
  // by Governance, effectively go through a multi-day timelock. If the veto
  // call was required to provide the index in an array of activeProposalIds to
  // remove corresponding to the vetoed exchange proposal, the timelock could result
  // in the provided index being stale by the time the veto would be executed.
  // Alternative approaches exist, like maintaining a linkedlist of active proposal
  // IDs, but this approach was chosen for its low implementation complexity.
  uint256[] public activeProposalIdsSuperset;

  // Number of exchange proposals that have ever been created. Used for assigning
  // an exchange proposal ID to a new proposal.
  uint256 public exchangeProposalCount;

  /**
   * @notice Reverts if the sender is not the approver.
   */
  modifier onlyApprover() {
    require(msg.sender == approver, "Sender must be approver");
    _;
  }

  /**
   * @notice Sets initialized == true on implementation contracts.
   * @param test Set to true to skip implementation initialization.
   */
  constructor(bool test) public Initializable(test) {}

  /**
   * @notice Returns the storage, major, minor, and patch version of the contract.
   * @return The storage, major, minor, and patch version of the contract.
   */
  function getVersionNumber() external pure returns (uint256, uint256, uint256, uint256) {
    return (1, 1, 0, 0);
  }

  /**
   * @notice Used in place of the constructor to allow the contract to be upgradable via proxy.
   * @param _registry The address of the registry.
   * @param _approver The approver that has the ability to approve exchange proposals.
   * @param _maxApprovalExchangeRateChange The maximum allowed change in CELO price
   * between an exchange proposal's creation and approval.
   * @param _spread The spread charged on exchanges.
   * @param _vetoPeriodSeconds The length of the veto period in seconds.
   */
  function initialize(
    address _registry,
    address _approver,
    uint256 _maxApprovalExchangeRateChange,
    uint256 _spread,
    uint256 _vetoPeriodSeconds
  ) external initializer {
    _transferOwnership(msg.sender);
    setRegistry(_registry);
    setApprover(_approver);
    setMaxApprovalExchangeRateChange(_maxApprovalExchangeRateChange);
    setSpread(_spread);
    setVetoPeriodSeconds(_vetoPeriodSeconds);
  }

  /**
   * @notice Creates a new exchange proposal and deposits the tokens being sold.
   * @dev Stable token value amounts are used for the sellAmount, not unit amounts.
   * @param stableTokenRegistryId The string registry ID for the stable token
   * involved in the exchange.
   * @param sellAmount The amount of the sell token being sold.
   * @param sellCelo Whether CELO is being sold.
   * @return The proposal identifier for the newly created exchange proposal.
   */
  function createExchangeProposal(
    string calldata stableTokenRegistryId,
    uint256 sellAmount,
    bool sellCelo
  ) external nonReentrant returns (uint256) {
    address stableToken = registry.getAddressForStringOrDie(stableTokenRegistryId);

    // Gets the price of CELO quoted in stableToken.
    uint256 celoStableTokenExchangeRate = getOracleExchangeRate(stableToken).unwrap();

    // Using the current oracle exchange rate, calculate what the buy amount is.
    // This takes the spread into consideration.
    uint256 buyAmount = getBuyAmount(celoStableTokenExchangeRate, sellAmount, sellCelo);

    // Create new scope to prevent a stack too deep error.
    {
      // Get the minimum and maximum amount of stable token than can be involved
      // in the exchange. This reverts if exchange limits for the stable token have
      // not been set.
      (uint256 minExchangeAmount, uint256 maxExchangeAmount) = getStableTokenExchangeLimits(
        stableTokenRegistryId
      );
      // Ensure that the amount of stableToken being bought or sold is within
      // the configurable exchange limits.
      uint256 stableTokenExchangeAmount = sellCelo ? buyAmount : sellAmount;
      require(
        stableTokenExchangeAmount <= maxExchangeAmount &&
          stableTokenExchangeAmount >= minExchangeAmount,
        "Stable token exchange amount not within limits"
      );
    }

    // Deposit the assets being sold.
    IERC20 sellToken = sellCelo ? getGoldToken() : IERC20(stableToken);
    require(
      sellToken.transferFrom(msg.sender, address(this), sellAmount),
      "Transfer in of sell token failed"
    );

    // Record the proposal.
    // Add 1 to the running proposal count, and use the updated proposal count as
    // the proposal ID. Proposal IDs intentionally start at 1.
    exchangeProposalCount = exchangeProposalCount.add(1);
    // For stable tokens, the amount is stored in units to deal with demurrage.
    uint256 storedSellAmount = sellCelo
      ? sellAmount
      : IStableToken(stableToken).valueToUnits(sellAmount);
    exchangeProposals[exchangeProposalCount] = ExchangeProposal({
      exchanger: msg.sender,
      stableToken: stableToken,
      state: ExchangeProposalState.Proposed,
      sellCelo: sellCelo,
      sellAmount: storedSellAmount,
      buyAmount: buyAmount,
      celoStableTokenExchangeRate: celoStableTokenExchangeRate,
      vetoPeriodSeconds: vetoPeriodSeconds,
      approvalTimestamp: 0 // initial value when not approved yet
    });
    // StableToken.unitsToValue (called within getSellTokenAndSellAmount) can
    // overflow for very large StableToken amounts. Call it here as a sanity
    // check, so that the overflow happens here, blocking proposal creation
    // rather than when attempting to execute the proposal, which would lock
    // funds in this contract.
    getSellTokenAndSellAmount(exchangeProposals[exchangeProposalCount]);
    // Push it into the array of active proposals.
    activeProposalIdsSuperset.push(exchangeProposalCount);
    // Even if stable tokens are being sold, the sellAmount emitted is the "value."
    emit ExchangeProposalCreated(
      exchangeProposalCount,
      msg.sender,
      stableTokenRegistryId,
      sellAmount,
      buyAmount,
      sellCelo
    );
    return exchangeProposalCount;
  }

  /**
   * @notice Approves an existing exchange proposal.
   * @dev Sender must be the approver. Exchange proposal must be in the Proposed state.
   * @param proposalId The identifier of the proposal to approve.
   */
  function approveExchangeProposal(uint256 proposalId) external nonReentrant onlyApprover {
    ExchangeProposal storage proposal = exchangeProposals[proposalId];
    // Ensure the proposal is in the Proposed state.
    require(proposal.state == ExchangeProposalState.Proposed, "Proposal must be in Proposed state");
    // Ensure the change in the current price of CELO quoted in the stable token
    // relative to the value when the proposal was created is within the allowed limit.
    FixidityLib.Fraction memory currentRate = getOracleExchangeRate(proposal.stableToken);
    FixidityLib.Fraction memory proposalRate = FixidityLib.wrap(
      proposal.celoStableTokenExchangeRate
    );
    (FixidityLib.Fraction memory lesserRate, FixidityLib.Fraction memory greaterRate) = currentRate
      .lt(proposalRate)
      ? (currentRate, proposalRate)
      : (proposalRate, currentRate);
    FixidityLib.Fraction memory rateChange = greaterRate.subtract(lesserRate).divide(proposalRate);
    require(
      rateChange.lte(maxApprovalExchangeRateChange),
      "CELO exchange rate is too different from the proposed price"
    );

    // Set the time the approval occurred and change the state.
    proposal.approvalTimestamp = block.timestamp;
    proposal.state = ExchangeProposalState.Approved;
    emit ExchangeProposalApproved(proposalId);
  }

  /**
   * @notice Cancels an exchange proposal.
   * @dev Only callable by the exchanger if the proposal is in the Proposed state
   * or the owner if the proposal is in the Approved state.
   * @param proposalId The identifier of the proposal to cancel.
   */
  function cancelExchangeProposal(uint256 proposalId) external nonReentrant {
    ExchangeProposal storage proposal = exchangeProposals[proposalId];
    // Require the appropriate state and sender.
    // This will also revert if a proposalId is given that does not correspond
    // to a previously created exchange proposal.
    if (proposal.state == ExchangeProposalState.Proposed) {
      require(proposal.exchanger == msg.sender, "Sender must be exchanger");
    } else if (proposal.state == ExchangeProposalState.Approved) {
      require(isOwner(), "Sender must be owner");
    } else {
      revert("Proposal must be in Proposed or Approved state");
    }
    // Mark the proposal as cancelled. Do so prior to refunding as a measure against reentrancy.
    proposal.state = ExchangeProposalState.Cancelled;
    // Get the token and amount that will be refunded to the proposer.
    (IERC20 refundToken, uint256 refundAmount) = getSellTokenAndSellAmount(proposal);
    // Finally, transfer out the deposited funds.
    require(
      refundToken.transfer(proposal.exchanger, refundAmount),
      "Transfer out of refund token failed"
    );
    emit ExchangeProposalCancelled(proposalId);
  }

  /**
   * @notice Executes an exchange proposal that's been approved and not vetoed.
   * @dev Callable by anyone. Reverts if the proposal is not in the Approved state
   * or proposal.vetoPeriodSeconds has not elapsed since approval.
   * @param proposalId The identifier of the proposal to execute.
   */
  function executeExchangeProposal(uint256 proposalId) external nonReentrant {
    ExchangeProposal storage proposal = exchangeProposals[proposalId];
    // Require that the proposal is in the Approved state.
    require(proposal.state == ExchangeProposalState.Approved, "Proposal must be in Approved state");
    // Require that the veto period has elapsed since the approval time.
    require(
      proposal.approvalTimestamp.add(proposal.vetoPeriodSeconds) <= block.timestamp,
      "Veto period not elapsed"
    );
    // Mark the proposal as executed. Do so prior to exchanging as a measure against reentrancy.
    proposal.state = ExchangeProposalState.Executed;
    // Perform the exchange.
    (IERC20 sellToken, uint256 sellAmount) = getSellTokenAndSellAmount(proposal);
    // If the exchange sells CELO, the CELO is sent to the Reserve from this contract
    // and stable token is minted to the exchanger.
    if (proposal.sellCelo) {
      // Send the CELO from this contract to the reserve.
      require(
        sellToken.transfer(address(getReserve()), sellAmount),
        "Transfer out of CELO to Reserve failed"
      );
      // Mint stable token to the exchanger.
      require(
        IStableToken(proposal.stableToken).mint(proposal.exchanger, proposal.buyAmount),
        "Stable token mint failed"
      );
    } else {
      // If the exchange is selling stable token, the stable token is burned from
      // this contract and CELO is transferred from the Reserve to the exchanger.

      // Burn the stable token from this contract.
      require(IStableToken(proposal.stableToken).burn(sellAmount), "Stable token burn failed");
      // Transfer the CELO from the Reserve to the exchanger.
      require(
        getReserve().transferExchangeGold(proposal.exchanger, proposal.buyAmount),
        "Transfer out of CELO from Reserve failed"
      );
    }
    emit ExchangeProposalExecuted(proposalId);
  }

  /**
   * @notice Gets the sell token and the sell amount for a proposal.
   * @dev For stable token sell amounts that are stored as units, the value
   * is returned. Ensures sell amount is not greater than this contract's balance.
   * @param proposal The proposal to get the sell token and sell amount for.
   * @return (the IERC20 sell token, the value sell amount).
   */
  function getSellTokenAndSellAmount(ExchangeProposal memory proposal)
    private
    view
    returns (IERC20, uint256)
  {
    IERC20 sellToken;
    uint256 sellAmount;
    if (proposal.sellCelo) {
      sellToken = getGoldToken();
      sellAmount = proposal.sellAmount;
    } else {
      address stableToken = proposal.stableToken;
      sellToken = IERC20(stableToken);
      // When selling stableToken, the sell amount is stored in units.
      // Units must be converted to value when refunding.
      sellAmount = IStableToken(stableToken).unitsToValue(proposal.sellAmount);
    }
    // In the event a precision issue from the unit <-> value calculations results
    // in sellAmount being greater than this contract's balance, set the sellAmount
    // to the entire balance.
    // This check should not be necessary for CELO, but is done so regardless
    // for extra certainty that cancelling an exchange proposal can never fail
    // if for some reason the CELO balance of this contract is less than the
    // recorded sell amount.
    uint256 totalBalance = sellToken.balanceOf(address(this));
    if (totalBalance < sellAmount) {
      sellAmount = totalBalance;
    }
    return (sellToken, sellAmount);
  }

  /**
   * @notice Using the oracle price, charges the spread and calculates the amount of
   * the asset being bought.
   * @dev Stable token value amounts are used for the sellAmount, not unit amounts.
   * Assumes both CELO and the stable token have 18 decimals.
   * @param celoStableTokenExchangeRate The unwrapped fraction exchange rate of CELO
   * quoted in the stable token.
   * @param sellAmount The amount of the sell token being sold.
   * @param sellCelo Whether CELO is being sold.
   * @return The amount of the asset being bought.
   */
  function getBuyAmount(uint256 celoStableTokenExchangeRate, uint256 sellAmount, bool sellCelo)
    public
    view
    returns (uint256)
  {
    FixidityLib.Fraction memory exchangeRate = FixidityLib.wrap(celoStableTokenExchangeRate);
    // If stableToken is being sold, instead use the price of stableToken
    // quoted in CELO.
    if (!sellCelo) {
      exchangeRate = exchangeRate.reciprocal();
    }
    // The sell amount taking the spread into account, ie:
    // (1 - spread) * sellAmount
    FixidityLib.Fraction memory adjustedSellAmount = FixidityLib.fixed1().subtract(spread).multiply(
      FixidityLib.newFixed(sellAmount)
    );
    // Calculate the buy amount:
    // exchangeRate * adjustedSellAmount
    return exchangeRate.multiply(adjustedSellAmount).fromFixed();
  }

  /**
   * @notice Removes the proposal ID found at the provided index of activeProposalIdsSuperset
   * if the exchange proposal is not active.
   * @dev Anyone can call. Reverts if the exchange proposal is active.
   * @param index The index of the proposal ID to remove from activeProposalIdsSuperset.
   */
  function removeFromActiveProposalIdsSuperset(uint256 index) external {
    require(index < activeProposalIdsSuperset.length, "Index out of bounds");
    uint256 proposalId = activeProposalIdsSuperset[index];
    // Require the exchange proposal to be inactive.
    require(
      exchangeProposals[proposalId].state != ExchangeProposalState.Proposed &&
        exchangeProposals[proposalId].state != ExchangeProposalState.Approved,
      "Exchange proposal not inactive"
    );
    // If not removing the last element, overwrite the index with the value of
    // the last element.
    uint256 lastIndex = activeProposalIdsSuperset.length.sub(1);
    if (index < lastIndex) {
      activeProposalIdsSuperset[index] = activeProposalIdsSuperset[lastIndex];
    }
    // Delete the last element.
    activeProposalIdsSuperset.length--;
  }

  /**
   * @notice Gets the proposal identifiers of exchange proposals in the
   * Proposed or Approved state. Returns a version of activeProposalIdsSuperset
   * with inactive proposal IDs set as 0.
   * @dev Elements with a proposal ID of 0 should be filtered out by the consumer.
   * @return An array of active exchange proposals IDs.
   */
  function getActiveProposalIds() external view returns (uint256[] memory) {
    // Solidity doesn't play well with dynamically sized memory arrays.
    // Instead, this array is created with the same length as activeProposalIdsSuperset,
    // and will replace elements that are inactive proposal IDs with the value 0.
    uint256[] memory activeProposalIds = new uint256[](activeProposalIdsSuperset.length);

    for (uint256 i = 0; i < activeProposalIdsSuperset.length; i = i.add(1)) {
      uint256 proposalId = activeProposalIdsSuperset[i];
      if (
        exchangeProposals[proposalId].state == ExchangeProposalState.Proposed ||
        exchangeProposals[proposalId].state == ExchangeProposalState.Approved
      ) {
        activeProposalIds[i] = proposalId;
      }
    }
    return activeProposalIds;
  }

  /**
   * @notice Gets the oracle CELO price quoted in the stable token.
   * @dev Reverts if there is not a rate for the provided stable token.
   * @param stableToken The stable token to get the oracle price for.
   * @return The oracle CELO price quoted in the stable token.
   */
  function getOracleExchangeRate(address stableToken)
    private
    view
    returns (FixidityLib.Fraction memory)
  {
    uint256 rateNumerator;
    uint256 rateDenominator;
    (rateNumerator, rateDenominator) = getSortedOracles().medianRate(stableToken);
    // When rateDenominator is 0, it means there are no rates known to SortedOracles.
    require(rateDenominator > 0, "No oracle rates present for token");
    return FixidityLib.wrap(rateNumerator).divide(FixidityLib.wrap(rateDenominator));
  }

  /**
   * @notice Gets the minimum and maximum amount of a stable token that can be
   * involved in a single exchange.
   * @dev Reverts if there is no explicit exchange limit for the stable token.
   * @param stableTokenRegistryId The string registry ID for the stable token.
   * @return (minimum exchange amount, maximum exchange amount).
   */
  function getStableTokenExchangeLimits(string memory stableTokenRegistryId)
    public
    view
    returns (uint256, uint256)
  {
    ExchangeLimits memory exchangeLimits = stableTokenExchangeLimits[stableTokenRegistryId];
    // Require the configurable stableToken max exchange amount to be > 0.
    // This covers the case where a stableToken has never been explicitly permitted.
    require(
      exchangeLimits.maxExchangeAmount > 0,
      "Max stable token exchange amount must be defined"
    );
    return (exchangeLimits.minExchangeAmount, exchangeLimits.maxExchangeAmount);
  }

  /**
   * @notice Sets the approver.
   * @dev Sender must be owner. New approver is allowed to be address(0).
   * @param newApprover The new value for the approver.
   */
  function setApprover(address newApprover) public onlyOwner {
    approver = newApprover;
    emit ApproverSet(newApprover);
  }

  /**
   * @notice Sets the maximum allowed change in the CELO/stable token price when
   * an exchange proposal is being approved relative to the price when the proposal
   * was created.
   * @dev Sender must be owner.
   * @param newMaxApprovalExchangeRateChange The new value for maxApprovalExchangeRateChange
   * to be wrapped.
   */
  function setMaxApprovalExchangeRateChange(uint256 newMaxApprovalExchangeRateChange)
    public
    onlyOwner
  {
    maxApprovalExchangeRateChange = FixidityLib.wrap(newMaxApprovalExchangeRateChange);
    emit MaxApprovalExchangeRateChangeSet(newMaxApprovalExchangeRateChange);
  }

  /**
   * @notice Sets the spread.
   * @dev Sender must be owner.
   * @param newSpread The new value for the spread to be wrapped. Must be <= fixed 1.
   */
  function setSpread(uint256 newSpread) public onlyOwner {
    require(newSpread <= FixidityLib.fixed1().unwrap(), "Spread must be smaller than 1");
    spread = FixidityLib.wrap(newSpread);
    emit SpreadSet(newSpread);
  }

  /**
   * @notice Sets the minimum and maximum amount of the stable token an exchange can involve.
   * @dev Sender must be owner. Setting the maxExchangeAmount to 0 effectively disables new
   * exchange proposals for the token.
   * @param stableTokenRegistryId The registry ID string for the stable token to set limits for.
   * @param minExchangeAmount The new minimum exchange amount for the stable token.
   * @param maxExchangeAmount The new maximum exchange amount for the stable token.
   */
  function setStableTokenExchangeLimits(
    string calldata stableTokenRegistryId,
    uint256 minExchangeAmount,
    uint256 maxExchangeAmount
  ) external onlyOwner {
    require(
      minExchangeAmount <= maxExchangeAmount,
      "Min exchange amount must not be greater than max"
    );
    stableTokenExchangeLimits[stableTokenRegistryId] = ExchangeLimits({
      minExchangeAmount: minExchangeAmount,
      maxExchangeAmount: maxExchangeAmount
    });
    emit StableTokenExchangeLimitsSet(stableTokenRegistryId, minExchangeAmount, maxExchangeAmount);
  }

  /**
   * @notice Sets the veto period in seconds.
   * @dev Sender must be owner.
   * @param newVetoPeriodSeconds The new value for the veto period in seconds.
   */
  function setVetoPeriodSeconds(uint256 newVetoPeriodSeconds) public onlyOwner {
    // Hardcode a max of 4 weeks.
    // A minimum is not enforced for flexibility. A case of interest is if
    // Governance were to be set as the `approver`, it would be desirable to
    // set the veto period to 0 seconds.
    require(newVetoPeriodSeconds <= 4 weeks, "Veto period cannot exceed 4 weeks");
    vetoPeriodSeconds = newVetoPeriodSeconds;
    emit VetoPeriodSecondsSet(newVetoPeriodSeconds);
  }
}


pragma solidity ^0.5.0;

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


pragma solidity ^0.5.13;

interface IAccounts {
  function isAccount(address) external view returns (bool);
  function voteSignerToAccount(address) external view returns (address);
  function validatorSignerToAccount(address) external view returns (address);
  function attestationSignerToAccount(address) external view returns (address);
  function signerToAccount(address) external view returns (address);
  function getAttestationSigner(address) external view returns (address);
  function getValidatorSigner(address) external view returns (address);
  function getVoteSigner(address) external view returns (address);
  function hasAuthorizedVoteSigner(address) external view returns (bool);
  function hasAuthorizedValidatorSigner(address) external view returns (bool);
  function hasAuthorizedAttestationSigner(address) external view returns (bool);

  function setAccountDataEncryptionKey(bytes calldata) external;
  function setMetadataURL(string calldata) external;
  function setName(string calldata) external;
  function setWalletAddress(address, uint8, bytes32, bytes32) external;
  function setAccount(string calldata, bytes calldata, address, uint8, bytes32, bytes32) external;

  function getDataEncryptionKey(address) external view returns (bytes memory);
  function getWalletAddress(address) external view returns (address);
  function getMetadataURL(address) external view returns (string memory);
  function batchGetMetadataURL(address[] calldata)
    external
    view
    returns (uint256[] memory, bytes memory);
  function getName(address) external view returns (string memory);

  function authorizeVoteSigner(address, uint8, bytes32, bytes32) external;
  function authorizeValidatorSigner(address, uint8, bytes32, bytes32) external;
  function authorizeValidatorSignerWithPublicKey(address, uint8, bytes32, bytes32, bytes calldata)
    external;
  function authorizeValidatorSignerWithKeys(
    address,
    uint8,
    bytes32,
    bytes32,
    bytes calldata,
    bytes calldata,
    bytes calldata
  ) external;
  function authorizeAttestationSigner(address, uint8, bytes32, bytes32) external;
  function createAccount() external returns (bool);
}


pragma solidity ^0.5.0;

import "../GSN/Context.sol";
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


pragma solidity ^0.5.0;

/**
 * @dev Wrappers over Solidity's arithmetic operations with added overflow
 * checks.
 *
 * Arithmetic operations in Solidity wrap on overflow. This can easily result
 * in bugs, because programmers usually assume that an overflow raises an
 * error, which is the standard behavior in high level programming languages.
 * `SafeMath` restores this intuition by reverting the transaction when an
 * operation overflows.
 *
 * Using this library instead of the unchecked operations eliminates an entire
 * class of bugs, so it's recommended to use it always.
 */
library SafeMath {
    /**
     * @dev Returns the addition of two unsigned integers, reverting on
     * overflow.
     *
     * Counterpart to Solidity's `+` operator.
     *
     * Requirements:
     * - Addition cannot overflow.
     */
    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a, "SafeMath: addition overflow");

        return c;
    }

    /**
     * @dev Returns the subtraction of two unsigned integers, reverting on
     * overflow (when the result is negative).
     *
     * Counterpart to Solidity's `-` operator.
     *
     * Requirements:
     * - Subtraction cannot overflow.
     */
    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        return sub(a, b, "SafeMath: subtraction overflow");
    }

    /**
     * @dev Returns the subtraction of two unsigned integers, reverting with custom message on
     * overflow (when the result is negative).
     *
     * Counterpart to Solidity's `-` operator.
     *
     * Requirements:
     * - Subtraction cannot overflow.
     *
     * _Available since v2.4.0._
     */
    function sub(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b <= a, errorMessage);
        uint256 c = a - b;

        return c;
    }

    /**
     * @dev Returns the multiplication of two unsigned integers, reverting on
     * overflow.
     *
     * Counterpart to Solidity's `*` operator.
     *
     * Requirements:
     * - Multiplication cannot overflow.
     */
    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        // Gas optimization: this is cheaper than requiring 'a' not being zero, but the
        // benefit is lost if 'b' is also tested.
        // See: https://github.com/OpenZeppelin/openzeppelin-contracts/pull/522
        if (a == 0) {
            return 0;
        }

        uint256 c = a * b;
        require(c / a == b, "SafeMath: multiplication overflow");

        return c;
    }

    /**
     * @dev Returns the integer division of two unsigned integers. Reverts on
     * division by zero. The result is rounded towards zero.
     *
     * Counterpart to Solidity's `/` operator. Note: this function uses a
     * `revert` opcode (which leaves remaining gas untouched) while Solidity
     * uses an invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     * - The divisor cannot be zero.
     */
    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        return div(a, b, "SafeMath: division by zero");
    }

    /**
     * @dev Returns the integer division of two unsigned integers. Reverts with custom message on
     * division by zero. The result is rounded towards zero.
     *
     * Counterpart to Solidity's `/` operator. Note: this function uses a
     * `revert` opcode (which leaves remaining gas untouched) while Solidity
     * uses an invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     * - The divisor cannot be zero.
     *
     * _Available since v2.4.0._
     */
    function div(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        // Solidity only automatically asserts when dividing by 0
        require(b > 0, errorMessage);
        uint256 c = a / b;
        // assert(a == b * c + a % b); // There is no case in which this doesn't hold

        return c;
    }

    /**
     * @dev Returns the remainder of dividing two unsigned integers. (unsigned integer modulo),
     * Reverts when dividing by zero.
     *
     * Counterpart to Solidity's `%` operator. This function uses a `revert`
     * opcode (which leaves remaining gas untouched) while Solidity uses an
     * invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     * - The divisor cannot be zero.
     */
    function mod(uint256 a, uint256 b) internal pure returns (uint256) {
        return mod(a, b, "SafeMath: modulo by zero");
    }

    /**
     * @dev Returns the remainder of dividing two unsigned integers. (unsigned integer modulo),
     * Reverts with custom message when dividing by zero.
     *
     * Counterpart to Solidity's `%` operator. This function uses a `revert`
     * opcode (which leaves remaining gas untouched) while Solidity uses an
     * invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     * - The divisor cannot be zero.
     *
     * _Available since v2.4.0._
     */
    function mod(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b != 0, errorMessage);
        return a % b;
    }
}


pragma solidity ^0.5.0;

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


pragma solidity ^0.5.13;

/**
 * @title This interface describes the functions specific to Celo Stable Tokens, and in the
 * absence of interface inheritance is intended as a companion to IERC20.sol and ICeloToken.sol.
 */
interface IStableToken {
  function mint(address, uint256) external returns (bool);
  function burn(uint256) external returns (bool);
  function setInflationParameters(uint256, uint256) external;
  function valueToUnits(uint256) external view returns (uint256);
  function unitsToValue(uint256) external view returns (uint256);
  function getInflationParameters() external view returns (uint256, uint256, uint256, uint256);

  // NOTE: duplicated with IERC20.sol, remove once interface inheritance is supported.
  function balanceOf(address) external view returns (uint256);
}


pragma solidity ^0.5.13;

interface ISortedOracles {
  function addOracle(address, address) external;
  function removeOracle(address, address, uint256) external;
  function report(address, uint256, address, address) external;
  function removeExpiredReports(address, uint256) external;
  function isOldestReportExpired(address token) external view returns (bool, address);
  function numRates(address) external view returns (uint256);
  function medianRate(address) external view returns (uint256, uint256);
  function numTimestamps(address) external view returns (uint256);
  function medianTimestamp(address) external view returns (uint256);
}


pragma solidity ^0.5.13;

interface IReserve {
  function setTobinTaxStalenessThreshold(uint256) external;
  function addToken(address) external returns (bool);
  function removeToken(address, uint256) external returns (bool);
  function transferGold(address payable, uint256) external returns (bool);
  function transferExchangeGold(address payable, uint256) external returns (bool);
  function getReserveGoldBalance() external view returns (uint256);
  function getUnfrozenReserveGoldBalance() external view returns (uint256);
  function getOrComputeTobinTax() external returns (uint256, uint256);
  function getTokens() external view returns (address[] memory);
  function getReserveRatio() external view returns (uint256);
  function addExchangeSpender(address) external;
  function removeExchangeSpender(address, uint256) external;
  function addSpender(address) external;
  function removeSpender(address) external;
}


pragma solidity ^0.5.13;

interface IExchange {
  function buy(uint256, uint256, bool) external returns (uint256);
  function sell(uint256, uint256, bool) external returns (uint256);
  function exchange(uint256, uint256, bool) external returns (uint256);
  function setUpdateFrequency(uint256) external;
  function getBuyTokenAmount(uint256, bool) external view returns (uint256);
  function getSellTokenAmount(uint256, bool) external view returns (uint256);
  function getBuyAndSellBuckets(bool) external view returns (uint256, uint256);
}


pragma solidity ^0.5.13;

interface IRandom {
  function revealAndCommit(bytes32, bytes32, address) external;
  function randomnessBlockRetentionWindow() external view returns (uint256);
  function random() external view returns (bytes32);
  function getBlockRandomness(uint256) external view returns (bytes32);
}


pragma solidity ^0.5.13;

interface IAttestations {
  function request(bytes32, uint256, address) external;
  function selectIssuers(bytes32) external;
  function complete(bytes32, uint8, bytes32, bytes32) external;
  function revoke(bytes32, uint256) external;
  function withdraw(address) external;
  function approveTransfer(bytes32, uint256, address, address, bool) external;

  // view functions
  function getUnselectedRequest(bytes32, address) external view returns (uint32, uint32, address);
  function getAttestationIssuers(bytes32, address) external view returns (address[] memory);
  function getAttestationStats(bytes32, address) external view returns (uint32, uint32);
  function batchGetAttestationStats(bytes32[] calldata)
    external
    view
    returns (uint256[] memory, address[] memory, uint64[] memory, uint64[] memory);
  function getAttestationState(bytes32, address, address)
    external
    view
    returns (uint8, uint32, address);
  function getCompletableAttestations(bytes32, address)
    external
    view
    returns (uint32[] memory, address[] memory, uint256[] memory, bytes memory);
  function getAttestationRequestFee(address) external view returns (uint256);
  function getMaxAttestations() external view returns (uint256);
  function validateAttestationCode(bytes32, address, uint8, bytes32, bytes32)
    external
    view
    returns (address);
  function lookupAccountsForIdentifier(bytes32) external view returns (address[] memory);
  function requireNAttestationsRequested(bytes32, address, uint32) external view;

  // only owner
  function setAttestationRequestFee(address, uint256) external;
  function setAttestationExpiryBlocks(uint256) external;
  function setSelectIssuersWaitBlocks(uint256) external;
  function setMaxAttestations(uint256) external;
}


pragma solidity ^0.5.13;

interface IValidators {
  function registerValidator(bytes calldata, bytes calldata, bytes calldata)
    external
    returns (bool);
  function deregisterValidator(uint256) external returns (bool);
  function affiliate(address) external returns (bool);
  function deaffiliate() external returns (bool);
  function updateBlsPublicKey(bytes calldata, bytes calldata) external returns (bool);
  function registerValidatorGroup(uint256) external returns (bool);
  function deregisterValidatorGroup(uint256) external returns (bool);
  function addMember(address) external returns (bool);
  function addFirstMember(address, address, address) external returns (bool);
  function removeMember(address) external returns (bool);
  function reorderMember(address, address, address) external returns (bool);
  function updateCommission() external;
  function setNextCommissionUpdate(uint256) external;
  function resetSlashingMultiplier() external;

  // only owner
  function setCommissionUpdateDelay(uint256) external;
  function setMaxGroupSize(uint256) external returns (bool);
  function setMembershipHistoryLength(uint256) external returns (bool);
  function setValidatorScoreParameters(uint256, uint256) external returns (bool);
  function setGroupLockedGoldRequirements(uint256, uint256) external returns (bool);
  function setValidatorLockedGoldRequirements(uint256, uint256) external returns (bool);
  function setSlashingMultiplierResetPeriod(uint256) external;

  // view functions
  function getMaxGroupSize() external view returns (uint256);
  function getCommissionUpdateDelay() external view returns (uint256);
  function getValidatorScoreParameters() external view returns (uint256, uint256);
  function getMembershipHistory(address)
    external
    view
    returns (uint256[] memory, address[] memory, uint256, uint256);
  function calculateEpochScore(uint256) external view returns (uint256);
  function calculateGroupEpochScore(uint256[] calldata) external view returns (uint256);
  function getAccountLockedGoldRequirement(address) external view returns (uint256);
  function meetsAccountLockedGoldRequirements(address) external view returns (bool);
  function getValidatorBlsPublicKeyFromSigner(address) external view returns (bytes memory);
  function getValidator(address account)
    external
    view
    returns (bytes memory, bytes memory, address, uint256, address);
  function getValidatorGroup(address)
    external
    view
    returns (address[] memory, uint256, uint256, uint256, uint256[] memory, uint256, uint256);
  function getGroupNumMembers(address) external view returns (uint256);
  function getTopGroupValidators(address, uint256) external view returns (address[] memory);
  function getGroupsNumMembers(address[] calldata accounts)
    external
    view
    returns (uint256[] memory);
  function getNumRegisteredValidators() external view returns (uint256);
  function groupMembershipInEpoch(address, uint256, uint256) external view returns (address);

  // only registered contract
  function updateEcdsaPublicKey(address, address, bytes calldata) external returns (bool);
  function updatePublicKeys(address, address, bytes calldata, bytes calldata, bytes calldata)
    external
    returns (bool);
  function getValidatorLockedGoldRequirements() external view returns (uint256, uint256);
  function getGroupLockedGoldRequirements() external view returns (uint256, uint256);
  function getRegisteredValidators() external view returns (address[] memory);
  function getRegisteredValidatorSigners() external view returns (address[] memory);
  function getRegisteredValidatorGroups() external view returns (address[] memory);
  function isValidatorGroup(address) external view returns (bool);
  function isValidator(address) external view returns (bool);
  function getValidatorGroupSlashingMultiplier(address) external view returns (uint256);
  function getMembershipInLastEpoch(address) external view returns (address);
  function getMembershipInLastEpochFromSigner(address) external view returns (address);

  // only VM
  function updateValidatorScoreFromSigner(address, uint256) external;
  function distributeEpochPaymentsFromSigner(address, uint256) external returns (uint256);

  // only slasher
  function forceDeaffiliateIfValidator(address) external;
  function halveSlashingMultiplier(address) external;

}


pragma solidity ^0.5.13;

interface ILockedGold {
  function incrementNonvotingAccountBalance(address, uint256) external;
  function decrementNonvotingAccountBalance(address, uint256) external;
  function getAccountTotalLockedGold(address) external view returns (uint256);
  function getTotalLockedGold() external view returns (uint256);
  function getPendingWithdrawals(address)
    external
    view
    returns (uint256[] memory, uint256[] memory);
  function getTotalPendingWithdrawals(address) external view returns (uint256);
  function lock() external payable;
  function unlock(uint256) external;
  function relock(uint256, uint256) external;
  function withdraw(uint256) external;
  function slash(
    address account,
    uint256 penalty,
    address reporter,
    uint256 reward,
    address[] calldata lessers,
    address[] calldata greaters,
    uint256[] calldata indices
  ) external;
  function isSlasher(address) external view returns (bool);
}


pragma solidity ^0.5.13;

interface IGovernance {
  function isVoting(address) external view returns (bool);
}


pragma solidity ^0.5.13;

interface IElection {
  function electValidatorSigners() external view returns (address[] memory);
  function electNValidatorSigners(uint256, uint256) external view returns (address[] memory);
  function vote(address, uint256, address, address) external returns (bool);
  function activate(address) external returns (bool);
  function revokeActive(address, uint256, address, address, uint256) external returns (bool);
  function revokeAllActive(address, address, address, uint256) external returns (bool);
  function revokePending(address, uint256, address, address, uint256) external returns (bool);
  function markGroupIneligible(address) external;
  function markGroupEligible(address, address, address) external;
  function forceDecrementVotes(
    address,
    uint256,
    address[] calldata,
    address[] calldata,
    uint256[] calldata
  ) external returns (uint256);

  // view functions
  function getElectableValidators() external view returns (uint256, uint256);
  function getElectabilityThreshold() external view returns (uint256);
  function getNumVotesReceivable(address) external view returns (uint256);
  function getTotalVotes() external view returns (uint256);
  function getActiveVotes() external view returns (uint256);
  function getTotalVotesByAccount(address) external view returns (uint256);
  function getPendingVotesForGroupByAccount(address, address) external view returns (uint256);
  function getActiveVotesForGroupByAccount(address, address) external view returns (uint256);
  function getTotalVotesForGroupByAccount(address, address) external view returns (uint256);
  function getActiveVoteUnitsForGroupByAccount(address, address) external view returns (uint256);
  function getTotalVotesForGroup(address) external view returns (uint256);
  function getActiveVotesForGroup(address) external view returns (uint256);
  function getPendingVotesForGroup(address) external view returns (uint256);
  function getGroupEligibility(address) external view returns (bool);
  function getGroupEpochRewards(address, uint256, uint256[] calldata)
    external
    view
    returns (uint256);
  function getGroupsVotedForByAccount(address) external view returns (address[] memory);
  function getEligibleValidatorGroups() external view returns (address[] memory);
  function getTotalVotesForEligibleValidatorGroups()
    external
    view
    returns (address[] memory, uint256[] memory);
  function getCurrentValidatorSigners() external view returns (address[] memory);
  function canReceiveVotes(address, uint256) external view returns (bool);
  function hasActivatablePendingVotes(address, address) external view returns (bool);

  // only owner
  function setElectableValidators(uint256, uint256) external returns (bool);
  function setMaxNumGroupsVotedFor(uint256) external returns (bool);
  function setElectabilityThreshold(uint256) external returns (bool);

  // only VM
  function distributeEpochRewards(address, uint256, address, address) external;
}


pragma solidity ^0.5.13;

/**
 * @title Helps contracts guard against reentrancy attacks.
 * @author Remco Bloemen <[email protected]π.com>, Eenae <[email protected]>
 * @dev If you mark a function `nonReentrant`, you should also
 * mark it `external`.
 */
contract ReentrancyGuard {
  /// @dev counter to allow mutex lock with only one SSTORE operation
  uint256 private _guardCounter;

  constructor() internal {
    // The counter starts at one to prevent changing it from zero to a non-zero
    // value, which is a more expensive operation.
    _guardCounter = 1;
  }

  /**
   * @dev Prevents a contract from calling itself, directly or indirectly.
   * Calling a `nonReentrant` function from another `nonReentrant`
   * function is not supported. It is possible to prevent this from happening
   * by making the `nonReentrant` function external, and make it call a
   * `private` function that does the actual work.
   */
  modifier nonReentrant() {
    _guardCounter += 1;
    uint256 localCounter = _guardCounter;
    _;
    require(localCounter == _guardCounter, "reentrant call");
  }
}


pragma solidity ^0.5.13;

interface IRegistry {
  function setAddressFor(string calldata, address) external;
  function getAddressForOrDie(bytes32) external view returns (address);
  function getAddressFor(bytes32) external view returns (address);
  function getAddressForStringOrDie(string calldata identifier) external view returns (address);
  function getAddressForString(string calldata identifier) external view returns (address);
  function isOneOf(bytes32[] calldata, address) external view returns (bool);
}


pragma solidity ^0.5.13;

interface IFreezer {
  function isFrozen(address) external view returns (bool);
}


pragma solidity ^0.5.13;

interface IFeeCurrencyWhitelist {
  function addToken(address) external;
  function getWhitelist() external view returns (address[] memory);
}


pragma solidity ^0.5.13;

interface ICeloVersionedContract {
  /**
   * @notice Returns the storage, major, minor, and patch version of the contract.
   * @return The storage, major, minor, and patch version of the contract.
   */
  function getVersionNumber() external pure returns (uint256, uint256, uint256, uint256);
}


pragma solidity ^0.5.13;

import "openzeppelin-solidity/contracts/ownership/Ownable.sol";
import "openzeppelin-solidity/contracts/token/ERC20/IERC20.sol";

import "./interfaces/IAccounts.sol";
import "./interfaces/IFeeCurrencyWhitelist.sol";
import "./interfaces/IFreezer.sol";
import "./interfaces/IRegistry.sol";

import "../governance/interfaces/IElection.sol";
import "../governance/interfaces/IGovernance.sol";
import "../governance/interfaces/ILockedGold.sol";
import "../governance/interfaces/IValidators.sol";

import "../identity/interfaces/IRandom.sol";
import "../identity/interfaces/IAttestations.sol";

import "../stability/interfaces/IExchange.sol";
import "../stability/interfaces/IReserve.sol";
import "../stability/interfaces/ISortedOracles.sol";
import "../stability/interfaces/IStableToken.sol";

contract UsingRegistry is Ownable {
  event RegistrySet(address indexed registryAddress);

  // solhint-disable state-visibility
  bytes32 constant ACCOUNTS_REGISTRY_ID = keccak256(abi.encodePacked("Accounts"));
  bytes32 constant ATTESTATIONS_REGISTRY_ID = keccak256(abi.encodePacked("Attestations"));
  bytes32 constant DOWNTIME_SLASHER_REGISTRY_ID = keccak256(abi.encodePacked("DowntimeSlasher"));
  bytes32 constant DOUBLE_SIGNING_SLASHER_REGISTRY_ID = keccak256(
    abi.encodePacked("DoubleSigningSlasher")
  );
  bytes32 constant ELECTION_REGISTRY_ID = keccak256(abi.encodePacked("Election"));
  bytes32 constant EXCHANGE_REGISTRY_ID = keccak256(abi.encodePacked("Exchange"));
  bytes32 constant FEE_CURRENCY_WHITELIST_REGISTRY_ID = keccak256(
    abi.encodePacked("FeeCurrencyWhitelist")
  );
  bytes32 constant FREEZER_REGISTRY_ID = keccak256(abi.encodePacked("Freezer"));
  bytes32 constant GOLD_TOKEN_REGISTRY_ID = keccak256(abi.encodePacked("GoldToken"));
  bytes32 constant GOVERNANCE_REGISTRY_ID = keccak256(abi.encodePacked("Governance"));
  bytes32 constant GOVERNANCE_SLASHER_REGISTRY_ID = keccak256(
    abi.encodePacked("GovernanceSlasher")
  );
  bytes32 constant LOCKED_GOLD_REGISTRY_ID = keccak256(abi.encodePacked("LockedGold"));
  bytes32 constant RESERVE_REGISTRY_ID = keccak256(abi.encodePacked("Reserve"));
  bytes32 constant RANDOM_REGISTRY_ID = keccak256(abi.encodePacked("Random"));
  bytes32 constant SORTED_ORACLES_REGISTRY_ID = keccak256(abi.encodePacked("SortedOracles"));
  bytes32 constant STABLE_TOKEN_REGISTRY_ID = keccak256(abi.encodePacked("StableToken"));
  bytes32 constant VALIDATORS_REGISTRY_ID = keccak256(abi.encodePacked("Validators"));
  // solhint-enable state-visibility

  IRegistry public registry;

  modifier onlyRegisteredContract(bytes32 identifierHash) {
    require(registry.getAddressForOrDie(identifierHash) == msg.sender, "only registered contract");
    _;
  }

  modifier onlyRegisteredContracts(bytes32[] memory identifierHashes) {
    require(registry.isOneOf(identifierHashes, msg.sender), "only registered contracts");
    _;
  }

  /**
   * @notice Updates the address pointing to a Registry contract.
   * @param registryAddress The address of a registry contract for routing to other contracts.
   */
  function setRegistry(address registryAddress) public onlyOwner {
    require(registryAddress != address(0), "Cannot register the null address");
    registry = IRegistry(registryAddress);
    emit RegistrySet(registryAddress);
  }

  function getAccounts() internal view returns (IAccounts) {
    return IAccounts(registry.getAddressForOrDie(ACCOUNTS_REGISTRY_ID));
  }

  function getAttestations() internal view returns (IAttestations) {
    return IAttestations(registry.getAddressForOrDie(ATTESTATIONS_REGISTRY_ID));
  }

  function getElection() internal view returns (IElection) {
    return IElection(registry.getAddressForOrDie(ELECTION_REGISTRY_ID));
  }

  function getExchange() internal view returns (IExchange) {
    return IExchange(registry.getAddressForOrDie(EXCHANGE_REGISTRY_ID));
  }

  function getFeeCurrencyWhitelistRegistry() internal view returns (IFeeCurrencyWhitelist) {
    return IFeeCurrencyWhitelist(registry.getAddressForOrDie(FEE_CURRENCY_WHITELIST_REGISTRY_ID));
  }

  function getFreezer() internal view returns (IFreezer) {
    return IFreezer(registry.getAddressForOrDie(FREEZER_REGISTRY_ID));
  }

  function getGoldToken() internal view returns (IERC20) {
    return IERC20(registry.getAddressForOrDie(GOLD_TOKEN_REGISTRY_ID));
  }

  function getGovernance() internal view returns (IGovernance) {
    return IGovernance(registry.getAddressForOrDie(GOVERNANCE_REGISTRY_ID));
  }

  function getLockedGold() internal view returns (ILockedGold) {
    return ILockedGold(registry.getAddressForOrDie(LOCKED_GOLD_REGISTRY_ID));
  }

  function getRandom() internal view returns (IRandom) {
    return IRandom(registry.getAddressForOrDie(RANDOM_REGISTRY_ID));
  }

  function getReserve() internal view returns (IReserve) {
    return IReserve(registry.getAddressForOrDie(RESERVE_REGISTRY_ID));
  }

  function getSortedOracles() internal view returns (ISortedOracles) {
    return ISortedOracles(registry.getAddressForOrDie(SORTED_ORACLES_REGISTRY_ID));
  }

  function getStableToken() internal view returns (IStableToken) {
    return IStableToken(registry.getAddressForOrDie(STABLE_TOKEN_REGISTRY_ID));
  }

  function getValidators() internal view returns (IValidators) {
    return IValidators(registry.getAddressForOrDie(VALIDATORS_REGISTRY_ID));
  }
}


pragma solidity ^0.5.13;

contract Initializable {
  bool public initialized;

  constructor(bool testingDeployment) public {
    if (!testingDeployment) {
      initialized = true;
    }
  }

  modifier initializer() {
    require(!initialized, "contract already initialized");
    initialized = true;
    _;
  }
}


pragma solidity ^0.5.13;

/**
 * @title FixidityLib
 * @author Gadi Guy, Alberto Cuesta Canada
 * @notice This library provides fixed point arithmetic with protection against
 * overflow.
 * All operations are done with uint256 and the operands must have been created
 * with any of the newFrom* functions, which shift the comma digits() to the
 * right and check for limits, or with wrap() which expects a number already
 * in the internal representation of a fraction.
 * When using this library be sure to use maxNewFixed() as the upper limit for
 * creation of fixed point numbers.
 * @dev All contained functions are pure and thus marked internal to be inlined
 * on consuming contracts at compile time for gas efficiency.
 */
library FixidityLib {
  struct Fraction {
    uint256 value;
  }

  /**
   * @notice Number of positions that the comma is shifted to the right.
   */
  function digits() internal pure returns (uint8) {
    return 24;
  }

  uint256 private constant FIXED1_UINT = 1000000000000000000000000;

  /**
   * @notice This is 1 in the fixed point units used in this library.
   * @dev Test fixed1() equals 10^digits()
   * Hardcoded to 24 digits.
   */
  function fixed1() internal pure returns (Fraction memory) {
    return Fraction(FIXED1_UINT);
  }

  /**
   * @notice Wrap a uint256 that represents a 24-decimal fraction in a Fraction
   * struct.
   * @param x Number that already represents a 24-decimal fraction.
   * @return A Fraction struct with contents x.
   */
  function wrap(uint256 x) internal pure returns (Fraction memory) {
    return Fraction(x);
  }

  /**
   * @notice Unwraps the uint256 inside of a Fraction struct.
   */
  function unwrap(Fraction memory x) internal pure returns (uint256) {
    return x.value;
  }

  /**
   * @notice The amount of decimals lost on each multiplication operand.
   * @dev Test mulPrecision() equals sqrt(fixed1)
   */
  function mulPrecision() internal pure returns (uint256) {
    return 1000000000000;
  }

  /**
   * @notice Maximum value that can be converted to fixed point. Optimize for deployment.
   * @dev
   * Test maxNewFixed() equals maxUint256() / fixed1()
   */
  function maxNewFixed() internal pure returns (uint256) {
    return 115792089237316195423570985008687907853269984665640564;
  }

  /**
   * @notice Converts a uint256 to fixed point Fraction
   * @dev Test newFixed(0) returns 0
   * Test newFixed(1) returns fixed1()
   * Test newFixed(maxNewFixed()) returns maxNewFixed() * fixed1()
   * Test newFixed(maxNewFixed()+1) fails
   */
  function newFixed(uint256 x) internal pure returns (Fraction memory) {
    require(x <= maxNewFixed(), "can't create fixidity number larger than maxNewFixed()");
    return Fraction(x * FIXED1_UINT);
  }

  /**
   * @notice Converts a uint256 in the fixed point representation of this
   * library to a non decimal. All decimal digits will be truncated.
   */
  function fromFixed(Fraction memory x) internal pure returns (uint256) {
    return x.value / FIXED1_UINT;
  }

  /**
   * @notice Converts two uint256 representing a fraction to fixed point units,
   * equivalent to multiplying dividend and divisor by 10^digits().
   * @param numerator numerator must be <= maxNewFixed()
   * @param denominator denominator must be <= maxNewFixed() and denominator can't be 0
   * @dev
   * Test newFixedFraction(1,0) fails
   * Test newFixedFraction(0,1) returns 0
   * Test newFixedFraction(1,1) returns fixed1()
   * Test newFixedFraction(1,fixed1()) returns 1
   */
  function newFixedFraction(uint256 numerator, uint256 denominator)
    internal
    pure
    returns (Fraction memory)
  {
    Fraction memory convertedNumerator = newFixed(numerator);
    Fraction memory convertedDenominator = newFixed(denominator);
    return divide(convertedNumerator, convertedDenominator);
  }

  /**
   * @notice Returns the integer part of a fixed point number.
   * @dev
   * Test integer(0) returns 0
   * Test integer(fixed1()) returns fixed1()
   * Test integer(newFixed(maxNewFixed())) returns maxNewFixed()*fixed1()
   */
  function integer(Fraction memory x) internal pure returns (Fraction memory) {
    return Fraction((x.value / FIXED1_UINT) * FIXED1_UINT); // Can't overflow
  }

  /**
   * @notice Returns the fractional part of a fixed point number.
   * In the case of a negative number the fractional is also negative.
   * @dev
   * Test fractional(0) returns 0
   * Test fractional(fixed1()) returns 0
   * Test fractional(fixed1()-1) returns 10^24-1
   */
  function fractional(Fraction memory x) internal pure returns (Fraction memory) {
    return Fraction(x.value - (x.value / FIXED1_UINT) * FIXED1_UINT); // Can't overflow
  }

  /**
   * @notice x+y.
   * @dev The maximum value that can be safely used as an addition operator is defined as
   * maxFixedAdd = maxUint256()-1 / 2, or
   * 57896044618658097711785492504343953926634992332820282019728792003956564819967.
   * Test add(maxFixedAdd,maxFixedAdd) equals maxFixedAdd + maxFixedAdd
   * Test add(maxFixedAdd+1,maxFixedAdd+1) throws
   */
  function add(Fraction memory x, Fraction memory y) internal pure returns (Fraction memory) {
    uint256 z = x.value + y.value;
    require(z >= x.value, "add overflow detected");
    return Fraction(z);
  }

  /**
   * @notice x-y.
   * @dev
   * Test subtract(6, 10) fails
   */
  function subtract(Fraction memory x, Fraction memory y) internal pure returns (Fraction memory) {
    require(x.value >= y.value, "substraction underflow detected");
    return Fraction(x.value - y.value);
  }

  /**
   * @notice x*y. If any of the operators is higher than the max multiplier value it
   * might overflow.
   * @dev The maximum value that can be safely used as a multiplication operator
   * (maxFixedMul) is calculated as sqrt(maxUint256()*fixed1()),
   * or 340282366920938463463374607431768211455999999999999
   * Test multiply(0,0) returns 0
   * Test multiply(maxFixedMul,0) returns 0
   * Test multiply(0,maxFixedMul) returns 0
   * Test multiply(fixed1()/mulPrecision(),fixed1()*mulPrecision()) returns fixed1()
   * Test multiply(maxFixedMul,maxFixedMul) is around maxUint256()
   * Test multiply(maxFixedMul+1,maxFixedMul+1) fails
   */
  function multiply(Fraction memory x, Fraction memory y) internal pure returns (Fraction memory) {
    if (x.value == 0 || y.value == 0) return Fraction(0);
    if (y.value == FIXED1_UINT) return x;
    if (x.value == FIXED1_UINT) return y;

    // Separate into integer and fractional parts
    // x = x1 + x2, y = y1 + y2
    uint256 x1 = integer(x).value / FIXED1_UINT;
    uint256 x2 = fractional(x).value;
    uint256 y1 = integer(y).value / FIXED1_UINT;
    uint256 y2 = fractional(y).value;

    // (x1 + x2) * (y1 + y2) = (x1 * y1) + (x1 * y2) + (x2 * y1) + (x2 * y2)
    uint256 x1y1 = x1 * y1;
    if (x1 != 0) require(x1y1 / x1 == y1, "overflow x1y1 detected");

    // x1y1 needs to be multiplied back by fixed1
    // solium-disable-next-line mixedcase
    uint256 fixed_x1y1 = x1y1 * FIXED1_UINT;
    if (x1y1 != 0) require(fixed_x1y1 / x1y1 == FIXED1_UINT, "overflow x1y1 * fixed1 detected");
    x1y1 = fixed_x1y1;

    uint256 x2y1 = x2 * y1;
    if (x2 != 0) require(x2y1 / x2 == y1, "overflow x2y1 detected");

    uint256 x1y2 = x1 * y2;
    if (x1 != 0) require(x1y2 / x1 == y2, "overflow x1y2 detected");

    x2 = x2 / mulPrecision();
    y2 = y2 / mulPrecision();
    uint256 x2y2 = x2 * y2;
    if (x2 != 0) require(x2y2 / x2 == y2, "overflow x2y2 detected");

    // result = fixed1() * x1 * y1 + x1 * y2 + x2 * y1 + x2 * y2 / fixed1();
    Fraction memory result = Fraction(x1y1);
    result = add(result, Fraction(x2y1)); // Add checks for overflow
    result = add(result, Fraction(x1y2)); // Add checks for overflow
    result = add(result, Fraction(x2y2)); // Add checks for overflow
    return result;
  }

  /**
   * @notice 1/x
   * @dev
   * Test reciprocal(0) fails
   * Test reciprocal(fixed1()) returns fixed1()
   * Test reciprocal(fixed1()*fixed1()) returns 1 // Testing how the fractional is truncated
   * Test reciprocal(1+fixed1()*fixed1()) returns 0 // Testing how the fractional is truncated
   * Test reciprocal(newFixedFraction(1, 1e24)) returns newFixed(1e24)
   */
  function reciprocal(Fraction memory x) internal pure returns (Fraction memory) {
    require(x.value != 0, "can't call reciprocal(0)");
    return Fraction((FIXED1_UINT * FIXED1_UINT) / x.value); // Can't overflow
  }

  /**
   * @notice x/y. If the dividend is higher than the max dividend value, it
   * might overflow. You can use multiply(x,reciprocal(y)) instead.
   * @dev The maximum value that can be safely used as a dividend (maxNewFixed) is defined as
   * divide(maxNewFixed,newFixedFraction(1,fixed1())) is around maxUint256().
   * This yields the value 115792089237316195423570985008687907853269984665640564.
   * Test maxNewFixed equals maxUint256()/fixed1()
   * Test divide(maxNewFixed,1) equals maxNewFixed*(fixed1)
   * Test divide(maxNewFixed+1,multiply(mulPrecision(),mulPrecision())) throws
   * Test divide(fixed1(),0) fails
   * Test divide(maxNewFixed,1) = maxNewFixed*(10^digits())
   * Test divide(maxNewFixed+1,1) throws
   */
  function divide(Fraction memory x, Fraction memory y) internal pure returns (Fraction memory) {
    require(y.value != 0, "can't divide by 0");
    uint256 X = x.value * FIXED1_UINT;
    require(X / FIXED1_UINT == x.value, "overflow at divide");
    return Fraction(X / y.value);
  }

  /**
   * @notice x > y
   */
  function gt(Fraction memory x, Fraction memory y) internal pure returns (bool) {
    return x.value > y.value;
  }

  /**
   * @notice x >= y
   */
  function gte(Fraction memory x, Fraction memory y) internal pure returns (bool) {
    return x.value >= y.value;
  }

  /**
   * @notice x < y
   */
  function lt(Fraction memory x, Fraction memory y) internal pure returns (bool) {
    return x.value < y.value;
  }

  /**
   * @notice x <= y
   */
  function lte(Fraction memory x, Fraction memory y) internal pure returns (bool) {
    return x.value <= y.value;
  }

  /**
   * @notice x == y
   */
  function equals(Fraction memory x, Fraction memory y) internal pure returns (bool) {
    return x.value == y.value;
  }

  /**
   * @notice x <= 1
   */
  function isProperFraction(Fraction memory x) internal pure returns (bool) {
    return lte(x, fixed1());
  }
}