// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

/* ========== IMPORTS ========== */
import "openzeppelin-contracts/token/ERC721/ERC721.sol";
import "openzeppelin-contracts/access/AccessControl.sol";
import "openzeppelin-contracts/utils/Counters.sol";
import "openzeppelin-contracts/utils/Strings.sol";
import "openzeppelin-contracts/utils/Base64.sol";

contract RentalPackNFT is ERC721, AccessControl {
    /* ========== LIBRARIES ========== */
    using Counters for Counters.Counter;

    /* ========== STRUCTS ========== */
    struct RentalCondition {
        uint256 feePerHour;
        uint256 minHour;
        uint256 maxHour;
    }

    /* ========== ENUMS ========== */
    enum Status {
        NotListed,
        Listed,
        Rented
    }

    /* ========== CONSTANT VARIABLES ========== */
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    /* ========== STATE VARIABLES ========== */
    Counters.Counter private _tokenIdCounter;

    /* ========== MAPPINGS ========== */
    mapping(uint256 => RentalCondition) private _idToRentalCondition;

    // mapping(uint256 => bytes[]) private _idToRentalAssets; // abi.encodePacked(address contractAddress, uint256 tokenId, uint256 amount, uint256 tokenType);

    mapping(uint256 => uint256) private _idToRentalExpireTimestamp;

    mapping(uint256 => address) private _idToTokenBoundAccount;

    mapping(uint256 => address) private _idToRentalPackOwner;

    mapping(uint256 => Status) private _idToStatus;

    mapping(address => uint256[]) private _ownedIds;

    /* ========== CONSTRUCTOR ========== */
    constructor() ERC721("RentalPack", "RENTAL") {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(OPERATOR_ROLE, msg.sender);
    }

    /* ========== MUTATIVE FUNCTIONS ========== */
    function grantOperatorRole(address to) public onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(OPERATOR_ROLE, to);
    }

    function transferFrom(address from, address to, uint256 tokenId) public override onlyRole(OPERATOR_ROLE) {
        //solhint-disable-next-line max-line-length
        require(_isApprovedOrOwner(_msgSender(), tokenId), "ERC721: caller is not token owner or approved");

        _transfer(from, to, tokenId);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId) public override onlyRole(OPERATOR_ROLE) {
        safeTransferFrom(from, to, tokenId, "");
    }

    function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory data)
        public
        override
        onlyRole(OPERATOR_ROLE)
    {
        require(_isApprovedOrOwner(_msgSender(), tokenId), "ERC721: caller is not token owner or approved");
        _safeTransfer(from, to, tokenId, data);
    }

    function safeMint(address to) public onlyRole(OPERATOR_ROLE) returns (uint256) {
        _tokenIdCounter.increment();
        uint256 tokenId = _tokenIdCounter.current();
        _safeMint(to, tokenId);
        return tokenId;
    }

    function updataRentalCondition(uint256 tokenId, RentalCondition memory condition) public onlyRole(OPERATOR_ROLE) {
        _idToRentalCondition[tokenId] = condition;
    }

    function updataRentalExpireTimestamp(uint256 tokenId, uint256 timestamp) public onlyRole(OPERATOR_ROLE) {
        _idToRentalExpireTimestamp[tokenId] = timestamp;
    }

    function updataStatus(uint256 tokenId, Status status) public onlyRole(OPERATOR_ROLE) {
        _idToStatus[tokenId] = status;
    }

    function updateOwnedIds(address owner, uint256 tokenId) public onlyRole(OPERATOR_ROLE) {
        _ownedIds[owner].push(tokenId);
    }

    function recordTokenBoundAccount(uint256 tokenId, address tba) public onlyRole(OPERATOR_ROLE) {
        _idToTokenBoundAccount[tokenId] = tba;
    }

    function recordRentalPackOwner(uint256 tokenId, address owner) public onlyRole(OPERATOR_ROLE) {
        _idToRentalPackOwner[tokenId] = owner;
    }

    /* ========== VIEW FUNCTIONS ========== */
    function checkRentalCondition(uint256 tokenId) public view returns (RentalCondition memory) {
        return _idToRentalCondition[tokenId];
    }

    function checkRentalExpireTimestamp(uint256 tokenId) public view returns (uint256) {
        return _idToRentalExpireTimestamp[tokenId];
    }

    function checkStatus(uint256 tokenId) public view returns (uint256) {
        return uint256(_idToStatus[tokenId]);
    }

    function checkOwnedIds(address owner) public view returns (uint256[] memory) {
        return _ownedIds[owner];
    }

    function checkTokenBoundAccount(uint256 tokenId) public view returns (address) {
        return _idToTokenBoundAccount[tokenId];
    }

    function checkRentalPackOwner(uint256 tokenId) public view returns (address) {
        return _idToRentalPackOwner[tokenId];
    }

    function supportsInterface(bytes4 interfaceId) public view override(ERC721, AccessControl) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        require(_exists(tokenId), "Token ID does not exist.");
        string memory rentalPackName = string(abi.encodePacked("Rental Pack #", Strings.toString(tokenId)));
        string memory tokenBoundAccount = Strings.toHexString(uint160(_idToTokenBoundAccount[tokenId]), 20);
        string memory rentalPackOwner = Strings.toHexString(uint160(_idToRentalPackOwner[tokenId]), 20);
        string memory rentalInfo = string(
            abi.encodePacked(
                '{"fee_per_hour": ',
                Strings.toString(_idToRentalCondition[tokenId].feePerHour),
                ', "min_hour": ',
                Strings.toString(_idToRentalCondition[tokenId].minHour),
                ', "max_hour": ',
                Strings.toString(_idToRentalCondition[tokenId].maxHour),
                ', "status": ',
                Strings.toString(checkStatus(tokenId)),
                "}"
            )
        );
        string memory encodedData = string(
            abi.encodePacked(
                '{"id": ',
                Strings.toString((tokenId)),
                ", ",
                '"name": "',
                rentalPackName,
                '", ',
                '"description": "this is a rental pack NFT powered by HyperRental protocol", ',
                '"image": "https://bafkreifrphrgwh6tgdjjii2sjtairtbuxbiwuy544kbvyxq5yxi5cf5vuu.ipfs.nftstorage.link/", ',
                '"token_bound_account": "',
                tokenBoundAccount,
                '", ',
                '"rental_pack_owner": "',
                rentalPackOwner,
                '", ',
                '"rental_info": ',
                rentalInfo,
                "}"
            )
        );
        string memory json = Base64.encode(bytes(encodedData));
        return string(abi.encodePacked("data:application/json;base64,", json));
    }

    function getAllTokenUris() public view returns (string[] memory) {
        uint256 tokenId = _tokenIdCounter.current();
        string[] memory uris = new string[](tokenId);
        for (uint256 i; i < tokenId; i++) {
            uris[i] = tokenURI(i + 1);
        }
        return uris;
    }
}
