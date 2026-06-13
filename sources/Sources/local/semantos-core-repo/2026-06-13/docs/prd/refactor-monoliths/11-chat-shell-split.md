---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/refactor-monoliths/11-chat-shell-split.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.768087+00:00
---

# 11 — Split `runtime/shell/src/chat.ts`

**Phase:** 5 (Runtime services) · **Depends on:** 01, 08 · **Est. effort:** 1 day · **Branch:** `refactor/11-chat-shell`

## Why

1034 LOC: REPL, LLM orchestration, conversation state, auto-ROM pricing, attachment handling, shell argument parsing — all in one module. Direct import of the router (circular-ish coupling) and a hardcoded OpenRouter URL.

## Deliverables

Create under `runtime/shell/src/chat/`:

- `chat-shell-repl.ts` — REPL loop, prompt rendering, command dispatch. Accepts `router`, `messageProcessor`, `stateSink` as ports/params.
- `conversation-state-store.ts` — atoms: `historyAtom`, `objectsAtom`, `attachmentsAtom`, `activeHatAtom`. (Uses post-rename vocabulary from prompt 00A.)
- `llm-processor.ts` — `processMessage(message, context) → LLMAction`. Uses `llmClientPort`.
- `rom-engine.ts` — pure `tryAutoROM`, `presentROM`, pricing calc.
- `shell-attachment-handler.ts` — attachment record/patch logic, injectable storage.
- `llm-action-types.ts` — `LLMAction`, `RomResult`, `ActionItem`.
- `ports.ts` — `llmClientPort`, `routerPort`, `settingsPort`.
- `__tests__/*.test.ts`.

Edit:

- `runtime/shell/src/chat.ts` → facade re-exporting the REPL entrypoint.

## Acceptance criteria

- [ ] Every new file ≤ 220 LOC.
- [ ] Router is imported via port, not directly.
- [ ] OpenRouter URL and model read from settings/ports, not module-level constants.
- [ ] All existing chat tests pass.
- [ ] `pnpm -r check` passes.

## Out of scope

- Changing REPL behavior or LLM prompts.
- Removing OpenRouter as the default (just make it swappable).

## Test plan

Golden transcript test: scripted user input sequence → expected system output, byte-identical pre- and post-refactor.
