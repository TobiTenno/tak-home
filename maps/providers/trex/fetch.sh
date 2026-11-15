#!/usr/bin/env bash
# Cut selected North America regions out of the T.Rex Arms archives.
# pmtiles extract reads only the tiles inside the box. The hillshade
# archive is not clustered, so it cannot be cut. It stays on
# tiles.trex-arms.com.
#
# Interactive: toggleable region checklist, then elevation / sprites prompts.
# Non-interactive:
#   ./maps/fetch.sh --regions ks,mo
#   ./maps/fetch.sh --regions conus --elevation --sprites
#   ./maps/fetch.sh --sprites-only
#
# Sprites are proprietary T.REX ARMS assets. Fetch keeps them under
# maps/data/ (gitignored) for local deploy only — do not commit or redistribute.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
maps=$(cd "$here/../.." && pwd)
regions_file=$here/regions.tsv
mkdir -p "$maps/data"

IMAGE="${PMTILES_IMAGE:-protomaps/go-pmtiles:latest}"
BASE="${TREX_MAPS_BASE:-https://tiles.trex-arms.com/maps}"
SPRITE_BASE="${TREX_SPRITE_BASE:-https://tiles.trex-arms.com/maps/web/2026-11-11b/sprites/topo-print}"
UA="${TREX_UA:-Mozilla/5.0 (compatible; tak-home-fetch/1.0)}"

FEATURES_OUT=features.pmtiles
ELEVATION_OUT=elevation.pmtiles
EXTRACT_META=$maps/data/extract.json

want_elevation=0
want_sprites=0
sprites_only=0
force_extract=0
regions_arg=
noninteractive=0

usage() {
  cat <<'EOF'
Usage: fetch.sh [options]

  --regions id,id,...   Region ids from regions.tsv (skips checklist)
  --elevation           Also extract elevation DEM tiles
  --sprites             Download T.REX sprites into maps/data/sprites/
  --sprites-only        Only download sprites
  --force               Re-extract even if the output file exists
  -h, --help            Show this help

Interactive (no --regions): toggleable checklist. Default selection: ks + mo.
Sprites are proprietary; local deploy only — not for git or redistribution.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --regions)
      [[ $# -ge 2 ]] || { echo "--regions needs a value" >&2; exit 1; }
      regions_arg=$2
      noninteractive=1
      shift 2
      ;;
    --regions=*)
      regions_arg=${1#--regions=}
      noninteractive=1
      shift
      ;;
    --elevation)
      want_elevation=1
      shift
      ;;
    --sprites)
      want_sprites=1
      shift
      ;;
    --sprites-only)
      sprites_only=1
      want_sprites=1
      shift
      ;;
    --force)
      force_extract=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

declare -a REGION_IDS=()
declare -A REGION_LABEL=()
declare -A REGION_BBOX=()
declare -A SELECTED=()
declare -a selected_ids=()

load_regions() {
  [[ -f "$regions_file" ]] || { echo "missing $regions_file" >&2; exit 1; }
  REGION_IDS=()
  while IFS=$'\t' read -r id label bbox || [[ -n "${id:-}" ]]; do
    [[ -z "${id:-}" || "$id" =~ ^# ]] && continue
    REGION_IDS+=("$id")
    REGION_LABEL[$id]=$label
    REGION_BBOX[$id]=$bbox
  done < "$regions_file"
}

compute_bbox() {
  local ids_csv=$1
  python3 - "$regions_file" "$ids_csv" <<'PY'
import sys
path, ids_csv = sys.argv[1], sys.argv[2]
ids = [x.strip() for x in ids_csv.split(",") if x.strip()]
bboxes = {}
for line in open(path):
    line = line.strip()
    if not line or line.startswith("#"):
        continue
    parts = line.split("\t")
    if len(parts) < 3:
        continue
    bboxes[parts[0]] = tuple(map(float, parts[2].split(",")))
missing = [i for i in ids if i not in bboxes]
if missing:
    raise SystemExit("unknown region id(s): " + ", ".join(missing))
if not ids:
    raise SystemExit("no regions selected")
w = min(bboxes[i][0] for i in ids)
s = min(bboxes[i][1] for i in ids)
e = max(bboxes[i][2] for i in ids)
n = max(bboxes[i][3] for i in ids)
print(f"{w:.4f},{s:.4f},{e:.4f},{n:.4f}")
PY
}

interactive_checklist() {
  SELECTED=()
  SELECTED[ks]=1
  SELECTED[mo]=1

  if [[ ! -t 0 ]]; then
    echo "stdin not a TTY. Pass --regions id,id,... (default would be ks,mo)." >&2
    selected_ids=(ks mo)
    return
  fi

  local page=0
  local page_size=20
  local total=${#REGION_IDS[@]}
  local pages=$(( (total + page_size - 1) / page_size ))
  local input

  while true; do
    clear 2>/dev/null || true
    echo "T.Rex NA extract — toggle regions, then Done"
    echo "Assets from tiles.trex-arms.com. Operator responsibility for their terms."
    echo
    local start=$((page * page_size))
    local end=$((start + page_size))
    (( end > total )) && end=$total
    local i
    for ((i=start; i<end; i++)); do
      local id=${REGION_IDS[$i]}
      local mark=" "
      [[ -n ${SELECTED[$id]+x} ]] && mark="x"
      printf " %2d [%s] %-8s %s\n" "$((i+1))" "$mark" "$id" "${REGION_LABEL[$id]}"
    done
    echo
    local count=0
    for id in "${REGION_IDS[@]}"; do
      [[ -n ${SELECTED[$id]+x} ]] && count=$((count+1))
    done
    echo "Selected: $count   page $((page+1))/$pages"
    echo
    echo "Commands:  <n> toggle   a=all-on-page   c=clear-page"
    echo "           n=next page  p=prev page"
    echo "           ksmo / conus / na = presets"
    echo "           d=done       q=quit"
    printf "> "
    read -r input || exit 1
    case "$input" in
      q|Q) echo "aborted"; exit 1 ;;
      d|D|"")
        selected_ids=()
        for id in "${REGION_IDS[@]}"; do
          [[ -n ${SELECTED[$id]+x} ]] && selected_ids+=("$id")
        done
        if [[ ${#selected_ids[@]} -eq 0 ]]; then
          echo "Pick at least one region." >&2
          sleep 1
          continue
        fi
        break
        ;;
      n|N) page=$(( (page + 1) % pages )) ;;
      p|P) page=$(( (page - 1 + pages) % pages )) ;;
      a|A)
        for ((i=start; i<end; i++)); do
          SELECTED[${REGION_IDS[$i]}]=1
        done
        ;;
      c|C)
        for ((i=start; i<end; i++)); do
          unset "SELECTED[${REGION_IDS[$i]}]"
        done
        ;;
      ksmo|KSMO)
        SELECTED=()
        SELECTED[ks]=1
        SELECTED[mo]=1
        page=0
        ;;
      conus|CONUS)
        SELECTED=()
        SELECTED[conus]=1
        ;;
      na|NA)
        SELECTED=()
        SELECTED[na]=1
        ;;
      *)
        if [[ "$input" =~ ^[0-9]+$ ]]; then
          local idx=$((input - 1))
          if (( idx >= 0 && idx < total )); then
            local tid=${REGION_IDS[$idx]}
            if [[ -n ${SELECTED[$tid]+x} ]]; then
              unset "SELECTED[$tid]"
            else
              SELECTED[$tid]=1
            fi
          fi
        else
          local tok
          for tok in ${input//,/ }; do
            [[ -n ${REGION_BBOX[$tok]+x} ]] || continue
            if [[ -n ${SELECTED[$tok]+x} ]]; then
              unset "SELECTED[$tok]"
            else
              SELECTED[$tok]=1
            fi
          done
        fi
        ;;
    esac
  done

  printf "Also extract elevation? [y/N] "
  read -r input || true
  [[ "$input" =~ ^[Yy] ]] && want_elevation=1

  echo
  echo "Sprites are proprietary T.REX ARMS cartography icons."
  echo "Fetched files stay under maps/data/sprites/ (gitignored)."
  echo "Do not commit or redistribute them."
  printf "Download sprites for local deploy? [y/N] "
  read -r input || true
  [[ "$input" =~ ^[Yy] ]] && want_sprites=1
}

fetch_sprites() {
  local dest=$maps/data/sprites
  mkdir -p "$dest"
  echo
  echo "WARNING: T.REX sprites are proprietary. Local deploy only. Not for git/redistribution."
  for ext in json png; do
    local url="${SPRITE_BASE}.${ext}"
    local out="$dest/topo-print.${ext}"
    if [[ -f "$out" && $force_extract -eq 0 ]]; then
      echo "keep sprites/topo-print.${ext}"
      continue
    fi
    echo "get $url"
    curl -fsSL -A "$UA" -o "$out.partial" "$url"
    mv "$out.partial" "$out"
  done
  echo "Sprites at $dest/topo-print.{json,png}"
  echo "URL base: https://<map-host>/pmtiles/sprites/topo-print"
  cat > "$dest/load-in-cloudtak.js" <<'JS'
// Paste in CloudTAK map page DevTools after the map is up.
// Same-origin sprites under /pmtiles/sprites/topo-print
(async () => {
  const base = `${location.origin}/pmtiles/sprites/topo-print`;
  const meta = await (await fetch(`${base}.json`)).json();
  const bmp = await createImageBitmap(await (await fetch(`${base}.png`)).blob());
  const map = window.__map || window.map;
  if (!map || !map.addImage) throw new Error('Set window.__map = mapLibreMapInstance first');
  for (const [id, s] of Object.entries(meta)) {
    const c = document.createElement('canvas');
    c.width = s.width; c.height = s.height;
    c.getContext('2d').drawImage(bmp, s.x, s.y, s.width, s.height, 0, 0, s.width, s.height);
    const data = c.getContext('2d').getImageData(0, 0, s.width, s.height);
    if (!map.hasImage(id)) map.addImage(id, data, { pixelRatio: s.pixelRatio || 1 });
  }
  console.log('loaded', Object.keys(meta).length, 'T.Rex sprite icons');
})();
JS
  echo "Inject helper: $dest/load-in-cloudtak.js"
}

resolve_archives() {
  FEATURES_SRC="na/2026-10-26/na_features.pmtiles"
  ELEVATION_SRC="na/2026-10-25/na_elevation.pmtiles"
  if curl -fsSL -A "$UA" "$BASE/zones.json" -o "$maps/data/.zones.json" 2>/dev/null; then
    local resolved f e
    resolved=$(python3 - "$maps/data/.zones.json" <<'PY'
import json,sys
z=json.load(open(sys.argv[1]))
for zone in z.get("zones", []):
    if zone.get("id")=="na":
        print(zone.get("features",""))
        print(zone.get("elevation",""))
        break
PY
)
    f=$(printf '%s\n' "$resolved" | sed -n '1p')
    e=$(printf '%s\n' "$resolved" | sed -n '2p')
    [[ -n "$f" ]] && FEATURES_SRC=$f
    [[ -n "$e" ]] && ELEVATION_SRC=$e
  fi
  rm -f "$maps/data/.zones.json"
}

extract() {
  local src=$1 dest=$2 bbox=$3
  if [[ -f "$maps/data/$dest" && $force_extract -eq 0 ]]; then
    echo "keep data/$dest (use --force to redo)"
    return
  fi
  echo "extract $src -> data/$dest  bbox=$bbox"
  docker run --rm -v "$maps/data:/data" "$IMAGE" \
    extract "$BASE/$src" "/data/$dest" \
    --bbox="$bbox" \
    --download-threads=8
}

update_basemap() {
  local labels=$1
  local basemap=$maps/basemap.json
  [[ -f "$basemap" ]] || return 0
  python3 - "$basemap" "$FEATURES_OUT" "$labels" <<'PY'
import json, sys
path, features, labels = sys.argv[1:4]
doc = json.load(open(path))
url = doc.get("url", "")
if "/pmtiles/" in url:
    base = url.rsplit("/", 1)[0]
    doc["url"] = f"{base}/{features}"
doc["name"] = f"T.Rex {labels}" if labels else doc.get("name", "T.Rex")
json.dump(doc, open(path, "w"), indent=2)
open(path, "a").write("\n")
print(f"Basemap URL -> {doc['url']}")
print(f"Basemap name -> {doc['name']}")
PY
}

write_meta() {
  local bbox=$1
  python3 - "$EXTRACT_META" "$bbox" "$want_sprites" "${selected_ids[@]}" <<'PY'
import json, sys
path, bbox, sprites_flag, *ids = sys.argv[1:]
json.dump({
  "regions": ids,
  "bbox": bbox,
  "features": "features.pmtiles",
  "elevation": "elevation.pmtiles",
  "sprites_downloaded": sprites_flag == "1",
  "sprites": "sprites/topo-print",
  "source": "tiles.trex-arms.com",
  "note": "Extracted tiles and sprites may be subject to T.REX ARMS terms. Do not redistribute proprietary assets from this tree.",
}, open(path, "w"), indent=2)
open(path, "a").write("\n")
PY
}

# --- main ---

load_regions

if [[ $sprites_only -eq 1 ]]; then
  fetch_sprites
  exit 0
fi

if [[ $noninteractive -eq 1 ]]; then
  IFS=',' read -r -a raw_ids <<< "$regions_arg"
  selected_ids=()
  for id in "${raw_ids[@]}"; do
    id=${id// /}
    [[ -z "$id" ]] && continue
    [[ -n ${REGION_BBOX[$id]+x} ]] || { echo "unknown region: $id" >&2; exit 1; }
    selected_ids+=("$id")
  done
  [[ ${#selected_ids[@]} -gt 0 ]] || { echo "--regions needs at least one id" >&2; exit 1; }
else
  interactive_checklist
fi

ids_csv=$(IFS=,; echo "${selected_ids[*]}")
BBOX=$(compute_bbox "$ids_csv")
labels=$ids_csv

echo
echo "Regions: $ids_csv"
echo "BBox:    $BBOX"
echo "Elevation: $([[ $want_elevation -eq 1 ]] && echo yes || echo no)"
echo "Sprites:   $([[ $want_sprites -eq 1 ]] && echo yes || echo no)"
echo

resolve_archives
extract "$FEATURES_SRC" "$FEATURES_OUT" "$BBOX"

if [[ $want_elevation -eq 1 ]]; then
  extract "$ELEVATION_SRC" "$ELEVATION_OUT" "$BBOX"
fi

if [[ $want_sprites -eq 1 ]]; then
  fetch_sprites
fi

write_meta "$BBOX"
update_basemap "$labels"

echo
ls -lh "$maps/data"/*.pmtiles 2>/dev/null || true
[[ -d $maps/data/sprites ]] && ls -lh "$maps/data/sprites"/topo-print.* 2>/dev/null || true
echo "Meta: $EXTRACT_META"
echo "Basemap file: $maps/basemap.json"
echo "Hosted (Garage): ./maps/publish-garage.sh"
echo "  keep old Hosted name: ./maps/publish-garage.sh --as ks-mo-features features.pmtiles"
