---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/scg-relations/src/lexicon.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.816527+00:00
---

# core/scg-relations/src/lexicon.ts

```ts
/**
 * SCG relation lexicon. Plugs into `core/semantos-sir/src/lexicons.ts`
 * alongside JuralLexicon / TradesLexicon / etc.
 *
 * The `header` function is the identity — `RelationKind` values are
 * already canonical uppercase strings, so identity is trivially
 * injective on the declared set.
 *
 * Registration in `ALL_LEXICONS` lands in RM-010's accompanying edit;
 * the runtime-injectivity guard `verifyLexiconInjective` from semantos-sir
 * confirms safety at startup.
 */
import type { Lexicon } from '@semantos/lexicon-core';
import { ALL_RELATION_KINDS, type RelationKind } from './types.js';

export const relationLexicon: Lexicon<RelationKind> = {
  name: 'scg-relation',
  categories: ALL_RELATION_KINDS,
  header: (c) => c,
};

```
