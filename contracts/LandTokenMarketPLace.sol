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

    uint256 public marketplaceFeePercentage = 250;
    uint256 public constant PERCENTAGE_BASE = 10000;

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
    // Liste de tous les tokens actifs sur le marketplace
    uint256[] public activeListingIds;
    // Mapping pour stocker l'index d'un token dans le tableau activeListingIds
    mapping(uint256 => uint256) private activeListingIndex;
    // Mapping pour suivre les tokens listés par chaque utilisateur
    mapping(address => uint256[]) private userListedTokens;
    // Mapping pour suivre l'index d'un token dans le tableau userListedTokens
    mapping(address => mapping(uint256 => uint256))
        private userListedTokenIndex;
    // Horodatage du listing pour chaque token
    mapping(uint256 => uint256) public listingTimestamps;

    event MarketplaceFeeUpdated(uint256 newFeePercentage);
    event MarketplaceFeesCollected(uint256 tokenId, uint256 amount);
    event MarketplaceFeesWithdrawn(address indexed to, uint256 amount);

    /**
     * @dev Événement émis lorsqu'un token est listé à la vente.
     * @param tokenId L'ID du token listé.
     * @param price Le prix demandé pour le token.
     * @param seller L'adresse du vendeur.
     */
    event TokenListed(uint256 indexed tokenId, uint256 price, address seller);
    event RelayerAdded(address indexed relayer);
    event RelayerRemoved(address indexed relayer);
    event MultipleTokensListed(address indexed seller, uint256 count);
    event MultipleTokensBought(
        address indexed buyer,
        uint256 count,
        uint256 totalPrice,
        uint256 totalMarketplaceFee
    );

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
    /**
     * @dev Événement émis lorsqu'une liste est annulée.
     * @param tokenId L'ID du token dont la liste a été annulée.
     */
    event ListingCancelled(uint256 indexed tokenId);
    event ActiveListingsUpdated(uint256 totalActive);

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

    /**
     * @dev Permet au propriétaire de modifier le pourcentage des frais du marketplace.
     * @param _newFeePercentage Nouveau pourcentage de frais (en base 10000, 250 = 2.5%).
     */
    function setMarketplaceFeePercentage(
        uint256 _newFeePercentage
    ) external onlyOwner {
        require(_newFeePercentage <= 1000, "Fee cannot exceed 10%");

        marketplaceFeePercentage = _newFeePercentage;

        emit MarketplaceFeeUpdated(_newFeePercentage);
    }

    /**
     * @dev Permet au propriétaire de retirer les frais du marketplace collectés.
     */
    function withdrawMarketplaceFees() external nonReentrant onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "No fees to withdraw");

        address payable ownerPayable = payable(owner());
        (bool success, ) = ownerPayable.call{value: balance}("");
        require(success, "Transfer failed");

        emit MarketplaceFeesWithdrawn(ownerPayable, balance);
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

        activeListingIds.push(_tokenId);
        activeListingIndex[_tokenId] = activeListingIds.length - 1;
        listingTimestamps[_tokenId] = block.timestamp;

        userListedTokens[_seller].push(_tokenId);
        userListedTokenIndex[_seller][_tokenId] =
            userListedTokens[_seller].length -
            1;

        landToken.transferFrom(_seller, address(this), _tokenId);
        emit TokenListed(_tokenId, _price, _seller);
        emit ActiveListingsUpdated(activeListingIds.length);
    }

    /**
     * @dev Permet à un relayer d'acheter un token pour un utilisateur.
     * @param _tokenId L'ID du token à acheter.
     * @param _buyer L'adresse de l'acheteur.
     */
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

        // Désactiver le listing avant les transferts
        listing.isActive = false;

        _removeFromActiveListings(_tokenId);
        _removeFromUserListings(seller, _tokenId);
        delete listingTimestamps[_tokenId];

        // Calculer les frais de marketplace
        uint256 marketplaceFee = (price * marketplaceFeePercentage) /
            PERCENTAGE_BASE;
        uint256 sellerAmount = price - marketplaceFee;

        // Transfert du token
        landToken.transferFrom(address(this), _buyer, _tokenId);

        // Transfert des fonds au vendeur
        (bool sellerSuccess, ) = payable(seller).call{value: sellerAmount}("");
        if (!sellerSuccess) revert TransferFailed();

        // Enregistrer les frais collectés
        if (marketplaceFee > 0) {
            emit MarketplaceFeesCollected(_tokenId, marketplaceFee);
        }

        // Remboursement de l'excédent
        uint256 excess = msg.value - price;
        if (excess > 0) {
            (bool refundSuccess, ) = payable(msg.sender).call{value: excess}(
                ""
            );
            if (!refundSuccess) revert TransferFailed();
        }

        emit TokenSold(_tokenId, seller, _buyer, price);
        emit ActiveListingsUpdated(activeListingIds.length);
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

        activeListingIds.push(_tokenId);
        activeListingIndex[_tokenId] = activeListingIds.length - 1;
        listingTimestamps[_tokenId] = block.timestamp;

        userListedTokens[msg.sender].push(_tokenId);
        userListedTokenIndex[msg.sender][_tokenId] =
            userListedTokens[msg.sender].length -
            1;

        // Appel externe après la mise à jour de l'état
        landToken.transferFrom(msg.sender, address(this), _tokenId);

        emit TokenListed(_tokenId, _price, msg.sender);
        emit ActiveListingsUpdated(activeListingIds.length);
    }

    /**
     * @dev Liste plusieurs tokens à la vente en une seule transaction.
     * @param _tokenIds Tableau des IDs des tokens à lister.
     * @param _prices Tableau des prix demandés pour chaque token.
     */
    function listMultipleTokens(
        uint256[] calldata _tokenIds,
        uint256[] calldata _prices
    ) external nonReentrant {
        require(_tokenIds.length == _prices.length, "Arrays length mismatch");
        require(_tokenIds.length > 0, "Empty arrays");

        for (uint256 i = 0; i < _tokenIds.length; i++) {
            uint256 tokenId = _tokenIds[i];
            uint256 price = _prices[i];

            if (landToken.ownerOf(tokenId) != msg.sender)
                revert NotTokenOwner();
            if (price == 0) revert InvalidPrice();
            if (listings[tokenId].isActive) revert AlreadyListed();

            listings[tokenId] = Listing({
                tokenId: tokenId,
                price: price,
                seller: msg.sender,
                isActive: true
            });

            activeListingIds.push(tokenId);
            activeListingIndex[tokenId] = activeListingIds.length - 1;
            listingTimestamps[tokenId] = block.timestamp;

            userListedTokens[msg.sender].push(tokenId);
            userListedTokenIndex[msg.sender][tokenId] =
                userListedTokens[msg.sender].length -
                1;

            landToken.transferFrom(msg.sender, address(this), tokenId);
            emit TokenListed(tokenId, price, msg.sender);
        }

        emit MultipleTokensListed(msg.sender, _tokenIds.length);
        emit ActiveListingsUpdated(activeListingIds.length);
    }

    /**
     * @dev Achète un token listé à la vente avec frais de marketplace.
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

        _removeFromActiveListings(_tokenId);
        _removeFromUserListings(seller, _tokenId);
        delete listingTimestamps[_tokenId];

        // Calculer les frais de marketplace
        uint256 marketplaceFee = (price * marketplaceFeePercentage) /
            PERCENTAGE_BASE;
        uint256 sellerAmount = price - marketplaceFee;

        // Transfert du token
        landToken.transferFrom(address(this), msg.sender, _tokenId);

        // Transfert des fonds au vendeur
        (bool sellerSuccess, ) = payable(seller).call{value: sellerAmount}("");
        if (!sellerSuccess) revert TransferFailed();

        // Enregistrer les frais collectés
        if (marketplaceFee > 0) {
            emit MarketplaceFeesCollected(_tokenId, marketplaceFee);
        }

        // Remboursement de l'excédent
        uint256 excess = msg.value - price;
        if (excess > 0) {
            (bool refundSuccess, ) = payable(msg.sender).call{value: excess}(
                ""
            );
            if (!refundSuccess) revert TransferFailed();
        }

        emit TokenSold(_tokenId, seller, msg.sender, price);
        emit ActiveListingsUpdated(activeListingIds.length);
    }

    /**
     * @dev Achète plusieurs tokens listés à la vente en une seule transaction.
     * @param _tokenIds Tableau des IDs des tokens à acheter.
     */
    function buyMultipleTokens(
        uint256[] calldata _tokenIds
    ) external payable nonReentrant {
        require(_tokenIds.length > 0, "Empty token IDs array");

        uint256 totalPrice = 0;
        address[] memory sellers = new address[](_tokenIds.length);
        uint256[] memory prices = new uint256[](_tokenIds.length);
        uint256[] memory marketplaceFees = new uint256[](_tokenIds.length);
        uint256[] memory sellerAmounts = new uint256[](_tokenIds.length);

        // Première étape: vérifier tous les tokens et calculer le prix total
        for (uint256 i = 0; i < _tokenIds.length; i++) {
            uint256 tokenId = _tokenIds[i];
            Listing storage listing = listings[tokenId];

            if (!listing.isActive) revert NotListed();
            if (!landToken.exists(tokenId)) revert TokenDoesNotExist();

            uint256 price = listing.price;
            totalPrice += price;

            // Stocker les informations pour le traitement ultérieur
            sellers[i] = listing.seller;
            prices[i] = price;

            // Calculer les frais de marketplace et le montant du vendeur
            marketplaceFees[i] =
                (price * marketplaceFeePercentage) /
                PERCENTAGE_BASE;
            sellerAmounts[i] = price - marketplaceFees[i];

            // Désactiver le listing
            listing.isActive = false;

            _removeFromActiveListings(tokenId);
            _removeFromUserListings(sellers[i], tokenId);

            delete listingTimestamps[tokenId];
        }

        // Vérifier que l'acheteur a envoyé assez d'ETH
        if (msg.value < totalPrice) revert InsufficientFunds();

        // Deuxième étape: transférer les tokens et les fonds
        uint256 totalMarketplaceFee = 0;

        for (uint256 i = 0; i < _tokenIds.length; i++) {
            uint256 tokenId = _tokenIds[i];
            address seller = sellers[i];
            uint256 sellerAmount = sellerAmounts[i];
            uint256 marketplaceFee = marketplaceFees[i];

            // Transférer le token
            landToken.transferFrom(address(this), msg.sender, tokenId);

            // Transférer les fonds au vendeur
            (bool sellerSuccess, ) = payable(seller).call{value: sellerAmount}(
                ""
            );
            if (!sellerSuccess) revert TransferFailed();

            // Ajouter au total des frais de marketplace
            totalMarketplaceFee += marketplaceFee;

            // Émettre l'événement de vente
            emit TokenSold(tokenId, seller, msg.sender, prices[i]);
            emit MarketplaceFeesCollected(tokenId, marketplaceFee);
        }

        // Émettre un événement pour l'achat groupé
        emit MultipleTokensBought(
            msg.sender,
            _tokenIds.length,
            totalPrice,
            totalMarketplaceFee
        );
        emit ActiveListingsUpdated(activeListingIds.length);

        // Remboursement de l'excédent
        uint256 excess = msg.value - totalPrice;
        if (excess > 0) {
            (bool refundSuccess, ) = payable(msg.sender).call{value: excess}(
                ""
            );
            if (!refundSuccess) revert TransferFailed();
        }
    }

    /**
     * @dev Permet à un relayer d'acheter plusieurs tokens pour un utilisateur.
     * @param _tokenIds Tableau des IDs des tokens à acheter.
     * @param _buyer L'adresse de l'acheteur.
     */
    function buyMultipleTokensForUser(
        uint256[] calldata _tokenIds,
        address _buyer
    ) external payable nonReentrant onlyRelayerOrOwner {
        require(_tokenIds.length > 0, "Empty token IDs array");

        uint256 totalPrice = 0;
        address[] memory sellers = new address[](_tokenIds.length);
        uint256[] memory prices = new uint256[](_tokenIds.length);
        uint256[] memory marketplaceFees = new uint256[](_tokenIds.length);
        uint256[] memory sellerAmounts = new uint256[](_tokenIds.length);

        // Première étape: vérifier tous les tokens et calculer le prix total
        for (uint256 i = 0; i < _tokenIds.length; i++) {
            uint256 tokenId = _tokenIds[i];
            Listing storage listing = listings[tokenId];

            if (!listing.isActive) revert NotListed();
            if (!landToken.exists(tokenId)) revert TokenDoesNotExist();

            uint256 price = listing.price;
            totalPrice += price;

            // Stocker les informations pour le traitement ultérieur
            sellers[i] = listing.seller;
            prices[i] = price;

            // Calculer les frais de marketplace et le montant du vendeur
            marketplaceFees[i] =
                (price * marketplaceFeePercentage) /
                PERCENTAGE_BASE;
            sellerAmounts[i] = price - marketplaceFees[i];

            // Désactiver le listing
            listing.isActive = false;

            // NOUVEAU CODE: Retirer des index
            _removeFromActiveListings(tokenId);
            _removeFromUserListings(sellers[i], tokenId);
            delete listingTimestamps[tokenId];
        }

        // Vérifier que le relayer a envoyé assez d'ETH
        if (msg.value < totalPrice) revert InsufficientFunds();

        // Deuxième étape: transférer les tokens et les fonds
        uint256 totalMarketplaceFee = 0;

        for (uint256 i = 0; i < _tokenIds.length; i++) {
            uint256 tokenId = _tokenIds[i];
            address seller = sellers[i];
            uint256 sellerAmount = sellerAmounts[i];
            uint256 marketplaceFee = marketplaceFees[i];

            // Transférer le token
            landToken.transferFrom(address(this), _buyer, tokenId);

            // Transférer les fonds au vendeur
            (bool sellerSuccess, ) = payable(seller).call{value: sellerAmount}(
                ""
            );
            if (!sellerSuccess) revert TransferFailed();

            // Ajouter au total des frais de marketplace
            totalMarketplaceFee += marketplaceFee;

            // Émettre l'événement de vente
            emit TokenSold(tokenId, seller, _buyer, prices[i]);
            emit MarketplaceFeesCollected(tokenId, marketplaceFee);
        }

        // Émettre un événement pour l'achat groupé
        emit MultipleTokensBought(
            _buyer,
            _tokenIds.length,
            totalPrice,
            totalMarketplaceFee
        );
        emit ActiveListingsUpdated(activeListingIds.length);

        // Remboursement de l'excédent
        uint256 excess = msg.value - totalPrice;
        if (excess > 0) {
            (bool refundSuccess, ) = payable(msg.sender).call{value: excess}(
                ""
            );
            if (!refundSuccess) revert TransferFailed();
        }
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

        _removeFromActiveListings(_tokenId);
        _removeFromUserListings(msg.sender, _tokenId);
        delete listingTimestamps[_tokenId];

        // Émettre l'événement avant l'appel externe
        emit ListingCancelled(_tokenId);
        emit ActiveListingsUpdated(activeListingIds.length);

        // External call last
        landToken.transferFrom(address(this), msg.sender, _tokenId);
    }

    /**
     * @dev Retire un token de la liste des tokens actifs.
     * @param _tokenId L'ID du token à retirer.
     */
    function _removeFromActiveListings(uint256 _tokenId) private {
        uint256 index = activeListingIndex[_tokenId];
        uint256 lastIndex = activeListingIds.length - 1;

        if (index != lastIndex) {
            uint256 lastTokenId = activeListingIds[lastIndex];
            activeListingIds[index] = lastTokenId;
            activeListingIndex[lastTokenId] = index;
        }

        activeListingIds.pop();
        delete activeListingIndex[_tokenId];
    }

    /**
     * @dev Retire un token de la liste des tokens d'un utilisateur.
     * @param _user L'adresse de l'utilisateur.
     * @param _tokenId L'ID du token à retirer.
     */
    function _removeFromUserListings(address _user, uint256 _tokenId) private {
        uint256[] storage userTokens = userListedTokens[_user];
        uint256 index = userListedTokenIndex[_user][_tokenId];
        uint256 lastIndex = userTokens.length - 1;

        if (index != lastIndex) {
            uint256 lastTokenId = userTokens[lastIndex];
            userTokens[index] = lastTokenId;
            userListedTokenIndex[_user][lastTokenId] = index;
        }

        userTokens.pop();
        delete userListedTokenIndex[_user][_tokenId];
    }

    /**
     * @dev Récupère tous les tokens actifs listés sur le marketplace.
     * @return Un tableau des IDs des tokens actifs.
     */
    function getAllActiveListings() external view returns (uint256[] memory) {
        return activeListingIds;
    }

    /**
     * @dev Récupère une page des tokens actifs listés sur le marketplace.
     * @param _offset L'index de départ.
     * @param _limit Le nombre maximum de tokens à retourner.
     * @return tokenIds Un tableau des IDs des tokens actifs pour la page demandée.
     */
    function getActiveListingsPage(
        uint256 _offset,
        uint256 _limit
    ) external view returns (uint256[] memory tokenIds) {
        uint256 total = activeListingIds.length;

        if (_offset >= total) {
            return new uint256[](0);
        }

        // Ajuster la limite si nécessaire
        uint256 limit = _limit;
        if (_offset + limit > total) {
            limit = total - _offset;
        }

        // Créer le tableau de résultats
        tokenIds = new uint256[](limit);
        for (uint256 i = 0; i < limit; i++) {
            tokenIds[i] = activeListingIds[_offset + i];
        }

        return tokenIds;
    }

    /**
     * @dev Récupère les détails de plusieurs listings en une seule requête.
     * @param _tokenIds Les IDs des tokens à vérifier.
     * @return prices Les prix des tokens.
     * @return sellers Les vendeurs des tokens.
     * @return isActives Si les tokens sont actifs.
     * @return timestamps Les horodatages des listings.
     */
    function getMultipleListingDetails(
        uint256[] calldata _tokenIds
    )
        external
        view
        returns (
            uint256[] memory prices,
            address[] memory sellers,
            bool[] memory isActives,
            uint256[] memory timestamps
        )
    {
        uint256 length = _tokenIds.length;
        prices = new uint256[](length);
        sellers = new address[](length);
        isActives = new bool[](length);
        timestamps = new uint256[](length);

        for (uint256 i = 0; i < length; i++) {
            uint256 tokenId = _tokenIds[i];
            Listing storage listing = listings[tokenId];

            prices[i] = listing.price;
            sellers[i] = listing.seller;
            isActives[i] = listing.isActive;
            timestamps[i] = listingTimestamps[tokenId];
        }

        return (prices, sellers, isActives, timestamps);
    }

    /**
     * @dev Récupère tous les tokens listés par un utilisateur.
     * @param _user L'adresse de l'utilisateur.
     * @return Un tableau des IDs des tokens listés par l'utilisateur.
     */
    function getListingsByUser(
        address _user
    ) external view returns (uint256[] memory) {
        return userListedTokens[_user];
    }

    /**
     * @dev Vérifie si un tableau de tokens est toujours en vente.
     * @param _tokenIds Les IDs des tokens à vérifier.
     * @return results Un tableau de booléens indiquant si chaque token est en vente.
     */
    function checkActiveListings(
        uint256[] calldata _tokenIds
    ) external view returns (bool[] memory results) {
        results = new bool[](_tokenIds.length);

        for (uint256 i = 0; i < _tokenIds.length; i++) {
            results[i] = listings[_tokenIds[i]].isActive;
        }

        return results;
    }

    /**
     * @dev Retourne le nombre total de tokens actifs.
     * @return Le nombre de tokens actifs.
     */
    function getActiveListingsCount() external view returns (uint256) {
        return activeListingIds.length;
    }
}
