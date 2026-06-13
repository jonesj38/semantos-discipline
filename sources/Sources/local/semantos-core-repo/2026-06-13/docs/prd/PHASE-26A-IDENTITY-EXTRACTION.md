---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-26A-IDENTITY-EXTRACTION.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.672703+00:00
---

# Phase 26A — Identity Adapter Extraction

**Version**: 1.0
**Date**: April 2026
**Status**: Ready for implementation
**Duration**: 2–3 days
**Prerequisites**: Phase 25D complete (BsvOverlayAdapter working)
**Master document**: `PHASE-26-KERNEL-ISOLATION-MASTER.md`
**Branch**: `phase-26a-identity-extraction`

---

## Context

The `PlexusAdapter` interface currently lives in `packages/loom/src/plexus/types.ts` — a loom-owned file. However, **identity is a kernel-level concern**, not a loom concern. The kernel needs to validate capabilities, enforce domain flags, and manage cert chains independently of the React UI.

Phase 26A extracts `PlexusAdapter` from the loom to the protocol layer, renames it to `IdentityAdapter`, and establishes it as the third core adapter interface (alongside `StorageAdapter` from Phase 25 and `AnchorAdapter` from Phase 26C).

This extraction accomplishes three goals:

1. **Kernel isolation**: Identity operations are now kernel-compatible, not loom-specific
2. **Adapter composition**: The four adapter interfaces (Storage, Identity, Anchor, Network) live together in `protocol-types/src/`
3. **Backward compatibility**: PlexusAdapter remains as an alias in loom code, so existing code does not break

---

## Source Files / References

| Alias | Path | What to extract |
|-------|------|-----------------|
| `SRC:TYPES` | `packages/loom/src/plexus/types.ts` | PlexusAdapter interface, PlexusConfig, PlexusError, PlexusState, PlexusMode |
| `SRC:STUB` | `packages/loom/src/plexus/stub.ts` | StubPlexusAdapter full implementation |
| `PROTO:STORAGE` | `packages/protocol-types/src/storage.ts` | Reference pattern for adapter interface structure |
| `PROTO:ADAPTERS` | `packages/protocol-types/src/adapters/` | Reference directory structure and create-*-adapter.ts pattern |
| `PROTO:CREATE` | `packages/protocol-types/src/adapters/create-adapter.ts` | Reference factory function pattern |
| `SVC:SHELL` | `packages/shell/src/capabilities.ts` | Capability mapping — domain flags 0x00010001–0x0001000A |
| `POLICY:BRANCH` | `docs/BRANCHING-AND-CI-POLICY.md` | Commit naming convention, branch rules |

---

## Deliverables

### D26A.1 — IdentityAdapter Interface

**New file**: `packages/protocol-types/src/identity.ts`

Move and rename the `PlexusAdapter` interface to `IdentityAdapter`. Update JSDoc to reflect kernel-level usage (not loom-specific).

Interface methods (unchanged from PlexusAdapter):
- `registerIdentity(email: string)`
- `deriveChild(parentCertId, resourceId, domainFlag)`
- `resolveIdentity(certId)`
- `createEdge(initiatorCertId, responderCertId)`
- `querySubtree(rootCertId, depth)`
- `presentCapability(certId, capabilityId)`
- `initiateRecovery(email)`
- `submitChallengeAnswers(sessionId, answers)`
- `sendAuthenticated(senderCertId, receiverCertId, payload)`

Also include supporting types:
- `IdentityMode` type: `'stub' | 'local' | 'cloud'` (rename from PlexusMode)
- `IdentityConfig` interface (rename from PlexusConfig)
- `IdentityError` interface (rename from PlexusError)
- `IdentityInfo` interface for resolved identities
- `CertTree` interface for subtree queries

**No @plexus imports in this file.** The interface is pure protocol types.

Commit: `phase-26a/D26A.1: IdentityAdapter interface extracted to protocol-types/src/identity.ts`

---

### D26A.2 — StubIdentityAdapter

**New file**: `packages/protocol-types/src/adapters/stub-identity-adapter.ts`

Move the `StubPlexusAdapter` implementation to the protocol layer and rename to `StubIdentityAdapter`. Full deterministic implementation, no changes to behavior.

Commit: `phase-26a/D26A.2: StubIdentityAdapter moved to protocol-types with deterministic in-memory DAG`

---

### D26A.3 — create-identity-adapter Factory

**New file**: `packages/protocol-types/src/adapters/create-identity-adapter.ts`

Create a factory function following the pattern of `create-adapter.ts` (Phase 25A):

```typescript
export interface CreateIdentityAdapterOptions {
  adapter?: IdentityAdapter;
  mode?: IdentityMode;
  endpoint?: string;
  debugLogging?: boolean;
}

export async function createIdentityAdapter(
  options?: CreateIdentityAdapterOptions
): Promise<IdentityAdapter> {
  // Return StubIdentityAdapter if mode==='stub' or no mode specified
  // Return CloudIdentityAdapter if mode==='cloud' (Phase 26B)
  // Return LocalIdentityAdapter if mode==='local' (Phase 26B)
}
```

For Phase 26A, only the stub path is implemented. Cloud and local paths raise "not yet implemented" errors with helpful messages pointing to Phase 26B.

Commit: `phase-26a/D26A.3: create-identity-adapter factory with environment detection`

---

### D26A.4 — PlexusAdapter Backward Compatibility Alias

**Modified file**: `packages/loom/src/plexus/types.ts`

Replace the full interface definition with:

```typescript
// Backward compatibility: PlexusAdapter is now IdentityAdapter in protocol-types
export { IdentityAdapter as PlexusAdapter } from '@semantos/protocol-types';
export type { IdentityConfig as PlexusConfig } from '@semantos/protocol-types';
export type { IdentityError as PlexusError } from '@semantos/protocol-types';
export type { IdentityMode as PlexusMode } from '@semantos/protocol-types';
```

This ensures existing loom code importing `PlexusAdapter` continues to work without modification.

Commit: `phase-26a/D26A.4: PlexusAdapter aliased to IdentityAdapter for backward compatibility`

---

### D26A.5 — Update Import Paths

**Modified files**: All loom and shell files that import from PlexusAdapter

Search for all imports of `PlexusAdapter`, `PlexusConfig`, `PlexusError`, etc. from `packages/loom/src/plexus/types.ts`. No changes needed — they continue to work via the alias. However, update PlexusService and stub imports:

- `packages/loom/src/plexus/PlexusService.ts`: Update imports to use `createIdentityAdapter` from protocol-types
- `packages/loom/src/plexus/stub.ts`: Import `StubIdentityAdapter` from protocol-types instead of local implementation
- `packages/loom/src/plexus/index.ts`: Re-export from protocol-types if needed

Verify no `@plexus/*` imports are added in the process.

Commit: `phase-26a/D26A.5: Update PlexusService and adapter registration to use create-identity-adapter`

---

## TDD Gate

Create `packages/__tests__/phase26a-gate.test.ts`.

### Unit Tests (T1–T7)

```typescript
describe("IdentityAdapter interface", () => {
  // T1: IdentityAdapter interface exists in protocol-types
  //   → import { IdentityAdapter } from '@semantos/protocol-types'
  // T2: IdentityAdapter has all 9 required methods
  //   → registerIdentity, deriveChild, resolveIdentity, createEdge, querySubtree,
  //     presentCapability, initiateRecovery, submitChallengeAnswers, sendAuthenticated
  // T3: StubIdentityAdapter implements IdentityAdapter fully
  //   → All methods execute (no 'not implemented' errors)
  // T4: create-identity-adapter factory returns StubIdentityAdapter by default
  //   → const adapter = await createIdentityAdapter(); should return StubIdentityAdapter instance
  // T5: StubIdentityAdapter behavior matches former StubPlexusAdapter
  //   → registerIdentity produces deterministic certId + publicKey
  // T6: Monotonic childIndex enforced in StubIdentityAdapter
  //   → Derive 2 children from same parent, indices are 0, 1 (never reuse)
  // T7: PlexusAdapter alias works in loom
  //   → import { PlexusAdapter } from '@semantos/loom/src/plexus/types' resolves to IdentityAdapter
});
```

### Integration Tests (T8–T12)

```typescript
describe("IdentityAdapter in protocol-types", () => {
  // T8: PlexusService still works after extraction
  //   → New PlexusService with createIdentityAdapter() performs registerIdentity
  // T9: Subtree query returns correct tree structure post-extraction
  //   → Register root, derive 2 children, deriveChild from one child, querySubtree depth=2
  // T10: Edge creation works in extracted adapter
  //   → createEdge between two registered identities returns edgeId + sharedSecret
  // T11: Backward compatibility tests
  //   → Old imports (PlexusAdapter from loom) still resolve correctly
  // T12: Protocol-types exports are clean
  //   → No circular imports, no loom dependencies in protocol-types
});
```

### Anti-Lock Tests (T13–T15)

```typescript
describe("Anti-lock boundary for Phase 26A", () => {
  // T13: No @plexus imports in protocol-types
  //   → Scan packages/protocol-types/ for @plexus imports
  // T14: Protocol-types/src/identity.ts contains only primitive types
  //   → No PlexusNode, PlexusCert, or @plexus/* types in interface signature
  // T15: StubIdentityAdapter moved completely (not duplicated)
  //   → Verify packages/loom/src/plexus/stub.ts is removed or imports from protocol-types
});
```

Commit: `phase-26a/T1-T15: full gate test suite — unit, integration, anti-lock`

---

## Phase Completion Criteria

- [ ] `packages/protocol-types/src/identity.ts` exists with full `IdentityAdapter` interface
- [ ] `packages/protocol-types/src/adapters/stub-identity-adapter.ts` exists with full `StubIdentityAdapter` implementation
- [ ] `packages/protocol-types/src/adapters/create-identity-adapter.ts` factory exists and returns stub by default
- [ ] `packages/protocol-types/src/adapters/index.ts` exports IdentityAdapter and factory
- [ ] `packages/loom/src/plexus/types.ts` re-exports as PlexusAdapter alias
- [ ] `packages/loom/src/plexus/PlexusService.ts` imports from protocol-types
- [ ] Tests T1–T15 all pass
- [ ] `bun run check` passes (zero TypeScript errors)
- [ ] `bun run build` succeeds
- [ ] No @plexus imports in protocol-types/
- [ ] All commits follow `phase-26a/D26A.N:` naming convention
- [ ] Branch is `phase-26a-identity-extraction`

---

## What NOT to Do

- Do NOT leave duplicate implementations of StubPlexusAdapter
- Do NOT add loom imports to protocol-types
- Do NOT break existing loom imports via PlexusAdapter alias
- Do NOT implement CloudIdentityAdapter or LocalIdentityAdapter in Phase 26A (defer to 26B)
- Do NOT modify the PlexusService behavior — extraction only, behavior unchanged

---

## Next Phase

Phase 26B implements local and cloud identity adapters, enabling the kernel to work offline (LocalIdentityAdapter) and in production (CloudIdentityAdapter via Plexus RaaS). The IdentityAdapter interface created in 26A remains unchanged.

---

## Notes

This extraction is the first of four in Phase 26. Phase 26C extracts AnchorAdapter, 26D extracts NetworkAdapter. All four adapters follow the same pattern: interface in protocol-types, factory function, stub + production implementations, backward compatibility in old locations if needed.
