#!/usr/bin/env bash
set -euo pipefail

# Configuration
ARCHIVE_URL="${ARCHIVE_URL:-https://example.com/idris2-pack-nightly-250828.tar.gz}"
COLLECTION="nightly-250828"

# Couleurs
RED='\e[91m'
GREEN='\e[92m'
YELLOW='\e[93m'
NC='\e[0m'

info() { echo -e "${GREEN}[INFO]${NC} $*"; }
error() { echo -e "${RED}[ERREUR]${NC} $*" >&2; exit 1; }

# Vérifications
[[ "${EUID:-$(id -u)}" -eq 0 ]] && error "Ne pas exécuter en root."
command -v curl &>/dev/null || error "curl est requis. Installez-le avec: sudo apt install curl"

# Installation
info "Téléchargement des binaires Idris2 + pack..."
mkdir -p "$HOME/.local/bin" "$HOME/.local/state" "$HOME/.config" "$HOME/.cache"

curl -fSL "$ARCHIVE_URL" | tar xzf - -C "$HOME"

# PATH
if ! grep -q '.local/bin' "$HOME/.bashrc" 2>/dev/null; then
  echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
  info "PATH mis à jour dans ~/.bashrc"
fi

export PATH="$HOME/.local/bin:$PATH"

# Vérification
if command -v pack &>/dev/null && command -v idris2 &>/dev/null; then
  info "Installation terminée."
  echo ""
  pack info
  echo ""
  echo -e "${YELLOW}Ouvrez un nouveau terminal ou tapez:${NC} source ~/.bashrc"
else
  error "Problème lors de l'installation."
fi
