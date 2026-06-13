---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/design/WORLD-APP-DEPLOY.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.734719+00:00
---

# World-app deploy pattern

How world-app SPAs (`apps/world-apps/<name>/`) get from a local repo to
a public host. Codifies the shape established for `chess-game →
doublemate.app` and `jam-room → jam.semantos.me`.

## Topology

```
                ┌───────────────────────────────────────────────┐
                │  consulting_proxy (caddy:alpine on rbs:443)    │
                │                                                │
                │  doublemate.app    → /var/www/doublemate.app/  │  (static SPA bundle)
                │  jam.semantos.me   → /var/www/jam.semantos.me/ │  (static SPA bundle)
                │  relay.semantos.me → 172.18.0.1:5178           │  (BEAM cell-relay)
                │  brain.oddjobtodd.info → 172.18.0.1:8080       │  (Semantos brain)
                │  headers.semantos.me → 172.18.0.1:8334         │  (BSV headers HTTP)
                └─────────────┬──────────────────────────────────┘
                              │
                              ▼ wss
       ┌──────────────────────┴──────────────────────┐
       │                                              │
   browser SPA                              browser SPA
   (doublemate.app)                         (jam.semantos.me)
       │                                              │
       └──────► wss://relay.semantos.me/relay/socket  ◄──── (room state)
       └──────► wss://brain.oddjobtodd.info/api/v1/wallet   (verb.dispatch)
```

Every world-app is a static SPA. The browser does all the heavy
lifting (UI, click-to-move, three.js); the brain enforces all
authority (verb dispatch through capabilities), the cell-relay
shuttles state between peers in a room, and the headers service is
the SPV anchor. No app-specific backend exists.

## The four pieces of a world-app deploy

| Piece                              | Where it lives                                               |
|------------------------------------|--------------------------------------------------------------|
| SPA source                         | `apps/world-apps/<name>/`                                    |
| Production build envs              | `apps/world-apps/<name>/.env.production` (Vite `VITE_*`)     |
| Caddy block                        | `/opt/consulting/Caddyfile` on rbs (the only source of truth)|
| Deploy command                     | `tools/release/deploy-world-app.sh <name> <host>`            |

`/opt/consulting/Caddyfile` is bind-mounted into the
`consulting_proxy` container at `/etc/caddy/Caddyfile`. Edit it on
the host, validate inside the container, reload inside the
container — see `runtime/semantos-brain/deploy/caddy/world-apps/
README.md` for the exact commands.

## Build-time URL wiring

World-apps don't munge their origin to guess the brain or relay
hostname — that breaks the moment the SPA moves to a domain that
doesn't share a prefix with the brain (`doublemate.app` is the
canonical example: there is no `brain.doublemate.app`).

Instead, every world-app resolves its brain + relay URLs from this
order:

1. `localStorage.<app>.brainUrl` / `localStorage.<app>.relayUrl` —
   runtime operator override (useful for pointing a production SPA
   at a staging brain without rebuilding)
2. `import.meta.env.VITE_BRAIN_WSS_URL` / `VITE_RELAY_WSS_URL` —
   baked at build time by Vite from `.env.production`
3. localhost fallback (`ws://<hostname>:7777` for brain,
   `ws://<hostname>:4000` for relay) — for `bun run dev`

Production `.env.production` for `chess-game`:

```
VITE_BRAIN_WSS_URL=wss://brain.oddjobtodd.info/api/v1/wallet
VITE_RELAY_WSS_URL=wss://relay.semantos.me/relay/socket
```

`jam-room` (when it adopts this pattern) takes the same shape; only
the SPA-side namespaces differ.

## Caddy fragment

Every world-app gets its own block in the live Caddyfile (which lives
inside the `consulting_proxy` Docker container on rbs). The shape is
the same for all of them:

```
<host>, www.<host> {
    root * /var/www/<host>
    file_server
    encode zstd gzip
    try_files {path} /index.html   # SPA fallback for client-side routes
    header {
        X-Content-Type-Options nosniff
        Referrer-Policy strict-origin-when-cross-origin
    }
    @html path /index.html /
    header @html Cache-Control "no-cache"
}
```

Vite emits content-hashed asset filenames, so the immutable cache
policy is safe for everything except `index.html` — which must update
on every deploy or browsers won't pick up new bundles.

Paste the block directly into `/opt/consulting/Caddyfile` on rbs
and reload (`sudo docker exec consulting_proxy caddy reload --config
/etc/caddy/Caddyfile`). The repo does not track a local copy of
the live file — see `runtime/semantos-brain/deploy/caddy/world-apps/
README.md` for the editing workflow.

## Deploy

```bash
tools/release/deploy-world-app.sh chess-game doublemate.app
```

What this does:

1. `bun run build` in `apps/world-apps/chess-game/` (vite emits
   `dist/`).
2. `rsync -a --delete dist/ rbs:/var/www/doublemate.app/`.
3. `ssh rbs 'sudo docker exec consulting_proxy caddy reload …'` — a
   no-op if the Caddyfile didn't change, but the command is cheap and
   keeps the deploy idempotent.

Flags: `--dry-run` (preview), `--skip-build` (reuse existing `dist/`),
`--skip-reload` (rsync without reloading Caddy — for the first deploy
before the Caddyfile block exists).

## First-time bringup for a new domain

1. **DNS** — A/AAAA records for the host and its `www.` alias point
   at rbs.
2. **Webroot** — `ssh rbs 'sudo install -d -o $USER -g www-data -m
   0755 /var/www/<host>'`. Without this the rsync step fails.
3. **First deploy** — `tools/release/deploy-world-app.sh <name>
   <host> --skip-reload` lands the bundle on disk.
4. **Caddy block** — paste the block (template above) into
   `/opt/consulting/Caddyfile` on rbs and reload. Caddy fetches a
   Let's Encrypt cert on first request — so DNS (step 1) must
   resolve to rbs before the reload or ACME will fail.
5. **Verify** — `curl -I https://<host>/` returns 200 + correct
   `content-type: text/html`.

## Why this shape

- **Static-only origin** keeps the SPA tier completely separable from
  the brain tier — a chess outage doesn't take down the brain, a
  brain restart doesn't drop chess SPA traffic.
- **No app-specific backend** means new world-apps don't need new
  systemd units or new ports — only DNS + a Caddy fragment + a
  webroot.
- **Single shared brain + single shared relay** lets cartridges
  compose: a future world-app that uses both chess and jam-room
  cartridges talks to one brain.
- **`relay.semantos.me` is the canonical relay** so cross-app
  invariants (room-id format, presence semantics) have one wire
  endpoint to test against.

## What this does NOT cover

- The brain's own deploy chain — see
  `runtime/semantos-brain/deploy/deploy-rbs.sh` and the comment
  preamble for the atomic build → backup → install → systemd
  sequence.
- The cell-relay's own deploy chain — it's an OTP release from
  `runtime/world-beam/`; covered separately under that repo.
- Headers service deploy — `headers.semantos.me` runs from the
  same Caddyfile but its brain is a separate `semantos-headers.
  service` unit; deploy is the same `deploy-rbs.sh` shape but
  against a different systemd unit.
