---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/semantic-fs/semantic-path-validator.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.867663+00:00
---

# core/protocol-types/src/semantic-fs/semantic-path-validator.ts

```ts
/**
 * Validate a semantic path for write operations.
 *
 * Wraps {@link parseSemanticPath} with the additional rule that
 * "objects" writes must include a taxonomy prefix — you cannot write
 * directly to bare "objects".
 */

import type { TaxonomyResolver } from '../taxonomy-resolver';
import { parseSemanticPath } from './semantic-path-parser';
import { InvalidSemanticPathError, type ParsedSemanticPath } from './types';

export function validateForWrite(
  path: string,
  taxonomy: TaxonomyResolver,
): ParsedSemanticPath {
  const parsed = parseSemanticPath(path, taxonomy);
  if (parsed.prefix === 'objects' && parsed.taxonomyPath.length === 0) {
    throw new InvalidSemanticPathError(path, 'cannot write to bare "objects" prefix');
  }
  return parsed;
}

```
