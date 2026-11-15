# Moving development to another machine

Use this when copying `tak-home` (and related deploy context) to a different box for a while.

## What this repo is

| Path | Role |
| --- | --- |
| Authoring / git source (this tree) | `/var/home/tobiah/projects/tak-home` (or clone) |
| Deploy copy (example) | Often `…/pvr/tak-home` next to shared compose via `./setup.sh -f …` |
| Older src mention | `~/tak-home` may exist — prefer one canonical clone |

Generated / secret / bulky paths are **not** what you develop against blindly — see below.

## Bring with you

### Required

- [ ] Git remote + branch (or `rsync`/`scp` of the project tree)
- [ ] This docs set: `docs/setup-guide.html`, `docs/AUTH-PLAN.md`, `docs/DEV-MOVE.md`
- [ ] `README.md`, `compose.yaml`, `setup.sh`, `init/`, `swag/`, `maps/providers/`, scripts

### Secrets (do not commit; copy privately)

- [ ] Deploy `config/cloudtak.env` (SigningSecret, Garage keys, CSP, `API_URL` / `PMTILES_URL`)
- [ ] Deploy `config/secrets.env` / `takserver.env`
- [ ] Authelia / LLDAP secrets once created (OIDC client secrets, JWT, admin passwords)
- [ ] Cloudflare / SWAG DNS tokens if you edit LE from the new machine

### Optional / large

- [ ] `maps/data/*.pmtiles` and `maps/data/sprites/` (gitignored; re-fetch with `./maps/fetch.sh` if easier)
- [ ] Generated `maps/basemap.hosted*.json` (rebuild with `./maps/render-basemap.sh`)
- [ ] `tak-ca.pem` / datapackages if you test ATAK against the same CA

## Do not assume on the new machine

- Docker containers from the server are **not** running here unless you start them (lab policy: often diagnose only; deploy via setup/`-f` on the server).
- `setup.sh` only rewrites `API_URL` / `PMTILES_URL` on existing `cloudtak.env` — it does **not** merge new CSP template lines automatically.
- Hosted basemap tile URL must use `{$z}` not `{z}`.
- After Garage republish, restart `tak_tiles` (publish script does this unless `--no-restart`).

## Suggested workflow on the new box

1. Clone / sync repo.
2. Read `docs/AUTH-PLAN.md` for SSO backlog; `docs/setup-guide.html` for stack ops.
3. Edit templates/scripts locally; copy changed files to deploy host (or push + pull).
4. Run `./setup.sh <domain> -f <shared-compose>` on the **server** when regenerating confs.
5. Keep other Authelia OIDC clients / app compose in a personal notes folder or sibling stack — outside `tak-home` so it doesn’t block TAK work.

## Current known-good (as of plan write-up)

- Map site + T.Rex Hosted basemap recovered; Google basemaps OK after wiping stale **profile overlays** (DELETE is `DELETE /api/profile/overlay?id=`).
- CSP in live header includes T.Rex + Google hosts; template in `config/cloudtak.env.template` lists explicit hosts (no `*.google.com` wildcards).
- Auth stack (LLDAP/Authelia) is **separate from `tak-home`** and not implemented yet — follow `AUTH-PLAN.md` (Stack boundary).

## Sync checklist before you leave this machine

- [ ] Commit or stash plan docs + setup guide (when you want them in git)
- [ ] List uncommitted local-only secrets paths you still need
- [ ] Note live domains: `map.` / `tiles.` / `tak.` / `auth.` (+ any other OIDC apps)
- [ ] Note deploy compose path and SWAG config paths on the server
- [ ] Paste break-glass for OIDC lockout into password manager:
  - `PUT /api/config` `{"oidc::enforced": false}`
  - or `DELETE FROM settings WHERE key = 'oidc::enforced';`
