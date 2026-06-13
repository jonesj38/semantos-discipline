---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/semantic-fs/semantic-path-parser.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.866017+00:00
---

# core/protocol-types/src/semantic-fs/semantic-path-parser.ts

```ts
/**
 * Pure semantic-path parser. Splits a slash-separated path into
 * prefix / taxonomy-path / objectId / sub-resource via a greedy
 * backward scan against the supplied {@link TaxonomyResolver}.
 *
 * Greedy backward scan: for "objects/<segments…>", try the longest
 * candidate taxonomy path first, then shorten one segment at a time
 * until `taxonomy.getNodeAt(...)` returns a node. The first match
 * yields the split; remaining segments become objectId + sub-resources.
 *
 * No I/O, no hashing — pure function over `(path, taxonomy)`.
 */

import type { TaxonomyResolver } from '../taxonomy-resolver';
import {
  InvalidSemanticPathError,
  VALID_PREFIXES,
  type ParsedSemanticPath,
} from './types';

export function parseSemanticPath(
  path: string,
  taxonomy: TaxonomyResolver,
): ParsedSemanticPath {
  const segments = path.split('/').filter((s) => s.length > 0);
  if (segments.length === 0) {
    throw new InvalidSemanticPathError(path, 'empty path');
  }

  const prefix = segments[0] as string;
  if (!VALID_PREFIXES.has(prefix)) {
    throw new InvalidSemanticPathError(path, `unknown prefix "${prefix}"`);
  }

  const rest = segments.slice(1);

  // Non-objects prefixes pass through without taxonomy validation.
  if (prefix !== 'objects') {
    return {
      prefix,
      taxonomyPath: [],
      objectId: null,
      subResource: rest,
      storageKey: segments.join('/'),
    };
  }

  // Bare "objects" is a valid listing prefix.
  if (rest.length === 0) {
    return {
      prefix,
      taxonomyPath: [],
      objectId: null,
      subResource: [],
      storageKey: 'objects',
    };
  }

  // Greedy backward scan for the longest taxonomy match.
  let taxonomyLen = rest.length;
  while (taxonomyLen > 0) {
    const candidate = rest.slice(0, taxonomyLen);
    const node = taxonomy.getNodeAt(candidate);
    if (node !== null) {
      const remaining = rest.slice(taxonomyLen);
      return {
        prefix,
        taxonomyPath: candidate,
        objectId: remaining.length > 0 ? (remaining[0] as string) : null,
        subResource: remaining.length > 1 ? remaining.slice(1) : [],
        storageKey: segments.join('/'),
      };
    }
    taxonomyLen--;
  }

  throw new InvalidSemanticPathError(
    path,
    `taxonomy path "${rest.join('.')}" does not resolve to a valid node`,
  );
}

```
