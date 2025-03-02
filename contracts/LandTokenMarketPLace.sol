// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "./Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "./LandToken.sol";

/**
 * @title LandTokenMarketplace
 * @dev Contrat permettant la vente, l'achat et l'échange de tokens ERC-721 (LandToken).
 */
contract LandTokenMarketplace is ReentrancyGuard, Pausable, Ownable {
    LandToken public immutable landToken;

    /**
     * @dev Structure représentant une liste de token à vendre.
     */
    struct Listing {
        uint256 tokenId;
        uint256 price;
        address seller;
        bool isActive;
    }

    /**
     * @dev Mapping des listings par ID de token.
     */
    mapping(uint256 => Listing) public listings;

    /**
     * @dev Événement émis lorsqu'un token est listé à la vente.
     * @param tokenId L'ID du token listé.
     * @param price Le prix demandé pour le token.
     * @param seller L'adresse du vendeur.
     */
    event TokenListed(uint256 indexed tokenId, uint256 price, address seller);

    /**
     * @dev Événement émis lorsqu'un token est acheté.
     * @param tokenId L'ID du token acheté.
     * @param seller L'adresse du vendeur.
     * @param buyer L'adresse de l'acheteur.
     * @param price Le prix payé pour le token.
     */
    event TokenSold(
        uint256 indexed tokenId,
        address seller,
        address buyer,
        uint256 price
    );

    error InvalidTokenAddress();
    error NotTokenOwner();
    error InvalidPrice();
    error AlreadyListed();
    error NotListed();
    error TokenDoesNotExist();
    error InsufficientFunds();
    error NotSeller();
    error TransferFailed();

    /**
     * @dev Événement émis lorsqu'une liste est annulée.
     * @param tokenId L'ID du token dont la liste a été annulée.
     */
    event ListingCancelled(uint256 indexed tokenId);

    /**
     * @dev Constructeur du contrat.
     * @param _landTokenAddress Adresse du contrat LandToken.
     */
    constructor(address _landTokenAddress) {
        if (_landTokenAddress == address(0)) revert InvalidTokenAddress();
        landToken = LandToken(_landTokenAddress);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @dev Liste un token à la vente.
     * @param _tokenId L'ID du token à lister.
     * @param _price Le prix demandé pour le token.
     */
    function listToken(uint256 _tokenId, uint256 _price) external nonReentrant {
        // Vérifications
        if (landToken.ownerOf(_tokenId) != msg.sender) revert NotTokenOwner();
        if (_price == 0) revert InvalidPrice();
        if (listings[_tokenId].isActive) revert AlreadyListed();

        // Mettre à jour l'état avant l'appel externe
        listings[_tokenId] = Listing({
            tokenId: _tokenId,
            price: _price,
            seller: msg.sender,
            isActive: true
        });

        // Appel externe après la mise à jour de l'état
        landToken.transferFrom(msg.sender, address(this), _tokenId);

        emit TokenListed(_tokenId, _price, msg.sender);
    }

    /**
     * @dev Achète un token listé à la vente.
     * @param _tokenId L'ID du token à acheter.
     */
    function buyToken(uint256 _tokenId) external payable nonReentrant {
        Listing storage listing = listings[_tokenId];
        if (!listing.isActive) revert NotListed();
        if (!landToken.exists(_tokenId)) revert TokenDoesNotExist();
        if (msg.value < listing.price) revert InsufficientFunds();

        address seller = listing.seller;
        uint256 price = listing.price;

        // Désactiver le listing avant les transferts
        listing.isActive = false;

        // Transfert du token
        landToken.transferFrom(address(this), msg.sender, _tokenId);

        // Transfert des fonds au vendeur
        (bool success, ) = payable(seller).call{value: price}("");
        if (!success) revert TransferFailed();

        // Remboursement de l'excédent si nécessaire
        if (msg.value > price) {
            (bool refundSuccess, ) = payable(msg.sender).call{
                value: msg.value - price
            }("");
            if (!refundSuccess) revert TransferFailed();
        }

        emit TokenSold(_tokenId, seller, msg.sender, price);
    }

    /**
     * @dev Annule une liste de token.
     * @param _tokenId L'ID du token dont la liste doit être annulée.
     */
    function cancelListing(uint256 _tokenId) external nonReentrant {
        Listing storage listing = listings[_tokenId];
        if (listing.seller != msg.sender) revert NotSeller();
        if (!listing.isActive) revert NotListed();

        // Update state before external call
        listing.isActive = false;

        // Émettre l'événement avant l'appel externe
        emit ListingCancelled(_tokenId);

        // External call last
        landToken.transferFrom(address(this), msg.sender, _tokenId);
    }
}
