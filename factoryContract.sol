// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;
import "./Property.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
 
error InvalidAddress();
error TransferFailed();
error Unauthorized();
// 0xA6907d0F353Bc84C1e8C79Bd20eb7E98f8b34E85  usdt sepolia
// 0x694AA1769357215DE4FAC081bf1f309aDC325306 data feed ETH/USD
contract FactoryContract is Ownable{

    using SafeERC20 for IERC20;
    IERC20 public immutable usdt;             // USDT token address 
    uint256 public globalPlatformFee = 0;     // By default platform fee will be 0%  (1% = 100 bps).
    uint256 public slippage = 100;            // By default 1% = 100bps .
    address public fundsHolderAccount;
    address public immutable aggregatorV3;
    address public claimAuthority;

    mapping(bytes32 propertyId => address propertyAddress) public propertiesListed;
    mapping(address propertyAddress =>bool isActive) public propertiesStatus;
    mapping(address adminAddress => bool isActive) public admins;
    mapping(address moderatorAddress => bool isActive) public moderators;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     Events                                 */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    event OwnerChanged(address indexed oldOwner, address indexed newOwner);
    event PropertyListed(bytes32 indexed propertyId, address indexed propertyAddress);
    event Propertydelisted(bytes32 indexed propertyId, address indexed propertyAddress);  
    event PlatformFeeUpdated(address indexed updater, uint256 oldFee, uint256 newFee);
    event FundsHolderAccountChanged(address indexed oldAccount, address indexed newAccount, address indexed updater);
    event ClaimAuthorityChanged(address indexed oldAccount, address indexed newAccount, address indexed updater);
    event FundsWithdrawn(address indexed withdrawer,address indexed account, string indexed tokenType, uint256 amount);
    event SlippageUpdated(address indexed updater, uint256 oldSlippage, uint256 newSlippage);
    event AdminAdded(address indexed adminAddress, address indexed updater);
    event AdminRemoved(address indexed adminAddress, address indexed updater);
    event ModeratorAdded(address indexed moderatorAddress, address indexed updater);
    event ModeratorRemoved(address indexed moderatorAddress, address indexed updater);
    event FundsReceived(address indexed sender, uint256 amount);

    constructor(address usdtAddress,address owner,address  _fundsHolderAccount,address _aggregatorV3)Ownable(owner){
        if(usdtAddress == address(0)||owner == address(0)||_fundsHolderAccount == address(0)||_aggregatorV3 == address(0)){
            revert InvalidAddress();
        }
        usdt = IERC20(usdtAddress);
        fundsHolderAccount = _fundsHolderAccount;
        aggregatorV3 = _aggregatorV3;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     Modifiers                              */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    modifier onlyAdmin() {
        if (!(admins[msg.sender] || owner() == msg.sender)) {
            revert Unauthorized();
        }
        _;
    }
    modifier onlyModerator() {
        if (!(moderators[msg.sender] || admins[msg.sender] || owner() == msg.sender)) {
            revert Unauthorized();
        }
        _;
    } 

    function listProperty(
        string memory name,
        string memory symbol,
        uint256 _totalSupply,
        uint256 _price,
        string memory baseURI,
        uint256 _companySharePercentage,
        address companyShareHolder
        ) external onlyModerator returns (bytes32,address) {

        require(bytes(name).length > 0, "Name cannot be empty");
        require(bytes(symbol).length > 0, "Symbol cannot be empty");
        require(_totalSupply > 0, "Total supply must be greater than zero");
        require(_price > 0, "Price must be greater than zero");
        require(bytes(baseURI).length > 0, "Base URI cannot be empty");
        bytes32 p_id=(keccak256(abi.encodePacked (name,symbol,_totalSupply,_price,baseURI,_companySharePercentage)));
        require(propertiesListed[p_id]==address(0),"Property already listed");
        Property newNFT = new Property(
            name,
            symbol,
            _totalSupply,
            _price,
            baseURI,
            _companySharePercentage,
            companyShareHolder,
            address(usdt),
            payable (address(this)),
            aggregatorV3,
            owner()
            );
        propertiesListed[p_id]=address(newNFT);
        propertiesStatus[address(newNFT)]=true;
        emit PropertyListed(p_id, address(newNFT));
        return (p_id, address(newNFT));
    }

    function delistProperty(bytes32 propertyId) external onlyAdmin { 
        address propertyAddress = propertiesListed[propertyId];
        require(propertyAddress != address(0), "Property does not exist");
        propertiesStatus[propertyAddress] = false;
        emit Propertydelisted(propertyId,propertyAddress);
    }

    function getPropertyDetails(bytes32 propertyId) external view returns (
        string memory name,
        string memory symbol,
        uint256 price,
        string memory baseURI,
        uint256 totalFractions,
        uint256 soldFractions,
        uint256 companySharePercentage
        ) {
        address propertyAddress = propertiesListed[propertyId];
        require(propertyAddress != address(0), "Property does not exist");
        Property nft = Property(propertyAddress);
        return (nft.name(),nft.symbol(),nft.price(),nft._baseTokenURI(),nft.totalFractions(),nft.count(),nft.companySharePercentage());
    }

     function setFundsHolderAccount(address  _newFundsHolderAccount) external onlyOwner {
        if(_newFundsHolderAccount == address(0)){
            revert InvalidAddress();
        }
        address oldFundsHolderAccount = fundsHolderAccount;
        fundsHolderAccount = _newFundsHolderAccount;
        emit FundsHolderAccountChanged(oldFundsHolderAccount, _newFundsHolderAccount, msg.sender);
    }

    function setClaimAuthorityAddress(address  _newClaimAuthority) external onlyOwner {
        if(_newClaimAuthority == address(0)){
            revert InvalidAddress();
        }
        address oldClaimAuthority = claimAuthority;
        claimAuthority = _newClaimAuthority;
        emit ClaimAuthorityChanged(oldClaimAuthority, _newClaimAuthority, msg.sender);
    }
    
    function setGlobalPlatformFee(uint256 _platformFee)external onlyAdmin{
        uint256 oldFee=globalPlatformFee;
        globalPlatformFee=_platformFee;
        emit PlatformFeeUpdated(msg.sender, oldFee, _platformFee);
    }

    function setSlippage(uint256 _newSlippage)external onlyAdmin{
        uint256 oldSlippage = slippage;
        slippage = _newSlippage;
        emit SlippageUpdated(msg.sender,oldSlippage,_newSlippage);
    }

    function setAdmin(address adminAddress, bool isAdmin) external onlyOwner {
        if (adminAddress == address(0)) {
            revert InvalidAddress();
        }
        admins[adminAddress] = isAdmin;

        if (isAdmin) {
            emit AdminAdded(adminAddress, msg.sender);
        } else {
            emit AdminRemoved(adminAddress, msg.sender);
        }
    }

    function setModerator(address moderatorAddress, bool isModerator) external onlyAdmin {
        if (moderatorAddress == address(0)) {
            revert InvalidAddress();
        }
        moderators[moderatorAddress] = isModerator;

        if (isModerator) {
            emit ModeratorAdded(moderatorAddress, msg.sender);
        } else {
            emit ModeratorRemoved(moderatorAddress, msg.sender);
        }   
    }

    function isPropertyActive(bytes32 propertyId) external view returns (bool) {
        address propertyAddress = propertiesListed[propertyId];
        return (propertyAddress != address(0) && propertiesStatus[propertyAddress]);
    }

    function getETHAndUSDTBalances() external view onlyAdmin returns (uint256 ethBalance, uint256 usdtBalance) {
        ethBalance = address(this).balance;
        usdtBalance = usdt.balanceOf(address(this));
    }

    function withdrawETH() external onlyAdmin {
        (bool success, ) = fundsHolderAccount.call{value: address(this).balance}("");
        if(success == false){
            revert TransferFailed();
        }
        emit FundsWithdrawn(msg.sender,fundsHolderAccount,"ETH",address(this).balance);
    } 

    function withdrawUSDT(uint256 amount) external onlyAdmin {
        require(usdt.balanceOf(address(this)) >= amount, "Insufficient USDT balance");
        usdt.safeTransfer(fundsHolderAccount, amount);
        emit FundsWithdrawn(msg.sender,fundsHolderAccount,"USDT",amount);
    }

    // Function to accept ETH
    receive() external payable {
        emit FundsReceived(msg.sender, msg.value);
    }
    
}

