// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

import "@openzeppelin/contracts/security/Pausable.sol";
import "./LandRegistry.sol";
import "./Ownable.sol";

contract LandToken is
    ERC721,
    ERC721URIStorage,
    ReentrancyGuard,
    Pausable,
    Ownable
{
    using Counters for Counters.Counter;

    // Compteur pour générer des IDs uniques pour chaque token
    Counters.Counter private _tokenIds;

    // Référence vers le contrat LandRegistry
    LandRegistry public immutable landRegistry;

    // Variables pour les frais de plateforme
    uint256 public platformFeePercentage = 500;
    uint256 public constant PERCENTAGE_BASE = 10000;

    // Structure pour stocker les détails du token
    struct TokenData {
        uint256 landId;
        uint256 tokenNumber;
        uint256 purchasePrice;
        uint256 mintDate;
    }

    // Mapping pour stocker les détails de chaque token
    mapping(uint256 => TokenData) public tokenData;

    // Mapping pour associer chaque terrain à ses tokens
    mapping(uint256 => uint256[]) public landTokens;
    mapping(address => bool) public relayers;
    // Mapping pour suivre les tokens possédés par chaque utilisateur
    mapping(address => uint256[]) private userOwnedTokens;
    // Mapping pour suivre l'index d'un token dans le tableau userOwnedTokens
    mapping(address => mapping(uint256 => uint256)) private userOwnedTokenIndex;

    // Événements
    event TokenMinted(
        uint256 indexed landId,
        uint256 indexed tokenId,
        address owner
    );
    event TokenTransferred(uint256 indexed tokenId, address from, address to);
    event LandTokenized(uint256 indexed landId);
    event EtherWithdrawn(address indexed to, uint256 amount);
    event RelayerAdded(address indexed relayer);
    event RelayerRemoved(address indexed relayer);

    // événements pour la distribution des fonds
    event PaymentToOwner(
        uint256 indexed landId,
        address indexed owner,
        uint256 amount
    );
    event PlatformFeesCollected(uint256 indexed landId, uint256 amount);
    event PlatformFeeUpdated(uint256 newFeePercentage);
    event PlatformFeesWithdrawn(address indexed to, uint256 amount);
    event TokensBatchMinted(
        uint256 indexed landId,
        address indexed recipient,
        uint256 quantity,
        uint256[] tokenIds
    );

    error InvalidRegistry();
    error NoEtherToWithdraw();
    error TransferFailed();
    error LandNotTokenized();
    error LandNotValidated();
    error NoTokensAvailable();
    error InsufficientPayment();
    error InvalidTransferParameters();
    error UnauthorizedRelayer();
    error InvalidRelayer();
    error InvalidFeePercentage();
    error DistributionFailed();
    error NoTokensToMint();

    constructor(
        address _landRegistryAddress
    ) ERC721("Real Estate Token", "RET") {
        if (_landRegistryAddress == address(0)) revert InvalidRegistry();
        landRegistry = LandRegistry(_landRegistryAddress);
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
     * @dev Required override for ERC721/ERC721URIStorage compatibility
     */
    function _burn(
        uint256 tokenId
    ) internal override(ERC721, ERC721URIStorage) {
        super._burn(tokenId);
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

    /**
     * @dev Implémentation combinée de supportsInterface.
     * @param interfaceId Identifiant de l'interface.
     * @return true si l'interface est supportée, false sinon.
     */
    function supportsInterface(
        bytes4 interfaceId
    ) public view override(ERC721, ERC721URIStorage) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    /**
     * @dev Crée un nouveau token pour un terrain donné.
     * @param _landId ID du terrain.
     * @return ID du nouveau token.
     */
    function mintToken(
        uint256 _landId
    ) external payable whenNotPaused nonReentrant returns (uint256) {
        (
            bool isTokenized,
            LandRegistry.ValidationStatus status,
            uint256 availableTokens,
            uint256 pricePerToken,

        ) = landRegistry.getLandDetails(_landId);

        if (!isTokenized) revert LandNotTokenized();
        if (status != LandRegistry.ValidationStatus.Valide)
            revert LandNotValidated();
        if (availableTokens == 0) revert NoTokensAvailable();
        if (msg.value < pricePerToken) revert InsufficientPayment();

        // Récupérer l'adresse du propriétaire du terrain
        address owner = landRegistry.getLandOwner(_landId);

        // Distribuer les fonds selon le pourcentage configuré
        bool distributionSuccess = distributePayment(owner, msg.value, _landId);
        if (!distributionSuccess) revert DistributionFailed();

        _tokenIds.increment();
        uint256 newTokenId = _tokenIds.current();

        tokenData[newTokenId] = TokenData({
            landId: _landId,
            tokenNumber: newTokenId,
            purchasePrice: pricePerToken,
            mintDate: block.timestamp
        });

        landTokens[_landId].push(newTokenId);
        landRegistry.updateAvailableTokens(_landId, 1);

        userOwnedTokens[msg.sender].push(newTokenId);
        userOwnedTokenIndex[msg.sender][newTokenId] =
            userOwnedTokens[msg.sender].length -
            1;

        _safeMint(msg.sender, newTokenId);

        emit TokenMinted(_landId, newTokenId, msg.sender);
        return newTokenId;
    }

    /**
     * @dev Crée plusieurs tokens pour un terrain donné en une seule transaction.
     * @param _landId ID du terrain.
     * @param _quantity Nombre de tokens à minter.
     * @return Un tableau des IDs des nouveaux tokens créés.
     */
    function mintMultipleTokens(
        uint256 _landId,
        uint256 _quantity
    ) external payable whenNotPaused nonReentrant returns (uint256[] memory) {
        if (_quantity == 0) revert NoTokensToMint();

        (
            bool isTokenized,
            LandRegistry.ValidationStatus status,
            uint256 availableTokens,
            uint256 pricePerToken,

        ) = landRegistry.getLandDetails(_landId);

        if (!isTokenized) revert LandNotTokenized();
        if (status != LandRegistry.ValidationStatus.Valide)
            revert LandNotValidated();
        if (availableTokens < _quantity) revert NoTokensAvailable();
        if (msg.value < pricePerToken * _quantity) revert InsufficientPayment();

        // Récupérer l'adresse du propriétaire du terrain
        address owner = landRegistry.getLandOwner(_landId);

        // Distribuer les fonds selon le pourcentage configuré
        bool distributionSuccess = distributePayment(owner, msg.value, _landId);
        if (!distributionSuccess) revert DistributionFailed();

        uint256[] memory tokenIds = new uint256[](_quantity);

        for (uint256 i = 0; i < _quantity; i++) {
            _tokenIds.increment();
            uint256 newTokenId = _tokenIds.current();

            tokenData[newTokenId] = TokenData({
                landId: _landId,
                tokenNumber: newTokenId,
                purchasePrice: pricePerToken,
                mintDate: block.timestamp
            });

            landTokens[_landId].push(newTokenId);
            tokenIds[i] = newTokenId;

            userOwnedTokens[msg.sender].push(newTokenId);
            userOwnedTokenIndex[msg.sender][newTokenId] =
                userOwnedTokens[msg.sender].length -
                1;

            _safeMint(msg.sender, newTokenId);
            emit TokenMinted(_landId, newTokenId, msg.sender);
        }

        // Mettre à jour le nombre de tokens disponibles
        landRegistry.updateAvailableTokens(_landId, _quantity);

        emit TokensBatchMinted(_landId, msg.sender, _quantity, tokenIds);

        return tokenIds;
    }

    /**
     * @dev Tokenize un terrain dans le registre.
     * Cette fonction ne peut être appelée que par le propriétaire du contrat.
     * @param _landId L'ID du terrain à tokenizer
     */
    function tokenizeLand(uint256 _landId) external {
        // Émettre l'événement avant l'appel externe
        emit LandTokenized(_landId);
        // Faire l'appel externe en dernier
        landRegistry.tokenizeLand(_landId);
    }

    function withdrawEther() external nonReentrant onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "No ether to withdraw");

        address payable ownerPayable = payable(owner());
        (bool success, ) = ownerPayable.call{value: balance}("");
        require(success, "Transfer failed");

        emit EtherWithdrawn(ownerPayable, balance);
    }

    /**
     * @dev Transfère un token d'un propriétaire à un autre.
     * @param _to Adresse du destinataire.
     * @param _tokenId ID du token à transférer.
     */
    function transferToken(address _to, uint256 _tokenId) external {
        require(_to != address(0), "Transfer to zero address");
        require(ownerOf(_tokenId) != address(0), "Token does not exist"); // Vérifie si le token existe
        require(
            ownerOf(_tokenId) == msg.sender || // Propriétaire actuel
                isApprovedForAll(ownerOf(_tokenId), _to) || // Approuvé pour tous
                getApproved(_tokenId) == msg.sender, // Approuvé spécifiquement
            "Not authorized"
        );

        // Mettre à jour les tokens des utilisateurs
        address from = ownerOf(_tokenId);
        _removeFromUserTokens(from, _tokenId);
        userOwnedTokens[_to].push(_tokenId);
        userOwnedTokenIndex[_to][_tokenId] = userOwnedTokens[_to].length - 1;

        // Effectuer le transfert sécurisé
        safeTransferFrom(msg.sender, _to, _tokenId);

        // Émettre un événement
        emit TokenTransferred(_tokenId, msg.sender, _to);
    }

    /**
     * @dev Vérifie si un token existe.
     * @param _tokenId ID du token.
     * @return true si le token existe, false sinon.
     */
    function exists(uint256 _tokenId) external view returns (bool) {
        try this.ownerOf(_tokenId) returns (address) {
            return true; // Si ownerOf ne lève pas d'exception, le token existe
        } catch {
            return false; // Sinon, le token n'existe pas
        }
    }

     /**
     * @dev Implémentation personnalisée de tokenURI.
     * @param tokenId ID du token.
     * @return URI du token.
     */
    function tokenURI(
        uint256 tokenId
    ) public view override(ERC721, ERC721URIStorage) returns (string memory) {
        return super.tokenURI(tokenId);
    }

    /**
     * @dev Retourne tous les tokens associés à un terrain.
     * @param _landId ID du terrain.
     * @return Liste des IDs des tokens associés au terrain.
     */
    function getTokensByLand(
        uint256 _landId
    ) external view returns (uint256[] memory) {
        return landTokens[_landId];
    }

    /**
     * @dev Permet au propriétaire de modifier le pourcentage des frais de plateforme.
     * @param _newFeePercentage Nouveau pourcentage de frais (en base 10000, 500 = 5%).
     */
    function setPlatformFeePercentage(
        uint256 _newFeePercentage
    ) external onlyOwner {
        if (_newFeePercentage > 2000) revert InvalidFeePercentage(); // Max 20%

        platformFeePercentage = _newFeePercentage;

        emit PlatformFeeUpdated(_newFeePercentage);
    }

    /**
     * @dev Distribue les fonds entre le propriétaire du terrain et la plateforme.
     * @param _landOwner Adresse du propriétaire du terrain.
     * @param _amount Montant total à distribuer.
     * @param _landId ID du terrain pour les événements.
     * @return true si la distribution a réussi.
     */
    function distributePayment(
        address _landOwner,
        uint256 _amount,
        uint256 _landId
    ) internal returns (bool) {
        // Calculer les parts
        uint256 platformFee = (_amount * platformFeePercentage) /
            PERCENTAGE_BASE;
        uint256 ownerAmount = _amount - platformFee;

        // Transférer au propriétaire du terrain
        if (ownerAmount > 0) {
            (bool ownerSuccess, ) = payable(_landOwner).call{
                value: ownerAmount
            }("");
            if (!ownerSuccess) return false;

            emit PaymentToOwner(_landId, _landOwner, ownerAmount);
        }

        // Les frais de plateforme restent dans le contrat pour être retirés plus tard
        if (platformFee > 0) {
            emit PlatformFeesCollected(_landId, platformFee);
        }

        return true;
    }

    /**
     * @dev Permet au propriétaire du contrat de retirer les frais de plateforme collectés.
     */
    function withdrawPlatformFees() external nonReentrant onlyOwner {
        uint256 balance = address(this).balance;
        if (balance == 0) revert NoEtherToWithdraw();

        address payable ownerPayable = payable(owner());
        (bool success, ) = ownerPayable.call{value: balance}("");
        if (!success) revert TransferFailed();

        emit PlatformFeesWithdrawn(ownerPayable, balance);
    }

    /**
     * @dev Retourne le pourcentage de frais de plateforme actuel.
     * @return Le pourcentage de frais (500 = 5.00%)
     */
    function getPlatformFeePercentage() external view returns (uint256) {
        return platformFeePercentage;
    }

    /**
     * @dev Calcule combien un propriétaire recevrait et combien la plateforme prendrait pour un montant donné.
     * @param _amount Le montant total.
     * @return ownerAmount Montant qui irait au propriétaire.
     * @return platformAmount Montant qui irait à la plateforme.
     */
    function calculateDistribution(
        uint256 _amount
    ) external view returns (uint256 ownerAmount, uint256 platformAmount) {
        platformAmount = (_amount * platformFeePercentage) / PERCENTAGE_BASE;
        ownerAmount = _amount - platformAmount;
        return (ownerAmount, platformAmount);
    }

    /**
     * @dev Retire un token de la liste des tokens d'un utilisateur.
     * @param _user L'adresse de l'utilisateur.
     * @param _tokenId L'ID du token à retirer.
     */
    function _removeFromUserTokens(address _user, uint256 _tokenId) private {
        if (userOwnedTokens[_user].length == 0) return;

        uint256 tokenIndex = userOwnedTokenIndex[_user][_tokenId];
        uint256 lastIndex = userOwnedTokens[_user].length - 1;

        if (tokenIndex != lastIndex) {
            uint256 lastTokenId = userOwnedTokens[_user][lastIndex];
            userOwnedTokens[_user][tokenIndex] = lastTokenId;
            userOwnedTokenIndex[_user][lastTokenId] = tokenIndex;
        }

        userOwnedTokens[_user].pop();
        delete userOwnedTokenIndex[_user][_tokenId];
    }
}
