// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.12;

import "./AssetSwapper.sol";
import "./interfaces/IPxaMarket.sol";
import "./interfaces/IPxtPool.sol";

contract Pixpress is AssetSwapper {
  uint256 public constant RATE_BASE = 1e6;

  IPxaMarket private _pxaMarket;
  IPxtPool private _pxtPool;
  uint256 private _recycleRewardRatio;

  constructor(address pxaMarketAddr, address pxtPoolAddr) {
    _pxaMarket = IPxaMarket(pxaMarketAddr);
    _pxtPool = IPxtPool(pxtPoolAddr);
    _recycleRewardRatio = 1e5;
  }

  function pxaMarket() external view returns (address) {
    return address(_pxaMarket);
  }

  function setPxaMarket(address _addr) external onlyRole(COORDINATOR) {
    _pxaMarket = IPxaMarket(_addr);
  }

  function pxtPool() external view returns (address) {
    return address(_pxtPool);
  }

  function setPxtPool(address _addr) external onlyRole(COORDINATOR) {
    _pxtPool = IPxtPool(_addr);
  }

  function recycleRewardRatio() external view returns (uint256) {
    return _recycleRewardRatio;
  }

  function setRecycleRewardRatio(uint256 val) external onlyRole(COORDINATOR) {
    _recycleRewardRatio = val;
  }

  function _processFee(uint256 _fee) internal {
    _pxaMarket.shareIncome{ value: _fee }();
  }

  function _spendPxtForOrder(address user) internal {
    uint256 fee = _pxtPool.perDeposit();
    _pxtPool.userDesposit(user, fee);
  }

  function _rewardRemoveOrderWithPxt(address user) internal {
    uint256 fee = (_pxtPool.perWithdraw() * _recycleRewardRatio) / RATE_BASE;
    _pxtPool.userWithdraw(user, fee);
  }

  function _rewardAcceptOrderWithPxt(address[2] memory users) internal {
    uint256 fee = _pxtPool.perWithdraw();
    if (fee > 0) {
      for (uint256 i = 0; i < users.length; i++) {
        _pxtPool.userWithdraw(users[i], fee / users.length);
      }
    }
  }

  function isProposeAssetsValid(uint256 proposeId) public view returns (bool) {
    ProposeRecord storage record = _proposeRecords[proposeId];
    address proposer = record.proposer;
    address[] storage tokenAddresses = record.tokenAddresses;
    uint256[] storage tokenIds = record.ids;
    uint8[] storage protocols = record.protocols;
    uint256[] storage amounts = record.amounts;
    bool[] storage wanted = record.wanted;
    for (uint256 i = 0; i < tokenAddresses.length; i++) {
      if (wanted[i]) continue;
      if (
        !_isAssetApproved(proposer, tokenAddresses[i], tokenIds[i], protocols[i], amounts[i]) ||
        !_isAssetInStock(proposer, tokenAddresses[i], tokenIds[i], protocols[i], amounts[i])
      ) {
        return false;
      }
    }
    return true;
  }

  function proposeSwap(
    address receiver,
    string memory note,
    address[] memory tokenAddresses,
    uint256[] memory amounts,
    uint256[] memory ids,
    uint8[] memory protocols,
    bool[] memory wanted
  ) external payable nonReentrant whenNotPaused {
    uint256 fee = swapFee(tokenAddresses, protocols, amounts, wanted);
    require(msg.value >= fee, "Pixpress: insufficient swap fee");
    _proposeSwap(receiver, note, tokenAddresses, amounts, ids, protocols, wanted);
    _processFee(fee);
  }

  function proposeSwapWithPxt(
    address receiver,
    string memory note,
    address[] memory tokenAddresses,
    uint256[] memory amounts,
    uint256[] memory ids,
    uint8[] memory protocols,
    bool[] memory wanted
  ) external nonReentrant whenNotPaused {
    _spendPxtForOrder(msg.sender);
    _proposeSwap(receiver, note, tokenAddresses, amounts, ids, protocols, wanted);
  }

  function removeProposeRecord(uint256 proposeId) external nonReentrant whenNotPaused {
    require((msg.sender == _proposeRecords[proposeId].proposer), "Asset Swapper: invalid proposer");
    _removeProposeRecord(proposeId);
    _rewardRemoveOrderWithPxt(msg.sender);

    emit ProposalRemoved(proposeId, _proposeRecords[proposeId]);
  }

  function cleanProposeRecord(uint256 proposeId) public nonReentrant whenNotPaused {
    require(!isProposeAssetsValid(proposeId), "Asset Swapper: cannot clean valid propose swap order");
    _removeProposeRecord(proposeId);
    _rewardRemoveOrderWithPxt(msg.sender);

    emit ProposalCleaned(proposeId, msg.sender, _proposeRecords[proposeId]);
  }

  function isMatchAssetsValid(uint256 matchId) public view returns (bool) {
    MatchRecord storage record = _matchRecords[matchId];
    address matcher = record.matcher;
    address[] storage tokenAddresses = record.tokenAddresses;
    uint256[] storage tokenIds = record.ids;
    uint8[] storage protocols = record.protocols;
    uint256[] storage amounts = record.amounts;
    for (uint256 i = 0; i < tokenAddresses.length; i++) {
      if (
        !_isAssetApproved(matcher, tokenAddresses[i], tokenIds[i], protocols[i], amounts[i]) ||
        !_isAssetInStock(matcher, tokenAddresses[i], tokenIds[i], protocols[i], amounts[i])
      ) {
        return false;
      }
    }
    return true;
  }

  function matchSwap(
    uint256 proposeId,
    address[] memory tokenAddresses,
    uint256[] memory amounts,
    uint256[] memory ids,
    uint8[] memory protocols
  ) external payable nonReentrant whenNotPaused {
    bool[] memory wanted = new bool[](tokenAddresses.length);
    for (uint256 i = 0; i < wanted.length; i++) {
      wanted[i] = false;
    }
    uint256 fee = swapFee(tokenAddresses, protocols, amounts, wanted);
    require(msg.value >= fee, "Pixpress: insufficient swap fee");
    _matchSwap(proposeId, tokenAddresses, amounts, ids, protocols);
    _processFee(fee);
  }

  function matchSwapWithPxt(
    uint256 proposeId,
    address[] memory tokenAddresses,
    uint256[] memory amounts,
    uint256[] memory ids,
    uint8[] memory protocols
  ) external nonReentrant whenNotPaused {
    _spendPxtForOrder(msg.sender);
    _matchSwap(proposeId, tokenAddresses, amounts, ids, protocols);
  }

  function removeMatchRecord(uint256 matchId) public nonReentrant whenNotPaused {
    require(_matchRecords[matchId].matcher == msg.sender, "Asset Swapper: invalid matcher");
    MatchRecord storage mRecord = _matchRecords[matchId];
    _removeProposeRecordMatchId(mRecord);
    _removeMatchRecord(matchId);
    _rewardRemoveOrderWithPxt(msg.sender);

    emit MatcherRemoved(matchId, _matchRecords[matchId]);
  }

  function cleanMatchRecord(uint256 matchId) public nonReentrant whenNotPaused {
    require(!isMatchAssetsValid(matchId), "Asset Swapper: cannot clean valid match swap order");
    MatchRecord storage mRecord = _matchRecords[matchId];
    _removeProposeRecordMatchId(mRecord);
    _removeMatchRecord(matchId);
    _rewardRemoveOrderWithPxt(msg.sender);

    emit MatcherCleaned(matchId, msg.sender, _matchRecords[matchId]);
  }

  function acceptSwap(uint256 proposeId, uint256 matchId) external nonReentrant {
    _acceptSwap(proposeId, matchId);
    _rewardAcceptOrderWithPxt([msg.sender, _matchRecords[matchId].matcher]);
    _removeProposeRecord((proposeId));
  }

  function swapFee(
    address[] memory tokenAddreses,
    uint8[] memory protocols,
    uint256[] memory amounts,
    bool[] memory wanted
  ) public view returns (uint256) {
    uint256 totalFee = 0;
    for (uint256 i = 0; i < tokenAddreses.length; i++) {
      if (wanted[i] == false) {
        totalFee += _assetFee(tokenAddreses[i], protocols[i], amounts[i]);
      }
    }
    return totalFee;
  }

  function pause() external onlyRole(COORDINATOR) {
    _pause();
  }

  function resume() external onlyRole(COORDINATOR) {
    _unpause();
  }
}


// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.12;

interface IPxtPool {
  function name() external view returns (string memory);

  function balance() external view returns (uint256);

  function setWindowRange(uint256 value) external;

  function systemDeposit(uint256 value) external;

  function systemWithdraw(uint256 value) external;

  function perDeposit() external view returns (uint256);

  function perWithdraw() external view returns (uint256);

  function userDesposit(address user, uint256 value) external;

  function userWithdraw(address user, uint256 value) external;
}


// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.12;

interface IPxaMarket {
  struct Order {
    address seller;
    uint256 tokenId;
    uint256 price;
    uint256 revenue;
    uint256 index;
  }

  event OrderCreated(uint256 indexed tokenId, address seller, uint256 price);
  event Bought(uint256 indexed tokenId, uint256 price, uint256 revenue);
  event Claimed(uint256 indexed tokenId, uint256 revenue);
  event OrderRemoved(uint256 indexed tokenId, uint256 revenue);
  event RevenueIncreased(uint256 indexed tokenId, uint256 revenue);
  event IncomeAdded(uint256 amount);
  event IncomeClaimed(address indexed receiver, uint256 amount);
  event Withdraw(address indexed receiver, uint256 amount);

  function rateBase() external view returns (uint256);

  function name() external view returns (string memory);

  function order(uint256 tokenId) external view returns (Order memory order);

  function createOrder(uint256 tokenId, uint256 price) external;

  function buy(uint256 tokenId) external payable;

  function claim(uint256 tokenId) external payable;

  function cancelOrder(uint256 tokenId) external payable;

  function pxaAddress() external view returns (address);

  function setPxaAddress(address value) external;

  function pwsAddress() external view returns (address);

  function setPwsAddress(address value) external;

  function feeRatio() external view returns (uint256);

  function setFeeRatio(uint256 value) external;

  function feeShareRatio() external view returns (uint256);

  function setFeeShareRatio(uint256 value) external;

  function addDividend() external payable;

  function shareIncome() external payable;

  function income() external view returns (uint256);

  function addIncome() external payable;

  function claimIncome(address receiver, uint256 amount) external;

  function withdraw(address receiver, uint256 amount) external;
}


// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.12;

import "./IAssetManager.sol";

interface IAssetSwapper {
  struct ProposeRecord {
    address proposer;
    address receiver;
    string note;
    address[] tokenAddresses;
    uint256[] amounts;
    uint256[] ids;
    uint8[] protocols;
    bool[] wanted;
    uint256[] matchRecordIds;
  }

  struct MatchRecord {
    uint256 proposeId;
    address matcher;
    address[] tokenAddresses;
    uint256[] amounts;
    uint256[] ids;
    uint8[] protocols;
    uint256 index;
  }

  // events
  event Proposed(uint256 indexed id, ProposeRecord record);
  event Matched(uint256 indexed id, MatchRecord record);
  event Swapped(uint256 indexed proposeId, uint256 indexed matchId);
  event ProposalRemoved(uint256 indexed id, ProposeRecord record);
  event MatcherRemoved(uint256 indexed id, MatchRecord record);
  event ProposalCleaned(uint256 indexed id, address indexed cleaner, ProposeRecord record);
  event MatcherCleaned(uint256 indexed id, address indexed cleaner, MatchRecord record);

  function proposeRecord(uint256 id) external view returns (ProposeRecord memory record);

  function matchRecord(uint256 id) external view returns (MatchRecord memory record);
}


// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.12;

interface IAssetManager {
  struct Asset {
    address tokenAddress;
    uint8 protocol;
    uint256 feeBase;
    uint256 feeRatio;
  }

  // events
  event AssetCreated(address indexed tokenAddress, Asset record);
  event AssetRemoved(address indexed tokenAddress);
  event AssetFeeBaseUpdated(address indexed tokenAddress, uint256 feeBase);
  event AssetFeeRatioUpdated(address indexed tokenAddress, uint256 feeRatio);
  event DefaultAssetFeeBaseUpdated(uint256 feeBase);
  event DefaultAssetFeeRatioUpdated(uint256 feeRatio);

  function asset(address tokenAddress) external view returns (Asset memory record);

  function createAsset(
    address tokenAddress,
    uint8 protocol,
    uint256 base,
    uint256 ratio
  ) external;

  function removeAsset(address tokenAddress) external;

  function setAssetFeeBase(address tokenAddress, uint256 base) external;

  function setAssetFeeRatio(address tokenAddress, uint256 ratio) external;

  function amFeeBase() external view returns (uint256);

  function setAmFeeBase(uint256 value) external;

  function amFeeRatio() external view returns (uint256);

  function setAmFeeRatio(uint256 value) external;
}


// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.12;

import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./AssetManager.sol";
import "./interfaces/IAssetSwapper.sol";

contract AssetSwapper is AssetManager, IAssetSwapper {
  using Counters for Counters.Counter;
  using SafeERC20 for IERC20;

  Counters.Counter private _proposeRecordIds;
  mapping(uint256 => ProposeRecord) _proposeRecords;
  Counters.Counter private _matchRecordIds;
  mapping(uint256 => MatchRecord) _matchRecords;

  function proposeRecord(uint256 id) external view returns (ProposeRecord memory record) {
    return _proposeRecords[id];
  }

  function matchRecord(uint256 id) external view returns (MatchRecord memory record) {
    return _matchRecords[id];
  }

  function _proposeSwap(
    address receiver,
    string memory note,
    address[] memory tokenAddresses,
    uint256[] memory amounts,
    uint256[] memory ids,
    uint8[] memory protocols,
    bool[] memory wanted
  ) internal {
    require(tokenAddresses.length == amounts.length, "Asset Swapper: amount record size does not match");
    require(tokenAddresses.length == ids.length, "Asset Swapper: id record size does not match");
    require(tokenAddresses.length == protocols.length, "Asset Swapper: protocol record size does not match");
    require(tokenAddresses.length == wanted.length, "Asset Swapper: wanted record size does not match");

    _proposeRecordIds.increment();
    uint256 id = _proposeRecordIds.current();
    _proposeRecords[id] = ProposeRecord(
      msg.sender,
      receiver,
      note,
      tokenAddresses,
      amounts,
      ids,
      protocols,
      wanted,
      new uint256[](0)
    );

    emit Proposed(id, _proposeRecords[id]);
  }

  function _matchSwap(
    uint256 proposeId,
    address[] memory tokenAddresses,
    uint256[] memory amounts,
    uint256[] memory ids,
    uint8[] memory protocols
  ) internal {
    require(tokenAddresses.length == amounts.length, "Assest Swapper: amount record size does not match");
    require(tokenAddresses.length == ids.length, "Assest Swapper: id record size does not match");
    require(tokenAddresses.length == protocols.length, "Assest Swapper: protocol record size does not match");
    if (_proposeRecords[proposeId].receiver != address(0)) {
      require(_msgSender() == _proposeRecords[proposeId].receiver, "Assest Swapper: receiver does not match");
    }
    _matchRecordIds.increment();
    uint256 id = _matchRecordIds.current();
    _matchRecords[id] = MatchRecord(
      proposeId,
      msg.sender,
      tokenAddresses,
      amounts,
      ids,
      protocols,
      _proposeRecords[proposeId].matchRecordIds.length
    );
    _proposeRecords[proposeId].matchRecordIds.push(id);

    emit Matched(id, _matchRecords[id]);
  }

  function _acceptSwap(uint256 proposeId, uint256 matchId) internal {
    ProposeRecord storage pRecord = _proposeRecords[proposeId];
    MatchRecord storage mRecord = _matchRecords[matchId];
    require(pRecord.proposer == msg.sender, "Asset Swapper: invalid proposer");
    require(proposeId == mRecord.proposeId, "Asset Swapper: invalid match id");
    require(_proposeAssetsValid(pRecord), "Asset Swapper: proposer assets invalid");
    require(_matchAssetsValid(mRecord), "Asset Swapper: matcher assets invalid");

    for (uint256 index = 0; index < pRecord.tokenAddresses.length; index++) {
      if (pRecord.wanted[index] == true) continue;
      _transferAsset(
        pRecord.proposer,
        mRecord.matcher,
        pRecord.tokenAddresses[index],
        pRecord.amounts[index],
        pRecord.ids[index],
        pRecord.protocols[index]
      );
    }
    for (uint256 index = 0; index < mRecord.tokenAddresses.length; index++) {
      _transferAsset(
        mRecord.matcher,
        pRecord.proposer,
        mRecord.tokenAddresses[index],
        mRecord.amounts[index],
        mRecord.ids[index],
        mRecord.protocols[index]
      );
    }

    emit Swapped(proposeId, matchId);
  }

  function _isAssetInStock(
    address tokenOwner,
    address tokenAddress,
    uint256 tokenId,
    uint8 protocol,
    uint256 amount
  ) internal view returns (bool) {
    if (protocol == PROTOCOL_ERC20) {
      IERC20 t = IERC20(tokenAddress);
      return t.balanceOf(tokenOwner) >= amount;
    } else if (protocol == PROTOCOL_ERC721) {
      IERC721 t = IERC721(tokenAddress);
      return t.ownerOf(tokenId) == tokenOwner;
    } else if (protocol == PROTOCOL_ERC1155) {
      IERC1155 t = IERC1155(tokenAddress);
      return t.balanceOf(tokenOwner, tokenId) >= amount;
    } else {
      return false;
    }
  }

  function _isAssetApproved(
    address tokenOwner,
    address tokenAddress,
    uint256 tokenId,
    uint8 protocol,
    uint256 amount
  ) internal view returns (bool) {
    if (protocol == PROTOCOL_ERC20) {
      IERC20 t = IERC20(tokenAddress);
      return t.allowance(tokenOwner, address(this)) >= amount;
    } else if (protocol == PROTOCOL_ERC721) {
      IERC721 t = IERC721(tokenAddress);
      return t.getApproved(tokenId) == address(this) || t.isApprovedForAll(tokenOwner, address(this));
    } else if (protocol == PROTOCOL_ERC1155) {
      IERC1155 t = IERC1155(tokenAddress);
      return t.isApprovedForAll(tokenOwner, address(this));
    } else {
      return false;
    }
  }

  function _proposeAssetsValid(ProposeRecord storage record) internal view returns (bool) {
    address proposer = record.proposer;
    address[] storage tokenAddresses = record.tokenAddresses;
    uint256[] storage tokenIds = record.ids;
    uint8[] storage protocols = record.protocols;
    uint256[] storage amounts = record.amounts;
    bool[] storage wanted = record.wanted;
    for (uint256 i = 0; i < tokenAddresses.length; i++) {
      if (wanted[i]) continue;
      require(
        _assetApproved(proposer, tokenAddresses[i], tokenIds[i], protocols[i], amounts[i]),
        "Asset Swapper: some proposer assets are not approved"
      );
      require(
        _assetInStock(proposer, tokenAddresses[i], tokenIds[i], protocols[i], amounts[i]),
        "Asset Swapper: some proposer assets are not in stock"
      );
    }
    return true;
  }

  function _matchAssetsValid(MatchRecord storage record) internal view returns (bool) {
    address matcher = record.matcher;
    address[] storage tokenAddresses = record.tokenAddresses;
    uint256[] storage tokenIds = record.ids;
    uint8[] storage protocols = record.protocols;
    uint256[] storage amounts = record.amounts;
    for (uint256 i = 0; i < tokenAddresses.length; i++) {
      require(
        _assetApproved(matcher, tokenAddresses[i], tokenIds[i], protocols[i], amounts[i]),
        "Asset Swapper: some matcher assets are not approved"
      );
      require(
        _assetInStock(matcher, tokenAddresses[i], tokenIds[i], protocols[i], amounts[i]),
        "Asset Swapper: some matcher assets are not in stock"
      );
    }
    return true;
  }

  function _assetApproved(
    address tokenOwner,
    address tokenAddress,
    uint256 tokenId,
    uint8 protocol,
    uint256 amount
  ) internal view returns (bool) {
    if (protocol == PROTOCOL_ERC20) {
      IERC20 t = IERC20(tokenAddress);
      require(t.allowance(tokenOwner, address(this)) >= amount, "Asset Swapper: insufficient token allowance");
    } else if (protocol == PROTOCOL_ERC721) {
      IERC721 t = IERC721(tokenAddress);
      require(
        t.getApproved(tokenId) == address(this) || t.isApprovedForAll(tokenOwner, address(this)),
        "Asset Swapper: ERC721 token not approved "
      );
    } else if (protocol == PROTOCOL_ERC1155) {
      IERC1155 t = IERC1155(tokenAddress);
      require(t.isApprovedForAll(tokenOwner, address(this)), "Asset Swapper: ERC1155 token not approved ");
    } else {
      revert("Asset Swapper: unsupported token protocol");
    }
    return true;
  }

  function _assetInStock(
    address tokenOwner,
    address tokenAddress,
    uint256 tokenId,
    uint8 protocol,
    uint256 amount
  ) internal view returns (bool) {
    if (protocol == PROTOCOL_ERC20) {
      IERC20 t = IERC20(tokenAddress);
      require(t.balanceOf(tokenOwner) >= amount, "Asset Swapper: ERC20 insufficient token balance");
    } else if (protocol == PROTOCOL_ERC721) {
      IERC721 t = IERC721(tokenAddress);
      require(t.ownerOf(tokenId) == tokenOwner, "Asset Swapper: ERC721 insufficient token balance");
    } else if (protocol == PROTOCOL_ERC1155) {
      IERC1155 t = IERC1155(tokenAddress);
      require(t.balanceOf(tokenOwner, tokenId) >= amount, "Asset Swapper: ERC1155 insufficient token balance");
    } else {
      revert("Asset Swapper: unsupported token protocol");
    }
    return true;
  }

  function _transferAsset(
    address sender,
    address receiver,
    address tokenAddress,
    uint256 amount,
    uint256 id,
    uint8 protocol
  ) internal {
    if (protocol == PROTOCOL_ERC20) {
      IERC20(tokenAddress).safeTransferFrom(sender, receiver, amount);
    } else if (protocol == PROTOCOL_ERC721) {
      IERC721(tokenAddress).safeTransferFrom(sender, receiver, id);
    } else if (protocol == PROTOCOL_ERC1155) {
      IERC1155(tokenAddress).safeTransferFrom(sender, receiver, id, amount, "");
    } else {
      revert("Asset Swapper: cannot swap unsupported token protocol");
    }
  }

  function _removeProposeRecord(uint256 proposeId) internal {
    ProposeRecord storage record = _proposeRecords[proposeId];

    delete _proposeRecords[proposeId];
    for (uint256 index = 0; index < record.matchRecordIds.length; index++) {
      _removeMatchRecord(record.matchRecordIds[index]);
    }
  }

  function _removeProposeRecordMatchId(MatchRecord storage mRecord) internal {
    ProposeRecord storage pRecord = _proposeRecords[mRecord.proposeId];
    uint256 lastMatchIdIndex = pRecord.matchRecordIds.length - 1;
    MatchRecord storage lastMatchIdRecord = _matchRecords[pRecord.matchRecordIds[lastMatchIdIndex]];
    lastMatchIdRecord.index = mRecord.index;
    pRecord.matchRecordIds[mRecord.index] = pRecord.matchRecordIds[lastMatchIdIndex];
    pRecord.matchRecordIds.pop();
  }

  function _removeMatchRecord(uint256 matchId) internal {
    delete _matchRecords[matchId];
  }
}


// SPDX-License-Identifier: GPL-3.0

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "./interfaces/IAssetManager.sol";

pragma solidity ^0.8.12;

contract AssetManager is IAssetManager, AccessControl, ReentrancyGuard, Pausable {
  // constants
  uint256 public constant AM_RATE_BASE = 1e6;
  uint8 public constant PROTOCOL_ERC20 = 1;
  uint8 public constant PROTOCOL_ERC721 = 2;
  uint8 public constant PROTOCOL_ERC1155 = 3;
  bytes32 public constant COORDINATOR = keccak256("COORDINATOR");

  // vars
  uint256 _amFeeBase = 20 ether;
  uint256 _amFeeRatio = 10000;

  mapping(address => Asset) public assets;

  constructor() {
    _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    _grantRole(COORDINATOR, msg.sender);
  }

  function asset(address tokenAddress) external view returns (Asset memory record) {
    return assets[tokenAddress];
  }

  function createAsset(
    address tokenAddress,
    uint8 protocol,
    uint256 base,
    uint256 ratio
  ) external onlyRole(COORDINATOR) {
    require(assets[tokenAddress].tokenAddress == address(0x0), "AssetManager: asset already exist");
    assets[tokenAddress] = Asset(tokenAddress, protocol, base, ratio);

    emit AssetCreated(tokenAddress, assets[tokenAddress]);
  }

  function removeAsset(address tokenAddress) external onlyRole(COORDINATOR) {
    delete assets[tokenAddress];

    emit AssetRemoved(tokenAddress);
  }

  function setAssetFeeBase(address tokenAddress, uint256 base) external onlyRole(COORDINATOR) {
    require(assets[tokenAddress].tokenAddress != address(0x0), "AssetManager: asset does not exist");
    assets[tokenAddress].feeBase = base;

    emit AssetFeeBaseUpdated(tokenAddress, base);
  }

  function setAssetFeeRatio(address tokenAddress, uint256 ratio) external onlyRole(COORDINATOR) {
    require(assets[tokenAddress].tokenAddress != address(0x0), "AssetManager: asset does not exist");
    assets[tokenAddress].feeRatio = ratio;

    emit AssetFeeRatioUpdated(tokenAddress, ratio);
  }

  function setAmFeeBase(uint256 value) external onlyRole(COORDINATOR) {
    _amFeeBase = value;

    emit DefaultAssetFeeBaseUpdated(value);
  }

  function amFeeBase() external view returns (uint256) {
    return _amFeeBase;
  }

  function setAmFeeRatio(uint256 value) external onlyRole(COORDINATOR) {
    _amFeeRatio = value;

    emit DefaultAssetFeeRatioUpdated(value);
  }

  function amFeeRatio() external view returns (uint256) {
    return _amFeeRatio;
  }

  function _assetFee(
    address tokenAddress,
    uint8 protocol,
    uint256 amount
  ) internal view returns (uint256) {
    if (assets[tokenAddress].tokenAddress == address(0x0)) {
      if (protocol == PROTOCOL_ERC20) {
        return (amount * _amFeeRatio) / AM_RATE_BASE;
      } else {
        return (_amFeeBase * _amFeeRatio) / AM_RATE_BASE;
      }
    } else {
      if (protocol == PROTOCOL_ERC20) {
        return (amount * assets[tokenAddress].feeBase * assets[tokenAddress].feeRatio) / AM_RATE_BASE;
      } else {
        return (assets[tokenAddress].feeBase * assets[tokenAddress].feeRatio) / AM_RATE_BASE;
      }
    }
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
// OpenZeppelin Contracts v4.4.1 (utils/Strings.sol)

pragma solidity ^0.8.0;

/**
 * @dev String operations.
 */
library Strings {
    bytes16 private constant _HEX_SYMBOLS = "0123456789abcdef";

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
}


// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts v4.4.1 (utils/Counters.sol)

pragma solidity ^0.8.0;

/**
 * @title Counters
 * @author Matt Condon (@shrugs)
 * @dev Provides counters that can only be incremented, decremented or reset. This can be used e.g. to track the number
 * of elements in a mapping, issuing ERC721 ids, or counting request ids.
 *
 * Include with `using Counters for Counters.Counter;`
 */
library Counters {
    struct Counter {
        // This variable should never be directly accessed by users of the library: interactions must be restricted to
        // the library's function. As of Solidity v0.5.2, this cannot be enforced, though there is a proposal to add
        // this feature: see https://github.com/ethereum/solidity/issues/4637
        uint256 _value; // default: 0
    }

    function current(Counter storage counter) internal view returns (uint256) {
        return counter._value;
    }

    function increment(Counter storage counter) internal {
        unchecked {
            counter._value += 1;
        }
    }

    function decrement(Counter storage counter) internal {
        uint256 value = counter._value;
        require(value > 0, "Counter: decrement overflow");
        unchecked {
            counter._value = value - 1;
        }
    }

    function reset(Counter storage counter) internal {
        counter._value = 0;
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
// OpenZeppelin Contracts (last updated v4.5.0) (utils/Address.sol)

pragma solidity ^0.8.1;

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
// OpenZeppelin Contracts v4.4.1 (token/ERC721/IERC721.sol)

pragma solidity ^0.8.0;

import "../../utils/introspection/IERC165.sol";

/**
 * @dev Required interface of an ERC721 compliant contract.
 */
interface IERC721 is IERC165 {
    /**
     * @dev Emitted when `tokenId` token is transferred from `from` to `to`.
     */
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);

    /**
     * @dev Emitted when `owner` enables `approved` to manage the `tokenId` token.
     */
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);

    /**
     * @dev Emitted when `owner` enables or disables (`approved`) `operator` to manage all of its assets.
     */
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

    /**
     * @dev Returns the number of tokens in ``owner``'s account.
     */
    function balanceOf(address owner) external view returns (uint256 balance);

    /**
     * @dev Returns the owner of the `tokenId` token.
     *
     * Requirements:
     *
     * - `tokenId` must exist.
     */
    function ownerOf(uint256 tokenId) external view returns (address owner);

    /**
     * @dev Safely transfers `tokenId` token from `from` to `to`, checking first that contract recipients
     * are aware of the ERC721 protocol to prevent tokens from being forever locked.
     *
     * Requirements:
     *
     * - `from` cannot be the zero address.
     * - `to` cannot be the zero address.
     * - `tokenId` token must exist and be owned by `from`.
     * - If the caller is not `from`, it must be have been allowed to move this token by either {approve} or {setApprovalForAll}.
     * - If `to` refers to a smart contract, it must implement {IERC721Receiver-onERC721Received}, which is called upon a safe transfer.
     *
     * Emits a {Transfer} event.
     */
    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId
    ) external;

    /**
     * @dev Transfers `tokenId` token from `from` to `to`.
     *
     * WARNING: Usage of this method is discouraged, use {safeTransferFrom} whenever possible.
     *
     * Requirements:
     *
     * - `from` cannot be the zero address.
     * - `to` cannot be the zero address.
     * - `tokenId` token must be owned by `from`.
     * - If the caller is not `from`, it must be approved to move this token by either {approve} or {setApprovalForAll}.
     *
     * Emits a {Transfer} event.
     */
    function transferFrom(
        address from,
        address to,
        uint256 tokenId
    ) external;

    /**
     * @dev Gives permission to `to` to transfer `tokenId` token to another account.
     * The approval is cleared when the token is transferred.
     *
     * Only a single account can be approved at a time, so approving the zero address clears previous approvals.
     *
     * Requirements:
     *
     * - The caller must own the token or be an approved operator.
     * - `tokenId` must exist.
     *
     * Emits an {Approval} event.
     */
    function approve(address to, uint256 tokenId) external;

    /**
     * @dev Returns the account approved for `tokenId` token.
     *
     * Requirements:
     *
     * - `tokenId` must exist.
     */
    function getApproved(uint256 tokenId) external view returns (address operator);

    /**
     * @dev Approve or remove `operator` as an operator for the caller.
     * Operators can call {transferFrom} or {safeTransferFrom} for any token owned by the caller.
     *
     * Requirements:
     *
     * - The `operator` cannot be the caller.
     *
     * Emits an {ApprovalForAll} event.
     */
    function setApprovalForAll(address operator, bool _approved) external;

    /**
     * @dev Returns if the `operator` is allowed to manage all of the assets of `owner`.
     *
     * See {setApprovalForAll}
     */
    function isApprovedForAll(address owner, address operator) external view returns (bool);

    /**
     * @dev Safely transfers `tokenId` token from `from` to `to`.
     *
     * Requirements:
     *
     * - `from` cannot be the zero address.
     * - `to` cannot be the zero address.
     * - `tokenId` token must exist and be owned by `from`.
     * - If the caller is not `from`, it must be approved to move this token by either {approve} or {setApprovalForAll}.
     * - If `to` refers to a smart contract, it must implement {IERC721Receiver-onERC721Received}, which is called upon a safe transfer.
     *
     * Emits a {Transfer} event.
     */
    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId,
        bytes calldata data
    ) external;
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


// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts v4.4.1 (token/ERC1155/IERC1155.sol)

pragma solidity ^0.8.0;

import "../../utils/introspection/IERC165.sol";

/**
 * @dev Required interface of an ERC1155 compliant contract, as defined in the
 * https://eips.ethereum.org/EIPS/eip-1155[EIP].
 *
 * _Available since v3.1._
 */
interface IERC1155 is IERC165 {
    /**
     * @dev Emitted when `value` tokens of token type `id` are transferred from `from` to `to` by `operator`.
     */
    event TransferSingle(address indexed operator, address indexed from, address indexed to, uint256 id, uint256 value);

    /**
     * @dev Equivalent to multiple {TransferSingle} events, where `operator`, `from` and `to` are the same for all
     * transfers.
     */
    event TransferBatch(
        address indexed operator,
        address indexed from,
        address indexed to,
        uint256[] ids,
        uint256[] values
    );

    /**
     * @dev Emitted when `account` grants or revokes permission to `operator` to transfer their tokens, according to
     * `approved`.
     */
    event ApprovalForAll(address indexed account, address indexed operator, bool approved);

    /**
     * @dev Emitted when the URI for token type `id` changes to `value`, if it is a non-programmatic URI.
     *
     * If an {URI} event was emitted for `id`, the standard
     * https://eips.ethereum.org/EIPS/eip-1155#metadata-extensions[guarantees] that `value` will equal the value
     * returned by {IERC1155MetadataURI-uri}.
     */
    event URI(string value, uint256 indexed id);

    /**
     * @dev Returns the amount of tokens of token type `id` owned by `account`.
     *
     * Requirements:
     *
     * - `account` cannot be the zero address.
     */
    function balanceOf(address account, uint256 id) external view returns (uint256);

    /**
     * @dev xref:ROOT:erc1155.adoc#batch-operations[Batched] version of {balanceOf}.
     *
     * Requirements:
     *
     * - `accounts` and `ids` must have the same length.
     */
    function balanceOfBatch(address[] calldata accounts, uint256[] calldata ids)
        external
        view
        returns (uint256[] memory);

    /**
     * @dev Grants or revokes permission to `operator` to transfer the caller's tokens, according to `approved`,
     *
     * Emits an {ApprovalForAll} event.
     *
     * Requirements:
     *
     * - `operator` cannot be the caller.
     */
    function setApprovalForAll(address operator, bool approved) external;

    /**
     * @dev Returns true if `operator` is approved to transfer ``account``'s tokens.
     *
     * See {setApprovalForAll}.
     */
    function isApprovedForAll(address account, address operator) external view returns (bool);

    /**
     * @dev Transfers `amount` tokens of token type `id` from `from` to `to`.
     *
     * Emits a {TransferSingle} event.
     *
     * Requirements:
     *
     * - `to` cannot be the zero address.
     * - If the caller is not `from`, it must be have been approved to spend ``from``'s tokens via {setApprovalForAll}.
     * - `from` must have a balance of tokens of type `id` of at least `amount`.
     * - If `to` refers to a smart contract, it must implement {IERC1155Receiver-onERC1155Received} and return the
     * acceptance magic value.
     */
    function safeTransferFrom(
        address from,
        address to,
        uint256 id,
        uint256 amount,
        bytes calldata data
    ) external;

    /**
     * @dev xref:ROOT:erc1155.adoc#batch-operations[Batched] version of {safeTransferFrom}.
     *
     * Emits a {TransferBatch} event.
     *
     * Requirements:
     *
     * - `ids` and `amounts` must have the same length.
     * - If `to` refers to a smart contract, it must implement {IERC1155Receiver-onERC1155BatchReceived} and return the
     * acceptance magic value.
     */
    function safeBatchTransferFrom(
        address from,
        address to,
        uint256[] calldata ids,
        uint256[] calldata amounts,
        bytes calldata data
    ) external;
}


// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts v4.4.1 (security/ReentrancyGuard.sol)

pragma solidity ^0.8.0;

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
abstract contract ReentrancyGuard {
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

    constructor() {
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
}


// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts v4.4.1 (security/Pausable.sol)

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
// OpenZeppelin Contracts (last updated v4.5.0) (access/AccessControl.sol)

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
        _checkRole(role, _msgSender());
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
     */
    function _revokeRole(bytes32 role, address account) internal virtual {
        if (hasRole(role, account)) {
            _roles[role].members[account] = false;
            emit RoleRevoked(role, account, _msgSender());
        }
    }
}