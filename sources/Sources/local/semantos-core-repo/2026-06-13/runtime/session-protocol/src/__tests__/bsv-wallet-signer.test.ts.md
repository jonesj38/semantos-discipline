---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/__tests__/bsv-wallet-signer.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.045856+00:00
---

# runtime/session-protocol/src/__tests__/bsv-wallet-signer.test.ts

```ts
/**
 * Unit tests — `WalletClientSigner` (Slice 5h).
 *
 * Uses a fake BRC-100 wallet backed by a real @bsv/sdk PrivateKey so
 * the signatures the signer emits can be verified end-to-end by
 * BsvSdkVerifier (same verifier bundle-envelope.ts uses). That
 * proves the signer meets the `Signer` contract — not just
 * mechanically, but cryptographically: a bundle signed by
 * WalletClientSigner round-trips through signBundle →
 * verifyBundle without contract drift.
 *
 * Gates:
 *   T1 identity() returns the wallet's pubkey + a BCA from the
 *      injected deriver; certId passes through when configured
 *   T2 identity() caches — two calls hit the wallet once
 *   T3 sign() → verify() round-trip via the same pubkey
 *   T4 signBundle / verifyBundle end-to-end with a WalletClientSigner
 *   T5 signBundle + precomputeHash mode round-trips too (wallets
 *      that want the hash pre-computed stay verifiable)
 *   T6 wallet returns an empty signature → sign throws
 *   T7 wallet returns a short pubkey → identity throws with a
 *      recognisable message
 *   T8 custom protocolID + counterparty pass through to the wallet
 */

import { describe, test, expect } from "bun:test";
import { PrivateKey, PublicKey, Signature, Hash } from "@bsv/sdk";

import {
  WalletClientSigner,
  type WalletSigningLike,
} from "../adapters/bsv-wallet-signer.js";
import { BsvSdkVerifier } from "../signer.js";
import { signBundle, verifyBundle } from "../bundle-envelope.js";

// ── Fake BRC-100 wallet ─────────────────────────────────────────

/**
 * Fake wallet that signs with a fixed local PrivateKey, records all
 * calls, and returns valid ECDSA signatures verifiable with the
 * corresponding PublicKey. Mimics metanet-desktop's contract
 * closely enough for the signer to round-trip.
 */
function makeFakeWallet(opts?: {
  privateKeyHex?: string;
  pubkeyOverride?: string;
  signatureOverride?: number[];
}): WalletSigningLike & {
  calls: {
    getPublicKey: Parameters<WalletSigningLike["getPublicKey"]>[0][];
    createSignature: Parameters<WalletSigningLike["createSignature"]>[0][];
  };
  publicKeyHex: string;
} {
  const pk = PrivateKey.fromHex(opts?.privateKeyHex ?? "aa".repeat(32));
  const pub = pk.toPublicKey();
  const pubHex = pub.toString();

  const calls = {
    getPublicKey: [] as any[],
    createSignature: [] as any[],
  };

  return {
    calls,
    publicKeyHex: pubHex,
    async getPublicKey(args) {
      calls.getPublicKey.push(args);
      return opts?.pubkeyOverride ?? pubHex;
    },
    async createSignature(args) {
      calls.createSignature.push(args);
      if (opts?.signatureOverride) {
        return { signature: opts.signatureOverride };
      }
      // BRC-3 semantics (per the published test vector): sign
      // `data` bytes DIRECTLY as a BigNumber — no SHA-256 applied.
      // `hashToDirectlySign` bypasses this, signing the supplied
      // hash-bytes as a BigNumber just the same.
      let bytes: number[];
      if (args.hashToDirectlySign) {
        bytes = args.hashToDirectlySign;
      } else if (args.data) {
        bytes = args.data;
      } else {
        throw new Error("fake wallet: createSignature needs data or hashToDirectlySign");
      }
      // Convert bytes to hex — ECDSA.sign interprets hex as a
      // big-endian BigNumber, matching BRC-3's raw-bytes approach.
      const bytesHex = bytes
        .map((b) => b.toString(16).padStart(2, "0"))
        .join("");
      const sig: Signature = pk.sign(bytesHex, "hex", true);
      return { signature: sig.toDER() as number[] };
    },
  };
}

async function stubBcaDeriver(pubkey: Uint8Array): Promise<string> {
  const tail = Array.from(pubkey.slice(-2))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
  return `2602:f9f8::${tail}`;
}

// ── Gates ───────────────────────────────────────────────────────

describe("Slice 5h · WalletClientSigner", () => {
  test("T1 identity() returns wallet pubkey + derived BCA + certId", async () => {
    const wallet = makeFakeWallet();
    const signer = new WalletClientSigner({
      wallet,
      bcaDeriver: stubBcaDeriver,
      certId: "cert-xyz",
    });

    const id = await signer.identity();
    expect(id.pubkey.byteLength).toBe(33);
    const hex = Array.from(id.pubkey)
      .map((b) => b.toString(16).padStart(2, "0"))
      .join("");
    expect(hex).toBe(wallet.publicKeyHex);
    expect(id.bca).toMatch(/^2602:f9f8::[0-9a-f]{4}$/);
    expect(id.certId).toBe("cert-xyz");
  });

  test("T2 identity() caches across calls", async () => {
    const wallet = makeFakeWallet();
    const signer = new WalletClientSigner({ wallet, bcaDeriver: stubBcaDeriver });

    const a = await signer.identity();
    const b = await signer.identity();
    expect(b).toBe(a);
    expect(wallet.calls.getPublicKey).toHaveLength(1);
  });

  test("T3 sign() produces a DER signature verifiable with BsvSdkVerifier", async () => {
    const wallet = makeFakeWallet();
    const signer = new WalletClientSigner({ wallet, bcaDeriver: stubBcaDeriver });
    const verifier = new BsvSdkVerifier();

    const msg = new TextEncoder().encode("hello from slice 5h");
    const sig = await signer.sign(msg);
    const id = await signer.identity();

    const ok = await verifier.verify(id.pubkey, msg, sig);
    expect(ok).toBe(true);
  });

  test("T4 signBundle + verifyBundle round-trip via WalletClientSigner", async () => {
    const wallet = makeFakeWallet();
    const signer = new WalletClientSigner({ wallet, bcaDeriver: stubBcaDeriver });
    const verifier = new BsvSdkVerifier();

    const bundle = await signBundle(
      { op: "intent", id: 42 },
      signer,
      {
        recipient: { certId: "rea-1" },
        now: () => "2026-04-20T00:00:00.000Z",
      },
    );

    const result = await verifyBundle(bundle, verifier);
    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.payload).toEqual({ op: "intent", id: 42 });
      expect(result.signer.pubkeyHex).toBe(wallet.publicKeyHex);
    }
  });

  test("T5 sign() pre-hashes and sends the 32-byte digest as `data`", async () => {
    // BRC-3 signs `data` as a BigNumber directly. Our signer
    // pre-hashes so the wallet signs SHA-256(bytes) — a stable
    // 32-byte value that `BsvSdkVerifier` (which also SHA-256s
    // internally) agrees with.
    const wallet = makeFakeWallet();
    const signer = new WalletClientSigner({ wallet, bcaDeriver: stubBcaDeriver });

    const msg = new TextEncoder().encode("hello");
    await signer.sign(msg);

    const call = wallet.calls.createSignature.at(-1)!;
    expect(call.data).toBeDefined();
    expect(call.data!.length).toBe(32); // SHA-256 digest
    expect(call.hashToDirectlySign).toBeUndefined();
  });

  test("T6 empty signature → sign throws", async () => {
    const wallet = makeFakeWallet({ signatureOverride: [] });
    const signer = new WalletClientSigner({ wallet, bcaDeriver: stubBcaDeriver });
    await expect(signer.sign(new Uint8Array([1, 2, 3]))).rejects.toThrow(
      /wallet returned empty signature/,
    );
  });

  test("T7 short pubkey → identity throws with readable message", async () => {
    const wallet = makeFakeWallet({ pubkeyOverride: "aabb" /* 2 bytes */ });
    const signer = new WalletClientSigner({ wallet, bcaDeriver: stubBcaDeriver });
    await expect(signer.identity()).rejects.toThrow(
      /33-byte compressed pubkey.*got 2 bytes/,
    );
  });

  test("T8 custom protocolID + counterparty pass through to the wallet", async () => {
    const wallet = makeFakeWallet();
    const signer = new WalletClientSigner({
      wallet,
      bcaDeriver: stubBcaDeriver,
      protocolID: [2, "semantos bundle"],
      keyID: "bundle-42",
      counterparty: "anyone",
    });

    await signer.identity();
    await signer.sign(new Uint8Array([1, 2, 3]));

    expect(wallet.calls.getPublicKey[0]).toEqual({
      protocolID: [2, "semantos bundle"],
      keyID: "bundle-42",
      counterparty: "anyone",
      // `forSelf: true` is always passed so `counterparty: "self"`
      // mode picks up the MY-side derived pubkey. Harmless here.
      forSelf: true,
    });
    expect(wallet.calls.createSignature[0].protocolID).toEqual([2, "semantos bundle"]);
    expect(wallet.calls.createSignature[0].keyID).toBe("bundle-42");
    expect(wallet.calls.createSignature[0].counterparty).toBe("anyone");
  });
});

```
