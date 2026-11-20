# Docs

GitHub Pages mini-site (this folder): **https://tobitenno.github.io/tak-home/**

| File | What |
| --- | --- |
| [logo.png](./logo.png) / [favicon.svg](./favicon.svg) | Project mark — official TAK shield, banner reads HOME (US gov PD derivative) |
| [index.html](./index.html) | Landing |
| [setup-guide.html](./setup-guide.html) | Interactive operator guide |
| [auth-plan.html](./auth-plan.html) | SSO plan (from [`AUTH-PLAN.md`](./AUTH-PLAN.md)) — auth is **`auth-home`** |
| [dev-move.html](./dev-move.html) | Move notes (from [`DEV-MOVE.md`](./DEV-MOVE.md)) |
| [site.css](./site.css) / [render_md.mjs](./render_md.mjs) | Shared docs chrome + MD→HTML build |

Deploy: push `docs/**` to `main` → workflow renders markdown then publishes.  
One-time: repo **Settings → Pages → Source = GitHub Actions**.  
Local: `cd docs && npm i marked@15 && node render_md.mjs`

Root [README.md](../README.md) is the short install reference.
