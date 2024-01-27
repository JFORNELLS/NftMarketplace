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


contract NftMarketplaceV1 is UUPSUpgradeable {
                
    ///////////////////////////////////////////////////////////
    ///                     EVENTS                          ///
    ///////////////////////////////////////////////////////////

    event SellOrderCrwated(
        address indexed offerer, 
        address nft,
        uint256 tokenId,
        uint256 price,
        uint256 dealine,
        bool isEnded
    );
    event SellOfferAccepted(address indexed buyer, Offer offer);
    event OfferCancelled(Offer offer);

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

    ///////////////////////////////////////////////////////////
    ///                     STORAGE                         ///
    ///////////////////////////////////////////////////////////

    struct Offer {
        uint48 tokenId;   
        uint48 deadline;            
        address nftAddress;
        uint128 price;
        address offerer;
        bool isEnded;            
    } 

    uint256 sellOfferIdCounter;
    uint256 buyOfferIdCounter;
    mapping(uint256 => Offer) public sellOffers;
    mapping(uint256 => Offer) public buyOffers;
    string public marketplaceName;

    ///////////////////////////////////////////////////////////
    ///                INITILIZA FUNCTION                   ///
    ///////////////////////////////////////////////////////////    

    function initialize(string calldata _marketplaceName) external onlyProxy{
        marketplaceName = _marketplaceName;
    }

    ///////////////////////////////////////////////////////////
    ///                     MODIFIERS                       ///
    ///////////////////////////////////////////////////////////    

    ///////////////////////////////////////////////////////////
    ///                  FACING FUNCTIONS                   ///
    ///////////////////////////////////////////////////////////    

    /** 
    * @notice Creates a sell order for a specific NFT.
    * @param _nftAddress The address of the NFT contract.
    * @param _tokenId The ID of the NFT token to be listed for sale.
    * @param _price The price at which the NFT is listed for sale.
    * @param _deadline The deadline for accepting the offer.     
    * @dev Being mindful of the bit packing in uint variables like 
    * `_tokenId`, `_price`, and `_deadline` is crucial for correct usage.
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
            sellOfferIdCounter++;
        }
        nft.safeTransferFrom(msg.sender, address(this), _tokenId);
        emit SellOrderCrwated(
            msg.sender, 
            _nftAddress, 
            _tokenId, 
            _price, 
            _deadline,
            offer.isEnded
        );
        
    }    

    /**
    * @notice Accepts a sell offer for a specific NFT.
    * @param _offerId The unique identifier of the sell offer.
    * @dev This function transfers the NFT to the buyer and the payment to the seller.
    * It also updates the state of the sell offer to mark it as accepted.
    * The caller must ensure that the offer is still active and the payment is correct.
    * Emits a `SellOfferAccepted` event with details of the accepted offer.
    */   
    function acceptSellOffer(uint256 _offerId) external payable {
        Offer memory offer = sellOffers[_offerId];
        IERC721 nft = IERC721(offer.nftAddress); 
        if (block.timestamp > offer.deadline) revert OutOfTime();        
        if (msg.value != offer.price) revert IncorrectAmount();
        if (offer.isEnded) revert OfferIsNotActive();
        sellOffers[_offerId].isEnded = true;
        nft.safeTransferFrom(address(this), msg.sender, offer.tokenId);
        SafeTransferLib.safeTransferETH(offer.offerer, offer.price);
        emit SellOfferAccepted(msg.sender, sellOffers[_offerId]);
    }

    /**
    * @notice Cancels a sell offer.
    * @param _offerId The unique identifier of the sell offer.
    * @dev This function allows the offerer to cancel a sell offer 
    * and retrieve their NFT if the conditions are met.
    * The offer must not be already ended, the sender must be the owner of the offer, 
    * and the offer must still be within the specified deadline.
    */    
    function cancelSellOffer(uint256 _offerId) external {
        Offer memory offer = sellOffers[_offerId];
        IERC721 nft = IERC721(offer.nftAddress);
        if (offer.isEnded == true) revert OfferIsNotActive();
        if (offer.offerer != msg.sender) revert NotTheOwner();
        if (offer.deadline > block.timestamp) revert OfferIsInTime();
        sellOffers[_offerId].isEnded = true;
        nft.safeTransferFrom(address(this), msg.sender, offer.tokenId);
        emit OfferCancelled(offer);

    }

    ///////////////////////////////////////////////////////////
    ///                 INTERNAL FUNCTIONS                  /// 
    ///////////////////////////////////////////////////////////    

    function _authorizeUpgrade(address newImplementation) internal override {

    }

    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

}               
