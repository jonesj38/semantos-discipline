---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/tools/crystallization/lib/corpus-internal.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.556147+00:00
---

# tools/crystallization/lib/corpus-internal.ts

```ts
import type { ConceptDef } from '../types';

export type Matcher = { name: string; re: RegExp };

export function buildMatchers(concepts: ConceptDef[]): Matcher[] {
  return concepts.map(c => ({
    name: c.name,
    re: new RegExp(
      c.aliases.map(a => a.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')).join('|'),
      'gi'
    ),
  }));
}

export function countMentions(text: string, matchers: Matcher[]): Map<string, number> {
  const m = new Map<string, number>();
  for (const { name, re } of matchers) {
    re.lastIndex = 0;
    const matches = text.match(re);
    if (matches && matches.length > 0) m.set(name, matches.length);
  }
  return m;
}

```
