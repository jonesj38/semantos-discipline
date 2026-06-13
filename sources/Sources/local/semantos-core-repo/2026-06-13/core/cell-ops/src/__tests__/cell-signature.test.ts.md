---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-ops/src/__tests__/cell-signature.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.832074+00:00
---

# core/cell-ops/src/__tests__/cell-signature.test.ts

```ts
/**
 * RM-096 — typed cell signatures.
 *
 * Pins three things:
 *   - C1: `defineCell` returns a typed CellDef with the declared pre/post.
 *   - C2: `compose` works for matching pre/post pairs.
 *   - C3: `@ts-expect-error` confirms a mismatched composition is a
 *         compile-time error.
 *   - C4: `OPCODE_SIGNATURES` table exposes the kernel opcode shapes.
 *   - C5: `composeAll` builds a chain of length >= 2.
 *
 * Tests run at runtime; the negative test is a type-only assertion via
 * `@ts-expect-error` — if `compose` silently accepts the bad call, the
 * `@ts-expect-error` becomes "unused" and the compiler complains.
 */
import { describe, expect, test } from 'bun:test';
import {
  defineCell,
  compose,
  composeAll,
  signatureOf,
  OPCODE_SIGNATURES,
  type StackShape,
} from '../cell-signature.js';

// ── Tiny re-usable cells ─────────────────────────────────────────────

const pushCellId = defineCell({
  name: 'pushCellId',
  pre: [] as const,
  post: ['cell-id'] as const,
  body: { op: 'OP_PUSH', value: 'cell-id-placeholder' },
});

const checkCapability = defineCell({
  name: 'checkCapability',
  pre: ['capability'] as const,
  post: ['bool'] as const,
  body: { op: 'OP_CHECKCAPABILITY' },
});

const verifyBool = defineCell({
  name: 'verifyBool',
  pre: ['bool'] as const,
  post: [] as const,
  body: { op: 'OP_VERIFY' },
});

const pushCapability = defineCell({
  name: 'pushCapability',
  pre: [] as const,
  post: ['capability'] as const,
  body: { op: 'OP_PUSH', value: 'capability-placeholder' },
});

// ── Tests ────────────────────────────────────────────────────────────

describe('defineCell (RM-096)', () => {
  test('C1 returns the declared pre/post and name', () => {
    expect(checkCapability.name).toBe('checkCapability');
    expect(checkCapability.pre).toEqual(['capability']);
    expect(checkCapability.post).toEqual(['bool']);
  });
});

describe('compose (RM-096)', () => {
  test('C2 chains a matching pair', () => {
    const checked = compose(checkCapability, verifyBool);
    expect(checked.pre).toEqual(['capability']);
    expect(checked.post).toEqual([]);
    expect(checked.name).toBe('checkCapability >> verifyBool');
  });

  test('C2a longer chain via composeAll', () => {
    const chain = composeAll([pushCapability, checkCapability, verifyBool]);
    expect(chain.pre).toEqual([]);
    expect(chain.post).toEqual([]);
  });

  test('C3 mismatched composition is a compile-time error', () => {
    // pushCellId.post = ['cell-id']
    // checkCapability.pre = ['capability']
    // → composition is invalid; @ts-expect-error must fire.
    // @ts-expect-error: 'cell-id' is not assignable to 'capability'
    const _bad = compose(pushCellId, checkCapability);
    // Runtime assertion — keep the symbol "used" so eslint stays quiet;
    // the meaningful assertion is the @ts-expect-error above.
    expect(_bad.name).toBe('pushCellId >> checkCapability');
  });
});

describe('OPCODE_SIGNATURES (RM-096)', () => {
  test('C4 exposes the kernel opcode shapes', () => {
    expect(OPCODE_SIGNATURES.OP_CHECKCAPABILITY.pre).toEqual(['capability']);
    expect(OPCODE_SIGNATURES.OP_CHECKCAPABILITY.post).toEqual(['bool']);
    expect(OPCODE_SIGNATURES.OP_EQUAL.pre).toEqual(['bytes', 'bytes']);
    expect(OPCODE_SIGNATURES.OP_EQUAL.post).toEqual(['bool']);
  });

  test('C4a signatureOf retrieves by opcode name', () => {
    const sig = signatureOf('OP_VERIFY');
    expect(sig.pre).toEqual(['bool']);
    expect(sig.post).toEqual([]);
  });
});

describe('composeAll error paths', () => {
  test('C5 empty chain throws', () => {
    expect(() => composeAll([] as unknown as never)).toThrow(/at least one cell/);
  });
});

// ── Type-only sanity (never runs) ───────────────────────────────────

// Compile-time sanity: a single cell's pre/post type-narrows through
// defineCell. The function below is never called; the inference is
// the test.
function _typeNarrowing(): void {
  const c = defineCell({
    name: 'narrow',
    pre: ['i64'] as const,
    post: ['bool'] as const,
    body: null,
  });
  const _pre: readonly ['i64'] = c.pre;
  const _post: readonly ['bool'] = c.post;
  void _pre;
  void _post;
}
void _typeNarrowing;

```
