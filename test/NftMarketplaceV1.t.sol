// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {NftMarketplaceV1} from "../src/NftMarketplaceV1.sol";
import {Poket} from "../src/PoketNft.sol";
import {ProxyMarketplace} from "../src/ProxyMarketplace.sol";

    ///////////////////////////////////////////////////////////
    ///                     INTERFACES                      ///
    ///////////////////////////////////////////////////////////
interface IMarketplace {
    function createSellOrder(
        address _nftAddress, 
        uint48 _tokenId, 
        uint128 _price,
        uint48 _deadline
    ) external;
    
    function sellOffers(
        uint256 _offerId
    ) external view returns(uint48,uint48,address,uint128,address,bool);
    function buyOffers(
        uint256 _offerId
    ) external view returns(uint48,uint48,address,uint128,address,bool);
    function createBuyOffer(
        address _nftAddress, 
        uint48 _tokenId, 
        uint48 _deadline
    ) external payable;
    function cancelSellOffer(uint256 _offerId) external;
    function acceptSellOffer(uint256 _offerId) external payable;
    function acceptBuyOffer(uint256 _offerId) external;
    function cancelBuyOffer(uint256 _offerId) external;
    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external returns (bytes4);
}


contract NftMarketplaceV1Test is Test {

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

    mapping(uint256 => Offer) public sellOffers;
    mapping(uint256 => Offer) public buyOffers;
    NftMarketplaceV1 public nftMarketplaceV1;
    Poket public poket;
    ProxyMarketplace public proxyMarketplace;
    address public alice;
    address public bob;
    address public jack;
    address public aMarket;
    address public aNft;
    address public aProxy;



    function setUp() public {
        // Address creation for Alice, Bob, Jack.
        alice = makeAddr("alice");
        bob = makeAddr("bob"); 
        jack = makeAddr("jack");
        // Give ETH to Bob and Jack
        vm.deal(bob, 2 ** 160 -1 wei);
        vm.deal(jack, 2 ** 160 -1 wei);
        // Deploy an NFT contract for testing the NftMarketplace
        // and give 10 NFT to Alice and 1 NFT to Bob.
        poket = new Poket("Poket", "pkt", alice, bob);
        // Deploy NftMarketplace contract.
        nftMarketplaceV1 = new NftMarketplaceV1();
        //Save the signature of the 'initialize' function.
        bytes memory data = abi.encodeWithSignature("initialize(string)", "NftMarketplaceV1");
        // Deploy the Proxy and initialize the implementation NftMarketplace.
        proxyMarketplace = new ProxyMarketplace(address(nftMarketplaceV1), data);
        // Convert variables from contract variables to address variables.
        aMarket = address(nftMarketplaceV1);
        aNft = address(poket);
        aProxy = address(proxyMarketplace);
    }

    // In this function, it will be executed 1000 times with different amounts.
    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_CreateSellOrder(uint128 amount) public {
        // --- snip ---

        ////////////////// SETUP \\\\\\\\\\\\\\\\\\\

        // The amount of the 'price' is checked from 0.00001 ETH up to the maximum capacity of uint128.
        vm.assume(amount >  0.00001 ether);
        // I store the values to verify that the event is emitted correctly.   
        Offer storage offer = sellOffers[0];
        offer.tokenId = 1;
        offer.deadline = 2 days;
        offer.nftAddress = aNft;
        offer.price = amount;
        offer.offerer = alice;
        offer.isEnded = false;   

        ////////////////// TEST \\\\\\\\\\\\\\\\\\\

        // The functions will be called by Alice.      
        vm.startPrank(alice);
        // Approve to the marketplace to move the NFT,
        poket.approve(aProxy, 1);
        // If price is zero, it will revert.
        vm.expectRevert(NftMarketplaceV1.PriceCannotBeZero.selector);
        IMarketplace(aProxy).createSellOrder(aNft, 1, 0 ether, 2 days);
        // If the deadline is zero, it will revert.
        vm.expectRevert(NftMarketplaceV1.InvalidDeadline.selector);
        IMarketplace(aProxy).createSellOrder(aNft, 1, amount, 0);
        // If the deadline is equal to "block.timestamp", it will revert.
        vm.expectRevert(NftMarketplaceV1.InvalidDeadline.selector);
        IMarketplace(aProxy).createSellOrder(aNft, 1, amount, 0);
        // If msg.sender is not the owner of the NFT, it will revert.
        vm.expectRevert(NftMarketplaceV1.NotTheOwner.selector);
        IMarketplace(aProxy).createSellOrder(aNft, 11, amount, 2 days);
        // Check that the event is emitted correctly.
        vm.expectEmit();
        emit SellOfferCreated(0, offer);    
        // Alice creates a sell offer.
        IMarketplace(aProxy).createSellOrder(aNft, 1, amount, 2 days);
        // Check that the owner of the NFT is now NftMarketplace."
        assertEq(poket.ownerOf(1), aProxy);
        // I query the values stored in the mapping sellOffers.
        (
            uint48 tokenId, 
            uint48 deadline, 
            address nftAddress, 
            uint128 price,
            address offerer, 
            bool isEnded
        ) = IMarketplace(aProxy).sellOffers(0);
         // Check that the values are stored correctly in the sellOffers mapping.
        assertEq(price, amount);
        assertEq(tokenId, 1);
        assertEq(deadline, 2 days);
        assertEq(nftAddress, aNft);
        assertEq(offerer, alice);
        assertEq(isEnded, false);
        // Check that marketplace is the new owner.
        assertEq(poket.ownerOf(1), aProxy);
     
    }

    // In this function, it will be executed 1000 times with different amounts.
    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_AcceptSellOffer(uint128 amount) public {
        // --- snip ---

        ////////////////// SETUP \\\\\\\\\\\\\\\\\\\

        // The amount of the 'price' variable is checked from 0.0001 ETH up to the maximum capacity of uint128.
        vm.assume(amount > 0.00001 ether);

        // Alice cretaes 3 sell Offers.
        vm.startPrank(alice);
        poket.approve(aProxy, 9);     
        poket.approve(aProxy, 8);  
        poket.approve(aProxy, 2);
        IMarketplace(aProxy).createSellOrder(aNft, 9, amount, 7 days);
        IMarketplace(aProxy).createSellOrder(aNft, 8, amount, 7 days);
        IMarketplace(aProxy).createSellOrder(aNft, 2, amount, 7 days);
        // Alice cancells one of 3 offers.
        vm.warp(7 days + 1);
        IMarketplace(aProxy).cancelSellOffer(1);
        vm.stopPrank();
        // Jack accepts one of two offers.
        vm.prank(jack);
        vm.warp(1 days);
        IMarketplace(aProxy).acceptSellOffer{value: amount}(0);
        // Save Bob's and Alic's balances..
        uint256 bobBal = bob.balance;
        uint256 aliceBal = alice.balance;     
        // Incorrect amount.
        uint256 incorrectAmount = amount - 1;
        // I store the values of the with id 2 offer to verify that the event is emitted correctly.   
        Offer storage offer = sellOffers[2];
        offer.tokenId = 2;
        offer.deadline = 7 days;
        offer.nftAddress = aNft;
        offer.price = amount;
        offer.offerer = alice;
        offer.isEnded = true;        

        ////////////////// TEST \\\\\\\\\\\\\\\\\\\

        // the funcions will be called by Bob.
        vm.startPrank(bob);   
        // I set the time outside the limits of the offer.
        vm.warp(7 days + 1);       
        // If Bob tries to accept an order after the deadline has passed, it will revert.
        vm.expectRevert(NftMarketplaceV1.OutOfTime.selector);
        IMarketplace(aProxy).acceptSellOffer{value: amount}(2);
        // I set the time within the limits of the offer.
        vm.warp(1 days);
        // If the amount of ETH sent is not equal to the price of the offer, it will revert.
        vm.expectRevert(NftMarketplaceV1.IncorrectAmount.selector);
        IMarketplace(aProxy).acceptSellOffer{value: incorrectAmount}(2);
        // If Bob tries to accept an offer that has been accepted, it will revert.
        vm.expectRevert(NftMarketplaceV1.OfferIsNotActive.selector);
        IMarketplace(aProxy).acceptSellOffer{value: amount}(0);  
        // If Bob tries to accept an offer that has been cancelled, it will revert.
        vm.expectRevert(NftMarketplaceV1.OfferIsNotActive.selector);
        IMarketplace(aProxy).acceptSellOffer{value: amount}(1);         
        // Check that the event is emitted correctly.
        vm.expectEmit();
        emit SellOfferAccepted(bob, 2, offer);
        // Bob accepts the offer.
        IMarketplace(aProxy).acceptSellOffer{value: amount}(2);
        // Check that Alice's balance has increased by the amount of the offer.
        assertEq(alice.balance, aliceBal + amount);
        // Check that Bob's balance has decreased by the amount of the offer
        assertEq(bob.balance, bobBal - amount);
        // Check that Bob is the new owner of the NFT.
        assertEq(poket.ownerOf(2), bob);
    }

    // In this function, it will be executed 1000 times with different amounts.
    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_CancelSellOffer(uint128 amount) public {
        // --- snip ---

        ////////////////// SETUP \\\\\\\\\\\\\\\\\\\

        // The amount of the 'price' variable is checked from 0.0001 ETH up to the maximum capacity of uint128.
        vm.assume(amount > 0.00001 ether);

        // Bob creates an offer.
        vm.startPrank(bob);
        poket.approve(aProxy, 11);
        IMarketplace(aProxy).createSellOrder(aNft, 11, amount, 30 days);   
        vm.stopPrank();

        // Alice creates 3 sell offers.
        vm.startPrank(alice);
        poket.approve(aProxy, 4);
        poket.approve(aProxy, 5);
        poket.approve(aProxy, 6);
        IMarketplace(aProxy).createSellOrder(aNft, 4, amount, 30 days);
        IMarketplace(aProxy).createSellOrder(aNft, 5, amount, 30 days);
        IMarketplace(aProxy).createSellOrder(aNft, 6, amount, 30 days);
        // Alice cancels the first offer.
        vm.warp(30 days + 1);
        IMarketplace(aProxy).cancelSellOffer(1);
        vm.stopPrank();
        // Jack accepts the second offer.
        vm.warp(1 days);
        vm.prank(jack);
        IMarketplace(aProxy).acceptSellOffer{value: amount}(2);
        // I store the values of the offer with id 3 to verify that the event is emitted correctly.
        Offer storage offer = sellOffers[3];
        offer.tokenId = 6;
        offer.deadline = 30 days;
        offer.nftAddress = aNft;
        offer.price = amount;
        offer.offerer = alice;
        offer.isEnded = true;        

        ////////////////// TEST \\\\\\\\\\\\\\\\\\\

        vm.startPrank(alice);
        // If Alice tries to cancel an offer that has been accepted, it will revert.
        vm.expectRevert(NftMarketplaceV1.OfferIsNotActive.selector);
        IMarketplace(aProxy).cancelSellOffer(2);
        // Alice tries to cancel an offer that has been cancelled, it will revert.
        vm.expectRevert(NftMarketplaceV1.OfferIsNotActive.selector);
        IMarketplace(aProxy).cancelSellOffer(1);
        // If Alice tries to cancel an offer that is not hers, it will revert.
        vm.expectRevert(NftMarketplaceV1.NotTheOwner.selector);
        IMarketplace(aProxy).cancelSellOffer(0);        
        // I set the time outside the limits of the offer.
        vm.warp(29 days + 1);
        // If Alice tries to cancel an order that is still within the time frame, it will revert.
        vm.expectRevert(NftMarketplaceV1.OfferIsInTime.selector);
        IMarketplace(aProxy).cancelSellOffer(3);
        // I set the time within the limits of the offer.
        vm.warp(30 days + 1);
        // Check that the event is emitted correctly.
        vm.expectEmit();
        emit SellOfferCancelled(3, offer);
        // Alice cancels an offer.
        IMarketplace(aProxy).cancelSellOffer(3);    
        // Check that alice is the owner again.
        assertEq(poket.ownerOf(6), alice);
    }

    // In this function, it will be executed 1000 times with different amounts.
    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_CreateBuyOffer(uint128 amount) public {
        // --- snip ---

        ////////////////// SETUP \\\\\\\\\\\\\\\\\

        // The amount of the "price" is checked from 0.00001 ETH up to the maximum capacity of uint128.
        vm.assume(amount >  0.00001 ether);
        // Save the balances of Jack and marketplace to check after accepting the offer.
        uint256 jackBalance = jack.balance;
        uint256 marketplaceBalance = aProxy.balance;
        // I store the values to verify that the event is emitted correctly.
        Offer storage offer = buyOffers[0];
        offer.tokenId = 7;
        offer.deadline = 21 days;
        offer.nftAddress = aNft;
        offer.price = amount;
        offer.offerer = jack;    

        ////////////////// TEST \\\\\\\\\\\\\\\\\\\

        // The function will be called by Jack.
        vm.startPrank(jack);
        // If price is zero, it will revert.
        vm.expectRevert(NftMarketplaceV1.PriceCannotBeZero.selector);
        IMarketplace(aProxy).createBuyOffer{value: 0}(aNft, 7, 4 days);
        // If the deadline is zero,it will revert.
        vm.expectRevert(NftMarketplaceV1.InvalidDeadline.selector);
        IMarketplace(aProxy).createBuyOffer{value: amount}(aNft, 7, 0);
        // If the deadline is equal to "block.timestamp", it will revert.
        vm.expectRevert(NftMarketplaceV1.InvalidDeadline.selector);
        IMarketplace(aProxy).createBuyOffer{value: amount}(aNft, 7, 1);
        // Check that the event is emitted correctly.
        vm.expectEmit();
        emit BuyOfferCreated(0, offer);
        // Jack creates a buy offer.
        IMarketplace(aProxy).createBuyOffer{value: amount}(aNft, 7, 21 days);
        // I query the values stored in the mapping buyOffers.
        (
            uint48 tokenId, 
            uint48 deadline, 
            address nftAddress, 
            uint128 price,
            address offerer, 
            bool isEnded
        ) = IMarketplace(aProxy).buyOffers(0);
         // Check that the values are stored correctly in the buyOffers mapping.
        assertEq(price, amount);
        assertEq(tokenId, 7);
        assertEq(deadline, 21 days);
        assertEq(nftAddress, aNft);
        assertEq(offerer, jack);
        assertEq(isEnded, false);
        // Check that Jack's balance has decreasseb by amount.
        assertEq(jack.balance, jackBalance - amount);
        // Check that marketplace's balance has increassed by amount.
        assertEq(aProxy.balance, marketplaceBalance + amount);
    }

    // In this function, it will be executed 1000 times with different amounts.
    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_AcceptBuyOffer(uint128 amount) public {
        // --- snip ---

        ////////////////// SETUP \\\\\\\\\\\\\\\\\

        // The amount of the "price" is checked from 0.00001 ETH up to the maximum capacity of uint128.
        vm.assume(amount >  0.00001 ether);

        vm.startPrank(jack);
        // Jack creates an offer for bob.
        IMarketplace(aProxy).createBuyOffer{value: amount}(aNft, 11, 4 days);
        // jack creates 2 offers for Alice.
        IMarketplace(aProxy).createBuyOffer{value: amount}(aNft, 1, 4 days);
        IMarketplace(aProxy).createBuyOffer{value: amount}(aNft, 2, 10 days);
        // After the time limit has passed, Jack cancels the first offer.
        vm.warp(5 days);
        IMarketplace(aProxy).cancelBuyOffer(1);
        vm.stopPrank();
        // Ssave Alice's and markeplace's balance.
        uint256 aliceBalance = alice.balance;
        uint256 marketplaceBalance = aProxy.balance;
        // I store the values to verify that the event is emitted correctly.
        Offer storage offer = buyOffers[2];
        offer.tokenId = 2;
        offer.deadline = 10 days;
        offer.nftAddress = aNft;
        offer.price = amount;
        offer.offerer = jack;
        offer.isEnded = true;

        ////////////////// TEST \\\\\\\\\\\\\\\\\\\

        vm.startPrank(alice);
        // If Alice tries to accept an offer when she's not the owner of the NFT, it will revert.
        vm.expectRevert(NftMarketplaceV1.NotTheOwner.selector);
        IMarketplace(aProxy).acceptBuyOffer(0);
        // If the offer has benn cancelled, it will revert.
        vm.expectRevert(NftMarketplaceV1.OfferIsNotActive.selector);
        IMarketplace(aProxy).acceptBuyOffer(1);
        // If Alice tries to accept an offer that deadline has passed, it will revert.
        vm.warp(10 days + 1);
        vm.expectRevert(NftMarketplaceV1.OutOfTime.selector);
        IMarketplace(aProxy).acceptBuyOffer(2);
        //I set the time within the limits of the offer.
        vm.warp(6 days);
        poket.approve(aProxy, 2);
        // Check that the event is emitted correctly.
        vm.expectEmit();
        emit BuyOfferAccepted(alice, 2, offer);
        // Alice accepts the offer.
        
        IMarketplace(aProxy).acceptBuyOffer(2);
        // check that the new owner is Jack.
        assertEq(poket.ownerOf(2), jack);
        // Check that Alice's balance has increased by amount.
        assertEq(alice.balance, aliceBalance + amount);
        // Check that maketplace balance has decreassed by amount.
        assertEq(aProxy.balance, marketplaceBalance - amount);
    }

    // In this function, it will be executed 1000 times with different amounts.
    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_CancelBuyOffer(uint128 amount) public {
        // --- snip ---

        ////////////////// SETUP \\\\\\\\\\\\\\\\\

        // The amount of the "price" is checked from 0.00001 ETH up to the maximum capacity of uint128.
        vm.assume(amount >  0.00001 ether);
        // Bobb creates an offer for Alice;
        vm.prank(bob);
        IMarketplace(aProxy).createBuyOffer{value: amount}(aNft, 1, 4 days);
        // Jack creates 3 offer for Alice.
        vm.startPrank(jack);
        IMarketplace(aProxy).createBuyOffer{value: amount}(aNft, 5, 4 days);
        IMarketplace(aProxy).createBuyOffer{value: amount}(aNft, 6, 8 days);
        IMarketplace(aProxy).createBuyOffer{value: amount}(aNft, 7, 10 days);
        // Jack cancels the first offer.
        vm.warp(4 days + 1);
        IMarketplace(aProxy).cancelBuyOffer(1);
        vm.stopPrank();
        // Alice accepts the second offer.
        vm.startPrank(alice);
        poket.approve(aProxy, 6);
        IMarketplace(aProxy).acceptBuyOffer(2);
        vm.stopPrank();
        // I store the values to verify that the event is emitted correctly.
        Offer storage offer = buyOffers[3];
        offer.tokenId = 7;
        offer.deadline = 10 days;
        offer.nftAddress = aNft;
        offer.price = amount;
        offer.offerer = jack;
        offer.isEnded = true;
        // Save Jack's and the marketplace's balances.
        uint256 jackBalance = jack.balance;
        uint256 marketplaceBalance = aProxy.balance;

        ////////////////// TEST \\\\\\\\\\\\\\\\\\\
        // The functions will be called by Jack.
        vm.startPrank(jack);
        // If Jack tries to cancel an offer that has been cancelled, it will revert.
        vm.expectRevert(NftMarketplaceV1.OfferIsNotActive.selector);
        IMarketplace(aProxy).cancelBuyOffer(1);
        // If Jack tries to cancel an offer that has been accepted, it will revert.
        vm.expectRevert(NftMarketplaceV1.OfferIsNotActive.selector);
        IMarketplace(aProxy).cancelBuyOffer(2);
        // If Jack tries to cancel an offer of which he is not the owner, it will revert.
        vm.expectRevert(NftMarketplaceV1.NotTheOwner.selector);
        IMarketplace(aProxy).cancelBuyOffer(0);
        // If Alice tries to cancel an offer that is still within the time frame, it will revert
        vm.expectRevert(NftMarketplaceV1.OfferIsInTime.selector);
        IMarketplace(aProxy).cancelBuyOffer(3);
        // I set the time within the limits of the offer.
        vm.warp(10 days + 1);
        // Check that the event is emitted correctly.
        vm.expectEmit();
        emit BuyOfferCancelled(3, offer);
        // Jack cancels the third offer.
        IMarketplace(aProxy).cancelBuyOffer(3);
        // Check that Jack's balance has increassed by amount.
        assertEq(jack.balance, jackBalance + amount);
        // Check that marketplace's balance has decreassed by amount.
        assertEq(aProxy.balance, marketplaceBalance - amount);
    }

    function test_AuthorizeUpgrade() public {
        // If someone tries to upgrade the proxy to a new implementation and is not the administrator, it will revert.
        vm.prank(jack);
        vm.expectRevert(NftMarketplaceV1.OnlyAdmin.selector);
        (bool ok, ) = aProxy.call(abi.encodeWithSignature(
            "upgradeToAndCall(address,bytes)", address(nftMarketplaceV1), "")
        );
        require(ok, "");
        // The administrator calls 2upgradeToAndCall' function.
        (bool ok1, ) = aProxy.call(abi.encodeWithSignature(
            "upgradeToAndCall(address,bytes)", address(nftMarketplaceV1), "")
        );
        require(ok1, "");

    }







    
}
