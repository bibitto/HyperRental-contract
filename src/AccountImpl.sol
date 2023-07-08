// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "openzeppelin-contracts/token/ERC721/IERC721.sol";
import "openzeppelin-contracts/interfaces/IERC1271.sol";
import "openzeppelin-contracts/utils/cryptography/SignatureChecker.sol";
import "openzeppelin-contracts/utils/introspection/IERC165.sol";
import "openzeppelin-contracts/token/ERC1155/IERC1155Receiver.sol";
import "openzeppelin-contracts/access/Ownable.sol";

import "./MinimalReceiver.sol";
import "./interfaces/IAccount.sol";
import "./lib/MinimalProxyStore.sol";

/**
 * @title A smart contract wallet owned by a single ERC721 token
 * @author Jayden Windle (jaydenwindle)
 */
contract AccountImpl is IERC165, IERC1271, IAccount, MinimalReceiver {
    error NotAuthorized();
    error AccountLocked();

    bool public isLocked;
    address public deployer;

    event Locked();
    event Unlocked();

    constructor() {
        deployer = msg.sender;
    }

    /**
     * @dev Ensures execution can only continue if the account is not locked
     */
    modifier onlyUnlocked() {
        if (isLocked) revert AccountLocked();
        _;
    }

    modifier onlyAdmin() {
        if (msg.sender != owner() && msg.sender != deployer) revert NotAuthorized();
        _;
    }

    /**
     * @dev Executes a transaction from the Account. Must be called by an account owner.
     *
     * @param to      Destination address of the transaction
     * @param value   Ether value of the transaction
     * @param data    Encoded payload of the transaction
     */
    function executeCall(address to, uint256 value, bytes calldata data)
        external
        payable
        onlyUnlocked
        onlyAdmin
        returns (bytes memory result)
    {
        return _call(to, value, data);
    }

    function lock() external onlyUnlocked onlyAdmin {
        isLocked = true;
        emit Locked();
    }

    function unlock() external onlyAdmin {
        isLocked = false;
        emit Unlocked();
    }

    /**
     * @dev Implements EIP-1271 signature validation
     *
     * @param hash      Hash of the signed data
     * @param signature Signature to validate
     */
    function isValidSignature(bytes32 hash, bytes memory signature) external view returns (bytes4 magicValue) {
        // If account is locked, disable signing
        if (isLocked) return "";

        // If account has an executor, check if executor signature is valid
        address _owner = owner();

        // Default - check if signature is valid for account owner
        if (SignatureChecker.isValidSignatureNow(_owner, hash, signature)) {
            return IERC1271.isValidSignature.selector;
        }

        return "";
    }

    /**
     * @dev Implements EIP-165 standard interface detection
     *
     * @param interfaceId the interfaceId to check support for
     * @return true if the interface is supported, false otherwise
     */
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(IERC165, ERC1155Receiver)
        returns (bool)
    {
        // default interface support
        if (
            interfaceId == type(IAccount).interfaceId || interfaceId == type(IERC1155Receiver).interfaceId
                || interfaceId == type(IERC165).interfaceId
        ) {
            return true;
        }
        return false;
    }

    /**
     * @dev Returns the owner of the token that controls this Account (public for Ownable compatibility)
     *
     * @return the address of the Account owner
     */
    function owner() public view override returns (address) {
        (uint256 chainId, address tokenCollection, uint256 tokenId) = context();

        if (chainId != block.chainid) {
            return address(0);
        }

        return IERC721(tokenCollection).ownerOf(tokenId);
    }

    /**
     * @dev Returns information about the token that owns this account
     *
     * @return tokenCollection the contract address of the  ERC721 token which owns this account
     * @return tokenId the tokenId of the  ERC721 token which owns this account
     */
    function token() public view returns (address tokenCollection, uint256 tokenId) {
        (, tokenCollection, tokenId) = context();
    }

    function context() internal view returns (uint256, address, uint256) {
        bytes memory rawContext = MinimalProxyStore.getContext(address(this));
        if (rawContext.length == 0) return (0, address(0), 0);

        return abi.decode(rawContext, (uint256, address, uint256));
    }

    /**
     * @dev Executes a low-level call
     */
    function _call(address to, uint256 value, bytes calldata data) internal returns (bytes memory result) {
        bool success;
        (success, result) = to.call{value: value}(data);

        if (!success) {
            assembly {
                revert(add(result, 32), mload(result))
            }
        }
    }
}
