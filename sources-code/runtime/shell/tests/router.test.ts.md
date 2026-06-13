---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/shell/tests/router.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.361312+00:00
---

# runtime/shell/tests/router.test.ts

```ts
/**
 * Router tests — validates routing logic via route-helpers and capability checks.
 *
 * Note: The full route() function cannot be unit-tested in isolation because
 * router.ts imports from sibling packages (games, loom) that require
 * the full monorepo dependency chain. This is the import hygiene issue
 * identified in Phase 3 of the hardening plan.
 *
 * These tests cover the extracted route helpers and capability logic directly,
 * which is where the routing bugs and boilerplate lived.
 */

import { describe, test, expect } from 'bun:test';
import { requireObject, requireType, isShellError } from '../src/route-helpers';
import type { ShellError } from '../src/route-helpers';
import { getRequiredCapability, getCapabilityName, MUTATION_VERBS } from '../src/capabilities';

// ── Minimal context factory ──────────────────────────────────

function makeObject(id: string, overrides?: Record<string, unknown>) {
  return {
    id,
    typeDefinition: {
      name: 'Job',
      category: 'trades',
      typeHash: '0xabc',
      linearity: 'LINEAR',
      fields: [
        { name: 'urgency', type: 'string' },
        { name: 'status', type: 'string' },
      ],
    },
    header: {
      linearity: 1,
      version: 1,
      flags: 0,
      refCount: 0,
      typeHash: new Uint8Array(32),
      ownerId: new Uint8Array(32),
      timestamp: BigInt(Date.now()),
      phase: 0,
    },
    visibility: 'draft',
    payload: {},
    patches: [],
    createdAt: Date.now(),
    updatedAt: Date.now(),
    ...(overrides ?? {}),
  };
}

function makeCtx(objects?: Map<string, any>, objectTypes?: any[]) {
  return {
    store: {
      getState: () => ({
        objects: objects ?? new Map(),
      }),
    },
    config: {
      getConfig: () =>
        objectTypes
          ? {
              id: 'core',
              name: 'Core',
              objectTypes,
              capabilities: [],
              scripts: [],
              commercePhases: [],
              flows: [],
            }
          : null,
    },
    identity: {
      getActiveHat: () => ({
        id: 'test-facet',
        name: 'test',
        displayName: 'Test Facet',
        capabilities: [2, 3, 4, 5, 6, 7, 8, 9],
        derivationPath: 'm/0',
        certId: 'cert-123',
      }),
    },
    plexus: {
      presentCapability: async () => ({ valid: true }),
    },
    activeHatId: 'test-facet',
    activeHatCertId: 'cert-123',
  } as any;
}

// ── Object lookup via requireObject ──────────────────────────

describe('router — object lookup', () => {
  test('returns structured error for missing object ID', () => {
    const ctx = makeCtx();
    const result = requireObject(ctx, undefined, 'inspect');
    expect(isShellError(result)).toBe(true);
    expect((result as ShellError).code).toBe('MISSING_OBJECT_ID');
    expect((result as ShellError).error).toContain("'inspect'");
  });

  test('returns structured error for nonexistent object', () => {
    const ctx = makeCtx(new Map());
    const result = requireObject(ctx, 'nonexistent', 'trace');
    expect(isShellError(result)).toBe(true);
    expect((result as ShellError).code).toBe('OBJECT_NOT_FOUND');
    expect((result as ShellError).details?.objectId).toBe('nonexistent');
  });

  test('returns object when it exists', () => {
    const obj = makeObject('obj-1');
    const objects = new Map([['obj-1', obj]]);
    const ctx = makeCtx(objects);
    const result = requireObject(ctx, 'obj-1', 'inspect');
    expect(isShellError(result)).toBe(false);
    expect((result as any).id).toBe('obj-1');
  });

  test('error per verb: patch', () => {
    const ctx = makeCtx();
    const result = requireObject(ctx, undefined, 'patch') as ShellError;
    expect(result.error).toContain("'patch'");
  });

  test('error per verb: transfer', () => {
    const ctx = makeCtx();
    const result = requireObject(ctx, undefined, 'transfer') as ShellError;
    expect(result.error).toContain("'transfer'");
  });
});

// ── Type lookup via requireType ──────────────────────────────

describe('router — type lookup', () => {
  const types = [
    { name: 'Job', category: 'trades', fields: [] },
    { name: 'Quote', category: 'trades', fields: [] },
    { name: 'Certificate', fields: [] }, // no category
  ];

  test('returns structured error for missing type path', () => {
    const ctx = makeCtx(new Map(), types);
    const result = requireType(ctx, undefined, 'new');
    expect(isShellError(result)).toBe(true);
    expect((result as ShellError).code).toBe('MISSING_TYPE_PATH');
  });

  test('returns NO_CONFIG when no config loaded', () => {
    const ctx = makeCtx(); // no objectTypes → getConfig returns null
    const result = requireType(ctx, 'Job', 'new');
    expect(isShellError(result)).toBe(true);
    expect((result as ShellError).code).toBe('NO_CONFIG');
  });

  test('returns UNKNOWN_TYPE for nonexistent type', () => {
    const ctx = makeCtx(new Map(), types);
    const result = requireType(ctx, 'Nonexistent', 'new');
    expect(isShellError(result)).toBe(true);
    expect((result as ShellError).code).toBe('UNKNOWN_TYPE');
    expect((result as ShellError).details?.available).toContain('Job');
  });

  test('resolves by short name', () => {
    const ctx = makeCtx(new Map(), types);
    const result = requireType(ctx, 'Job', 'new');
    expect(isShellError(result)).toBe(false);
    expect((result as any).name).toBe('Job');
  });

  test('resolves by full category.name', () => {
    const ctx = makeCtx(new Map(), types);
    const result = requireType(ctx, 'trades.Job', 'new');
    expect(isShellError(result)).toBe(false);
    expect((result as any).name).toBe('Job');
  });

  test('case-insensitive matching', () => {
    const ctx = makeCtx(new Map(), types);
    expect(isShellError(requireType(ctx, 'job', 'new'))).toBe(false);
    expect(isShellError(requireType(ctx, 'TRADES.JOB', 'new'))).toBe(false);
  });

  test('resolves type without category by name only', () => {
    const ctx = makeCtx(new Map(), types);
    const result = requireType(ctx, 'Certificate', 'new');
    expect(isShellError(result)).toBe(false);
    expect((result as any).name).toBe('Certificate');
  });
});

// ── Capability system ────────────────────────────────────────

describe('router — capability system', () => {
  test('mutation verbs have required capabilities', () => {
    for (const verb of MUTATION_VERBS) {
      const cap = getRequiredCapability(verb);
      expect(cap).not.toBeNull();
      expect(typeof cap).toBe('number');
    }
  });

  test('read verbs return null capability', () => {
    expect(getRequiredCapability('inspect')).toBeNull();
    expect(getRequiredCapability('list')).toBeNull();
    expect(getRequiredCapability('trace')).toBeNull();
    expect(getRequiredCapability('verify')).toBeNull();
    expect(getRequiredCapability('whoami')).toBeNull();
  });

  test('capability names are human-readable', () => {
    const name = getCapabilityName(0x00010002);
    expect(typeof name).toBe('string');
    expect(name.length).toBeGreaterThan(0);
  });

  test('MUTATION_VERBS contains expected verbs', () => {
    const expected = ['new', 'patch', 'publish', 'revoke', 'transfer', 'stake', 'vote', 'dispute'];
    for (const v of expected) {
      expect(MUTATION_VERBS.has(v)).toBe(true);
    }
  });

  test('MUTATION_VERBS does not contain read verbs', () => {
    expect(MUTATION_VERBS.has('inspect')).toBe(false);
    expect(MUTATION_VERBS.has('list')).toBe(false);
    expect(MUTATION_VERBS.has('trace')).toBe(false);
  });
});

// ── Dry-run simulation ───────────────────────────────────────
// Note: Full dry-run testing requires route(), which depends on the full
// dependency chain. These tests verify the building blocks that dry-run uses.

describe('router — dry-run building blocks', () => {
  test('capability check returns structured result for mutation verb', () => {
    const cap = getRequiredCapability('patch');
    expect(cap).toBe(0x00010003);
    expect(getCapabilityName(cap!)).toBeDefined();
  });

  test('capability check returns null for read verb', () => {
    const cap = getRequiredCapability('inspect');
    expect(cap).toBeNull();
  });
});

```
