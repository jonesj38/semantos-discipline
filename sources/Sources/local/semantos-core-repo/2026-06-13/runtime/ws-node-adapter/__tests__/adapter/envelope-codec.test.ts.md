---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/ws-node-adapter/__tests__/adapter/envelope-codec.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.337898+00:00
---

# runtime/ws-node-adapter/__tests__/adapter/envelope-codec.test.ts

```ts
/**
 * adapter/envelope-codec.ts — pure envelope build/sign/verify.
 *
 * Distinct from `__tests__/codec.test.ts` which covers the wire-level
 * CBOR codec; this file covers the layer above (turning a
 * `PublishableObject` + signer into a `SessionEnvelopeFrame`).
 */

import { describe, expect, test } from "bun:test";
import { PrivateKey } from "@bsv/sdk";
import {
  BsvSdkSigner,
  BsvSdkVerifier,
} from "@semantos/session-protocol";
import {
  buildSignedEnvelope,
  verifyInboundEnvelope,
} from "../../src/adapter/envelope-codec";
import { FRAME_KIND } from "../../src/types";
import type { PublishableObject } from "@semantos/protocol-types/network";

function compressedPubkey(pk: PrivateKey): Uint8Array {
  return Uint8Array.from(pk.toPublicKey().encode(true) as number[]);
}

const HOLDER_SEED = "bb".repeat(32);
const ATTACKER_SEED = "cc".repeat(32);

function makeSigner(seedHex: string) {
  const privKey = PrivateKey.fromHex(seedHex);
  const pubkey = compressedPubkey(privKey);
  const signer = new BsvSdkSigner(privKey, async () => "x");
  return { signer, privKey, pubkey };
}

function makeObject(): PublishableObject {
  return {
    cellBytes: new Uint8Array([0x01, 0x02, 0x03]),
    semanticPath: "p",
    contentHash: "a".repeat(64),
    ownerCert: "cert",
    typeHash: "b".repeat(64),
  };
}

describe("buildSignedEnvelope", () => {
  test("produces a SessionEnvelopeFrame with all expected fields", async () => {
    const { signer } = makeSigner(HOLDER_SEED);
    const env = await buildSignedEnvelope({
      signer,
      object: makeObject(),
      topic: "topic-x",
      sessionId: "s-1",
      seq: 7,
      sentAt: 1_700_000_000_000,
    });
    expect(env.kind).toBe(FRAME_KIND.SESSION_ENVELOPE);
    expect(env.topic).toBe("topic-x");
    expect(env.sessionId).toBe("s-1");
    expect(env.seq).toBe(7);
    expect(env.sentAt).toBe(1_700_000_000_000);
    expect(env.contentHash).toBe("a".repeat(64));
    expect(env.ownerCert).toBe("cert");
    expect(env.typeHash).toBe("b".repeat(64));
    expect(env.payload).toEqual(new Uint8Array([0x01, 0x02, 0x03]));
    expect(env.sig.length).toBeGreaterThan(0);
  });

  test("sig verifies against the signer's public key", async () => {
    const { signer, pubkey } = makeSigner(HOLDER_SEED);
    const env = await buildSignedEnvelope({
      signer,
      object: makeObject(),
      topic: "t",
      sessionId: "s",
      seq: 1,
      sentAt: 0,
    });
    const ok = await verifyInboundEnvelope(new BsvSdkVerifier(), pubkey, env);
    expect(ok).toBe(true);
  });
});

describe("verifyInboundEnvelope", () => {
  test("returns false when signed by the wrong key", async () => {
    const { signer } = makeSigner(HOLDER_SEED);
    const attacker = makeSigner(ATTACKER_SEED);
    const env = await buildSignedEnvelope({
      signer,
      object: makeObject(),
      topic: "t",
      sessionId: "s",
      seq: 1,
      sentAt: 0,
    });
    // Verify against the wrong pubkey.
    const ok = await verifyInboundEnvelope(
      new BsvSdkVerifier(),
      attacker.pubkey,
      env,
    );
    expect(ok).toBe(false);
  });

  test("returns false when payload was tampered after signing", async () => {
    const { signer, pubkey } = makeSigner(HOLDER_SEED);
    const env = await buildSignedEnvelope({
      signer,
      object: makeObject(),
      topic: "t",
      sessionId: "s",
      seq: 1,
      sentAt: 0,
    });
    const tampered = { ...env, payload: new Uint8Array([0x99]) };
    const ok = await verifyInboundEnvelope(
      new BsvSdkVerifier(),
      pubkey,
      tampered,
    );
    expect(ok).toBe(false);
  });

  test("returns false (does not throw) when verifier itself throws", async () => {
    const env = {
      kind: FRAME_KIND.SESSION_ENVELOPE as const,
      sessionId: "s",
      topic: "t",
      payload: new Uint8Array(),
      contentHash: "x",
      ownerCert: "o",
      typeHash: "y",
      seq: 1,
      sig: new Uint8Array([0xaa]),
      sentAt: 0,
    };
    const ok = await verifyInboundEnvelope(
      {
        async verify() {
          throw new Error("kaboom");
        },
      },
      new Uint8Array([0x01]),
      env,
    );
    expect(ok).toBe(false);
  });
});

```
