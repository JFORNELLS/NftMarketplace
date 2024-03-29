// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "openzeppelin/proxy/utils/UUPSUpgradeable.sol";
import "openzeppelin/interfaces/IERC721.sol";
import "solmate/utils/SafeTransferLib.sol";

    ///////////////////////////////////////////////////////////
    ///                     INTERFACES                      ///
    ///////////////////////////////////////////////////////////
interface IERC721Receiver {

    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external returns (bytes4);
}

 /**
  * @title NFT Marketplace.
  * - Users can:
  * Creates sell and buy offers.
  * Accepts sell and buy offer.
  * Cancels sell and buy offers creted.
  * @dev A decentralized marketplace contract for buying and selling NFTs, 
  * Contract with Upgradeable Proxy with support for upgradeable functionality using a proxy.
  */
contract NftMarketplaceV1 is UUPSUpgradeable {
    
                
    ///////////////////////////////////////////////////////////
    ///                     EVENTS                          ///
    ///////////////////////////////////////////////////////////

    event SellOfferCreated(uint256 indexed offerId, Offer offer);
    event SellOfferAccepted(address indexed buyer, uint256 offerId, Offer offer);
    event SellOfferCancelled(uint256 indexed offerId, Offer offer);
    event BuyOfferCreated(uint256 indexed offerId, Offer offer);    
    event BuyOfferAccepted(address indexed seller, uint256 offerId, Offer offer);
    event BuyOfferCancelled(uint256 indexed offerId, Offer offer);

    ///////////////////////////////////////////////////////////
    ///                     ERRORS                          ///
    ///////////////////////////////////////////////////////////   

    error NotTheOwner(); 
    error PriceCannotBeZero();
    error OfferIsNotActive();
    error OutOfTime();    
    error InvalidDeadline();
    error IncorrectAmount();
    error OfferIsInTime();
    error OnlyAdmin();

    ///////////////////////////////////////////////////////////
    ///                     STORAGE                         ///
    ///////////////////////////////////////////////////////////

    /// @notice Struct defining an offer for buying or selling an NFT on the marketplace.
    struct Offer {
        uint48 tokenId;       // Unique identifier of the NFT.
        uint48 deadline;      // Deadline for the offer to be valid.
        address nftAddress;   // Address of the NFT contract.
        uint128 price;        // Price of the NFT in wei.
        address offerer;      // Address of the user making the offer.
        bool isEnded;         // Flag indicating if the offer has accepted or cancelled.
    } 

    /// @notice Name of the marketplace.
    string public marketplaceName;
    /// @notice Address of the marketplace administrator.
    address public admin;
    /// @notice Counter for sell offer IDs.
    uint256 sellOfferIdCounter;
    /// @notice Counter for buy offer IDs.
    uint256 buyOfferIdCounter;
    /// @notice Mapping of sell offers by their unique IDs.
    mapping(uint256 => Offer) public sellOffers;
    /// @notice Mapping of buy offers by their unique IDs.
    mapping(uint256 => Offer) public buyOffers;

    ///////////////////////////////////////////////////////////
    ///                INITILIZE FUNCTION                   ///
    ///////////////////////////////////////////////////////////    

    /**
     * @dev Initialize the contract with the specified marketplace name.
     * Assign the sender's address as the admin.
     */
    function initialize(string calldata _marketplaceName) external onlyProxy {
        marketplaceName = _marketplaceName;
        admin = msg.sender;
    }

    ///////////////////////////////////////////////////////////
    ///                     MODIFIERS                       ///
    ///////////////////////////////////////////////////////////

    /**
     * @notice Restricts access to functions to only the designated admin.
     */
    modifier onlyAdmin {
        if (msg.sender != admin) revert OnlyAdmin();
        _;
    }
 
    ///////////////////////////////////////////////////////////
    ///                USER FACING FUNCTIONS                ///
    ///////////////////////////////////////////////////////////    

    /** 
     * @notice Creates a sell order for a specific NFT.
     * @param _nftAddress The address of the NFT contract.
     * @param _tokenId The ID of the NFT token to be listed for sale.
     * @param _price The price at which the NFT is listed for sale.
     * @param _deadline The deadline for accepting the offer.     
     * @dev Ensure that the price is greater than zero, the deadline 
     * is later than 'block.timestamo', and the sender is the owner of the NFT. 
     * Being mindful of the bit packing in uint variables like 
     * `_tokenId`, `_price`, and `_deadline` is crucial for correct usage.
     * Emits a `SellOfferCreated` event with details of the accepted offer.
     */
    function createSellOrder(
        address _nftAddress,
        uint48 _tokenId,
        uint128 _price,
        uint48 _deadline
    ) external {
        uint256 offerId = sellOfferIdCounter;
        IERC721 nft = IERC721(_nftAddress);

        if (_price == 0) revert PriceCannotBeZero();
        if (_deadline <= block.timestamp) revert InvalidDeadline();
        if (nft.ownerOf(_tokenId) != msg.sender) revert NotTheOwner();

        Offer storage offer = sellOffers[offerId];
        offer.nftAddress = _nftAddress;
        offer.tokenId = _tokenId;
        offer.price = _price;
        offer.deadline = _deadline;
        offer.offerer = msg.sender;
        unchecked {
            sellOfferIdCounter = offerId + 1;
        }
        nft.safeTransferFrom(msg.sender, address(this), _tokenId);

        emit SellOfferCreated(offerId, offer);   
    }    

    /**
     * @notice Accepts a sell offer for a specific NFT.
     * @param _offerId The unique identifier of the sell offer.
     * @dev This function transfers the NFT to the buyer and the payment to the seller.
     * Updates the state of the sell offer to mark it as accepted.
     * The caller must ensure that the offer is still active, 
     * that msg.value is equal to the offer's price, 
     * and that the offer's time has not elapsed.
     * Emits a `SellOfferAccepted` event with details of the accepted offer.
     */   
    function acceptSellOffer(uint256 _offerId) external payable {
        Offer memory offer = sellOffers[_offerId];
        IERC721 nft = IERC721(offer.nftAddress); 

        if (offer.isEnded) revert OfferIsNotActive();
        if (block.timestamp > offer.deadline) revert OutOfTime();        
        if (msg.value != offer.price) revert IncorrectAmount();

        offer.isEnded = true;
        sellOffers[_offerId] = offer;

        nft.safeTransferFrom(address(this), msg.sender, offer.tokenId);
        SafeTransferLib.safeTransferETH(offer.offerer, offer.price);

        emit SellOfferAccepted(msg.sender, _offerId, offer);
    }

    /**
     * @notice Cancels a sell offer.
     * @dev This function allows the offerer to cancel a sell offer 
     * and retrieve their NFT if the conditions are met.
     * The offer must not be already accepted, the sender must be the owner of the offer, 
     * and the deadline must have elapsed.
     * @param _offerId The unique identifier of the sell offer.
     * Emits a `SellOfferCancelled` event with details of the accepted offer.
     */    
    function cancelSellOffer(uint256 _offerId) external {
        Offer memory offer = sellOffers[_offerId];
        IERC721 nft = IERC721(offer.nftAddress);

        if (offer.isEnded) revert OfferIsNotActive();
        if (offer.offerer != msg.sender) revert NotTheOwner();
        if (offer.deadline > block.timestamp) revert OfferIsInTime();

        offer.isEnded = true;
        sellOffers[_offerId] = offer;

        nft.safeTransferFrom(address(this), msg.sender, offer.tokenId);
        
        emit SellOfferCancelled(_offerId, offer);
    }

    /**
     * @notice Creates a buy offer for a specific NFT.
     * The caller must deposit the ETH of the offer.
     * Ensure thet 'msg.value' is greater than zero, 
     * and the deadline is later than 'block.timestamp'.
     * @param _nftAddress The address of the NFT contract.
     * @param _tokenId The ID of the NFT.
     * @param _deadline The deadline for the offer in seconds since the epoch.
     * @dev Being mindful of the bit packing in uint variables like 
     * `_tokenId`, and `_deadline` is crucial for correct usage.
     * Emits a `BuyOfferCreated` event with details of the accepted offer.
     */    
    function createBuyOffer(
        address _nftAddress,
        uint48 _tokenId,
        uint48 _deadline
    ) external payable {
        uint256 offerId = buyOfferIdCounter;

        if (msg.value == 0) revert PriceCannotBeZero();
        if (_deadline <= block.timestamp) revert InvalidDeadline();

        Offer storage offer = buyOffers[offerId];
        offer.nftAddress = _nftAddress;
        offer.tokenId = _tokenId;
        offer.price = uint128(msg.value);
        offer.deadline = _deadline;
        offer.offerer = msg.sender;
        unchecked {
            buyOfferIdCounter = offerId + 1;
        }
        
        emit BuyOfferCreated(offerId, offer);   
    }

    /**
     * @notice Accepts a buy offer for a specific NFT.
     * Allows the seller to accept a buy offer, transferring the NFT to the buyer
     * and the payment to the seller. The caller must be the owner of the NFT,
     * ensure that the offer is still active, and that the offer's time has not elapsed.
     * @param _offerId The unique identifier of the buy offer.
     * Emits a `BuyOfferAccepted` event with details of the accepted offer.
     */
    function acceptBuyOffer(uint256 _offerId) external {
        Offer memory offer = buyOffers[_offerId];
        IERC721 nft = IERC721(offer.nftAddress);
        address owner = nft.ownerOf(offer.tokenId);

        if (owner != msg.sender) revert NotTheOwner();
        if (offer.isEnded) revert OfferIsNotActive();
        if (offer.deadline < block.timestamp) revert OutOfTime();

        offer.isEnded = true;
        buyOffers[_offerId] = offer;

        nft.safeTransferFrom(msg.sender, offer.offerer, offer.tokenId);
        SafeTransferLib.safeTransferETH(msg.sender, offer.price);

        emit BuyOfferAccepted(msg.sender, _offerId, offer);        
    }
    
    /**
     * @notice Cancels a buy offer.
     * Allows the offerer to cancel a buy offer and retrieve their funds
     * if the conditions are met. The offer must not be already accepted, the sender
     * must be the owner of the offer, and the offer's time must have elapsed.
     * @param _offerId The unique identifier of the buy offer.
     * Emits a `BuyOfferCancelled(` event with details of the accepted offer.
     */
    function cancelBuyOffer(uint256 _offerId) external {
        Offer memory offer = buyOffers[_offerId];

        if (offer.isEnded) revert OfferIsNotActive();
        if (offer.offerer != msg.sender) revert NotTheOwner();
        if (offer.deadline > block.timestamp) revert OfferIsInTime();

        offer.isEnded = true;
        buyOffers[_offerId] = offer;

        SafeTransferLib.safeTransferETH(msg.sender, offer.price);

        emit BuyOfferCancelled(_offerId, offer);
    }

    /**
     * @dev External function to handle ERC721 token received.
     * @return The ERC721 receiver function selector.
     */
    function onERC721Received(
        address,
        address,
        uint256,
        bytes memory
    ) external returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

    ///////////////////////////////////////////////////////////
    ///                 INTERNAL FUNCTIONS                  /// 
    ///////////////////////////////////////////////////////////    

    /**
     * @dev Internal function to authorize an upgrade to a new implementation.
     * @param newImplementation The address of the new implementation.
     * @dev Restricts the authorization to the admin.
     */
    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyAdmin {

    }

    receive() external payable {}

}               
