🇬🇧 *[English version](README-EN.md)*

# Installation de binaires pré-compilés pour [Idris2](https://www.idris-lang.org/) et le gestionnaire de paquets [pack](https://github.com/stefan-hoeck/idris2-pack) [collection : `nightly-250828` (Idris2 0.7.0)]


> Vous cherchez l'installation officielle depuis les sources ? Voir le [guide d'installation idris2-pack](https://github.com/stefan-hoeck/idris2-pack/blob/main/INSTALL.md).


**Plateformes supportées :**
| Plateforme | Versions |
|------------|----------|
| Ubuntu | 22.04 (jammy), 24.04 (noble) |
| Debian | 12 (bookworm) |
| Fedora | 40, 43 |
| Arch Linux |  |
| Linux Mint | 21, 22 |


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



