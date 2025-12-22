#!/bin/bash
# Script to create portable wrappers for idris2 and idris2-lsp
# Usage: ./create-wrappers.sh <IDRIS2_VERSION> [linux|macos]
set -e

IDRIS2_VERSION="${1:-0.7.0}"
PLATFORM="${2:-linux}"

echo "=== Creating portable wrappers ==="
echo "IDRIS2_VERSION=$IDRIS2_VERSION"
echo "PLATFORM=$PLATFORM"

# Debug: Show all install directories
echo "=== All install directories ==="
ls -la ~/.local/state/pack/install/

# Find idris2-lsp first - it tells us where everything is
LSP_DIR=$(ls -d ~/.local/state/pack/install/*/idris2-lsp/*/ 2>/dev/null | head -1)

if [ -z "$LSP_DIR" ]; then
  echo "ERROR: Could not find idris2-lsp directory"
  find ~/.local/state/pack/install -name "idris2-lsp" -type d 2>/dev/null || true
  exit 1
fi

# Extract the commit and hash from the path
# Path format: ~/.local/state/pack/install/COMMIT/idris2-lsp/HASH/
IDRIS2_COMMIT=$(echo "$LSP_DIR" | sed 's|.*/install/\([^/]*\)/idris2-lsp/.*|\1|')
LSP_HASH=$(basename $(dirname "$LSP_DIR"))

echo "IDRIS2_COMMIT=$IDRIS2_COMMIT"
echo "LSP_HASH=$LSP_HASH"

# Verify paths exist
echo "Verifying paths..."
ls ~/.local/state/pack/install/$IDRIS2_COMMIT/idris2/bin/idris2
ls ~/.local/state/pack/install/$IDRIS2_COMMIT/idris2-lsp/$LSP_HASH/bin/idris2-lsp

# Create idris2 wrapper
cat > ~/.local/bin/idris2 << 'WRAPPER'
#!/bin/sh
set -e
if [ "$(uname)" = "Darwin" ]; then
  DIR=$(cd "$(dirname "$0")" && pwd -P)
else
  DIR=$(dirname "$(readlink -f -- "$0")")
fi
INSTALL_DIR="$DIR/../state/pack/install/IDRIS2_COMMIT_PLACEHOLDER"
APPLICATION="$INSTALL_DIR/idris2/bin/idris2"
if [ ! -x "$APPLICATION" ]; then
  echo "[ fatal ] idris2 binary not found at $APPLICATION" >&2
  exit 2
fi
export IDRIS2_PREFIX="$INSTALL_DIR/idris2/idris2-IDRIS2_VERSION_PLACEHOLDER"
export IDRIS2_PACKAGE_PATH="$INSTALL_DIR"
export IDRIS2_LIBS="$INSTALL_DIR/idris2/idris2-IDRIS2_VERSION_PLACEHOLDER/lib"
export IDRIS2_DATA="$INSTALL_DIR/idris2/idris2-IDRIS2_VERSION_PLACEHOLDER/support"
exec "$APPLICATION" "$@"
WRAPPER

# Create idris2-lsp wrapper
cat > ~/.local/bin/idris2-lsp << 'WRAPPER'
#!/bin/sh
set -e
if [ "$(uname)" = "Darwin" ]; then
  DIR=$(cd "$(dirname "$0")" && pwd -P)
else
  DIR=$(dirname "$(readlink -f -- "$0")")
fi
INSTALL_DIR="$DIR/../state/pack/install/IDRIS2_COMMIT_PLACEHOLDER"
APPLICATION="$INSTALL_DIR/idris2-lsp/LSP_HASH_PLACEHOLDER/bin/idris2-lsp"
if [ ! -x "$APPLICATION" ]; then
  echo "[ fatal ] idris2-lsp binary not found at $APPLICATION" >&2
  exit 2
fi
export IDRIS2_PREFIX="$INSTALL_DIR/idris2/idris2-IDRIS2_VERSION_PLACEHOLDER"
export IDRIS2_PACKAGE_PATH="$INSTALL_DIR"
export IDRIS2_LIBS="$INSTALL_DIR/idris2/idris2-IDRIS2_VERSION_PLACEHOLDER/lib"
export IDRIS2_DATA="$INSTALL_DIR/idris2/idris2-IDRIS2_VERSION_PLACEHOLDER/support"
LSP_APP_DIR="$INSTALL_DIR/idris2-lsp/LSP_HASH_PLACEHOLDER/bin/idris2-lsp_app"
export LD_LIBRARY_PATH="$LSP_APP_DIR:${LD_LIBRARY_PATH:-}"
export DYLD_LIBRARY_PATH="$LSP_APP_DIR:${DYLD_LIBRARY_PATH:-}"
exec "$APPLICATION" "$@"
WRAPPER

# Replace placeholders
if [ "$PLATFORM" = "macos" ]; then
  sed -i '' "s/IDRIS2_COMMIT_PLACEHOLDER/$IDRIS2_COMMIT/g" ~/.local/bin/idris2
  sed -i '' "s/IDRIS2_VERSION_PLACEHOLDER/$IDRIS2_VERSION/g" ~/.local/bin/idris2
  sed -i '' "s/IDRIS2_COMMIT_PLACEHOLDER/$IDRIS2_COMMIT/g" ~/.local/bin/idris2-lsp
  sed -i '' "s/LSP_HASH_PLACEHOLDER/$LSP_HASH/g" ~/.local/bin/idris2-lsp
  sed -i '' "s/IDRIS2_VERSION_PLACEHOLDER/$IDRIS2_VERSION/g" ~/.local/bin/idris2-lsp
else
  sed -i "s/IDRIS2_COMMIT_PLACEHOLDER/$IDRIS2_COMMIT/g" ~/.local/bin/idris2
  sed -i "s/IDRIS2_VERSION_PLACEHOLDER/$IDRIS2_VERSION/g" ~/.local/bin/idris2
  sed -i "s/IDRIS2_COMMIT_PLACEHOLDER/$IDRIS2_COMMIT/g" ~/.local/bin/idris2-lsp
  sed -i "s/LSP_HASH_PLACEHOLDER/$LSP_HASH/g" ~/.local/bin/idris2-lsp
  sed -i "s/IDRIS2_VERSION_PLACEHOLDER/$IDRIS2_VERSION/g" ~/.local/bin/idris2-lsp
fi

chmod +x ~/.local/bin/idris2 ~/.local/bin/idris2-lsp

echo "=== idris2 wrapper ==="
head -15 ~/.local/bin/idris2
echo "=== idris2-lsp wrapper ==="
head -15 ~/.local/bin/idris2-lsp

echo "=== Wrappers created successfully ==="
