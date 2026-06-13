---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-14-ERRATA.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.701469+00:00
---

# Phase 14 Errata — PlexusAdapter + Stub

**Date**: 2026-03-30
**Phase**: 14 (PlexusAdapter + StubAdapter + PlexusService)
**Status**: Complete

---

## E1: StubPlexusAdapter — resolveIdentity does not track revocation

**Severity**: Low (stub only)
**Issue**: The stub has no `revokeIdentity()` method and `resolveIdentity()` never returns `isRevoked: true`. The PRD execution prompt mentions revocation tracking but the PRD interface does not include an `isRevoked` field in the return type.
**Impact**: None for Phase 14. Phase 15+ will add revocation via the real SDK. The stub can be extended with a `revokeIdentity(certId)` method if needed for testing governance flows.
**Resolution**: Document as known limitation. The adapter interface can be extended in Phase 16 (edges + capabilities) when revocation becomes relevant.

## E2: Monotonic childIndex does NOT survive service re-instantiation

**Severity**: Medium
**Issue**: The `nextChildIndex` Map is in-memory only. If `PlexusService` is re-instantiated (page reload, new test), the counter resets to 0. For the same email, `registerIdentity` returns the same deterministic certId, but subsequent `deriveChild` calls restart from childIndex 0.
**Impact**: In tests, this is fine — each test creates a fresh adapter. In the browser with localStorage persistence, a reloaded identity will produce the same childIndex sequence. The real Plexus SDK (Phase 15) persists this server-side.
**Mitigation**: Could serialize `nextChildIndex` to localStorage alongside identity data, but this adds complexity for minimal benefit in stub mode.

## E3: IdentityStore async queue prevents error surfacing

**Severity**: Low
**Issue**: The `addFacet` sequential queue (`this.queue = this.queue.then(...)`) swallows errors silently. If `deriveChild` fails, the Promise resolves without error and the facet is not added, but the caller (IdentityProvider) does not know.
**Mitigation**: The stub's `deriveChild` only fails on unknown parentCertId, which cannot happen in normal flow since `createIdentity` always registers the root first. For Phase 15 with real SDK, add error state to IdentityStore and surface via `useSyncExternalStore`.

## E4: hexToBytes16 truncation is intentional

**Severity**: Info
**Issue**: `hexToBytes16()` takes only the first 16 bytes of a 32-byte SHA-256 certId. The header's `ownerId` field is `Uint8Array(16)`.
**Impact**: This is a fingerprint, not a full cryptographic identity. 16 bytes (128 bits) of entropy is sufficient for collision resistance in loom-scale usage. The full certId is stored on the Identity/Facet objects and used for all PlexusService operations.

## E5: sendAuthenticated logging is safe

**Severity**: Info
**Issue**: Verified that `sendAuthenticated()` only logs payload keys (not values) when `debugLogging` is true. No sensitive data leaks through logging.

## E6: No `any` casts at adapter boundary

**Severity**: Info
**Issue**: Verified. The PlexusAdapter interface uses only `string`, `number`, `boolean`, `Record<string, string>`, and structured return types. No `any` casts in types.ts, stub.ts, or PlexusService.ts. The `querySubtree` return type uses `grandchildren?` with explicit typing.

## E7: PlexusService.subscribe cleanup verified

**Severity**: Info
**Issue**: The unsubscribe function returned by `subscribe()` correctly calls `this.listeners.delete(listener)`. Test T10 verifies that after unsubscribe, no further notifications are received.

## E8: Pre-existing build issues (not Phase 14)

**Severity**: Info (pre-existing)
**Issue**: `bun run check` and `bun run build` fail due to Buffer/Uint8Array type errors in `src/cell-engine/cellPacker.ts` and `src/cell-engine/typeHashRegistry.ts`. Phase 0 gate tests (Zig build timeout, WASM size) also fail. None of these are caused by Phase 14 changes. Zero type errors exist in `packages/loom/`.

---

## Summary

Phase 14 introduces 4 new files and modifies 5 existing files. All 20 gate tests pass. No loom TypeScript errors. No `@plexus` imports leak outside the adapter directory. The main errata items (E1-E3) are stub-mode limitations that will be resolved when the real Plexus SDK is wired in Phase 15.
