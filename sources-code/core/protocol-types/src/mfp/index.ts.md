---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/mfp/index.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.868292+00:00
---

# core/protocol-types/src/mfp/index.ts

```ts
/**
 * MFP — Metered-Flow-Protocol.
 *
 * Consumer-side adapter + protocolID convention for prepaid, metered BSV
 * payment-channel flows fronted by a BRC-100 wallet. The vault is a
 * `(protocolID, cap)` Tier-0 grant, not a storage location — so the same
 * adapter works against any BRC-100 backend (Metanet Desktop, the
 * Semantos browser iframe wallet, wallet-headers, or an embedded agent
 * wallet). The device side (the metered channel + drain + actuator) runs
 * on the C6 cell-mesh; see esp32-hackkit/docs/x402-over-cells.md.
 */

export * from './protocol-id.js';
export * from './flow-adapter.js';
export * from './iframe-wallet-port.js';

```
