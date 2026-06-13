---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/refactor-monoliths/32-conversation-panel-refactor.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.774066+00:00
---

# 32 — Refactor `apps/loom-react/src/canvas/ConversationPanel.tsx`

**Phase:** 10 (Loom-react panels) · **Depends on:** 03 · **Est. effort:** 0.5 day · **Branch:** `refactor/32-conversation-panel`

## Why

534 LOC panel showing conversation context, evidence, governance signals. Same anti-pattern: reaches into loomStore state shape directly.

## Deliverables

Create under `apps/loom-react/src/canvas/conversation-panel/`:

- `atoms.ts` — `conversationAtom`, `evidenceAtom`; derived from `loomStateAtom`.
- `components/context-block.tsx`
- `components/evidence-block.tsx`
- `components/governance-signals.tsx`
- `hooks/useConversation.ts`
- `conversation-panel.tsx` — orchestrator (≤120 LOC).
- `__tests__/*.test.tsx`.

Edit:

- `apps/loom-react/src/canvas/ConversationPanel.tsx` → re-export orchestrator.

## Acceptance criteria

- [ ] Zero direct `loomStore.getState()`.
- [ ] Every component ≤ 150 LOC.
- [ ] All existing tests pass.
- [ ] `pnpm --filter @semantos/loom-react check` passes.

## Out of scope

- Changing panel UX.

## Test plan

Visual regression (or existing snapshot) shows identical output for 10 fixture conversations.
