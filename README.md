
# Script d'installation rapide d'[Idris2](https://www.idris-lang.org/) et [pack](https://github.com/stefan-hoeck/idris2-pack) [`nightly-250828`]


> Vous cherchez l'installation officielle depuis les sources ? Voir le [guide d'installation idris2-pack](https://github.com/stefan-hoeck/idris2-pack/blob/main/INSTALL.md).


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



