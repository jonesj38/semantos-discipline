---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/worktree-audit-2026-04.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.325938+00:00
---

# Worktree audit — 2026-04-18

Pre-deletion audit of all 27 worktrees in `.claude/worktrees/` before pruning as part of restructuring branch `refactor/core-runtime-extensions-apps`.

Each worktree was checked for:
1. Uncommitted changes (`git status --porcelain`)
2. Commits ahead of upstream (`git log @{u}..HEAD --oneline`)
3. Branch + last commit hash

## Recovery follow-up (post-deletion)

After pruning, a follow-up audit found 63 dangling commits in the object store — orphaned WIP/snapshot commits from the pruned worktrees that are not reachable from any live branch. Each was preserved as `refs/recovery/<short-hash>` so it survives `git gc`. Catalog with high-value commits flagged: [recovered-orphans-2026-04.md](recovered-orphans-2026-04.md).

The 47 plain working-tree edits from `nice-shaw` (uncommitted, never staged) are not in any git object and could not be recovered. The most recent staged WIP from related branches (DoMode/FindMode/TalkMode cleanup, Phase 39 Helm + calendar events) IS preserved via the recovery refs.

## Audit results

| Worktree | Branch | HEAD | Uncommitted | Ahead of upstream |
|---|---|---|---|---|
| affectionate-hodgkin | ? | ? | 0 file(s) | 0 commit(s) |
| angry-villani | ? | ? | 0 file(s) | 0 commit(s) |
| busy-dhawan | shell/consolidation | 4813ca8 | 29 file(s) | 0 commit(s) |
| determined-lewin | phase-36e-extension-manager-ui | 59e8e5e | 26 file(s) | 0 commit(s) |
| ecstatic-ishizaka | claude/ecstatic-ishizaka | 01d7afc | 36 file(s) | 0 commit(s) |
| ecstatic-kare | ? | ? | 0 file(s) | 0 commit(s) |
| eloquent-cannon | claude/eloquent-cannon | 01d7afc | 10 file(s) | 0 commit(s) |
| flamboyant-allen | library/types-and-ui | cce407b | 26 file(s) | 0 commit(s) |
| flamboyant-saha-814d | claude/flamboyant-saha-814d | 78e368e | 10 file(s) | 0 commit(s) |
| funny-mendel | ? | ? | 0 file(s) | 0 commit(s) |
| heuristic-galileo | claude/heuristic-galileo | e4a61ba | 13 file(s) | 0 commit(s) |
| intelligent-northcutt | ? | ? | 0 file(s) | 0 commit(s) |
| keen-euler | claude/keen-euler | c3b7533 | 10 file(s) | 0 commit(s) |
| naughty-khayyam | ? | ? | 0 file(s) | 0 commit(s) |
| nervous-blackwell | claude/nervous-blackwell | e2f9f88 | 0 file(s) | 0 commit(s) |
| nice-shaw | claude/nice-shaw | 044e88f | 47 file(s) | 0 commit(s) |
| nostalgic-euler | claude/nostalgic-euler | 79d5795 | 0 file(s) | 0 commit(s) |
| practical-meitner | claude/practical-meitner | 044e88f | 0 file(s) | 0 commit(s) |
| relaxed-hawking | claude/relaxed-hawking | f58757d | 0 file(s) | 0 commit(s) |
| romantic-noyce | ? | ? | 0 file(s) | 0 commit(s) |
| silly-kare | phase-37-kernel-bridge-adapter-wiring | beb2d06 | 1 file(s) | 0 commit(s) |
| stupefied-roentgen | claude/stupefied-roentgen | 4624712 | 0 file(s) | 0 commit(s) |
| thirsty-bardeen | claude/thirsty-bardeen | bcd8738 | 10 file(s) | 0 commit(s) |
| upbeat-shamir | claude/upbeat-shamir | 20233a3 | 23 file(s) | 0 commit(s) |
| vibrant-sanderson | phase-36d-extension-governance-model | 09db065 | 36 file(s) | 0 commit(s) |
| zealous-noether | claude/zealous-noether | 4813ca8 | 0 file(s) | 0 commit(s) |
| zen-williamson | claude/zen-williamson | 4964388 | 0 file(s) | 0 commit(s) |
