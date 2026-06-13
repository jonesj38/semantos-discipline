---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/refactor-monoliths/39-ws-node-adapter-split.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.775571+00:00
---

# 39 — Split `runtime/ws-node-adapter/src/ws-node-adapter.ts`

**Phase:** 12 (Session protocol + cell ops) · **Depends on:** 01 · **Est. effort:** 0.5 day · **Branch:** `refactor/39-ws-node-adapter`

## Why

560 LOC mixes WebSocket lifecycle, license verification, envelope encode/decode, and adapter registry into one module.

## Deliverables

Create under `runtime/ws-node-adapter/src/`:

- `peer-connection.ts` — single-peer lifecycle (connect, disconnect, keepalive, reconnection policy).
- `license-verifier.ts` — license token verification; pure function `verifyLicense(token, now) → Result<LicenseClaims, LicenseError>`.
- `envelope-codec.ts` — encode/decode + version negotiation.
- `adapter-registry.ts` — map of `{ peerId → PeerConnection }`; add/remove/lookup.
- `ws-node-adapter.ts` — orchestrator (≤180 LOC).
- `__tests__/*.test.ts`.

Edit:

- Keep `runtime/ws-node-adapter/src/ws-node-adapter.ts` exporting the orchestrator.

## Acceptance criteria

- [ ] No file over 200 LOC.
- [ ] License verifier has no import of `ws` (pure logic).
- [ ] Peer connection can be exercised against an in-memory `WebSocket` stub.
- [ ] `pnpm --filter ws-node-adapter check` passes.

## Out of scope

- Changing the WS wire protocol or licensing scheme.

## Test plan

Unit tests: connection with valid/invalid license; reconnection backoff; registry churn. Integration test with two in-process nodes.
