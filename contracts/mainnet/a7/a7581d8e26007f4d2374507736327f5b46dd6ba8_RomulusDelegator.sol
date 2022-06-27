// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@poofcash/poof-token/contracts/NomResolve.sol";
import "./RomulusInterfaces.sol";

contract RomulusDelegator is RomulusDelegatorStorage, RomulusEvents, NomResolve {
  constructor(
    bytes32 timelock_,
    address token_,
    address releaseToken_,
    bytes32 admin_,
    address implementation_,
    uint votingPeriod_,
    uint votingDelay_,
    uint proposalThreshold_
  ) {
    // Admin set to msg.sender for initialization
    admin = msg.sender;

    delegateTo(
      implementation_, 
      abi.encodeWithSignature(
        "initialize(address,address,address,uint256,uint256,uint256)",
         resolve(timelock_),
         token_,
         releaseToken_,
         votingPeriod_,
         votingDelay_,
         proposalThreshold_
      )
    );
    _setImplementation(implementation_);
    admin = resolve(admin_);
	}


	/**
   * @notice Called by the admin to update the implementation of the delegator
   * @param implementation_ The address of the new implementation for delegation
   */
  function _setImplementation(address implementation_) public {
    require(msg.sender == admin, "RomulusDelegator::_setImplementation: admin only");
    require(implementation_ != address(0), "RomulusDelegator::_setImplementation: invalid implementation address");

    address oldImplementation = implementation;
    implementation = implementation_;

    emit NewImplementation(oldImplementation, implementation);
  } 

  /**
   * @notice Internal method to delegate execution to another contract
   * @dev It returns to the external caller whatever the implementation returns or forwards reverts
   * @param callee The contract to delegatecall
   * @param data The raw data to delegatecall
   */
  function delegateTo(address callee, bytes memory data) internal {
    (bool success, bytes memory returnData) = callee.delegatecall(data);
    assembly {
      if eq(success, 0) {
          revert(add(returnData, 0x20), returndatasize())
      }
    }
  }

	/**
   * @dev Delegates execution to an implementation contract.
   * It returns to the external caller whatever the implementation returns
   * or forwards reverts.
   */
  fallback () external {
    // delegate all other functions to current implementation
    (bool success, ) = implementation.delegatecall(msg.data);

    assembly {
      let free_mem_ptr := mload(0x40)
      returndatacopy(free_mem_ptr, 0, returndatasize())

      switch success
      case 0 { revert(free_mem_ptr, returndatasize()) }
      default { return(free_mem_ptr, returndatasize()) }
    }
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

pragma solidity ^0.8.0;

import "@nomspace/nomspace/contracts/interfaces/INom.sol";

contract NomResolve {
  function resolve(bytes32 name) public view virtual returns (address) {
    INom nom = INom(
      computeChainId() == 42220 ? 0xABf8faBbC071F320F222A526A2e1fBE26429344d : 0x36C976Da6A6499Cad683064F849afa69CD4dec2e
    );
    return nom.resolve(name);
  }

  function computeChainId() internal view returns (uint256) {
    uint256 chainId;
    assembly {
      chainId := chainid()
    }
    return chainId;
  }
}


// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// NOTE: Name == Nom in the documentation and is used interchangeably
interface INom {
  // @dev Reserve a Nom for a duration of time
  // @param name The name to reserve
  // @param durationToReserve The length of time in seconds to reserve this name
  function reserve(bytes32 name, uint256 durationToReserve) external;

  // @dev Extend a Nom reservation
  // @param name The name to extend the reservation of
  // @param durationToExtend The length of time in seconds to extend
  function extend(bytes32 name, uint256 durationToExtend) external;

  // @dev Retrieve the address that a Nom points to
  // @param name The name to resolve
  // @returns resolution The address that the Nom points to
  function resolve(bytes32 name) external view returns (address resolution);

  // @dev Get the expiration timestamp of a Nom 
  // @param name The name to get the expiration of
  // @returns expiration Time in seconds from epoch that this Nom expires
  function expirations(bytes32 name) external view returns (uint256 expiration);

  // @dev Change the resolution of a Nom
  // @param name The name to change the resolution of
  // @param newResolution The new address that should be pointed to
  function changeResolution(bytes32 name, address newResolution) external;

  // @dev Retrieve the owner of a Nom
  // @param name The name to find the owner of
  // @returns owner The address that owns the Nom
  function nameOwner(bytes32 name) external view returns (address owner);

  // @dev Change the owner of a Nom
  // @param name The name to change the owner of
  // @param newOwner The new owner
  function changeNameOwner(bytes32 name, address newOwner) external;

  // @dev Check whether a Nom is expired
  // @param name The name to check the expiration of
  // @param expired Flag indicating whether this Nom is expired
  function isExpired(bytes32 name) external view returns (bool expired);
}