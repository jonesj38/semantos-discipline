---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/legacy-ingest/src/extractor/registry.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.159905+00:00
---

# runtime/legacy-ingest/src/extractor/registry.ts

```ts
/**
 * Per-content-type extractor registry — LI3.
 *
 * The runner looks up extractors by RawItem.contentType.
 */
import type { ContentExtractor } from './types';

export class ExtractorRegistry {
  private readonly map = new Map<string, ContentExtractor>();

  register(extractor: ContentExtractor): void {
    if (this.map.has(extractor.contentType)) {
      throw new Error(`extractor already registered for '${extractor.contentType}'`);
    }
    this.map.set(extractor.contentType, extractor);
  }

  get(contentType: string): ContentExtractor | undefined {
    return this.map.get(contentType);
  }

  list(): ContentExtractor[] {
    return [...this.map.values()];
  }
}

```
