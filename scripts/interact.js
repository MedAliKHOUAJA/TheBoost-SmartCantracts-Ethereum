const hre = require("hardhat");

async function main() {
  console.log("Test d'interaction avec les contrats déployés...");

  try {
    // Charger les adresses depuis le fichier généré par deploy.js
    const addresses = require('../deployed-addresses.json');

    // Récupérer les signers pour les tests
    const [owner, user1, user2, validator1, validator2, validator3] = await hre.ethers.getSigners();

    // Attacher aux contrats déployés
    const LandRegistry = await hre.ethers.getContractFactory("LandRegistry");
    const LandToken = await hre.ethers.getContractFactory("LandToken");
    const LandTokenMarketplace = await hre.ethers.getContractFactory("LandTokenMarketplace");

    const landRegistry = LandRegistry.attach(addresses.landRegistry);
    const landToken = LandToken.attach(addresses.landToken);
    const marketplace = LandTokenMarketplace.attach(addresses.marketplace);

    // Vérification du tokenizer
    console.log("\nTokenizer configuré:", await landRegistry.tokenizer());

    // Vérification et configuration des validateurs
    console.log("\nVérification et configuration des validateurs...");

    // Vérifier si les validateurs sont déjà configurés
    const isValidator1 = await landRegistry.validators(validator1.address);
    const isValidator2 = await landRegistry.validators(validator2.address);
    const isValidator3 = await landRegistry.validators(validator3.address);

    // Configurer les validateurs s'ils ne le sont pas déjà
    if (!isValidator1) {
      console.log("Configuration du validateur 1 (Notaire)...");
      await landRegistry.connect(owner).addValidator(validator1.address, 0);
    }
    if (!isValidator2) {
      console.log("Configuration du validateur 2 (Geometre)...");
      await landRegistry.connect(owner).addValidator(validator2.address, 1);
    }
    if (!isValidator3) {
      console.log("Configuration du validateur 3 (Expert Juridique)...");
      await landRegistry.connect(owner).addValidator(validator3.address, 2);
    }

    // Vérifier que les validateurs sont bien configurés
    const checkValidator1 = await landRegistry.validators(validator1.address);
    const checkValidator2 = await landRegistry.validators(validator2.address);
    const checkValidator3 = await landRegistry.validators(validator3.address);

    if (!checkValidator1 || !checkValidator2 || !checkValidator3) {
      throw new Error("La configuration des validateurs a échoué");
    }
    console.log("Tous les validateurs sont correctement configurés");

    // Test 1: Enregistrement d'un terrain
    console.log("\nTest 1: Enregistrement d'un terrain");
    const registerTx = await landRegistry.connect(user1).registerLand(
      "Paris",
      1500,
      10,
      hre.ethers.parseEther("500"),
      "QmTestCID"
    );
    await registerTx.wait();
    console.log("Terrain enregistré avec succès");

    // Test 2: Validation du terrain
    console.log("\nTest 2: Validation du terrain");
    console.log("Validation par le Notaire...");
    await landRegistry.connect(validator1).validateLand(1, "QmValidation1", true);
    console.log("Validation par le Géomètre...");
    await landRegistry.connect(validator2).validateLand(1, "QmValidation2", true);
    console.log("Validation par l'Expert Juridique...");
    await landRegistry.connect(validator3).validateLand(1, "QmValidation3", true);
    console.log("Terrain validé par tous les validateurs");

    // Vérifier le statut du terrain
    const [isTokenized, status, availableTokens, pricePerToken] = await landRegistry.getLandDetails(1);
    console.log("\nStatut du terrain après validation:");
    console.log("Status:", ["EnAttente", "Valide", "Rejete"][status]);

    // Test 3: Tokenisation
    console.log("\nTest 3: Tokenisation");

    // Vérification des adresses pour débogage
    console.log("Address of LandToken:", await landToken.getAddress());
    console.log("Tokenizer configured in LandRegistry:", await landRegistry.tokenizer());

    // Appeler tokenizeLand avec le compte owner
    await landToken.connect(owner).tokenizeLand(1);
    console.log("Terrain tokenisé avec succès");

    // Test 4: Minting d'un token
    console.log("\nTest 4: Minting d'un token");
    await landToken.connect(user1).mintToken(1, {
      value: hre.ethers.parseEther("500")
    });
    console.log("Token minté avec succès");

    // Test 5: Listing sur le marketplace
    console.log("\nTest 5: Listing sur le marketplace");
    const tokenId = 1;
    const listingPrice = hre.ethers.parseEther("1000");

    await landToken.connect(user1).approve(addresses.marketplace, tokenId);
    await marketplace.connect(user1).listToken(tokenId, listingPrice);
    console.log("Token listé sur le marketplace");

    console.log("\nTous les tests d'interaction ont réussi !");

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