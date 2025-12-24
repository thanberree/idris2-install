
# Script d'installation rapide d'[Idris2](https://www.idris-lang.org/) et [pack](https://github.com/stefan-hoeck/idris2-pack) [`nightly-250828`]

Le script `install.sh` installe des binaires précompilés. Cela permet une installation très rapide comparée à  [l'installation « officielle »](https://github.com/stefan-hoeck/idris2-pack/blob/main/INSTALL.md) depuis les sources.


**Plateformes supportées :**
| Plateforme                          | Versions                              |
|-------------------------------------|---------------------------------------|
| Ubuntu                              | 22.04 (jammy), 24.04 (noble)          |
| Debian                              | 12 (bookworm), 13 (trixie)            |
| Fedora                              | 40, 43                                |
| Arch Linux                          |                                       |
| Linux Mint                          | 21, 22                                |


## Prérequis

- Avoir un **utilisateur non-root** avec des **droits sudo**.
- Avoir la commande `curl`.

Si `curl` n'est pas installé :

- Ubuntu / Debian / Mint : `sudo apt-get update && sudo apt-get install -y curl`
- Fedora : `sudo dnf install -y curl`
- Arch Linux : `sudo pacman -Sy --noconfirm curl`


## Installation

```bash
curl -fsSL https://raw.githubusercontent.com/thanberree/idris2-install/main/install.sh | bash
```

Ouvrez ensuite un nouveau terminal (ou exécutez `source ~/.bashrc` / `source ~/.zshrc`) et vérifiez :

```bash
pack info
idris2 --version
idris2-lsp --version
```

## VS Code (extensions)

Ce dépôt ne cherche pas à installer VS Code automatiquement.

En revanche, si la commande `code` est disponible, vous pouvez installer les extensions requises avec :

```bash
./install-vscode-extensions.sh <extension-id> [<extension-id> ...]
```

Ou via un fichier :

```bash
./install-vscode-extensions.sh --from-file vscode-extensions.txt
```

La liste recommandée pour le cours est fournie dans `vscode-extensions.txt`.

Extensions personnelles : si vous avez un fichier `.vsix`, vous pouvez aussi l'installer :

```bash
./install-vscode-extensions.sh --vsix /chemin/vers/mon-extension.vsix
```

Et si vous voulez appliquer des settings VS Code au niveau du projet (fichier `.vscode/settings.json`) :

```bash
./install-vscode-extensions.sh --recommended --apply-workspace-settings vscode-settings.json
```

### Réinstallation

Si vous avez déjà une installation et souhaitez réinstaller :
```bash
curl -fsSL https://raw.githubusercontent.com/thanberree/idris2-install/main/install.sh | bash -s -- --force
```

## Désinstallation

```bash
rm -rf ~/.local/bin/pack ~/.local/bin/pack_app ~/.local/bin/idris2 ~/.local/bin/idris2-lsp
rm -rf ~/.local/state/pack ~/.config/pack ~/.cache/pack
```

## Contenu

L'archive contient :
- Compilateur Idris2 (0.7.0)
- Gestionnaire de paquets pack
- idris2-lsp (serveur LSP pour VS Code)
- Bibliothèques pré-compilées : base, contrib, linear, network, prelude, ansi, containers, elab-pretty, elab-util, getopts, hedgehog, prettier-ansi, pretty-show, prim, sop



