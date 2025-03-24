const hre = require("hardhat");

async function main() {
  console.log("Déploiement des contrats...");

  // Récupérer les signers
  const [owner, user1, user2, validator1, validator2, validator3] = await hre.ethers.getSigners();
  
  // 1. Déploiement de LandRegistry sans paramètre dans le constructeur
  console.log("Déploiement de LandRegistry...");
  const LandRegistry = await hre.ethers.getContractFactory("LandRegistry");
  const landRegistry = await LandRegistry.deploy();
  await landRegistry.waitForDeployment();
  console.log("LandRegistry déployé à:", await landRegistry.getAddress());

  // 2. Déploiement de LandToken avec l'adresse du LandRegistry
  console.log("Déploiement de LandToken...");
  const LandToken = await hre.ethers.getContractFactory("LandToken");
  const landToken = await LandToken.deploy(await landRegistry.getAddress());
  await landToken.waitForDeployment();
  const landTokenAddress = await landToken.getAddress();
  console.log("LandToken déployé à:", landTokenAddress);

  // 3. Configuration du tokenizer dans LandRegistry
  console.log("Configuration du tokenizer dans LandRegistry...");
  await landRegistry.connect(owner).setTokenizer(landTokenAddress);
  console.log("Tokenizer configuré dans LandRegistry");

  // 4. Déploiement de LandTokenMarketplace
  console.log("Déploiement de LandTokenMarketplace...");
  const LandTokenMarketplace = await hre.ethers.getContractFactory("LandTokenMarketplace");
  const marketplace = await LandTokenMarketplace.deploy(landTokenAddress);
  await marketplace.waitForDeployment();
  console.log("LandTokenMarketplace déployé à:", await marketplace.getAddress());

  // 5. Configuration des validateurs
  console.log("Configuration des validateurs...");
  await landRegistry.connect(owner).addValidator(validator1.address, 0); // Notaire
  await landRegistry.connect(owner).addValidator(validator2.address, 1); // Géomètre
  await landRegistry.connect(owner).addValidator(validator3.address, 2); // Expert Juridique

  // 6. Vérification de la configuration
  console.log("\nVérification de la configuration...");
  const tokenizer = await landRegistry.tokenizer();
  console.log("Tokenizer configuré:", tokenizer);
  console.log("LandToken address:", landTokenAddress);
  if(tokenizer !== landTokenAddress) {
    throw new Error("Configuration incorrecte du tokenizer");
  }

  console.log("\nDéploiement terminé !");
  console.log("===================");
  console.log("Adresses des contrats :");
  console.log("LandRegistry:", await landRegistry.getAddress());
  console.log("LandToken:", landTokenAddress);
  console.log("LandTokenMarketplace:", await marketplace.getAddress());
  console.log("\nValidateurs :");
  console.log("Notaire:", validator1.address);
  console.log("Géomètre:", validator2.address);
  console.log("Expert Juridique:", validator3.address);

  // Écrire les adresses dans un fichier
  const fs = require("fs");
  const addresses = {
    landRegistry: await landRegistry.getAddress(),
    landToken: landTokenAddress,
    marketplace: await marketplace.getAddress(),
    validators: {
      notaire: validator1.address,
      geometre: validator2.address,
      expertJuridique: validator3.address
    }
  };

  fs.writeFileSync("deployed-addresses.json", JSON.stringify(addresses, null, 2));
  console.log("\nAdresses sauvegardées dans deployed-addresses.json");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("Erreur détaillée:", error);
    process.exit(1);
  });