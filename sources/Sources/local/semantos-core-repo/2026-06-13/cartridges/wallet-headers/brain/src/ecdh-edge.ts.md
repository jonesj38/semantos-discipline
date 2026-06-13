---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/wallet-headers/brain/src/ecdh-edge.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.655676+00:00
---

# cartridges/wallet-headers/brain/src/ecdh-edge.ts

```ts
// ecdh-edge.ts — Phase C: ECDH shared secret derivation for an edge (never stored)

import * as secp from '@noble/secp256k1';
import { hmac } from '@noble/hashes/hmac';
import { sha256 } from '@noble/hashes/sha2';
import { deriveLeafSync } from './host';
import { type PeerInvite } from './peer-invite';
import { saveEdgeEnvelope, type LocalEdgeEnvelope } from './local-edge-store';

// Wire sync HMAC backend for @noble/secp256k1 (required for deriveLeafSync)
secp.etc.hmacSha256Sync = (key: Uint8Array, ...msgs: Uint8Array[]): Uint8Array =>
  hmac(sha256, key, secp.etc.concatBytes(...msgs));

// protocolHash = SHA256("BRC-42-edge-creation")[0:16]
const PROTOCOL_HASH_EDGE_CREATION: Uint8Array = (() => {
  const full = sha256(new TextEncoder().encode('BRC-42-edge-creation'));
  return full.slice(0, 16);
})();

function bytesToHex(b: Uint8Array): string {
  return Array.from(b).map(x => x.toString(16).padStart(2, '0')).join('');
}

function hexToBytes(hex: string): Uint8Array {
  if (hex.length % 2 !== 0) throw new Error('odd-length hex');
  const out = new Uint8Array(hex.length / 2);
  for (let i = 0; i < out.length; i++) {
    out[i] = parseInt(hex.slice(i * 2, i * 2 + 2), 16);
  }
  return out;
}

/**
 * Derive the ECDH shared secret for an edge at a given signing key index.
 * Uses BRC-42: deriveLeafSync(mySk, protocolHash_EDGE_CREATION, theirPk, index)
 * protocolHash = SHA256("BRC-42-edge-creation")[0:16]
 * Returns 32-byte shared secret (SHA256 of the secp point), or null on failure.
 */
export function deriveEdgeSharedSecret(
  myIdentitySk: Uint8Array,
  theirPublicKey: Uint8Array,
  signingKeyIndex: number,
): Uint8Array | null {
  const leafSk = deriveLeafSync(
    myIdentitySk,
    PROTOCOL_HASH_EDGE_CREATION,
    theirPublicKey,
    BigInt(signingKeyIndex),
  );
  if (!leafSk) return null;

  // Compute ECDH point: leafSk * theirPublicKey (compressed 33 bytes)
  let sharedPoint: Uint8Array;
  try {
    sharedPoint = secp.getSharedSecret(leafSk, theirPublicKey, true); // 33-byte compressed
  } catch {
    return null;
  }

  // Return SHA256 of the shared point as 32-byte secret
  return sha256(sharedPoint);
}

/**
 * Build a BRC-69-style backup recipe:
 * HMAC-SHA256(sharedSecret, "edge-backup-recipe" || edgeId_bytes)
 * This proves the edge existed without revealing the shared secret.
 */
export function buildEdgeBackupRecipe(
  myIdentitySk: Uint8Array,
  theirPublicKey: Uint8Array,
  signingKeyIndex: number,
  edgeId: string,  // hex string used as input bytes
): string | null {
  const sharedSecret = deriveEdgeSharedSecret(myIdentitySk, theirPublicKey, signingKeyIndex);
  if (!sharedSecret) return null;

  // HMAC-SHA256(sharedSecret, "edge-backup-recipe" || edgeId_bytes)
  const prefix = new TextEncoder().encode('edge-backup-recipe');
  let edgeIdBytes: Uint8Array;
  try {
    edgeIdBytes = hexToBytes(edgeId);
  } catch {
    // If edgeId isn't valid hex, use UTF-8 bytes instead
    edgeIdBytes = new TextEncoder().encode(edgeId);
  }

  const msg = new Uint8Array(prefix.length + edgeIdBytes.length);
  msg.set(prefix, 0);
  msg.set(edgeIdBytes, prefix.length);

  const recipe = hmac(sha256, sharedSecret, msg);
  return bytesToHex(recipe);
}

/**
 * Accept an incoming invite: create a new edge, compute recipe, store locally.
 * Returns the LocalEdgeEnvelope or null on failure.
 */
export function acceptInvite(
  invite: PeerInvite,
  myIdentity: { certId: string; sk: Uint8Array; pk: Uint8Array },
  signingKeyIndex: number,
): LocalEdgeEnvelope | null {
  let theirPk: Uint8Array;
  try {
    theirPk = hexToBytes(invite.publicKey);
  } catch {
    return null;
  }

  // Generate a deterministic edge ID: SHA256(myCertId || theirCertId || nonce)[0:32] as hex
  const edgeIdInput = new TextEncoder().encode(
    myIdentity.certId + invite.certId + invite.nonce,
  );
  const edgeIdBytes = sha256(edgeIdInput);
  const edgeId = bytesToHex(edgeIdBytes);

  const backupRecipe = buildEdgeBackupRecipe(
    myIdentity.sk,
    theirPk,
    signingKeyIndex,
    edgeId,
  );
  if (!backupRecipe) return null;

  const envelope: LocalEdgeEnvelope = {
    edgeId,
    myCertId: myIdentity.certId,
    theirCertId: invite.certId,
    theirPublicKey: invite.publicKey,
    signingKeyIndex,
    edgeType: 'MESSAGING',
    backupRecipe,
    createdAt: Date.now(),
  };

  saveEdgeEnvelope(envelope);
  return envelope;
}

```
