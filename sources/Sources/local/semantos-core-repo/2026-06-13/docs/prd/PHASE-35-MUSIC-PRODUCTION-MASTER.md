---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-35-MUSIC-PRODUCTION-MASTER.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.678276+00:00
---

# Phase 35 — Music Production Extension: Semantic DAW Collaboration & Version Control

**Version**: 1.0
**Date**: April 2026
**Status**: Draft PRD
**Duration**: 4–6 weeks (with 20% buffer: ~5–7.5 weeks)
**Prerequisites**: Phase 26A–26H complete (four adapter interfaces + extension loading), Phase 30E (WASM target for browser)
**Branch prefix**: `phase-35-music-production`

---

## Context

Music production has a version control problem. Every DAW — Ableton, Logic, FL Studio, Reaper — stores project state as a monolithic binary or XML blob. Ableton's `.als` files are gzipped XML; Logic's `.logicx` bundles are directories of plists and binary chunks. Saving creates a complete snapshot. Comparing two versions means diffing megabytes of opaque structure where a single knob turn changes one attribute buried thousands of lines deep.

The result: producers end up with `track_v3_final_FINAL_mixdown2.als` on their desktop and lose the ability to answer "what exactly changed between Tuesday's session and Wednesday's?" Collaboration is worse — two producers working on the same track email project files back and forth, manually merging changes by ear. There is no `git blame` for music.

Semantos solves this by treating every discrete musical action as a semantic patch cell, storing content in a three-tier CAS with LCS delta deduplication, and using the existing dispatch envelope pattern for real-time multi-party collaboration — the same pattern that connects a PM to a tradie, connecting producer A's drums to producer B's synths.

### What This Is Not

This is not a DAW. Semantos does not record audio, host VSTs, or render waveforms. It is a **version control and collaboration layer** that sits alongside any DAW, capturing state changes, computing minimal deltas, enabling branch/merge/cherry-pick, and federating changes between collaborating nodes. The DAW remains the instrument. Semantos is the memory.

### Commercial Motivation

Music production is a $5.5B market (2024) growing at ~8% CAGR. Every serious producer has experienced version hell. Collaboration tools (Splice, BandLab, Soundtrap) either force you into their DAW or offer crude file-sharing with no structural awareness. No tool provides Git-level version control with DAW-level structural understanding.

Revenue model follows the established pattern:
- **Extension purchase**: one-time ($49–$79) from the marketplace
- **Node storage**: MFP-metered, pay for what you use — a bedroom producer stores a few GB, a professional studio stores terabytes
- **Collaboration channels**: MFP-metered per-session, same payment channel pattern as every other extension
- **Premium modules**: stem separation, AI-assisted merge conflict resolution, mastering chain version management — marketplace extensions on top of the base extension

---

## Architecture: Three-Tier Semantic Storage

The core insight: separate the **semantic layer** (what changed and why) from the **content layer** (the actual bytes) from the **snapshot layer** (materialized project states). Each tier has different storage characteristics and deduplication strategies.

```
┌─────────────────────────────────────────────────────────────┐
│               SEMANTIC PATCH LOG (Tier 1)                    │
│  Append-only log of intent-level operations                  │
│  Each entry is a semantic cell with taxonomy classification  │
│                                                              │
│  "Add Serum VST to Track 3"                                 │
│  "Set filter cutoff to 2.4kHz on Track 3 > Serum > Filter"  │
│  "Move clip 'verse_vocal' from bar 8 to bar 12"             │
│  "Automate reverb send from 0% to 40% over bars 16-20"     │
│                                                              │
│  Cell size: 256 bytes – 1KB per patch                        │
│  Growth rate: ~50-500 patches per session                    │
└──────────────────────────┬──────────────────────────────────┘
                           │ references (content hashes)
┌──────────────────────────┴──────────────────────────────────┐
│            CONTENT-ADDRESSABLE STORE (Tier 2)                │
│  CAS with LCS delta deduplication                            │
│                                                              │
│  Content blocks stored by SHA-256 hash                       │
│  Identical content across projects stored once               │
│  LCS diffing between consecutive states → minimal deltas     │
│  Delta chains with configurable max depth before snapshot    │
│                                                              │
│  A knob turn: ~8-64 bytes (parameter ID + new value)         │
│  A new VST preset: ~2-50KB (stored once, referenced many)    │
│  An audio clip: content-addressed, deduped across projects   │
│                                                              │
│  Disk cost ∝ information changed, NOT file size              │
└──────────────────────────┬──────────────────────────────────┘
                           │ materialized on demand
┌──────────────────────────┴──────────────────────────────────┐
│          MATERIALIZED SNAPSHOTS (Tier 3)                     │
│  Full project states computed by replaying patches           │
│                                                              │
│  Cached at configurable intervals (every N patches,          │
│  every session boundary, on explicit "save point")           │
│  Any historical state recoverable by replay to that point    │
│  Snapshot cache size = disk budget knob                      │
│                                                              │
│  Bedroom producer: cache last 5 snapshots, replay the rest   │
│  Pro studio: cache every session boundary, fast random access │
└─────────────────────────────────────────────────────────────┘
```

### LCS Delta Engine

The Longest Common Subsequence diffing operates at the **structured content level**, not raw bytes. A DAW project, once parsed into the Semantos object model, is a tree of typed nodes (tracks, clips, plugins, parameters, automation lanes). The LCS engine compares two trees and produces a minimal edit script:

```
TreeDelta {
  inserts:  [{ path: "tracks[3].plugins[0]", value: <SerumState> }]
  removes:  []
  updates:  [{ path: "tracks[3].plugins[0].params.filter_cutoff",
               old: 2400, new: 2600 }]
  moves:    [{ from: "tracks[1].clips[2].start", to: bar(12) }]
}
```

The delta is the semantic patch cell's payload. The CAS stores the delta, not the full state. Consecutive deltas form a chain. When the chain gets long (configurable — default 64 deltas), a full snapshot is materialized and the chain resets.

This means the storage cost of turning a knob from 2.4kHz to 2.6kHz is **8 bytes** (parameter path hash + new value), not a new copy of the entire project file.

### Deduplication Across Projects

The CAS deduplicates at the content block level. Two projects using the same Serum preset store it once. A sample pack imported into 50 projects consumes disk once. Audio stems shared between a mix project and a mastering project point to the same content hash.

This is the same content-addressing that Git uses for blobs, extended with:
1. **Structural awareness** — the system knows "this is a VST preset" vs "this is an audio clip" vs "this is an automation curve", enabling type-specific delta compression
2. **Cross-project dedup** — Git deduplicates within a repo; the CAS deduplicates across all projects on the node
3. **Configurable granularity** — the operator (studio, producer, label) decides how fine-grained to track: every parameter change, or batched per save

---

## Extension Grammar

Following the `PaskianStoryGrammar` and `DEPIN_TYPES` patterns:

```typescript
export const MUSIC_PRODUCTION_TYPES = {
  // === Projects ===
  // A project (Ableton set, Logic project, etc.) — always accessible
  'music.project':                    LINEARITY.RELEVANT,
  // Project configuration (tempo, time sig, sample rate) — always accessible
  'music.project.config':             LINEARITY.RELEVANT,

  // === Tracks ===
  // Audio/MIDI/bus/return track — exists while in project
  'music.track':                      LINEARITY.RELEVANT,
  // Track state snapshot (volume, pan, mute, solo, routing)
  'music.track.state':                LINEARITY.RELEVANT,

  // === Clips & Regions ===
  // Audio clip reference — content-addressed, deduped
  'music.clip.audio':                 LINEARITY.RELEVANT,
  // MIDI clip — note data, CC data
  'music.clip.midi':                  LINEARITY.RELEVANT,
  // Clip arrangement position (which bar, which track, duration)
  'music.clip.placement':             LINEARITY.RELEVANT,

  // === Plugins & Processing ===
  // VST/AU/CLAP plugin instance on a track
  'music.plugin.instance':            LINEARITY.RELEVANT,
  // Plugin preset/state blob — content-addressed in CAS
  'music.plugin.state':               LINEARITY.RELEVANT,
  // Individual parameter value
  'music.plugin.parameter':           LINEARITY.RELEVANT,

  // === Automation ===
  // Automation lane (parameter + envelope)
  'music.automation.lane':            LINEARITY.RELEVANT,
  // Automation breakpoint (time + value + curve type)
  'music.automation.point':           LINEARITY.RELEVANT,

  // === Mix State ===
  // Full mixer snapshot (all faders, pans, sends, buses)
  'music.mix.snapshot':               LINEARITY.RELEVANT,
  // Send routing (source → bus, level, pre/post)
  'music.mix.send':                   LINEARITY.RELEVANT,

  // === Version Control ===
  // Semantic patch — the atomic unit of change (LINEAR: applied once)
  'music.patch':                      LINEARITY.LINEAR,
  // Branch tip — only one writer advances (LINEAR: consumed on advance)
  'music.branch.tip':                 LINEARITY.LINEAR,
  // Merge commit — records two parent states merging
  'music.merge':                      LINEARITY.LINEAR,
  // Tag / save point — named snapshot reference
  'music.tag':                        LINEARITY.RELEVANT,
  // Cherry-pick record — provenance of which patches were selected
  'music.cherrypick':                 LINEARITY.LINEAR,

  // === Collaboration ===
  // Session — a live collab session between producers (AFFINE: can be abandoned)
  'music.session':                    LINEARITY.AFFINE,
  // Session invite — capability token for joining (LINEAR: used once)
  'music.session.invite':             LINEARITY.LINEAR,
  // Conflict — two patches touching the same parameter (LINEAR: must be resolved)
  'music.conflict':                   LINEARITY.LINEAR,
  // Review comment — feedback on a specific patch or range
  'music.review':                     LINEARITY.RELEVANT,

  // === Content Store ===
  // CAS content block — raw bytes, content-addressed
  'music.content.block':              LINEARITY.RELEVANT,
  // Delta — LCS-computed diff between two content states
  'music.content.delta':              LINEARITY.RELEVANT,
  // Materialized snapshot — cached full project state
  'music.content.snapshot':           LINEARITY.AFFINE,
} as const;
```

### Why These Linearity Choices

| Type | Linearity | Reason |
|------|-----------|--------|
| `music.patch` | LINEAR | A patch is applied exactly once. Cannot be duplicated or double-applied. Consuming the patch cell IS applying it. |
| `music.branch.tip` | LINEAR | Only the holder of the tip token can advance the branch. Prevents concurrent pushes without locks. Merge consumes two tips, produces one. |
| `music.session.invite` | LINEAR | An invite is used once. Prevents invite link forwarding — the token is consumed on join. |
| `music.conflict` | LINEAR | A conflict must be resolved exactly once. Consuming it IS resolving it (by choosing a side or providing a merged value). |
| `music.session` | AFFINE | A session can be abandoned (discarded) without being "completed". No obligation to finish a collab session. |
| `music.content.snapshot` | AFFINE | Snapshots can be evicted (discarded) when disk pressure requires it. The patch log can always reconstruct them. |
| Everything else | RELEVANT | Reference data that can be read many times. Track definitions, plugin states, content blocks — always accessible. |

### Anchor Policy

```typescript
export const MUSIC_ANCHOR_POLICY: AnchorPolicy = {
  requireAnchorOn: ['linear_consume', 'branch_advance', 'tag_create'],
  complianceEvents: ['session_closed', 'project_published', 'conflict_resolved'],
  batchInterval: 300_000, // 5 minutes — studio sessions batch
};
```

---

## DAW Integration Model

Semantos does not modify the DAW. It observes state changes from outside and decomposes them into semantic patches.

### Integration Tiers

**Tier 1: File watcher (works with any DAW)**
- Watches the project file for saves
- On save: parses the new project state, computes TreeDelta against previous state, emits semantic patches
- Granularity: per-save (coarsest)
- Works immediately with Ableton (.als → XML), Logic (.logicx → plist), Reaper (.rpp → plaintext), FL Studio (.flp → binary with known format)

**Tier 2: DAW API / control surface (richer integration)**
- Ableton: Max for Live device using the Live Object Model (LOM) — observes parameter changes, clip movements, device additions in real-time
- Logic: OSC bridge or control surface script
- Reaper: ReaScript (Lua/Python) monitoring state changes via the API
- Granularity: per-action (every knob turn, every clip move)

**Tier 3: Plugin bridge (deepest integration)**
- A VST3/CLAP plugin that runs inside the DAW, with direct access to host callbacks
- Captures parameter changes at the sample-accurate level
- Can inject "branch switch" as a transport-like action
- Granularity: per-parameter-change (finest)

Each tier feeds the same semantic patch pipeline. The extension works at Tier 1 out of the box. Tiers 2 and 3 are optional deeper integrations developed per-DAW.

### Ableton .als Parser

The primary Tier 1 target. Ableton's `.als` format:
- Gzipped XML
- Well-documented community schema (Ableton's XML structure is stable across versions)
- Contains: tracks, clips, devices (VSTs), automation, mixer state, arrangement, session view

The parser decomposes an `.als` file into the Semantos object tree:

```
AbletonProject
├── GlobalConfig (tempo, time_sig, sample_rate, groove_pool)
├── Tracks[]
│   ├── AudioTrack
│   │   ├── name, color, volume, pan, mute, solo
│   │   ├── DeviceChain[]
│   │   │   ├── PluginInstance (VST/AU reference + state blob)
│   │   │   └── PluginInstance
│   │   ├── ClipSlots[] (session view)
│   │   │   └── AudioClip (sample ref, warp markers, gain, pitch)
│   │   └── ArrangementClips[] (arrangement view)
│   │       └── AudioClip @ bar position
│   ├── MidiTrack
│   │   ├── DeviceChain[]
│   │   ├── ClipSlots[]
│   │   │   └── MidiClip (notes[], CCs[], length)
│   │   └── ArrangementClips[]
│   └── ReturnTrack
│       └── DeviceChain[]
├── Sends[] (routing matrix)
├── MasterTrack
│   └── DeviceChain[]
└── Scenes[] (session view scene metadata)
```

Two parses, one TreeDelta. That's the fundamental operation.

---

## Collaboration: Sessions as Dispatch Envelopes

Multi-producer collaboration uses the same dispatch envelope pattern as cross-extension dispatch (PM ↔ tradie), applied to music production.

### The Session Object

When Producer A invites Producer B to collaborate:

```
Session Envelope (semantic object)
│
├── Shared patches (RELEVANT — both producers see):
│   - Project structure (tracks, routing, arrangement)
│   - Committed patches to shared branches
│   - Tags / save points
│   - Review comments
│
├── Producer A patches (AFFINE — A only):
│   - Work-in-progress on A's branches
│   - "I'm trying three different kick samples" (uncommitted experiments)
│   - Internal notes ("the verse needs to be 4 bars shorter")
│   - Local plugin states not ready for review
│
├── Producer B patches (AFFINE — B only):
│   - Same: private experiments, notes, local WIP
│
└── Conflict resolution (LINEAR — consumed on resolve):
    - Both touched master bus EQ → conflict cell created
    - Resolution: A/B test both, pick one, or manual merge
    - Consuming the conflict cell IS the resolution
```

### Conflict Detection and Resolution

Conflicts occur when two patches in the same session touch the same parameter path within the same time window. The system detects conflicts at merge time (like Git), not in real-time (not OT/CRDT — that's a different architecture with different tradeoffs).

```
Producer A: set tracks[2].plugins[0].params.filter_cutoff = 2400
Producer B: set tracks[2].plugins[0].params.filter_cutoff = 3200

→ music.conflict cell created:
  {
    parameterPath: "tracks[2].plugins[0].params.filter_cutoff",
    patchA: { value: 2400, author: A.cert, timestamp: T1 },
    patchB: { value: 3200, author: B.cert, timestamp: T2 },
    resolution: null  // LINEAR — must be consumed by resolving
  }
```

Resolution strategies:
1. **Pick a side**: "Use A's value" → consumes conflict, applies A's patch
2. **New value**: "Actually, 2800 is the compromise" → consumes conflict, creates new patch
3. **A/B render**: system renders both versions for listening comparison → producer picks after hearing both
4. **Scope split**: "A owns the low end, B owns the highs" → capability token scoping, prevents future conflicts on those parameter ranges

### Independent vs. Dependent Patches

Most music production changes are **independent** — Producer A editing drums on tracks 1-4 and Producer B editing synths on tracks 5-8 produce patches that commute (can be applied in either order). The system tracks dependency via parameter paths:

- **Independent**: different tracks, different plugins, different automation lanes → auto-merge, no conflict
- **Dependent**: same parameter path → conflict detection at merge
- **Structural**: adding/removing/reordering tracks → structural conflict, requires manual resolution

This means most real-world collab sessions produce zero conflicts — producers naturally work on different parts of the arrangement.

---

## Version Control Operations

The extension provides Git-like operations translated to the music production domain:

### Branch

```
sem music branch create "vocal-experiment"
```

Creates a new `music.branch.tip` LINEAR cell forked from the current state. The producer can experiment freely — changes go to the branch, not to main. Multiple branches can coexist (different vocal takes, different mix approaches, different arrangements).

### Merge

```
sem music merge "vocal-experiment" into "main"
```

Consumes both branch tip cells, produces a new `music.merge` LINEAR cell and a new `music.branch.tip` for main. If patches conflict, `music.conflict` cells are created for each conflicting parameter. Merge does not complete until all conflicts are consumed (resolved).

### Cherry-Pick

```
sem music cherry-pick <patch-range> from "experimental-reverbs"
```

"I want the reverb settings from Thursday's session but keep the drum pattern from today." Selects specific `music.patch` cells from another branch and applies them to the current branch. The `music.cherrypick` cell records provenance — which patches came from where.

### Tag

```
sem music tag "pre-mastering-mix" 
```

Creates a `music.tag` RELEVANT cell pointing to the current state hash. Named reference point. Cheap to create (just a pointer), anchored to BSV for timestamping.

### Diff

```
sem music diff "tuesday-session".."wednesday-session"
```

Computes and displays the TreeDelta between two points. Shows: tracks added/removed, plugins changed, parameters adjusted, clips moved, automation curves modified. Human-readable output, not raw bytes.

### Log

```
sem music log --last 50
```

Shows the semantic patch history. Each entry shows the operation type, the affected component, the author (in collab), and the timestamp. Filterable: `sem music log --track "Bass" --last 20` shows only changes to the bass track.

---

## Storage Budget and Granularity Dial

The operator (studio, producer, label) controls the tradeoff between granularity and disk usage:

### Profiles

```typescript
export const STORAGE_PROFILES = {
  // Bedroom producer — laptop, limited SSD
  'minimal': {
    patchGranularity: 'per-save',        // Tier 1 only
    deltaChainMaxDepth: 128,             // long chains, fewer snapshots
    snapshotCacheCount: 3,               // only recent snapshots cached
    audioDedup: true,                    // samples deduped across projects
    estimatedOverhead: '2-5% of project size per save',
  },

  // Professional studio — NAS or server
  'standard': {
    patchGranularity: 'per-action',      // Tier 2, every discrete action
    deltaChainMaxDepth: 64,
    snapshotCacheCount: 20,              // per-session-boundary snapshots cached
    audioDedup: true,
    estimatedOverhead: '10-20% of project size per session',
  },

  // Archive / label — every change matters
  'maximum': {
    patchGranularity: 'per-parameter',   // Tier 3, every knob turn
    deltaChainMaxDepth: 32,              // short chains, frequent snapshots
    snapshotCacheCount: 'unlimited',     // cache everything, disk is cheap
    audioDedup: true,
    estimatedOverhead: '30-50% of project size per session',
  },
} as const;
```

Storage cost is metered via MFP — the producer pays for actual bytes stored, not a subscription tier. Quiet months (no new projects) cost near zero. An album production sprint costs proportionally more. The CAS deduplication means the cost is always less than naive file copying.

---

## Node Deployment Profiles

### Bedroom Producer (Laptop)

```
storage:   NodeFsAdapter('~/.semantos/music')
identity:  CloudIdentityAdapter (Plexus RaaS)
anchor:    BsvAnchorAdapter (every 30 min — session-boundary batching)
network:   StubNetworkAdapter (solo producer, no federation)
extensions: [music-production]
profile:   'minimal'
```

### Professional Studio (Server / NAS)

```
storage:   NodeFsAdapter('/mnt/studio-nas/semantos')
identity:  LocalIdentityAdapter (studio cert chain)
anchor:    BsvAnchorAdapter (every 5 min)
network:   BsvOverlayNetworkAdapter (federation with collaborators)
extensions: [music-production, music-mastering]
profile:   'standard'
```

### Record Label (Enterprise)

```
storage:   NodeFsAdapter('/data/label-archive/semantos')
identity:  LocalIdentityAdapter (label + artist certs)
anchor:    BsvAnchorAdapter (every 1 min — contractual audit trail)
network:   BsvOverlayNetworkAdapter + DirectNetworkAdapter (studio LAN)
extensions: [music-production, music-mastering, music-rights]
profile:   'maximum'
```

---

## Deliverables

### D35.1 — Music Production Extension Grammar (TypeScript)

New file: `configs/extensions/music-production.json`
New file: `packages/music-engine/src/grammar.ts`

- `MUSIC_PRODUCTION_TYPES` with linearity assignments per type table above
- `MUSIC_ANCHOR_POLICY` with session-boundary batch semantics
- `MusicProductionGrammar` exported following `PaskianStoryGrammar` pattern
- Type hashes registered in `cell-ops/src/typeHashRegistry.ts`
- Storage profile configurations

### D35.2 — Three-Tier Storage Engine (TypeScript)

New package: `packages/music-engine/src/storage/`

- `semantic-log.ts` — append-only semantic patch log backed by StorageAdapter
- `content-store.ts` — CAS with SHA-256 content addressing, block-level dedup
- `delta-engine.ts` — LCS tree diff computation, delta chain management, structured TreeDelta format
- `snapshot-cache.ts` — materialized snapshot management, LRU eviction, replay-from-patches reconstruction
- `storage-budget.ts` — profile configuration, disk usage monitoring, MFP metering integration

### D35.3 — DAW Project Parser Framework (TypeScript)

New package: `packages/music-engine/src/parsers/`

- `parser-interface.ts` — `DawParser` interface: `parse(bytes: Uint8Array) → ProjectTree`, `serialize(tree: ProjectTree) → Uint8Array`
- `ableton-parser.ts` — `.als` (gzipped XML) parser/serializer, full object tree extraction
- `project-tree.ts` — canonical project tree model (DAW-agnostic): tracks, clips, plugins, parameters, automation, routing, arrangement
- `tree-diff.ts` — structural tree comparison producing `TreeDelta` objects

Future parsers (not in this phase): `reaper-parser.ts` (.rpp), `logic-parser.ts` (.logicx), `flstudio-parser.ts` (.flp)

### D35.4 — Version Control Operations (TypeScript)

New package: `packages/music-engine/src/vcs/`

- `branch.ts` — branch create, branch tip management (LINEAR token handling), list branches
- `merge.ts` — three-way merge of patch logs, conflict detection by parameter path, conflict cell creation
- `cherry-pick.ts` — patch range selection, dependency analysis, provenance recording
- `tag.ts` — named save points, anchor integration for timestamping
- `diff.ts` — human-readable TreeDelta rendering (CLI and structured output)
- `log.ts` — patch history query, filtering by track/plugin/time/author

### D35.5 — Collaboration Engine (TypeScript)

New package: `packages/music-engine/src/collab/`

- `session.ts` — session creation, invite token management (LINEAR), participant tracking
- `envelope.ts` — dispatch envelope for cross-node collaboration, facet management (RELEVANT shared / AFFINE private)
- `conflict-resolver.ts` — conflict detection, resolution strategies (pick-side, new-value, scope-split), LINEAR conflict cell consumption
- `sync.ts` — real-time patch synchronization between nodes via NetworkAdapter, causal ordering

### D35.6 — File Watcher Service (TypeScript)

New package: `packages/music-engine/src/watcher/`

- `watcher.ts` — filesystem watcher for DAW project files, debounced change detection
- `ingest.ts` — on change: parse new state, compute TreeDelta, emit semantic patches to log
- `ableton-watcher.ts` — Ableton-specific: watches `.als` file, handles Ableton's temp file pattern (`*.als.tmp` → rename)

### D35.7 — Semantic Shell Commands

New file: `packages/music-engine/src/shell/commands.ts`

Shell command registrations following the semantic shell pattern:

```
sem music init <project-file>          — initialise tracking on an existing project
sem music status                       — show uncommitted changes since last tracked state
sem music commit "message"             — commit current patches with message
sem music branch create <name>         — create branch
sem music branch list                  — list branches
sem music merge <source> into <target> — merge branches
sem music cherry-pick <range> from <branch>
sem music tag <name>                   — create named save point
sem music diff <ref>..<ref>            — show changes between two points
sem music log [--track X] [--last N]   — show patch history
sem music session create               — start collab session
sem music session invite <cert>        — generate LINEAR invite token
sem music session join <token>         — join session (consumes invite)
sem music snapshot create              — force materialized snapshot
sem music snapshot list                — list cached snapshots
sem music export <ref> --format als    — materialise and export as native DAW format
```

### D35.8 — Ableton Integration Example

New directory: `packages/music-engine/examples/ableton-tracking/`

- Working example: initialise tracking on a real `.als` file
- Demonstrate: save file in Ableton → watcher detects → patches emitted → log updated
- Demonstrate: branch, make changes, merge, view diff
- Demonstrate: cherry-pick a specific plugin change from one branch to another
- Demonstrate: two-node collab session (both tracking the same project, patches sync via NetworkAdapter)
- README with screenshots and walkthrough

---

## Phase Decomposition

```
Phase 35A: D35.1 + D35.2                  (grammar + three-tier storage engine)
Phase 35B: D35.3                           (DAW parser framework + Ableton parser)
Phase 35C: D35.4 + D35.7                   (VCS operations + shell commands)
Phase 35D: D35.5 + D35.6                   (collaboration engine + file watcher)
Phase 35E: D35.8                           (Ableton integration example)
```

```
35A ──→ 35B ──→ 35C ──→ 35E
  │              ↑
  └──→ 35D ─────┘
```

35A and 35D can start in parallel (collab engine needs grammar but not the parser). 35B needs 35A (storage engine). 35C needs 35B (VCS operates on parsed trees). 35D needs 35A (session envelopes use grammar types). 35E needs all four.

Critical path: ~4–5 weeks from 35A start.

---

## The Ableton Use Case: End to End

A concrete walkthrough of how this works in practice.

### Solo producer, Tuesday night session

1. Producer opens Ableton, loads `summer_track.als`
2. Semantos watcher is running: `sem music init summer_track.als` was run previously
3. Producer adds a Serum VST to Track 3 → saves
4. Watcher detects save, parses `.als`, computes TreeDelta:
   ```
   + tracks[3].plugins[0] = { type: "VST", name: "Serum", state: <sha256:abc123> }
   ```
5. `music.patch` LINEAR cell created, appended to log
6. CAS stores Serum's initial preset state blob at `sha256:abc123`
7. Producer tweaks filter cutoff from 2.4kHz to 2.6kHz → saves
8. TreeDelta: `Δ tracks[3].plugins[0].params.filter_cutoff: 2400 → 2600` (8 bytes)
9. Producer works for 3 hours, makes 200 saves. Total new storage: ~50KB of deltas + a few MB for any new audio clips. Not 200 copies of a 50MB project file.

### Wednesday: "I liked Tuesday's bass better"

10. `sem music log --track "Bass" --last 30` — shows every change to the bass track
11. `sem music diff tuesday-end..now --track "Bass"` — shows exactly what changed
12. `sem music branch create "restore-tuesday-bass"`
13. `sem music cherry-pick <patch-ids> from tuesday-end` — grabs just the bass patches
14. `sem music export HEAD --format als` — materialises the hybrid state as a `.als` file
15. Producer opens the exported `.als` in Ableton — Wednesday's arrangement with Tuesday's bass sound

### Thursday: collab session with producer B

16. `sem music session create` → session envelope created
17. `sem music session invite B.cert` → LINEAR invite token generated, sent to B's node
18. B: `sem music session join <token>` → token consumed, B is now a participant
19. A works on drums (tracks 1-4), B works on synths (tracks 5-8) — independent patches, no conflicts
20. B pushes changes → A's node receives patches via NetworkAdapter → auto-merged (independent paths)
21. Both touch master bus compressor → `music.conflict` LINEAR cell created
22. A: `sem music conflict list` → shows the compressor conflict
23. A: `sem music conflict resolve <id> --strategy pick-b` → consumes conflict cell, applies B's value
24. `sem music session close` → session envelope finalised, anchored to BSV

The entire history — every change, every branch, every collab decision — is preserved in the semantic patch log with cryptographic provenance. A year later, anyone with read access can replay exactly how this track was built, who contributed what, and when.

---

## Future Extensions (Not in This Phase)

- **music-mastering**: mastering chain version control, reference track comparison, loudness targeting — separate extension that loads alongside music-production
- **music-rights**: split sheet management as semantic objects, LINEAR ownership tokens, royalty calculation, ISRC/ISWC registration anchored to BSV — the "who owns what" layer
- **music-stems**: AI-powered stem separation integrated with the CAS — separate a mix into stems, each stem becomes a content block, remixers can branch from individual stems
- **music-live**: real-time performance capture, set list as semantic object, per-song patch snapshots for live rig recall
- **DAW-specific Tier 2/3 plugins**: Max for Live device for Ableton, ReaScript for Reaper, Logic control surface — deeper real-time integration per DAW

---

## Cumulative Phase Completion

Phase 35 is complete when:

1. `music-production.json` extension config exists with all object types, linearity assignments, and taxonomy nodes
2. Grammar file exports `MUSIC_PRODUCTION_TYPES` and `MUSIC_ANCHOR_POLICY` following established patterns
3. Three-tier storage engine (semantic log + CAS + snapshot cache) passes unit tests with configurable profiles
4. LCS delta engine correctly computes minimal TreeDeltas between project tree states
5. Ableton `.als` parser correctly decomposes a real project file into the canonical ProjectTree model
6. Round-trip test: parse `.als` → serialize → parse → trees are identical
7. All VCS operations (branch, merge, cherry-pick, tag, diff, log) work correctly on the semantic patch log
8. Branch tips are LINEAR — concurrent advance attempts fail deterministically
9. Merge conflict detection correctly identifies overlapping parameter paths
10. Conflict resolution consumes the LINEAR conflict cell exactly once
11. Collaboration session with two nodes: patches sync, independent changes auto-merge, conflicts surface correctly
12. File watcher correctly detects Ableton saves and emits semantic patches
13. Shell commands registered and functional
14. Ableton integration example runs end-to-end
15. All existing gate tests still pass (no regressions)
16. `npm run build` succeeds with zero errors

---

## Next Phase

Phase 35F (future): Tier 2 Ableton integration via Max for Live device — real-time parameter observation without requiring file saves, enabling per-knob-turn granularity. Phase 35G: Reaper parser (.rpp format). Phase 35H: music-rights extension for ownership and royalty management as semantic objects.
