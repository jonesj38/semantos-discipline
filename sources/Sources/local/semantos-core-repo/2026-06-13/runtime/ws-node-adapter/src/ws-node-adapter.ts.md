---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/ws-node-adapter/src/ws-node-adapter.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.333246+00:00
---

# runtime/ws-node-adapter/src/ws-node-adapter.ts

```ts
/**
 * @deprecated — moved to `./adapter/`.
 *
 * This module used to hold the entire `WsNodeAdapter` (560 LOC mixing
 * lifecycle, license verification, envelope codec, and adapter
 * registry). Phase 12 / refactor-39 split it into focused modules
 * under `./adapter/`:
 *
 *   - adapter/transport.ts          — WS transport seam (port-style)
 *   - adapter/lifecycle.ts          — server start / stop / accept
 *   - adapter/dial.ts               — outbound dial + handshake
 *   - adapter/registry.ts           — peer + subscriber maps
 *   - adapter/envelope-codec.ts     — build / sign / verify envelopes
 *   - adapter/license-verifier.ts   — fail-closed inbound envelope gate
 *   - adapter/local-delivery.ts     — subscriber fan-out
 *   - adapter/well-known.ts         — discovery JSON builder
 *   - adapter/facade.ts             — composes the above into WsNodeAdapter
 *
 * This file remains as a re-export shim so existing consumers
 * (`runtime/node`, `tests/gates/phase35b-gate.test.ts`, etc.) and
 * the package's own `index.ts` continue to compile byte-identically.
 *
 * New code should import from `@semantos/ws-node-adapter` (the package
 * root index) rather than the deep `ws-node-adapter` path.
 */

export { WsNodeAdapter, type WsNodeAdapterConfig } from "./adapter/index.js";

```
