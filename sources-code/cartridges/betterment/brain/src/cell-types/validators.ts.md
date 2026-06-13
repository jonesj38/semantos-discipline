---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/betterment/brain/src/cell-types/validators.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.567220+00:00
---

# cartridges/betterment/brain/src/cell-types/validators.ts

```ts
/**
 * Lightweight payload validators for self cellTypes.
 *
 * Per Todd's T7 direction: brain integration is light; most interaction
 * happens in-app (Flutter PWA), brain only sees cells at ratification time.
 * These validators are the ratification-time gate — they assert the
 * minimum invariants on incoming payloads from the in-app draft state.
 *
 * Mirrors `cartridges/oddjobz/brain/src/cell-types/validators.ts` shape
 * but trimmed to what self actually needs.
 */

export function assertString(v: unknown, field: string): asserts v is string {
  if (typeof v !== 'string') {
    throw new Error(`self/cell-types: '${field}' must be a string (got ${typeof v})`);
  }
}

export function assertNonEmptyString(v: unknown, field: string): asserts v is string {
  assertString(v, field);
  if (v.length === 0) {
    throw new Error(`self/cell-types: '${field}' must be a non-empty string`);
  }
}

export function assertOptionalString(v: unknown, field: string): asserts v is string | undefined {
  if (v === undefined) return;
  assertString(v, field);
}

export function assertNumber(v: unknown, field: string): asserts v is number {
  if (typeof v !== 'number' || !Number.isFinite(v)) {
    throw new Error(`self/cell-types: '${field}' must be a finite number (got ${v})`);
  }
}

export function assertOptionalNumber(v: unknown, field: string): asserts v is number | undefined {
  if (v === undefined) return;
  assertNumber(v, field);
}

export function assertEnum<T extends string>(
  v: unknown,
  field: string,
  allowed: readonly T[],
): asserts v is T {
  assertString(v, field);
  if (!(allowed as readonly string[]).includes(v)) {
    throw new Error(
      `self/cell-types: '${field}' must be one of ${allowed.join('|')} (got ${JSON.stringify(v)})`,
    );
  }
}

export function assertOptionalEnum<T extends string>(
  v: unknown,
  field: string,
  allowed: readonly T[],
): asserts v is T | undefined {
  if (v === undefined) return;
  assertEnum(v, field, allowed);
}

export function assertIsoDateString(v: unknown, field: string): asserts v is string {
  assertString(v, field);
  if (Number.isNaN(Date.parse(v))) {
    throw new Error(`self/cell-types: '${field}' must be an ISO date string (got ${v})`);
  }
}

export function assertOptionalIsoDateString(
  v: unknown,
  field: string,
): asserts v is string | undefined {
  if (v === undefined) return;
  assertIsoDateString(v, field);
}

```
