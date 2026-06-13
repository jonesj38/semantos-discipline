---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/semantic-fs/__tests__/semantic-path-parser.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.906310+00:00
---

# core/protocol-types/src/semantic-fs/__tests__/semantic-path-parser.test.ts

```ts
/**
 * semantic-path-parser tests — the greedy-backward-scan rule has a
 * lot of edge cases; pin them all.
 */

import { describe, expect, test } from 'bun:test';
import { parseSemanticPath } from '../semantic-path-parser';
import { InvalidSemanticPathError } from '../types';
import { makeTaxonomy } from './fixtures';

const taxonomy = makeTaxonomy();

describe('parseSemanticPath', () => {
  test('1. empty path throws', () => {
    expect(() => parseSemanticPath('', taxonomy)).toThrow(InvalidSemanticPathError);
  });

  test('2. unknown prefix throws', () => {
    expect(() => parseSemanticPath('garbage/foo', taxonomy)).toThrow(/unknown prefix/);
  });

  test('3. bare "objects" yields the listing prefix', () => {
    const parsed = parseSemanticPath('objects', taxonomy);
    expect(parsed).toEqual({
      prefix: 'objects',
      taxonomyPath: [],
      objectId: null,
      subResource: [],
      storageKey: 'objects',
    });
  });

  test('4. taxonomy path with no object-id is allowed', () => {
    const parsed = parseSemanticPath('objects/create/job/plumbing', taxonomy);
    expect(parsed.taxonomyPath).toEqual(['create', 'job', 'plumbing']);
    expect(parsed.objectId).toBeNull();
  });

  test('5. taxonomy + object-id', () => {
    const parsed = parseSemanticPath('objects/create/job/plumbing/job-1774', taxonomy);
    expect(parsed.taxonomyPath).toEqual(['create', 'job', 'plumbing']);
    expect(parsed.objectId).toBe('job-1774');
    expect(parsed.subResource).toEqual([]);
  });

  test('6. taxonomy + object-id + sub-resource', () => {
    const parsed = parseSemanticPath(
      'objects/create/job/plumbing/job-1774/evidence/0001-patch.json',
      taxonomy,
    );
    expect(parsed.taxonomyPath).toEqual(['create', 'job', 'plumbing']);
    expect(parsed.objectId).toBe('job-1774');
    expect(parsed.subResource).toEqual(['evidence', '0001-patch.json']);
  });

  test('7. greedy scan: ambiguous "create/job" with extra unknown segment chooses the longest valid taxonomy', () => {
    // "create/job" is a valid taxonomy node, "create/job/zzz" is not.
    // Parser should treat "zzz" as the object-id.
    const parsed = parseSemanticPath('objects/create/job/zzz', taxonomy);
    expect(parsed.taxonomyPath).toEqual(['create', 'job']);
    expect(parsed.objectId).toBe('zzz');
  });

  test('8. invalid taxonomy throws with informative reason', () => {
    expect(() => parseSemanticPath('objects/garbage', taxonomy)).toThrow(/does not resolve/);
  });

  test('9. non-objects prefix passes through with no taxonomy validation', () => {
    const parsed = parseSemanticPath('policies/whatever/here', taxonomy);
    expect(parsed.prefix).toBe('policies');
    expect(parsed.taxonomyPath).toEqual([]);
    expect(parsed.subResource).toEqual(['whatever', 'here']);
    expect(parsed.storageKey).toBe('policies/whatever/here');
  });

  test('10. multiple slashes are normalized away', () => {
    const parsed = parseSemanticPath('objects//create///job/plumbing///', taxonomy);
    expect(parsed.taxonomyPath).toEqual(['create', 'job', 'plumbing']);
  });
});

```
