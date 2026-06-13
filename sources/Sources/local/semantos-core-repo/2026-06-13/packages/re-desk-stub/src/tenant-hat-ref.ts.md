---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/re-desk-stub/src/tenant-hat-ref.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.536466+00:00
---

# packages/re-desk-stub/src/tenant-hat-ref.ts

```ts
/**
 * D-O11 phase O11a — tenant-hat reference syntax.
 *
 * A tenant-hat reference is a string of the form `<domain>#<hat-id>`,
 * e.g. `oddjobtodd.info#tradie-todd`. The substring before the `#` is
 * the receiving tenant's brain-routable domain (the brain whose `/api/v1/
 * bundle` endpoint the dispatch envelope is posted to via SignedBundle
 * mesh transport — D-W1 Phase 4). The substring after is the hat-id
 * within that tenant whose context-tag the envelope's accept-handler
 * keys against (per D-O7 hat-scoping; the K3 cryptographic isolation
 * proven in `proofs/lean/Semantos/Theorems/DomainIsolationK3.lean`).
 *
 * Why a single delimiter:
 *  - operator-readable: a PM operator can type
 *    `oddjobtodd.info#tradie-todd` into a UI without escaping.
 *  - unambiguous-to-parse: domain syntax forbids `#`; hat-ids are
 *    `[a-z0-9-]+`. One `#` ⇒ one split.
 *  - extensible: future revisions can use additional delimiters
 *    (`?` for query params, `@` for revision pinning) without
 *    reshaping the canonical form.
 *
 * The shape is documented in `docs/canon/glossary.yml` under
 * `tenant-hat-reference` (added by D-O11).
 */

const TENANT_HAT_RE = /^([a-z0-9.-]+)#([a-z0-9-]+)$/;

export interface TenantHatRef {
  readonly tenantDomain: string;
  readonly hatId: string;
}

export class InvalidTenantHatRefError extends Error {
  constructor(input: string) {
    super(
      `not a tenant-hat reference: ${JSON.stringify(input)} (expected '<domain>#<hat-id>')`,
    );
    this.name = 'InvalidTenantHatRefError';
  }
}

/**
 * Parse a tenant-hat reference. Throws `InvalidTenantHatRefError`
 * on malformed input.
 */
export function parseTenantHatRef(input: string): TenantHatRef {
  const m = TENANT_HAT_RE.exec(input);
  if (m === null || m[1] === undefined || m[2] === undefined) {
    throw new InvalidTenantHatRefError(input);
  }
  return Object.freeze({
    tenantDomain: m[1],
    hatId: m[2],
  });
}

/** Format a `TenantHatRef` back to its canonical wire form. */
export function formatTenantHatRef(ref: TenantHatRef): string {
  return `${ref.tenantDomain}#${ref.hatId}`;
}

/** Type-guard: is `s` a syntactically-valid tenant-hat reference? */
export function isTenantHatRef(s: string): boolean {
  return TENANT_HAT_RE.test(s);
}

```
