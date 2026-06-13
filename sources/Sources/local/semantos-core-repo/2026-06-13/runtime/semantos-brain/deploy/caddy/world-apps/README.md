---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/deploy/caddy/world-apps/README.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.269503+00:00
---

# World-app Caddy config — operator reference

The live Caddyfile is the only source of truth. It lives at:

```
rbs:/opt/consulting/Caddyfile          (host)
consulting_proxy:/etc/caddy/Caddyfile  (bind-mounted into the container)
```

This directory is intentionally empty of `.caddy` fragments — a copy
in the repo would drift from the live file and silently mislead.

## Editing the live config

```bash
ssh rbs

# Always back up before editing.
sudo cp /opt/consulting/Caddyfile "/opt/consulting/Caddyfile.bak.$(date +%Y%m%d-%H%M)"

# Edit in place.
sudo nano /opt/consulting/Caddyfile

# Validate before reload — a bad block can fail the whole container.
sudo docker exec consulting_proxy caddy validate --config /etc/caddy/Caddyfile

# Graceful reload — no dropped connections.
sudo docker exec consulting_proxy caddy reload --config /etc/caddy/Caddyfile

# Verify.
curl -I https://<host>/
```

## World-app block shape

Every world-app static SPA gets a block like this:

```
<host>, www.<host> {
    root * /var/www/<host>
    file_server
    encode zstd gzip
    try_files {path} /index.html
    header {
        X-Content-Type-Options nosniff
        Referrer-Policy strict-origin-when-cross-origin
    }
    @html path /index.html /
    header @html Cache-Control "no-cache"
}
```

`try_files {path} /index.html` is the SPA fallback — client-side
routes (`/room/<id>`, `?invite=<gameId>`) resolve to index.html
rather than 404.

## Webroot bringup

Before the first deploy to a new host:

```bash
ssh rbs 'sudo install -d -o $USER -g www-data -m 0755 /var/www/<host>'
```

`/var/www` is bind-mounted read-only into `consulting_proxy`, so the
SPA bundle goes on the host filesystem and the container reads from
there.

## Currently routed world-app related hosts

- `relay.semantos.me` — cell-relay WSS (BEAM at `172.18.0.1:5178`)
- `jam.semantos.me` — jam-room static SPA at `/var/www/jam.semantos.me/`
- `doublemate.app` — chess-game static SPA at `/var/www/doublemate.app/`
- `world.semantos.me` — Phoenix `cell_relay + world_host` (`127.0.0.1:4000`)
- `headers.semantos.me` — BSV headers HTTP (`172.18.0.1:8334`)
- `brain.oddjobtodd.info` — brain (`172.18.0.1:8080`) + `/helm-viewer/*` static

For end-to-end pattern documentation see
`docs/design/WORLD-APP-DEPLOY.md`.
