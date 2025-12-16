# Installation d'Idris2 et pack

## Prérequis

- Ubuntu 22.04 / 24.04 ou macOS
- curl (`sudo apt install curl` sur Ubuntu)

## Installation

Ouvrez un terminal et exécutez :

```
curl -fsSL https://example.com/install.sh | bash
```

L'installation prend environ 1 à 2 minutes.

## Après l'installation

Ouvrez un nouveau terminal, puis vérifiez :

```
pack info
idris2 --version
```

## Utilisation de base

Lancer le REPL :
```
idris2
```

Compiler un fichier :
```
idris2 MonFichier.idr -o monprogramme
```

Installer un paquet :
```
pack install nom-du-paquet
```

## En cas de problème

Vérifiez que le PATH est configuré :
```
echo $PATH | grep -q '.local/bin' && echo "OK" || echo "PATH non configuré"
```

Si le PATH n'est pas configuré :
```
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

Pour réinstaller complètement :
```
rm -rf ~/.local/state/pack ~/.config/pack ~/.cache/pack
rm -f ~/.local/bin/pack ~/.local/bin/idris2
```
Puis relancez l'installation.
