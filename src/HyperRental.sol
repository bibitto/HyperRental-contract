// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

/* ========== IMPORTS ========== */
import "openzeppelin-contracts/utils/introspection/IERC165.sol";
import "openzeppelin-contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/token/ERC721/IERC721.sol";
import "openzeppelin-contracts/token/ERC1155/IERC1155.sol";
import "openzeppelin-contracts/token/ERC721/utils/ERC721Holder.sol";
import "chainlink/interfaces/automation/AutomationCompatibleInterface.sol";
import "./interfaces/IERC3525.sol";
import "./interfaces/IRegistry.sol";
import "./interfaces/IAccount.sol";
import "./RentalPackNFT.sol";

contract HyperRental is ERC721Holder, AutomationCompatibleInterface {
    /* ========== STATE VARIABLES ========== */
    address public tokenBoundAccountImplement;

    address public tokenBoundAccountRegistry;

    address public rentalPackAddress;

    /* ========== MAPPINGS ========== */
    mapping(uint256 => uint256[]) private _timestampToRentalPackTokenIds;

    /* ========== CONSTRUCTOR ========== */
    constructor(address tokenBoundAccountImplement_, address tokenBoundAccountRegistry_, address rentalPackAddress_) {
        tokenBoundAccountImplement = tokenBoundAccountImplement_;
        tokenBoundAccountRegistry = tokenBoundAccountRegistry_;
        rentalPackAddress = rentalPackAddress_;
    }

    /* ========== MUTATIVE FUNCTIONS ========== */
    function createRentalPack() public returns (uint256, address) {
        uint256 tokenId = RentalPackNFT(rentalPackAddress).safeMint(address(this));
        address tokenBoundAddress = IRegistry(tokenBoundAccountRegistry).createAccount(rentalPackAddress, tokenId);
        RentalPackNFT(rentalPackAddress).recordRentalPackOwner(tokenId, msg.sender);
        RentalPackNFT(rentalPackAddress).recordTokenBoundAccount(tokenId, tokenBoundAddress);
        RentalPackNFT(rentalPackAddress).updateOwnedIds(msg.sender, tokenId);
        return (tokenId, tokenBoundAddress);
    }

    // function _batchDepositAssets(uint256 rentalPackTokenId, bytes[] memory assetDatas) private {
    //     address tokenBoundAddress = IRegistry(tokenBoundAccountRegistry).account(rentalPackAddress, rentalPackTokenId);
    //     for (uint256 i; i < assetDatas.length; i++) {
    //         (address contractAddress, uint256 tokenId, uint256 amount, bytes32 dataType) =
    //             abi.decode(assetDatas[i], (address, uint256, uint256, bytes32));

    //         if (dataType == keccak256("ERC20")) {
    //             require(
    //                 IERC20(contractAddress).allowance(msg.sender, address(this)) >= amount,
    //                 "ERC20: HyperRental is not approved for the given amount"
    //             );
    //             IERC20(contractAddress).transfer(tokenBoundAddress, amount);
    //         } else if (dataType == keccak256("ERC721")) {
    //             require(
    //                 IERC721(contractAddress).getApproved(tokenId) == address(this),
    //                 "ERC721: HyperRental is not approved"
    //             );
    //             IERC721(contractAddress).transferFrom(msg.sender, tokenBoundAddress, tokenId);
    //         } else if (dataType == keccak256("ERC1155")) {
    //             require(
    //                 IERC1155(contractAddress).isApprovedForAll(msg.sender, address(this)),
    //                 "ERC1155: HyperRental is not approved"
    //             );
    //             IERC1155(contractAddress).safeTransferFrom(msg.sender, tokenBoundAddress, tokenId, amount, "0x");
    //         } else if (dataType == keccak256("ERC3525")) {
    //             require(
    //                 IERC3525(contractAddress).allowance(tokenId, address(this)) >= amount,
    //                 "ERC3525: HyperRental is not approved for the given amount"
    //             );
    //             IERC3525(contractAddress).transferFrom(tokenId, tokenBoundAddress, amount);
    //         } else {
    //             revert NotSupportedToken(contractAddress);
    //         }
    //     }
    // }

    function _lockTokenBoundAccount(uint256 rentalPackTokenId) private {
        address tokenBoundAccount = IRegistry(tokenBoundAccountRegistry).account(rentalPackAddress, rentalPackTokenId);
        IAccount(tokenBoundAccount).lock();
    }

    function lend(uint256 rentalPackTokenId, RentalPackNFT.RentalCondition memory rentalCondition) public {
        require(
            RentalPackNFT(rentalPackAddress).checkRentalPackOwner(rentalPackTokenId) == msg.sender,
            "msg.sender is not rentalPack owner"
        );
        _lockTokenBoundAccount(rentalPackTokenId);
        RentalPackNFT(rentalPackAddress).updataRentalCondition(rentalPackTokenId, rentalCondition);
        RentalPackNFT(rentalPackAddress).updataStatus(rentalPackTokenId, RentalPackNFT.Status.Listed);
        emit Lend(rentalPackAddress, rentalPackTokenId, rentalCondition);
    }

    function _unlockTokenBoundAccount(uint256 rentalPackTokenId) private {
        address tokenBoundAccount = IRegistry(tokenBoundAccountRegistry).account(rentalPackAddress, rentalPackTokenId);
        IAccount(tokenBoundAccount).unlock();
    }

    function _delistRentalPack(uint256 rentalPackTokenId) private {
        RentalPackNFT(rentalPackAddress).updataStatus(rentalPackTokenId, RentalPackNFT.Status.NotListed);
    }

    function _refreshRentalRecord(uint256 rentalPackTokenId) private {
        RentalPackNFT(rentalPackAddress).updataRentalCondition(
            rentalPackTokenId, RentalPackNFT.RentalCondition(0, 0, 0)
        );
        if (RentalPackNFT(rentalPackAddress).checkRentalExpireTimestamp(rentalPackTokenId) != 0) {
            RentalPackNFT(rentalPackAddress).updataRentalExpireTimestamp(rentalPackTokenId, 0);
        }
    }

    function cancelLending(uint256 rentalPackTokenId) external {
        require(
            RentalPackNFT(rentalPackAddress).checkRentalPackOwner(rentalPackTokenId) == msg.sender,
            "msg.sender is not a lender"
        );
        require(
            RentalPackNFT(rentalPackAddress).checkStatus(rentalPackTokenId) == uint256(RentalPackNFT.Status.Listed),
            "the rental pack is not listed"
        );
        require(
            RentalPackNFT(rentalPackAddress).checkRentalExpireTimestamp(rentalPackTokenId) == 0,
            "cannot cancel lending when the rental pack is rented "
        );
        _delistRentalPack(rentalPackTokenId);
        _refreshRentalRecord(rentalPackTokenId);
        _unlockTokenBoundAccount(rentalPackTokenId);
        emit LendingCanceled(rentalPackAddress, rentalPackTokenId);
    }

    function rent(uint256 rentalPackTokenId, uint256 rentalHour, address receiver) public payable {
        require(
            RentalPackNFT(rentalPackAddress).checkStatus(rentalPackTokenId) == uint256(RentalPackNFT.Status.Listed),
            "the rental pack is not listed"
        );
        require(
            RentalPackNFT(rentalPackAddress).checkRentalExpireTimestamp(rentalPackTokenId) == 0,
            "anyone has already rented"
        );
        RentalPackNFT.RentalCondition memory condition =
            RentalPackNFT(rentalPackAddress).checkRentalCondition(rentalPackTokenId);
        if (condition.feePerHour * rentalHour != msg.value) {
            revert InvalidRentalFee(condition.feePerHour * rentalHour, msg.value);
        }
        require(condition.minHour <= rentalHour, "the given rental hour is too shoot");
        require(condition.maxHour >= rentalHour, "the given rental hour is too long");
        // update listing status
        RentalPackNFT(rentalPackAddress).updataStatus(rentalPackTokenId, RentalPackNFT.Status.Rented);
        // update expire timestamp info
        uint256 rentalExpireTimestamp = block.timestamp + (rentalHour * 1 hours);
        RentalPackNFT(rentalPackAddress).updataRentalExpireTimestamp(rentalPackTokenId, rentalExpireTimestamp);
        _timestampToRentalPackTokenIds[rentalExpireTimestamp].push(rentalPackTokenId);
        // transfer fee to TBA
        address tokenBoundAddress = RentalPackNFT(rentalPackAddress).checkTokenBoundAccount(rentalPackTokenId);
        (bool success, bytes memory data) = tokenBoundAddress.call{value: msg.value}("");
        require(success, "Failed to send Ether to NFT owner");
        // tranffer rentalPack NFT to receiver address
        IERC721(rentalPackAddress).safeTransferFrom(address(this), receiver, rentalPackTokenId, "0x");
        emit Rent(rentalPackAddress, rentalPackTokenId, rentalHour);
    }

        function withdrawAssets(uint256 rentalPackTokenId, bytes[] calldata assetDatas) public {
        require(
            RentalPackNFT(rentalPackAddress).checkRentalPackOwner(rentalPackTokenId) == msg.sender, "invalid msg.sender"
        );
        require(
            RentalPackNFT(rentalPackAddress).checkStatus(rentalPackTokenId) == uint256(RentalPackNFT.Status.NotListed),
            'the status should be "NotListed"'
        );
        address tokenBoundAddress = IRegistry(tokenBoundAccountRegistry).account(rentalPackAddress, rentalPackTokenId);
        for (uint256 i; i < assetDatas.length; i++) {
            (address contractAddress, uint256 tokenId, uint256 amount, bytes32 dataType) =
                abi.decode(assetDatas[i], (address, uint256, uint256, bytes32));
            if (dataType == keccak256("ERC20")) {
                IAccount(tokenBoundAddress).executeCall(
                    contractAddress,
                    0,
                    abi.encodeWithSignature(
                        "transferFrom(address,address,uint256)", tokenBoundAddress, msg.sender, amount
                    )
                );
            } else if (dataType == keccak256("ERC721")) {
                IAccount(tokenBoundAddress).executeCall(
                    contractAddress,
                    0,
                    abi.encodeWithSignature(
                        "transferFrom(address,address,uint256)", tokenBoundAddress, msg.sender, tokenId
                    )
                );
            } else if (dataType == keccak256("ERC1155")) {
                IAccount(tokenBoundAddress).executeCall(
                    contractAddress,
                    0,
                    abi.encodeWithSignature(
                        "safeTransferFrom(address,address,uint256,uint256,bytes)",
                        tokenBoundAddress,
                        msg.sender,
                        tokenId,
                        amount,
                        "0x"
                    )
                );
            } else if (dataType == keccak256("ERC3525")) {
                IAccount(tokenBoundAddress).executeCall(
                    contractAddress,
                    0,
                    abi.encodeWithSignature("transferFrom(uint256,address,uint256)", tokenId, msg.sender, amount)
                );
            }
        }
    }

    /* ========== CHAINLINK AUTOMATION FUNCTIONS ========== */
    function checkUpkeep(bytes calldata /*checkData*/ )
        public
        view
        override
        returns (bool upkeepNeeded, bytes memory performData)
    {
        return (_timestampToRentalPackTokenIds[block.timestamp].length > 0, abi.encodePacked(block.timestamp));
    }

    function performUpkeep(bytes calldata performData) external override {
        uint256 timestamp = abi.decode(performData, (uint256));
        uint256[] memory rentalPackIds = _timestampToRentalPackTokenIds[timestamp];
        require(block.timestamp >= timestamp && timestamp != 0, "invalid timestamp");
        require(rentalPackIds.length > 0, "no rental packs");

        for (uint256 i; i < rentalPackIds.length; i++) {
            if (RentalPackNFT(rentalPackAddress).checkRentalExpireTimestamp(rentalPackIds[i]) != 0) {
                IERC721(rentalPackAddress).safeTransferFrom(
                    IERC721(rentalPackAddress).ownerOf(rentalPackIds[i]), address(this), rentalPackIds[i]
                );
                _delistRentalPack(rentalPackIds[i]);
                _refreshRentalRecord(rentalPackIds[i]);
                _unlockTokenBoundAccount(rentalPackIds[i]);
                emit RentalFinished(timestamp, rentalPackAddress, rentalPackIds[i]);
            }
        }
    }

    /* ========== EVENTS ========== */
    event Lend(address rentalPackAddress, uint256 rentalPackTokenId, RentalPackNFT.RentalCondition rentalCondition);

    event LendingCanceled(address rentalPackAddress, uint256 rentalPackTokenId);

    event Rent(address rentalPackAddress, uint256 rentalPackTokenId, uint256 rentalHour);

    event RentalFinished(uint256 timestamp, address rentalPackAddress, uint256 rentalPackTokenId);

    /* ========== ERRORS ========== */
    error NotSupportedToken(address contractAddress);

    error InvalidRentalFee(uint256 fee, uint256 givenValue);
}
