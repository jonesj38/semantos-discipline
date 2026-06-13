---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/rtc/brain-operator-signer.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.041785+00:00
---

# runtime/session-protocol/src/rtc/brain-operator-signer.ts

```ts
/**
 * brain-operator-signer — a `BundleSigner` that signs an `rtc.jingle` (or any
 * SignedBundle payload) AS the operator by delegating to the brain's
 * `POST /api/v1/bundle/sign` endpoint (D-helm-rtc-operator-sign).
 *
 * The operator's pin private key lives ONLY on the brain (the sovereign node),
 * never in the helm SPA. The helm builds the UNSIGNED bundle, the brain signs
 * it with `operator_root_priv`, and the recipient verifies the result via
 * `verifyBrainBundleSignature` / `makeContactBundleVerifier` — the preimage
 * (`SIG_DOMAIN || canonical-json(bundle - signature)`) is byte-identical
 * across the Zig signer and the TS verifier (see bsv-signed-bundle-verifier.ts
 * + core/protocol-types/src/signed-bundle/codec.ts).
 *
 * This is the production replacement for the dev placeholder signer
 * (rtc-call.devSignBundle). With a real operator signature the recipient turns
 * `verifyInbound` ON (BrainRtcSignalChannel.verifyInbound).
 */

import type { BundleSigner } from '../xmpp-node';
import { ENVELOPE_VERSION, type SignedBundle } from '@semantos/protocol-types/signed-bundle';

/** carpenter context tag (0x10) — the operator's default hat. */
const CONTEXT_TAG_OPERATOR = 0x10;

export interface BrainOperatorSignerOptions {
  /** Brain origin, e.g. https://brain.example.com (no trailing slash). */
  brainBase: string;
  /** Admin bearer — the sign route is an admin surface (cap.brain.admin). */
  bearer: string;
  /** The operator's pin cert id (32-hex) — the leaf cert. */
  selfCertId: string;
  /** The operator's pin pubkey (66-hex compressed) — must match the brain's
   *  operator_root_priv, else the signature won't verify downstream. */
  selfPubkeyHex: string;
  /** Injectable fetch (tests). Defaults to global fetch. */
  fetchImpl?: typeof fetch;
  /** Injectable 32-byte nonce hex (tests). Defaults to crypto.getRandomValues. */
  nonceHex?: () => string;
}

function randomNonceHex(): string {
  const b = new Uint8Array(32);
  crypto.getRandomValues(b);
  return Array.from(b, (x) => x.toString(16).padStart(2, '0')).join('');
}

/**
 * Build the UNSIGNED bundle the helm sends to the brain to sign. Exposed for
 * tests; the brain overwrites `signature` and re-stamps `timestamp_unix`.
 */
export function unsignedBundle(
  opts: Pick<BrainOperatorSignerOptions, 'selfCertId' | 'selfPubkeyHex'>,
  req: { recipientCertId: string; payload: string; payloadType: string },
  nonceHex: string,
): SignedBundle {
  return {
    v: ENVELOPE_VERSION,
    sender_cert_chain: [
      {
        cert_id: opts.selfCertId,
        pubkey: opts.selfPubkeyHex,
        context_tag: CONTEXT_TAG_OPERATOR,
        parent_cert_id: null,
      },
    ],
    recipient_cert_id: req.recipientCertId,
    payload_type: req.payloadType,
    payload: req.payload,
    signature: '00'.repeat(64),
    signature_metadata: { algorithm: 'ecdsa-secp256k1-sha256', nonce_hex: nonceHex, timestamp_unix: 0 },
  };
}

/** A BundleSigner backed by the brain's operator key (POST /api/v1/bundle/sign). */
export function makeBrainOperatorSigner(opts: BrainOperatorSignerOptions): BundleSigner {
  const doFetch = opts.fetchImpl ?? fetch;
  const nonce = opts.nonceHex ?? randomNonceHex;
  const url = `${opts.brainBase}/api/v1/bundle/sign`;
  return async (req): Promise<SignedBundle> => {
    const body = unsignedBundle(opts, req, nonce());
    const res = await doFetch(url, {
      method: 'POST',
      headers: { 'content-type': 'application/json', authorization: `Bearer ${opts.bearer}` },
      body: JSON.stringify(body),
    });
    if (!res.ok) throw new Error(`POST /api/v1/bundle/sign → ${res.status}`);
    return (await res.json()) as SignedBundle;
  };
}

```
