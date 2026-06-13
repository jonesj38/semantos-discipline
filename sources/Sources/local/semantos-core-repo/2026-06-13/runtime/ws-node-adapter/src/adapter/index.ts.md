---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/ws-node-adapter/src/adapter/index.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.335343+00:00
---

# runtime/ws-node-adapter/src/adapter/index.ts

```ts
/**
 * adapter/ — split modules behind the `WsNodeAdapter` facade.
 *
 * The legacy single-file `ws-node-adapter.ts` is now a deprecation
 * re-export shim that points here. New code should import the facade
 * from this sub-folder; everything else (transport, lifecycle, dial,
 * registry, codec, license-verifier, local-delivery, well-known) is
 * intentionally not re-exported from `@semantos/ws-node-adapter`'s
 * top-level — they're internals.
 */

export { WsNodeAdapter, type WsNodeAdapterConfig } from "./facade.js";

// Internal seams (not re-exported from the package root, but available
// to in-package tests via `../adapter/...` imports).
export {
  bunWsTransport,
  type WsTransport,
  type WsServer,
  type WsSocket,
  type WsSocketHooks,
  type WsListenConfig,
  type WsListenerHooks,
  type WsAcceptedHooks,
} from "./transport.js";
export {
  buildSignedEnvelope,
  verifyInboundEnvelope,
} from "./envelope-codec.js";
export {
  gateInboundEnvelope,
  type EnvelopeGateInput,
  type EnvelopeGateVerdict,
} from "./license-verifier.js";
export {
  PeerRegistry,
  SubscriberRegistry,
  type Subscriber,
} from "./registry.js";
export { deliverLocally } from "./local-delivery.js";
export { buildWellKnownBody } from "./well-known.js";
export { startListener } from "./lifecycle.js";
export { dialAndAuthenticate } from "./dial.js";

```
