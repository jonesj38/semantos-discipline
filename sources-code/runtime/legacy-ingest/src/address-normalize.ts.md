---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/legacy-ingest/src/address-normalize.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.131019+00:00
---

# runtime/legacy-ingest/src/address-normalize.ts

```ts
/**
 * D-RTC.1 — Address normalizer.
 *
 * Reference: docs/prd/D-Reingest-Typed-Cells.md §Deliverables / D-RTC.1.
 *
 * Canonicalises a free-text Australian address string into a stable
 * lookup key for site-cell deduplication. The contract:
 *
 *   normalizeAddress("10 List Lane, Brisbane QLD 4000")
 *     → "10 list lane brisbane qld 4000"
 *
 *   normalizeAddress("10 List Ln., Brisbane, Qld 4000")
 *     → "10 list lane brisbane qld 4000"     (Ln. → lane; commas dropped)
 *
 *   normalizeAddress("Unit 2 / 15 Pine Street, North Sydney NSW 2060")
 *     → "unit 2/15 pine street north sydney nsw 2060"
 *
 * Two addresses that produce the same normalized key are treated as
 * the same physical site by `site-dedupe.ts` (D-RTC.1 sibling).
 *
 * Scope (V1 — Australian only):
 *   • Lowercase + whitespace-collapse
 *   • Suffix canonicalisation: st/str/street, rd/road, ln/lane,
 *     ave/avenue, dr/drive, ct/court, pl/place, hwy/highway, cres/
 *     crescent, blvd/boulevard, tce/terrace, pde/parade
 *   • State abbreviation canonicalisation: NSW/QLD/VIC/SA/WA/TAS/ACT/NT
 *   • Unit / sub-unit normalisation: "Unit 2 / 15" → "unit 2/15";
 *     "U2/15" → "unit 2/15"; "Apt 5, 12" → "apt 5/12"
 *   • Strip periods, commas, and double-spaces
 *   • Strip "Australia" / country suffixes (we're operating in AU)
 *
 * Out of scope: international addresses, PO boxes, complex unit
 * compound forms ("Lot 17 DP12345"), GNAF-grade canonicalisation.
 * If we see one, return null and let the operator review at
 * ratification time.
 */

/* ──────────────────────────────────────────────────────────────────────
 * Suffix + state lookup tables
 * ────────────────────────────────────────────────────────────────────── */

/** Maps street-suffix abbreviations (and common variants) to canonical form. */
const SUFFIX_CANON: ReadonlyMap<string, string> = new Map([
  // street
  ['st', 'street'], ['str', 'street'], ['street', 'street'],
  // road
  ['rd', 'road'], ['road', 'road'],
  // lane
  ['ln', 'lane'], ['lane', 'lane'],
  // avenue
  ['ave', 'avenue'], ['av', 'avenue'], ['avenue', 'avenue'],
  // drive
  ['dr', 'drive'], ['drv', 'drive'], ['drive', 'drive'],
  // court
  ['ct', 'court'], ['crt', 'court'], ['court', 'court'],
  // place
  ['pl', 'place'], ['plc', 'place'], ['place', 'place'],
  // highway
  ['hwy', 'highway'], ['highway', 'highway'],
  // crescent
  ['cres', 'crescent'], ['cr', 'crescent'], ['crescent', 'crescent'],
  // boulevard
  ['blvd', 'boulevard'], ['bvd', 'boulevard'], ['boulevard', 'boulevard'],
  // terrace
  ['tce', 'terrace'], ['ter', 'terrace'], ['terrace', 'terrace'],
  // parade
  ['pde', 'parade'], ['parade', 'parade'],
  // close
  ['cl', 'close'], ['close', 'close'],
  // way
  ['wy', 'way'], ['way', 'way'],
  // grove
  ['gr', 'grove'], ['grv', 'grove'], ['grove', 'grove'],
  // square
  ['sq', 'square'], ['square', 'square'],
]);

/** Canonical Australian state codes — kept uppercase for the lookup
 *  but emitted lowercase in the normalized output. */
const STATE_CANON: ReadonlyMap<string, string> = new Map([
  ['nsw', 'nsw'], ['new south wales', 'nsw'],
  ['qld', 'qld'], ['queensland', 'qld'],
  ['vic', 'vic'], ['victoria', 'vic'],
  ['sa', 'sa'], ['south australia', 'sa'],
  ['wa', 'wa'], ['western australia', 'wa'],
  ['tas', 'tas'], ['tasmania', 'tas'],
  ['act', 'act'], ['australian capital territory', 'act'],
  ['nt', 'nt'], ['northern territory', 'nt'],
]);

/** Country suffixes to strip (we only operate in AU for V1). */
const COUNTRY_STRIP = new Set(['australia', 'au', 'aus']);

/** Unit / sub-unit prefix tokens. "Unit 2 / 15 Pine" → "unit 2/15 pine". */
const UNIT_PREFIXES: ReadonlyMap<string, string> = new Map([
  ['unit', 'unit'], ['u', 'unit'],
  ['apt', 'apt'], ['apartment', 'apt'],
  ['suite', 'suite'], ['ste', 'suite'],
  ['flat', 'flat'], ['fl', 'flat'],
  ['shop', 'shop'],
]);

/* ──────────────────────────────────────────────────────────────────────
 * Public API
 * ────────────────────────────────────────────────────────────────────── */

/**
 * Normalize a free-text address to a stable lookup key.
 *
 * Returns `null` for empty input, obvious garbage, or addresses we
 * can't confidently canonicalise (PO boxes, international addresses,
 * lot-based legal descriptions). Callers should let those fall
 * through to operator review at ratification time.
 */
export function normalizeAddress(input: string): string | null {
  if (typeof input !== 'string') return null;
  const trimmed = input.trim();
  if (trimmed.length === 0) return null;
  if (trimmed.length > 256) return null; // pathological

  // Reject PO boxes and lot-only legal descriptions for V1. Run BEFORE
  // period-stripping below — otherwise "P.O. Box" becomes "p o  box"
  // and the bare `\bpo\b` boundary check misses.
  const lower = trimmed.toLowerCase();
  if (/\bp\.?\s*o\.?\s*box\b/.test(lower)) return null;
  if (/\blot\s+\d+\s+dp\d+/.test(lower)) return null;

  // Step 1: lowercase, strip periods (Ln. → ln), normalize unicode
  // dashes, drop commas.
  let s = lower
    .normalize('NFKC')
    .replace(/[.,]/g, ' ')
    .replace(/[‐-―]/g, '-');

  // Step 2: handle unit forms. "U2/15", "Unit 2 / 15", "Apt 5, 12"
  // (the comma already became space above) all → "unit 2/15".
  s = normalizeUnitForm(s);

  // Step 3: canonicalise multi-word state names BEFORE token-split
  // (so "new south wales" survives intact).
  for (const [variant, canon] of STATE_CANON) {
    if (variant.includes(' ')) {
      s = s.replace(new RegExp(`\\b${variant}\\b`, 'g'), canon);
    }
  }

  // Step 4: token-level canonicalisation. Split on whitespace, but
  // keep `/` glued in unit forms (already handled by step 2).
  const tokens = s.split(/\s+/).filter(t => t.length > 0);
  const canonTokens: string[] = [];
  for (const tok of tokens) {
    // Strip country suffixes entirely.
    if (COUNTRY_STRIP.has(tok)) continue;

    // Suffix canonicalisation.
    const suffixCanon = SUFFIX_CANON.get(tok);
    if (suffixCanon !== undefined) {
      canonTokens.push(suffixCanon);
      continue;
    }

    // Single-word state code (already-canonical) passes through.
    const stateCanon = STATE_CANON.get(tok);
    if (stateCanon !== undefined) {
      canonTokens.push(stateCanon);
      continue;
    }

    canonTokens.push(tok);
  }

  if (canonTokens.length === 0) return null;
  return canonTokens.join(' ');
}

/* ──────────────────────────────────────────────────────────────────────
 * Internals
 * ────────────────────────────────────────────────────────────────────── */

/**
 * Normalize unit/apt/suite/flat forms into `<unit-prefix> N/M`.
 *   "U2/15"        → "unit 2/15"
 *   "Unit 2 / 15"  → "unit 2/15"
 *   "Apt 5 12"     → "apt 5/12"   (post comma-strip)
 *   "Suite 304, 100" → "suite 304/100"  (post comma-strip)
 *
 * Anchors only at the start of the address. A unit prefix in the
 * middle of a string is left alone.
 */
function normalizeUnitForm(s: string): string {
  // Pattern A: "u2/15", "u 2 / 15", "u2 15" (after comma strip), etc.
  // Match an optional unit-prefix word, then a unit number, optional
  // separator (/ or space), then a street number.
  const trimmed = s.trimStart();

  // Try the explicit-word forms first ("unit", "apt", "suite", ...).
  for (const [variant, canon] of UNIT_PREFIXES) {
    if (variant === 'u' || variant === 'fl') continue; // handled separately
    const re = new RegExp(`^${variant}\\s+(\\d+)\\s*[/\\s]\\s*(\\d+)\\b`, 'i');
    const m = trimmed.match(re);
    if (m) {
      return `${canon} ${m[1]}/${m[2]} ` + trimmed.slice(m[0].length).trimStart();
    }
  }

  // Single-letter prefixes (U, Fl) with no space: "U2/15".
  const compact = trimmed.match(/^(u|fl)(\d+)\s*[/\s]\s*(\d+)\b/i);
  if (compact) {
    const canon = UNIT_PREFIXES.get(compact[1].toLowerCase()) ?? compact[1].toLowerCase();
    return `${canon} ${compact[2]}/${compact[3]} ` + trimmed.slice(compact[0].length).trimStart();
  }

  // Number/number at start without explicit unit prefix: "2/15 Pine".
  // Already canonical; leave alone.
  return s;
}

```
