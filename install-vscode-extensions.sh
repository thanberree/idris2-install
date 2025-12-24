#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  ./install-vscode-extensions.sh <extension-id> [<extension-id> ...]
  ./install-vscode-extensions.sh --from-file <path>

This helper installs VS Code extensions using the `code` CLI.

Requirements:
  - VS Code installed
  - `code` command available in PATH

Examples:
  ./install-vscode-extensions.sh ms-vscode-remote.remote-wsl
  ./install-vscode-extensions.sh --from-file vscode-extensions.txt
EOF
}

if [[ ${1:-} == "-h" || ${1:-} == "--help" ]]; then
  usage
  exit 0
fi

if ! command -v code >/dev/null 2>&1; then
  echo "[ERROR] La commande 'code' est introuvable." >&2
  echo "- Installez VS Code, puis activez la commande shell 'code'." >&2
  echo "- Dans VS Code: Ctrl+Shift+P → 'Shell Command: Install \'code\' command in PATH'" >&2
  exit 1
fi

extensions=()

if [[ ${1:-} == "--from-file" ]]; then
  file=${2:-}
  if [[ -z "$file" ]]; then
    echo "[ERROR] --from-file nécessite un chemin de fichier." >&2
    usage >&2
    exit 2
  fi
  if [[ ! -f "$file" ]]; then
    echo "[ERROR] Fichier introuvable: $file" >&2
    exit 2
  fi

  while IFS= read -r line; do
    # strip comments and whitespace
    line=${line%%#*}
    line=$(echo "$line" | xargs)
    [[ -z "$line" ]] && continue
    extensions+=("$line")
  done < "$file"
else
  if [[ $# -lt 1 ]]; then
    echo "[ERROR] Aucune extension fournie." >&2
    usage >&2
    exit 2
  fi
  extensions=("$@")
fi

if [[ ${#extensions[@]} -eq 0 ]]; then
  echo "[ERROR] Liste d'extensions vide." >&2
  exit 2
fi

for ext in "${extensions[@]}"; do
  echo "[INFO] Installation de l'extension VS Code: $ext"
  code --install-extension "$ext" --force
done

echo "[OK] Extensions installées. Redémarrez VS Code si nécessaire."