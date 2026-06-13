---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/semantic-fs/tombstone-resolver.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.865753+00:00
---

# core/protocol-types/src/semantic-fs/tombstone-resolver.ts

```ts
/**
 * Tombstone resolver — follows the redirect chain from a tombstoned
 * cell to its current location.
 *
 * A tombstoned cell carries `header.flags & FLAGS_TOMBSTONE`; its
 * payload is a UTF-8, NUL-terminated string holding the new storage
 * key. We re-read the new key, check its flags, and keep walking up
 * to {@link MAX_REDIRECT_HOPS} hops before erroring.
 */

import type { StorageAdapter } from '../storage';
import { deserializeCellHeader } from '../cell-header';
import { HEADER_SIZE } from '../constants';
import { FLAGS_TOMBSTONE, MAX_REDIRECT_HOPS } from './types';

export async function resolvePath(
  adapter: StorageAdapter,
  semanticPath: string,
): Promise<string> {
  let current = semanticPath;
  for (let hops = 0; hops < MAX_REDIRECT_HOPS; hops++) {
    const cellBytes = await adapter.read(current);
    if (!cellBytes || cellBytes.length < HEADER_SIZE) return current;

    const header = deserializeCellHeader(cellBytes);
    if (!(header.flags & FLAGS_TOMBSTONE)) return current;

    const payloadStart = HEADER_SIZE;
    let end = payloadStart;
    while (end < cellBytes.length && cellBytes[end] !== 0) end++;
    const redirect = new TextDecoder().decode(cellBytes.subarray(payloadStart, end));
    if (!redirect) return current;
    current = redirect;
  }
  throw new Error(`Too many redirects (>${MAX_REDIRECT_HOPS}) resolving "${semanticPath}"`);
}

```
