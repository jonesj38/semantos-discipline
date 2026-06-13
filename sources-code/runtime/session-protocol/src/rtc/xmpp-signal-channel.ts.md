---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/rtc/xmpp-signal-channel.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.042069+00:00
---

# runtime/session-protocol/src/rtc/xmpp-signal-channel.ts

```ts
/**
 * xmppSignalChannel — binds the S1 `RtcSignalChannel` port to the merged XMPP
 * node (`runtime/session-protocol/src/xmpp-node`, #974).
 *
 * This is the wiring that makes the fingerprint pin real: the Jingle stanza
 * rides as the PAYLOAD of a SignedBundle (payload_type `rtc.jingle`), so the
 * sender's cert chain signs over the SDP + its DTLS fingerprint. The node's
 * inbound path shape-checks the bundle and the brain verifies the signature +
 * cert chain; by the time `onInbound` fires, `fromCertId` (the bundle's leaf
 * cert id) is the authenticated peer identity that the fingerprint is pinned
 * to.
 *
 * The import is type-only, so rtc/ takes no runtime dependency on the node —
 * the signalling plane stays carrier-agnostic and unit-testable against an
 * in-memory channel.
 *
 * Cross-reference: docs/prd/RTC-ROADMAP.md §3, fingerprint.ts.
 */

import type { SignedBundle } from '@semantos/protocol-types/signed-bundle';
import type { XmppNode } from '../xmpp-node';
import { RtcSignalPlane, type RtcSignalChannel } from './signal';

/** SignedBundle payload_type that carries a Jingle signalling stanza. */
export const RTC_JINGLE_PAYLOAD_TYPE = 'rtc.jingle';

export interface XmppSignalChannelOptions {
  /**
   * Recipient-side verification: authenticate each inbound bundle (signature +
   * known-contact binding) before surfacing the call. Returns false → dropped.
   * Build with `makeContactBundleVerifier(...)`. Absent → shape-validated only
   * (the brain still verifies on its own receive seam; this is the in-TS gate).
   */
  verifyInbound?: (bundle: SignedBundle) => boolean | Promise<boolean>;
}

/**
 * Adapt an `XmppNode` to the S1 channel port. Outbound Jingle goes out as a
 * signed dispatch; inbound bundles of type `rtc.jingle` surface with the sender
 * cert id (authenticated by `verifyInbound` when provided).
 */
export function xmppSignalChannel(node: XmppNode, opts: XmppSignalChannelOptions = {}): RtcSignalChannel {
  return {
    async sendTo(peerCertId, jingleXml) {
      await node.sendDispatch(peerCertId, jingleXml, RTC_JINGLE_PAYLOAD_TYPE);
    },
    onInbound(handler) {
      return node.onInboundBundle(async (bundle) => {
        if (bundle.payload_type !== RTC_JINGLE_PAYLOAD_TYPE) return;
        if (opts.verifyInbound && !(await opts.verifyInbound(bundle))) return; // unauthenticated — drop
        const fromCertId = bundle.sender_cert_chain[0]?.cert_id ?? '';
        handler({ fromCertId, jingleXml: bundle.payload });
      });
    },
  };
}

/**
 * The one-call wiring: an RTC signalling plane that places + answers calls to a
 * CONTACT over the SRS / XMPP carrier. `node` carries the operator's identity +
 * ContactBook (the contacts established by the offband invite → bilateral-edge
 * → PKI flow), so calls are addressed by the contact's cert id, routed to their
 * BCA, and authenticated by the DTLS fingerprint pinned into the SignedBundle
 * the bilateral edge signs. This is what a helm binds: `placeMediaCall(plane,
 * factory, ice, contactCertId, …)`.
 */
export function rtcOverXmpp(node: XmppNode, opts: XmppSignalChannelOptions = {}): RtcSignalPlane {
  return new RtcSignalPlane({ channel: xmppSignalChannel(node, opts), selfJid: node.selfJid() });
}

```
