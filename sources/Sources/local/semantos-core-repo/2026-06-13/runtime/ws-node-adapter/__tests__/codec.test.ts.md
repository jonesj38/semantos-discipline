---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/ws-node-adapter/__tests__/codec.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.333562+00:00
---

# runtime/ws-node-adapter/__tests__/codec.test.ts

```ts
/**
 * codec.ts tests — encodeFrame / decodeFrame roundtrip + signing helpers.
 */

import { describe, test, expect } from "bun:test";
import {
  encodeFrame,
  decodeFrame,
  canonicalEnvelopeBytesForSigning,
  handshakeSigPayload,
} from "../src/codec";
import {
  FRAME_KIND,
  type LicenseHandshakeFrame,
  type SessionEnvelopeFrame,
  type HeartbeatFrame,
  type GoodbyeFrame,
} from "../src/types";

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

const FAKE_LICENSE = new Uint8Array(128).fill(0x11);
const FAKE_SIG = new Uint8Array(70).fill(0x22);
const FAKE_CHALLENGE = new Uint8Array(32).fill(0x33);
const FAKE_PAYLOAD = new Uint8Array(1024).fill(0x44);

function makeHandshake(): LicenseHandshakeFrame {
  return {
    kind: FRAME_KIND.LICENSE_HANDSHAKE,
    license: FAKE_LICENSE,
    sig: FAKE_SIG,
    challenge: FAKE_CHALLENGE,
    claimedBca: "2602:f9f8::a11ce",
  };
}

function makeEnvelope(overrides: Partial<SessionEnvelopeFrame> = {}): SessionEnvelopeFrame {
  return {
    kind: FRAME_KIND.SESSION_ENVELOPE,
    sessionId: "poker-table-7",
    topic: "tm_semantos_objects",
    payload: FAKE_PAYLOAD,
    contentHash: "a".repeat(64),
    ownerCert: "cert-alice",
    typeHash: "b".repeat(64),
    seq: 42,
    sig: FAKE_SIG,
    sentAt: 1_800_000_000_000,
    ...overrides,
  };
}

function makeHeartbeat(): HeartbeatFrame {
  return {
    kind: FRAME_KIND.HEARTBEAT,
    at: 1_800_000_000_000,
    peerBca: "2602:f9f8::b0b",
  };
}

function makeGoodbye(reason?: string): GoodbyeFrame {
  return { kind: FRAME_KIND.GOODBYE, reason };
}

// ---------------------------------------------------------------------------
// encode/decode roundtrip
// ---------------------------------------------------------------------------

describe("Frame encode/decode roundtrip", () => {
  test("LicenseHandshake roundtrip preserves all fields", () => {
    const f = makeHandshake();
    const back = decodeFrame(encodeFrame(f));
    expect(back).toEqual(f);
  });

  test("SessionEnvelope roundtrip preserves all fields", () => {
    const f = makeEnvelope();
    const back = decodeFrame(encodeFrame(f));
    expect(back).toEqual(f);
  });

  test("Heartbeat roundtrip preserves fields", () => {
    const f = makeHeartbeat();
    const back = decodeFrame(encodeFrame(f));
    expect(back).toEqual(f);
  });

  test("Goodbye with reason roundtrips", () => {
    const f = makeGoodbye("graceful shutdown");
    const back = decodeFrame(encodeFrame(f));
    expect(back).toEqual(f);
  });

  test("Goodbye without reason roundtrips", () => {
    const f = makeGoodbye();
    const back = decodeFrame(encodeFrame(f));
    expect(back.kind).toBe(FRAME_KIND.GOODBYE);
    if (back.kind === FRAME_KIND.GOODBYE) {
      expect(back.reason).toBeUndefined();
    }
  });

  test("byte-array fields survive as Uint8Array (not Buffer)", () => {
    const back = decodeFrame(encodeFrame(makeHandshake()));
    if (back.kind !== FRAME_KIND.LICENSE_HANDSHAKE) throw new Error("wrong kind");
    expect(back.license).toBeInstanceOf(Uint8Array);
    expect(back.sig).toBeInstanceOf(Uint8Array);
    expect(back.challenge).toBeInstanceOf(Uint8Array);
  });
});

// ---------------------------------------------------------------------------
// decode error paths
// ---------------------------------------------------------------------------

describe("Frame decode error paths", () => {
  test("decodeFrame on malformed CBOR throws", () => {
    expect(() => decodeFrame(new Uint8Array([0xff, 0xff, 0xff]))).toThrow();
  });

  test("decodeFrame on unknown kind throws", () => {
    const { Encoder } = require("cbor-x");
    const bogus = new Uint8Array(
      new Encoder({ useRecords: false }).encode({ kind: "not_a_kind" }),
    );
    expect(() => decodeFrame(bogus)).toThrow(/unknown frame kind/);
  });

  test("decodeFrame on non-object input throws", () => {
    const { Encoder } = require("cbor-x");
    const bogus = new Uint8Array(new Encoder({ useRecords: false }).encode(123));
    expect(() => decodeFrame(bogus)).toThrow(/malformed frame/);
  });
});

// ---------------------------------------------------------------------------
// canonicalEnvelopeBytesForSigning
// ---------------------------------------------------------------------------

describe("canonicalEnvelopeBytesForSigning", () => {
  test("bytes identical regardless of sig field value", () => {
    const a = makeEnvelope({ sig: new Uint8Array([1, 2, 3]) });
    const b = makeEnvelope({ sig: new Uint8Array([9, 9, 9]) });

    expect(canonicalEnvelopeBytesForSigning(a)).toEqual(
      canonicalEnvelopeBytesForSigning(b),
    );
  });

  test("bytes differ when substantive fields differ (payload)", () => {
    const a = makeEnvelope({ payload: new Uint8Array([1]) });
    const b = makeEnvelope({ payload: new Uint8Array([2]) });

    expect(canonicalEnvelopeBytesForSigning(a)).not.toEqual(
      canonicalEnvelopeBytesForSigning(b),
    );
  });

  test("bytes differ when seq changes", () => {
    const a = makeEnvelope({ seq: 1 });
    const b = makeEnvelope({ seq: 2 });

    expect(canonicalEnvelopeBytesForSigning(a)).not.toEqual(
      canonicalEnvelopeBytesForSigning(b),
    );
  });

  test("bytes deterministic across calls", () => {
    const f = makeEnvelope();
    expect(canonicalEnvelopeBytesForSigning(f)).toEqual(
      canonicalEnvelopeBytesForSigning(f),
    );
  });
});

// ---------------------------------------------------------------------------
// handshakeSigPayload
// ---------------------------------------------------------------------------

describe("handshakeSigPayload", () => {
  test("payload is challenge || sha256(licenseBytes)", () => {
    const challenge = new Uint8Array(32).fill(0xaa);
    const license = new Uint8Array([1, 2, 3, 4]);
    const payload = handshakeSigPayload(challenge, license);

    expect(payload.length).toBe(32 + 32);
    expect(Array.from(payload.slice(0, 32))).toEqual(Array.from(challenge));

    // Second half is the sha256 of `license`. Compute and compare.
    const { createHash } = require("node:crypto");
    const expectedHash = createHash("sha256").update(license).digest();
    expect(Array.from(payload.slice(32))).toEqual(Array.from(expectedHash));
  });

  test("different challenges produce different payloads", () => {
    const license = new Uint8Array([1]);
    const a = handshakeSigPayload(new Uint8Array(32).fill(0x00), license);
    const b = handshakeSigPayload(new Uint8Array(32).fill(0x01), license);
    expect(a).not.toEqual(b);
  });

  test("different licenses produce different payloads", () => {
    const challenge = new Uint8Array(32);
    const a = handshakeSigPayload(challenge, new Uint8Array([1]));
    const b = handshakeSigPayload(challenge, new Uint8Array([2]));
    expect(a).not.toEqual(b);
  });

  test("stable across calls", () => {
    const challenge = new Uint8Array(32);
    const license = new Uint8Array([1, 2, 3]);
    expect(handshakeSigPayload(challenge, license)).toEqual(
      handshakeSigPayload(challenge, license),
    );
  });
});

```
