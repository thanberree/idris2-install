#!/usr/bin/env bash
# =============================================================================
# Script de réparation pour les machines ISTIC
# =============================================================================
# Ce script répare les dégâts causés par l'exécution accidentelle de install.sh
# sur une machine de l'université (salle de TP ISTIC).
#
# Usage: curl -fsSL https://raw.githubusercontent.com/thanberree/idris2-install/main/repair-istic.sh | bash
# =============================================================================

set -euo pipefail

# Couleurs
if [[ -t 1 ]]; then
  RED='\e[91m'
  GREEN='\e[92m'
  YELLOW='\e[93m'
  BLUE='\e[94m'
  BOLD='\e[1m'
  NC='\e[0m'
else
  RED=''
  GREEN=''
  YELLOW=''
  BLUE=''
  BOLD=''
  NC=''
fi

info()    { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
error()   { echo -e "${RED}[ERREUR]${NC} $*" >&2; exit 1; }
success() { echo -e "${GREEN}[OK]${NC} $*"; }

echo ""
echo -e "${BLUE}╔══════════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║       Script de réparation pour les machines ISTIC                   ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Vérifier qu'on n'est pas root
[[ "${EUID:-$(id -u)}" -eq 0 ]] && error "Ne pas exécuter en root."

REPAIRS_DONE=0

# =============================================================================
# 1. Supprimer les binaires installés par le script dans ~/.local/bin
# =============================================================================
info "Recherche des fichiers installés par le script..."

for file in "$HOME/.local/bin/pack" "$HOME/.local/bin/pack_app" "$HOME/.local/bin/idris2" "$HOME/.local/bin/idris2-lsp" "$HOME/.local/bin/idris2-install-info" "$HOME/.local/bin/idris2_app" "$HOME/.local/bin/idris2-lsp_app"; do
  if [[ -e "$file" ]]; then
    rm -rf "$file"
    warn "Supprimé: $file"
    REPAIRS_DONE=$((REPAIRS_DONE + 1))
  fi
done

# =============================================================================
# 2. Supprimer les dossiers de données pack
# =============================================================================
for dir in "$HOME/.local/state/pack" "$HOME/.config/pack" "$HOME/.cache/pack" "$HOME/.local/state/istic-idris2-install" "$HOME/.pack"; do
  if [[ -d "$dir" ]]; then
    rm -rf "$dir"
    warn "Supprimé: $dir"
    REPAIRS_DONE=$((REPAIRS_DONE + 1))
  fi
done

# =============================================================================
# 3. Nettoyer .bashrc
# =============================================================================
if [[ -f "$HOME/.bashrc" ]]; then
  # Créer un backup
  cp "$HOME/.bashrc" "$HOME/.bashrc.backup-repair-$(date +%Y%m%d%H%M%S)"
  
  # Supprimer les lignes ajoutées par le script d'installation
  # - export PATH="$HOME/.local/bin:$PATH"
  # - Lignes contenant .pack/bin
  # - Lignes contenant SCHEMEHEAPDIRS ajoutées par le script
  
  BEFORE=$(wc -l < "$HOME/.bashrc")
  
  # Utiliser un fichier temporaire pour éviter les problèmes de sed in-place
  grep -v '\.local/bin.*PATH\|\.pack/bin\|SCHEMEHEAPDIRS.*pack\|SCHEMEHEAPDIRS.*\.local' "$HOME/.bashrc" > "$HOME/.bashrc.tmp" 2>/dev/null || true
  mv "$HOME/.bashrc.tmp" "$HOME/.bashrc"
  
  AFTER=$(wc -l < "$HOME/.bashrc")
  
  if [[ "$BEFORE" -ne "$AFTER" ]]; then
    REMOVED=$((BEFORE - AFTER))
    warn "Nettoyé ~/.bashrc: $REMOVED ligne(s) supprimée(s)"
    REPAIRS_DONE=$((REPAIRS_DONE + 1))
  fi
fi

# =============================================================================
# 4. Nettoyer .zshrc si présent
# =============================================================================
if [[ -f "$HOME/.zshrc" ]]; then
  cp "$HOME/.zshrc" "$HOME/.zshrc.backup-repair-$(date +%Y%m%d%H%M%S)"
  
  BEFORE=$(wc -l < "$HOME/.zshrc")
  
  grep -v '\.local/bin.*PATH\|\.pack/bin\|SCHEMEHEAPDIRS.*pack\|SCHEMEHEAPDIRS.*\.local' "$HOME/.zshrc" > "$HOME/.zshrc.tmp" 2>/dev/null || true
  mv "$HOME/.zshrc.tmp" "$HOME/.zshrc"
  
  AFTER=$(wc -l < "$HOME/.zshrc")
  
  if [[ "$BEFORE" -ne "$AFTER" ]]; then
    REMOVED=$((BEFORE - AFTER))
    warn "Nettoyé ~/.zshrc: $REMOVED ligne(s) supprimée(s)"
    REPAIRS_DONE=$((REPAIRS_DONE + 1))
  fi
fi

# =============================================================================
# 5. Nettoyer .profile si modifié
# =============================================================================
if [[ -f "$HOME/.profile" ]]; then
  BEFORE=$(wc -l < "$HOME/.profile")
  
  if grep -q '\.local/bin.*PATH\|\.pack/bin' "$HOME/.profile" 2>/dev/null; then
    cp "$HOME/.profile" "$HOME/.profile.backup-repair-$(date +%Y%m%d%H%M%S)"
    grep -v '\.local/bin.*PATH\|\.pack/bin' "$HOME/.profile" > "$HOME/.profile.tmp" 2>/dev/null || true
    mv "$HOME/.profile.tmp" "$HOME/.profile"
    
    AFTER=$(wc -l < "$HOME/.profile")
    REMOVED=$((BEFORE - AFTER))
    warn "Nettoyé ~/.profile: $REMOVED ligne(s) supprimée(s)"
    REPAIRS_DONE=$((REPAIRS_DONE + 1))
  fi
fi

# =============================================================================
# Résumé
# =============================================================================
echo ""
if [[ "$REPAIRS_DONE" -gt 0 ]]; then
  echo -e "${GREEN}╔══════════════════════════════════════════════════════════════════════╗${NC}"
  echo -e "${GREEN}║                        Réparation terminée !                         ║${NC}"
  echo -e "${GREEN}╚══════════════════════════════════════════════════════════════════════╝${NC}"
  echo ""
  info "$REPAIRS_DONE élément(s) réparé(s)."
  echo ""
  warn "IMPORTANT: Fermez ce terminal et ouvrez-en un nouveau pour appliquer les changements."
  echo ""
  
  # Vérifier que idris2 global est accessible
  if [[ -x /usr/local/bin/idris2 ]]; then
    info "Vérification: /usr/local/bin/idris2 est disponible."
    echo ""
    echo "Après avoir ouvert un nouveau terminal, testez avec:"
    echo "  idris2 --version"
  fi
else
  echo -e "${GREEN}╔══════════════════════════════════════════════════════════════════════╗${NC}"
  echo -e "${GREEN}║                   Aucune réparation nécessaire                       ║${NC}"
  echo -e "${GREEN}╚══════════════════════════════════════════════════════════════════════╝${NC}"
  echo ""
  info "Votre compte n'a pas été affecté par le script d'installation."
  
  # Vérifier que idris2 fonctionne
  if command -v idris2 &>/dev/null; then
    info "idris2 est accessible: $(which idris2)"
  fi
fi

echo ""
