---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/adapters/bsv-wallet-signer.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.044694+00:00
---

# runtime/session-protocol/src/adapters/bsv-wallet-signer.ts

```ts
/**
 * BRC-100 wallet-backed `Signer` — bundles are signed by the user's
 * actual wallet identity key via `wallet.createSignature`, closing
 * the last gap in the Slice 5 trust chain.
 *
 * Slices 5a–5g built the full federation pipeline (sign → verify →
 * trust → handoff-policy → overlay transport → real BSV wire) but
 * always signed with `StubSigner` — a deterministic local key. That
 * proves the wire but NOT the identity: a receiver can't know the
 * bundle came from the user's real wallet. 5h replaces the stub
 * with this adapter. Bundles now carry signatures derived from the
 * same key the wallet uses for createAction + identity attestation.
 *
 * Design — port-and-adapter, same shape as Slice 5f:
 *
 *   WalletSigningLike — minimal subset of BRC-100 needed for
 *     sign + identity-lookup. Any object with the right shape works
 *     (metanet-desktop's WalletClient, bsv-desktop, wallet-toolbox,
 *     a future Plexus SDK). Tests inject a fake backed by a local
 *     PrivateKey so signatures still verify against BsvSdkVerifier.
 *
 *   WalletClientSigner — implements the Signer interface from
 *     signer.ts. identity() caches the pubkey after the first call;
 *     sign() forwards bytes as `data` and returns the signature.
 *
 * Protocol/key/counterparty tuple is fixed at construction time and
 * used for BOTH getPublicKey AND createSignature — the wallet must
 * sign with the same key it reported for identity, else the
 * resulting bundle verifies against a different pubkey than it
 * claims. Default tuple:
 *   protocolID:   [1, 'semantos identity']
 *   keyID:        '1'
 *   counterparty: 'self'
 *
 * The wallet is responsible for hashing `data` with SHA-256 before
 * ECDSA — this matches BsvSdkVerifier's expectation (signer.ts
 * sha256s then verifies the DER signature). If a wallet deviates
 * from that, verification fails loudly at the bundle-verify site;
 * the signer trusts the wallet's hashing contract rather than
 * pre-hashing, so we don't ship a second SHA-256 implementation
 * (avoids drift). A hash-out-of-band variant via
 * `hashToDirectlySign` is available through the optional
 * `precomputeHash` config toggle for wallets that need it.
 *
 * This file is @bsv/sdk-free: `Identity.pubkey` is a raw Uint8Array,
 * hex parsing is a handful of lines, and signature / data are plain
 * byte arrays. G35A.12 holds without the `bsv-*` allowlist — the
 * prefix is there because the ADAPTER is BSV-specific (BRC-100),
 * not because we reach into @bsv/sdk.
 *
 * ── BRC-3 preimage: raw bytes, not SHA-256(bytes) ────────────
 *
 * BRC-3 §(Spec) and the public BRC-3 test vector at
 * https://bsv.brc.dev/wallet/0003 prove that `createSignature`
 * ECDSA-signs the `data` bytes DIRECTLY as a BigNumber — no
 * SHA-256 is applied first. (That's why the reference ProtoWallet
 * implementation's `Hash.sha256(args.data)` path produces a
 * DIFFERENT signature from what metanet-desktop and the BRC-3
 * vector show. The test-vector decoder in
 * `__tests__/bsv-wallet-signer-brc3-vector.test.ts` confirms the
 * ""raw msg (no hash)"" candidate is the one that verifies.)
 *
 * Since ECDSA takes a 256-bit integer, signing raw bytes longer
 * than 32 bytes truncates to the most-significant 256 bits — a
 * collision hazard for messages > 32 bytes. The signer therefore
 * **pre-hashes with SHA-256 locally** and passes the 32-byte
 * digest as `data`. The wallet signs those 32 bytes as a BigNumber
 * (= SHA-256(message)-as-BigNumber), and `BsvSdkVerifier`
 * independently computes SHA-256(bytes) then verifies — both sides
 * agree on the same 32-byte value.
 *
 * Net result: `WalletClientSigner` produces signatures verifiable
 * by `BsvSdkVerifier` end-to-end, over any-length payload, via a
 * real BRC-100 wallet. Cross-party federation works.
 */

import type { Signer } from "../signer.js";
import type { Identity } from "../types.js";

// ── Port ──────────────────────────────────────────────────────

/**
 * Minimal BRC-100 wallet surface the signer needs. The project's
 * `WalletClient` satisfies this shape; so does any equivalent shim.
 *
 * Using a structural interface instead of importing `WalletClient`
 * keeps this module free of `core/protocol-types` — the session-
 * protocol package already avoids upward dependencies.
 */
export interface WalletSigningLike {
  /**
   * Return the 33-byte compressed pubkey (hex) for a (protocolID,
   * keyID, counterparty) tuple.
   *
   * `forSelf` controls BRC-42's asymmetric derivation:
   *   - false/undefined: returns the pubkey the counterparty would
   *     use to talk to me (their derived-for-me pubkey).
   *   - true: returns MY derived pubkey — the one that pairs with
   *     `createSignature`'s private key for the same tuple. Needed
   *     when the caller wants to verify their OWN signatures against
   *     the returned pubkey.
   */
  getPublicKey(args: {
    protocolID: [number, string];
    keyID: string;
    counterparty: string;
    forSelf?: boolean;
  }): Promise<string>;
  /**
   * Sign `data` with the key derived from (protocolID, keyID,
   * counterparty). Wallets that hash data internally return a
   * signature over SHA-256(data); wallets that honour
   * `hashToDirectlySign` sign the hash directly.
   */
  createSignature(args: {
    protocolID: [number, string];
    keyID: string;
    counterparty: string;
    data?: number[];
    hashToDirectlySign?: number[];
  }): Promise<{ signature: number[] }>;
}

// ── Config ────────────────────────────────────────────────────

export interface WalletClientSignerConfig {
  /** BRC-100 wallet. Anything with a matching getPublicKey + createSignature. */
  wallet: WalletSigningLike;
  /**
   * BCA deriver — callback that turns a 33-byte compressed pubkey
   * into a BCA string. Same shape `BsvSdkSigner` uses; lets the
   * signer stay free of cell-engine / protocol-types coupling.
   */
  bcaDeriver: (pubkey: Uint8Array) => Promise<string>;
  /** BRC-100 protocolID tuple. Default: `[1, "semantos identity"]`. */
  protocolID?: [number, string];
  /** Key ID within the protocol. Default: `"1"`. */
  keyID?: string;
  /**
   * BRC-42 counterparty for key derivation. Choices:
   *   "anyone" — symmetric derivation. `derivePrivateKey(..., 'anyone')`
   *     and `derivePublicKey(..., 'anyone', forSelf?)` always produce
   *     a matching keypair, regardless of `forSelf`. Bundle signatures
   *     are verifiable by ANY party that knows the signer's identity
   *     key. **This is the default — cross-party bundle signing
   *     requires `'anyone'`.**
   *   "self" — asymmetric "only me" derivation. `forSelf: true` on
   *     getPublicKey is required to retrieve the pubkey that pairs
   *     with `createSignature`'s output. Used for data only the
   *     signer ever needs to verify (local-state signatures).
   *   <hex pubkey> — counterparty-specific derivation. Use when the
   *     bundle is addressed to a single known recipient identity key
   *     and you want signatures readable only by them.
   */
  counterparty?: string;
  /** Plexus cert SHA256 when available (stamped into Identity.certId). */
  certId?: string;
  /**
   * @deprecated No longer used — BRC-3 signs `data` bytes directly
   * as a BigNumber (no SHA-256 applied), so the signer always
   * pre-hashes locally and passes the 32-byte digest as `data`.
   * Setting this field has no effect.
   */
  precomputeHash?: boolean;
}

// ── Hex helpers (local, to keep this file @bsv/sdk-free) ──────

function hexToBytes(hex: string): Uint8Array {
  const clean = hex.startsWith("0x") ? hex.slice(2) : hex;
  if (clean.length % 2 !== 0) {
    throw new Error(`WalletClientSigner: hex string has odd length (got ${clean.length})`);
  }
  const out = new Uint8Array(clean.length / 2);
  for (let i = 0; i < clean.length; i += 2) {
    const byte = parseInt(clean.slice(i, i + 2), 16);
    if (Number.isNaN(byte)) {
      throw new Error(`WalletClientSigner: invalid hex at offset ${i}`);
    }
    out[i / 2] = byte;
  }
  return out;
}

async function sha256(bytes: Uint8Array): Promise<Uint8Array> {
  // Web Crypto is available in Node 20+, Bun, and modern browsers —
  // the runtime surface this module targets.
  const buf = await crypto.subtle.digest("SHA-256", bytes);
  return new Uint8Array(buf);
}

// ── Signer ────────────────────────────────────────────────────

/**
 * `Signer` backed by a BRC-100 wallet. One instance per identity
 * slot — construct with a fixed (protocolID, keyID, counterparty)
 * tuple and the wallet will derive the same key for both identity
 * reporting and signing.
 *
 * identity() caches after the first wallet round-trip; subsequent
 * calls are local. sign() is always a wallet call.
 */
export class WalletClientSigner implements Signer {
  private readonly wallet: WalletSigningLike;
  private readonly bcaDeriver: (pubkey: Uint8Array) => Promise<string>;
  private readonly protocolID: [number, string];
  private readonly keyID: string;
  private readonly counterparty: string;
  private readonly certId?: string;
  private readonly precomputeHash: boolean;
  private cached?: Identity;

  constructor(config: WalletClientSignerConfig) {
    this.wallet = config.wallet;
    this.bcaDeriver = config.bcaDeriver;
    this.protocolID = config.protocolID ?? [1, "semantos identity"];
    this.keyID = config.keyID ?? "1";
    this.counterparty = config.counterparty ?? "anyone";
    this.certId = config.certId;
    this.precomputeHash = config.precomputeHash ?? true;
  }

  async identity(): Promise<Identity> {
    if (this.cached) return this.cached;
    // `forSelf: true` is critical for `counterparty: 'self'` mode —
    // without it BRC-42 derives the counterparty-side pubkey, which
    // won't match `createSignature`'s private key. Harmless for
    // `'anyone'` (symmetric derivation ignores forSelf) and for hex
    // counterparties.
    const hex = await this.wallet.getPublicKey({
      protocolID: this.protocolID,
      keyID: this.keyID,
      counterparty: this.counterparty,
      forSelf: true,
    });
    const pubkey = hexToBytes(hex);
    if (pubkey.byteLength !== 33) {
      throw new Error(
        `WalletClientSigner: expected 33-byte compressed pubkey from wallet, got ${pubkey.byteLength} bytes`,
      );
    }
    const bca = await this.bcaDeriver(pubkey);
    this.cached = {
      bca,
      pubkey,
      ...(this.certId ? { certId: this.certId } : {}),
    };
    return this.cached;
  }

  async sign(bytes: Uint8Array): Promise<Uint8Array> {
    // BRC-3 signs `data` as a BigNumber directly — no SHA-256
    // applied wallet-side. Pre-hash locally so the wallet signs a
    // stable 32-byte value = SHA-256(bytes), which `BsvSdkVerifier`
    // reproduces independently.
    const hash = await sha256(bytes);
    const { signature } = await this.wallet.createSignature({
      protocolID: this.protocolID,
      keyID: this.keyID,
      counterparty: this.counterparty,
      data: Array.from(hash),
    });
    if (!signature || signature.length === 0) {
      throw new Error("WalletClientSigner: wallet returned empty signature");
    }
    return Uint8Array.from(signature);
  }
}

```
