#!/usr/bin/env bash
# Cut Kansas and Missouri out of the T.Rex Arms North America archives.
# pmtiles extract reads only the tiles inside the box. The hillshade
# archive is not clustered, so it cannot be cut. It stays on
# tiles.trex-arms.com.
set -euo pipefail
maps=$(cd "$(dirname "$0")/../.." && pwd)
mkdir -p "$maps/data"

# West, south, east, north. Padded past the state lines.
BBOX="-102.10,35.95,-89.05,40.65"
IMAGE="${PMTILES_IMAGE:-protomaps/go-pmtiles:latest}"
BASE="https://tiles.trex-arms.com/maps"

extract() {
  local src="$1" dest="$2"
  if [[ -f "$maps/data/$dest" ]]; then
    echo "keep data/$dest"
    return
  fi
  echo "extract $src -> data/$dest"
  docker run --rm -v "$maps/data:/data" "$IMAGE" \
    extract "$BASE/$src" "/data/$dest" \
    --bbox="$BBOX" \
    --download-threads=8
}

extract "na/2026-10-26/na_features.pmtiles" "ks-mo-features.pmtiles"

if [[ "${1:-}" == "--elevation" ]]; then
  extract "na/2026-10-25/na_elevation.pmtiles" "ks-mo-elevation.pmtiles"
fi

echo
ls -lh "$maps/data"/*.pmtiles
echo "Basemap file: $maps/basemap.json"
