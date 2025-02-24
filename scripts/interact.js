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
    await landRegistry.connect(validator1).validateLand(1, "QmValidation1", true);
    await landRegistry.connect(validator2).validateLand(1, "QmValidation2", true);
    await landRegistry.connect(validator3).validateLand(1, "QmValidation3", true);
    console.log("Terrain validé par tous les validateurs");

    // Test 3: Tokenisation
    console.log("\nTest 3: Tokenisation");
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
    
    // Approuver le marketplace
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