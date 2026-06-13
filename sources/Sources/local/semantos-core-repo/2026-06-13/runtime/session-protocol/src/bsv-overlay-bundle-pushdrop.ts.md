---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/bsv-overlay-bundle-pushdrop.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.036578+00:00
---

# runtime/session-protocol/src/bsv-overlay-bundle-pushdrop.ts

```ts
/**
 * PushDrop codec for signed-bundle envelopes on the BSV overlay.
 *
 * Slice 5e shipped the `OverlayBundleClient` interface with a loopback
 * implementation. Slice 5f lands the real BSV-backed wire format: a
 * BRC-48 PushDrop output that carries:
 *
 *   [0] magic:           "semantos-bundle-v1" (UTF-8 bytes)
 *   [1] recipient certId: UTF-8 bytes (indexable by the lookup service)
 *   [2] bundle JSON:      canonicalised SignedBundle<T> as UTF-8 bytes
 *   <pubkey>
 *   OP_CHECKSIG
 *
 * Three data pushes + one P2PK lock = the standard PushDrop skeleton
 * matching @semantos/protocol-types/src/cell-token.ts. For three data
 * pushes we emit `OP_2DROP OP_DROP` to clear the stack before the
 * CHECKSIG.
 *
 * The magic field + the recipient field are *redundant* with the
 * bundle JSON (the envelope already carries signer + recipient). They
 * exist so overlay indexers can filter without parsing JSON per
 * output. After decode the bundle JSON is the source of truth — any
 * mismatch between the outer fields and the bundle's signed preimage
 * is detected at verifyBundle time downstream.
 *
 * Why not `PushDrop.lock()` from @bsv/sdk? Because that helper uses a
 * `WalletInterface` to sign and attach a signature inside the output
 * script. We don't need an embedded signature here — the bundle is
 * already signed at the envelope layer (Slice 5a). Raw
 * LockingScript construction keeps the output cheap and portable
 * across any tx builder.
 */

import {
  LockingScript,
  OP,
  PublicKey,
  PushDrop,
} from "@bsv/sdk";

import type { SignedBundle } from "./bundle-envelope.js";

/** Protocol magic tag for field[0]. Bump the suffix on breaking changes. */
export const BUNDLE_PUSHDROP_MAGIC = "semantos-bundle-v1";

/** Result of extracting a bundle envelope from a PushDrop output. */
export interface DecodedBundleOutput<T = unknown> {
  /** Protocol magic string (always `BUNDLE_PUSHDROP_MAGIC` for a success). */
  magic: string;
  /** Recipient certId as encoded in the indexable field. */
  recipientCertId: string;
  /** The SignedBundle recovered from the payload field. */
  bundle: SignedBundle<T>;
  /** Sender public key from the P2PK lock. */
  senderPubKey: PublicKey;
}

// ── Low-level push encoding (mirrors cell-token.ts) ───────────

/** Minimally encode a data push as a ScriptChunk. */
function pushData(data: number[]): { op: number; data?: number[] } {
  if (data.length === 0) return { op: 0 };
  if (data.length === 1 && data[0] === 0) return { op: 0 };
  if (data.length === 1 && data[0] > 0 && data[0] <= 16) return { op: 0x50 + data[0] };
  if (data.length === 1 && data[0] === 0x81) return { op: 0x4f };
  if (data.length <= 75) return { op: data.length, data };
  if (data.length <= 255) return { op: 0x4c, data };
  if (data.length <= 65535) return { op: 0x4d, data };
  return { op: 0x4e, data };
}

function utf8Bytes(s: string): number[] {
  return Array.from(new TextEncoder().encode(s));
}

// ── Encode ────────────────────────────────────────────────────

/**
 * Build the LockingScript for a signed-bundle PushDrop output.
 *
 * The script is pure — no wallet calls, no signing. Call this once
 * with the bundle bytes + sender pubkey; the resulting script is the
 * `lockingScript` passed into `createAction` or a raw `Transaction`.
 *
 * Throws if the bundle is unaddressed — unaddressed bundles can't be
 * routed by `ls_semantos_bundles_by_recipient`, so sending them over
 * the overlay is a bug.
 */
export function encodeBundlePushDrop<T>(
  bundle: SignedBundle<T>,
  senderPubKey: PublicKey,
): LockingScript {
  const recipientCertId = bundle.recipient?.certId;
  if (!recipientCertId) {
    throw new Error(
      "bsv-overlay-bundle-pushdrop: bundle has no recipient.certId — overlay routing requires an addressed bundle",
    );
  }

  const bundleJson = JSON.stringify(bundle);

  const magicField = utf8Bytes(BUNDLE_PUSHDROP_MAGIC);
  const recipientField = utf8Bytes(recipientCertId);
  const payloadField = utf8Bytes(bundleJson);
  const pubkeyBytes = Array.from(senderPubKey.encode(true) as number[]);

  // Stack at spend time (lockPosition = 'after'):
  //   unlocking script: [sig]
  //   after pushes:     [sig, magic, recipient, payload]
  //   OP_2DROP:         [sig, magic]
  //   OP_DROP:          [sig]
  //   PUSH pubkey:      [sig, pubkey]
  //   OP_CHECKSIG:      [true/false]
  return new LockingScript([
    pushData(magicField),
    pushData(recipientField),
    pushData(payloadField),
    { op: OP.OP_2DROP },
    { op: OP.OP_DROP },
    pushData(pubkeyBytes),
    { op: OP.OP_CHECKSIG },
  ]);
}

// ── Decode ────────────────────────────────────────────────────

/**
 * Decode a PushDrop output back into a bundle envelope. Returns
 * `null` for any shape-level failure (malformed fields, wrong magic,
 * bad JSON) — callers treat null as "not a semantos bundle output"
 * and skip it rather than throwing mid-stream.
 *
 * The returned envelope is *unverified* — the receiver still needs
 * to run `verifyBundleWithTrust` (Slice 5b+5c) before touching state.
 * This function only guarantees shape.
 */
export function decodeBundlePushDrop<T = unknown>(
  script: LockingScript,
): DecodedBundleOutput<T> | null {
  let decoded: { fields: number[][]; lockingPublicKey: PublicKey };
  try {
    decoded = PushDrop.decode(script, "after");
  } catch {
    return null;
  }

  const { fields, lockingPublicKey } = decoded;
  if (fields.length < 3) return null;

  let magic: string;
  let recipientCertId: string;
  let bundleJson: string;
  try {
    magic = new TextDecoder().decode(new Uint8Array(fields[0]));
    recipientCertId = new TextDecoder().decode(new Uint8Array(fields[1]));
    bundleJson = new TextDecoder().decode(new Uint8Array(fields[2]));
  } catch {
    return null;
  }

  if (magic !== BUNDLE_PUSHDROP_MAGIC) return null;

  let bundle: SignedBundle<T>;
  try {
    bundle = JSON.parse(bundleJson) as SignedBundle<T>;
  } catch {
    return null;
  }

  // Shape sanity — don't verify the signature here (that's the trust
  // layer's job), but reject envelopes whose outer recipient field
  // disagrees with the signed inner one. The signed preimage wins;
  // the outer field is only for overlay indexing.
  if (bundle.recipient?.certId !== recipientCertId) return null;

  return {
    magic,
    recipientCertId,
    bundle,
    senderPubKey: lockingPublicKey,
  };
}

```
