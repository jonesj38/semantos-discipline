---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/plexus-schema-registry/src/registry.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.947610+00:00
---

# core/plexus-schema-registry/src/registry.ts

```ts
/**
 * `SchemaRegistry` — in-memory store of `(domain_flag, version) →
 * DomainSchema`. Persistence is plugged in via an injectable adapter
 * (`persistence.ts`'s `SchemaPersistence` interface); the registry
 * itself stays pure and synchronous on the read path.
 *
 * Versioning rules (H §6.4) — enforced at `register()`:
 *   - Appending a field requires a NEW `version` and a new `typeHash`
 *     (typeHash is computed downstream; the registry only checks that
 *     the (flag, version) key is unique and that the schema is well-formed).
 *   - Reordering / removing / changing the type or size of an existing
 *     field is a BREAKING change. Register under a new `domainFlag`.
 *   - These rules are encoded in `verifyAgainstHistory()` below: a new
 *     `(flag, version)` entry is allowed only if every same-flag
 *     entry at a lower version is a strict prefix (same fields, same
 *     order, same types/sizes) of the new entry's fields.
 *
 * The registry is intentionally NOT a global singleton — consumers
 * instantiate one per Plexus identity. Use `cartridgeRegistry`-style
 * package singletons elsewhere when global access is appropriate; the
 * schema registry is per-tenant.
 */
import { encodeSchema, validateSchemaLayout } from './encoding.js';
import type { SchemaPersistence } from './persistence.js';
import {
  RejectSchemaAuthorityVerifier,
  type DomainSchema,
  type RegisterErrorCode,
  type RegisterResult,
  type SchemaAuthorityVerifier,
  type SchemaLookupKey,
  type VerifyResult,
} from './types.js';

export interface SchemaRegistryOptions {
  /** Optional persistence adapter. Defaults to in-memory only. */
  persistence?: SchemaPersistence;
  /** Optional authority verifier. If set, every signed-schema
   *  registration is verified. Defaults to `RejectSchemaAuthorityVerifier`
   *  so unsigned-or-broken authorities fail loudly. Tests inject
   *  `StubSchemaAuthorityVerifier`. */
  authorityVerifier?: SchemaAuthorityVerifier;
}

export class SchemaRegistry {
  private readonly byKey = new Map<string, DomainSchema>();
  private readonly persistence: SchemaPersistence | undefined;
  private readonly verifier: SchemaAuthorityVerifier;

  constructor(opts: SchemaRegistryOptions = {}) {
    this.persistence = opts.persistence;
    this.verifier = opts.authorityVerifier ?? new RejectSchemaAuthorityVerifier();
  }

  /**
   * Register a schema. The schema is structurally validated, then
   * checked against the registry's existing history for that
   * `domainFlag`, then (if the schema is signed) the authority is
   * verified, then it's stored.
   */
  async register(schema: DomainSchema): Promise<RegisterResult> {
    const structural = validateSchemaLayout(schema);
    if (!structural.ok) {
      return { ok: false, code: 'INVALID_SCHEMA', message: structural.message };
    }

    const versioning = this.verifyAgainstHistory(schema);
    if (!versioning.ok) return { ok: false, code: versioning.code, message: versioning.message };

    if (schema.authority) {
      const canonicalBytes = encodeSchema(schema);
      const v = await this.verifier.verifyAuthority(schema.authority, canonicalBytes);
      if (!v.ok) {
        return {
          ok: false,
          code: 'INVALID_AUTHORITY',
          message: `${v.code}: ${v.message}`,
        };
      }
    }

    this.byKey.set(keyOf(schema), schema);
    if (this.persistence) await this.persistence.put(schema);
    return { ok: true, key: { domainFlag: schema.domainFlag, version: schema.version } };
  }

  /**
   * Verify a schema would be acceptable, without persisting. Useful
   * for dry-run validation.
   */
  async verify(schema: DomainSchema): Promise<VerifyResult> {
    const structural = validateSchemaLayout(schema);
    if (!structural.ok) {
      return { ok: false, code: 'INVALID_SCHEMA', message: structural.message };
    }
    const versioning = this.verifyAgainstHistory(schema);
    if (!versioning.ok) return { ok: false, code: versioning.code, message: versioning.message };
    if (schema.authority) {
      const canonical = encodeSchema(schema);
      const v = await this.verifier.verifyAuthority(schema.authority, canonical);
      if (!v.ok) {
        return {
          ok: false,
          code: 'INVALID_AUTHORITY',
          message: `${v.code}: ${v.message}`,
        };
      }
    }
    return { ok: true };
  }

  lookup(key: SchemaLookupKey): DomainSchema | undefined {
    return this.byKey.get(keyStr(key));
  }

  list(): ReadonlyArray<DomainSchema> {
    return [...this.byKey.values()];
  }

  /**
   * Repopulate the in-memory map from the persistence adapter. Used
   * after key recovery: the vendor restores their identity backup and
   * walks the persisted `domain_schemas` rows back into a live registry.
   */
  async loadFromPersistence(): Promise<number> {
    if (!this.persistence) return 0;
    const all = await this.persistence.list();
    this.byKey.clear();
    for (const s of all) this.byKey.set(keyOf(s), s);
    return all.length;
  }

  /** Test-only: clear in-memory state without touching persistence. */
  evict(): void {
    this.byKey.clear();
  }

  // ── History check (H §6.4) ─────────────────────────────────────────

  private verifyAgainstHistory(
    schema: DomainSchema,
  ): { ok: true } | { ok: false; code: RegisterErrorCode; message: string } {
    const sameFlag = [...this.byKey.values()].filter(
      (s) => s.domainFlag === schema.domainFlag,
    );

    // Exact (flag, version) collision.
    const existingExact = sameFlag.find((s) => s.version === schema.version);
    if (existingExact) {
      return {
        ok: false,
        code: 'DUPLICATE_VERSION',
        message: `schema (domainFlag=${schema.domainFlag}, version=${schema.version}) already registered`,
      };
    }

    // Lower versions: incoming must extend each strictly.
    const lowerVersions = sameFlag
      .filter((s) => s.version < schema.version)
      .sort((a, b) => b.version - a.version);
    for (const prior of lowerVersions) {
      if (!isStrictExtension(prior, schema)) {
        return {
          ok: false,
          code: 'BREAKING_CHANGE',
          message:
            `schema (flag=${schema.domainFlag}, version=${schema.version}) ` +
            `does not strictly extend prior version ${prior.version}. ` +
            `Reordering / removing / type-changing existing fields is a breaking change; ` +
            `register under a new domainFlag.`,
        };
      }
    }
    return { ok: true };
  }
}

function keyOf(s: DomainSchema): string {
  return keyStr({ domainFlag: s.domainFlag, version: s.version });
}
function keyStr(k: SchemaLookupKey): string {
  return `${k.domainFlag}:${k.version}`;
}

/**
 * True iff `incoming` strictly extends `prior` — same first N fields
 * (by name, offset, size, type) plus any additional appended fields.
 */
function isStrictExtension(prior: DomainSchema, incoming: DomainSchema): boolean {
  if (incoming.fields.length < prior.fields.length) return false;
  if (incoming.commitmentMode !== prior.commitmentMode) return false;
  for (let i = 0; i < prior.fields.length; i++) {
    const p = prior.fields[i]!;
    const c = incoming.fields[i]!;
    if (
      p.name !== c.name ||
      p.offset !== c.offset ||
      p.size !== c.size ||
      p.type !== c.type
    ) {
      return false;
    }
  }
  return true;
}

```
