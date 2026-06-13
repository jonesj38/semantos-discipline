---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/plexus-schema-registry/src/persistence.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.947341+00:00
---

# core/plexus-schema-registry/src/persistence.ts

```ts
/**
 * Persistence adapter for `SchemaRegistry`.
 *
 * The registry's reads are synchronous (in-memory `Map`); writes go
 * through an injectable `SchemaPersistence` so the same registry shape
 * supports:
 *   - in-memory only (default in tests),
 *   - a bun:sqlite-backed store (default in production — sibling of
 *     `core/plexus-vendor-sdk/src/store.ts`'s certificate tables),
 *   - any custom backend a vendor wants (cloud DB, KV, etc.).
 *
 * The roadmap (RM-012) instructs us to add a `domain_schemas` table to
 * `core/plexus-vendor-sdk/src/store.ts::PlexusStore`. That integration
 * lives in a follow-up — for now this package ships a self-contained
 * SQLite adapter that mirrors what would go into PlexusStore. The
 * schema is identical, so the future merge is straight transcription.
 */
import { Database } from 'bun:sqlite';
import type { DomainSchema, SchemaLookupKey } from './types.js';

export interface SchemaPersistence {
  put(schema: DomainSchema): Promise<void> | void;
  get(key: SchemaLookupKey): Promise<DomainSchema | null> | DomainSchema | null;
  list(): Promise<ReadonlyArray<DomainSchema>> | ReadonlyArray<DomainSchema>;
  /** Optional close hook. */
  close?(): Promise<void> | void;
}

// ── In-memory adapter (test default) ────────────────────────────────

export class InMemoryPersistence implements SchemaPersistence {
  private readonly rows = new Map<string, DomainSchema>();
  put(schema: DomainSchema): void {
    this.rows.set(`${schema.domainFlag}:${schema.version}`, schema);
  }
  get(key: SchemaLookupKey): DomainSchema | null {
    return this.rows.get(`${key.domainFlag}:${key.version}`) ?? null;
  }
  list(): ReadonlyArray<DomainSchema> {
    return [...this.rows.values()];
  }
}

// ── SQLite adapter ─────────────────────────────────────────────────-

/**
 * Bun-native SQLite persistence. Table shape matches what the
 * roadmap calls for in `core/plexus-vendor-sdk/src/store.ts`'s
 * post-RM-012 form:
 *
 *   domain_schemas (
 *     domain_flag   INTEGER NOT NULL,
 *     version       INTEGER NOT NULL,
 *     fields_json   TEXT NOT NULL,        -- JSON.stringify(schema.fields)
 *     commitment_mode TEXT NOT NULL,
 *     authority_json TEXT,                 -- JSON.stringify(schema.authority)
 *     created_at    INTEGER NOT NULL,
 *     PRIMARY KEY (domain_flag, version)
 *   )
 */
export class SqliteSchemaPersistence implements SchemaPersistence {
  private readonly db: Database;
  constructor(dbPath?: string) {
    this.db = new Database(dbPath ?? ':memory:');
    this.db.exec('PRAGMA journal_mode=WAL');
    this.db.exec(`
      CREATE TABLE IF NOT EXISTS domain_schemas (
        domain_flag     INTEGER NOT NULL,
        version         INTEGER NOT NULL,
        fields_json     TEXT NOT NULL,
        commitment_mode TEXT NOT NULL,
        authority_json  TEXT,
        created_at      INTEGER NOT NULL,
        PRIMARY KEY (domain_flag, version)
      );
    `);
  }

  put(schema: DomainSchema): void {
    this.db
      .prepare(
        `INSERT OR REPLACE INTO domain_schemas
           (domain_flag, version, fields_json, commitment_mode, authority_json, created_at)
         VALUES (?, ?, ?, ?, ?, ?)`,
      )
      .run(
        schema.domainFlag,
        schema.version,
        JSON.stringify(schema.fields),
        schema.commitmentMode,
        schema.authority ? JSON.stringify(authorityToJson(schema.authority)) : null,
        Date.now(),
      );
  }

  get(key: SchemaLookupKey): DomainSchema | null {
    const row = this.db
      .prepare(
        `SELECT * FROM domain_schemas WHERE domain_flag = ? AND version = ?`,
      )
      .get(key.domainFlag, key.version) as SchemaRow | undefined;
    return row ? rowToSchema(row) : null;
  }

  list(): ReadonlyArray<DomainSchema> {
    const rows = this.db
      .prepare(`SELECT * FROM domain_schemas ORDER BY domain_flag, version`)
      .all() as SchemaRow[];
    return rows.map(rowToSchema);
  }

  close(): void {
    this.db.close();
  }
}

// ── Row marshalling ────────────────────────────────────────────────-

interface SchemaRow {
  domain_flag: number;
  version: number;
  fields_json: string;
  commitment_mode: string;
  authority_json: string | null;
  created_at: number;
}

function authorityToJson(a: NonNullable<DomainSchema['authority']>): unknown {
  return {
    cert: a.cert,
    schemaSignature: a.schemaSignature,
    // Uint8Array → hex so SQLite stores cleanly.
    schemaBytes: Array.from(a.schemaBytes)
      .map((b) => b.toString(16).padStart(2, '0'))
      .join(''),
  };
}

function authorityFromJson(s: string): NonNullable<DomainSchema['authority']> {
  const o = JSON.parse(s) as {
    cert: { certId: string; subjectPublicKey: string };
    schemaSignature: string;
    schemaBytes: string;
  };
  const bytes = new Uint8Array(o.schemaBytes.length / 2);
  for (let i = 0; i < bytes.length; i++) {
    bytes[i] = parseInt(o.schemaBytes.slice(i * 2, i * 2 + 2), 16);
  }
  return {
    cert: o.cert,
    schemaSignature: o.schemaSignature,
    schemaBytes: bytes,
  };
}

function rowToSchema(row: SchemaRow): DomainSchema {
  return {
    domainFlag: row.domain_flag,
    version: row.version,
    fields: JSON.parse(row.fields_json),
    commitmentMode: row.commitment_mode as DomainSchema['commitmentMode'],
    ...(row.authority_json
      ? { authority: authorityFromJson(row.authority_json) }
      : {}),
  };
}

```
