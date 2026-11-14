#!/usr/bin/env bash
# Run from this directory, or from the compose project that includes compose.yaml.
#
#   ./make-datapackage.sh <server address>
#   ./make-datapackage.sh --with-cert <user> <server address>
set -euo pipefail
cd "$(dirname "$0")"
if [[ -f .compose-file ]]; then
  compose=(docker compose -f "$(cat .compose-file)" --profile tak)
else
  compose=(docker compose --profile tak)
fi

usage() {
  echo "Usage: ./make-datapackage.sh <server address>" >&2
  echo "       ./make-datapackage.sh --with-cert <user> <server address>" >&2
  exit 1
}

user=""
if [[ "${1:-}" == "--with-cert" ]]; then
  user=${2:-}; address=${3:-}
  [[ -n "$user" && -n "$address" ]] || usage
else
  address=${1:-}
  [[ -n "$address" ]] || usage
fi

if ! "${compose[@]}" ps --status running --services 2>/dev/null | grep -qx tak_server; then
  echo "tak_server is not running." >&2
  exit 1
fi

if [[ -n "$user" ]] && ! "${compose[@]}" exec -T tak_server test -f "/opt/tak/certs/files/$user.p12"; then
  echo "No certificate for '$user'. Add it to CLIENT_CERTS in config/takserver.env, then start the profile again." >&2
  exit 1
fi

name=${user:-enroll}-$address
mkdir -p datapackages

"${compose[@]}" exec -T -e DP_USER="$user" -e DP_ADDRESS="$address" -e DP_NAME="$name" tak_server python3 - <<'PY'
import os, uuid, zipfile
user, address, name = os.environ["DP_USER"], os.environ["DP_ADDRESS"], os.environ["DP_NAME"]
files = "/opt/tak/certs/files"

stream = f"""    <entry key="count" class="class java.lang.Integer">1</entry>
    <entry key="description0" class="class java.lang.String">TAK Server</entry>
    <entry key="enabled0" class="class java.lang.Boolean">true</entry>
    <entry key="connectString0" class="class java.lang.String">{address}:8089:ssl</entry>
    <entry key="caLocation0" class="class java.lang.String">cert/truststore.p12</entry>
    <entry key="caPassword0" class="class java.lang.String">{os.environ["CA_PASS"]}</entry>"""
app = """    <entry key="displayServerConnectionWidget" class="class java.lang.Boolean">true</entry>"""
contents = ["certs/server.pref", "certs/truststore.p12"]

if user:
    stream += f"""
    <entry key="certificateLocation0" class="class java.lang.String">cert/{user}.p12</entry>
    <entry key="clientPassword0" class="class java.lang.String">{os.environ["CLIENT_CERT_PASS"]}</entry>"""
    contents.append(f"certs/{user}.p12")
else:
    stream += """
    <entry key="enrollForCertificateWithTrust0" class="class java.lang.Boolean">true</entry>
    <entry key="enrollUseTrust0" class="class java.lang.Boolean">true</entry>
    <entry key="useAuth0" class="class java.lang.Boolean">true</entry>
    <entry key="cacheCreds0" class="class java.lang.String">Cache credentials</entry>"""

server_pref = f"""<?xml version='1.0' encoding='ASCII' standalone='yes'?>
<preferences>
  <preference version="1" name="cot_streams">
{stream}
  </preference>
  <preference version="1" name="com.atakmap.app_preferences">
{app}
  </preference>
</preferences>
"""
entries = "\n".join(f'    <Content ignore="false" zipEntry="{c}"/>' for c in contents)
manifest = f"""<MissionPackageManifest version="2">
  <Configuration>
    <Parameter name="uid" value="{uuid.uuid4()}"/>
    <Parameter name="name" value="{name}"/>
    <Parameter name="onReceiveDelete" value="true"/>
  </Configuration>
  <Contents>
{entries}
  </Contents>
</MissionPackageManifest>
"""
with zipfile.ZipFile(f"/tmp/{name}.zip", "w", zipfile.ZIP_DEFLATED) as z:
    z.writestr("MANIFEST/manifest.xml", manifest)
    z.writestr("certs/server.pref", server_pref)
    z.write(f"{files}/truststore-active.p12", "certs/truststore.p12")
    if user:
        z.write(f"{files}/{user}.p12", f"certs/{user}.p12")
PY
"${compose[@]}" cp "tak_server:/tmp/$name.zip" "datapackages/$name.zip" >/dev/null
"${compose[@]}" exec -T tak_server rm -f "/tmp/$name.zip"
echo "Created datapackages/$name.zip"
