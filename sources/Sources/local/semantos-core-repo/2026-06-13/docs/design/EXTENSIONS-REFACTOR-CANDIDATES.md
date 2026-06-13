---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/design/EXTENSIONS-REFACTOR-CANDIDATES.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.736600+00:00
---

# Extensions → cartridges refactor candidates

**Status:** Triage findings + `self` cartridge proposal
**Date:** 2026-05-25
**Context:** Q14 closure (Q14 was T4.b's "wholesale extension migration" question; this document is the answer — bucket-triage, not bulk-migrate)
**Tracker:** [`docs/STRUCTURED-TYPEHASH-TRACKER.md`](../STRUCTURED-TYPEHASH-TRACKER.md) T4.b

---

## TL;DR

The legacy `configs/extensions/*.json` pipeline is **fundamentally different** from cartridges — own loader, own registry, own grammar handling.  Migrating them all to the new triple-based identity is the wrong abstraction match.

Instead, **triage**:
- 4 are alive and stay on the old pipeline (no win in moving them)
- 1 was self-declared dead — **deleted in this PR**
- 6 are orphaned; 3 of those have high design value worth preserving, the other 3 are likely just clutter

Plus one new direction: **`self` cartridge** — a real domain cartridge that absorbs `consciousness.json` (personal practice) + `settlement-story.json` (Paskian narrative substrate).  Per Todd's 2026-05-25 direction: "tied in with settlement-story as well so pask is in the self cartridge."

---

## Triage table

| Config | Object types | Status | Action |
|---|---|---|---|
| `core.json` | 17 | LIVE — hardcoded in `scripts/compute-type-hashes.ts` allowlist | **Leave alone** — works on old pipeline; T4.b migration not justified |
| `trades-services.json` | 7 | LIVE — same | **Leave alone** — overlaps oddjobz cartridge; eventual consolidation but not in this PR |
| `blockchain-risk.json` | 4 | LIVE — same; BREM-Agent risk scoring | **Leave alone** — specialised; refactor to `risk-cartridge` only if it scales |
| `development.json` | 1 | LIVE — debug `Generic Object` type | **Leave alone** — utility |
| `navigation.json` | 16 | DEAD — explicitly `deprecated: true, supersededBy: ["navigator-core", "consciousness-process"]` | ✅ **Deleted in this PR** |
| `consciousness.json` | 14 | ✅ **Deleted 2026-05-25** — content cherry-picked into `cartridges/self/cartridge.json` per T6 + post-cleanup. Bundled loader entry removed from `default-boot.ts`. | **Refactored into `self` cartridge** — flows (12) + theme.colors (17) + capabilities (1) + scripts→enforcementHooks (3) folded in alongside the 14 cellTypes (already moved by T6). |
| `settlement-story.json` | 9 | ORPHANED — no runtime refs | **Refactor into `self` cartridge** as the Paskian substrate layer (see below) |
| `commerce.json` | 6 | ORPHANED — duplicates trades-services concepts | ✅ **Deleted 2026-05-25** — not in `default-boot.ts` bundled loaders, confirmed no consumer |
| `navigator.json` | 1 | ORPHANED — single `ConsumerBinding` type, likely duplicate of `core.json` | ✅ **Deleted 2026-05-25** — `default-boot.ts` `navigator` loader points at the separate `configs/packages/navigator.json` (which doesn't exist anyway); `extensions/navigator.json` had no consumers |
| `host-ops.json` | 1 | LIVE — `HostCommand` is bundle-loaded via `default-boot.ts` + consumed by `runtime/shell/src/commands/host-exec.ts` + `host-audit.ts` | **Keep** — Phase 38A HOST_EXEC capability is real and active. Reclassified from "orphan" to "live" after deeper audit. |
| `commerce-manifest.json` | 0 | Grammar/governance meta | **Leave alone** — referenced by grammar system |
| `propertyme/grammar.json` | 0+6 connector | ORPHANED — REST connector for PropertyMe (OAuth2) | **Cartridge socket** pattern (new concept — see §"Cartridge sockets" below). Not a cartridge itself; not destined to become one. |

---

## The `self` cartridge proposal

**Domain:** Todd's personal practice + narrative-arc learning, surfaced through the PWA.

**Why now:** PWA exists; consciousness + settlement-story content is rich and already designed; pask is the kernel graph engine and "self" is exactly what pask runs over for personal data.

### Proposed shape

```
cartridges/self/
├── cartridge.json
│   {
│     "id": "self",
│     "version": "0.1.0",
│     "role": "domain",
│     "description": "Todd's personal practice cartridge — release/intention/insight
│                     loops + Paskian narrative substrate for arc learning.",
│     "cellTypes": [ /* 18-23 entries, triples below */ ]
│   }
└── brain/
    └── self_cell_specs.zig    # Zig comptime mirror (matches MNCA/Tessera pattern)
```

### Proposed cellTypes (consolidated from consciousness + settlement-story)

All under `segment1 = "self"`.  Routing-prefix property: any relay subscribed to `self.*` does an 8-byte memcmp on cell[30:38] against `sha256("self")[0:8]`.

**Paskian substrate (segment2 = "paskian")** — the graph engine state cells.  Pask is kernel; these cells are pask's *output shape* surfaced as cells for inspection/PWA-rendering:

| name | linearity | from | triple |
|---|---|---|---|
| `self.paskian.graph.node` | RELEVANT | settlement-story.GraphNode | `(self, paskian, graph, node)` |
| `self.paskian.graph.edge` | RELEVANT | settlement-story.GraphEdge | `(self, paskian, graph, edge)` |
| `self.paskian.graph.stabilised` | RELEVANT | settlement-story.StabilityEvent | `(self, paskian, graph, stabilised)` |
| `self.paskian.graph.pruned` | LINEAR | settlement-story.PruningEvent | `(self, paskian, graph, pruned)` |

**Narrative arc (segment2 = "story")** — the arc-shaped reads over the Paskian substrate:

| name | linearity | from | triple |
|---|---|---|---|
| `self.story.thread` | RELEVANT | NarrativeThread | `(self, story, thread, "")` |
| `self.story.artifact` | LINEAR | StoryArtifact | `(self, story, artifact, "")` |
| `self.story.entity` | AFFINE | StoryEntity | `(self, story, entity, "")` |
| `self.story.relation` | RELEVANT | StoryRelation | `(self, story, relation, "")` |
| `self.story.moment` | LINEAR | StoryMoment | `(self, story, moment, "")` |

**Personal practice (segment2 = "practice")** — release/integrate/seal cycle:

| name | linearity | from | triple |
|---|---|---|---|
| `self.practice.release` | LINEAR | Release | `(self, practice, release, "")` |
| `self.practice.session` | LINEAR | Session | `(self, practice, session, "")` |
| `self.practice.intention` | AFFINE | Intention | `(self, practice, intention, "")` |
| `self.practice.insight` | RELEVANT | Insight | `(self, practice, insight, "")` |
| `self.practice.pattern` | RELEVANT | Pattern | `(self, practice, pattern, "")` |
| `self.practice.connection` | LINEAR | Connection | `(self, practice, connection, "")` |
| `self.practice.vacuum` | LINEAR | VacuumSession | `(self, practice, vacuum, "")` |
| `self.practice.seal` | LINEAR | GoldSeal | `(self, practice, seal, "")` |

**Accountability (segment2 = "accountability")** — daily review cycle:

| name | linearity | from | triple |
|---|---|---|---|
| `self.accountability.morning` | LINEAR | MorningIntention | `(self, accountability, morning, "")` |
| `self.accountability.review` | LINEAR | DailyReview | `(self, accountability, review, "")` |
| `self.accountability.pulse` | AFFINE | DimensionPulse | `(self, accountability, pulse, "")` |
| `self.accountability.streak` | RELEVANT | AccountabilityStreak | `(self, accountability, streak, "")` |

**State (segment2 = "state")** — derived current-state cells:

| name | linearity | from | triple |
|---|---|---|---|
| `self.state.dimension` | RELEVANT | DimensionState | `(self, state, dimension, "")` |
| `self.state.elevation` | RELEVANT | ElevationState | `(self, state, elevation, "")` |

**Total: 23 cellTypes** (was 14 consciousness + 9 settlement-story = 23 raw; same count post-consolidation).

### Pask integration shape

**Pask stays in the kernel** (at `core/pask/`) — it does not move into the `self` cartridge.  What the `self` cartridge does:
- Declares the cell shapes that pask emits (`self.paskian.graph.node`, `.edge`, `.stabilised`, `.pruned`) when reducing over personal data
- Declares the cell shapes that pask reads (`self.practice.*`, `self.accountability.*`) — these are the input cells that pask traces relationships over

Conceptually:
```
input cells (self.practice.*, self.accountability.*)
        │
        ▼
   pask kernel (graph engine, h-state stability)
        │
        ▼
output cells (self.paskian.graph.*, self.story.*)
```

The `self.story.*` cells are the **arc-shaped reads** — narrative threads that emerge from the Paskian substrate's stability patterns.

### Routing-prefix property visible

Once minted, the typeHash hex shows the structure:
- All 23 `self.*` cells share bytes 0:7 = `sha256("self")[0:8]`
- All 4 `self.paskian.graph.*` share bytes 0:23
- All 8 `self.practice.*` share bytes 0:15
- All 4 `self.accountability.*` share bytes 0:15

A PWA subscriber to "everything from my personal substrate" does an 8-byte peek.  A subscriber to "just the Paskian arc state" does a 24-byte peek.

---

## Open design decisions for `self` cartridge

These need Todd's call before creating files:

**SQ1 — Field schemas.** Existing schemas in `consciousness.json` / `settlement-story.json` use snake-and-camel mix and lots of single-purpose fields (e.g. `DailyReview` has `win1`, `win1Dimension`, `win2`, `win2Dimension`, `win3`, `win3Dimension`... up to 16 fields).  Migrate as-is or refactor to array shapes (`wins: [{text, dimension}]`)?  Recommendation: migrate as-is for v0.1.0, refactor in v0.2.0 once it survives real PWA use.

**SQ2 — Merge similar cells.**
- `MorningIntention` + `DailyReview` are clearly paired (yesterday's review feeds today's intention).  Keep as 2 cells or merge?  Recommendation: keep separate (different linearity logic).
- `StabilityEvent` + `PruningEvent` are paired graph lifecycle events.  Keep separate (different linearity).
- `Intention` (practice) vs `MorningIntention` (accountability) — overlap in concept but different cadence.  Keep separate.

**SQ3 — PWA surface priority.** Which cells get UI fields (`displayName`, `payloadSchema`, `primaryAnchor`) first?  Recommendation: start with practice cells (release/intention/insight/pattern), defer state + paskian cells (those are derived/computed).

**SQ4 — Zig comptime spec.** Mirror MNCA's `cartridges/mnca/brain/mnca_cell_specs.zig` pattern.  Just identity comptime; pask hot-path stays kernel-side.

**SQ5 — Personal-data privacy / scope.** This cartridge holds personal practice data.  Decide:
- Single-user scope (todd's brain) vs multi-tenant from day one?
- Encryption-at-rest on practice cells, or rely on substrate cell encryption?
- Recommendation: single-user v0.1.0; multi-tenant when other users want it.

**SQ6 — Tracker integration.** Once `self` cartridge ships, this becomes T6 (new step) in the tracker, separate from the typehash-canonical PR scope.  The current PR closes T4.b via triage + documentation; the actual `self` cartridge creation is a follow-up PR.

---

## What this PR does (the close-out)

- ✅ Delete `navigation.json` (explicitly deprecated)
- ✅ Document the triage table here (this file)
- ✅ Document the `self` cartridge proposal (this file) — not creating yet, surfaces SQ1-SQ6 for Todd
- ✅ Tracker: T4.b flipped from "TODO" → "DONE (scope correctly understood — triage, not bulk-migrate)"
- ⏸ Audit-flag entries for `commerce.json` / `navigator.json` / `host-ops.json` deletion in separate small PRs (not blocking)
- ⏸ Actual `cartridges/self/` creation is a follow-up PR (T6) after SQ1-SQ6 decisions

---

## What this PR does NOT do

- Migrate the 4 live extension configs (core, trades-services, blockchain-risk, development).  They keep working on the old pipeline; T4.b's wholesale migration is the wrong abstraction match — extensions and cartridges are different pipelines, not "good cartridges" vs "bad cartridges."
- Touch `commerce-manifest.json` (it's the actual commerce extension manifest; `commerce.json` is the orphan).
- Migrate `propertyme/` connector — see "Cartridge sockets" section below.

---

## Cartridge sockets (new pattern, surfaced 2026-05-25)

Per Todd: "propertyme is probably something more like a cartridge socket than a cartridge itself."

A **cartridge socket** is a connector shape — an adapter that pulls external data (REST APIs, OAuth-secured endpoints, file imports, webhooks, scheduled polls) into cell shapes that any consuming cartridge can subscribe to.  It is NOT a cartridge itself:

| | Cartridge | Cartridge socket |
|---|---|---|
| Declares cellTypes? | yes (its own domain) | no (re-shapes external data into existing cartridge cellTypes) |
| Owns typeHash triples? | yes | no — uses the consuming cartridge's triples |
| Has cartridge.json `cellTypes[]`? | yes | no — has `socketSpec[]` instead |
| Loaded by manifest-loader? | yes | yes, but via different loader path |
| Routing-prefix namespace | `<cartridge>.*` | inherits from data destination (e.g. cells minted on behalf of `nonprofit-os` carry `nonprofit-os.*` triples) |

**Example shape** for `propertyme` as a socket:

```jsonc
// cartridges/propertyme-socket/socket.json (proposed)
{
  "id": "propertyme",
  "kind": "socket",
  "auth": "oauth2",
  "endpoint": "https://api.propertyme.com",
  "entitySockets": [
    {
      "externalEntity": "Property",
      "destinationCellType": "<consumer-supplied>",   // e.g. "nonprofit-os.property"
      "fieldMapping": { /* PropertyMe fields → consumer cell schema */ }
    }
    // ... 5 more entities: Lease, Tenant, MaintenanceRequest, Inspection, Owner
  ]
}
```

The socket runs in the background, polls PropertyMe, transforms external records into cells of the **consumer cartridge's** type.  Multiple consumers can share one socket (e.g. a nonprofit-os tenant + a property-management-cartridge tenant both subscribe to the same PropertyMe socket; each receives cells under their own typeHashes).

**Why this matters architecturally:**
- Sockets are **infrastructure**, not domain.  They're how external data enters the substrate.
- Sockets compose with cartridges via type-targeting (the destination triple is the consumer's choice).
- A future `gmail`, `calendar`, `slack`, `quickbooks` socket follows the same shape.
- Socket auth / refresh / rate-limiting lives in the socket; cartridges stay pure-domain.

**Status:** concept captured here.  Actual implementation deferred — `propertyme/grammar.json` stays as legacy reference until a consumer cartridge (likely a property-management cartridge for Bridget's grants flow) materialises and the socket pattern gets its first real shape.

---

## Other findings from the 2026-05-25 deletion audit

While verifying the 3 orphans for deletion, two infrastructure surprises surfaced (not blockers, just worth flagging):

### `consciousness.json` is still bundle-loaded — duplicate with `self` cartridge

`runtime/services/src/services/config-store/default-boot.ts` bundles `consciousness.json` as an extension at runtime:

```typescript
consciousness: () => import('@configs/extensions/consciousness.json'),
```

T6 created `cartridges/self/cartridge.json` with the same 14 cellTypes (under `(self, practice, *, *)` and `(self, accountability, *, *)` triples) — but didn't remove the old extension config.  Result: **parallel data, different registries, different hashes.**  Not breaking (extension consumers use the extension registry; cartridge consumers use the cartridge registry), just redundant.

When the PWA wires the `self` cartridge as the personal-practice source, the extension entry should be removed from `default-boot.ts` and `consciousness.json` deleted.  Tracked as **post-T6 cleanup**.

### `navigator: () => import('@configs/packages/navigator.json')` points at nonexistent path

`default-boot.ts` registers a `navigator` extension that imports from `@configs/packages/navigator.json` — but `configs/packages/` doesn't exist.  The loader is registered but would fail at runtime if invoked.  Either:
- Some other thing creates `configs/packages/navigator.json` at build time (TBD)
- Or this is a dead bundled-loader entry that needs cleaning up

`configs/extensions/navigator.json` (the file deleted in this PR) was a totally separate orphan, not related to the bundled `navigator` loader.
