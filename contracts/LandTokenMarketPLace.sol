// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "./Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
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
    function listToken(uint256 _tokenId, uint256 _price) external {
        // Vérifie que le msg.sender est le propriétaire du token.
        require(landToken.ownerOf(_tokenId) == msg.sender, "Non proprietaire");

        // Vérifie que le prix est valide (> 0).
        require(_price > 0, "Prix invalide");

        // Vérifie que le token n'est pas déjà en vente.
        require(!listings[_tokenId].isActive, "Deja en vente");

        // Transfère le token du propriétaire au contrat.
        landToken.transferFrom(msg.sender, address(this), _tokenId);

        // Crée une nouvelle liste pour le token.
        listings[_tokenId] = Listing({
            tokenId: _tokenId,
            price: _price,
            seller: msg.sender,
            isActive: true
        });

        // Émet l'événement TokenListed.
        emit TokenListed(_tokenId, _price, msg.sender);
    }

    /**
     * @dev Achète un token listé à la vente.
     * @param _tokenId L'ID du token à acheter.
     */
    function buyToken(uint256 _tokenId) external payable nonReentrant {
        // Récupère les informations de la liste.
        Listing storage listing = listings[_tokenId];

        // Vérifie que le token est actuellement en vente.
        require(listing.isActive, "Pas en vente");

        // Vérifie que le token existe.
        require(landToken.exists(_tokenId), "Token inexistant");

        // Vérifie que l'acheteur a envoyé un montant suffisant.
        require(msg.value >= listing.price, "Fonds insuffisants");

        // Désactive la liste.
        listing.isActive = false;

        // Récupère les informations du vendeur et du prix.
        address seller = listing.seller;
        uint256 price = listing.price;

        // Transfère le token à l'acheteur.
        landToken.transferFrom(address(this), msg.sender, _tokenId);

        // Passe le paiement au vendeur via call.
        (bool success, ) = payable(seller).call{value: price}("");
        require(success, "Paiement echoue");

        if (msg.value > price) {
            (bool refundSuccess, ) = payable(msg.sender).call{
                value: msg.value - price
            }("");
            require(refundSuccess, "Refund failed");
        }

        emit TokenSold(_tokenId, seller, msg.sender, price);
    }

    /**
     * @dev Annule une liste de token.
     * @param _tokenId L'ID du token dont la liste doit être annulée.
     */
    function cancelListing(uint256 _tokenId) external {
        // Récupère les informations de la liste.
        Listing storage listing = listings[_tokenId];

        // Vérifie que le msg.sender est le vendeur.
        require(listing.seller == msg.sender, "Non vendeur");

        // Vérifie que le token est actuellement en vente.
        require(listing.isActive, "Pas en vente");

        // Update state before external calls
        listing.isActive = false;

        // External call after state updates
        landToken.transferFrom(address(this), msg.sender, _tokenId);

        emit ListingCancelled(_tokenId);
    }
}
