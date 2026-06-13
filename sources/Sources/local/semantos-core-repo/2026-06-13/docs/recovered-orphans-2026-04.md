---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/recovered-orphans-2026-04.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.329267+00:00
---

# Recovered orphan commits — 2026-04-18

After the worktree prune, 63 dangling commits were preserved as refs under `refs/recovery/<short-hash>` to survive `git gc`.

## Recovery commands

```bash
# Inspect a recovered commit
git show refs/recovery/<short-hash>

# Cherry-pick onto your current branch
git cherry-pick refs/recovery/<short-hash>

# Check out as a detached HEAD to investigate
git checkout refs/recovery/<short-hash>

# List all preserved refs
git for-each-ref refs/recovery/
```

## High-value commits (substantial real changes, not WIP/stash)

Sorted by file-change magnitude. These are the most likely candidates for re-incorporation.

| Hash | Date | Summary | Files | Insertions |
|---|---|---|---|---|
| `9c3ef06` | 2026-03-30 | docs: add PRD and design docs for Phases 13-21 | 24 | 12331 |
| `3906d5d` | 2026-03-29 | Merge phase-9.5-publication-governance: visibility + governance types | 82 | 8205 |
| `7429fd2` | 2026-04-12 | Merge remote-tracking branch 'origin/main' into claude/crazy-mccarthy | 44 | 4523 |
| `3c2aa2a` | 2026-04-14 | Phase 39: Helm attention surface + type foundation + calendar events | 75 | 4467 |
| `39fa803` | 2026-04-10 | feat(esp32+games): add esp32-hackkit and bitECS integration | 32 | 3165 |
| `cad8c1c` | 2026-04-14 | fix: resolve 16 pre-existing test failures across gate suite | 70 | 1867 |
| `4e5a023` | 2026-04-12 | fix: resolve 16 pre-existing test failures across gate suite | 71 | 1854 |
| `e8e1ddf` | 2026-03-30 | Merge phase-25a-storage-adapter into main | 20 | 1369 |
| `b158a27` | 2026-03-30 | full test pass | 4 | 1070 |
| `d533008` | 2026-03-30 | phase-24/D24.1: embedding-enhanced intent classification | 4 | 651 |
| `0aed489` | 2026-04-17 | On post-helm-merge: wip-step1 | 20 | 556 |
| `894131b` | 2026-04-16 | On helm-to-shell-sprint: build-artifacts-cleanup-sprint-start | 17 | 475 |
| `735fd6c` | 2026-04-17 | phase-38/D38A.3: gate tests for HostCommand, HOST_EXEC, and trust-tier enforceme | 1 | 323 |
| `b4deba2` | 2026-04-03 | phase-30g/D30G.7: add comprehensive Dart/Flutter integration tests | 3 | 308 |
| `3056cfc` | 2026-04-01 | phase-26a/T1-T15: gate tests — adapter interface, integration, anti-lock | 2 | 263 |
| `08891af` | 2026-03-29 | Add Phase 10 full execution prompt (git + build + errata) | 1 | 191 |
| `f29de2e` | 2026-04-01 | phase-26d/errata: adversarial review — zero MUST FIX, two low-severity observa | 1 | 102 |
| `aa4933d` | 2026-03-30 | phase-14/errata: adversarial review — 8 findings, all low/info severity | 1 | 59 |
| `783ec21` | 2026-03-29 | Revert "phase-9.5/D9.5.1 (WIP): visibility states, reducer, store validation" | 7 | 25 |
| `0121c2c` | 2026-04-10 | On wip/session-safety-net: payment-channel prev-hash fix | 1 | 24 |
| `6bbe84a` | 2026-03-30 | phase-19/CI: anti-lock lint checks for shell package | 1 | 12 |
| `d16e066` | 2026-03-30 | fix CI: pin TS 5.8, add Zig to gate, fix lint grep pattern | 3 | 9 |
| `d426bfc` | 2026-03-31 | fix(gate): update T17 assertion for Phase 25 EmbeddingService migration | 1 | 4 |
| `50e27e1` | 2026-03-30 | Revert "fix/strip-gip-nomenclature: update README to reflect GIP removal" | 1 | 3 |
| `c8f9efe` | 2026-04-16 | On helm-to-shell-sprint: vite config changes | 1 | 2 |

## All preserved orphans (chronological, newest first)

| Date | Hash | Summary | Files |
|---|---|---|---|
| 2026-04-17T22:43 | `1bcc5e0` | WIP on feat/phase-38d: 0db1c7c Phase 38D: host.audit — read-only cryptographic verificat | 20 |
| 2026-04-17T20:09 | `cc1acb4` | WIP on feat/semantos-ir: 91a425e sir/W3.4: domain binding types + multi-flag lowering with | 16 |
| 2026-04-17T01:22 | `735fd6c` | phase-38/D38A.3: gate tests for HostCommand, HOST_EXEC, and trust-tier enforcement | 1 |
| 2026-04-17T01:14 | `0aed489` | On post-helm-merge: wip-step1 | 20 |
| 2026-04-17T00:24 | `afed119` | WIP on cleanup/helm-shell-redundancy: a0104e4 cleanup: remove orphaned pre-pyramid command | 18 |
| 2026-04-17T00:22 | `5f9079e` | WIP on cleanup/helm-shell-redundancy: a0104e4 cleanup: remove orphaned pre-pyramid command | 18 |
| 2026-04-16T14:36 | `894131b` | On helm-to-shell-sprint: build-artifacts-cleanup-sprint-start | 17 |
| 2026-04-16T00:39 | `c8f9efe` | On helm-to-shell-sprint: vite config changes | 1 |
| 2026-04-16T00:00 | `0974a48` | On rename/workbench-package-to-loom: WIP: lean artifacts on pedantic-brown | 23 |
| 2026-04-15T21:39 | `f1f8995` | On rename/workbench-package-to-loom: WIP: unstaged lean artifacts and cli.ts on rename/wor | 23 |
| 2026-04-15T00:31 | `0b3fbe1` | WIP on claude/hungry-euclid: f0c3a71 rename: Facet → Hat across entire codebase (identit | 1 |
| 2026-04-14T23:28 | `cad8c1c` | fix: resolve 16 pre-existing test failures across gate suite | 70 |
| 2026-04-14T23:12 | `e87c2dc` | On feat/extended-opcodes: WIP: feat/extended-opcodes changes before PR merge plan | 50 |
| 2026-04-14T22:48 | `f91d71e` | Remove web UI server and navigation_app package | 169 |
| 2026-04-14T17:05 | `67c4f15` | WIP on shell/consolidation: 4813ca8 Fix duplicate exports after nostalgic-euler merge | 15 |
| 2026-04-14T16:18 | `3c2932a` | WIP on main: cce407b Merge phase-4-route-table: Route table + library verb pattern | 25 |
| 2026-04-14T16:16 | `7948fd9` | WIP on shell/consolidation: 4071bdf Phase 5F: Register 11 new extensions in ConfigStore BU | 25 |
| 2026-04-14T14:48 | `c72e365` | WIP on library/types-and-ui: cce407b Merge phase-4-route-table: Route table + library verb | 3 |
| 2026-04-14T11:48 | `ec56fa0` | WIP on main: ba9ce33 Merge shell/consolidation: Phase 1-3 shell revision (109 tests, impor | 25 |
| 2026-04-14T11:33 | `18d0ad6` | WIP on main: 446dd73 Merge phase-36e-extension-manager-ui: Extension Manager UI | 25 |
| 2026-04-14T01:28 | `3c2aa2a` | Phase 39: Helm attention surface + type foundation + calendar events | 75 |
| 2026-04-12T23:37 | `0186ae5` | WIP on claude/silly-kare: 8f37d8d Navigator PWA: multi-extension kernel bridge + Phase 37  | 1 |
| 2026-04-12T23:02 | `f91a23a` | WIP on main: df79210 Merge phase-36d-extension-governance-model: Extension Governance Mode | 25 |
| 2026-04-12T22:44 | `291a420` | WIP on phase-36e-extension-manager-ui: 59e8e5e phase-36e/D36E.1-D36E.8: Extension Manager  | 25 |
| 2026-04-12T22:06 | `591d249` | WIP on main: a2e6400 Merge navigator-consciousness-split: navigation → navigator (core)  | 25 |
| 2026-04-12T22:03 | `5c5b6bc` | WIP on main: 0dc44ab Merge phase-36c-schema-inference-agent: Schema Inference Agent | 35 |
| 2026-04-12T22:03 | `07c0c97` | WIP on main: 0dc44ab Merge phase-36c-schema-inference-agent: Schema Inference Agent | 35 |
| 2026-04-12T09:44 | `4e5a023` | fix: resolve 16 pre-existing test failures across gate suite | 71 |
| 2026-04-12T09:20 | `8e58a31` | WIP on hackathon/semantos-swarm: 05e4944 fix: resolve pre-existing merge conflict markers  | 2 |
| 2026-04-12T01:32 | `d78d539` | WIP on main: 645bba8 Merge pull request #53 from todriguez/worktree-crazy-mccarthy | 25 |
| 2026-04-12T00:20 | `7429fd2` | Merge remote-tracking branch 'origin/main' into claude/crazy-mccarthy | 44 |
| 2026-04-12T00:19 | `066e6b8` | WIP on claude/crazy-mccarthy: 78e368e phase-36a/D36A.8: errata sprint — adversarial revi | 25 |
| 2026-04-11T23:25 | `cba9bd4` | WIP on hackathon/semantos-swarm: 7d78727 merge: incorporate CAS storage (phase-30f2) — r | 6 |
| 2026-04-11T23:25 | `acd84d3` | WIP on hackathon/semantos-swarm: 7d78727 merge: incorporate CAS storage (phase-30f2) — r | 216 |
| 2026-04-11T23:24 | `7cc1987` | WIP on hackathon/semantos-swarm: 7d78727 merge: incorporate CAS storage (phase-30f2) — r | 1 |
| 2026-04-11T23:03 | `bf90ad0` | WIP on hackathon/semantos-swarm: e9ed63f merge: incorporate ISDA CDM (phase-28) | 1 |
| 2026-04-11T23:03 | `0a6cb3b` | WIP on hackathon/semantos-swarm: 6d383d8 wip: full working-tree snapshot before clean-bran | 1 |
| 2026-04-11T22:35 | `1c665b7` | WIP on claude/amazing-newton: c451366 fix: chess registry passthrough, T24 taxonomy check, | 1 |
| 2026-04-11T22:15 | `5c055f1` | fix: align @bsv/sdk version to ^2.0.0 in policy-runtime | 1 |
| 2026-04-11T22:04 | `dc9eb42` | fix: BCA sec parameter guard uses BCA_COLLISION_COUNT_MAX (not 7) | 1 |
| 2026-04-10T22:07 | `d568a38` | WIP on claude/wonderful-jennings: 5a9d334 wip: uncommitted chess-stakes game + flutter pod | 5 |
| 2026-04-10T22:06 | `5b44a96` | WIP on phase-29-scada: aee37be wip: uncommitted SCADA demo script | 2 |
| 2026-04-10T21:50 | `77d3fc5` | WIP on phase-12-implementation-bridge: 2f9c0d5 Phase 12 errata: audit doc + fix 2 issues | 1 |
| 2026-04-10T21:50 | `0121c2c` | On wip/session-safety-net: payment-channel prev-hash fix | 1 |
| 2026-04-10T21:49 | `edc7a94` | WIP on wip/session-safety-net: 6d383d8 wip: full working-tree snapshot before clean-branch | 1 |
| 2026-04-10T08:08 | `39fa803` | feat(esp32+games): add esp32-hackkit and bitECS integration | 32 |
| 2026-04-03T10:40 | `b4deba2` | phase-30g/D30G.7: add comprehensive Dart/Flutter integration tests | 3 |
| 2026-04-02T23:38 | `2f8c765` | WIP on phase-30b-adapter-callbacks: e00c83b errata/phase24-T17: update T17 to reflect Phas | 3 |
| 2026-04-02T07:38 | `cc9cf35` | WIP on phase-26h-extension-rename: 6fcc73b phase-26h/D26H.6-fix: fix straggler vertical re | 2 |
| 2026-04-01T23:29 | `f29de2e` | phase-26d/errata: adversarial review — zero MUST FIX, two low-severity observations | 1 |
| 2026-04-01T21:05 | `3056cfc` | phase-26a/T1-T15: gate tests — adapter interface, integration, anti-lock | 2 |
| 2026-03-31T07:12 | `d426bfc` | fix(gate): update T17 assertion for Phase 25 EmbeddingService migration | 1 |
| 2026-03-30T23:23 | `e8e1ddf` | Merge phase-25a-storage-adapter into main | 20 |
| 2026-03-30T21:49 | `d533008` | phase-24/D24.1: embedding-enhanced intent classification | 4 |
| 2026-03-30T12:10 | `b158a27` | full test pass | 4 |
| 2026-03-30T11:28 | `50e27e1` | Revert "fix/strip-gip-nomenclature: update README to reflect GIP removal" | 1 |
| 2026-03-30T10:57 | `9c3ef06` | docs: add PRD and design docs for Phases 13-21 | 24 |
| 2026-03-30T00:51 | `6bbe84a` | phase-19/CI: anti-lock lint checks for shell package | 1 |
| 2026-03-30T00:46 | `aa4933d` | phase-14/errata: adversarial review — 8 findings, all low/info severity | 1 |
| 2026-03-30T00:14 | `d16e066` | fix CI: pin TS 5.8, add Zig to gate, fix lint grep pattern | 3 |
| 2026-03-29T08:33 | `3906d5d` | Merge phase-9.5-publication-governance: visibility + governance types | 82 |
| 2026-03-29T08:15 | `08891af` | Add Phase 10 full execution prompt (git + build + errata) | 1 |
| 2026-03-29T07:57 | `783ec21` | Revert "phase-9.5/D9.5.1 (WIP): visibility states, reducer, store validation" | 7 |

## Cleanup

Once you've recovered everything you want, prune the refs:

```bash
# Delete all recovery refs (commits then become eligible for git gc)
git for-each-ref refs/recovery/ --format="delete %(refname)" | git update-ref --stdin
```
