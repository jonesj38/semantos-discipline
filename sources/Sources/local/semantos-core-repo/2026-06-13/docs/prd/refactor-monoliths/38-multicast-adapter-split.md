---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/refactor-monoliths/38-multicast-adapter-split.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.772803+00:00
---

# 38 — Split `runtime/session-protocol/src/adapters/multicast-adapter.ts`

**Phase:** 12 (Session protocol + cell ops) · **Depends on:** 01 · **Est. effort:** 1 day · **Branch:** `refactor/38-multicast-adapter`

## Why

793 LOC adapter handling codec selection, peer management, inbound/outbound message handling, and subscription lifecycle — all inside one class. Testing any one concern drags the rest along.

## Deliverables

Create under `runtime/session-protocol/src/adapters/multicast/`:

- `ports/codec-port.ts` — `CodecPort` interface (`encode(envelope) → bytes`, `decode(bytes) → envelope`). Move existing codec logic behind it.
- `peer-manager.ts` — peer registry; tracks connected peers, addresses, last-seen; pure struct + functions.
- `message-handler.ts` — inbound envelope dispatch; pure function `handleIncoming(envelope, ctx) → HandlerEffect[]`.
- `outbound-queue.ts` — outbound queue + retry policy; driven by an effect atom.
- `subscription-store.ts` — `{ sessionId → Subscriber[] }`; add/remove/notify.
- `multicast-adapter.ts` — orchestrator (≤200 LOC) wiring peer-manager + message-handler + outbound-queue + subscription-store.
- `__tests__/` — unit tests per module + one integration test using in-memory codec + peer transport.

Edit:

- Re-export from `runtime/session-protocol/src/adapters/multicast-adapter.ts`.

## Acceptance criteria

- [ ] No file over 220 LOC.
- [ ] Codec is a port; swapping it requires only constructor wiring.
- [ ] All existing callers of `MulticastAdapter` compile without source changes.
- [ ] `pnpm --filter @semantos/session-protocol check` passes.

## Out of scope

- Changing wire format or protocol semantics.
- Adding new codecs.

## Test plan

Two peers over in-memory transport exchange 1k envelopes; subscription fan-out delivers each envelope to every subscriber exactly once. Peer-manager unit tests for add/remove/timeout.
