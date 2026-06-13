---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/refactor-monoliths/40-bundle-client-split.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.771092+00:00
---

# 40 — Split `runtime/session-protocol/src/bsv-overlay-bundle-client.ts`

**Phase:** 12 (Session protocol + cell ops) · **Depends on:** 01 · **Est. effort:** 0.5 day · **Branch:** `refactor/40-bundle-client`

## Why

481 LOC client that publishes bundles, subscribes for new ones, dedupes, and polls — all in one shape.

## Deliverables

Create under `runtime/session-protocol/src/bundle/`:

- `publisher.ts` — publish bundle to overlay; pure request builder + adapter call.
- `subscriber.ts` — long-poll / streaming subscription; returns `AsyncIterable<Bundle>`.
- `dedupe-cache.ts` — content-addressed dedupe (txid/bundleHash → seen-at); LRU with TTL.
- `poller.ts` — polling loop + backoff; driven by an effect atom or manual start/stop.
- `bundle-client.ts` — facade (≤150 LOC).
- `__tests__/*.test.ts`.

Edit:

- Re-export from `runtime/session-protocol/src/bsv-overlay-bundle-client.ts`.

## Acceptance criteria

- [ ] No file over 180 LOC.
- [ ] Dedupe cache unit-tested against a 10k-event replay fixture.
- [ ] `pnpm --filter @semantos/session-protocol check` passes.

## Out of scope

- Changing overlay query URLs or bundle schema.

## Test plan

Stub overlay server answering publish/subscribe; exercise publish → subscribe → dedupe path end-to-end.
