---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docker-compose.yml
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.308152+00:00
---

# docker-compose.yml

```yml
# Semantos Node — Docker Compose
#
# Services:
#   semantos-node    — kernel + admin API + workbench
#   block-headers    — block header sync sidecar
#
# Volumes:
#   semantos-data    — persistent object storage
#   semantos-config  — node config and certs
#
# Usage:
#   docker compose up -d
#   docker compose logs -f semantos-node
#   docker compose down

services:
  semantos-node:
    build:
      context: .
      dockerfile: Dockerfile
    ports:
      - "3000:3000"       # workbench UI
      - "6443:6443"       # admin API (mTLS)
      - "9000:9000/udp"   # shard proxy
    volumes:
      - semantos-data:/var/semantos/data
      - ./certs:/etc/semantos/certs:ro
      - ./node.json:/etc/semantos/node.json:ro
      - ./configs/extensions:/var/semantos/extensions:ro
    environment:
      SEMANTOS_MODE: docker
      SEMANTOS_BYOK_KEY: ${SEMANTOS_BYOK_KEY:-}
      SEMANTOS_SUBNET_PREFIX: ${SEMANTOS_SUBNET_PREFIX:-}
      SEMANTOS_DEBUG_LOGGING: ${SEMANTOS_DEBUG_LOGGING:-false}
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "bun", "run", "packages/node/src/health-check.ts"]
      interval: 30s
      timeout: 5s
      start_period: 10s
      retries: 3

  block-headers:
    image: oven/bun:1-alpine
    volumes:
      - semantos-data:/var/semantos/data
    command: >
      sh -c "echo 'Block headers sidecar — placeholder for Phase 27 anchor integration' && sleep infinity"
    restart: unless-stopped

  # Phase H3 — Border Router Aggregator (settlement layer)
  # Collects poker bot multicast cells, batches every 30s, anchors Merkle roots to BSV
  border-router:
    build:
      context: .
      dockerfile: packages/settlement/Dockerfile.border-router
    network_mode: host   # Required for IPv6 multicast reception from poker containers
    volumes:
      - semantos-data:/var/semantos/data
    environment:
      MULTICAST_GROUP: ${MULTICAST_GROUP:-ff02::semantos:poker}
      MULTICAST_PORT: ${MULTICAST_PORT:-6969}
      MULTICAST_INTERFACE: ${MULTICAST_INTERFACE:-eth0}
      ANCHOR_BATCH_INTERVAL_MS: ${ANCHOR_BATCH_INTERVAL_MS:-30000}
      SQLITE_DB_PATH: /var/semantos/data/provenance.db
      REST_PORT: ${REST_PORT:-8080}
      WS_PORT: ${WS_PORT:-8081}
      BSV_NETWORK: ${BSV_NETWORK:-testnet}
      HOT_WALLET_PRIVKEY: ${HOT_WALLET_PRIVKEY:-}
      ARC_URL: ${ARC_URL:-https://arc.gorillapool.io}
      DRY_RUN: ${DRY_RUN:-true}
      LOG_LEVEL: ${LOG_LEVEL:-info}
      CELL_DEDUP_WINDOW_MS: ${CELL_DEDUP_WINDOW_MS:-60000}
    depends_on:
      - semantos-node
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/health"]
      interval: 30s
      timeout: 5s
      start_period: 10s
      retries: 3

volumes:
  semantos-data:

```
