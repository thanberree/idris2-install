#!/usr/bin/env bash
set -euo pipefail

# Version de l'installeur
INSTALLER_VERSION="1.4.0"

# Configuration
COLLECTION="nightly-250828"
RELEASE_BASE_URL="https://github.com/thanberree/idris2-install/releases/download/v1.0"
MIN_DISK_SPACE_MB=300

# Couleurs (désactivées si pas de terminal)
if [[ -t 1 ]]; then
  RED='\e[91m'
  GREEN='\e[92m'
  YELLOW='\e[93m'
  NC='\e[0m'
else
  RED=''
  GREEN=''
  YELLOW=''
  NC=''
fi

info() { echo -e "${GREEN}[INFO]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERREUR]${NC} $*" >&2; exit 1; }

# Nettoyage en cas d'erreur
TEMP_ARCHIVE=""
cleanup() {
  if [[ -n "$TEMP_ARCHIVE" ]] && [[ -f "$TEMP_ARCHIVE" ]]; then
    rm -f "$TEMP_ARCHIVE"
  fi
}
trap cleanup EXIT

# Parser les arguments
FORCE=0
for arg in "$@"; do
  case "$arg" in
    --force|-f) FORCE=1 ;;
    --version|-v)
      echo "install.sh version $INSTALLER_VERSION"
      exit 0
      ;;
    --help|-h)
      echo "Usage: $0 [OPTIONS]"
      echo ""
      echo "Options:"
      echo "  --force, -f    Réinstaller même si une installation existe"
      echo "  --version, -v  Afficher la version du script"
      echo "  --help, -h     Afficher cette aide"
      exit 0
      ;;
    *)
      warn "Option inconnue: $arg"
      ;;
  esac
done

echo "Installation d'Idris2 et du gestionnaire de paquets pack."
echo -e "${YELLOW}[Script v$INSTALLER_VERSION]${NC}"
echo ""

# Vérifications de base
[[ "${EUID:-$(id -u)}" -eq 0 ]] && error "Ne pas exécuter en root."
command -v curl &>/dev/null || error "curl est requis. Installez-le avec: sudo apt install curl"

# Détecter l'OS et choisir la bonne archive
detect_archive_url() {
  if [[ -n "${ARCHIVE_URL:-}" ]]; then
    # URL fournie manuellement
    echo "$ARCHIVE_URL"
    return
  fi
  
  local os_type arch codename
  os_type=$(uname -s)
  arch=$(uname -m)
  
  case "$os_type" in
    Linux)
      if command -v lsb_release &>/dev/null; then
        codename=$(lsb_release -cs)
      elif [[ -f /etc/os-release ]]; then
        codename=$(grep VERSION_CODENAME /etc/os-release | cut -d= -f2)
      else
        codename="noble"  # fallback Ubuntu 24.04
      fi
      echo "${RELEASE_BASE_URL}/idris2-pack-${COLLECTION}-${codename}-full.tar.gz"
      ;;
    Darwin)
      if [[ "$arch" == "arm64" ]]; then
        echo "${RELEASE_BASE_URL}/idris2-pack-${COLLECTION}-macos-arm64-full.tar.gz"
      else
        echo "${RELEASE_BASE_URL}/idris2-pack-${COLLECTION}-macos-x86_64-full.tar.gz"
      fi
      ;;
    *)
      error "OS non supporté: $os_type. Seuls Linux (Ubuntu) et macOS sont supportés."
      ;;
  esac
}

ARCHIVE_URL=$(detect_archive_url)
info "Archive détectée: $(basename "$ARCHIVE_URL")"

# Vérifier l'espace disque disponible
check_disk_space() {
  local available_mb
  available_mb=$(df -m "$HOME" | awk 'NR==2 {print $4}')
  if [[ "$available_mb" -lt "$MIN_DISK_SPACE_MB" ]]; then
    error "Espace disque insuffisant. Requis: ${MIN_DISK_SPACE_MB} Mo, Disponible: ${available_mb} Mo"
  fi
}
check_disk_space

# Détection d'installations existantes
OLD_INSTALL=""
NEW_INSTALL=""

if [[ -d "$HOME/.pack" ]] || [[ -x "$HOME/.pack/bin/pack" ]]; then
  OLD_INSTALL="$HOME/.pack"
fi

if [[ -x "$HOME/.local/bin/pack" ]] || [[ -d "$HOME/.local/state/pack" ]]; then
  NEW_INSTALL="$HOME/.local"
fi

# Si une installation existe, proposer de désinstaller
if [[ -n "$OLD_INSTALL" ]] || [[ -n "$NEW_INSTALL" ]]; then
  warn "Une installation existante d'Idris2/pack a été détectée."
  echo ""
  
  if [[ "$FORCE" == "1" ]]; then
    info "Option --force détectée, réinstallation..."
  elif [[ -t 0 ]]; then
    read -p "Voulez-vous la supprimer et réinstaller ? [o/N] " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[OoYy]$ ]]; then
      info "Installation annulée."
      exit 0
    fi
  else
    echo "Pour réinstaller, utilisez l'option --force :"
    echo "  curl -fsSL https://raw.githubusercontent.com/thanberree/idris2-install/main/install.sh | bash -s -- --force"
    exit 0
  fi
  
  info "Suppression de l'ancienne installation..."
  
  if [[ -n "$OLD_INSTALL" ]]; then
    rm -rf "$HOME/.pack"
    sed -i '/\.pack\/bin/d' "$HOME/.bashrc" 2>/dev/null || true
  fi
  
  if [[ -n "$NEW_INSTALL" ]]; then
    rm -rf "$HOME/.local/bin/pack" "$HOME/.local/bin/pack_app" "$HOME/.local/bin/idris2"
    rm -rf "$HOME/.local/state/pack" "$HOME/.config/pack" "$HOME/.cache/pack"
  fi
  
  info "Ancienne installation supprimée."
  echo ""
fi

# Collecter les paquets apt à installer
APT_PACKAGES=""
APT_UPDATED=0

need_apt_update() {
  if [[ "$APT_UPDATED" == "0" ]] && command -v apt-get &>/dev/null; then
    info "Mise à jour des sources apt..."
    sudo apt-get update
    APT_UPDATED=1
  fi
}

# Vérifier Chez Scheme
if ! command -v chezscheme &>/dev/null && ! command -v chez &>/dev/null && ! command -v scheme &>/dev/null; then
  APT_PACKAGES="$APT_PACKAGES chezscheme"
fi

# Vérifier rlwrap
if ! command -v rlwrap &>/dev/null; then
  APT_PACKAGES="$APT_PACKAGES rlwrap"
fi

# Vérifier outils nécessaires
command -v timeout &>/dev/null || APT_PACKAGES="$APT_PACKAGES coreutils"
command -v unzip &>/dev/null || APT_PACKAGES="$APT_PACKAGES unzip"

# Installer tous les paquets apt en une seule fois
if [[ -n "$APT_PACKAGES" ]]; then
  if command -v apt-get &>/dev/null; then
    need_apt_update
    info "Installation des dépendances:$APT_PACKAGES"
    sudo apt-get install -y $APT_PACKAGES
  else
    error "apt-get non disponible. Installez manuellement:$APT_PACKAGES"
  fi
fi

# Vérifier que /usr/bin/chezscheme existe (le shebang des binaires en a besoin)
if [[ ! -x /usr/bin/chezscheme ]]; then
  if [[ -x /usr/bin/scheme ]]; then
    info "Création du lien /usr/bin/chezscheme -> /usr/bin/scheme"
    sudo ln -sf /usr/bin/scheme /usr/bin/chezscheme
  elif [[ -x /usr/bin/chez ]]; then
    info "Création du lien /usr/bin/chezscheme -> /usr/bin/chez"
    sudo ln -sf /usr/bin/chez /usr/bin/chezscheme
  elif command -v chezscheme &>/dev/null; then
    # chezscheme existe mais pas dans /usr/bin
    chez_path=$(command -v chezscheme)
    info "Création du lien /usr/bin/chezscheme -> $chez_path"
    sudo ln -sf "$chez_path" /usr/bin/chezscheme
  else
    error "Chez Scheme introuvable. Vérifiez: which scheme chez chezscheme"
  fi
fi

# Téléchargement et installation
info "Téléchargement des binaires Idris2 + pack..."
mkdir -p "$HOME/.local/bin" "$HOME/.local/state" "$HOME/.config" "$HOME/.cache"

TEMP_ARCHIVE=$(mktemp)
if ! curl -fSL "$ARCHIVE_URL" -o "$TEMP_ARCHIVE"; then
  error "Échec du téléchargement. Vérifiez votre connexion internet."
fi

# Vérifier que l'archive n'est pas vide ou trop petite
ARCHIVE_SIZE=$(stat -c%s "$TEMP_ARCHIVE" 2>/dev/null || stat -f%z "$TEMP_ARCHIVE" 2>/dev/null || echo "0")
if [[ "$ARCHIVE_SIZE" -lt 1000000 ]]; then
  error "Archive téléchargée invalide (taille: $ARCHIVE_SIZE octets)"
fi

info "Extraction de l'archive..."
if ! tar xzf "$TEMP_ARCHIVE" -C "$HOME"; then
  error "Échec de l'extraction de l'archive."
fi

rm -f "$TEMP_ARCHIVE"
TEMP_ARCHIVE=""

# Corriger les chemins codés en dur dans les scripts wrapper
# Les binaires générés par pack contiennent des chemins absolus vers le HOME de la machine de build
info "Correction des chemins dans les scripts..."
for script in "$HOME/.local/bin/pack" "$HOME/.local/bin/idris2" "$HOME/.local/bin/idris2-lsp"; do
  if [[ -f "$script" ]]; then
    # Remplacer tout chemin /home/*/. par $HOME/.
    sed -i "s|/home/[^/]*/\\.local/|$HOME/.local/|g" "$script"
  fi
done

# Corriger aussi les chemins dans pack_app si présent
if [[ -d "$HOME/.local/bin/pack_app" ]]; then
  for script in "$HOME/.local/bin/pack_app/"*; do
    if [[ -f "$script" ]]; then
      sed -i "s|/home/[^/]*/\\.local/|$HOME/.local/|g" "$script"
    fi
  done
fi

# PATH
if ! grep -q '.local/bin' "$HOME/.bashrc" 2>/dev/null; then
  echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
  info "PATH mis à jour dans ~/.bashrc"
fi

# Support zsh
if [[ -f "$HOME/.zshrc" ]] && ! grep -q '.local/bin' "$HOME/.zshrc" 2>/dev/null; then
  echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.zshrc"
  info "PATH mis à jour dans ~/.zshrc"
fi

export PATH="$HOME/.local/bin:$PATH"

# Vérification finale détaillée
echo ""
info "Vérification de l'installation..."

INSTALL_OK=1
MISSING_CMDS=""

# Vérifier chaque commande individuellement
for cmd in pack idris2 idris2-lsp; do
  if ! command -v "$cmd" &>/dev/null; then
    MISSING_CMDS="$MISSING_CMDS $cmd"
    INSTALL_OK=0
    
    # Diagnostic détaillé
    echo ""
    error_msg="${RED}[ERREUR]${NC} $cmd n'est pas accessible."
    echo -e "$error_msg"
    
    # Vérifier si le fichier existe
    if [[ -f "$HOME/.local/bin/$cmd" ]]; then
      echo "  → Le fichier existe: $HOME/.local/bin/$cmd"
      if [[ -x "$HOME/.local/bin/$cmd" ]]; then
        echo "  → Le fichier est exécutable"
        echo "  → Problème probable: PATH non configuré correctement"
        echo "  → Contenu actuel du PATH: $PATH"
      else
        echo "  → Le fichier n'est PAS exécutable"
        echo "  → Correction: chmod +x $HOME/.local/bin/$cmd"
        chmod +x "$HOME/.local/bin/$cmd"
      fi
    else
      echo "  → Le fichier n'existe PAS dans $HOME/.local/bin/"
      echo "  → L'archive téléchargée ne contenait peut-être pas ce binaire"
    fi
  fi
done

if [[ "$INSTALL_OK" == "1" ]]; then
  echo ""
  info "Installation terminée avec succès !"
  echo ""
  pack info
  echo ""
  
  # Vérifier si pack/idris2 sont accessibles sans le PATH modifié
  ORIGINAL_PATH="${PATH#$HOME/.local/bin:}"
  if PATH="$ORIGINAL_PATH" command -v pack &>/dev/null; then
    info "Les commandes pack, idris2 et idris2-lsp sont prêtes à l'emploi."
  else
    echo -e "${YELLOW}Pour utiliser Idris2, ouvrez un nouveau terminal ou tapez:${NC}"
    echo "  source ~/.bashrc"
    echo ""
    echo "Puis vérifiez avec:"
    echo "  pack info"
    echo "  idris2 --version"
    echo "  idris2-lsp --version"
  fi
else
  echo ""
  echo -e "${RED}══════════════════════════════════════════════════════════════${NC}"
  echo -e "${RED}INSTALLATION INCOMPLÈTE${NC}"
  echo -e "${RED}══════════════════════════════════════════════════════════════${NC}"
  echo ""
  echo "Les commandes suivantes ne sont pas accessibles:$MISSING_CMDS"
  echo ""
  echo "Solutions possibles:"
  echo "  1. Rechargez votre shell: source ~/.bashrc"
  echo "  2. Vérifiez que ~/.local/bin est dans votre PATH"
  echo "  3. Réinstallez avec: curl -fsSL https://raw.githubusercontent.com/thanberree/idris2-install/main/install.sh | bash -s -- --force"
  echo ""
  exit 1
fi
