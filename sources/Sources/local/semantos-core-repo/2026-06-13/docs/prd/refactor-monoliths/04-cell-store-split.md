---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/refactor-monoliths/04-cell-store-split.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.773810+00:00
---

# 04 — Split `core/protocol-types/src/cell-store.ts`

**Phase:** 3 (Core protocol-types) · **Depends on:** 01 · **Est. effort:** 1 day · **Branch:** `refactor/04-cell-store-split`

## Why

601 LOC mixing: cell header serialization, 1024-byte cell packing, SHA-256 hashing, chunking for large payloads, version-chain walking via prevStateHash, content-hash indexing, and storage adapter calls. Every downstream consumer (semantic-fs, poker-state-machine, payment-channel) reaches into one or more of these responsibilities.

## Deliverables

Create (under `core/protocol-types/src/cell-store/`):

- `cell-header-serializer.ts` — pure: `serializeCellHeader(h): Uint8Array`, `deserializeCellHeader(buf): CellHeader`.
- `cell-packer.ts` — pure: `packCell(header, payload): Uint8Array`, `unpackCell(bytes): { header, payload }`. Enforces 1024-byte fixed cell size.
- `cell-chunker.ts` — pure: `chunkData(data, chunkSize): Uint8Array[]`, `reassembleChunks(chunks): Uint8Array`.
- `content-hasher.ts` — `hashPort = port<{ sha256: (data: Uint8Array) => Promise<string> }>('content-hasher')`. Default impl uses `SubtleCrypto`.
- `version-chain-walker.ts` — `walkVersions(key, adapter): AsyncGenerator<CellRef>`.
- `content-indexer.ts` — manages `_index/content/{hash}` sidecar writes.
- `storage-adapter-facade.ts` — wraps raw `StorageAdapter` with named methods: `read`, `write`, `list`, `getVersioned`.
- `cell-store-facade.ts` — high-level `CellStore` class that orchestrates the modules. Maintains current public API (`put`, `get`, `history`, `verify`).
- `__tests__/*.test.ts` — per-module, plus one integration test exercising the facade.

Edit:

- `core/protocol-types/src/cell-store.ts` → re-export facade for backward compat; add `@deprecated` JSDoc pointing at `cell-store/cell-store-facade.ts`.
- `core/protocol-types/src/index.ts` — update exports.

## Acceptance criteria

- [ ] No file over 250 LOC.
- [ ] `content-hasher.ts` hashing implementation selectable via port (bind `SubtleCrypto` by default in a boot file).
- [ ] All existing cell-store tests pass.
- [ ] New unit tests for each pure module (≥8 cases each).
- [ ] `pnpm -r check` passes.

## Out of scope

- Changing cell binary layout, chunk sizes, or hashing algorithm.
- Rewriting the storage adapter implementations (cell-store is the only thing that should change here).

## Test plan

Golden-value test: take 100 key-value writes, put through old code, capture serialized cell bytes. Run through new facade, assert byte-identical output. Include at least one multi-cell payload (>1024 bytes) and one version chain of length ≥3.
