---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/hrr-library/src/library.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.299012+00:00
---

# runtime/hrr-library/src/library.ts

```ts
/**
 * HRR vector library indexed per (domain_flag, jural_category).
 *
 * Population flow (two-phase promotion):
 *   1. onIntentOutcome(event) — encodes a structural metadata vector from the
 *      event's (domainFlag, juralCategory, lexicon, action) fields via
 *      `encodePartialIntent`, and stages it keyed by cellOutcomeHash.
 *      The raw anfBindingsJson is stored for WI-B4 full-program ranking.
 *   2. onStableTransition(event) — promotes the staged entry into the library.
 *
 * Stored vectors use `encodePartialIntent` (structural metadata basis), so
 * WI-B3 pre-filter queries — which build the same kind of vector from the
 * partial Intent at the rhetoric stage — produce meaningful cosine similarities.
 * WI-B4 rank pass retrieves the stored `anfBindingsJson` and re-encodes using
 * `encodeSIRProgram` for a higher-fidelity final score.
 *
 * Query API:
 *   nearest(query, domainFlag, jural, k, capabilities) → {cellId, similarity}[]
 *
 * Capability gating: each stored entry carries the capability numbers present
 * in its IRProgram. A query with capabilities set C only returns entries where
 * every required capability is a member of C.
 *
 * Snapshot API: serialise() / deserialise(json) for disk persistence.
 *
 * See research/cognition-implementation-plan.md §WI-B2, §WI-B3.
 */

import type { IRBinding } from '@semantos/semantos-ir';
import { encodePartialIntent, cosine } from '@semantos/hrr';

// ── Public event shapes (mirrors NATS payload from nats_event_producer.zig) ───

export interface IntentOutcomeEvent {
  intentId: string;
  domainFlag: number;
  lexicon: string;
  juralCategory: string;
  /** Speech-act action name (e.g. "pay_invoice"). Used to differentiate
   *  entries within the same (domain, category) group. Optional for
   *  backwards-compat with producers that don't yet supply it. */
  action?: string;
  /** JSON-serialised IRBinding[] */
  anfBindingsJson: string;
  compositeConfidence: number;
  cellOutcomeHash: string;
  tsMs: number;
  hatId: string;
}

export interface StableTransitionEvent {
  nodeIdx: number;
  cellId: string;
  hState: number;
  totalConstraintStrength: number;
  interactionCount: number;
  kernelId: string;
  tsMs: number;
  opPkh: string;
}

// ── Internal types ────────────────────────────────────────────────────────────

interface LibraryEntry {
  cellId: string;
  /** Structural metadata vector (encodePartialIntent basis) — used by nearest(). */
  vec: Float64Array;
  /** Raw ANF bindings JSON for WI-B4 full-program re-encoding. */
  anfBindingsJson: string;
  domainFlag: number;
  juralCategory: string;
  /** capability numbers extracted from the IRProgram's capability bindings */
  capabilities: number[];
  promotedAt: number;
}

interface StagedEntry {
  vec: Float64Array;
  anfBindingsJson: string;
  domainFlag: number;
  juralCategory: string;
  capabilities: number[];
  intentId: string;
  tsMs: number;
}

// ── Serialisable snapshot form ────────────────────────────────────────────────

export interface LibrarySnapshot {
  version: 1;
  entries: Array<{
    cellId: string;
    vecB64: string; // base64-encoded Float64Array bytes
    anfBindingsJson: string;
    domainFlag: number;
    juralCategory: string;
    capabilities: number[];
    promotedAt: number;
  }>;
}

// ── HrrLibrary ────────────────────────────────────────────────────────────────

export class HrrLibrary {
  /** Main store: cellId → entry */
  private readonly _entries = new Map<string, LibraryEntry>();
  /**
   * Staging: cellOutcomeHash → partial entry awaiting stable_transition.
   * Keyed by cellOutcomeHash because intent_outcome arrives before stable_transition.
   */
  private readonly _pending = new Map<string, StagedEntry>();

  // ── Population ─────────────────────────────────────────────────────────────

  /**
   * Call when an `intent_outcome` NATS event is received.
   * Builds a structural metadata vector via `encodePartialIntent` and stages it.
   * Also parses anfBindingsJson to extract capability requirements; drops the
   * event silently if the JSON is malformed.
   * Does not promote to the library — waits for the matching stable_transition.
   */
  onIntentOutcome(event: IntentOutcomeEvent): void {
    let bindings: IRBinding[];
    try {
      bindings = JSON.parse(event.anfBindingsJson) as IRBinding[];
    } catch {
      return; // malformed payload — drop silently; caller should log
    }

    const vec = encodePartialIntent({
      domainFlag: event.domainFlag,
      juralCategory: event.juralCategory,
      lexicon: event.lexicon,
      action: event.action,
    });
    const capabilities = extractCapabilities(bindings);

    this._pending.set(event.cellOutcomeHash, {
      vec,
      anfBindingsJson: event.anfBindingsJson,
      domainFlag: event.domainFlag,
      juralCategory: event.juralCategory,
      capabilities,
      intentId: event.intentId,
      tsMs: event.tsMs,
    });
  }

  /**
   * Call when a `stable_transition` NATS event is received.
   * If a staged vector exists for this cell_id, promotes it into the library.
   * Returns true if a vector was promoted, false otherwise.
   */
  onStableTransition(event: StableTransitionEvent): boolean {
    const staged = this._pending.get(event.cellId);
    if (!staged) return false;

    this._pending.delete(event.cellId);
    this._entries.set(event.cellId, {
      cellId: event.cellId,
      vec: staged.vec,
      anfBindingsJson: staged.anfBindingsJson,
      domainFlag: staged.domainFlag,
      juralCategory: staged.juralCategory,
      capabilities: staged.capabilities,
      promotedAt: event.tsMs,
    });
    return true;
  }

  // ── Query ──────────────────────────────────────────────────────────────────

  /**
   * Return the top-k most similar entries for the given query vector,
   * filtered to (domainFlag, juralCategory) and the caller's capability set.
   *
   * Capability gating: an entry is eligible only if every capability number
   * in `entry.capabilities` is present in the `capabilities` set. An entry
   * with no capability requirements is always eligible.
   *
   * Returns results sorted by descending similarity.
   */
  nearest(
    query: Float64Array,
    domainFlag: number,
    juralCategory: string,
    k: number,
    capabilities: Set<number>,
  ): Array<{ cellId: string; similarity: number }> {
    const results: Array<{ cellId: string; similarity: number }> = [];

    for (const entry of this._entries.values()) {
      if (entry.domainFlag !== domainFlag) continue;
      if (entry.juralCategory !== juralCategory) continue;
      if (!capabilitiesPermit(entry.capabilities, capabilities)) continue;

      results.push({ cellId: entry.cellId, similarity: cosine(query, entry.vec) });
    }

    results.sort((a, b) => b.similarity - a.similarity);
    return results.slice(0, k);
  }

  // ── Snapshot ───────────────────────────────────────────────────────────────

  /** Serialise the promoted library (not the staging area) to a JSON object. */
  serialise(): LibrarySnapshot {
    const entries = Array.from(this._entries.values()).map(e => ({
      cellId: e.cellId,
      vecB64: float64ToBase64(e.vec),
      anfBindingsJson: e.anfBindingsJson,
      domainFlag: e.domainFlag,
      juralCategory: e.juralCategory,
      capabilities: e.capabilities,
      promotedAt: e.promotedAt,
    }));
    return { version: 1, entries };
  }

  /** Restore library state from a snapshot, merging with any existing entries. */
  deserialise(snapshot: LibrarySnapshot): void {
    for (const raw of snapshot.entries) {
      this._entries.set(raw.cellId, {
        cellId: raw.cellId,
        vec: base64ToFloat64(raw.vecB64),
        anfBindingsJson: raw.anfBindingsJson,
        domainFlag: raw.domainFlag,
        juralCategory: raw.juralCategory,
        capabilities: raw.capabilities,
        promotedAt: raw.promotedAt,
      });
    }
  }

  /** Number of promoted entries in the library. */
  get size(): number { return this._entries.size; }

  /** Number of staged entries awaiting stable_transition. */
  get pendingSize(): number { return this._pending.size; }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

function extractCapabilities(bindings: IRBinding[]): number[] {
  return bindings
    .filter(b => b.kind === 'capability' && b.capabilityNumber != null)
    .map(b => b.capabilityNumber as number);
}

function capabilitiesPermit(
  required: number[],
  available: Set<number>,
): boolean {
  return required.every(c => available.has(c));
}

function float64ToBase64(v: Float64Array): string {
  const bytes = new Uint8Array(v.buffer, v.byteOffset, v.byteLength);
  return Buffer.from(bytes).toString('base64');
}

function base64ToFloat64(b64: string): Float64Array {
  const bytes = Buffer.from(b64, 'base64');
  return new Float64Array(
    bytes.buffer,
    bytes.byteOffset,
    bytes.byteLength / 8,
  );
}

```
