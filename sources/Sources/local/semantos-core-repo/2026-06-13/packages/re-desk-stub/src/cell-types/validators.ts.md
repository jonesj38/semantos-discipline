---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/re-desk-stub/src/cell-types/validators.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.538646+00:00
---

# packages/re-desk-stub/src/cell-types/validators.ts

```ts
/**
 * Field-level validators for the re-desk-stub MaintenanceRequest cell.
 *
 * Thin shape — the stub extension intentionally avoids growing a
 * substantial schema layer. The four predicates below cover the
 * MaintenanceRequest shape; further fields (when the real re-desk
 * extension lands) can either grow this module locally or migrate to
 * a shared workspace package.
 *
 * The regex shapes mirror @semantos/oddjobz's `cell-types/validators.ts`
 * verbatim so a MaintenanceRequest is accepted/rejected consistently
 * with an OddjobzJob (relevant for cross-vertical conformance vectors).
 */

const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const ISO_DATE_RE =
  /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,9})?(?:Z|[+-]\d{2}:\d{2})$/;

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

export function assertOptionalString(
  field: string,
  value: unknown,
): asserts value is string | undefined {
  if (value !== undefined && typeof value !== 'string') {
    throw new Error(`field ${field}: not a string|undefined`);
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

export function assertEnum<T extends string>(
  field: string,
  value: unknown,
  allowed: readonly T[],
): asserts value is T {
  if (typeof value !== 'string' || !(allowed as readonly string[]).includes(value)) {
    throw new Error(
      `field ${field}: not one of [${allowed.join(',')}]`,
    );
  }
}

```
