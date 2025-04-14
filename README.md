# ompf

Unofficial package manager for Odin.

# External Dependencies
- libgit2

# Bootstrap

```console
git clone --depth=1 https://github.com/Up05/toml_parser ./vendor/toml_parser/
odin build . -o:speed -extra-linker-flags:-L$HOME/.local/lib/
```

# Usage

```console
ompf fetch # fetch dependencies
ompf checkout # checkout tags or branches for dependencies
```

