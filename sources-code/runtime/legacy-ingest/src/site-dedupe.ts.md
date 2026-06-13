---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/legacy-ingest/src/site-dedupe.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.132152+00:00
---

# runtime/legacy-ingest/src/site-dedupe.ts

```ts
/**
 * D-RTC.1b — Site dedupe.
 *
 * Reference: docs/prd/D-Reingest-Typed-Cells.md §Deliverables / D-RTC.1.
 *
 * Companion to `address-normalize.ts`. Given a free-text address +
 * optional sub-address key (unit / lot / office number), produces a
 * deterministic site-cell proposal:
 *
 *   • `lookupKey`       — the index entry the sites_store hashmap uses
 *   • `proposedCellId`  — the 32-byte SHA-256 id the brain will mint
 *                          if no existing site matches `lookupKey`
 *
 * Callers wire a `SitesView` (file-backed or dispatcher-backed) to
 * resolve `lookupKey → existing site_cell_id`. If matched, reingest
 * reuses the existing cell; if not, the proposal carries everything
 * needed to mint a fresh site_cell.
 *
 * Naming scheme is intentionally REINGEST-NAMESPACED (not the legacy
 * `oddjobz.site.v2` brain-rpc namespace) — per memory
 * `v1_production_is_test_data.md`, the existing V1 site cells are
 * throwaway and will be rebuilt from gmail. Stable IDs under reingest
 * mean two emails about the same physical site collapse onto one
 * site_cell, regardless of how the address was written.
 */

import { createHash } from 'node:crypto';
import { normalizeAddress } from './address-normalize';

/* ──────────────────────────────────────────────────────────────────────
 * Public types
 * ────────────────────────────────────────────────────────────────────── */

/**
 * Caller-supplied lookup against the brain's view of sites_store.
 *
 * V1 wirings:
 *   • File-backed — reads `<dataDir>/oddjobz/sites.jsonl` (legacy)
 *   • Dispatcher-backed — issues a `verb.dispatch` for `site.lookup`
 *     against the brain over WSS (preferred for reingest)
 *   • In-memory — used by site-dedupe.test.ts
 */
export interface SitesView {
  /**
   * Returns the existing site_cell_id (lowercase 64-char hex) for the
   * given `lookupKey`, or `null` if no site matches.
   */
  findByLookupKey(lookupKey: string): Promise<string | null>;
}

/** What we propose minting if no existing site matches. */
export interface SiteProposal {
  kind: 'propose';
  /** Deterministic 64-char hex id. Same address → same id, every time. */
  proposedCellId: string;
  /** The hashmap index entry. */
  lookupKey: string;
  /** Output of `normalizeAddress()` — the stable canonical form. */
  normalizedAddress: string;
  /** Sub-address discriminator (unit/lot/office number), or null. */
  keyNumber: string | null;
  /** Original raw address, unmodified — retained for display + audit. */
  rawAddress: string;
}

/** What we report if an existing site matches the lookup key. */
export interface SiteMatch {
  kind: 'match';
  cellId: string;
  lookupKey: string;
  normalizedAddress: string;
  keyNumber: string | null;
  rawAddress: string;
}

export type SiteDedupeResult = SiteMatch | SiteProposal;

/* ──────────────────────────────────────────────────────────────────────
 * Public API
 * ────────────────────────────────────────────────────────────────────── */

/**
 * Pure-function half of D-RTC.1b. Normalises the address and computes
 * the deterministic lookup key + proposed cell id. Does NOT touch any
 * storage — callers compose this with `SitesView` via `findOrPropose`.
 *
 * Returns `null` for input that `normalizeAddress` rejects (PO box,
 * lot-DP legal description, empty/garbage input). Those rows should
 * fall through to operator review at ratification time, not collapse
 * onto a wrong site.
 */
export function proposeSiteCell(args: {
  rawAddress: string;
  keyNumber?: string | null;
}): SiteProposal | null {
  const normalized = normalizeAddress(args.rawAddress);
  if (normalized === null) return null;

  const keyNumber = canonicaliseKeyNumber(args.keyNumber);
  const lookupKey = deriveLookupKey(normalized, keyNumber);
  const proposedCellId = computeSiteCellId(normalized, keyNumber);

  return {
    kind: 'propose',
    proposedCellId,
    lookupKey,
    normalizedAddress: normalized,
    keyNumber,
    rawAddress: args.rawAddress,
  };
}

/**
 * Composed entry point: normalize → propose → query view → branch.
 *
 * The contract is the keystone property of D-RTC.1:
 *
 *   Two reingest passes over the same physical site produce the same
 *   `cellId`, regardless of address spelling variations the operator's
 *   gmail history happens to contain.
 *
 * Returns `null` for unsupported input — callers should hold those
 * proposals for operator review (per PRD §D-RTC.1 acceptance gate).
 */
export async function findOrPropose(
  args: { rawAddress: string; keyNumber?: string | null },
  view: SitesView,
): Promise<SiteDedupeResult | null> {
  const proposal = proposeSiteCell(args);
  if (proposal === null) return null;

  const existing = await view.findByLookupKey(proposal.lookupKey);
  if (existing !== null) {
    return {
      kind: 'match',
      cellId: existing,
      lookupKey: proposal.lookupKey,
      normalizedAddress: proposal.normalizedAddress,
      keyNumber: proposal.keyNumber,
      rawAddress: proposal.rawAddress,
    };
  }
  return proposal;
}

/* ──────────────────────────────────────────────────────────────────────
 * Internals (exported for parity-oracle testing only)
 * ────────────────────────────────────────────────────────────────────── */

/**
 * Reingest-namespaced site cell id formula.
 *
 *   SHA-256("reingest.site.v1|" + normalized + "|" + (keyNumber ?? ""))
 *
 * Intentionally namespaced apart from `brain-rpc.ts::computeSiteCellId`
 * (which uses `oddjobz.site.v2|<weak-normalized>|<keyNum>|<fullAddress>`)
 * — the V1 production sites are throwaway test data and will be rebuilt
 * from gmail with strong normalization.
 */
export function computeSiteCellId(
  normalizedAddress: string,
  keyNumber: string | null,
): string {
  const h = createHash('sha256');
  h.update('reingest.site.v1|', 'utf8');
  h.update(normalizedAddress, 'utf8');
  h.update('|', 'utf8');
  h.update(keyNumber ?? '', 'utf8');
  return h.digest('hex');
}

/** `<normalized>|<keyNumber>` — what the sites_store hashmap indexes on. */
export function deriveLookupKey(
  normalizedAddress: string,
  keyNumber: string | null,
): string {
  return `${normalizedAddress}|${keyNumber ?? ''}`;
}

/** Strip whitespace + lowercase the key-number (so "Unit 2" → "2"). */
function canonicaliseKeyNumber(raw: unknown): string | null {
  if (raw === null || raw === undefined) return null;
  if (typeof raw !== 'string') return null;
  const trimmed = raw.trim().toLowerCase();
  if (trimmed.length === 0) return null;
  // Operators commonly write "Unit 2", "U2", "Apt 5", "Lot 17" as the
  // sub-address. The address normalizer already canonicalises unit
  // prefixes into the main address string; here we just want the bare
  // number/identifier as the dedupe discriminator.
  const m = trimmed.match(/^(?:unit|u|apt|apartment|suite|ste|flat|fl|shop|lot)\s*([a-z0-9-]+)$/i);
  if (m) return m[1] ?? trimmed;
  return trimmed;
}

```
