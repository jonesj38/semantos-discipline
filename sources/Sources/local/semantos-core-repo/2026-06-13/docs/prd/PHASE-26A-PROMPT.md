---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-26A-PROMPT.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.712244+00:00
---

# Phase 26A Execution Prompt — Identity Adapter Extraction

> Paste this prompt into a fresh session to execute Phase 26A.

---

## Context

You are working in the `semantos-core` repo — the TypeScript application layer and React loom for Bitcoin-native semantic objects (npm: `@semantos/core`). The kernel (cell engine, 2-PDA, linearity enforcement) is Zig/WASM in the sibling `semantos` repo; this repo holds the type system, compiler, WASM bindings, and loom UI.

Phase 26A extracts the `PlexusAdapter` interface from the loom to the protocol layer and renames it to `IdentityAdapter`. This establishes identity as a kernel-level concern (not loom-specific) and creates the first of four core adapter interfaces in `protocol-types/src/`.

Your task is to:

1. Move `PlexusAdapter` from `packages/loom/src/plexus/types.ts` → `packages/protocol-types/src/identity.ts` (rename to IdentityAdapter)
2. Move `StubPlexusAdapter` from `packages/loom/src/plexus/stub.ts` → `packages/protocol-types/src/adapters/stub-identity-adapter.ts`
3. Create a `create-identity-adapter.ts` factory function in protocol-types (following the Phase 25A pattern)
4. Replace the loom types.ts with a re-export/alias for backward compatibility
5. Update PlexusService to use the factory from protocol-types
6. Write gate tests T1–T15

After this phase, identity is a kernel-level adapter, deployable independently of the loom.

---

## CRITICAL: READ THESE FILES FIRST

Before writing a single line of code, read every file listed below. These are the real implementations you are building on top of. If you haven't read them, you will produce stubs, mocks, or code that doesn't integrate. That is not acceptable.

**Read first** (the PRDs — your requirements):
- `/Users/toddprice/projects/semantos-core/docs/prd/PHASE-26A-IDENTITY-EXTRACTION.md` — Phase 26A spec with deliverables D26A.1–D26A.5, TDD gate T1–T15, completion criteria
- `/Users/toddprice/projects/semantos-core/docs/prd/PHASE-26-KERNEL-ISOLATION-MASTER.md` — Master doc explaining adapter interfaces, deployment profiles, node object model
- `/Users/toddprice/projects/semantos-core/docs/prd/PLATFORM-ARCHITECTURE.md` — **Product context.** Three-product platform (trades, property management, dispatch envelope). Understand why identity extraction matters: cross-vertical dispatch requires capability tokens that work across vertical boundaries, which requires IdentityAdapter at kernel level not loom level.

**Read second** (the existing implementations you are extracting from):
- `/Users/toddprice/projects/semantos-core/packages/loom/src/plexus/types.ts` — Full PlexusAdapter interface, PlexusConfig, PlexusError, PlexusMode, PlexusState
- `/Users/toddprice/projects/semantos-core/packages/loom/src/plexus/stub.ts` — Full StubPlexusAdapter implementation
- `/Users/toddprice/projects/semantos-core/packages/loom/src/plexus/PlexusService.ts` — PlexusService wrapper (will update after extraction)

**Read third** (the reference patterns you must follow):
- `/Users/toddprice/projects/semantos-core/packages/protocol-types/src/storage.ts` — StorageAdapter interface pattern (Phase 25A reference)
- `/Users/toddprice/projects/semantos-core/packages/protocol-types/src/adapters/create-adapter.ts` — Factory function pattern (Phase 25A reference)
- `/Users/toddprice/projects/semantos-core/packages/protocol-types/src/adapters/memory-adapter.ts` — Stub adapter pattern reference

**Read fourth** (the integration points):
- `/Users/toddprice/projects/semantos-core/packages/shell/src/capabilities.ts` — Capability mapping (domain flags 0x00010001–0x0001000A) — referenced by identity operations
- `/Users/toddprice/projects/semantos-core/packages/loom/src/plexus/index.ts` — Existing barrel export (will update)

**Read fifth** (branching policy):
- `/Users/toddprice/projects/semantos-core/docs/BRANCHING-AND-CI-POLICY.md` — Branch as `phase-26a-identity-extraction`. Commits as `phase-26a/D26A.N: description`.

---

## ANTI-BULLSHIT RULES (NON-NEGOTIABLE)

Same as Phases 9–25. Plus Phase 26A-specific rules:

### 1. EXTRACTION, NOT DUPLICATION

Copy the interface and implementation **once**. Do not leave old copies in place. After moving to protocol-types, the loom re-exports via alias only.

### 2. INTERFACE INTEGRITY

The `IdentityAdapter` interface must be **identical** to `PlexusAdapter` — same method signatures, same return types, same parameter order. Renaming types (PlexusAdapter → IdentityAdapter, PlexusConfig → IdentityConfig, etc.) is OK. Changing behavior is not.

### 3. BACKWARD COMPATIBILITY IS MANDATORY

All existing imports of `PlexusAdapter` from loom code must continue to work. The alias in `packages/loom/src/plexus/types.ts` is the contract.

### 4. NO PROTOCOL-TYPES WORKBENCH IMPORTS

`packages/protocol-types/` must not import from `packages/loom/`. Protocol is foundation; workbench is a consumer. Never invert this dependency.

### 5. PRIMITIVE TYPES ONLY IN INTERFACE SIGNATURE

The `IdentityAdapter` interface uses only primitives: `string`, `number`, `boolean`, `Record<string, string>`. No internal types. No Plexus SDK types.

### 6. FACTORY FUNCTION FOLLOWS PHASE 25A PATTERN

The `create-identity-adapter.ts` function must match the structure and style of `create-adapter.ts`. Same docs, same error handling, same environment detection logic (adapted for identity mode).

### 7. TESTS USE REAL OPERATIONS

Tests are not mock assertions. T1–T7 verify the extracted adapter works. T8–T12 verify integration. T13–T15 verify the boundary. No `expect().toBeDefined()` tests.

### 8. STUB DETERMINISM PRESERVED

`StubIdentityAdapter` must produce the same certIds, publicKeys, and tree structure as the original `StubPlexusAdapter`. Seeds, hashes, and child index logic must be identical.

### 9. NO PLEXUS IMPORTS IN PROTOCOL-TYPES

Scan every new file in `packages/protocol-types/src/adapters/` and `packages/protocol-types/src/identity.ts` for `@plexus` imports. Zero tolerance.

### 10. RENAME IS SEMANTIC, NOT COSMETIC

PlexusAdapter → IdentityAdapter because identity is now a kernel concern. PlexusConfig → IdentityConfig. PlexusMode → IdentityMode. PlexusError → IdentityError. This naming shift signals the architectural change.

---

## PART 0: GIT HYGIENE

### 0.1 Assess

```bash
cd /Users/toddprice/projects/semantos-core
git status -u
git log --oneline -10
git branch -a
```

### 0.2 Commit or discard uncommitted work

Stage files explicitly, never `git add -A`. Discard stale files. Ignore `.claude/worktrees/`.

### 0.3 Verify prerequisites are complete

```bash
# Phase 25D files exist
ls packages/protocol-types/src/storage.ts
ls packages/protocol-types/src/adapters/
ls packages/loom/src/plexus/types.ts
ls packages/loom/src/plexus/stub.ts
ls packages/loom/src/plexus/PlexusService.ts

# Shell capability mapping exists
ls packages/shell/src/capabilities.ts
```

All files must exist and not be stubbed. If anything is missing, STOP.

### 0.4 Create Phase 26A branch

```bash
git checkout -b phase-26a-identity-extraction
```

---

## Step 1: IdentityAdapter Interface (D26A.1)

Create `/Users/toddprice/projects/semantos-core/packages/protocol-types/src/identity.ts`.

Copy the entire `PlexusAdapter` interface from `packages/loom/src/plexus/types.ts`, but rename:
- `PlexusAdapter` → `IdentityAdapter`
- `PlexusConfig` → `IdentityConfig`
- `PlexusError` → `IdentityError`
- `PlexusMode` → `IdentityMode`
- `PlexusState` → `IdentityState`

Update JSDoc comments to reflect kernel-level (not loom-specific) concerns:

```typescript
/**
 * IdentityAdapter — the kernel's gateway to identity and capability validation.
 *
 * All kernel identity and graph operations flow through this interface.
 * No Plexus types leak into the kernel. No `@plexus/*` imports outside
 * the adapter implementation files.
 *
 * Rule: All method signatures use ONLY primitive types (string, number,
 * boolean, Record<string, string>). No Plexus-internal types cross this
 * boundary.
 */
```

Include all supporting types and enums:
- `IdentityMode` = `'stub' | 'local' | 'cloud'`
- `IdentityConfig` with mode, endpoint, debugLogging
- `IdentityError` with code, message, recoverable
- `IdentityState` with identities, edges, lastOperation
- `IdentityInfo` interface for resolved identities

Do NOT import from `@plexus/*`. Do NOT import from loom. This file is pure protocol.

Verify:
```bash
grep -n "@plexus" packages/protocol-types/src/identity.ts
# Should produce zero matches
```

Commit: `phase-26a/D26A.1: IdentityAdapter interface extracted to protocol-types`

---

## Step 2: StubIdentityAdapter (D26A.2)

Create `/Users/toddprice/projects/semantos-core/packages/protocol-types/src/adapters/stub-identity-adapter.ts`.

Move the entire `StubPlexusAdapter` class from `packages/loom/src/plexus/stub.ts` and rename to `StubIdentityAdapter`.

Update imports at the top:
```typescript
import type { IdentityAdapter, IdentityConfig, IdentityError } from '../identity';
```

The implementation logic must be **identical** to the original:
- `sha256hex()`, `hexToBase64()`, `fakePEM()` helper functions copied verbatim
- `StubIdentity`, `StubEdge`, `StubRecoverySession` interfaces copied verbatim
- All methods (registerIdentity, deriveChild, resolveIdentity, etc.) logic unchanged
- Monotonic childIndex enforcement preserved exactly

Test that the adapter works:
```bash
bun test packages/__tests__/phase26a-gate.test.ts --grep "StubIdentityAdapter"
# Should verify deterministic certId generation
```

Commit: `phase-26a/D26A.2: StubIdentityAdapter moved to protocol-types with deterministic in-memory DAG`

---

## Step 3: create-identity-adapter Factory (D26A.3)

Create `/Users/toddprice/projects/semantos-core/packages/protocol-types/src/adapters/create-identity-adapter.ts`.

Follow the exact pattern of `create-adapter.ts` (Phase 25A):

```typescript
import type { IdentityAdapter, IdentityConfig, IdentityMode } from '../identity';
import { StubIdentityAdapter } from './stub-identity-adapter';

export interface CreateIdentityAdapterOptions {
  /** Use this adapter directly — bypasses environment detection. */
  adapter?: IdentityAdapter;
  /** Identity mode: 'stub' | 'local' | 'cloud'. Defaults to 'stub'. */
  mode?: IdentityMode;
  /** Endpoint for local/cloud modes. Not used by stub. */
  endpoint?: string;
  /** Enable debug logging. */
  debugLogging?: boolean;
}

export async function createIdentityAdapter(
  options?: CreateIdentityAdapterOptions,
): Promise<IdentityAdapter> {
  const config: IdentityConfig = {
    mode: options?.mode ?? 'stub',
    endpoint: options?.endpoint,
    debugLogging: options?.debugLogging ?? false,
  };

  if (options?.adapter) {
    // Explicit override
    return options.adapter;
  }

  if (config.mode === 'stub') {
    return new StubIdentityAdapter(config);
  }

  if (config.mode === 'local') {
    // Phase 26B: LocalIdentityAdapter
    throw new Error(
      '[semantos] LocalIdentityAdapter not yet implemented. See Phase 26B-LOCAL-IDENTITY.md',
    );
  }

  if (config.mode === 'cloud') {
    // Phase 26B: CloudIdentityAdapter (Plexus RaaS)
    throw new Error(
      '[semantos] CloudIdentityAdapter not yet implemented. See Phase 26B-CLOUD-IDENTITY.md',
    );
  }

  throw new Error(`Unknown identity mode: ${config.mode}`);
}
```

Commit: `phase-26a/D26A.3: create-identity-adapter factory with mode detection`

---

## Step 4: Export IdentityAdapter from protocol-types Index (D26A.3b)

Modify `/Users/toddprice/projects/semantos-core/packages/protocol-types/src/adapters/index.ts` (or create if it doesn't exist).

Add exports for identity:
```typescript
export type { IdentityAdapter, IdentityConfig, IdentityError, IdentityMode, IdentityState } from '../identity';
export { createIdentityAdapter } from './create-identity-adapter';
export { StubIdentityAdapter } from './stub-identity-adapter';
```

Also verify that `packages/protocol-types/src/index.ts` re-exports from adapters:
```typescript
export * from './adapters/index';
export * from './storage';
export * from './identity';
```

Commit: `phase-26a/D26A.3b: Export IdentityAdapter and factory from protocol-types`

---

## Step 5: PlexusAdapter Backward Compatibility (D26A.4)

Modify `/Users/toddprice/projects/semantos-core/packages/loom/src/plexus/types.ts`.

Replace the entire interface definition with:

```typescript
/**
 * BACKWARD COMPATIBILITY: PlexusAdapter is now IdentityAdapter in protocol-types.
 *
 * This file re-exports IdentityAdapter and related types as PlexusAdapter
 * for backward compatibility with existing loom code.
 *
 * New code should import directly from @semantos/protocol-types.
 */

export {
  IdentityAdapter as PlexusAdapter,
  IdentityConfig as PlexusConfig,
  IdentityError as PlexusError,
  IdentityMode as PlexusMode,
  IdentityState as PlexusState,
} from '@semantos/protocol-types';
```

Test backward compatibility:
```bash
# This import should still work
node -e "import('@semantos/loom').then(m => console.log(typeof m.PlexusAdapter))"
```

Verify no old definitions remain in the file (no duplicate interfaces).

Commit: `phase-26a/D26A.4: PlexusAdapter aliased to IdentityAdapter for backward compatibility`

---

## Step 6: Update PlexusService (D26A.5a)

Modify `/Users/toddprice/projects/semantos-core/packages/loom/src/plexus/PlexusService.ts`.

Update imports to use the protocol-types factory:

**OLD:**
```typescript
import { createAdapter } from './config';
```

**NEW:**
```typescript
import { createIdentityAdapter } from '@semantos/protocol-types';
import type { IdentityConfig } from '@semantos/protocol-types';
```

Update the constructor:
```typescript
export class PlexusService {
  private adapter: IdentityAdapter;
  // ... rest of class

  constructor(config: IdentityConfig) {
    this.adapter = await createIdentityAdapter({ mode: config.mode, endpoint: config.endpoint });
  }
}
```

**Note**: If `PlexusService` is currently synchronous and createIdentityAdapter is async, you may need to defer adapter creation to an async init method. Check the current PlexusService implementation for the pattern.

Test:
```bash
bun test packages/__tests__/phase26a-gate.test.ts --grep "PlexusService"
```

Commit: `phase-26a/D26A.5a: PlexusService uses createIdentityAdapter from protocol-types`

---

## Step 7: Remove Old Stub (D26A.5b)

Modify `/Users/toddprice/projects/semantos-core/packages/loom/src/plexus/stub.ts`.

The file should now either:
- Be deleted entirely (preferred), OR
- Contain only a re-export from protocol-types for backward compatibility:

```typescript
/**
 * BACKWARD COMPATIBILITY: StubPlexusAdapter moved to protocol-types.
 */
export { StubIdentityAdapter as StubPlexusAdapter } from '@semantos/protocol-types';
```

If deleting, verify no other loom files import directly from stub.ts:
```bash
grep -r "from './stub'" packages/loom/
grep -r "from './plexus/stub'" packages/loom/
# Should return zero matches (or only index.ts re-exports)
```

Commit: `phase-26a/D26A.5b: Remove or re-export old StubPlexusAdapter`

---

## Step 8: Update Loom Plexus Index (D26A.5c)

Modify `/Users/toddprice/projects/semantos-core/packages/loom/src/plexus/index.ts`.

Ensure it re-exports from the new locations:

```typescript
// Re-export from protocol-types for loom consumers
export type {
  PlexusAdapter,
  PlexusConfig,
  PlexusError,
  PlexusMode,
  PlexusState,
} from './types';

export { PlexusService } from './PlexusService';
```

Verify no broken imports in loom:
```bash
bun check
# Should produce zero errors related to plexus imports
```

Commit: `phase-26a/D26A.5c: Update loom plexus index with new re-exports`

---

## Step 9: Gate Tests (T1–T15)

Create `/Users/toddprice/projects/semantos-core/packages/__tests__/phase26a-gate.test.ts`.

### T1–T7: Unit Tests

```typescript
import { describe, it, expect } from 'bun:test';
import { IdentityAdapter } from '@semantos/protocol-types';
import { StubIdentityAdapter } from '@semantos/protocol-types';
import { createIdentityAdapter } from '@semantos/protocol-types';

describe('IdentityAdapter interface (D26A.1)', () => {
  it('T1: IdentityAdapter interface exists in protocol-types', () => {
    // Verify the type is exported
    expect(typeof IdentityAdapter).not.toBe('undefined');
  });

  it('T2: IdentityAdapter has all 9 required methods', async () => {
    const adapter = new StubIdentityAdapter({ mode: 'stub' });
    expect(typeof adapter.registerIdentity).toBe('function');
    expect(typeof adapter.deriveChild).toBe('function');
    expect(typeof adapter.resolveIdentity).toBe('function');
    expect(typeof adapter.createEdge).toBe('function');
    expect(typeof adapter.querySubtree).toBe('function');
    expect(typeof adapter.presentCapability).toBe('function');
    expect(typeof adapter.initiateRecovery).toBe('function');
    expect(typeof adapter.submitChallengeAnswers).toBe('function');
    expect(typeof adapter.sendAuthenticated).toBe('function');
  });

  it('T3: StubIdentityAdapter implements IdentityAdapter fully', async () => {
    const adapter = new StubIdentityAdapter({ mode: 'stub' });
    const result = await adapter.registerIdentity('test@example.com');
    expect(result).toHaveProperty('certId');
    expect(result).toHaveProperty('publicKey');
    expect(result.certId).toMatch(/^cert:/);
  });

  it('T4: create-identity-adapter factory returns StubIdentityAdapter by default', async () => {
    const adapter = await createIdentityAdapter();
    expect(adapter).toBeInstanceOf(StubIdentityAdapter);
  });

  it('T5: StubIdentityAdapter produces deterministic certId + publicKey', async () => {
    const adapter1 = new StubIdentityAdapter({ mode: 'stub' });
    const adapter2 = new StubIdentityAdapter({ mode: 'stub' });

    const result1 = await adapter1.registerIdentity('alice@example.com');
    const result2 = await adapter2.registerIdentity('alice@example.com');

    expect(result1.certId).toBe(result2.certId);
    expect(result1.publicKey).toBe(result2.publicKey);
  });

  it('T6: Monotonic childIndex enforced in StubIdentityAdapter', async () => {
    const adapter = new StubIdentityAdapter({ mode: 'stub' });
    const root = await adapter.registerIdentity('root@example.com');

    const child1 = await adapter.deriveChild(root.certId, 'resource1', 0x00010002);
    const child2 = await adapter.deriveChild(root.certId, 'resource2', 0x00010002);

    expect(child1.childIndex).toBe(0);
    expect(child2.childIndex).toBe(1);
  });

  it('T7: PlexusAdapter alias works in loom', async () => {
    // Import from old location
    const { PlexusAdapter } = await import('@semantos/loom');
    expect(typeof PlexusAdapter).not.toBe('undefined');
  });
});
```

### T8–T12: Integration Tests

```typescript
describe('IdentityAdapter in protocol-types (D26A.1–D26A.3)', () => {
  it('T8: PlexusService still works after extraction', async () => {
    const { PlexusService } = await import('@semantos/loom');
    const service = new PlexusService({ mode: 'stub' });
    const result = await service.registerIdentity('test@example.com');
    expect(result).toHaveProperty('certId');
    expect(result.certId).toMatch(/^cert:/);
  });

  it('T9: Subtree query returns correct tree structure post-extraction', async () => {
    const adapter = new StubIdentityAdapter({ mode: 'stub' });
    const root = await adapter.registerIdentity('root@example.com');

    const child1 = await adapter.deriveChild(root.certId, 'res1', 0x00010002);
    const child2 = await adapter.deriveChild(root.certId, 'res2', 0x00010002);
    const grandchild = await adapter.deriveChild(child1.certId, 'res1.1', 0x00010002);

    const tree = await adapter.querySubtree(root.certId, 2);
    expect(tree.root).toBe(root.certId);
    expect(tree.children.length).toBe(2);
    expect(tree.children[0].grandchildren?.length || 0).toBeGreaterThan(0);
  });

  it('T10: Edge creation works in extracted adapter', async () => {
    const adapter = new StubIdentityAdapter({ mode: 'stub' });
    const alice = await adapter.registerIdentity('alice@example.com');
    const bob = await adapter.registerIdentity('bob@example.com');

    const edge = await adapter.createEdge(alice.certId, bob.certId);
    expect(edge).toHaveProperty('edgeId');
    expect(edge).toHaveProperty('sharedSecret');
    expect(edge.edgeId).toMatch(/^edge:/);
  });

  it('T11: Backward compatibility — PlexusAdapter from loom resolves correctly', async () => {
    const { PlexusAdapter } = await import('@semantos/loom');
    const Adapter = PlexusAdapter as any; // For testing purposes
    expect(Adapter.name === 'IdentityAdapter' || typeof Adapter === 'object').toBeTruthy();
  });

  it('T12: Protocol-types exports are clean (no circular imports)', async () => {
    const protocol = await import('@semantos/protocol-types');
    expect(protocol).toHaveProperty('IdentityAdapter');
    expect(protocol).toHaveProperty('createIdentityAdapter');
    expect(protocol).toHaveProperty('StubIdentityAdapter');
  });
});
```

### T13–T15: Anti-Lock Tests

```typescript
describe('Anti-lock boundary for Phase 26A', () => {
  it('T13: No @plexus imports in protocol-types', async () => {
    // Scan protocol-types directory for @plexus imports
    const fs = await import('fs/promises');
    const path = await import('path');

    const protocolDir = path.resolve('/Users/toddprice/projects/semantos-core/packages/protocol-types/src');
    const scanDir = async (dir: string) => {
      const files = await fs.readdir(dir, { recursive: true, withFileTypes: true });
      for (const file of files) {
        if (file.isFile() && file.name.endsWith('.ts')) {
          const content = await fs.readFile(path.join(dir, file.parentPath || '', file.name), 'utf8');
          if (content.includes('@plexus')) {
            throw new Error(`Found @plexus import in ${file.name}`);
          }
        }
      }
    };

    await scanDir(protocolDir);
    expect(true).toBe(true); // If we get here, no @plexus found
  });

  it('T14: IdentityAdapter interface contains only primitive types', async () => {
    const fs = await import('fs/promises');
    const content = await fs.readFile(
      '/Users/toddprice/projects/semantos-core/packages/protocol-types/src/identity.ts',
      'utf8',
    );

    // Check for Plexus type references
    const forbiddenPatterns = /PlexusNode|PlexusCert|BRC52|@plexus/gi;
    const matches = content.match(forbiddenPatterns);
    expect(matches).toBeNull();
  });

  it('T15: StubIdentityAdapter moved completely (not duplicated)', async () => {
    // Old file should not exist or should only re-export
    const fs = await import('fs/promises');
    try {
      const oldContent = await fs.readFile(
        '/Users/toddprice/projects/semantos-core/packages/loom/src/plexus/stub.ts',
        'utf8',
      );

      // If file exists, it should only contain re-exports or comments
      const hasClass = oldContent.includes('class StubPlexusAdapter implements');
      expect(hasClass).toBe(false);
    } catch (e: any) {
      // File doesn't exist (expected) or can't be read
      if (e.code !== 'ENOENT') throw e;
    }
  });
});
```

Run all tests:
```bash
bun test packages/__tests__/phase26a-gate.test.ts
```

Commit: `phase-26a/T1-T15: full gate test suite — unit, integration, anti-lock`

---

## Step 10: Type Check and Build

Verify zero TypeScript errors:
```bash
bun check
```

Verify build succeeds:
```bash
bun run build
```

If there are errors, fix them. Do NOT ignore type errors.

Commit (if changes needed): `phase-26a/fix: [description of fix]`

---

## Step 11: Errata Sprint

After all tests pass, review for mutations not caught by tests:

1. Verify `resolveIdentity()` on a revoked node behavior (not changed, extraction only)
2. Verify monotonic childIndex survives adapter re-instantiation (should, in-memory state)
3. Verify `createIdentityAdapter()` factory handles all modes correctly (stub only in 26A)
4. Verify no `any` casts mask type errors at the adapter boundary
5. Verify `sendAuthenticated()` logging doesn't leak sensitive data (unchanged from original)

Write errata doc as `/Users/toddprice/projects/semantos-core/docs/prd/PHASE-26A-ERRATA.md` (optional but recommended).

---

## Completion Criteria

- [ ] `packages/protocol-types/src/identity.ts` exists with full `IdentityAdapter` interface
- [ ] `packages/protocol-types/src/adapters/stub-identity-adapter.ts` exists with full `StubIdentityAdapter`
- [ ] `packages/protocol-types/src/adapters/create-identity-adapter.ts` factory exists
- [ ] `packages/protocol-types/src/adapters/index.ts` re-exports identity types and factory
- [ ] `packages/loom/src/plexus/types.ts` re-exports as PlexusAdapter alias
- [ ] `packages/loom/src/plexus/PlexusService.ts` imports from protocol-types
- [ ] Tests T1–T15 all pass
- [ ] `bun check` produces zero TypeScript errors
- [ ] `bun run build` succeeds
- [ ] No @plexus imports in protocol-types/
- [ ] All commits follow `phase-26a/D26A.N:` naming convention
- [ ] Branch is `phase-26a-identity-extraction`

---

## Next Phase

Phase 26B: Local and Cloud Identity Adapters. Implements LocalIdentityAdapter (on-prem cert chain, no network) and CloudIdentityAdapter (Plexus RaaS). The IdentityAdapter interface remains unchanged — only new implementations.

---

## Notes on Testing

- T1–T7 verify the extraction was done correctly (interface exists, methods work)
- T8–T12 verify integration (PlexusService still works, backward compat)
- T13–T15 verify the boundary (no plexus imports in protocol, only primitives, no duplication)

If any test fails, fix the underlying issue, not the test. Tests define the contract.
