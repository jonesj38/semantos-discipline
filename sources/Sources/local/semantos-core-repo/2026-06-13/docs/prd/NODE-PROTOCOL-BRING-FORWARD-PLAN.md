---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/NODE-PROTOCOL-BRING-FORWARD-PLAN.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.671580+00:00
---

# Phase U.1 — `node-protocol` bring-forward plan

**Status**: paste-ready agent brief OR operator-runnable plan.
**Origin**: blocks all subsequent UDP/mesh work per `UDP-MESH-DIRECTION.md` §3.
**Branch**: `node-protocol` (origin/node-protocol)
**Currently**: 14 commits ahead of main, 11 conflicting files on naïve merge against current main (verified 2026-05-07).

---

## §1 — What's on the branch

14 commits forming Codex's Wave 35 Phase A track (chain-broadcast + session-protocol + udp-transport):

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

**Diff stat**: 39 files changed, +6859 / −556. New packages added:
- `runtime/udp-transport/` (UDP multi-group membership API — the U.2 foundation)
- `runtime/session-protocol/` (SessionRuntime + multicast adapter — the U.2/U.3 foundation)
- `extensions/chain-broadcast/` (BSV chain broadcast — orthogonal to UDP mesh; supports D-DOG.1.0e BSV anchoring later)

---

## §2 — Conflicting files (11)

```
README.md
apps/poker-agent/package.json
apps/poker-agent/src/game-loop.ts
core/protocol-types/package.json
docs/prd/PHASE-35B-NODE-AS-SERVICE.md
runtime/node/package.json
runtime/session-protocol/package.json
runtime/session-protocol/src/adapters/multicast-adapter.ts
runtime/session-protocol/src/index.ts
runtime/session-protocol/tsconfig.json
tests/gates/phase35a-gate.test.ts
```

Conflict shape analysis (most are package.json / config files where both sides moved forward independently):

### 2.1 — Easy (mechanical merge)

- `README.md` — likely a package-table addition both sides made; merge is "include both new entries"
- `apps/poker-agent/package.json` — dep version bump on both sides; pick newer
- `core/protocol-types/package.json` — same
- `runtime/node/package.json` — same
- `runtime/session-protocol/package.json` — same
- `runtime/session-protocol/tsconfig.json` — config drift on both sides; manual re-application of either side's intent

### 2.2 — Medium (re-apply both intents)

- `runtime/session-protocol/src/index.ts` — exports added on both sides. Need to merge both export lists.
- `tests/gates/phase35a-gate.test.ts` — gate test was updated on both sides; merge is to keep both sets of assertions.
- `apps/poker-agent/src/game-loop.ts` — the only application-code conflict. Needs case-by-case: if main's change is to a different lifecycle event than `node-protocol`'s change, both apply; if same event, pick the more-recent intent.

### 2.3 — Worth careful review

- `runtime/session-protocol/src/adapters/multicast-adapter.ts` — the multicast adapter is the U.2 foundation for emergency-broadcast use case (`UDP-MESH-DIRECTION.md` §5.4). If main has refactored this file in any way, must understand both intents. Worst case is a clean re-apply of the `node-protocol` version since it's the more-recent UDP-specific work.
- `docs/prd/PHASE-35B-NODE-AS-SERVICE.md` — content doc. Both sides authored. Likely "include both narratives, possibly de-dup overlapping sections."

---

## §3 — Bring-forward plan

### Step 1 — Audit each conflict (read-only)

For each of the 11 files, view both sides' content + the merge-base. Produce a 1-3 sentence note per file recording what each side intended. This is the "before you touch anything, understand what's there" step.

```bash
git checkout origin/main
for f in README.md apps/poker-agent/package.json ...; do
  echo "=== $f ===" 
  git diff $(git merge-base origin/main origin/node-protocol)..origin/main -- $f | head -20
  echo "--- vs node-protocol ---"
  git diff $(git merge-base origin/main origin/node-protocol)..origin/node-protocol -- $f | head -20
done
```

### Step 2 — Rebase node-protocol onto main

```bash
git checkout -b feat/u1-node-protocol-bring-forward origin/node-protocol
git rebase origin/main
# Resolve each conflict per §2 guidance above
# git add <resolved-file>
# git rebase --continue
```

For each resolution, write a clear commit message explaining both intents + the resolution chosen.

### Step 3 — Verify

```bash
# TS-side
bun install && bun test

# Specifically the new packages
bun run --cwd runtime/udp-transport check
bun run --cwd runtime/session-protocol check
bun run --cwd extensions/chain-broadcast check
bun test tests/gates/phase35a-gate.test.ts

# Lean + TLA+ defensive cross-check
cd proofs/lean && lake build
cd ../tla && make check

# All other repo tests
bun test
```

### Step 4 — PR

```bash
git push -u origin feat/u1-node-protocol-bring-forward
gh pr create --base main --head feat/u1-node-protocol-bring-forward \
  --title "Phase U.1 — bring node-protocol (Wave 35 Phase A) to main" \
  --body "..."
```

PR body must include:
- Diff stat (~39 files, +6859/−556 expected)
- List of newly-merged packages (`runtime/udp-transport`, `runtime/session-protocol`, `extensions/chain-broadcast`)
- Conflict resolution summary (1-3 sentences per resolved file with intent-preservation notes)
- Verification: lake build, make check, bun test all green
- Reference: `UDP-MESH-DIRECTION.md` §3 Phase U.1
- "RIP-OUT" notes — list of newly-introduced packages so a future "rip out the UDP work" task can do it cleanly

### Step 5 — Auto-merge after verification

Operator pre-authorized auto-merge. If all green, `gh pr merge --squash --delete-branch <PR>`.

---

## §4 — Effort estimate

- Step 1 (audit): 1-2 hours of careful reading
- Step 2 (rebase + resolve): 2-4 hours depending on §2.2 + §2.3 conflicts
- Step 3 (verify): 30 min (assuming nothing surprises)
- Step 4 (PR): 30 min
- **Total**: a half-day to a full day of focused work

This is meaningfully easier than the Semantos Brain-wedge work because nothing in `node-protocol` touches concurrent state — it's mostly new-package additions plus shared-file additions.

## §4.5 — Concrete conflict-resolution patterns (verified 2026-05-07 night)

I attempted a `git rebase origin/main` on `origin/node-protocol` overnight and aborted after the first 3 commits. What I learned:

**Pattern A — "scaffold-vs-evolution"** (most common)
Files where `node-protocol`'s commit is the initial scaffold (e.g. `package.json` v0.1.0 with minimal exports, `src/index.ts` with `export {}`) but `main` has the fully-evolved version (v0.6.0, all the dist/exports config, full barrel exports).

**Resolution**: `git checkout --ours <file> && git add <file>`. This preserves main's evolution. The `node-protocol` commit's intent (scaffold this file) is already subsumed by main's later commits which kept evolving the same file.

Verified case: `runtime/session-protocol/src/index.ts`, `runtime/session-protocol/package.json`, `runtime/session-protocol/tsconfig.json`. All cleanly resolve via `--ours`.

**Pattern B — "main + node-protocol authored independently"** (PRD docs)
File didn't exist before either branch. Both sides created it with overlapping but non-identical content.

**Resolution**: keep main's version + ADD node-protocol's unique sections, OR vice-versa. Manual merge.

Verified case: `docs/prd/PHASE-35B-NODE-AS-SERVICE.md` — main added a "Reachability — what actually counts as a node endpoint" section; node-protocol's commit didn't have it. Resolution was: keep main's section (delete the conflict markers; node-protocol's empty side adds nothing).

**Pattern C — "node-protocol's later commit adds fresh content"** (the value)
This is the actual VALUE of the bring-forward. Late commits on `node-protocol` add `runtime/udp-transport/`, `runtime/session-protocol/src/runtime.ts`, `extensions/chain-broadcast/`, etc. — directories/files that don't exist on main. These are NOT conflicts; they merge clean.

**Resolution**: nothing — the rebase machinery applies them automatically. The value of the whole bring-forward is in pattern C. Patterns A and B are friction.

### Estimated effort revised (with patterns clear)

Pattern A files: ~1 minute each via `--ours`. Pattern B files: 5-15 minutes of careful merging. Pattern C files: zero time (auto-applied).

For the 11 conflicting files identified by `git merge-tree`: roughly 6-7 are pattern A (mechanical), 3-4 are pattern B (careful), and the rest of the diff (~28 files added by node-protocol) is pattern C.

**Revised effort**: 1.5-3 hours of focused work. Easier than initially estimated.

### Pattern B files needing careful judgment

Worth flagging for the operator/agent picking this up:
- `runtime/session-protocol/src/adapters/multicast-adapter.ts` — multicast-adapter is the U.2 emergency-broadcast foundation. If main has refactored this from the version `node-protocol` inherits, careful intent-preservation needed. Likely "merge both forward".
- `apps/poker-agent/src/game-loop.ts` — poker-agent is an existing consumer of session-protocol. node-protocol's commit `df2f58b` added "skeleton-consumer regression + stale-path fixes" — read those commits' messages + diffs; they describe specific bugs being fixed.
- `tests/gates/phase35a-gate.test.ts` — the canonical Phase 35A gate. If both sides updated assertions, pick the assumption set that matches the merged code.

### My overnight progress

I resolved the first 3 conflicts (`PHASE-35B-NODE-AS-SERVICE.md` pattern B, `runtime/session-protocol/{src/index.ts, tsconfig.json, package.json}` all pattern A) before aborting because:
1. Each remaining commit (4 of 14) introduced more pattern-B conflicts requiring judgment
2. I don't have the test rig to validate the merged result mid-night
3. The brain-wedge agent is concurrently working on the same repo
4. Pattern-B conflicts on multicast-adapter.ts (the U.2 foundation) deserve operator attention before resolution

The work I did on those 3 conflicts was discarded with `git rebase --abort`. **No state changed on origin.** The next attempt starts fresh from `origin/node-protocol`. The verified pattern-A and pattern-B resolutions above are durable knowledge for that next attempt.

---

## §5 — Risks

- **Wave 35 Phase A design intent**: I haven't read the entire branch. The agent picking this up should read the architectural notes Codex left (`PHASE-35B-NODE-AS-SERVICE.md`, `PHASE-35A` doc references in commit `f203cd4`) before doing the rebase. Some decisions may have been encoded in patterns that aren't obvious from the diff alone.
- **`tsconfig.json` drift**: TypeScript project references in monorepo can interact in subtle ways. If main has changed `core/protocol-types`'s exports and `node-protocol`'s `session-protocol` imports them, the rebase might compile against stale assumptions. Verify with `bun install + bun run check` post-rebase.
- **Test flake**: gate test conflict (`phase35a-gate.test.ts`) — if both sides changed assertions, the merged test might fail because main's assumption + node-protocol's assumption don't both hold simultaneously. Pragmatic resolution: pick the assumption set that matches the merged code, document the choice in the resolution commit.

---

## §6 — Cross-references

- `docs/prd/UDP-MESH-DIRECTION.md` — why this matters
- `docs/prd/CODEX-INTEGRATION-MAP.md` §2.1 — original triage finding
- `runtime/udp-transport/` (post-merge) — U.2 foundation
- `runtime/session-protocol/` (post-merge) — U.2/U.3 foundation
- `extensions/chain-broadcast/` (post-merge) — orthogonal but useful for D-DOG.1.0e BSV anchoring later
