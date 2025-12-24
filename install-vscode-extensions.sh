#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  ./install-vscode-extensions.sh <extension-id> [<extension-id> ...]
  ./install-vscode-extensions.sh --recommended
  ./install-vscode-extensions.sh --from-file <path>
  ./install-vscode-extensions.sh --vsix <path/to/extension.vsix> [--vsix ...]
  ./install-vscode-extensions.sh --apply-workspace-settings <settings.json>

This helper installs VS Code extensions using the `code` CLI.

Requirements:
  - VS Code installed
  - `code` command available in PATH

Examples:
  ./install-vscode-extensions.sh ms-vscode-remote.remote-wsl
  ./install-vscode-extensions.sh --from-file vscode-extensions.txt
  ./install-vscode-extensions.sh --recommended
  ./install-vscode-extensions.sh --vsix ./my-extension.vsix
  ./install-vscode-extensions.sh --recommended --apply-workspace-settings vscode-settings.json

Notes:
  - --apply-workspace-settings writes to .vscode/settings.json in the current directory.
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

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

extensions=()
vsix_files=()
apply_workspace_settings=""

add_extension() {
  local ext="$1"
  [[ -z "$ext" ]] && return 0
  extensions+=("$ext")
}

add_vsix() {
  local path="$1"
  if [[ -z "$path" ]]; then
    echo "[ERROR] --vsix nécessite un chemin." >&2
    exit 2
  fi
  if [[ ! -f "$path" ]]; then
    echo "[ERROR] Fichier .vsix introuvable: $path" >&2
    exit 2
  fi
  vsix_files+=("$path")
}

load_extensions_file() {
  local file="$1"
  if [[ ! -f "$file" ]]; then
    echo "[ERROR] Fichier introuvable: $file" >&2
    exit 2
  fi

  while IFS= read -r line; do
    line=${line%%#*}
    line=$(echo "$line" | xargs)
    [[ -z "$line" ]] && continue
    add_extension "$line"
  done < "$file"
}

apply_settings_json_to_workspace() {
  local source_json="$1"
  if [[ -z "$source_json" ]]; then
    echo "[ERROR] --apply-workspace-settings nécessite un fichier JSON." >&2
    exit 2
  fi
  if [[ ! -f "$source_json" ]]; then
    echo "[ERROR] Fichier introuvable: $source_json" >&2
    exit 2
  fi
  if ! command -v python3 >/dev/null 2>&1; then
    echo "[ERROR] python3 est requis pour appliquer les settings." >&2
    echo "- Installez python3 (ou appliquez les settings manuellement)." >&2
    exit 1
  fi

  mkdir -p .vscode
  local target=".vscode/settings.json"
  if [[ ! -f "$target" ]]; then
    printf '%s\n' '{}' > "$target"
  fi

  python3 - "$target" "$source_json" <<'PY'
import json, sys

target_path, src_path = sys.argv[1], sys.argv[2]

def read_json(path):
    with open(path, 'r', encoding='utf-8') as f:
        return json.load(f)

target = read_json(target_path)
src = read_json(src_path)

if not isinstance(target, dict):
    raise SystemExit(f"Target settings is not an object: {target_path}")
if not isinstance(src, dict):
    raise SystemExit(f"Source settings is not an object: {src_path}")

# Shallow merge (VS Code settings are typically flat key/value)
target.update(src)

with open(target_path, 'w', encoding='utf-8') as f:
    json.dump(target, f, ensure_ascii=False, indent=2, sort_keys=True)
    f.write("\n")
PY

  echo "[OK] Settings appliqués dans: $target"
}

if [[ $# -lt 1 ]]; then
  echo "[ERROR] Aucun argument fourni." >&2
  usage >&2
  exit 2
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --recommended)
      load_extensions_file "$script_dir/vscode-extensions.txt"
      shift
      ;;
    --from-file)
      file=${2:-}
      if [[ -z "$file" ]]; then
        echo "[ERROR] --from-file nécessite un chemin de fichier." >&2
        usage >&2
        exit 2
      fi
      load_extensions_file "$file"
      shift 2
      ;;
    --vsix)
      add_vsix "${2:-}"
      shift 2
      ;;
    --apply-workspace-settings)
      apply_workspace_settings="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      break
      ;;
    -* )
      echo "[ERROR] Option inconnue: $1" >&2
      usage >&2
      exit 2
      ;;
    *)
      add_extension "$1"
      shift
      ;;
  esac
done

if [[ ${#extensions[@]} -eq 0 && ${#vsix_files[@]} -eq 0 ]]; then
  echo "[ERROR] Rien à faire: aucune extension ID et aucun .vsix." >&2
  usage >&2
  exit 2
fi

if [[ -n "$apply_workspace_settings" ]]; then
  apply_settings_json_to_workspace "$apply_workspace_settings"
fi

for ext in "${extensions[@]}"; do
  echo "[INFO] Installation de l'extension VS Code: $ext"
  code --install-extension "$ext" --force
done

for vsix in "${vsix_files[@]}"; do
  echo "[INFO] Installation de l'extension VS Code (.vsix): $vsix"
  code --install-extension "$vsix" --force
done

echo "[OK] Extensions installées. Redémarrez VS Code si nécessaire."