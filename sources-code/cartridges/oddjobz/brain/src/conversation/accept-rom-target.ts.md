---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/src/conversation/accept-rom-target.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.526789+00:00
---

# cartridges/oddjobz/brain/src/conversation/accept-rom-target.ts

```ts
/**
 * U1 — `accept_rom` targetJson money-channel builder (pure).
 *
 * The decision-independent, env-free core of the structured-cell
 * submit seam (DECISION-P4C, option (ii)-pure). Per
 * `docs/spec/oddjobz-intent-cell-v1.md`, an `accept_rom` intent
 * carries `originalIntent.targetJson` — a stringified, all-optional
 * `{jobId, customerId, costMin, costMax, currency}`. When present and
 * parseable the brain's `intent_action_router` honours the resolved
 * ids directly and, on an `accept_rom`-class action, mints an accepted
 * `auto_rom` Estimate from the ROM **range** (`intent_action_router.
 * parseTargetCost`, shipped `ae9eabb`) instead of the
 * intent-summary substring heuristic.
 *
 * Canonical money fields: `costMin`/`costMax`, BOTH integers in the
 * smallest currency unit (cents for AUD/USD, sats for BSV). A ROM is a
 * range; `amount` (single integer) is only an accepted point-collapse
 * alias (costMin == costMax == amount) and is intentionally NOT
 * emitted here — we always emit the explicit range.
 *
 * This module is deliberately pure + has NO `@semantos/intent`
 * dependency: it produces the exact wire string the (env-gated)
 * pipeline integration will place on `originalIntent.targetJson`.
 * That keeps the money-channel contract unit-testable in any context
 * and isolates it from the Intent/SIR-lexicon construction (the
 * focused integration unit, patterned on `tools/voice-extract.ts`).
 */

/** Spec cap: encoded targetJson ≤ 1 KiB. */
export const TARGET_JSON_MAX_BYTES = 1024;

export interface AcceptRomTargetInput {
  /** Resolved job id (UUID) — omit when not yet resolved. */
  readonly jobId?: string | null;
  /** Resolved customer id (UUID) — omit when not yet resolved. */
  readonly customerId?: string | null;
  /** ROM lower bound, smallest currency unit (e.g. cents). Integer. */
  readonly costMin: number;
  /** ROM upper bound, smallest currency unit. Integer, ≥ costMin. */
  readonly costMax: number;
  /** ISO-4217 (AUD/USD) or 'BSV'. Defaults to 'AUD' (oddjobz AU). */
  readonly currency?: string;
}

export interface AcceptRomTarget {
  readonly jobId?: string;
  readonly customerId?: string;
  readonly costMin: number;
  readonly costMax: number;
  readonly currency: string;
}

function isIntCents(n: unknown): n is number {
  return typeof n === 'number' && Number.isInteger(n) && n >= 0 && Number.isFinite(n);
}

/**
 * Build the canonical `accept_rom` target object. Throws on a
 * malformed money range (caller bug — surfaced, never silently
 * coerced; the safe-default contract: a bad range must NOT become a
 * fabricated price downstream).
 */
export function buildAcceptRomTarget(
  input: AcceptRomTargetInput,
): AcceptRomTarget {
  if (!isIntCents(input.costMin) || !isIntCents(input.costMax)) {
    throw new Error(
      'accept_rom target: costMin/costMax must be non-negative integers (smallest currency unit)',
    );
  }
  if (input.costMax < input.costMin) {
    throw new Error('accept_rom target: costMax < costMin');
  }
  const currency = (input.currency ?? 'AUD').trim() || 'AUD';
  const out: AcceptRomTarget = {
    costMin: input.costMin,
    costMax: input.costMax,
    currency,
    // Only include ids when genuinely resolved (non-empty) — the
    // spec's fields are all-optional; an empty/blank id must be
    // omitted, not emitted as "".
    ...(input.jobId && input.jobId.trim() ? { jobId: input.jobId.trim() } : {}),
    ...(input.customerId && input.customerId.trim()
      ? { customerId: input.customerId.trim() }
      : {}),
  };
  return out;
}

/**
 * Serialise to the exact `originalIntent.targetJson` wire string.
 * Stable key order (jobId, customerId, costMin, costMax, currency) so
 * the string is deterministic for hashing / idempotency. Enforces the
 * 1 KiB spec cap.
 */
export function serialiseAcceptRomTarget(t: AcceptRomTarget): string {
  const ordered: Record<string, unknown> = {};
  if (t.jobId !== undefined) ordered.jobId = t.jobId;
  if (t.customerId !== undefined) ordered.customerId = t.customerId;
  ordered.costMin = t.costMin;
  ordered.costMax = t.costMax;
  ordered.currency = t.currency;
  const s = JSON.stringify(ordered);
  const bytes = Buffer.byteLength(s, 'utf8');
  if (bytes > TARGET_JSON_MAX_BYTES) {
    throw new Error(
      `accept_rom targetJson ${bytes}B exceeds ${TARGET_JSON_MAX_BYTES}B spec cap`,
    );
  }
  return s;
}

/** Convenience: input → wire string in one call. */
export function acceptRomTargetJson(input: AcceptRomTargetInput): string {
  return serialiseAcceptRomTarget(buildAcceptRomTarget(input));
}

```
