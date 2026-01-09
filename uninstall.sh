#!/usr/bin/env bash
# ==============================================================================
# Désinstalleur Idris2 / pack / idris2-lsp
# ==============================================================================
# Supprime proprement toutes les installations d'Idris2 et pack, y compris :
#   - Les binaires dans ~/.local/bin/
#   - Les données pack dans ~/.pack/ (nouveau layout)
#   - Les données pack dans ~/.local/state/pack, ~/.config/pack, ~/.cache/pack (ancien layout)
#   - Les fichiers de debug de l'installateur ISTIC
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/thanberree/idris2-install/main/uninstall.sh | bash
#   # ou
#   ./uninstall.sh [--yes] [--keep-config]
#
# Options:
#   --yes          Ne pas demander de confirmation
#   --keep-config  Garder les fichiers de configuration (~/.config/pack)
#   --dry-run      Afficher ce qui serait supprimé sans rien supprimer
#   --help         Afficher cette aide
# ==============================================================================

set -euo pipefail

# Couleurs (désactivées si pas de terminal)
if [[ -t 1 ]]; then
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  YELLOW='\033[1;33m'
  BLUE='\033[0;34m'
  BOLD='\033[1m'
  NC='\033[0m'
else
  RED='' GREEN='' YELLOW='' BLUE='' BOLD='' NC=''
fi

# Options
AUTO_YES=false
KEEP_CONFIG=false
DRY_RUN=false

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --yes|-y)
      AUTO_YES=true
      shift
      ;;
    --keep-config)
      KEEP_CONFIG=true
      shift
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --help|-h)
      head -30 "$0" | grep "^#" | sed 's/^# \?//'
      exit 0
      ;;
    *)
      echo -e "${RED}Option inconnue: $1${NC}"
      echo "Utilisez --help pour voir les options disponibles."
      exit 1
      ;;
  esac
done

# Fonctions utilitaires
info() { echo -e "${BLUE}[INFO]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERREUR]${NC} $*"; }
success() { echo -e "${GREEN}[OK]${NC} $*"; }

# Fonction pour supprimer un fichier/dossier avec feedback
remove_item() {
  local item="$1"
  local description="${2:-$1}"
  
  if [[ -e "$item" ]] || [[ -L "$item" ]]; then
    if [[ "$DRY_RUN" == "true" ]]; then
      echo -e "  ${YELLOW}[DRY-RUN]${NC} Supprimerait: $description"
    else
      if rm -rf "$item" 2>/dev/null; then
        echo -e "  ${GREEN}✓${NC} Supprimé: $description"
        return 0
      else
        echo -e "  ${RED}✗${NC} Échec suppression: $description"
        return 1
      fi
    fi
  fi
  return 0
}

# Fonction pour nettoyer une ligne du PATH dans un fichier rc
clean_path_from_rc() {
  local rcfile="$1"
  
  if [[ ! -f "$rcfile" ]]; then
    return 0
  fi
  
  # Patterns à supprimer (lignes ajoutées par l'installateur)
  local patterns=(
    'export PATH="\$HOME/.local/bin:\$PATH"'
    'export PATH="$HOME/.local/bin:$PATH"'
    '# Added by Idris2 installer'
    '# Ajouté par installateur Idris2'
  )
  
  local modified=false
  local tmpfile
  tmpfile=$(mktemp)
  
  cp "$rcfile" "$tmpfile"
  
  for pattern in "${patterns[@]}"; do
    if grep -qF "$pattern" "$rcfile" 2>/dev/null; then
      if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "  ${YELLOW}[DRY-RUN]${NC} Nettoierait PATH dans: $rcfile"
      else
        grep -vF "$pattern" "$tmpfile" > "${tmpfile}.new" 2>/dev/null || true
        mv "${tmpfile}.new" "$tmpfile"
        modified=true
      fi
    fi
  done
  
  if [[ "$modified" == "true" ]] && [[ "$DRY_RUN" != "true" ]]; then
    # Ne remplacer que si le fichier a changé
    if ! diff -q "$rcfile" "$tmpfile" >/dev/null 2>&1; then
      cp "$tmpfile" "$rcfile"
      echo -e "  ${GREEN}✓${NC} Nettoyé PATH dans: $rcfile"
    fi
  fi
  
  rm -f "$tmpfile" "${tmpfile}.new" 2>/dev/null || true
}

# ==============================================================================
# MAIN
# ==============================================================================

echo ""
echo -e "${BOLD}══════════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}       Désinstallation d'Idris2 / pack / idris2-lsp${NC}"
echo -e "${BOLD}══════════════════════════════════════════════════════════════${NC}"
echo ""

# Détecter ce qui est installé
FOUND_ITEMS=()
FOUND_SIZE=0

check_and_add() {
  local path="$1"
  local desc="$2"
  if [[ -e "$path" ]] || [[ -L "$path" ]]; then
    FOUND_ITEMS+=("$path|$desc")
    if [[ -d "$path" ]]; then
      local size
      size=$(du -sh "$path" 2>/dev/null | cut -f1 || echo "?")
      echo -e "  ${GREEN}✓${NC} $desc ($size)"
    elif [[ -L "$path" ]]; then
      echo -e "  ${GREEN}✓${NC} $desc (lien symbolique)"
    else
      echo -e "  ${GREEN}✓${NC} $desc"
    fi
  fi
}

echo -e "${BLUE}Recherche des composants installés...${NC}"
echo ""

# Binaires dans ~/.local/bin/
echo -e "${BOLD}Binaires:${NC}"
check_and_add "$HOME/.local/bin/pack" "pack (gestionnaire de paquets)"
check_and_add "$HOME/.local/bin/pack_app" "pack_app (runtime)"
check_and_add "$HOME/.local/bin/idris2" "idris2 (compilateur)"
check_and_add "$HOME/.local/bin/idris2_app" "idris2_app (runtime)"
check_and_add "$HOME/.local/bin/idris2-lsp" "idris2-lsp (serveur LSP)"
check_and_add "$HOME/.local/bin/idris2-lsp_app" "idris2-lsp_app (runtime)"
check_and_add "$HOME/.local/bin/git" "git wrapper (installé par l'archive)"
check_and_add "$HOME/.local/bin/idris2-install-info" "idris2-install-info (debug)"
echo ""

# Données pack (nouveau layout ~/.pack/)
echo -e "${BOLD}Données pack (nouveau layout):${NC}"
check_and_add "$HOME/.pack" "~/.pack/ (installation complète)"
echo ""

# Données pack (ancien layout)
echo -e "${BOLD}Données pack (ancien layout):${NC}"
check_and_add "$HOME/.local/state/pack" "~/.local/state/pack/"
check_and_add "$HOME/.cache/pack" "~/.cache/pack/"
if [[ "$KEEP_CONFIG" != "true" ]]; then
  check_and_add "$HOME/.config/pack" "~/.config/pack/"
fi
echo ""

# Fichiers ISTIC
echo -e "${BOLD}Fichiers de l'installateur ISTIC:${NC}"
check_and_add "$HOME/.local/state/istic-idris2-install" "Infos d'installation ISTIC"
echo ""

# Fichiers idris2 globaux (peuvent exister indépendamment de pack)
echo -e "${BOLD}Autres fichiers Idris2:${NC}"
check_and_add "$HOME/.idris2" "~/.idris2/ (cache/config Idris2)"
echo ""

# Rien trouvé ?
if [[ ${#FOUND_ITEMS[@]} -eq 0 ]]; then
  echo -e "${GREEN}Aucune installation d'Idris2/pack détectée.${NC}"
  echo ""
  exit 0
fi

# Résumé
echo -e "${BOLD}──────────────────────────────────────────────────────────────${NC}"
TOTAL_ITEMS=${#FOUND_ITEMS[@]}
echo -e "  ${BOLD}$TOTAL_ITEMS${NC} éléments trouvés"

if [[ "$KEEP_CONFIG" == "true" ]]; then
  echo -e "  ${YELLOW}Note:${NC} --keep-config activé, ~/.config/pack sera conservé"
fi
echo ""

# Confirmation
if [[ "$AUTO_YES" != "true" ]] && [[ "$DRY_RUN" != "true" ]]; then
  echo -e "${YELLOW}Voulez-vous supprimer ces éléments ? Cette action est irréversible.${NC}"
  echo ""
  # Lire depuis /dev/tty pour supporter "curl ... | bash"
  if [[ -t 0 ]]; then
    # stdin est un terminal, read normal
    read -rp "Confirmer la suppression ? [o/N] " response
  elif [[ -r /dev/tty ]]; then
    # stdin est un pipe (curl|bash), lire depuis /dev/tty
    # Le prompt doit être affiché manuellement sur /dev/tty
    printf "Confirmer la suppression ? [o/N] " > /dev/tty
    read -r response < /dev/tty
  else
    echo -e "${RED}Impossible de lire la confirmation (pas de terminal).${NC}"
    echo "Utilisez --yes pour désinstaller sans confirmation :"
    echo "  curl -fsSL .../uninstall.sh | bash -s -- --yes"
    exit 1
  fi
  case "$response" in
    [oOyY]|[oOyY][uUeE][iIsS])
      echo ""
      ;;
    *)
      echo ""
      echo -e "${BLUE}Annulé.${NC}"
      exit 0
      ;;
  esac
fi

if [[ "$DRY_RUN" == "true" ]]; then
  echo -e "${YELLOW}Mode dry-run: rien ne sera supprimé${NC}"
  echo ""
fi

# Suppression
echo -e "${BLUE}Suppression en cours...${NC}"
echo ""

ERRORS=0

for item_entry in "${FOUND_ITEMS[@]}"; do
  path="${item_entry%%|*}"
  desc="${item_entry##*|}"
  if ! remove_item "$path" "$desc"; then
    ((ERRORS++)) || true
  fi
done

# Nettoyer les fichiers rc
echo ""
echo -e "${BLUE}Nettoyage des fichiers de configuration shell...${NC}"
echo ""

for rcfile in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.profile" "$HOME/.bash_profile"; do
  clean_path_from_rc "$rcfile"
done

# Résultat final
echo ""
echo -e "${BOLD}══════════════════════════════════════════════════════════════${NC}"

if [[ "$DRY_RUN" == "true" ]]; then
  echo -e "${YELLOW}       MODE DRY-RUN - Rien n'a été supprimé${NC}"
  echo -e "${BOLD}══════════════════════════════════════════════════════════════${NC}"
  echo ""
  echo "Relancez sans --dry-run pour effectuer la suppression."
elif [[ $ERRORS -eq 0 ]]; then
  echo -e "${GREEN}       DÉSINSTALLATION TERMINÉE${NC}"
  echo -e "${BOLD}══════════════════════════════════════════════════════════════${NC}"
  echo ""
  echo "  Idris2, pack et idris2-lsp ont été supprimés."
  echo ""
  echo "  Pour appliquer les changements de PATH, fermez et rouvrez votre terminal"
  echo "  ou exécutez: source ~/.bashrc"
  echo ""
  if [[ "$KEEP_CONFIG" == "true" ]]; then
    echo -e "  ${YELLOW}Note:${NC} ~/.config/pack a été conservé (--keep-config)"
    echo ""
  fi
  echo "  Pour réinstaller:"
  echo "    curl -fsSL https://raw.githubusercontent.com/thanberree/idris2-install/main/install.sh | bash"
  echo ""
else
  echo -e "${YELLOW}       DÉSINSTALLATION PARTIELLE${NC}"
  echo -e "${BOLD}══════════════════════════════════════════════════════════════${NC}"
  echo ""
  echo -e "  ${YELLOW}$ERRORS erreur(s) rencontrée(s).${NC}"
  echo "  Certains fichiers n'ont pas pu être supprimés."
  echo "  Vérifiez les permissions ou supprimez-les manuellement."
  echo ""
  exit 1
fi
