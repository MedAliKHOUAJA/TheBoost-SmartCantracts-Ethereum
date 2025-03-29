const fs = require('fs');
const path = require('path');

async function main() {
  try {
    const contracts = [
      'LandRegistry',
      'LandToken',
      'LandTokenMarketplace'
    ];

    // Chemin absolu vers le dossier artifacts
    const artifactsPath = path.resolve(__dirname, '..', 'artifacts', 'contracts');
    console.log('Checking artifacts path:', artifactsPath);

    // Vérifier si le dossier artifacts existe
    if (!fs.existsSync(artifactsPath)) {
      console.error('Dossier artifacts non trouvé. Compilation requise.');
      process.exit(1);
    }

    // Créer le dossier abis s'il n'existe pas
    const abisPath = path.resolve(__dirname, '..', 'abis');
    if (!fs.existsSync(abisPath)) {
      fs.mkdirSync(abisPath, { recursive: true });
    }

    for (const contractName of contracts) {
      const contractArtifactPath = path.join(
        artifactsPath,
        `${contractName}.sol`,
        `${contractName}.json`
      );
      console.log('Checking contract path:', contractArtifactPath);

      if (!fs.existsSync(contractArtifactPath)) {
        console.error(`Artifact non trouvé pour ${contractName}`);
        continue;
      }

      const artifactContent = fs.readFileSync(contractArtifactPath, 'utf8');
      const artifact = JSON.parse(artifactContent);

      if (!artifact.abi) {
        console.error(`ABI non trouvé pour ${contractName}`);
        continue;
      }

      const abiOutputPath = path.join(abisPath, `${contractName}.json`);
      fs.writeFileSync(
        abiOutputPath,
        JSON.stringify(artifact.abi, null, 2)
      );

      console.log(`ABI extrait avec succès pour ${contractName}`);
    }
  } catch (error) {
    console.error('Erreur lors de l\'extraction des ABIs:', error);
    process.exit(1);
  }
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });