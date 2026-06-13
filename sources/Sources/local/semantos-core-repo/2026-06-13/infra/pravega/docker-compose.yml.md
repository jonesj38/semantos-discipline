---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/infra/pravega/docker-compose.yml
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.042892+00:00
---

# infra/pravega/docker-compose.yml

```yml
# M3.1 — Pravega single-node dev cluster.
#
# Acceptance: `docker compose up -d` brings up Pravega;
# `infra/pravega/tests/smoke_test.sh` creates a scope, creates a stream,
# writes one event, reads it back — all green.
#
# Architecture decision (M3.1 — open question #2 resolved here):
#   Pravega's native client is JVM-only. We use the standalone Pravega image
#   which bundles a Controller + Segment Store in a single process — ideal for
#   local dev. Production deployment (M3.7+) will add real ZooKeeper + HDFS
#   and run Controller / SegmentStore in separate pods.
#
# Ports:
#   9090  — Controller REST API (scope/stream/readergroup CRUD)
#   9091  — Data plane REST API (event write/read)
#   12345 — Controller gRPC (for the Zig host client in M3.2)
#
# Gateway strategy (open question #2):
#   We expose Pravega's built-in REST gateway on ports 9090/9091.
#   M3.2 will evaluate: (a) drive gRPC from Zig via C FFI to
#   the Go client (`pravega-client-go`), or (b) a thin HTTP gateway
#   in front of the gRPC API. This docker-compose lets both paths be
#   tested without committing to either.

services:
  pravega:
    image: pravega/pravega:0.14.0
    container_name: semantos-pravega-dev
    command: standalone
    ports:
      - "9090:9090"     # Controller REST
      - "9091:9091"     # Data plane REST
      - "12345:12345"   # Controller gRPC
      - "12346:12346"   # Segment store (internal, exposed for diagnostics)
    environment:
      # Standalone mode configuration
      PRAVEGA_STANDALONE_CONTROLLER_URL: "tcp://0.0.0.0:12345"
      # Disable ZK / HDFS for dev: standalone mode uses in-process equivalents
      HOST_IP: "127.0.0.1"
    volumes:
      - pravega-data:/mnt/tier2
    healthcheck:
      test:
        - CMD
        - sh
        - -c
        - "curl -sf http://localhost:9090/v1/ping"
      interval: 10s
      timeout: 5s
      retries: 12
      start_period: 30s
    restart: unless-stopped

  # ── Schema registry (optional, for M3 stream schema evolution) ───────
  # Starts a Pravega Schema Registry alongside the standalone cluster.
  # Not required for M3.1 smoke test; comment out to save resources.
  schema-registry:
    image: pravega/schemaregistry:0.4.0
    container_name: semantos-schema-registry-dev
    ports:
      - "9092:9092"
    environment:
      JAVA_OPTS: "-Xmx256m"
    depends_on:
      pravega:
        condition: service_healthy
    restart: unless-stopped

volumes:
  pravega-data:
    driver: local

```
