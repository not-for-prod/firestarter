#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  ./tools/goland/install.sh [--version <2025.1|GoLand2025.1>] [--config-dir <path>] [--mode copy|symlink]

Examples:
  ./tools/goland/install.sh
  ./tools/goland/install.sh --version 2025.1
  ./tools/goland/install.sh --config-dir "$HOME/Library/Application Support/JetBrains/GoLand2025.1"
  ./tools/goland/install.sh --mode symlink

Installs:
  - File and code templates into <config>/fileTemplates
  - Live templates into <config>/templates/firestarter.xml

Notes:
  - Close GoLand before running this script. JetBrains may overwrite settings on shutdown.
  - Live templates are installed as one managed group: "firestarter".
EOF
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODE="copy"
VERSION=""
CONFIG_DIR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      VERSION="${2:-}"
      shift 2
      ;;
    --config-dir)
      CONFIG_DIR="${2:-}"
      shift 2
      ;;
    --mode)
      MODE="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ "$MODE" != "copy" && "$MODE" != "symlink" ]]; then
  echo "Unsupported mode: $MODE" >&2
  exit 1
fi

jetbrains_base_dir() {
  case "$(uname -s)" in
    Darwin)
      printf '%s\n' "$HOME/Library/Application Support/JetBrains"
      ;;
    Linux)
      printf '%s\n' "$HOME/.config/JetBrains"
      ;;
    *)
      echo "Unsupported OS: $(uname -s). Pass --config-dir explicitly." >&2
      exit 1
      ;;
  esac
}

resolve_config_dir() {
  if [[ -n "$CONFIG_DIR" ]]; then
    printf '%s\n' "$CONFIG_DIR"
    return
  fi

  local base_dir
  base_dir="$(jetbrains_base_dir)"

  if [[ ! -d "$base_dir" ]]; then
    echo "JetBrains config base directory does not exist: $base_dir" >&2
    exit 1
  fi

  if [[ -n "$VERSION" ]]; then
    case "$VERSION" in
      GoLand*)
        printf '%s\n' "$base_dir/$VERSION"
        ;;
      *)
        printf '%s\n' "$base_dir/GoLand$VERSION"
        ;;
    esac
    return
  fi

  local detected
  detected="$(
    find "$base_dir" -maxdepth 1 -type d -name 'GoLand*' -print \
      | sort -V \
      | tail -n 1
  )"

  if [[ -z "$detected" ]]; then
    echo "Could not detect a GoLand config directory under $base_dir" >&2
    exit 1
  fi

  printf '%s\n' "$detected"
}

xml_value_escape() {
  awk '
    BEGIN { ORS = "" }
    {
      gsub(/&/, "\\&amp;");
      gsub(/</, "\\&lt;");
      gsub(/>/, "\\&gt;");
      gsub(/"/, "\\&quot;");
      if (NR > 1) {
        printf "&#10;";
      }
      printf "%s", $0;
    }
  ' "$1"
}

write_live_template() {
  local name="$1"
  local source_file="$2"
  local context="$3"
  local variables_block="$4"
  local value

  value="$(xml_value_escape "$source_file")"

  cat <<EOF
  <template name="$name" value="$value" description="" toReformat="false" toShortenFQNames="true">
$variables_block
    <context>
$context
    </context>
  </template>
EOF
}

install_file_template() {
  local src="$1"
  local dest="$2"

  case "$MODE" in
    copy)
      cp "$src" "$dest"
      ;;
    symlink)
      ln -sfn "$src" "$dest"
      ;;
  esac
}

CONFIG_DIR="$(resolve_config_dir)"
FILE_TEMPLATES_DIR="$CONFIG_DIR/fileTemplates"
LIVE_TEMPLATES_DIR="$CONFIG_DIR/templates"
MANAGED_LIVE_TEMPLATE_FILE="$LIVE_TEMPLATES_DIR/firestarter.xml"

if [[ ! -d "$CONFIG_DIR" ]]; then
  echo "GoLand config directory does not exist: $CONFIG_DIR" >&2
  exit 1
fi

if pgrep -f '[G]oLand' >/dev/null 2>&1; then
  echo "Warning: GoLand appears to be running. Close it before installing templates." >&2
fi

mkdir -p "$FILE_TEMPLATES_DIR" "$LIVE_TEMPLATES_DIR"

file_template_sources=(
  "domain_infrastructure_interface"
  "domain_service_interface"
  "proto"
  "test_suite"
)

file_template_targets=(
  "domain infrastructure ifce.go"
  "domain service ifce.go"
  "proto.proto"
  "Test Suite.go"
)

for i in "${!file_template_sources[@]}"; do
  src="$SCRIPT_DIR/file-and-code-templates/${file_template_sources[$i]}"
  dest="$FILE_TEMPLATES_DIR/${file_template_targets[$i]}"

  if [[ ! -f "$src" ]]; then
    echo "Missing template source: $src" >&2
    exit 1
  fi

  install_file_template "$src" "$dest"
  echo "Installed file template: ${file_template_targets[$i]}"
done

tmp_live_template_file="$(mktemp)"
trap 'rm -f "$tmp_live_template_file"' EXIT

{
  cat <<'EOF'
<templateSet group="firestarter">
EOF

  write_live_template \
    "embed" \
    "$SCRIPT_DIR/live-templates/embed" \
    '      <option name="GO" value="true" />' \
    '    <variable name="FILE" expression="" defaultValue="" alwaysStopAt="true" />
    <variable name="NAME" expression="" defaultValue="" alwaysStopAt="true" />'

  write_live_template \
    "options" \
    "$SCRIPT_DIR/live-templates/options" \
    '      <option name="GO" value="true" />' \
    '    <variable name="NAME" expression="" defaultValue="" alwaysStopAt="true" />'

  write_live_template \
    "enum" \
    "$SCRIPT_DIR/live-templates/proto_enum" \
    '      <option name="PROTO" value="true" />' \
    '    <variable name="NAME" expression="" defaultValue="" alwaysStopAt="true" />
    <variable name="ENUM_NAME" expression="groovyScript(&quot;_1.replaceAll(/([a-z0-9])([A-Z])/, '\''\$1_\$2'\'').toUpperCase()&quot;, NAME) " defaultValue="" alwaysStopAt="false" />'

  write_live_template \
    "rpc" \
    "$SCRIPT_DIR/live-templates/proto_rpc" \
    '      <option name="PROTO" value="true" />
      <option name="PROTOTEXT" value="true" />' \
    '    <variable name="NAME" expression="" defaultValue="" alwaysStopAt="true" />
    <variable name="METHOD" expression="" defaultValue="" alwaysStopAt="true" />
    <variable name="URL" expression="" defaultValue="" alwaysStopAt="true" />'

  write_live_template \
    "service" \
    "$SCRIPT_DIR/live-templates/proto_service" \
    '      <option name="PROTO" value="true" />
      <option name="PROTOTEXT" value="true" />' \
    '    <variable name="NAME" expression="" defaultValue="" alwaysStopAt="true" />'

  cat <<'EOF'
</templateSet>
EOF
} > "$tmp_live_template_file"

case "$MODE" in
  copy)
    cp "$tmp_live_template_file" "$MANAGED_LIVE_TEMPLATE_FILE"
    ;;
  symlink)
    managed_source="$SCRIPT_DIR/live-templates/firestarter.xml"
    cp "$tmp_live_template_file" "$managed_source"
    ln -sfn "$managed_source" "$MANAGED_LIVE_TEMPLATE_FILE"
    ;;
esac

echo "Installed live templates: $MANAGED_LIVE_TEMPLATE_FILE"
echo "Target GoLand config: $CONFIG_DIR"
