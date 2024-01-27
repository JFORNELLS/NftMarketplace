// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {NftMarketplaceV1} from "../src/NftMarketplaceV1.sol";
import {Poket} from "../src/PoketNft.sol";
import {ProxyMarketplace} from "../src/ProxyMarketplace.sol";

interface IMarketplace {
    function createSellOrder(address _nftAddress, uint48 _tokenId, uint128 _price,uint48 _deadline) external;
    function acceptSellOffer(uint256 _offerId) external payable;
    function sellOffers(uint256 _offerId) external view returns(uint48,uint48,address,uint128,address,bool);
    function cancelSellOffer(uint256 _offerId) external;

}


contract NftMarketplaceV1Test is Test {

    event SellOrderCrwated(
        address indexed offerer, 
        address nft,
        uint256 tokenId,
        uint256 price,
        uint256 dealine,
        bool isEnded
    );
    event SellOfferAccepted(address indexed buyer, Offer offer);

    struct Offer {
        uint48 tokenId;   
        uint48 deadline;            
        address nftAddress;
        uint128 price;
        address offerer;
        bool isEnded;            
    }     

    mapping(uint256 => Offer) public sellOffers;
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
        alice = makeAddr("alice");
        bob = makeAddr("bob"); 
        jack = makeAddr("jack");

        vm.deal(bob, 2 ** 160 -1 wei);
        vm.deal(jack, 2 ** 160 -1 wei);

        poket = new Poket("Poket", "pkt", alice, bob);
        aNft = address(poket);
        nftMarketplaceV1 = new NftMarketplaceV1();
        aMarket = address(nftMarketplaceV1);
        bytes memory data = abi.encodeWithSignature("initialize(string)", "NftMarketplaceV1");
        proxyMarketplace = new ProxyMarketplace(address(nftMarketplaceV1), data);
        aProxy = address(proxyMarketplace);


    }

    function testFuzz_CreateSellOrder(uint128 amount) public {
        // The amount of the 'price' variable is checked from 1 Wei up to the maximum capacity of uint128
        vm.assume(amount > 1 wei);
        // The functions will be called by Alice.
        vm.startPrank(alice);
        // Save Alice's NFTs balance;
        uint256 aliceNftBalance = poket.balanceOf(alice);
        // Approve to the marketplace to move the NFT,
        poket.approve(aProxy, 1);
        // If price is zero, it will revert.
        vm.expectRevert(NftMarketplaceV1.PriceCannotBeZero.selector);
        IMarketplace(aProxy).createSellOrder(aNft, 1, 0 ether, 2 days);
        // If the deadline is less than or equal to block.timestamp, it will revert.
        vm.expectRevert(NftMarketplaceV1.InvalidDeadline.selector);
        IMarketplace(aProxy).createSellOrder(aNft, 1, amount, 0);
        // If msg.sender is not the owner of the NFT, it will revert.
        vm.expectRevert(NftMarketplaceV1.NotTheOwner.selector);
        IMarketplace(aProxy).createSellOrder(aNft, 11, amount, 2 days);
        // Check that the event is emitted correctly.
        vm.expectEmit();
        emit SellOrderCrwated(alice, aNft, 1, amount, 2 days, false);    
        // Alice creates a sell offer.
        IMarketplace(aProxy).createSellOrder(aNft, 1, amount, 2 days);
        // Check that the owner of the NFT is now NftMarketplace."
        assertEq(poket.ownerOf(1), aProxy);
        // Check that the values are stored correctly in the sellOffers mapping.
        (uint48 tokenId, uint48 deadline, address nftAddress, uint128 price,address offerer, bool isEnded) =
        IMarketplace(aProxy).sellOffers(0);
        assertEq(price, amount);
        assertEq(tokenId, 1);
        assertEq(deadline, 2 days);
        assertEq(nftAddress, aNft);
        assertEq(offerer, alice);
        assertEq(isEnded, false);
        // Check that Alice's balance has decreased by 1 NFT.
        assertEq(poket.balanceOf(alice), aliceNftBalance - 1);
        // Check that marketplace is the new owner.
        assertEq(poket.ownerOf(1), aProxy);
     
    }

    function testFuzz_AcceptSellOffer(uint128 amount) public {
        // The amount of the 'price' variable is checked from 1 Wei up to the maximum capacity of uint128
        vm.assume(amount > 1 wei);

        ////////////////// PREPARATION FOR THE TEST \\\\\\\\\\\\\\\\\\\
        
        vm.startPrank(alice);
        //Save Alice's NFT balance
        uint256 aliceNftBalance = poket.balanceOf(alice);
        // Alice cretaes 3 sell Offers.
        poket.approve(aProxy, 9);     
        poket.approve(aProxy, 8);  
        poket.approve(aProxy, 2);
        IMarketplace(aProxy).createSellOrder(aNft, 9, amount, 7 days);
        IMarketplace(aProxy).createSellOrder(aNft, 8, amount, 7 days);
        IMarketplace(aProxy).createSellOrder(aNft, 2, amount, 7 days);
        // Alice cancells one of 3 offers.
        vm.warp(7 days + 1);
        IMarketplace(aProxy).cancelSellOffer(1);
        // Check that Alice's balance has decreased by 2 NFTs.
        assertEq(poket.balanceOf(alice), aliceNftBalance - 2);
         vm.stopPrank();
        // Jack accepts one of two offers.
        vm.prank(jack);
        vm.warp(1 days);
        IMarketplace(aProxy).acceptSellOffer{value: amount}(0);
        // Save the balances of Bob and Alice to check after accepting the offer.
        uint256 bobBal = bob.balance;
        uint256 aliceBal = alice.balance;     
        uint256 bobNftAmount = poket.balanceOf(bob);   

        /////////////////////////////////////////////////////////////////

        // the funcions will be called by Bob.
        vm.startPrank(bob);
        // If Bob tries to accept an order after the deadline has passed, it will revert
        vm.warp(7 days + 1);       
        vm.expectRevert(NftMarketplaceV1.OutOfTime.selector);
        IMarketplace(aProxy).acceptSellOffer{value: amount}(2);
        uint256 incorrectAmount = amount - 1;
        // Bob accepts the offer within the specified time.
        vm.warp(1 days);
        // If the amount of ETH sent is not equal to the price of the order, it will revert.
        vm.expectRevert(NftMarketplaceV1.IncorrectAmount.selector);
        IMarketplace(aProxy).acceptSellOffer{value: incorrectAmount}(2);
        // If Bob tries to accept an offer that has been accepted, it will revert.
        vm.expectRevert(NftMarketplaceV1.OfferIsNotActive.selector);
        IMarketplace(aProxy).acceptSellOffer{value: amount}(0);  
        // If Bob tries to accept an offer that has been cancelled, it will revert.
        vm.expectRevert(NftMarketplaceV1.OfferIsNotActive.selector);
        IMarketplace(aProxy).acceptSellOffer{value: amount}(1);         
        // I store the values to verify that the event is emitted correctly.   
        Offer storage offer = sellOffers[2];
        offer.tokenId = 2;
        offer.deadline = 7 days;
        offer.nftAddress = aNft;
        offer.price = amount;
        offer.offerer = alice;
        offer.isEnded = true;
        vm.expectEmit();
        emit SellOfferAccepted(bob, offer);
        // Bob accepts the offer.
        IMarketplace(aProxy).acceptSellOffer{value: amount}(2);
        // Check that Alice's balance has increased by the amount of the offer.
        assertEq(alice.balance, aliceBal + amount);
        // Check that Bob's balance has decreased by the amount of the offer
        assertEq(bob.balance, bobBal - amount);
        // Check that Bob's NFT balance has increased by 1.
        assertEq(poket.balanceOf(bob), bobNftAmount + 1);
        // Check that Bob is the new owner of the tokenId.
        assertEq(poket.ownerOf(2), bob);
    }

    function test_CancelSellOffer() public {

        ////////////////// PREPARATION FOR THE TEST \\\\\\\\\\\\\\\\\\\

        // Bob creates an offer.
        vm.startPrank(bob);
        poket.approve(aProxy, 11);
        IMarketplace(aProxy).createSellOrder(aNft, 11, 10 ether, 30 days);   
        vm.stopPrank();

        // Alice creates 3 sell orffer.
        vm.startPrank(alice);
        poket.approve(aProxy, 4);
        poket.approve(aProxy, 5);
        poket.approve(aProxy, 6);
        IMarketplace(aProxy).createSellOrder(aNft, 4, 10 ether, 30 days);
        IMarketplace(aProxy).createSellOrder(aNft, 5, 10 ether, 30 days);
        IMarketplace(aProxy).createSellOrder(aNft, 6, 10 ether, 30 days);
        // Alice cancels an offer.
        vm.warp(30 days + 1);
        IMarketplace(aProxy).cancelSellOffer(1);
        vm.stopPrank();

        vm.warp(1 days);
        vm.prank(jack);
        IMarketplace(aProxy).acceptSellOffer{value: 10 ether}(2);
        
        // Save Alice's NFTs balance.
        uint256 aliceNftBalance = poket.balanceOf(alice);

        /////////////////////////////////////////////////////////////////

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
        // If Alice tries to cancel an order that is still within the time frame, it will revert.
        vm.warp(29 days + 1);
        vm.expectRevert(NftMarketplaceV1.OfferIsInTime.selector);
        IMarketplace(aProxy).cancelSellOffer(3);
        // Alice cancels an offer.
        vm.warp(30 days + 1);
        IMarketplace(aProxy).cancelSellOffer(3);    
        // Check that after the cancellation, Alice has one more NFT."
        assertEq(poket.balanceOf(alice), aliceNftBalance + 1);
        // vm.expectRevert(NftMarketplaceV1.OfferIsNotActive.selector);
        // IMarketplace(aProxy).cancelSellOffer(0);
        // vm.warp(10 days + 1);
    }



    
}
