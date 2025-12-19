#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  ./init.sh <destination-module>

Example:
  ./init.sh github.com/acme/payment-service
EOF
}

if [[ "${1:-}" == "" ]] || [[ "${1:-}" == "-h" ]] || [[ "${1:-}" == "--help" ]]; then
  usage
  [[ "${1:-}" == "" ]] && exit 1
  exit 0
fi

MODULE="$1"
SERVICE_NAME="$(basename "$MODULE")"

if [[ "$SERVICE_NAME" == "" ]] || [[ "$SERVICE_NAME" == "." ]] || [[ "$SERVICE_NAME" == "/" ]]; then
  echo "Invalid destination module: $MODULE" >&2
  exit 1
fi

escape_sed_replacement() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//&/\\&}"
  printf '%s' "$s"
}

MODULE_ESCAPED="$(escape_sed_replacement "$MODULE")"

# go.mod (support both placeholder templates and the current "firestarter" module name)
if [[ -f "go.mod" ]]; then
  sed -i "" "s|{{MODULE_NAME}}|$MODULE_ESCAPED|g" go.mod
  sed -i "" "s|firestarter|$MODULE_ESCAPED|g" go.mod
fi

# Rename folders that still contain "firestarter" (avoid touching Go's vendor cache under pkg/)
while IFS= read -r -d '' dir; do
  new_dir="${dir//firestarter/$SERVICE_NAME}"
  if [[ "$new_dir" == "$dir" ]]; then
    continue
  fi
  if [[ -e "$new_dir" ]]; then
    echo "Refusing to rename: destination exists: $new_dir" >&2
    exit 1
  fi
  mkdir -p "$(dirname "$new_dir")"
  echo "Renaming: $dir -> $new_dir"
  mv "$dir" "$new_dir"
done < <(
  find . -depth \
    \( -path './.git' -o -path './pkg' \) -prune -o \
    -type d -name '*firestarter*' -print0
)

echo "Initialized project:"
echo "  module:  $MODULE"
echo "  service: $SERVICE_NAME"
