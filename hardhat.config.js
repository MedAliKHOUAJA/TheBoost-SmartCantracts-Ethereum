require("@nomicfoundation/hardhat-toolbox");
require('hardhat-slither');
require('dotenv').config();

// Vérification des variables d'environnement requises
const SEPOLIA_RPC_URL = process.env.SEPOLIA_RPC_URL;
const PRIVATE_KEY = process.env.PRIVATE_KEY;
const ETHERSCAN_API_KEY = process.env.ETHERSCAN_API_KEY;

// Validation des variables d'environnement
if (!SEPOLIA_RPC_URL || !PRIVATE_KEY || !ETHERSCAN_API_KEY) {
  console.warn("\x1b[33m%s\x1b[0m", `
    ⚠️  Warning: Environment variables missing
    To deploy to Sepolia, make sure you have set:
    - SEPOLIA_RPC_URL
    - PRIVATE_KEY
    - ETHERSCAN_API_KEY
  `);
}

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: {
    compilers: [
      { version: "0.8.0" },
      { version: "0.8.17" }
    ]
  },
  defaultNetwork: "hardhat",
  networks: {
    hardhat: {
      chainId: 31337
    },
    localhost: {
      url: "http://127.0.0.1:8545",
      chainId: 31337
    },
    sepolia: SEPOLIA_RPC_URL && PRIVATE_KEY ? {
      url: SEPOLIA_RPC_URL,
      accounts: [PRIVATE_KEY],
      chainId: 11155111,
      blockConfirmations: 6,
      gas: 2100000,
      gasPrice: 8000000000,
      verify: {
        etherscan: {
          apiKey: ETHERSCAN_API_KEY
        }
      }
    } : undefined
  },
  etherscan: {
    apiKey: ETHERSCAN_API_KEY
  },
  gasReporter: {
    enabled: true,
    currency: "USD",
    outputFile: "gas-report.txt",
    noColors: true
  },
  paths: {
    sources: "./contracts",
    tests: "./test",
    cache: "./cache",
    artifacts: "./artifacts"
  },
  mocha: {
    timeout: 40000
  }
};