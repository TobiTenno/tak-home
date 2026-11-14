# tak-home

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

`tak.example.com` is added to the server certificate. Point `map`, `tiles`, and `tak` at SWAG. The certificate must cover `map.example.com` and `tiles.example.com`.

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
      - "9001:9001"
networks:
  tak:
    name: tak
```

A separate compose file uses the same network with `external: true`. Copy `swag/cloudtak.conf` into SWAG `site-confs` and `swag/tak-stream.conf` into SWAG `stream-confs`. The stream file forwards 8089, 8443, 8446, and 9001 to `tak_server` without decrypting them.

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

Enrollment package, after the server is up. Use the same name setup put on the certificate:

```sh
./make-datapackage.sh tak.example.com
```
