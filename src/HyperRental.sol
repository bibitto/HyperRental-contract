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
    /* ========== STRUCTS ========== */

    struct RentalCondition {
        uint256 feePerHour;
        uint256 minHour;
        uint256 maxHour;
    }

    struct RentalPack {
        uint256 tokenId;
        address tokenBoundAccount;
    }

    /* ========== STATE VARIABLES ========== */
    address public tokenBoundAccountImplement;

    address public tokenBoundAccountRegistry;

    address public rentalPackAddress;

    RentalPack[] public listedRentalPacks;

    /* ========== MAPPINGS ========== */
    mapping(bytes32 => RentalCondition) private _idToRentalConditions;

    mapping(bytes32 => bytes[]) private _idToRentalAssets; // rentalId => abi.encodePacked(contractAddress,tokenId,amount,tokenType);

    mapping(bytes32 => uint256) private _idToRentalTimestamp;

    mapping(uint256 => uint256[]) private _timestampTorentalPackTokenIds;

    mapping(uint256 => address) private _rentalPackOwner;

    /* ========== CONSTRUCTOR ========== */
    constructor(address tokenBoundAccountImplement_, address tokenBoundAccountRegistry_, address rentalPackAddress_) {
        tokenBoundAccountImplement = tokenBoundAccountImplement_;
        tokenBoundAccountRegistry = tokenBoundAccountRegistry_;
        rentalPackAddress = rentalPackAddress_;
    }

    /* ========== VIEW FUNCTIONS ========== */
    function checkRentalCondition(uint256 rentalPackTokenId) public view returns (RentalCondition memory) {
        bytes32 rentalId = keccak256(abi.encodePacked(rentalPackAddress, rentalPackTokenId));
        return _idToRentalConditions[rentalId];
    }

    function checkRentalAssets(uint256 rentalPackTokenId) public view returns (bytes[] memory) {
        bytes32 rentalId = keccak256(abi.encodePacked(rentalPackAddress, rentalPackTokenId));
        return _idToRentalAssets[rentalId];
    }

    function checkRentalTimestamp(uint256 rentalPackTokenId) public view returns (uint256) {
        bytes32 rentalId = keccak256(abi.encodePacked(rentalPackAddress, rentalPackTokenId));
        return _idToRentalTimestamp[rentalId];
    }

    function checkRentalPackOwner(uint256 rentalPackTokenId) public view returns (address) {
        return _rentalPackOwner[rentalPackTokenId];
    }

    /* ========== MUTATIVE FUNCTIONS ========== */
    function createRentalPack() public returns (uint256, address) {
        uint256 tokenId = RentalPackNFT(rentalPackAddress).safeMint(address(this));
        address tokenBoundAddress = IRegistry(tokenBoundAccountRegistry).createAccount(rentalPackAddress, tokenId);
        _rentalPackOwner[tokenId] = msg.sender;
        IAccount(tokenBoundAddress).setHyperRental(address(this));
        return (tokenId, tokenBoundAddress);
    }

    function _recordRentalInfo(uint256 rentalPackTokenId, RentalCondition memory condition, bytes[] memory rentalAssets)
        private
    {
        bytes32 rentalId = keccak256(abi.encodePacked(rentalPackAddress, rentalPackTokenId));
        _idToRentalConditions[rentalId] = condition;
        _idToRentalAssets[rentalId] = rentalAssets;
    }

    function _batchDepositAssets(uint256 rentalPackTokenId, bytes[] memory assetDatas) private {
        address tokenBoundAddress = IRegistry(tokenBoundAccountRegistry).account(rentalPackAddress, rentalPackTokenId);
        for (uint256 i; i < assetDatas.length; i++) {
            (address contractAddress, uint256 tokenId, uint256 amount, bytes32 dataType) =
                abi.decode(assetDatas[i], (address, uint256, uint256, bytes32));

            if (dataType == keccak256("ERC20")) {
                require(IERC20(contractAddress).allowance(msg.sender, address(this)) >= amount, "ERC20: HyperRental is not approved for the given amount");
                IERC20(contractAddress).transfer(tokenBoundAddress, amount);
            } else if (dataType == keccak256("ERC721")) {
                require(
                    IERC721(contractAddress).getApproved(tokenId) == address(this), "ERC721: HyperRental is not approved"
                );
                IERC721(contractAddress).transferFrom(msg.sender, tokenBoundAddress, tokenId);
            } else if (dataType == keccak256("ERC1155")) {
                require(
                    IERC1155(contractAddress).isApprovedForAll(msg.sender, address(this)),
                    "ERC1155: HyperRental is not approved"
                );
                IERC1155(contractAddress).safeTransferFrom(msg.sender, tokenBoundAddress, tokenId, amount, "0x");
            } else if (dataType == keccak256("ERC3525")) {
                require(
                    IERC3525(contractAddress).allowance(tokenId, address(this)) >= amount,
                    "ERC3525: HyperRental is not approved for the given amount"
                );
                IERC3525(contractAddress).transferFrom(tokenId, tokenBoundAddress, amount);
            } else {
                revert NotSupportedToken(contractAddress);
            }
        }
    }

    function _lockTokenBoundAccount(uint256 rentalPackTokenId) private {
        address tokenBoundAccount = IRegistry(tokenBoundAccountRegistry).account(rentalPackAddress, rentalPackTokenId);
        IAccount(tokenBoundAccount).lock();
    }

    function _listRentalPack(uint256 rentalPackTokenId) private {
        address tokenBoundAccount = IRegistry(tokenBoundAccountRegistry).account(rentalPackAddress, rentalPackTokenId);
        listedRentalPacks.push(RentalPack(rentalPackTokenId, tokenBoundAccount));
    }

    function lend(uint256 rentalPackTokenId, RentalCondition memory rentalCondition, bytes[] memory rentalAssets)
        public
    {
        require(_rentalPackOwner[rentalPackTokenId] == msg.sender, "msg.sender is not rentalPack owner");
        _recordRentalInfo(rentalPackTokenId, rentalCondition, rentalAssets);
        _batchDepositAssets(rentalPackTokenId, rentalAssets);
        _lockTokenBoundAccount(rentalPackTokenId);
        _listRentalPack(rentalPackTokenId);
        emit Lend(rentalPackAddress, rentalPackTokenId, rentalCondition, rentalAssets);
    }

    function _unlockTokenBoundAccount(uint256 rentalPackTokenId) private {
        address tokenBoundAccount = IRegistry(tokenBoundAccountRegistry).account(rentalPackAddress, rentalPackTokenId);
        IAccount(tokenBoundAccount).unlock();
    }

    function _withdrawAllAssets(uint256 rentalPackTokenId) private {
        bytes32 rentalId = keccak256(abi.encodePacked(rentalPackAddress, rentalPackTokenId));
        bytes[] memory assetDatas = _idToRentalAssets[rentalId];
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
            }
            if (dataType == keccak256("ERC721")) {
                IAccount(tokenBoundAddress).executeCall(
                    contractAddress,
                    0,
                    abi.encodeWithSignature(
                        "transferFrom(address,address,uint256)", tokenBoundAddress, msg.sender, tokenId
                    )
                );
            }
            if (dataType == keccak256("ERC1155")) {
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
            }
            if (dataType == keccak256("ERC3525")) {
                IAccount(tokenBoundAddress).executeCall(
                    contractAddress,
                    0,
                    abi.encodeWithSignature("transferFrom(uint256,address,uint256)", tokenId, msg.sender, amount)
                );
            }
        }
    }

    function _delistRentalPack(uint256 rentalPackTokenId) private {
        uint256 length = listedRentalPacks.length;
        for (uint256 i; i < length; i++) {
            if (rentalPackTokenId == listedRentalPacks[i].tokenId) {
                listedRentalPacks[i] = listedRentalPacks[length - 1];
            }
        }
        listedRentalPacks.pop();
    }

    function _refreshRentalRecord(uint256 rentalPackTokenId) private {
        bytes32 rentalId = keccak256(abi.encodePacked(rentalPackAddress, rentalPackTokenId));
        _idToRentalConditions[rentalId] = RentalCondition(0, 0, 0);
        bytes[] memory emptyArray;
        _idToRentalAssets[rentalId] = emptyArray;
        if (_idToRentalTimestamp[rentalId] != 0) {
            _idToRentalTimestamp[rentalId] = 0;
        }
    }

    function cancelLending(uint256 rentalPackTokenId) external {
        bytes32 rentalId = keccak256(abi.encodePacked(rentalPackAddress, rentalPackTokenId));
        require(_rentalPackOwner[rentalPackTokenId] != address(0), "the given RentalPack is invalid");
        require(msg.sender == _rentalPackOwner[rentalPackTokenId], "msg.sender is not a lender");
        require(_idToRentalTimestamp[rentalId] == 0, "cannot cancel lending when the rental pack is rented ");
        _unlockTokenBoundAccount(rentalPackTokenId);
        _withdrawAllAssets(rentalPackTokenId);
        _delistRentalPack(rentalPackTokenId);
        _refreshRentalRecord(rentalPackTokenId);
        emit LendingCanceled(rentalPackAddress, rentalPackTokenId);
    }

    function rent(uint256 rentalPackTokenId, uint256 rentalHour, address receiver) public payable {
        bytes32 rentalId = keccak256(abi.encodePacked(rentalPackAddress, rentalPackTokenId));
        RentalCondition memory condition = _idToRentalConditions[rentalId];
        require(_rentalPackOwner[rentalPackTokenId] != address(0), "the given RentalPack is invalid");
        require(condition.feePerHour * rentalHour * 1 ether == msg.value, "msg.value is invalid");
        require(condition.minHour <= rentalHour, "the given rental hour is too shoot");
        require(condition.maxHour >= rentalHour, "the given rental hour is too long");
        uint256 rentalTimestamp = block.timestamp + rentalHour * 1 hours;
        _idToRentalTimestamp[rentalId] = rentalTimestamp;
        _timestampTorentalPackTokenIds[rentalTimestamp].push(rentalPackTokenId);
        payable(_rentalPackOwner[rentalPackTokenId]).transfer(msg.value);
        IERC721(rentalPackAddress).safeTransferFrom(address(this), receiver, rentalPackTokenId);
        emit Rent(rentalPackAddress, rentalPackTokenId, rentalHour);
    }

    /* ========== CHAINLINK AUTOMATION FUNCTIONS ========== */
    function checkUpkeep(bytes calldata /*checkData*/ )
        public
        view
        override
        returns (bool upkeepNeeded, bytes memory performData)
    {
        return (_timestampTorentalPackTokenIds[block.timestamp].length > 0, abi.encode(block.timestamp));
    }

    function performUpkeep(bytes calldata performData) external override {
        uint256 timestamp = abi.decode(performData, (uint256));
        uint256[] memory rentalPackIds = _timestampTorentalPackTokenIds[timestamp];
        require(block.timestamp >= timestamp, "invalid timestamp");
        require(rentalPackIds.length > 0, "no rental packs");

        for (uint256 i; i < rentalPackIds.length; i++) {
            bytes32 rentalId = keccak256(abi.encodePacked(rentalPackAddress, rentalPackIds[i]));
            if (_idToRentalTimestamp[rentalId] != 0) {
                IERC721(rentalPackAddress).safeTransferFrom(
                    IERC721(rentalPackAddress).ownerOf(rentalPackIds[i]), address(this), rentalPackIds[i]
                );
                _unlockTokenBoundAccount(rentalPackIds[i]);
                _withdrawAllAssets(rentalPackIds[i]);
                _delistRentalPack(rentalPackIds[i]);
                _refreshRentalRecord(rentalPackIds[i]);
                emit RentalFinished(timestamp, rentalPackAddress, rentalPackIds[i]);
            }
        }
    }

    /* ========== EVENTS ========== */
    event Lend(
        address rentalPackAddress, uint256 rentalPackTokenId, RentalCondition rentalCondition, bytes[] rentalAssets
    );

    event LendingCanceled(address rentalPackAddress, uint256 rentalPackTokenId);

    event Rent(address rentalPackAddress, uint256 rentalPackTokenId, uint256 rentalHour);

    event RentalFinished(uint256 timestamp, address rentalPackAddress, uint256 rentalPackTokenId);

    /* ========== ERRORS ========== */
    error NotSupportedToken(address contractAddress);
}
