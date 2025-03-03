// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import "erc721a/contracts/ERC721A.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "erc721a/contracts/extensions/ERC721ABurnable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./FactoryContract.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

error MaxSupplyReached();
error NonZeroQuanityRequired();
error InvalidPrice();
error InvalidBaseURI();

contract Property is  ERC721A,ERC721ABurnable,Ownable,ReentrancyGuard {
   
    using SafeERC20 for IERC20;
    using SafeMath for uint256;
    IERC20 public immutable usdt;  
    FactoryContract public immutable factoryContract;
    AggregatorV3Interface  public immutable datafeed;
 
    uint256 public price;                               // price refers to per share price in USDT (6 decimals)
    string  public _baseTokenURI;                       // URI of metadata file stored on IPFS
    uint256 public count;                               // Count for minted NFTs .
    uint256 public immutable totalFractions;            // totalFractions refers to the total shares of a property .
    uint256 public immutable companySharePercentage;    // Percentage of shares company holds .(should be in basis points(bps) : 1% = 100bps)
    uint256 public platformFee;
    bool public isGlobalPlatformFee = true;
    address[] public propertyHolders;

    mapping(address holderAddress => uint256[] tokenIds) public ownedTokens;
   
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     Events                                 */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    event PropertySharesPurchased(address indexed to, uint256 quantity,uint256 purchasePrice,uint256 platformFeeDeducted);
    event PlatformFeeUpdated(address indexed updater, uint256 oldFee, uint256 newFee);
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
        address payable  factoryAddress,
        address aggregatorV3,
        address owner
        ) ERC721A(name, symbol)Ownable(owner) {

        if(factoryAddress == address(0)){
            revert InvalidAddress();
        }
        if (_price == 0) {
            revert InvalidPrice();
        }
        if (bytes(baseURI).length == 0) {
            revert InvalidBaseURI();
        }
    
        totalFractions=_totalFractions;
        price=_price;
        _baseTokenURI=baseURI;
        companySharePercentage=_companySharePercentage;
        usdt = IERC20(usdtAddress);
        factoryContract = FactoryContract(factoryAddress);
        datafeed=AggregatorV3Interface(aggregatorV3);

        uint256 quantity = (_totalFractions.mul(100)).mul(_companySharePercentage);
        quantity = quantity.div(1000000);
        if(quantity!=0){
            _mint(companyShareHolder, quantity);
            propertyHolders.push(companyShareHolder);
            addOwnedTokens(companyShareHolder,quantity); 
        }          
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     Modifier                               */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
     
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

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     Helper Function                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function addOwnedTokens(address to,uint256 quantity)private{
        for (uint256 i = 0; i < quantity; i++) {
            ownedTokens[to].push(count);  
            count+=1;  
        }
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

    // It converts amount of eth required to buy nfts along with platform fee.
    function USDTToETHRate(uint256 quantity) public view returns (uint256 EthRequired, uint256 platformFeeAdded) {
        (, int256 answer, , ,) = datafeed.latestRoundData();
        require(answer > 0, "Invalid price feed data");

        uint256 USDtprice = uint256(answer).div(1e2);
        require(USDtprice > 0, "Price conversion issue");

        uint256 shareAmount = quantity.mul(price);

        // Now we add the platform fee
        uint256 _platformFee = platformFee;
        if (isGlobalPlatformFee) {
            _platformFee = factoryContract.globalPlatformFee();
        }

        uint256 feeAddedInEth = 0;
        if (_platformFee != 0) {
            uint256 tempFee = shareAmount.mul(_platformFee).div(10000); // Adjust for basis points (1% = 100)
            shareAmount = shareAmount.add(tempFee);
            feeAddedInEth = tempFee.mul(1e18).div(USDtprice);
        }

        uint256 requiredAmount = shareAmount.mul(1e18).div(USDtprice);
        return (requiredAmount, feeAddedInEth);
    }
    
    /**
     * @notice Allows a user to purchase property fractions using ETH.
     * @dev This function checks if the buyer has sufficient ETH based on the current USDT to ETH exchange rate. 
     *   It applies a slippage tolerance, refunds any excess ETH, and transfers the required ETH to the factory contract.
     * @param to The recipient address of the minted property fractions.
     * @param quantity The number of property fractions to be minted.
    */
    function purchaseByETH(address to, uint256 quantity) external payable isListed nonReentrant {
        if(to == address(0)){
            revert InvalidAddress();
        }
        if(quantity == 0){
            revert NonZeroQuanityRequired();
        }
        // count -> No. of minted Fractions
        if(count + quantity > totalFractions){
            revert MaxSupplyReached();
        }

        (uint256 ethRequired, uint256 platformFeeAdded) = USDTToETHRate(quantity);
        uint256 slippage = factoryContract.slippage();
        // Calculate slippage tolerance
        if(slippage > 0){
            uint256 slippageAmount = ethRequired.mul(factoryContract.slippage()).div(10000);
            require(msg.value >= ethRequired.sub(slippageAmount), "Insufficient ETH balance for minting");
        }
    
        // Refund excess ETH if overpaid
        if (msg.value > ethRequired) {
            uint256 refund = msg.value.sub(ethRequired);
            (bool refundSuccess, ) = msg.sender.call{value: refund}("");
            require(refundSuccess, "Refund failed");
        }

        (bool transferSuccess, ) = address(factoryContract).call{value: ethRequired}("");
        require(transferSuccess, "ETH transfer failed");

        if (balanceOf(to) == 0) {
            propertyHolders.push(to);
        }
        _mint(to, quantity);
        addOwnedTokens(to, quantity);
        emit PropertySharesPurchased(to, quantity, ethRequired, platformFeeAdded);
    }

    /**
     * @notice Allows a user to purchase property fractions using USDT.
     * @dev This function calculates the required USDT amount based on the quantity and price per fraction, 
     *     applies platform fees if applicable, verifies the sender’s USDT balance, and transfers USDT to the factory contract.
     * @param to The recipient address of the minted property fractions.
     * @param quantity The number of property fractions to be minted.
    */
    function purchaseByUSDT(address to, uint256 quantity) external isListed nonReentrant{
        if(to == address(0)){
            revert InvalidAddress();
        }
        if(quantity == 0){
            revert NonZeroQuanityRequired();
        }
        if(count + quantity > totalFractions){
            revert MaxSupplyReached();
        }
        uint256 sharesCost = quantity * price;
        uint256 _platformFee = platformFee; 
        if (isGlobalPlatformFee){
           _platformFee=factoryContract.globalPlatformFee(); 
        }
        uint256 usdtAmountToBeTransferred = sharesCost;
        uint256 feeAdded = 0;
        if(_platformFee!=0){
            uint256 tempFee = (sharesCost).mul(_platformFee);
            tempFee = (tempFee.div(10000));
            usdtAmountToBeTransferred = usdtAmountToBeTransferred + tempFee;
            feeAdded=tempFee;
        }
        require(usdt.balanceOf(msg.sender) >= usdtAmountToBeTransferred, "Insufficient USDT funds in senders account");
        usdt.safeTransferFrom(msg.sender, address(factoryContract), usdtAmountToBeTransferred) ;
        if (balanceOf(to) == 0) {
            propertyHolders.push(to); 
        }
        _mint(to, quantity);
        addOwnedTokens(to,quantity);
        emit PropertySharesPurchased(to, quantity,usdtAmountToBeTransferred,feeAdded);  
    }  


    /**
     * @notice Allows an authorized entity to mint NFTs for a user at no cost.
     * @dev Only the claim authority set in the factory contract can call this function.
     *      It ensures that the recipient address is valid and that the minting does not exceed the total supply.
     * @param to The recipient address receiving the NFTs.
     * @param quantity The number of NFTs to be minted.
    */
    function claim(address to, uint256 quantity) external isListed nonReentrant{
        require(msg.sender == factoryContract.claimAuthority(), "Sender has no claim authority");
        if(to == address(0)){
            revert InvalidAddress();
        }
        if(quantity == 0){
            revert NonZeroQuanityRequired();
        }
        if(count + quantity > totalFractions){
            revert MaxSupplyReached();
        }
        _mint(to, quantity);
        addOwnedTokens(to,quantity);
        emit SharesClaimed(to, quantity);
    }

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

    function batchBurn() external {
        uint256[] memory tokenIds = ownedTokens[msg.sender]; 
        require(tokenIds.length > 0, "No tokens to burn");
        for (uint256 i = 0; i < tokenIds.length; i++) {
            burn(tokenIds[i]);
        }
        delete ownedTokens[msg.sender];
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     Setter Functions                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function setBaseURI(string calldata baseURI) external onlyModerator isListed {
        string memory oldBaseURI = _baseTokenURI;
        _baseTokenURI = baseURI;
        emit BaseURIChanged(oldBaseURI, baseURI);
    }

    function changeSharePrice(uint256 newPrice)external onlyModerator isListed{
        uint256 oldPrice=price;
        price=newPrice;
        emit PriceChanged(oldPrice,newPrice);
    }

    function platformFeeSetter(uint256 _platformFee,bool status )external onlyModerator isListed{
        uint256 oldFee = platformFee;
        platformFee = _platformFee;
        isGlobalPlatformFee = status;
        emit PlatformFeeUpdated(msg.sender, oldFee, _platformFee);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     Getter Functions                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function tokenURI(uint256 tokenId) public view override(ERC721A, IERC721A) returns (string memory) {
        require(_exists(tokenId), "URI query for nonexistent token");
        return _baseTokenURI;
    }
    
    function getPropertyHolders() external view returns (address[] memory) {
        return propertyHolders;
    }

    function getOwnedTokens(address holder) public view returns (uint256[] memory) {
        return ownedTokens[holder];
    }
}
