---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/ws-node-adapter/__tests__/adapter/license-verifier.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.338760+00:00
---

# runtime/ws-node-adapter/__tests__/adapter/license-verifier.test.ts

```ts
/**
 * adapter/license-verifier.ts — fail-closed envelope gate.
 *
 * Acceptance criterion (prompt 39): "license verification fails closed
 * (rejects unsigned envelopes)" — pinned here.
 */

import { describe, expect, test } from "bun:test";
import type { Verifier } from "@semantos/session-protocol";
import { gateInboundEnvelope } from "../../src/adapter/license-verifier";
import { FRAME_KIND, type SessionEnvelopeFrame } from "../../src/types";
import { canonicalEnvelopeBytesForSigning } from "../../src/codec";

function makeEnvelope(overrides: Partial<SessionEnvelopeFrame> = {}): SessionEnvelopeFrame {
  return {
    kind: FRAME_KIND.SESSION_ENVELOPE,
    sessionId: "s",
    topic: "t",
    payload: new Uint8Array([1, 2, 3]),
    contentHash: "a".repeat(64),
    ownerCert: "o",
    typeHash: "b".repeat(64),
    seq: 1,
    sig: new Uint8Array([0xaa]),
    sentAt: 0,
    ...overrides,
  };
}

/** Verifier double — returns whatever you tell it. */
function recordingVerifier(verdict: boolean | (() => Promise<boolean>)): {
  verifier: Verifier;
  calls: Array<{ pubkey: Uint8Array; bytes: Uint8Array; sig: Uint8Array }>;
} {
  const calls: Array<{ pubkey: Uint8Array; bytes: Uint8Array; sig: Uint8Array }> = [];
  const verifier: Verifier = {
    async verify(pubkey, bytes, sig) {
      calls.push({ pubkey, bytes, sig });
      return typeof verdict === "function" ? verdict() : verdict;
    },
  };
  return { verifier, calls };
}

describe("gateInboundEnvelope — fail-closed", () => {
  test("rejects when peerPubkey is missing (unauthenticated peer)", async () => {
    const { verifier, calls } = recordingVerifier(true);
    const verdict = await gateInboundEnvelope(verifier, {
      envelope: makeEnvelope(),
      peerPubkey: undefined,
    });
    expect(verdict).toEqual({ accept: false, reason: "no-peer-pubkey" });
    // Verifier never invoked — short-circuit before any crypto.
    expect(calls).toHaveLength(0);
  });

  test("rejects when sig is empty (defence in depth — verifier might say yes)", async () => {
    const { verifier, calls } = recordingVerifier(true);
    const verdict = await gateInboundEnvelope(verifier, {
      envelope: makeEnvelope({ sig: new Uint8Array(0) }),
      peerPubkey: new Uint8Array([0x01]),
    });
    expect(verdict).toEqual({ accept: false, reason: "empty-sig" });
    expect(calls).toHaveLength(0);
  });

  test("rejects when verifier returns false", async () => {
    const { verifier } = recordingVerifier(false);
    const verdict = await gateInboundEnvelope(verifier, {
      envelope: makeEnvelope(),
      peerPubkey: new Uint8Array([0x01]),
    });
    expect(verdict).toEqual({ accept: false, reason: "sig-invalid" });
  });

  test("rejects when verifier throws (fail-closed)", async () => {
    const verifier: Verifier = {
      async verify() {
        throw new Error("verifier blew up");
      },
    };
    const verdict = await gateInboundEnvelope(verifier, {
      envelope: makeEnvelope(),
      peerPubkey: new Uint8Array([0x01]),
    });
    expect(verdict).toEqual({ accept: false, reason: "sig-invalid" });
  });

  test("accepts when peerPubkey is present, sig non-empty, verifier returns true", async () => {
    const { verifier } = recordingVerifier(true);
    const verdict = await gateInboundEnvelope(verifier, {
      envelope: makeEnvelope(),
      peerPubkey: new Uint8Array([0x01]),
    });
    expect(verdict).toEqual({ accept: true });
  });

  test("verifier is called with canonical envelope bytes (sig stripped)", async () => {
    const { verifier, calls } = recordingVerifier(true);
    const env = makeEnvelope();
    await gateInboundEnvelope(verifier, {
      envelope: env,
      peerPubkey: new Uint8Array([0x01]),
    });
    expect(calls).toHaveLength(1);
    expect(calls[0]!.bytes).toEqual(canonicalEnvelopeBytesForSigning(env));
    expect(calls[0]!.sig).toEqual(env.sig);
  });
});

```
