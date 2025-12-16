# Idris2 + pack - Installation rapide

Ce dépôt contient les outils pour installer Idris2 et pack rapidement via des binaires pré-compilés.

## Pour les étudiants

Voir `INSTALL-ETUDIANTS.md` pour les instructions d'installation.

## Pour les enseignants / mainteneurs

### Structure du dépôt

```
.github/workflows/build-binaries.yml  - Workflow GitHub Actions
install.sh                            - Script d'installation pour étudiants
create-archive.sh                     - Création manuelle d'archive
INSTALL-ETUDIANTS.md                  - Instructions étudiants
```

### Générer les binaires

1. Allez dans l'onglet "Actions" de ce repo
2. Cliquez sur "Build Idris2 + pack binaries"
3. Cliquez "Run workflow"
4. Entrez la collection souhaitée (ex: `nightly-250828`)
5. Attendez ~1h que les builds terminent

Le workflow génère des binaires pour :
- Ubuntu 22.04 (jammy)
- Ubuntu 24.04 (noble)
- macOS Intel (x86_64)
- macOS Apple Silicon (arm64)

### Récupérer les binaires

1. Une fois le workflow terminé, allez dans le run
2. Téléchargez les artifacts en bas de page
3. Hébergez les `.tar.gz` sur votre serveur

### Mettre à jour le script d'installation

Modifiez `ARCHIVE_URL` dans `install.sh` avec l'URL de votre serveur :

```bash
ARCHIVE_URL="https://votre-serveur.fr/idris2/idris2-pack-nightly-250828-jammy.tar.gz"
```

### Changer de collection

Pour passer à une nouvelle collection (ex: `nightly-260115`) :
1. Relancez le workflow avec la nouvelle collection
2. Mettez à jour les URLs dans `install.sh`
3. Mettez à jour `COLLECTION` dans `install.sh`
