---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/rtc/brain-rtc-signal-channel.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.039253+00:00
---

# runtime/session-protocol/src/rtc/brain-rtc-signal-channel.ts

```ts
/**
 * brain-rtc-signal-channel — the RTC signalling carrier over the brain's
 * MessageBox (BRC-77/78). This is the relay that lets two SEPARATE operators
 * (two helms) ring each other: the signalling no longer needs both peers in one
 * process — it traverses the brain.
 *
 * It implements the same `RtcSignalChannel` port as the in-process and XMPP
 * carriers, so the signalling plane + call binding are unchanged. A call's
 * Jingle is wrapped in a SignedBundle (payload_type `rtc.jingle`) — exactly as
 * over the XMPP carrier — so the SDP + DTLS fingerprint are signed by the
 * sender's cert; the brain relays it opaquely and cannot MITM the media
 * endpoint. (Inbound bundles are shape-validated here; full signature / cert-
 * chain verification is the recipient's job, same contract as the XMPP node.)
 *
 * Transport: the brain MessageBox is store-and-forward, addressed by a 66-hex
 * mailbox (use the contact's compressed pubkey hex). `sendTo` POSTs the bundle;
 * inbound is delivered by POLLING `/messages/list` (the brain's WSS push only
 * nudges "you have mail", so we poll), then ACKing to consume. No brain change.
 *
 *   send   POST /api/v1/messages/send  { recipient, kind:"signed", sender, payload:b64 }
 *   list   GET  /api/v1/messages/list?recipient=<66hex>   (Bearer)
 *   ack    POST /api/v1/messages/ack   { id }              (Bearer)
 *
 * Cross-reference: xmpp-signal-channel.ts (the XMPP-carrier sibling),
 * runtime/semantos-brain/src/messagebox_http.zig (the relay endpoint).
 */

import type { SignedBundle } from '@semantos/protocol-types/xmpp';
import type { BundleSigner } from '../xmpp-node';
import { RtcSignalPlane, type InboundSignal, type RtcSignalChannel } from './signal';

const RTC_JINGLE_PAYLOAD_TYPE = 'rtc.jingle';

function b64encode(s: string): string {
  return typeof Buffer !== 'undefined' ? Buffer.from(s, 'utf8').toString('base64') : btoa(unescape(encodeURIComponent(s)));
}
function b64decode(s: string): string {
  return typeof Buffer !== 'undefined' ? Buffer.from(s, 'base64').toString('utf8') : decodeURIComponent(escape(atob(s)));
}

export interface BrainRtcSignalChannelOptions {
  /** Brain base URL, e.g. `http://[::1]:8080`. */
  brainBase: string;
  /** Bearer token (64-hex) for list/ack. */
  bearer: string;
  /** This client's mailbox — a 66-hex string (the operator's compressed pubkey). */
  selfMailbox: string;
  /** Map a peer cert id → their 66-hex mailbox (the contact's pubkey hex). */
  mailboxFor: (peerCertId: string) => string;
  /** Wrap a Jingle stanza into a SignedBundle (parity with the XMPP carrier). */
  signBundle: BundleSigner;
  /** Inbound poll interval, ms (default 400). */
  pollMs?: number;
  /**
   * Recipient-side verification: authenticate each inbound bundle (signature +
   * known-contact binding) before delivering. Returns false → the message is
   * dropped (acked, not surfaced). Build with
   * `makeContactBundleVerifier(...)` (bsv-signed-bundle-verifier). When absent,
   * the bundle is shape-validated only (the legacy posture).
   */
  verifyInbound?: (bundle: SignedBundle) => boolean | Promise<boolean>;
  /** Injected fetch (defaults to global). */
  fetchImpl?: typeof fetch;
}

export class BrainRtcSignalChannel implements RtcSignalChannel {
  private readonly opts: Required<Pick<BrainRtcSignalChannelOptions, 'pollMs'>> & BrainRtcSignalChannelOptions;
  private readonly fetch: typeof fetch;
  private timer: ReturnType<typeof setInterval> | null = null;
  private polling = false;

  constructor(opts: BrainRtcSignalChannelOptions) {
    this.opts = { pollMs: 400, ...opts };
    this.fetch = opts.fetchImpl ?? globalThis.fetch.bind(globalThis);
  }

  async sendTo(peerCertId: string, jingleXml: string): Promise<void> {
    const bundle = await this.opts.signBundle({
      recipientCertId: peerCertId,
      payload: jingleXml,
      payloadType: RTC_JINGLE_PAYLOAD_TYPE,
    });
    const payload = b64encode(JSON.stringify(bundle));
    const res = await this.fetch(`${this.opts.brainBase}/api/v1/messages/send`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        recipient: this.opts.mailboxFor(peerCertId),
        kind: 'signed',
        sender: this.opts.selfMailbox,
        payload,
      }),
    });
    if (!res.ok) throw new Error(`brain messagebox send failed: ${res.status}`);
  }

  onInbound(handler: (msg: InboundSignal) => void): () => void {
    this.polling = true;
    const poll = async () => {
      try {
        const res = await this.fetch(
          `${this.opts.brainBase}/api/v1/messages/list?recipient=${encodeURIComponent(this.opts.selfMailbox)}`,
          { headers: { Authorization: `Bearer ${this.opts.bearer}` } },
        );
        if (!res.ok) return;
        const body = (await res.json()) as { messages?: Array<{ id: string; payload: string }> };
        for (const m of body.messages ?? []) {
          await this.consume(m, handler);
        }
      } catch {
        /* transient — keep polling */
      }
    };
    this.timer = setInterval(() => void poll(), this.opts.pollMs);
    void poll(); // fetch immediately
    return () => {
      this.polling = false;
      if (this.timer) clearInterval(this.timer);
      this.timer = null;
    };
  }

  private async consume(m: { id: string; payload: string }, handler: (msg: InboundSignal) => void): Promise<void> {
    let delivered = false;
    try {
      const bundle = JSON.parse(b64decode(m.payload)) as SignedBundle;
      if (bundle.payload_type === RTC_JINGLE_PAYLOAD_TYPE) {
        // Authenticate the bundle (signature + known contact) before surfacing
        // the call. A failed verify is dropped (acked) — not delivered.
        const ok = this.opts.verifyInbound ? await this.opts.verifyInbound(bundle) : true;
        if (ok) {
          const fromCertId = bundle.sender_cert_chain?.[0]?.cert_id ?? '';
          handler({ fromCertId, jingleXml: bundle.payload });
        }
        delivered = true;
      }
    } catch {
      /* not a jingle bundle — ack + drop so it doesn't wedge the inbox */
      delivered = true;
    }
    if (delivered) await this.ack(m.id);
  }

  private async ack(id: string): Promise<void> {
    await this.fetch(`${this.opts.brainBase}/api/v1/messages/ack`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${this.opts.bearer}` },
      body: JSON.stringify({ id }),
    }).catch(() => {});
  }
}

/**
 * Wire an RTC signalling plane that rings contacts THROUGH the brain (the relay
 * that lets two separate helms call each other). `selfJid` is informational;
 * the trust/identity is the signed bundle's cert chain.
 */
export function rtcOverBrain(opts: BrainRtcSignalChannelOptions & { selfJid: string }): RtcSignalPlane {
  return new RtcSignalPlane({ channel: new BrainRtcSignalChannel(opts), selfJid: opts.selfJid });
}

```
