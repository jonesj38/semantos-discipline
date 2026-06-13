---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/scripts/piggybank/wire.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.384659+00:00
---

# scripts/piggybank/wire.ts

```ts
/**
 * Length-prefixed JSON framing over a TCP socket.
 *
 * Emulates the framing the real firmware will use over USB CDC serial:
 * each message is a 4-byte big-endian length prefix followed by the
 * UTF-8 JSON bytes. This keeps the TypeScript dry-run byte-identical
 * to what the ESP32 will do once we have hardware.
 */

import type { Socket } from 'node:net';
import type { ProvisioningMessage } from '../../apps/piggybank/src/device.js';

/** Send a provisioning message with length-prefixed JSON framing. */
export function sendFramed(socket: Socket, msg: ProvisioningMessage): void {
  const json = JSON.stringify(msg);
  const body = Buffer.from(json, 'utf8');
  const header = Buffer.alloc(4);
  header.writeUInt32BE(body.length, 0);
  socket.write(Buffer.concat([header, body]));
}

/**
 * Register a framed-message receiver on a socket. Calls `onMessage` for
 * every complete frame, even if TCP delivers them fragmented.
 */
export function onFramedMessage(
  socket: Socket,
  onMessage: (msg: ProvisioningMessage) => void,
  onError: (err: Error) => void,
): void {
  let buffer = Buffer.alloc(0);
  socket.on('data', chunk => {
    buffer = Buffer.concat([buffer, chunk]);
    while (buffer.length >= 4) {
      const bodyLen = buffer.readUInt32BE(0);
      if (buffer.length < 4 + bodyLen) break;
      const body = buffer.subarray(4, 4 + bodyLen);
      buffer = buffer.subarray(4 + bodyLen);
      try {
        const msg = JSON.parse(body.toString('utf8')) as ProvisioningMessage;
        onMessage(msg);
      } catch (err) {
        onError(err instanceof Error ? err : new Error(String(err)));
        return;
      }
    }
  });
  socket.on('error', onError);
}

```
