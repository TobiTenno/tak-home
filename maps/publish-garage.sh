#!/usr/bin/env bash
# Push maps/data/*.pmtiles into Garage for CloudTAK Hosted tilesets.
# Objects land at s3://cloudtak/public/<name>.pmtiles
# (tile URL shape: …/tiles/public/<name>/tiles/{z}/{x}/{y}.mvt).
#
# Requires: docker, network `tak`, running tak_store, config/cloudtak.env
#
#   ./maps/publish-garage.sh
#   ./maps/publish-garage.sh features.pmtiles elevation.pmtiles
#   ./maps/publish-garage.sh --as ks-mo-features features.pmtiles
set -euo pipefail

maps=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$maps/.." && pwd)
envfile=$root/config/cloudtak.env
data=$maps/data
py=$maps/publish_garage.py
network="${TAK_NETWORK:-tak}"
prefix=public

as_name=
files=()
restart_tiles=1

usage() {
  cat <<'EOF'
Usage: publish-garage.sh [options] [file.pmtiles ...]

  (no files)     Upload every *.pmtiles under maps/data/
  --as NAME      Object key public/NAME.pmtiles (one file only)
  --no-restart   Do not restart tak_tiles after upload
  -h, --help     Show help

Reads AWS_S3_* from config/cloudtak.env. Uploads via docker on network tak
to http://tak-store:3900 (boto3 rejects hostnames with underscores).

Restarts tak_tiles by default so its in-memory PMTiles/ETag cache drops
the old object (stale IfMatch → Garage 412 → tiles 500).
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --as)
      [[ $# -ge 2 ]] || { echo "--as needs a name" >&2; exit 1; }
      as_name=$2
      shift 2
      ;;
    --as=*)
      as_name=${1#--as=}
      shift
      ;;
    --no-restart)
      restart_tiles=0
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -*)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
    *)
      files+=("$1")
      shift
      ;;
  esac
done

[[ -f "$envfile" ]] || { echo "missing $envfile — run setup.sh first" >&2; exit 1; }
[[ -f "$py" ]] || { echo "missing $py" >&2; exit 1; }
[[ -d "$data" ]] || { echo "missing $data — run ./maps/fetch.sh first" >&2; exit 1; }

access=$(grep -E '^AWS_S3_AccessKeyId=' "$envfile" | head -1 | cut -d= -f2- | tr -d '\r')
secret=$(grep -E '^AWS_S3_SecretAccessKey=' "$envfile" | head -1 | cut -d= -f2- | tr -d '\r')
bucket=$(grep -E '^ASSET_BUCKET=' "$envfile" | head -1 | cut -d= -f2- | tr -d '\r')
bucket=${bucket:-$(grep -E '^GARAGE_DEFAULT_BUCKET=' "$envfile" | head -1 | cut -d= -f2- | tr -d '\r')}
bucket=${bucket:-cloudtak}

[[ -n "$access" && -n "$secret" ]] || {
  echo "AWS_S3_AccessKeyId / AWS_S3_SecretAccessKey missing in cloudtak.env" >&2
  exit 1
}

if [[ ${#files[@]} -eq 0 ]]; then
  shopt -s nullglob
  for f in "$data"/*.pmtiles; do
    files+=("$(basename "$f")")
  done
  shopt -u nullglob
fi

[[ ${#files[@]} -gt 0 ]] || { echo "no .pmtiles under $data" >&2; exit 1; }

if [[ -n "$as_name" && ${#files[@]} -ne 1 ]]; then
  echo "--as only works with a single file" >&2
  exit 1
fi

pairs=()
mounts=(-v "$data:/data:ro" -v "$py:/publish_garage.py:ro")
i=0
for f in "${files[@]}"; do
  if [[ "$f" == /* ]]; then
    path=$f
  elif [[ -f "$data/$f" ]]; then
    path=$data/$f
  elif [[ -f "$f" ]]; then
    path=$(cd "$(dirname "$f")" && pwd)/$(basename "$f")
  else
    echo "not found: $f" >&2
    exit 1
  fi
  base=$(basename "$path")
  [[ "$base" == *.pmtiles ]] || { echo "not a .pmtiles file: $path" >&2; exit 1; }
  if [[ -n "$as_name" ]]; then
    key=$prefix/${as_name%.pmtiles}.pmtiles
  else
    key=$prefix/$base
  fi
  if [[ "$path" == "$data"/* ]]; then
    src=/data/$(basename "$path")
  else
    src=/extra/$i.pmtiles
    mounts+=(-v "$path:$src:ro")
  fi
  pairs+=("$src|$key")
  echo "  $(basename "$path")  ($(du -h "$path" | awk '{print $1}')) -> s3://$bucket/$key"
  i=$((i + 1))
done

if ! docker network inspect "$network" >/dev/null 2>&1; then
  echo "docker network '$network' missing — start the TAK stack first" >&2
  exit 1
fi
if ! docker inspect tak_store >/dev/null 2>&1; then
  echo "container tak_store not found — start tak_store first" >&2
  exit 1
fi

echo
echo "Endpoint http://tak-store:3900 (network $network)"
echo

docker run --rm --network "$network" \
  "${mounts[@]}" \
  -e "AWS_ACCESS_KEY_ID=$access" \
  -e "AWS_SECRET_ACCESS_KEY=$secret" \
  -e "BUCKET=$bucket" \
  python:3.12-slim \
  bash -c 'pip install -q boto3 && python /publish_garage.py "$@"' \
  bash "${pairs[@]}"

if [[ $restart_tiles -eq 1 ]]; then
  if docker inspect tak_tiles >/dev/null 2>&1; then
    echo
    echo "Restart tak_tiles (drop stale PMTiles/ETag cache)..."
    docker restart tak_tiles >/dev/null
    echo "tak_tiles restarted"
  else
    echo
    echo "warn: tak_tiles not running — restart it after upload or TileJSON may 500 (412 ETag)"
  fi
fi

echo
echo "Hosted basemap URL pattern:"
echo "  https://tiles.<domain>/tiles/public/<name>/tiles/{\$z}/{\$x}/{\$y}.mvt"
echo "where <name> is the file basename without .pmtiles (e.g. features)."
echo "If you still use the old Hosted name:  ./maps/publish-garage.sh --as ks-mo-features features.pmtiles"
