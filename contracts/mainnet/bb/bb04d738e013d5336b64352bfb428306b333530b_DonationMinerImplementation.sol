//SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.4;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "./interfaces/DonationMinerStorageV4.sol";

contract DonationMinerImplementation is
    Initializable,
    OwnableUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable,
    DonationMinerStorageV4
{
    using SafeERC20 for IERC20;

    /**
     * @notice Triggered when a donation has been added
     *
     * @param donationId        Id of the donation
     * @param delegateAddress   Address of the delegate
     * @param amount            Value of the donation
     * @param token             Address of the token after conversion
     * @param amount            Number of token donated
     * @param target            Address of the receiver (community or treasury)
     *                          or address of the DonationMiner contract otherwise
     */
    event DonationAdded(
        uint256 indexed donationId,
        address indexed delegateAddress,
        uint256 amount,
        address token,
        uint256 initialAmount,
        address indexed target
    );

    /**
     * @notice Triggered when a donor has claimed his reward
     *
     * @param donor             Address of the donner
     * @param amount            Value of the reward
     */
    event RewardClaimed(address indexed donor, uint256 amount);

    /**
     * @notice Triggered when a donor has claimed his reward
     *
     * @param donor             Address of the donner
     * @param amount            Value of the reward
     * @param lastRewardPeriod  Number of the last reward period for witch the claim was made
     */
    event RewardClaimedPartial(address indexed donor, uint256 amount, uint256 lastRewardPeriod);

    /**
     * @notice Triggered when a donor has staked his reward
     *
     * @param donor             Address of the donner
     * @param amount            Value of the reward
     */
    event RewardStaked(address indexed donor, uint256 amount);

    /**
     * @notice Triggered when a donor has staked his reward
     *
     * @param donor             Address of the donner
     * @param amount            Value of the reward
     * @param lastRewardPeriod  Number of the last reward period for witch tha stake was made
     */
    event RewardStakedPartial(address indexed donor, uint256 amount, uint256 lastRewardPeriod);

    /**
     * @notice Triggered when an amount of an ERC20 has been transferred from this contract to an address
     *
     * @param token               ERC20 token address
     * @param to                  Address of the receiver
     * @param amount              Amount of the transaction
     */
    event TransferERC20(address indexed token, address indexed to, uint256 amount);

    /**
     * @notice Triggered when reward period params have been updated
     *
     * @param oldRewardPeriodSize   Old rewardPeriodSize value
     * @param oldDecayNumerator     Old decayNumerator value
     * @param oldDecayDenominator   Old decayDenominator value
     * @param newRewardPeriodSize   New rewardPeriodSize value
     * @param newDecayNumerator     New decayNumerator value
     * @param newDecayDenominator   New decayDenominator value
     *
     * For further information regarding each parameter, see
     * *DonationMiner* smart contract initialize method.
     */
    event RewardPeriodParamsUpdated(
        uint256 oldRewardPeriodSize,
        uint256 oldDecayNumerator,
        uint256 oldDecayDenominator,
        uint256 newRewardPeriodSize,
        uint256 newDecayNumerator,
        uint256 newDecayDenominator
    );

    /**
     * @notice Triggered when the claimDelay value has been updated
     *
     * @param oldClaimDelay            Old claimDelay value
     * @param newClaimDelay            New claimDelay value
     */
    event ClaimDelayUpdated(uint256 oldClaimDelay, uint256 newClaimDelay);

    /**
     * @notice Triggered when the stakingDonationRatio value has been updated
     *
     * @param oldStakingDonationRatio            Old stakingDonationRatio value
     * @param newStakingDonationRatio            New stakingDonationRatio value
     */
    event StakingDonationRatioUpdated(
        uint256 oldStakingDonationRatio,
        uint256 newStakingDonationRatio
    );

    /**
     * @notice Triggered when the communityDonationRatio value has been updated
     *
     * @param oldCommunityDonationRatio            Old communityDonationRatio value
     * @param newCommunityDonationRatio            New communityDonationRatio value
     */
    event CommunityDonationRatioUpdated(
        uint256 oldCommunityDonationRatio,
        uint256 newCommunityDonationRatio
    );

    /**
     * @notice Triggered when the againstPeriods value has been updated
     *
     * @param oldAgainstPeriods            Old againstPeriods value
     * @param newAgainstPeriods            New againstPeriods value
     */
    event AgainstPeriodsUpdated(uint256 oldAgainstPeriods, uint256 newAgainstPeriods);

    /**
     * @notice Triggered when the treasury address has been updated
     *
     * @param oldTreasury             Old treasury address
     * @param newTreasury             New treasury address
     */
    event TreasuryUpdated(address indexed oldTreasury, address indexed newTreasury);

    /**
     * @notice Triggered when the staking address has been updated
     *
     * @param oldStaking             Old staking address
     * @param newStaking             New staking address
     */
    event StakingUpdated(address indexed oldStaking, address indexed newStaking);

    /**
     * @notice Enforces beginning rewardPeriod has started
     */
    modifier whenStarted() {
        require(block.number >= rewardPeriods[1].startBlock, "DonationMiner: ERR_NOT_STARTED");
        _;
    }

    /**
     * @notice Enforces sender to be Staking contract
     */
    modifier onlyStaking() {
        require(msg.sender == address(staking), "DonationMiner: NOT_STAKING");
        _;
    }

    /**
     * @notice Used to initialize a new DonationMiner contract
     *
     * @param _cUSD                 Address of the cUSD token
     * @param _PACT                 Address of the PACT Token
     * @param _treasury             Address of the Treasury
     * @param _firstRewardPerBlock  Number of PACTs given for each block
     *                              from the first reward period
     * @param _rewardPeriodSize     Number of blocks of the reward period
     * @param _startingBlock        First block of the first reward period
     * @param _decayNumerator       Decay numerator used for calculating
                                    the new reward per block based on
                                    the previous reward per block
     * @param _decayDenominator     Decay denominator used for calculating
                                    the new reward per block based on
                                    the previous reward per block
     */
    function initialize(
        IERC20 _cUSD,
        IERC20 _PACT,
        ITreasury _treasury,
        uint256 _firstRewardPerBlock,
        uint256 _rewardPeriodSize,
        uint256 _startingBlock,
        uint256 _decayNumerator,
        uint256 _decayDenominator
    ) public initializer {
        require(address(_cUSD) != address(0), "DonationMiner::initialize: cUSD address not set");
        require(address(_PACT) != address(0), "DonationMiner::initialize: PACT address not set");
        require(address(_treasury) != address(0), "DonationMiner::initialize: treasury_ not set");
        require(
            _firstRewardPerBlock != 0,
            "DonationMiner::initialize: firstRewardPerBlock not set!"
        );
        require(_startingBlock != 0, "DonationMiner::initialize: startingRewardPeriod not set!");
        require(_rewardPeriodSize != 0, "DonationMiner::initialize: rewardPeriodSize is invalid!");

        __Ownable_init();
        __Pausable_init();
        __ReentrancyGuard_init();

        cUSD = _cUSD;
        PACT = _PACT;
        treasury = _treasury;
        rewardPeriodSize = _rewardPeriodSize;
        decayNumerator = _decayNumerator;
        decayDenominator = _decayDenominator;

        rewardPeriodCount = 1;
        initFirstPeriod(_startingBlock, _firstRewardPerBlock);
    }

    /**
     * @notice Returns the current implementation version
     */
    function getVersion() external pure override returns (uint256) {
        return 4;
    }

    /**
     * @notice Returns the amount of cUSD donated by a user in a reward period
     *
     * @param _period number of the reward period
     * @param _donor address of the donor
     * @return uint256 amount of cUSD donated by the user in this reward period
     */
    function rewardPeriodDonorAmount(uint256 _period, address _donor)
        external
        view
        override
        returns (uint256)
    {
        return rewardPeriods[_period].donorAmounts[_donor];
    }

    /**
     * @notice Returns the amount of PACT staked by a user at the and of the reward period
     *
     * @param _period reward period number
     * @param _donor address of the donor
     * @return uint256 amount of PACT staked by a user at the and of the reward period
     */
    function rewardPeriodDonorStakeAmounts(uint256 _period, address _donor)
        external
        view
        override
        returns (uint256)
    {
        return rewardPeriods[_period].donorStakeAmounts[_donor];
    }

    /**
     * @notice Returns a reward period number from a donor reward period list
     *
     * @param _donor address of the donor
     * @param _rewardPeriodIndex index of the reward period
     * @return uint256 number of the reward period
     */
    function donorRewardPeriod(address _donor, uint256 _rewardPeriodIndex)
        external
        view
        override
        returns (uint256)
    {
        return donors[_donor].rewardPeriods[_rewardPeriodIndex];
    }

    /**
     * @notice Updates reward period default params
     *
     * @param _newRewardPeriodSize value of new rewardPeriodSize
     * @param _newDecayNumerator value of new decayNumerator
     * @param _newDecayDenominator value of new decayDenominator
     */
    function updateRewardPeriodParams(
        uint256 _newRewardPeriodSize,
        uint256 _newDecayNumerator,
        uint256 _newDecayDenominator
    ) external override onlyOwner {
        require(
            _newRewardPeriodSize != 0,
            "DonationMiner::initialize: rewardPeriodSize is invalid!"
        );

        initializeRewardPeriods();

        emit RewardPeriodParamsUpdated(
            rewardPeriodSize,
            decayNumerator,
            decayDenominator,
            _newRewardPeriodSize,
            _newDecayNumerator,
            _newDecayDenominator
        );

        rewardPeriodSize = _newRewardPeriodSize;
        decayNumerator = _newDecayNumerator;
        decayDenominator = _newDecayDenominator;
    }

    /**
     * @notice Updates claimDelay value
     *
     * @param _newClaimDelay      Number of reward periods a donor has to wait after
     *                            a donation until he will be able to claim his reward
     */
    function updateClaimDelay(uint256 _newClaimDelay) external override onlyOwner {
        emit ClaimDelayUpdated(claimDelay, _newClaimDelay);

        claimDelay = _newClaimDelay;
    }

    /**
     * @notice Updates stakingDonationRatio value
     *
     * @param _newStakingDonationRatio    Number of tokens that need to be staked to be counted as 1 PACT donated
     */
    function updateStakingDonationRatio(uint256 _newStakingDonationRatio)
        external
        override
        onlyOwner
    {
        initializeRewardPeriods();

        emit StakingDonationRatioUpdated(stakingDonationRatio, _newStakingDonationRatio);

        stakingDonationRatio = _newStakingDonationRatio;
    }

    /**
     * @notice Updates communityDonationRatio value
     *
     * @param _newCommunityDonationRatio    Ratio between 1USD donated into the treasury vs 1USD donated to a community
     */
    function updateCommunityDonationRatio(uint256 _newCommunityDonationRatio)
        external
        override
        onlyOwner
    {
        emit CommunityDonationRatioUpdated(communityDonationRatio, _newCommunityDonationRatio);
        communityDonationRatio = _newCommunityDonationRatio;
    }

    /**
     * @notice Updates againstPeriods value
     *
     * @param _newAgainstPeriods      Number of reward periods for the backward computation
     */
    function updateAgainstPeriods(uint256 _newAgainstPeriods) external override onlyOwner {
        initializeRewardPeriods();

        emit AgainstPeriodsUpdated(againstPeriods, _newAgainstPeriods);
        againstPeriods = _newAgainstPeriods;
    }

    /**
     * @notice Updates Treasury address
     *
     * @param _newTreasury address of new treasury_ contract
     */
    function updateTreasury(ITreasury _newTreasury) external override onlyOwner {
        emit TreasuryUpdated(address(treasury), address(_newTreasury));
        treasury = _newTreasury;
    }

    /**
     * @notice Updates Staking address
     *
     * @param _newStaking address of new Staking contract
     */
    function updateStaking(IStaking _newStaking) external override onlyOwner {
        emit StakingUpdated(address(staking), address(_newStaking));
        staking = _newStaking;
    }

    /**
     * @notice Transfers cUSD tokens to the treasury contract
     *
     * @param _token address of the token
     * @param _amount Amount of cUSD tokens to deposit.
     * @param _delegateAddress the address that will claim the reward for the donation
     */
    function donate(
        IERC20 _token,
        uint256 _amount,
        address _delegateAddress
    ) external override whenNotPaused whenStarted nonReentrant {
        require(
            _token == cUSD || treasury.isToken(address(_token)),
            "DonationMiner::donate: Invalid token"
        );

        _token.safeTransferFrom(msg.sender, address(treasury), _amount);

        _addDonation(_delegateAddress, _token, _amount, address(treasury));
    }

    /**
     * @dev Transfers tokens to the community contract
     *
     * @param _community address of the community
     * @param _token address of the token
     * @param _amount amount of cUSD tokens to deposit
     * @param _delegateAddress the address that will claim the reward for the donation
     */
    function donateToCommunity(
        ICommunity _community,
        IERC20 _token,
        uint256 _amount,
        address _delegateAddress
    ) external override whenNotPaused whenStarted nonReentrant {
        ICommunityAdmin _communityAdmin = treasury.communityAdmin();
        require(
            _communityAdmin.communities(address(_community)) ==
                ICommunityAdmin.CommunityState.Valid,
            "DonationMiner::donateToCommunity: This is not a valid community address"
        );

        require(
            address(_token) == address(_community.cUSD()),
            "DonationMiner::donateToCommunity: Invalid token"
        );

        _community.donate(msg.sender, _amount);
        _addDonation(_delegateAddress, _token, _amount, address(_community));
    }

    /**
     * @notice Transfers to the sender the rewards
     */
    function claimRewards() external override whenNotPaused whenStarted nonReentrant {
        uint256 _claimAmount = _computeRewardsByPeriodNumber(msg.sender, _getLastClaimablePeriod());

        PACT.safeTransfer(msg.sender, _claimAmount);
        emit RewardClaimed(msg.sender, _claimAmount);
    }

    /**
     * @notice Transfers to the sender the rewards
     */
    function claimRewardsPartial(uint256 _lastPeriodNumber)
        external
        override
        whenNotPaused
        whenStarted
        nonReentrant
    {
        require(
            _lastPeriodNumber <= _getLastClaimablePeriod(),
            "DonationMiner::claimRewardsPartial: This reward period isn't claimable yet"
        );

        uint256 _claimAmount = _computeRewardsByPeriodNumber(msg.sender, _lastPeriodNumber);

        PACT.safeTransfer(msg.sender, _claimAmount);

        emit RewardClaimedPartial(msg.sender, _claimAmount, _lastPeriodNumber);
    }

    /**
     * @notice Stakes the reward
     */
    function stakeRewards() external override whenNotPaused whenStarted nonReentrant {
        initializeRewardPeriods();

        uint256 _stakeAmount = _computeRewardsByPeriodNumber(msg.sender, rewardPeriodCount - 1);

        PACT.approve(address(staking), _stakeAmount);
        staking.stake(msg.sender, _stakeAmount);

        emit RewardStaked(msg.sender, _stakeAmount);
    }

    /**
     * @notice Stakes the reward
     */
    function stakeRewardsPartial(uint256 _lastPeriodNumber)
        external
        override
        whenNotPaused
        whenStarted
        nonReentrant
    {
        initializeRewardPeriods();

        require(
            _lastPeriodNumber < rewardPeriodCount,
            "DonationMiner::stakeRewardsPartial: This reward period isn't claimable yet"
        );

        uint256 _stakeAmount = _computeRewardsByPeriodNumber(msg.sender, _lastPeriodNumber);

        PACT.approve(address(staking), _stakeAmount);
        staking.stake(msg.sender, _stakeAmount);

        emit RewardStaked(msg.sender, _stakeAmount);
    }

    /**
     * @notice Calculates the rewards from ended reward periods of a donor
     *
     * @param _donorAddress address of the donor
     * @param _lastPeriodNumber last reward period number to be computed
     * @return uint256 sum of all donor's rewards that has not been claimed until _lastPeriodNumber
     */
    function calculateClaimableRewardsByPeriodNumber(
        address _donorAddress,
        uint256 _lastPeriodNumber
    ) external view override returns (uint256) {
        uint256 _maxRewardPeriod;

        if (rewardPeriods[rewardPeriodCount].endBlock < block.number) {
            _maxRewardPeriod =
                (block.number - rewardPeriods[rewardPeriodCount].endBlock) /
                rewardPeriodSize;
            _maxRewardPeriod += rewardPeriodCount;
        } else {
            _maxRewardPeriod = rewardPeriodCount - 1;
        }

        require(
            _lastPeriodNumber <= _maxRewardPeriod,
            "DonationMiner::calculateClaimableRewardsByPeriodNumber: This reward period isn't available yet"
        );

        (uint256 _claimAmount, ) = _calculateRewardByPeriodNumber(_donorAddress, _lastPeriodNumber);
        return _claimAmount;
    }

    /**
     * @notice Calculates the rewards from ended reward periods of a donor
     *
     * @param _donorAddress address of the donor
     * @return claimAmount uint256 sum of all donor's rewards that has not been claimed until _lastPeriodNumber
     */
    function calculateClaimableRewards(address _donorAddress)
        external
        view
        override
        returns (uint256)
    {
        (uint256 _claimAmount, ) = _calculateRewardByPeriodNumber(
            _donorAddress,
            currentRewardPeriodNumber() - 1
        );
        return _claimAmount;
    }

    /**
     * @notice Calculates the estimate reward of a donor for current reward period
     *
     * @param _donorAddress             address of the donor
     *
     * @return uint256 reward that donor will receive in current reward period if there isn't another donation
     */
    function estimateClaimableReward(address _donorAddress)
        external
        view
        override
        whenStarted
        whenNotPaused
        returns (uint256)
    {
        return _estimateClaimableReward(_donorAddress, 0);
    }

    /**
     * @notice Calculates the estimate reward of a donor for the next x reward periods
     *
     * @param _donorAddress             address of the donor
     *
     * @return uint256 reward that donor will receive in current reward period if there isn't another donation
     */
    function estimateClaimableRewardAdvance(address _donorAddress)
        external
        view
        override
        whenStarted
        whenNotPaused
        returns (uint256)
    {
        return _estimateClaimableReward(_donorAddress, againstPeriods);
    }

    /**
     * @notice Calculates the estimate reward of a donor for current reward period based on his staking
     *
     * @return uint256 estimated reward by donor stakes
     */
    function estimateClaimableRewardByStaking(address _donorAddress)
        external
        view
        override
        whenStarted
        whenNotPaused
        returns (uint256)
    {
        uint256 _donorAmount;
        uint256 _totalAmount;

        (, _totalAmount) = lastPeriodsDonations(address(0));

        uint256 _currentPeriodReward = _calculateCurrentPeriodReward();

        return
            (_currentPeriodReward * staking.stakeholderAmount(_donorAddress)) /
            (_totalAmount * stakingDonationRatio + staking.currentTotalAmount());
    }

    /**
     * @notice Calculates the APR of a user based on his staking
     *
     * @param _stakeholderAddress      address of the stakeHolder
     *
     * @return uint256 APR of the user
     */
    function apr(address _stakeholderAddress)
        external
        view
        override
        whenStarted
        whenNotPaused
        returns (uint256)
    {
        uint256 _stakeholderAmount = staking.stakeholderAmount(_stakeholderAddress);
        if (_stakeholderAmount == 0) {
            return 0;
        }

        return
            (1e18 * 365100 * _estimateClaimableReward(_stakeholderAddress, 0)) / _stakeholderAmount;
    }

    /**
     * @notice Calculates the APR
     *
     * @return uint256 APR
     */
    function generalApr() public view override whenStarted whenNotPaused returns (uint256) {
        uint256 _donorAmount;
        uint256 _totalAmount;

        (, _totalAmount) = lastPeriodsDonations(address(0));

        uint256 _currentPeriodReward = _calculateCurrentPeriodReward();
        uint256 _totalReward = _currentPeriodReward;
        uint256 _index;
        while (_index < 364) {
            _currentPeriodReward = (_currentPeriodReward * decayNumerator) / decayDenominator;
            _totalReward += _currentPeriodReward;
            _index++;
        }

        return
            (1e18 * 100 * _totalReward) /
            (_totalAmount * stakingDonationRatio + staking.currentTotalAmount());
    }

    /**
     * @dev Calculate the score of a user based as
     * this ratio (his donation and staking) / (all donation and staking)
     * E.G. score = 0.01 * 1e18 => the donor have have 1% score
     *      so he will get 1% of the reward
     *
     * @param _donorAddress  address of the donor
     *
     * @return uint256    donor's score
     */
    function donorScore(address _donorAddress) public view returns (uint256) {
        return _calculateDonorShare(_donorAddress, 1e18);
    }

    /**
     * @dev Calculate all donations on the last X epochs as well as everyone
     * else in the same period.
     *
     * @param _donorAddress  address of the donor
     *
     * @return donorAmount uint256    sum of donor's donations
     * @return totalAmount uint256    sum of all donations
     */
    function lastPeriodsDonations(address _donorAddress)
        public
        view
        override
        returns (uint256 donorAmount, uint256 totalAmount)
    {
        uint256 _currentRewardPeriodNumber = currentRewardPeriodNumber();

        uint256 _startPeriod = _currentRewardPeriodNumber > againstPeriods
            ? _currentRewardPeriodNumber - againstPeriods
            : 1;

        if (rewardPeriodCount >= _startPeriod) {
            (donorAmount, totalAmount) = _calculateDonorIntervalAmounts(
                _donorAddress,
                _startPeriod,
                rewardPeriodCount
            );
        }
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
    ) external override onlyOwner nonReentrant {
        _token.safeTransfer(_to, _amount);

        emit TransferERC20(address(_token), _to, _amount);
    }

    function setStakingAmounts(
        address _holderAddress,
        uint256 _holderAmount,
        uint256 _totalAmount
    ) external override whenNotPaused whenStarted onlyStaking {
        initializeRewardPeriods();

        RewardPeriod storage _rewardPeriod = rewardPeriods[rewardPeriodCount];
        _rewardPeriod.hasSetStakeAmount[_holderAddress] = true;
        _rewardPeriod.donorStakeAmounts[_holderAddress] = _holderAmount;
        _rewardPeriod.stakesAmount = _totalAmount;

        Donor storage _donor = donors[_holderAddress];
        //if user hasn't made any donation/staking
        //set _donor.lastClaimPeriod to be previous reward period
        //to not calculate reward for epochs 1 to rewardPeriodsCount -1
        if (_donor.lastClaimPeriod == 0 && _donor.rewardPeriodsCount == 0) {
            _donor.lastClaimPeriod = rewardPeriodCount - 1;
        }
    }

    function currentRewardPeriodNumber() public view override returns (uint256) {
        uint256 lastRewardPeriodEndBlock = rewardPeriods[rewardPeriodCount].endBlock;

        return
            lastRewardPeriodEndBlock > block.number
                ? rewardPeriodCount
                : rewardPeriodCount +
                    (block.number - lastRewardPeriodEndBlock) /
                    rewardPeriodSize +
                    1;
    }

    /**
     * @notice Initializes all reward periods that haven't been initialized yet until the current one.
     *         The first donor in a reward period will pay for that operation.
     */
    function initializeRewardPeriods() internal {
        RewardPeriod storage _lastPeriod = rewardPeriods[rewardPeriodCount];

        while (_lastPeriod.endBlock < block.number) {
            rewardPeriodCount++;
            RewardPeriod storage _newPeriod = rewardPeriods[rewardPeriodCount];
            _newPeriod.againstPeriods = againstPeriods;
            _newPeriod.startBlock = _lastPeriod.endBlock + 1;
            _newPeriod.endBlock = _newPeriod.startBlock + rewardPeriodSize - 1;
            _newPeriod.rewardPerBlock =
                (_lastPeriod.rewardPerBlock * decayNumerator) /
                decayDenominator;
            _newPeriod.stakesAmount = _lastPeriod.stakesAmount;
            _newPeriod.stakingDonationRatio = stakingDonationRatio;
            uint256 _rewardAmount = rewardPeriodSize * _newPeriod.rewardPerBlock;

            uint256 _startPeriod = (rewardPeriodCount - 1 > _lastPeriod.againstPeriods)
                ? rewardPeriodCount - 1 - _lastPeriod.againstPeriods
                : 1;

            if (!hasDonationOrStake(_startPeriod, rewardPeriodCount - 1)) {
                _rewardAmount += _lastPeriod.rewardAmount;
            }
            _newPeriod.rewardAmount = _rewardAmount;
            _lastPeriod = _newPeriod;
        }
    }

    /**
     * @notice Adds a new donation in donations list
     *
     * @param _delegateAddress address of the wallet that will claim the reward
     * @param _initialAmount amount of the donation
     * @param _target address of the receiver (community or treasury)
     */
    function _addDonation(
        address _delegateAddress,
        IERC20 _token,
        uint256 _initialAmount,
        address _target
    ) internal {
        initializeRewardPeriods();

        donationCount++;
        Donation storage _donation = donations[donationCount];
        _donation.donor = _delegateAddress;
        _donation.target = _target;
        _donation.blockNumber = block.number;
        _donation.rewardPeriod = rewardPeriodCount;
        _donation.token = _token;
        _donation.initialAmount = _initialAmount;

        if (_target == address(treasury)) {
            _donation.amount = (_token == cUSD)
                ? _initialAmount
                : treasury.getConvertedAmount(address(_token), _initialAmount);
        } else {
            _donation.amount = _initialAmount / communityDonationRatio;
        }

        updateRewardPeriodAmounts(rewardPeriodCount, _delegateAddress, _donation.amount);
        addCurrentRewardPeriodToDonor(_delegateAddress);

        emit DonationAdded(
            donationCount,
            _delegateAddress,
            _donation.amount,
            address(_token),
            _initialAmount,
            _target
        );
    }

    /**
     * @notice Adds the current reward period number to a donor's list only if it hasn't been added yet
     *
     * @param _donorAddress address of the donor
     */
    function addCurrentRewardPeriodToDonor(address _donorAddress) internal {
        Donor storage _donor = donors[_donorAddress];
        uint256 _lastDonorRewardPeriod = _donor.rewardPeriods[_donor.rewardPeriodsCount];

        //ensures that the current reward period number hasn't been added in the donor's list
        if (_lastDonorRewardPeriod != rewardPeriodCount) {
            _donor.rewardPeriodsCount++;
            _donor.rewardPeriods[_donor.rewardPeriodsCount] = rewardPeriodCount;
        }

        //if user hasn't made any donation/staking
        //set _donor.lastClaimPeriod to be previous reward period
        //to not calculate reward for epochs 1 to rewardPeriodsCount -1
        if (_donor.lastClaimPeriod == 0 && _donor.rewardPeriodsCount == 0) {
            _donor.lastClaimPeriod = rewardPeriodCount - 1;
        }
    }

    /**
     * @notice Updates the amounts of a reward period
     *
     * @param _rewardPeriodNumber number of the reward period
     * @param _donorAddress address of the donor
     * @param _amount amount to be added
     */
    function updateRewardPeriodAmounts(
        uint256 _rewardPeriodNumber,
        address _donorAddress,
        uint256 _amount
    ) internal {
        RewardPeriod storage _currentPeriod = rewardPeriods[_rewardPeriodNumber];
        _currentPeriod.donationsAmount += _amount;
        _currentPeriod.donorAmounts[_donorAddress] += _amount;
    }

    /**
     * @notice Checks if current reward period has been initialized
     *
     * @return bool true if current reward period has been initialized
     */
    function isCurrentRewardPeriodInitialized() internal view returns (bool) {
        return rewardPeriods[rewardPeriodCount].endBlock >= block.number;
    }

    function _calculateDonorIntervalAmounts(
        address _donorAddress,
        uint256 _startPeriod,
        uint256 _endPeriod
    ) internal view returns (uint256, uint256) {
        uint256 _donorAmount;
        uint256 _totalAmount;
        uint256 _index = _startPeriod;
        for (; _index <= _endPeriod; _index++) {
            RewardPeriod storage _rewardPeriod = rewardPeriods[_index];
            _donorAmount += _rewardPeriod.donorAmounts[_donorAddress];
            _totalAmount += _rewardPeriod.donationsAmount;
        }
        return (_donorAmount, _totalAmount);
    }

    function _getLastClaimablePeriod() internal returns (uint256) {
        initializeRewardPeriods();

        return rewardPeriodCount > claimDelay + 1 ? rewardPeriodCount - 1 - claimDelay : 0;
    }

    /**
     * @notice Computes the rewards
     */
    function _computeRewardsByPeriodNumber(address _donorAddress, uint256 _lastPeriodNumber)
        internal
        returns (uint256)
    {
        Donor storage _donor = donors[_donorAddress];
        uint256 _claimAmount;
        uint256 _lastDonorStakeAmount;

        (_claimAmount, _lastDonorStakeAmount) = _calculateRewardByPeriodNumber(
            _donorAddress,
            _lastPeriodNumber
        );

        if (_donor.lastClaimPeriod < _lastPeriodNumber) {
            _donor.lastClaimPeriod = _lastPeriodNumber;
        }

        rewardPeriods[_lastPeriodNumber].donorStakeAmounts[_donorAddress] = _lastDonorStakeAmount;

        if (_claimAmount == 0) {
            return _claimAmount;
        }

        if (_claimAmount > PACT.balanceOf(address(this))) {
            _claimAmount = PACT.balanceOf(address(this));
        }

        return _claimAmount;
    }

    /**
     * @notice Calculates the reward for a donor starting with his last reward period claimed
     *
     * @param _donorAddress address of the donor
     * @param _lastPeriodNumber last reward period number to be computed
     * @return _claimAmount uint256 sum of all donor's rewards that has not been claimed until _lastPeriodNumber
     * @return _lastDonorStakeAmount uint256 number of PACTs that are staked by the donor at the end of _lastPeriodNumber
     */
    function _calculateRewardByPeriodNumber(address _donorAddress, uint256 _lastPeriodNumber)
        internal
        view
        returns (uint256 _claimAmount, uint256 _lastDonorStakeAmount)
    {
        Donor storage _donor = donors[_donorAddress];

        // _index is the last reward period number for which the donor claimed his reward
        uint256 _index = _donor.lastClaimPeriod + 1;

        // this is only used for the transition from V2 to V3
        // we have to be sure a user is not able to claim for a epoch that he's claimed
        //      so, if the _donor.lastClaimPeriod hasn't been set yet,
        //      we will start from _donor.rewardPeriods[_donor.lastClaim]
        if (_index == 1) {
            _index = _donor.rewardPeriods[_donor.lastClaim] + 1;
        }

        uint256 _donorAmount;
        uint256 _totalAmount;
        uint256 _rewardAmount;
        uint256 _stakesAmount;
        uint256 _stakingDonationRatio;

        //first time _previousRewardPeriod must be rewardPeriods[0] in order to have:
        //_currentRewardPeriod.againstPeriods = _currentRewardPeriod.againstPeriods - _previousRewardPeriod.againstPeriods
        RewardPeriod storage _previousRewardPeriod = rewardPeriods[0];
        RewardPeriod storage _currentRewardPeriod = rewardPeriods[_index];
        RewardPeriod storage _expiredRewardPeriod = rewardPeriods[0];

        //we save the stake amount of a donor at the end of each claim,
        //so rewardPeriods[_index - 1].donorStakeAmounts[_donorAddress] is the amount staked by the donor at his last claim
        _lastDonorStakeAmount = rewardPeriods[_index - 1].donorStakeAmounts[_donorAddress];

        while (_index <= _lastPeriodNumber) {
            if (_currentRewardPeriod.startBlock > 0) {
                // this case is used to calculate the reward for periods that have been initialized

                if (_currentRewardPeriod.againstPeriods == 0) {
                    _donorAmount = _currentRewardPeriod.donorAmounts[_donorAddress];
                    _totalAmount = _currentRewardPeriod.donationsAmount;
                } else if (
                    _previousRewardPeriod.againstPeriods == _currentRewardPeriod.againstPeriods
                ) {
                    if (_index > _currentRewardPeriod.againstPeriods + 1) {
                        _expiredRewardPeriod = rewardPeriods[
                            _index - 1 - _currentRewardPeriod.againstPeriods
                        ];
                        _donorAmount -= _expiredRewardPeriod.donorAmounts[_donorAddress];
                        _totalAmount -= _expiredRewardPeriod.donationsAmount;
                    }

                    _donorAmount += _currentRewardPeriod.donorAmounts[_donorAddress];
                    _totalAmount += _currentRewardPeriod.donationsAmount;
                } else {
                    if (_index > _currentRewardPeriod.againstPeriods) {
                        (_donorAmount, _totalAmount) = _calculateDonorIntervalAmounts(
                            _donorAddress,
                            _index - _currentRewardPeriod.againstPeriods,
                            _index
                        );
                    } else {
                        (_donorAmount, _totalAmount) = _calculateDonorIntervalAmounts(
                            _donorAddress,
                            0,
                            _index
                        );
                    }
                }

                _rewardAmount = _currentRewardPeriod.rewardAmount;
                _stakesAmount = _currentRewardPeriod.stakesAmount;
                _stakingDonationRatio = _currentRewardPeriod.stakingDonationRatio > 0
                    ? _currentRewardPeriod.stakingDonationRatio
                    : 1;
            } else {
                // this case is used to calculate the reward for periods that have not been initialized yet
                // E.g. calculateClaimableRewardsByPeriodNumber & calculateClaimableRewards
                // this step can be reached only after calculating the reward for periods that have been initialized

                if (_index > againstPeriods + 1) {
                    _expiredRewardPeriod = rewardPeriods[_index - 1 - againstPeriods];

                    //we already know that _donorAmount >= _expiredRewardPeriod.donorAmounts[_donorAddress]
                    //because _donorAmount is a sum of some donorAmounts, including _expiredRewardPeriod.donorAmounts[_donorAddress]
                    _donorAmount -= _expiredRewardPeriod.donorAmounts[_donorAddress];
                    //we already know that _totalAmount >= _expiredRewardPeriod.donationsAmount
                    //because _totalAmount is a sum of some donationsAmounts, including _expiredRewardPeriod.donationsAmount
                    _totalAmount -= _expiredRewardPeriod.donationsAmount;
                }

                _donorAmount += _currentRewardPeriod.donorAmounts[_donorAddress];
                _totalAmount += _currentRewardPeriod.donationsAmount;
                _rewardAmount = (_rewardAmount * decayNumerator) / decayDenominator;
            }

            if (_currentRewardPeriod.hasSetStakeAmount[_donorAddress]) {
                _lastDonorStakeAmount = _currentRewardPeriod.donorStakeAmounts[_donorAddress];
            }

            if (_donorAmount + _lastDonorStakeAmount > 0) {
                _claimAmount +=
                    (_rewardAmount *
                        (_donorAmount * _stakingDonationRatio + _lastDonorStakeAmount)) /
                    (_totalAmount * _stakingDonationRatio + _stakesAmount);
            }

            _index++;

            _previousRewardPeriod = _currentRewardPeriod;
            _currentRewardPeriod = rewardPeriods[_index];
        }

        return (_claimAmount, _lastDonorStakeAmount);
    }

    /**
     * @notice Initializes the first reward period
     *
     * @param _startingBlock first block
     * @param _firstRewardPerBlock initial reward per block
     */
    function initFirstPeriod(uint256 _startingBlock, uint256 _firstRewardPerBlock) internal {
        RewardPeriod storage _firstPeriod = rewardPeriods[1];
        _firstPeriod.startBlock = _startingBlock;
        _firstPeriod.endBlock = _startingBlock + rewardPeriodSize - 1;
        _firstPeriod.rewardPerBlock = _firstRewardPerBlock;
        _firstPeriod.rewardAmount = _firstRewardPerBlock * rewardPeriodSize;
    }

    /**
     * @notice Checks if there is any donation or stake between _startPeriod and _endPeriod
     *
     * @return bool true if there is any donation or stake
     */
    function hasDonationOrStake(uint256 _startPeriod, uint256 _endPeriod)
        internal
        view
        returns (bool)
    {
        while (_startPeriod <= _endPeriod) {
            if (
                rewardPeriods[_startPeriod].donationsAmount +
                    rewardPeriods[_startPeriod].stakesAmount >
                0
            ) {
                return true;
            }
            _startPeriod++;
        }
        return false;
    }

    /**
     * @notice Calculates the estimate reward of a donor
     *
     * @param _donorAddress             address of the donor
     * @param _inAdvanceRewardPeriods   number of reward periods in front
     *                                   if _inAdvanceRewardPeriods is 0 the method returns
     *                                        the estimated reward for current reward period
     * @return uint256 reward that donor will receive in current reward period if there isn't another donation
     */
    function _estimateClaimableReward(address _donorAddress, uint256 _inAdvanceRewardPeriods)
        internal
        view
        returns (uint256)
    {
        uint256 _currentPeriodReward = _calculateCurrentPeriodReward();
        uint256 _totalReward = _currentPeriodReward;

        while (_inAdvanceRewardPeriods > 0) {
            _currentPeriodReward = (_currentPeriodReward * decayNumerator) / decayDenominator;
            _totalReward += _currentPeriodReward;
            _inAdvanceRewardPeriods--;
        }
        return _calculateDonorShare(_donorAddress, _totalReward);
    }

    /**
     * @notice Calculates a donor share based on the donations and stakes from the last x rewardPeriods
     *
     *
     * @return uint256  the share from the _total
     */
    function _calculateDonorShare(address _donorAddress, uint256 _total)
        internal
        view
        returns (uint256)
    {
        uint256 _donorAmount;
        uint256 _totalAmount;

        (_donorAmount, _totalAmount) = lastPeriodsDonations(_donorAddress);

        uint256 totalStakeAmount = staking.SPACT().totalSupply();
        if (totalStakeAmount == 0 && _totalAmount == 0) {
            return 0;
        }

        uint256 _stakingDonationRatio = stakingDonationRatio > 0 ? stakingDonationRatio : 1;

        return
            (_total *
                (_donorAmount * _stakingDonationRatio + staking.stakeholderAmount(_donorAddress))) /
            (_totalAmount * _stakingDonationRatio + staking.currentTotalAmount());
    }

    function _calculateCurrentPeriodReward() internal view returns (uint256) {
        uint256 _currentRewardPeriodNumber = currentRewardPeriodNumber();

        uint256 _rewardPerBlock = (rewardPeriods[rewardPeriodCount].rewardPerBlock *
            decayNumerator**(_currentRewardPeriodNumber - rewardPeriodCount)) /
            decayDenominator**(_currentRewardPeriodNumber - rewardPeriodCount);

        return _rewardPerBlock * rewardPeriodSize;
    }
}


// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.4;

interface IUniswapV2Router {
    function factory() external pure returns (address);

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external returns (uint amountA, uint amountB, uint liquidity);
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external returns (uint amountA, uint amountB);
    function removeLiquidityWithPermit(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external returns (uint amountA, uint amountB);
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);
    function swapTokensForExactTokens(
        uint amountOut,
        uint amountInMax,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);

    function quote(uint amountA, uint reserveA, uint reserveB) external pure returns (uint amountB);
    function getAmountOut(uint amountIn, uint reserveIn, uint reserveOut) external pure returns (uint amountOut);
    function getAmountIn(uint amountOut, uint reserveIn, uint reserveOut) external pure returns (uint amountIn);
    function getAmountsOut(uint amountIn, address[] calldata path) external view returns (uint[] memory amounts);
    function getAmountsIn(uint amountOut, address[] calldata path) external view returns (uint[] memory amounts);

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external;

    function pairFor(address tokenA, address tokenB) external view returns (address);
}


//SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.4;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../../community/interfaces/ICommunityAdmin.sol";
import "./IUniswapV2Router.sol";

interface ITreasury {
    struct Token {
        uint256 rate;
        address[] exchangePath;
    }

    function getVersion() external returns(uint256);
    function communityAdmin() external view returns(ICommunityAdmin);
    function uniswapRouter() external view returns(IUniswapV2Router);
    function updateCommunityAdmin(ICommunityAdmin _communityAdmin) external;
    function updateUniswapRouter(IUniswapV2Router _uniswapRouter) external;
    function transfer(IERC20 _token, address _to, uint256 _amount) external;
    function isToken(address _tokenAddress) external view returns (bool);
    function tokenListLength() external view returns (uint256);
    function tokenListAt(uint256 _index) external view returns (address);
    function tokens(address _tokenAddress) external view returns (uint256 rate, address[] memory exchangePath);
    function setToken(address _tokenAddress, uint256 _rate, address[] calldata _exchangePath) external;
    function removeToken(address _tokenAddress) external;
    function getConvertedAmount(address _tokenAddress, uint256 _amount) external view returns (uint256);
    function convertAmount(
        address _tokenAddress,
        uint256 _amountIn,
        uint256 _amountOutMin,
        address[] memory _exchangePath,
        uint256 _deadline
    ) external;
}


//SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.4;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../../donationMiner/interfaces/IDonationMiner.sol";
import "../../interfaces/IMintableERC20.sol";

interface IStaking {
    struct Unstake {
        uint256 amount;         //amount unstaked
        uint256 cooldownBlock;  //first block number that will allow holder to claim this unstake
    }

    struct Holder {
        uint256 amount;          // amount of PACT that are staked by holder
        uint256 nextUnstakeId;   //
        Unstake[] unstakes;      //list of all unstakes amount
    }

    function getVersion() external view returns(uint256);
    function updateCooldown(uint256 _newCooldown) external;
    function PACT() external view returns (IERC20);
    function SPACT() external view returns (IMintableERC20);
    function donationMiner() external view returns (IDonationMiner);
    function cooldown() external view returns(uint256);
    function currentTotalAmount() external view returns(uint256);
    function stakeholderAmount(address _holderAddress) external view returns(uint256);
    function stakeholder(address _holderAddress) external view returns (uint256 amount, uint256 nextUnstakeId, uint256 unstakeListLength, uint256 unstakedAmount);
    function stakeholderUnstakeAt(address _holderAddress, uint256 _unstakeIndex) external view returns (Unstake memory);
    function stakeholdersListAt(uint256 _index) external view returns (address);
    function stakeholdersListLength() external view returns (uint256);

    function stake(address _holder, uint256 _amount) external;
    function unstake(uint256 _amount) external;
    function claim() external;
    function claimPartial(uint256 _lastUnstakeId) external;
    function claimAmount(address _holderAddress) external view returns (uint256);
}


//SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.4;

interface IMintableERC20 {
    function mint(address _account, uint96 _amount) external;

    function burn(address _account, uint96 _amount) external;

    function totalSupply() external view returns (uint256);

    function balanceOf(address _account) external view returns (uint256);

    function transfer(address _recipient, uint256 _amount) external returns (bool);

    function allowance(address _owner, address _spender) external view returns (uint256);

    function approve(address _spender, uint256 _amount) external returns (bool);

    function transferFrom(
        address _sender,
        address _recipient,
        uint256 _amount
    ) external returns (bool);
}


// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.4;

import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IImpactMarketCouncil {
    //
}


//SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.4;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../../community/interfaces/ICommunityAdmin.sol";
import "../../treasury/interfaces/ITreasury.sol";
import "../../staking/interfaces/IStaking.sol";

interface IDonationMiner {
    struct RewardPeriod {
        //reward tokens created per block
        uint256 rewardPerBlock;
        //reward tokens from previous periods + reward tokens from this reward period
        uint256 rewardAmount;
        //block number at which reward period starts
        uint256 startBlock;
        //block number at which reward period ends
        uint256 endBlock;
        //total of donations for this rewardPeriod
        uint256 donationsAmount;
        //amounts donated by every donor in this rewardPeriod
        mapping(address => uint256) donorAmounts;
        uint256 againstPeriods;
        //total stake amount at the end of this rewardPeriod
        uint256 stakesAmount;
        //ratio between 1 cUSD donated and 1 PACT staked
        uint256 stakingDonationRatio;
        //true if user has staked/unstaked in this reward period
        mapping(address => bool) hasSetStakeAmount;
        //stake amount of a user at the end of this reward period;
        //if a user doesn't stake/unstake in a reward period,
        //              this value will remain 0 (and hasSetStakeAmount will be false)
        //if hasNewStakeAmount is false it means the donorStakeAmount
        //              is the same as the last reward period where hasSetStakeAmount is true
        mapping(address => uint256) donorStakeAmounts;
    }

    struct Donor {
        uint256 lastClaim;  //last reward period index for which the donor has claimed the reward; used until v2
        uint256 rewardPeriodsCount; //total number of reward periods in which the donor donated
        mapping(uint256 => uint256) rewardPeriods; //list of all reward period ids in which the donor donated
        uint256 lastClaimPeriod; //last reward period id for which the donor has claimed the reward
    }

    struct Donation {
        address donor;  //address of the donner
        address target;  //address of the receiver (community or treasury)
        uint256 rewardPeriod;  //number of the reward period in which the donation was made
        uint256 blockNumber;  //number of the block in which the donation was executed
        uint256 amount;  //the convertedAmount value
        IERC20 token;  //address of the token
        uint256 initialAmount;  //number of tokens donated
    }

    function getVersion() external returns(uint256);
    function cUSD() external view returns (IERC20);
    function PACT() external view returns (IERC20);
    function treasury() external view returns (ITreasury);
    function staking() external view returns (IStaking);
    function rewardPeriodSize() external view returns (uint256);
    function decayNumerator() external view returns (uint256);
    function decayDenominator() external view returns (uint256);
    function stakingDonationRatio() external view returns (uint256);
    function communityDonationRatio() external view returns (uint256);
    function rewardPeriodCount() external view returns (uint256);
    function donationCount() external view returns (uint256);
    function rewardPeriods(uint256 _period) external view returns (
        uint256 rewardPerBlock,
        uint256 rewardAmount,
        uint256 startBlock,
        uint256 endBlock,
        uint256 donationsAmount,
        uint256 againstPeriods,
        uint256 stakesAmount,
        uint256 stakingDonationRatio

);
    function rewardPeriodDonorAmount(uint256 _period, address _donor) external view returns (uint256);
    function rewardPeriodDonorStakeAmounts(uint256 _period, address _donor) external view returns (uint256);
    function donors(address _donor) external view returns (
        uint256 rewardPeriodsCount,
        uint256 lastClaim,
        uint256 lastClaimPeriod
    );
    function donorRewardPeriod(address _donor, uint256 _rewardPeriodIndex) external view returns (uint256);
    function donations(uint256 _index) external view returns (
        address donor,
        address target,
        uint256 rewardPeriod,
        uint256 blockNumber,
        uint256 amount,
        IERC20 token,
        uint256 tokenPrice
    );
    function claimDelay() external view returns (uint256);
    function againstPeriods() external view returns (uint256);
    function updateRewardPeriodParams(
        uint256 _newRewardPeriodSize,
        uint256 _newDecayNumerator,
        uint256 _newDecayDenominator
    ) external;
    function updateClaimDelay(uint256 _newClaimDelay) external;
    function updateStakingDonationRatio(uint256 _newStakingDonationRatio) external;
    function updateCommunityDonationRatio(uint256 _newCommunityDonationRatio) external;
    function updateAgainstPeriods(uint256 _newAgainstPeriods) external;
    function updateTreasury(ITreasury _newTreasury) external;
    function updateStaking(IStaking _newStaking) external;
    function donate(IERC20 _token, uint256 _amount, address _delegateAddress) external;
    function donateToCommunity(ICommunity _community, IERC20 _token, uint256 _amount, address _delegateAddress) external;
    function claimRewards() external;
    function claimRewardsPartial(uint256 _lastPeriodNumber) external;
    function stakeRewards() external;
    function stakeRewardsPartial(uint256 _lastPeriodNumber) external;
    function calculateClaimableRewards(address _donor) external returns (uint256);
    function calculateClaimableRewardsByPeriodNumber(address _donor, uint256 _lastPeriodNumber) external returns (uint256);
    function estimateClaimableReward(address _donor) external view returns (uint256);
    function estimateClaimableRewardAdvance(address _donor) external view returns (uint256);
    function estimateClaimableRewardByStaking(address _donor) external view returns (uint256);
    function apr(address _stakeholderAddress) external view returns (uint256);
    function generalApr() external view returns (uint256);
    function lastPeriodsDonations(address _donor) external view returns (uint256 donorAmount, uint256 totalAmount);
    function transfer(IERC20 _token, address _to, uint256 _amount) external;
    function setStakingAmounts(address _holderAddress, uint256 _holderStakeAmount, uint256 _totalStakesAmount) external;
    function currentRewardPeriodNumber() external view returns (uint256);

}


// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.4;

import "./DonationMinerStorageV3.sol";

/**
 * @title Storage for DonationMiner
 * @notice For future upgrades, do not change DonationMinerStorageV4. Create a new
 * contract which implements DonationMinerStorageV4 and following the naming convention
 * DonationMinerStorageVX.
 */
abstract contract DonationMinerStorageV4 is DonationMinerStorageV3 {
    IStaking public override staking;
    //ratio between 1 cUSD donated and 1 PACT staked
    uint256 public override stakingDonationRatio;
    uint256 public override communityDonationRatio;
}


// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.4;

import "./DonationMinerStorageV2.sol";

/**
 * @title Storage for DonationMiner
 * @notice For future upgrades, do not change DonationMinerStorageV3. Create a new
 * contract which implements DonationMinerStorageV3 and following the naming convention
 * DonationMinerStorageVX.
 */
abstract contract DonationMinerStorageV3 is DonationMinerStorageV2 {
    uint256 public override againstPeriods;
}


// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.4;

import "./DonationMinerStorageV1.sol";

/**
 * @title Storage for DonationMiner
 * @notice For future upgrades, do not change DonationMinerStorageV2. Create a new
 * contract which implements DonationMinerStorageV2 and following the naming convention
 * DonationMinerStorageVX.
 */
abstract contract DonationMinerStorageV2 is DonationMinerStorageV1 {
    uint256 public override claimDelay;
}


// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.4;

import "./IDonationMiner.sol";

/**
 * @title Storage for DonationMiner
 * @notice For future upgrades, do not change DonationMinerStorageV1. Create a new
 * contract which implements DonationMinerStorageV1 and following the naming convention
 * DonationMinerStorageVX.
 */
abstract contract DonationMinerStorageV1 is IDonationMiner {
    IERC20 public override cUSD;
    IERC20 public override PACT;
    ITreasury public override treasury;
    uint256 public override rewardPeriodSize;
    uint256 public override donationCount;
    uint256 public override rewardPeriodCount;
    uint256 public override decayNumerator;
    uint256 public override decayDenominator;

    mapping(uint256 => Donation) public override donations;
    mapping(uint256 => RewardPeriod) public override rewardPeriods;
    mapping(address => Donor) public override donors;
}


// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.4;

import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./ICommunity.sol";
import "../../treasury/interfaces/ITreasury.sol";
import "../../governor/impactMarketCouncil/interfaces/IImpactMarketCouncil.sol";
import "../../ambassadors/interfaces/IAmbassadors.sol";

interface ICommunityAdmin {
    enum CommunityState {
        NONE,
        Valid,
        Removed,
        Migrated
    }

    function getVersion() external returns(uint256);
    function cUSD() external view returns(IERC20);
    function treasury() external view returns(ITreasury);
    function impactMarketCouncil() external view returns(IImpactMarketCouncil);
    function ambassadors() external view returns(IAmbassadors);
    function communityMiddleProxy() external view returns(address);
    function communities(address _community) external view returns(CommunityState);
    function communityImplementation() external view returns(ICommunity);
    function communityProxyAdmin() external view returns(ProxyAdmin);
    function communityListAt(uint256 _index) external view returns (address);
    function communityListLength() external view returns (uint256);
    function isAmbassadorOrEntityOfCommunity(address _community, address _ambassadorOrEntity) external view returns (bool);
    function updateTreasury(ITreasury _newTreasury) external;
    function updateImpactMarketCouncil(IImpactMarketCouncil _newImpactMarketCouncil) external;
    function updateAmbassadors(IAmbassadors _newAmbassadors) external;
    function updateCommunityMiddleProxy(address _communityMiddleProxy) external;
    function updateCommunityImplementation(ICommunity _communityImplementation_) external;
    function setCommunityToAmbassador(address _ambassador, ICommunity _communityAddress) external;
    function updateBeneficiaryParams(
        ICommunity _community,
        uint256 _claimAmount,
        uint256 _maxClaim,
        uint256 _decreaseStep,
        uint256 _baseInterval,
        uint256 _incrementInterval,
        uint256 _maxBeneficiaries
    ) external;
    function updateCommunityParams(
        ICommunity _community,
        uint256 _minTranche,
        uint256 _maxTranche
    ) external;
    function updateProxyImplementation(address _CommunityMiddleProxy, address _newLogic) external;
    function updateCommunityToken(
        ICommunity _community,
        IERC20 _newToken,
        address[] memory _exchangePath
    ) external;
    function addCommunity(
        address[] memory _managers,
        address _ambassador,
        uint256 _claimAmount,
        uint256 _maxClaim,
        uint256 _decreaseStep,
        uint256 _baseInterval,
        uint256 _incrementInterval,
        uint256 _minTranche,
        uint256 _maxTranche,
        uint256 _maxBeneficiaries
    ) external;
    function migrateCommunity(
        address[] memory _managers,
        ICommunity _previousCommunity
    ) external;
    function removeCommunity(ICommunity _community) external;
    function fundCommunity() external;
    function transfer(IERC20 _token, address _to, uint256 _amount) external;
    function transferFromCommunity(
        ICommunity _community,
        IERC20 _token,
        address _to,
        uint256 _amount
    ) external;
}


// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.4;

import "@openzeppelin/contracts-upgradeable/access/IAccessControlUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./ICommunityAdmin.sol";

interface ICommunity {
    enum BeneficiaryState {
        NONE, //the beneficiary hasn't been added yet
        Valid,
        Locked,
        Removed
    }

    struct Beneficiary {
        BeneficiaryState state;  //beneficiary state
        uint256 claims;          //total number of claims
        uint256 claimedAmount;   //total amount of cUSD received
        uint256 lastClaim;       //block number of the last claim
    }

    function initialize(
        address[] memory _managers,
        uint256 _claimAmount,
        uint256 _maxClaim,
        uint256 _decreaseStep,
        uint256 _baseInterval,
        uint256 _incrementInterval,
        uint256 _minTranche,
        uint256 _maxTranche,
        uint256 _maxBeneficiaries,
        ICommunity _previousCommunity
    ) external;
    function getVersion() external returns(uint256);
    function previousCommunity() external view returns(ICommunity);
    function claimAmount() external view returns(uint256);
    function baseInterval() external view returns(uint256);
    function incrementInterval() external view returns(uint256);
    function maxClaim() external view returns(uint256);
    function validBeneficiaryCount() external view returns(uint);
    function maxBeneficiaries() external view returns(uint);
    function treasuryFunds() external view returns(uint);
    function privateFunds() external view returns(uint);
    function communityAdmin() external view returns(ICommunityAdmin);
    function cUSD() external view  returns(IERC20);
    function token() external view  returns(IERC20);
    function locked() external view returns(bool);
    function beneficiaries(address _beneficiaryAddress) external view returns(
        BeneficiaryState state,
        uint256 claims,
        uint256 claimedAmount,
        uint256 lastClaim
    );
    function decreaseStep() external view returns(uint);
    function beneficiaryListAt(uint256 _index) external view returns (address);
    function beneficiaryListLength() external view returns (uint256);
    function impactMarketAddress() external pure returns (address);
    function minTranche() external view returns(uint256);
    function maxTranche() external view returns(uint256);
    function lastFundRequest() external view returns(uint256);

    function updateCommunityAdmin(ICommunityAdmin _communityAdmin) external;
    function updatePreviousCommunity(ICommunity _newPreviousCommunity) external;
    function updateBeneficiaryParams(
        uint256 _claimAmount,
        uint256 _maxClaim,
        uint256 _decreaseStep,
        uint256 _baseInterval,
        uint256 _incrementInterval
    ) external;
    function updateCommunityParams(
        uint256 _minTranche,
        uint256 _maxTranche
    ) external;
    function updateMaxBeneficiaries(uint256 _newMaxBeneficiaries) external;
    function updateToken(IERC20 _newToken, address[] memory _exchangePath) external;
    function donate(address _sender, uint256 _amount) external;
    function addTreasuryFunds(uint256 _amount) external;
    function transfer(IERC20 _token, address _to, uint256 _amount) external;
    function addManager(address _managerAddress) external;
    function removeManager(address _managerAddress) external;
    function addBeneficiaries(address[] memory _beneficiaryAddresses) external;
    function addBeneficiary(address _beneficiaryAddress) external;
    function lockBeneficiary(address _beneficiaryAddress) external;
    function unlockBeneficiary(address _beneficiaryAddress) external;
    function removeBeneficiary(address _beneficiaryAddress) external;
    function claim() external;
    function lastInterval(address _beneficiaryAddress) external view returns (uint256);
    function claimCooldown(address _beneficiaryAddress) external view returns (uint256);
    function lock() external;
    function unlock() external;
    function requestFunds() external;
    function beneficiaryJoinFromMigrated(address _beneficiaryAddress) external;
    function getInitialMaxClaim() external view returns (uint256);
}


// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.4;

interface IAmbassadors {
    function getVersion() external returns(uint256);
    function isAmbassador(address _ambassador) external view returns (bool);
    function isAmbassadorOf(address _ambassador, address _community) external view returns (bool);
    function isEntityOf(address _ambassador, address _entityAddress) external view returns (bool);
    function isAmbassadorAt(address _ambassador, address _entityAddress) external view returns (bool);

    function addEntity(address _entity) external;
    function removeEntity(address _entity) external;
    function replaceEntityAccount(address _entity, address _newEntity) external;
    function addAmbassador(address _ambassador) external;
    function removeAmbassador(address _ambassador) external;
    function replaceAmbassadorAccount(address _ambassador, address _newAmbassador) external;
    function replaceAmbassador(address _oldAmbassador, address _newAmbassador) external;
    function transferAmbassador(address _ambassador, address _toEntity, bool _keepCommunities) external;
    function transferCommunityToAmbassador(address _to, address _community) external;
    function setCommunityToAmbassador(address _ambassador, address _community) external;
    function removeCommunity(address _community) external;
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
// OpenZeppelin Contracts v4.4.1 (utils/math/Math.sol)

pragma solidity ^0.8.0;

/**
 * @dev Standard math utilities missing in the Solidity language.
 */
library Math {
    /**
     * @dev Returns the largest of two numbers.
     */
    function max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a >= b ? a : b;
    }

    /**
     * @dev Returns the smallest of two numbers.
     */
    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    /**
     * @dev Returns the average of two numbers. The result is rounded towards
     * zero.
     */
    function average(uint256 a, uint256 b) internal pure returns (uint256) {
        // (a + b) / 2 can overflow.
        return (a & b) + (a ^ b) / 2;
    }

    /**
     * @dev Returns the ceiling of the division of two numbers.
     *
     * This differs from standard division with `/` in that it rounds up instead
     * of rounding down.
     */
    function ceilDiv(uint256 a, uint256 b) internal pure returns (uint256) {
        // (a + b - 1) / b can overflow on addition, so we distribute.
        return a / b + (a % b == 0 ? 0 : 1);
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
        __Context_init_unchained();
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
// OpenZeppelin Contracts v4.4.1 (access/IAccessControl.sol)

pragma solidity ^0.8.0;

/**
 * @dev External interface of AccessControl declared to support ERC165 detection.
 */
interface IAccessControlUpgradeable {
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
// OpenZeppelin Contracts v4.4.1 (utils/StorageSlot.sol)

pragma solidity ^0.8.0;

/**
 * @dev Library for reading and writing primitive types to specific storage slots.
 *
 * Storage slots are often used to avoid storage conflict when dealing with upgradeable contracts.
 * This library helps with reading and writing to such slots without the need for inline assembly.
 *
 * The functions in this library return Slot structs that contain a `value` member that can be used to read or write.
 *
 * Example usage to set ERC1967 implementation slot:
 * ```
 * contract ERC1967 {
 *     bytes32 internal constant _IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
 *
 *     function _getImplementation() internal view returns (address) {
 *         return StorageSlot.getAddressSlot(_IMPLEMENTATION_SLOT).value;
 *     }
 *
 *     function _setImplementation(address newImplementation) internal {
 *         require(Address.isContract(newImplementation), "ERC1967: new implementation is not a contract");
 *         StorageSlot.getAddressSlot(_IMPLEMENTATION_SLOT).value = newImplementation;
 *     }
 * }
 * ```
 *
 * _Available since v4.1 for `address`, `bool`, `bytes32`, and `uint256`._
 */
library StorageSlot {
    struct AddressSlot {
        address value;
    }

    struct BooleanSlot {
        bool value;
    }

    struct Bytes32Slot {
        bytes32 value;
    }

    struct Uint256Slot {
        uint256 value;
    }

    /**
     * @dev Returns an `AddressSlot` with member `value` located at `slot`.
     */
    function getAddressSlot(bytes32 slot) internal pure returns (AddressSlot storage r) {
        assembly {
            r.slot := slot
        }
    }

    /**
     * @dev Returns an `BooleanSlot` with member `value` located at `slot`.
     */
    function getBooleanSlot(bytes32 slot) internal pure returns (BooleanSlot storage r) {
        assembly {
            r.slot := slot
        }
    }

    /**
     * @dev Returns an `Bytes32Slot` with member `value` located at `slot`.
     */
    function getBytes32Slot(bytes32 slot) internal pure returns (Bytes32Slot storage r) {
        assembly {
            r.slot := slot
        }
    }

    /**
     * @dev Returns an `Uint256Slot` with member `value` located at `slot`.
     */
    function getUint256Slot(bytes32 slot) internal pure returns (Uint256Slot storage r) {
        assembly {
            r.slot := slot
        }
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


// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts v4.4.1 (proxy/transparent/TransparentUpgradeableProxy.sol)

pragma solidity ^0.8.0;

import "../ERC1967/ERC1967Proxy.sol";

/**
 * @dev This contract implements a proxy that is upgradeable by an admin.
 *
 * To avoid https://medium.com/nomic-labs-blog/malicious-backdoors-in-ethereum-proxies-62629adf3357[proxy selector
 * clashing], which can potentially be used in an attack, this contract uses the
 * https://blog.openzeppelin.com/the-transparent-proxy-pattern/[transparent proxy pattern]. This pattern implies two
 * things that go hand in hand:
 *
 * 1. If any account other than the admin calls the proxy, the call will be forwarded to the implementation, even if
 * that call matches one of the admin functions exposed by the proxy itself.
 * 2. If the admin calls the proxy, it can access the admin functions, but its calls will never be forwarded to the
 * implementation. If the admin tries to call a function on the implementation it will fail with an error that says
 * "admin cannot fallback to proxy target".
 *
 * These properties mean that the admin account can only be used for admin actions like upgrading the proxy or changing
 * the admin, so it's best if it's a dedicated account that is not used for anything else. This will avoid headaches due
 * to sudden errors when trying to call a function from the proxy implementation.
 *
 * Our recommendation is for the dedicated account to be an instance of the {ProxyAdmin} contract. If set up this way,
 * you should think of the `ProxyAdmin` instance as the real administrative interface of your proxy.
 */
contract TransparentUpgradeableProxy is ERC1967Proxy {
    /**
     * @dev Initializes an upgradeable proxy managed by `_admin`, backed by the implementation at `_logic`, and
     * optionally initialized with `_data` as explained in {ERC1967Proxy-constructor}.
     */
    constructor(
        address _logic,
        address admin_,
        bytes memory _data
    ) payable ERC1967Proxy(_logic, _data) {
        assert(_ADMIN_SLOT == bytes32(uint256(keccak256("eip1967.proxy.admin")) - 1));
        _changeAdmin(admin_);
    }

    /**
     * @dev Modifier used internally that will delegate the call to the implementation unless the sender is the admin.
     */
    modifier ifAdmin() {
        if (msg.sender == _getAdmin()) {
            _;
        } else {
            _fallback();
        }
    }

    /**
     * @dev Returns the current admin.
     *
     * NOTE: Only the admin can call this function. See {ProxyAdmin-getProxyAdmin}.
     *
     * TIP: To get this value clients can read directly from the storage slot shown below (specified by EIP1967) using the
     * https://eth.wiki/json-rpc/API#eth_getstorageat[`eth_getStorageAt`] RPC call.
     * `0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103`
     */
    function admin() external ifAdmin returns (address admin_) {
        admin_ = _getAdmin();
    }

    /**
     * @dev Returns the current implementation.
     *
     * NOTE: Only the admin can call this function. See {ProxyAdmin-getProxyImplementation}.
     *
     * TIP: To get this value clients can read directly from the storage slot shown below (specified by EIP1967) using the
     * https://eth.wiki/json-rpc/API#eth_getstorageat[`eth_getStorageAt`] RPC call.
     * `0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc`
     */
    function implementation() external ifAdmin returns (address implementation_) {
        implementation_ = _implementation();
    }

    /**
     * @dev Changes the admin of the proxy.
     *
     * Emits an {AdminChanged} event.
     *
     * NOTE: Only the admin can call this function. See {ProxyAdmin-changeProxyAdmin}.
     */
    function changeAdmin(address newAdmin) external virtual ifAdmin {
        _changeAdmin(newAdmin);
    }

    /**
     * @dev Upgrade the implementation of the proxy.
     *
     * NOTE: Only the admin can call this function. See {ProxyAdmin-upgrade}.
     */
    function upgradeTo(address newImplementation) external ifAdmin {
        _upgradeToAndCall(newImplementation, bytes(""), false);
    }

    /**
     * @dev Upgrade the implementation of the proxy, and then call a function from the new implementation as specified
     * by `data`, which should be an encoded function call. This is useful to initialize new storage variables in the
     * proxied contract.
     *
     * NOTE: Only the admin can call this function. See {ProxyAdmin-upgradeAndCall}.
     */
    function upgradeToAndCall(address newImplementation, bytes calldata data) external payable ifAdmin {
        _upgradeToAndCall(newImplementation, data, true);
    }

    /**
     * @dev Returns the current admin.
     */
    function _admin() internal view virtual returns (address) {
        return _getAdmin();
    }

    /**
     * @dev Makes sure the admin cannot access the fallback function. See {Proxy-_beforeFallback}.
     */
    function _beforeFallback() internal virtual override {
        require(msg.sender != _getAdmin(), "TransparentUpgradeableProxy: admin cannot fallback to proxy target");
        super._beforeFallback();
    }
}


// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts v4.4.1 (proxy/transparent/ProxyAdmin.sol)

pragma solidity ^0.8.0;

import "./TransparentUpgradeableProxy.sol";
import "../../access/Ownable.sol";

/**
 * @dev This is an auxiliary contract meant to be assigned as the admin of a {TransparentUpgradeableProxy}. For an
 * explanation of why you would want to use this see the documentation for {TransparentUpgradeableProxy}.
 */
contract ProxyAdmin is Ownable {
    /**
     * @dev Returns the current implementation of `proxy`.
     *
     * Requirements:
     *
     * - This contract must be the admin of `proxy`.
     */
    function getProxyImplementation(TransparentUpgradeableProxy proxy) public view virtual returns (address) {
        // We need to manually run the static call since the getter cannot be flagged as view
        // bytes4(keccak256("implementation()")) == 0x5c60da1b
        (bool success, bytes memory returndata) = address(proxy).staticcall(hex"5c60da1b");
        require(success);
        return abi.decode(returndata, (address));
    }

    /**
     * @dev Returns the current admin of `proxy`.
     *
     * Requirements:
     *
     * - This contract must be the admin of `proxy`.
     */
    function getProxyAdmin(TransparentUpgradeableProxy proxy) public view virtual returns (address) {
        // We need to manually run the static call since the getter cannot be flagged as view
        // bytes4(keccak256("admin()")) == 0xf851a440
        (bool success, bytes memory returndata) = address(proxy).staticcall(hex"f851a440");
        require(success);
        return abi.decode(returndata, (address));
    }

    /**
     * @dev Changes the admin of `proxy` to `newAdmin`.
     *
     * Requirements:
     *
     * - This contract must be the current admin of `proxy`.
     */
    function changeProxyAdmin(TransparentUpgradeableProxy proxy, address newAdmin) public virtual onlyOwner {
        proxy.changeAdmin(newAdmin);
    }

    /**
     * @dev Upgrades `proxy` to `implementation`. See {TransparentUpgradeableProxy-upgradeTo}.
     *
     * Requirements:
     *
     * - This contract must be the admin of `proxy`.
     */
    function upgrade(TransparentUpgradeableProxy proxy, address implementation) public virtual onlyOwner {
        proxy.upgradeTo(implementation);
    }

    /**
     * @dev Upgrades `proxy` to `implementation` and calls a function on the new implementation. See
     * {TransparentUpgradeableProxy-upgradeToAndCall}.
     *
     * Requirements:
     *
     * - This contract must be the admin of `proxy`.
     */
    function upgradeAndCall(
        TransparentUpgradeableProxy proxy,
        address implementation,
        bytes memory data
    ) public payable virtual onlyOwner {
        proxy.upgradeToAndCall{value: msg.value}(implementation, data);
    }
}


// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts v4.4.1 (proxy/beacon/IBeacon.sol)

pragma solidity ^0.8.0;

/**
 * @dev This is the interface that {BeaconProxy} expects of its beacon.
 */
interface IBeacon {
    /**
     * @dev Must return an address that can be used as a delegate call target.
     *
     * {BeaconProxy} will check that this address is a contract.
     */
    function implementation() external view returns (address);
}


// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts v4.4.1 (proxy/Proxy.sol)

pragma solidity ^0.8.0;

/**
 * @dev This abstract contract provides a fallback function that delegates all calls to another contract using the EVM
 * instruction `delegatecall`. We refer to the second contract as the _implementation_ behind the proxy, and it has to
 * be specified by overriding the virtual {_implementation} function.
 *
 * Additionally, delegation to the implementation can be triggered manually through the {_fallback} function, or to a
 * different contract through the {_delegate} function.
 *
 * The success and return data of the delegated call will be returned back to the caller of the proxy.
 */
abstract contract Proxy {
    /**
     * @dev Delegates the current call to `implementation`.
     *
     * This function does not return to its internall call site, it will return directly to the external caller.
     */
    function _delegate(address implementation) internal virtual {
        assembly {
            // Copy msg.data. We take full control of memory in this inline assembly
            // block because it will not return to Solidity code. We overwrite the
            // Solidity scratch pad at memory position 0.
            calldatacopy(0, 0, calldatasize())

            // Call the implementation.
            // out and outsize are 0 because we don't know the size yet.
            let result := delegatecall(gas(), implementation, 0, calldatasize(), 0, 0)

            // Copy the returned data.
            returndatacopy(0, 0, returndatasize())

            switch result
            // delegatecall returns 0 on error.
            case 0 {
                revert(0, returndatasize())
            }
            default {
                return(0, returndatasize())
            }
        }
    }

    /**
     * @dev This is a virtual function that should be overriden so it returns the address to which the fallback function
     * and {_fallback} should delegate.
     */
    function _implementation() internal view virtual returns (address);

    /**
     * @dev Delegates the current call to the address returned by `_implementation()`.
     *
     * This function does not return to its internall call site, it will return directly to the external caller.
     */
    function _fallback() internal virtual {
        _beforeFallback();
        _delegate(_implementation());
    }

    /**
     * @dev Fallback function that delegates calls to the address returned by `_implementation()`. Will run if no other
     * function in the contract matches the call data.
     */
    fallback() external payable virtual {
        _fallback();
    }

    /**
     * @dev Fallback function that delegates calls to the address returned by `_implementation()`. Will run if call data
     * is empty.
     */
    receive() external payable virtual {
        _fallback();
    }

    /**
     * @dev Hook that is called before falling back to the implementation. Can happen as part of a manual `_fallback`
     * call, or as part of the Solidity `fallback` or `receive` functions.
     *
     * If overriden should call `super._beforeFallback()`.
     */
    function _beforeFallback() internal virtual {}
}


// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts v4.4.1 (proxy/ERC1967/ERC1967Upgrade.sol)

pragma solidity ^0.8.2;

import "../beacon/IBeacon.sol";
import "../../utils/Address.sol";
import "../../utils/StorageSlot.sol";

/**
 * @dev This abstract contract provides getters and event emitting update functions for
 * https://eips.ethereum.org/EIPS/eip-1967[EIP1967] slots.
 *
 * _Available since v4.1._
 *
 * @custom:oz-upgrades-unsafe-allow delegatecall
 */
abstract contract ERC1967Upgrade {
    // This is the keccak-256 hash of "eip1967.proxy.rollback" subtracted by 1
    bytes32 private constant _ROLLBACK_SLOT = 0x4910fdfa16fed3260ed0e7147f7cc6da11a60208b5b9406d12a635614ffd9143;

    /**
     * @dev Storage slot with the address of the current implementation.
     * This is the keccak-256 hash of "eip1967.proxy.implementation" subtracted by 1, and is
     * validated in the constructor.
     */
    bytes32 internal constant _IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    /**
     * @dev Emitted when the implementation is upgraded.
     */
    event Upgraded(address indexed implementation);

    /**
     * @dev Returns the current implementation address.
     */
    function _getImplementation() internal view returns (address) {
        return StorageSlot.getAddressSlot(_IMPLEMENTATION_SLOT).value;
    }

    /**
     * @dev Stores a new address in the EIP1967 implementation slot.
     */
    function _setImplementation(address newImplementation) private {
        require(Address.isContract(newImplementation), "ERC1967: new implementation is not a contract");
        StorageSlot.getAddressSlot(_IMPLEMENTATION_SLOT).value = newImplementation;
    }

    /**
     * @dev Perform implementation upgrade
     *
     * Emits an {Upgraded} event.
     */
    function _upgradeTo(address newImplementation) internal {
        _setImplementation(newImplementation);
        emit Upgraded(newImplementation);
    }

    /**
     * @dev Perform implementation upgrade with additional setup call.
     *
     * Emits an {Upgraded} event.
     */
    function _upgradeToAndCall(
        address newImplementation,
        bytes memory data,
        bool forceCall
    ) internal {
        _upgradeTo(newImplementation);
        if (data.length > 0 || forceCall) {
            Address.functionDelegateCall(newImplementation, data);
        }
    }

    /**
     * @dev Perform implementation upgrade with security checks for UUPS proxies, and additional setup call.
     *
     * Emits an {Upgraded} event.
     */
    function _upgradeToAndCallSecure(
        address newImplementation,
        bytes memory data,
        bool forceCall
    ) internal {
        address oldImplementation = _getImplementation();

        // Initial upgrade and setup call
        _setImplementation(newImplementation);
        if (data.length > 0 || forceCall) {
            Address.functionDelegateCall(newImplementation, data);
        }

        // Perform rollback test if not already in progress
        StorageSlot.BooleanSlot storage rollbackTesting = StorageSlot.getBooleanSlot(_ROLLBACK_SLOT);
        if (!rollbackTesting.value) {
            // Trigger rollback using upgradeTo from the new implementation
            rollbackTesting.value = true;
            Address.functionDelegateCall(
                newImplementation,
                abi.encodeWithSignature("upgradeTo(address)", oldImplementation)
            );
            rollbackTesting.value = false;
            // Check rollback was effective
            require(oldImplementation == _getImplementation(), "ERC1967Upgrade: upgrade breaks further upgrades");
            // Finally reset to the new implementation and log the upgrade
            _upgradeTo(newImplementation);
        }
    }

    /**
     * @dev Storage slot with the admin of the contract.
     * This is the keccak-256 hash of "eip1967.proxy.admin" subtracted by 1, and is
     * validated in the constructor.
     */
    bytes32 internal constant _ADMIN_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    /**
     * @dev Emitted when the admin account has changed.
     */
    event AdminChanged(address previousAdmin, address newAdmin);

    /**
     * @dev Returns the current admin.
     */
    function _getAdmin() internal view returns (address) {
        return StorageSlot.getAddressSlot(_ADMIN_SLOT).value;
    }

    /**
     * @dev Stores a new address in the EIP1967 admin slot.
     */
    function _setAdmin(address newAdmin) private {
        require(newAdmin != address(0), "ERC1967: new admin is the zero address");
        StorageSlot.getAddressSlot(_ADMIN_SLOT).value = newAdmin;
    }

    /**
     * @dev Changes the admin of the proxy.
     *
     * Emits an {AdminChanged} event.
     */
    function _changeAdmin(address newAdmin) internal {
        emit AdminChanged(_getAdmin(), newAdmin);
        _setAdmin(newAdmin);
    }

    /**
     * @dev The storage slot of the UpgradeableBeacon contract which defines the implementation for this proxy.
     * This is bytes32(uint256(keccak256('eip1967.proxy.beacon')) - 1)) and is validated in the constructor.
     */
    bytes32 internal constant _BEACON_SLOT = 0xa3f0ad74e5423aebfd80d3ef4346578335a9a72aeaee59ff6cb3582b35133d50;

    /**
     * @dev Emitted when the beacon is upgraded.
     */
    event BeaconUpgraded(address indexed beacon);

    /**
     * @dev Returns the current beacon.
     */
    function _getBeacon() internal view returns (address) {
        return StorageSlot.getAddressSlot(_BEACON_SLOT).value;
    }

    /**
     * @dev Stores a new beacon in the EIP1967 beacon slot.
     */
    function _setBeacon(address newBeacon) private {
        require(Address.isContract(newBeacon), "ERC1967: new beacon is not a contract");
        require(
            Address.isContract(IBeacon(newBeacon).implementation()),
            "ERC1967: beacon implementation is not a contract"
        );
        StorageSlot.getAddressSlot(_BEACON_SLOT).value = newBeacon;
    }

    /**
     * @dev Perform beacon upgrade with additional setup call. Note: This upgrades the address of the beacon, it does
     * not upgrade the implementation contained in the beacon (see {UpgradeableBeacon-_setImplementation} for that).
     *
     * Emits a {BeaconUpgraded} event.
     */
    function _upgradeBeaconToAndCall(
        address newBeacon,
        bytes memory data,
        bool forceCall
    ) internal {
        _setBeacon(newBeacon);
        emit BeaconUpgraded(newBeacon);
        if (data.length > 0 || forceCall) {
            Address.functionDelegateCall(IBeacon(newBeacon).implementation(), data);
        }
    }
}


// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts v4.4.1 (proxy/ERC1967/ERC1967Proxy.sol)

pragma solidity ^0.8.0;

import "../Proxy.sol";
import "./ERC1967Upgrade.sol";

/**
 * @dev This contract implements an upgradeable proxy. It is upgradeable because calls are delegated to an
 * implementation address that can be changed. This address is stored in storage in the location specified by
 * https://eips.ethereum.org/EIPS/eip-1967[EIP1967], so that it doesn't conflict with the storage layout of the
 * implementation behind the proxy.
 */
contract ERC1967Proxy is Proxy, ERC1967Upgrade {
    /**
     * @dev Initializes the upgradeable proxy with an initial implementation specified by `_logic`.
     *
     * If `_data` is nonempty, it's used as data in a delegate call to `_logic`. This will typically be an encoded
     * function call, and allows initializating the storage of the proxy like a Solidity constructor.
     */
    constructor(address _logic, bytes memory _data) payable {
        assert(_IMPLEMENTATION_SLOT == bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1));
        _upgradeToAndCall(_logic, _data, false);
    }

    /**
     * @dev Returns the current implementation address.
     */
    function _implementation() internal view virtual override returns (address impl) {
        return ERC1967Upgrade._getImplementation();
    }
}


// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts v4.4.1 (access/Ownable.sol)

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
}