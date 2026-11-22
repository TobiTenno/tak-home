# Auth / SSO plan (Authelia + LLDAP)

Status: **scaffolded** — sibling repo [`auth-home`](../../auth-home) (`~/projects/auth-home`): compose, `setup.sh`, `scripts/migrate-users.sh` (`--bind-only`, `--migrate-plaintext-pass`), SWAG snippet + admin expose modes.  
Operator walkthrough: [`setup-guide.html`](./setup-guide.html) (domain field + copyable commands).  
**Boot order:** start `auth_lldap` → `./scripts/migrate-users.sh --bind-only` (creates Authelia LDAP bind user) → start `auth_authelia`. Skipping the seed → Authelia fatal `LDAP Result Code 49 Invalid Credentials`.  
This doc remains the integration plan for CloudTAK/TAK after auth-home is up.

## Stack boundary (decided)

**Auth is its own stack — technically separate from `tak-home`.**

| Stack | Owns | Does not own |
| --- | --- | --- |
| **`tak-home`** | TAK Server, CloudTAK, maps, SWAG snippets for `map`/`tiles`/`tak` stream, OIDC *client* config notes, CoreConfig oauth/ldap *integration* docs | Authelia, LLDAP, authelia-admin containers |
| **Auth stack** (`auth-home`) | `auth_lldap`, `auth_authelia`, optional `auth_authelia_admin`; OIDC provider; env files under `config/` | TAK/CloudTAK services |

Reasons:

- Auth serves CloudTAK **and** other apps; lifecycle should not follow `--profile tak` up/down.
- Secrets and bespoke clients stay out of the TAK repo.
- Join the shared Docker network (`tak` or whatever SWAG uses) so `tak_api` / `tak_server` can reach Authelia discovery (and LLDAP if Phase 5 uses LDAP).
- SWAG proxies `auth.<domain>` to the auth stack; `tak-home` only documents the CloudTAK/TAK side of the wire-up.

`tak-home` keeps this plan + setup-guide SSO sections as **integration** docs, not the auth compose.

## Goals

1. Stop managing CloudTAK (and other app) passwords by hand.
2. One directory (LLDAP) for users/groups; Authelia for login, 2FA, OIDC.
3. Wire CloudTAK + TAK Server so SSO login and cert enroll work.
4. Optionally map LLDAP groups → TAK Server channel groups / admin.
5. Other apps = extra Authelia OIDC clients on the **auth** stack — never folded into `tak-home` compose.

## Non-goals (for now)

- Replacing ATAK client-cert auth with Authelia cookies (won’t work that way).
- Auto-promoting CloudTAK `system_admin` / `agency_admin` from LLDAP groups (CloudTAK stores those in its DB; no first-class OIDC→admin map today).
- Putting Authelia/LLDAP (or other apps’ compose) inside `tak-home`.
- Importing **password hashes** into LLDAP (OPAQUE — hashes from other systems won’t load).
  Plaintext passwords already held in deploy secrets **can** be seeded (see migration).

## Architecture

```
                  ┌─────────────┐
                  │  LLDAP UI / │
                  │ authelia-admin│
                  └──────┬──────┘
                         │ users/groups
                         ▼
┌──────────┐      ┌─────────────┐      OIDC       ┌──────────┐
│ Browser  │─────▶│  Authelia   │───────────────▶│ CloudTAK │
└──────────┘      │ auth.<dom>  │                │ map.<dom>│
                  └──────┬──────┘                └────┬─────┘
                         │ LDAP bind                  │ enroll w/ IdP token
                         ▼                            ▼
                  ┌─────────────┐                ┌──────────┐
                  │    LLDAP    │◀── optional ───│tak_server│
                  └─────────────┘   LDAP groups  └──────────┘
```

| Piece | Job |
| --- | --- |
| **LLDAP** | Source of truth for users, emails, groups |
| **Authelia** | 1FA/2FA, OIDC provider, app access policies |
| **authelia-admin** (optional) | Same host path `/auth-admin/` — users + TOTP/bans |
| **CloudTAK OIDC** | SSO button; username = IdP `email` claim |
| **TAK CoreConfig oauth** | New-user / renew cert enroll via IdP token |
| **TAK LDAP** (optional phase) | Channel groups + `adminGroup` from LLDAP |

SWAG already lists `auth` in subdomains on the home lab — reuse `auth.<domain>` for Authelia.

**Do not** put Authelia forward-auth in front of CloudTAK as the only “SSO”. CloudTAK needs its own OIDC session/JWT. Forward-auth is fine for some apps; wrong primary layer for CloudTAK.

## Admin panels — optional network lock (decided intent)

Public Authelia login (`auth.<domain>/`) stays reachable for SSO. **Admin UIs** (LLDAP web UI and/or `authelia-admin` at `/auth-admin/`) should be **optionally hidden** from the open internet.

Allowlist modes (pick one or combine via SWAG/`allow`/`deny` or bind address):

| Mode | Who can reach admin UI |
| --- | --- |
| **subnet** | LAN / RFC1918 (e.g. `192.168.0.0/16`, `10.0.0.0/8`) |
| **localhost** | `127.0.0.1` / `::1` only (SSH tunnel or local browser) |
| **Tailscale** | Tailscale CGNAT / interface (e.g. `100.64.0.0/10` or known tailnet IPs) |
| **off / public** | Same exposure as login (not recommended for admin) |

Implementation notes (auth stack, not `tak-home`):

- Prefer **nginx/SWAG `allow`/`deny`** (or Authelia access control on the admin location) so login stays public while `/auth-admin/` and LLDAP’s UI port/path are locked.
- Or bind admin ports to Tailscale/localhost only and do **not** publish them on the WAN-facing proxy.
- Document the chosen mode in auth-stack env (e.g. `ADMIN_EXPOSE=subnet|localhost|tailscale|public`).
- Still require Authelia login / admin groups on top of the network lock — network is defense in depth, not the only gate.

## Phases

### Phase 0 — Prerequisites (already mostly done)

- [x] TAK + CloudTAK up behind SWAG (`map`, `tiles`, stream `tak`)
- [x] Operator guide: `docs/setup-guide.html`
- [ ] Note live domain and where Authelia will live
- [ ] Confirm whether `auth.<domain>` already points at something

### Phase 1 — LLDAP (auth stack)

- [x] Separate auth compose: `auth-home/compose.yaml` (not `tak-home`)
- [x] `lldap` on shared `tak` network (external)
- [x] `./setup.sh` writes `LLDAP_*` into `config/auth.env`
- [ ] Create bind user for Authelia (migrate script seeds `authelia`; verify after first up)
- [ ] Create groups (examples):
  - `authelia_users` / `cloudtak_users` — who may SSO
  - `tak_*` — TAK channel groups (prefix match in CoreConfig)
  - `tak_admins` — candidate for TAK `adminGroup`
  - `lldap_admin`, `authelia_user_manager` — admin UIs
- [ ] Bootstrap first real users with **email = CloudTAK username**

### Phase 2 — Authelia (auth stack)

- [x] Authelia in same auth compose as LLDAP
- [x] Authelia config template: LDAP `implementation: lldap` + CloudTAK OIDC client
- [x] Local SQLite storage under volume (Postgres later if desired)
- [x] SWAG `swag/auth.conf` — public login; admin paths allowlisted
- [x] `ADMIN_EXPOSE=subnet|localhost|tailscale|public` via `./setup.sh --admin-expose`
- [ ] Deploy on server: compose up, copy SWAG conf, verify discovery URL
- [ ] Enable OIDC provider (HMAC/JWKS secrets)
- [ ] Register client **`cloudtak`**:
  - Redirect: `https://map.<domain>/api/login/oidc/callback`
  - Scopes: `openid`, `profile`, `email`
  - Confidential; secret hashed in Authelia, plaintext in CloudTAK
- [ ] Authorization policy: only `group:cloudtak_users` (or similar) may consent/login to that client

### Phase 3 — CloudTAK OIDC

- [ ] Admin → Login → Enable OIDC (Enforce **off**)
- [ ] Discovery: `https://auth.<domain>/.well-known/openid-configuration`
- [ ] Client id/secret match Authelia
- [ ] Test SSO as existing user (same email) → existing profile/cert
- [ ] Test brand-new user → expect enroll path (needs Phase 4)

Docs: https://docs.cloudtak.io/admin/#single-sign-on-oidc

### Phase 4 — TAK Server OAuth (cert enroll)

In `CoreConfig.xml` `<auth>`:

```xml
<oauth usernameClaim="email">
  <openIdDiscoveryConfiguration
    name="cloudtak-sso"
    clientId="cloudtak"
    secret="SAME_PLAINTEXT_AS_CLOUDTAK"
    redirectUri="https://map.DOMAIN/api/login/oidc/callback"
    configurationUri="https://auth.DOMAIN/.well-known/openid-configuration"/>
</oauth>
```

- [ ] Patch via `init/start-takserver.sh` or documented manual edit
- [ ] Restart `tak_server`
- [ ] TAK must reach Authelia discovery; document must include `scopes_supported`
- [ ] New SSO user gets a cert; check `takserver-api.log` if 500 on enroll

### Phase 5 — TAK groups from LLDAP (optional)

- [ ] Point TAK `<ldap>` at LLDAP **or** ensure OIDC tokens carry `groups` + `groupsClaim`
- [ ] `groupprefix` e.g. `tak_` so only intentional groups become channels
- [ ] `adminGroup` → LLDAP group that grants TAK `ROLE_ADMIN`
- [ ] Document IN/OUT naming for this deploy
- [ ] CloudTAK `system_admin` still set in CloudTAK Admin (call out in runbook)

### Phase 6 — Cut over (incl. password seed from secrets)

`tak-home` already stores **plaintext** enroll passwords in deploy `config/secrets.env` as `USER_PASS_<NAME>` (from `setup.sh` + `USERS=` in `takserver.env`). Auth setup **should detect those** and use them as the initial LLDAP passwords so users keep the same secret at first SSO — no hash import needed; LLDAP re-derives OPAQUE from the plaintext once.

- [ ] Export identities: TAK `USERS` / CloudTAK `profiles` emails → LLDAP users (`mail` must match CloudTAK username for SSO)
- [ ] **Detect** `USER_PASS_*` (and any optional auth-stack secret map) during auth bootstrap
- [ ] For each matched user: create LLDAP account + `lldap_set_password` / bootstrap with that exact plaintext
- [ ] Users without a detected secret → generate temp password or invite / reset flow
- [ ] Document identity map when TAK name ≠ email (e.g. `alpha-1` → `alpha@example.com`) — SSO needs the email CloudTAK expects
- [ ] All users SSO once with enforce still off
- [ ] Set `oidc::enforced` true
- [ ] Break-glass: `PUT /api/config` `{"oidc::enforced": false}` or delete settings row
- [ ] Optional later: rotate / drop plaintext `USER_PASS_*` from long-term secrets once everyone uses Authelia (TAK file users may still need them if LDAP not default for ATAK enroll)

Caveats:

- Only works where plaintext still exists in secrets (or an operator-supplied seed file). Cannot recover from LLDAP/Authelia/TAK hashes alone.
- First login after seed can use the old password via Authelia; changing it in LLDAP/Authelia does not auto-update TAK `UserManager` unless LDAP is the TAK auth backend too.
- Prefer one-shot bootstrap script on the **auth stack**, reading a path to `tak-home`’s `secrets.env` (or a copied seed) — do not commit those values.

### Phase 7 — Other apps (out of repo; keep in mind)

Same Authelia + LLDAP can issue OIDC to anything that speaks Authorization Code. Pattern:

- Register a new confidential client (own `client_id`, redirect URI(s), scopes).
- Prefer native OIDC in the app over Authelia forward-auth alone when the app has its own session.
- Gate who may use the client with an Authelia authorization policy / LLDAP group.
- Match each app’s quirks (callback path, `offline_access`, token auth method) from that app’s docs — not from this repo.
- Keep those compose/env files outside `tak-home`.

## Migration cheat sheet

| Migrate | How |
| --- | --- |
| Emails / usernames | Yes → LLDAP `uid` + `mail` (must match CloudTAK) |
| Groups | Yes → recreate in LLDAP |
| CloudTAK data / certs | Stay in CloudTAK DB |
| Passwords (hashes) | No — cannot import into LLDAP OPAQUE |
| Passwords (plaintext in `USER_PASS_*` / seed file) | **Yes** — detect at auth setup; set as initial LLDAP password |
| Passwords (no secret on hand) | Temp / invite / reset |
| ATAK client certs | Keep |

## Work TBD

### Auth stack (separate project / compose)

- [ ] Compose: `lldap`, `authelia`, optional `authelia-admin`
- [ ] Templates: Authelia `configuration.yml`, LLDAP env, SWAG `auth` site conf snippet
- [ ] SWAG (or bind) rules for optional admin-panel lock: subnet / localhost / Tailscale / public
- [ ] OIDC clients + secrets live here (CloudTAK client definition, plus any other apps)
- [ ] Network: attach to shared `tak` (or SWAG) network; publish nothing host-side that SWAG doesn’t need

### `tak-home` (this repo) — integration only

- [ ] Docs/runbook: CoreConfig oauth (+ optional ldap) snippet; `init/` hook only if we automate TAK side
- [ ] Document `USER_PASS_*` layout for auth-stack bootstrap to detect
- [ ] Optional helper export: users + emails (+ path to secrets) for auth seed — no Authelia in this compose
- [ ] Keep SSO sections in `setup-guide.html` pointing at the external auth stack
- [ ] No Authelia/LLDAP services in `tak-home/compose.yaml`

### Auth stack — bootstrap

- [x] `scripts/migrate-users.sh` — `--bind-only`, `--tak-home`, `--email-domain`, `--dry-run`, `--migrate-plaintext-pass`
- [x] `--bind-only` before Authelia: create `uid=authelia` + default groups (password from `LLDAP_AUTHELIA_PASSWORD`)
- [x] Without plaintext flag: random temps printed once; with flag: seed `USER_PASS_*`
- [ ] Validate GraphQL mutations against live LLDAP; fix group-id edge cases if needed
- [ ] Never commit `config/auth.env` / `config/secrets/` (gitignored) |

## References

Full image/project citations (containers, T.REX, OpenTopoMap, etc.): [references](./references.html).  
Host hardening pointers: [security](./security.html).

- CloudTAK OIDC: https://docs.cloudtak.io/admin/#single-sign-on-oidc
- Authelia ↔ LLDAP: https://www.authelia.com/integration/ldap/lldap/
- Authelia OIDC clients: https://www.authelia.com/integration/openid-connect/clients/
- authelia-admin: https://github.com/asalimonov/authelia-admin
- TAK LDAP groups (community): groupprefix / groupBaseRDN / adminGroup patterns

## Open decisions (fill when implementing)

| Decision | Options | Pick |
| --- | --- | --- |
| Where Authelia/LLDAP compose lives | Inside `tak-home` vs **separate auth stack** on shared network | **Separate auth stack** (decided) |
| Auth stack location | New repo vs sibling folder next to SWAG compose | |
| Admin panel exposure | subnet / localhost / Tailscale / public | **Optional lock** — prefer subnet or Tailscale; public discouraged |
| Authelia storage | Local vs Postgres | |
| TAK groups | LDAP bind vs OIDC `groupsClaim` only | |
| First cutover date / enforce SSO | | |
