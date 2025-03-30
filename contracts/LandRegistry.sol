// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

contract LandRegistry is Ownable, ReentrancyGuard, Pausable {
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
        string cid; // CID  des documents associés au terrain
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
    mapping(address => bool) public relayers;

    uint256 public currentLandId;
    uint256 private _landCounter;
    address public tokenizer; // variable pour le tokenizer

    //events
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

    event LandTokenized(uint256 indexed landId);

    event RelayerAdded(address indexed relayer);
    event RelayerRemoved(address indexed relayer);

    error UnauthorizedTokenizer();
    error InvalidTokenizer();
    event TokenizerUpdated(
        address indexed previousTokenizer,
        address indexed newTokenizer
    );

    error InvalidValidator();
    error UnauthorizedValidator();
    error InvalidCIDComments();
    error ValidatorAlreadyValidated();
    error LandNotRegistered();
    error LandNotValid();
    error LandAlreadyTokenized();
    error InvalidTokenAmount();
    error InsufficientTokens();
    error UnauthorizedRelayer();
    error InvalidRelayer();

    constructor() {}

    // Fonction pour mettre à jour le tokenizer
    function setTokenizer(address _tokenizer) external onlyOwner {
        require(_tokenizer != address(0), "Invalid address");
        address oldTokenizer = tokenizer;
        tokenizer = _tokenizer;
        emit TokenizerUpdated(oldTokenizer, _tokenizer);
    }

    modifier onlyTokenizer() {
        require(msg.sender == tokenizer, "Not tokenizer");
        _;
    }

    modifier onlyValidator() {
        if (!validators[msg.sender]) revert UnauthorizedValidator();
        _;
    }

    modifier onlyRelayerOrValidator() {
        if (!relayers[msg.sender] && !validators[msg.sender]) 
            revert UnauthorizedRelayer();
        _;
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function addRelayer(address _relayer) external onlyOwner whenNotPaused {
        if (_relayer == address(0)) revert InvalidRelayer();
        relayers[_relayer] = true;
        emit RelayerAdded(_relayer);
    }

    function removeRelayer(address _relayer) external onlyOwner {
        relayers[_relayer] = false;
        emit RelayerRemoved(_relayer);
    }

    /**
     * @dev Ajoute un validateur.
     * @param _validator Adresse du validateur.
     * @param _type Type de validateur.
     */
    function addValidator(
        address _validator,
        ValidatorType _type
    ) external onlyOwner whenNotPaused {
        if (_validator == address(0)) revert InvalidValidator();
        validators[_validator] = true;
        validatorTypes[_validator] = _type;
        emit ValidatorAdded(_validator, _type);
    }

    /**
     * @dev Valide ou rejette un terrain.
     * @param _landId ID du terrain.
     * @param _cidComments CID IPFS contenant les commentaires.
     * @param _isValid Indique si le terrain est validé.
     * @param _validator Indique l'adresse du validator pour accepter les relayers .
     */
        function validateLand(
        uint256 _landId,
        string calldata _cidComments,
        bool _isValid,
        address _validator // Ajout du paramètre validator
    ) external whenNotPaused onlyRelayerOrValidator nonReentrant {
        if (bytes(_cidComments).length == 0) revert InvalidCIDComments();
        
        // Déterminer le validateur réel
        address actualValidator = validators[msg.sender] ? msg.sender : _validator;
        
        // Vérifier que le validateur est autorisé
        if (!validators[actualValidator]) revert UnauthorizedValidator();

        // Vérifier que le validateur n'a pas déjà validé
        for (uint256 i = 0; i < landValidations[_landId].length; i++) {
            if (landValidations[_landId][i].validator == actualValidator) {
                revert ValidatorAlreadyValidated();
            }
        }

        landValidations[_landId].push(
            Validation({
                validator: actualValidator,
                timestamp: block.timestamp,
                cidComments: _cidComments,
                validatorType: validatorTypes[actualValidator],
                isValidated: _isValid
            })
        );

        if (!_isValid) {
            lands[_landId].status = ValidationStatus.Rejete;
        } else if (_checkAllValidations(_landId)) {
            lands[_landId].status = ValidationStatus.Valide;
        }

        emit ValidationAdded(_landId, actualValidator, _isValid);
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
            if (!validation.isValidated) continue;

            ValidatorType vType = validation.validatorType;
            if (vType == ValidatorType.Notaire) hasNotaire = true;
            else if (vType == ValidatorType.Geometre) hasGeometre = true;
            else if (vType == ValidatorType.ExpertJuridique) hasExpert = true;

            if (hasNotaire && hasGeometre && hasExpert) return true;
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
     * @dev Tokenize un terrain. Seul le contrat tokenizer peut appeler cette fonction
     * @param _landId L'ID du terrain à tokenizer
     */
    function tokenizeLand(
        uint256 _landId
    ) external whenNotPaused onlyTokenizer nonReentrant {
        if (!lands[_landId].isRegistered) revert LandNotRegistered();
        if (lands[_landId].status != ValidationStatus.Valide)
            revert LandNotValid();
        if (lands[_landId].isTokenized) revert LandAlreadyTokenized();

        lands[_landId].isTokenized = true;
        emit LandTokenized(_landId);
    }

    function registerLand(
        string calldata _location,
        uint256 _surface,
        uint256 _totalTokens,
        uint256 _pricePerToken,
        string calldata _cid
    ) external whenNotPaused nonReentrant {
        if (_totalTokens == 0) revert InvalidTokenAmount();
        if (bytes(_cid).length == 0) revert InvalidCIDComments();

        unchecked {
            _landCounter++;
        }

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
    function updateAvailableTokens(
        uint256 _landId,
        uint256 _amount
    ) external whenNotPaused onlyTokenizer nonReentrant {
        if (!lands[_landId].isTokenized) revert LandNotValid();
        if (lands[_landId].availableTokens < _amount)
            revert InsufficientTokens();

        lands[_landId].availableTokens -= _amount;
    }
}
