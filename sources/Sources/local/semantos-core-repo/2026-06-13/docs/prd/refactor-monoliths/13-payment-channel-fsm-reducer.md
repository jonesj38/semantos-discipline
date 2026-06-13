---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/refactor-monoliths/13-payment-channel-fsm-reducer.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.769337+00:00
---

# 13 — Payment-channel FSM: extract pure reducer

**Phase:** 6 (Payment channel) · **Depends on:** 01 · **Est. effort:** 1 day · **Branch:** `refactor/13-payment-channel-reducer`

## Why

`apps/poker-agent/src/payment-channel.ts` is 1627 LOC — the largest file in the repo — and a perfect target for the reducer-plus-effects split described in `CLAUDE.md`. That doc already prescribes the FSM (`UNFUNDED → FUNDING_PENDING → FUNDED → FLOW_READY → FLOW_ACTIVE → SETTLING → CLOSED`) and the freeze-bytes guardrails. We're going to make the FSM a pure function, the freeze rules reducer invariants, and let 14/15 wire the external effects.

## Deliverables

Create under `apps/poker-agent/src/payment-channel/fsm/`:

- `types.ts` — `ChannelState`, `ChannelEvent`, `ChannelAction` (union), `ChannelArtifacts` (frozen bytes).
- `reducer.ts` — `export function channelReducer(state, action): { next, emitted }` returns next state plus a list of commands/events to be executed by effects.
- `invariants.ts` — pure assertions enforcing `CLAUDE.md` guardrails: (1) freeze envelopeHex and simpleRawTx bytes at funding; (2) only advance on real wallet success / SPV proof attachment; (3) no P2SH; (4) role-scoped keyIDs have required entropy format `<role>-<scope>:<orgId>:<ts>:<nonce>`.
- `transitions.ts` — per-phase transition handlers used by the reducer.
- `__tests__/reducer.test.ts` — ≥40 transition cases covering happy path + every invariant rejection.
- `__tests__/invariants.test.ts` — explicit tests for each `CLAUDE.md` guardrail.

Edit:

- `apps/poker-agent/src/payment-channel.ts` — keep class as facade; route its state updates through `channelReducer`. Side-effecting methods (wallet calls, broadcasts) still live here — they'll move in prompt 15.

## Acceptance criteria

- [ ] Reducer is pure: `grep -n "await\|this\.\|Date\.now\|Math\.random" fsm/reducer.ts fsm/transitions.ts fsm/invariants.ts` returns zero matches.
- [ ] Invariant tests explicitly reference `CLAUDE.md` rule numbers in the test descriptions.
- [ ] All existing payment-channel tests pass.
- [ ] `pnpm -r check` passes.
- [ ] Net LOC delta: `payment-channel.ts` drops by ~300 LOC into the fsm module.

## Out of scope

- Wallet/broadcast/SPV integration (prompts 14, 15).
- Changing the FSM state set — it's fixed by `CLAUDE.md`.

## Test plan

Record 5 end-to-end channel flows pre-refactor (happy path, funding failure, extract mismatch, settle without SPV, close). Replay the event sequences through `channelReducer` post-refactor; final state plus intermediate snapshots must match exactly.
