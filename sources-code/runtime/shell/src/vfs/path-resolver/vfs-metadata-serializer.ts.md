---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/shell/src/vfs/path-resolver/vfs-metadata-serializer.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.389512+00:00
---

# runtime/shell/src/vfs/path-resolver/vfs-metadata-serializer.ts

```ts
/**
 * Pure CellHeader → 256-byte sidecar serializer for the VFS
 * `header.bin` view.
 *
 * Reuses `serializeCellHeader` from the cell-store split (prompt 04)
 * for the canonical wire layout — no duplication of the byte
 * offsets across modules.
 */

import { serializeCellHeader } from '@semantos/protocol-types';
import type { CellHeader } from '@semantos/protocol-types';

import type { VfsFileContent } from './types';

/**
 * Serialize an object's CellHeader into the canonical 256-byte
 * binary sidecar. Mirrors the bytes the pre-split monolith emitted.
 */
export function serializeHeaderBin(header: CellHeader): VfsFileContent {
  const bytes = serializeCellHeader(header);
  const buf = Buffer.from(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  return { data: buf, size: buf.length };
}

```
