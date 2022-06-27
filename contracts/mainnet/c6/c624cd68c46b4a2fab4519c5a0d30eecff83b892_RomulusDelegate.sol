// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "@ubeswap/governance/contracts/interfaces/IHasVotes.sol";
import "./RomulusInterfaces.sol";

contract RomulusDelegate is RomulusDelegateStorageV1, RomulusEvents, Initializable {
  /// @notice The name of this contract
  string public constant name = "Romulus";

  /// @notice The minimum setable proposal threshold
  uint256 public constant MIN_PROPOSAL_THRESHOLD = 1000000e18; // 1,000,000 Tokens

  /// @notice The maximum setable proposal threshold
  uint256 public constant MAX_PROPOSAL_THRESHOLD = 5000000e18; // 5,000,000 Tokens

  /// @notice The minimum setable voting period
  uint256 public constant MIN_VOTING_PERIOD = 17280; // About 24 hours

  /// @notice The max setable voting period
  uint256 public constant MAX_VOTING_PERIOD = 241920; // About 2 weeks

  /// @notice The min setable voting delay
  uint256 public constant MIN_VOTING_DELAY = 1;

  /// @notice The max setable voting delay
  uint256 public constant MAX_VOTING_DELAY = 120960; // About 1 week

  /// @notice The number of votes in support of a proposal required in order for a quorum to be reached and for a vote to succeed
  uint256 public constant quorumVotes = 4000000e18; // 4,000,000 Tokens

  /// @notice The maximum number of actions that can be included in a proposal
  uint256 public constant proposalMaxOperations = 10; // 10 actions

  /// @notice The EIP-712 typehash for the contract's domain
  bytes32 public constant DOMAIN_TYPEHASH = keccak256("EIP712Domain(string name,uint256 chainId,address verifyingContract)");

  /// @notice The EIP-712 typehash for the ballot struct used by the contract
  bytes32 public constant BALLOT_TYPEHASH = keccak256("Ballot(uint256 proposalId,uint8 support)");

  modifier adminOnly() {
    require(msg.sender == admin, "Only admin can call");
    _;
  }

  /**
   * @notice Used to initialize the contract during delegator contructor
   * @param timelock_ The address of the Timelock
   * @param token_ The address of the voting token
   * @param releaseToken_ The address of the "Release" voting token. If none, specify the zero address.
   * @param votingPeriod_ The initial voting period
   * @param votingDelay_ The initial voting delay
   * @param proposalThreshold_ The initial proposal threshold
   */
  function initialize(
    address timelock_,
    address token_,
    address releaseToken_,
    uint256 votingPeriod_,
    uint256 votingDelay_,
    uint256 proposalThreshold_
  ) public initializer adminOnly {
    require(TimelockInterface(timelock_).admin() == address(this), "Romulus::initialize: timelock admin is not assigned to RomulusDelegate");
    require(
      votingPeriod_ >= MIN_VOTING_PERIOD && votingPeriod_ <= MAX_VOTING_PERIOD,
      "Romulus::initialize: invalid voting period"
    );
    require(votingDelay_ >= MIN_VOTING_DELAY && votingDelay_ <= MAX_VOTING_DELAY, "Romulus::initialize: invalid voting delay");
    require(
      proposalThreshold_ >= MIN_PROPOSAL_THRESHOLD && proposalThreshold_ <= MAX_PROPOSAL_THRESHOLD,
      "Romulus::initialize: invalid proposal threshold"
    );
    timelock = TimelockInterface(timelock_);
    require(timelock.admin() == address(this), "Romulus::initialize: timelock admin is not assigned to RomulusDelegate");

    admin = msg.sender;
    token = IHasVotes(token_);
    releaseToken = IHasVotes(releaseToken_);
    votingPeriod = votingPeriod_;
    votingDelay = votingDelay_;
    proposalThreshold = proposalThreshold_;

    // Create dummy proposal
    Proposal memory dummyProposal =
      Proposal({
        id: proposalCount,
        proposer: address(this),
        eta: 0,
        startBlock: 0,
        endBlock: 0,
        forVotes: 0,
        againstVotes: 0,
        abstainVotes: 0,
        canceled: true,
        executed: false
      });
    proposalCount++;

    proposals[dummyProposal.id] = dummyProposal;
    latestProposalIds[dummyProposal.proposer] = dummyProposal.id;

    emit ProposalCreated(
      dummyProposal.id,
      address(this),
      proposalTargets[dummyProposal.id],
      proposalValues[dummyProposal.id],
      proposalSignatures[dummyProposal.id],
      proposalCalldatas[dummyProposal.id],
      0,
      0,
      ""
    );
  }

  /**
   * @notice Function used to propose a new proposal. Sender must have delegates above the proposal threshold.
   * @param targets Target addresses for proposal calls.
   * @param values Eth values for proposal calls.
   * @param signatures Function signatures for proposal calls.
   * @param calldatas Calldatas for proposal calls.
   * @param description String description of the proposal.
   * @return Proposal id of new proposal.
   */
  function propose(
    address[] memory targets,
    uint256[] memory values,
    string[] memory signatures,
    bytes[] memory calldatas,
    string memory description
  ) public returns (uint256) {
    require(
      getPriorVotes(msg.sender, sub256(block.number, 1)) > proposalThreshold,
      "Romulus::propose: proposer votes below proposal threshold"
    );
    require(
      targets.length == values.length && targets.length == signatures.length && targets.length == calldatas.length,
      "Romulus::propose: proposal function information arity mismatch"
    );
    require(targets.length != 0, "Romulus::propose: must provide actions");
    require(targets.length <= proposalMaxOperations, "Romulus::propose: too many actions");

    uint256 latestProposalId = latestProposalIds[msg.sender];
    if (latestProposalId != 0) {
      ProposalState proposersLatestProposalState = state(latestProposalId);
      require(
        proposersLatestProposalState != ProposalState.Active,
        "Romulus::propose: one live proposal per proposer, found an already active proposal"
      );
      require(
        proposersLatestProposalState != ProposalState.Pending,
        "Romulus::propose: one live proposal per proposer, found an already pending proposal"
      );
    }

    uint256 startBlock = add256(block.number, votingDelay);
    uint256 endBlock = add256(startBlock, votingPeriod);

    Proposal memory newProposal =
      Proposal({
        id: proposalCount,
        proposer: msg.sender,
        eta: 0,
        startBlock: startBlock,
        endBlock: endBlock,
        forVotes: 0,
        againstVotes: 0,
        abstainVotes: 0,
        canceled: false,
        executed: false
      });
    proposalCount++;

    proposals[newProposal.id] = newProposal;
    proposalTargets[newProposal.id] = targets;
    proposalValues[newProposal.id] = values;
    proposalSignatures[newProposal.id] = signatures;
    proposalCalldatas[newProposal.id] = calldatas;
    latestProposalIds[newProposal.proposer] = newProposal.id;

    emit ProposalCreated(newProposal.id, msg.sender, targets, values, signatures, calldatas, startBlock, endBlock, description);
    return newProposal.id;
  }

  /**
   * @notice Queues a proposal of state succeeded
   * @param proposalId The id of the proposal to queue
   */
  function queue(uint256 proposalId) external {
    require(state(proposalId) == ProposalState.Succeeded, "Romulus::queue: proposal can only be queued if it is succeeded");
    Proposal storage proposal = proposals[proposalId];
    uint256 eta = add256(block.timestamp, timelock.delay());
    for (uint256 i = 0; i < proposalTargets[proposalId].length; i++) {
      queueOrRevertInternal(
        proposalTargets[proposalId][i],
        proposalValues[proposalId][i],
        proposalSignatures[proposalId][i],
        proposalCalldatas[proposalId][i],
        eta
      );
    }
    proposal.eta = eta;
    emit ProposalQueued(proposalId, eta);
  }

  function queueOrRevertInternal(
    address target,
    uint256 value,
    string memory signature,
    bytes memory data,
    uint256 eta
  ) internal {
    require(
      !timelock.queuedTransactions(keccak256(abi.encode(target, value, signature, data, eta))),
      "Romulus::queueOrRevertInternal: identical proposal action already queued at eta"
    );
    timelock.queueTransaction(target, value, signature, data, eta);
  }

  /**
   * @notice Executes a queued proposal if eta has passed
   * @param proposalId The id of the proposal to execute
   */
  function execute(uint256 proposalId) external payable {
    require(state(proposalId) == ProposalState.Queued, "Romulus::execute: proposal can only be executed if it is queued");
    Proposal storage proposal = proposals[proposalId];
    proposal.executed = true;
    for (uint256 i = 0; i < proposalTargets[proposalId].length; i++) {
      timelock.executeTransaction{ value: proposalValues[proposalId][i] }(
        proposalTargets[proposalId][i],
        proposalValues[proposalId][i],
        proposalSignatures[proposalId][i],
        proposalCalldatas[proposalId][i],
        proposal.eta
      );
    }
    emit ProposalExecuted(proposalId);
  }

  /**
   * @notice Cancels a proposal only if sender is the proposer, or proposer delegates dropped below proposal threshold
   * @param proposalId The id of the proposal to cancel
   */
  function cancel(uint256 proposalId) external {
    require(state(proposalId) != ProposalState.Executed, "Romulus::cancel: cannot cancel executed proposal");

    Proposal storage proposal = proposals[proposalId];
    require(
      msg.sender == proposal.proposer || getPriorVotes(proposal.proposer, sub256(block.number, 1)) < proposalThreshold,
      "Romulus::cancel: proposer above threshold"
    );

    proposal.canceled = true;
    for (uint256 i = 0; i < proposalTargets[proposalId].length; i++) {
      timelock.cancelTransaction(
        proposalTargets[proposalId][i],
        proposalValues[proposalId][i],
        proposalSignatures[proposalId][i],
        proposalCalldatas[proposalId][i],
        proposal.eta
      );
    }

    emit ProposalCanceled(proposalId);
  }

  /**
   * @notice Gets actions of a proposal.
   * @param proposalId Proposal to query.
   * @return targets Target addresses for proposal calls.
   * @return values Eth values for proposal calls.
   * @return signatures Function signatures for proposal calls.
   * @return calldatas Calldatas for proposal calls.
   */
  function getActions(uint256 proposalId)
    external
    view
    returns (
      address[] memory targets,
      uint256[] memory values,
      string[] memory signatures,
      bytes[] memory calldatas
    )
  {
    return (
      proposalTargets[proposalId],
      proposalValues[proposalId],
      proposalSignatures[proposalId],
      proposalCalldatas[proposalId]
    );
  }

  /**
   * @notice Gets the receipt for a voter on a given proposal
   * @param proposalId the id of proposal
   * @param voter The address of the voter
   * @return The voting receipt
   */
  function getReceipt(uint256 proposalId, address voter) external view returns (Receipt memory) {
    return proposalReceipts[proposalId][voter];
  }

  /**
   * @notice Gets the state of a proposal
   * @param proposalId The id of the proposal
   * @return Proposal state
   */
  function state(uint256 proposalId) public view returns (ProposalState) {
    require(proposalCount > proposalId, "Romulus::state: invalid proposal id");
    Proposal storage proposal = proposals[proposalId];
    if (proposal.canceled) {
      return ProposalState.Canceled;
    } else if (block.number <= proposal.startBlock) {
      return ProposalState.Pending;
    } else if (block.number <= proposal.endBlock) {
      return ProposalState.Active;
    } else if (proposal.forVotes <= proposal.againstVotes || proposal.forVotes < quorumVotes) {
      return ProposalState.Defeated;
    } else if (proposal.eta == 0) {
      return ProposalState.Succeeded;
    } else if (proposal.executed) {
      return ProposalState.Executed;
    } else if (block.timestamp >= add256(proposal.eta, timelock.GRACE_PERIOD())) {
      return ProposalState.Expired;
    } else {
      return ProposalState.Queued;
    }
  }

  /**
   * @notice Cast a vote for a proposal
   * @param proposalId The id of the proposal to vote on
   * @param support The support value for the vote. 0=against, 1=for, 2=abstain
   */
  function castVote(uint256 proposalId, uint8 support) external {
    emit VoteCast(msg.sender, proposalId, support, castVoteInternal(msg.sender, proposalId, support), "");
  }

  /**
   * @notice Cast a vote for a proposal with a reason
   * @param proposalId The id of the proposal to vote on
   * @param support The support value for the vote. 0=against, 1=for, 2=abstain
   * @param reason The reason given for the vote by the voter
   */
  function castVoteWithReason(
    uint256 proposalId,
    uint8 support,
    string calldata reason
  ) external {
    emit VoteCast(msg.sender, proposalId, support, castVoteInternal(msg.sender, proposalId, support), reason);
  }

  /**
   * @notice Cast a vote for a proposal by signature
   * @dev External function that accepts EIP-712 signatures for voting on proposals.
   */
  function castVoteBySig(
    uint256 proposalId,
    uint8 support,
    uint8 v,
    bytes32 r,
    bytes32 s
  ) external {
    bytes32 domainSeparator = keccak256(abi.encode(DOMAIN_TYPEHASH, keccak256(bytes(name)), getChainIdInternal(), address(this)));
    bytes32 structHash = keccak256(abi.encode(BALLOT_TYPEHASH, proposalId, support));
    bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
    address signatory = ecrecover(digest, v, r, s);
    require(signatory != address(0), "Romulus::castVoteBySig: invalid signature");
    emit VoteCast(signatory, proposalId, support, castVoteInternal(signatory, proposalId, support), "");
  }

  /**
   * @notice Internal function that caries out voting logic
   * @param voter The voter that is casting their vote
   * @param proposalId The id of the proposal to vote on
   * @param support The support value for the vote. 0=against, 1=for, 2=abstain
   * @return The number of votes cast
   */
  function castVoteInternal(
    address voter,
    uint256 proposalId,
    uint8 support
  ) internal returns (uint96) {
    require(state(proposalId) == ProposalState.Active, "Romulus::castVoteInternal: voting is closed");
    require(support <= 2, "Romulus::castVoteInternal: invalid vote type");
    Proposal storage proposal = proposals[proposalId];
    Receipt storage receipt = proposalReceipts[proposalId][voter];
    require(receipt.hasVoted == false, "Romulus::castVoteInternal: voter already voted");
    uint96 votes = getPriorVotes(voter, proposal.startBlock);

    if (support == 0) {
      proposal.againstVotes = add256(proposal.againstVotes, votes);
    } else if (support == 1) {
      proposal.forVotes = add256(proposal.forVotes, votes);
    } else if (support == 2) {
      proposal.abstainVotes = add256(proposal.abstainVotes, votes);
    }

    receipt.hasVoted = true;
    receipt.support = support;
    receipt.votes = votes;

    return votes;
  }

  /**
   * @notice Admin function for setting the voting delay
   * @param newVotingDelay new voting delay, in blocks
   */
  function _setVotingDelay(uint256 newVotingDelay) external adminOnly {
    require(
      newVotingDelay >= MIN_VOTING_DELAY && newVotingDelay <= MAX_VOTING_DELAY,
      "Romulus::_setVotingDelay: invalid voting delay"
    );
    uint256 oldVotingDelay = votingDelay;
    votingDelay = newVotingDelay;

    emit VotingDelaySet(oldVotingDelay, votingDelay);
  }

  /**
   * @notice Admin function for setting the voting period
   * @param newVotingPeriod new voting period, in blocks
   */
  function _setVotingPeriod(uint256 newVotingPeriod) external virtual adminOnly {
    require(
      newVotingPeriod >= MIN_VOTING_PERIOD && newVotingPeriod <= MAX_VOTING_PERIOD,
      "Romulus::_setVotingPeriod: invalid voting period"
    );
    uint256 oldVotingPeriod = votingPeriod;
    votingPeriod = newVotingPeriod;

    emit VotingPeriodSet(oldVotingPeriod, votingPeriod);
  }

  /**
   * @notice Admin function for setting the proposal threshold
   * @dev newProposalThreshold must be greater than the hardcoded min
   * @param newProposalThreshold new proposal threshold
   */
  function _setProposalThreshold(uint256 newProposalThreshold) external adminOnly {
    require(
      newProposalThreshold >= MIN_PROPOSAL_THRESHOLD && newProposalThreshold <= MAX_PROPOSAL_THRESHOLD,
      "Romulus::_setProposalThreshold: invalid proposal threshold"
    );
    uint256 oldProposalThreshold = proposalThreshold;
    proposalThreshold = newProposalThreshold;

    emit ProposalThresholdSet(oldProposalThreshold, proposalThreshold);
  }

  /**
   * @notice Begins transfer of admin rights. The newPendingAdmin must call `_acceptAdmin` to finalize the transfer.
   * @dev Admin function to begin change of admin. The newPendingAdmin must call `_acceptAdmin` to finalize the transfer.
   * @param newPendingAdmin New pending admin.
   */
  function _setPendingAdmin(address newPendingAdmin) external adminOnly {
    // Save current value, if any, for inclusion in log
    address oldPendingAdmin = pendingAdmin;

    // Store pendingAdmin with value newPendingAdmin
    pendingAdmin = newPendingAdmin;

    // Emit NewPendingAdmin(oldPendingAdmin, newPendingAdmin)
    emit NewPendingAdmin(oldPendingAdmin, newPendingAdmin);
  }

  /**
   * @notice Accepts transfer of admin rights. msg.sender must be pendingAdmin
   * @dev Admin function for pending admin to accept role and update admin
   */
  function _acceptAdmin() external {
    // Check caller is pendingAdmin and pendingAdmin ≠ address(0)
    require(msg.sender == pendingAdmin && msg.sender != address(0), "Romulus:_acceptAdmin: pending admin only");

    // Save current values for inclusion in log
    address oldAdmin = admin;
    address oldPendingAdmin = pendingAdmin;

    // Store admin with value pendingAdmin
    admin = pendingAdmin;

    // Clear the pending value
    pendingAdmin = address(0);

    emit NewAdmin(oldAdmin, admin);
    emit NewPendingAdmin(oldPendingAdmin, pendingAdmin);
  }

  function add256(uint256 a, uint256 b) internal pure returns (uint256) {
    uint256 c = a + b;
    require(c >= a, "addition overflow");
    return c;
  }

  function sub256(uint256 a, uint256 b) internal pure returns (uint256) {
    require(b <= a, "subtraction underflow");
    return a - b;
  }

  function getChainIdInternal() internal view returns (uint256) {
    uint256 chainId;
    assembly {
      chainId := chainid()
    }
    return chainId;
  }

  function getPriorVotes(address voter, uint256 beforeBlock) internal view returns (uint96) {
    if (address(releaseToken) == address(0)) {
      return token.getPriorVotes(voter, beforeBlock);
    }
    return add96(token.getPriorVotes(voter, beforeBlock), releaseToken.getPriorVotes(voter, beforeBlock), "getPriorVotes overflow");
  }

  function add96(uint96 a, uint96 b, string memory errorMessage) internal pure returns (uint96) {
    uint96 c = a + b;
    require(c >= a, errorMessage);
    return c;
  }
}


// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@ubeswap/governance/contracts/interfaces/IHasVotes.sol";

contract RomulusEvents {
  /// @notice An event emitted when a new proposal is created
  event ProposalCreated(
    uint256 id,
    address proposer,
    address[] targets,
    uint256[] values,
    string[] signatures,
    bytes[] calldatas,
    uint256 startBlock,
    uint256 endBlock,
    string description
  );

  /// @notice An event emitted when a vote has been cast on a proposal
  /// @param voter The address which casted a vote
  /// @param proposalId The proposal id which was voted on
  /// @param support Support value for the vote. 0=against, 1=for, 2=abstain
  /// @param votes Number of votes which were cast by the voter
  /// @param reason The reason given for the vote by the voter
  event VoteCast(address indexed voter, uint256 proposalId, uint8 support, uint256 votes, string reason);

  /// @notice An event emitted when a proposal has been canceled
  event ProposalCanceled(uint256 id);

  /// @notice An event emitted when a proposal has been queued in the Timelock
  event ProposalQueued(uint256 id, uint256 eta);

  /// @notice An event emitted when a proposal has been executed in the Timelock
  event ProposalExecuted(uint256 id);

  /// @notice An event emitted when the voting delay is set
  event VotingDelaySet(uint256 oldVotingDelay, uint256 newVotingDelay);

  /// @notice An event emitted when the voting period is set
  event VotingPeriodSet(uint256 oldVotingPeriod, uint256 newVotingPeriod);

  /// @notice Emitted when implementation is changed
  event NewImplementation(address oldImplementation, address newImplementation);

  /// @notice Emitted when proposal threshold is set
  event ProposalThresholdSet(uint256 oldProposalThreshold, uint256 newProposalThreshold);

  /// @notice Emitted when pendingAdmin is changed
  event NewPendingAdmin(address oldPendingAdmin, address newPendingAdmin);

  /// @notice Emitted when pendingAdmin is accepted, which means admin is updated
  event NewAdmin(address oldAdmin, address newAdmin);
}

contract RomulusDelegatorStorage {
  /// @notice Administrator for this contract
  address public admin;

  /// @notice Pending administrator for this contract
  address public pendingAdmin;

  /// @notice Active brains of Governor
  address public implementation;
}

/**
 * @title Storage for Governor Bravo Delegate
 * @notice For future upgrades, do not change RomulusDelegateStorageV1. Create a new
 * contract which implements RomulusDelegateStorageV1 and following the naming convention
 * RomulusDelegateStorageVX.
 */
contract RomulusDelegateStorageV1 is RomulusDelegatorStorage {
  /// @notice The delay before voting on a proposal may take place, once proposed, in blocks
  uint256 public votingDelay;

  /// @notice The duration of voting on a proposal, in blocks
  uint256 public votingPeriod;

  /// @notice The number of votes required in order for a voter to become a proposer
  uint256 public proposalThreshold;

  /// @notice The total number of proposals
  uint256 public proposalCount;

  /// @notice The address of the Governance Timelock
  TimelockInterface public timelock;

  /// @notice The address of the governance token
  IHasVotes public token;

  /// @notice The address of the "Release" governance token
  IHasVotes public releaseToken;

  /// @notice The official record of all proposals ever proposed
  mapping(uint256 => Proposal) public proposals;
  /// @notice The official each proposal's targets:
  /// An ordered list of target addresses for calls to be made
  mapping(uint256 => address[]) public proposalTargets;
  /// @notice The official each proposal's values:
  /// An ordered list of values (i.e. msg.value) to be passed to the calls to be made
  mapping(uint256 => uint256[]) public proposalValues;
  /// @notice The official each proposal's signatures:
  /// An ordered list of function signatures to be called
  mapping(uint256 => string[]) public proposalSignatures;
  /// @notice The official each proposal's calldatas:
  /// An ordered list of calldata to be passed to each call
  mapping(uint256 => bytes[]) public proposalCalldatas;
  /// @notice The official each proposal's receipts:
  /// Receipts of ballots for the entire set of voters
  mapping(uint256 => mapping(address => Receipt)) public proposalReceipts;

  /// @notice The latest proposal for each proposer
  mapping(address => uint256) public latestProposalIds;

  struct Proposal {
    // Unique id for looking up a proposal
    uint256 id;
    // Creator of the proposal
    address proposer;
    // The timestamp that the proposal will be available for execution, set once the vote succeeds
    uint256 eta;
    // The block at which voting begins: holders must delegate their votes prior to this block
    uint256 startBlock;
    // The block at which voting ends: votes must be cast prior to this block
    uint256 endBlock;
    // Current number of votes in favor of this proposal
    uint256 forVotes;
    // Current number of votes in opposition to this proposal
    uint256 againstVotes;
    // Current number of votes for abstaining for this proposal
    uint256 abstainVotes;
    // Flag marking whether the proposal has been canceled
    bool canceled;
    // Flag marking whether the proposal has been executed
    bool executed;
  }

  /// @notice Ballot receipt record for a voter
  struct Receipt {
    // Whether or not a vote has been cast
    bool hasVoted;
    // Whether or not the voter supports the proposal or abstains
    uint8 support;
    // The number of votes the voter had, which were cast
    uint96 votes;
  }

  /// @notice Possible states that a proposal may be in
  enum ProposalState { Pending, Active, Canceled, Defeated, Succeeded, Queued, Expired, Executed }
}

interface TimelockInterface {
  function admin() external view returns (address);

  function delay() external view returns (uint256);

  function GRACE_PERIOD() external view returns (uint256);

  function acceptAdmin() external;

  function queuedTransactions(bytes32 hash) external view returns (bool);

  function queueTransaction(
    address target,
    uint256 value,
    string calldata signature,
    bytes calldata data,
    uint256 eta
  ) external returns (bytes32);

  function cancelTransaction(
    address target,
    uint256 value,
    string calldata signature,
    bytes calldata data,
    uint256 eta
  ) external;

  function executeTransaction(
    address target,
    uint256 value,
    string calldata signature,
    bytes calldata data,
    uint256 eta
  ) external payable returns (bytes memory);
}


// SPDX-License-Identifier: MIT

pragma solidity ^0.8.3;

/**
 * Reads the votes that an account has.
 */
interface IHasVotes {
    /**
     * @notice Gets the current votes balance for `account`
     * @param account The address to get votes balance
     * @return The number of current votes for `account`
     */
    function getCurrentVotes(address account) external view returns (uint96);

    /**
     * @notice Determine the prior number of votes for an account as of a block number
     * @dev Block number must be a finalized block or else this function will revert to prevent misinformation.
     * @param account The address of the account to check
     * @param blockNumber The block number to get the vote balance at
     * @return The number of votes the account had as of the given block
     */
    function getPriorVotes(address account, uint256 blockNumber)
        external
        view
        returns (uint96);
}


// SPDX-License-Identifier: MIT

// solhint-disable-next-line compiler-version
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