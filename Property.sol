// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import "erc721a/contracts/ERC721A.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "erc721a/contracts/extensions/ERC721ABurnable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "contracts/VRDA1/factoryContract.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";


// @Currently we have single metadata file for all nfts
contract Property is  ERC721A,ERC721ABurnable {
   
    using SafeERC20 for IERC20;
    using SafeMath for uint256;
 
    uint256 public price;                   // price refers to per share price in USDT (6 decimals)
    string public _baseTokenURI;            // URI of metadata file stored on IPFS
    uint256 public totalFractions;          // totalFractions refers to the total shares of a property .
    uint256 public companySharePercentage;  // Percentage of shares company holds .(should be in basis points(bps) : 1% = 100bps)
    uint256 public count = 0;               // Count for minted NFTs .
    uint256 public platformFee = 0 ;        // Default 0%
    bool public isGlobalPlatformFee = true;

    address[] public propertyHolders;
    mapping(address holderAddress => uint256[] tokenIds) private ownedTokens;

    IERC20 public usdt;  
    PropertiesFactory private factoryContract;
 
    event PropertySharesPurchased(address indexed to, uint256 quantity,uint256 purchasePrice,uint256 platformFeeDeducted);
    event PlatformFeeUpdated(uint256 indexed timestamp, address indexed updater, uint256 oldFee, uint256 newFee);
    event SharesClaimed(address indexed to, uint256 quantity);
    event PriceChanged(uint256 oldPrice, uint256 newPrice);
    event BaseURIChanged(string oldBaseURI, string newBaseURI);
    
    constructor(
        string memory name,
        string memory symbol,
        uint256  _totalFractions,
        uint256 _price,
        string memory baseURI,
        uint256 _companySharePercentage,
        address companyShareHolder,
        address usdtAddress,
        address factoryAddress
        ) ERC721A(name, symbol) {
        if(factoryAddress == address(0)){
            revert InvalidAddress();
        }
    
        totalFractions=_totalFractions;
        price=_price;
        _baseTokenURI=baseURI;
        companySharePercentage=_companySharePercentage;
        usdt = IERC20(usdtAddress);
        factoryContract = PropertiesFactory(factoryAddress);
        
        // Minting company shares . 
        uint256 quantity = (_totalFractions.mul(100)).mul(_companySharePercentage);
        quantity = quantity.div(1000000);
        if(quantity!=0){
            _mint(companyShareHolder, quantity);
            if (balanceOf(companyShareHolder) == quantity) {
                propertyHolders.push(companyShareHolder);
            }
            addOwnedTokens(companyShareHolder,quantity); 
        }          
    }

    // Access modifier
    modifier isListed() {
        require(factoryContract.propertiesStatus(address(this)), "Delisted Properties can neither be purchased nor updated");
        _;
    }
    modifier onlyModerator() {
        if (!(factoryContract.moderators(msg.sender) || factoryContract.admins(msg.sender) || factoryContract.owner() == msg.sender)) {
            revert Unauthorized();
        }
        _;
    }


    // Helper functions
    function addOwnedTokens(address to,uint256 quantity)private{
        for (uint256 i = 0; i < quantity; i++) {
            uint id=count+i;
            ownedTokens[to].push(id);    
        }
        count=count+quantity;
    }

    function removeTokenFromOwnerEnumeration(address from, uint256 tokenId) private {

        uint256 length = ownedTokens[from].length;
       
        if (length == 1) {
            require(ownedTokens[from][0] == tokenId, "Token ID not found in owner's list");
            ownedTokens[from].pop();
            return;
        }

        for (uint256 i = 0; i < length; i++) {
            if (ownedTokens[from][i] == tokenId) {
                ownedTokens[from][i] = ownedTokens[from][length - 1]; 
                ownedTokens[from].pop(); 
                return;
            }
        }

        revert("Token ID not found in owner's list");
    }
    // It gives amount of eth required to buy nfts along with platform fee.
    function USDTToETHRate(uint256 quanity)public view returns(uint256 EthRequired,uint256 platformFeeAdded){
        // ETH/USD
        AggregatorV3Interface  datafeed=AggregatorV3Interface(0x694AA1769357215DE4FAC081bf1f309aDC325306);
        ( , int256 answer, , ,)=datafeed.latestRoundData();
        uint256 USDtprice=uint256(answer)/1e2;
        uint256 shareAmount=(quanity.mul(price));
        // now we have to add platform fee in it
        uint256 _platformFee = platformFee ;
        if (isGlobalPlatformFee){
            // factory contract platform fee will be considerred
           _platformFee=factoryContract.globalPlatformFee(); 
        }
        uint256 feeAddedInEth = 0;
         if(_platformFee!=0){
            // platform fee will be charged
            // here platform fee is in basis points
            uint256 tempFee = (shareAmount.mul(100)).mul(_platformFee);
            tempFee = (tempFee.div(1000000));
            shareAmount = shareAmount + tempFee;
            feeAddedInEth = (tempFee.mul(1e18)).div(USDtprice);
        }
        uint256 requiredAmount=(shareAmount.mul(1e18)).div(USDtprice);
        return (requiredAmount,feeAddedInEth);
    }
    
    // purchase shares of property by ETH
    function purchaseByETH(address to, uint256 quantity) external payable isListed {
        if(to == address(0)){
            revert InvalidAddress();
        }
        require(quantity != 0, "Quantity cannot be zero");
        require(count + quantity <= totalFractions, "Max supply reached");
        require(msg.sender.balance > msg.value, "Insufficient Funds (ETH) for Minting");

        (uint256 ethRequired, uint256 platformFeeAdded)=USDTToETHRate(quantity);
       
        if(msg.value<ethRequired){
            // check if its less than slippage (represented as 100 = 1% in basis points be default )as well 
            uint256 slippageAmount = (ethRequired.mul(100)).mul(factoryContract.slippage());
            slippageAmount = (slippageAmount.div(1000000));
            // if msg.value is still less than required balance after deducting 5% slippage revert transaction .
            require(msg.value < (ethRequired.sub(slippageAmount)),"Insufficient ETH balance for minting ");

        }else{
            // if send balance (msg.value) is greater than required than transfer back accessive amount .
            uint256 amountTransferBack = (msg.value).sub(ethRequired);
            (bool success, ) = (msg.sender).call{value:amountTransferBack }("");
            if(success == false){
                revert TransferFailed();
            }
        }   
        // transfer purchase price in factory contract
        (bool txSuccess, ) = (address(factoryContract)).call{value:msg.value}("");
        if(txSuccess == false){
            revert TransferFailed();
        }
        
        // Mint NFT
        if (balanceOf(to) == 0) {
            propertyHolders.push(to); 
        }
        _mint(to, quantity);
        addOwnedTokens(to,quantity);
        emit PropertySharesPurchased(to, quantity,ethRequired,platformFeeAdded); 
    }

    // purchase shares of property by USDT 
    function purchaseByUSDT(address to, uint256 quantity) external isListed{
        if(to == address(0)){
            revert InvalidAddress();
        }
        require(quantity != 0, "Quantity cannot be zero");
        // count -> No. of minted Fractions
        require(count + quantity <= totalFractions,"Max supply reached");
        uint256 sharesCost = quantity * price;
        uint256 _platformFee = platformFee; 
        if (isGlobalPlatformFee){
            // factory contract platform fee will be considerred
           _platformFee=factoryContract.globalPlatformFee(); 
        }
        uint256 usdtAmountToBeTransferred = sharesCost;
        uint256 feeAdded = 0;
        if(_platformFee!=0){
            // platform fee will be charged
            // here platform fee is in basis points
            uint256 tempFee = (sharesCost.mul(100)).mul(_platformFee);
            tempFee = (tempFee.div(1000000));
            usdtAmountToBeTransferred = usdtAmountToBeTransferred + tempFee;
            feeAdded=tempFee;
        }
        // check senders balance
        require(usdt.balanceOf(msg.sender) >= usdtAmountToBeTransferred, "Insufficient USDT funds in senders account");
        // Check allowance given to contract by buyer
        require(usdt.allowance(msg.sender, address(this)) >= usdtAmountToBeTransferred, "USDT allowance too low");
        // Transfer USDT from sender to the factory contract
        usdt.safeTransferFrom(msg.sender, address(factoryContract), usdtAmountToBeTransferred) ;
        // Mint the NFTs
        if (balanceOf(to) == 0) {
            propertyHolders.push(to); 
        }
        _mint(to, quantity);
        addOwnedTokens(to,quantity);
        emit PropertySharesPurchased(to, quantity,sharesCost,feeAdded);  
    }  
    // Buy nfts with no cost
    function claim(address to, uint256 quantity) external  isListed{
        if(to == address(0)){
            revert InvalidAddress();
        }
        require(quantity != 0, "Quantity cannot be zero");
        require(count + quantity <= totalFractions,"Max supply reached");
        _mint(to, quantity);
        addOwnedTokens(to,quantity);
        emit SharesClaimed(to, quantity);
    }
    // Transfer NFT (transfer share)
    function transferFrom(address from, address to, uint256 tokenId) public payable override(ERC721A, IERC721A) {
        super.transferFrom(from, to, tokenId);
        if (balanceOf(from) == 0) {
            for (uint256 i = 0; i < propertyHolders.length; i++) {
                if (propertyHolders[i] == from) {
                    propertyHolders[i] = propertyHolders[propertyHolders.length - 1];
                    propertyHolders.pop();
                    break;
                }
            }
        }
        if (balanceOf(to) == 1) {
            propertyHolders.push(to);  
        } 
        ownedTokens[to].push(tokenId);
        removeTokenFromOwnerEnumeration(from, tokenId);

    }
    // to call batchBurn function contract should be approved to transfer all these tokens to zero address .
    function batchBurn(address ownerAddress) public {
        if(ownerAddress == address(0)){
            revert InvalidAddress();
        }
        uint256[] memory tokenIds = ownedTokens[ownerAddress]; 
        require(tokenIds.length > 0, "No tokens to burn");
        for (uint256 i = 0; i < tokenIds.length; i++) {
            burn(tokenIds[i]);
        }
        delete ownedTokens[ownerAddress];
    }

    function setBaseURI(string calldata baseURI) external onlyModerator isListed {
        string memory oldBaseURI = _baseTokenURI;
        _baseTokenURI = baseURI;
        emit BaseURIChanged(oldBaseURI, baseURI);
    }

    // Change per share price
    function changeSharePrice(uint256 newPrice)external onlyModerator isListed{
        uint256 oldPrice=price;
        price=newPrice;
        emit PriceChanged(oldPrice,newPrice);
    }
    function platformFeeSetter(uint256 _platformFee,bool status )external onlyModerator isListed{
        uint256 oldFee = platformFee;
        platformFee = _platformFee;
        isGlobalPlatformFee = status;
        emit PlatformFeeUpdated(block.timestamp, msg.sender, oldFee, _platformFee);
    }
    // This function will return baseURI for the metadata file stored on IPFS .
    function tokenURI(uint256 tokenId) public view override(ERC721A, IERC721A) returns (string memory) {
        require(_exists(tokenId), "URI query for nonexistent token");
        return _baseTokenURI;
    }
    // This function will return all shares(NFTs) hold by this specific address  . 
    function tokensOfOwner(address ownerAddress) public view returns (uint256[] memory) {
        return ownedTokens[ownerAddress];
    }
    // This function will return all property share holders .
    function getPropertyHolders() external view returns (address[] memory) {
        return propertyHolders;
    }
}
