// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/RentalPackNFT.sol";

contract RentalPackNFTTest is Test {
    RentalPackNFT private rentalPack;

    function setUp() public {
        rentalPack = new RentalPackNFT();
    }

    function testMint() public {
        rentalPack.safeMint(vm.addr(125));
    }

    function testTokenUri() public {
        testMint();
        rentalPack.tokenURI(1);
    }
}
