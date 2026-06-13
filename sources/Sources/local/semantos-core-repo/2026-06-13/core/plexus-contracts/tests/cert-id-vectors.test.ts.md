---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/plexus-contracts/tests/cert-id-vectors.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.820610+00:00
---

# core/plexus-contracts/tests/cert-id-vectors.test.ts

```ts
/**
 * D-A0b — BRC-52 cert_id cross-language conformance (TS side, @plexus/contracts path).
 *
 * W1.5C-1 note: the canonical home for these types and this conformance
 * suite is now @semantos/protocol-types (core/protocol-types/__tests__/
 * cert-id-vectors.test.ts). This file validates that the @plexus/contracts
 * re-export shim (src/identity.ts) still exposes the same functions with
 * identical behaviour.
 *
 * Loads 100 deterministic vectors from
 * tests/vectors/cert_id_vectors.json and asserts:
 *
 *   1. canonicalCertPreimage(cert) produces the expected preimage bytes
 *      (hex-encoded in the vector as expected_canonical_preimage_hex).
 *   2. computeCertId(cert) produces the expected cert_id
 *      (hex-encoded as expected_cert_id_hex).
 *
 * The SAME vectors file is consumed by the Elixir test at
 * runtime/world-beam/apps/world_host/test/world_host/identity_test.exs so any divergence
 * between TS and Elixir shows up as a test failure on one side.
 *
 * Spec source: docs/spec/protocol-v0.5.md §4.2 (BRC-52 cert format).
 * D-A0b — Phase 1a. W1.5C-1 — cleanup phase (re-export shim validation).
 */

import { describe, test, expect } from "bun:test";
import { readFileSync } from "node:fs";
import { resolve, dirname } from "node:path";
import { canonicalCertPreimage, computeCertId } from "../src/identity.js";
import type { Brc52Cert } from "../src/identity.js";

// ── Load vectors ─────────────────────────────────────────────────────────────

interface CertVector {
  description: string;
  cert: Pick<Brc52Cert, "subjectPublicKey" | "certifierPublicKey" | "type" | "serialNumber" | "fields" | "signature">;
  expected_canonical_preimage_hex: string;
  expected_cert_id_hex: string;
}

interface VectorFile {
  vectors: CertVector[];
}

const vectorsPath = resolve(dirname(import.meta.path), "vectors", "cert_id_vectors.json");
const vectorFile: VectorFile = JSON.parse(readFileSync(vectorsPath, "utf-8")) as VectorFile;
const { vectors } = vectorFile;

// ── Helpers ──────────────────────────────────────────────────────────────────

function bytesToHex(bytes: Uint8Array): string {
  return Array.from(bytes)
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

// ── Tests ────────────────────────────────────────────────────────────────────

describe("D-A0b cert_id conformance vectors (TS)", () => {
  test(`vector count is exactly 100`, () => {
    expect(vectors.length).toBe(100);
  });

  for (const [i, vector] of vectors.entries()) {
    test(`vector ${i + 1}: canonicalCertPreimage — ${vector.description}`, () => {
      const preimageBytes = canonicalCertPreimage(vector.cert);
      const gotHex = bytesToHex(preimageBytes);
      expect(gotHex).toBe(vector.expected_canonical_preimage_hex);
    });

    test(`vector ${i + 1}: computeCertId — ${vector.description}`, () => {
      const gotId = computeCertId(vector.cert);
      expect(gotId).toBe(vector.expected_cert_id_hex);
    });
  }
});

describe("D-A0b cert_id invariants", () => {
  test("canonical preimage excludes certId and signature fields", () => {
    // Build a cert where certId and signature are present; preimage must not
    // change when we modify those fields (they are not part of the preimage).
    const base = vectors[0]!.cert;
    const withCertId: Brc52Cert = {
      ...base,
      certId: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      signature: base.signature,
    };
    const withDiffCertId: Brc52Cert = {
      ...base,
      certId: "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
      signature: base.signature,
    };

    // Both should produce the same preimage — certId is not in the preimage.
    expect(bytesToHex(canonicalCertPreimage(withCertId))).toBe(
      bytesToHex(canonicalCertPreimage(withDiffCertId)),
    );
    // And the preimage matches the vector.
    expect(bytesToHex(canonicalCertPreimage(base))).toBe(
      vectors[0]!.expected_canonical_preimage_hex,
    );
  });

  test("field key insertion order does not affect preimage (deep sort)", () => {
    // Insert fields in reverse alphabetical order; preimage must be identical
    // to inserting them in alphabetical order.
    const baseVec = vectors[0]!;
    const certAlpha = {
      ...baseVec.cert,
      fields: Object.fromEntries(
        Object.entries(baseVec.cert.fields).sort(([a], [b]) => a.localeCompare(b)),
      ),
    };
    const certReverse = {
      ...baseVec.cert,
      fields: Object.fromEntries(
        Object.entries(baseVec.cert.fields).sort(([a], [b]) => b.localeCompare(a)),
      ),
    };
    expect(bytesToHex(canonicalCertPreimage(certAlpha))).toBe(
      bytesToHex(canonicalCertPreimage(certReverse)),
    );
  });

  test("computeCertId is SHA-256 of canonicalCertPreimage", () => {
    // Verify the relationship cert_id = SHA-256(preimage) for every vector.
    for (const vec of vectors) {
      const preimageHex = bytesToHex(canonicalCertPreimage(vec.cert));
      expect(preimageHex).toBe(vec.expected_canonical_preimage_hex);
      expect(computeCertId(vec.cert)).toBe(vec.expected_cert_id_hex);
    }
  });

  test("preimage contains no random nonces or timestamps", () => {
    // Two calls with the same cert must return byte-identical preimage.
    const cert = vectors[5]!.cert;
    const p1 = bytesToHex(canonicalCertPreimage(cert));
    const p2 = bytesToHex(canonicalCertPreimage(cert));
    expect(p1).toBe(p2);
  });

  test("computeCertId output is deterministic across calls", () => {
    // Call computeCertId twice for each vector — must return the same value both times.
    for (const vec of vectors) {
      const id1 = computeCertId(vec.cert);
      const id2 = computeCertId(vec.cert);
      expect(id1).toBe(id2);
      expect(id1).toBe(vec.expected_cert_id_hex);
    }
  });
});

```
