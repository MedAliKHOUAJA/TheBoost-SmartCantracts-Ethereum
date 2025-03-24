const hre = require("hardhat");
const fs = require('fs');

async function main() {
    console.log("Current Date and Time (UTC):", new Date().toISOString().slice(0, 19).replace('T', ' '));

    // Charger les adresses déployées
    const deployedAddresses = JSON.parse(fs.readFileSync('deployed-addresses.json'));
    
    // Récupérer les contrats
    const LandRegistry = await hre.ethers.getContractFactory("LandRegistry");
    const LandToken = await hre.ethers.getContractFactory("LandToken");
    
    const landRegistry = await LandRegistry.attach(deployedAddresses.landRegistry);
    const landToken = await LandToken.attach(deployedAddresses.landToken);

    // Récupérer les signers
    const [owner, user1, validator1, validator2, validator3] = await hre.ethers.getSigners();

    try {
        console.log("\nTest 1: Enregistrement d'un terrain");
        const tx1 = await landRegistry.connect(user1).registerLand(
            "Paris",
            1500,
            10,
            hre.ethers.parseEther("0.1"),
            "QmTest123"
        );
        await tx1.wait();
        console.log("Terrain enregistré avec succès");

        console.log("\nTest 2: Validation du terrain");
        // Validation par les trois validateurs
        await landRegistry.connect(validator1).validateLand(1, "QmValidation1", true);
        await landRegistry.connect(validator2).validateLand(1, "QmValidation2", true);
        await landRegistry.connect(validator3).validateLand(1, "QmValidation3", true);
        console.log("Terrain validé par tous les validateurs");

        console.log("\nTest 3: Tokenisation");
        // Important : La tokenisation doit être faite via le contrat LandToken
        // car c'est lui qui est configuré comme tokenizer
        await landToken.tokenizeLand(1);
        console.log("Terrain tokenisé avec succès");

        // Vérification de la tokenisation
        const [isTokenized, status, availableTokens, pricePerToken] = await landRegistry.getLandDetails(1);
        console.log("\nÉtat du terrain après tokenisation:");
        console.log("Tokenisé:", isTokenized);
        console.log("Status:", ["EnAttente", "Valide", "Rejete"][status]);
        console.log("Tokens disponibles:", availableTokens.toString());
        console.log("Prix par token:", hre.ethers.formatEther(pricePerToken), "ETH");

    } catch (error) {
        console.error("Erreur lors des tests d'interaction:", error);
        throw error;
    }
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });