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

`tak.example.com` is added to the server certificate. Point that name at the machine that publishes 8089. Point `map` and `tiles` at SWAG. The certificate must cover `map.example.com` and `tiles.example.com`.

Running `./setup.sh` again with the same or a new parent name rewrites those hostnames and keeps the passwords already in `config/secrets.env` and `config/cloudtak.env`.

From the directory that contains the compose file you passed to `-f`:

```sh
docker compose -f docker-compose.yml --profile tak up -d tak_certs tak_database tak_server
docker compose -f docker-compose.yml --profile tak cp tak_server:/opt/tak/certs/files/root-ca.pem tak-home/tak-ca.pem
docker compose -f docker-compose.yml --profile tak up -d
```

Copy `swag/cloudtak.conf` into SWAG's `site-confs`.

Tiles, on the server, when the chosen provider has a `fetch.sh`:

```sh
./maps/fetch.sh
```

Enrollment package, after the server is up. Use the same name setup put on the certificate:

```sh
./make-datapackage.sh tak.example.com
```
