---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/plexus-contracts/tests/vectors/generate_cert_vectors.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.822946+00:00
---

# core/plexus-contracts/tests/vectors/generate_cert_vectors.ts

```ts
/**
 * Generator script for cert_id conformance vectors.
 *
 * Usage: bun core/plexus-contracts/tests/vectors/generate_cert_vectors.ts
 *
 * Produces cert_id_vectors.json with 100 deterministic cert vectors.
 * Each vector contains:
 *   - cert: full Brc52Cert fields (excluding certId — it is computed)
 *   - expected_canonical_preimage_hex: hex of the UTF-8 JSON preimage
 *   - expected_cert_id_hex: hex of SHA-256(preimage)
 *
 * Deterministic RNG: linear congruential generator seeded at 0xDEADBEEF.
 * No random(), no Date.now() — output is 100% reproducible.
 *
 * D-A0b deliverable — Phase 1a.
 */

import { writeFileSync } from "node:fs";
import { resolve, dirname } from "node:path";
import { Hash } from "@bsv/sdk";

// ── Deterministic LCG RNG ───────────────────────────────────────────────────
// Parameters: Knuth MMIX (64-bit variant, reduced to 32-bit for JS safety)
// seed: 0xDEADBEEF

let lcgState = 0xdeadbeef;

function lcgNext(): number {
  // 32-bit LCG: multiplier 1664525, increment 1013904223 (Numerical Recipes)
  lcgState = (Math.imul(lcgState, 1664525) + 1013904223) >>> 0;
  return lcgState;
}

function lcgHex(bytes: number): string {
  let out = "";
  for (let i = 0; i < bytes; i++) {
    out += (lcgNext() & 0xff).toString(16).padStart(2, "0");
  }
  return out;
}

function lcgChoice<T>(arr: T[]): T {
  const idx = lcgNext() % arr.length;
  return arr[idx]!;
}

// ── Cert-field corpus ────────────────────────────────────────────────────────

const CERT_TYPES = [
  "plexus.identity.root",
  "plexus.identity.derived",
  "plexus.identity.operator",
  "plexus.identity.service",
  "plexus.identity.device",
];

const FIELD_KEYS = [
  "email",
  "resourceId",
  "domainFlag",
  "childIndex",
  "tenantId",
  "appId",
  "role",
  "region",
  "tier",
  "scope",
  "label",
  "org",
  "department",
  "country",
  "locale",
  "tag",
];

// ── Deep-sort (mirrors identity.ts) ─────────────────────────────────────────

function deepSortObject(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(deepSortObject);
  if (value !== null && typeof value === "object") {
    const sorted: Record<string, unknown> = {};
    for (const key of Object.keys(value as Record<string, unknown>).sort()) {
      sorted[key] = deepSortObject((value as Record<string, unknown>)[key]);
    }
    return sorted;
  }
  return value;
}

function canonicalPreimageBytes(cert: {
  certifierPublicKey: string;
  fields: Record<string, string>;
  serialNumber: string;
  subjectPublicKey: string;
  type: string;
}): Uint8Array {
  const preimageObj = {
    certifierPublicKey: cert.certifierPublicKey,
    fields: cert.fields,
    serialNumber: cert.serialNumber,
    subjectPublicKey: cert.subjectPublicKey,
    type: cert.type,
  };
  const sorted = deepSortObject(preimageObj);
  const json = JSON.stringify(sorted);
  return new TextEncoder().encode(json);
}

function sha256hex(bytes: Uint8Array): string {
  const digest = Hash.sha256(Array.from(bytes)) as number[];
  return digest.map((b) => b.toString(16).padStart(2, "0")).join("");
}

// ── Vector generation ────────────────────────────────────────────────────────

interface CertVector {
  description: string;
  cert: {
    subjectPublicKey: string;
    certifierPublicKey: string;
    type: string;
    serialNumber: string;
    fields: Record<string, string>;
    signature: string;
  };
  expected_canonical_preimage_hex: string;
  expected_cert_id_hex: string;
}

function generateVector(index: number): CertVector {
  const subjectPublicKey = lcgHex(33);
  const isSelfCert = lcgNext() % 4 === 0; // ~25% root (self-certified)
  const certifierPublicKey = isSelfCert ? subjectPublicKey : lcgHex(33);
  const type = lcgChoice(CERT_TYPES);
  const serialNumber = lcgHex(32);
  const signature = lcgHex(71); // DER ECDSA sig (nominal 71 bytes)

  // Generate 1..4 fields, intentionally in non-alphabetical insertion order
  const numFields = 1 + (lcgNext() % 4);
  // Shuffle field keys by repeatedly picking from the pool
  const availableKeys = [...FIELD_KEYS];
  const chosenKeys: string[] = [];
  for (let k = 0; k < numFields && availableKeys.length > 0; k++) {
    const idx = lcgNext() % availableKeys.length;
    chosenKeys.push(availableKeys.splice(idx, 1)[0]!);
  }
  // Insert in REVERSE alphabetical order to stress-test the sort
  chosenKeys.sort().reverse();
  const fields: Record<string, string> = {};
  for (const key of chosenKeys) {
    fields[key] = lcgHex(8); // 8-byte (16 char) hex value
  }

  const cert = { subjectPublicKey, certifierPublicKey, type, serialNumber, fields, signature };

  const preimageBytes = canonicalPreimageBytes(cert);
  const preimageHex = Array.from(preimageBytes)
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
  const certIdHex = sha256hex(preimageBytes);

  return {
    description: `cert_id vector ${index + 1}: type=${type} fields=${chosenKeys.join(",")}`,
    cert,
    expected_canonical_preimage_hex: preimageHex,
    expected_cert_id_hex: certIdHex,
  };
}

const vectors: CertVector[] = [];
for (let i = 0; i < 100; i++) {
  vectors.push(generateVector(i));
}

const outputPath = resolve(dirname(import.meta.path), "cert_id_vectors.json");
writeFileSync(outputPath, JSON.stringify({ vectors }, null, 2) + "\n", "utf-8");
console.log(`Generated ${vectors.length} vectors → ${outputPath}`);

```
