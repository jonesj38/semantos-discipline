---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/semantic-fs/__tests__/semantic-path-validator.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.906880+00:00
---

# core/protocol-types/src/semantic-fs/__tests__/semantic-path-validator.test.ts

```ts
/**
 * semantic-path-validator tests — write paths must include a
 * taxonomy prefix; everything else is delegated to the parser.
 */

import { describe, expect, test } from 'bun:test';
import { validateForWrite } from '../semantic-path-validator';
import { InvalidSemanticPathError } from '../types';
import { makeTaxonomy } from './fixtures';

const taxonomy = makeTaxonomy();

describe('validateForWrite', () => {
  test('1. accepts a fully-qualified taxonomy + object-id', () => {
    const parsed = validateForWrite('objects/create/job/plumbing/job-1', taxonomy);
    expect(parsed.objectId).toBe('job-1');
  });

  test('2. accepts a taxonomy path without an object id', () => {
    const parsed = validateForWrite('objects/create/job/plumbing', taxonomy);
    expect(parsed.taxonomyPath).toEqual(['create', 'job', 'plumbing']);
  });

  test('3. rejects bare "objects" as a write target', () => {
    expect(() => validateForWrite('objects', taxonomy)).toThrow(InvalidSemanticPathError);
    expect(() => validateForWrite('objects/', taxonomy)).toThrow(InvalidSemanticPathError);
  });

  test('4. rejects unknown taxonomy', () => {
    expect(() => validateForWrite('objects/garbage', taxonomy)).toThrow(/does not resolve/);
  });

  test('5. lets non-objects prefixes through (no taxonomy required)', () => {
    const parsed = validateForWrite('policies/anything', taxonomy);
    expect(parsed.prefix).toBe('policies');
  });

  test('6. propagates the parser empty-path error', () => {
    expect(() => validateForWrite('', taxonomy)).toThrow(/empty path/);
  });
});

```
