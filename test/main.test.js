const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("Land System Tests", function () {
    let ownable, landRegistry, landToken, marketplace;
    let owner, user1, user2, validator1, validator2, validator3, relayer;
    const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";
    let tokenId;

    this.timeout(50000);

    beforeEach(async function () {
        try {
            // Récupération des signataires
            const signers = await ethers.getSigners();
            [owner, user1, user2, validator1, validator2, validator3, relayer] = signers;

            // 1. Déploiement d'Ownable
            console.log("Déploiement de Ownable...");
            const Ownable = await ethers.getContractFactory("Ownable");
            ownable = await Ownable.deploy();
            await ownable.waitForDeployment();

            // 2. Déployer LandRegistry sans paramètre
            console.log("Déploiement de LandRegistry...");
            const LandRegistry = await ethers.getContractFactory("LandRegistry");
            landRegistry = await LandRegistry.deploy(); // Suppression du paramètre ZERO_ADDRESS
            await landRegistry.waitForDeployment();
            console.log("LandRegistry déployé à:", await landRegistry.getAddress());

            // 3. Déployer LandToken
            console.log("Déploiement de LandToken...");
            const LandToken = await ethers.getContractFactory("LandToken");
            landToken = await LandToken.deploy(await landRegistry.getAddress());
            await landToken.waitForDeployment();
            console.log("LandToken déployé à:", await landToken.getAddress());

            // 4. Configurer le tokenizer
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

            // Vérification de la configuration du tokenizer
            const configuredTokenizer = await landRegistry.tokenizer();
            if (configuredTokenizer.toLowerCase() !== (await landToken.getAddress()).toLowerCase()) {
                throw new Error("Tokenizer non configuré correctement");
            }
            // la configuration des relayers
            console.log("Configuration des relayers...");
            await landRegistry.connect(owner).addRelayer(relayer.address);
            await landToken.connect(owner).addRelayer(relayer.address);
            await marketplace.connect(owner).addRelayer(relayer.address);

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
        it("Doit permettre d'enregistrer un terrain (client paie ses frais)", async function () {
            await landRegistry.connect(user1).registerLand(
                "Paris",
                1500,
                10,
                ethers.parseEther("500"),
                "QmWmyoMoctfbAaiEs2G4bNi1KxatgFfJw47y36p2uUd3Yr"
            );

            const land = await landRegistry.lands(1);
            expect(land.owner).to.equal(user1.address);
        });

        it("Doit permettre la validation via relayer", async function () {
            // Enregistrement du terrain
            await landRegistry.connect(user1).registerLand(
                "Paris",
                1500,
                10,
                ethers.parseEther("500"),
                "QmWmyoMoctfbAaiEs2G4bNi1KxatgFfJw47y36p2uUd3Yr"
            );

            // Validation via relayer
            await landRegistry.connect(relayer).validateLand(
                1,
                "QmValidationCID1",
                true,
                validator1.address
            );
            await landRegistry.connect(relayer).validateLand(
                1,
                "QmValidationCID2",
                true,
                validator2.address
            );
            await landRegistry.connect(relayer).validateLand(
                1,
                "QmValidationCID3",
                true,
                validator3.address
            );

            const [isTokenized, status, availableTokens, pricePerToken] = await landRegistry.getLandDetails(1);
            expect(status).to.equal(1); // ValidationStatus.Valide
        });

        it("Doit permettre de voir l'historique des validations", async function () {
            await landRegistry.connect(user1).registerLand(
                "Paris",
                1500,
                10,
                ethers.parseEther("500"),
                "QmWmyoMoctfbAaiEs2G4bNi1KxatgFfJw47y36p2uUd3Yr"
            );

            await landRegistry.connect(relayer).validateLand(
                1,
                "QmValidationCID1",
                true,
                validator1.address
            );

            const validations = await landRegistry.getValidationHistory(1);
            expect(validations.length).to.be.above(0);
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
    
            // Correction des appels à validateLand
            await landRegistry.connect(validator1).validateLand(
                landId, 
                "QmValidationCID1", 
                true,
                validator1.address  // Ajout de l'adresse du validateur
            );
            await landRegistry.connect(validator2).validateLand(
                landId, 
                "QmValidationCID2", 
                true,
                validator2.address
            );
            await landRegistry.connect(validator3).validateLand(
                landId, 
                "QmValidationCID3", 
                true,
                validator3.address
            );
    
            const [, status] = await landRegistry.getLandDetails(landId);
            expect(status).to.equal(1); // ValidationStatus.Valide
        });

        it("Doit permettre le minting standard (client paie)", async function () {
            await landToken.tokenizeLand(landId);

            await landToken.connect(user1).mintToken(landId, {
                value: ethers.parseEther("500")
            });

            expect(await landToken.ownerOf(1)).to.equal(user1.address);
        });

        it("Doit permettre le minting via relayer", async function () {
            await landToken.tokenizeLand(landId);

            await landToken.connect(relayer).mintTokenForUser(
                landId,
                user1.address,
                { value: ethers.parseEther("500") }
            );

            expect(await landToken.ownerOf(1)).to.equal(user1.address);
        });
        it("Doit permettre le minting de plusieurs tokens à la fois", async function () {
            await landToken.tokenizeLand(landId);
            
            const quantity = 3;
            const pricePerToken = ethers.parseEther("500");
            const totalPrice = pricePerToken * BigInt(quantity);
            
            await landToken.connect(user1).mintMultipleTokens(landId, quantity, {
                value: totalPrice
            });
            
            // Vérifier que 3 tokens ont été créés
            const tokens = await landToken.getTokensByLand(landId);
            expect(tokens.length).to.equal(quantity);
            
            // Vérifier que tous les tokens appartiennent à user1
            for (let i = 0; i < quantity; i++) {
                expect(await landToken.ownerOf(tokens[i])).to.equal(user1.address);
            }
        });
        
        it("Doit permettre le minting multiple via relayer", async function () {
            await landToken.tokenizeLand(landId);
            
            const quantity = 2;
            const pricePerToken = ethers.parseEther("500");
            const totalPrice = pricePerToken * BigInt(quantity);
            
            await landToken.connect(relayer).mintMultipleTokensForUser(
                landId,
                user2.address,
                quantity,
                { value: totalPrice }
            );
            
            // Vérifier que 2 tokens ont été créés
            const tokens = await landToken.getTokensByLand(landId);
            expect(tokens.length).to.equal(quantity);
            
            // Vérifier que tous les tokens appartiennent à user2
            for (let i = 0; i < quantity; i++) {
                expect(await landToken.ownerOf(tokens[i])).to.equal(user2.address);
            }
        });
        it("Doit distribuer correctement les fonds lors du minting (avec frais de plateforme)", async function () {
            await landToken.tokenizeLand(landId);
            
            // Définir des frais de plateforme de 10%
            await landToken.connect(owner).setPlatformFeePercentage(1000);
            expect(await landToken.platformFeePercentage()).to.equal(1000);
            
            // Obtenir les soldes initiaux
            const initialContractBalance = await ethers.provider.getBalance(landToken.target);
            const initialLandOwnerBalance = await ethers.provider.getBalance(user1.address);
            
            // Minter un token (user2 mint, user1 est le propriétaire du terrain)
            const price = ethers.parseEther("500");
            const platformFee = price * BigInt(1000) / BigInt(10000); // 10%
            const ownerAmount = price - platformFee;
            
            const mintTx = await landToken.connect(user2).mintToken(landId, {
                value: price
            });
            
            // Vérifier que les frais sont correctement collectés par le contrat
            const finalContractBalance = await ethers.provider.getBalance(landToken.target);
            expect(finalContractBalance - initialContractBalance).to.equal(platformFee);
            
            // Vérifier que le propriétaire du terrain a reçu le bon montant
            // Note: nous devons prendre en compte que user1 a peut-être dépensé du gaz pour d'autres transactions
            // Pour simplifier, vérifions simplement que le solde a augmenté d'environ le montant attendu
            const finalLandOwnerBalance = await ethers.provider.getBalance(user1.address);
            const landOwnerBalanceDiff = finalLandOwnerBalance - initialLandOwnerBalance;
            
            // Vérifier avec une marge d'erreur pour le gaz dépensé par user1
            expect(landOwnerBalanceDiff).to.be.closeTo(ownerAmount, ethers.parseEther("0.01"));
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
    
            // Correction des appels à validateLand
            await landRegistry.connect(validator1).validateLand(
                landId, 
                "QmValidationCID1", 
                true,
                validator1.address
            );
            await landRegistry.connect(validator2).validateLand(
                landId, 
                "QmValidationCID2", 
                true,
                validator2.address
            );
            await landRegistry.connect(validator3).validateLand(
                landId, 
                "QmValidationCID3", 
                true,
                validator3.address
            );
    
            await landToken.tokenizeLand(landId);
    
            await landToken.connect(user1).mintToken(landId, {
                value: ethers.parseEther("500")
            });
            tokenId = 1;
        });

        it("Doit permettre le listing standard (client paie)", async function () {
            const listingPrice = ethers.parseEther("1000");

            await landToken.connect(user1).approve(marketplace.target, tokenId);
            await marketplace.connect(user1).listToken(tokenId, listingPrice);

            const listing = await marketplace.listings(tokenId);
            expect(listing.isActive).to.be.true;
        });

        it("Doit permettre le listing via relayer", async function () {
            const listingPrice = ethers.parseEther("1000");

            await landToken.connect(user1).approve(marketplace.target, tokenId);
            await marketplace.connect(relayer).listTokenForUser(
                tokenId,
                listingPrice,
                user1.address
            );

            const listing = await marketplace.listings(tokenId);
            expect(listing.isActive).to.be.true;
            expect(listing.seller).to.equal(user1.address);
        });

        it("Doit permettre l'achat via relayer", async function () {
            const listingPrice = ethers.parseEther("1000");

            await landToken.connect(user1).approve(marketplace.target, tokenId);
            await marketplace.connect(user1).listToken(tokenId, listingPrice);

            await marketplace.connect(relayer).buyTokenForUser(
                tokenId,
                user2.address,
                { value: listingPrice }
            );

            expect(await landToken.ownerOf(tokenId)).to.equal(user2.address);
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
        it("Doit permettre de lister plusieurs tokens à la fois", async function () {
            await landToken.tokenizeLand(landId);
            
            // Minter 3 tokens
            const quantity = 3;
            const pricePerToken = ethers.parseEther("500");
            const totalPrice = pricePerToken * BigInt(quantity);
            
            await landToken.connect(user1).mintMultipleTokens(landId, quantity, {
                value: totalPrice
            });
            
            const tokens = await landToken.getTokensByLand(landId);
            expect(tokens.length).to.equal(quantity);
            
            // Approuver le marketplace pour tous les tokens
            for (let i = 0; i < tokens.length; i++) {
                await landToken.connect(user1).approve(marketplace.target, tokens[i]);
            }
            
            // Lister les tokens avec des prix différents
            const prices = [
                ethers.parseEther("600"),
                ethers.parseEther("700"),
                ethers.parseEther("800")
            ];
            
            await marketplace.connect(user1).listMultipleTokens(tokens, prices);
            
            // Vérifier que les tokens sont correctement listés
            for (let i = 0; i < tokens.length; i++) {
                const listing = await marketplace.listings(tokens[i]);
                expect(listing.isActive).to.be.true;
                expect(listing.price).to.equal(prices[i]);
                expect(listing.seller).to.equal(user1.address);
            }
        });
        
        it("Doit permettre d'acheter plusieurs tokens à la fois", async function () {
            await landToken.tokenizeLand(landId);
            
            // Minter 2 tokens
            const quantity = 2;
            const pricePerToken = ethers.parseEther("500");
            const totalPrice = pricePerToken * BigInt(quantity);
            
            await landToken.connect(user1).mintMultipleTokens(landId, quantity, {
                value: totalPrice
            });
            
            const tokens = await landToken.getTokensByLand(landId);
            
            // Approuver le marketplace pour tous les tokens
            for (let i = 0; i < tokens.length; i++) {
                await landToken.connect(user1).approve(marketplace.target, tokens[i]);
            }
            
            // Lister les tokens au même prix
            const listingPrice = ethers.parseEther("1000");
            const listingPrices = [listingPrice, listingPrice];
            
            await marketplace.connect(user1).listMultipleTokens(tokens, listingPrices);
            
            // Acheter les tokens en une seule transaction
            const totalPurchasePrice = listingPrice * BigInt(tokens.length);
            
            // Configurer les frais de marketplace à 5%
            await marketplace.connect(owner).setMarketplaceFeePercentage(500);
            
            // Capturer le solde du vendeur avant la vente
            const sellerInitialBalance = await ethers.provider.getBalance(user1.address);
            
            // Acheter les tokens
            await marketplace.connect(user2).buyMultipleTokens(tokens, {
                value: totalPurchasePrice
            });
            
            // Vérifier que les tokens appartiennent maintenant à user2
            for (let i = 0; i < tokens.length; i++) {
                expect(await landToken.ownerOf(tokens[i])).to.equal(user2.address);
            }
            
            // Vérifier que les listings sont inactifs
            for (let i = 0; i < tokens.length; i++) {
                const listing = await marketplace.listings(tokens[i]);
                expect(listing.isActive).to.be.false;
            }
            
            // Vérifier que les frais de marketplace ont été collectés
            const marketplaceFee = totalPurchasePrice * BigInt(500) / BigInt(10000); // 5%
            const expectedSellerAmount = totalPurchasePrice - marketplaceFee;
            
            // Vérifier le solde du contrat (frais de marketplace)
            const marketplaceBalance = await ethers.provider.getBalance(marketplace.target);
            expect(marketplaceBalance).to.equal(marketplaceFee);
            
            // Vérifier le solde du vendeur (avec une marge d'erreur pour le gaz)
            const sellerFinalBalance = await ethers.provider.getBalance(user1.address);
            const sellerBalanceDiff = sellerFinalBalance - sellerInitialBalance;
            expect(sellerBalanceDiff).to.be.closeTo(expectedSellerAmount, ethers.parseEther("0.01"));
        });
        it("Doit permettre au propriétaire de retirer les frais du marketplace", async function () {
            await landToken.tokenizeLand(landId);
            
            // Minter un token
            await landToken.connect(user1).mintToken(landId, {
                value: ethers.parseEther("500")
            });
            
            // Lister le token
            const listingPrice = ethers.parseEther("1000");
            await landToken.connect(user1).approve(marketplace.target, tokenId);
            await marketplace.connect(user1).listToken(tokenId, listingPrice);
            
            // Configurer les frais de marketplace à 5%
            await marketplace.connect(owner).setMarketplaceFeePercentage(500);
            
            // User2 achète le token
            await marketplace.connect(user2).buyToken(tokenId, {
                value: listingPrice
            });
            
            // Calculer les frais de marketplace
            const marketplaceFee = listingPrice * BigInt(500) / BigInt(10000); // 5%
            
            // Vérifier le solde du contrat (frais de marketplace)
            const marketplaceBalance = await ethers.provider.getBalance(marketplace.target);
            expect(marketplaceBalance).to.equal(marketplaceFee);
            
            // Capturer le solde du propriétaire avant le retrait
            const ownerInitialBalance = await ethers.provider.getBalance(owner.address);
            
            // Retirer les frais
            const withdrawTx = await marketplace.connect(owner).withdrawMarketplaceFees();
            const withdrawReceipt = await withdrawTx.wait();
            const gasCost = withdrawReceipt.gasUsed * withdrawReceipt.gasPrice;
            
            // Vérifier que le contrat n'a plus de fonds
            const marketplaceFinalBalance = await ethers.provider.getBalance(marketplace.target);
            expect(marketplaceFinalBalance).to.equal(0);
            
            // Vérifier que le propriétaire a reçu les frais (moins le coût du gaz)
            const ownerFinalBalance = await ethers.provider.getBalance(owner.address);
            const expectedOwnerBalance = ownerInitialBalance + marketplaceFee - gasCost;
            expect(ownerFinalBalance).to.equal(expectedOwnerBalance);
        });
        
        it("Doit permettre au propriétaire de retirer les frais de plateforme", async function () {
            await landToken.tokenizeLand(landId);
            
            // Configurer les frais de plateforme à 10%
            await landToken.connect(owner).setPlatformFeePercentage(1000);
            
            // Minter un token
            await landToken.connect(user2).mintToken(landId, {
                value: ethers.parseEther("500")
            });
            
            // Calculer les frais de plateforme
            const price = ethers.parseEther("500");
            const platformFee = price * BigInt(1000) / BigInt(10000); // 10%
            
            // Vérifier le solde du contrat
            const contractBalance = await ethers.provider.getBalance(landToken.target);
            expect(contractBalance).to.equal(platformFee);
            
            // Capturer le solde du propriétaire avant le retrait
            const ownerInitialBalance = await ethers.provider.getBalance(owner.address);
            
            // Retirer les frais
            const withdrawTx = await landToken.connect(owner).withdrawPlatformFees();
            const withdrawReceipt = await withdrawTx.wait();
            const gasCost = withdrawReceipt.gasUsed * withdrawReceipt.gasPrice;
            
            // Vérifier que le contrat n'a plus de fonds
            const contractFinalBalance = await ethers.provider.getBalance(landToken.target);
            expect(contractFinalBalance).to.equal(0);
            
            // Vérifier que le propriétaire a reçu les frais (moins le coût du gaz)
            const ownerFinalBalance = await ethers.provider.getBalance(owner.address);
            const expectedOwnerBalance = ownerInitialBalance + platformFee - gasCost;
            expect(ownerFinalBalance).to.equal(expectedOwnerBalance);
        });
    });
    describe("5. Relayer System Tests", function () {
        it("Doit permettre à l'owner d'ajouter un relayer", async function () {
            await landRegistry.connect(owner).addRelayer(user1.address);
            expect(await landRegistry.relayers(user1.address)).to.be.true;
        });

        it("Doit permettre à l'owner de supprimer un relayer", async function () {
            await landRegistry.connect(owner).addRelayer(user1.address);
            await landRegistry.connect(owner).removeRelayer(user1.address);
            expect(await landRegistry.relayers(user1.address)).to.be.false;
        });

        it("Ne doit pas permettre à un non-owner d'ajouter un relayer", async function () {
            await expect(
                landRegistry.connect(user1).addRelayer(user2.address)
            ).to.be.revertedWithCustomError(landRegistry, "OwnableUnauthorizedAccount");
        });

        it("Doit rejeter les validations d'un non-relayer/non-validator", async function () {
            await landRegistry.connect(user1).registerLand(
                "Paris",
                1500,
                10,
                ethers.parseEther("500"),
                "QmWmyoMoctfbAaiEs2G4bNi1KxatgFfJw47y36p2uUd3Yr"
            );

            await expect(
                landRegistry.connect(user2).validateLand(
                    1,
                    "QmValidationCID1",
                    true,
                    validator1.address
                )
            ).to.be.revertedWithCustomError(landRegistry, "UnauthorizedRelayer");
        });
        it("Doit permettre à un relayer d'acheter plusieurs tokens pour un utilisateur", async function () {
            await landToken.tokenizeLand(landId);
            
            // Minter 2 tokens
            const quantity = 2;
            const pricePerToken = ethers.parseEther("500");
            const totalPrice = pricePerToken * BigInt(quantity);
            
            await landToken.connect(user1).mintMultipleTokens(landId, quantity, {
                value: totalPrice
            });
            
            const tokens = await landToken.getTokensByLand(landId);
            
            // Approuver le marketplace pour tous les tokens
            for (let i = 0; i < tokens.length; i++) {
                await landToken.connect(user1).approve(marketplace.target, tokens[i]);
            }
            
            // Lister les tokens
            const listingPrice = ethers.parseEther("1000");
            const listingPrices = [listingPrice, listingPrice];
            
            await marketplace.connect(user1).listMultipleTokens(tokens, listingPrices);
            
            // Relayer achète les tokens pour user2
            const totalPurchasePrice = listingPrice * BigInt(tokens.length);
            
            await marketplace.connect(relayer).buyMultipleTokensForUser(tokens, user2.address, {
                value: totalPurchasePrice
            });
            
            // Vérifier que les tokens appartiennent maintenant à user2
            for (let i = 0; i < tokens.length; i++) {
                expect(await landToken.ownerOf(tokens[i])).to.equal(user2.address);
            }
        });
    });

});

