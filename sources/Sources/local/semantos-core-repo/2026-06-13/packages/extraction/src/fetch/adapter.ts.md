---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/extraction/src/fetch/adapter.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.459556+00:00
---

# packages/extraction/src/fetch/adapter.ts

```ts
/**
 * Fetch adapter interface and factory.
 *
 * Each protocol (REST, GraphQL, file, stub) has its own adapter.
 * The pipeline selects the adapter based on grammar.source.protocol
 * and never sees protocol-specific details.
 */

import type { SourceEntity, SourceDeclaration, ContentStore } from '@semantos/protocol-types';
import type { RawResponse, Credentials, ExtractionContext } from '../stages';

/** Protocol-specific fetch adapter. */
export interface FetchAdapter {
  fetch(
    entity: SourceEntity,
    source: SourceDeclaration,
    credentials: Credentials,
    context: ExtractionContext,
  ): AsyncGenerator<RawResponse, void, void>;
}

/** Cross-cutting options threaded into protocol-specific adapters. */
export interface FetchAdapterOptions {
  /** When set, the file fetch path stores raw documents through this. */
  contentStore?: ContentStore;
}

/** Select the correct fetch adapter for a protocol. */
export function selectFetchAdapter(
  protocol: string,
  options?: FetchAdapterOptions,
): FetchAdapter {
  // Lazy imports to avoid circular dependency issues
  switch (protocol) {
    case 'rest': {
      const { RestFetchAdapter } = require('./rest') as typeof import('./rest');
      return new RestFetchAdapter();
    }
    case 'graphql': {
      const { GraphQLFetchAdapter } = require('./graphql') as typeof import('./graphql');
      return new GraphQLFetchAdapter();
    }
    case 'file': {
      const { FileFetchAdapter } = require('./file') as typeof import('./file');
      return new FileFetchAdapter(
        options?.contentStore ? { contentStore: options.contentStore } : undefined,
      );
    }
    case 'stub': {
      const { StubFetchAdapter } = require('./stub') as typeof import('./stub');
      return new StubFetchAdapter();
    }
    default:
      throw new Error(`Unknown fetch protocol: ${protocol}`);
  }
}

```
