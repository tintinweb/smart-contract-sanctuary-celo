//SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.4;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/PACTDelegateStorageV1.sol";
import "./interfaces/PACTEvents.sol";

contract PACTDelegate is
    PACTEvents,
    Initializable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    PACTDelegateStorageV1
{
    using SafeERC20 for IERC20;

    /// @notice The name of this contract
    string public constant NAME = "PACT";

    /// @notice The minimum setable proposal threshold
    uint256 public constant MIN_PROPOSAL_THRESHOLD = 100_000_000e18; // 100,000,000 Tokens

    /// @notice The maximum setable proposal threshold
    uint256 public constant MAX_PROPOSAL_THRESHOLD = 500_000_000e18; // 500,000,000 Tokens

    /// @notice The minimum setable voting period
    uint256 public constant MIN_VOTING_PERIOD = 720; // About 1 hour

    /// @notice The max setable voting period
    uint256 public constant MAX_VOTING_PERIOD = 241920; // About 2 weeks

    /// @notice The min setable voting delay
    uint256 public constant MIN_VOTING_DELAY = 1;

    /// @notice The max setable voting delay
    uint256 public constant MAX_VOTING_DELAY = 120960; // About 1 week

    /// @notice The maximum number of actions that can be included in a proposal
    uint256 public constant PROPOSAL_MAX_OPERATIONS = 10; // 10 actions

    /// @notice The EIP-712 typehash for the contract's domain
    bytes32 public constant DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,uint256 chainId,address verifyingContract)");

    /// @notice The EIP-712 typehash for the ballot struct used by the contract
    bytes32 public constant BALLOT_TYPEHASH = keccak256("Ballot(uint256 proposalId,uint8 support)");

    /**
     * @notice Used to initialize the contract during delegator constructor
     * @param _timelock The address of the Timelock
     * @param _token The address of the voting token
     * @param _releaseToken The address of the "Release" voting token. If none, specify the zero address.
     * @param _votingPeriod The initial voting period
     * @param _votingDelay The initial voting delay
     * @param _proposalThreshold The initial proposal threshold
     * @param _quorumVotes The initial quorum votes
     */
    function initialize(
        address _timelock,
        address _token,
        address _releaseToken,
        uint256 _votingPeriod,
        uint256 _votingDelay,
        uint256 _proposalThreshold,
        uint256 _quorumVotes
    ) public initializer {
        require(
            TimelockInterface(_timelock).admin() == address(this),
            "PACT::initialize: timelock admin is not assigned to PACTDelegate"
        );
        require(
            _votingPeriod >= MIN_VOTING_PERIOD && _votingPeriod <= MAX_VOTING_PERIOD,
            "PACT::initialize: invalid voting period"
        );
        require(
            _votingDelay >= MIN_VOTING_DELAY && _votingDelay <= MAX_VOTING_DELAY,
            "PACT::initialize: invalid voting delay"
        );
        require(
            _proposalThreshold >= MIN_PROPOSAL_THRESHOLD &&
                _proposalThreshold <= MAX_PROPOSAL_THRESHOLD,
            "PACT::initialize: invalid proposal threshold"
        );
        require(_quorumVotes >= _proposalThreshold, "PACT::initialize: invalid quorum votes");
        timelock = TimelockInterface(_timelock);
        require(_token != address(0), "PACT::initialize: invalid _token address");

        __Ownable_init();
        __ReentrancyGuard_init();

        transferOwnership(_timelock);

        token = IHasVotes(_token);
        releaseToken = IHasVotes(_releaseToken);
        votingPeriod = _votingPeriod;
        votingDelay = _votingDelay;
        proposalThreshold = _proposalThreshold;
        quorumVotes = _quorumVotes;

        // Create dummy proposal
        Proposal memory _dummyProposal = Proposal({
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

        proposals[_dummyProposal.id] = _dummyProposal;
        latestProposalIds[_dummyProposal.proposer] = _dummyProposal.id;

        emit ProposalCreated(
            _dummyProposal.id,
            address(this),
            proposalTargets[_dummyProposal.id],
            proposalValues[_dummyProposal.id],
            proposalSignatures[_dummyProposal.id],
            proposalCalldatas[_dummyProposal.id],
            0,
            0,
            ""
        );
    }

    /**
     * @notice Function used to propose a new proposal. Sender must have delegates above the proposal threshold.
     * @param _targets Target addresses for proposal calls.
     * @param _values Eth values for proposal calls.
     * @param _signatures Function signatures for proposal calls.
     * @param _calldatas Calldatas for proposal calls.
     * @param _description String description of the proposal.
     * @return Proposal id of new proposal.
     */
    function propose(
        address[] memory _targets,
        uint256[] memory _values,
        string[] memory _signatures,
        bytes[] memory _calldatas,
        string memory _description
    ) public returns (uint256) {
        require(
            getPriorVotes(msg.sender, sub256(block.number, 1)) > proposalThreshold,
            "PACT::propose: proposer votes below proposal threshold"
        );
        require(
            _targets.length == _values.length &&
                _targets.length == _signatures.length &&
                _targets.length == _calldatas.length,
            "PACT::propose: proposal function information arity mismatch"
        );
        require(_targets.length != 0, "PACT::propose: must provide actions");
        require(_targets.length <= PROPOSAL_MAX_OPERATIONS, "PACT::propose: too many actions");

        uint256 _latestProposalId = latestProposalIds[msg.sender];
        if (_latestProposalId != 0) {
            ProposalState proposersLatestProposalState = state(_latestProposalId);
            require(
                proposersLatestProposalState != ProposalState.Active,
                "PACT::propose: one live proposal per proposer, found an already active proposal"
            );
            require(
                proposersLatestProposalState != ProposalState.Pending,
                "PACT::propose: one live proposal per proposer, found an already pending proposal"
            );
        }

        uint256 _startBlock = add256(block.number, votingDelay);
        uint256 _endBlock = add256(_startBlock, votingPeriod);

        Proposal memory _newProposal = Proposal({
            id: proposalCount,
            proposer: msg.sender,
            eta: 0,
            startBlock: _startBlock,
            endBlock: _endBlock,
            forVotes: 0,
            againstVotes: 0,
            abstainVotes: 0,
            canceled: false,
            executed: false
        });
        proposalCount++;

        proposals[_newProposal.id] = _newProposal;
        proposalTargets[_newProposal.id] = _targets;
        proposalValues[_newProposal.id] = _values;
        proposalSignatures[_newProposal.id] = _signatures;
        proposalCalldatas[_newProposal.id] = _calldatas;
        latestProposalIds[_newProposal.proposer] = _newProposal.id;

        emit ProposalCreated(
            _newProposal.id,
            msg.sender,
            _targets,
            _values,
            _signatures,
            _calldatas,
            _startBlock,
            _endBlock,
            _description
        );
        return _newProposal.id;
    }

    /**
     * @notice Queues a proposal of state succeeded
     * @param _proposalId The id of the proposal to queue
     */
    function queue(uint256 _proposalId) external {
        require(
            state(_proposalId) == ProposalState.Succeeded,
            "PACT::queue: proposal can only be queued if it is succeeded"
        );
        Proposal storage _proposal = proposals[_proposalId];
        uint256 _eta = add256(block.timestamp, timelock.delay());
        uint256 _i;
        uint256 _numberOfActions = proposalTargets[_proposalId].length;
        for (; _i < _numberOfActions; _i++) {
            queueOrRevertInternal(
                proposalTargets[_proposalId][_i],
                proposalValues[_proposalId][_i],
                proposalSignatures[_proposalId][_i],
                proposalCalldatas[_proposalId][_i],
                _eta
            );
        }
        _proposal.eta = _eta;
        emit ProposalQueued(_proposalId, _eta);
    }

    function queueOrRevertInternal(
        address _target,
        uint256 _value,
        string memory _signature,
        bytes memory _data,
        uint256 _eta
    ) internal {
        require(
            !timelock.queuedTransactions(
                keccak256(abi.encode(_target, _value, _signature, _data, _eta))
            ),
            "PACT::queueOrRevertInternal: identical proposal action already queued at eta"
        );
        timelock.queueTransaction(_target, _value, _signature, _data, _eta);
    }

    /**
     * @notice Executes a queued proposal if eta has passed
     * @param _proposalId The id of the proposal to execute
     */
    function execute(uint256 _proposalId) external payable {
        require(
            state(_proposalId) == ProposalState.Queued,
            "PACT::execute: proposal can only be executed if it is queued"
        );
        Proposal storage _proposal = proposals[_proposalId];
        _proposal.executed = true;
        uint256 _i;
        uint256 _numberOfActions = proposalTargets[_proposalId].length;
        for (; _i < _numberOfActions; _i++) {
            timelock.executeTransaction{value: proposalValues[_proposalId][_i]}(
                proposalTargets[_proposalId][_i],
                proposalValues[_proposalId][_i],
                proposalSignatures[_proposalId][_i],
                proposalCalldatas[_proposalId][_i],
                _proposal.eta
            );
        }
        emit ProposalExecuted(_proposalId);
    }

    /**
     * @notice Cancels a proposal only if sender is the proposer, or proposer delegates dropped below proposal threshold
     * @param _proposalId The id of the proposal to cancel
     */
    function cancel(uint256 _proposalId) external {
        require(
            state(_proposalId) != ProposalState.Executed,
            "PACT::cancel: cannot cancel executed proposal"
        );

        Proposal storage _proposal = proposals[_proposalId];
        require(
            msg.sender == _proposal.proposer ||
                getPriorVotes(_proposal.proposer, sub256(block.number, 1)) < proposalThreshold,
            "PACT::cancel: proposer above threshold"
        );

        _proposal.canceled = true;
        uint256 _i;
        uint256 _numberOfActions = proposalTargets[_proposalId].length;
        for (; _i < _numberOfActions; _i++) {
            timelock.cancelTransaction(
                proposalTargets[_proposalId][_i],
                proposalValues[_proposalId][_i],
                proposalSignatures[_proposalId][_i],
                proposalCalldatas[_proposalId][_i],
                _proposal.eta
            );
        }

        emit ProposalCanceled(_proposalId);
    }

    /**
     * @notice Gets actions of a proposal.
     * @param _proposalId Proposal to query.
     * @return targets Target addresses for proposal calls.
     * @return values Eth values for proposal calls.
     * @return signatures Function signatures for proposal calls.
     * @return calldatas Calldatas for proposal calls.
     */
    function getActions(uint256 _proposalId)
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
            proposalTargets[_proposalId],
            proposalValues[_proposalId],
            proposalSignatures[_proposalId],
            proposalCalldatas[_proposalId]
        );
    }

    /**
     * @notice Gets the receipt for a voter on a given proposal
     * @param _proposalId the id of proposal
     * @param _voter The address of the voter
     * @return The voting receipt
     */
    function getReceipt(uint256 _proposalId, address _voter)
        external
        view
        returns (Receipt memory)
    {
        return proposalReceipts[_proposalId][_voter];
    }

    /**
     * @notice Gets the state of a proposal
     * @param _proposalId The id of the proposal
     * @return Proposal state
     */
    function state(uint256 _proposalId) public view returns (ProposalState) {
        require(proposalCount > _proposalId, "PACT::state: invalid proposal id");
        Proposal storage _proposal = proposals[_proposalId];

        if (_proposal.canceled) {
            return ProposalState.Canceled;
        } else if (block.number <= _proposal.startBlock) {
            return ProposalState.Pending;
        } else if (block.number <= _proposal.endBlock) {
            return ProposalState.Active;
        } else if (
            _proposal.forVotes <= _proposal.againstVotes || _proposal.forVotes < quorumVotes
        ) {
            return ProposalState.Defeated;
        } else if (_proposal.eta == 0) {
            return ProposalState.Succeeded;
        } else if (_proposal.executed) {
            return ProposalState.Executed;
        } else if (block.timestamp >= add256(_proposal.eta, timelock.GRACE_PERIOD())) {
            return ProposalState.Expired;
        } else {
            return ProposalState.Queued;
        }
    }

    /**
     * @notice Cast a vote for a proposal
     * @param _proposalId The id of the proposal to vote on
     * @param _support The support value for the vote. 0=against, 1=for, 2=abstain
     */
    function castVote(uint256 _proposalId, uint8 _support) external {
        emit VoteCast(
            msg.sender,
            _proposalId,
            _support,
            castVoteInternal(msg.sender, _proposalId, _support),
            ""
        );
    }

    /**
     * @notice Cast a vote for a proposal with a reason
     * @param _proposalId The id of the proposal to vote on
     * @param _support The support value for the vote. 0=against, 1=for, 2=abstain
     * @param _reason The reason given for the vote by the voter
     */
    function castVoteWithReason(
        uint256 _proposalId,
        uint8 _support,
        string calldata _reason
    ) external {
        emit VoteCast(
            msg.sender,
            _proposalId,
            _support,
            castVoteInternal(msg.sender, _proposalId, _support),
            _reason
        );
    }

    /**
     * @notice Cast a vote for a proposal by signature
     * @dev External function that accepts EIP-712 signatures for voting on proposals.
     */
    function castVoteBySig(
        uint256 _proposalId,
        uint8 _support,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) external {
        require(_v == 27 || _v == 28, "PACT::castVoteBySig: invalid v value");
        require(
            _s < 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A1,
            "PACT::castVoteBySig: invalid s value"
        );
        bytes32 _domainSeparator = keccak256(
            abi.encode(DOMAIN_TYPEHASH, keccak256(bytes(NAME)), getChainIdInternal(), address(this))
        );
        bytes32 _structHash = keccak256(abi.encode(BALLOT_TYPEHASH, _proposalId, _support));
        bytes32 _digest = keccak256(abi.encodePacked("\x19\x01", _domainSeparator, _structHash));
        address _signatory = ecrecover(_digest, _v, _r, _s);
        require(_signatory != address(0), "PACT::castVoteBySig: invalid signature");
        emit VoteCast(
            _signatory,
            _proposalId,
            _support,
            castVoteInternal(_signatory, _proposalId, _support),
            ""
        );
    }

    /**
     * @notice Internal function that caries out voting logic
     * @param _voter The voter that is casting their vote
     * @param _proposalId The id of the proposal to vote on
     * @param _support The support value for the vote. 0=against, 1=for, 2=abstain
     * @return The number of votes cast
     */
    function castVoteInternal(
        address _voter,
        uint256 _proposalId,
        uint8 _support
    ) internal returns (uint96) {
        require(
            state(_proposalId) == ProposalState.Active,
            "PACT::castVoteInternal: voting is closed"
        );
        require(_support <= 2, "PACT::castVoteInternal: invalid vote type");
        Proposal storage _proposal = proposals[_proposalId];
        Receipt storage _receipt = proposalReceipts[_proposalId][_voter];
        require(!_receipt.hasVoted, "PACT::castVoteInternal: voter already voted");
        uint96 _votes = getPriorVotes(_voter, _proposal.startBlock);

        if (_support == 0) {
            _proposal.againstVotes = add256(_proposal.againstVotes, _votes);
        } else if (_support == 1) {
            _proposal.forVotes = add256(_proposal.forVotes, _votes);
        } else if (_support == 2) {
            _proposal.abstainVotes = add256(_proposal.abstainVotes, _votes);
        }

        _receipt.hasVoted = true;
        _receipt.support = _support;
        _receipt.votes = _votes;

        return _votes;
    }

    /**
     * @notice Owner function for setting the voting delay
     * @param _newVotingDelay new voting delay, in blocks
     */
    function _setVotingDelay(uint256 _newVotingDelay) external virtual onlyOwner {
        require(
            _newVotingDelay >= MIN_VOTING_DELAY && _newVotingDelay <= MAX_VOTING_DELAY,
            "PACT::_setVotingDelay: invalid voting delay"
        );
        uint256 _oldVotingDelay = votingDelay;
        votingDelay = _newVotingDelay;

        emit VotingDelaySet(_oldVotingDelay, _newVotingDelay);
    }

    /**
     * @notice Owner function for setting the quorum votes
     * @param _newQuorumVotes new quorum votes
     */
    function _setQuorumVotes(uint256 _newQuorumVotes) external onlyOwner {
        require(
            _newQuorumVotes >= proposalThreshold,
            "PACT::_setQuorumVotes: invalid quorum votes"
        );

        emit QuorumVotesSet(quorumVotes, _newQuorumVotes);
        quorumVotes = _newQuorumVotes;
    }

    /**
     * @notice Owner function for setting the voting period
     * @param _newVotingPeriod new voting period, in blocks
     */
    function _setVotingPeriod(uint256 _newVotingPeriod) external virtual onlyOwner {
        require(
            _newVotingPeriod >= MIN_VOTING_PERIOD && _newVotingPeriod <= MAX_VOTING_PERIOD,
            "PACT::_setVotingPeriod: invalid voting period"
        );
        emit VotingPeriodSet(votingPeriod, _newVotingPeriod);
        votingPeriod = _newVotingPeriod;
    }

    /**
     * @notice Owner function for setting the proposal threshold
     * @dev _newProposalThreshold must be greater than the hardcoded min
     * @param _newProposalThreshold new proposal threshold
     */
    function _setProposalThreshold(uint256 _newProposalThreshold) external onlyOwner {
        require(
            _newProposalThreshold >= MIN_PROPOSAL_THRESHOLD &&
                _newProposalThreshold <= MAX_PROPOSAL_THRESHOLD,
            "PACT::_setProposalThreshold: invalid proposal threshold"
        );
        emit ProposalThresholdSet(proposalThreshold, _newProposalThreshold);
        proposalThreshold = _newProposalThreshold;
    }

    /**
     * @notice Owner function for setting the release token
     * @param _newReleaseToken new release token address
     */
    function _setReleaseToken(IHasVotes _newReleaseToken) external onlyOwner {
        require(
            _newReleaseToken != token,
            "PACT::_setReleaseToken: releaseToken and token must be different"
        );
        emit ReleaseTokenSet(address(releaseToken), address(_newReleaseToken));
        releaseToken = _newReleaseToken;
    }

    function getPriorVotes(address _voter, uint256 _beforeBlock) public view returns (uint96) {
        if (address(releaseToken) == address(0)) {
            return token.getPriorVotes(_voter, _beforeBlock);
        }
        return
            add96(
                token.getPriorVotes(_voter, _beforeBlock),
                releaseToken.getPriorVotes(_voter, _beforeBlock),
                "getPriorVotes overflow"
            );
    }

    /**
     * @notice Transfers an amount of an ERC20 from this contract to an address
     *
     * @param _token address of the ERC20 token
     * @param _to address of the receiver
     * @param _amount amount of the transaction
     */
    function transfer(
        IERC20 _token,
        address _to,
        uint256 _amount
    ) external onlyOwner nonReentrant {
        _token.safeTransfer(_to, _amount);

        emit TransferERC20(address(_token), _to, _amount);
    }

    function add256(uint256 _a, uint256 _b) internal pure returns (uint256) {
        uint256 _c = _a + _b;
        require(_c >= _a, "addition overflow");
        return _c;
    }

    function sub256(uint256 _a, uint256 _b) internal pure returns (uint256) {
        require(_b <= _a, "subtraction underflow");
        return _a - _b;
    }

    function getChainIdInternal() internal view returns (uint256) {
        uint256 _chainId;
        assembly {
            _chainId := chainid()
        }
        return _chainId;
    }

    function add96(
        uint96 _a,
        uint96 _b,
        string memory _errorMessage
    ) internal pure returns (uint96) {
        uint96 _c = _a + _b;
        require(_c >= _a, _errorMessage);
        return _c;
    }
}


//SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.4;

contract PACTEvents {
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

    /// @notice Emitted when release token is set
    event ReleaseTokenSet(address oldReleaseToken, address newReleaseToken);

    /// @notice An event emitted when the quorum votes is set
    event QuorumVotesSet(uint256 oldQuorumVotes, uint256 newQuorumVotes);

    /// @notice Emitted when pendingAdmin is changed
    event NewPendingAdmin(address oldPendingAdmin, address newPendingAdmin);

    /// @notice Emitted when pendingAdmin is accepted, which means admin is updated
    event NewAdmin(address oldAdmin, address newAdmin);

    /**
     * @notice Triggered when an amount of an ERC20 has been transferred from this contract to an address
     *
     * @param token               ERC20 token address
     * @param to                  Address of the receiver
     * @param amount              Amount of the transaction
     */
    event TransferERC20(address indexed token, address indexed to, uint256 amount);
}


//SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.4;

interface TimelockInterface {
  function admin() external view returns (address);

  function delay() external view returns (uint256);

  function GRACE_PERIOD() external view returns (uint256);

  function acceptAdmin() external;

  function queuedTransactions(bytes32 _hash) external view returns (bool);

  function queueTransaction(
    address target,
    uint256 value,
    string calldata signature,
    bytes calldata data,
    uint256 eta
  ) external returns (bytes32);

  function cancelTransaction(
    address _target,
    uint256 _value,
    string calldata _signature,
    bytes calldata _data,
    uint256 _eta
  ) external;

  function executeTransaction(
    address _target,
    uint256 _value,
    string calldata _signature,
    bytes calldata _data,
    uint256 _eta
  ) external payable returns (bytes memory);
}


//SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.4;

import "@ubeswap/governance/contracts/interfaces/IHasVotes.sol";
import "./TimelockInterface.sol";

/**
 * @title Storage for Governor Delegate
 * @notice For future upgrades, do not change PACTDelegateStorageV1. Create a new
 * contract which implements PACTDelegateStorageV1 and following the naming convention
 * PACTDelegateStorageVX.
 */
contract PACTDelegateStorageV1 {
    /// @notice The delay before voting on a proposal may take place, once proposed, in blocks
    uint256 public votingDelay;

    /// @notice The duration of voting on a proposal, in blocks
    uint256 public votingPeriod;

    /// @notice The number of votes required in order for a voter to become a proposer
    uint256 public proposalThreshold;

    /// @notice The total number of proposals
    uint256 public proposalCount;

    /// @notice The number of votes in support of a proposal required in order for a quorum to be reached and for a vote to succeed
    uint256 public quorumVotes;

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
    enum ProposalState {
        Pending,
        Active,
        Canceled,
        Defeated,
        Succeeded,
        Queued,
        Expired,
        Executed
    }
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
        __Context_init_unchained();
    }

    function __Context_init_unchained() internal onlyInitializing {
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
// OpenZeppelin Contracts v4.4.1 (utils/Address.sol)

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
// OpenZeppelin Contracts v4.4.1 (security/ReentrancyGuard.sol)

pragma solidity ^0.8.0;
import "../proxy/utils/Initializable.sol";

/**
 * @dev Contract module that helps prevent reentrant calls to a function.
 *
 * Inheriting from `ReentrancyGuard` will make the {nonReentrant} modifier
 * available, which can be applied to functions to make sure there are no nested
 * (reentrant) calls to them.
 *
 * Note that because there is a single `nonReentrant` guard, functions marked as
 * `nonReentrant` may not call one another. This can be worked around by making
 * those functions `private`, and then adding `external` `nonReentrant` entry
 * points to them.
 *
 * TIP: If you would like to learn more about reentrancy and alternative ways
 * to protect against it, check out our blog post
 * https://blog.openzeppelin.com/reentrancy-after-istanbul/[Reentrancy After Istanbul].
 */
abstract contract ReentrancyGuardUpgradeable is Initializable {
    // Booleans are more expensive than uint256 or any type that takes up a full
    // word because each write operation emits an extra SLOAD to first read the
    // slot's contents, replace the bits taken up by the boolean, and then write
    // back. This is the compiler's defense against contract upgrades and
    // pointer aliasing, and it cannot be disabled.

    // The values being non-zero value makes deployment a bit more expensive,
    // but in exchange the refund on every call to nonReentrant will be lower in
    // amount. Since refunds are capped to a percentage of the total
    // transaction's gas, it is best to keep them low in cases like this one, to
    // increase the likelihood of the full refund coming into effect.
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;

    uint256 private _status;

    function __ReentrancyGuard_init() internal onlyInitializing {
        __ReentrancyGuard_init_unchained();
    }

    function __ReentrancyGuard_init_unchained() internal onlyInitializing {
        _status = _NOT_ENTERED;
    }

    /**
     * @dev Prevents a contract from calling itself, directly or indirectly.
     * Calling a `nonReentrant` function from another `nonReentrant`
     * function is not supported. It is possible to prevent this from happening
     * by making the `nonReentrant` function external, and making it call a
     * `private` function that does the actual work.
     */
    modifier nonReentrant() {
        // On the first call to nonReentrant, _notEntered will be true
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");

        // Any calls to nonReentrant after this point will fail
        _status = _ENTERED;

        _;

        // By storing the original value once again, a refund is triggered (see
        // https://eips.ethereum.org/EIPS/eip-2200)
        _status = _NOT_ENTERED;
    }
    uint256[49] private __gap;
}


// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts v4.4.1 (proxy/utils/Initializable.sol)

pragma solidity ^0.8.0;

import "../../utils/AddressUpgradeable.sol";

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
        __Context_init_unchained();
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
    uint256[49] private __gap;
}


// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts v4.4.1 (utils/Address.sol)

pragma solidity ^0.8.0;

/**
 * @dev Collection of functions related to the address type
 */
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
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but performing a delegate call.
     *
     * _Available since v3.4._
     */
    function functionDelegateCall(address target, bytes memory data) internal returns (bytes memory) {
        return functionDelegateCall(target, data, "Address: low-level delegate call failed");
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-string-}[`functionCall`],
     * but performing a delegate call.
     *
     * _Available since v3.4._
     */
    function functionDelegateCall(
        address target,
        bytes memory data,
        string memory errorMessage
    ) internal returns (bytes memory) {
        require(isContract(target), "Address: delegate call to non-contract");

        (bool success, bytes memory returndata) = target.delegatecall(data);
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
// OpenZeppelin Contracts v4.4.1 (token/ERC20/utils/SafeERC20.sol)

pragma solidity ^0.8.0;

import "../IERC20.sol";
import "../../../utils/Address.sol";

/**
 * @title SafeERC20
 * @dev Wrappers around ERC20 operations that throw on failure (when the token
 * contract returns false). Tokens that return no value (and instead revert or
 * throw on failure) are also supported, non-reverting calls are assumed to be
 * successful.
 * To use this library you can add a `using SafeERC20 for IERC20;` statement to your contract,
 * which allows you to call the safe operations as `token.safeTransfer(...)`, etc.
 */
library SafeERC20 {
    using Address for address;

    function safeTransfer(
        IERC20 token,
        address to,
        uint256 value
    ) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(token.transfer.selector, to, value));
    }

    function safeTransferFrom(
        IERC20 token,
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
        IERC20 token,
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
        IERC20 token,
        address spender,
        uint256 value
    ) internal {
        uint256 newAllowance = token.allowance(address(this), spender) + value;
        _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, newAllowance));
    }

    function safeDecreaseAllowance(
        IERC20 token,
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
    function _callOptionalReturn(IERC20 token, bytes memory data) private {
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
// OpenZeppelin Contracts v4.4.1 (token/ERC20/IERC20.sol)

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