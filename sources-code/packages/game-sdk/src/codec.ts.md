---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/game-sdk/src/codec.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.523213+00:00
---

# packages/game-sdk/src/codec.ts

```ts
/**
 * Entity payload codec — binary serialization for game entity metadata.
 *
 * Encodes game entity data into the 768-byte cell payload region.
 *
 * Binary layout:
 *   [0..1]  entityType (u16 LE)
 *   [2..3]  metadataLength (u16 LE)
 *   [4..5]  scriptLength (u16 LE)
 *   [6..7]  reserved (0x0000)
 *   [8..]   JSON metadata (UTF-8, sorted keys for determinism)
 *   [..]    script bytes
 */

import {
  GameEntityType,
  ENTITY_PAYLOAD_HEADER_SIZE,
  MAX_PAYLOAD_CONTENT_SIZE,
} from './types';

const PAYLOAD_SIZE = 768;

/**
 * Encode entity metadata and script bytes into a payload buffer.
 *
 * @param entityType - Entity classification tag
 * @param metadata - Key-value metadata (JSON-serialized with sorted keys)
 * @param scriptBytes - Optional compiled script bytes
 * @returns Payload buffer (up to 768 bytes, zero-padded)
 */
export function encodeEntityPayload(
  entityType: GameEntityType,
  metadata: Record<string, unknown>,
  scriptBytes?: Uint8Array,
): Uint8Array {
  const metadataJson = JSON.stringify(metadata, Object.keys(metadata).sort());
  const metadataBytes = new TextEncoder().encode(metadataJson);
  const scriptLen = scriptBytes?.length ?? 0;

  const totalContent = metadataBytes.length + scriptLen;
  if (totalContent > MAX_PAYLOAD_CONTENT_SIZE) {
    throw new Error(
      `Payload content too large: ${totalContent} bytes exceeds limit of ${MAX_PAYLOAD_CONTENT_SIZE}`,
    );
  }

  const payload = new Uint8Array(PAYLOAD_SIZE);
  const view = new DataView(payload.buffer);

  // 8-byte binary prefix
  view.setUint16(0, entityType, true);
  view.setUint16(2, metadataBytes.length, true);
  view.setUint16(4, scriptLen, true);
  // bytes 6-7 reserved (already zero)

  // Metadata JSON
  payload.set(metadataBytes, ENTITY_PAYLOAD_HEADER_SIZE);

  // Script bytes
  if (scriptBytes && scriptLen > 0) {
    payload.set(scriptBytes, ENTITY_PAYLOAD_HEADER_SIZE + metadataBytes.length);
  }

  return payload;
}

/**
 * Decode entity metadata and script bytes from a payload buffer.
 *
 * @param payload - The 768-byte (or shorter) payload region
 * @returns Decoded entity type, metadata, and script bytes
 */
export function decodeEntityPayload(payload: Uint8Array): {
  entityType: GameEntityType;
  metadata: Record<string, unknown>;
  scriptBytes: Uint8Array;
} {
  if (payload.length < ENTITY_PAYLOAD_HEADER_SIZE) {
    throw new Error(`Payload too small: ${payload.length} bytes`);
  }

  const view = new DataView(payload.buffer, payload.byteOffset, payload.byteLength);

  const entityType = view.getUint16(0, true) as GameEntityType;
  const metadataLength = view.getUint16(2, true);
  const scriptLength = view.getUint16(4, true);

  // Decode metadata JSON
  const metadataStart = ENTITY_PAYLOAD_HEADER_SIZE;
  const metadataEnd = metadataStart + metadataLength;
  const metadataJson = new TextDecoder().decode(
    payload.subarray(metadataStart, metadataEnd),
  );
  const metadata = metadataLength > 0 ? JSON.parse(metadataJson) : {};

  // Extract script bytes
  const scriptStart = metadataEnd;
  const scriptBytes = payload.slice(scriptStart, scriptStart + scriptLength);

  return { entityType, metadata, scriptBytes };
}

```
