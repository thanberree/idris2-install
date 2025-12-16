# Idris2 + pack — Pre-compiled binaries

Pre-compiled binaries for [Idris2](https://www.idris-lang.org/) and [pack](https://github.com/stefan-hoeck/idris2-pack) package manager.

**Collection:** `nightly-250828` (Idris2 0.7.0)  
**Platforms:** Ubuntu 24.04 (noble)

> Looking for the official installation from source? See [idris2-pack install guide](https://github.com/stefan-hoeck/idris2-pack/blob/main/INSTALL.md).

## Installation

```bash
curl -fsSL https://raw.githubusercontent.com/thanberree/idris2-install/main/install.sh | bash
```

Then open a new terminal (or run `source ~/.bashrc`) and verify:
```bash
pack info
idris2 --version
```

### Reinstall

If you already have an installation and want to reinstall:
```bash
curl -fsSL https://raw.githubusercontent.com/thanberree/idris2-install/main/install.sh | bash -s -- --force
```

## Uninstall

```bash
rm -rf ~/.local/bin/pack ~/.local/bin/pack_app ~/.local/bin/idris2
rm -rf ~/.local/state/pack ~/.config/pack ~/.cache/pack
```

## What's included

The archive contains:
- Idris2 compiler (0.7.0)
- pack package manager
- Pre-built libraries: base, contrib, linear, network, prelude
- Additional packages: ansi, containers, elab-pretty, elab-util, getopts, hedgehog, prettier-ansi, pretty-show, prim, sop

## License

The installation scripts are provided as-is. Idris2 and pack are subject to their respective licenses.
