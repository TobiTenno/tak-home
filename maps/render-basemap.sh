#!/usr/bin/env bash
# Rebuild maps/basemap.json from the provider template (full replace, not a
# half-patch). Use this on the server after updating providers/*/basemap.json.template.
#
#   ./maps/render-basemap.sh --map-host map.example.com
#   ./maps/render-basemap.sh --hosted --tiles-host tiles.example.com --name ks-mo-features
#   ./maps/render-basemap.sh --hosted --out maps/basemap.hosted.json
set -euo pipefail

maps=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$maps/.." && pwd)

provider=
map_host=
tiles_host=
mode=pmtiles          # pmtiles | hosted
features=features     # object / file stem (no .pmtiles)
out=
name_override=

usage() {
  cat <<'EOF'
Usage: render-basemap.sh [options]

  --map-host HOST       map.<domain> (required for pmtiles; guessed from existing file)
  --tiles-host HOST     tiles.<domain> (required for --hosted)
  --hosted              CloudTAK Hosted URL under tiles host
  --pmtiles             Local /pmtiles/<features>.pmtiles on map host (default)
  --features STEM       Default: features  (Hosted often: ks-mo-features)
  --name LABEL          Basemap display name
  --provider NAME       Default: maps/provider or trex
  --out PATH            Default: maps/basemap.json (hosted default: maps/basemap.hosted.json)
  -h, --help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --map-host) map_host=$2; shift 2 ;;
    --map-host=*) map_host=${1#*=}; shift ;;
    --tiles-host) tiles_host=$2; shift 2 ;;
    --tiles-host=*) tiles_host=${1#*=}; shift ;;
    --hosted) mode=hosted; shift ;;
    --pmtiles) mode=pmtiles; shift ;;
    --features) features=$2; shift 2 ;;
    --features=*) features=${1#*=}; shift ;;
    --name) name_override=$2; shift 2 ;;
    --name=*) name_override=${1#*=}; shift ;;
    --provider) provider=$2; shift 2 ;;
    --provider=*) provider=${1#*=}; shift ;;
    --out) out=$2; shift 2 ;;
    --out=*) out=${1#*=}; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
  esac
done

features=${features%.pmtiles}

if [[ -z "$provider" ]]; then
  if [[ -f "$maps/provider" ]]; then
    provider=$(cat "$maps/provider")
  else
    provider=trex
  fi
fi

template=$maps/providers/$provider/basemap.json.template
[[ -f "$template" ]] || { echo "missing template: $template" >&2; exit 1; }

# Guess hosts from existing basemap / cloudtak.env / SWAG conf
guess_host() {
  local kind=$1 # map|tiles
  local f
  for f in "$maps/basemap.json" "$maps/basemap.hosted.json" "$root/config/cloudtak.env" "$root/swag/cloudtak.conf"; do
    [[ -f "$f" ]] || continue
    if [[ $kind == map ]]; then
      grep -Eo 'https://map\.[^/"[:space:]]+' "$f" 2>/dev/null | head -1 | sed 's|https://||' && return
      grep -Eo 'map\.[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}' "$f" 2>/dev/null | head -1 && return
    else
      grep -Eo 'https://tiles\.[^/"[:space:]]+' "$f" 2>/dev/null | head -1 | sed 's|https://||' && return
      grep -Eo 'tiles\.[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}' "$f" 2>/dev/null | head -1 && return
    fi
  done
  return 1
}

if [[ -z "$map_host" ]]; then
  map_host=$(guess_host map || true)
fi
if [[ -z "$tiles_host" ]]; then
  tiles_host=$(guess_host tiles || true)
fi

if [[ "$mode" == pmtiles ]]; then
  [[ -n "$map_host" ]] || {
    echo "Need --map-host map.example.com (could not guess)" >&2
    exit 1
  }
  out=${out:-$maps/basemap.json}
else
  [[ -n "$tiles_host" ]] || {
    echo "Need --tiles-host tiles.example.com for --hosted (could not guess)" >&2
    exit 1
  }
  out=${out:-$maps/basemap.hosted.json}
  # Hosted often keeps legacy object name
  if [[ "$features" == features && -z "${FEATURES_SET:-}" ]]; then
    : # allow features; user can pass --features ks-mo-features
  fi
fi

data_dir=$maps/data
mkdir -p "$data_dir"

python3 - "$template" "$out" "$mode" "$map_host" "$tiles_host" "$features" "$name_override" "$data_dir" <<'PY'
import json, os, sys
template, out, mode, map_host, tiles_host, features, name_override, data_dir = sys.argv[1:9]
doc = json.loads(open(template).read())

if mode == "pmtiles":
    # Local nginx /pmtiles archive (not a CloudTAK Basemap_Protocol enum value).
    doc["protocol"] = "pmtiles"
    doc["url"] = f"https://{map_host}/pmtiles/{features}.pmtiles"
    default_name = "T.Rex" if features == "features" else f"T.Rex {features}"
    patch = None
else:
    doc["protocol"] = "hosted"
    # CloudTAK Hosted URLs must use {$z}/{$x}/{$y} (dollar). Plain {z}
    # gets mangled and TileJSON ends up as /api/basemap/??tiles → 400.
    doc["url"] = (
        f"https://{tiles_host}/tiles/public/{features}/tiles/{{$z}}/{{$x}}/{{$y}}.mvt"
    )
    default_name = f"T.Rex {features}"
    patch = {
        "protocol": "hosted",
        "type": "vector",
        "name": name_override or default_name,
        "url": doc["url"],
        "tilejson": f"https://{tiles_host}/tiles/public/{features}",
        "minzoom": doc.get("minzoom", 0),
        "maxzoom": doc.get("maxzoom", 13),
        "attribution": doc.get("attribution"),
        "styles": doc.get("styles") or [],
    }

doc["name"] = name_override or default_name
doc["type"] = doc.get("type") or "vector"
doc["overlay"] = bool(doc.get("overlay", False))

for layer in doc.get("styles") or []:
    if layer.get("type") == "background":
        continue
    layer["source"] = "basemap"

if patch is not None:
    patch["styles"] = doc["styles"]
    patch["name"] = doc["name"]

json.dump(doc, open(out, "w"), indent=2)
open(out, "a").write("\n")
print(f"wrote {out}")
print(f"  name     {doc['name']}")
print(f"  protocol {doc['protocol']}")
print(f"  url      {doc['url']}")
print(f"  styles   {len(doc.get('styles') or [])}")

if patch is not None:
    patch_path = out.rsplit(".", 1)[0] + ".patch.json"
    json.dump(patch, open(patch_path, "w"))
    open(patch_path, "a").write("\n")
    # Also under maps/data so CloudTAK same-origin can fetch /pmtiles/<file>
    data_patch = os.path.join(data_dir, os.path.basename(patch_path))
    json.dump(patch, open(data_patch, "w"))
    open(data_patch, "a").write("\n")
    print(f"wrote {patch_path}")
    print(f"wrote {data_patch}  (fetch as /pmtiles/{os.path.basename(data_patch)})")
PY
