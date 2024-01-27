// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "openzeppelin/proxy/ERC1967/ERC1967Proxy.sol";

contract ProxyMarketplace is ERC1967Proxy {

    constructor(
        address _marketplaceV1, 
        bytes memory _data
    ) ERC1967Proxy(_marketplaceV1, _data) {}
    
}