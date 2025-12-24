#!/usr/bin/env bash
set -euo pipefail

# Root / sudo handling
run_as_root() {
  if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
    "$@"
  else
    sudo "$@"
  fi
}

ensure_sudo_or_root() {
  if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
    return 0
  fi
  if ! command -v sudo &>/dev/null; then
    error "Cette installation nécessite 'sudo' (ou être root). Installez sudo puis relancez : Debian/Ubuntu: 'apt-get install -y sudo' ; Fedora: 'dnf install -y sudo' ; Arch: 'pacman -Sy --noconfirm sudo'."
  fi
  # Try to validate sudo early to fail fast with a clear message
  if ! sudo -n true 2>/dev/null; then
    info "Une élévation de privilèges (sudo) est nécessaire. Saisissez votre mot de passe si demandé."
    sudo true || error "Échec de l'authentification sudo. Relancez avec: curl -fsSL ... | sudo bash"
  fi
}

# Version de l'installeur
INSTALLER_VERSION="1.6.4"

# Configuration
COLLECTION="nightly-250828"
OS_TYPE=$(uname -s)
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

read_os_release_field() {
  local key="$1"
  [[ -f /etc/os-release ]] || return 0
  # shellcheck disable=SC2002
  cat /etc/os-release 2>/dev/null | grep -E "^${key}=" | head -1 | cut -d= -f2- | tr -d '"'
}

print_distro_context() {
  local pretty id version_id codename arch
  pretty="$(read_os_release_field PRETTY_NAME)"
  id="$(read_os_release_field ID)"
  version_id="$(read_os_release_field VERSION_ID)"
  codename="$(read_os_release_field VERSION_CODENAME)"
  arch="$(uname -m 2>/dev/null || true)"

  echo -e "${YELLOW}[Contexte]${NC} OS=${OS_TYPE} ARCH=${arch}"
  if [[ -n "$pretty" ]]; then
    echo -e "${YELLOW}[Contexte]${NC} Distro=${pretty} (ID=${id:-?}, VERSION_ID=${version_id:-?}, CODENAME=${codename:-?})"
  fi
  if [[ -n "${ARCHIVE_URL:-}" ]]; then
    echo -e "${YELLOW}[Contexte]${NC} Archive=${ARCHIVE_URL}"
  fi
}

error() {
  echo -e "${RED}[ERREUR]${NC} $*" >&2
  ISTIC_STATUS="failed"
  if declare -F write_install_info_files >/dev/null 2>&1; then
    write_install_info_files >&2 || true
  fi
  print_distro_context >&2 || true
  exit 1
}

ASSUME_YES=0
ALLOW_FALLBACK=0

# Debug / post-install diagnostics
DEBUG_STATE_DIR="$HOME/.local/state/istic-idris2-install"
DEBUG_INFO_ENV="$DEBUG_STATE_DIR/install-info.env"
DEBUG_INFO_TXT="$DEBUG_STATE_DIR/install-info.txt"
DEBUG_INFO_CMD="$HOME/.local/bin/idris2-install-info"
INSTALL_TIMESTAMP_UTC="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

write_install_info_files() {
  mkdir -p "$DEBUG_STATE_DIR" "$HOME/.local/bin" 2>/dev/null || true

  emit_env_kv() {
    local k="$1"
    local v="${2:-}"
    local q
    printf -v q '%q' "$v"
    echo "$k=$q"
  }

  local uname_m
  uname_m="$(uname -m 2>/dev/null || echo "unknown")"

  local os_pretty os_id os_version_id os_codename
  os_pretty="$(read_os_release_field PRETTY_NAME)"
  os_id="$(read_os_release_field ID)"
  os_version_id="$(read_os_release_field VERSION_ID)"
  os_codename="$(read_os_release_field VERSION_CODENAME)"

  {
    emit_env_kv ISTIC_INSTALL_TIMESTAMP_UTC "${INSTALL_TIMESTAMP_UTC}"
    emit_env_kv ISTIC_INSTALLER_VERSION "${INSTALLER_VERSION}"
    emit_env_kv ISTIC_COLLECTION "${COLLECTION}"
    emit_env_kv ISTIC_OS_TYPE "${OS_TYPE}"
    emit_env_kv ISTIC_UNAME_M "${uname_m}"
    emit_env_kv ISTIC_OS_PRETTY_NAME "${os_pretty}"
    emit_env_kv ISTIC_OS_ID "${os_id}"
    emit_env_kv ISTIC_OS_VERSION_ID "${os_version_id}"
    emit_env_kv ISTIC_OS_VERSION_CODENAME "${os_codename}"
    emit_env_kv ISTIC_ARCHIVE_URL "${ARCHIVE_URL:-}"
    emit_env_kv ISTIC_ARCHIVE_BASENAME "${ARCHIVE_BASENAME:-}"
    emit_env_kv ISTIC_ARCHIVE_SIZE_BYTES "${ARCHIVE_SIZE:-}"
    emit_env_kv ISTIC_ARCHIVE_SHA256 "${ARCHIVE_SHA256:-}"
    emit_env_kv ISTIC_PACK_INFO_FIRSTLINE "${PACK_INFO_FIRSTLINE:-}"
    emit_env_kv ISTIC_IDRIS2_VERSION_LINE "${IDRIS2_VERSION_LINE:-}"
    emit_env_kv ISTIC_IDRIS2_LSP_VERSION_LINE "${IDRIS2_LSP_VERSION_LINE:-}"
    emit_env_kv ISTIC_STATUS "${ISTIC_STATUS:-unknown}"
  } >"$DEBUG_INFO_ENV"

  cat >"$DEBUG_INFO_TXT" <<EOF
ISTIC Idris2 installer debug info

- Timestamp (UTC): ${INSTALL_TIMESTAMP_UTC}
- Installer version: ${INSTALLER_VERSION}
- Collection: ${COLLECTION}
- OS: ${OS_TYPE}
- Arch: ${uname_m}

- Distro: ${os_pretty} (ID=${os_id}, VERSION_ID=${os_version_id}, CODENAME=${os_codename})

- Archive URL: ${ARCHIVE_URL:-}
- Archive file: ${ARCHIVE_BASENAME:-}
- Archive size (bytes): ${ARCHIVE_SIZE:-}
- Archive sha256: ${ARCHIVE_SHA256:-}

- pack info: ${PACK_INFO_FIRSTLINE:-}
- idris2 --version: ${IDRIS2_VERSION_LINE:-}
- idris2-lsp --version: ${IDRIS2_LSP_VERSION_LINE:-}

- Status: ${ISTIC_STATUS:-unknown}
EOF

  # Install a helper command for students/scripts.
  cat >"$DEBUG_INFO_CMD" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

STATE_DIR="$HOME/.local/state/istic-idris2-install"
ENV_FILE="$STATE_DIR/install-info.env"
TXT_FILE="$STATE_DIR/install-info.txt"

if [[ -f "$ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$ENV_FILE"

  echo "ISTIC Idris2 installer debug info"
  echo "- Timestamp (UTC): ${ISTIC_INSTALL_TIMESTAMP_UTC:-}"
  echo "- Installer version: ${ISTIC_INSTALLER_VERSION:-}"
  echo "- Collection: ${ISTIC_COLLECTION:-}"
  echo "- OS: ${ISTIC_OS_TYPE:-}"
  echo "- Arch: ${ISTIC_UNAME_M:-}"
  echo "- Distro: ${ISTIC_OS_PRETTY_NAME:-} (ID=${ISTIC_OS_ID:-}, VERSION_ID=${ISTIC_OS_VERSION_ID:-}, CODENAME=${ISTIC_OS_VERSION_CODENAME:-})"
  echo "- Archive: ${ISTIC_ARCHIVE_BASENAME:-}"
  echo "- Archive URL: ${ISTIC_ARCHIVE_URL:-}"
  echo "- Archive size (bytes): ${ISTIC_ARCHIVE_SIZE_BYTES:-}"
  echo "- Archive sha256: ${ISTIC_ARCHIVE_SHA256:-}"
  echo "- pack info: ${ISTIC_PACK_INFO_FIRSTLINE:-}"
  echo "- idris2 --version: ${ISTIC_IDRIS2_VERSION_LINE:-}"
  echo "- idris2-lsp --version: ${ISTIC_IDRIS2_LSP_VERSION_LINE:-}"
  echo "- Status: ${ISTIC_STATUS:-unknown}"
  echo ""
  echo "Files:"
  echo "- $ENV_FILE"
  echo "- $TXT_FILE"
  exit 0
fi

if [[ -f "$TXT_FILE" ]]; then
  cat "$TXT_FILE"
  exit 0
fi

echo "No install info found in $STATE_DIR" >&2
exit 1
EOF

  chmod +x "$DEBUG_INFO_CMD" 2>/dev/null || true
}

confirm_or_abort() {
  local prompt="$1"
  local noninteractive_hint="$2"
  local reply=""

  if [[ "$ASSUME_YES" == "1" ]]; then
    return 0
  fi

  # Allow confirmation even when script is piped (curl | bash) by reading /dev/tty.
  if [[ -t 0 ]]; then
    read -r -p "$prompt [o/N] " reply
  elif [[ -r /dev/tty ]]; then
    read -r -p "$prompt [o/N] " reply </dev/tty
  else
    error "$noninteractive_hint"
  fi

  if [[ ! "$reply" =~ ^[OoYy]$ ]]; then
    error "Annulé par l'utilisateur."
  fi
}

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
    --yes|-y) ASSUME_YES=1 ;;
    --allow-fallback) ALLOW_FALLBACK=1 ;;
    --version|-v)
      echo "install.sh version $INSTALLER_VERSION"
      exit 0
      ;;
    --help|-h)
      echo "Usage: $0 [OPTIONS]"
      echo ""
      echo "Options:"
      echo "  --force, -f    Réinstaller même si une installation existe"
      echo "  --yes, -y      Répondre 'oui' aux confirmations (mode scripté)"
      echo "  --allow-fallback  Autoriser l'usage d'une archive de repli (si proposé)"
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
    # Debian testing/unstable often reports codenames without a matching archive.
    # We keep the codename as-is here; detect_archive_url will probe/fallback.
    trixie|testing|unstable|sid) echo "$codename" ;;
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
  
  local os_type arch codename distro_id version_id pretty id_like
  os_type=$(uname -s)
  arch=$(uname -m)
  
  case "$os_type" in
    Linux)
      # Détecter l'ID de la distribution
      if [[ -f /etc/os-release ]]; then
        distro_id=$(grep "^ID=" /etc/os-release | cut -d= -f2 | tr -d '"')
        version_id=$(read_os_release_field VERSION_ID)
        pretty=$(read_os_release_field PRETTY_NAME)
        id_like=$(read_os_release_field ID_LIKE)
      fi
      
      # Gérer Fedora/Arch différemment
      case "$distro_id" in
        fedora)
          # Fedora archives are sensitive to the Chez Scheme version shipped by Fedora.
          # We only support fast *prebuilt* installs here.
          # Currently supported: Fedora 40 (baseline archive) and Fedora 43 (fedora43 archive).
          local fedora_ver="${version_id:-}"
          fedora_ver=${fedora_ver%%.*}

          if [[ -z "$fedora_ver" ]]; then
            error "Fedora détectée mais VERSION_ID est introuvable. Installation binaire impossible."
          fi

          if [[ "$fedora_ver" == "40" ]]; then
            # Baseline Fedora archive (built on Fedora 40)
            echo "${RELEASE_BASE_URL}/idris2-pack-${COLLECTION}-fedora-full.tar.gz"
            return
          fi

          if [[ "$fedora_ver" == "43" ]]; then
            local candidate="${RELEASE_BASE_URL}/idris2-pack-${COLLECTION}-fedora43-full.tar.gz"
            # Early check to give a clearer error than a later curl/tar failure.
            if ! curl -fsI "$candidate" >/dev/null 2>&1; then
              error "Fedora 43 détectée mais l'archive binaire Fedora 43 n'est pas encore disponible dans la release."
            fi
            echo "$candidate"
            return
          fi

          error "Fedora ${fedora_ver} n'est pas supportée en binaire pour le moment (support: Fedora 40 et Fedora 43)."
          ;;
        arch|manjaro)
          warn "Arch/Manjaro détecté. Arch est une distribution rolling : une archive pré-compilée peut devenir incompatible après une mise à jour (Chez Scheme / glibc)."
          confirm_or_abort \
            "Continuer quand même avec l'archive 'arch' ?" \
            "Arch détecté mais confirmation impossible (pas de TTY). Relancez avec: curl ... | bash -s -- --yes"
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

      # Prefer an exact match when available.
      local candidate="${RELEASE_BASE_URL}/idris2-pack-${COLLECTION}-${codename}-full.tar.gz"
      if curl -fsI "$candidate" >/dev/null 2>&1; then
        # Derived distros (Mint/Pop/etc.) can report Ubuntu codenames; warn and ask confirmation.
        if [[ -n "${distro_id:-}" ]] && [[ "$distro_id" != "ubuntu" ]] && [[ "$distro_id" != "debian" ]] && [[ "$distro_id" != "fedora" ]] && [[ "$distro_id" != "arch" ]] && [[ "$distro_id" != "manjaro" ]]; then
          warn "Distribution dérivée détectée: ${pretty:-$distro_id}. L'archive utilisée correspond à Ubuntu/Debian ($codename)."
          confirm_or_abort \
            "Cette combinaison peut être incompatible. Continuer ?" \
            "Confirmation impossible (pas de TTY). Relancez avec: curl ... | bash -s -- --yes"
        fi
        echo "$candidate"
        return
      fi

      # Debian: fall back to bookworm if the codename doesn't have an archive.
      if [[ "$distro_id" == "debian" ]]; then
        warn "Debian détecté (codename: '${codename}'), mais aucune archive dédiée n'existe."
        warn "On peut tenter l'archive Debian 12 (bookworm), mais cela peut ne pas fonctionner."
        if [[ "$ALLOW_FALLBACK" != "1" ]]; then
          confirm_or_abort \
            "Utiliser l'archive 'bookworm' en repli ?" \
            "Repli proposé (bookworm) mais confirmation impossible (pas de TTY). Relancez avec: curl ... | bash -s -- --allow-fallback --yes"
        fi
        echo "${RELEASE_BASE_URL}/idris2-pack-${COLLECTION}-bookworm-full.tar.gz"
        return
      fi

      error "Aucune archive pré-compilée trouvée pour '${codename}'. Utilisez une distro supportée ou définissez ARCHIVE_URL manuellement."
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

ARCHIVE_BASENAME="$(basename "$ARCHIVE_URL")"
ISTIC_STATUS="started"
write_install_info_files || true

# Vérifier l'espace disque disponible
check_disk_space() {
  local available_mb
  # Avoid depending on awk here: on Fedora minimal/WSL it may not be installed yet.
  # df output: Filesystem 1M-blocks Used Available Use% Mounted on
  # We parse the 2nd line and take the 4th column (Available).
  local _fs _blocks _used _avail _usep _mnt
  read -r _fs _blocks _used _avail _usep _mnt < <(df -m "$HOME" | sed -n '2p')
  available_mb="${_avail:-0}"
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

# Détection du gestionnaire de paquets
PKG_MANAGER=""
if [[ "$OS_TYPE" == "Darwin" ]]; then
  # macOS - utiliser Homebrew
  if ! command -v brew &>/dev/null; then
    error "Homebrew est requis sur macOS. Installez-le depuis https://brew.sh"
  fi
  PKG_MANAGER="brew"
elif command -v apt-get &>/dev/null; then
  PKG_MANAGER="apt"
elif command -v dnf &>/dev/null; then
  PKG_MANAGER="dnf"
elif command -v pacman &>/dev/null; then
  PKG_MANAGER="pacman"
fi

# Collecter les paquets à installer
PACKAGES_TO_INSTALL=""
PKG_UPDATED=0

need_pkg_update() {
  if [[ "$PKG_UPDATED" == "0" ]]; then
    case "$PKG_MANAGER" in
      apt)
        info "Mise à jour des sources apt..."
        sudo apt-get update
        ;;
      dnf)
        # dnf n'a pas besoin de update explicite avant install
        ;;
      pacman)
        info "Mise à jour des sources pacman..."
        sudo pacman -Sy --noconfirm
        ;;
      brew)
        info "Mise à jour de Homebrew..."
        brew update
        ;;
    esac
    PKG_UPDATED=1
  fi
}

# Fonction pour mapper les noms de paquets selon le gestionnaire
map_package_name() {
  local pkg="$1"
  case "$PKG_MANAGER" in
    apt)
      echo "$pkg"
      ;;
    dnf)
      case "$pkg" in
        chezscheme) echo "chez-scheme" ;;
        gawk) echo "gawk" ;;
        *) echo "$pkg" ;;
      esac
      ;;
    pacman)
      case "$pkg" in
        chezscheme) echo "chez-scheme" ;;
        coreutils) echo "coreutils" ;;
        *) echo "$pkg" ;;
      esac
      ;;
    brew)
      case "$pkg" in
        chezscheme) echo "chezscheme" ;;
        rlwrap) echo "rlwrap" ;;
        coreutils) echo "coreutils" ;;
        unzip) echo "unzip" ;;
        git) echo "git" ;;
        *) echo "$pkg" ;;
      esac
      ;;
    *)
      echo "$pkg"
      ;;
  esac
}

# Vérifier Chez Scheme
# Note: sur Arch, chez-scheme n'est pas dans les dépôts officiels mais dans AUR
# Note: sur macOS, Homebrew installe 'chez' pas 'chezscheme'
if ! command -v chezscheme &>/dev/null && ! command -v chez &>/dev/null && ! command -v scheme &>/dev/null; then
  if [[ "$PKG_MANAGER" == "brew" ]]; then
    # Sur macOS, installer via Homebrew
    info "Installation de Chez Scheme via Homebrew..."
    brew install chezscheme
  elif [[ "$PKG_MANAGER" == "pacman" ]]; then
    # Sur Arch, installer depuis AUR
    info "Chez Scheme n'est pas dans les dépôts officiels Arch. Installation depuis AUR..."
    if ! command -v yay &>/dev/null && ! command -v paru &>/dev/null; then
      # Installer yay si aucun AUR helper n'est présent
      info "Installation de yay (AUR helper)..."
      sudo pacman -S --noconfirm --needed base-devel git
      TEMP_YAY=$(mktemp -d)
      git clone https://aur.archlinux.org/yay.git "$TEMP_YAY"
      (cd "$TEMP_YAY" && makepkg -si --noconfirm)
      rm -rf "$TEMP_YAY"
    fi
    # Utiliser yay ou paru pour installer chez-scheme
    if command -v yay &>/dev/null; then
      yay -S --noconfirm --needed --answerdiff None --answerclean None chez-scheme
    elif command -v paru &>/dev/null; then
      paru -S --noconfirm --needed --skipreview --removemake chez-scheme
    fi
  else
    PACKAGES_TO_INSTALL="$PACKAGES_TO_INSTALL $(map_package_name chezscheme)"
  fi
fi

# Vérifier rlwrap
if ! command -v rlwrap &>/dev/null; then
  PACKAGES_TO_INSTALL="$PACKAGES_TO_INSTALL $(map_package_name rlwrap)"
fi

# Vérifier outils nécessaires
command -v timeout &>/dev/null || PACKAGES_TO_INSTALL="$PACKAGES_TO_INSTALL $(map_package_name coreutils)"
command -v unzip &>/dev/null || PACKAGES_TO_INSTALL="$PACKAGES_TO_INSTALL $(map_package_name unzip)"
command -v git &>/dev/null || PACKAGES_TO_INSTALL="$PACKAGES_TO_INSTALL $(map_package_name git)"
command -v awk &>/dev/null || PACKAGES_TO_INSTALL="$PACKAGES_TO_INSTALL $(map_package_name gawk)"

# Installer tous les paquets en une seule fois
if [[ -n "$PACKAGES_TO_INSTALL" ]]; then
  PACKAGES_TO_INSTALL=$(echo "$PACKAGES_TO_INSTALL" | xargs)  # trim whitespace
  ensure_sudo_or_root
  case "$PKG_MANAGER" in
    apt)
      need_pkg_update
      info "Installation des dépendances (apt): $PACKAGES_TO_INSTALL"
      run_as_root apt-get install -y $PACKAGES_TO_INSTALL
      ;;
    dnf)
      info "Installation des dépendances (dnf): $PACKAGES_TO_INSTALL"
      run_as_root dnf install -y $PACKAGES_TO_INSTALL
      ;;
    pacman)
      need_pkg_update
      info "Installation des dépendances (pacman): $PACKAGES_TO_INSTALL"
      run_as_root pacman -S --noconfirm $PACKAGES_TO_INSTALL
      ;;
    brew)
      info "Installation des dépendances (brew): $PACKAGES_TO_INSTALL"
      brew install $PACKAGES_TO_INSTALL
      ;;
    *)
      error "Gestionnaire de paquets non supporté. Installez manuellement: $PACKAGES_TO_INSTALL"
      ;;
  esac
fi

# Vérifier que chezscheme est accessible
# Sur Linux: créer un symlink dans /usr/local/bin si nécessaire
# Sur macOS: créer un symlink dans /usr/local/bin (pas /usr/bin qui est protégé par SIP)
ensure_chezscheme_accessible() {
  # Trouver le binaire chez scheme
  local chez_bin=""
  if command -v chezscheme &>/dev/null; then
    chez_bin=$(command -v chezscheme)
  elif command -v chez &>/dev/null; then
    chez_bin=$(command -v chez)
  elif command -v scheme &>/dev/null; then
    chez_bin=$(command -v scheme)
  elif [[ "$OS_TYPE" == "Darwin" ]]; then
    # Sur macOS, Homebrew peut installer dans /opt/homebrew (ARM) ou /usr/local (Intel)
    local brew_prefix
    brew_prefix=$(brew --prefix 2>/dev/null || echo "/usr/local")
    if [[ -x "$brew_prefix/bin/chez" ]]; then
      chez_bin="$brew_prefix/bin/chez"
    elif [[ -x "$brew_prefix/bin/chezscheme" ]]; then
      chez_bin="$brew_prefix/bin/chezscheme"
    fi
  fi
  
  if [[ -z "$chez_bin" ]]; then
    error "Chez Scheme introuvable. Vérifiez: which scheme chez chezscheme"
  fi
  
  # Créer les symlinks si nécessaire
  if [[ "$OS_TYPE" == "Darwin" ]]; then
    # Sur macOS, utiliser /usr/local/bin (pas /usr/bin - protégé par SIP)
    if [[ ! -x /usr/local/bin/chezscheme ]]; then
      info "Création du lien /usr/local/bin/chezscheme -> $chez_bin"
      ensure_sudo_or_root
      run_as_root mkdir -p /usr/local/bin
      run_as_root ln -sf "$chez_bin" /usr/local/bin/chezscheme
    fi
    if [[ ! -x /usr/local/bin/chez ]] && [[ "$chez_bin" != *"chezscheme" ]]; then
      ensure_sudo_or_root
      run_as_root ln -sf "$chez_bin" /usr/local/bin/chez
    fi
  else
    # Sur Linux, utiliser /usr/bin si possible, sinon /usr/local/bin
    if [[ ! -x /usr/bin/chezscheme ]]; then
      if [[ -x /usr/bin/scheme ]]; then
        info "Création du lien /usr/bin/chezscheme -> /usr/bin/scheme"
        ensure_sudo_or_root
        run_as_root ln -sf /usr/bin/scheme /usr/bin/chezscheme
      elif [[ -x /usr/bin/chez ]]; then
        info "Création du lien /usr/bin/chezscheme -> /usr/bin/chez"
        ensure_sudo_or_root
        run_as_root ln -sf /usr/bin/chez /usr/bin/chezscheme
      else
        info "Création du lien /usr/bin/chezscheme -> $chez_bin"
        ensure_sudo_or_root
        run_as_root ln -sf "$chez_bin" /usr/bin/chezscheme
      fi
    fi
  fi
}

ensure_chezscheme_accessible

# Téléchargement et installation
info "Téléchargement des binaires Idris2 + pack..."
mkdir -p "$HOME/.local/bin" "$HOME/.local/state" "$HOME/.config" "$HOME/.cache"

TEMP_ARCHIVE=$(mktemp)
if ! curl -fSL "$ARCHIVE_URL" -o "$TEMP_ARCHIVE"; then
  ISTIC_STATUS="failed"
  write_install_info_files || true
  error "Échec du téléchargement. Vérifiez votre connexion internet."
fi

# Vérifier que l'archive n'est pas vide ou trop petite
ARCHIVE_SIZE=$(stat -c%s "$TEMP_ARCHIVE" 2>/dev/null || stat -f%z "$TEMP_ARCHIVE" 2>/dev/null || echo "0")
if [[ "$ARCHIVE_SIZE" -lt 1000000 ]]; then
  ISTIC_STATUS="failed"
  write_install_info_files || true
  error "Archive téléchargée invalide (taille: $ARCHIVE_SIZE octets)"
fi

if command -v sha256sum &>/dev/null; then
  ARCHIVE_SHA256="$(sha256sum "$TEMP_ARCHIVE" | awk '{print $1}')"
elif command -v shasum &>/dev/null; then
  ARCHIVE_SHA256="$(shasum -a 256 "$TEMP_ARCHIVE" | awk '{print $1}')"
else
  ARCHIVE_SHA256=""
fi

write_install_info_files || true

info "Extraction de l'archive..."
if ! tar xzf "$TEMP_ARCHIVE" -C "$HOME"; then
  ISTIC_STATUS="failed"
  write_install_info_files || true
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

# Fonction sed compatible Linux et macOS
portable_sed_inplace() {
  local file="$1"
  local pattern="$2"
  if [[ "$OS_TYPE" == "Darwin" ]]; then
    sed -i '' "$pattern" "$file"
  else
    sed -i "$pattern" "$file"
  fi
}

for script in "$HOME/.local/bin/pack" "$HOME/.local/bin/idris2" "$HOME/.local/bin/idris2-lsp"; do
  if [[ -f "$script" ]]; then
    # Remplacer tout chemin /home/*/. ou /Users/*/.local par $HOME/.local
    portable_sed_inplace "$script" "s|/home/[^/]*/\\.local/|$HOME/.local/|g"
    portable_sed_inplace "$script" "s|/Users/[^/]*/\\.local/|$HOME/.local/|g"
  fi
done

# Corriger aussi les chemins codés en dur dans les fichiers de runtime pack/Idris2
# (certains fichiers générés par Chez/Idris2 contiennent "/home/builder/..." qui casse
# la résolution des bibliothèques après extraction dans un autre HOME).
fix_builder_paths() {
  local bases=(
    "$HOME/.local/state/pack"
    "$HOME/.config/pack"
    "$HOME/.cache/pack"
    "$HOME/.local/bin/idris2_app"
    "$HOME/.local/bin/idris2-lsp_app"
  )

  local base
  for base in "${bases[@]}"; do
    [[ -d "$base" ]] || continue

    # Only edit text files where grep can see the pattern
    while IFS= read -r file; do
      # Skip shared objects even if grep misclassifies them
      [[ "$file" =~ \.so$ ]] && continue
      portable_sed_inplace "$file" "s|/home/builder|$HOME|g"
      portable_sed_inplace "$file" "s|/Users/builder|$HOME|g"
    done < <(grep -RIl --exclude='*.so' '/home/builder\|/Users/builder' "$base" 2>/dev/null || true)
  done
}

fix_builder_paths

# Corriger aussi les chemins dans pack_app si présent (seulement les scripts texte)
if [[ -d "$HOME/.local/bin/pack_app" ]]; then
  for script in "$HOME/.local/bin/pack_app/"*; do
    # Skip binary files (.so), only process text files
    if [[ -f "$script" ]] && [[ ! "$script" =~ \.so$ ]]; then
      portable_sed_inplace "$script" "s|/home/[^/]*/\\.local/|$HOME/.local/|g"
      portable_sed_inplace "$script" "s|/Users/[^/]*/\\.local/|$HOME/.local/|g"
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

# Configure SCHEMEHEAPDIRS for Chez Scheme boot files (needed on Fedora/Arch)
# The pre-built binaries expect boot files in specific locations
configure_scheme_paths() {
  local chez_lib_dirs=""
  
  # Find directories containing scheme.boot (the actual boot file location)
  # On Fedora, boot files are in /usr/lib64/csv<version>/ta6le/ or similar arch subdirs
  local boot_file
  boot_file=$(find /usr/lib64 /usr/lib /usr/local/lib /opt/homebrew/lib -name 'scheme.boot' 2>/dev/null | head -1 || true)
  
  if [[ -n "$boot_file" ]]; then
    # Get the directory containing scheme.boot
    local boot_dir
    boot_dir=$(dirname "$boot_file")
    chez_lib_dirs="$boot_dir"
  else
    # Fallback: search for csv* directories and their subdirs
    for dir in /usr/lib64/csv*/ta6le /usr/lib/csv*/ta6le /usr/lib64/csv* /usr/lib/csv* /usr/local/lib/csv*; do
      if [[ -d "$dir" ]]; then
        chez_lib_dirs="${chez_lib_dirs:+$chez_lib_dirs:}$dir"
      fi
    done
    
    # Also check standard boot locations
    for dir in /usr/lib/chez-scheme /usr/lib64/chez-scheme /usr/share/chez-scheme; do
      if [[ -d "$dir" ]]; then
        chez_lib_dirs="${chez_lib_dirs:+$chez_lib_dirs:}$dir"
      fi
    done
  fi
  
  if [[ -n "$chez_lib_dirs" ]]; then
    # Create chezscheme.boot symlink if only scheme.boot exists
    # This is needed because pre-built binaries may expect chezscheme.boot
    local first_dir="${chez_lib_dirs%%:*}"
    if [[ -f "$first_dir/scheme.boot" ]] && [[ ! -f "$first_dir/chezscheme.boot" ]]; then
      info "Création du lien chezscheme.boot -> scheme.boot"
      sudo ln -sf "$first_dir/scheme.boot" "$first_dir/chezscheme.boot" 2>/dev/null || true
    fi
    
    # Add SCHEMEHEAPDIRS to bashrc if not present
    if ! grep -q 'SCHEMEHEAPDIRS' "$HOME/.bashrc" 2>/dev/null; then
      echo "" >> "$HOME/.bashrc"
      echo "# Chez Scheme boot files location (for Idris2)" >> "$HOME/.bashrc"
      echo "export SCHEMEHEAPDIRS=\"$chez_lib_dirs\"" >> "$HOME/.bashrc"
      info "SCHEMEHEAPDIRS configuré dans ~/.bashrc"
    fi
    
    if [[ -f "$HOME/.zshrc" ]] && ! grep -q 'SCHEMEHEAPDIRS' "$HOME/.zshrc" 2>/dev/null; then
      echo "" >> "$HOME/.zshrc"
      echo "# Chez Scheme boot files location (for Idris2)" >> "$HOME/.zshrc"
      echo "export SCHEMEHEAPDIRS=\"$chez_lib_dirs\"" >> "$HOME/.zshrc"
    fi
    
    # Export for current session
    export SCHEMEHEAPDIRS="$chez_lib_dirs"
  fi
}

# On Fedora/Arch, pre-built binaries need SCHEMEHEAPDIRS
if [[ "$PKG_MANAGER" == "dnf" ]] || [[ "$PKG_MANAGER" == "pacman" ]]; then
  configure_scheme_paths
fi

# Vérification finale détaillée
echo ""
info "Vérification de l'installation..."

# Vérifier les commandes essentielles (pack et idris2)
PACK_OK=0
IDRIS2_OK=0
LSP_OK=0

PACK_INFO_OUTPUT=""
PACK_INFO_FIRSTLINE=""
IDRIS2_VERSION_LINE=""
IDRIS2_LSP_VERSION_LINE=""

if command -v pack &>/dev/null; then
  set +e
  PACK_INFO_OUTPUT=$(pack info 2>&1)
  pack_rc=$?
  set -e
  PACK_INFO_FIRSTLINE=$(echo "$PACK_INFO_OUTPUT" | head -1 | tr -d '\r')
  if [[ $pack_rc -eq 0 ]]; then
    PACK_OK=1
  else
    PACK_OK=0
  fi
fi

if command -v idris2 &>/dev/null; then
  IDRIS2_OK=1
  IDRIS2_VERSION_LINE=$(idris2 --version 2>/dev/null | head -1 | tr -d '\r' || true)
fi

if command -v idris2-lsp &>/dev/null; then
  LSP_OK=1
  IDRIS2_LSP_VERSION_LINE=$(idris2-lsp --version 2>/dev/null | head -1 | tr -d '\r' || true)
fi

# Persist debug info now that we know what works.
if [[ "$PACK_OK" == "1" ]] && [[ "$IDRIS2_OK" == "1" ]] && [[ "$LSP_OK" == "1" ]]; then
  ISTIC_STATUS="ok"
elif [[ "$PACK_OK" == "1" ]] && [[ "$IDRIS2_OK" == "1" ]]; then
  ISTIC_STATUS="partial"
else
  ISTIC_STATUS="failed"
fi
write_install_info_files || true

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
    pack_collection=$(echo "$PACK_INFO_OUTPUT" | grep -i "collection" | head -1 || echo "$COLLECTION")
    echo -e "  ${GREEN}✓${NC} pack           : installé"
    echo "                    Chemin  : $HOME/.local/bin/pack"
    echo "                    $pack_collection"
  else
    if command -v pack &>/dev/null; then
      echo -e "  ${RED}✗${NC} pack           : installé mais NON FONCTIONNEL"
      echo "                    Chemin  : $HOME/.local/bin/pack"
      echo "                    Erreur  : $(echo "$PACK_INFO_OUTPUT" | head -1)"
    else
      echo -e "  ${RED}✗${NC} pack           : NON INSTALLÉ"
    fi
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

  echo -e "${GREEN}──────────────────────────────────────────────────────────────${NC}"
  echo "  Débogage :"
  echo ""
  echo "  Pour afficher les infos d'installation (date, version, archive, etc.) :"
  echo "    → idris2-install-info"
  echo ""
  echo "  Fichier machine-friendly (pour scripts) :"
  echo "    → $DEBUG_INFO_ENV"
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
  
  # Diagnostic pack
  pack_error_output="$PACK_INFO_OUTPUT"
  if [[ -z "$pack_error_output" ]]; then
    pack_error_output=$(pack info 2>&1 || true)
  fi

  # Chez Scheme FASL mismatch (common on Fedora when using an archive built on another Fedora release)
  if echo "$pack_error_output" | grep -q "incompatible fasl-object version"; then
    echo -e "  ${RED}✗ Erreur Chez Scheme : incompatibilité de version (FASL)${NC}"
    echo ""
    echo "  Votre Chez Scheme est d'une version différente de celle utilisée pour compiler pack."
    echo "  Sur Fedora, cela arrive quand on installe une archive construite sur une autre version de Fedora."
    echo ""
    echo "  Solution recommandée : relancer l'installation (le script choisit maintenant une archive Fedora spécifique à VERSION_ID quand elle existe)."
    echo "    curl -fsSL https://raw.githubusercontent.com/thanberree/idris2-install/main/install.sh | bash -s -- --force"
    echo ""
    echo "  Détail : $pack_error_output" 
    print_distro_context || true
    exit 1
  fi

  # Check for Chez Scheme boot file issue
  if echo "$pack_error_output" | grep -q "chezscheme.boot\|petite.boot\|cannot find compatible"; then
    echo -e "  ${RED}✗ Erreur Chez Scheme : fichiers boot introuvables${NC}"
    echo ""
    echo "  Les binaires pré-compilés ne trouvent pas les fichiers boot de Chez Scheme."
    echo "  Ce problème survient quand l'archive a été compilée sur une autre distribution."
    echo ""
    echo "  Solutions :"
    echo ""
    echo "  1. Définir SCHEMEHEAPDIRS et recharger le shell :"
    echo "     Ajoutez à ~/.bashrc :"
    
    # Find chez scheme library directories
    chez_dirs=""
    for dir in /usr/lib64/csv* /usr/lib/csv* /usr/lib/chez-scheme /usr/lib64/chez-scheme; do
      if [[ -d "$dir" ]]; then
        chez_dirs="${chez_dirs:+$chez_dirs:}$dir"
      fi
    done
    
    if [[ -n "$chez_dirs" ]]; then
      echo "       export SCHEMEHEAPDIRS=\"$chez_dirs\""
    else
      echo "       export SCHEMEHEAPDIRS=\"/usr/lib64/csv9.5:/usr/lib/csv9.5\""
    fi
    echo "     Puis : source ~/.bashrc"
    echo ""
    print_distro_context || true
    exit 1
  fi
  
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
  print_distro_context || true
  exit 1
fi
