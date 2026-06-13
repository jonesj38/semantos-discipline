---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/dispatch/dispatch/src/index.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.511842+00:00
---

# packages/dispatch/dispatch/src/index.ts

```ts
/**
 * @semantos/dispatch — dispatch envelope bridge primitive.
 *
 * D-O11 phase O11b per `docs/design/ODDJOBZ-EXTENSION-PLAN.md` §3
 * phase O11. The cross-vertical federation seam: defines the
 * envelope/accepted/completion cell types and a transport-agnostic
 * handler that routes envelope payloads to registered receiving
 * extensions.
 *
 * Reference: docs/textbook/29-cross-vertical-dispatch-and-federation.md
 */

export * from './cell-types/index.js';
export * from './handler/index.js';
export {
  InMemoryBundleTransport,
  packEnvelope,
  unpackEnvelope,
  bytesToHex,
  hexToBytes,
  type EnvelopeSubscriber,
} from './transport.js';

// Re-export tenant-hat reference helpers from re-desk-stub so
// dispatch consumers don't need a transitive import.
export {
  parseTenantHatRef,
  formatTenantHatRef,
  isTenantHatRef,
  InvalidTenantHatRefError,
  type TenantHatRef,
} from '@semantos/re-desk-stub';

```
