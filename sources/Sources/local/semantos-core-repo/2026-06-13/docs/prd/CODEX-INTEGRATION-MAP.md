---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/CODEX-INTEGRATION-MAP.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.673325+00:00
---

# Codex Parallel-Work Integration Map

**Purpose**: this session ran inside Claude Code; operator was running parallel sessions in OpenAI Codex on orthogonal surfaces. This doc maps Codex's deliverables onto our roadmap so the next session knows what's already shipped vs. what we still need to build.

Generated 2026-05-06 from `git log origin/main` post-PR-#392.

---

## §1 — Codex deliverables on origin/main

Listed in chronological order, with our-roadmap implications.

### 1.1 — Voice pipeline (Tier 4 platform layer)

| Commit | What |
|---|---|
| `4a4254c` | Wire Whisper + llama.cpp voice pipeline; 4-node dock; jobs offline cache |
| `9b17fe5` | Add on-device model download UI to TalkNode |
| `c03d52d` | fix(android): resolve llama_cpp + whisper_cpp NDK build failures |
| `d179330` | fix(android): add INTERNET permission + streaming SHA-256 in model managers |
| `94774c8` | fix(whisper): skip SHA-256 check while hash is unverified after HF drift |

**Implication for Tier 4 (voice triggers)**: the platform-side wiring is shipped. Whisper + llama.cpp run on-device via the Flutter bindings at `platforms/flutter/{whisper_cpp,llama_cpp}/`. TalkNode has an on-device model download UI.

What we still need for Tier 4:
- **Voice → SIRProgram extraction** — a structured-intent prompt for the local Llama (3B model fits the constraint per the operator's earlier "pleb model" direction)
- **SIR → ratify pipeline integration** — feeding the voice-extracted SIRProgram into the `oddjobz.ratify_proposal` RPC the same way `legacy ingest` does
- **TalkNode → operator helm wiring** — the tap-to-talk button in the helm or mobile app that captures the audio, runs Whisper, runs llama.cpp on the transcript, hands the result off

Estimated remaining work: ~3-5 dev-days (the platform is done; we're just plumbing).

### 1.2 — Helm v7 cockpit + jam-room redesign

| Commit | What |
|---|---|
| `a3f08e4` | Helm v7 cockpit design — Flutter mobile + Svelte brain helm |
| `7a5b28c` | Rewire jam-room UI: Svelte 5 desktop + Flutter mobile redesign |
| `bff8529` | jam-room: wire Phase A–G components into live app + streamline layout |

**Implication**: helm SPA was upgraded under the hood while we built D-DOG.1.0c's graph-aware views on top. The new D-DOG.1.0c routes (`/sites/[id]`, `/customers/[id]`, `/jobs/[id]`) plug into the v7 cockpit's hash router (per E.2's PR #380 implementation).

**No conflicts surfaced.** The v7 cockpit is the visual shell; D-DOG.1.0c is the data + view-content. They compose cleanly.

What this means for Tier 2 (kanban):
- The kanban view fits inside the v7 cockpit naturally — same hash-router treatment as the pivot routes
- We may want to coordinate the v7 cockpit's nav surface with the new `/kanban` route (does it deserve a top-nav button or stays under the JobList toggle?). Operator decision.

### 1.3 — Wallet UX

| Commit | What |
|---|---|
| `0e5504f` (#383) | wallet-browser: wrap plexus signup engine flow |
| `974d36a` (#385) | wallet-browser: smooth first-run recovery UX |
| `5e40dd2` (#384) | Fix/brain firstrun ux |
| `fad1fe6` (#381) | brain: fix first-run UX regressions (Bridget Doran bug report) |
| `9087020` (#382) | fix(brain): use DNS seed for headers sync |

**Implication for our open follow-up "HatBkds production root"** (§5.2 of `SESSION-HANDOFF-2026-05-06.md`): the wallet UX work is bringing real BRC-42 BKDS roots online. When `codex/wallet-engine-wrapup` lands in main, the HatBkds module can be swapped from its current data-dir-seeded scalar to a wallet-KEK-decrypted operator-root-priv source.

**Update (post-triage 2026-05-06)**: the wallet-engine-wrapup branch turned out to be a stale duplicate of PR #383 (already on main). PR #385 also landed first-run recovery. The HatBkds production swap-in is therefore **no longer gated on a Codex branch landing** — it's gated on operator decision about whether to wire BRC-42 root from a wallet-KEK-decrypted source now, or stay on the deterministic data-dir-seeded scalar (correct for single-machine ops).

### 1.4 — Oddjobz Meta ingestion (Tier 5 prerequisite)

| Commit | What |
|---|---|
| `0e18eb3` | feat(oddjobz): unify meta ingestion dispatch and attention |

**Implication for Tier 5 (Meta + Bricks summary ingestion)**: prerequisite is partially in place. Codex unified the Meta ingestion dispatcher; the same shape Gmail ingestion uses (`legacy ingest gmail` → `oddjobz.ratify_proposal`) should now work for `legacy ingest meta` with minor adapter changes.

What we still need for Tier 5:
- **Meta provider adapter** — IF Codex's `0e18eb3` already exposed it through `legacy connect meta` + `legacy ingest meta` (likely — they "unified the dispatch"), this may be shipped. Verify next session.
- **Bricks weekly-summary ingest** — Bricks emails operator a weekly summary of outstanding items. Wire this as either (a) a Gmail-source filter (the summary email becomes a special proposal that fans out into multiple jobs) or (b) a Bricks-API direct fetch if available.

Estimated remaining: probably ~2-3 days, depending on what Codex's `0e18eb3` already wired.

---

## §2 — Codex worktrees triage (2026-05-06, end-of-session)

Originally this section listed worktrees as "untriaged — check next session." That was operator-flagged, so I went through them all post-handoff. **Final state:**

| Worktree | Branch | Triage outcome |
|---|---|---|
| `semantos-core-jambox` | `codex/jambox-semantic-three` | **Branch 0 commits ahead of main** — fully merged. Worktree has uncommitted local edits in `apps/jam-room/` (operator WIP). Left as-is. |
| `semantos-core-wallet-engine` | `codex/wallet-engine-wrapup` | **Stale duplicate of merged PR #383** (commit message + content matched exactly). Local branch + remote branch + worktree all deleted. |
| `semantos-core-wallet-ux-followup` | `codex/wallet-browser-first-run-ux` | **Stale duplicate of merged PR #385**. Local branch + remote branch + worktree all deleted. |
| (current repo HEAD's tracking branch) | `codex/brain-headers-dns-seed` | **Stale duplicate of merged PR #382** (DNS seed for headers sync). Local branch + remote branch deleted. (No separate worktree — was the main repo's checkout state.) |
| `semantos-core-node-protocol` | `node-protocol` | **14 real unmerged commits** — Wave 35 Phase A: chain-broadcast extension + session-protocol package + udp-transport multi-group + poker-agent. Merge has 11 conflicting files (README, multiple `package.json`, `tsconfig.json`, session-protocol adapters, phase35a-gate test). **Left for operator review** — non-trivial conflicts warrant manual resolution. See §2.1. |
| `/private/tmp/jam-room-g-rebase` | `jam-room-g-mobile` | **Branch 0 commits ahead of main**, only untracked `node_modules` + a snapshot file. Worktree removed, branch deleted. |
| `/private/tmp/wsite35-worktree` | `feat/wallet-wsite35-identity-certs` | Gitdir was already broken (not a real git checkout). Worktree pruned. Branch left untouched (still on remote — possibly relevant to D-O5p, owner unclear). |

### §2.1 — node-protocol unmerged work

Wave 35 Phase A is genuinely independent from D-DOG and was not part of any open PR. The 14 commits trace a coherent track:

```
f203cd4  docs(prd): restore PHASE-35A and PHASE-35B dropped in #96 squash
ca0d2df  feat(session-protocol): scaffold runtime/session-protocol/ package
07b53d3  feat(session-protocol): add types + signer seam (D35A.1 + D35A.5)
592e60c  feat(udp-transport): multi-group membership API (D35A.4)
80b5760  feat(session-protocol): promote MulticastAdapter with injected seams (D35A.3)
aee7d8e  feat(chain-broadcast): scaffold extensions/chain-broadcast + port BeefStore
07240f5  feat(chain-broadcast): ChainTipManager + MapiBroadcaster (ARC injectable)
babaedf  feat(chain-broadcast): CellTxBuilder + ChainBroadcaster facade
12e5ea2  test(chain-broadcast): port BeefStore + ChainTipManager suites (18/18)
546c5d6  feat(session-protocol): SessionRuntime + lean broadcast (D35A.2)
8c237d1  feat(session-protocol): PlexusCertBCAProvider + G35A.5 (D35A.5 wrap-up)
df2f58b  feat(poker-agent): G35A.4 skeleton-consumer regression + stale-path fixes
4cbb33d  docs(35A): package READMEs + root table updates
5f3c5de  chore(35A): remove stale packages/ dir + restore Lean build cache
```

Diff stat: **39 files changed, +6859 -556** — manageable size, but the conflicts are real and span:

- `README.md` (3-way conflict on the package table)
- `apps/poker-agent/package.json` + `src/game-loop.ts`
- `core/protocol-types/package.json`
- `runtime/node/package.json`
- `runtime/session-protocol/package.json` + `src/index.ts` + `src/adapters/multicast-adapter.ts` + `tsconfig.json`
- `tests/gates/phase35a-gate.test.ts`

These suggest concurrent edits to the same files on main since the branch's merge-base (`483f1ff`). The conflicts are file-level, not catastrophic.

**Recommendation for operator**: rebase `node-protocol` onto current `main`, resolve the 11 conflicts manually (they're genuine — both sides moved forward), then PR it as a single Wave 35 Phase A drop. Estimate: 1-2 hours of careful conflict resolution.

**Why I didn't auto-merge**: the conflicts span files I haven't been working in (poker-agent, session-protocol multicast adapter) and where I can't confidently pick a side without operator context on the Wave 35 design intent.

**Cleanup actions taken** (this session, post-handoff):
- 3 stale codex/* remote branches deleted
- 4 stale local branches deleted
- 3 stale worktrees removed (2 wallet, 1 jam-room-g, 1 broken /private/tmp)
- `git worktree list` now clean of confirmed-stale entries

---

## §3 — Who-owns-what map

| Surface | Owner | Status |
|---|---|---|
| Cell-DAG layer 1 promotion (sites/customers/jobs/attachments + signing + graph nav UI + migration verb) | This session (Claude) | Shipped (D-DOG.1.0c, 20 PRs) |
| Voice pipeline platform (Whisper + llama.cpp + 4-node dock + on-device model download) | Codex | Shipped |
| Wallet UX (first-run recovery + plexus signup) | Codex | Partial — `wallet-engine-wrapup` still in flight |
| Helm v7 cockpit shell | Codex | Shipped (`a3f08e4`, `7a5b28c`, `bff8529`) |
| Jam-room phase A-G | Codex | Shipped |
| Bridget's iOS Simulator block | This session (Claude, tonight) | Shipped (#392) |
| Tier 2 (backlog kanban) | Next session | Not started — PRD at `docs/prd/TIER-2-BACKLOG-KANBAN.md` |
| Tier 3 (execution proposal engine) | Next session | Not started — PRD at `docs/prd/TIER-3-EXECUTION-PROPOSAL-ENGINE.md` |
| Tier 4 (voice triggers) | Next session — but platform from Codex | Plumbing only (~3-5 days) |
| Tier 5 (Meta + Bricks summary ingestion) | Next session — but prerequisite from Codex | Partial (need to verify what `0e18eb3` shipped) |
| Tier 6 (sovereign promotion — lift legacy verbs into brain) | Next session | Big architectural; do after Tier 2/3 |
| HatBkds production root | Next session — gated on `codex/wallet-engine-wrapup` merging | Tracked as follow-up §5.2 |

---

## §4 — Recommended next-session order

Given the Codex parallel work + open follow-ups + operator preferences:

1. **Tier 2 (backlog kanban)** — highest-value-per-day; operator-visible; builds directly on D-DOG.1.0c. ~5 wall-clock days with parallel agents.
2. **Tier 5 (Meta + Bricks)** — small (Codex did the prerequisite); ~2-3 days; gives operator a second ingestion source.
3. **HatBkds production swap-in** — gated on `codex/wallet-engine-wrapup`; check first; ~1 day if unblocked.
4. **Tier 4 (voice triggers)** — Codex did the platform; we wire voice → SIR → ratify. ~3-5 days.
5. **Tier 3 (execution proposal engine)** — biggest UX win; ~5 wall-clock days.
6. **Tier 6 (sovereign promotion)** — lift legacy verbs into brain, drop FS fallback warning permanently. Do after Tier 2/3 inform the Semantos Brain-side verb shape. ~5-7 days.

Each tier has a PRD or scoped matrix at `docs/prd/`. Match the D-DOG.1.0c phasing pattern (split aggressively, parallel where file-disjoint, single agent per sub-PR with bounded scope).

---

## §5 — Coordination with operator's Codex worktrees

If Codex is actively working on a surface, **don't fire a parallel Claude agent on the same files**. Check `git worktree list` before scoping.

Post-triage state (2026-05-06): the only Codex worktree with genuinely unmerged work is `semantos-core-node-protocol` (Wave 35 Phase A — see §2.1). The wallet-engine-wrapup branch is gone, so HatBkds production swap-in is no longer gated on it landing — instead, it's gated on operator decision about which BRC-42 root source to wire (current data-dir-seeded scalar is acceptable for single-machine ops).

When in doubt: ask the operator before firing.
