---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/scg-relations/src/__tests__/lexicon-injective.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.819017+00:00
---

# core/scg-relations/src/__tests__/lexicon-injective.test.ts

```ts
import { describe, expect, test } from 'bun:test';
import { verifyLexiconInjective } from '@semantos/lexicon-core';
import { relationLexicon } from '../lexicon.js';
import { ALL_RELATION_KINDS } from '../types.js';

describe('relationLexicon', () => {
  test('L1 declares every Phase-1 RelationKind', () => {
    expect(relationLexicon.categories.length).toBe(ALL_RELATION_KINDS.length);
    for (const k of ALL_RELATION_KINDS) {
      expect(relationLexicon.categories).toContain(k);
    }
  });

  test('L2 header function is injective across categories', () => {
    const result = verifyLexiconInjective(relationLexicon);
    expect(result.injective).toBe(true);
  });

  test('L3 carries a unique lexicon name', () => {
    expect(relationLexicon.name).toBe('scg-relation');
  });
});

```
