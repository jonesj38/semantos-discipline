---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/swarm/bsv-access-grant-signer.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.057803+00:00
---

# runtime/session-protocol/src/swarm/bsv-access-grant-signer.ts

```ts
/**
 * bsv-access-grant-signer — the grantee's signing leg for DAM access grants
 * (the real `AccessGrantProver`, vs #987's test stub).
 *
 * A grantee proves access by signing the canonical access-challenge digest with
 * the private key whose pubkey the grant was issued to. The brain's 2-PDA
 * verifies it via `host.checksig` (BSVZ-native secp256k1), which expects a
 * **DER ECDSA signature over the raw 32-byte digest, with the BSV sighash-flag
 * byte (0x41) appended** (`core/cell-engine/src/host.zig` checksig; the flag is
 * stripped before DER decode).
 *
 * THE SUBTLETY (DAM handoff gotcha #3): `@bsv/sdk`'s `PrivateKey.sign(msg)`
 * sha256-hashes `msg` before ECDSA — but the brain verifies over the digest
 * DIRECTLY (`verifyDigest256RelaxedSec1`). So we must NOT use `PrivateKey.sign`;
 * we sign the digest as a raw hash via the low-level `ECDSA.sign(msgHash, key)`,
 * which does no extra hashing.
 *
 * This is a `bsv-*` adapter (the @bsv/sdk choke-point — see
 * tests/gates/phase35a-gate.test.ts G35A.12); the rest of the swarm stays
 * SDK-free and consumes the `AccessGrantProver` port.
 *
 * Cross-reference: core/protocol-types/src/bsv/access-grant.ts (the digest),
 * access-grant-serve.ts (the prover port), brain-access-grant-verifier.ts (the
 * verifying counterpart).
 */

import { PrivateKey, BigNumber, ECDSA } from '@bsv/sdk';
import { toHex } from '@semantos/protocol-types';
import { accessChallengeDigest, SIGHASH_ALL_FORKID } from '@semantos/protocol-types/bsv/access-grant';
import type { AccessGrantProver } from './access-grant-serve';

/** The 33-byte compressed pubkey of a private key (the grantee identity). */
export function granteePubkeyOf(privKey: PrivateKey): Uint8Array {
  return Uint8Array.from(privKey.toPublicKey().encode(true) as number[]);
}

/**
 * Sign the access challenge for a grant: DER ECDSA over the raw
 * `accessChallengeDigest(grantHash, granteePubkey)`, with the 0x41 sighash flag
 * appended. Returns the bytes the `verify.intent` carries.
 */
export function signAccessChallenge(
  privKey: PrivateKey,
  grantHash: Uint8Array,
  granteePubkey: Uint8Array,
): Uint8Array {
  const digest = accessChallengeDigest(grantHash, granteePubkey);
  // Low-level sign — NO extra hashing (PrivateKey.sign would sha256 first).
  const sig = ECDSA.sign(new BigNumber(toHex(digest), 16), privKey, true);
  const der = Uint8Array.from(sig.toDER() as number[]);
  const out = new Uint8Array(der.length + 1);
  out.set(der, 0);
  out[der.length] = SIGHASH_ALL_FORKID; // 0x41 — BSV sighash convention
  return out;
}

/**
 * A real `AccessGrantProver` backed by a BSV private key: it signs the challenge
 * for any grant issued to its pubkey. Wire this into a leecher's pay policy via
 * `makeGrantPayPolicy`.
 */
export function bsvAccessGrantProver(privKey: PrivateKey): AccessGrantProver {
  const granteePubkey = granteePubkeyOf(privKey);
  return {
    async proveAccess(grantHash) {
      return { grantHash, signature: signAccessChallenge(privKey, grantHash, granteePubkey) };
    },
  };
}

/**
 * Generate a fresh grantee identity + its prover. Keeps @bsv/sdk out of
 * callers/tests that only need a key and the prover (e.g. integration tests, a
 * node provisioning a new contact's edge key).
 */
export function randomGranteeProver(): { prover: AccessGrantProver; granteePubkey: Uint8Array } {
  const priv = PrivateKey.fromRandom();
  return { prover: bsvAccessGrantProver(priv), granteePubkey: granteePubkeyOf(priv) };
}

```
