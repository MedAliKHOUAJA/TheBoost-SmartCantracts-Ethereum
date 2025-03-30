// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "./Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "./LandToken.sol";

/**
 * @title LandTokenMarketplacee
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
    mapping(address => bool) public relayers;

    /**
     * @dev Événement émis lorsqu'un token est listé à la vente.
     * @param tokenId L'ID du token listé.
     * @param price Le prix demandé pour le token.
     * @param seller L'adresse du vendeur.
     */
    event TokenListed(uint256 indexed tokenId, uint256 price, address seller);
    event RelayerAdded(address indexed relayer);
    event RelayerRemoved(address indexed relayer);

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
    error UnauthorizedRelayer();
    error InvalidRelayer();

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

    modifier onlyRelayerOrOwner() {
        if (!relayers[msg.sender] && msg.sender != owner())
            revert UnauthorizedRelayer();
        _;
    }

    // Fonctions de gestion des relayers
    function addRelayer(address _relayer) external onlyOwner {
        if (_relayer == address(0)) revert InvalidRelayer();
        relayers[_relayer] = true;
        emit RelayerAdded(_relayer);
    }

    function removeRelayer(address _relayer) external onlyOwner {
        relayers[_relayer] = false;
        emit RelayerRemoved(_relayer);
    }

    // Ajout d'une fonction de listing pour les relayers
    function listTokenForUser(
        uint256 _tokenId,
        uint256 _price,
        address _seller
    ) external nonReentrant onlyRelayerOrOwner {
        if (landToken.ownerOf(_tokenId) != _seller) revert NotTokenOwner();
        if (_price == 0) revert InvalidPrice();
        if (listings[_tokenId].isActive) revert AlreadyListed();

        listings[_tokenId] = Listing({
            tokenId: _tokenId,
            price: _price,
            seller: _seller,
            isActive: true
        });

        landToken.transferFrom(_seller, address(this), _tokenId);
        emit TokenListed(_tokenId, _price, _seller);
    }

    // Ajout d'une fonction d'achat pour les relayers
    function buyTokenForUser(
        uint256 _tokenId,
        address _buyer
    ) external payable nonReentrant onlyRelayerOrOwner {
        Listing storage listing = listings[_tokenId];
        if (!listing.isActive) revert NotListed();
        if (!landToken.exists(_tokenId)) revert TokenDoesNotExist();
        if (msg.value < listing.price) revert InsufficientFunds();

        address seller = listing.seller;
        uint256 price = listing.price;
        listing.isActive = false;

        landToken.transferFrom(address(this), _buyer, _tokenId);

        (bool success, ) = payable(seller).call{value: price}("");
        if (!success) revert TransferFailed();

        uint256 excess = msg.value - price;
        if (excess > 0) {
            (bool refundSuccess, ) = payable(msg.sender).call{value: excess}(
                ""
            );
            if (!refundSuccess) revert TransferFailed();
        }

        emit TokenSold(_tokenId, seller, _buyer, price);
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
        require(listing.isActive, "Not listed");
        require(landToken.exists(_tokenId), "Token does not exist");
        require(msg.value >= listing.price, "Insufficient payment");

        address seller = listing.seller;
        uint256 price = listing.price;

        // Désactiver le listing avant les transferts
        listing.isActive = false;

        // Transfert du token
        landToken.transferFrom(address(this), msg.sender, _tokenId);

        // Transfert des fonds au vendeur
        (bool success, ) = payable(seller).call{value: price}("");
        require(success, "Seller payment failed");

        // Remboursement de l'excédent
        uint256 excess = msg.value - price;
        if (excess > 0) {
            (bool refundSuccess, ) = payable(msg.sender).call{value: excess}(
                ""
            );
            require(refundSuccess, "Refund failed");
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
