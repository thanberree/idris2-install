# Idris2 + pack — Pre-compiled binaries

🇫🇷 *[Version française](README.md)*

Pre-compiled binaries for [Idris2](https://www.idris-lang.org/) and [pack](https://github.com/stefan-hoeck/idris2-pack) package manager.

**Collection:** `nightly-250828` (Idris2 0.7.0)

**Supported platforms:**
| Platform | Versions |
|----------|----------|
| Ubuntu | 22.04 (jammy), 24.04 (noble) |
| Debian | 12 (bookworm) |
| Fedora | 40, 43 |
| Arch Linux | yes |
| Linux Mint | 21.x, 22.x |

If your system is not supported, use the from-source installer:
`curl -fsSL https://raw.githubusercontent.com/thanberree/idris2-install/main/install_pack.sh | bash`

> Looking for the official installation from source? See [idris2-pack install guide](https://github.com/stefan-hoeck/idris2-pack/blob/main/INSTALL.md).

## Installation

```bash
curl -fsSL https://raw.githubusercontent.com/thanberree/idris2-install/main/install.sh | bash
```

Then open a new terminal (or run `source ~/.bashrc` / `source ~/.zshrc`) and verify:
```bash
pack info
idris2 --version
idris2-lsp --version
```

### Reinstall

If you already have an installation and want to reinstall:
```bash
curl -fsSL https://raw.githubusercontent.com/thanberree/idris2-install/main/install.sh | bash -s -- --force
```

## Uninstall

```bash
rm -rf ~/.local/bin/pack ~/.local/bin/pack_app ~/.local/bin/idris2 ~/.local/bin/idris2-lsp
rm -rf ~/.local/state/pack ~/.config/pack ~/.cache/pack
```

## What's included

The archive contains:
- Idris2 compiler (0.7.0)
- pack package manager
- idris2-lsp (LSP server for VS Code)
- Pre-built libraries: base, contrib, linear, network, prelude
- Additional packages: ansi, containers, elab-pretty, elab-util, getopts, hedgehog, prettier-ansi, pretty-show, prim, sop

## VS Code integration

1. Install the [Idris2-LSP](https://marketplace.visualstudio.com/items?itemName=meraymond.idris-vscode) extension in VS Code
2. The extension should automatically detect `idris2-lsp` if your PATH is configured

## License

The installation scripts are provided as-is. Idris2 and pack are subject to their respective licenses.
