#!/bin/bash
# Script de build automatisé pour créer les archives Idris2+pack
# Usage: ./build-archive.sh <distro> [collection]
# Exemples:
#   ./build-archive.sh ubuntu:22.04
#   ./build-archive.sh debian:12
#   ./build-archive.sh fedora:40
#   ./build-archive.sh ubuntu:24.04 nightly-250828

set -e

DISTRO="${1:-ubuntu:24.04}"
COLLECTION="${2:-nightly-250828}"

# Parser distro:version
DISTRO_NAME=$(echo "$DISTRO" | cut -d: -f1)
DISTRO_VERSION=$(echo "$DISTRO" | cut -d: -f2)

# Mapping version -> codename et image Docker
case "$DISTRO_NAME" in
  ubuntu)
    case "$DISTRO_VERSION" in
      22.04) CODENAME="jammy" ;;
      24.04) CODENAME="noble" ;;
      *) echo "Version Ubuntu non supportée: $DISTRO_VERSION"; exit 1 ;;
    esac
    DOCKER_IMAGE="ubuntu:$DISTRO_VERSION"
    PKG_MANAGER="apt"
    ;;
  debian)
    case "$DISTRO_VERSION" in
      12|bookworm) CODENAME="bookworm"; DISTRO_VERSION="12" ;;
      11|bullseye) CODENAME="bullseye"; DISTRO_VERSION="11" ;;
      *) echo "Version Debian non supportée: $DISTRO_VERSION"; exit 1 ;;
    esac
    DOCKER_IMAGE="debian:$DISTRO_VERSION"
    PKG_MANAGER="apt"
    ;;
  fedora)
    case "$DISTRO_VERSION" in
      39|40|41) CODENAME="fedora" ;;
      *) echo "Version Fedora non supportée: $DISTRO_VERSION"; exit 1 ;;
    esac
    DOCKER_IMAGE="fedora:$DISTRO_VERSION"
    PKG_MANAGER="dnf"
    ;;
  *)
    echo "Distribution non supportée: $DISTRO_NAME"
    echo "Distributions supportées: ubuntu, debian, fedora"
    exit 1
    ;;
esac

CONTAINER_NAME="idris2-build-${CODENAME}"
ARCHIVE_NAME="idris2-pack-${COLLECTION}-${CODENAME}-full.tar.gz"

echo "=== Build Idris2+pack pour $DISTRO_NAME $DISTRO_VERSION ($CODENAME) ==="
echo "Image Docker: $DOCKER_IMAGE"
echo "Gestionnaire de paquets: $PKG_MANAGER"
echo "Collection: $COLLECTION"
echo "Archive: $ARCHIVE_NAME"
echo ""

# Vérifier si le conteneur existe déjà
if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
  echo "Le conteneur $CONTAINER_NAME existe déjà."
  read -p "Voulez-vous le supprimer et recommencer? [y/N] " -n 1 -r
  echo
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    docker rm -f "$CONTAINER_NAME"
  else
    echo "Réutilisation du conteneur existant..."
  fi
fi

# Créer le conteneur s'il n'existe pas
if ! docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
  echo "=== Création du conteneur ==="
  
  case "$PKG_MANAGER" in
    apt)
      docker run --name "$CONTAINER_NAME" -d "$DOCKER_IMAGE" bash -c "
        ln -snf /usr/share/zoneinfo/UTC /etc/localtime && echo UTC > /etc/timezone
        apt-get update -qq
        apt-get install -y -qq curl sudo lsb-release chezscheme libgmp-dev make gcc git >/dev/null 2>&1
        useradd -m -s /bin/bash builder
        echo 'builder ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers
        sleep infinity
      "
      ;;
    dnf)
      docker run --name "$CONTAINER_NAME" -d "$DOCKER_IMAGE" bash -c "
        ln -snf /usr/share/zoneinfo/UTC /etc/localtime && echo UTC > /etc/timezone
        dnf install -y curl sudo chez-scheme gmp-devel make gcc git >/dev/null 2>&1
        useradd -m -s /bin/bash builder
        echo 'builder ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers
        # Créer le lien chezscheme si nécessaire
        if [[ ! -x /usr/bin/chezscheme ]] && [[ -x /usr/bin/scheme ]]; then
          ln -sf /usr/bin/scheme /usr/bin/chezscheme
        fi
        sleep infinity
      "
      ;;
  esac
  
  echo "Attente du démarrage du conteneur..."
  sleep 10
  
  # Vérifier que le conteneur est prêt
  for i in {1..30}; do
    if docker exec "$CONTAINER_NAME" id builder &>/dev/null; then
      echo "Conteneur prêt."
      break
    fi
    echo "Attente... ($i/30)"
    sleep 2
  done
fi

# Fonction pour exécuter une commande dans le conteneur
run_in_container() {
  docker exec "$CONTAINER_NAME" su - builder -c "export PATH=\"\$HOME/.local/bin:\$PATH\" && $1"
}

# Vérifier si pack est déjà installé
if ! run_in_container "command -v pack" &>/dev/null; then
  echo "=== Installation de pack + Idris2 ==="
  run_in_container '
    curl -fsSL https://raw.githubusercontent.com/stefan-hoeck/idris2-pack/main/install.bash -o install.bash
    sed -i "s/read -r -p .*/SCHEME=\${SCHEME:-\$DETECTED_SCHEME}/" install.bash
    SCHEME=chezscheme bash install.bash
  '
fi

# Vérifier la collection actuelle
CURRENT_COLLECTION=$(run_in_container "pack info 2>/dev/null | grep 'Package Collection' | awk '{print \$4}'" || echo "")
if [[ "$CURRENT_COLLECTION" != "$COLLECTION" ]]; then
  echo "=== Switch vers $COLLECTION ==="
  run_in_container "pack --bootstrap switch $COLLECTION"
fi

# Installer les packages
echo "=== Installation des packages ==="
run_in_container "pack install ansi containers contrib elab-pretty elab-util getopts hedgehog prettier-ansi pretty-show prim sop"

# Installer idris2-lsp
if ! run_in_container "command -v idris2-lsp" &>/dev/null; then
  echo "=== Installation de idris2-lsp ==="
  run_in_container "pack install-app idris2-lsp"
fi

# Vérification
echo "=== Vérification ==="
run_in_container "pack info && echo '---' && idris2 --version && echo '---' && idris2-lsp --version"

# Créer l'archive
echo "=== Création de l'archive ==="
run_in_container "
  cd ~
  tar --exclude='.git' --exclude='.cache/pack/git' -czvf /tmp/$ARCHIVE_NAME \
    .local/bin/pack \
    .local/bin/pack_app \
    .local/bin/idris2 \
    .local/bin/idris2-lsp \
    .local/state/pack \
    .config/pack \
    .cache/pack 2>&1 | tail -5
"

# Copier l'archive
echo "=== Extraction de l'archive ==="
docker cp "$CONTAINER_NAME:/tmp/$ARCHIVE_NAME" "/tmp/$ARCHIVE_NAME"
ls -lh "/tmp/$ARCHIVE_NAME"

echo ""
echo "=== BUILD TERMINÉ ==="
echo "Archive: /tmp/$ARCHIVE_NAME"
echo ""
echo "Pour uploader sur GitHub:"
echo "  gh release upload v1.0 /tmp/$ARCHIVE_NAME --clobber"
echo ""
echo "Pour supprimer le conteneur:"
echo "  docker rm -f $CONTAINER_NAME"
