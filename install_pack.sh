#!/usr/bin/env bash
# ==============================================================================
# ISTIC Idris2 + pack FROM-SOURCE Installer
# ==============================================================================
#
# PURPOSE:
#   This script installs Idris2 + pack + idris2-lsp by building from source.
#   Use this when pre-built archives are not available for your platform.
#
#   For most users, the pre-built installer is faster (~2 min vs 30-60 min):
#     curl -fsSL https://raw.githubusercontent.com/thanberree/idris2-install/main/install.sh | bash
#
# WHAT IT DOES:
#   1. Installs system prerequisites (apt/dnf/pacman)
#   2. Runs the official pack bootstrap (compiles Idris2 + pack from source)
#   3. Switches to the ISTIC package collection (nightly-250828)
#   4. Installs idris2-lsp (and required TP libraries)
#   5. Configures PATH and HEDGEHOG_COLOR in ~/.bashrc
#
# RESUME CAPABILITY:
#   The script can be restarted if interrupted - it will skip completed stages.
#   Progress is tracked in ~/.local/state/pack/.istic_install.log
#
# USAGE:
#   ./install_pack.sh
#
# ENVIRONMENT VARIABLES:
#   SCHEME                   - Chez Scheme executable (default: auto-detect)
#   ISTIC_PACKAGE_COLLECTION - Target collection (default: nightly-250828)
#
# ==============================================================================
set -euo pipefail

# ==============================================================================
# Configuration
# ==============================================================================
ISTIC_PACKAGE_COLLECTION="${ISTIC_PACKAGE_COLLECTION:-nightly-250828}"
BIN_DIR="$HOME/.local/bin"
STATE_DIR="$HOME/.local/state/pack"
INSTALL_LOG="$STATE_DIR/.istic_install.log"
BASH_RC="$HOME/.bashrc"
START_TIME=$(date)

# Stage descriptions (for progress display)
STAGES=(
  "Installation des prérequis système"
  "Bootstrap de pack + Idris2 (compilation ~20-40 min)"
  "Switch vers la collection $ISTIC_PACKAGE_COLLECTION"
  "Installation de idris2-lsp (compilation ~10-20 min)"
  "Configuration de HEDGEHOG_COLOR"
  "Configuration du PATH"
  "Vérification finale"
)
TOTAL_STAGES=${#STAGES[@]}

# ==============================================================================
# Colors
# ==============================================================================
if [[ -t 1 ]]; then
  RED='\e[91m'
  GREEN='\e[92m'
  YELLOW='\e[93m'
  BLUE='\e[94m'
  WHITE='\e[97m'
  DIM='\e[2m'
  NC='\e[0m'
  BOLD='\e[1m'
else
  RED='' GREEN='' YELLOW='' BLUE='' WHITE='' DIM='' NC='' BOLD=''
fi

# ==============================================================================
# Logging and Display Functions
# ==============================================================================
info()    { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
error()   { echo -e "${RED}[ERREUR]${NC} $*" >&2; }
success() { echo -e "${GREEN}[OK]${NC} $*"; }

# Print horizontal line
horizline() {
  local cols
  cols=$(tput cols 2>/dev/null || echo 80)
  printf '%*s\n' "$cols" '' | tr ' ' '='
}

# Print elapsed time
print_elapsed() {
  local end_time
  end_time=$(date)
  echo -e "${DIM}Début: $START_TIME${NC}"
  echo -e "${DIM}Maintenant: $end_time${NC}"
}

# Display progress of all stages
show_progress() {
  local current_stage=$1

  horizline
  echo -e "${BOLD}Installation Idris2 + pack (depuis les sources)${NC}"
  echo -e "${DIM}Collection: $ISTIC_PACKAGE_COLLECTION${NC}"
  horizline

  for i in "${!STAGES[@]}"; do
    local stage_num=$((i + 1))
    local stage_text="${STAGES[$i]}"

    if [[ $stage_num -lt $current_stage ]]; then
      echo -e "  ${GREEN}✓${NC} Phase $stage_num/$TOTAL_STAGES : ${WHITE}$stage_text${NC}"
    elif [[ $stage_num -eq $current_stage ]]; then
      echo -e "  ${YELLOW}➤${NC} Phase $stage_num/$TOTAL_STAGES : ${YELLOW}$stage_text${NC} ${DIM}(en cours...)${NC}"
    else
      echo -e "  ${DIM}○ Phase $stage_num/$TOTAL_STAGES : $stage_text${NC}"
    fi
  done

  horizline
  print_elapsed
  horizline
  echo ""
}

# ==============================================================================
# Checkpoint System (for resume capability)
# ==============================================================================
mark_done() {
  local stage="$1"
  mkdir -p "$STATE_DIR"
  echo "$stage" >> "$INSTALL_LOG"
}

is_done() {
  local stage="$1"
  [[ -f "$INSTALL_LOG" ]] && grep -qFx "$stage" "$INSTALL_LOG" 2>/dev/null
}

# ==============================================================================
# Preflight Checks
# ==============================================================================
if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
  error "Ne pas exécuter ce script en tant que root (pas de sudo)."
  exit 1
fi

mkdir -p "$BIN_DIR" "$STATE_DIR"

# ==============================================================================
# Stage 1: Install System Prerequisites
# ==============================================================================
install_stage_1() {
  show_progress 1

  if is_done "stage1"; then
    success "Prérequis déjà installés."
    return 0
  fi

  info "Installation des prérequis système..."

  if command -v apt-get &>/dev/null; then
    info "Détecté: apt (Debian/Ubuntu)"
    sudo apt-get update -qq
    sudo apt-get install -y -qq \
      git curl wget make gcc \
      chezscheme libgmp3-dev \
      rlwrap
  elif command -v dnf &>/dev/null; then
    info "Détecté: dnf (Fedora)"
    sudo dnf install -y \
      git curl wget make gcc \
      chez-scheme gmp-devel \
      rlwrap
  elif command -v pacman &>/dev/null; then
    info "Détecté: pacman (Arch)"
    sudo pacman -Sy --noconfirm \
      git curl wget make gcc gmp rlwrap base-devel

    if ! command -v chezscheme &>/dev/null && ! command -v chez &>/dev/null; then
      if command -v yay &>/dev/null; then
        yay -S --noconfirm chez-scheme
      elif command -v paru &>/dev/null; then
        paru -S --noconfirm chez-scheme
      else
        warn "Installez chez-scheme manuellement depuis AUR"
      fi
    fi
  else
    error "Gestionnaire de paquets non reconnu. Installez manuellement: git curl make gcc chezscheme libgmp rlwrap"
    exit 1
  fi

  mark_done "stage1"
  success "Prérequis installés."
}

# ==============================================================================
# Stage 2: Bootstrap pack + Idris2
# ==============================================================================
install_stage_2() {
  show_progress 2

  if is_done "stage2"; then
    success "pack + Idris2 déjà installés."
    return 0
  fi

  if [[ -z "${SCHEME:-}" ]]; then
    if command -v chezscheme &>/dev/null; then
      SCHEME=chezscheme
    elif command -v chez &>/dev/null; then
      SCHEME=chez
    elif command -v scheme &>/dev/null; then
      SCHEME=scheme
    else
      error "Chez Scheme non trouvé. Installez-le d'abord."
      exit 1
    fi
  fi
  export SCHEME
  info "Utilisation de SCHEME=$SCHEME"

  if [[ -x "$BIN_DIR/pack" ]]; then
    success "pack est déjà installé."
  else
    info "Téléchargement du script d'installation officiel..."
    local tmpdir
    tmpdir=$(mktemp -d)
    local install_script="$tmpdir/install.bash"

    curl -fsSL https://raw.githubusercontent.com/stefan-hoeck/idris2-pack/main/install.bash -o "$install_script"

    sed -i 's/read -r -p "Enter the name of your chez-scheme or racket binary \[\$DETECTED_SCHEME\]: " SCHEME/SCHEME=${SCHEME:-$DETECTED_SCHEME}/' "$install_script"

    info "Exécution du bootstrap (cela peut prendre 20-40 minutes)..."
    echo -e "${YELLOW}   ⏳ Veuillez patienter, la compilation est en cours...${NC}"

    bash "$install_script"

    rm -rf "$tmpdir"
  fi

  export PATH="$BIN_DIR:$PATH"
  if ! command -v pack &>/dev/null; then
    error "pack n'est pas accessible après l'installation."
    exit 1
  fi

  mark_done "stage2"
  success "pack + Idris2 installés."
}

# ==============================================================================
# Stage 3: Switch to ISTIC Collection
# ==============================================================================
install_stage_3() {
  show_progress 3

  if is_done "stage3"; then
    success "Collection $ISTIC_PACKAGE_COLLECTION déjà active."
    return 0
  fi

  export PATH="$BIN_DIR:$PATH"

  local current_collection
  current_collection=$("$BIN_DIR/pack" info 2>/dev/null | grep -oP 'Package Collection\s*:\s*\K\S+' || echo "unknown")

  if [[ "$current_collection" == "$ISTIC_PACKAGE_COLLECTION" ]]; then
    success "Déjà sur la collection $ISTIC_PACKAGE_COLLECTION."
  else
    info "Switch vers la collection $ISTIC_PACKAGE_COLLECTION..."
    "$BIN_DIR/pack" --bootstrap switch "$ISTIC_PACKAGE_COLLECTION"
  fi

  mark_done "stage3"
  success "Collection $ISTIC_PACKAGE_COLLECTION active."
}

# ==============================================================================
# Stage 4: Install idris2-lsp + TP packages
# ==============================================================================
install_stage_4() {
  show_progress 4

  if is_done "stage4"; then
    success "idris2-lsp déjà installé."
    return 0
  fi

  export PATH="$BIN_DIR:$PATH"

  if [[ -x "$BIN_DIR/idris2-lsp" ]]; then
    success "idris2-lsp est déjà installé."
  else
    info "Installation de idris2-lsp (cela peut prendre 10-20 minutes)..."
    echo -e "${YELLOW}   ⏳ Compilation en cours...${NC}"
    "$BIN_DIR/pack" install-app idris2-lsp
  fi

  info "Installation des paquets nécessaires aux TPs (hedgehog, ansi, etc.)..."
  "$BIN_DIR/pack" --no-prompt install ansi containers elab-pretty elab-util getopts hedgehog prettier-ansi pretty-show prim sop || true

  if [[ ! -x "$BIN_DIR/idris2-lsp" ]]; then
    warn "idris2-lsp n'a pas pu être installé. Vous pouvez réessayer plus tard avec:"
    echo "  pack install-app idris2-lsp"
  fi

  mark_done "stage4"
  success "idris2-lsp installé."
}

# ==============================================================================
# Stage 5: Configure HEDGEHOG_COLOR
# ==============================================================================
install_stage_5() {
  show_progress 5

  if is_done "stage5"; then
    success "HEDGEHOG_COLOR déjà configuré."
    return 0
  fi

  if grep -q 'HEDGEHOG_COLOR' "$BASH_RC" 2>/dev/null; then
    success "HEDGEHOG_COLOR est déjà dans $BASH_RC."
  else
    info "Ajout de HEDGEHOG_COLOR dans $BASH_RC..."
    echo '' >> "$BASH_RC"
    echo '# Added by install_pack.sh for Idris2 hedgehog tests' >> "$BASH_RC"
    echo 'export HEDGEHOG_COLOR="1"' >> "$BASH_RC"
  fi

  mark_done "stage5"
  success "HEDGEHOG_COLOR configuré."
}

# ==============================================================================
# Stage 6: Configure PATH
# ==============================================================================
install_stage_6() {
  show_progress 6

  if is_done "stage6"; then
    success "PATH déjà configuré."
    return 0
  fi

  if grep -q '\.local/bin' "$BASH_RC" 2>/dev/null; then
    success "\$HOME/.local/bin est déjà dans PATH."
  else
    info "Ajout de \$HOME/.local/bin au PATH dans $BASH_RC..."
    echo '' >> "$BASH_RC"
    echo '# Added by install_pack.sh for Idris2/pack' >> "$BASH_RC"
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$BASH_RC"
  fi

  if [[ -f "$HOME/.zshrc" ]] && ! grep -q '\.local/bin' "$HOME/.zshrc" 2>/dev/null; then
    echo '' >> "$HOME/.zshrc"
    echo '# Added by install_pack.sh for Idris2/pack' >> "$HOME/.zshrc"
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.zshrc"
    info "PATH également ajouté à ~/.zshrc"
  fi

  mark_done "stage6"
  success "PATH configuré."
}

# ==============================================================================
# Stage 7: Final Verification
# ==============================================================================
install_stage_7() {
  show_progress 7

  export PATH="$BIN_DIR:$PATH"

  local all_ok=true

  echo ""
  echo -e "${BOLD}Vérification de l'installation:${NC}"
  echo ""

  if command -v pack &>/dev/null; then
    echo -e "  ${GREEN}✓${NC} pack        : $("$BIN_DIR/pack" --version 2>/dev/null || echo 'installé')"
  else
    echo -e "  ${RED}✗${NC} pack        : NON INSTALLÉ"
    all_ok=false
  fi

  if command -v idris2 &>/dev/null; then
    local idris_version
    idris_version=$(idris2 --version 2>/dev/null | head -1 || echo 'installé')
    echo -e "  ${GREEN}✓${NC} idris2      : $idris_version"
  else
    echo -e "  ${RED}✗${NC} idris2      : NON INSTALLÉ"
    all_ok=false
  fi

  if command -v idris2-lsp &>/dev/null; then
    local lsp_version
    lsp_version=$(idris2-lsp --version 2>/dev/null | head -1 || echo 'installé')
    echo -e "  ${GREEN}✓${NC} idris2-lsp  : $lsp_version"
  else
    echo -e "  ${YELLOW}○${NC} idris2-lsp  : non installé (optionnel pour VS Code)"
  fi

  echo ""

  if command -v pack &>/dev/null; then
    echo -e "${BOLD}Configuration pack:${NC}"
    "$BIN_DIR/pack" info | head -7
    echo ""
  fi

  mark_done "stage7"

  if $all_ok; then
    return 0
  else
    return 1
  fi
}

# ==============================================================================
# Main Installation
# ==============================================================================
echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║     Installation Idris2 + pack depuis les sources            ║${NC}"
echo -e "${BOLD}║     Collection: $ISTIC_PACKAGE_COLLECTION                              ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

install_stage_1
install_stage_2
install_stage_3
install_stage_4
install_stage_5
install_stage_6
install_stage_7

# ==============================================================================
# Final Message
# ==============================================================================
horizline
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║              INSTALLATION TERMINÉE !                         ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "Les commandes ${BLUE}pack${NC}, ${BLUE}idris2${NC} et ${BLUE}idris2-lsp${NC} sont installées dans:"
echo -e "  ${BLUE}$BIN_DIR${NC}"
echo ""
echo -e "${YELLOW}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${YELLOW}║  IMPORTANT: Pour utiliser Idris2, vous devez:                ║${NC}"
echo -e "${YELLOW}║                                                              ║${NC}"
echo -e "${YELLOW}║  → Ouvrir un NOUVEAU terminal                                ║${NC}"
echo -e "${YELLOW}║    OU exécuter: ${WHITE}source ~/.bashrc${YELLOW}                           ║${NC}"
echo -e "${YELLOW}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "Vérification:"
echo -e "  ${BLUE}pack info${NC}"
echo -e "  ${BLUE}idris2 --version${NC}"
echo -e "  ${BLUE}idris2-lsp --version${NC}"
echo ""
horizline
print_elapsed
horizline
