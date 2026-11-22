# tak-home

<p align="center">
  <img src="docs/logo.png" alt="tak-home" width="128" height="128" />
</p>

Docs site: [tobitenno.github.io/tak-home](https://tobitenno.github.io/tak-home/) · [setup guide](docs/setup-guide.html) · [auth plan](docs/auth-plan.html) · [dev move](docs/dev-move.html) · [references](docs/references.html) · [security](docs/security.html).

Copy this directory to the server. One argument sets the public names:

```sh
./setup.sh example.com -f ../docker-compose.yml
./setup.sh -h example.com --file ../docker-compose.yml
./setup.sh example.com -p opentopomap
```

`-p` picks the map provider. The default is `trex`. A provider is `maps/providers/<name>/basemap.json.template`. Add `fetch.sh` there when the tiles have to be downloaded into `maps/data`. `./maps/fetch.sh` runs that script. `opentopomap` is a remote ZXY layer and has nothing to download.

`-f` is the compose file to include this stack in. Generated files go in `tak-home/` next to that file, not in the compose file's own directory. The include Compose adds is `tak-home/compose.yaml`, and volume paths inside it stay relative to that file.

That writes:

| Name | Use |
| --- | --- |
| `map.example.com` | CloudTAK |
| `tiles.example.com` | CloudTAK tiles |
| `tak.example.com` | ATAK, port 8089 |

`tak.example.com` is added to the TAK server certificate (private CA). Point `map`, `tiles`, and `tak` at SWAG.

Two certificate worlds. Keep them apart:

| Name | Port | Certificate |
| --- | --- | --- |
| `map.example.com`, `tiles.example.com` | 443 | SWAG Let's Encrypt |
| `tak.example.com` | 8089, 8443, 8446, **9473** (federation v2) | TAK private CA (stream passthrough) |

Federation uses **9473** (not 9001) so host 9001 stays free (e.g. Mosquitto WebSockets).

SWAG `SUBDOMAINS` / `EXTRA_DOMAINS` should list `map` and `tiles` only. Leave `tak` out of Let's Encrypt. Do not copy TAK `*.pem` / `*.p12` into SWAG `/config/keys`.

This stack publishes no host ports. Every service is on Docker network `tak` (`name: tak`). Add the SWAG service to that network and publish the proxy ports there:

```yaml
services:
  swag:
    networks:
      - tak
    ports:
      - "443:443"
      - "8089:8089"
      - "8443:8443"
      - "8446:8446"
      - "9473:9473"
networks:
  tak:
    name: tak
```

A separate compose file uses the same network with `external: true`. Copy paths matter:

| File | SWAG directory |
| --- | --- |
| `swag/cloudtak.conf` | `/config/nginx/site-confs/` |
| `swag/tak-stream.conf` | `/config/nginx/stream-confs/` |

Do not put `tak-stream.conf` in `site-confs`. That directory is HTTP only; nginx will reject `proxy_pass` there. The stream file forwards 8089, 8443, 8446, and 9473 to `tak_server` without decrypting them.

SWAG dropped the stock stream include. In `/config/nginx/nginx.conf`, add a top-level block (next to `http`, not inside it):

```nginx
stream {
    include /config/nginx/stream-confs/*.conf;
}
```

Then `docker exec swag nginx -t` and restart SWAG. Confirm `netstat` inside SWAG shows 8089/8443/8446, not only 443.

Running `./setup.sh` again with the same or a new parent name rewrites those hostnames and keeps the passwords already in `config/secrets.env` and `config/cloudtak.env`.

From the directory that contains the compose file you passed to `-f`.

`--profile tak` adds this stack to every service that has no profile. Name the services and Compose starts only those:

```sh
docker compose -f docker-compose.yml up -d tak_certs tak_database tak_server
docker compose -f docker-compose.yml cp tak_server:/opt/tak/certs/files/root-ca.pem tak-home/tak-ca.pem
docker compose -f docker-compose.yml up -d \
  tak_certs tak_database tak_server tak_api tak_tiles tak_events \
  tak_retention tak_media tak_postgis tak_store tak_pmtiles
```

Tiles, on the server, when the chosen provider has a `fetch.sh`:

```sh
./maps/fetch.sh
```

For `trex`, that opens a toggleable North America region checklist (default Kansas + Missouri), then asks about elevation and sprites. Non-interactive:

```sh
./maps/fetch.sh --regions ks,mo,ar
./maps/fetch.sh --regions conus --elevation
./maps/fetch.sh --sprites-only
```

Region ids live in `maps/providers/trex/regions.tsv` (states, provinces, `conus`, `na`, `ksmo`). Output is `maps/data/features.pmtiles` (and optional `elevation.pmtiles`). Sprites go to `maps/data/sprites/` and are gitignored — proprietary T.REX ARMS assets for local deploy only; do not commit or redistribute. CloudTAK does not auto-load them; use the helper script fetch writes under that folder.

Rebuild basemap JSON from the template on the **server** (generated `*.hosted*.json` is gitignored — do not expect it from git):

```sh
./maps/render-basemap.sh --map-host map.example.com
./maps/render-basemap.sh --hosted --tiles-host tiles.example.com --features ks-mo-features
# writes maps/basemap.hosted.json + maps/basemap.hosted.patch.json
# and maps/data/basemap.hosted.patch.json → https://map…/pmtiles/basemap.hosted.patch.json
```

Push extracts into Garage for CloudTAK **Hosted** tilesets (`tak_store` must be up):

```sh
./maps/publish-garage.sh
./maps/publish-garage.sh --as ks-mo-features features.pmtiles
```

That writes `s3://cloudtak/public/<name>.pmtiles` and restarts `tak_tiles` so its ETag cache does not 412/500 on the new object (`--no-restart` to skip). The `/pmtiles/` nginx path is separate; Hosted basemaps need the Garage copy.

Enrollment package, after the server is up. Use the same name setup put on the certificate:

```sh
./make-datapackage.sh tak.example.com
```
