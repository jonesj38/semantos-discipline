---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/signed-bundle/codec.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.897440+00:00
---

# core/protocol-types/src/signed-bundle/codec.ts

```ts
/**
 * SignedBundle canonical codec — the byte-exact signature preimage.
 *
 * Dependency-free home (substrate) for the canonical-JSON encoding the brain's
 * SignedBundle signature is computed over. Byte-identical to the Zig
 * `signed_bundle.canonicalSignaturePreimage` and the TS signer
 * (cartridges/oddjobz/brain/tools/send-bundle.ts `encodeBundle`) — a signature
 * produced by either verifies here, so recipients (e.g. the RTC signalling
 * channels) can authenticate inbound bundles in TS without the cartridge or the
 * brain.
 *
 * The preimage is `SIG_DOMAIN ‖ canonicalJson(bundle minus signature)` — the
 * domain prefix prevents cross-protocol signature reuse. Key order mirrors
 * Zig's `writeBundleJson`: payload, payload_type, recipient_cert_id,
 * sender_cert_chain, [signature], signature_metadata, v.
 *
 * Cross-reference: runtime/semantos-brain/src/signed_bundle.zig,
 * cartridges/oddjobz/brain/tools/send-bundle.ts, ./types.ts.
 */

import { SIG_DOMAIN, type CertRef, type SignatureMetadata, type SignedBundle } from './types';

function jsonStr(s: string): string {
  return JSON.stringify(s);
}

function encodeCertRef(c: CertRef): string {
  // Key order: cert_id, context_tag, parent_cert_id, pubkey.
  return `{${[
    `${jsonStr('cert_id')}:${jsonStr(c.cert_id)}`,
    `${jsonStr('context_tag')}:${c.context_tag}`,
    `${jsonStr('parent_cert_id')}:${c.parent_cert_id === null ? 'null' : jsonStr(c.parent_cert_id)}`,
    `${jsonStr('pubkey')}:${jsonStr(c.pubkey)}`,
  ].join(',')}}`;
}

function encodeChain(chain: CertRef[]): string {
  return `[${chain.map(encodeCertRef).join(',')}]`;
}

function encodeSignatureMetadata(m: SignatureMetadata): string {
  return `{${[
    `${jsonStr('algorithm')}:${jsonStr(m.algorithm)}`,
    `${jsonStr('nonce_hex')}:${jsonStr(m.nonce_hex)}`,
    `${jsonStr('timestamp_unix')}:${m.timestamp_unix}`,
  ].join(',')}}`;
}

/**
 * The canonical JSON byte form of a bundle. Pass `includeSignature = false` for
 * the signature preimage (the signature field is excluded from its own input).
 */
export function encodeBundle(b: SignedBundle, includeSignature: boolean): string {
  const parts: string[] = [];
  parts.push(`${jsonStr('payload')}:${jsonStr(b.payload)}`);
  parts.push(`${jsonStr('payload_type')}:${jsonStr(b.payload_type)}`);
  parts.push(`${jsonStr('recipient_cert_id')}:${b.recipient_cert_id === null ? 'null' : jsonStr(b.recipient_cert_id)}`);
  parts.push(`${jsonStr('sender_cert_chain')}:${encodeChain(b.sender_cert_chain)}`);
  if (includeSignature) parts.push(`${jsonStr('signature')}:${jsonStr(b.signature)}`);
  parts.push(`${jsonStr('signature_metadata')}:${encodeSignatureMetadata(b.signature_metadata)}`);
  parts.push(`${jsonStr('v')}:${b.v}`);
  return `{${parts.join(',')}}`;
}

/** The canonical signature preimage bytes: `SIG_DOMAIN ‖ canonicalJson(minus sig)`. */
export function canonicalSignaturePreimage(b: SignedBundle): Uint8Array {
  return new TextEncoder().encode(SIG_DOMAIN + encodeBundle(b, false));
}

```
