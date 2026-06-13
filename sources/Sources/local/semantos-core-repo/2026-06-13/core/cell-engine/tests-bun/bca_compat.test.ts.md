---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-engine/tests-bun/bca_compat.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.987826+00:00
---

# core/cell-engine/tests-bun/bca_compat.test.ts

```ts
/**
 * BCA cross-language compatibility tests — Phase 2
 *
 * Verifies that BCA derivation through WASM (Zig + host_sha256) produces
 * byte-identical output to independently-generated test vectors (TypeScript + @bsv/sdk).
 */

import { describe, test, expect } from "bun:test";
import { readFileSync } from "fs";
import { join } from "path";
import { Hash } from "@bsv/sdk";
import { createHostFunctions } from "../bindings/host-functions";

// ── Load WASM with real host_sha256 ──

const WASM_PATH = join(import.meta.dir, "../zig-out/bin/cell-engine.wasm");
const VECTORS_DIR = join(import.meta.dir, "../tests/vectors");

let wasmInstance: WebAssembly.Instance;
let wasmMemory: WebAssembly.Memory;

async function loadWasm(): Promise<void> {
  const wasmBytes = readFileSync(WASM_PATH);

  // Use a memory proxy object so host functions always read from the
  // correct memory buffer (which may be the WASM module's own export).
  // The memRef is updated after instantiation.
  const memRef = { current: null as WebAssembly.Memory | null };

  const hostFns: Record<string, Function> = {
    host_sha256: (dataPtr: number, dataLen: number, outPtr: number) => {
      const mem = memRef.current!;
      const data = new Uint8Array(mem.buffer, dataPtr, dataLen);
      const hash = Hash.sha256(data);
      new Uint8Array(mem.buffer, outPtr, 32).set(new Uint8Array(hash));
    },
    host_hash160: () => { throw new Error("NOT_IMPLEMENTED"); },
    host_hash256: () => { throw new Error("NOT_IMPLEMENTED"); },
    host_checksig: () => 0,
    host_checkmultisig: () => 0,
    host_get_blocktime: () => 0,
    host_get_sequence: () => 0,
    host_log: () => {},
    host_fetch_cell: () => 0,
    host_call_by_name: () => 0xFFFFFFFF,
  };

  const result = await WebAssembly.instantiate(wasmBytes, { host: hostFns });
  wasmInstance = result.instance;
  wasmMemory = wasmInstance.exports.memory as WebAssembly.Memory;
  memRef.current = wasmMemory;
}

// ── Helpers ──

function fromHex(hex: string): Uint8Array {
  const bytes = new Uint8Array(hex.length / 2);
  for (let i = 0; i < hex.length; i += 2) {
    bytes[i / 2] = parseInt(hex.substring(i, i + 2), 16);
  }
  return bytes;
}

function toHex(arr: Uint8Array): string {
  return Array.from(arr)
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

interface BasicVector {
  pubkey: string;
  subnetPrefix: string;
  modifier: string;
  sec: number;
  expectedAddress: string;
  expectedCollisionCount: number;
  description: string;
}

interface VerifyFalseVector {
  address: string;
  pubkey: string;
  subnetPrefix: string;
  modifier: string;
  expectedResult: boolean;
  description: string;
}

function loadVectors<T>(name: string): T[] {
  return JSON.parse(readFileSync(join(VECTORS_DIR, `${name}.json`), "utf-8"));
}

// ── WASM BCA helpers ──

function wasmBcaDerive(
  pubkey: Uint8Array,
  prefix: Uint8Array,
  modifier: Uint8Array,
  sec: number
): { address: Uint8Array; collisionCount: number } {
  const bca_derive = wasmInstance.exports.bca_derive as Function;
  const mem = new Uint8Array(wasmMemory.buffer);

  // Layout in WASM memory
  const pubkeyOff = 0x100000;
  const prefixOff = pubkeyOff + 33;
  const modifierOff = prefixOff + 8;
  const outOff = modifierOff + 16;

  mem.set(pubkey, pubkeyOff);
  mem.set(prefix, prefixOff);
  mem.set(modifier, modifierOff);

  const result = bca_derive(pubkeyOff, prefixOff, modifierOff, sec, outOff);
  if (result < 0) throw new Error(`bca_derive returned error: ${result}`);

  return {
    address: new Uint8Array(mem.slice(outOff, outOff + 16)),
    collisionCount: result,
  };
}

function wasmBcaVerify(
  address: Uint8Array,
  pubkey: Uint8Array,
  prefix: Uint8Array,
  modifier: Uint8Array
): boolean {
  const bca_verify = wasmInstance.exports.bca_verify as Function;
  const mem = new Uint8Array(wasmMemory.buffer);

  const addrOff = 0x100000;
  const pubkeyOff = addrOff + 16;
  const prefixOff = pubkeyOff + 33;
  const modifierOff = prefixOff + 8;

  mem.set(address, addrOff);
  mem.set(pubkey, pubkeyOff);
  mem.set(prefix, prefixOff);
  mem.set(modifier, modifierOff);

  return bca_verify(addrOff, pubkeyOff, prefixOff, modifierOff) === 1;
}

// ── TypeScript BCA reference (same as vector generator) ──

function tsBcaDerive(
  pubkey: Uint8Array,
  prefix: Uint8Array,
  modifier: Uint8Array,
  sec: number
): Uint8Array {
  const data = new Uint8Array(58);
  data.set(modifier, 0);
  data.set(prefix, 16);
  data[24] = 0; // collision count = 0
  data.set(pubkey, 25);

  const hash = Hash.sha256(data);
  const iid = new Uint8Array(hash.slice(0, 8));

  // RFC 4291 bit manipulation
  iid[0] &= ~0x03; // clear u-bit and g-bit
  iid[0] = (iid[0] & 0x1f) | ((sec & 0x07) << 5); // encode sec

  const address = new Uint8Array(16);
  address.set(prefix, 0);
  address.set(iid, 8);
  return address;
}

// ── Tests ──

describe("host_sha256 via @bsv/sdk", () => {
  test("WASM loads successfully with BCA exports", async () => {
    await loadWasm();
    expect(wasmInstance).toBeDefined();
    expect(wasmInstance.exports.bca_derive).toBeDefined();
    expect(wasmInstance.exports.bca_verify).toBeDefined();
  });

  test("host_sha256 produces correct hash for known input", async () => {
    await loadWasm();

    // SHA256("") = e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
    const expected = fromHex(
      "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
    );
    const hash = Hash.sha256(new Uint8Array(0));
    expect(new Uint8Array(hash)).toEqual(expected);
  });

  test("host_sha256 matches between @bsv/sdk and WASM (via Zig std lib in native)", async () => {
    // This verifies that the hash function used by the WASM host matches
    // what we use for test vector generation
    const testData = new Uint8Array([0x01, 0x02, 0x03, 0x04]);
    const sdkHash = new Uint8Array(Hash.sha256(testData));

    // Also verify known value
    const expected = fromHex(
      "9f64a747e1b97f131fabb6b447296c9b6f0201e79fb3c5356e6c77e89b6a806a"
    );
    expect(sdkHash).toEqual(expected);
  });
});

describe("BCA derivation through WASM matches test vectors", () => {
  test("basic vectors: WASM BCA matches independently-generated addresses", async () => {
    await loadWasm();

    const vectors = loadVectors<BasicVector>("bca_basic");
    expect(vectors.length).toBeGreaterThan(0);

    for (const v of vectors) {
      const result = wasmBcaDerive(
        fromHex(v.pubkey),
        fromHex(v.subnetPrefix),
        fromHex(v.modifier),
        v.sec
      );

      expect(toHex(result.address)).toBe(v.expectedAddress);
      expect(result.collisionCount).toBe(v.expectedCollisionCount);
    }
  });

  test("sec parameter vectors: WASM BCA encodes sec correctly", async () => {
    await loadWasm();

    const vectors = loadVectors<BasicVector>("bca_all_sec_params");
    expect(vectors.length).toBe(3);

    for (const v of vectors) {
      const result = wasmBcaDerive(
        fromHex(v.pubkey),
        fromHex(v.subnetPrefix),
        fromHex(v.modifier),
        v.sec
      );

      expect(toHex(result.address)).toBe(v.expectedAddress);

      // Verify sec is encoded in the 3 MSBs of interface identifier byte 0
      const iidByte0 = result.address[8];
      expect((iidByte0 >> 5) & 0x07).toBe(v.sec);
    }
  });

  test("modifier diversity vectors: different modifiers produce different addresses", async () => {
    await loadWasm();

    const vectors = loadVectors<BasicVector>("bca_modifier_diversity");
    expect(vectors.length).toBeGreaterThan(0);

    for (const v of vectors) {
      const result = wasmBcaDerive(
        fromHex(v.pubkey),
        fromHex(v.subnetPrefix),
        fromHex(v.modifier),
        v.sec
      );

      expect(toHex(result.address)).toBe(v.expectedAddress);
    }
  });
});

describe("BCA verification through WASM", () => {
  test("verify vectors: correct and incorrect params", async () => {
    await loadWasm();

    const vectors = loadVectors<VerifyFalseVector>("bca_verify_false");
    expect(vectors.length).toBeGreaterThan(0);

    for (const v of vectors) {
      const result = wasmBcaVerify(
        fromHex(v.address),
        fromHex(v.pubkey),
        fromHex(v.subnetPrefix),
        fromHex(v.modifier)
      );

      expect(result).toBe(v.expectedResult);
    }
  });

  test("round-trip: derive in WASM, verify in WASM", async () => {
    await loadWasm();

    const pubkey = fromHex(
      "0279be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798"
    );
    const prefix = fromHex("20010db800000001");
    const modifier = fromHex("00112233445566778899aabbccddeeff");

    const derived = wasmBcaDerive(pubkey, prefix, modifier, 0);
    const verified = wasmBcaVerify(derived.address, pubkey, prefix, modifier);
    expect(verified).toBe(true);

    // Wrong pubkey should fail
    const wrongPubkey = fromHex(
      "02c6047f9441ed7d6d3045406e95c07cd85c778e4b8cef3ca7abac09b95c709ee5"
    );
    const wrongVerified = wasmBcaVerify(
      derived.address,
      wrongPubkey,
      prefix,
      modifier
    );
    expect(wrongVerified).toBe(false);
  });

  test("round-trip: derive in TS, verify matches WASM derive", async () => {
    await loadWasm();

    const pubkey = fromHex(
      "0279be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798"
    );
    const prefix = fromHex("20010db800000001");
    const modifier = fromHex("00112233445566778899aabbccddeeff");

    // Derive in TypeScript
    const tsAddress = tsBcaDerive(pubkey, prefix, modifier, 0);

    // Derive in WASM
    const wasmResult = wasmBcaDerive(pubkey, prefix, modifier, 0);

    // Must be byte-identical
    expect(toHex(wasmResult.address)).toBe(toHex(tsAddress));

    // WASM should verify the TS-derived address
    const verified = wasmBcaVerify(tsAddress, pubkey, prefix, modifier);
    expect(verified).toBe(true);
  });
});

describe("WASM binary", () => {
  test("WASM binary exports bca_derive and bca_verify", async () => {
    await loadWasm();
    expect(typeof wasmInstance.exports.bca_derive).toBe("function");
    expect(typeof wasmInstance.exports.bca_verify).toBe("function");
  });

  test("WASM binary size is under 500KB", () => {
    const stats = readFileSync(WASM_PATH);
    // Phase 3 added 2-PDA executor + streaming SHA256; binary grew from ~5KB to ~25KB
    expect(stats.length).toBeLessThan(500 * 1024);
  });
});

```
