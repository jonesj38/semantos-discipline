---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-R0-REPO-HYGIENE.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.710011+00:00
---

# Phase R0 — Repository Hygiene & README Correction

> **Goal**: Get `main` into a clean, accurate, shareable state.
> **Risk level**: Low — no structural refactoring, only branch cleanup, doc commits, and README rewrite.
> **Prerequisite**: None. This is step zero.

---

## Current State (assessed 2026-03-29)

### Git

| Branch | Behind main | Ahead of main | Status |
|--------|------------|---------------|--------|
| `main` (local) | 5 behind origin | 0 | **Stale** — needs `git pull` to pick up Phase 10 |
| `phase-10-taxonomy-governance` | 0 | 0 | Identical to `origin/main`. **Delete.** |
| `phase-9.5-publication-governance` | 18 | 12 | Work is on main (different SHAs — was rebased). PR #3 open. **Close PR, delete.** |
| `phase-9-intent-classification` | 17 | 0 | Fully merged (PR #2). **Delete.** |
| `phase-7.5-errata-sprint` | 18 | 7 | All 7 commits are duplicates of work on main (went via other branches). **Delete.** |
| `phase-7-bindings` | 19 | 1 | Fully merged. **Delete.** |
| `claude/affectionate-hodgkin` | — | 0 | Empty. **Delete.** |
| `claude/angry-villani` | — | 0 | Empty. **Delete.** |
| `claude/ecstatic-kare` | — | 0 | Empty. **Delete.** |
| `claude/funny-mendel` | — | 0 | Empty. **Delete.** |
| `claude/intelligent-northcutt` | — | 0 | Empty. **Delete.** |
| `claude/naughty-khayyam` | — | 7 | Duplicates of phase-7.5 work. **Delete.** |

No tags exist anywhere. No recovery points.

### Untracked Files on Current Branch

All of these are docs/PRDs that should be committed:

```
docs/BRANCHING-AND-CI-POLICY.md
docs/FORMAL-VERIFICATION-STRATEGY.md
docs/PHASE-4-UPDATE.md
docs/Semantos-Protocol-Spec-v0.01.docx
docs/Semantos-Whitepaper-v2.docx
docs/TAXONOMY-SEED-DESIGN.md
docs/design/SHOMEE-TO-SEMANTOS-MAPPING.md
docs/prd/PHASE-11-FORMAL-VERIFICATION.md
docs/prd/PHASE-11-FULL-PROMPT.md
docs/prd/PHASE-11.5-FULL-PROMPT.md
docs/prd/PHASE-11.5-TLA-PROTOCOL.md
docs/prd/PHASE-12-FULL-PROMPT.md
docs/prd/PHASE-12-IMPLEMENTATION-BRIDGE.md
packages/cell-engine/OPCODE-HARDENING-PLAN.md
```

Also needs `.gitignore` entries for: `.DS_Store`, `.claude/`, `packages/loom/bun.lock` (debatable), `.zig-cache/`, `zig-out/`.

### README Problem

The root README says:
- "This is the TypeScript half of Semantos" — **false**, the Zig kernel is in `packages/cell-engine/`
- "The Zig/WASM cell engine lives in the sibling `semantos` repo" — **false**, it's here
- "What's NOT here" table claims the 2-PDA is elsewhere — **false**, it's `packages/cell-engine/src/pda.zig`

---

## Deliverables

### R0.1 — Baseline Tag

Before touching anything, tag the current `origin/main` so we have a known recovery point.

```bash
git checkout main
git pull origin main
git tag v0.3.0-baseline -m "Baseline before repo hygiene — Phase 10 complete"
git push origin v0.3.0-baseline
```

### R0.2 — Branch Cleanup

Delete all stale branches, local and remote. Close PR #3 first if it hasn't been merged.

**Local deletions:**
```bash
# Safe — all fully merged or duplicate
git branch -d phase-7-bindings
git branch -d phase-9-intent-classification
git branch -d phase-10-taxonomy-governance
git branch -D phase-7.5-errata-sprint        # -D because diverged (duplicates)
git branch -D phase-9.5-publication-governance # -D because diverged (duplicates)
git branch -D claude/affectionate-hodgkin
git branch -D claude/angry-villani
git branch -D claude/ecstatic-kare
git branch -D claude/funny-mendel
git branch -D claude/intelligent-northcutt
git branch -D claude/naughty-khayyam
```

**Remote deletions:**
```bash
git push origin --delete phase-7-bindings
git push origin --delete phase-7.5-errata-sprint
git push origin --delete phase-9-intent-classification
git push origin --delete phase-9.5-publication-governance
git push origin --delete phase-10-taxonomy-governance
```

### R0.3 — Gitignore & Untracked Docs

On `main`, in a single commit:

1. Add/update `.gitignore`:
   ```
   # OS
   .DS_Store
   Thumbs.db

   # Build artifacts
   dist/
   node_modules/
   packages/loom/node_modules/
   packages/cell-engine/.zig-cache/
   packages/cell-engine/zig-out/

   # IDE / tools
   .claude/
   .vscode/

   # Lock files (Bun — regenerated on install)
   bun.lock
   ```

2. Remove tracked `.DS_Store` if any: `git rm --cached .DS_Store` etc.

3. Commit all untracked docs:
   ```
   git add docs/ packages/cell-engine/OPCODE-HARDENING-PLAN.md .gitignore
   git commit -m "R0.3: commit untracked docs, add .gitignore"
   ```

### R0.4 — README Rewrite

Replace the root README with one that accurately describes this as a **polyglot monorepo** containing both the Zig/WASM kernel and the TypeScript type system, compiler, and loom. Key corrections:

- Remove all references to a sibling `semantos` repo
- Describe `packages/cell-engine/` as the Zig/WASM kernel (4,900 LOC)
- Describe `src/` as the TypeScript core library (types, compiler, recovery, metering)
- Show the actual dependency graph
- Drop the "What's NOT here" row for 2-PDA
- Add a "Repository Structure" section showing the real layout

```
git add README.md
git commit -m "R0.4: rewrite README to accurately describe polyglot monorepo"
```

### R0.5 — Protect Main & Tag

1. Enable branch protection on `main` via GitHub (require PR reviews before merge)
2. Tag the clean state:
   ```bash
   git tag v0.3.1 -m "Clean main: accurate README, docs committed, branches pruned"
   git push origin main --tags
   ```

---

## Verification Checklist

- [ ] `git branch` shows only `main` (and any active feature branches)
- [ ] `git status` on main is clean (nothing untracked except intentionally ignored files)
- [ ] README accurately describes both Zig and TypeScript components
- [ ] No references to a sibling `semantos` repo anywhere in README
- [ ] `v0.3.0-baseline` tag exists as recovery point
- [ ] `v0.3.1` tag marks clean state
- [ ] `bun run check` passes
- [ ] `bun run build` passes

---

## What This Does NOT Do

This phase is deliberately limited to hygiene. The following structural improvements are deferred to Phase R1:

| Deferred concern | Why defer |
|-----------------|-----------|
| Promote `src/` modules into `packages/` | Import rewiring, high risk |
| Merge `src/cell-engine/` into `packages/cell-engine/` | Same — needs careful import migration |
| Add Bun workspace config | Depends on package structure being finalised |
| Standardise inter-package dependency style | `file:` vs tsconfig paths — decide after structure settles |
| CI pipeline setup | Needs branch protection + structure first |

---

## Recovery

If anything goes wrong during R0, the `v0.3.0-baseline` tag is the recovery point:

```bash
git checkout main
git reset --hard v0.3.0-baseline
git push origin main --force-with-lease
```
