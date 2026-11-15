# Auth / SSO plan (Authelia + LLDAP)

Status: **planned** — identity stack not built yet.  
Operator walkthrough for the existing TAK stack: [`setup-guide.html`](./setup-guide.html).  
This doc is the implementation plan for identity after the TAK/CloudTAK stack is up.

## Stack boundary (decided)

**Auth is its own stack — technically separate from `tak-home`.**

| Stack | Owns | Does not own |
| --- | --- | --- |
| **`tak-home`** | TAK Server, CloudTAK, maps, SWAG snippets for `map`/`tiles`/`tak` stream, OIDC *client* config notes, CoreConfig oauth/ldap *integration* docs | Authelia, LLDAP, authelia-admin containers |
| **Auth stack** (separate repo or sibling compose, e.g. `auth-home` / lab compose) | LLDAP, Authelia, optional authelia-admin, Authelia OIDC *provider* + clients, auth secrets | TAK/CloudTAK services |

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
- Seamless password-hash migration into LLDAP (impossible — OPAQUE; reset once).

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

## Phases

### Phase 0 — Prerequisites (already mostly done)

- [x] TAK + CloudTAK up behind SWAG (`map`, `tiles`, stream `tak`)
- [x] Operator guide: `docs/setup-guide.html`
- [ ] Note live domain and where Authelia will live
- [ ] Confirm whether `auth.<domain>` already points at something

### Phase 1 — LLDAP (auth stack)

- [ ] Create / extend the **separate** auth compose (not `tak-home/compose.yaml`)
- [ ] Add `lldap` on the shared proxy/`tak` network (reachable from Authelia + optionally `tak_server`)
- [ ] Set `LLDAP_BASE_DN`, admin password, JWT secret
- [ ] Create bind user for Authelia (read users/groups; password change if Authelia reset used)
- [ ] Create groups (examples):
  - `authelia_users` / `cloudtak_users` — who may SSO
  - `tak_*` — TAK channel groups (prefix match in CoreConfig)
  - `tak_admins` — candidate for TAK `adminGroup`
  - `lldap_admin`, `authelia_user_manager` — admin UIs
- [ ] Bootstrap first real users with **email = CloudTAK username**

### Phase 2 — Authelia (auth stack)

- [ ] Add Authelia to the **same** auth compose as LLDAP
- [ ] Authelia config: LDAP backend `implementation: lldap`
- [ ] Session / storage (Postgres or local — prefer Postgres if already on host)
- [ ] SWAG vhost `auth.<domain>` → Authelia
- [ ] Optional: `location /auth-admin/` → authelia-admin (protect with Authelia)
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

### Phase 6 — Cut over

- [ ] Export CloudTAK profile emails → create LLDAP users (script TBD)
- [ ] Password reset / invite (hashes do not migrate)
- [ ] All users SSO once with enforce still off
- [ ] Set `oidc::enforced` true
- [ ] Break-glass: `PUT /api/config` `{"oidc::enforced": false}` or delete settings row

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
| Passwords | Reset once (LLDAP OPAQUE ≠ bcrypt import) |
| ATAK client certs | Keep |

## Work TBD

### Auth stack (separate project / compose)

- [ ] Compose: `lldap`, `authelia`, optional `authelia-admin`
- [ ] Templates: Authelia `configuration.yml`, LLDAP env, SWAG `auth` site conf snippet
- [ ] OIDC clients + secrets live here (CloudTAK client definition, plus any other apps)
- [ ] Network: attach to shared `tak` (or SWAG) network; publish nothing host-side that SWAG doesn’t need

### `tak-home` (this repo) — integration only

- [ ] Docs/runbook: CoreConfig oauth (+ optional ldap) snippet; `init/` hook only if we automate TAK side
- [ ] Script or notes: CloudTAK `profiles` emails → LLDAP bootstrap (runs against auth stack API)
- [ ] Keep SSO sections in `setup-guide.html` pointing at the external auth stack
- [ ] No Authelia/LLDAP services in `tak-home/compose.yaml`

## References

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
| Authelia storage | Local vs Postgres | |
| TAK groups | LDAP bind vs OIDC `groupsClaim` only | |
| First cutover date / enforce SSO | | |
