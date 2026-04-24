# GoLand Templates

Install the templates from this directory into a local GoLand config with:

```sh
./tools/goland/install.sh
```

Useful flags:

```sh
./tools/goland/install.sh --version 2025.1
./tools/goland/install.sh --config-dir "$HOME/Library/Application Support/JetBrains/GoLand2025.1"
./tools/goland/install.sh --mode symlink
```

What it installs:

- `file-and-code-templates/*` into `<GoLand config>/fileTemplates`
- `live-templates/*` as one managed group in `<GoLand config>/templates/firestarter.xml`

Close GoLand before running the installer. JetBrains can overwrite settings on shutdown.
