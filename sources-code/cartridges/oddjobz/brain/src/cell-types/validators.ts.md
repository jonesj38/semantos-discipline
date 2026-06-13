---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/src/cell-types/validators.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.501785+00:00
---

# cartridges/oddjobz/brain/src/cell-types/validators.ts

```ts
/**
 * Field-level validators shared across cell-type schemas. Cheap,
 * deterministic, and side-effect-free. Throws Error on first failure.
 */

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const ISO_DATE_RE = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,9})?(?:Z|[+-]\d{2}:\d{2})$/;

export function assertUuid(field: string, value: unknown): asserts value is string {
  if (typeof value !== 'string' || !UUID_RE.test(value)) {
    throw new Error(`field ${field}: not a UUID v4 string`);
  }
}

export function assertNonEmptyString(field: string, value: unknown): asserts value is string {
  if (typeof value !== 'string' || value.length === 0) {
    throw new Error(`field ${field}: not a non-empty string`);
  }
}

export function assertOptionalString(field: string, value: unknown): asserts value is string | undefined {
  if (value !== undefined && typeof value !== 'string') {
    throw new Error(`field ${field}: not a string|undefined`);
  }
}

export function assertOptionalUuid(field: string, value: unknown): asserts value is string | undefined {
  if (value === undefined) return;
  assertUuid(field, value);
}

export function assertIsoDateString(field: string, value: unknown): asserts value is string {
  if (typeof value !== 'string' || !ISO_DATE_RE.test(value)) {
    throw new Error(`field ${field}: not an ISO-8601 datetime string`);
  }
}

export function assertOptionalIsoDateString(
  field: string,
  value: unknown,
): asserts value is string | undefined {
  if (value === undefined) return;
  assertIsoDateString(field, value);
}

export function assertNonNegativeInt(field: string, value: unknown): asserts value is number {
  if (
    typeof value !== 'number' ||
    !Number.isInteger(value) ||
    value < 0 ||
    !Number.isFinite(value)
  ) {
    throw new Error(`field ${field}: not a non-negative integer`);
  }
}

export function assertOptionalNonNegativeInt(
  field: string,
  value: unknown,
): asserts value is number | undefined {
  if (value === undefined) return;
  assertNonNegativeInt(field, value);
}

export function assertOptionalFiniteNumber(
  field: string,
  value: unknown,
): asserts value is number | undefined {
  if (value === undefined) return;
  if (typeof value !== 'number' || !Number.isFinite(value)) {
    throw new Error(`field ${field}: not a finite number|undefined`);
  }
}

export function assertOptionalBoolean(
  field: string,
  value: unknown,
): asserts value is boolean | undefined {
  if (value === undefined) return;
  if (typeof value !== 'boolean') {
    throw new Error(`field ${field}: not a boolean|undefined`);
  }
}

export function assertEnum<T extends string>(
  field: string,
  value: unknown,
  allowed: readonly T[],
): asserts value is T {
  if (typeof value !== 'string' || !allowed.includes(value as T)) {
    throw new Error(
      `field ${field}: not one of [${allowed.join('|')}], got ${JSON.stringify(value)}`,
    );
  }
}

export function assertOptionalEnum<T extends string>(
  field: string,
  value: unknown,
  allowed: readonly T[],
): asserts value is T | undefined {
  if (value === undefined) return;
  assertEnum(field, value, allowed);
}

```
