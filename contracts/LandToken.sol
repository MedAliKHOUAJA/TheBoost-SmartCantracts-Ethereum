// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "./LandRegistry.sol";
import "./Ownable.sol";

contract LandToken is ERC721, ERC721URIStorage, ReentrancyGuard,Ownable {
    using Counters for Counters.Counter;

    // Compteur pour générer des IDs uniques pour chaque token
    Counters.Counter private _tokenIds;

    // Référence vers le contrat LandRegistry
    LandRegistry public landRegistry;

    // Structure pour stocker les détails du token
    struct TokenData {
        uint256 landId; // ID du terrain associé
        uint256 tokenNumber; // Numéro du token
        uint256 purchasePrice; // Prix d'achat du token
        uint256 mintDate; // Date de création du token
    }

    // Mapping pour stocker les détails de chaque token
    mapping(uint256 => TokenData) public tokenData;

    // Mapping pour associer chaque terrain à ses tokens
    mapping(uint256 => uint256[]) public landTokens;

    // Événements
    event TokenMinted(uint256 indexed landId, uint256 indexed tokenId, address owner);
    event TokenTransferred(uint256 indexed tokenId, address from, address to);
    event LandTokenized(uint256 indexed landId);

    constructor(address _landRegistryAddress) ERC721("Real Estate Token", "RET") {
        require(_landRegistryAddress != address(0), "Invalid registry address");
        landRegistry = LandRegistry(_landRegistryAddress);
    }

        /**
     * @dev Remplace la fonction _burn pour résoudre le conflit entre ERC721 et ERC721URIStorage.
     */
    function _burn(uint256 tokenId) internal override(ERC721, ERC721URIStorage) {
        super._burn(tokenId);
    }

     /**
     * @dev Tokenize un terrain dans le registre.
     * Cette fonction ne peut être appelée que par le propriétaire du contrat.
     * @param _landId L'ID du terrain à tokenizer
     */
    function tokenizeLand(uint256 _landId) external onlyOwner {
        // Vérifie que le terrain existe et est validé dans le registre
        (bool isTokenized, LandRegistry.ValidationStatus status, , ,) = landRegistry.getLandDetails(_landId);
        require(!isTokenized, "Terrain deja tokenise");
        require(status == LandRegistry.ValidationStatus.Valide, "Terrain non valide");
        
        // Appelle la fonction tokenizeLand du contrat LandRegistry
        landRegistry.tokenizeLand(_landId);
        
        // Émet un événement pour la tokenisation
        emit LandTokenized(_landId);
    }


    /**
     * @dev Crée un nouveau token pour un terrain donné.
     * @param _landId ID du terrain.
     * @return ID du nouveau token.
     */
   function mintToken(uint256 _landId) external payable nonReentrant returns (uint256) {
    // Récupérer les données du terrain depuis LandRegistry
    (bool isTokenized, LandRegistry.ValidationStatus status, uint256 availableTokens, uint256 pricePerToken, ) = landRegistry.getLandDetails(_landId);

    // Vérifications sur le terrain
    require(isTokenized, "Land not tokenized");
    require(status == LandRegistry.ValidationStatus.Valide, "Land not validated");
    require(availableTokens > 0, "No tokens available");
    require(msg.value >= pricePerToken, "Insufficient payment");

    // Incrémenter le compteur de tokens
    _tokenIds.increment();
    uint256 newTokenId = _tokenIds.current();

    // Stocker les détails du token
    tokenData[newTokenId] = TokenData({
        landId: _landId,
        tokenNumber: newTokenId,
        purchasePrice: msg.value,
        mintDate: block.timestamp
    });

    // Mettre à jour les tokens disponibles pour le terrain via LandRegistry
    landRegistry.updateAvailableTokens(_landId, 1);

    // Associer le token au terrain
    landTokens[_landId].push(newTokenId);

    // Créer et attribuer le token
    _safeMint(msg.sender, newTokenId);

    // Émettre un événement
    emit TokenMinted(_landId, newTokenId, msg.sender);

    return newTokenId;
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
 * @dev Retourne les détails d'un token.
 * @param _tokenId ID du token.
 * @return landId ID du terrain associé au token.
 * @return tokenNumber Numéro unique du token.
 * @return purchasePrice Prix d'achat du token.
 * @return mintDate Date de création (mint) du token.
 */

    /**
     * @dev Retourne tous les tokens associés à un terrain.
     * @param _landId ID du terrain.
     * @return Liste des IDs des tokens associés au terrain.
     */
    function getTokensByLand(uint256 _landId) external view returns (uint256[] memory) {
        return landTokens[_landId];
    }

    /**
     * @dev Implémentation personnalisée de tokenURI.
     * @param tokenId ID du token.
     * @return URI du token.
     */
    function tokenURI(uint256 tokenId) public view override(ERC721, ERC721URIStorage) returns (string memory) {
        return super.tokenURI(tokenId);
    }

    /**
     * @dev Implémentation combinée de supportsInterface.
     * @param interfaceId Identifiant de l'interface.
     * @return true si l'interface est supportée, false sinon.
     */
    function supportsInterface(bytes4 interfaceId) public view override(ERC721, ERC721URIStorage) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}