---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/refactor-monoliths/12-vfs-path-resolver-split.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.766068+00:00
---

# 12 — Split `runtime/shell/src/vfs/pathResolver.ts`

**Phase:** 5 (Runtime services) · **Depends on:** 01, 03 · **Est. effort:** 0.5 day · **Branch:** `refactor/12-vfs-path-resolver`

## Why

665 LOC VFS path translator mixing path parsing, metadata serialization (header.bin, cert.json, capabilities.json), taxonomy tree walking, governance indexing, and async fallback logic for optional SemanticFS.

## Deliverables

Create under `runtime/shell/src/vfs/path-resolver/`:

- `path-parser.ts` — pure: `parseVfsPath(path) → { prefix, objectId, tail }`.
- `vfs-metadata-serializer.ts` — pure: `serializeObjectMetadata(obj, key) → VfsFileContent`.
- `taxonomy-walker.ts` — pure: `walkTaxonomyDir(nodes, segments)`.
- `governance-index.ts` — governance-specific view (ballots, disputes).
- `async-resolver.ts` — async variants using optional SemanticFS via port.
- `entry-cache.ts` — atom-backed `vfsEntryCache`, invalidated by effect watching `loomStateAtom`.
- `path-resolver-facade.ts` — orchestrator.
- `__tests__/*.test.ts`.

Edit:

- `runtime/shell/src/vfs/pathResolver.ts` → re-export facade.

## Acceptance criteria

- [ ] Path structure constants moved to config.
- [ ] Taxonomy tree walk is a pure function with tests.
- [ ] CellHeader serialization uses `cell-store` helpers from prompt 04 (no duplication).
- [ ] All existing VFS tests pass.
- [ ] `pnpm -r check` passes.

## Out of scope

- Changing VFS path layout.
- Changing binary layout of sidecar files.

## Test plan

Fixture: 50 VFS paths covering all prefixes and governance cases. Byte-identical resolved-entry output.
