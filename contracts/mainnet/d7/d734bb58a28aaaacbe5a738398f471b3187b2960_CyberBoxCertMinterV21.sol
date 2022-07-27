// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.3;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/utils/Address.sol";

import "hardhat/console.sol";

import "./DateTimeManager.sol";
import "./CyberBoxCertNFT.sol";
import "./CyberBoxCertInterface.sol";
import "./V2/CyberBoxCertInterface2.sol";
import "./CyberBoxCertResource.sol";
import "./Uniswap/uniswpv2.sol";
import "./CyberBoxCertMinterV2.sol";

import "./MarketPlace/CertificationMarketPlace.sol";
import "./V2/CertificationURIParser.sol";

contract CyberBoxCertMinterV21 is DateTimeManager, CyberBoxCertInterface, CyberBoxCertResource, CertificationMarketPlace, CertificationURIParser, CyberBoxCertInterface2 {
    using Address for address;

    struct NFTMAP  {
        uint256 tokenType;
        uint256 year;
        uint256 month;
    }

    address public dev;
    address public owner;
    address public c02Owner;
    uint256 public offsetFee;
    uint256 public carvonFeeOnOffset;
    uint256 public referFee;

    address public linkedNFTAddress;

    address private constant UNISWAP_V2_ROUTER = 0xE3D8bd6Aed4F159bc8000a9cD47CffDb95F96121;
    address private constant WETH = 0x471EcE3750Da237f93B8E339c536989b8978a438;
    address public CARBOM = 0x32A9FE697a32135BFd313a6Ac28792DaE4D9979d;

    uint256 public limitMonthNFTPrice;
    uint256 public limitBonusNFTPrice;
    
    //////// owner address => year_month_key => token id
    mapping (address => mapping(uint256 => uint256)) public ownedMonthData;
    mapping (address => mapping(uint256 => uint256)) public ownedYearData;
    mapping (address => mapping(uint256 => uint256)) public ownedBonusData;

    mapping (uint256 => NFTMAP) public _nftDateMap;
    

    uint256 private TOKEN_TYPE_MONTH = 0;
    uint256 private TOKEN_TYPE_YEAR = 1;
    uint256 private TOKEN_TYPE_BONUS = 2;

    uint256 public syncedNFTId = 1;

    constructor(
        address _nft,
        address _dev,
        address _owner,
        address _carvon
    ) public {
        linkedNFTAddress = _nft;
        initializeWithERC721(_nft, _owner);
        dev = _dev;
        owner = _owner;
        c02Owner = _carvon;
        offsetFee = 400;
        carvonFeeOnOffset = 1000;
        referFee = 100;

        limitMonthNFTPrice = 15e18;
        limitBonusNFTPrice = 15e18;


        uint256 producerFee = (offsetFee * carvonFeeOnOffset) / 1000;
        uint256 devFee = (offsetFee * (1000 - carvonFeeOnOffset)) / 1000;
        uint256 createrFee = 1000 - producerFee - devFee;
        emit CertificationReferFeeChanged(referFee);
    }

    function restoreFromV2(address contractV2) public onlyDev {
        Listing[] memory listedTokens = CyberBoxCertMinterV2(contractV2).getAllTokenListings();
        uint256 querySize = listedTokens.length;
        for (uint256 i = 0; i < querySize; i++) {
            Listing memory item = listedTokens[i];
            emit CertificationTokenDelisted(
                linkedNFTAddress,
                item.tokenId
            );
        }
        c02Owner = CyberBoxCertMinterV2(contractV2).c02Owner();
        offsetFee = CyberBoxCertMinterV2(contractV2).offsetFee();
        carvonFeeOnOffset = CyberBoxCertMinterV2(contractV2).carvonFeeOnOffset();
        limitMonthNFTPrice = CyberBoxCertMinterV2(contractV2).limitMonthNFTPrice();
        limitBonusNFTPrice = CyberBoxCertMinterV2(contractV2).limitBonusNFTPrice();
        CARBOM = CyberBoxCertMinterV2(contractV2).CARBOM();
    }

    function parseMetadata(uint256 tokenId) private returns (uint256, uint256, uint256){
        string memory tokenUri = CyberBoxCertNFT(linkedNFTAddress).tokenURI(tokenId);
        return parsingTokenURI(tokenUri, baseURI);
    }

    function restoreNFTs(uint256 totalSupply) public onlyDev {
        uint256 stepCount = 50;
        if(totalSupply - syncedNFTId < stepCount){
            stepCount = totalSupply - syncedNFTId;
        }
        for (uint256 i = 0; i <= stepCount; i++) {
            uint256 tokenId = i + syncedNFTId;
            address nftOwner = IERC721(linkedNFTAddress).ownerOf(tokenId);
            (uint256 tokenType, uint256 year, uint256 month) = parseMetadata(tokenId);
            if(tokenType == TOKEN_TYPE_MONTH) {
                ownedMonthData[nftOwner][year*100 + month] = tokenId;
            }else if(tokenType == TOKEN_TYPE_YEAR){
                ownedYearData[nftOwner][year] = tokenId;
            }else{
                ownedBonusData[nftOwner][year] = tokenId;
            }
            _nftDateMap[tokenId] = NFTMAP(tokenType, year, month);
        }
        syncedNFTId = syncedNFTId + stepCount;
    }

    function contractIdValidate(uint256 contractId) public returns (bool) {
        NFTMAP memory ownerMap = _nftDateMap[contractId];
        if(ownerMap.year != 0){
            return (true);
        }
        return (false);
    }

    function uniwapCarbon(address _to, uint256 _amountIn) public returns (uint256[] memory amounts){
        
        IERC20(WETH).approve(UNISWAP_V2_ROUTER, _amountIn);
        address[] memory path = new address[](2);
        path[0] = WETH;
        path[1] = CARBOM;
        return IUniswapV2Router(UNISWAP_V2_ROUTER).swapExactTokensForTokens(_amountIn, 0, path, _to, block.timestamp);
    }

    function offset(uint256 amount) private returns(uint256 sf, uint256 df, uint256 co2) {
        uint256 totalFee = (amount * offsetFee) / 1000;
        uint256 c02Fee = (totalFee * carvonFeeOnOffset) / 1000;
        uint256 devFee = totalFee - c02Fee;
        uint256 sellerFee = amount - totalFee;

        payable(owner).transfer(sellerFee);
        payable(dev).transfer(devFee);

        uint256[] memory amounts = uniwapCarbon(c02Owner, c02Fee);
        uint256 co2Value = amounts[amounts.length - 1];
        
        return (sellerFee, devFee, co2Value);
    }

    function mintMonthNFTFromRefer(address refer)  external payable {
        (uint256 year, uint256 month) = getDateTimeSymbol();
        uint256 current_nft_id = getCurrentMonthNFTID(msg.sender);
        require(current_nft_id < 1, "This user already mint nft for this month.");
        require(msg.value >= limitMonthNFTPrice, "This user must pay for mint nft.");

        uint256 totalValue = msg.value;
        uint256 referValue = (msg.value * referFee) / 1000;
        uint256 mintValue = totalValue - referValue;
        (uint256 sellerFee, uint256 devFee, uint256 co2Value) = offset(mintValue);

        payable(refer).transfer(referValue);

        string memory token_uri = getMonthTokenURI(year, month);
        uint256 nft_id = CyberBoxCertNFT(linkedNFTAddress).mintNFT(msg.sender, token_uri);
        ownedMonthData[msg.sender][year*100 + month] = nft_id;
        _nftDateMap[nft_id] = NFTMAP(TOKEN_TYPE_MONTH, year, month);
        emit CertificationNFTMinted(msg.sender, TOKEN_TYPE_MONTH, nft_id, year, month, totalValue, devFee, co2Value);
        emit CertificationNFTReferMinted(msg.sender, refer, TOKEN_TYPE_MONTH, nft_id, year, month, totalValue, devFee, referValue, co2Value);
    }

    function mintMonthNFT() external payable {
        (uint256 year, uint256 month) = getDateTimeSymbol();
        uint256 current_nft_id = getCurrentMonthNFTID(msg.sender);
        require(current_nft_id < 1, "This user already mint nft for this month.");
        require(msg.value >= limitMonthNFTPrice, "This user must pay for mint nft.");

        uint256 totalValue = msg.value;
        (uint256 sellerFee, uint256 devFee, uint256 co2Value) = offset(totalValue);
        
        string memory token_uri = getMonthTokenURI(year, month);
        uint256 nft_id = CyberBoxCertNFT(linkedNFTAddress).mintNFT(msg.sender, token_uri);
        ownedMonthData[msg.sender][year*100 + month] = nft_id;
        _nftDateMap[nft_id] = NFTMAP(TOKEN_TYPE_MONTH, year, month);
        emit CertificationNFTMinted(msg.sender, TOKEN_TYPE_MONTH, nft_id, year, month, totalValue, devFee, co2Value);
    }


    function adminMintMonthlyNFT(address user, uint256 month) public onlyDev {
        uint256 year = 2022;
        require(month < 7, "You can't mint over June.");
        uint256 current_nft_id = getMonthNFTID(user, year, month);
        if(current_nft_id < 1) {
            string memory token_uri = getMonthTokenURI(year, month);
            uint256 nft_id = CyberBoxCertNFT(linkedNFTAddress).mintNFT(user, token_uri);
            ownedMonthData[user][year*100 + month] = nft_id;
            _nftDateMap[nft_id] = NFTMAP(TOKEN_TYPE_MONTH, year, month);
            emit CertificationNFTMinted(user, TOKEN_TYPE_MONTH, nft_id, year, month, 0, 0, 0);
        }
    }
    function adminMintAllNFTs(address user)  public onlyDev {
        uint256 year = 2022;
        for(uint256 month = 1; month<=6; month++){
            uint256 current_nft_id = getMonthNFTID(user, year, month);
            if(current_nft_id < 1) {
                string memory token_uri = getMonthTokenURI(year, month);
                uint256 nft_id = CyberBoxCertNFT(linkedNFTAddress).mintNFT(user, token_uri);
                ownedMonthData[user][year*100 + month] = nft_id;
                _nftDateMap[nft_id] = NFTMAP(TOKEN_TYPE_MONTH, year, month);
                emit CertificationNFTMinted(user, TOKEN_TYPE_MONTH, nft_id, year, month, 0, 0, 0);
            }
        }
    }

    function mintMonthNFTFor(address receipt, uint256 year, uint256 month) private {
        uint256 current_nft_id = getMonthNFTID(receipt, year, month);
        if(current_nft_id < 1) {
            string memory token_uri = getMonthTokenURI(year, month);
            uint256 nft_id = CyberBoxCertNFT(linkedNFTAddress).mintNFT(msg.sender, token_uri);
            ownedMonthData[msg.sender][year*100 + month] = nft_id;
            _nftDateMap[nft_id] = NFTMAP(TOKEN_TYPE_MONTH, year, month);
            emit CertificationNFTMinted(msg.sender, TOKEN_TYPE_MONTH, nft_id, year, month, 0, 0, 0);
        }
    }

    function mintYearNFT()  external onlyDev payable  {
        (uint256 year, uint256 month) = getDateTimeSymbol();
        uint256 current_nft_id = getCurrentYearNFTID(msg.sender);
        require(current_nft_id < 1, "This user already mint nft for this month.");
        require(msg.value >= limitMonthNFTPrice, "This user must pay for mint nft.");
        
        uint256 totalValue = msg.value;
        
        (uint256 sellerFee, uint256 devFee, uint256 co2Value) = offset(totalValue);

        string memory token_uri = getYearTokenURI(year);
        uint256 nft_id = CyberBoxCertNFT(linkedNFTAddress).mintNFT(msg.sender, token_uri);
        ownedYearData[msg.sender][year] = nft_id;
        _nftDateMap[nft_id] = NFTMAP(TOKEN_TYPE_YEAR, year, 0);
        emit CertificationNFTMinted(msg.sender, TOKEN_TYPE_YEAR, nft_id, year, 0, totalValue, devFee, co2Value);
    }

    function mintBonusNFT() external onlyDev payable {
        (uint256 year, uint256 month) = getDateTimeSymbol();
        uint256 current_nft_id = getCurrentBonusNFTID(msg.sender);
        require(current_nft_id < 1, "This user already mint nft for this month.");
        require(msg.value >= limitBonusNFTPrice, "This user must pay for mint nft.");

        uint256 totalValue = msg.value;
        (uint256 sellerFee, uint256 devFee, uint256 co2Value) = offset(totalValue);

        string memory token_uri = getBonusTokenURI(year);
        uint256 nft_id = CyberBoxCertNFT(linkedNFTAddress).mintNFT(msg.sender, token_uri);
        ownedBonusData[msg.sender][year] = nft_id;
        _nftDateMap[nft_id] = NFTMAP(TOKEN_TYPE_BONUS, year, 0);
        emit CertificationNFTMinted(msg.sender, TOKEN_TYPE_BONUS, nft_id, year, 0, totalValue, devFee, co2Value);
    }

    function exchangeBonusNFTToMonth(uint256 year) public {
        uint256 current_nft_id = getBonusNFTID(msg.sender, year);
        require(current_nft_id > 0, "This user don't have bonus NFT.");
        CyberBoxCertNFT(linkedNFTAddress).burn(msg.sender, current_nft_id);
        ownedBonusData[msg.sender][year] = 0;
        emit CertificationNFTBurned(msg.sender, TOKEN_TYPE_BONUS, current_nft_id, year, 0);
        for(uint256 month = 1; month<=12; month++){
            mintMonthNFTFor(msg.sender, year, month);
        }
    }

    function exchangeMonthNFTToBonus(uint256 year) public {
        uint256 current_bonus_id = getCurrentBonusNFTID(msg.sender);
        require(current_bonus_id < 1, "This user already mint nft for this month.");
        for(uint256 month = 1; month<=12; month++){
            uint256 current_nft_id = getMonthNFTID(msg.sender, year, month);
            require(current_nft_id > 0, "This user don't have all month NFT.");
            CyberBoxCertNFT(linkedNFTAddress).burn(msg.sender, current_nft_id);
            ownedMonthData[msg.sender][year*100 + month] = 0;
            emit CertificationNFTBurned(msg.sender, TOKEN_TYPE_MONTH, current_nft_id, year, 0);
        }
        string memory token_uri = getBonusTokenURI(year);
        uint256 nft_id = CyberBoxCertNFT(linkedNFTAddress).mintNFT(msg.sender, token_uri);
        ownedBonusData[msg.sender][year] = nft_id;
        emit CertificationNFTMinted(msg.sender, TOKEN_TYPE_BONUS, nft_id, year, 0, 0, 0, 0);
    }

    function transferNFTOwnedData(address from, address to, uint256 tokenId) private {
        NFTMAP memory mapData = _nftDateMap[tokenId];
        uint256 tokenType = mapData.tokenType;
        uint256 year = mapData.year;
        uint256 month = mapData.month;
        if (tokenType == TOKEN_TYPE_MONTH){
            ownedMonthData[from][year*100 + month] = 0;
            ownedMonthData[to][year*100 + month] = tokenId;
        }
        if (tokenType == TOKEN_TYPE_YEAR) {
            ownedYearData[from][year] = 0;
            ownedYearData[to][year] = tokenId;
        }
        if (tokenType == TOKEN_TYPE_BONUS) {
            ownedBonusData[from][year] = 0;
            ownedBonusData[to][year] = tokenId;
        }
    }


    function getMonthNFTID(address owner, uint256 year, uint256 month) public returns (uint256){
        console.log("Month:", ownedMonthData[owner][year * 100 + month]);
        return ownedMonthData[owner][year * 100 + month];
    }

    function getYearNFTID(address owner, uint256 year) public returns (uint256) {
        return ownedYearData[owner][year];
    }

    function getBonusNFTID(address owner, uint256 year) public returns (uint256) {
        return ownedBonusData[owner][year];
    }

    
    function getCurrentMonthNFTID(address owner) public returns (uint256) {
        (uint256 year, uint256 month) = getDateTimeSymbol();
        console.log("Month:", ownedMonthData[owner][year * 100 + month]);
        return ownedMonthData[owner][year * 100 + month];
    }
    function getCurrentYearNFTID(address owner) public returns (uint256) {
        (uint256 year, uint256 month) = getDateTimeSymbol();
        console.log("year:", ownedMonthData[owner][year * 100 + month]);
        return ownedYearData[owner][year];
    }
    function getCurrentBonusNFTID(address owner) public returns (uint256) {
        (uint256 year, uint256 month) = getDateTimeSymbol();
        console.log("bonus:", ownedBonusData[owner][year * 100 + month]);
        return ownedBonusData[owner][year];
    }
    
    
    function changeDev(address _newDev) public onlyDev {
        dev  = _newDev;
    }
    function changeOwner(address _newOnwer) public onlyDev {
        owner  = _newOnwer;
    }
    function changeCo2Owner(address _newOnwer) public onlyDev {
        c02Owner  = _newOnwer;
    }

    function changeCarvonTokenAddress(address _carvonToken) public onlyDev {CARBOM = _carvonToken;}
    function changeReferFee(uint256 _referFee) public onlyDev {
        referFee = _referFee;
        emit CertificationReferFeeChanged(referFee);
    }
    function changeOffsetFee(uint256 _offsetFee) public onlyDev {
        offsetFee = _offsetFee;
    }
    function changeCarbonPercent(uint256 _carbonPercent) public onlyDev {
        carvonFeeOnOffset = _carbonPercent;
    }

    function changeMonthNFTLimitPrice(uint256 _price) public onlyDev {limitMonthNFTPrice = _price;}
    function changeBonusNFTLimitPrice(uint256 _price) public onlyDev {limitBonusNFTPrice = _price;}

    modifier onlyDev() { require(msg.sender == dev, "CyberBoxCertNFT: wrong developer");_;}

    /**
     * @dev List token for sale
     * @param tokenId erc721 token Id
     * @param value min price to sell the token
     */
    function ListToken(
    // function listToken(
        uint256 tokenId,
        uint256 value
    ) external  {
        (
        address fromAddress, 
        uint256 minValue
        ) = listToken(msg.sender, tokenId, value);
        emit CertificationTokenListed(
            linkedNFTAddress,
            tokenId,
            fromAddress,
            minValue
        );
    }
    /**
     * @dev See {INFTKEYMarketPlaceV1-delistToken}.
     * msg.sender must be the seller of the listing record
     */
    function delistToken(
        uint256 tokenId
    ) external {
        delistToken(msg.sender, tokenId);
        emit CertificationTokenDelisted(
            linkedNFTAddress,
            tokenId
        );
    }
    /**
     * @dev See {INFTKEYMarketPlaceV1-cleanAllInvalidListings}.
     */
    function cleanAllInvalidListings() external {
        (uint256[] memory idList) = certCleanAllInvalidListings();
        for (uint256 i = 0; i < idList.length; i++) {
            uint256 contract_id = idList[i];
            emit CertificationCleanList(
                linkedNFTAddress,
                contract_id
            );
        }
        deleteTempTokenIdStorage();
    }

    function buyToken(
        uint256 tokenId,
        uint256 value
    ) external payable{
        (
            address sellerAddress, 
            address devAddress,
            address createrAddress,
            address producerAddress
        ) = buyTokenPrepare(msg.sender, tokenId, value);
        uint256 payment_value = msg.value;
        address nftAddress = linkedNFTAddress;
        uint256 sellerFee = calculateSellerFee(payment_value);
        uint256 devFee = calculateDevFee(payment_value);
        uint256 createrFee = calculateCreaterFee(payment_value);
        uint256 producerFee = calculateProducerFee(payment_value);
        transferCelo(msg.sender, sellerAddress, sellerFee);
        emit CertificationPayment(msg.sender, sellerAddress, tokenId, nftAddress, 0, sellerFee);
        transferCelo(msg.sender, devAddress, devFee);
        emit CertificationPayment(msg.sender, devAddress, tokenId, nftAddress, 1, devFee);
        if(createrAddress != address(0) && createrFee > 0){
            transferCelo(msg.sender, createrAddress, createrFee);
            emit CertificationPayment(msg.sender, createrAddress, tokenId, nftAddress, 2, createrFee);
        }
        if(producerAddress != address(0) && producerFee > 0){
            transferCelo(msg.sender, producerAddress, producerFee);
            emit CertificationPayment(msg.sender, producerAddress, tokenId, nftAddress, 3, producerFee);
        }
        buyTokenComplete(msg.sender, tokenId);
        transferNFTOwnedData(sellerAddress, msg.sender, tokenId);
        emit CertificationTokenBought(
            nftAddress,
            tokenId,
            sellerAddress,
            msg.sender,
            payment_value,
            sellerFee,
            devFee + createrFee + producerFee
        );
    }

    function transfer(
        address to,
        uint256 tokenId
    )external {
        transfer(msg.sender, to, tokenId);
        transferNFTOwnedData(msg.sender, to, tokenId);
        emit CertificationTokenTransfered(
            linkedNFTAddress,
            tokenId,
            msg.sender,
            to,
            0
        );
    }

    function changePrice(address _nftAddress, uint256 tokenId, uint256 newPrice) external {
        certChangePrice(msg.sender, tokenId, newPrice);
        emit CertificationTokenPriceChanged(
            _nftAddress,
            tokenId,
            newPrice
        );
    }


    function transferCelo(address sender, address receiver, uint256 value)  private{
        require(sender != address(0), "transfer address must not 0x0");
        require(receiver != address(0), "transfer address must not 0x0");
        require(value > 0, "transfer amount must large than 0");
        if(sender == address(this)){
            payable(receiver).transfer(value);
        }else{
            Address.sendValue(payable(receiver), value);
        }
    }
}

// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v4.7.0) (utils/Address.sol)

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
                /// @solidity memory-safe-assembly
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
pragma solidity >= 0.4.22 <0.9.0;

library console {
	address constant CONSOLE_ADDRESS = address(0x000000000000000000636F6e736F6c652e6c6f67);

	function _sendLogPayload(bytes memory payload) private view {
		uint256 payloadLength = payload.length;
		address consoleAddress = CONSOLE_ADDRESS;
		assembly {
			let payloadStart := add(payload, 32)
			let r := staticcall(gas(), consoleAddress, payloadStart, payloadLength, 0, 0)
		}
	}

	function log() internal view {
		_sendLogPayload(abi.encodeWithSignature("log()"));
	}

	function logInt(int p0) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(int)", p0));
	}

	function logUint(uint p0) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint)", p0));
	}

	function logString(string memory p0) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string)", p0));
	}

	function logBool(bool p0) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool)", p0));
	}

	function logAddress(address p0) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address)", p0));
	}

	function logBytes(bytes memory p0) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bytes)", p0));
	}

	function logBytes1(bytes1 p0) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bytes1)", p0));
	}

	function logBytes2(bytes2 p0) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bytes2)", p0));
	}

	function logBytes3(bytes3 p0) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bytes3)", p0));
	}

	function logBytes4(bytes4 p0) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bytes4)", p0));
	}

	function logBytes5(bytes5 p0) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bytes5)", p0));
	}

	function logBytes6(bytes6 p0) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bytes6)", p0));
	}

	function logBytes7(bytes7 p0) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bytes7)", p0));
	}

	function logBytes8(bytes8 p0) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bytes8)", p0));
	}

	function logBytes9(bytes9 p0) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bytes9)", p0));
	}

	function logBytes10(bytes10 p0) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bytes10)", p0));
	}

	function logBytes11(bytes11 p0) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bytes11)", p0));
	}

	function logBytes12(bytes12 p0) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bytes12)", p0));
	}

	function logBytes13(bytes13 p0) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bytes13)", p0));
	}

	function logBytes14(bytes14 p0) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bytes14)", p0));
	}

	function logBytes15(bytes15 p0) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bytes15)", p0));
	}

	function logBytes16(bytes16 p0) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bytes16)", p0));
	}

	function logBytes17(bytes17 p0) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bytes17)", p0));
	}

	function logBytes18(bytes18 p0) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bytes18)", p0));
	}

	function logBytes19(bytes19 p0) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bytes19)", p0));
	}

	function logBytes20(bytes20 p0) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bytes20)", p0));
	}

	function logBytes21(bytes21 p0) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bytes21)", p0));
	}

	function logBytes22(bytes22 p0) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bytes22)", p0));
	}

	function logBytes23(bytes23 p0) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bytes23)", p0));
	}

	function logBytes24(bytes24 p0) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bytes24)", p0));
	}

	function logBytes25(bytes25 p0) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bytes25)", p0));
	}

	function logBytes26(bytes26 p0) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bytes26)", p0));
	}

	function logBytes27(bytes27 p0) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bytes27)", p0));
	}

	function logBytes28(bytes28 p0) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bytes28)", p0));
	}

	function logBytes29(bytes29 p0) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bytes29)", p0));
	}

	function logBytes30(bytes30 p0) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bytes30)", p0));
	}

	function logBytes31(bytes31 p0) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bytes31)", p0));
	}

	function logBytes32(bytes32 p0) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bytes32)", p0));
	}

	function log(uint p0) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint)", p0));
	}

	function log(string memory p0) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string)", p0));
	}

	function log(bool p0) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool)", p0));
	}

	function log(address p0) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address)", p0));
	}

	function log(uint p0, uint p1) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,uint)", p0, p1));
	}

	function log(uint p0, string memory p1) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,string)", p0, p1));
	}

	function log(uint p0, bool p1) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,bool)", p0, p1));
	}

	function log(uint p0, address p1) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,address)", p0, p1));
	}

	function log(string memory p0, uint p1) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,uint)", p0, p1));
	}

	function log(string memory p0, string memory p1) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,string)", p0, p1));
	}

	function log(string memory p0, bool p1) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,bool)", p0, p1));
	}

	function log(string memory p0, address p1) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,address)", p0, p1));
	}

	function log(bool p0, uint p1) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,uint)", p0, p1));
	}

	function log(bool p0, string memory p1) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,string)", p0, p1));
	}

	function log(bool p0, bool p1) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,bool)", p0, p1));
	}

	function log(bool p0, address p1) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,address)", p0, p1));
	}

	function log(address p0, uint p1) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,uint)", p0, p1));
	}

	function log(address p0, string memory p1) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,string)", p0, p1));
	}

	function log(address p0, bool p1) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,bool)", p0, p1));
	}

	function log(address p0, address p1) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,address)", p0, p1));
	}

	function log(uint p0, uint p1, uint p2) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,uint,uint)", p0, p1, p2));
	}

	function log(uint p0, uint p1, string memory p2) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,uint,string)", p0, p1, p2));
	}

	function log(uint p0, uint p1, bool p2) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,uint,bool)", p0, p1, p2));
	}

	function log(uint p0, uint p1, address p2) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,uint,address)", p0, p1, p2));
	}

	function log(uint p0, string memory p1, uint p2) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,string,uint)", p0, p1, p2));
	}

	function log(uint p0, string memory p1, string memory p2) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,string,string)", p0, p1, p2));
	}

	function log(uint p0, string memory p1, bool p2) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,string,bool)", p0, p1, p2));
	}

	function log(uint p0, string memory p1, address p2) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,string,address)", p0, p1, p2));
	}

	function log(uint p0, bool p1, uint p2) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,bool,uint)", p0, p1, p2));
	}

	function log(uint p0, bool p1, string memory p2) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,bool,string)", p0, p1, p2));
	}

	function log(uint p0, bool p1, bool p2) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,bool,bool)", p0, p1, p2));
	}

	function log(uint p0, bool p1, address p2) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,bool,address)", p0, p1, p2));
	}

	function log(uint p0, address p1, uint p2) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,address,uint)", p0, p1, p2));
	}

	function log(uint p0, address p1, string memory p2) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,address,string)", p0, p1, p2));
	}

	function log(uint p0, address p1, bool p2) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,address,bool)", p0, p1, p2));
	}

	function log(uint p0, address p1, address p2) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,address,address)", p0, p1, p2));
	}

	function log(string memory p0, uint p1, uint p2) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,uint,uint)", p0, p1, p2));
	}

	function log(string memory p0, uint p1, string memory p2) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,uint,string)", p0, p1, p2));
	}

	function log(string memory p0, uint p1, bool p2) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,uint,bool)", p0, p1, p2));
	}

	function log(string memory p0, uint p1, address p2) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,uint,address)", p0, p1, p2));
	}

	function log(string memory p0, string memory p1, uint p2) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,string,uint)", p0, p1, p2));
	}

	function log(string memory p0, string memory p1, string memory p2) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,string,string)", p0, p1, p2));
	}

	function log(string memory p0, string memory p1, bool p2) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,string,bool)", p0, p1, p2));
	}

	function log(string memory p0, string memory p1, address p2) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,string,address)", p0, p1, p2));
	}

	function log(string memory p0, bool p1, uint p2) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,bool,uint)", p0, p1, p2));
	}

	function log(string memory p0, bool p1, string memory p2) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,bool,string)", p0, p1, p2));
	}

	function log(string memory p0, bool p1, bool p2) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,bool,bool)", p0, p1, p2));
	}

	function log(string memory p0, bool p1, address p2) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,bool,address)", p0, p1, p2));
	}

	function log(string memory p0, address p1, uint p2) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,address,uint)", p0, p1, p2));
	}

	function log(string memory p0, address p1, string memory p2) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,address,string)", p0, p1, p2));
	}

	function log(string memory p0, address p1, bool p2) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,address,bool)", p0, p1, p2));
	}

	function log(string memory p0, address p1, address p2) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,address,address)", p0, p1, p2));
	}

	function log(bool p0, uint p1, uint p2) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,uint,uint)", p0, p1, p2));
	}

	function log(bool p0, uint p1, string memory p2) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,uint,string)", p0, p1, p2));
	}

	function log(bool p0, uint p1, bool p2) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,uint,bool)", p0, p1, p2));
	}

	function log(bool p0, uint p1, address p2) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,uint,address)", p0, p1, p2));
	}

	function log(bool p0, string memory p1, uint p2) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,string,uint)", p0, p1, p2));
	}

	function log(bool p0, string memory p1, string memory p2) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,string,string)", p0, p1, p2));
	}

	function log(bool p0, string memory p1, bool p2) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,string,bool)", p0, p1, p2));
	}

	function log(bool p0, string memory p1, address p2) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,string,address)", p0, p1, p2));
	}

	function log(bool p0, bool p1, uint p2) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,bool,uint)", p0, p1, p2));
	}

	function log(bool p0, bool p1, string memory p2) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,bool,string)", p0, p1, p2));
	}

	function log(bool p0, bool p1, bool p2) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,bool,bool)", p0, p1, p2));
	}

	function log(bool p0, bool p1, address p2) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,bool,address)", p0, p1, p2));
	}

	function log(bool p0, address p1, uint p2) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,address,uint)", p0, p1, p2));
	}

	function log(bool p0, address p1, string memory p2) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,address,string)", p0, p1, p2));
	}

	function log(bool p0, address p1, bool p2) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,address,bool)", p0, p1, p2));
	}

	function log(bool p0, address p1, address p2) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,address,address)", p0, p1, p2));
	}

	function log(address p0, uint p1, uint p2) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,uint,uint)", p0, p1, p2));
	}

	function log(address p0, uint p1, string memory p2) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,uint,string)", p0, p1, p2));
	}

	function log(address p0, uint p1, bool p2) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,uint,bool)", p0, p1, p2));
	}

	function log(address p0, uint p1, address p2) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,uint,address)", p0, p1, p2));
	}

	function log(address p0, string memory p1, uint p2) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,string,uint)", p0, p1, p2));
	}

	function log(address p0, string memory p1, string memory p2) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,string,string)", p0, p1, p2));
	}

	function log(address p0, string memory p1, bool p2) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,string,bool)", p0, p1, p2));
	}

	function log(address p0, string memory p1, address p2) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,string,address)", p0, p1, p2));
	}

	function log(address p0, bool p1, uint p2) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,bool,uint)", p0, p1, p2));
	}

	function log(address p0, bool p1, string memory p2) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,bool,string)", p0, p1, p2));
	}

	function log(address p0, bool p1, bool p2) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,bool,bool)", p0, p1, p2));
	}

	function log(address p0, bool p1, address p2) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,bool,address)", p0, p1, p2));
	}

	function log(address p0, address p1, uint p2) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,address,uint)", p0, p1, p2));
	}

	function log(address p0, address p1, string memory p2) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,address,string)", p0, p1, p2));
	}

	function log(address p0, address p1, bool p2) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,address,bool)", p0, p1, p2));
	}

	function log(address p0, address p1, address p2) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,address,address)", p0, p1, p2));
	}

	function log(uint p0, uint p1, uint p2, uint p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,uint,uint,uint)", p0, p1, p2, p3));
	}

	function log(uint p0, uint p1, uint p2, string memory p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,uint,uint,string)", p0, p1, p2, p3));
	}

	function log(uint p0, uint p1, uint p2, bool p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,uint,uint,bool)", p0, p1, p2, p3));
	}

	function log(uint p0, uint p1, uint p2, address p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,uint,uint,address)", p0, p1, p2, p3));
	}

	function log(uint p0, uint p1, string memory p2, uint p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,uint,string,uint)", p0, p1, p2, p3));
	}

	function log(uint p0, uint p1, string memory p2, string memory p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,uint,string,string)", p0, p1, p2, p3));
	}

	function log(uint p0, uint p1, string memory p2, bool p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,uint,string,bool)", p0, p1, p2, p3));
	}

	function log(uint p0, uint p1, string memory p2, address p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,uint,string,address)", p0, p1, p2, p3));
	}

	function log(uint p0, uint p1, bool p2, uint p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,uint,bool,uint)", p0, p1, p2, p3));
	}

	function log(uint p0, uint p1, bool p2, string memory p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,uint,bool,string)", p0, p1, p2, p3));
	}

	function log(uint p0, uint p1, bool p2, bool p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,uint,bool,bool)", p0, p1, p2, p3));
	}

	function log(uint p0, uint p1, bool p2, address p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,uint,bool,address)", p0, p1, p2, p3));
	}

	function log(uint p0, uint p1, address p2, uint p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,uint,address,uint)", p0, p1, p2, p3));
	}

	function log(uint p0, uint p1, address p2, string memory p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,uint,address,string)", p0, p1, p2, p3));
	}

	function log(uint p0, uint p1, address p2, bool p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,uint,address,bool)", p0, p1, p2, p3));
	}

	function log(uint p0, uint p1, address p2, address p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,uint,address,address)", p0, p1, p2, p3));
	}

	function log(uint p0, string memory p1, uint p2, uint p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,string,uint,uint)", p0, p1, p2, p3));
	}

	function log(uint p0, string memory p1, uint p2, string memory p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,string,uint,string)", p0, p1, p2, p3));
	}

	function log(uint p0, string memory p1, uint p2, bool p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,string,uint,bool)", p0, p1, p2, p3));
	}

	function log(uint p0, string memory p1, uint p2, address p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,string,uint,address)", p0, p1, p2, p3));
	}

	function log(uint p0, string memory p1, string memory p2, uint p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,string,string,uint)", p0, p1, p2, p3));
	}

	function log(uint p0, string memory p1, string memory p2, string memory p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,string,string,string)", p0, p1, p2, p3));
	}

	function log(uint p0, string memory p1, string memory p2, bool p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,string,string,bool)", p0, p1, p2, p3));
	}

	function log(uint p0, string memory p1, string memory p2, address p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,string,string,address)", p0, p1, p2, p3));
	}

	function log(uint p0, string memory p1, bool p2, uint p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,string,bool,uint)", p0, p1, p2, p3));
	}

	function log(uint p0, string memory p1, bool p2, string memory p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,string,bool,string)", p0, p1, p2, p3));
	}

	function log(uint p0, string memory p1, bool p2, bool p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,string,bool,bool)", p0, p1, p2, p3));
	}

	function log(uint p0, string memory p1, bool p2, address p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,string,bool,address)", p0, p1, p2, p3));
	}

	function log(uint p0, string memory p1, address p2, uint p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,string,address,uint)", p0, p1, p2, p3));
	}

	function log(uint p0, string memory p1, address p2, string memory p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,string,address,string)", p0, p1, p2, p3));
	}

	function log(uint p0, string memory p1, address p2, bool p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,string,address,bool)", p0, p1, p2, p3));
	}

	function log(uint p0, string memory p1, address p2, address p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,string,address,address)", p0, p1, p2, p3));
	}

	function log(uint p0, bool p1, uint p2, uint p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,bool,uint,uint)", p0, p1, p2, p3));
	}

	function log(uint p0, bool p1, uint p2, string memory p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,bool,uint,string)", p0, p1, p2, p3));
	}

	function log(uint p0, bool p1, uint p2, bool p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,bool,uint,bool)", p0, p1, p2, p3));
	}

	function log(uint p0, bool p1, uint p2, address p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,bool,uint,address)", p0, p1, p2, p3));
	}

	function log(uint p0, bool p1, string memory p2, uint p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,bool,string,uint)", p0, p1, p2, p3));
	}

	function log(uint p0, bool p1, string memory p2, string memory p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,bool,string,string)", p0, p1, p2, p3));
	}

	function log(uint p0, bool p1, string memory p2, bool p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,bool,string,bool)", p0, p1, p2, p3));
	}

	function log(uint p0, bool p1, string memory p2, address p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,bool,string,address)", p0, p1, p2, p3));
	}

	function log(uint p0, bool p1, bool p2, uint p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,bool,bool,uint)", p0, p1, p2, p3));
	}

	function log(uint p0, bool p1, bool p2, string memory p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,bool,bool,string)", p0, p1, p2, p3));
	}

	function log(uint p0, bool p1, bool p2, bool p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,bool,bool,bool)", p0, p1, p2, p3));
	}

	function log(uint p0, bool p1, bool p2, address p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,bool,bool,address)", p0, p1, p2, p3));
	}

	function log(uint p0, bool p1, address p2, uint p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,bool,address,uint)", p0, p1, p2, p3));
	}

	function log(uint p0, bool p1, address p2, string memory p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,bool,address,string)", p0, p1, p2, p3));
	}

	function log(uint p0, bool p1, address p2, bool p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,bool,address,bool)", p0, p1, p2, p3));
	}

	function log(uint p0, bool p1, address p2, address p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,bool,address,address)", p0, p1, p2, p3));
	}

	function log(uint p0, address p1, uint p2, uint p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,address,uint,uint)", p0, p1, p2, p3));
	}

	function log(uint p0, address p1, uint p2, string memory p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,address,uint,string)", p0, p1, p2, p3));
	}

	function log(uint p0, address p1, uint p2, bool p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,address,uint,bool)", p0, p1, p2, p3));
	}

	function log(uint p0, address p1, uint p2, address p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,address,uint,address)", p0, p1, p2, p3));
	}

	function log(uint p0, address p1, string memory p2, uint p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,address,string,uint)", p0, p1, p2, p3));
	}

	function log(uint p0, address p1, string memory p2, string memory p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,address,string,string)", p0, p1, p2, p3));
	}

	function log(uint p0, address p1, string memory p2, bool p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,address,string,bool)", p0, p1, p2, p3));
	}

	function log(uint p0, address p1, string memory p2, address p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,address,string,address)", p0, p1, p2, p3));
	}

	function log(uint p0, address p1, bool p2, uint p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,address,bool,uint)", p0, p1, p2, p3));
	}

	function log(uint p0, address p1, bool p2, string memory p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,address,bool,string)", p0, p1, p2, p3));
	}

	function log(uint p0, address p1, bool p2, bool p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,address,bool,bool)", p0, p1, p2, p3));
	}

	function log(uint p0, address p1, bool p2, address p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,address,bool,address)", p0, p1, p2, p3));
	}

	function log(uint p0, address p1, address p2, uint p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,address,address,uint)", p0, p1, p2, p3));
	}

	function log(uint p0, address p1, address p2, string memory p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,address,address,string)", p0, p1, p2, p3));
	}

	function log(uint p0, address p1, address p2, bool p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,address,address,bool)", p0, p1, p2, p3));
	}

	function log(uint p0, address p1, address p2, address p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,address,address,address)", p0, p1, p2, p3));
	}

	function log(string memory p0, uint p1, uint p2, uint p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,uint,uint,uint)", p0, p1, p2, p3));
	}

	function log(string memory p0, uint p1, uint p2, string memory p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,uint,uint,string)", p0, p1, p2, p3));
	}

	function log(string memory p0, uint p1, uint p2, bool p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,uint,uint,bool)", p0, p1, p2, p3));
	}

	function log(string memory p0, uint p1, uint p2, address p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,uint,uint,address)", p0, p1, p2, p3));
	}

	function log(string memory p0, uint p1, string memory p2, uint p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,uint,string,uint)", p0, p1, p2, p3));
	}

	function log(string memory p0, uint p1, string memory p2, string memory p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,uint,string,string)", p0, p1, p2, p3));
	}

	function log(string memory p0, uint p1, string memory p2, bool p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,uint,string,bool)", p0, p1, p2, p3));
	}

	function log(string memory p0, uint p1, string memory p2, address p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,uint,string,address)", p0, p1, p2, p3));
	}

	function log(string memory p0, uint p1, bool p2, uint p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,uint,bool,uint)", p0, p1, p2, p3));
	}

	function log(string memory p0, uint p1, bool p2, string memory p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,uint,bool,string)", p0, p1, p2, p3));
	}

	function log(string memory p0, uint p1, bool p2, bool p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,uint,bool,bool)", p0, p1, p2, p3));
	}

	function log(string memory p0, uint p1, bool p2, address p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,uint,bool,address)", p0, p1, p2, p3));
	}

	function log(string memory p0, uint p1, address p2, uint p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,uint,address,uint)", p0, p1, p2, p3));
	}

	function log(string memory p0, uint p1, address p2, string memory p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,uint,address,string)", p0, p1, p2, p3));
	}

	function log(string memory p0, uint p1, address p2, bool p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,uint,address,bool)", p0, p1, p2, p3));
	}

	function log(string memory p0, uint p1, address p2, address p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,uint,address,address)", p0, p1, p2, p3));
	}

	function log(string memory p0, string memory p1, uint p2, uint p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,string,uint,uint)", p0, p1, p2, p3));
	}

	function log(string memory p0, string memory p1, uint p2, string memory p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,string,uint,string)", p0, p1, p2, p3));
	}

	function log(string memory p0, string memory p1, uint p2, bool p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,string,uint,bool)", p0, p1, p2, p3));
	}

	function log(string memory p0, string memory p1, uint p2, address p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,string,uint,address)", p0, p1, p2, p3));
	}

	function log(string memory p0, string memory p1, string memory p2, uint p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,string,string,uint)", p0, p1, p2, p3));
	}

	function log(string memory p0, string memory p1, string memory p2, string memory p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,string,string,string)", p0, p1, p2, p3));
	}

	function log(string memory p0, string memory p1, string memory p2, bool p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,string,string,bool)", p0, p1, p2, p3));
	}

	function log(string memory p0, string memory p1, string memory p2, address p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,string,string,address)", p0, p1, p2, p3));
	}

	function log(string memory p0, string memory p1, bool p2, uint p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,string,bool,uint)", p0, p1, p2, p3));
	}

	function log(string memory p0, string memory p1, bool p2, string memory p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,string,bool,string)", p0, p1, p2, p3));
	}

	function log(string memory p0, string memory p1, bool p2, bool p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,string,bool,bool)", p0, p1, p2, p3));
	}

	function log(string memory p0, string memory p1, bool p2, address p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,string,bool,address)", p0, p1, p2, p3));
	}

	function log(string memory p0, string memory p1, address p2, uint p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,string,address,uint)", p0, p1, p2, p3));
	}

	function log(string memory p0, string memory p1, address p2, string memory p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,string,address,string)", p0, p1, p2, p3));
	}

	function log(string memory p0, string memory p1, address p2, bool p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,string,address,bool)", p0, p1, p2, p3));
	}

	function log(string memory p0, string memory p1, address p2, address p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,string,address,address)", p0, p1, p2, p3));
	}

	function log(string memory p0, bool p1, uint p2, uint p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,bool,uint,uint)", p0, p1, p2, p3));
	}

	function log(string memory p0, bool p1, uint p2, string memory p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,bool,uint,string)", p0, p1, p2, p3));
	}

	function log(string memory p0, bool p1, uint p2, bool p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,bool,uint,bool)", p0, p1, p2, p3));
	}

	function log(string memory p0, bool p1, uint p2, address p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,bool,uint,address)", p0, p1, p2, p3));
	}

	function log(string memory p0, bool p1, string memory p2, uint p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,bool,string,uint)", p0, p1, p2, p3));
	}

	function log(string memory p0, bool p1, string memory p2, string memory p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,bool,string,string)", p0, p1, p2, p3));
	}

	function log(string memory p0, bool p1, string memory p2, bool p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,bool,string,bool)", p0, p1, p2, p3));
	}

	function log(string memory p0, bool p1, string memory p2, address p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,bool,string,address)", p0, p1, p2, p3));
	}

	function log(string memory p0, bool p1, bool p2, uint p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,bool,bool,uint)", p0, p1, p2, p3));
	}

	function log(string memory p0, bool p1, bool p2, string memory p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,bool,bool,string)", p0, p1, p2, p3));
	}

	function log(string memory p0, bool p1, bool p2, bool p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,bool,bool,bool)", p0, p1, p2, p3));
	}

	function log(string memory p0, bool p1, bool p2, address p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,bool,bool,address)", p0, p1, p2, p3));
	}

	function log(string memory p0, bool p1, address p2, uint p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,bool,address,uint)", p0, p1, p2, p3));
	}

	function log(string memory p0, bool p1, address p2, string memory p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,bool,address,string)", p0, p1, p2, p3));
	}

	function log(string memory p0, bool p1, address p2, bool p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,bool,address,bool)", p0, p1, p2, p3));
	}

	function log(string memory p0, bool p1, address p2, address p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,bool,address,address)", p0, p1, p2, p3));
	}

	function log(string memory p0, address p1, uint p2, uint p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,address,uint,uint)", p0, p1, p2, p3));
	}

	function log(string memory p0, address p1, uint p2, string memory p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,address,uint,string)", p0, p1, p2, p3));
	}

	function log(string memory p0, address p1, uint p2, bool p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,address,uint,bool)", p0, p1, p2, p3));
	}

	function log(string memory p0, address p1, uint p2, address p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,address,uint,address)", p0, p1, p2, p3));
	}

	function log(string memory p0, address p1, string memory p2, uint p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,address,string,uint)", p0, p1, p2, p3));
	}

	function log(string memory p0, address p1, string memory p2, string memory p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,address,string,string)", p0, p1, p2, p3));
	}

	function log(string memory p0, address p1, string memory p2, bool p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,address,string,bool)", p0, p1, p2, p3));
	}

	function log(string memory p0, address p1, string memory p2, address p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,address,string,address)", p0, p1, p2, p3));
	}

	function log(string memory p0, address p1, bool p2, uint p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,address,bool,uint)", p0, p1, p2, p3));
	}

	function log(string memory p0, address p1, bool p2, string memory p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,address,bool,string)", p0, p1, p2, p3));
	}

	function log(string memory p0, address p1, bool p2, bool p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,address,bool,bool)", p0, p1, p2, p3));
	}

	function log(string memory p0, address p1, bool p2, address p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,address,bool,address)", p0, p1, p2, p3));
	}

	function log(string memory p0, address p1, address p2, uint p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,address,address,uint)", p0, p1, p2, p3));
	}

	function log(string memory p0, address p1, address p2, string memory p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,address,address,string)", p0, p1, p2, p3));
	}

	function log(string memory p0, address p1, address p2, bool p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,address,address,bool)", p0, p1, p2, p3));
	}

	function log(string memory p0, address p1, address p2, address p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,address,address,address)", p0, p1, p2, p3));
	}

	function log(bool p0, uint p1, uint p2, uint p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,uint,uint,uint)", p0, p1, p2, p3));
	}

	function log(bool p0, uint p1, uint p2, string memory p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,uint,uint,string)", p0, p1, p2, p3));
	}

	function log(bool p0, uint p1, uint p2, bool p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,uint,uint,bool)", p0, p1, p2, p3));
	}

	function log(bool p0, uint p1, uint p2, address p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,uint,uint,address)", p0, p1, p2, p3));
	}

	function log(bool p0, uint p1, string memory p2, uint p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,uint,string,uint)", p0, p1, p2, p3));
	}

	function log(bool p0, uint p1, string memory p2, string memory p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,uint,string,string)", p0, p1, p2, p3));
	}

	function log(bool p0, uint p1, string memory p2, bool p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,uint,string,bool)", p0, p1, p2, p3));
	}

	function log(bool p0, uint p1, string memory p2, address p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,uint,string,address)", p0, p1, p2, p3));
	}

	function log(bool p0, uint p1, bool p2, uint p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,uint,bool,uint)", p0, p1, p2, p3));
	}

	function log(bool p0, uint p1, bool p2, string memory p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,uint,bool,string)", p0, p1, p2, p3));
	}

	function log(bool p0, uint p1, bool p2, bool p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,uint,bool,bool)", p0, p1, p2, p3));
	}

	function log(bool p0, uint p1, bool p2, address p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,uint,bool,address)", p0, p1, p2, p3));
	}

	function log(bool p0, uint p1, address p2, uint p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,uint,address,uint)", p0, p1, p2, p3));
	}

	function log(bool p0, uint p1, address p2, string memory p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,uint,address,string)", p0, p1, p2, p3));
	}

	function log(bool p0, uint p1, address p2, bool p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,uint,address,bool)", p0, p1, p2, p3));
	}

	function log(bool p0, uint p1, address p2, address p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,uint,address,address)", p0, p1, p2, p3));
	}

	function log(bool p0, string memory p1, uint p2, uint p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,string,uint,uint)", p0, p1, p2, p3));
	}

	function log(bool p0, string memory p1, uint p2, string memory p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,string,uint,string)", p0, p1, p2, p3));
	}

	function log(bool p0, string memory p1, uint p2, bool p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,string,uint,bool)", p0, p1, p2, p3));
	}

	function log(bool p0, string memory p1, uint p2, address p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,string,uint,address)", p0, p1, p2, p3));
	}

	function log(bool p0, string memory p1, string memory p2, uint p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,string,string,uint)", p0, p1, p2, p3));
	}

	function log(bool p0, string memory p1, string memory p2, string memory p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,string,string,string)", p0, p1, p2, p3));
	}

	function log(bool p0, string memory p1, string memory p2, bool p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,string,string,bool)", p0, p1, p2, p3));
	}

	function log(bool p0, string memory p1, string memory p2, address p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,string,string,address)", p0, p1, p2, p3));
	}

	function log(bool p0, string memory p1, bool p2, uint p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,string,bool,uint)", p0, p1, p2, p3));
	}

	function log(bool p0, string memory p1, bool p2, string memory p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,string,bool,string)", p0, p1, p2, p3));
	}

	function log(bool p0, string memory p1, bool p2, bool p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,string,bool,bool)", p0, p1, p2, p3));
	}

	function log(bool p0, string memory p1, bool p2, address p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,string,bool,address)", p0, p1, p2, p3));
	}

	function log(bool p0, string memory p1, address p2, uint p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,string,address,uint)", p0, p1, p2, p3));
	}

	function log(bool p0, string memory p1, address p2, string memory p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,string,address,string)", p0, p1, p2, p3));
	}

	function log(bool p0, string memory p1, address p2, bool p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,string,address,bool)", p0, p1, p2, p3));
	}

	function log(bool p0, string memory p1, address p2, address p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,string,address,address)", p0, p1, p2, p3));
	}

	function log(bool p0, bool p1, uint p2, uint p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,bool,uint,uint)", p0, p1, p2, p3));
	}

	function log(bool p0, bool p1, uint p2, string memory p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,bool,uint,string)", p0, p1, p2, p3));
	}

	function log(bool p0, bool p1, uint p2, bool p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,bool,uint,bool)", p0, p1, p2, p3));
	}

	function log(bool p0, bool p1, uint p2, address p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,bool,uint,address)", p0, p1, p2, p3));
	}

	function log(bool p0, bool p1, string memory p2, uint p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,bool,string,uint)", p0, p1, p2, p3));
	}

	function log(bool p0, bool p1, string memory p2, string memory p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,bool,string,string)", p0, p1, p2, p3));
	}

	function log(bool p0, bool p1, string memory p2, bool p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,bool,string,bool)", p0, p1, p2, p3));
	}

	function log(bool p0, bool p1, string memory p2, address p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,bool,string,address)", p0, p1, p2, p3));
	}

	function log(bool p0, bool p1, bool p2, uint p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,bool,bool,uint)", p0, p1, p2, p3));
	}

	function log(bool p0, bool p1, bool p2, string memory p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,bool,bool,string)", p0, p1, p2, p3));
	}

	function log(bool p0, bool p1, bool p2, bool p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,bool,bool,bool)", p0, p1, p2, p3));
	}

	function log(bool p0, bool p1, bool p2, address p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,bool,bool,address)", p0, p1, p2, p3));
	}

	function log(bool p0, bool p1, address p2, uint p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,bool,address,uint)", p0, p1, p2, p3));
	}

	function log(bool p0, bool p1, address p2, string memory p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,bool,address,string)", p0, p1, p2, p3));
	}

	function log(bool p0, bool p1, address p2, bool p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,bool,address,bool)", p0, p1, p2, p3));
	}

	function log(bool p0, bool p1, address p2, address p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,bool,address,address)", p0, p1, p2, p3));
	}

	function log(bool p0, address p1, uint p2, uint p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,address,uint,uint)", p0, p1, p2, p3));
	}

	function log(bool p0, address p1, uint p2, string memory p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,address,uint,string)", p0, p1, p2, p3));
	}

	function log(bool p0, address p1, uint p2, bool p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,address,uint,bool)", p0, p1, p2, p3));
	}

	function log(bool p0, address p1, uint p2, address p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,address,uint,address)", p0, p1, p2, p3));
	}

	function log(bool p0, address p1, string memory p2, uint p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,address,string,uint)", p0, p1, p2, p3));
	}

	function log(bool p0, address p1, string memory p2, string memory p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,address,string,string)", p0, p1, p2, p3));
	}

	function log(bool p0, address p1, string memory p2, bool p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,address,string,bool)", p0, p1, p2, p3));
	}

	function log(bool p0, address p1, string memory p2, address p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,address,string,address)", p0, p1, p2, p3));
	}

	function log(bool p0, address p1, bool p2, uint p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,address,bool,uint)", p0, p1, p2, p3));
	}

	function log(bool p0, address p1, bool p2, string memory p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,address,bool,string)", p0, p1, p2, p3));
	}

	function log(bool p0, address p1, bool p2, bool p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,address,bool,bool)", p0, p1, p2, p3));
	}

	function log(bool p0, address p1, bool p2, address p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,address,bool,address)", p0, p1, p2, p3));
	}

	function log(bool p0, address p1, address p2, uint p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,address,address,uint)", p0, p1, p2, p3));
	}

	function log(bool p0, address p1, address p2, string memory p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,address,address,string)", p0, p1, p2, p3));
	}

	function log(bool p0, address p1, address p2, bool p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,address,address,bool)", p0, p1, p2, p3));
	}

	function log(bool p0, address p1, address p2, address p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,address,address,address)", p0, p1, p2, p3));
	}

	function log(address p0, uint p1, uint p2, uint p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,uint,uint,uint)", p0, p1, p2, p3));
	}

	function log(address p0, uint p1, uint p2, string memory p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,uint,uint,string)", p0, p1, p2, p3));
	}

	function log(address p0, uint p1, uint p2, bool p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,uint,uint,bool)", p0, p1, p2, p3));
	}

	function log(address p0, uint p1, uint p2, address p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,uint,uint,address)", p0, p1, p2, p3));
	}

	function log(address p0, uint p1, string memory p2, uint p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,uint,string,uint)", p0, p1, p2, p3));
	}

	function log(address p0, uint p1, string memory p2, string memory p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,uint,string,string)", p0, p1, p2, p3));
	}

	function log(address p0, uint p1, string memory p2, bool p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,uint,string,bool)", p0, p1, p2, p3));
	}

	function log(address p0, uint p1, string memory p2, address p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,uint,string,address)", p0, p1, p2, p3));
	}

	function log(address p0, uint p1, bool p2, uint p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,uint,bool,uint)", p0, p1, p2, p3));
	}

	function log(address p0, uint p1, bool p2, string memory p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,uint,bool,string)", p0, p1, p2, p3));
	}

	function log(address p0, uint p1, bool p2, bool p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,uint,bool,bool)", p0, p1, p2, p3));
	}

	function log(address p0, uint p1, bool p2, address p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,uint,bool,address)", p0, p1, p2, p3));
	}

	function log(address p0, uint p1, address p2, uint p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,uint,address,uint)", p0, p1, p2, p3));
	}

	function log(address p0, uint p1, address p2, string memory p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,uint,address,string)", p0, p1, p2, p3));
	}

	function log(address p0, uint p1, address p2, bool p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,uint,address,bool)", p0, p1, p2, p3));
	}

	function log(address p0, uint p1, address p2, address p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,uint,address,address)", p0, p1, p2, p3));
	}

	function log(address p0, string memory p1, uint p2, uint p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,string,uint,uint)", p0, p1, p2, p3));
	}

	function log(address p0, string memory p1, uint p2, string memory p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,string,uint,string)", p0, p1, p2, p3));
	}

	function log(address p0, string memory p1, uint p2, bool p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,string,uint,bool)", p0, p1, p2, p3));
	}

	function log(address p0, string memory p1, uint p2, address p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,string,uint,address)", p0, p1, p2, p3));
	}

	function log(address p0, string memory p1, string memory p2, uint p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,string,string,uint)", p0, p1, p2, p3));
	}

	function log(address p0, string memory p1, string memory p2, string memory p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,string,string,string)", p0, p1, p2, p3));
	}

	function log(address p0, string memory p1, string memory p2, bool p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,string,string,bool)", p0, p1, p2, p3));
	}

	function log(address p0, string memory p1, string memory p2, address p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,string,string,address)", p0, p1, p2, p3));
	}

	function log(address p0, string memory p1, bool p2, uint p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,string,bool,uint)", p0, p1, p2, p3));
	}

	function log(address p0, string memory p1, bool p2, string memory p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,string,bool,string)", p0, p1, p2, p3));
	}

	function log(address p0, string memory p1, bool p2, bool p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,string,bool,bool)", p0, p1, p2, p3));
	}

	function log(address p0, string memory p1, bool p2, address p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,string,bool,address)", p0, p1, p2, p3));
	}

	function log(address p0, string memory p1, address p2, uint p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,string,address,uint)", p0, p1, p2, p3));
	}

	function log(address p0, string memory p1, address p2, string memory p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,string,address,string)", p0, p1, p2, p3));
	}

	function log(address p0, string memory p1, address p2, bool p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,string,address,bool)", p0, p1, p2, p3));
	}

	function log(address p0, string memory p1, address p2, address p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,string,address,address)", p0, p1, p2, p3));
	}

	function log(address p0, bool p1, uint p2, uint p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,bool,uint,uint)", p0, p1, p2, p3));
	}

	function log(address p0, bool p1, uint p2, string memory p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,bool,uint,string)", p0, p1, p2, p3));
	}

	function log(address p0, bool p1, uint p2, bool p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,bool,uint,bool)", p0, p1, p2, p3));
	}

	function log(address p0, bool p1, uint p2, address p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,bool,uint,address)", p0, p1, p2, p3));
	}

	function log(address p0, bool p1, string memory p2, uint p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,bool,string,uint)", p0, p1, p2, p3));
	}

	function log(address p0, bool p1, string memory p2, string memory p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,bool,string,string)", p0, p1, p2, p3));
	}

	function log(address p0, bool p1, string memory p2, bool p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,bool,string,bool)", p0, p1, p2, p3));
	}

	function log(address p0, bool p1, string memory p2, address p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,bool,string,address)", p0, p1, p2, p3));
	}

	function log(address p0, bool p1, bool p2, uint p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,bool,bool,uint)", p0, p1, p2, p3));
	}

	function log(address p0, bool p1, bool p2, string memory p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,bool,bool,string)", p0, p1, p2, p3));
	}

	function log(address p0, bool p1, bool p2, bool p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,bool,bool,bool)", p0, p1, p2, p3));
	}

	function log(address p0, bool p1, bool p2, address p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,bool,bool,address)", p0, p1, p2, p3));
	}

	function log(address p0, bool p1, address p2, uint p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,bool,address,uint)", p0, p1, p2, p3));
	}

	function log(address p0, bool p1, address p2, string memory p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,bool,address,string)", p0, p1, p2, p3));
	}

	function log(address p0, bool p1, address p2, bool p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,bool,address,bool)", p0, p1, p2, p3));
	}

	function log(address p0, bool p1, address p2, address p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,bool,address,address)", p0, p1, p2, p3));
	}

	function log(address p0, address p1, uint p2, uint p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,address,uint,uint)", p0, p1, p2, p3));
	}

	function log(address p0, address p1, uint p2, string memory p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,address,uint,string)", p0, p1, p2, p3));
	}

	function log(address p0, address p1, uint p2, bool p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,address,uint,bool)", p0, p1, p2, p3));
	}

	function log(address p0, address p1, uint p2, address p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,address,uint,address)", p0, p1, p2, p3));
	}

	function log(address p0, address p1, string memory p2, uint p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,address,string,uint)", p0, p1, p2, p3));
	}

	function log(address p0, address p1, string memory p2, string memory p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,address,string,string)", p0, p1, p2, p3));
	}

	function log(address p0, address p1, string memory p2, bool p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,address,string,bool)", p0, p1, p2, p3));
	}

	function log(address p0, address p1, string memory p2, address p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,address,string,address)", p0, p1, p2, p3));
	}

	function log(address p0, address p1, bool p2, uint p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,address,bool,uint)", p0, p1, p2, p3));
	}

	function log(address p0, address p1, bool p2, string memory p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,address,bool,string)", p0, p1, p2, p3));
	}

	function log(address p0, address p1, bool p2, bool p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,address,bool,bool)", p0, p1, p2, p3));
	}

	function log(address p0, address p1, bool p2, address p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,address,bool,address)", p0, p1, p2, p3));
	}

	function log(address p0, address p1, address p2, uint p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,address,address,uint)", p0, p1, p2, p3));
	}

	function log(address p0, address p1, address p2, string memory p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,address,address,string)", p0, p1, p2, p3));
	}

	function log(address p0, address p1, address p2, bool p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,address,address,bool)", p0, p1, p2, p3));
	}

	function log(address p0, address p1, address p2, address p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,address,address,address)", p0, p1, p2, p3));
	}

}


// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity 0.8.3;
pragma experimental ABIEncoderV2;

interface CyberBoxCertInterface2 {
    event CertificationReferFeeChanged(
        uint256 referFee
    );

    event CertificationNFTReferMinted(
        address owner,
        address refer,
        uint256 tokenType,
        uint256 tokenId,
        uint256 year,
        uint256 month,
        uint256 price,
        uint256 devFee,
        uint256 referFee,
        uint256 c02
    );
}

// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity 0.8.3;
pragma experimental ABIEncoderV2;

import {StringsUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/StringsUpgradeable.sol";
import "hardhat/console.sol";

contract CertificationURIParser {
    function substring(string memory str, uint startIndex, uint endIndex) private returns (string memory ) {
        bytes memory strBytes = bytes(str);
        bytes memory result = new bytes(endIndex-startIndex);
        for(uint i = startIndex; i < endIndex; i++) {
            result[i-startIndex] = strBytes[i];
        }
        return string(result);
    }

    function strLen(string memory s) private returns (uint256) {
        return bytes(s).length;
    }

    function compareStrings(string memory a, string memory b) private returns (bool) {
        return (keccak256(abi.encodePacked((a))) == keccak256(abi.encodePacked((b))));
    }

    function strToUint(string memory _str) private returns(uint256 res, bool err) {
        for (uint256 i = 0; i < bytes(_str).length; i++) {
            if ((uint8(bytes(_str)[i]) - 48) < 0 || (uint8(bytes(_str)[i]) - 48) > 9) {
                return (0, false);
            }
            res += (uint8(bytes(_str)[i]) - 48) * 10**(bytes(_str).length - i - 1);
        }
        return (res, true);
    }
    
    function parsingTokenURI(string memory _url, string memory baseURI) public returns (uint256, uint256, uint256) {
        uint256 tokenType;
        uint256 year;
        uint256 month;
        string memory parsedString = substring(_url, strLen(baseURI) + 1, strLen(_url));
        string memory typeStr = substring(parsedString, 0, 1);
        string memory yearStr = substring(parsedString, 1, 5);
        (uint256 _year, bool success) = strToUint(yearStr);
        year = _year;
        if(compareStrings(typeStr, "m") == true){
            tokenType = 0;
            string memory monthStr = substring(parsedString, 5, 6);
            (uint256 _month, bool success) = strToUint(monthStr);
            month = _month;
        }else if(compareStrings(typeStr, "y") == true){
            tokenType = 1;
        }else{
            tokenType = 2;
        }
        return (tokenType, year, month);
    }
}


// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity 0.8.3;
pragma experimental ABIEncoderV2;

interface IUniswapV2Router {
  function getAmountsOut(uint256 amountIn, address[] memory path)
    external
    view
    returns (uint256[] memory amounts);
  
  function swapExactTokensForTokens(
  
    //amount of tokens we are sending in
    uint256 amountIn,
    //the minimum amount of tokens we want out of the trade
    uint256 amountOutMin,
    //list of token addresses we are going to trade in.  this is necessary to calculate amounts
    address[] calldata path,
    //this is the address we are going to send the output tokens to
    address to,
    //the last time that the trade is valid for
    uint256 deadline
  ) external returns (uint256[] memory amounts);
}

interface IUniswapV2Pair {
  function token0() external view returns (address);
  function token1() external view returns (address);
  function swap(
    uint256 amount0Out,
    uint256 amount1Out,
    address to,
    bytes calldata data
  ) external;
}

interface IUniswapV2Factory {
  function getPair(address token0, address token1) external returns (address);
}

// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity 0.8.3;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

import "./CertificationMarketAPI.sol";

contract CertificationMarketPlace is CertificationMarketAPI {
    using SafeMath for uint256;
    using Address for address;
    using EnumerableSet for EnumerableSet.UintSet;
    using EnumerableSet for EnumerableSet.AddressSet;

    struct Listing {
        uint256 tokenId;
        uint256 listingPrice;
        address seller;
    }

    mapping(uint256 => Listing) private _tokenListings;
    EnumerableSet.UintSet private _tokenIdWithListing;

    uint256[] private _tempTokenIdStorage; // Storage to assist cleaning


    function initializeWithERC721(
        address _erc721Address,
        address _owner
    ) public {
        initializeAPI(_owner, _erc721Address);
    }

    function _isListingValid(Listing memory listing) private view returns (bool) {
        if (
            _isTokenOwner(listing.tokenId, listing.seller) &&
            (_isTokenApproved(listing.tokenId) || _isAllTokenApproved(listing.seller)) &&
            listing.listingPrice > 0) {
            return true;
        }
    }
    function deleteTempTokenIdStorage() public {
        delete _tempTokenIdStorage;
    }

    function getTokenListing(uint256 tokenId) public view returns (Listing memory) {
        Listing memory listing = _tokenListings[tokenId];
        if (_isListingValid(listing)) {
            return listing;
        }
    }
    function getTokenListings(uint256 from, uint256 size)
        public
        view
        returns (Listing[] memory)
    {
        if (from < _tokenIdWithListing.length() && size > 0) {
            uint256 querySize = size;
            if ((from + size) > _tokenIdWithListing.length()) {
                querySize = _tokenIdWithListing.length() - from;
            }
            Listing[] memory listings = new Listing[](querySize);
            for (uint256 i = 0; i < querySize; i++) {
                Listing memory listing = _tokenListings[_tokenIdWithListing.at(i + from)];
                if (_isListingValid(listing)) {
                    listings[i] = listing;
                }
            }
            return listings;
        }
    }
    function getAllTokenListings() external view returns (Listing[] memory) {
        return getTokenListings(0, _tokenIdWithListing.length());
    }
    function _delistToken(uint256 tokenId) private {
        if (_tokenIdWithListing.contains(tokenId)) {
            delete _tokenListings[tokenId];
            _tokenIdWithListing.remove(tokenId);
        }
    }
    function getInvalidListingCount() external view returns (uint256) {
        uint256 count = 0;
        for (uint256 i = 0; i < _tokenIdWithListing.length(); i++) {
            if (!_isListingValid(_tokenListings[_tokenIdWithListing.at(i)])) {
                count = count.add(1);
            }
        }
        return count;
    }

    function listToken(
        address sender,
        uint256 tokenId,
        uint256 value
    ) public
     returns (
        address, 
        uint256
    ) {
        require(value > 0, "Please list for more than 0 or use the transfer function");
        require(_isTokenOwner(tokenId, sender), "Only token owner can list token");
        require(
            _isTokenApproved(tokenId) || _isAllTokenApproved(sender),
            "This token is not allowed to transfer by this contract"
        );
        _tokenListings[tokenId] = Listing(tokenId, value, sender);
        _tokenIdWithListing.add(tokenId);
        return ( sender, value);
    }

    function delistToken(address sender, uint256 tokenId) public {
        require(_tokenListings[tokenId].seller == sender, "Only token seller can delist token");
        _delistToken(tokenId);
    }

    function certCleanAllInvalidListings() public returns(uint256[] memory){
        for (uint256 i = 0; i < _tokenIdWithListing.length(); i++) {
            uint256 tokenId = _tokenIdWithListing.at(i);
            if (!_isListingValid(_tokenListings[tokenId])) {
                _tempTokenIdStorage.push(tokenId);
            }
        }
        for (uint256 i = 0; i < _tempTokenIdStorage.length; i++) {
            _delistToken(_tempTokenIdStorage[i]);
        }
        
        return (_tempTokenIdStorage);
    }


    function certChangePrice(address sender,uint256 tokenId, uint256 newPrice) public {
        Listing memory listing = getTokenListing(tokenId); // Get valid listing
        require(_isTokenOwner(tokenId, sender), "Only token owner can change price of token");
        require(listing.seller != address(0), "Token is not for sale"); // Listing not valid
        require(
            newPrice >= 0,
            "The value send is below zero"
        );
        _tokenListings[tokenId].listingPrice = newPrice;
    }

    function buyTokenPrepare(address sender, uint256 tokenId, uint256 value) public returns (
        address,
        address, 
        address,
        address
    ) {
        Listing memory listing = getTokenListing(tokenId); // Get valid listing
        require(listing.seller != address(0), "Token is not for sale"); // Listing not valid
        require(!_isTokenOwner(tokenId, sender), "Token owner can't buy their own token");
        require(
            value >= listing.listingPrice,
            
            "The value send is below sale price plus fees"
        );
        return (
            listing.seller,
            maketPlaceFeeAddress,
            nftCreaterAddress,
            nftProducerAddress
        );
    }
    function buyTokenComplete(address sender, uint256 tokenId) public  {
        Listing memory listing = getTokenListing(tokenId); // Get valid listing
         nftTransferFrom(listing.seller, sender, tokenId);
         // Remove token listing
        _delistToken(tokenId);
    }

}

// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity 0.8.3;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import "../CyberBoxCertInterface.sol";

contract CertificationMarketAPI is CyberBoxCertInterface {
    using SafeMath for uint256;

    uint256 private _baseFeeTokenSeller;
    uint256 private _baseFeeTokenProducer;
    uint256 private _baseFeeTokenCreater;
    uint256 private _baseFeeTokenDev;
    uint256 private _baseFeeFraction;
    uint256 private _baseFeeTokenBase;

    address public maketPlaceFeeAddress;
    address public nftCreaterAddress;
    address public nftProducerAddress;

    IERC721 private _erc721;

    function initializeAPI(
        address _owner,
        address _certNft
    ) public {
        _baseFeeTokenSeller = 975;
        _baseFeeTokenProducer = 0;
        _baseFeeTokenCreater = 0;
        _baseFeeTokenDev = 25;
        _baseFeeFraction = 25;
        _baseFeeTokenBase = 1000;

        maketPlaceFeeAddress = _owner;

        _erc721 = IERC721(_certNft);

        emit CertificationDevFeeChanged(
            maketPlaceFeeAddress,
            _baseFeeTokenDev
        );
    }
    
    function calculateSellerFee(uint256 value) public returns(uint256){
        return value.sub(value.mul(_baseFeeFraction).div(_baseFeeTokenBase));
    }
    function calculateDevFee(uint256 value) public returns(uint256){
        return value.mul(_baseFeeTokenDev).div(_baseFeeTokenBase);
    }
    function calculateCreaterFee(uint256 value) public returns(uint256){
        return value.mul(_baseFeeTokenCreater).div(_baseFeeTokenBase);
    }
    function calculateProducerFee(uint256 value) public returns(uint256){
        return value.mul(_baseFeeTokenProducer).div(_baseFeeTokenBase);
    }

    function setNFTFees(
        uint256 _feeCreater,
        uint256 _feeProducer
        )
        external
    {
        require(
            _feeCreater == 0 || nftCreaterAddress != address(0), "This token don't set creater address"
        );
        require(
            _feeProducer == 0 || nftProducerAddress != address(0), "This token don't set producer address"
        );

        _baseFeeTokenCreater = _feeCreater;
        _baseFeeTokenProducer = _feeProducer;
        _baseFeeTokenSeller = _baseFeeTokenBase - _baseFeeTokenCreater - _baseFeeTokenDev - _baseFeeTokenProducer;
        _baseFeeFraction = _baseFeeTokenCreater + _baseFeeTokenDev + _baseFeeTokenProducer;

        emit CertificationFeeChanged(_feeCreater, _feeProducer);
    }

    function setMaketPlaceAddressAndDevFee(
        address _maketPlaceFeeAddress, 
        uint256 _maketPlaceFeePercentage)
        external
    {
        require(
            _maketPlaceFeePercentage > 0 && _maketPlaceFeePercentage <= 1000,
            "Allowed percentage range is 1 to 1000"
        );
        maketPlaceFeeAddress = _maketPlaceFeeAddress;
        require(
            1000 == _baseFeeTokenBase, "This token is not registed"
        );

        _baseFeeTokenDev = _maketPlaceFeePercentage;
        _baseFeeTokenSeller = _baseFeeTokenBase - _baseFeeTokenDev - _baseFeeTokenCreater - _baseFeeTokenProducer; 
        _baseFeeFraction = _baseFeeTokenDev + _baseFeeTokenCreater + _baseFeeTokenProducer;
    
        emit CertificationDevFeeChanged(_maketPlaceFeeAddress, _maketPlaceFeePercentage);
    }

    function setTokenCreaterAddress(
        address _tokenCreaterAddress)
        external
    {
        require(_tokenCreaterAddress != address(0), "Can't set to address 0x0");
        require(
            1000 == _baseFeeTokenBase, "This token is not registed"
        );
        nftCreaterAddress = _tokenCreaterAddress;

        emit CertificationTokenCreaterChanged(_tokenCreaterAddress);
    }

    function setTokenProducerAddress(
        address _tokenProducerAddress)
        external
    {
        require(_tokenProducerAddress != address(0), "Can't set to address 0x0");
        require(
            1000 == _baseFeeTokenBase, "This token is not registed"
        );
        nftProducerAddress = _tokenProducerAddress;

        emit CertificationTokenProducerChanged(_tokenProducerAddress);
    }

    function changeTokenCreaterAddress(
        address _tokenCreaterAddress) external {
        nftCreaterAddress = _tokenCreaterAddress;
    }

    function _isTokenOwner(uint256 tokenId, address account) public view returns (bool) {
        try _erc721.ownerOf(tokenId) returns (address tokenOwner) {
            return tokenOwner == account;
        } catch {
            return false;
        }
   }

   function _isTokenApproved(uint256 tokenId) public view returns (bool) {
        try _erc721.getApproved(tokenId) returns (address tokenOperator) {
            return tokenOperator == address(this);
        } catch {
            return false;
        }
    }

    function _isAllTokenApproved(address owner) public view returns (bool) {
        return _erc721.isApprovedForAll(owner, address(this));
    }

    function nftTransferFrom(
        address sender,
        address to,
        uint256 tokenId
    ) public {
        _erc721.safeTransferFrom(sender, to, tokenId);
    }


    function transfer(
        address sender,
        address to,
        uint256 tokenId
    ) public {
        require(_isTokenOwner(tokenId, sender), "Only token owner can accept bid of token");
        require(
            _isTokenApproved(tokenId) || _isAllTokenApproved(sender),
            "The token is not approved to transfer by the contract"
        );
        _erc721.safeTransferFrom(sender, to, tokenId);
    }
}

// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.3;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";

import "hardhat/console.sol";

contract DateTimeManager {

    mapping (uint256 => uint256) public YEARS; /// year num => year start timestamp
    mapping (uint256 => uint256) public MONTHS; /// year num * 100 + month num => month start timestamp

    uint256 public current_year;
    uint256 public current_month;

    constructor() public {
        YEARS[2022] = 1641020400; /// timestamp of 2022-01-01
        YEARS[2023] = 1672556400; /// timestamp of 2023-01-01
        YEARS[2024] = 1704092400; /// timestamp of 2024-01-01

        MONTHS[202203] = 1646118000; /// timestamp of 2022-03-01
        MONTHS[202303] = 1677654000; /// timestamp of 2023-03-01
        MONTHS[202403] = 1709276400; /// timestamp of 2024-03-01

        current_year = 2022;
        current_month = 5;

        generateMonthStartTimes(current_year);
        determineDateTime();
    }

    function generateMonthStartTimes(uint256 year) private {
        MONTHS[year * 100 + 1] = YEARS[year];
        MONTHS[year * 100 + 2] = YEARS[year] + (24*3600*31);
        MONTHS[year * 100 + 4] = MONTHS[year * 100 + 3] + (24*3600*31);
        MONTHS[year * 100 + 5] = MONTHS[year * 100 + 4] + (24*3600*30);
        MONTHS[year * 100 + 6] = MONTHS[year * 100 + 5] + (24*3600*31);
        MONTHS[year * 100 + 7] = MONTHS[year * 100 + 6] + (24*3600*30);
        MONTHS[year * 100 + 8] = MONTHS[year * 100 + 7] + (24*3600*31);
        MONTHS[year * 100 + 9] = MONTHS[year * 100 + 8] + (24*3600*31);
        MONTHS[year * 100 + 10] = MONTHS[year * 100 + 9] + (24*3600*30);
        MONTHS[year * 100 + 11] = MONTHS[year * 100 + 10] + (24*3600*31);
        MONTHS[year * 100 + 12] = MONTHS[year * 100 + 11] + (24*3600*30);
    }

    function determineDateTime() public {
        uint256 current_time = block.timestamp;
        uint256 nextYearStartTime = YEARS[current_year + 1];
        if(current_time > nextYearStartTime) {
            current_year = current_year + 1;
            generateMonthStartTimes(current_year);
        }

        uint256 current_month_start = MONTHS[current_year * 100 + current_month];
        uint256 next_month_start = MONTHS[current_year * 100 + current_month + 1];
        if(current_time > next_month_start || current_time < current_month_start){
            for(uint256 i = 1; i <= 12; i ++){
                uint256 select_month_start = MONTHS[current_year * 100 + i];
                if(current_time < select_month_start){
                    break;
                }
                current_month = i;
            }
        }
    }

    function getDateTimeSymbol() public returns (uint256 year, uint256 month){
        determineDateTime();
        return (current_year, current_month);
    }


    function addNewYear(uint256 year, uint256 startTimeStamp) public {
        YEARS[year] = startTimeStamp;
    }
    function addNewMarch(uint256 year, uint256 startTimeStamp) public {
        uint256 march_key = year * 100 + 3;
        MONTHS[march_key] = startTimeStamp;
    }
    function setCurrentYear(uint256 year) public {
        current_year = year;
    }
    function setCurrentMonth(uint256 month) public {
        current_month = month;
    }
}

// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity 0.8.3;
pragma experimental ABIEncoderV2;

import {StringsUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/StringsUpgradeable.sol";

contract CyberBoxCertResource {

    string public baseURI;

    function setBaseURI(string memory _uri) public {
        baseURI = _uri;
    }

    function numberToString(uint256 value)
        public
        pure
        returns (string memory)
    {
        return StringsUpgradeable.toString(value);
    }

    

    function getMonthTokenURI(uint256 year, uint256 month) public returns (string memory) {
        return string(
            abi.encodePacked(
                    baseURI,
                    "/m",
                    numberToString(year),
                    numberToString(month),
                    ".json"
                )
            );
    }
    function getYearTokenURI(uint256 year) public returns (string memory) {
        return string(
            abi.encodePacked(
                    baseURI,
                    "/y",
                    numberToString(year),
                    ".json"
                )
            );
    }
    function getBonusTokenURI(uint256 year) public returns (string memory) {
        return string(
            abi.encodePacked(
                    baseURI,
                    "/b",
                    numberToString(year),
                    ".json"
                )
            );
    }

}

// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity 0.8.3;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ERC721URIStorage} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import {CountersUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/CountersUpgradeable.sol";

import "hardhat/console.sol";

contract CyberBoxCertNFT is ERC721URIStorage  {

    address public dev;
    address public owner;

    using CountersUpgradeable for CountersUpgradeable.Counter;
    
    CountersUpgradeable.Counter private atEditionId;

    constructor(
        address _owner,
        address _dev
    ) public ERC721("CyberBoxCertNFT", "CBCN") {
        owner = _owner;
        dev = _dev;
    }

    function mintNFT(address _recipient, string memory _tokenURI) public onlyDev returns (uint256) {
        atEditionId.increment();
        uint256 tokenId = atEditionId.current();
        _mint(_recipient, tokenId);
        _setTokenURI(tokenId, _tokenURI);
        return (tokenId);
    }

    function burn(address _recipient, uint256 tokenId) public onlyDev {
        require(_isApprovedOrOwner(_recipient, tokenId), "Not approved");
        _burn(tokenId);
    }

    function changeDev(address _newDev) public onlyDev {
        dev  = _newDev;
    }

    modifier onlyDev() {
        require((msg.sender == dev || msg.sender == owner), "CyberBoxCertNFT: wrong developer");
        _;
    }

    function tokenURI(uint256 tokenId)
        public
        view
        override
        returns (string memory)
    {
        return super.tokenURI(tokenId);
    }
}

// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.3;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/utils/Address.sol";

import "hardhat/console.sol";

import "./DateTimeManager.sol";
import "./CyberBoxCertNFT.sol";
import "./CyberBoxCertInterface.sol";
import "./V2/CyberBoxCertInterface2.sol";
import "./CyberBoxCertResource.sol";
import "./Uniswap/uniswpv2.sol";
import "./CyberBoxCertMinter.sol";

import "./MarketPlace/CertificationMarketPlace.sol";
import "./V2/CertificationURIParser.sol";

contract CyberBoxCertMinterV2 is DateTimeManager, CyberBoxCertInterface, CyberBoxCertResource, CertificationMarketPlace, CertificationURIParser, CyberBoxCertInterface2 {
    using Address for address;

    struct NFTMAP  {
        uint256 tokenType;
        uint256 year;
        uint256 month;
    }

    address public dev;
    address public owner;
    address public c02Owner;
    uint256 public offsetFee;
    uint256 public carvonFeeOnOffset;
    uint256 public referFee;

    address public linkedNFTAddress;

    address private constant UNISWAP_V2_ROUTER = 0xE3D8bd6Aed4F159bc8000a9cD47CffDb95F96121;
    address private constant WETH = 0x471EcE3750Da237f93B8E339c536989b8978a438;
    address public CARBOM = 0x32A9FE697a32135BFd313a6Ac28792DaE4D9979d;

    uint256 public limitMonthNFTPrice;
    uint256 public limitBonusNFTPrice;
    
    //////// owner address => year_month_key => token id
    mapping (address => mapping(uint256 => uint256)) public ownedMonthData;
    mapping (address => mapping(uint256 => uint256)) public ownedYearData;
    mapping (address => mapping(uint256 => uint256)) public ownedBonusData;

    mapping (uint256 => NFTMAP) public _nftDateMap;
    

    uint256 private TOKEN_TYPE_MONTH = 0;
    uint256 private TOKEN_TYPE_YEAR = 1;
    uint256 private TOKEN_TYPE_BONUS = 2;

    uint256 public syncedNFTId = 1;

    constructor(
        address _nft,
        address _dev,
        address _owner,
        address _carvon
    ) public {
        linkedNFTAddress = _nft;
        initializeWithERC721(_nft, _owner);
        dev = _dev;
        owner = _owner;
        c02Owner = _carvon;
        offsetFee = 400;
        carvonFeeOnOffset = 1000;
        referFee = 100;

        limitMonthNFTPrice = 15e18;
        limitBonusNFTPrice = 15e18;


        uint256 producerFee = (offsetFee * carvonFeeOnOffset) / 1000;
        uint256 devFee = (offsetFee * (1000 - carvonFeeOnOffset)) / 1000;
        uint256 createrFee = 1000 - producerFee - devFee;
        emit CertificationReferFeeChanged(referFee);
    }

    function restoreFromV1(address contractV1) public onlyDev {
        Listing[] memory listedTokens = CyberBoxCertMinter(contractV1).getAllTokenListings();
        uint256 querySize = listedTokens.length;
        for (uint256 i = 0; i < querySize; i++) {
            Listing memory item = listedTokens[i];
            emit CertificationTokenDelisted(
                linkedNFTAddress,
                item.tokenId
            );
        }
        c02Owner = CyberBoxCertMinter(contractV1).c02Owner();
        offsetFee = CyberBoxCertMinter(contractV1).offsetFee();
        carvonFeeOnOffset = CyberBoxCertMinter(contractV1).carvonFeeOnOffset();
        limitMonthNFTPrice = CyberBoxCertMinter(contractV1).limitMonthNFTPrice();
        limitBonusNFTPrice = CyberBoxCertMinter(contractV1).limitBonusNFTPrice();
        CARBOM = CyberBoxCertMinter(contractV1).CARBOM();
    }

    function parseMetadata(uint256 tokenId) private returns (uint256, uint256, uint256){
        string memory tokenUri = CyberBoxCertNFT(linkedNFTAddress).tokenURI(tokenId);
        return parsingTokenURI(tokenUri, baseURI);
    }

    function restoreNFTs(uint256 totalSupply) public onlyDev {
        uint256 stepCount = 50;
        if(totalSupply - syncedNFTId < stepCount){
            stepCount = totalSupply - syncedNFTId;
        }
        for (uint256 i = 0; i <= stepCount; i++) {
            uint256 tokenId = i + syncedNFTId;
            address nftOwner = IERC721(linkedNFTAddress).ownerOf(tokenId);
            (uint256 tokenType, uint256 year, uint256 month) = parseMetadata(tokenId);
            if(tokenType == TOKEN_TYPE_MONTH) {
                ownedMonthData[nftOwner][year*100 + month] = tokenId;
            }else if(tokenType == TOKEN_TYPE_YEAR){
                ownedYearData[nftOwner][year] = tokenId;
            }else{
                ownedBonusData[nftOwner][year] = tokenId;
            }
            _nftDateMap[tokenId] = NFTMAP(tokenType, year, month);
        }
        syncedNFTId = syncedNFTId + stepCount;
    }

    function contractIdValidate(uint256 contractId) public returns (bool) {
        NFTMAP memory ownerMap = _nftDateMap[contractId];
        if(ownerMap.year != 0){
            return (true);
        }
        return (false);
    }

    function uniwapCarbon(address _to, uint256 _amountIn) public returns (uint256[] memory amounts){
        
        IERC20(WETH).approve(UNISWAP_V2_ROUTER, _amountIn);
        address[] memory path = new address[](2);
        path[0] = WETH;
        path[1] = CARBOM;
        return IUniswapV2Router(UNISWAP_V2_ROUTER).swapExactTokensForTokens(_amountIn, 0, path, _to, block.timestamp);
    }

    function offset(uint256 amount) private returns(uint256 sf, uint256 df, uint256 co2) {
        uint256 totalFee = (amount * offsetFee) / 1000;
        uint256 c02Fee = (totalFee * carvonFeeOnOffset) / 1000;
        uint256 devFee = totalFee - c02Fee;
        uint256 sellerFee = amount - totalFee;

        payable(owner).transfer(sellerFee);
        payable(dev).transfer(devFee);

        uint256[] memory amounts = uniwapCarbon(c02Owner, c02Fee);
        uint256 co2Value = amounts[amounts.length - 1];
        
        return (sellerFee, devFee, co2Value);
    }

    function mintMonthNFTFromRefer(address refer)  external payable {
        (uint256 year, uint256 month) = getDateTimeSymbol();
        uint256 current_nft_id = getCurrentMonthNFTID(msg.sender);
        require(current_nft_id < 1, "This user already mint nft for this month.");
        require(msg.value >= limitMonthNFTPrice, "This user must pay for mint nft.");

        uint256 totalValue = msg.value;
        uint256 referValue = (msg.value * referFee) / 1000;
        uint256 mintValue = totalValue - referValue;
        (uint256 sellerFee, uint256 devFee, uint256 co2Value) = offset(mintValue);

        payable(refer).transfer(referValue);

        string memory token_uri = getMonthTokenURI(year, month);
        uint256 nft_id = CyberBoxCertNFT(linkedNFTAddress).mintNFT(msg.sender, token_uri);
        ownedMonthData[msg.sender][year*100 + month] = nft_id;
        _nftDateMap[nft_id] = NFTMAP(TOKEN_TYPE_MONTH, year, month);
        emit CertificationNFTMinted(msg.sender, TOKEN_TYPE_MONTH, nft_id, year, month, totalValue, devFee, co2Value);
        emit CertificationNFTReferMinted(msg.sender, refer, TOKEN_TYPE_MONTH, nft_id, year, month, totalValue, devFee, referValue, co2Value);
    }

    function mintMonthNFT() external payable {
        (uint256 year, uint256 month) = getDateTimeSymbol();
        uint256 current_nft_id = getCurrentMonthNFTID(msg.sender);
        require(current_nft_id < 1, "This user already mint nft for this month.");
        require(msg.value >= limitMonthNFTPrice, "This user must pay for mint nft.");

        uint256 totalValue = msg.value;
        (uint256 sellerFee, uint256 devFee, uint256 co2Value) = offset(totalValue);
        
        string memory token_uri = getMonthTokenURI(year, month);
        uint256 nft_id = CyberBoxCertNFT(linkedNFTAddress).mintNFT(msg.sender, token_uri);
        ownedMonthData[msg.sender][year*100 + month] = nft_id;
        _nftDateMap[nft_id] = NFTMAP(TOKEN_TYPE_MONTH, year, month);
        emit CertificationNFTMinted(msg.sender, TOKEN_TYPE_MONTH, nft_id, year, month, totalValue, devFee, co2Value);
    }


    function adminMintMonthlyNFT(address user, uint256 month) public onlyDev {
        uint256 year = 2022;
        require(month < 7, "You can't mint over June.");
        uint256 current_nft_id = getMonthNFTID(user, year, month);
        if(current_nft_id < 1) {
            string memory token_uri = getMonthTokenURI(year, month);
            uint256 nft_id = CyberBoxCertNFT(linkedNFTAddress).mintNFT(user, token_uri);
            ownedMonthData[user][year*100 + month] = nft_id;
            _nftDateMap[nft_id] = NFTMAP(TOKEN_TYPE_MONTH, year, month);
            emit CertificationNFTMinted(user, TOKEN_TYPE_MONTH, nft_id, year, month, 0, 0, 0);
        }
    }
    function adminMintAllNFTs(address user)  public onlyDev {
        uint256 year = 2022;
        for(uint256 month = 1; month<=6; month++){
            uint256 current_nft_id = getMonthNFTID(user, year, month);
            if(current_nft_id < 1) {
                string memory token_uri = getMonthTokenURI(year, month);
                uint256 nft_id = CyberBoxCertNFT(linkedNFTAddress).mintNFT(user, token_uri);
                ownedMonthData[user][year*100 + month] = nft_id;
                _nftDateMap[nft_id] = NFTMAP(TOKEN_TYPE_MONTH, year, month);
                emit CertificationNFTMinted(user, TOKEN_TYPE_MONTH, nft_id, year, month, 0, 0, 0);
            }
        }
    }

    function mintMonthNFTFor(address receipt, uint256 year, uint256 month) private {
        uint256 current_nft_id = getMonthNFTID(receipt, year, month);
        if(current_nft_id < 1) {
            string memory token_uri = getMonthTokenURI(year, month);
            uint256 nft_id = CyberBoxCertNFT(linkedNFTAddress).mintNFT(msg.sender, token_uri);
            ownedMonthData[msg.sender][year*100 + month] = nft_id;
            _nftDateMap[nft_id] = NFTMAP(TOKEN_TYPE_MONTH, year, month);
            emit CertificationNFTMinted(msg.sender, TOKEN_TYPE_MONTH, nft_id, year, month, 0, 0, 0);
        }
    }

    function mintYearNFT()  external onlyDev payable  {
        (uint256 year, uint256 month) = getDateTimeSymbol();
        uint256 current_nft_id = getCurrentYearNFTID(msg.sender);
        require(current_nft_id < 1, "This user already mint nft for this month.");
        require(msg.value >= limitMonthNFTPrice, "This user must pay for mint nft.");
        
        uint256 totalValue = msg.value;
        
        (uint256 sellerFee, uint256 devFee, uint256 co2Value) = offset(totalValue);

        string memory token_uri = getYearTokenURI(year);
        uint256 nft_id = CyberBoxCertNFT(linkedNFTAddress).mintNFT(msg.sender, token_uri);
        ownedYearData[msg.sender][year] = nft_id;
        _nftDateMap[nft_id] = NFTMAP(TOKEN_TYPE_YEAR, year, 0);
        emit CertificationNFTMinted(msg.sender, TOKEN_TYPE_YEAR, nft_id, year, 0, totalValue, devFee, co2Value);
    }

    function mintBonusNFT() external onlyDev payable {
        (uint256 year, uint256 month) = getDateTimeSymbol();
        uint256 current_nft_id = getCurrentBonusNFTID(msg.sender);
        require(current_nft_id < 1, "This user already mint nft for this month.");
        require(msg.value >= limitBonusNFTPrice, "This user must pay for mint nft.");

        uint256 totalValue = msg.value;
        (uint256 sellerFee, uint256 devFee, uint256 co2Value) = offset(totalValue);

        string memory token_uri = getBonusTokenURI(year);
        uint256 nft_id = CyberBoxCertNFT(linkedNFTAddress).mintNFT(msg.sender, token_uri);
        ownedBonusData[msg.sender][year] = nft_id;
        _nftDateMap[nft_id] = NFTMAP(TOKEN_TYPE_BONUS, year, 0);
        emit CertificationNFTMinted(msg.sender, TOKEN_TYPE_BONUS, nft_id, year, 0, totalValue, devFee, co2Value);
    }

    function exchangeBonusNFTToMonth(uint256 year) public {
        uint256 current_nft_id = getBonusNFTID(msg.sender, year);
        require(current_nft_id > 0, "This user don't have bonus NFT.");
        CyberBoxCertNFT(linkedNFTAddress).burn(msg.sender, current_nft_id);
        ownedBonusData[msg.sender][year] = 0;
        emit CertificationNFTBurned(msg.sender, TOKEN_TYPE_BONUS, current_nft_id, year, 0);
        for(uint256 month = 1; month<=12; month++){
            mintMonthNFTFor(msg.sender, year, month);
        }
    }

    function exchangeMonthNFTToBonus(uint256 year) public {
        uint256 current_bonus_id = getCurrentBonusNFTID(msg.sender);
        require(current_bonus_id < 1, "This user already mint nft for this month.");
        for(uint256 month = 1; month<=12; month++){
            uint256 current_nft_id = getMonthNFTID(msg.sender, year, month);
            require(current_nft_id > 0, "This user don't have all month NFT.");
            CyberBoxCertNFT(linkedNFTAddress).burn(msg.sender, current_nft_id);
            ownedMonthData[msg.sender][year*100 + month] = 0;
            emit CertificationNFTBurned(msg.sender, TOKEN_TYPE_MONTH, current_nft_id, year, 0);
        }
        string memory token_uri = getBonusTokenURI(year);
        uint256 nft_id = CyberBoxCertNFT(linkedNFTAddress).mintNFT(msg.sender, token_uri);
        ownedBonusData[msg.sender][year] = nft_id;
        emit CertificationNFTMinted(msg.sender, TOKEN_TYPE_BONUS, nft_id, year, 0, 0, 0, 0);
    }

    function transferNFTOwnedData(address from, address to, uint256 tokenId) private {
        NFTMAP memory mapData = _nftDateMap[tokenId];
        uint256 tokenType = mapData.tokenType;
        uint256 year = mapData.year;
        uint256 month = mapData.month;
        if (tokenType == TOKEN_TYPE_MONTH){
            ownedMonthData[from][year*100 + month] = 0;
            ownedMonthData[to][year*100 + month] = tokenId;
        }
        if (tokenType == TOKEN_TYPE_YEAR) {
            ownedYearData[from][year] = 0;
            ownedYearData[to][year] = tokenId;
        }
        if (tokenType == TOKEN_TYPE_BONUS) {
            ownedBonusData[from][year] = 0;
            ownedBonusData[to][year] = tokenId;
        }
    }


    function getMonthNFTID(address owner, uint256 year, uint256 month) public returns (uint256){
        console.log("Month:", ownedMonthData[owner][year * 100 + month]);
        return ownedMonthData[owner][year * 100 + month];
    }

    function getYearNFTID(address owner, uint256 year) public returns (uint256) {
        return ownedYearData[owner][year];
    }

    function getBonusNFTID(address owner, uint256 year) public returns (uint256) {
        return ownedBonusData[owner][year];
    }

    
    function getCurrentMonthNFTID(address owner) public returns (uint256) {
        (uint256 year, uint256 month) = getDateTimeSymbol();
        console.log("Month:", ownedMonthData[owner][year * 100 + month]);
        return ownedMonthData[owner][year * 100 + month];
    }
    function getCurrentYearNFTID(address owner) public returns (uint256) {
        (uint256 year, uint256 month) = getDateTimeSymbol();
        console.log("year:", ownedMonthData[owner][year * 100 + month]);
        return ownedYearData[owner][year];
    }
    function getCurrentBonusNFTID(address owner) public returns (uint256) {
        (uint256 year, uint256 month) = getDateTimeSymbol();
        console.log("bonus:", ownedBonusData[owner][year * 100 + month]);
        return ownedBonusData[owner][year];
    }
    
    
    function changeDev(address _newDev) public onlyDev {
        dev  = _newDev;
    }
    function changeOwner(address _newOnwer) public onlyDev {
        owner  = _newOnwer;
    }
    function changeCo2Owner(address _newOnwer) public onlyDev {
        c02Owner  = _newOnwer;
    }

    function changeCarvonTokenAddress(address _carvonToken) public onlyDev {CARBOM = _carvonToken;}
    function changeReferFee(uint256 _referFee) public onlyDev {
        referFee = _referFee;
        emit CertificationReferFeeChanged(referFee);
    }
    function changeOffsetFee(uint256 _offsetFee) public onlyDev {
        offsetFee = _offsetFee;
    }
    function changeCarbonPercent(uint256 _carbonPercent) public onlyDev {
        carvonFeeOnOffset = _carbonPercent;
    }

    function changeMonthNFTLimitPrice(uint256 _price) public onlyDev {limitMonthNFTPrice = _price;}
    function changeBonusNFTLimitPrice(uint256 _price) public onlyDev {limitBonusNFTPrice = _price;}

    modifier onlyDev() { require(msg.sender == dev, "CyberBoxCertNFT: wrong developer");_;}

    /**
     * @dev List token for sale
     * @param tokenId erc721 token Id
     * @param value min price to sell the token
     */
    function ListToken(
    // function listToken(
        uint256 tokenId,
        uint256 value
    ) external  {
        (
        address fromAddress, 
        uint256 minValue
        ) = listToken(msg.sender, tokenId, value);
        emit CertificationTokenListed(
            linkedNFTAddress,
            tokenId,
            fromAddress,
            minValue
        );
    }
    /**
     * @dev See {INFTKEYMarketPlaceV1-delistToken}.
     * msg.sender must be the seller of the listing record
     */
    function delistToken(
        uint256 tokenId
    ) external {
        delistToken(msg.sender, tokenId);
        emit CertificationTokenDelisted(
            linkedNFTAddress,
            tokenId
        );
    }
    /**
     * @dev See {INFTKEYMarketPlaceV1-cleanAllInvalidListings}.
     */
    function cleanAllInvalidListings() external {
        (uint256[] memory idList) = certCleanAllInvalidListings();
        for (uint256 i = 0; i < idList.length; i++) {
            uint256 contract_id = idList[i];
            emit CertificationCleanList(
                linkedNFTAddress,
                contract_id
            );
        }
        deleteTempTokenIdStorage();
    }

    function buyToken(
        uint256 tokenId,
        uint256 value
    ) external payable{
        (
            address sellerAddress, 
            address devAddress,
            address createrAddress,
            address producerAddress
        ) = buyTokenPrepare(msg.sender, tokenId, value);
        uint256 payment_value = msg.value;
        address nftAddress = linkedNFTAddress;
        uint256 sellerFee = calculateSellerFee(payment_value);
        uint256 devFee = calculateDevFee(payment_value);
        uint256 createrFee = calculateCreaterFee(payment_value);
        uint256 producerFee = calculateProducerFee(payment_value);
        transferCelo(msg.sender, sellerAddress, sellerFee);
        emit CertificationPayment(msg.sender, sellerAddress, tokenId, nftAddress, 0, sellerFee);
        transferCelo(msg.sender, devAddress, devFee);
        emit CertificationPayment(msg.sender, devAddress, tokenId, nftAddress, 1, devFee);
        if(createrAddress != address(0) && createrFee > 0){
            transferCelo(msg.sender, createrAddress, createrFee);
            emit CertificationPayment(msg.sender, createrAddress, tokenId, nftAddress, 2, createrFee);
        }
        if(producerAddress != address(0) && producerFee > 0){
            transferCelo(msg.sender, producerAddress, producerFee);
            emit CertificationPayment(msg.sender, producerAddress, tokenId, nftAddress, 3, producerFee);
        }
        buyTokenComplete(msg.sender, tokenId);
        transferNFTOwnedData(sellerAddress, msg.sender, tokenId);
        emit CertificationTokenBought(
            nftAddress,
            tokenId,
            sellerAddress,
            msg.sender,
            payment_value,
            sellerFee,
            devFee + createrFee + producerFee
        );
    }

    function transfer(
        address to,
        uint256 tokenId
    )external {
        transfer(msg.sender, to, tokenId);
        transferNFTOwnedData(msg.sender, to, tokenId);
        emit CertificationTokenTransfered(
            linkedNFTAddress,
            tokenId,
            msg.sender,
            to,
            0
        );
    }

    function changePrice(address _nftAddress, uint256 tokenId, uint256 newPrice) external {
        certChangePrice(msg.sender, tokenId, newPrice);
        emit CertificationTokenPriceChanged(
            _nftAddress,
            tokenId,
            newPrice
        );
    }


    function transferCelo(address sender, address receiver, uint256 value)  private{
        require(sender != address(0), "transfer address must not 0x0");
        require(receiver != address(0), "transfer address must not 0x0");
        require(value > 0, "transfer amount must large than 0");
        if(sender == address(this)){
            payable(receiver).transfer(value);
        }else{
            Address.sendValue(payable(receiver), value);
        }
    }
}

// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.3;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC777} from "@openzeppelin/contracts/token/ERC777/ERC777.sol";
import "@openzeppelin/contracts/utils/Address.sol";

import "hardhat/console.sol";

import "./DateTimeManager.sol";
import "./CyberBoxCertNFT.sol";
import "./CyberBoxCertInterface.sol";
import "./CyberBoxCertResource.sol";
import "./Uniswap/uniswpv2.sol";

import "./MarketPlace/CertificationMarketPlace.sol";

contract CyberBoxCertMinter is DateTimeManager, CyberBoxCertInterface, CyberBoxCertResource, CertificationMarketPlace {
    using Address for address;

    struct NFTMAP  {
        uint256 tokenType;
        uint256 year;
        uint256 month;
    }

    address public dev;
    address public owner;
    address public c02Owner;
    uint256 public offsetFee;
    uint256 public carvonFeeOnOffset;

    address public linkedNFTAddress;

    address private constant UNISWAP_V2_ROUTER = 0xE3D8bd6Aed4F159bc8000a9cD47CffDb95F96121;
    address private constant WETH = 0x471EcE3750Da237f93B8E339c536989b8978a438;
    address public CARBOM = 0x32A9FE697a32135BFd313a6Ac28792DaE4D9979d;

    uint256 public limitMonthNFTPrice;
    uint256 public limitBonusNFTPrice;
    
    //////// owner address => year_month_key => token id
    mapping (address => mapping(uint256 => uint256)) public ownedMonthData;
    mapping (address => mapping(uint256 => uint256)) public ownedYearData;
    mapping (address => mapping(uint256 => uint256)) public ownedBonusData;

    mapping (uint256 => NFTMAP) private _nftDateMap;
    

    uint256 private TOKEN_TYPE_MONTH = 0;
    uint256 private TOKEN_TYPE_YEAR = 1;
    uint256 private TOKEN_TYPE_BONUS = 2;

    constructor(
        address _nft,
        address _dev,
        address _owner,
        address _carvon
    ) public {
        linkedNFTAddress = _nft;
        initializeWithERC721(_nft, _owner);
        dev = _dev;
        owner = _owner;
        c02Owner = _carvon;
        offsetFee = 400;
        carvonFeeOnOffset = 1000;

        limitMonthNFTPrice = 15e18;
        limitBonusNFTPrice = 15e18;


        uint256 producerFee = (offsetFee * carvonFeeOnOffset) / 1000;
        uint256 devFee = (offsetFee * (1000 - carvonFeeOnOffset)) / 1000;
        uint256 createrFee = 1000 - producerFee - devFee;
        emit CertificationTokenCreaterChanged(owner);
        emit CertificationTokenProducerChanged(c02Owner);
        emit CertificationFeeChanged(createrFee, producerFee);
        emit CertificationDevFeeChanged(dev, devFee);
    }

    function uniwapCarbon(address _to, uint256 _amountIn) public returns (uint256[] memory amounts){
        
        IERC20(WETH).approve(UNISWAP_V2_ROUTER, _amountIn);
        address[] memory path = new address[](2);
        path[0] = WETH;
        path[1] = CARBOM;
        return IUniswapV2Router(UNISWAP_V2_ROUTER).swapExactTokensForTokens(_amountIn, 0, path, _to, block.timestamp);
    }

    function offset(uint256 amount) private returns(uint256 sf, uint256 df, uint256 co2) {
        uint256 totalFee = (amount * offsetFee) / 1000;
        uint256 c02Fee = (totalFee * carvonFeeOnOffset) / 1000;
        uint256 devFee = totalFee - c02Fee;
        uint256 sellerFee = amount - totalFee;

        payable(owner).transfer(sellerFee);
        payable(dev).transfer(devFee);

        uint256[] memory amounts = uniwapCarbon(c02Owner, c02Fee);
        uint256 co2Value = amounts[amounts.length - 1];
    
        return (sellerFee, devFee, co2Value);
    }

    function mintMonthNFT() external payable {
        (uint256 year, uint256 month) = getDateTimeSymbol();
        uint256 current_nft_id = getCurrentMonthNFTID(msg.sender);
        require(current_nft_id < 1, "This user already mint nft for this month.");
        require(msg.value >= limitMonthNFTPrice, "This user must pay for mint nft.");

        uint256 totalValue = msg.value;
        (uint256 sellerFee, uint256 devFee, uint256 co2Value) = offset(totalValue);
        
        string memory token_uri = getMonthTokenURI(year, month);
        uint256 nft_id = CyberBoxCertNFT(linkedNFTAddress).mintNFT(msg.sender, token_uri);
        ownedMonthData[msg.sender][year*100 + month] = nft_id;
        _nftDateMap[nft_id] = NFTMAP(TOKEN_TYPE_MONTH, year, month);
        emit CertificationNFTMinted(msg.sender, TOKEN_TYPE_MONTH, nft_id, year, month, totalValue, devFee, co2Value);
    }


    function adminMintMonthlyNFT(address user, uint256 month) public onlyDev {
        uint256 year = 2022;
        require(month < 7, "You can't mint over June.");
        uint256 current_nft_id = getMonthNFTID(user, year, month);
        if(current_nft_id < 1) {
            string memory token_uri = getMonthTokenURI(year, month);
            uint256 nft_id = CyberBoxCertNFT(linkedNFTAddress).mintNFT(user, token_uri);
            ownedMonthData[user][year*100 + month] = nft_id;
            _nftDateMap[nft_id] = NFTMAP(TOKEN_TYPE_MONTH, year, month);
            emit CertificationNFTMinted(user, TOKEN_TYPE_MONTH, nft_id, year, month, 0, 0, 0);
        }
    }
    function adminMintAllNFTs(address user)  public onlyDev {
        uint256 year = 2022;
        for(uint256 month = 1; month<=6; month++){
            uint256 current_nft_id = getMonthNFTID(user, year, month);
            if(current_nft_id < 1) {
                string memory token_uri = getMonthTokenURI(year, month);
                uint256 nft_id = CyberBoxCertNFT(linkedNFTAddress).mintNFT(user, token_uri);
                ownedMonthData[user][year*100 + month] = nft_id;
                _nftDateMap[nft_id] = NFTMAP(TOKEN_TYPE_MONTH, year, month);
                emit CertificationNFTMinted(user, TOKEN_TYPE_MONTH, nft_id, year, month, 0, 0, 0);
            }
        }
    }

    function mintMonthNFTFor(address receipt, uint256 year, uint256 month) private {
        uint256 current_nft_id = getMonthNFTID(receipt, year, month);
        if(current_nft_id < 1) {
            string memory token_uri = getMonthTokenURI(year, month);
            uint256 nft_id = CyberBoxCertNFT(linkedNFTAddress).mintNFT(msg.sender, token_uri);
            ownedMonthData[msg.sender][year*100 + month] = nft_id;
            _nftDateMap[nft_id] = NFTMAP(TOKEN_TYPE_MONTH, year, month);
            emit CertificationNFTMinted(msg.sender, TOKEN_TYPE_MONTH, nft_id, year, month, 0, 0, 0);
        }
    }

    function mintYearNFT()  external onlyDev payable  {
        (uint256 year, uint256 month) = getDateTimeSymbol();
        uint256 current_nft_id = getCurrentYearNFTID(msg.sender);
        require(current_nft_id < 1, "This user already mint nft for this month.");
        require(msg.value >= limitMonthNFTPrice, "This user must pay for mint nft.");
        
        uint256 totalValue = msg.value;
        
        (uint256 sellerFee, uint256 devFee, uint256 co2Value) = offset(totalValue);

        string memory token_uri = getYearTokenURI(year);
        uint256 nft_id = CyberBoxCertNFT(linkedNFTAddress).mintNFT(msg.sender, token_uri);
        ownedYearData[msg.sender][year] = nft_id;
        _nftDateMap[nft_id] = NFTMAP(TOKEN_TYPE_YEAR, year, 0);
        emit CertificationNFTMinted(msg.sender, TOKEN_TYPE_YEAR, nft_id, year, 0, totalValue, devFee, co2Value);
    }

    function mintBonusNFT() external onlyDev payable {
        (uint256 year, uint256 month) = getDateTimeSymbol();
        uint256 current_nft_id = getCurrentBonusNFTID(msg.sender);
        require(current_nft_id < 1, "This user already mint nft for this month.");
        require(msg.value >= limitBonusNFTPrice, "This user must pay for mint nft.");

        uint256 totalValue = msg.value;
        (uint256 sellerFee, uint256 devFee, uint256 co2Value) = offset(totalValue);

        string memory token_uri = getBonusTokenURI(year);
        uint256 nft_id = CyberBoxCertNFT(linkedNFTAddress).mintNFT(msg.sender, token_uri);
        ownedBonusData[msg.sender][year] = nft_id;
        _nftDateMap[nft_id] = NFTMAP(TOKEN_TYPE_BONUS, year, 0);
        emit CertificationNFTMinted(msg.sender, TOKEN_TYPE_BONUS, nft_id, year, 0, totalValue, devFee, co2Value);
    }

    function exchangeBonusNFTToMonth(uint256 year) public {
        uint256 current_nft_id = getBonusNFTID(msg.sender, year);
        require(current_nft_id > 0, "This user don't have bonus NFT.");
        CyberBoxCertNFT(linkedNFTAddress).burn(msg.sender, current_nft_id);
        ownedBonusData[msg.sender][year] = 0;
        emit CertificationNFTBurned(msg.sender, TOKEN_TYPE_BONUS, current_nft_id, year, 0);
        for(uint256 month = 1; month<=12; month++){
            mintMonthNFTFor(msg.sender, year, month);
        }
    }

    function exchangeMonthNFTToBonus(uint256 year) public {
        uint256 current_bonus_id = getCurrentBonusNFTID(msg.sender);
        require(current_bonus_id < 1, "This user already mint nft for this month.");
        for(uint256 month = 1; month<=12; month++){
            uint256 current_nft_id = getMonthNFTID(msg.sender, year, month);
            require(current_nft_id > 0, "This user don't have all month NFT.");
            CyberBoxCertNFT(linkedNFTAddress).burn(msg.sender, current_nft_id);
            ownedMonthData[msg.sender][year*100 + month] = 0;
            emit CertificationNFTBurned(msg.sender, TOKEN_TYPE_MONTH, current_nft_id, year, 0);
        }
        string memory token_uri = getBonusTokenURI(year);
        uint256 nft_id = CyberBoxCertNFT(linkedNFTAddress).mintNFT(msg.sender, token_uri);
        ownedBonusData[msg.sender][year] = nft_id;
        emit CertificationNFTMinted(msg.sender, TOKEN_TYPE_BONUS, nft_id, year, 0, 0, 0, 0);
    }

    function transferNFTOwnedData(address from, address to, uint256 tokenId) private {
        NFTMAP memory mapData = _nftDateMap[tokenId];
        uint256 tokenType = mapData.tokenType;
        uint256 year = mapData.year;
        uint256 month = mapData.month;
        if (tokenType == TOKEN_TYPE_MONTH){
            ownedMonthData[from][year*100 + month] = 0;
            ownedMonthData[to][year*100 + month] = tokenId;
        }
        if (tokenType == TOKEN_TYPE_YEAR) {
            ownedYearData[from][year] = 0;
            ownedYearData[to][year] = tokenId;
        }
        if (tokenType == TOKEN_TYPE_BONUS) {
            ownedBonusData[from][year] = 0;
            ownedBonusData[to][year] = tokenId;
        }
    }


    function getMonthNFTID(address owner, uint256 year, uint256 month) public returns (uint256){
        return ownedMonthData[owner][year * 100 + month];
    }

    function getYearNFTID(address owner, uint256 year) public returns (uint256) {
        return ownedYearData[owner][year];
    }

    function getBonusNFTID(address owner, uint256 year) public returns (uint256) {
        return ownedBonusData[owner][year];
    }

    
    function getCurrentMonthNFTID(address owner) public returns (uint256) {
        (uint256 year, uint256 month) = getDateTimeSymbol();
        return ownedMonthData[owner][year * 100 + month];
    }
    function getCurrentYearNFTID(address owner) public returns (uint256) {
        (uint256 year, uint256 month) = getDateTimeSymbol();
        return ownedYearData[owner][year];
    }
    function getCurrentBonusNFTID(address owner) public returns (uint256) {
        (uint256 year, uint256 month) = getDateTimeSymbol();
        return ownedBonusData[owner][year];
    }
    
    
    function changeDev(address _newDev) public onlyDev {
        dev  = _newDev;
        uint256 producerFee = (offsetFee * carvonFeeOnOffset) / 1000;
        uint256 devFee = (offsetFee * (1000 - carvonFeeOnOffset)) / 1000;
        uint256 createrFee = 1000 - producerFee - devFee;
        emit CertificationTokenCreaterChanged(owner);
        emit CertificationTokenProducerChanged(c02Owner);
        emit CertificationFeeChanged(createrFee, producerFee);
        emit CertificationDevFeeChanged(dev, devFee);
    }
    function changeOwner(address _newOnwer) public onlyDev {
        owner  = _newOnwer;
        uint256 producerFee = (offsetFee * carvonFeeOnOffset) / 1000;
        uint256 devFee = (offsetFee * (1000 - carvonFeeOnOffset)) / 1000;
        uint256 createrFee = 1000 - producerFee - devFee;
        emit CertificationTokenCreaterChanged(owner);
        emit CertificationTokenProducerChanged(c02Owner);
        emit CertificationFeeChanged(createrFee, producerFee);
        emit CertificationDevFeeChanged(dev, devFee);
    }
    function changeCo2Owner(address _newOnwer) public onlyDev {
        c02Owner  = _newOnwer;
        uint256 producerFee = (offsetFee * carvonFeeOnOffset) / 1000;
        uint256 devFee = (offsetFee * (1000 - carvonFeeOnOffset)) / 1000;
        uint256 createrFee = 1000 - producerFee - devFee;
        emit CertificationTokenCreaterChanged(owner);
        emit CertificationTokenProducerChanged(c02Owner);
        emit CertificationFeeChanged(createrFee, producerFee);
        emit CertificationDevFeeChanged(dev, devFee);
    }

    function changeCarvonTokenAddress(address _carvonToken) public onlyDev {CARBOM = _carvonToken;}
    function changeOffsetFee(uint256 _offsetFee) public onlyDev {
        offsetFee = _offsetFee;
        uint256 producerFee = (offsetFee * carvonFeeOnOffset) / 1000;
        uint256 devFee = (offsetFee * (1000 - carvonFeeOnOffset)) / 1000;
        uint256 createrFee = 1000 - producerFee - devFee;
        emit CertificationTokenCreaterChanged(owner);
        emit CertificationTokenProducerChanged(c02Owner);
        emit CertificationFeeChanged(createrFee, producerFee);
        emit CertificationDevFeeChanged(dev, devFee);    
    }
    function changeCarbonPercent(uint256 _carbonPercent) public onlyDev {
        carvonFeeOnOffset = _carbonPercent;
        uint256 producerFee = (offsetFee * carvonFeeOnOffset) / 1000;
        uint256 devFee = (offsetFee * (1000 - carvonFeeOnOffset)) / 1000;
        uint256 createrFee = 1000 - producerFee - devFee;
        emit CertificationTokenCreaterChanged(owner);
        emit CertificationTokenProducerChanged(c02Owner);
        emit CertificationFeeChanged(createrFee, producerFee);
        emit CertificationDevFeeChanged(dev, devFee);
    }

    function changeMonthNFTLimitPrice(uint256 _price) public onlyDev {limitMonthNFTPrice = _price;}
    function changeBonusNFTLimitPrice(uint256 _price) public onlyDev {limitBonusNFTPrice = _price;}

    modifier onlyDev() { require(msg.sender == dev, "CyberBoxCertNFT: wrong developer");_;}

    /**
     * @dev List token for sale
     * @param tokenId erc721 token Id
     * @param value min price to sell the token
     */
    function ListToken(
    // function listToken(
        uint256 tokenId,
        uint256 value
    ) external  {
        (
        address fromAddress, 
        uint256 minValue
        ) = listToken(msg.sender, tokenId, value);
        emit CertificationTokenListed(
            linkedNFTAddress,
            tokenId,
            fromAddress,
            minValue
        );
    }
    /**
     * @dev See {INFTKEYMarketPlaceV1-delistToken}.
     * msg.sender must be the seller of the listing record
     */
    function delistToken(
        uint256 tokenId
    ) external {
        delistToken(msg.sender, tokenId);
        emit CertificationTokenDelisted(
            linkedNFTAddress,
            tokenId
        );
    }
    /**
     * @dev See {INFTKEYMarketPlaceV1-cleanAllInvalidListings}.
     */
    function cleanAllInvalidListings() external {
        (uint256[] memory idList) = certCleanAllInvalidListings();
        for (uint256 i = 0; i < idList.length; i++) {
            uint256 contract_id = idList[i];
            emit CertificationCleanList(
                linkedNFTAddress,
                contract_id
            );
        }
        deleteTempTokenIdStorage();
    }

    function buyToken(
        uint256 tokenId,
        uint256 value
    ) external payable{
        (
            address sellerAddress, 
            address devAddress,
            address createrAddress,
            address producerAddress
        ) = buyTokenPrepare(msg.sender, tokenId, value);
        uint256 payment_value = msg.value;
        address nftAddress = linkedNFTAddress;
        uint256 sellerFee = calculateSellerFee(payment_value);
        uint256 devFee = calculateDevFee(payment_value);
        uint256 createrFee = calculateCreaterFee(payment_value);
        uint256 producerFee = calculateProducerFee(payment_value);
        transferCelo(msg.sender, sellerAddress, sellerFee);
        emit CertificationPayment(msg.sender, sellerAddress, tokenId, nftAddress, 0, sellerFee);
        transferCelo(msg.sender, devAddress, devFee);
        emit CertificationPayment(msg.sender, devAddress, tokenId, nftAddress, 1, devFee);
        if(createrAddress != address(0) && createrFee > 0){
            transferCelo(msg.sender, createrAddress, createrFee);
            emit CertificationPayment(msg.sender, createrAddress, tokenId, nftAddress, 2, createrFee);
        }
        if(producerAddress != address(0) && producerFee > 0){
            transferCelo(msg.sender, producerAddress, producerFee);
            emit CertificationPayment(msg.sender, producerAddress, tokenId, nftAddress, 3, producerFee);
        }
        buyTokenComplete(msg.sender, tokenId);
        transferNFTOwnedData(sellerAddress, msg.sender, tokenId);
        emit CertificationTokenBought(
            nftAddress,
            tokenId,
            sellerAddress,
            msg.sender,
            payment_value,
            sellerFee,
            devFee + createrFee + producerFee
        );
    }

    function transfer(
        address to,
        uint256 tokenId
    )external {
        transfer(msg.sender, to, tokenId);
        transferNFTOwnedData(msg.sender, to, tokenId);
        emit CertificationTokenTransfered(
            linkedNFTAddress,
            tokenId,
            msg.sender,
            to,
            0
        );
    }

    function changePrice(address _nftAddress, uint256 tokenId, uint256 newPrice) external {
        certChangePrice(msg.sender, tokenId, newPrice);
        emit CertificationTokenPriceChanged(
            _nftAddress,
            tokenId,
            newPrice
        );
    }


    function transferCelo(address sender, address receiver, uint256 value)  private{
        require(sender != address(0), "transfer address must not 0x0");
        require(receiver != address(0), "transfer address must not 0x0");
        require(value > 0, "transfer amount must large than 0");
        if(sender == address(this)){
            payable(receiver).transfer(value);
        }else{
            Address.sendValue(payable(receiver), value);
        }
    }
}

// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity 0.8.3;
pragma experimental ABIEncoderV2;

interface CyberBoxCertInterface {
    event CertificationNFTMinted(
        address owner,
        uint256 tokenType,
        uint256 tokenId,
        uint256 year,
        uint256 month,
        uint256 price,
        uint256 devFee,
        uint256 c02
    );

    event CertificationNFTBurned(
        address owner,
        uint256 tokenType,
        uint256 tokenId,
        uint256 year,
        uint256 month
    );

    event CertificationNFTExchanged(
        address owner,
        uint256 fromType,
        uint256 toType,
        uint256 year
    );

    event CertificationTokenListed(
        address nftAddress,
        uint256 indexed tokenId, 
        address indexed fromAddress, 
        uint256 minValue
    );
    event CertificationTokenDelisted(
        address nftAddress,
        uint256 indexed tokenId
    );
    event CertificationCleanList(
        address nftAddress,
        uint256 tokenId
    );

    event CertificationPayment(
        address fromAddress,
        address toAddress,
        uint256 tokenId,
        address nftAddress,
        uint256 paymentType,
        uint256 amount
    );
    event CertificationTokenBought(
        address nftAddress,
        uint256 tokenId,
        address fromAddress, 
        address toAddress,
        uint256 total,
        uint256 value,
        uint256 fees
    );
    event CertificationTokenTransfered(
        address nftAddress,
        uint256 indexed tokenId,
        address indexed from,
        address indexed to,
        uint256 total
    );
    event CertificationTokenPriceChanged(
        address nftAddress,
        uint256 indexed tokenId,
        uint256 price
    );

    event CertificationFeeChanged(
        uint256 createrFee,
        uint256 producerFee
    );
    event CertificationDevFeeChanged(
        address marketPlaceFeeAddress,
        uint256 marketFee
    );
    event CertificationTokenCreaterChanged(
        address tokenCreaterAddress
    );
    event CertificationTokenProducerChanged(
        address tokenCreaterAddress
    );
}

// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v4.7.0) (utils/Strings.sol)

pragma solidity ^0.8.0;

/**
 * @dev String operations.
 */
library StringsUpgradeable {
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
library CountersUpgradeable {
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
// OpenZeppelin Contracts (last updated v4.7.0) (utils/Address.sol)

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
                /// @solidity memory-safe-assembly
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
// OpenZeppelin Contracts (last updated v4.7.0) (proxy/utils/Initializable.sol)

pragma solidity ^0.8.2;

import "../../utils/AddressUpgradeable.sol";

/**
 * @dev This is a base contract to aid in writing upgradeable contracts, or any kind of contract that will be deployed
 * behind a proxy. Since proxied contracts do not make use of a constructor, it's common to move constructor logic to an
 * external initializer function, usually called `initialize`. It then becomes necessary to protect this initializer
 * function so it can only be called once. The {initializer} modifier provided by this contract will have this effect.
 *
 * The initialization functions use a version number. Once a version number is used, it is consumed and cannot be
 * reused. This mechanism prevents re-execution of each "step" but allows the creation of new initialization steps in
 * case an upgrade adds a module that needs to be initialized.
 *
 * For example:
 *
 * [.hljs-theme-light.nopadding]
 * ```
 * contract MyToken is ERC20Upgradeable {
 *     function initialize() initializer public {
 *         __ERC20_init("MyToken", "MTK");
 *     }
 * }
 * contract MyTokenV2 is MyToken, ERC20PermitUpgradeable {
 *     function initializeV2() reinitializer(2) public {
 *         __ERC20Permit_init("MyToken");
 *     }
 * }
 * ```
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
 * contract, which may impact the proxy. To prevent the implementation contract from being used, you should invoke
 * the {_disableInitializers} function in the constructor to automatically lock it when it is deployed:
 *
 * [.hljs-theme-light.nopadding]
 * ```
 * /// @custom:oz-upgrades-unsafe-allow constructor
 * constructor() {
 *     _disableInitializers();
 * }
 * ```
 * ====
 */
abstract contract Initializable {
    /**
     * @dev Indicates that the contract has been initialized.
     * @custom:oz-retyped-from bool
     */
    uint8 private _initialized;

    /**
     * @dev Indicates that the contract is in the process of being initialized.
     */
    bool private _initializing;

    /**
     * @dev Triggered when the contract has been initialized or reinitialized.
     */
    event Initialized(uint8 version);

    /**
     * @dev A modifier that defines a protected initializer function that can be invoked at most once. In its scope,
     * `onlyInitializing` functions can be used to initialize parent contracts. Equivalent to `reinitializer(1)`.
     */
    modifier initializer() {
        bool isTopLevelCall = !_initializing;
        require(
            (isTopLevelCall && _initialized < 1) || (!AddressUpgradeable.isContract(address(this)) && _initialized == 1),
            "Initializable: contract is already initialized"
        );
        _initialized = 1;
        if (isTopLevelCall) {
            _initializing = true;
        }
        _;
        if (isTopLevelCall) {
            _initializing = false;
            emit Initialized(1);
        }
    }

    /**
     * @dev A modifier that defines a protected reinitializer function that can be invoked at most once, and only if the
     * contract hasn't been initialized to a greater version before. In its scope, `onlyInitializing` functions can be
     * used to initialize parent contracts.
     *
     * `initializer` is equivalent to `reinitializer(1)`, so a reinitializer may be used after the original
     * initialization step. This is essential to configure modules that are added through upgrades and that require
     * initialization.
     *
     * Note that versions can jump in increments greater than 1; this implies that if multiple reinitializers coexist in
     * a contract, executing them in the right order is up to the developer or operator.
     */
    modifier reinitializer(uint8 version) {
        require(!_initializing && _initialized < version, "Initializable: contract is already initialized");
        _initialized = version;
        _initializing = true;
        _;
        _initializing = false;
        emit Initialized(version);
    }

    /**
     * @dev Modifier to protect an initialization function so that it can only be invoked by functions with the
     * {initializer} and {reinitializer} modifiers, directly or indirectly.
     */
    modifier onlyInitializing() {
        require(_initializing, "Initializable: contract is not initializing");
        _;
    }

    /**
     * @dev Locks the contract, preventing any future reinitialization. This cannot be part of an initializer call.
     * Calling this in the constructor of a contract will prevent that contract from being initialized or reinitialized
     * to any version. It is recommended to use this to lock implementation contracts that are designed to be called
     * through proxies.
     */
    function _disableInitializers() internal virtual {
        require(!_initializing, "Initializable: contract is initializing");
        if (_initialized < type(uint8).max) {
            _initialized = type(uint8).max;
            emit Initialized(type(uint8).max);
        }
    }
}


// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v4.7.0) (access/Ownable.sol)

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

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[49] private __gap;
}


// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v4.7.0) (utils/structs/EnumerableSet.sol)

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
 *
 * [WARNING]
 * ====
 *  Trying to delete such a structure from storage will likely result in data corruption, rendering the structure unusable.
 *  See https://github.com/ethereum/solidity/pull/11843[ethereum/solidity#11843] for more info.
 *
 *  In order to clean an EnumerableSet, you can either remove all elements one by one or create a fresh instance using an array of EnumerableSet.
 * ====
 */
library EnumerableSet {
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
                bytes32 lastValue = set._values[lastIndex];

                // Move the last value to the index where the value to delete is
                set._values[toDeleteIndex] = lastValue;
                // Update the index for the moved value
                set._indexes[lastValue] = valueIndex; // Replace lastValue's index to valueIndex
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

        /// @solidity memory-safe-assembly
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

        /// @solidity memory-safe-assembly
        assembly {
            result := store
        }

        return result;
    }
}


// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts v4.4.1 (token/ERC777/IERC777Sender.sol)

pragma solidity ^0.8.0;

/**
 * @dev Interface of the ERC777TokensSender standard as defined in the EIP.
 *
 * {IERC777} Token holders can be notified of operations performed on their
 * tokens by having a contract implement this interface (contract holders can be
 * their own implementer) and registering it on the
 * https://eips.ethereum.org/EIPS/eip-1820[ERC1820 global registry].
 *
 * See {IERC1820Registry} and {ERC1820Implementer}.
 */
interface IERC777Sender {
    /**
     * @dev Called by an {IERC777} token contract whenever a registered holder's
     * (`from`) tokens are about to be moved or destroyed. The type of operation
     * is conveyed by `to` being the zero address or not.
     *
     * This call occurs _before_ the token contract's state is updated, so
     * {IERC777-balanceOf}, etc., can be used to query the pre-operation state.
     *
     * This function may revert to prevent the operation from being executed.
     */
    function tokensToSend(
        address operator,
        address from,
        address to,
        uint256 amount,
        bytes calldata userData,
        bytes calldata operatorData
    ) external;
}


// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v4.6.0) (utils/math/SafeMath.sol)

pragma solidity ^0.8.0;

// CAUTION
// This version of SafeMath should only be used with Solidity 0.8 or later,
// because it relies on the compiler's built in overflow checks.

/**
 * @dev Wrappers over Solidity's arithmetic operations.
 *
 * NOTE: `SafeMath` is generally not needed starting with Solidity 0.8, since the compiler
 * now has built in overflow checking.
 */
library SafeMath {
    /**
     * @dev Returns the addition of two unsigned integers, with an overflow flag.
     *
     * _Available since v3.4._
     */
    function tryAdd(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        unchecked {
            uint256 c = a + b;
            if (c < a) return (false, 0);
            return (true, c);
        }
    }

    /**
     * @dev Returns the subtraction of two unsigned integers, with an overflow flag.
     *
     * _Available since v3.4._
     */
    function trySub(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        unchecked {
            if (b > a) return (false, 0);
            return (true, a - b);
        }
    }

    /**
     * @dev Returns the multiplication of two unsigned integers, with an overflow flag.
     *
     * _Available since v3.4._
     */
    function tryMul(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        unchecked {
            // Gas optimization: this is cheaper than requiring 'a' not being zero, but the
            // benefit is lost if 'b' is also tested.
            // See: https://github.com/OpenZeppelin/openzeppelin-contracts/pull/522
            if (a == 0) return (true, 0);
            uint256 c = a * b;
            if (c / a != b) return (false, 0);
            return (true, c);
        }
    }

    /**
     * @dev Returns the division of two unsigned integers, with a division by zero flag.
     *
     * _Available since v3.4._
     */
    function tryDiv(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        unchecked {
            if (b == 0) return (false, 0);
            return (true, a / b);
        }
    }

    /**
     * @dev Returns the remainder of dividing two unsigned integers, with a division by zero flag.
     *
     * _Available since v3.4._
     */
    function tryMod(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        unchecked {
            if (b == 0) return (false, 0);
            return (true, a % b);
        }
    }

    /**
     * @dev Returns the addition of two unsigned integers, reverting on
     * overflow.
     *
     * Counterpart to Solidity's `+` operator.
     *
     * Requirements:
     *
     * - Addition cannot overflow.
     */
    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        return a + b;
    }

    /**
     * @dev Returns the subtraction of two unsigned integers, reverting on
     * overflow (when the result is negative).
     *
     * Counterpart to Solidity's `-` operator.
     *
     * Requirements:
     *
     * - Subtraction cannot overflow.
     */
    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        return a - b;
    }

    /**
     * @dev Returns the multiplication of two unsigned integers, reverting on
     * overflow.
     *
     * Counterpart to Solidity's `*` operator.
     *
     * Requirements:
     *
     * - Multiplication cannot overflow.
     */
    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        return a * b;
    }

    /**
     * @dev Returns the integer division of two unsigned integers, reverting on
     * division by zero. The result is rounded towards zero.
     *
     * Counterpart to Solidity's `/` operator.
     *
     * Requirements:
     *
     * - The divisor cannot be zero.
     */
    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        return a / b;
    }

    /**
     * @dev Returns the remainder of dividing two unsigned integers. (unsigned integer modulo),
     * reverting when dividing by zero.
     *
     * Counterpart to Solidity's `%` operator. This function uses a `revert`
     * opcode (which leaves remaining gas untouched) while Solidity uses an
     * invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     *
     * - The divisor cannot be zero.
     */
    function mod(uint256 a, uint256 b) internal pure returns (uint256) {
        return a % b;
    }

    /**
     * @dev Returns the subtraction of two unsigned integers, reverting with custom message on
     * overflow (when the result is negative).
     *
     * CAUTION: This function is deprecated because it requires allocating memory for the error
     * message unnecessarily. For custom revert reasons use {trySub}.
     *
     * Counterpart to Solidity's `-` operator.
     *
     * Requirements:
     *
     * - Subtraction cannot overflow.
     */
    function sub(
        uint256 a,
        uint256 b,
        string memory errorMessage
    ) internal pure returns (uint256) {
        unchecked {
            require(b <= a, errorMessage);
            return a - b;
        }
    }

    /**
     * @dev Returns the integer division of two unsigned integers, reverting with custom message on
     * division by zero. The result is rounded towards zero.
     *
     * Counterpart to Solidity's `/` operator. Note: this function uses a
     * `revert` opcode (which leaves remaining gas untouched) while Solidity
     * uses an invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     *
     * - The divisor cannot be zero.
     */
    function div(
        uint256 a,
        uint256 b,
        string memory errorMessage
    ) internal pure returns (uint256) {
        unchecked {
            require(b > 0, errorMessage);
            return a / b;
        }
    }

    /**
     * @dev Returns the remainder of dividing two unsigned integers. (unsigned integer modulo),
     * reverting with custom message when dividing by zero.
     *
     * CAUTION: This function is deprecated because it requires allocating memory for the error
     * message unnecessarily. For custom revert reasons use {tryMod}.
     *
     * Counterpart to Solidity's `%` operator. This function uses a `revert`
     * opcode (which leaves remaining gas untouched) while Solidity uses an
     * invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     *
     * - The divisor cannot be zero.
     */
    function mod(
        uint256 a,
        uint256 b,
        string memory errorMessage
    ) internal pure returns (uint256) {
        unchecked {
            require(b > 0, errorMessage);
            return a % b;
        }
    }
}


// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v4.6.0) (utils/introspection/IERC1820Registry.sol)

pragma solidity ^0.8.0;

/**
 * @dev Interface of the global ERC1820 Registry, as defined in the
 * https://eips.ethereum.org/EIPS/eip-1820[EIP]. Accounts may register
 * implementers for interfaces in this registry, as well as query support.
 *
 * Implementers may be shared by multiple accounts, and can also implement more
 * than a single interface for each account. Contracts can implement interfaces
 * for themselves, but externally-owned accounts (EOA) must delegate this to a
 * contract.
 *
 * {IERC165} interfaces can also be queried via the registry.
 *
 * For an in-depth explanation and source code analysis, see the EIP text.
 */
interface IERC1820Registry {
    event InterfaceImplementerSet(address indexed account, bytes32 indexed interfaceHash, address indexed implementer);

    event ManagerChanged(address indexed account, address indexed newManager);

    /**
     * @dev Sets `newManager` as the manager for `account`. A manager of an
     * account is able to set interface implementers for it.
     *
     * By default, each account is its own manager. Passing a value of `0x0` in
     * `newManager` will reset the manager to this initial state.
     *
     * Emits a {ManagerChanged} event.
     *
     * Requirements:
     *
     * - the caller must be the current manager for `account`.
     */
    function setManager(address account, address newManager) external;

    /**
     * @dev Returns the manager for `account`.
     *
     * See {setManager}.
     */
    function getManager(address account) external view returns (address);

    /**
     * @dev Sets the `implementer` contract as ``account``'s implementer for
     * `interfaceHash`.
     *
     * `account` being the zero address is an alias for the caller's address.
     * The zero address can also be used in `implementer` to remove an old one.
     *
     * See {interfaceHash} to learn how these are created.
     *
     * Emits an {InterfaceImplementerSet} event.
     *
     * Requirements:
     *
     * - the caller must be the current manager for `account`.
     * - `interfaceHash` must not be an {IERC165} interface id (i.e. it must not
     * end in 28 zeroes).
     * - `implementer` must implement {IERC1820Implementer} and return true when
     * queried for support, unless `implementer` is the caller. See
     * {IERC1820Implementer-canImplementInterfaceForAddress}.
     */
    function setInterfaceImplementer(
        address account,
        bytes32 _interfaceHash,
        address implementer
    ) external;

    /**
     * @dev Returns the implementer of `interfaceHash` for `account`. If no such
     * implementer is registered, returns the zero address.
     *
     * If `interfaceHash` is an {IERC165} interface id (i.e. it ends with 28
     * zeroes), `account` will be queried for support of it.
     *
     * `account` being the zero address is an alias for the caller's address.
     */
    function getInterfaceImplementer(address account, bytes32 _interfaceHash) external view returns (address);

    /**
     * @dev Returns the interface hash for an `interfaceName`, as defined in the
     * corresponding
     * https://eips.ethereum.org/EIPS/eip-1820#interface-name[section of the EIP].
     */
    function interfaceHash(string calldata interfaceName) external pure returns (bytes32);

    /**
     * @notice Updates the cache with whether the contract implements an ERC165 interface or not.
     * @param account Address of the contract for which to update the cache.
     * @param interfaceId ERC165 interface for which to update the cache.
     */
    function updateERC165Cache(address account, bytes4 interfaceId) external;

    /**
     * @notice Checks whether a contract implements an ERC165 interface or not.
     * If the result is not cached a direct lookup on the contract address is performed.
     * If the result is not cached or the cached value is out-of-date, the cache MUST be updated manually by calling
     * {updateERC165Cache} with the contract address.
     * @param account Address of the contract to check.
     * @param interfaceId ERC165 interface to check.
     * @return True if `account` implements `interfaceId`, false otherwise.
     */
    function implementsERC165Interface(address account, bytes4 interfaceId) external view returns (bool);

    /**
     * @notice Checks whether a contract implements an ERC165 interface or not without using nor updating the cache.
     * @param account Address of the contract to check.
     * @param interfaceId ERC165 interface to check.
     * @return True if `account` implements `interfaceId`, false otherwise.
     */
    function implementsERC165InterfaceNoCache(address account, bytes4 interfaceId) external view returns (bool);
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
// OpenZeppelin Contracts v4.4.1 (token/ERC777/IERC777Recipient.sol)

pragma solidity ^0.8.0;

/**
 * @dev Interface of the ERC777TokensRecipient standard as defined in the EIP.
 *
 * Accounts can be notified of {IERC777} tokens being sent to them by having a
 * contract implement this interface (contract holders can be their own
 * implementer) and registering it on the
 * https://eips.ethereum.org/EIPS/eip-1820[ERC1820 global registry].
 *
 * See {IERC1820Registry} and {ERC1820Implementer}.
 */
interface IERC777Recipient {
    /**
     * @dev Called by an {IERC777} token contract whenever tokens are being
     * moved or created into a registered account (`to`). The type of operation
     * is conveyed by `from` being the zero address or not.
     *
     * This call occurs _after_ the token contract's state is updated, so
     * {IERC777-balanceOf}, etc., can be used to query the post-operation state.
     *
     * This function may revert to prevent the operation from being executed.
     */
    function tokensReceived(
        address operator,
        address from,
        address to,
        uint256 amount,
        bytes calldata userData,
        bytes calldata operatorData
    ) external;
}


// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v4.6.0) (token/ERC777/IERC777.sol)

pragma solidity ^0.8.0;

/**
 * @dev Interface of the ERC777Token standard as defined in the EIP.
 *
 * This contract uses the
 * https://eips.ethereum.org/EIPS/eip-1820[ERC1820 registry standard] to let
 * token holders and recipients react to token movements by using setting implementers
 * for the associated interfaces in said registry. See {IERC1820Registry} and
 * {ERC1820Implementer}.
 */
interface IERC777 {
    /**
     * @dev Emitted when `amount` tokens are created by `operator` and assigned to `to`.
     *
     * Note that some additional user `data` and `operatorData` can be logged in the event.
     */
    event Minted(address indexed operator, address indexed to, uint256 amount, bytes data, bytes operatorData);

    /**
     * @dev Emitted when `operator` destroys `amount` tokens from `account`.
     *
     * Note that some additional user `data` and `operatorData` can be logged in the event.
     */
    event Burned(address indexed operator, address indexed from, uint256 amount, bytes data, bytes operatorData);

    /**
     * @dev Emitted when `operator` is made operator for `tokenHolder`
     */
    event AuthorizedOperator(address indexed operator, address indexed tokenHolder);

    /**
     * @dev Emitted when `operator` is revoked its operator status for `tokenHolder`
     */
    event RevokedOperator(address indexed operator, address indexed tokenHolder);

    /**
     * @dev Returns the name of the token.
     */
    function name() external view returns (string memory);

    /**
     * @dev Returns the symbol of the token, usually a shorter version of the
     * name.
     */
    function symbol() external view returns (string memory);

    /**
     * @dev Returns the smallest part of the token that is not divisible. This
     * means all token operations (creation, movement and destruction) must have
     * amounts that are a multiple of this number.
     *
     * For most token contracts, this value will equal 1.
     */
    function granularity() external view returns (uint256);

    /**
     * @dev Returns the amount of tokens in existence.
     */
    function totalSupply() external view returns (uint256);

    /**
     * @dev Returns the amount of tokens owned by an account (`owner`).
     */
    function balanceOf(address owner) external view returns (uint256);

    /**
     * @dev Moves `amount` tokens from the caller's account to `recipient`.
     *
     * If send or receive hooks are registered for the caller and `recipient`,
     * the corresponding functions will be called with `data` and empty
     * `operatorData`. See {IERC777Sender} and {IERC777Recipient}.
     *
     * Emits a {Sent} event.
     *
     * Requirements
     *
     * - the caller must have at least `amount` tokens.
     * - `recipient` cannot be the zero address.
     * - if `recipient` is a contract, it must implement the {IERC777Recipient}
     * interface.
     */
    function send(
        address recipient,
        uint256 amount,
        bytes calldata data
    ) external;

    /**
     * @dev Destroys `amount` tokens from the caller's account, reducing the
     * total supply.
     *
     * If a send hook is registered for the caller, the corresponding function
     * will be called with `data` and empty `operatorData`. See {IERC777Sender}.
     *
     * Emits a {Burned} event.
     *
     * Requirements
     *
     * - the caller must have at least `amount` tokens.
     */
    function burn(uint256 amount, bytes calldata data) external;

    /**
     * @dev Returns true if an account is an operator of `tokenHolder`.
     * Operators can send and burn tokens on behalf of their owners. All
     * accounts are their own operator.
     *
     * See {operatorSend} and {operatorBurn}.
     */
    function isOperatorFor(address operator, address tokenHolder) external view returns (bool);

    /**
     * @dev Make an account an operator of the caller.
     *
     * See {isOperatorFor}.
     *
     * Emits an {AuthorizedOperator} event.
     *
     * Requirements
     *
     * - `operator` cannot be calling address.
     */
    function authorizeOperator(address operator) external;

    /**
     * @dev Revoke an account's operator status for the caller.
     *
     * See {isOperatorFor} and {defaultOperators}.
     *
     * Emits a {RevokedOperator} event.
     *
     * Requirements
     *
     * - `operator` cannot be calling address.
     */
    function revokeOperator(address operator) external;

    /**
     * @dev Returns the list of default operators. These accounts are operators
     * for all token holders, even if {authorizeOperator} was never called on
     * them.
     *
     * This list is immutable, but individual holders may revoke these via
     * {revokeOperator}, in which case {isOperatorFor} will return false.
     */
    function defaultOperators() external view returns (address[] memory);

    /**
     * @dev Moves `amount` tokens from `sender` to `recipient`. The caller must
     * be an operator of `sender`.
     *
     * If send or receive hooks are registered for `sender` and `recipient`,
     * the corresponding functions will be called with `data` and
     * `operatorData`. See {IERC777Sender} and {IERC777Recipient}.
     *
     * Emits a {Sent} event.
     *
     * Requirements
     *
     * - `sender` cannot be the zero address.
     * - `sender` must have at least `amount` tokens.
     * - the caller must be an operator for `sender`.
     * - `recipient` cannot be the zero address.
     * - if `recipient` is a contract, it must implement the {IERC777Recipient}
     * interface.
     */
    function operatorSend(
        address sender,
        address recipient,
        uint256 amount,
        bytes calldata data,
        bytes calldata operatorData
    ) external;

    /**
     * @dev Destroys `amount` tokens from `account`, reducing the total supply.
     * The caller must be an operator of `account`.
     *
     * If a send hook is registered for `account`, the corresponding function
     * will be called with `data` and `operatorData`. See {IERC777Sender}.
     *
     * Emits a {Burned} event.
     *
     * Requirements
     *
     * - `account` cannot be the zero address.
     * - `account` must have at least `amount` tokens.
     * - the caller must be an operator for `account`.
     */
    function operatorBurn(
        address account,
        uint256 amount,
        bytes calldata data,
        bytes calldata operatorData
    ) external;

    event Sent(
        address indexed operator,
        address indexed from,
        address indexed to,
        uint256 amount,
        bytes data,
        bytes operatorData
    );
}


// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v4.7.0) (token/ERC777/ERC777.sol)

pragma solidity ^0.8.0;

import "./IERC777.sol";
import "./IERC777Recipient.sol";
import "./IERC777Sender.sol";
import "../ERC20/IERC20.sol";
import "../../utils/Address.sol";
import "../../utils/Context.sol";
import "../../utils/introspection/IERC1820Registry.sol";

/**
 * @dev Implementation of the {IERC777} interface.
 *
 * This implementation is agnostic to the way tokens are created. This means
 * that a supply mechanism has to be added in a derived contract using {_mint}.
 *
 * Support for ERC20 is included in this contract, as specified by the EIP: both
 * the ERC777 and ERC20 interfaces can be safely used when interacting with it.
 * Both {IERC777-Sent} and {IERC20-Transfer} events are emitted on token
 * movements.
 *
 * Additionally, the {IERC777-granularity} value is hard-coded to `1`, meaning that there
 * are no special restrictions in the amount of tokens that created, moved, or
 * destroyed. This makes integration with ERC20 applications seamless.
 */
contract ERC777 is Context, IERC777, IERC20 {
    using Address for address;

    IERC1820Registry internal constant _ERC1820_REGISTRY = IERC1820Registry(0x1820a4B7618BdE71Dce8cdc73aAB6C95905faD24);

    mapping(address => uint256) private _balances;

    uint256 private _totalSupply;

    string private _name;
    string private _symbol;

    bytes32 private constant _TOKENS_SENDER_INTERFACE_HASH = keccak256("ERC777TokensSender");
    bytes32 private constant _TOKENS_RECIPIENT_INTERFACE_HASH = keccak256("ERC777TokensRecipient");

    // This isn't ever read from - it's only used to respond to the defaultOperators query.
    address[] private _defaultOperatorsArray;

    // Immutable, but accounts may revoke them (tracked in __revokedDefaultOperators).
    mapping(address => bool) private _defaultOperators;

    // For each account, a mapping of its operators and revoked default operators.
    mapping(address => mapping(address => bool)) private _operators;
    mapping(address => mapping(address => bool)) private _revokedDefaultOperators;

    // ERC20-allowances
    mapping(address => mapping(address => uint256)) private _allowances;

    /**
     * @dev `defaultOperators` may be an empty array.
     */
    constructor(
        string memory name_,
        string memory symbol_,
        address[] memory defaultOperators_
    ) {
        _name = name_;
        _symbol = symbol_;

        _defaultOperatorsArray = defaultOperators_;
        for (uint256 i = 0; i < defaultOperators_.length; i++) {
            _defaultOperators[defaultOperators_[i]] = true;
        }

        // register interfaces
        _ERC1820_REGISTRY.setInterfaceImplementer(address(this), keccak256("ERC777Token"), address(this));
        _ERC1820_REGISTRY.setInterfaceImplementer(address(this), keccak256("ERC20Token"), address(this));
    }

    /**
     * @dev See {IERC777-name}.
     */
    function name() public view virtual override returns (string memory) {
        return _name;
    }

    /**
     * @dev See {IERC777-symbol}.
     */
    function symbol() public view virtual override returns (string memory) {
        return _symbol;
    }

    /**
     * @dev See {ERC20-decimals}.
     *
     * Always returns 18, as per the
     * [ERC777 EIP](https://eips.ethereum.org/EIPS/eip-777#backward-compatibility).
     */
    function decimals() public pure virtual returns (uint8) {
        return 18;
    }

    /**
     * @dev See {IERC777-granularity}.
     *
     * This implementation always returns `1`.
     */
    function granularity() public view virtual override returns (uint256) {
        return 1;
    }

    /**
     * @dev See {IERC777-totalSupply}.
     */
    function totalSupply() public view virtual override(IERC20, IERC777) returns (uint256) {
        return _totalSupply;
    }

    /**
     * @dev Returns the amount of tokens owned by an account (`tokenHolder`).
     */
    function balanceOf(address tokenHolder) public view virtual override(IERC20, IERC777) returns (uint256) {
        return _balances[tokenHolder];
    }

    /**
     * @dev See {IERC777-send}.
     *
     * Also emits a {IERC20-Transfer} event for ERC20 compatibility.
     */
    function send(
        address recipient,
        uint256 amount,
        bytes memory data
    ) public virtual override {
        _send(_msgSender(), recipient, amount, data, "", true);
    }

    /**
     * @dev See {IERC20-transfer}.
     *
     * Unlike `send`, `recipient` is _not_ required to implement the {IERC777Recipient}
     * interface if it is a contract.
     *
     * Also emits a {Sent} event.
     */
    function transfer(address recipient, uint256 amount) public virtual override returns (bool) {
        _send(_msgSender(), recipient, amount, "", "", false);
        return true;
    }

    /**
     * @dev See {IERC777-burn}.
     *
     * Also emits a {IERC20-Transfer} event for ERC20 compatibility.
     */
    function burn(uint256 amount, bytes memory data) public virtual override {
        _burn(_msgSender(), amount, data, "");
    }

    /**
     * @dev See {IERC777-isOperatorFor}.
     */
    function isOperatorFor(address operator, address tokenHolder) public view virtual override returns (bool) {
        return
            operator == tokenHolder ||
            (_defaultOperators[operator] && !_revokedDefaultOperators[tokenHolder][operator]) ||
            _operators[tokenHolder][operator];
    }

    /**
     * @dev See {IERC777-authorizeOperator}.
     */
    function authorizeOperator(address operator) public virtual override {
        require(_msgSender() != operator, "ERC777: authorizing self as operator");

        if (_defaultOperators[operator]) {
            delete _revokedDefaultOperators[_msgSender()][operator];
        } else {
            _operators[_msgSender()][operator] = true;
        }

        emit AuthorizedOperator(operator, _msgSender());
    }

    /**
     * @dev See {IERC777-revokeOperator}.
     */
    function revokeOperator(address operator) public virtual override {
        require(operator != _msgSender(), "ERC777: revoking self as operator");

        if (_defaultOperators[operator]) {
            _revokedDefaultOperators[_msgSender()][operator] = true;
        } else {
            delete _operators[_msgSender()][operator];
        }

        emit RevokedOperator(operator, _msgSender());
    }

    /**
     * @dev See {IERC777-defaultOperators}.
     */
    function defaultOperators() public view virtual override returns (address[] memory) {
        return _defaultOperatorsArray;
    }

    /**
     * @dev See {IERC777-operatorSend}.
     *
     * Emits {Sent} and {IERC20-Transfer} events.
     */
    function operatorSend(
        address sender,
        address recipient,
        uint256 amount,
        bytes memory data,
        bytes memory operatorData
    ) public virtual override {
        require(isOperatorFor(_msgSender(), sender), "ERC777: caller is not an operator for holder");
        _send(sender, recipient, amount, data, operatorData, true);
    }

    /**
     * @dev See {IERC777-operatorBurn}.
     *
     * Emits {Burned} and {IERC20-Transfer} events.
     */
    function operatorBurn(
        address account,
        uint256 amount,
        bytes memory data,
        bytes memory operatorData
    ) public virtual override {
        require(isOperatorFor(_msgSender(), account), "ERC777: caller is not an operator for holder");
        _burn(account, amount, data, operatorData);
    }

    /**
     * @dev See {IERC20-allowance}.
     *
     * Note that operator and allowance concepts are orthogonal: operators may
     * not have allowance, and accounts with allowance may not be operators
     * themselves.
     */
    function allowance(address holder, address spender) public view virtual override returns (uint256) {
        return _allowances[holder][spender];
    }

    /**
     * @dev See {IERC20-approve}.
     *
     * NOTE: If `value` is the maximum `uint256`, the allowance is not updated on
     * `transferFrom`. This is semantically equivalent to an infinite approval.
     *
     * Note that accounts cannot have allowance issued by their operators.
     */
    function approve(address spender, uint256 value) public virtual override returns (bool) {
        address holder = _msgSender();
        _approve(holder, spender, value);
        return true;
    }

    /**
     * @dev See {IERC20-transferFrom}.
     *
     * NOTE: Does not update the allowance if the current allowance
     * is the maximum `uint256`.
     *
     * Note that operator and allowance concepts are orthogonal: operators cannot
     * call `transferFrom` (unless they have allowance), and accounts with
     * allowance cannot call `operatorSend` (unless they are operators).
     *
     * Emits {Sent}, {IERC20-Transfer} and {IERC20-Approval} events.
     */
    function transferFrom(
        address holder,
        address recipient,
        uint256 amount
    ) public virtual override returns (bool) {
        address spender = _msgSender();
        _spendAllowance(holder, spender, amount);
        _send(holder, recipient, amount, "", "", false);
        return true;
    }

    /**
     * @dev Creates `amount` tokens and assigns them to `account`, increasing
     * the total supply.
     *
     * If a send hook is registered for `account`, the corresponding function
     * will be called with the caller address as the `operator` and with
     * `userData` and `operatorData`.
     *
     * See {IERC777Sender} and {IERC777Recipient}.
     *
     * Emits {Minted} and {IERC20-Transfer} events.
     *
     * Requirements
     *
     * - `account` cannot be the zero address.
     * - if `account` is a contract, it must implement the {IERC777Recipient}
     * interface.
     */
    function _mint(
        address account,
        uint256 amount,
        bytes memory userData,
        bytes memory operatorData
    ) internal virtual {
        _mint(account, amount, userData, operatorData, true);
    }

    /**
     * @dev Creates `amount` tokens and assigns them to `account`, increasing
     * the total supply.
     *
     * If `requireReceptionAck` is set to true, and if a send hook is
     * registered for `account`, the corresponding function will be called with
     * `operator`, `data` and `operatorData`.
     *
     * See {IERC777Sender} and {IERC777Recipient}.
     *
     * Emits {Minted} and {IERC20-Transfer} events.
     *
     * Requirements
     *
     * - `account` cannot be the zero address.
     * - if `account` is a contract, it must implement the {IERC777Recipient}
     * interface.
     */
    function _mint(
        address account,
        uint256 amount,
        bytes memory userData,
        bytes memory operatorData,
        bool requireReceptionAck
    ) internal virtual {
        require(account != address(0), "ERC777: mint to the zero address");

        address operator = _msgSender();

        _beforeTokenTransfer(operator, address(0), account, amount);

        // Update state variables
        _totalSupply += amount;
        _balances[account] += amount;

        _callTokensReceived(operator, address(0), account, amount, userData, operatorData, requireReceptionAck);

        emit Minted(operator, account, amount, userData, operatorData);
        emit Transfer(address(0), account, amount);
    }

    /**
     * @dev Send tokens
     * @param from address token holder address
     * @param to address recipient address
     * @param amount uint256 amount of tokens to transfer
     * @param userData bytes extra information provided by the token holder (if any)
     * @param operatorData bytes extra information provided by the operator (if any)
     * @param requireReceptionAck if true, contract recipients are required to implement ERC777TokensRecipient
     */
    function _send(
        address from,
        address to,
        uint256 amount,
        bytes memory userData,
        bytes memory operatorData,
        bool requireReceptionAck
    ) internal virtual {
        require(from != address(0), "ERC777: transfer from the zero address");
        require(to != address(0), "ERC777: transfer to the zero address");

        address operator = _msgSender();

        _callTokensToSend(operator, from, to, amount, userData, operatorData);

        _move(operator, from, to, amount, userData, operatorData);

        _callTokensReceived(operator, from, to, amount, userData, operatorData, requireReceptionAck);
    }

    /**
     * @dev Burn tokens
     * @param from address token holder address
     * @param amount uint256 amount of tokens to burn
     * @param data bytes extra information provided by the token holder
     * @param operatorData bytes extra information provided by the operator (if any)
     */
    function _burn(
        address from,
        uint256 amount,
        bytes memory data,
        bytes memory operatorData
    ) internal virtual {
        require(from != address(0), "ERC777: burn from the zero address");

        address operator = _msgSender();

        _callTokensToSend(operator, from, address(0), amount, data, operatorData);

        _beforeTokenTransfer(operator, from, address(0), amount);

        // Update state variables
        uint256 fromBalance = _balances[from];
        require(fromBalance >= amount, "ERC777: burn amount exceeds balance");
        unchecked {
            _balances[from] = fromBalance - amount;
        }
        _totalSupply -= amount;

        emit Burned(operator, from, amount, data, operatorData);
        emit Transfer(from, address(0), amount);
    }

    function _move(
        address operator,
        address from,
        address to,
        uint256 amount,
        bytes memory userData,
        bytes memory operatorData
    ) private {
        _beforeTokenTransfer(operator, from, to, amount);

        uint256 fromBalance = _balances[from];
        require(fromBalance >= amount, "ERC777: transfer amount exceeds balance");
        unchecked {
            _balances[from] = fromBalance - amount;
        }
        _balances[to] += amount;

        emit Sent(operator, from, to, amount, userData, operatorData);
        emit Transfer(from, to, amount);
    }

    /**
     * @dev See {ERC20-_approve}.
     *
     * Note that accounts cannot have allowance issued by their operators.
     */
    function _approve(
        address holder,
        address spender,
        uint256 value
    ) internal virtual {
        require(holder != address(0), "ERC777: approve from the zero address");
        require(spender != address(0), "ERC777: approve to the zero address");

        _allowances[holder][spender] = value;
        emit Approval(holder, spender, value);
    }

    /**
     * @dev Call from.tokensToSend() if the interface is registered
     * @param operator address operator requesting the transfer
     * @param from address token holder address
     * @param to address recipient address
     * @param amount uint256 amount of tokens to transfer
     * @param userData bytes extra information provided by the token holder (if any)
     * @param operatorData bytes extra information provided by the operator (if any)
     */
    function _callTokensToSend(
        address operator,
        address from,
        address to,
        uint256 amount,
        bytes memory userData,
        bytes memory operatorData
    ) private {
        address implementer = _ERC1820_REGISTRY.getInterfaceImplementer(from, _TOKENS_SENDER_INTERFACE_HASH);
        if (implementer != address(0)) {
            IERC777Sender(implementer).tokensToSend(operator, from, to, amount, userData, operatorData);
        }
    }

    /**
     * @dev Call to.tokensReceived() if the interface is registered. Reverts if the recipient is a contract but
     * tokensReceived() was not registered for the recipient
     * @param operator address operator requesting the transfer
     * @param from address token holder address
     * @param to address recipient address
     * @param amount uint256 amount of tokens to transfer
     * @param userData bytes extra information provided by the token holder (if any)
     * @param operatorData bytes extra information provided by the operator (if any)
     * @param requireReceptionAck if true, contract recipients are required to implement ERC777TokensRecipient
     */
    function _callTokensReceived(
        address operator,
        address from,
        address to,
        uint256 amount,
        bytes memory userData,
        bytes memory operatorData,
        bool requireReceptionAck
    ) private {
        address implementer = _ERC1820_REGISTRY.getInterfaceImplementer(to, _TOKENS_RECIPIENT_INTERFACE_HASH);
        if (implementer != address(0)) {
            IERC777Recipient(implementer).tokensReceived(operator, from, to, amount, userData, operatorData);
        } else if (requireReceptionAck) {
            require(!to.isContract(), "ERC777: token recipient contract has no implementer for ERC777TokensRecipient");
        }
    }

    /**
     * @dev Updates `owner` s allowance for `spender` based on spent `amount`.
     *
     * Does not update the allowance amount in case of infinite allowance.
     * Revert if not enough allowance is available.
     *
     * Might emit an {Approval} event.
     */
    function _spendAllowance(
        address owner,
        address spender,
        uint256 amount
    ) internal virtual {
        uint256 currentAllowance = allowance(owner, spender);
        if (currentAllowance != type(uint256).max) {
            require(currentAllowance >= amount, "ERC777: insufficient allowance");
            unchecked {
                _approve(owner, spender, currentAllowance - amount);
            }
        }
    }

    /**
     * @dev Hook that is called before any token transfer. This includes
     * calls to {send}, {transfer}, {operatorSend}, minting and burning.
     *
     * Calling conditions:
     *
     * - when `from` and `to` are both non-zero, `amount` of ``from``'s tokens
     * will be to transferred to `to`.
     * - when `from` is zero, `amount` tokens will be minted for `to`.
     * - when `to` is zero, `amount` of ``from``'s tokens will be burned.
     * - `from` and `to` are never both zero.
     *
     * To learn more about hooks, head to xref:ROOT:extending-contracts.adoc#using-hooks[Using Hooks].
     */
    function _beforeTokenTransfer(
        address operator,
        address from,
        address to,
        uint256 amount
    ) internal virtual {}
}


// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts v4.4.1 (token/ERC721/extensions/IERC721Metadata.sol)

pragma solidity ^0.8.0;

import "../IERC721.sol";

/**
 * @title ERC-721 Non-Fungible Token Standard, optional metadata extension
 * @dev See https://eips.ethereum.org/EIPS/eip-721
 */
interface IERC721Metadata is IERC721 {
    /**
     * @dev Returns the token collection name.
     */
    function name() external view returns (string memory);

    /**
     * @dev Returns the token collection symbol.
     */
    function symbol() external view returns (string memory);

    /**
     * @dev Returns the Uniform Resource Identifier (URI) for `tokenId` token.
     */
    function tokenURI(uint256 tokenId) external view returns (string memory);
}


// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v4.7.0) (token/ERC721/extensions/ERC721URIStorage.sol)

pragma solidity ^0.8.0;

import "../ERC721.sol";

/**
 * @dev ERC721 token with storage based token URI management.
 */
abstract contract ERC721URIStorage is ERC721 {
    using Strings for uint256;

    // Optional mapping for token URIs
    mapping(uint256 => string) private _tokenURIs;

    /**
     * @dev See {IERC721Metadata-tokenURI}.
     */
    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        _requireMinted(tokenId);

        string memory _tokenURI = _tokenURIs[tokenId];
        string memory base = _baseURI();

        // If there is no base URI, return the token URI.
        if (bytes(base).length == 0) {
            return _tokenURI;
        }
        // If both are set, concatenate the baseURI and tokenURI (via abi.encodePacked).
        if (bytes(_tokenURI).length > 0) {
            return string(abi.encodePacked(base, _tokenURI));
        }

        return super.tokenURI(tokenId);
    }

    /**
     * @dev Sets `_tokenURI` as the tokenURI of `tokenId`.
     *
     * Requirements:
     *
     * - `tokenId` must exist.
     */
    function _setTokenURI(uint256 tokenId, string memory _tokenURI) internal virtual {
        require(_exists(tokenId), "ERC721URIStorage: URI set of nonexistent token");
        _tokenURIs[tokenId] = _tokenURI;
    }

    /**
     * @dev See {ERC721-_burn}. This override additionally checks to see if a
     * token-specific URI was set for the token, and if so, it deletes the token URI from
     * the storage mapping.
     */
    function _burn(uint256 tokenId) internal virtual override {
        super._burn(tokenId);

        if (bytes(_tokenURIs[tokenId]).length != 0) {
            delete _tokenURIs[tokenId];
        }
    }
}


// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v4.6.0) (token/ERC721/IERC721Receiver.sol)

pragma solidity ^0.8.0;

/**
 * @title ERC721 token receiver interface
 * @dev Interface for any contract that wants to support safeTransfers
 * from ERC721 asset contracts.
 */
interface IERC721Receiver {
    /**
     * @dev Whenever an {IERC721} `tokenId` token is transferred to this contract via {IERC721-safeTransferFrom}
     * by `operator` from `from`, this function is called.
     *
     * It must return its Solidity selector to confirm the token transfer.
     * If any other value is returned or the interface is not implemented by the recipient, the transfer will be reverted.
     *
     * The selector can be obtained in Solidity with `IERC721Receiver.onERC721Received.selector`.
     */
    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external returns (bytes4);
}


// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v4.7.0) (token/ERC721/IERC721.sol)

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

    /**
     * @dev Safely transfers `tokenId` token from `from` to `to`, checking first that contract recipients
     * are aware of the ERC721 protocol to prevent tokens from being forever locked.
     *
     * Requirements:
     *
     * - `from` cannot be the zero address.
     * - `to` cannot be the zero address.
     * - `tokenId` token must exist and be owned by `from`.
     * - If the caller is not `from`, it must have been allowed to move this token by either {approve} or {setApprovalForAll}.
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
     * @dev Returns the account approved for `tokenId` token.
     *
     * Requirements:
     *
     * - `tokenId` must exist.
     */
    function getApproved(uint256 tokenId) external view returns (address operator);

    /**
     * @dev Returns if the `operator` is allowed to manage all of the assets of `owner`.
     *
     * See {setApprovalForAll}
     */
    function isApprovedForAll(address owner, address operator) external view returns (bool);
}


// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v4.7.0) (token/ERC721/ERC721.sol)

pragma solidity ^0.8.0;

import "./IERC721.sol";
import "./IERC721Receiver.sol";
import "./extensions/IERC721Metadata.sol";
import "../../utils/Address.sol";
import "../../utils/Context.sol";
import "../../utils/Strings.sol";
import "../../utils/introspection/ERC165.sol";

/**
 * @dev Implementation of https://eips.ethereum.org/EIPS/eip-721[ERC721] Non-Fungible Token Standard, including
 * the Metadata extension, but not including the Enumerable extension, which is available separately as
 * {ERC721Enumerable}.
 */
contract ERC721 is Context, ERC165, IERC721, IERC721Metadata {
    using Address for address;
    using Strings for uint256;

    // Token name
    string private _name;

    // Token symbol
    string private _symbol;

    // Mapping from token ID to owner address
    mapping(uint256 => address) private _owners;

    // Mapping owner address to token count
    mapping(address => uint256) private _balances;

    // Mapping from token ID to approved address
    mapping(uint256 => address) private _tokenApprovals;

    // Mapping from owner to operator approvals
    mapping(address => mapping(address => bool)) private _operatorApprovals;

    /**
     * @dev Initializes the contract by setting a `name` and a `symbol` to the token collection.
     */
    constructor(string memory name_, string memory symbol_) {
        _name = name_;
        _symbol = symbol_;
    }

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC165, IERC165) returns (bool) {
        return
            interfaceId == type(IERC721).interfaceId ||
            interfaceId == type(IERC721Metadata).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    /**
     * @dev See {IERC721-balanceOf}.
     */
    function balanceOf(address owner) public view virtual override returns (uint256) {
        require(owner != address(0), "ERC721: address zero is not a valid owner");
        return _balances[owner];
    }

    /**
     * @dev See {IERC721-ownerOf}.
     */
    function ownerOf(uint256 tokenId) public view virtual override returns (address) {
        address owner = _owners[tokenId];
        require(owner != address(0), "ERC721: invalid token ID");
        return owner;
    }

    /**
     * @dev See {IERC721Metadata-name}.
     */
    function name() public view virtual override returns (string memory) {
        return _name;
    }

    /**
     * @dev See {IERC721Metadata-symbol}.
     */
    function symbol() public view virtual override returns (string memory) {
        return _symbol;
    }

    /**
     * @dev See {IERC721Metadata-tokenURI}.
     */
    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        _requireMinted(tokenId);

        string memory baseURI = _baseURI();
        return bytes(baseURI).length > 0 ? string(abi.encodePacked(baseURI, tokenId.toString())) : "";
    }

    /**
     * @dev Base URI for computing {tokenURI}. If set, the resulting URI for each
     * token will be the concatenation of the `baseURI` and the `tokenId`. Empty
     * by default, can be overridden in child contracts.
     */
    function _baseURI() internal view virtual returns (string memory) {
        return "";
    }

    /**
     * @dev See {IERC721-approve}.
     */
    function approve(address to, uint256 tokenId) public virtual override {
        address owner = ERC721.ownerOf(tokenId);
        require(to != owner, "ERC721: approval to current owner");

        require(
            _msgSender() == owner || isApprovedForAll(owner, _msgSender()),
            "ERC721: approve caller is not token owner nor approved for all"
        );

        _approve(to, tokenId);
    }

    /**
     * @dev See {IERC721-getApproved}.
     */
    function getApproved(uint256 tokenId) public view virtual override returns (address) {
        _requireMinted(tokenId);

        return _tokenApprovals[tokenId];
    }

    /**
     * @dev See {IERC721-setApprovalForAll}.
     */
    function setApprovalForAll(address operator, bool approved) public virtual override {
        _setApprovalForAll(_msgSender(), operator, approved);
    }

    /**
     * @dev See {IERC721-isApprovedForAll}.
     */
    function isApprovedForAll(address owner, address operator) public view virtual override returns (bool) {
        return _operatorApprovals[owner][operator];
    }

    /**
     * @dev See {IERC721-transferFrom}.
     */
    function transferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public virtual override {
        //solhint-disable-next-line max-line-length
        require(_isApprovedOrOwner(_msgSender(), tokenId), "ERC721: caller is not token owner nor approved");

        _transfer(from, to, tokenId);
    }

    /**
     * @dev See {IERC721-safeTransferFrom}.
     */
    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public virtual override {
        safeTransferFrom(from, to, tokenId, "");
    }

    /**
     * @dev See {IERC721-safeTransferFrom}.
     */
    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId,
        bytes memory data
    ) public virtual override {
        require(_isApprovedOrOwner(_msgSender(), tokenId), "ERC721: caller is not token owner nor approved");
        _safeTransfer(from, to, tokenId, data);
    }

    /**
     * @dev Safely transfers `tokenId` token from `from` to `to`, checking first that contract recipients
     * are aware of the ERC721 protocol to prevent tokens from being forever locked.
     *
     * `data` is additional data, it has no specified format and it is sent in call to `to`.
     *
     * This internal function is equivalent to {safeTransferFrom}, and can be used to e.g.
     * implement alternative mechanisms to perform token transfer, such as signature-based.
     *
     * Requirements:
     *
     * - `from` cannot be the zero address.
     * - `to` cannot be the zero address.
     * - `tokenId` token must exist and be owned by `from`.
     * - If `to` refers to a smart contract, it must implement {IERC721Receiver-onERC721Received}, which is called upon a safe transfer.
     *
     * Emits a {Transfer} event.
     */
    function _safeTransfer(
        address from,
        address to,
        uint256 tokenId,
        bytes memory data
    ) internal virtual {
        _transfer(from, to, tokenId);
        require(_checkOnERC721Received(from, to, tokenId, data), "ERC721: transfer to non ERC721Receiver implementer");
    }

    /**
     * @dev Returns whether `tokenId` exists.
     *
     * Tokens can be managed by their owner or approved accounts via {approve} or {setApprovalForAll}.
     *
     * Tokens start existing when they are minted (`_mint`),
     * and stop existing when they are burned (`_burn`).
     */
    function _exists(uint256 tokenId) internal view virtual returns (bool) {
        return _owners[tokenId] != address(0);
    }

    /**
     * @dev Returns whether `spender` is allowed to manage `tokenId`.
     *
     * Requirements:
     *
     * - `tokenId` must exist.
     */
    function _isApprovedOrOwner(address spender, uint256 tokenId) internal view virtual returns (bool) {
        address owner = ERC721.ownerOf(tokenId);
        return (spender == owner || isApprovedForAll(owner, spender) || getApproved(tokenId) == spender);
    }

    /**
     * @dev Safely mints `tokenId` and transfers it to `to`.
     *
     * Requirements:
     *
     * - `tokenId` must not exist.
     * - If `to` refers to a smart contract, it must implement {IERC721Receiver-onERC721Received}, which is called upon a safe transfer.
     *
     * Emits a {Transfer} event.
     */
    function _safeMint(address to, uint256 tokenId) internal virtual {
        _safeMint(to, tokenId, "");
    }

    /**
     * @dev Same as {xref-ERC721-_safeMint-address-uint256-}[`_safeMint`], with an additional `data` parameter which is
     * forwarded in {IERC721Receiver-onERC721Received} to contract recipients.
     */
    function _safeMint(
        address to,
        uint256 tokenId,
        bytes memory data
    ) internal virtual {
        _mint(to, tokenId);
        require(
            _checkOnERC721Received(address(0), to, tokenId, data),
            "ERC721: transfer to non ERC721Receiver implementer"
        );
    }

    /**
     * @dev Mints `tokenId` and transfers it to `to`.
     *
     * WARNING: Usage of this method is discouraged, use {_safeMint} whenever possible
     *
     * Requirements:
     *
     * - `tokenId` must not exist.
     * - `to` cannot be the zero address.
     *
     * Emits a {Transfer} event.
     */
    function _mint(address to, uint256 tokenId) internal virtual {
        require(to != address(0), "ERC721: mint to the zero address");
        require(!_exists(tokenId), "ERC721: token already minted");

        _beforeTokenTransfer(address(0), to, tokenId);

        _balances[to] += 1;
        _owners[tokenId] = to;

        emit Transfer(address(0), to, tokenId);

        _afterTokenTransfer(address(0), to, tokenId);
    }

    /**
     * @dev Destroys `tokenId`.
     * The approval is cleared when the token is burned.
     *
     * Requirements:
     *
     * - `tokenId` must exist.
     *
     * Emits a {Transfer} event.
     */
    function _burn(uint256 tokenId) internal virtual {
        address owner = ERC721.ownerOf(tokenId);

        _beforeTokenTransfer(owner, address(0), tokenId);

        // Clear approvals
        _approve(address(0), tokenId);

        _balances[owner] -= 1;
        delete _owners[tokenId];

        emit Transfer(owner, address(0), tokenId);

        _afterTokenTransfer(owner, address(0), tokenId);
    }

    /**
     * @dev Transfers `tokenId` from `from` to `to`.
     *  As opposed to {transferFrom}, this imposes no restrictions on msg.sender.
     *
     * Requirements:
     *
     * - `to` cannot be the zero address.
     * - `tokenId` token must be owned by `from`.
     *
     * Emits a {Transfer} event.
     */
    function _transfer(
        address from,
        address to,
        uint256 tokenId
    ) internal virtual {
        require(ERC721.ownerOf(tokenId) == from, "ERC721: transfer from incorrect owner");
        require(to != address(0), "ERC721: transfer to the zero address");

        _beforeTokenTransfer(from, to, tokenId);

        // Clear approvals from the previous owner
        _approve(address(0), tokenId);

        _balances[from] -= 1;
        _balances[to] += 1;
        _owners[tokenId] = to;

        emit Transfer(from, to, tokenId);

        _afterTokenTransfer(from, to, tokenId);
    }

    /**
     * @dev Approve `to` to operate on `tokenId`
     *
     * Emits an {Approval} event.
     */
    function _approve(address to, uint256 tokenId) internal virtual {
        _tokenApprovals[tokenId] = to;
        emit Approval(ERC721.ownerOf(tokenId), to, tokenId);
    }

    /**
     * @dev Approve `operator` to operate on all of `owner` tokens
     *
     * Emits an {ApprovalForAll} event.
     */
    function _setApprovalForAll(
        address owner,
        address operator,
        bool approved
    ) internal virtual {
        require(owner != operator, "ERC721: approve to caller");
        _operatorApprovals[owner][operator] = approved;
        emit ApprovalForAll(owner, operator, approved);
    }

    /**
     * @dev Reverts if the `tokenId` has not been minted yet.
     */
    function _requireMinted(uint256 tokenId) internal view virtual {
        require(_exists(tokenId), "ERC721: invalid token ID");
    }

    /**
     * @dev Internal function to invoke {IERC721Receiver-onERC721Received} on a target address.
     * The call is not executed if the target address is not a contract.
     *
     * @param from address representing the previous owner of the given token ID
     * @param to target address that will receive the tokens
     * @param tokenId uint256 ID of the token to be transferred
     * @param data bytes optional data to send along with the call
     * @return bool whether the call correctly returned the expected magic value
     */
    function _checkOnERC721Received(
        address from,
        address to,
        uint256 tokenId,
        bytes memory data
    ) private returns (bool) {
        if (to.isContract()) {
            try IERC721Receiver(to).onERC721Received(_msgSender(), from, tokenId, data) returns (bytes4 retval) {
                return retval == IERC721Receiver.onERC721Received.selector;
            } catch (bytes memory reason) {
                if (reason.length == 0) {
                    revert("ERC721: transfer to non ERC721Receiver implementer");
                } else {
                    /// @solidity memory-safe-assembly
                    assembly {
                        revert(add(32, reason), mload(reason))
                    }
                }
            }
        } else {
            return true;
        }
    }

    /**
     * @dev Hook that is called before any token transfer. This includes minting
     * and burning.
     *
     * Calling conditions:
     *
     * - When `from` and `to` are both non-zero, ``from``'s `tokenId` will be
     * transferred to `to`.
     * - When `from` is zero, `tokenId` will be minted for `to`.
     * - When `to` is zero, ``from``'s `tokenId` will be burned.
     * - `from` and `to` are never both zero.
     *
     * To learn more about hooks, head to xref:ROOT:extending-contracts.adoc#using-hooks[Using Hooks].
     */
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal virtual {}

    /**
     * @dev Hook that is called after any transfer of tokens. This includes
     * minting and burning.
     *
     * Calling conditions:
     *
     * - when `from` and `to` are both non-zero.
     * - `from` and `to` are never both zero.
     *
     * To learn more about hooks, head to xref:ROOT:extending-contracts.adoc#using-hooks[Using Hooks].
     */
    function _afterTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal virtual {}
}


// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v4.6.0) (token/ERC20/IERC20.sol)

pragma solidity ^0.8.0;

/**
 * @dev Interface of the ERC20 standard as defined in the EIP.
 */
interface IERC20 {
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