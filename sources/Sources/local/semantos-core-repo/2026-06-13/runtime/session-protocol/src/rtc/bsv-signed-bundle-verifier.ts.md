---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/rtc/bsv-signed-bundle-verifier.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.042339+00:00
---

# runtime/session-protocol/src/rtc/bsv-signed-bundle-verifier.ts

```ts
/**
 * bsv-signed-bundle-verifier — recipient-side verification of the brain
 * SignedBundle that carries RTC signalling (the relay hardening).
 *
 * Inbound `rtc.jingle` bundles were previously shape-validated only — a tampered
 * or forged jingle (and the SDP / DTLS fingerprint it carries) would pass. This
 * verifies the bundle's ECDSA signature over the canonical preimage and binds
 * the signer to a KNOWN CONTACT, so:
 *   - a relay (the brain) cannot alter the SDP/fingerprint — the signature
 *     covers them (so the fingerprint pin's chain of trust holds end-to-end);
 *   - an attacker cannot forge a call from a contact — the leaf cert id must be
 *     a known contact AND its advertised pubkey must match the one on file AND
 *     the signature must verify under it.
 *
 * Mirrors the signer (cartridges/oddjobz/brain/tools/send-bundle.ts) +
 * `signed_bundle.zig`: digest = sha256(canonical preimage); the compact
 * 64-byte (r‖s) signature is checked with @bsv/sdk over the digest hex
 * (`PublicKey.verify` hashes the hex input the same way `PrivateKey.sign` did).
 *
 * This is a `bsv-*` adapter (the @bsv/sdk choke point); the channels consume the
 * returned predicate, staying SDK-free.
 *
 * Cross-reference: core/protocol-types/src/signed-bundle/codec.ts (the preimage),
 * brain-rtc-signal-channel.ts / xmpp-signal-channel.ts (the inbound paths).
 */

import { PrivateKey, PublicKey, Signature, BigNumber, Hash } from '@bsv/sdk';
import { canonicalSignaturePreimage, type SignedBundle } from '@semantos/protocol-types/signed-bundle';

function bytesToHex(b: Uint8Array): string {
  let out = '';
  for (const x of b) out += x.toString(16).padStart(2, '0');
  return out;
}

function signDigestHex(b: SignedBundle): string {
  const digest = Hash.sha256(Array.from(canonicalSignaturePreimage(b))) as number[];
  return bytesToHex(Uint8Array.from(digest));
}

/**
 * Sign a brain SignedBundle's preimage with a secp256k1 key — the substrate-side
 * signer (byte-compatible with the cartridge signer + signed_bundle.zig). Fills
 * `signature` with the compact 64-byte (r‖s) hex. The cert pubkey in
 * `sender_cert_chain[0]` should be `privKey.toPublicKey()`.
 */
export function signBrainBundle(bundle: SignedBundle, privKey: PrivateKey): SignedBundle {
  const sig = privKey.sign(signDigestHex({ ...bundle, signature: '' }), 'hex', true);
  const r = Uint8Array.from((sig.r as BigNumber).toArray('be', 32));
  const s = Uint8Array.from((sig.s as BigNumber).toArray('be', 32));
  const compact = new Uint8Array(64);
  compact.set(r, 0);
  compact.set(s, 32);
  return { ...bundle, signature: bytesToHex(compact) };
}

/**
 * Verify a brain SignedBundle's ECDSA signature against a signer compressed
 * pubkey (66-hex). Returns false on any malformation rather than throwing.
 */
export function verifyBrainBundleSignature(bundle: SignedBundle, signerPubkeyHex: string): boolean {
  try {
    if (!/^[0-9a-fA-F]{128}$/.test(bundle.signature ?? '')) return false;
    const digest = Hash.sha256(Array.from(canonicalSignaturePreimage(bundle))) as number[];
    const digestHex = bytesToHex(Uint8Array.from(digest));
    const r = new BigNumber(bundle.signature.slice(0, 64), 16);
    const s = new BigNumber(bundle.signature.slice(64), 16);
    const pub = PublicKey.fromString(signerPubkeyHex);
    return pub.verify(digestHex, new Signature(r, s), 'hex');
  } catch {
    return false;
  }
}

/** A fresh signing identity (keeps @bsv/sdk out of callers/tests). */
export function randomBundleIdentity(): { privKey: PrivateKey; pubkeyHex: string } {
  const privKey = PrivateKey.fromRandom();
  return { privKey, pubkeyHex: privKey.toPublicKey().toString() };
}

/** Resolve a contact cert id → its known compressed pubkey hex, or undefined. */
export type ContactPubkeyResolver = (certId: string) => string | undefined;

/**
 * Build an inbound-bundle predicate that authenticates the signer against a
 * known-contacts registry. The leaf cert must be a known contact, its advertised
 * pubkey must match the one on file, and the signature must verify under it.
 * Wire it into the RTC signalling channels' `verifyInbound`.
 */
export function makeContactBundleVerifier(pubkeyOf: ContactPubkeyResolver): (bundle: SignedBundle) => boolean {
  return (bundle) => {
    const leaf = bundle.sender_cert_chain?.[0];
    if (!leaf?.cert_id || !leaf.pubkey) return false;
    const known = pubkeyOf(leaf.cert_id);
    if (!known) return false; // unknown signer
    if (known.toLowerCase() !== leaf.pubkey.toLowerCase()) return false; // cert↔pubkey mismatch
    return verifyBrainBundleSignature(bundle, leaf.pubkey);
  };
}

```
