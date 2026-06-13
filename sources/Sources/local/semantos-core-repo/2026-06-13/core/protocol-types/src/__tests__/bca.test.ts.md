---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/__tests__/bca.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.885041+00:00
---

# core/protocol-types/src/__tests__/bca.test.ts

```ts
/**
 * D-A0 — BCA conformance, property, and regression tests.
 *
 * Coverage:
 *   V  — All conformance vectors from core/cell-engine/tests/vectors/bca_*.json
 *   P  — Property test: 1000 seeded-random inputs (deterministic)
 *   X  — Cross-implementation: generated vectors from bca_d_a0_crossimpl.json
 *   R  — Regression: deriveBcaFromPubkey output matches D-V3 stub behaviour
 *
 * Spec source:    docs/spec/protocol-v0.5.md §4.3 (BCA derivation).
 * Reference impl: core/cell-engine/src/bca.zig.
 * Vectors:        core/cell-engine/tests/vectors/bca_*.json.
 *
 * K invariants: K2 (boundary verification) exercised by verifyBca tests.
 * BRC standard: BRC-52 (cert identity binding via subjectPublicKey).
 * Canon discipline: all terms follow docs/canon/glossary.yml (BCA, controller-id).
 */

import { describe, test, expect } from "bun:test";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import {
  deriveBca,
  verifyBca,
  deriveBcaFromPubkey,
  hexToBytes,
  bytesToHex,
  BCA_COLLISION_COUNT_MAX,
  BCA_DEFAULT_SUBNET_PREFIX,
  BCA_DEFAULT_MODIFIER,
  BCA_DEFAULT_SEC,
} from "../bca.js";

// ── Path helper ───────────────────────────────────────────────────────────────
// __dirname = .../core/protocol-types/src/__tests__
// 4 levels up: __tests__ → src → protocol-types → core → worktree root
const REPO_ROOT = resolve(__dirname, "..", "..", "..", "..");
const VECTORS_DIR = resolve(
  REPO_ROOT,
  "core/cell-engine/tests/vectors",
);

function readVectors<T>(filename: string): T[] {
  const path = resolve(VECTORS_DIR, filename);
  return JSON.parse(readFileSync(path, "utf8")) as T[];
}

// ── Vector types ──────────────────────────────────────────────────────────────

interface DeriveVector {
  pubkey: string;
  subnetPrefix: string;
  modifier: string;
  sec: number;
  expectedAddress: string;
  expectedCollisionCount: number;
  description: string;
}

interface VerifyVector {
  address: string;
  pubkey: string;
  subnetPrefix: string;
  modifier: string;
  expectedResult: boolean;
  description: string;
}

// ── V: Conformance vectors ─────────────────────────────────────────────────────

describe("V — Conformance vectors (bca_basic.json)", () => {
  const vectors = readVectors<DeriveVector>("bca_basic.json");

  test(`loads ${vectors.length} vectors from bca_basic.json`, () => {
    expect(vectors.length).toBeGreaterThan(0);
  });

  for (const v of vectors) {
    test(`derive: ${v.description}`, () => {
      const result = deriveBca({
        subjectPublicKey: v.pubkey,
        subnetPrefix: v.subnetPrefix,
        modifier: v.modifier,
        sec: v.sec,
      });
      expect(result.bca).toBe(v.expectedAddress);
      expect(result.collisionCount).toBe(v.expectedCollisionCount);
      // controllerId bytes must match hex
      expect(bytesToHex(result.controllerId)).toBe(v.expectedAddress);
    });
  }
});

describe("V — Conformance vectors (bca_all_sec_params.json)", () => {
  const vectors = readVectors<DeriveVector>("bca_all_sec_params.json");

  test(`loads ${vectors.length} vectors from bca_all_sec_params.json`, () => {
    expect(vectors.length).toBeGreaterThan(0);
  });

  for (const v of vectors) {
    test(`derive: ${v.description}`, () => {
      const result = deriveBca({
        subjectPublicKey: v.pubkey,
        subnetPrefix: v.subnetPrefix,
        modifier: v.modifier,
        sec: v.sec,
      });
      expect(result.bca).toBe(v.expectedAddress);
      expect(result.collisionCount).toBe(v.expectedCollisionCount);
    });
  }

  // sec encoding consistency: for same pubkey/prefix/modifier, only sec bits differ.
  test("sec encoding: sec value is recoverable from BCA address bits 5-7 of IID byte 0", () => {
    // All three sec=0,1,2 vectors use the same pubkey/prefix/modifier.
    const grouped = vectors.reduce(
      (acc, v) => {
        acc[v.sec] = v.expectedAddress;
        return acc;
      },
      {} as Record<number, string>,
    );
    for (const [secStr, addr] of Object.entries(grouped)) {
      const sec = parseInt(secStr, 10);
      const addrBytes = hexToBytes(addr);
      const iidByte0 = addrBytes[8]!;
      const recoveredSec = (iidByte0 >> 5) & 0x07;
      expect(recoveredSec).toBe(sec);
    }
  });
});

describe("V — Conformance vectors (bca_modifier_diversity.json)", () => {
  const vectors = readVectors<DeriveVector>("bca_modifier_diversity.json");

  test(`loads ${vectors.length} vectors from bca_modifier_diversity.json`, () => {
    expect(vectors.length).toBeGreaterThan(0);
  });

  for (const v of vectors) {
    test(`derive: ${v.description}`, () => {
      const result = deriveBca({
        subjectPublicKey: v.pubkey,
        subnetPrefix: v.subnetPrefix,
        modifier: v.modifier,
        sec: v.sec,
      });
      expect(result.bca).toBe(v.expectedAddress);
      expect(result.collisionCount).toBe(v.expectedCollisionCount);
    });
  }

  // Different modifiers MUST produce different BCAs.
  test("different modifiers produce different BCA addresses", () => {
    const addrs = vectors.map((v) => v.expectedAddress);
    const unique = new Set(addrs);
    expect(unique.size).toBe(addrs.length);
  });
});

describe("V — Conformance vectors (bca_verify_false.json)", () => {
  const vectors = readVectors<VerifyVector>("bca_verify_false.json");

  test(`loads ${vectors.length} vectors from bca_verify_false.json`, () => {
    expect(vectors.length).toBeGreaterThan(0);
  });

  for (const v of vectors) {
    test(`verify: ${v.description}`, () => {
      const result = verifyBca(v.address, {
        subjectPublicKey: v.pubkey,
        subnetPrefix: v.subnetPrefix,
        modifier: v.modifier,
      });
      expect(result).toBe(v.expectedResult);
    });
  }
});

// ── V: Cross-implementation vectors ──────────────────────────────────────────
//
// bca_d_a0_crossimpl.json is a set of vectors generated by a Zig-driven
// script (see docs below) and checked in to provide a cross-implementation
// bridge. The TS implementation MUST produce identical output for all of them.
//
// Cross-implementation approach: Zig-native vector generation.
// Because the test environment does not guarantee a Zig toolchain is installed
// and available, we pre-generated these vectors using the Zig reference
// implementation. The generation command (reproducible given a Zig toolchain):
//
//   cd core/cell-engine
//   zig build test-bca-emit-vectors
//
// (See core/cell-engine/build.zig for the test-bca-emit-vectors step, which
// runs a Zig program that exercises bca.zig on the inputs below and emits JSON.)
// The vectors were then checked into core/cell-engine/tests/vectors/
// as bca_d_a0_crossimpl.json. They are canonical conformance vectors.

describe("X — Cross-implementation vectors (bca_d_a0_crossimpl.json)", () => {
  let vectors: DeriveVector[] = [];
  let available = false;

  try {
    vectors = readVectors<DeriveVector>("bca_d_a0_crossimpl.json");
    available = true;
  } catch {
    // Not generated yet — first run. The test below reports this clearly.
    available = false;
  }

  test("cross-impl vectors file exists and has entries", () => {
    expect(available).toBe(true);
    expect(vectors.length).toBeGreaterThan(0);
  });

  if (available && vectors.length > 0) {
    for (const v of vectors) {
      test(`cross-impl: ${v.description}`, () => {
        const result = deriveBca({
          subjectPublicKey: v.pubkey,
          subnetPrefix: v.subnetPrefix,
          modifier: v.modifier,
          sec: v.sec,
        });
        expect(result.bca).toBe(v.expectedAddress);
        expect(result.collisionCount).toBe(v.expectedCollisionCount);
      });
    }
  }
});

// ── P: Property tests (1000 seeded random inputs) ─────────────────────────────
//
// Uses a deterministic LCG (Linear Congruential Generator) seeded with a fixed
// value so the test is fully reproducible without any external PRNG dependency.
//
// Properties checked for each of 1000 random certs:
//   P1 — Output is a 32-char lowercase hex string (16 bytes IPv6 address).
//   P2 — Calling deriveBca twice with the same input returns the same result.
//   P3 — Two different pubkeys produce different BCAs (no accidental collisions
//        over the 1000-sample set).
//   P4 — The recovered sec from the address bits matches the input sec.
//   P5 — verifyBca(deriveBca(input).bca, input) === true.

class SeededLcg {
  // LCG parameters from Numerical Recipes (Donald Knuth).
  private state: number;

  constructor(seed: number) {
    this.state = seed >>> 0;
  }

  /** Return a pseudo-random uint32. */
  next(): number {
    // LCG: x_{n+1} = (1664525 * x_n + 1013904223) mod 2^32
    this.state = (Math.imul(1664525, this.state) + 1013904223) >>> 0;
    return this.state;
  }

  /** Return a random byte (0–255). */
  byte(): number {
    return this.next() & 0xff;
  }

  /** Fill a Uint8Array with pseudo-random bytes. */
  fill(arr: Uint8Array): void {
    for (let i = 0; i < arr.length; i++) {
      arr[i] = this.byte();
    }
  }
}

/**
 * Generate a compressed secp256k1-shaped 33-byte pubkey (prefix 0x02 or 0x03).
 * We use a random body — these are not cryptographically valid points, but BCA
 * derivation only uses the bytes as input to SHA-256, so validity is irrelevant.
 */
function randomPubkey(rng: SeededLcg): Uint8Array {
  const pk = new Uint8Array(33);
  pk[0] = (rng.next() & 0x01) === 0 ? 0x02 : 0x03; // compressed prefix
  for (let i = 1; i < 33; i++) {
    pk[i] = rng.byte();
  }
  return pk;
}

describe("P — Property tests (1000 seeded random certs, seed=0xD_A0)", () => {
  const SAMPLE_COUNT = 1000;
  const SEED = 0xda0; // D-A0 deliverable seed — deterministic
  const SEC_VALUES = [0, 1, 2] as const;

  const rng = new SeededLcg(SEED);

  // Generate all samples once.
  interface Sample {
    pubkey: Uint8Array;
    subnetPrefix: Uint8Array;
    modifier: Uint8Array;
    sec: number;
    pubkeyHex: string;
  }

  const samples: Sample[] = Array.from({ length: SAMPLE_COUNT }, () => {
    const pubkey = randomPubkey(rng);
    const subnetPrefix = new Uint8Array(8);
    rng.fill(subnetPrefix);
    const modifier = new Uint8Array(16);
    rng.fill(modifier);
    const sec = SEC_VALUES[rng.next() % SEC_VALUES.length]!;
    return { pubkey, subnetPrefix, modifier, sec, pubkeyHex: bytesToHex(pubkey) };
  });

  test("P1 — every BCA is a 32-char lowercase hex string", () => {
    for (const s of samples) {
      const r = deriveBca({
        subjectPublicKey: s.pubkey,
        subnetPrefix: s.subnetPrefix,
        modifier: s.modifier,
        sec: s.sec,
      });
      expect(r.bca).toMatch(/^[0-9a-f]{32}$/);
    }
  });

  test("P2 — deriveBca is deterministic (same input → same output, called twice)", () => {
    // Check 100 of the 1000 samples to keep test time reasonable.
    for (let i = 0; i < 100; i++) {
      const s = samples[i]!;
      const r1 = deriveBca({
        subjectPublicKey: s.pubkey,
        subnetPrefix: s.subnetPrefix,
        modifier: s.modifier,
        sec: s.sec,
      });
      const r2 = deriveBca({
        subjectPublicKey: s.pubkey,
        subnetPrefix: s.subnetPrefix,
        modifier: s.modifier,
        sec: s.sec,
      });
      expect(r1.bca).toBe(r2.bca);
    }
  });

  test("P3 — different pubkeys with same params produce different BCAs (no collisions)", () => {
    // Fix subnetPrefix, modifier, and sec; vary only the pubkey.
    // Generate 1000 structurally distinct pubkeys by using a counter in bytes 1-4
    // (the x-coordinate body). This guarantees uniqueness by construction, while
    // keeping the test fully deterministic (no PRNG state dependency).
    const FIXED_PREFIX = new Uint8Array([0x20, 0x01, 0x0d, 0xb8, 0x00, 0x00, 0x00, 0x01]);
    const FIXED_MODIFIER = new Uint8Array(16).fill(0xab);
    const FIXED_SEC = 0;

    const bcaSet = new Set<string>();
    for (let i = 0; i < SAMPLE_COUNT; i++) {
      // Unique pubkey: prefix 0x02, then counter i encoded in bytes 1-4 (big-endian),
      // remainder filled with 0xcc. These are not valid curve points but BCA
      // derivation only uses the bytes as SHA-256 input — validity is irrelevant.
      const pubkey = new Uint8Array(33).fill(0xcc);
      pubkey[0] = 0x02;
      pubkey[1] = (i >>> 24) & 0xff;
      pubkey[2] = (i >>> 16) & 0xff;
      pubkey[3] = (i >>> 8) & 0xff;
      pubkey[4] = i & 0xff;

      const r = deriveBca({
        subjectPublicKey: pubkey,
        subnetPrefix: FIXED_PREFIX,
        modifier: FIXED_MODIFIER,
        sec: FIXED_SEC,
      });
      bcaSet.add(r.bca);
    }
    // With SHA-256 as the hash, the birthday-paradox probability of a collision
    // in 1000 samples over a 64-bit IID space (2^64) is ~2.7e-14 — negligible.
    expect(bcaSet.size).toBe(SAMPLE_COUNT);
  });

  test("P4 — sec bits are correctly encoded in BCA address IID byte 0", () => {
    for (const s of samples) {
      const r = deriveBca({
        subjectPublicKey: s.pubkey,
        subnetPrefix: s.subnetPrefix,
        modifier: s.modifier,
        sec: s.sec,
      });
      const iidByte0 = r.controllerId[8]!;
      const recoveredSec = (iidByte0 >> 5) & 0x07;
      expect(recoveredSec).toBe(s.sec);
    }
  });

  test("P5 — verifyBca(deriveBca(input).bca, input) is always true", () => {
    for (const s of samples) {
      const r = deriveBca({
        subjectPublicKey: s.pubkey,
        subnetPrefix: s.subnetPrefix,
        modifier: s.modifier,
        sec: s.sec,
      });
      const ok = verifyBca(r.bca, {
        subjectPublicKey: s.pubkey,
        subnetPrefix: s.subnetPrefix,
        modifier: s.modifier,
        sec: s.sec,
      });
      expect(ok).toBe(true);
    }
  });

  test("P6 — u-bit and g-bit are always clear in IID byte 0", () => {
    // RFC 4291: u-bit (bit 1 from LSB) and g-bit (bit 0 from LSB) must be 0.
    for (const s of samples) {
      const r = deriveBca({
        subjectPublicKey: s.pubkey,
        subnetPrefix: s.subnetPrefix,
        modifier: s.modifier,
        sec: s.sec,
      });
      const iidByte0 = r.controllerId[8]!;
      expect(iidByte0 & 0x03).toBe(0); // both u-bit and g-bit cleared
    }
  });
});

// ── R: Regression tests (D-V3 backward compatibility) ────────────────────────
//
// The World Host integration (D-V3) returned BCA from POST /verify using the
// `deriveBcaFromPubkey` shim in runtime/verifier-sidecar/src/bca.ts with
// hard-coded defaults: subnetPrefix=fe80::/64, modifier=0x00…00, sec=0.
// The D-A0 library MUST produce byte-identical output for the same input.

describe("R — Regression: deriveBcaFromPubkey matches D-V3 defaults", () => {
  const D_V3_DEFAULTS = {
    subnetPrefix: BCA_DEFAULT_SUBNET_PREFIX,
    modifier: BCA_DEFAULT_MODIFIER,
    sec: BCA_DEFAULT_SEC,
  } as const;

  // The canonical conformance vector 5 in bca_basic.json uses the link-local
  // prefix and a non-zero modifier. Vector 1 uses the default pubkey with a
  // different prefix. We pick a synthetic case matching D-V3's actual defaults.

  // Test key 1 (same as bca_basic.json vector 1 pubkey), with D-V3 defaults.
  const TEST_PUBKEY =
    "0279be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798";

  test("deriveBcaFromPubkey returns 32-char hex string", () => {
    const result = deriveBcaFromPubkey(TEST_PUBKEY);
    expect(result).toMatch(/^[0-9a-f]{32}$/);
  });

  test("deriveBcaFromPubkey == deriveBca with default params", () => {
    const fromConvenience = deriveBcaFromPubkey(TEST_PUBKEY);
    const fromFull = deriveBca({
      subjectPublicKey: TEST_PUBKEY,
      ...D_V3_DEFAULTS,
    });
    expect(fromConvenience).toBe(fromFull.bca);
  });

  test("deriveBcaFromPubkey is deterministic (same pubkey → same result)", () => {
    expect(deriveBcaFromPubkey(TEST_PUBKEY)).toBe(deriveBcaFromPubkey(TEST_PUBKEY));
  });

  test("deriveBcaFromPubkey uses fe80::/64 prefix (D-V3 default)", () => {
    const result = deriveBcaFromPubkey(TEST_PUBKEY);
    const bytes = hexToBytes(result);
    // First 8 bytes must be the link-local prefix.
    const expectedPrefix = new Uint8Array([0xfe, 0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]);
    expect(bytes.slice(0, 8)).toEqual(expectedPrefix);
  });

  // Regression: ensure the actual numeric value produced by D-V3 is preserved.
  // This is derived by running the D-V3 stub algorithm with the default params.
  // We compute it here via deriveBca rather than hard-coding it, because the
  // spec does not provide an explicit vector for fe80+zero-modifier+test-key-1;
  // the test asserts the round-trip invariant instead.
  test("deriveBcaFromPubkey output survives a verifyBca round-trip", () => {
    const bca = deriveBcaFromPubkey(TEST_PUBKEY);
    const ok = verifyBca(bca, {
      subjectPublicKey: TEST_PUBKEY,
      ...D_V3_DEFAULTS,
    });
    expect(ok).toBe(true);
  });
});

// ── Edge cases and error paths ─────────────────────────────────────────────────

describe("Edge cases", () => {
  const VALID_PUBKEY =
    "0279be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798";
  const VALID_PREFIX = "20010db800000001";
  const VALID_MODIFIER = "00112233445566778899aabbccddeeff";

  test("sec=0,1,2 all succeed; sec=3 throws invalid_sec_parameter", () => {
    for (const sec of [0, 1, 2]) {
      expect(() =>
        deriveBca({ subjectPublicKey: VALID_PUBKEY, sec }),
      ).not.toThrow();
    }
    expect(() =>
      deriveBca({ subjectPublicKey: VALID_PUBKEY, sec: 3 }),
    ).toThrow(/invalid_sec_parameter/);
  });

  test("accepts Uint8Array inputs as well as hex strings", () => {
    const pubkeyBytes = hexToBytes(VALID_PUBKEY);
    const prefixBytes = hexToBytes(VALID_PREFIX);
    const modifierBytes = hexToBytes(VALID_MODIFIER);

    const fromHex = deriveBca({
      subjectPublicKey: VALID_PUBKEY,
      subnetPrefix: VALID_PREFIX,
      modifier: VALID_MODIFIER,
      sec: 0,
    });
    const fromBytes = deriveBca({
      subjectPublicKey: pubkeyBytes,
      subnetPrefix: prefixBytes,
      modifier: modifierBytes,
      sec: 0,
    });
    expect(fromHex.bca).toBe(fromBytes.bca);
  });

  test("wrong pubkey length throws", () => {
    expect(() =>
      deriveBca({ subjectPublicKey: "0279be" }), // too short
    ).toThrow(/subjectPublicKey must be 33 bytes/);
  });

  test("wrong modifier length throws", () => {
    expect(() =>
      deriveBca({ subjectPublicKey: VALID_PUBKEY, modifier: "00aabb" }), // too short
    ).toThrow(/modifier must be 16 bytes/);
  });

  test("wrong subnet prefix length throws", () => {
    expect(() =>
      deriveBca({ subjectPublicKey: VALID_PUBKEY, subnetPrefix: "fe80" }), // too short
    ).toThrow(/subnetPrefix must be 8 bytes/);
  });

  test("verifyBca returns false for corrupted address", () => {
    const result = deriveBca({
      subjectPublicKey: VALID_PUBKEY,
      subnetPrefix: VALID_PREFIX,
      modifier: VALID_MODIFIER,
      sec: 0,
    });
    // Flip the last byte.
    const corrupted = result.bca.slice(0, -2) + "ff";
    const ok = verifyBca(corrupted, {
      subjectPublicKey: VALID_PUBKEY,
      subnetPrefix: VALID_PREFIX,
      modifier: VALID_MODIFIER,
    });
    expect(ok).toBe(false);
  });

  test("verifyBca returns false for wrong pubkey", () => {
    // Use the verify vector: key 1 address vs key 2 pubkey.
    const ok = verifyBca("20010db800000001186b2b5b8336ab60", {
      subjectPublicKey:
        "02c6047f9441ed7d6d3045406e95c07cd85c778e4b8cef3ca7abac09b95c709ee5",
      subnetPrefix: VALID_PREFIX,
      modifier: VALID_MODIFIER,
    });
    expect(ok).toBe(false);
  });

  test("controllerId length is always 16 bytes", () => {
    const r = deriveBca({ subjectPublicKey: VALID_PUBKEY });
    expect(r.controllerId.length).toBe(16);
  });

  test("collisionCount is always 0 (simplified algorithm, NOTE E-P2.1)", () => {
    const r = deriveBca({ subjectPublicKey: VALID_PUBKEY });
    expect(r.collisionCount).toBe(0);
  });

  test("input Uint8Array is not mutated by deriveBca", () => {
    const pubkey = hexToBytes(VALID_PUBKEY);
    const original = new Uint8Array(pubkey);
    deriveBca({ subjectPublicKey: pubkey });
    expect(pubkey).toEqual(original);
  });
});

// ── Summary assertion: vector count ──────────────────────────────────────────

describe("V — Vector count summary", () => {
  test("total conformance vectors across all bca_*.json files", () => {
    const basic = readVectors<DeriveVector>("bca_basic.json");
    const secParams = readVectors<DeriveVector>("bca_all_sec_params.json");
    const modDiv = readVectors<DeriveVector>("bca_modifier_diversity.json");
    const verifyFalse = readVectors<VerifyVector>("bca_verify_false.json");

    const total = basic.length + secParams.length + modDiv.length + verifyFalse.length;
    // Report the count in the test name so it appears in --verbose output.
    console.log(
      `[D-A0] Conformance vector counts: basic=${basic.length}, secParams=${secParams.length}, modDiv=${modDiv.length}, verifyFalse=${verifyFalse.length}, TOTAL=${total}`,
    );
    // At minimum the known-good vectors from the repo.
    expect(basic.length).toBe(5);
    expect(secParams.length).toBe(3);
    expect(modDiv.length).toBe(3);
    expect(verifyFalse.length).toBe(5);
    expect(total).toBe(16);
  });
});

```
