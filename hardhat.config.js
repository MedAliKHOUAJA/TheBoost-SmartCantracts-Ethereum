require("@nomicfoundation/hardhat-toolbox");
require('hardhat-slither');


/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: {
      compilers: [
          { version: "0.8.0" }, 
          { version: "0.8.17" } 
      ]
  },
  slither: {
    runs: ["all"], // Exécute toutes les analyses par défaut
    exclude: ["test", "scripts"], // Exclut les dossiers test et scripts
    masquerade: false, // Désactive le masquage des erreurs (optionnel)
},
};
