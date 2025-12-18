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

# Mapper les codenames dérivés vers leur base Ubuntu/Debian
map_codename() {
  local codename="$1"
  case "$codename" in
    # Linux Mint -> Ubuntu
    virginia|vera|vanessa|uma|ulyssa|ulyana) echo "jammy" ;;  # Mint 21.x -> Ubuntu 22.04
    wilma|faye) echo "noble" ;;  # Mint 22.x -> Ubuntu 24.04
    # Pop!_OS -> Ubuntu
    jammy|noble|focal|bionic) echo "$codename" ;;
    # Debian
    bookworm|bullseye|buster) echo "$codename" ;;
    # Fedora (pas de codename, utiliser ID)
    *) echo "$codename" ;;
  esac
}

# Détecter l'OS et choisir la bonne archive
detect_archive_url() {
  if [[ -n "${ARCHIVE_URL:-}" ]]; then
    # URL fournie manuellement
    echo "$ARCHIVE_URL"
    return
  fi
  
  local os_type arch codename distro_id
  os_type=$(uname -s)
  arch=$(uname -m)
  
  case "$os_type" in
    Linux)
      # Détecter l'ID de la distribution
      if [[ -f /etc/os-release ]]; then
        distro_id=$(grep "^ID=" /etc/os-release | cut -d= -f2 | tr -d '"')
      fi
      
      # Gérer Fedora/Arch différemment
      case "$distro_id" in
        fedora)
          echo "${RELEASE_BASE_URL}/idris2-pack-${COLLECTION}-fedora-full.tar.gz"
          return
          ;;
        arch|manjaro)
          echo "${RELEASE_BASE_URL}/idris2-pack-${COLLECTION}-arch-full.tar.gz"
          return
          ;;
      esac
      
      # Pour Debian/Ubuntu et dérivés
      if command -v lsb_release &>/dev/null; then
        codename=$(lsb_release -cs)
      elif [[ -f /etc/os-release ]]; then
        codename=$(grep VERSION_CODENAME /etc/os-release | cut -d= -f2)
      else
        codename="noble"  # fallback Ubuntu 24.04
      fi
      
      # Mapper vers la base Ubuntu/Debian
      codename=$(map_codename "$codename")
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
      error "OS non supporté: $os_type. Seuls Linux (Ubuntu/Debian/Fedora/Arch) et macOS sont supportés."
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
command -v git &>/dev/null || APT_PACKAGES="$APT_PACKAGES git"

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

# Supprimer le cache git incomplet
# L'archive contient .cache/pack/git/ sans les dossiers .git, ce qui casse pack install-app
if [[ -d "$HOME/.cache/pack/git" ]]; then
  info "Nettoyage du cache git incomplet..."
  rm -rf "$HOME/.cache/pack/git"
fi

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

# Vérifier les commandes essentielles (pack et idris2)
PACK_OK=0
IDRIS2_OK=0
LSP_OK=0

if command -v pack &>/dev/null; then
  PACK_OK=1
fi

if command -v idris2 &>/dev/null; then
  IDRIS2_OK=1
fi

if command -v idris2-lsp &>/dev/null; then
  LSP_OK=1
fi

# Fonction pour afficher le résumé de l'installation
show_install_summary() {
  echo ""
  echo -e "${GREEN}══════════════════════════════════════════════════════════════${NC}"
  echo -e "${GREEN}           RÉSUMÉ DE L'INSTALLATION${NC}"
  echo -e "${GREEN}══════════════════════════════════════════════════════════════${NC}"
  echo ""
  
  # Afficher les informations sur pack
  if [[ "$PACK_OK" == "1" ]]; then
    # pack n'a pas d'option --version, on utilise pack info pour obtenir la collection
    local pack_collection
    pack_collection=$(pack info 2>/dev/null | grep -i "collection" | head -1 || echo "$COLLECTION")
    echo -e "  ${GREEN}✓${NC} pack           : installé"
    echo "                    Chemin  : $HOME/.local/bin/pack"
    echo "                    $pack_collection"
  else
    echo -e "  ${RED}✗${NC} pack           : NON INSTALLÉ"
  fi
  echo ""
  
  # Afficher les informations sur idris2
  if [[ "$IDRIS2_OK" == "1" ]]; then
    local idris2_version
    idris2_version=$(idris2 --version 2>/dev/null | head -1 || echo "version inconnue")
    echo -e "  ${GREEN}✓${NC} idris2         : installé"
    echo "                    Chemin  : $HOME/.local/bin/idris2"
    echo "                    Version : $idris2_version"
  else
    echo -e "  ${RED}✗${NC} idris2         : NON INSTALLÉ"
  fi
  echo ""
  
  # Afficher les informations sur idris2-lsp
  if [[ "$LSP_OK" == "1" ]]; then
    local lsp_version
    lsp_version=$(idris2-lsp --version 2>/dev/null | head -1 || echo "version inconnue")
    echo -e "  ${GREEN}✓${NC} idris2-lsp     : installé"
    echo "                    Chemin  : $HOME/.local/bin/idris2-lsp"
    echo "                    Version : $lsp_version"
  else
    echo -e "  ${YELLOW}✗${NC} idris2-lsp     : NON INSTALLÉ"
  fi
  echo ""
  
  # Afficher ce qui a été ajouté au PATH
  echo -e "${GREEN}──────────────────────────────────────────────────────────────${NC}"
  echo "  Configuration du PATH :"
  echo ""
  echo "  La ligne suivante a été ajoutée à votre fichier de configuration :"
  echo -e "    ${YELLOW}export PATH=\"\$HOME/.local/bin:\$PATH\"${NC}"
  echo ""
  if [[ -f "$HOME/.bashrc" ]]; then
    echo "    → ~/.bashrc : configuré"
  fi
  if [[ -f "$HOME/.zshrc" ]]; then
    echo "    → ~/.zshrc  : configuré"
  fi
  echo ""
}

# Cas 1 : Tout est installé
if [[ "$PACK_OK" == "1" ]] && [[ "$IDRIS2_OK" == "1" ]] && [[ "$LSP_OK" == "1" ]]; then
  show_install_summary
  
  echo -e "${GREEN}══════════════════════════════════════════════════════════════${NC}"
  echo -e "${GREEN}           INSTALLATION COMPLÈTE !${NC}"
  echo -e "${GREEN}══════════════════════════════════════════════════════════════${NC}"
  echo ""
  echo "  Vous pouvez maintenant :"
  echo "    • Compiler et exécuter des projets Idris2 avec pack"
  echo "    • Utiliser VS Code avec l'extension Idris pour un retour en continu"
  echo ""
  
  # Vérifier si on doit recharger le shell
  ORIGINAL_PATH="${PATH#$HOME/.local/bin:}"
  if ! PATH="$ORIGINAL_PATH" command -v pack &>/dev/null; then
    echo -e "${YELLOW}  ⚠ Pour utiliser Idris2, ouvrez un nouveau terminal ou tapez:${NC}"
    echo "      source ~/.bashrc"
    echo ""
  fi

# Cas 2 : pack et idris2 OK, mais pas idris2-lsp
elif [[ "$PACK_OK" == "1" ]] && [[ "$IDRIS2_OK" == "1" ]] && [[ "$LSP_OK" == "0" ]]; then
  show_install_summary
  
  echo -e "${GREEN}══════════════════════════════════════════════════════════════${NC}"
  echo -e "${GREEN}           INSTALLATION FONCTIONNELLE${NC}"
  echo -e "${GREEN}══════════════════════════════════════════════════════════════${NC}"
  echo ""
  echo -e "  ${GREEN}✓ pack et idris2 sont correctement installés !${NC}"
  echo ""
  echo "  Vous pouvez dès maintenant :"
  echo "    • Compiler des projets Idris2 :  pack build <projet>"
  echo "    • Exécuter des projets Idris2 :  pack run <projet>"
  echo "    • Lancer le REPL Idris2       :  pack repl"
  echo ""
  echo -e "${YELLOW}──────────────────────────────────────────────────────────────${NC}"
  echo -e "${YELLOW}  ⚠ idris2-lsp n'est pas installé${NC}"
  echo -e "${YELLOW}──────────────────────────────────────────────────────────────${NC}"
  echo ""
  echo "  Cela n'empêche PAS d'exécuter vos projets Idris2."
  echo ""
  echo "  Cependant, sans idris2-lsp, vous n'aurez pas de retour en continu"
  echo "  dans VS Code (erreurs soulignées, autocomplétion, etc.)."
  echo ""
  
  # Diagnostic du problème idris2-lsp
  if [[ -f "$HOME/.local/bin/idris2-lsp" ]]; then
    echo "  Diagnostic :"
    echo "    → Le fichier existe : $HOME/.local/bin/idris2-lsp"
    if [[ -x "$HOME/.local/bin/idris2-lsp" ]]; then
      echo "    → Le fichier est exécutable"
      echo "    → Essayez de l'exécuter manuellement pour voir l'erreur :"
      echo "        $HOME/.local/bin/idris2-lsp --version"
    else
      echo "    → Le fichier n'est PAS exécutable. Correction..."
      chmod +x "$HOME/.local/bin/idris2-lsp"
      echo "    → Permissions corrigées. Réessayez l'installation."
    fi
  else
    echo "  Diagnostic :"
    echo "    → Le fichier idris2-lsp n'est pas inclus dans l'archive pré-compilée"
    echo ""
    echo "  Pour installer idris2-lsp (compilation ~5-10 minutes) :"
    echo ""
    # Vérifier si git est installé
    if ! command -v git &>/dev/null; then
      echo -e "    ${YELLOW}Installez d'abord git :${NC}"
      echo "       sudo apt install git"
      echo ""
    fi
    echo -e "    ${YELLOW}Puis installez idris2-lsp :${NC}"
    echo "       pack install-app idris2-lsp"
    echo ""
    echo "  Note: Cette commande télécharge et compile idris2-lsp depuis les sources."
    echo "  Cela nécessite git et une connexion internet (~5-10 min)."
  fi
  echo ""
  
  # Vérifier si on doit recharger le shell
  ORIGINAL_PATH="${PATH#$HOME/.local/bin:}"
  if ! PATH="$ORIGINAL_PATH" command -v pack &>/dev/null; then
    echo -e "${YELLOW}  Pour utiliser Idris2, ouvrez un nouveau terminal ou tapez:${NC}"
    echo "      source ~/.bashrc"
    echo ""
  fi

# Cas 3 : pack ou idris2 manquant (problème critique)
else
  echo ""
  echo -e "${RED}══════════════════════════════════════════════════════════════${NC}"
  echo -e "${RED}           ERREUR D'INSTALLATION${NC}"
  echo -e "${RED}══════════════════════════════════════════════════════════════${NC}"
  echo ""
  
  if [[ "$PACK_OK" == "0" ]]; then
    echo -e "  ${RED}✗ pack n'est pas accessible${NC}"
    if [[ -f "$HOME/.local/bin/pack" ]]; then
      echo "    → Le fichier existe : $HOME/.local/bin/pack"
      if [[ ! -x "$HOME/.local/bin/pack" ]]; then
        echo "    → Le fichier n'est pas exécutable. Correction..."
        chmod +x "$HOME/.local/bin/pack"
      fi
      echo "    → Problème probable : PATH non configuré"
    else
      echo "    → Le fichier n'existe pas dans $HOME/.local/bin/"
    fi
    echo ""
  fi
  
  if [[ "$IDRIS2_OK" == "0" ]]; then
    echo -e "  ${RED}✗ idris2 n'est pas accessible${NC}"
    if [[ -f "$HOME/.local/bin/idris2" ]]; then
      echo "    → Le fichier existe : $HOME/.local/bin/idris2"
      if [[ ! -x "$HOME/.local/bin/idris2" ]]; then
        echo "    → Le fichier n'est pas exécutable. Correction..."
        chmod +x "$HOME/.local/bin/idris2"
      fi
      echo "    → Problème probable : PATH non configuré"
    else
      echo "    → Le fichier n'existe pas dans $HOME/.local/bin/"
    fi
    echo ""
  fi
  
  echo "  Solutions possibles :"
  echo "    1. Rechargez votre shell : source ~/.bashrc"
  echo "    2. Vérifiez que ~/.local/bin est dans votre PATH"
  echo "    3. Réinstallez : curl -fsSL https://raw.githubusercontent.com/thanberree/idris2-install/main/install.sh | bash -s -- --force"
  echo ""
  exit 1
fi
