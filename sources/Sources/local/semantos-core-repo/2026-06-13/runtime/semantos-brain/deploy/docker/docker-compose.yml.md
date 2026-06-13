---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/deploy/docker/docker-compose.yml
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.268908+00:00
---

# runtime/semantos-brain/deploy/docker/docker-compose.yml

```yml
# Phase Brain 6 — docker-compose for the sovereign-node host shell.
#
# Reference: docs/design/WALLET-SHELL-VPS-SUBSTRATE.md §3 (Brain 6).
#
# Two services:
#   - brain   : the host shell, listening on :8080 plain HTTP
#   - caddy : reverse proxy, terminates TLS and proxies to brain
#
# Usage:
#
#   export BRAIN_DOMAIN=oddjobtodd.info
#   docker compose up -d
#
# Caddy auto-fetches Let's Encrypt certs for $BRAIN_DOMAIN. DNS for
# $BRAIN_DOMAIN must already point at this host.
#
# Re-run `docker compose up -d` after `docker compose pull` to upgrade
# the Semantos Brain binary; the named volumes preserve operator data + Caddy's
# cert cache across restarts.

services:
  brain:
    image: semantos/brain:${BRAIN_VERSION:-latest}
    # Or build locally from the monorepo:
    # build:
    #   context: ../../../..
    #   dockerfile: runtime/semantos-brain/deploy/docker/Dockerfile
    container_name: brain
    restart: unless-stopped
    environment:
      BRAIN_DOMAIN: "${BRAIN_DOMAIN:?must set BRAIN_DOMAIN}"
      BRAIN_DATA_DIR: /var/lib/semantos
      BRAIN_CONFIG_DIR: /etc/semantos
    volumes:
      - brain-data:/var/lib/semantos
      - brain-config:/etc/semantos
    expose:
      - "8080"
    # Don't publish 8080 to the host — Caddy speaks to brain over the
    # internal compose network. If you're not running Caddy here, swap
    # `expose` for `ports: ["127.0.0.1:8080:8080"]`.
    networks:
      - sovereign

  caddy:
    image: caddy:2-alpine
    container_name: caddy
    restart: unless-stopped
    depends_on:
      - brain
    ports:
      - "80:80"
      - "443:443"
    environment:
      BRAIN_DOMAIN: "${BRAIN_DOMAIN:?must set BRAIN_DOMAIN}"
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile:ro
      - caddy-data:/data
      - caddy-config:/config
    networks:
      - sovereign

networks:
  sovereign:
    driver: bridge

volumes:
  brain-data:
  brain-config:
  caddy-data:
  caddy-config:

# Notes:
# - The Caddyfile in this directory references `brain:8080` (the compose
#   service name), not 127.0.0.1:8080 — that's correct inside the
#   compose network.
# - First boot: `docker compose exec brain brain bearer issue --label laptop`
#   prints a token for the HTTP REPL.
# - Headers backfill runs as a one-shot:
#     docker compose exec brain brain headers sync --peer seed.bitcoinsv.io:8333

```
