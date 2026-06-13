---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/extraction/src/fetch/stub.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.459269+00:00
---

# packages/extraction/src/fetch/stub.ts

```ts
/**
 * Stub fetch adapter — deterministic canned responses for testing.
 *
 * Constructor accepts an array of RawResponse objects. Yields them in order.
 * Same input = same output, always.
 */

import type { SourceEntity, SourceDeclaration } from '@semantos/protocol-types';
import type { RawResponse, Credentials, ExtractionContext } from '../stages';
import type { FetchAdapter } from './adapter';

export class StubFetchAdapter implements FetchAdapter {
  constructor(private responses: RawResponse[] = []) {}

  async *fetch(
    _entity: SourceEntity,
    _source: SourceDeclaration,
    _credentials: Credentials,
    _context: ExtractionContext,
  ): AsyncGenerator<RawResponse, void, void> {
    for (const response of this.responses) {
      yield response;
    }
  }

  /** Replace the canned responses (for test setup). */
  setResponses(responses: RawResponse[]): void {
    this.responses = responses;
  }
}

/** Create a stub response from simple data (for tests). */
export function createStubResponse(
  data: unknown,
  endpoint = '/stub',
  statusCode = 200,
): RawResponse {
  const bodyStr = JSON.stringify(data);
  // Deterministic hash based on content
  const hash = simpleHash(bodyStr);

  return {
    endpoint,
    statusCode,
    body: data,
    headers: { 'content-type': 'application/json' },
    timestamp: 1700000000000, // fixed timestamp for determinism
    responseHash: hash,
  };
}

/** Simple non-crypto hash for deterministic test responses. */
function simpleHash(input: string): string {
  let h = 0;
  for (let i = 0; i < input.length; i++) {
    h = ((h << 5) - h + input.charCodeAt(i)) | 0;
  }
  return Math.abs(h).toString(16).padStart(16, '0');
}

```
