---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/__tests__/bsv-wallet-signer-brc3-vector.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.046151+00:00
---

# runtime/session-protocol/src/__tests__/bsv-wallet-signer-brc3-vector.test.ts

```ts
/**
 * BRC-3 test vector decoder — reverse-engineer the exact preimage
 * format used by BRC-3 / BRC-100 `createSignature`.
 *
 * The BRC-3 spec is silent about what bytes get hashed before ECDSA,
 * but provides a concrete test vector with all the inputs required
 * to reproduce the signature. By trying every plausible preimage
 * construction and checking which one verifies against the vector's
 * signature, we learn the authoritative format — and then
 * `WalletClientSigner` / `BsvSdkVerifier` can be aligned with it.
 *
 * Test vector (per https://bsv.brc.dev/wallet/0003 as of 2026-04):
 *
 *   message:      "BRC-3 Compliance Validated!"
 *   counterparty: "anyone"  (= PrivateKey(1), pubkey = G)
 *   signer pub:   0294c479f762f6baa97fbcd4393564c1d7bd8336ebd15928135bbcf575cd1a71a1
 *   securityLvl:  2
 *   protocolName: "BRC3 Test"
 *   keyID:        "42"
 *   signature:    DER [48, 68, 2, 32, 43, 34, 58, 156, 219, 32, 50,
 *                      70, 29, 240, 155, 137, 88, 60, 200, 95, 243,
 *                      198, 201, 21, 56, 82, 141, 112, 69, 196, 170,
 *                      73, 156, 6, 44, 48, 2, 32, 118, 125, 254, 201,
 *                      44, 87, 177, 170, 93, 11, 193, 134, 18, 70, 9,
 *                      31, 234, 27, 170, 177, 54, 96, 181, 140, 166,
 *                      196, 144, 14, 230, 118, 106, 105]
 *
 * The test below derives the expected pubkey from the signer's
 * identity via BRC-42 (KeyDeriver('anyone').derivePublicKey(signerPub))
 * and then tries a sweep of preimage candidates against the vector
 * signature. The candidate that verifies reveals the authoritative
 * BRC-3 preimage construction.
 *
 * No wallet I/O — pure computation from the published vector. Safe
 * to run in CI.
 */

import { describe, test, expect } from "bun:test";
import { KeyDeriver, PublicKey, Signature } from "@bsv/sdk";

const VECTOR = {
  message: "BRC-3 Compliance Validated!",
  signerPubHex: "0294c479f762f6baa97fbcd4393564c1d7bd8336ebd15928135bbcf575cd1a71a1",
  securityLevel: 2,
  protocolName: "BRC3 Test",
  keyID: "42",
  signatureDer: [
    48, 68, 2, 32, 43, 34, 58, 156, 219, 32, 50, 70, 29, 240, 155,
    137, 88, 60, 200, 95, 243, 198, 201, 21, 56, 82, 141, 112, 69,
    196, 170, 73, 156, 6, 44, 48, 2, 32, 118, 125, 254, 201, 44, 87,
    177, 170, 93, 11, 193, 134, 18, 70, 9, 31, 234, 27, 170, 177, 54,
    96, 181, 140, 166, 196, 144, 14, 230, 118, 106, 105,
  ],
};

async function digest(bytes: Uint8Array): Promise<Uint8Array> {
  return new Uint8Array(await crypto.subtle.digest("SHA-256", bytes));
}

function bytesToHex(bytes: Uint8Array): string {
  return Array.from(bytes)
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

function concat(...chunks: Uint8Array[]): Uint8Array {
  const total = chunks.reduce((n, c) => n + c.length, 0);
  const out = new Uint8Array(total);
  let off = 0;
  for (const c of chunks) {
    out.set(c, off);
    off += c.length;
  }
  return out;
}

function enc(s: string): Uint8Array {
  return new TextEncoder().encode(s);
}

describe("BRC-3 test vector preimage decoder", () => {
  test("sweep — find the preimage format that verifies the published signature", async () => {
    // Expected pubkey — from the signer's perspective, counterparty='anyone',
    // their derived private key's public key is what signed the vector.
    // Any third party (us) can reproduce this pubkey via KeyDeriver('anyone').
    const signerPub = PublicKey.fromString(VECTOR.signerPubHex);
    const anyoneDeriver = new KeyDeriver("anyone");
    const derivedPub = anyoneDeriver.derivePublicKey(
      [VECTOR.securityLevel, VECTOR.protocolName],
      VECTOR.keyID,
      signerPub,
      false, // anyone-side derive
    );
    const derivedPubHex = derivedPub.toString();
    // eslint-disable-next-line no-console
    console.log(`[brc3] derivedPub = ${derivedPubHex}`);

    const sig = Signature.fromDER(VECTOR.signatureDer);
    const msgBytes = enc(VECTOR.message);

    // Invoice number per BRC-43
    const invoiceNumber = `${VECTOR.securityLevel}-${VECTOR.protocolName.toLowerCase()}-${VECTOR.keyID}`;
    const invoiceBytes = enc(invoiceNumber);

    // Candidate preimages — everything plausible for BRC-3 given the spec is silent.
    const sha256 = digest;
    const candidates: { label: string; hash: Uint8Array }[] = [
      { label: "sha256(msg)", hash: await sha256(msgBytes) },
      { label: "sha256(sha256(msg))", hash: await sha256(await sha256(msgBytes)) },
      { label: "sha256(invoice+msg)", hash: await sha256(concat(invoiceBytes, msgBytes)) },
      { label: "sha256(msg+invoice)", hash: await sha256(concat(msgBytes, invoiceBytes)) },
      { label: "sha256(invoice)+sha256(msg)", hash: await sha256(concat(await sha256(invoiceBytes), await sha256(msgBytes))) },
      {
        label: "sha256(sha256(invoice)+sha256(msg))",
        hash: await sha256(concat(await sha256(invoiceBytes), await sha256(msgBytes))),
      },
      {
        label: "bitcoinSignedMessage (single sha256)",
        hash: await sha256(
          concat(
            new Uint8Array([0x18]),
            enc("Bitcoin Signed Message:\n"),
            new Uint8Array([msgBytes.length]),
            msgBytes,
          ),
        ),
      },
      {
        label: "bitcoinSignedMessage (double sha256)",
        hash: await sha256(
          await sha256(
            concat(
              new Uint8Array([0x18]),
              enc("Bitcoin Signed Message:\n"),
              new Uint8Array([msgBytes.length]),
              msgBytes,
            ),
          ),
        ),
      },
      { label: "raw msg (no hash)", hash: msgBytes },
    ];

    const matches: string[] = [];
    for (const c of candidates) {
      const ok = derivedPub.verify(bytesToHex(c.hash), sig, "hex");
      // eslint-disable-next-line no-console
      console.log(
        `[brc3] candidate=${c.label.padEnd(40)} hash=${bytesToHex(c.hash).slice(0, 24)}… ok=${ok}`,
      );
      if (ok) matches.push(c.label);
    }

    expect(matches.length).toBeGreaterThan(0);
    // eslint-disable-next-line no-console
    console.log(`[brc3] MATCHING PREIMAGE(S): ${matches.join(", ")}`);
  });
});

```
