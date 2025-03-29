const hre = require("hardhat");
const fs = require("fs");

async function main() {
  const [deployer] = await hre.ethers.getSigners();
  console.log("Deploying contracts with the account:", deployer.address);

  try {
    // 1. Deploy LandRegistry
    console.log("Deploying LandRegistry...");
    const LandRegistry = await hre.ethers.getContractFactory("LandRegistry");
    const landRegistry = await LandRegistry.deploy();
    await landRegistry.waitForDeployment();
    console.log("LandRegistry deployed to:", await landRegistry.getAddress());

    // Attendre les confirmations
    await landRegistry.deploymentTransaction().wait(6);
    
    // 2. Deploy LandToken
    console.log("Deploying LandToken...");
    const LandToken = await hre.ethers.getContractFactory("LandToken");
    const landToken = await LandToken.deploy(await landRegistry.getAddress());
    await landToken.waitForDeployment();
    console.log("LandToken deployed to:", await landToken.getAddress());

    // Attendre les confirmations
    await landToken.deploymentTransaction().wait(6);

    // 3. Configure tokenizer in LandRegistry
    console.log("Configuring tokenizer...");
    const setTokenizerTx = await landRegistry.setTokenizer(await landToken.getAddress());
    await setTokenizerTx.wait(6);

    // 4. Deploy Marketplace
    console.log("Deploploying LandTokenMarketplace...");
    const LandTokenMarketplace = await hre.ethers.getContractFactory("LandTokenMarketplace");
    const marketplace = await LandTokenMarketplace.deploy(await landToken.getAddress());
    await marketplace.waitForDeployment();
    console.log("Marketplace deployed to:", await marketplace.getAddress());

    // Attendre les confirmations
    await marketplace.deploymentTransaction().wait(6);

    // Sauvegarder les adresses
    const addresses = {
      network: "sepolia",
      landRegistry: await landRegistry.getAddress(),
      landToken: await landToken.getAddress(),
      marketplace: await marketplace.getAddress(),
      deployer: deployer.address,
      deploymentDate: new Date().toISOString()
    };

    // Sauvegarder dans un fichier spécifique pour Sepolia
    fs.writeFileSync(
      "deployed-addresses-sepolia.json", 
      JSON.stringify(addresses, null, 2)
    );

    // Vérifier les contrats sur Etherscan
    console.log("Verifying contracts on Etherscan...");
    
    await hre.run("verify:verify", {
      address: await landRegistry.getAddress(),
      constructorArguments: []
    });

    await hre.run("verify:verify", {
      address: await landToken.getAddress(),
      constructorArguments: [await landRegistry.getAddress()]
    });

    await hre.run("verify:verify", {
      address: await marketplace.getAddress(),
      constructorArguments: [await landToken.getAddress()]
    });

  } catch (error) {
    console.error("Error during deployment:", error);
    throw error;
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });