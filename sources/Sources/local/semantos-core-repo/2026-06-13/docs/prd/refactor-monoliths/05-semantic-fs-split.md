---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/refactor-monoliths/05-semantic-fs-split.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.768580+00:00
---

# 05 — Split `core/protocol-types/src/semantic-fs.ts`

**Phase:** 3 (Core protocol-types) · **Depends on:** 04 · **Est. effort:** 1 day · **Branch:** `refactor/05-semantic-fs-split`

## Why

530 LOC: taxonomy-aware path parsing, cell writing/reading, version history, reclassification with tombstones, semantic queries (byParent, byType, byOwner), and embedding-based semantic search — all in one class. The cell-store facade from prompt 04 makes this tractable.

## Deliverables

Create under `core/protocol-types/src/semantic-fs/`:

- `semantic-path-parser.ts` — pure: `parseSemanticPath(path, taxonomy): ParsedSemanticPath`. Greedy backward scan logic from lines 101–164 of the original.
- `semantic-path-validator.ts` — `validateForWrite(path, taxonomy): ParsedSemanticPath | throw`.
- `cell-reclassifier.ts` — writes tombstone + links new cell. Uses `CellStoreFacade` from prompt 04.
- `semantic-queries.ts` — pure filters: `queryByParent`, `queryByType`, `queryByOwner`, over metadata scanner output.
- `semantic-search.ts` — embedding-based search; defines `embeddingPort = port<EmbeddingProvider>('embedding')`.
- `metadata-scanner.ts` — scans `.meta` sidecars with a predicate.
- `type-hasher.ts` — `computeTypeHash(segments): Uint8Array`.
- `tombstone-resolver.ts` — resolves redirects: `resolvePath(path): string`.
- `semantic-fs-facade.ts` — the high-level `SemanticFS` class orchestrating the modules. Keeps current public API.
- `__tests__/*.test.ts`.

Edit:

- `core/protocol-types/src/semantic-fs.ts` → re-export facade for backward compat.

## Acceptance criteria

- [ ] No file over 220 LOC.
- [ ] Embedding search uses `embeddingPort`; test binds a deterministic stub.
- [ ] All existing semantic-fs tests pass.
- [ ] New tests per pure module.
- [ ] `pnpm -r check` passes.

## Out of scope

- Changing embedding behavior.
- Changing tombstone format.

## Test plan

Golden: 50-scenario fixture covering parse/validate/query/reclassify/search. Byte-for-byte identical cell writes before and after.
