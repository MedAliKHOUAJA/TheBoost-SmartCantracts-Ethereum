// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Ownable.sol";

contract LandRegistry is Ownable {
    struct Land {
        string location;
        uint256 surface;
        address owner;
        bool isRegistered;
        uint256 registrationDate;
        ValidationStatus status;
        uint256 totalTokens;
        uint256 availableTokens;
        uint256 pricePerToken;
        bool isTokenized;
        string cid; // CID IPFS des documents associés au terrain
    }

    struct Validation {
        address validator; // Adresse du validateur
        uint256 timestamp; // Timestamp de la validation
        string cidComments; // CID IPFS contenant les commentaires
        ValidatorType validatorType; // Type de validateur
        bool isValidated; // Indique si le terrain a été validé
    }

    enum ValidationStatus {
        EnAttente,
        Valide,
        Rejete
    }

    enum ValidatorType {
        Notaire,
        Geometre,
        ExpertJuridique
    }

    mapping(uint256 => Land) public lands;
    mapping(uint256 => Validation[]) public landValidations;
    mapping(address => bool) public validators;
    mapping(address => ValidatorType) public validatorTypes;

    uint256 private _landCounter;
    // variable pour le tokenizer
    address public tokenizer;

    event LandRegistered(
        uint256 indexed landId,
        string location,
        address owner,
        uint256 totalTokens,
        uint256 pricePerToken,
        string cid
    );

    event ValidatorAdded(
        address indexed validator,
        ValidatorType validatorType
    );

    event ValidationAdded(
        uint256 indexed landId,
        address validator,
        bool isValidated
    );

    event TokenizerSet(
        address indexed previousTokenizer,
        address indexed newTokenizer
    );
    event LandTokenized(uint256 indexed landId);

    /**
     * @dev Ajoute un validateur.
     * @param _validator Adresse du validateur.
     * @param _type Type de validateur.
     */
    function addValidator(
        address _validator,
        ValidatorType _type
    ) external onlyOwner {
        validators[_validator] = true;
        validatorTypes[_validator] = _type;
        emit ValidatorAdded(_validator, _type);
    }

    /**
     * @dev Valide ou rejette un terrain.
     * @param _landId ID du terrain.
     * @param _cidComments CID IPFS contenant les commentaires.
     * @param _isValid Indique si le terrain est validé.
     */
    function validateLand(
        uint256 _landId,
        string memory _cidComments,
        bool _isValid
    ) external {
        require(validators[msg.sender], "Non autorise");
        require(bytes(_cidComments).length > 0, "CID Comments required");

        // Vérifier si le validateur a déjà validé ce terrain
        for (uint256 i = 0; i < landValidations[_landId].length; i++) {
            if (landValidations[_landId][i].validator == msg.sender) {
                revert("Validator already validated this land");
            }
        }

        // Ajouter la validation à l'historique
        landValidations[_landId].push(
            Validation({
                validator: msg.sender,
                timestamp: block.timestamp,
                cidComments: _cidComments,
                validatorType: validatorTypes[msg.sender],
                isValidated: _isValid
            })
        );

        // Mettre à jour le statut du terrain
        if (!_isValid) {
            lands[_landId].status = ValidationStatus.Rejete;
        } else if (_checkAllValidations(_landId)) {
            lands[_landId].status = ValidationStatus.Valide;
        }

        emit ValidationAdded(_landId, msg.sender, _isValid);
    }

    /**
     * @dev Vérifie si toutes les validations nécessaires ont été effectuées pour un terrain.
     * @param _landId ID du terrain.
     * @return true si toutes les validations sont valides, false sinon.
     */
    function _checkAllValidations(uint256 _landId) private view returns (bool) {
        bool hasNotaire = false;
        bool hasGeometre = false;
        bool hasExpert = false;

        for (uint256 i = 0; i < landValidations[_landId].length; i++) {
            Validation memory validation = landValidations[_landId][i];
            if (!validation.isValidated) continue; // Ignorer les validations non approuvées

            ValidatorType vType = validation.validatorType;
            if (vType == ValidatorType.Notaire && !hasNotaire) {
                hasNotaire = true;
            } else if (vType == ValidatorType.Geometre && !hasGeometre) {
                hasGeometre = true;
            } else if (vType == ValidatorType.ExpertJuridique && !hasExpert) {
                hasExpert = true;
            }

            // Si toutes les validations sont présentes, arrêter la boucle
            if (hasNotaire && hasGeometre && hasExpert) {
                return true;
            }
        }

        return false;
    }

    /**
     * @dev Récupère l'historique des validations pour un terrain.
     * @param _landId ID du terrain.
     * @return Liste des validations associées au terrain.
     */
    function getValidationHistory(
        uint256 _landId
    ) external view returns (Validation[] memory) {
        return landValidations[_landId];
    }

     /**
     * @dev Configure l'adresse du contrat autorisé à tokenizer les terrains
     * @param _tokenizer L'adresse du contrat tokenizer
     */
    function setTokenizer(address _tokenizer) external onlyOwner {
        require(_tokenizer != address(0), "Adresse tokenizer invalide");
        address oldTokenizer = tokenizer;
        tokenizer = _tokenizer;
        emit TokenizerSet(oldTokenizer, _tokenizer);
    }

    /**
     * @dev Tokenize un terrain. Seul le contrat tokenizer peut appeler cette fonction
     * @param _landId L'ID du terrain à tokenizer
     */
    function tokenizeLand(uint256 _landId) external {
        require(msg.sender == tokenizer, "Seul le tokenizer peut appeler cette fonction");
        require(lands[_landId].isRegistered, "Terrain non enregistre");
        require(lands[_landId].status == ValidationStatus.Valide, "Terrain non valide");
        require(!lands[_landId].isTokenized, "Terrain deja tokenize");
        
        lands[_landId].isTokenized = true;
        emit LandTokenized(_landId);
    }

    function registerLand(
        string memory _location,
        uint256 _surface,
        uint256 _totalTokens,
        uint256 _pricePerToken,
        string memory _cid
    ) external {
        require(_totalTokens > 0, "Nombre de tokens invalide");
        require(bytes(_cid).length > 0, "CID IPFS requis");

        _landCounter++;
        lands[_landCounter] = Land({
            location: _location,
            surface: _surface,
            owner: msg.sender,
            isRegistered: true,
            registrationDate: block.timestamp,
            status: ValidationStatus.EnAttente,
            totalTokens: _totalTokens,
            availableTokens: _totalTokens,
            pricePerToken: _pricePerToken,
            isTokenized: false,
            cid: _cid
        });

        emit LandRegistered(
            _landCounter,
            _location,
            msg.sender,
            _totalTokens,
            _pricePerToken,
            _cid
        );
    }

    function getLandDetails(
        uint256 _landId
    )
        external
        view
        returns (
            bool isTokenized,
            ValidationStatus status,
            uint256 availableTokens,
            uint256 pricePerToken,
            string memory cid // Inclus le CID IPFS
        )
    {
        Land memory land = lands[_landId];
        return (
            land.isTokenized,
            land.status,
            land.availableTokens,
            land.pricePerToken,
            land.cid
        );
    }

 /**
     * @dev Met à jour le nombre de tokens disponibles pour un terrain.
     * @param _landId ID du terrain.
     * @param _amount Montant à déduire des tokens disponibles.
     */
    function updateAvailableTokens(uint256 _landId, uint256 _amount) external {
        require(msg.sender == tokenizer, "Seul le tokenizer peut appeler cette fonction");
        require(lands[_landId].isTokenized, "Terrain non tokenize");
        require(lands[_landId].availableTokens >= _amount, "Pas assez de tokens disponibles");
        lands[_landId].availableTokens -= _amount;
    }
}
