---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/refactor-monoliths/20-p2p-agent-runner-split.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.773562+00:00
---

# 20 — Split `apps/poker-agent/src/p2p-agent-runner.ts`

**Phase:** 7 (Poker stack) · **Depends on:** 16, 17 · **Est. effort:** 0.5 day · **Branch:** `refactor/20-p2p-agent-runner`

## Why

721 LOC standalone P2P player process: MessageBox transport, turn-based FSM, deterministic shuffle, hand result tracking.

## Deliverables

Create under `apps/poker-agent/src/p2p-agent-runner/`:

- `turn-coordinator.ts` — `turnAtom = atom<'mine' | 'opponent'>`; blocks on opponent turn via promise subscribers.
- `beef-transceiver.ts` — send/receive moves; wraps MessageBox; uses `shared/beef-codec.ts`.
- `hand-shuffle.ts` — uses `shared/deterministic-shuffle.ts`; seeded for both players.
- `message-queue.ts` — effect-driven queue: `messageQueueAtom`, `waitForMove()` as async effect.
- `p2p-context-builder.ts` — pure: `(me, opponent, table, config) → HandContext`.
- `p2p-agent-runner.ts` — facade.
- `__tests__/*.test.ts`.

Edit:

- `apps/poker-agent/src/p2p-agent-runner.ts` → re-export facade.

## Acceptance criteria

- [ ] Turn coordination testable without a real transport.
- [ ] Transport is a port (`transportPort`).
- [ ] `pnpm -r check` passes.

## Out of scope

- Changing P2P message protocol.

## Test plan

Two runners with a test-double transport complete a full hand; assert final state + audit log match recorded fixture.
