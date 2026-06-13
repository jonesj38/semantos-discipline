---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/xmpp/index.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.863202+00:00
---

# core/protocol-types/src/xmpp/index.ts

```ts
/**
 * `@semantos/protocol-types/xmpp` — public barrel for the SRS × XMPP
 * identity-transport binding.
 *
 * Re-exports the JID grammar, SignedBundle⇄stanza codec, roster/presence
 * bridge, the NetworkAdapter implementation, the in-memory stub transport, and
 * the type-multicast group strategy.  A wiring layer (e.g.
 * `runtime/session-protocol/src/xmpp-node/`) consumes this barrel to bind the
 * binding to a live ContactBook + cert stack.
 *
 * Cross-reference: docs/design/SRS-XMPP-IDENTITY-TRANSPORT.md.
 */

export * from './jid';
export * from './bundle-stanza';
export * from './roster-bridge';
export * from './xmpp-network-adapter';
export * from './stub-xmpp-transport';
export * from './pubsub-group-strategy';

// The wire shape the stanza carries — re-exported so callers don't need a
// second import path for the payload type.
export type { SignedBundle, CertRef } from '../signed-bundle/types';
export { ENVELOPE_VERSION } from '../signed-bundle/types';

```
