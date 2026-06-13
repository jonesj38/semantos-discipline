---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/dispatch/dispatch/src/cell-types/validators.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.515445+00:00
---

# packages/dispatch/dispatch/src/cell-types/validators.ts

```ts
/**
 * D-O11 phase O11b — field-level validators for dispatch cell types.
 * Mirrors the shape of `@semantos/oddjobz`'s validators.
 */

const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const ISO_DATE_RE =
  /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,9})?(?:Z|[+-]\d{2}:\d{2})$/;
const HEX_RE = /^[0-9a-f]*$/;
const TENANT_HAT_RE = /^[a-z0-9.-]+#[a-z0-9-]+$/;

export function assertUuid(
  field: string,
  value: unknown,
): asserts value is string {
  if (typeof value !== 'string' || !UUID_RE.test(value)) {
    throw new Error(`field ${field}: not a UUID v4 string`);
  }
}

export function assertNonEmptyString(
  field: string,
  value: unknown,
): asserts value is string {
  if (typeof value !== 'string' || value.length === 0) {
    throw new Error(`field ${field}: not a non-empty string`);
  }
}

export function assertIsoDateString(
  field: string,
  value: unknown,
): asserts value is string {
  if (typeof value !== 'string' || !ISO_DATE_RE.test(value)) {
    throw new Error(`field ${field}: not an ISO-8601 datetime string`);
  }
}

export function assertHex(
  field: string,
  value: unknown,
): asserts value is string {
  if (typeof value !== 'string' || !HEX_RE.test(value) || value.length % 2 !== 0) {
    throw new Error(`field ${field}: not a lower-case even-length hex string`);
  }
}

export function assertTenantHatRef(
  field: string,
  value: unknown,
): asserts value is string {
  if (typeof value !== 'string' || !TENANT_HAT_RE.test(value)) {
    throw new Error(
      `field ${field}: not a tenant-hat reference (expected '<domain>#<hat-id>')`,
    );
  }
}

export function assertEnum<T extends string>(
  field: string,
  value: unknown,
  allowed: readonly T[],
): asserts value is T {
  if (typeof value !== 'string' || !(allowed as readonly string[]).includes(value)) {
    throw new Error(`field ${field}: not one of [${allowed.join(',')}]`);
  }
}

```
