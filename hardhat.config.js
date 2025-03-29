// Importation des plugins nécessaires
require("@nomicfoundation/hardhat-toolbox");  // Boîte à outils standard de Hardhat
require('hardhat-slither');                   // Plugin pour l'analyse de sécurité avec Slither
require('dotenv').config();                   // Pour charger les variables d'environnement depuis .env

// Récupération des variables d'environnement
const SEPOLIA_RPC_URL = process.env.SEPOLIA_RPC_URL;   // URL du nœud Sepolia (Alchemy/Infura)
const PRIVATE_KEY = process.env.PRIVATE_KEY;           // Clé privée du wallet de déploiement
const ETHERSCAN_API_KEY = process.env.ETHERSCAN_API_KEY; // Clé API Etherscan pour la vérification

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  // Configuration du compilateur Solidity
  solidity: {
    compilers: [
      { version: "0.8.0" },  // Premier compilateur pour certains contrats
      { version: "0.8.17" }  // Second compilateur pour d'autres contrats
    ]
  },

  // Configuration des réseaux
  networks: {
    // Réseau Hardhat local (par défaut)
    hardhat: {
      chainId: 31337  // ID de chaîne pour le réseau local Hardhat
    },
    
    // Réseau local (pour le développement)
    localhost: {
      url: "http://127.0.0.1:8545",  // URL du nœud local
      chainId: 31337                 // Même ID de chaîne que hardhat
    },
    
    // Réseau de test Sepolia
    sepolia: {
      url: SEPOLIA_RPC_URL,         // URL du nœud Sepolia (depuis .env)
      accounts: [PRIVATE_KEY],      // Compte pour signer les transactions (depuis .env)
      chainId: 11155111,           // ID de chaîne Sepolia
      blockConfirmations: 6        // Nombre de confirmations à attendre
    }
  },

  // Configuration Etherscan pour la vérification des contrats
  etherscan: {
    apiKey: ETHERSCAN_API_KEY  // Clé API pour vérifier les contrats sur Etherscan
  },

  // Configuration du rapport de gas
  gasReporter: {
    enabled: true,              // Active le rapport de gas
    currency: "USD",           // Affiche les coûts en USD
    outputFile: "gas-report.txt", // Fichier de sortie pour le rapport
    noColors: true             // Désactive les couleurs pour la sortie fichier
  }
};