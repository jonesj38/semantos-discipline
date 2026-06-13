---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/refactor-monoliths/31-chat-view-refactor.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.773309+00:00
---

# 31 — Refactor `apps/loom-react/src/canvas/ChatView.tsx`

**Phase:** 10 (Loom-react panels) · **Depends on:** 03, 30 · **Est. effort:** 1 day · **Branch:** `refactor/31-chat-view`

## Why

632 LOC chat-first Loom interface: intent classification, flow execution, object creation/consumption, evidence chain display, settings, capabilities, autocompletion. Reaches into `loomStore.getState()` in many places — prime candidate for atom-based consumption.

## Deliverables

Create under `apps/loom-react/src/canvas/chat-view/`:

- `atoms.ts` — `messagesAtom`, `classifyingAtom`, `activeFlowStepAtom`, `flowProgressAtom`, `settingsOpenAtom`. Plus derived selectors reading from `loomStateAtom`.
- `components/message-list.tsx`
- `components/inspection-block.tsx`
- `components/settings-panel.tsx`
- `components/capabilities-display.tsx`
- `components/composer.tsx`
- `hooks/useSelectedObject.ts` — replaces inline `state.selectedObjectId` access.
- `services/intent-classifier.ts` — local wrapper around `runtime-services` classifier via port.
- `services/message-handler.ts` — `handleSend()` command dispatcher.
- `chat-view.tsx` — orchestrator (≤150 LOC).
- `__tests__/*.test.tsx`.

Edit:

- `apps/loom-react/src/canvas/ChatView.tsx` → re-export orchestrator.

## Acceptance criteria

- [ ] Zero direct `loomStore.getState()` calls anywhere in the chat-view directory.
- [ ] `LINEARITY_LABELS` moved to a shared constants module.
- [ ] Orchestrator ≤ 150 LOC; every component file ≤ 180 LOC.
- [ ] All existing chat-view tests pass.
- [ ] `pnpm --filter @semantos/loom-react check` passes.

## Out of scope

- Changing chat UX or intent classification.

## Test plan

Scripted conversation fixture produces identical message list and evidence chain output.
