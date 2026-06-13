---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/src/cell-types/field-tree-adapter.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.503275+00:00
---

# cartridges/oddjobz/brain/src/cell-types/field-tree-adapter.ts

```ts
/**
 * Field-tree adapter for oddjobz `CellTypeDef`s — first consumer of
 * CW Lift L8 (per-field intra-tx Merkle).
 *
 * Reference: docs/canon/cw-lift-matrix.yml L8.
 *
 * What this does:
 *   Bridges the oddjobz `CellTypeDef<T>` framework to the L8 field-tree
 *   primitive in `@semantos/protocol-types/field-tree`. Each TOP-LEVEL
 *   key of the cell's canonical projection becomes a Merkle leaf in the
 *   field tree; the cell's `typeHash` (already a 32-byte SHA-256) serves
 *   directly as the L8 `schemaFingerprint`. A verifier with the
 *   tree's root + a disclosure proof for one field can confirm that
 *   field's (label, value) without seeing the other fields.
 *
 * Why this is ADDITIVE:
 *   The existing `pack(value) → bytes` path (canonical-JSON of the whole
 *   payload) is the wire format that flows into the cell envelope and
 *   onto chain — unchanged. The field-tree is a SEPARATE artefact for
 *   selective-disclosure scenarios. A cartridge can:
 *     - keep using `pack/unpack` for the on-chain payload, AND
 *     - call `buildCellFieldTree(cellType, value)` to derive the
 *       disclosure-side artefact when an auditor / external integration
 *       wants per-field proofs.
 *   No existing call site changes.
 *
 * What gets disclosed:
 *   The adapter operates on the TOP-LEVEL keys of `toCanonical(value)`.
 *   For oddjobz cells this is the right granularity: `amount`,
 *   `customerId`, `summary`, etc. are each their own leaf. Nested
 *   sub-objects (if any) are serialised as canonical JSON before being
 *   committed as a leaf — they remain atomic from the disclosure
 *   perspective (caller chooses to share the whole sub-object or not).
 *
 * Use-case example (invoice):
 *   - Issue an invoice cell with status, amount, customerId, summary…
 *   - When sending to an auditor, build the field tree once + persist
 *     the root in the auditor's record (or commit it to a cell header).
 *   - Disclose only `amount` and `dueAt` to the auditor; they verify
 *     against the persisted root without seeing `customerId` or
 *     `summary`. The undisclosed fields remain sibling hashes —
 *     present in the tree but unreadable from outside.
 */

// Relative path used (vs. `@semantos/protocol-types/field-tree` subpath)
// to keep this adapter source-tree-resolvable in workspace mode without
// depending on the consumer's package.json exports map. The subpath
// export IS added to core/protocol-types/package.json so dist-consumers
// can also import via the canonical `@semantos/protocol-types/field-tree`;
// the adapter just doesn't rely on the symlink chain that name walks.
import {
  buildFieldTree,
  computeFieldLeaf,
  discloseField,
  verifyFieldDisclosure,
  type FieldDisclosureProof,
  type FieldLeaf,
  type FieldTree,
} from '../../../../../core/protocol-types/src/field-tree/index.js';
import type { CellTypeDef } from './cell-type.js';
import { encodeCanonicalJson, type CanonicalValue } from './canonical-json.js';

// ── Adapter ────────────────────────────────────────────────────────

/**
 * Build the field tree for a typed cell value.
 *
 * - `schemaFingerprint = cellType.typeHash` (already a 32B SHA-256
 *   bound to the (whatPath, howSlug, instPath) triple)
 * - For each top-level key in `toCanonical(value)`, the value is
 *   canonical-JSON-encoded into UTF-8 bytes; that's the field leaf's
 *   `value`. The key is the field's `label`.
 *
 * Empty payloads (zero canonical keys) throw — there's nothing to
 * commit. Cell types with structured payloads that intentionally
 * have a single field still work (single-leaf tree where root === leaf).
 */
export function buildCellFieldTree<T>(
  cellType: CellTypeDef<T>,
  value: T,
): FieldTree {
  const canonical = projectToFields(cellType, value);
  if (canonical.length === 0) {
    throw new Error(
      `buildCellFieldTree: ${cellType.name} produced zero canonical fields — nothing to commit`,
    );
  }
  return buildFieldTree(cellType.typeHash, canonical);
}

/**
 * Build a disclosure proof for one named field of the cell.
 *
 * Throws if `label` is not in the cell's canonical projection.
 */
export function discloseCellField<T>(
  cellType: CellTypeDef<T>,
  value: T,
  label: string,
): FieldDisclosureProof {
  const canonical = projectToFields(cellType, value);
  return discloseField(cellType.typeHash, canonical, label);
}

/**
 * Verify a disclosure proof against the trusted field-tree root for
 * a given cell type. Returns true iff:
 *   - proof.schemaFingerprint === cellType.typeHash
 *   - the recomputed leaf hash matches the proof's commitment
 *   - the Merkle path walks cleanly to expectedRoot
 *
 * Never throws.
 */
export function verifyCellFieldDisclosure<T>(
  cellType: CellTypeDef<T>,
  proof: FieldDisclosureProof,
  expectedRoot: Uint8Array,
): boolean {
  // Defensive: the proof must carry the same fingerprint as the cell
  // type. (The underlying verifyFieldDisclosure checks the leaf hash
  // re-derived from proof.schemaFingerprint, which catches a swap, but
  // we surface the mismatch here too for caller clarity.)
  if (!bytesEqual(proof.schemaFingerprint, cellType.typeHash)) {
    return false;
  }
  return verifyFieldDisclosure(proof, expectedRoot);
}

/**
 * Compute just the per-field commitments (leaf hashes) for the cell —
 * without building the tree. Useful for callers that want to anchor
 * commitments individually (e.g. one per disclosure-eligible field)
 * rather than collapse to a single root.
 *
 * Returns an array in canonical sorted-label order (matching the order
 * that `buildCellFieldTree` walks).
 */
export function computeCellFieldCommitments<T>(
  cellType: CellTypeDef<T>,
  value: T,
): readonly { label: string; commitment: Uint8Array }[] {
  const fields = projectToFields(cellType, value);
  return fields.map(f => ({
    label: f.label,
    commitment: computeFieldLeaf(cellType.typeHash, f),
  }));
}

// ── Internal: canonical → FieldLeaf[] projection ──────────────────

/**
 * Project a cell value onto its top-level canonical fields as
 * FieldLeaf entries. The label is the JSON key; the value bytes are
 * the canonical-JSON UTF-8 encoding of the leaf value.
 *
 * Why canonical JSON for the leaf value: oddjobz cells already use
 * canonical-JSON for the on-chain payload, so leaf bytes match what
 * a verifier would expect when reconstructing from the cell's own
 * pack format. Two callers projecting the same value get byte-equal
 * leaf bytes.
 */
function projectToFields<T>(
  cellType: CellTypeDef<T>,
  value: T,
): FieldLeaf[] {
  // We don't have direct access to the user-supplied toCanonical; but
  // pack(value) is canonical-JSON of the same projection. We
  // round-trip via the bytes: pack → JSON.parse → top-level entries.
  // This guarantees the field set matches what flows onto chain.
  const packedBytes = cellType.pack(value);
  const text = new TextDecoder('utf-8', { fatal: true }).decode(packedBytes);
  let obj: unknown;
  try {
    obj = JSON.parse(text);
  } catch (e) {
    throw new Error(
      `projectToFields: ${cellType.name} pack() did not produce JSON: ${(e as Error).message}`,
    );
  }
  if (typeof obj !== 'object' || obj === null || Array.isArray(obj)) {
    throw new Error(
      `projectToFields: ${cellType.name} canonical projection must be a plain object (got ${typeof obj})`,
    );
  }
  const fields: FieldLeaf[] = [];
  for (const [label, raw] of Object.entries(obj as Record<string, unknown>)) {
    // Canonical-JSON-encode the value so identical structural inputs
    // hash to identical bytes (sub-objects with reordered keys would
    // otherwise produce different leaf hashes).
    const canonicalBytes = encodeCanonicalJson(raw as CanonicalValue);
    fields.push({ label, value: canonicalBytes });
  }
  return fields;
}

function bytesEqual(a: Uint8Array, b: Uint8Array): boolean {
  if (a.byteLength !== b.byteLength) return false;
  for (let i = 0; i < a.byteLength; i++) if (a[i] !== b[i]) return false;
  return true;
}

```
