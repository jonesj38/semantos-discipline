---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/services/src/services/loom/__tests__/visibility-rules.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.118027+00:00
---

# runtime/services/src/services/loom/__tests__/visibility-rules.test.ts

```ts
/**
 * visibility-rules.ts pure-validator tests.
 *
 * Each case names the LoomStore.transitionVisibility behaviour it pins
 * down. We exercise:
 *   - missing visibility config
 *   - state not in `states` allowlist
 *   - draft → published happy path (with and without publishTransition)
 *   - revoke from various current states
 *   - LINEAR-cannot-publish + AFFINE-required-for-publish guards
 *   - capability gating (missing, present, partial)
 *   - draft → draft no-op rejection
 */

import { describe, expect, test } from 'bun:test';
import {
  LINEARITY_AFFINE,
  LINEARITY_LINEAR,
  LINEARITY_RELEVANT,
  validateVisibilityTransition,
} from '../visibility-rules';
import {
  makeHeader,
  makeObject,
  makeTypeDef,
  visibilityConfigCapGated,
  visibilityConfigSimple,
} from './fixtures';

describe('validateVisibilityTransition — preconditions', () => {
  test('rejects when type has no visibility config', () => {
    const obj = makeObject({
      typeDefinition: makeTypeDef({ visibility: undefined }),
    });
    const result = validateVisibilityTransition(obj, 'published');
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.reason).toMatch(/does not support visibility/);
  });

  test('rejects when target state is not in the allowed list', () => {
    const obj = makeObject({
      typeDefinition: makeTypeDef({
        visibility: { ...visibilityConfigSimple, states: ['draft'] },
      }),
    });
    const result = validateVisibilityTransition(obj, 'published');
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.reason).toMatch(/not allowed for type/);
  });
});

describe('validateVisibilityTransition — publish path', () => {
  test('AFFINE draft → published bumps linearity to RELEVANT', () => {
    const obj = makeObject({
      header: makeHeader(LINEARITY_AFFINE),
      typeDefinition: makeTypeDef({ visibility: visibilityConfigSimple }),
    });
    const result = validateVisibilityTransition(obj, 'published');
    expect(result.ok).toBe(true);
    if (result.ok) expect(result.transitions.newLinearity).toBe(LINEARITY_RELEVANT);
  });

  test('publish without publishTransition does not bump linearity', () => {
    const obj = makeObject({
      header: makeHeader(LINEARITY_AFFINE),
      typeDefinition: makeTypeDef({
        visibility: { ...visibilityConfigSimple, publishTransition: undefined },
      }),
    });
    const result = validateVisibilityTransition(obj, 'published');
    expect(result.ok).toBe(true);
    if (result.ok) expect(result.transitions).toEqual({});
  });

  test('LINEAR objects cannot be published', () => {
    const obj = makeObject({
      header: makeHeader(LINEARITY_LINEAR),
      typeDefinition: makeTypeDef({ visibility: visibilityConfigSimple }),
    });
    const result = validateVisibilityTransition(obj, 'published');
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.reason).toMatch(/LINEAR objects cannot be published/);
  });

  test('publish requires AFFINE linearity when publishTransition is configured', () => {
    const obj = makeObject({
      header: makeHeader(LINEARITY_RELEVANT),
      typeDefinition: makeTypeDef({ visibility: visibilityConfigSimple }),
    });
    const result = validateVisibilityTransition(obj, 'published');
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.reason).toMatch(/Publish requires AFFINE/);
  });

  test('publish from non-draft state is rejected', () => {
    const obj = makeObject({
      header: makeHeader(LINEARITY_AFFINE),
      visibility: 'published',
      typeDefinition: makeTypeDef({ visibility: visibilityConfigSimple }),
    });
    const result = validateVisibilityTransition(obj, 'published');
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.reason).toMatch(/Can only publish from draft/);
  });
});

describe('validateVisibilityTransition — capability gating', () => {
  test('publish without capabilities when required is rejected', () => {
    const obj = makeObject({
      header: makeHeader(LINEARITY_AFFINE),
      typeDefinition: makeTypeDef({ visibility: visibilityConfigCapGated }),
    });
    const result = validateVisibilityTransition(obj, 'published');
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.reason).toMatch(/Capabilities required/);
  });

  test('publish with missing required capability is rejected', () => {
    const obj = makeObject({
      header: makeHeader(LINEARITY_AFFINE),
      typeDefinition: makeTypeDef({ visibility: visibilityConfigCapGated }),
    });
    const result = validateVisibilityTransition(obj, 'published', [1, 2, 3]);
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.reason).toMatch(/Missing required capabilities for publish: 7/);
  });

  test('publish with required capability present succeeds', () => {
    const obj = makeObject({
      header: makeHeader(LINEARITY_AFFINE),
      typeDefinition: makeTypeDef({ visibility: visibilityConfigCapGated }),
    });
    const result = validateVisibilityTransition(obj, 'published', [7]);
    expect(result.ok).toBe(true);
    if (result.ok) expect(result.transitions.newLinearity).toBe(LINEARITY_RELEVANT);
  });
});

describe('validateVisibilityTransition — revoke path', () => {
  test('published → revoked is allowed', () => {
    const obj = makeObject({
      visibility: 'published',
      typeDefinition: makeTypeDef({ visibility: visibilityConfigSimple }),
    });
    const result = validateVisibilityTransition(obj, 'revoked');
    expect(result.ok).toBe(true);
    if (result.ok) expect(result.transitions).toEqual({});
  });

  test('draft → revoked is rejected', () => {
    const obj = makeObject({
      typeDefinition: makeTypeDef({ visibility: visibilityConfigSimple }),
    });
    const result = validateVisibilityTransition(obj, 'revoked');
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.reason).toMatch(/Can only revoke from published/);
  });

  test('revoked → revoked is rejected', () => {
    const obj = makeObject({
      visibility: 'revoked',
      typeDefinition: makeTypeDef({ visibility: visibilityConfigSimple }),
    });
    const result = validateVisibilityTransition(obj, 'revoked');
    expect(result.ok).toBe(false);
  });
});

describe('validateVisibilityTransition — draft transitions', () => {
  test('draft → draft on a fresh object is allowed (idempotent)', () => {
    const obj = makeObject({
      typeDefinition: makeTypeDef({ visibility: visibilityConfigSimple }),
    });
    const result = validateVisibilityTransition(obj, 'draft');
    expect(result.ok).toBe(true);
  });

  test('published → draft is rejected', () => {
    const obj = makeObject({
      visibility: 'published',
      typeDefinition: makeTypeDef({ visibility: visibilityConfigSimple }),
    });
    const result = validateVisibilityTransition(obj, 'draft');
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.reason).toMatch(/Cannot transition back to draft/);
  });
});

```
