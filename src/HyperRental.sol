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

    RentalPackNFT public rentalPackNFT;

    /* ========== MAPPINGS ========== */
    mapping(uint256 => uint256[]) private _timestampToRentalPackTokenIds;

    /* ========== CONSTRUCTOR ========== */
    constructor(address tokenBoundAccountImplement_, address tokenBoundAccountRegistry_, address rentalPackAddress_) {
        tokenBoundAccountImplement = tokenBoundAccountImplement_;
        tokenBoundAccountRegistry = tokenBoundAccountRegistry_;
        rentalPackNFT = RentalPackNFT(rentalPackAddress_);
    }

    /* ========== MUTATIVE FUNCTIONS ========== */
    function createRentalPack() public returns (uint256, address) {
        uint256 tokenId = rentalPackNFT.safeMint(address(this));
        address tokenBoundAddress = IRegistry(tokenBoundAccountRegistry).createAccount(address(rentalPackNFT), tokenId);
        rentalPackNFT.recordRentalPackOwner(tokenId, msg.sender);
        rentalPackNFT.recordTokenBoundAccount(tokenId, tokenBoundAddress);
        rentalPackNFT.updateOwnedIds(msg.sender, tokenId);
        return (tokenId, tokenBoundAddress);
    }

    function _lockTokenBoundAccount(uint256 rentalPackTokenId) private {
        address tokenBoundAccount = IRegistry(tokenBoundAccountRegistry).account(address(rentalPackNFT), rentalPackTokenId);
        IAccount(tokenBoundAccount).lock();
    }

    function lend(uint256 rentalPackTokenId, RentalPackNFT.RentalCondition memory rentalCondition) public {
        require(
            rentalPackNFT.checkRentalPackOwner(rentalPackTokenId) == msg.sender,
            "msg.sender is not rentalPack owner"
        );
        _lockTokenBoundAccount(rentalPackTokenId);
        rentalPackNFT.updataRentalCondition(rentalPackTokenId, rentalCondition);
        rentalPackNFT.updataStatus(rentalPackTokenId, RentalPackNFT.Status.Listed);
        emit Lend(address(rentalPackNFT), rentalPackTokenId, rentalCondition);
    }

    function _unlockTokenBoundAccount(uint256 rentalPackTokenId) private {
        address tokenBoundAccount = IRegistry(tokenBoundAccountRegistry).account(address(rentalPackNFT), rentalPackTokenId);
        IAccount(tokenBoundAccount).unlock();
    }

    function _delistRentalPack(uint256 rentalPackTokenId) private {
        rentalPackNFT.updataStatus(rentalPackTokenId, RentalPackNFT.Status.NotListed);
    }

    function _refreshRentalRecord(uint256 rentalPackTokenId) private {
        rentalPackNFT.updataRentalCondition(
            rentalPackTokenId, RentalPackNFT.RentalCondition(0, 0, 0)
        );
        if (rentalPackNFT.checkRentalExpireTimestamp(rentalPackTokenId) != 0) {
            rentalPackNFT.updataRentalExpireTimestamp(rentalPackTokenId, 0);
        }
    }

    function cancelLending(uint256 rentalPackTokenId) external {
        require(
            rentalPackNFT.checkRentalPackOwner(rentalPackTokenId) == msg.sender,
            "msg.sender is not a lender"
        );
        require(
            rentalPackNFT.checkStatus(rentalPackTokenId) == uint256(RentalPackNFT.Status.Listed),
            "the rental pack is not listed"
        );
        require(
            rentalPackNFT.checkRentalExpireTimestamp(rentalPackTokenId) == 0,
            "cannot cancel lending when the rental pack is rented "
        );
        _delistRentalPack(rentalPackTokenId);
        _refreshRentalRecord(rentalPackTokenId);
        _unlockTokenBoundAccount(rentalPackTokenId);
        emit LendingCanceled(address(rentalPackNFT), rentalPackTokenId);
    }

    function rent(uint256 rentalPackTokenId, uint256 rentalHour, address receiver) public payable {
        require(
            rentalPackNFT.checkStatus(rentalPackTokenId) == uint256(RentalPackNFT.Status.Listed),
            "the rental pack is not listed"
        );
        require(
            rentalPackNFT.checkRentalExpireTimestamp(rentalPackTokenId) == 0,
            "anyone has already rented"
        );
        RentalPackNFT.RentalCondition memory condition =
            rentalPackNFT.checkRentalCondition(rentalPackTokenId);
        if (condition.feePerHour * rentalHour != msg.value) {
            revert InvalidRentalFee(condition.feePerHour * rentalHour, msg.value);
        }
        require(condition.minHour <= rentalHour, "the given rental hour is too shoot");
        require(condition.maxHour >= rentalHour, "the given rental hour is too long");
        // update listing status
        rentalPackNFT.updataStatus(rentalPackTokenId, RentalPackNFT.Status.Rented);
        // update expire timestamp info
        uint256 rentalExpireTimestamp = block.timestamp + (rentalHour * 1 hours);
        rentalPackNFT.updataRentalExpireTimestamp(rentalPackTokenId, rentalExpireTimestamp);
        _timestampToRentalPackTokenIds[rentalExpireTimestamp].push(rentalPackTokenId);
        // transfer fee to TBA
        address tokenBoundAddress = rentalPackNFT.checkTokenBoundAccount(rentalPackTokenId);
        (bool success, bytes memory data) = tokenBoundAddress.call{value: msg.value}("");
        require(success, "Failed to send Ether to NFT owner");
        // tranffer rentalPack NFT to receiver address
        rentalPackNFT.safeTransferFrom(address(this), receiver, rentalPackTokenId, "0x");
        emit Rent(address(rentalPackNFT), rentalPackTokenId, rentalHour);
    }

    function withdrawAssets(uint256 rentalPackTokenId, bytes[] calldata assetDatas) public {
        require(
            rentalPackNFT.checkRentalPackOwner(rentalPackTokenId) == msg.sender, "invalid msg.sender"
        );
        require(
            rentalPackNFT.checkStatus(rentalPackTokenId) == uint256(RentalPackNFT.Status.NotListed),
            'the status should be "NotListed"'
        );
        address tokenBoundAddress = IRegistry(tokenBoundAccountRegistry).account(address(rentalPackNFT), rentalPackTokenId);
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

    function withdrawNativeToken(uint256 rentalPackTokenId, uint256 amount) public {
        require(
            rentalPackNFT.checkRentalPackOwner(rentalPackTokenId) == msg.sender,
            "msg.sender is not rental pack owner"
        );
        address tokenBoundAddress = rentalPackNFT.checkTokenBoundAccount(rentalPackTokenId);
        require(
            amount != 0 && address(tokenBoundAddress).balance >= amount,
            "the given amount is invalid. please check TBA's eth balance"
        );
        IAccount(tokenBoundAddress).executeCall(msg.sender, amount, "");
    }

    /* ========== CHAINLINK AUTOMATION FUNCTIONS ========== */
    function checkUpkeep(bytes calldata /*checkData*/ )
        public
        view
        override
        returns (bool upkeepNeeded, bytes memory performData)
    {
        uint256 endTimestamp = block.timestamp;
        uint256 startTimestamp = endTimestamp - 1 minutes;
        uint256 count;
        for (uint256 i = startTimestamp; i <= endTimestamp; i++) {
            count += _timestampToRentalPackTokenIds[i].length;
        }
        if (count == 0) return (false, "");

        uint256[] memory tokenIds = new uint256[](count);
        uint256 index;
        for (uint256 i = startTimestamp; i <= endTimestamp; i++) {
            for (uint256 j = 0; j < _timestampToRentalPackTokenIds[i].length; j++) {
                tokenIds[index] = _timestampToRentalPackTokenIds[i][j];
                index++;
            }
        }
        return (tokenIds.length > 0, abi.encodePacked(tokenIds));
    }

    function performUpkeep(bytes calldata performData) external override {
        uint256[] memory rentalPackIds = abi.decode(performData, (uint256[]));
        for (uint256 i; i < rentalPackIds.length; i++) {
            uint256 currentTimestamp = block.timestamp;
            uint256 id = rentalPackIds[i];
            uint256 expireTimestamp = rentalPackNFT.checkRentalExpireTimestamp(id);
            if (expireTimestamp != 0 && expireTimestamp <= currentTimestamp) {
                _refreshRentalRecord(id);
                _delistRentalPack(id);
                rentalPackNFT.safeTransferFrom(rentalPackNFT.ownerOf(id), address(this), id);
                _unlockTokenBoundAccount(id);
                emit RentalFinished(currentTimestamp, address(rentalPackNFT), id);
            }
            _timestampToRentalPackTokenIds[expireTimestamp] = new uint256[](0);
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
