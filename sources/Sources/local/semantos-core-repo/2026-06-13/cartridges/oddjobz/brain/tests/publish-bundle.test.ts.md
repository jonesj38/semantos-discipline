---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/tests/publish-bundle.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.472454+00:00
---

# cartridges/oddjobz/brain/tests/publish-bundle.test.ts

```ts
/**
 * D-W2 Phase 1 — extension-bundle publisher unit tests.
 *
 * Reference: docs/design/BRAIN-EXTENSION-DELIVERY-AND-REVOCATION.md §5.1
 *   (publishing flow, step 6).
 *
 * The TS publisher's wire format is pinned here byte-stable.  Two code
 * paths exist:
 *
 *   • assembleBundlePayload — the inner extension-bundle-v1 payload
 *     (version tag + bundle bytes + namespace + version + signer
 *     pubkey).  Layout pinned per the spec.  Decode round-trips the
 *     same input.
 *
 *   • buildExtensionBundleFrame — the outer ShardFrame.encode
 *     wrapper.  txid slot is the publish-tx's display-order txid,
 *     reversed to internal byte order; payload is assembleBundlePayload's
 *     output.
 *
 * UDP send is NOT exercised here — that's a smoke test against a live
 * shard-proxy.  We pin the bytes only.
 */

import { describe, expect, test } from "bun:test";
import {
  assembleBundlePayload,
  decodeBundlePayload,
  buildExtensionBundleFrame,
  txidDisplayHexToInternalBytes,
  hexToBytes,
} from "../tools/publish-bundle";
import { ShardFrame } from "@semantos/protocol-types";

describe("D-W2 P1 — extension-bundle publisher", () => {
  test("assembleBundlePayload byte layout is pinned", () => {
    const bundleBytes = new TextEncoder().encode("fixture-bundle");
    const payload = assembleBundlePayload({
      bundleBytes,
      namespace: "oddjobz.invoicer",
      version: "0.1.0",
      signerPubkey: new Uint8Array([0x02, ...new Array(32).fill(0xaa)]),
    });

    // Layout:
    //   tag_len (1) | "extension-bundle-v1" (19) |
    //   bundle_len (4 BE) | bundle (n) |
    //   ns_len (1) | ns (m) |
    //   ver_len (1) | ver (v) |
    //   pubkey (33)
    const tagLen = 19;
    const bundleLen = bundleBytes.length;
    const nsLen = "oddjobz.invoicer".length;
    const verLen = "0.1.0".length;
    expect(payload.length).toBe(1 + tagLen + 4 + bundleLen + 1 + nsLen + 1 + verLen + 33);

    expect(payload[0]).toBe(tagLen);
    const tagSlice = new TextDecoder().decode(payload.subarray(1, 1 + tagLen));
    expect(tagSlice).toBe("extension-bundle-v1");

    const dv = new DataView(payload.buffer, payload.byteOffset, payload.byteLength);
    expect(dv.getUint32(1 + tagLen, false)).toBe(bundleLen);

    const bundleStart = 1 + tagLen + 4;
    expect(payload.subarray(bundleStart, bundleStart + bundleLen)).toEqual(bundleBytes);

    const nsStart = bundleStart + bundleLen + 1;
    expect(payload[bundleStart + bundleLen]).toBe(nsLen);
    expect(new TextDecoder().decode(payload.subarray(nsStart, nsStart + nsLen))).toBe(
      "oddjobz.invoicer",
    );

    const verStart = nsStart + nsLen + 1;
    expect(payload[nsStart + nsLen]).toBe(verLen);
    expect(new TextDecoder().decode(payload.subarray(verStart, verStart + verLen))).toBe("0.1.0");

    const pkStart = verStart + verLen;
    expect(payload[pkStart]).toBe(0x02);
    expect(payload[pkStart + 32]).toBe(0xaa);
  });

  test("decodeBundlePayload round-trips assembleBundlePayload", () => {
    const bundleBytes = new TextEncoder().encode("hello world bundle bytes");
    const signerPubkey = new Uint8Array([0x03, ...new Array(32).fill(0x77)]);
    const payload = assembleBundlePayload({
      bundleBytes,
      namespace: "acme.thing",
      version: "1.2.3",
      signerPubkey,
    });
    const decoded = decodeBundlePayload(payload);
    expect(decoded.versionTag).toBe("extension-bundle-v1");
    expect(Array.from(decoded.bundleBytes)).toEqual(Array.from(bundleBytes));
    expect(decoded.namespace).toBe("acme.thing");
    expect(decoded.version).toBe("1.2.3");
    expect(Array.from(decoded.signerPubkey)).toEqual(Array.from(signerPubkey));
  });

  test("assembleBundlePayload rejects bad namespace/version lengths", () => {
    const tooLongNs = "x".repeat(65);
    expect(() =>
      assembleBundlePayload({
        bundleBytes: new Uint8Array(0),
        namespace: tooLongNs,
        version: "0.1.0",
      }),
    ).toThrow(/namespace must be 1-64 bytes/);

    expect(() =>
      assembleBundlePayload({
        bundleBytes: new Uint8Array(0),
        namespace: "",
        version: "0.1.0",
      }),
    ).toThrow(/namespace must be 1-64 bytes/);

    const tooLongVer = "1".repeat(33);
    expect(() =>
      assembleBundlePayload({
        bundleBytes: new Uint8Array(0),
        namespace: "ns",
        version: tooLongVer,
      }),
    ).toThrow(/version must be 1-32 bytes/);
  });

  test("txidDisplayHexToInternalBytes reverses byte order", () => {
    const display = "0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20";
    const internal = txidDisplayHexToInternalBytes(display);
    expect(internal.length).toBe(32);
    // Display first byte (0x01) → internal last byte.
    expect(internal[31]).toBe(0x01);
    expect(internal[0]).toBe(0x20);
  });

  test("buildExtensionBundleFrame emits a valid BRC-12 frame", () => {
    const txidHex = "deadbeefcafebabe1122334455667788aabbccddeeff00112233445566778899";
    const bundleBytes = new TextEncoder().encode("the bundle bytes");
    const frame = buildExtensionBundleFrame({
      txidDisplayHex: txidHex,
      bundleBytes,
      namespace: "oddjobz.test",
      version: "0.1.0",
    });

    // Decoder is the canonical reference — round-trip the frame.
    const decoded = ShardFrame.decode(frame);
    expect(decoded).not.toBeNull();
    if (!decoded) throw new Error("frame decode failed");

    // txid slot in internal byte order — reverse to get the display hex.
    const txidInternal = decoded.txid;
    const displayBytes = new Uint8Array(32);
    for (let i = 0; i < 32; i++) displayBytes[i] = txidInternal[31 - i];
    let recoveredHex = "";
    for (const b of displayBytes) recoveredHex += b.toString(16).padStart(2, "0");
    expect(recoveredHex).toBe(txidHex);

    // Payload decode round-trips.
    const inner = decodeBundlePayload(decoded.payload);
    expect(inner.versionTag).toBe("extension-bundle-v1");
    expect(Array.from(inner.bundleBytes)).toEqual(Array.from(bundleBytes));
    expect(inner.namespace).toBe("oddjobz.test");
    expect(inner.version).toBe("0.1.0");
  });

  test("hexToBytes round-trips with txidDisplayHexToInternalBytes (different shapes)", () => {
    const hex = "00112233";
    const bytes = hexToBytes(hex);
    expect(bytes.length).toBe(4);
    expect(bytes[0]).toBe(0x00);
    expect(bytes[3]).toBe(0x33);
  });
});

```
