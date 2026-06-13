---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/hackathon/EXECUTION-ORDER.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.762906+00:00
---

# Hackathon Execution Order & Dependency Tree

**Version**: 1.0
**Date**: April 2026
**Base branch**: `hackathon/semantos-swarm`
**Goal**: Wire all 5 hackathon phases to produce the Semantos Swarm demo

---

## Dependency Graph

```
                    ┌─────────────────────────────────────────────────┐
                    │         EXISTING (on hackathon/semantos-swarm)  │
                    │                                                  │
                    │  Phase 26D   NetworkAdapter interface            │
                    │  Phase 26E   NodeConfig, createNode()           │
                    │  Phase 26G   Dockerfile, docker-compose, CLI    │
                    │  Phase 27    GameCellEngine, poker, SRA         │
                    │  Phase 21    Lisp compiler (S-expr → Forth)     │
                    │  Phase 25.5  OP_CALLHOST host functions         │
                    │  Phase 30E   WASM target compilation            │
                    │  Phase 36A   ExtensionGrammar JSON schema       │
                    │  poker-agent payment-channel, broadcast, disco  │
                    └──────┬──────────┬──────────────────┬────────────┘
                           │          │                  │
              ┌────────────┘          │                  └────────────┐
              ▼                       ▼                               ▼
    ┌──────────────────┐   ┌──────────────────┐             (no new dep)
    │  PHASE H1        │   │  PHASE H2        │
    │  Docker Swarm    │   │  Poker Grammar   │
    │  Mesh            │   │  + Lisp Profiles │
    │                  │   │                  │
    │  DockerMulticast │   │  grammar.json    │
    │  Adapter, scale  │   │  nit.lisp        │
    │  25 bots, table  │   │  maniac.lisp     │
    │  formation       │   │  calculator.lisp │
    └────────┬─────────┘   └────────┬─────────┘
             │                      │
             │    ┌─────────────────┘
             │    │
             ▼    ▼
    ┌──────────────────┐
    │  PHASE H3        │
    │  Border Router   │
    │  Aggregator      │
    │                  │
    │  CellCollector   │
    │  MerkleBatcher   │
    │  BSV Anchor      │
    │  Overlay API     │
    │  Provenance DAG  │
    └────────┬─────────┘
             │
             ├──────────────────────┐
             ▼                      ▼
    ┌──────────────────┐   ┌──────────────────┐
    │  PHASE H4        │   │  PHASE H5        │
    │  Apex Agent      │   │  Swarm Dashboard │
    │                  │   │                  │
    │  Shadow Loop     │   │  Topology viz    │
    │  LLM polling     │   │  TPS counter     │
    │  Lisp hot-swap   │   │  Leaderboard     │
    │  Policy evolve   │   │  Hand feed       │
    │                  │   │  Anchor chain    │
    └──────────────────┘   └──────────────────┘
```

---

## Critical Path

The **longest chain** determines the minimum calendar time:

```
H1 (1–2 hrs) → H3 (2–3 hrs) → H4 (2 hrs) = 5–7 hours
```

H2, H5 are **off the critical path** and can be parallelised.

---

## Execution Order (Sessions)

### Wave 1 — Parallel (no dependencies between them)

| Session | Phase | Est. Time | What | Branch |
|---------|-------|-----------|------|--------|
| **S1** | **H1** | 1–2 hrs | DockerMulticastAdapter, docker-compose.hackathon.yml, bot entrypoint, table formation | `hackathon/h1-docker-swarm-mesh` |
| **S2** | **H2** | 1–2 hrs | depin.poker grammar.json, type hashes, 3 Lisp profiles, profile loader | `hackathon/h2-poker-grammar` |

**Why parallel**: H1 is pure infrastructure (Docker + networking). H2 is pure content (grammar + Lisp files). Zero file overlap.

**Gate before Wave 2**: H1's bots can multicast. H2's profiles compile to Forth.

---

### Wave 2 — Depends on H1 + H2

| Session | Phase | Est. Time | What | Branch |
|---------|-------|-----------|------|--------|
| **S3** | **H3** | 2–3 hrs | Border Router container, CellCollector, BatchAggregator, MerkleBatcher, BSV anchor pipeline, Overlay REST+WS API, Provenance SQLite store | `hackathon/h3-border-router` |

**Why sequential**: H3 listens to H1's multicast mesh and validates H2's cell types.

**Gate before Wave 3**: Border Router receives cells, batches to BSV, Overlay API responds.

---

### Wave 3 — Parallel (both depend on H3, independent of each other)

| Session | Phase | Est. Time | What | Branch |
|---------|-------|-----------|------|--------|
| **S4** | **H4** | 2 hrs | Apex Agent container, ShadowLoop, OpponentAnalyser, LLM prompt, Lisp hot-swap, PolicyEvolutionChain | `hackathon/h4-apex-agent` |
| **S5** | **H5** | 1–2 hrs | React dashboard, SwarmTopology, TPSCounter, PersonaLeaderboard, HandFeed, AnchorChain | `hackathon/h5-swarm-dashboard` |

**Why parallel**: H4 is backend (polls Overlay API, rewrites policy). H5 is frontend (connects to Overlay WS, renders). No file overlap.

**Gate**: Apex Agent's win rate climbs above swarm average. Dashboard shows it live.

---

## Session-by-Session Checklist

### S1: Docker Swarm Mesh (H1)

```
□ Create DockerMulticastAdapter implementing NetworkAdapter
   └── packages/protocol-types/src/adapters/docker-multicast-adapter.ts
□ Create docker-compose.hackathon.yml with bot service (replicas: 25)
   └── docker-compose.hackathon.yml
□ Create bot entrypoint script
   └── scripts/hackathon/bot-entrypoint.ts
□ Implement table formation protocol (announce → negotiate → lock)
   └── packages/poker-agent/src/table-formation.ts
□ Implement heartbeat + stale peer eviction
□ Test: 3 containers can multicast cells to each other
□ Test: Table forms automatically when 2+ compatible bots discover each other
```

### S2: Poker Grammar + Lisp Profiles (H2)

```
□ Create depin.poker extension grammar JSON
   └── configs/extensions/poker/grammar.json
□ Register type hashes for all 10 poker cell types
   └── Update packages/cell-ops/src/typeHashRegistry.ts
□ Write nit.lisp, compile to Forth
   └── configs/extensions/poker/profiles/nit.lisp
□ Write maniac.lisp, compile to Forth
   └── configs/extensions/poker/profiles/maniac.lisp
□ Write calculator.lisp, compile to Forth
   └── configs/extensions/poker/profiles/calculator.lisp
□ Create profile loader (BOT_PERSONA env var → compiled policy)
   └── packages/poker-agent/src/profile-loader.ts
□ Test: Each profile compiles without error
□ Test: Grammar validates against Phase 36A schema
```

### S3: Border Router Aggregator (H3)

```
□ Create CellCollector (multicast listener + validation)
   └── packages/border-router/src/cell-collector.ts
□ Create BatchAggregator (30-second windows + Merkle root)
   └── packages/border-router/src/batch-aggregator.ts
□ Create BSV anchor pipeline (OP_RETURN via DirectBroadcastEngine)
   └── packages/border-router/src/anchor-pipeline.ts
□ Create Provenance SQLite store
   └── packages/border-router/src/provenance-store.ts
□ Create Overlay REST API (6 endpoints)
   └── packages/border-router/src/api.ts
□ Create Overlay WebSocket live stream
   └── packages/border-router/src/ws.ts
□ Add border-router service to docker-compose.hackathon.yml
□ Test: Collector receives cells from 2+ bots
□ Test: Batch produces valid Merkle root
□ Test: GET /api/stats returns live data
□ Test: WS /ws/live streams new cells
```

### S4: Apex Agent (H4)

```
□ Create ShadowLoop service (poll → analyse → prompt → compile → swap)
   └── packages/apex-agent/src/shadow-loop.ts
□ Create OpponentAnalyser (fold%, raise%, 3bet% per persona)
   └── packages/apex-agent/src/opponent-analyser.ts
□ Create LLM prompt template + response parser
   └── packages/apex-agent/src/llm-bridge.ts
□ Create PolicyEvolutionChain (RELEVANT cell chain)
   └── packages/apex-agent/src/evolution-chain.ts
□ Implement hot-swap (atomic policy reference replacement)
□ Create Apex container entrypoint
   └── scripts/hackathon/apex-entrypoint.ts
□ Test: Shadow loop fetches hands from Overlay API
□ Test: Valid Lisp from LLM compiles to Forth
□ Test: Hot-swap replaces policy without dropping connections
□ Test: 3-strike revert works on invalid LLM output
```

### S5: Swarm Dashboard (H5)

```
□ Create SwarmTopology (force-directed graph, D3/canvas)
   └── packages/dashboard/src/SwarmTopology.tsx
□ Create TPSCounter (live counter + sparkline + progress to 1.5M)
   └── packages/dashboard/src/TPSCounter.tsx
□ Create PersonaLeaderboard (table + dominance indicator)
   └── packages/dashboard/src/PersonaLeaderboard.tsx
□ Create HandFeed (scrolling feed + BSV txid links)
   └── packages/dashboard/src/HandFeed.tsx
□ Create AnchorChain (visual Merkle root blocks)
   └── packages/dashboard/src/AnchorChain.tsx
□ Create Dashboard shell (layout, WS connection, dark theme)
   └── packages/dashboard/src/App.tsx
□ Test: Dashboard connects to WS and renders topology
□ Test: TPS counter updates in real-time
```

---

## Merge Strategy

Each session creates a feature branch from `hackathon/semantos-swarm`:

```bash
# Wave 1 (parallel)
git checkout hackathon/semantos-swarm -b hackathon/h1-docker-swarm-mesh
git checkout hackathon/semantos-swarm -b hackathon/h2-poker-grammar

# After Wave 1: merge both back
git checkout hackathon/semantos-swarm
git merge hackathon/h1-docker-swarm-mesh
git merge hackathon/h2-poker-grammar

# Wave 2
git checkout hackathon/semantos-swarm -b hackathon/h3-border-router

# After Wave 2: merge back
git checkout hackathon/semantos-swarm
git merge hackathon/h3-border-router

# Wave 3 (parallel)
git checkout hackathon/semantos-swarm -b hackathon/h4-apex-agent
git checkout hackathon/semantos-swarm -b hackathon/h5-swarm-dashboard

# After Wave 3: merge both back
git checkout hackathon/semantos-swarm
git merge hackathon/h4-apex-agent
git merge hackathon/h5-swarm-dashboard
```

---

## Timeline (Optimistic vs Conservative)

| Scenario | Wave 1 | Wave 2 | Wave 3 | Total |
|----------|--------|--------|--------|-------|
| **Optimistic** (1 hr/PRD) | 1 hr | 2 hrs | 1 hr | **4 hrs** |
| **Realistic** (your pace) | 2 hrs | 3 hrs | 2 hrs | **7 hrs** |
| **Conservative** (debugging) | 3 hrs | 4 hrs | 3 hrs | **10 hrs** |

You have until April 17 23:59 UTC. Plenty of time.

---

## Risk Mitigations

| Risk | Mitigation |
|------|-----------|
| Docker multicast doesn't work on Docker Desktop (macOS) | Fall back to UDP broadcast on bridge subnet (no multicast, just broadcast to 255.255.255.255:9000) |
| Claude API rate limits during Apex Agent loop | Cache last response; extend poll interval to 120s; use Haiku (cheaper, faster) |
| BSV testnet congestion blocks anchor TXs | Use mainnet with dust amounts; or queue and retry with exponential backoff |
| 25 containers overwhelm laptop | Scale down to 5 for dev; scale up for final demo run on a cloud VM |
| Dashboard WebSocket overwhelmed | Throttle WS events to 10/sec max; batch updates |

---

## Post-Hackathon: ESP32 Swap

When the Seeed Studio ESP32-C6 boards arrive (April 19), the swap is surgical:

```
H1's DockerMulticastAdapter    →  Phase 33's OpenThreadAdapter
H3's Border Router (Docker)    →  Phase 33's Gateway (TypeScript on Pi/laptop)
H1's docker-compose scaling    →  Physical mesh (2× ESP32-H2 + 1× ESP32-C6)
```

Everything else — kernel, Lisp profiles, grammar, payment channels, Apex Agent,
dashboard — remains 100% untouched. That's the point of the adapter architecture.

---

## Files Created by This Hackathon Sprint

### New Packages
- `packages/border-router/` — H3
- `packages/apex-agent/` — H4
- `packages/dashboard/` — H5

### New Files in Existing Packages
- `packages/protocol-types/src/adapters/docker-multicast-adapter.ts` — H1
- `packages/poker-agent/src/table-formation.ts` — H1
- `packages/poker-agent/src/profile-loader.ts` — H2

### New Config Files
- `configs/extensions/poker/grammar.json` — H2
- `configs/extensions/poker/profiles/nit.lisp` — H2
- `configs/extensions/poker/profiles/maniac.lisp` — H2
- `configs/extensions/poker/profiles/calculator.lisp` — H2

### New Scripts
- `scripts/hackathon/bot-entrypoint.ts` — H1
- `scripts/hackathon/apex-entrypoint.ts` — H4

### Modified Files
- `docker-compose.hackathon.yml` — H1, H3 (new file, extended in H3)
- `packages/cell-ops/src/typeHashRegistry.ts` — H2 (register poker type hashes)
