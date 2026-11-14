#!/usr/bin/env bash
# Run the fetch step for the provider chosen by setup.sh.
# A provider is a directory under providers/<name>/ with basemap.json.template.
# fetch.sh in that directory is optional. It downloads tiles into maps/data.
set -euo pipefail
cd "$(dirname "$0")"
[[ -f provider ]] || { echo "Run setup.sh before fetching tiles." >&2; exit 1; }
name=$(cat provider)
script=providers/$name/fetch.sh
if [[ ! -f "$script" ]]; then
  echo "Provider $name serves tiles from its own URL. Nothing to download."
  exit 0
fi
exec "$script" "$@"
