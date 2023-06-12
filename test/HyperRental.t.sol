// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/AccountImpl.sol";
import "../src/AccountRegistry.sol";
import "../src/HyperRental.sol";
import "../src/RentalPackNFT.sol";
import "../src/assets/DemoERC721.sol";
import "../src/assets/DemoERC20.sol";
import "../src/assets/DemoERC1155.sol";

contract HyperRentalTest is Test {
    AccountImpl private accountImpl;
    AccountRegistry private accountRegistry;
    HyperRental private hyperRental;
    RentalPackNFT private rentalPackNFT;
    DemoNFT private demoNFT;
    DemoERC20 private demoERC20;
    DemoERC1155 private demoERC1155;

    address private lender = vm.addr(12345);
    address private renter = vm.addr(6789);
    uint256 private mintedRentalNFTId;
    address private rentalNFTBoundAccount;
    bytes[] private assetDatas;

    function setUp() public {
        accountImpl = new AccountImpl();
        accountRegistry = new AccountRegistry(address(accountImpl));
        rentalPackNFT = new RentalPackNFT();
        hyperRental = new HyperRental(address(accountImpl), address(accountRegistry), address(rentalPackNFT));
        demoNFT = new DemoNFT();
        demoERC20 = new DemoERC20();
        demoERC1155 = new DemoERC1155();
        rentalPackNFT.grantMinterRole(address(hyperRental));
        // accountImpl.setHyperRental(address(hyperRental));
    }

    function testCreateRentalPack() public {
        vm.prank(lender);
        (uint256 tokenId, address account) = hyperRental.createRentalPack();
        assertEq(rentalPackNFT.ownerOf(tokenId), address(hyperRental));
        assertEq(accountRegistry.account(address(rentalPackNFT), tokenId), account);
    }

    function testMintDemoTokens() public {
        // nft
        vm.prank(lender);
        demoNFT.safeMint(lender, "");
        assertEq(demoNFT.ownerOf(0), lender);
        // erc-20
        demoERC20.mint(lender, 10000);
        // erc-1155
        demoERC1155.mint(lender, 0, 5, "0x");
        assertEq(demoERC1155.balanceOf(lender, 0), 5);
    }

    function testLend() public {
        testCreateRentalPack();
        testMintDemoTokens();
        HyperRental.RentalCondition memory condition = HyperRental.RentalCondition(1, 1, 50);
        vm.prank(lender);
        demoNFT.approve(address(hyperRental), 0);
        // vm.prank(lender);
        // demoERC20.approve(address(hyperRental), 100000 * 10 ** demoERC20.decimals());
        vm.prank(lender);
        demoERC1155.setApprovalForAll(address(hyperRental), true);
        assetDatas.push(abi.encode(address(demoNFT), 0, 0, keccak256("ERC721") ));
        // assetDatas.push(abi.encode(address(demoERC20), 0, 100, keccak256("ERC20")));
        assetDatas.push(abi.encode(address(demoERC1155), 0, 3, keccak256("ERC1155")));
        vm.prank(lender);
        hyperRental.lend(mintedRentalNFTId, condition, assetDatas);
    }

    function testCancelLending() public {
        testLend();
        vm.prank(lender);
        hyperRental.cancelLending(0);
        assertEq(demoNFT.ownerOf(0), lender);
    }

    function testRent() public {
        testLend();
        vm.prank(renter);
        vm.deal(renter, 10 ether);
        hyperRental.rent{value: 5 ether}(0, 5, renter);
        assertEq(rentalPackNFT.ownerOf(0), renter);
        assertEq(lender.balance, 5 ether);
    }
}
