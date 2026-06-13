---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docker-compose.sidecar.yml
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.311745+00:00
---

# docker-compose.sidecar.yml

```yml
# Verifier Sidecar — per-node deployment topology default
#
# Codifies D-V2: deployment topology decision for the Verifier Sidecar.
# Per-node sidecar process is the default per Unification Roadmap §8 Q3
# (resolved 2026-04-26) and protocol-v0.5.md §9.5.
#
# This compose file is intentionally a single-service deployment artifact:
# one verifier-sidecar per node, intercepting every request that crosses
# an adapter boundary. The two alternative topologies (per-surface
# in-process; edge gateway) are documented in
# runtime/verifier-sidecar/README.md and are not codified here because
# they are exception cases, not the default.
#
# Compose with the base node:
#   docker compose -f docker-compose.yml -f docker-compose.sidecar.yml up -d
#
# Inspect:
#   docker compose -f docker-compose.sidecar.yml logs -f verifier-sidecar
#   curl -fsS http://localhost:8787/healthz
#
# Cross-references:
#   docs/spec/protocol-v0.5.md §9.5     — Verifier Sidecar
#   docs/prd/UNIFICATION-ROADMAP.md §8 Q3 — topology decision
#   docs/canon/glossary.yml § verifier-sidecar
#   runtime/verifier-sidecar/             — sidecar source (D-V1 lands)
#
# Convention: the `verifier-sidecar` service binds host port 8787 and
# exposes /healthz. D-V1's reference implementation is expected to honour
# the same port + route. If D-V1 picks different defaults, this file is
# the single source of truth that needs to follow.

services:
  verifier-sidecar:
    build:
      # D-V1 (parallel deliverable) creates runtime/verifier-sidecar/.
      # When D-V1 lands, this build context resolves to the sidecar
      # source tree; until then, the integration test stubs the binary.
      context: ./runtime/verifier-sidecar
      dockerfile: Dockerfile
    container_name: semantos-verifier-sidecar
    ports:
      - "8787:8787"   # BRC-100 verification + /healthz
    environment:
      VERIFIER_SIDECAR_PORT: "8787"
      VERIFIER_SIDECAR_HEALTH_ROUTE: "/healthz"
      # Topology mode is observable for ops dashboards. The default is
      # `per-node`; alternative values (`in-process`, `edge-gateway`) are
      # documented in runtime/verifier-sidecar/README.md.
      VERIFIER_SIDECAR_TOPOLOGY: "per-node"
      LOG_LEVEL: ${LOG_LEVEL:-info}
    restart: unless-stopped
    healthcheck:
      # Conformant sidecars MUST return 200 on /healthz.
      test: ["CMD", "wget", "-qO-", "--tries=1", "http://localhost:8787/healthz"]
      interval: 15s
      timeout: 5s
      start_period: 10s
      retries: 3

```
