#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# Installeur graphique Idris2 + pack pour Ubuntu
# Double-cliquez sur ce fichier pour l'exécuter
# ------------------------------------------------------------------------------
set -euo pipefail

ARCHIVE_URL="${ARCHIVE_URL:-https://example.com/idris2-pack-nightly-250828-noble.tar.gz}"
COLLECTION="nightly-250828"
INSTALL_DIR="$HOME/.local"

# Vérifier que zenity est disponible
if ! command -v zenity &>/dev/null; then
    # Fallback terminal si pas de zenity
    echo "Installation de zenity requise pour l'interface graphique..."
    echo "Exécutez: sudo apt install zenity"
    echo "Ou utilisez la version en ligne de commande: curl -fsSL URL | bash"
    exit 1
fi

# Fonction pour afficher une erreur
error_dialog() {
    zenity --error --title="Erreur d'installation" --text="$1" --width=400
    exit 1
}

# Fonction pour afficher une info
info_dialog() {
    zenity --info --title="Installation Idris2" --text="$1" --width=400
}

# Vérifier qu'on n'est pas root
if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    error_dialog "Ne pas exécuter cet installeur en tant que root (pas de sudo)."
fi

# Dialogue de bienvenue
zenity --question \
    --title="Installation d'Idris2 et pack" \
    --text="Cet installeur va télécharger et installer :\n\n• Idris2 0.7.0\n• pack (gestionnaire de paquets)\n• Collection $COLLECTION\n\nTaille du téléchargement : ~64 Mo\nEmplacement : ~/.local/\n\nContinuer ?" \
    --width=400 \
    --ok-label="Installer" \
    --cancel-label="Annuler" || exit 0

# Vérifier curl
if ! command -v curl &>/dev/null; then
    error_dialog "curl n'est pas installé.\n\nExécutez dans un terminal :\nsudo apt install curl"
fi

# Vérifier si déjà installé
if [[ -x "$INSTALL_DIR/bin/pack" ]] && [[ -x "$INSTALL_DIR/bin/idris2" ]]; then
    zenity --question \
        --title="Installation existante détectée" \
        --text="Idris2 et pack sont déjà installés.\n\nVoulez-vous réinstaller ?" \
        --width=350 \
        --ok-label="Réinstaller" \
        --cancel-label="Annuler" || exit 0
    
    # Supprimer l'ancienne installation
    rm -rf "$HOME/.local/state/pack" "$HOME/.config/pack" "$HOME/.cache/pack"
    rm -f "$INSTALL_DIR/bin/pack" "$INSTALL_DIR/bin/idris2"
fi

# Créer les répertoires
mkdir -p "$INSTALL_DIR/bin" "$HOME/.local/state" "$HOME/.config" "$HOME/.cache"

# Téléchargement avec barre de progression
(
    echo "# Téléchargement en cours..."
    curl -fSL "$ARCHIVE_URL" -o /tmp/idris2-pack.tar.gz 2>/dev/null
    echo "50"
    echo "# Extraction des fichiers..."
    tar -xzf /tmp/idris2-pack.tar.gz -C "$HOME"
    echo "90"
    echo "# Nettoyage..."
    rm -f /tmp/idris2-pack.tar.gz
    echo "100"
) | zenity --progress \
    --title="Installation d'Idris2" \
    --text="Préparation..." \
    --percentage=0 \
    --auto-close \
    --width=400

# Vérifier le résultat
if [[ $? -ne 0 ]]; then
    error_dialog "Le téléchargement a échoué.\n\nVérifiez votre connexion internet."
fi

# Configurer le PATH dans .bashrc si nécessaire
if ! grep -q '.local/bin' "$HOME/.bashrc" 2>/dev/null; then
    echo '' >> "$HOME/.bashrc"
    echo '# Added by Idris2 installer' >> "$HOME/.bashrc"
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
fi

# Vérifier l'installation
export PATH="$INSTALL_DIR/bin:$PATH"
if command -v pack &>/dev/null && command -v idris2 &>/dev/null; then
    VERSION=$(idris2 --version 2>/dev/null | head -1 || echo "inconnue")
    info_dialog "Installation terminée avec succès !\n\nVersion : $VERSION\nCollection : $COLLECTION\n\n<b>Important :</b> Ouvrez un nouveau terminal pour utiliser Idris2.\n\nCommandes disponibles :\n• idris2 - compilateur\n• pack - gestionnaire de paquets"
else
    error_dialog "L'installation semble avoir échoué.\n\nVérifiez les fichiers dans ~/.local/bin/"
fi
