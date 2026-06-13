---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/ws-node-adapter/src/index.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.331590+00:00
---

# runtime/ws-node-adapter/src/index.ts

```ts
/**
 * @semantos/ws-node-adapter — NetworkAdapter over WSS with license-handshake
 * envelope auth.
 *
 * Step 4 landed wire-envelope types, CBOR codec, and license-handshake
 * exchange/verify. Step 5 adds WsPeerConnection (state machine) and
 * WsNodeAdapter (Bun.serve listen + WebSocket dial + publish/subscribe).
 */

// ── Envelope types ────────────────────────────────────────────
export {
  FRAME_KIND,
} from "./types.js";
export type {
  Frame,
  FrameKind,
  LicenseHandshakeFrame,
  SessionEnvelopeFrame,
  HeartbeatFrame,
  GoodbyeFrame,
  ConnectionState,
} from "./types.js";

// ── CBOR codec + signing helpers ──────────────────────────────
export {
  encodeFrame,
  decodeFrame,
  canonicalEnvelopeBytesForSigning,
  handshakeSigPayload,
} from "./codec.js";

// ── License handshake ────────────────────────────────────────
export {
  buildHandshakeFrame,
  verifyHandshakeFrame,
} from "./license-handshake.js";
export type {
  BuildHandshakeFrameParams,
  HandshakeVerifyConfig,
  HandshakeVerdict,
} from "./license-handshake.js";

// ── Per-peer connection ──────────────────────────────────────
export { WsPeerConnection } from "./ws-peer-connection.js";
export type {
  WsPeerConnectionConfig,
  LocalIdentity,
} from "./ws-peer-connection.js";

// ── NetworkAdapter ──────────────────────────────────────────
export { WsNodeAdapter } from "./ws-node-adapter.js";
export type { WsNodeAdapterConfig } from "./ws-node-adapter.js";

// ── BundleTransport bridge (Slice 5d over 35B.1 federation) ─
export {
  createWsBundleTransport,
  bundleTopicForCertId,
} from "./bundle-transport-bridge.js";
export type { WsBundleTransportConfig } from "./bundle-transport-bridge.js";

```
