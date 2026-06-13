---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/plexus-schema-registry/src/__tests__/recovery.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.949386+00:00
---

# core/plexus-schema-registry/src/__tests__/recovery.test.ts

```ts
/**
 * RM-012 recovery test — register, persist, evict in-memory, restore,
 * lookup succeeds. Models the H §6.2 "schemas are recoverable iff
 * persisted under the vendor identity before key loss" guarantee.
 */
import { afterEach, beforeEach, describe, expect, test } from 'bun:test';
import { SchemaRegistry } from '../registry.js';
import {
  InMemoryPersistence,
  SqliteSchemaPersistence,
  type SchemaPersistence,
} from '../persistence.js';
import type { DomainSchema } from '../types.js';

const SCHEMA_A: DomainSchema = {
  domainFlag: 0x0001fe01,
  version: 1,
  commitmentMode: 'payload-digest',
  fields: [
    { name: 'phase', offset: 0, size: 1, type: 'u8' },
    { name: 'parentHash', offset: 1, size: 32, type: 'u256' },
  ],
};

const SCHEMA_B: DomainSchema = {
  domainFlag: 0x0001fe02,
  version: 1,
  commitmentMode: 'payload-digest',
  fields: [{ name: 'txid', offset: 0, size: 32, type: 'u256' }],
};

async function runRecoveryCycle(persistence: SchemaPersistence): Promise<void> {
  // Phase 1 — register two schemas via registry A.
  const a = new SchemaRegistry({ persistence });
  await a.register(SCHEMA_A);
  await a.register(SCHEMA_B);
  expect(a.list()).toHaveLength(2);

  // Phase 2 — evict the in-memory state (simulating process restart).
  a.evict();
  expect(a.list()).toHaveLength(0);

  // Phase 3 — registry B uses the SAME persistence to restore.
  const b = new SchemaRegistry({ persistence });
  const restored = await b.loadFromPersistence();
  expect(restored).toBe(2);

  // Phase 4 — lookups succeed.
  const got = b.lookup({ domainFlag: SCHEMA_A.domainFlag, version: 1 });
  expect(got).toBeDefined();
  expect(got?.fields).toHaveLength(2);
  expect(got?.fields[0]?.name).toBe('phase');
}

describe('SchemaRegistry recovery', () => {
  test('R1 in-memory persistence round-trip', async () => {
    await runRecoveryCycle(new InMemoryPersistence());
  });

  describe('SQLite persistence', () => {
    let p: SqliteSchemaPersistence;
    beforeEach(() => {
      p = new SqliteSchemaPersistence(); // :memory:
    });
    afterEach(() => p.close());

    test('R2 SQLite persistence round-trip', async () => {
      await runRecoveryCycle(p);
    });

    test('R3 SQLite preserves signed schemas across recovery', async () => {
      const baseSigned: DomainSchema = {
        ...SCHEMA_A,
        domainFlag: 0x0001fe03,
      };

      // Stub verifier requires schemaBytes to match canonical encoding,
      // which itself excludes the authority — so we can compute the
      // canonical bytes from the unsigned form, then attach.
      const { encodeSchema } = await import('../encoding.js');
      const canonical = encodeSchema(baseSigned);
      const signed: DomainSchema = {
        ...baseSigned,
        authority: {
          cert: { certId: 'cert-z', subjectPublicKey: '02'.padEnd(66, 'b') },
          schemaSignature: 'sig-cafe',
          schemaBytes: canonical,
        },
      };

      // Register WITHOUT the verifier rejecting (StubSchemaAuthorityVerifier).
      const { StubSchemaAuthorityVerifier } = await import('../types.js');
      const a = new SchemaRegistry({
        persistence: p,
        authorityVerifier: new StubSchemaAuthorityVerifier(),
      });
      const reg = await a.register(signed);
      expect(reg.ok).toBe(true);

      // Restore in a fresh registry.
      const b = new SchemaRegistry({ persistence: p });
      await b.loadFromPersistence();
      const got = b.lookup({ domainFlag: signed.domainFlag, version: 1 });
      expect(got?.authority?.cert.certId).toBe('cert-z');
      expect(got?.authority?.schemaBytes).toEqual(signed.authority!.schemaBytes);
    });
  });
});

```
