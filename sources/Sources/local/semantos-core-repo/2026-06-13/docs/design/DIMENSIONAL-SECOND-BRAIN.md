---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/design/DIMENSIONAL-SECOND-BRAIN.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.733082+00:00
---

# Dimensional Second Brain — Pask as the operator's living graph

**Version**: 0.1 DRAFT
**Status**: Plan
**Authors**: Todd
**Related**: [HELM-ATTENTION-SURFACE.md](HELM-ATTENTION-SURFACE.md) (AS1–AS5, attention scoring + telemetry + signals); [core/pask/PRIMER.md](../../core/pask/PRIMER.md) (kernel contract); [core/pask/README.md](../../core/pask/README.md) (kernel API); commits `5a367ca` → `b890344` (Paskian learning kernel + GA + release pipeline, landed 2026-05-01)

---

## 0. Headline

> Notion stores what you wrote. Obsidian shows what you linked. Neither tells you what's *settled* in your own thinking. The Pask kernel that landed yesterday — constraint-graph learning that surfaced canonical chess openings from raw PGN with zero domain knowledge — applied to the operator's interaction stream gives semantos a property the incumbents structurally cannot have: **a self-organising memory that surfaces the topics your traffic has converged on, decays the ones you abandoned, and replays byte-for-byte from any prior snapshot.** The helm + AttentionSurface + AS1–AS5 telemetry already provide most of the wiring. This plan wires Pask as the merged graph across helm, Obsidian, and Notion; adds a Stable Threads panel; folds graph-proximity into the AttentionEngine; and lands snapshot-based memory rollback as a first-class operator verb.

### What "dimensional" means here

Three orthogonal axes of structure on the same set of objects:

1. **Authored** — what you wrote. Markdown files, Notion pages, helm-authored cells.
2. **Linked** — explicit relations. Wikilinks, Notion relation properties, helm cross-refs.
3. **Settled** — what your traffic converged on. Pask's stable threads, decayed by inactivity, traffic-weighted.

Notion has axis 1 and a structured form of axis 2. Obsidian has 1 and 2 with manual graph view. Semantos has all three, with axis 3 emerging *for free* from the interactions the helm already records — no tagging, no curation. The operator's working memory becomes inspectable, replayable, and forgettable.

### On layering

The Pask kernel is the substrate; the bridges are extensions. Concretely:

- `core/pask/` — kernel, untouched by this plan.
- `runtime/services/src/services/Pask*` — the merged-graph adapter, sitting next to AttentionEngine. One kernel instance per operator; cell IDs namespaced by source.
- `extensions/pask-vault-obsidian/`, `extensions/pask-vault-notion/` — source adapters. Each emits Pask interactions in the same shape as helm telemetry.
- `apps/loom-react/src/helm/StableThreads.tsx` — new helm panel, sibling to AttentionSurface.

The kernel doesn't know an Obsidian note from a helm card. That's the whole point.

---

## 1. Where We Are

| Piece | Location | Status |
|---|---|---|
| Pask kernel (Zig WASM) | `core/pask/` | Landed 2026-05-01 |
| Pask GA + entailment layer | `extensions/pask-ga/` | Landed `b9314f9` |
| AttentionEngine + 5-factor scoring | `runtime/services/src/services/AttentionEngine.ts` | Live |
| AttentionTelemetry (AS1) | `runtime/services/src/services/AttentionTelemetry.ts` | Live |
| AttentionWeightLearner (AS2) | `runtime/services/src/services/AttentionWeightLearner.ts` | Live |
| AttentionRules (AS3) | `runtime/services/src/services/AttentionRules.ts` | Live |
| AttentionSignals (AS4) | `runtime/services/src/services/AttentionSignals.ts` | Live |
| Helm renderer | `apps/loom-react/src/helm/Helm.tsx` | Live |
| AttentionSurface card list | `apps/loom-react/src/helm/AttentionSurface.tsx` | Live |
| Cross-surface delivery (AS5) | — | Open (out of scope for this plan; tracked separately) |

Two structural gaps relative to a "dimensional second brain":

- **Telemetry events stop at scoring weights.** The AS2 learner adjusts the AttentionEngine's five factor weights. It does not feed a graph that can answer "what topics has this operator's traffic settled on" or "which notes are 1–3 hops from the one I just opened." Pask is the kernel for that question, and it isn't connected.
- **External authored corpora are invisible.** A user with a 2,000-note Obsidian vault or a structured Notion workspace gets no value from semantos's attention layer. The graph the operator already lives inside isn't part of the substrate.

This plan closes both.

---

## 2. The Loop, in Pictures

```
   ┌─────────────────────────────────────────────────────────────┐
   │ Sources (each emits Pask interactions on the same wire):    │
   │   • helm telemetry  (taps, opens, dismissals, acted-on)     │
   │   • obsidian vault  (file writes, link traversals, opens)   │
   │   • notion api       (page edits, relation changes, views)   │
   │   • voice / repl     (verb dispatch, query terms)            │
   │   • calendar / signals (existing AS4 sources)                │
   └────────────────────────────┬────────────────────────────────┘
                                 │ pask.interact(cellId, related[], strength, now_ms)
                                 ▼
                    ┌──────────────────────────┐
                    │ Pask kernel (one per op) │
                    │  • constraint graph       │
                    │  • stable thread surface  │
                    │  • prune-on-decay         │
                    │  • snapshot/restore       │
                    └────────────┬─────────────┘
                                 │
              ┌──────────────────┼──────────────────┐
              ▼                  ▼                  ▼
   ┌────────────────┐  ┌──────────────────┐  ┌───────────────────┐
   │ Stable Threads │  │ AttentionEngine  │  │ Snapshot store    │
   │ panel (helm)   │  │ + graph-proximity │  │ (cell DAG; hash-  │
   │ ranked by      │  │ as 7th factor     │  │  chained, signed) │
   │ traffic + h    │  │ (AS2 learnable)   │  │                   │
   └────────────────┘  └──────────────────┘  └───────────────────┘
              ▲                                            │
              │                                            │
              └────────── operator can roll back ──────────┘
                          to any prior state
```

The kernel is source-blind. Helm taps, Obsidian opens, and Notion page edits all become `pask.interact()` calls with namespaced cell IDs (`helm:item:<id>`, `obs:note:<vault>/<path>`, `nx:page:<workspace>/<id>`). Stable threads surface across the merged graph. The same snapshot blob covers everything.

---

## 3. Phases

### DB1 — Telemetry-to-Pask bridge (~ 1 day)

**Goal**: every AttentionTelemetry event drives a Pask interaction. The helm's existing event stream becomes the operator's living graph, no new UX required.

**Deliverables**:

1. New file `runtime/services/src/services/PaskGraph.ts` exporting:
   ```typescript
   export interface PaskGraph {
     interact(args: {
       cellId: string;             // namespaced: 'helm:item:<id>', 'obs:note:<path>', 'nx:page:<id>'
       kind: string;               // 'open' | 'edit' | 'tap' | 'link-traverse' | 'acted-on' | ...
       strength: number;           // base 1.0; act-on=1.5; ignore=-0.3 (negative pulls toward prune)
       relatedCells: string[];     // up to 32 (kernel cap); siblings, links, type-path, hat
       nowMs: number;
     }): void;

     stableThreads(opts?: { limit?: number; sourcePrefix?: string }): StableThread[];
     neighbours(cellId: string, hops: 1 | 2 | 3): string[];
     snapshot(): Uint8Array;       // PASK-ABI blob, persisted as a signed cell
     restore(blob: Uint8Array): void;
   }
   ```

2. **Adapter from AttentionTelemetry**. Subscribe to the existing telemetry stream; map each `AttentionInteraction` to a `pask.interact()` call:

   | Telemetry event | strength | relatedCells |
   |---|---|---|
   | `tapped` | 1.0 | type-path, primaryReason, previously-tapped item |
   | `opened` (≥500ms visible) | 0.5 | as above |
   | `acted-on` (verb dispatched) | 1.5 | type-path, target verb, hat |
   | `dismissed` (explicit) | -0.5 | type-path |
   | `ignored` (scrolled past) | -0.1 | type-path |
   | `pinned` | 2.0 | type-path |
   | `suppressed` | -1.0 | pattern |

   Negative strengths feed Pask's normal pathway — the kernel's prune logic handles low-trend inbound edges; we don't need a separate "negative" code path.

3. **One kernel per operator, lifecycle bound to identity.** Created on hat activation; snapshot-restored from the most recent signed snapshot cell; finalised + snapshotted on hat deactivation, on quit, and every `stability_window_ms` (default 60s).

4. **Cell-ID namespacing convention**, frozen in this doc:
   - `helm:item:<loom-object-id>`
   - `helm:type:<type-path>`           — surfaced separately so type-paths form their own settling layer
   - `helm:hat:<hat-id>`
   - `obs:note:<vault-id>/<rel-path>`
   - `obs:tag:#<tag>`
   - `nx:page:<workspace-id>/<page-id>`
   - `nx:db:<workspace-id>/<db-id>`
   - `q:<voice-or-repl-query-hash>`

   The 64-byte cap on cell IDs ([core/pask/PRIMER.md](../../core/pask/PRIMER.md) §Capacities) means deep paths get hashed at the boundary.

5. **REPL surface**:
   ```
   pask threads [--source obs|helm|nx|all] [--limit 20]
   pask neighbours <cell-id> [--hops 2]
   pask snapshot save | restore <hash> | rollback --to <iso-date>
   pask stats         # node count, edge count, stable count, last finalize
   ```

**Success criterion**: a fresh helm session generating 100 interactions produces a Pask graph with non-trivial stable threads after `stability_window_ms`; `pask threads` returns sensible top-N items; snapshot+restore round-trips byte-identical (same as the kernel's existing determinism conformance, verified per-operator).

---

### DB2 — Stable Threads panel (~ 1 day)

**Goal**: the operator's "what have I been thinking about" view, lives in the helm above or beside AttentionSurface.

**Deliverables**:

1. New file `apps/loom-react/src/helm/StableThreads.tsx`. Renders the top-N stable threads from `PaskGraph.stableThreads({ limit: 20 })` as a sparse list:
   ```
   ┌─ Stable threads ──────────────────────────────────────┐
   │ ▣ trades.job.fencing            n=87  h=0.003  ↑      │
   │ ▣ obs:note:Projects/SemantOS    n=42  h=0.008  →      │
   │ ▣ helm:hat:builder@semantos     n=41  h=0.012  ↑      │
   │ ▣ nx:db:CRM/Customers           n=33  h=0.014  →      │
   │ ▣ q:"how do I deploy to prod"    n=18  h=0.019  ↓      │
   │   ... more ...                                          │
   └────────────────────────────────────────────────────────┘
   ```

   `n` is traffic (interaction count via `pask_node_h_state` proxy / edge count), `h` is the node's `h_state`, the arrow indicates 7-day trend.

2. **Click-through behaviour**. Clicking a thread sets it as the *active context* for the AttentionEngine — items 1–3 hops in the Pask graph from that thread are boosted (see DB4). Right-click context menu surfaces: `Pin`, `Open source` (for `obs:` and `nx:` cells, opens the actual file/page), `Show neighbours`, `Suppress class`.

3. **Layout placement**. Three options to test:
   - **Top strip** above AttentionSurface (matches the existing pinned-strip pattern in [Helm.tsx:14](../../apps/loom-react/src/helm/Helm.tsx)).
   - **Left rail** (new column).
   - **Toggle** with AttentionSurface via the same nav strip.

   Default to top strip for v0; lowest-friction insertion into the existing helm grid.

4. **Filter chips**. `helm` / `obs` / `nx` / `all`; persists per-operator. Most operators want `all` but a vault-heavy user may want `obs` only.

5. **Empty / cold-start state**. Until `min_interactions` (default 5) is reached, show "Pask is still settling — interact with X more items for stable threads to appear." Avoid showing noise threads from the first 50 interactions.

**Success criterion**: panel renders within 16ms; updates within `stability_window_ms` of each interact; click-through correctly sets the AttentionEngine's active-context boost; the 7-day trend arrow is computed from a snapshot-pair diff.

---

### DB3 — Obsidian vault adapter (~ 2 days)

**Goal**: every interaction with an Obsidian vault becomes a Pask interaction. The vault stays canonical on disk; semantos observes.

**Deliverables**:

1. New extension `extensions/pask-vault-obsidian/` with two pieces:
   - **File watcher** (`src/watcher.ts`). Uses `chokidar` over the configured vault root. Emits Pask interactions for every `add` / `change` / `unlink` on `*.md` files. Diff parser extracts wikilinks (`[[...]]`) and tags (`#...`); these become `relatedCells`.
   - **Companion Obsidian plugin** (`plugin/main.ts`). Hooks Obsidian's `workspace.on('file-open')`, `workspace.on('active-leaf-change')`, `metadataCache.on('resolved')`. Emits richer interactions: `open`, `link-traverse` (when an outgoing link is clicked), `search-result-click`. Communicates with the semantos extension via a local Unix socket or named pipe.

2. **Mapping rules**:

   | Obsidian event | Pask interaction |
   |---|---|
   | File write | `kind: 'edit'`, strength 0.8, related = wikilinks in diff |
   | File open | `kind: 'open'`, strength 0.5, related = vault tag + parent folder cell |
   | Link traversal (clicking `[[X]]`) | `kind: 'link-traverse'`, two interactions: source→target and target→source, strength 1.0 |
   | Backlink panel click | `kind: 'link-traverse'`, strength 0.8 |
   | Search result click | `kind: 'tap'`, strength 0.6, related = the search query as `q:<hash>` cell |
   | File rename | rewrite cell ID; pask exposes no rename op, so this is a snapshot mutation outside the kernel (see DB6) |
   | File delete | `kind: 'dismissed'`, strength -1.0 — pruning will handle the rest |

3. **Bidirectional render**. Pask's stable threads can write back into the vault as a generated MOC (Map of Content) note: `Stable Threads.md` at the vault root, regenerated every snapshot. Format:
   ```markdown
   # Stable Threads — generated by semantos pask, do not edit
   _Last updated: 2026-05-02 09:14_

   ## Top 20 by traffic

   - [[Projects/SemantOS]] — 42 interactions, h=0.008
   - [[People/Damian]] — 31, h=0.011
   - [[Topics/Constraint Graphs]] — 28, h=0.013
   - tag:#fencing — 24, h=0.015
   ...
   ```

   Vault-internal cells render as Obsidian wikilinks; cross-source cells (helm, Notion) render as plain text with a callout. The MOC note is a normal vault file, so the operator's existing Obsidian graph view sees it.

4. **Privacy and scoping**. The plugin has a config:
   ```toml
   [vault]
   path = "/Users/todd/Documents/SemantOS Vault"
   include = ["**/*.md"]
   exclude = [".obsidian/**", "Daily/**"]
   write_back_moc = true
   moc_path = "Stable Threads.md"

   [interactions]
   record_opens = true
   record_search = true
   record_link_traversal = true
   ```

5. **Cold-start ingestion**. On first connect, walk the vault, emit a low-strength `kind: 'seed'` interaction per existing note with `relatedCells = wikilinks`. This bootstraps the link topology without overwhelming the recency signal — set strength to 0.1 and use a backdated `now_ms` distributed over the last 30 days.

**Success criterion**: a 500-note vault reaches a stable graph state within ~5 minutes of cold-start; live edits surface in `pask threads` within 60s; the generated MOC matches the kernel's stable thread list; the Obsidian plugin works on macOS, Linux, Windows; opt-out via the `exclude` glob is respected.

---

### DB4 — Notion adapter (~ 2.5 days)

**Goal**: same shape as DB3 but for Notion workspaces. Polled via the Notion API; webhook-upgrade path documented.

**Deliverables**:

1. New extension `extensions/pask-vault-notion/`. OAuth-based; the operator authorises a workspace via the standard Notion integration flow. The integration is **read-only** — semantos never writes back to Notion. (Write-back is technically possible but introduces sync conflicts and data-loss risk; explicit operator opt-in only, deferred to a later phase.)

2. **Sync model**:
   - Initial cold-start: paginate `databases.list` and `pages.list`. Emit one `kind: 'seed'` interaction per page; relations (Notion relation property values) become `relatedCells`. Backdate `now_ms` by `last_edited_time`.
   - Incremental: poll the workspace every 5 minutes (config). Filter by `last_edited_time > <cursor>`. Each changed page emits `kind: 'edit'`, related = current relation values.
   - Webhooks: upgrade path. When Notion's webhook beta is GA, replace the poller with a push subscription; the interaction-emission code is unchanged.

3. **Cell-ID mapping**:
   - `nx:page:<workspace>/<id>` for pages.
   - `nx:db:<workspace>/<id>` for database objects (the schema, not rows).
   - Properties of type `relation` become edges; properties of type `select` / `multi_select` become tag cells (`nx:tag:<workspace>/<value>`).
   - Page titles are not used as cell IDs (they change); the page UUID is.

4. **Rate-limit-aware poller**. Notion's published limit is ~3 req/s averaged with bursts. The poller maintains a token bucket and prioritises:
   - High priority: pages updated in the last hour.
   - Medium: databases the operator has interacted with via helm.
   - Low: archive sweep, every 24h.

   On a workspace with 10k pages this comes out to a full reconciliation every ~1 hour.

5. **Open-in-Notion verb**. Clicking a `nx:` cell in Stable Threads opens the page in the Notion desktop app or web (URL: `notion://www.notion.so/<workspace>/<id>`). Helm tracks this as an `acted-on` event, which feeds back into Pask as a strength-1.5 interaction — closing the loop.

6. **Workspaces with structured DBs**. Notion's relational DBs *are* readable through the API (rows, schema, formulas). The adapter exposes them as a hierarchical cell pattern: `nx:db:<id>` → row cells `nx:row:<db-id>/<row-id>`, with relation columns generating edges between rows. This means a CRM-style Notion DB becomes a Pask sub-graph the operator can query via `pask neighbours nx:row:<customer-id> --hops 2` to surface related deals/notes/people regardless of which Notion view they're filed under.

**Success criterion**: cold-start over a 1k-page workspace completes within 10 minutes without rate-limit violations; incremental sync surfaces edits within 5 minutes; relation properties produce edges that match Notion's own backlink view; opening a stable thread cell launches the right Notion page; the integration works for both personal and team workspaces.

---

### DB5 — Graph-proximity scoring factor in AttentionEngine (~ 1 day)

**Goal**: the AttentionEngine gains a 7th factor — proximity in the Pask graph to a notion of "current context." Items adjacent to whatever the operator just opened, or to the active stable thread, get a transient boost.

**Deliverables**:

1. **New factor in `AttentionEngine.ts`**: `graph_proximity` (default weight 0.10, learnable via the AS2 learner). For each candidate item:
   - Compute the minimum Pask-graph distance from the item's cell to the *active context cell*. Active context = the cell of the most recently opened item (within a 10-minute window) OR the currently-selected Stable Threads cell.
   - Score = `1.0 / (1 + distance)`, clamped to `[0, 1]`. 0 hops (direct hit) = 1.0; 1 hop = 0.5; 2 hops = 0.33; etc.

2. **Active-context state**. Lives in `Helm.tsx`, fed into the engine via a new `setActiveContext(cellId | null)` method. Set on Stable Threads click (DB2 §2), on AttentionSurface tap (DB1 §2), and cleared after 10 minutes of no relevant interaction.

3. **Re-rank cadence**. The engine already recomputes within 16ms for ≤500 objects. Adding the proximity lookup costs one `pask.neighbours()` call per active context (cached; only changes when the context changes). Per-item lookup is O(1) bitset check — well within budget.

4. **Telemetry visibility**. The `AttentionItem.reason` payload extends with a `graph_proximity` reason variant: `{ type: 'graph_proximity', activeContext: 'obs:note:Projects/SemantOS', distance: 1 }`. Renderer shows: "1 hop from Projects/SemantOS" as the reason caption — the operator can see *why* an item rose.

5. **Per-context profile interaction**. The AS2 weight learner already supports per-`field`/`desk`/`night` profiles. `graph_proximity` likely matters more at-desk (deep-work mode) than in-field (where deadline + recency dominate). Let it learn.

**Success criterion**: opening a note surfaces its 1-hop neighbours within the next AttentionSurface refresh; the boost decays over 10 minutes; the AS2 learner correctly drifts the weight up for operators whose interactions follow graph-adjacent paths and down for operators who jump between unrelated contexts; reason captions render correctly.

---

### DB6 — Snapshot, rollback, fork (~ 1 day)

**Goal**: operator-visible verbs over the kernel's existing snapshot ABI. "Forget X," "rebuild from yesterday," "fork an experimental brain."

**Deliverables**:

1. **REPL verbs** (extending DB1 §5):
   ```
   pask snapshot save [--label <name>]      # writes a signed cell with the PASK blob
   pask snapshot list                       # by date, label, hash, size
   pask snapshot restore <hash>             # full kernel reset + restore; previous state archived
   pask rollback --to <iso-date>            # find latest snapshot ≤ date, restore it
   pask fork <hash> --as <name>             # boots a second kernel from snapshot; isolated, named
   pask diff <hash-a> <hash-b>              # node/edge counts; new/pruned/restabilised threads
   ```

2. **Forget verbs** (the bit Notion and Obsidian can't do without manual sweeping):
   ```
   pask forget <cell-id>                    # marks node pruned, snapshots, signs the event
   pask forget --pattern "obs:note:Old/**"  # bulk
   pask forget --inactive --since 90d       # everything not touched in 90 days
   ```

   Pruning is the kernel's existing one-way prune ([core/pask/PRIMER.md](../../core/pask/PRIMER.md) §Invariant 5). The verb is just a UX shell over `pask_upsert_node` + a synthetic high-negative interaction. Nothing is destroyed — the snapshot before the forget is retained, and `pask snapshot restore` brings it back.

3. **Rename / migrate handling**. Obsidian file renames and Notion page UUID migrations need cell-ID rewrites. Pask doesn't expose a rename op (indices are stable for kernel lifetime; cell IDs are not). The handler:
   - On rename, emits a `kind: 'edit'` interaction on the new cell ID with related = old cell ID (so Pask treats them as adjacent).
   - On the next snapshot+restore boundary, the snapshot is rewritten on disk (outside the kernel) to substitute the old ID for the new one in the node table. The kernel's layout asserts ([core/pask/README.md](../../core/pask/README.md) §Layout fidelity) make this safe — fields' offsets are documented.

4. **UI**. Stable Threads panel has a top-bar dropdown with "Now" / "1h ago" / "Yesterday" / "1 week ago" — picking a prior point loads a *read-only view* of the kernel's state at that time. The operator can flip back and forth without committing. A "Restore this state" button commits the rollback (with a confirm dialog).

**Success criterion**: snapshot save/restore round-trips correctly per the kernel's determinism contract; rollback to an arbitrary date works; forget by pattern correctly prunes without affecting unrelated cells; fork creates an isolated kernel that doesn't interfere with the live one; the UI time-travel view loads within 100ms for snapshots up to 16 MB.

---

### DB7 — Cross-source MOC + the "what changed" digest (~ 1 day)

**Goal**: the killer demo. A daily-or-weekly view that says, in plain language, what the operator's brain converged on this period — across helm, vault, and Notion — and what fell away.

**Deliverables**:

1. **Digest generator** (`runtime/services/src/services/PaskDigest.ts`). Takes two snapshot hashes (start, end) and produces a structured diff:
   ```typescript
   interface PaskDigest {
     period: { from: string; to: string };
     newlyStable: StableThread[];        // threads that crossed the stability threshold
     reinforced: StableThread[];         // already-stable, traffic up >50%
     fading: StableThread[];             // h_state drift, traffic down >50%
     pruned: PrunedThread[];             // crossed the prune threshold
     topInteractionsBySource: { source: string; count: number; topCells: string[] }[];
   }
   ```

2. **Rendered as a card on the helm**, top-of-AttentionSurface, dismissible:
   ```
   ┌─ This week — 2026-04-26 to 2026-05-02 ─────────────┐
   │ Newly stable:                                       │
   │   • Helm Attention Surface (helm + obs)            │
   │   • Pask kernel design (helm + obs + nx)           │
   │ Reinforced:                                         │
   │   • Trades dispatch (helm)                          │
   │ Fading:                                             │
   │   • Hackathon ESP32 (no interaction in 14 days)    │
   │ 312 interactions across helm (180), obs (98),      │
   │ notion (34). Top thread: Pask kernel design.        │
   └─────────────────────────────────────────────────────┘
   ```

3. **Voice surface**. `talk: what's new` speaks the digest aloud. Three sentences max — newly stable + top reinforced + the most surprising fade.

4. **Written-back MOC enhancement**. The Obsidian-vault MOC from DB3 §3 grows a "Recent shifts" section, regenerated weekly, listing the diff in vault-link form. Operators with vault habits get the digest where they already live.

5. **Frequency knob**. `daily` / `weekly` / `monthly` per operator. Default: weekly, generated Sunday evening (or Monday morning, configurable).

**Success criterion**: digest correctly identifies threads that crossed stability/prune thresholds within the period; the rendered card respects dismissal; voice rendering is concise and natural; the MOC append is idempotent (regeneration replaces the section, doesn't duplicate); the digest survives kernel state changes (computed from snapshots, not live state).

---

## 4. What This Plan Is Not

- **Not a Notion competitor.** Notion's structured-DB queries, formula columns, and team workspaces are out of scope. If the operator wants those, they keep using Notion; semantos observes.
- **Not an Obsidian replacement.** Obsidian's editor, plugin ecosystem, and graph view stay where they are. The vault remains the canonical store. Semantos adds a parallel kernel-derived view.
- **Not write-back to Notion.** Read-only by design (DB4 §1). Write-back is risky without conflict resolution; not worth it for v0.
- **Not LLM-mediated.** Stable threads are surfaced by Pask's deterministic constraint propagation, not an embedding model. The kernel's chess result is the empirical anchor — replace it with embeddings and you lose the determinism, replay, and audit properties that make this dimensional in the first place. (LLMs can sit *over* the kernel for explanation — "why did X surface" — but not in the surfacing path.)
- **Not a sync engine.** The kernel ingests one operator's interaction stream. Cross-operator merge is a different problem (federation, AS5-adjacent, separate plan).

---

## 5. Tradeoffs

- **Notion API rate limits** — handled by the priority bucket in DB4 §4. Workspaces with >50k pages will need either webhooks (when GA) or a slower-than-5min cadence; the architecture admits both without code changes.
- **Obsidian plugin distribution** — the companion plugin needs to land in Obsidian's community plugin registry to avoid manual install friction. Six-week review cycle. The file-watcher path works without it; richer signals require the plugin. Land both; users pick.
- **Cell-ID stability under rename** — DB6 §3 handles this with an out-of-kernel snapshot rewrite. It works but it's the one place the architecture leaks. Acceptable.
- **Kernel capacity** — the 16k-node / 32k-edge default cap (`core/pask/PRIMER.md` §Capacities) is enough for ~10k Notion pages + a 2k-note vault + a few months of helm telemetry. Beyond that, the kernel returns errors rather than silently truncating; the answer is multi-instance (one kernel per source, or per project) with a thin merge layer. Out of scope for v0.
- **Write-back MOC churn** — regenerating `Stable Threads.md` on every snapshot creates vault history noise. Mitigation: write only on weekly digest cadence, not per-interaction.
- **Privacy** — Notion OAuth grants semantos read access to the workspace. Operators who can't share that data with their semantos node (e.g., team workspaces with NDA content) opt out. The Obsidian path is local-only; no such issue.

---

## 6. Sequencing & Estimated Cost

Total: ~9.5 days for one engineer.

| Phase | Days | Depends on |
|---|---|---|
| DB1 — Telemetry → Pask bridge | 1.0 | Pask kernel (landed) |
| DB2 — Stable Threads panel | 1.0 | DB1 |
| DB3 — Obsidian vault adapter | 2.0 | DB1 |
| DB4 — Notion adapter | 2.5 | DB1 |
| DB5 — Graph-proximity factor | 1.0 | DB1 |
| DB6 — Snapshot / rollback / forget | 1.0 | DB1, DB2 |
| DB7 — Cross-source digest | 1.0 | DB1, DB2 (DB3/4 to be useful) |

Critical path: DB1 → DB2 → DB5. With those three landed (≈ 3 days), the helm has a working dimensional second brain over its own telemetry, demonstrable. DB3/DB4/DB6/DB7 layer on without re-architecting.

---

## 7. The Demo That Proves It

Two scenes the incumbents structurally cannot stage:

**Scene 1 — "What have I been thinking about this month?"**
```
> pask threads --since 2026-04-01 --limit 10
   Stable threads, 30 days, ranked by traffic:
    1. helm:type:trades.job.fencing            n=312  h=0.002  ↑
    2. obs:note:Projects/SemantOS               n=187  h=0.005  ↑
    3. obs:note:People/Damian                   n=156  h=0.007  ↑
    4. nx:db:CRM/Customers                      n=143  h=0.009  →
    5. helm:hat:builder@semantos                n=128  h=0.011  →
    6. q:"how do constraint graphs work"        n=44   h=0.018  ↓ (settling out)
    ...
```

Notion can't answer this. Obsidian can't answer this. The graph view in Obsidian shows topology, not traffic-weighted convergence over time.

**Scene 2 — "Roll my brain back to last Tuesday."**
```
> pask rollback --to 2026-04-23
   Found snapshot at 2026-04-23 19:00:14 (hash 7f3a...)
   Current state archived as snapshot 9c1d...
   Restoring 4,891 nodes, 14,203 edges, 1,022 stable threads.
   Restored. Stable Threads panel updated.
   To return to current: pask snapshot restore 9c1d...
```

The kernel's determinism ([core/pask/PRIMER.md](../../core/pask/PRIMER.md) §Invariant 1) means this is byte-identical replay, signed and audit-trailed. Notion has version history per page; Obsidian has Git. Neither has *the operator's whole working memory* as a single addressable, replayable, signable artefact.

That's the dimensional second brain. The pieces all exist. This plan wires them.
