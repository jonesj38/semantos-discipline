---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/deploy/README-helm.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.168120+00:00
---

# Helm SPA deployment (D-O5)

The helm SPA is the operator's desktop workbench for an oddjobz tenant.
It ships as a Vite-built static bundle at `apps/loom-svelte/dist/`,
copied to `<data-dir>/sites/<tenant>/public/helm/`, and served by brain
via the `RouteType.directory` route added in this PR.

## Build prerequisites

- Node 18+ (Node 16 fails to build vite 5 — the helm SPA uses globalThis.crypto).
- pnpm or npm at the repo root (workspace dependencies are pre-installed
  by `pnpm install` in CI).

## Quickstart

```sh
runtime/semantos-brain/deploy/oddjobz-helm-deploy.sh \
    --tenant oddjobtodd.info \
    --data-dir /var/lib/semantos/.semantos
```

This:

1. Runs `npm run build` in `apps/loom-svelte/` (skip with `--skip-build`).
2. Wipes `<data-dir>/sites/<tenant>/public/helm/` and copies the new bundle.
3. Prints the `site.json` route entry to add.

## Site.json route

```json
"/helm/": {
  "type": "directory",
  "root": "/var/lib/semantos/.semantos/sites/oddjobtodd.info/public/helm",
  "spa_fallback": "index.html",
  "auth": "identity_required"
}
```

The path **must end with `/`** — that's how `routeFor` identifies the
prefix-match dispatch path for the directory route.

## End-to-end smoke (D-O5d)

The §3 phase O5 acceptance test is:

> Operator opens https://oddjobtodd.info/helm, gets challenged, signs
> on his phone, lands in helm, sees his job list and attention feed
> live.

Local smoke:

1. `cd runtime/semantos-brain && zig build -Denable-wasmtime=true --release=safe`
2. Lay out a tmp tenant: `mkdir -p /tmp/d-o5-smoke/sites/local.test/public/helm`
3. Copy the SPA bundle: `cp -R apps/loom-svelte/dist/. /tmp/d-o5-smoke/sites/local.test/public/helm/`
4. Write `/tmp/d-o5-smoke/sites/local.test/site.json` with the route above
   and `auth: "public"` so no challenge fires for the smoke.
5. `brain start --data-dir /tmp/d-o5-smoke --site local.test --port 8080`
6. `curl -i http://localhost:8080/helm/` → returns the SPA index.html.
7. `curl -i http://localhost:8080/helm/assets/<bundle>.js` → returns
   the JS bundle with `content-type: application/javascript; charset=utf-8`.
8. `curl -i http://localhost:8080/helm/anything-not-on-disk` → returns
   the SPA index.html (SPA fallback for client-side routing).

Production verification (the actual §3 acceptance test) requires a
device-paired wallet origin and is exercised by hand on
oddjobtodd.info; the helm-SPA-side smoke above proves the wiring.

## Manual verification for the bearer flow

The `/api/v1/repl` endpoint demands `Authorization: Bearer <hex64>`.
Helm gets that from the auth-callback redirect (currently a
`?bearer=...` query param the SPA captures via
`auth.captureBearerFromUrl`; D-O5.followup-2 lands a cleaner cookie-
based mint).  For local testing without a wallet origin:

```sh
# issue a bearer via the Semantos Brain CLI (D-W1 Phase 0):
brain bearer issue --ttl 3600
# → prints a hex64 token. Manually drop into localStorage:
#     localStorage.setItem("helm.bearer", "<hex64>")
# in the browser devtools, then reload /helm/.
```
