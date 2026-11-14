#!/usr/bin/env bash
# ./setup.sh example.com -f ../docker-compose.yml
# ./setup.sh -h example.com --file ../docker-compose.yml -p trex
#
# HOSTNAME is the parent name. This writes, under tak-home/ next to the
# compose file given with -f:
#   map.example.com     CloudTAK
#   tiles.example.com   CloudTAK tiles
#   tak.example.com     ATAK. This name goes on the server certificate.
#
# Without -f, files are written in this directory.
set -euo pipefail

src=$(cd "$(dirname "$0")" && pwd)

usage() {
  echo "Usage: ./setup.sh [HOSTNAME] [-h HOSTNAME] [-f COMPOSE_FILE] [-p PROVIDER]" >&2
  echo "       ./setup.sh example.com -f ../docker-compose.yml" >&2
  echo "       ./setup.sh example.com -p opentopomap" >&2
  echo "Providers:" >&2
  local d
  for d in "$src/maps/providers"/*; do
    [[ -f "$d/basemap.json.template" ]] || continue
    echo "  $(basename "$d")" >&2
  done
}

die() {
  echo "$1" >&2
  exit 1
}

host=""
compose_file=""
provider="trex"
positionals=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--host)
      [[ $# -ge 2 && "$2" != -* ]] || die "$1 needs a hostname"
      host=$2
      shift 2
      ;;
    --host=*)
      host=${1#--host=}
      [[ -n "$host" ]] || die "--host needs a hostname"
      shift
      ;;
    -f|--file)
      [[ $# -ge 2 && "$2" != -* ]] || die "$1 needs a compose file"
      compose_file=$2
      shift 2
      ;;
    --file=*)
      compose_file=${1#--file=}
      [[ -n "$compose_file" ]] || die "--file needs a compose file"
      shift
      ;;
    -p|--provider)
      [[ $# -ge 2 && "$2" != -* ]] || die "$1 needs a provider name"
      provider=$2
      shift 2
      ;;
    --provider=*)
      provider=${1#--provider=}
      [[ -n "$provider" ]] || die "--provider needs a provider name"
      shift
      ;;
    --help)
      usage
      exit 0
      ;;
    --)
      shift
      positionals+=("$@")
      break
      ;;
    -*)
      die "Unknown option: $1"
      ;;
    *)
      positionals+=("$1")
      shift
      ;;
  esac
done

if [[ -z "$host" ]]; then
  [[ ${#positionals[@]} -ge 1 ]] || { usage; exit 1; }
  host=${positionals[0]}
  unset 'positionals[0]'
fi
if [[ ${#positionals[@]} -gt 0 ]]; then
  die "Unexpected argument: ${positionals[*]}"
fi

host=$(echo "$host" | tr '[:upper:]' '[:lower:]' | sed 's/\.$//')
if [[ "$host" == *"://"* || "$host" == */* ]]; then
  die "Pass the bare name, for example example.com"
fi
if [[ ! "$host" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$ ]]; then
  die "HOSTNAME should look like example.com"
fi
if [[ ! "$provider" =~ ^[a-z0-9][a-z0-9-]*$ || ! -f "$src/maps/providers/$provider/basemap.json.template" ]]; then
  usage
  die "Unknown provider: $provider"
fi

if [[ -n "$compose_file" ]]; then
  compose_file=$(cd "$(dirname "$compose_file")" && pwd)/$(basename "$compose_file")
  root=$(dirname "$compose_file")/tak-home
else
  root=$src
fi
mkdir -p "$root"

if [[ "$root" != "$src" ]]; then
  mkdir -p "$root/config/federation" "$root/init" "$root/maps" "$root/swag"
  cp "$src/compose.yaml" "$src/garage.toml" \
    "$src/setup.sh" "$src/make-datapackage.sh" "$src/README.md" "$root/"
  cp "$src/init/"*.sh "$root/init/"
  cp "$src/config/takserver.env.template" "$src/config/secrets.env.example" \
    "$src/config/cloudtak.env.template" "$root/config/"
  touch "$root/config/federation/.gitkeep"
  rm -f "$root/maps/extract-ks-mo.sh" "$root/maps/ks-mo-features-basemap.json.template"
  rm -rf "$root/maps/providers"
  cp -a "$src/maps/providers" "$root/maps/"
  cp "$src/maps/nginx.conf" "$src/maps/fetch.sh" "$root/maps/"
  cp "$src/swag/cloudtak.conf.template" "$root/swag/"
  chmod +x "$root/make-datapackage.sh" "$root/maps/fetch.sh"
  chmod +x "$root/maps/providers/"*/fetch.sh 2>/dev/null || true
fi

map_host=map.$host
tiles_host=tiles.$host
tak_host=tak.$host

cd "$root"

if [[ ! -f config/takserver.env ]]; then
  cp config/takserver.env.template config/takserver.env
fi
sed -i "s|^SERVER_ADDRESSES=.*|SERVER_ADDRESSES=localhost takserver $tak_host|" config/takserver.env

secrets=config/secrets.env
if [[ -f "$secrets" ]]; then
  echo "Passwords:   keeping existing $secrets"
else
  umask 077
  while IFS= read -r line; do
    if [[ "$line" =~ ^([A-Z_]+)=$ ]]; then
      echo "${BASH_REMATCH[1]}=$(openssl rand -hex 16)"
    else
      echo "$line"
    fi
  done < config/secrets.env.example > "$secrets"
  umask 022
  echo "Passwords:   created $secrets"
fi

users=$(grep -E '^USERS=' config/takserver.env | cut -d= -f2-)
for user in $users; do
  key="USER_PASS_$(echo "$user" | tr '[:lower:]-' '[:upper:]_')"
  if ! grep -q "^$key=" "$secrets"; then
    echo "$key=Tak!$(openssl rand -hex 6)" >> "$secrets"
    echo "Passwords:   created a password for $user"
  fi
done

if [[ -f config/cloudtak.env ]]; then
  sed -i "s|^API_URL=.*|API_URL=https://$map_host|" config/cloudtak.env
  sed -i "s|^PMTILES_URL=.*|PMTILES_URL=https://$tiles_host|" config/cloudtak.env
  echo "CloudTAK:    updated URLs in config/cloudtak.env"
else
  umask 077
  access_key=tak$(openssl rand -hex 8)
  sed \
    -e "s|@SIGNING_SECRET@|$(openssl rand -hex 32)|" \
    -e "s|@GARAGE_RPC_SECRET@|$(openssl rand -hex 32)|" \
    -e "s|@ACCESS_KEY@|$access_key|g" \
    -e "s|@SECRET_KEY@|$(openssl rand -hex 32)|" \
    -e "s|@API_URL@|https://$map_host|" \
    -e "s|@PMTILES_URL@|https://$tiles_host|" \
    config/cloudtak.env.template > config/cloudtak.env
  umask 022
  echo "CloudTAK:    created config/cloudtak.env"
fi

sed \
  -e "s|@MAP_HOST@|$map_host|g" \
  -e "s|@TILES_HOST@|$tiles_host|g" \
  swag/cloudtak.conf.template > swag/cloudtak.conf

printf '%s\n' "$provider" > maps/provider
sed "s|@MAP_HOST@|$map_host|g" \
  "maps/providers/$provider/basemap.json.template" > maps/basemap.json

if [[ -n "$compose_file" ]]; then
  printf '%s\n' "$compose_file" > .compose-file
  python3 - "$compose_file" "$root/compose.yaml" <<'PY'
import os, sys
compose_file, included = sys.argv[1], sys.argv[2]
base = os.path.dirname(os.path.abspath(compose_file))
rel = os.path.relpath(os.path.abspath(included), base).replace(os.sep, "/")
text = open(compose_file).read() if os.path.exists(compose_file) else ""
if f"path: {rel}" in text or f"path: \"{rel}\"" in text:
    print(f"Compose:     {compose_file} already includes {rel}")
    sys.exit(0)
item = f"  - path: {rel}\n"
if not text.strip():
    open(compose_file, "w").write(f"include:\n{item}")
elif text.startswith("include:"):
    lines = text.splitlines(keepends=True)
    out = []
    inserted = False
    for line in lines:
        out.append(line)
        if not inserted and line.startswith("include:"):
            out.append(item)
            inserted = True
    open(compose_file, "w").write("".join(out))
else:
    if not text.endswith("\n"):
        text += "\n"
    open(compose_file, "w").write(f"include:\n{item}\n{text}")
print(f"Compose:     included {rel} from {compose_file}")
PY
fi

echo
echo "Directory    $root"
echo "Provider     $provider"
echo "Basemap      $root/maps/basemap.json"
echo "CloudTAK     https://$map_host"
echo "Tiles        https://$tiles_host"
echo "ATAK         $tak_host:8089"
echo "SWAG file    $root/swag/cloudtak.conf"
echo
echo "Point DNS for $map_host and $tiles_host at SWAG."
echo "Point DNS for $tak_host at the machine that publishes 8089."
echo "The certificate must cover $map_host and $tiles_host before the first start."
if [[ -f "maps/providers/$provider/fetch.sh" ]]; then
  echo "Fetch tiles with ./maps/fetch.sh"
fi
