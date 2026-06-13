---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/jambox/web/src/core/sync.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.609496+00:00
---

# cartridges/jambox/web/src/core/sync.ts

```ts
// Relay client and types now live in @semantos/world-sdk — re-export for backward compat.
export type {
  SerializedCell,
  LiveTrigger,
  LivePayload,
  RelayCallbacks as SyncCallbacks,
  RelayServerMsg as ServerMsg,
} from "@semantos/world-sdk/relay";
export {
  RelayClient as JamSync,
  serializeCell,
  deserializeCell,
  bytesToHex,
  hexToBytes,
} from "@semantos/world-sdk/relay";

```
