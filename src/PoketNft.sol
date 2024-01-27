// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;
import "openzeppelin/token/ERC721/ERC721.sol";

contract Poket is ERC721 {

    address public alice;
    address public bob;
    uint256 public counter;

    constructor(
        string memory _name, 
        string memory _symbol,
        address _alice,
        address _bob
        ) 
        ERC721(_name, _symbol) 
    {
        
        alice = _alice;
        bob = _bob;
        for (uint256 i; i < 10; i++) {
            counter++;       
            uint256 tokenId = counter;     
            _mint(alice, tokenId);
        }    
        counter++;
        uint256 tokenId = counter;
        _mint(bob, tokenId);    
    }

}