---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/signed-bundle/types.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.897174+00:00
---

# core/protocol-types/src/signed-bundle/types.ts

```ts
/**
 * SignedBundle wire types — substrate home.
 *
 * These interfaces are the canonical, dependency-free wire shape for the
 * brain-to-brain SignedBundle (mesh transport, D-W1).  They are extracted here
 * (the home that `cartridges/oddjobz/brain/tools/send-bundle.ts:37` already
 * names as the eventual destination) so that lower-level substrate code — e.g.
 * the XMPP identity-transport binding in `../xmpp/` — can depend on the wire
 * shape WITHOUT pulling in `@bsv/sdk` (the encoder/signer in send-bundle.ts
 * imports the SDK; these types do not).
 *
 * The authoritative codec + signer still live in send-bundle.ts (TS) and
 * `runtime/semantos-brain/src/signed_bundle.zig` (Zig, the receive seam).
 * When send-bundle.ts relocates to `./send.ts`, it should re-export these.
 *
 * Cross-reference: docs/design/SRS-XMPP-IDENTITY-TRANSPORT.md §3.
 */

export const ENVELOPE_VERSION = 1 as const;
export const SIG_DOMAIN = 'BRAIN-SIGNED-BUNDLE-v1';
export const ALGORITHM = 'ecdsa-secp256k1-sha256';

export interface CertRef {
  /** 32-hex-char cert id (matches identity_certs.certIdFromPubkey). */
  cert_id: string;
  /** 33-byte compressed-SEC1 pubkey, hex-encoded (66 chars). */
  pubkey: string;
  /** 0-255; carpenter=0x10, musician=0x11, 0 for the root. */
  context_tag: number;
  /** 32-hex-char parent cert id; null only for the root. */
  parent_cert_id: string | null;
}

export interface SignatureMetadata {
  algorithm: typeof ALGORITHM;
  /** 64-hex-char nonce (32 random bytes). */
  nonce_hex: string;
  /** Unix seconds. */
  timestamp_unix: number;
}

export interface SignedBundle {
  v: typeof ENVELOPE_VERSION;
  /** Leaf-first; root last.  Length 1..16. */
  sender_cert_chain: CertRef[];
  /** Brain's root cert id; null = broadcast (rejected on receive). */
  recipient_cert_id: string | null;
  /** "dispatch.request" for a wire.Request envelope, e.g. */
  payload_type: string;
  /** Opaque payload; typically a wire.Request JSON string. */
  payload: string;
  /** 128-hex-char compact (r||s) ECDSA signature. */
  signature: string;
  signature_metadata: SignatureMetadata;
}

```
