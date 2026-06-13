---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/refactor-monoliths/27-game-commands-split.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.776828+00:00
---

# 27 — Split `extensions/games/src/cli/game-commands.ts`

**Phase:** 9 (Game extensions) · **Depends on:** 22 · **Est. effort:** 0.5 day · **Branch:** `refactor/27-game-commands`

## Why

690 LOC CLI command surface mixing parsing, help text, per-game dispatch, and output formatting.

## Deliverables

Create under `extensions/games/src/cli/commands/`:

- `command-registry.ts` — registry-based dispatcher.
- `commands/` — one file per command (`start.ts`, `move.ts`, `status.ts`, `join.ts`, etc.).
- `help-renderer.ts` — generates help from registry entries.
- `output-formatter.ts` — pure formatters per game type.
- `__tests__/*.test.ts`.

Edit:

- `extensions/games/src/cli/game-commands.ts` → re-export registry.

## Acceptance criteria

- [ ] No file over 150 LOC.
- [ ] Help output identical to pre-refactor.
- [ ] All existing CLI tests pass.
- [ ] `pnpm -r check` passes.

## Out of scope

- Changing CLI grammar or flags.

## Test plan

Snapshot help text; snapshot each command's output for fixture inputs.
