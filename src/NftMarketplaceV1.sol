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
 * @title NFT Marketplace Contract with Upgradeable Proxy
 * @dev A decentralized marketplace contract for buying and selling NFTs, 
 * with support for upgradeable functionality using a proxy.
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

    struct Offer {
        uint48 tokenId;   
        uint48 deadline;            
        address nftAddress;
        uint128 price;
        address offerer;
        bool isEnded;            
    } 

    string public marketplaceName;
    address public admin;
    uint256 sellOfferIdCounter;
    uint256 buyOfferIdCounter;
    mapping(uint256 => Offer) public sellOffers;
    mapping(uint256 => Offer) public buyOffers;

    ///////////////////////////////////////////////////////////
    ///                INITILIZE FUNCTION                   ///
    ///////////////////////////////////////////////////////////    

    function initialize(string calldata _marketplaceName) external onlyProxy {
        marketplaceName = _marketplaceName;
        admin = msg.sender;
    }

    ///////////////////////////////////////////////////////////
    ///                     MODIFIERS                       ///
    ///////////////////////////////////////////////////////////

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
        emit SellOfferCreated(offerId, offer);   
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
        offer.isEnded = true;
        sellOffers[_offerId] = offer;
        nft.safeTransferFrom(address(this), msg.sender, offer.tokenId);
        SafeTransferLib.safeTransferETH(offer.offerer, offer.price);
        emit SellOfferAccepted(msg.sender, _offerId, offer);
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
    * @param _nftAddress The address of the NFT contract.
    * @param _tokenId The ID of the NFT.
    * @param _deadline The deadline for the offer in seconds since the epoch.
    * @dev Being mindful of the bit packing in uint variables like 
    * `_tokenId`, and `_deadline` is crucial for correct usage.
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
            buyOfferIdCounter++;
        }
        emit BuyOfferCreated(offerId, offer);   
    }
    
    /**
    * @notice Accepts a buy offer for a specific NFT.
    * @param _offerId The unique identifier of the buy offer.
    * @dev Allows the seller to accept a buy offer, transferring the NFT to the buyer
    * and the payment to the seller.
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
    * @param _offerId The unique identifier of the buy offer.
    * @dev Allows the offerer to cancel a buy offer and retrieve their funds
    * if the conditions are met. The offer must not be already ended, the sender
    * must be the owner of the offer, and the offer must still be within the specified deadline.
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
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

    ///////////////////////////////////////////////////////////
    ///                 INTERNAL FUNCTIONS                  /// 
    ///////////////////////////////////////////////////////////    

    /**
    * @dev Internal function to authorize an upgrade to a new implementation.
    * @param newImplementation The address of the new implementation.
    * @dev Restricts the authorization to the proxy owner (onlyProxy) and the admin.
    */
    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyProxy onlyAdmin {

    }



}               
