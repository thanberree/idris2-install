#!/bin/bash
# Script de build automatisé pour créer les archives Idris2+pack
# pour plusieurs distributions Linux
#
# Usage: ./build-all.sh [collection]
# Exemple: ./build-all.sh nightly-250828

set -e

COLLECTION="${1:-nightly-250828}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG_DIR="/tmp/idris2-build-logs"
mkdir -p "$LOG_DIR"

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${BLUE}[$(date +%H:%M:%S)]${NC} $1"; }
success() { echo -e "${GREEN}[✓]${NC} $1"; }
error() { echo -e "${RED}[✗]${NC} $1"; }
warning() { echo -e "${YELLOW}[!]${NC} $1"; }

# Distributions à construire
declare -A DISTROS=(
  ["debian:12"]="bookworm"
  ["fedora:40"]="fedora"
  # ["archlinux:latest"]="arch"  # Désactivé: AUR existe déjà
)

# Fonction pour construire une distribution
build_distro() {
  local image="$1"
  local codename="$2"
  local container_name="idris2-build-${codename}"
  local archive_name="idris2-pack-${COLLECTION}-${codename}-full.tar.gz"
  local log_file="${LOG_DIR}/${codename}.log"
  
  log "=== Construction pour $image ($codename) ==="
  
  # Vérifier si l'archive existe déjà sur GitHub
  if curl -fsSL -o /dev/null "https://github.com/thanberree/idris2-install/releases/download/v1.0/${archive_name}" 2>/dev/null; then
    warning "Archive $archive_name existe déjà sur GitHub. Passer."
    return 0
  fi
  
  # Déterminer le gestionnaire de paquets
  local pkg_manager pkg_install pkg_update deps
  case "$image" in
    debian:*|ubuntu:*)
      pkg_manager="apt-get"
      pkg_update="apt-get update -qq"
      pkg_install="apt-get install -y -qq"
      deps="curl sudo lsb-release chezscheme libgmp-dev make gcc git"
      ;;
    fedora:*)
      pkg_manager="dnf"
      pkg_update="dnf check-update || true"
      pkg_install="dnf install -y -q"
      deps="curl sudo chez-scheme gmp-devel make gcc git"
      ;;
    archlinux:*)
      pkg_manager="pacman"
      pkg_update="pacman -Sy --noconfirm"
      pkg_install="pacman -S --noconfirm --needed"
      deps="curl sudo chez-scheme gmp make gcc git"
      ;;
  esac
  
  # Supprimer le conteneur existant s'il est arrêté
  if docker ps -a --format '{{.Names}}' | grep -q "^${container_name}$"; then
    if ! docker ps --format '{{.Names}}' | grep -q "^${container_name}$"; then
      log "Suppression du conteneur arrêté $container_name"
      docker rm -f "$container_name" >/dev/null
    fi
  fi
  
  # Créer le conteneur s'il n'existe pas
  if ! docker ps -a --format '{{.Names}}' | grep -q "^${container_name}$"; then
    log "Création du conteneur $container_name"
    docker run --name "$container_name" -d "$image" bash -c "
      ln -snf /usr/share/zoneinfo/UTC /etc/localtime 2>/dev/null || true
      echo UTC > /etc/timezone 2>/dev/null || true
      $pkg_update
      $pkg_install $deps
      useradd -m -s /bin/bash builder 2>/dev/null || true
      echo 'builder ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers
      sleep infinity
    " >> "$log_file" 2>&1
    sleep 10
  fi
  
  # Fonction pour exécuter dans le conteneur
  run_cmd() {
    docker exec "$container_name" su - builder -c "export PATH=\"\$HOME/.local/bin:\$PATH\" && $1"
  }
  
  # Étape 1: Installer pack si nécessaire
  if ! run_cmd "command -v pack" &>/dev/null; then
    log "[$codename] Installation de pack..."
    run_cmd '
      curl -fsSL https://raw.githubusercontent.com/stefan-hoeck/idris2-pack/main/install.bash -o install.bash
      sed -i "s/read -r -p .*/SCHEME=\${SCHEME:-\$DETECTED_SCHEME}/" install.bash
      SCHEME=chezscheme bash install.bash
    ' >> "$log_file" 2>&1
  else
    log "[$codename] pack déjà installé"
  fi
  
  # Étape 2: Vérifier/changer la collection
  local current_collection
  current_collection=$(run_cmd "pack info 2>/dev/null | grep 'Package Collection' | awk '{print \$4}'" || echo "")
  if [[ "$current_collection" != "$COLLECTION" ]]; then
    log "[$codename] Switch vers $COLLECTION..."
    run_cmd "pack --bootstrap switch $COLLECTION" >> "$log_file" 2>&1
  else
    log "[$codename] Collection $COLLECTION déjà active"
  fi
  
  # Étape 3: Installer les packages
  log "[$codename] Installation des packages..."
  run_cmd "pack install ansi containers contrib elab-pretty elab-util getopts hedgehog prettier-ansi pretty-show prim sop" >> "$log_file" 2>&1
  
  # Étape 4: Installer idris2-lsp si nécessaire
  if ! run_cmd "command -v idris2-lsp" &>/dev/null; then
    log "[$codename] Installation de idris2-lsp..."
    run_cmd "pack install-app idris2-lsp" >> "$log_file" 2>&1
  else
    log "[$codename] idris2-lsp déjà installé"
  fi
  
  # Étape 5: Vérification
  log "[$codename] Vérification..."
  run_cmd "pack info && idris2 --version && idris2-lsp --version"
  
  # Étape 6: Créer l'archive
  log "[$codename] Création de l'archive..."
  run_cmd "
    cd ~
    tar --exclude='.git' --exclude='.cache/pack/git' -czf /tmp/$archive_name \
      .local/bin/pack \
      .local/bin/pack_app \
      .local/bin/idris2 \
      .local/bin/idris2-lsp \
      .local/state/pack \
      .config/pack \
      .cache/pack
  " >> "$log_file" 2>&1
  
  # Étape 7: Extraire l'archive
  docker cp "$container_name:/tmp/$archive_name" "/tmp/$archive_name"
  
  success "[$codename] Archive créée: /tmp/$archive_name ($(du -h /tmp/$archive_name | cut -f1))"
  
  # Étape 8: Upload sur GitHub
  log "[$codename] Upload sur GitHub..."
  if gh release upload v1.0 "/tmp/$archive_name" --clobber 2>> "$log_file"; then
    success "[$codename] Upload réussi!"
  else
    error "[$codename] Échec de l'upload. Voir $log_file"
    return 1
  fi
  
  return 0
}

# Main
echo "════════════════════════════════════════════════════════════════"
echo "     Build Idris2+pack pour distributions Linux"
echo "     Collection: $COLLECTION"
echo "════════════════════════════════════════════════════════════════"
echo ""
echo "Distributions à construire:"
for image in "${!DISTROS[@]}"; do
  echo "  • $image (${DISTROS[$image]})"
done
echo ""
echo "Logs: $LOG_DIR/"
echo ""

# Construire chaque distribution
FAILED=()
SUCCESS=()

for image in "${!DISTROS[@]}"; do
  codename="${DISTROS[$image]}"
  if build_distro "$image" "$codename"; then
    SUCCESS+=("$codename")
  else
    FAILED+=("$codename")
  fi
  echo ""
done

# Résumé
echo "════════════════════════════════════════════════════════════════"
echo "                       RÉSUMÉ"
echo "════════════════════════════════════════════════════════════════"

if [[ ${#SUCCESS[@]} -gt 0 ]]; then
  echo -e "${GREEN}Réussis:${NC} ${SUCCESS[*]}"
fi

if [[ ${#FAILED[@]} -gt 0 ]]; then
  echo -e "${RED}Échoués:${NC} ${FAILED[*]}"
  echo ""
  echo "Consultez les logs dans $LOG_DIR/ pour les détails."
  exit 1
fi

echo ""
echo "Toutes les archives ont été créées et uploadées!"
