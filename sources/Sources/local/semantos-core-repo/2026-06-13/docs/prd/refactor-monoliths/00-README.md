---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/refactor-monoliths/00-README.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.771346+00:00
---

# Monolith Refactor Prompts

This directory contains the full prompt set for the semantos-core monolith decomposition laid out in `MONOLITH_DECOMPOSITION.md` (repo root). Each numbered file is **one self-contained task** — paste it into Claude Code on a fresh branch and you'll get one PR.

## How to use

1. Open `00-MASTER-ROADMAP.md` to see the full ordering and dependencies.
2. Pick the next unblocked prompt.
3. Create a branch: `refactor/<prompt-number>-<slug>` (e.g. `refactor/01-state-primitives`).
4. Paste the prompt into Claude Code. The prompt includes every file path, acceptance criterion, and test plan the agent needs.
5. Review the PR against the acceptance criteria in the prompt. Merge when green.
6. Tick the roadmap.

## House rules (copied into every prompt by reference — do not skip)

Every prompt assumes the repo-wide guardrails in `IMPLEMENTATION_PROMPT.md`, plus these refactor-specific ones:

- **One prompt = one PR.** Don't combine two prompts into one branch. If a prompt is sized wrong, stop and flag it rather than silently expand scope.
- **No behavior change per PR.** These are structural refactors. Golden-value tests must pass before and after. If behavior has to change, split into a separate PR labelled clearly.
- **Old API stays alive for one release.** When a class is replaced with atoms + handlers, keep the old class as a thin facade delegating to the new implementation so downstream callers migrate at their own pace. Deprecation comments on the facade, not deletions.
- **Ports live in `core/protocol-types`.** Any interface that multiple packages import must be published from core so test doubles live in one place.
- **No new `archive/` imports; no new `allowlist` entries in `tests/gates/import-boundaries.test.ts`.** See existing plan.
- **Target max 400 LOC per new file.** If you hit 400, keep splitting.
- **Tests with the PR.** At minimum: every new pure function gets unit tests; every new reducer gets 10+ transition cases; every new port gets a doubling fixture exported from the same package.
- **Type-check and gate tests must pass:** `pnpm -r check && bun test tests/gates/`.

## Phase layout

| Phase | Prompts | What it unlocks |
|------:|:--------|:----------------|
| 0. Rename preamble   | 00A             | `Facet` → `Hat` rename across code, UI, tests, docs — lands first so every split inherits the new name |
| 1. Foundation        | 01              | Atom / port / registry / eventBus primitives everything else builds on |
| 2. LoomStore         | 02–03           | Biggest single leverage point — every loom-react panel slims down |
| 3. Core protocol-types | 04–07         | Cell store, semantic FS, wallet client, local identity become composable |
| 4. Router            | 08              | Collapse router.ts + router-browser.ts duplication |
| 5. Runtime services  | 09–12           | Intent classifier, config store, chat shell, VFS path resolver |
| 6. Payment channel   | 13–15           | FSM reducer + ports + effects; structurally enforces CashLanes guardrails |
| 7. Poker stack       | 16–21           | Shared primitives extracted; six files refactored as one unit |
| 8. MUD + games       | 22–26           | Reducer/effect template applied to game-sdk, room-actor, world-server, dungeon, chess |
| 9. Game extensions   | 27–29           | Game commands, SCADA authorization, CDM lifecycle |
| 10. Loom-react panels | 30–33          | Panels consume atomized LoomStore; shed ~40% of code |
| 11. Site + navigation | 34–37          | Interactive demo; navigation_app TS port + split |
| 12. Session protocol | 38–40           | Multicast adapter, WS-node adapter, bundle client |
| 13. Cell-ops         | 41–42           | Cell packer, WASM interface |
| 14. Validators       | 43              | Extension grammar validator |
| 15. Settlement       | 44              | Paskian settlement store |

## Not in this set

The following large files are not refactored because they're genuinely single-concern (data tables, test files, declarative schemas):

- `core/cell-engine/tests-bun/*.test.ts`
- `core/semantos-sir/src/__tests__/golden.test.ts`
- `apps/settlement/src/__tests__/border-router.test.ts`
- `extensions/navigation/src/types/navigation-objects.ts`
- `core/semantos-sir/src/lexicons.ts`
