---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/tessera/brain/src/field-tree-adapter.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.638120+00:00
---

# cartridges/tessera/brain/src/field-tree-adapter.ts

```ts
/**
 * Tessera field-tree adapter — L8 consumer for the care-chain
 * provenance cartridge.
 *
 * Reference:
 *   docs/canon/cw-lift-matrix.yml L8 (per-field intra-tx Merkle).
 *   docs/prd/TESSERA-CARTRIDGE.md §0.1 (greenfield discipline #2).
 *
 * What this does:
 *   Bridges tessera's opaque-JSON cell bodies (`TesseraCellStore.put`
 *   accepts `body: unknown`) to the L8 field-tree primitive so the
 *   care-chain cells can produce selective-disclosure proofs without
 *   exposing every field to every verifier.
 *
 * Care-chain disclosure scenarios this enables:
 *   - A QR-scanning CONSUMER sees `origin`, `vintage`, `certifications`
 *     of a bottle cell — NOT `cost_basis`, `internal_sku`,
 *     `distributor_margin`.
 *   - A RETAILER sees `lot_id`, `batch_id`, `expected_arrival` —
 *     NOT producer margins or cellar care logs.
 *   - An AUDITOR sees the full chain of custody (every `care-event`
 *     cell's `handler_id`, `temp_log_root`, `transit_path`) without
 *     traversing every bottle individually.
 *   - The PRODUCER never has to disclose internal SKU mappings or
 *     cost data even though they're committed to the cell.
 *
 * Greenfield discipline (per TESSERA-CARTRIDGE.md §0.1 #2 +
 * tests/gates/tessera-adapter-consumption.test.ts):
 *   This module accesses substrate ONLY through @semantos/protocol-types/*.
 *   No @bsv/sdk, no wallet-toolbox, no LMDB binding. The L8 primitive
 *   lives in @semantos/protocol-types/field-tree — green-path import.
 *
 * What's NOT in scope here:
 *   L11 deriveSegment for tessera — tessera's greenfield discipline
 *   routes key derivation through `IdentityAdapter` (substrate-side
 *   port), NOT through direct @plexus/vendor-sdk imports (which would
 *   pull @bsv/sdk transitively, violating the consumption gate). When
 *   the substrate-side IdentityAdapter grows a deriveSegment-shaped
 *   method (a separate substrate-side lift), tessera's key paths
 *   (e.g. the DLO.1b cert mint when it lands) will adopt it via
 *   that port. See L11 matrix entry for the cross-cartridge surface.
 */

import {
  buildFieldTree,
  computeFieldLeaf,
  discloseField,
  verifyFieldDisclosure,
  type FieldDisclosureProof,
  type FieldLeaf,
  type FieldTree,
} from '@semantos/protocol-types/field-tree';
import type { TesseraCellType } from './store-adapter.js';

// ── Schema fingerprint per tessera cell type ───────────────────────

/**
 * Domain separator + version for tessera cell-type schema fingerprints.
 * Bumped when the fingerprint computation changes (which would
 * invalidate every persisted field-tree root).
 */
const TESSERA_FP_DOMAIN = 'tessera.cell-type/v1/';

/**
 * Compute the 32-byte L8 schema fingerprint for a tessera cell type.
 *
 *   schemaFingerprint = SHA-256(TESSERA_FP_DOMAIN || cellType)
 *
 * Caller can either compute on demand via `tesseraSchemaFingerprint(t)`
 * or cache the 10 well-known fingerprints (one per `TesseraCellType`)
 * at module load.
 */
export function tesseraSchemaFingerprint(cellType: TesseraCellType): Uint8Array {
  // Reuse the L8 primitive's SHA-256 by computing a leaf with a single
  // pre-image that combines our domain + the cellType string. This
  // sidesteps importing 'crypto' directly (tessera's gate is strict;
  // 'node:crypto' is allowed but doing this through the primitive
  // keeps the dependency surface minimal + provably consistent).
  // We feed it through computeFieldLeaf in a degenerate shape so we
  // get a deterministic 32B output bound to the cellType string.
  // (The fingerprint is itself an opaque 32B value — its computation
  // path doesn't have to match the L8 leaf-hash preimage shape; we
  // only need determinism + bound-to-cellType.)
  return sha256Utf8(TESSERA_FP_DOMAIN + cellType);
}

// Use a small private SHA-256 helper rather than 'node:crypto' to keep
// the file's import surface tightly bounded (the L8 primitive already
// provides hashing internally; we just don't want to add a top-level
// 'crypto' import that would complicate the consumption gate's audit
// surface).
function sha256Utf8(s: string): Uint8Array {
  const enc = new TextEncoder().encode(s);
  // Use the same hash function the L8 primitive uses internally.
  // computeFieldLeaf domain-separates with its own preimage shape, so
  // we route through it with a sentinel fingerprint + label to get a
  // deterministic 32-byte hash bound to `s`. This avoids importing
  // 'node:crypto' at this layer — the L8 module already does so.
  const SENTINEL_FP = new Uint8Array(32); // all zeros — fixed
  return computeFieldLeaf(SENTINEL_FP, {
    label: '__tessera_fp_internal__',
    value: enc,
  });
}

// ── Field-tree adapter ────────────────────────────────────────────

/**
 * Build a field tree for a tessera cell body.
 *
 * `body` is an arbitrary JSON-compatible object — top-level keys
 * become Merkle leaves; values are canonical-JSON-encoded into UTF-8
 * bytes for the leaf value.
 *
 * Throws if `body` is not a plain object (arrays / primitives don't
 * map to per-field disclosure semantics here).
 */
export function buildTesseraFieldTree(
  cellType: TesseraCellType,
  body: unknown,
): FieldTree {
  const fp = tesseraSchemaFingerprint(cellType);
  const fields = projectBodyToFields(body, cellType);
  if (fields.length === 0) {
    throw new Error(
      `buildTesseraFieldTree: ${cellType} body produced zero fields — nothing to commit`,
    );
  }
  return buildFieldTree(fp, fields);
}

/**
 * Disclose ONE field of a tessera cell body to a verifier. The
 * returned proof verifies against the tree's root without exposing
 * the other fields.
 */
export function discloseTesseraField(
  cellType: TesseraCellType,
  body: unknown,
  label: string,
): FieldDisclosureProof {
  const fp = tesseraSchemaFingerprint(cellType);
  const fields = projectBodyToFields(body, cellType);
  return discloseField(fp, fields, label);
}

/**
 * Verify a tessera disclosure proof against a trusted root.
 *
 *   1. Reject if proof.schemaFingerprint !== tessera fingerprint for cellType.
 *   2. Walk the Merkle path via the L8 primitive.
 *   3. Compare against expectedRoot.
 *
 * Never throws.
 */
export function verifyTesseraFieldDisclosure(
  cellType: TesseraCellType,
  proof: FieldDisclosureProof,
  expectedRoot: Uint8Array,
): boolean {
  if (!bytesEqual(proof.schemaFingerprint, tesseraSchemaFingerprint(cellType))) {
    return false;
  }
  return verifyFieldDisclosure(proof, expectedRoot);
}

/**
 * Compute per-field commitments without building the tree. Useful for
 * callers that anchor commitments individually (e.g. one chain-event
 * per disclosure-eligible field).
 */
export function computeTesseraFieldCommitments(
  cellType: TesseraCellType,
  body: unknown,
): readonly { label: string; commitment: Uint8Array }[] {
  const fp = tesseraSchemaFingerprint(cellType);
  const fields = projectBodyToFields(body, cellType);
  // Sort in the same canonical order buildFieldTree uses internally
  // so commits[i].label === tree.fields[i].label for the matching tree.
  const sorted = [...fields].sort((a, b) =>
    a.label < b.label ? -1 : a.label > b.label ? 1 : 0,
  );
  return sorted.map((f) => ({
    label: f.label,
    commitment: computeFieldLeaf(fp, f),
  }));
}

// ── Internal: body → FieldLeaf[] projection ──────────────────────

/**
 * Project a tessera cell body onto FieldLeaf entries: top-level keys
 * are labels; values are canonical-JSON-encoded into UTF-8 bytes.
 *
 * Canonical-JSON encoding (sorted object keys, no trailing whitespace,
 * no JSON `undefined` leakage) keeps the leaf bytes stable across
 * implementations + insertion-order differences in the body object.
 */
function projectBodyToFields(body: unknown, cellType: TesseraCellType): FieldLeaf[] {
  if (typeof body !== 'object' || body === null || Array.isArray(body)) {
    throw new Error(
      `projectBodyToFields: ${cellType} body must be a plain object (got ${typeof body})`,
    );
  }
  const out: FieldLeaf[] = [];
  for (const [label, raw] of Object.entries(body as Record<string, unknown>)) {
    out.push({
      label,
      value: new TextEncoder().encode(canonicalJsonStringify(raw)),
    });
  }
  return out;
}

/**
 * Minimal canonical-JSON stringifier. Sorts object keys, refuses
 * undefined/NaN/Infinity (refusal is the contract — silent dropping
 * would corrupt round-trip semantics).
 *
 * Same shape as @semantos/oddjobz's canonical-json encoder, kept
 * inline here because tessera's import gate forbids cross-cartridge
 * imports and the encoder is small.
 */
function canonicalJsonStringify(v: unknown): string {
  if (v === null) return 'null';
  if (v === undefined) {
    throw new Error('canonicalJsonStringify: undefined is not encodable');
  }
  if (typeof v === 'boolean') return v ? 'true' : 'false';
  if (typeof v === 'number') {
    if (!Number.isFinite(v)) {
      throw new Error(`canonicalJsonStringify: non-finite number ${v}`);
    }
    return v.toString();
  }
  if (typeof v === 'string') return JSON.stringify(v);
  if (Array.isArray(v)) {
    return '[' + v.map(canonicalJsonStringify).join(',') + ']';
  }
  if (typeof v === 'object') {
    const keys = Object.keys(v as Record<string, unknown>).sort();
    const parts: string[] = [];
    for (const k of keys) {
      const val = (v as Record<string, unknown>)[k];
      if (val === undefined) continue; // omit undefined values from objects
      parts.push(JSON.stringify(k) + ':' + canonicalJsonStringify(val));
    }
    return '{' + parts.join(',') + '}';
  }
  throw new Error(`canonicalJsonStringify: unsupported type ${typeof v}`);
}

function bytesEqual(a: Uint8Array, b: Uint8Array): boolean {
  if (a.byteLength !== b.byteLength) return false;
  for (let i = 0; i < a.byteLength; i++) if (a[i] !== b[i]) return false;
  return true;
}

```
