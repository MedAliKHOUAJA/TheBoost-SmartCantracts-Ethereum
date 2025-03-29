const hre = require("hardhat");

async function main() {
    console.log("Déploiement des contrats sur Sepolia...");

    const [deployer] = await hre.ethers.getSigners();
    console.log("Déploiement avec le compte:", deployer.address);

    try {
        // 1. Deploy LandRegistry
        console.log("\nDéploiement de LandRegistry...");
        const LandRegistry = await hre.ethers.getContractFactory("LandRegistry");
        const landRegistry = await LandRegistry.deploy();
        await landRegistry.waitForDeployment();
        console.log("LandRegistry déployé à:", await landRegistry.getAddress());

        // 2. Deploy LandToken
        console.log("\nDéploiement de LandToken...");
        const LandToken = await hre.ethers.getContractFactory("LandToken");
        const landToken = await LandToken.deploy(await landRegistry.getAddress());
        await landToken.waitForDeployment();
        console.log("LandToken déployé à:", await landToken.getAddress());

        // 3. Set Tokenizer
        console.log("\nConfiguration du tokenizer...");
        const setTokenizerTx = await landRegistry.setTokenizer(await landToken.getAddress());
        await setTokenizerTx.wait();
        console.log("Tokenizer configuré");

        // 4. Deploy Marketplace
        console.log("\nDéploiement de LandTokenMarketplace...");
        const LandTokenMarketplace = await hre.ethers.getContractFactory("LandTokenMarketplace");
        const marketplace = await LandTokenMarketplace.deploy(await landToken.getAddress());
        await marketplace.waitForDeployment();
        console.log("Marketplace déployé à:", await marketplace.getAddress());

        console.log("\nDéploiement terminé !");
        console.log("====================");
        console.log("LandRegistry:", await landRegistry.getAddress());
        console.log("LandToken:", await landToken.getAddress());
        console.log("Marketplace:", await marketplace.getAddress());

    } catch (error) {
        console.error("Erreur lors du déploiement:", error);
        process.exit(1);
    }
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });