const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("Land System Tests", function () {
    let ownable, landRegistry, landToken, marketplace;
    let owner, user1, user2, validator1, validator2, validator3;
    const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";
    let tokenId; // Déclarer tokenId globalement

    this.timeout(50000);

   
    beforeEach(async function () {
        try {
            // Récupération des signataires
            const signers = await ethers.getSigners();
            [owner, user1, user2, validator1, validator2, validator3] = signers;

            // 1. Déploiement d'Ownable
            console.log("Déploiement de Ownable...");
            const Ownable = await ethers.getContractFactory("Ownable");
            ownable = await Ownable.deploy();
            await ownable.waitForDeployment();

            // 2. Déployer LandRegistry initial avec une adresse temporaire
            console.log("Déploiement initial de LandRegistry...");
            const LandRegistry = await ethers.getContractFactory("LandRegistry");
            landRegistry = await LandRegistry.deploy(ZERO_ADDRESS); // Tokenizer non défini initialement
            await landRegistry.waitForDeployment();
            console.log("LandRegistry déployé à:", await landRegistry.getAddress());

            // 3. Déployer LandToken
            console.log("Déploiement de LandToken...");
            const LandToken = await ethers.getContractFactory("LandToken");
            landToken = await LandToken.deploy(await landRegistry.getAddress());
            await landToken.waitForDeployment();
            console.log("LandToken déployé à:", await landToken.getAddress());

            // 4. Configurer le tokenizer après le déploiement
            console.log("Configuration du tokenizer...");
            await landRegistry.connect(owner).setTokenizer(await landToken.getAddress());

            // 5. Déployer le Marketplace
            console.log("Déploiement de LandTokenMarketplace...");
            const LandTokenMarketplace = await ethers.getContractFactory("LandTokenMarketplace");
            marketplace = await LandTokenMarketplace.deploy(await landToken.getAddress());
            await marketplace.waitForDeployment();
            console.log("Marketplace déployée à:", await marketplace.getAddress());

            // 6. Configuration des validateurs
            console.log("Configuration des validateurs...");
            await landRegistry.connect(owner).addValidator(validator1.address, 0);
            await landRegistry.connect(owner).addValidator(validator2.address, 1);
            await landRegistry.connect(owner).addValidator(validator3.address, 2);

        } catch (error) {
            console.error("Erreur détaillée lors du déploiement:", error);
            throw error;
        }
    });

    describe("1. Ownable Tests", function () {
        it("Doit avoir le bon propriétaire initial", async function () {
            expect(await ownable.owner()).to.equal(owner.address);
        });

        it("Ne doit pas permettre le transfert à l'adresse zéro", async function () {
            await expect(
                ownable.connect(owner).transferOwnership(ZERO_ADDRESS)
            ).to.be.revertedWithCustomError(ownable, "OwnableInvalidOwner");
        });
    });

    describe("2. LandRegistry Tests", function () {
        it("Doit permettre d'enregistrer et valider un terrain", async function () {
            await landRegistry.connect(user1).registerLand(
                "Paris",
                1500,
                10,
                ethers.parseEther("500"),
                "QmWmyoMoctfbAaiEs2G4bNi1KxatgFfJw47y36p2uUd3Yr"
            );

            await landRegistry.connect(validator1).validateLand(1, "QmValidationCID1", true);
            await landRegistry.connect(validator2).validateLand(1, "QmValidationCID2", true);
            await landRegistry.connect(validator3).validateLand(1, "QmValidationCID3", true);

            const [isTokenized, status, availableTokens, pricePerToken] = await landRegistry.getLandDetails(1);
            expect(status).to.equal(1); // ValidationStatus.Valide
            expect(availableTokens).to.equal(10);
            expect(pricePerToken).to.equal(ethers.parseEther("500"));
        });
    });

    describe("3. LandToken Tests", function () {
        let landId;

        beforeEach(async function () {
            const tx = await landRegistry.connect(user1).registerLand(
                "Nice",
                1500,
                10,
                ethers.parseEther("500"),
                "QmWmyoMoctfbAaiEs2G4bNi1KxatgFfJw47y36p2uUd3Yr"
            );
            await tx.wait();
            landId = 1;

            await landRegistry.connect(validator1).validateLand(landId, "QmValidationCID1", true);
            await landRegistry.connect(validator2).validateLand(landId, "QmValidationCID2", true);
            await landRegistry.connect(validator3).validateLand(landId, "QmValidationCID3", true);

            const [, status] = await landRegistry.getLandDetails(landId);
            expect(status).to.equal(1); // ValidationStatus.Valide
        });

        it("Doit permettre la tokenisation et le minting", async function () {
            // Tokeniser avec le contrat LandToken (qui est maintenant le tokenizer autorisé)
            await landToken.tokenizeLand(landId);

            const [isTokenized] = await landRegistry.getLandDetails(landId);
            expect(isTokenized).to.be.true;

            await landToken.connect(user1).mintToken(landId, {
                value: ethers.parseEther("500")
            });

            expect(await landToken.ownerOf(1)).to.equal(user1.address);
        });
    });

    describe("4. LandTokenMarketplace Tests", function () {
        let landId;

        beforeEach(async function () {
            const tx = await landRegistry.connect(user1).registerLand(
                "Bordeaux",
                1500,
                10,
                ethers.parseEther("500"),
                "QmWmyoMoctfbAaiEs2G4bNi1KxatgFfJw47y36p2uUd3Yr"
            );
            await tx.wait();
            landId = 1;

            await landRegistry.connect(validator1).validateLand(landId, "QmValidationCID1", true);
            await landRegistry.connect(validator2).validateLand(landId, "QmValidationCID2", true);
            await landRegistry.connect(validator3).validateLand(landId, "QmValidationCID3", true);

            await landToken.tokenizeLand(landId);

            await landToken.connect(user1).mintToken(landId, {
                value: ethers.parseEther("500")
            });
            tokenId = 1; // Initialiser tokenId ici
        });

        it("Doit permettre de lister et acheter un token", async function () {
            const listingPrice = ethers.parseEther("1000");

            await landToken.connect(user1).approve(marketplace.target, tokenId);
            await marketplace.connect(user1).listToken(tokenId, listingPrice);

            const listing = await marketplace.listings(tokenId);
            expect(listing.isActive).to.be.true;
            expect(listing.price).to.equal(listingPrice);

            await marketplace.connect(user2).buyToken(tokenId, {
                value: listingPrice
            });

            expect(await landToken.ownerOf(tokenId)).to.equal(user2.address);
        });

        it("Doit permettre d'annuler un listing", async function () {
            const listingPrice = ethers.parseEther("1000");

            // Approuver et lister
            await landToken.connect(user1).approve(marketplace.target, tokenId);
            await marketplace.connect(user1).listToken(tokenId, listingPrice);

            // Annuler le listing
            await marketplace.connect(user1).cancelListing(tokenId);

            // Vérifier que le listing est inactif
            const listing = await marketplace.listings(tokenId);
            expect(listing.isActive).to.be.false;

            // Vérifier que le token est retourné au propriétaire
            expect(await landToken.ownerOf(tokenId)).to.equal(user1.address);
        });
    });
});