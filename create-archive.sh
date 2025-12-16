#!/usr/bin/env bash
set -euo pipefail

# Script pour créer l'archive des binaires Idris2 + pack
# À exécuter après une installation complète réussie

COLLECTION="nightly-250828"
OUTPUT="idris2-pack-${COLLECTION}-$(lsb_release -cs).tar.gz"

echo "Création de l'archive $OUTPUT..."

# Ajouter ~/.local/bin au PATH si nécessaire
export PATH="$HOME/.local/bin:$PATH"

# Vérifier que pack fonctionne
if ! command -v pack &>/dev/null; then
  echo "Erreur: pack n'est pas installé ou pas dans le PATH"
  exit 1
fi

echo "Collection actuelle:"
pack info | head -5

# Créer l'archive (version minimale sans cache git)
cd "$HOME"
tar -czvf "$OUTPUT" \
  .local/bin/pack \
  .local/bin/idris2 \
  .local/state/pack \
  .config/pack

echo ""
echo "Archive créée: $HOME/$OUTPUT"
echo "Taille: $(du -h "$OUTPUT" | cut -f1)"
echo ""
echo "Pour l'utiliser:"
echo "  1. Hébergez $OUTPUT sur un serveur web"
echo "  2. Modifiez ARCHIVE_URL dans install.sh"
echo "  3. Distribuez install.sh aux étudiants"
