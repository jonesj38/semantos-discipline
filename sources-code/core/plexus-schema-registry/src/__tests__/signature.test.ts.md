---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/plexus-schema-registry/src/__tests__/signature.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.950227+00:00
---

# core/plexus-schema-registry/src/__tests__/signature.test.ts

```ts
/**
 * RM-012 signature tests — `SchemaAuthority` verification via the
 * injectable `SchemaAuthorityVerifier` interface.
 */
import { describe, expect, test } from 'bun:test';
import { SchemaRegistry } from '../registry.js';
import { encodeSchema } from '../encoding.js';
import {
  StubSchemaAuthorityVerifier,
  RejectSchemaAuthorityVerifier,
  type DomainSchema,
  type SchemaAuthorityVerifier,
} from '../types.js';

function makeSchema(authorityOverride?: Partial<DomainSchema['authority']>): DomainSchema {
  const base: DomainSchema = {
    domainFlag: 0x00010110,
    version: 1,
    commitmentMode: 'payload-digest',
    fields: [{ name: 'x', offset: 0, size: 1, type: 'u8' }],
  };
  const canonical = encodeSchema(base);
  return {
    ...base,
    authority: {
      cert: { certId: 'cert-a', subjectPublicKey: '02'.padEnd(66, 'a') },
      schemaSignature: 'sig-ok',
      schemaBytes: canonical,
      ...authorityOverride,
    },
  };
}

describe('schema authority verification', () => {
  test('A1 stub verifier accepts well-formed authority with matching bytes', async () => {
    const r = new SchemaRegistry({ authorityVerifier: new StubSchemaAuthorityVerifier() });
    const result = await r.register(makeSchema());
    expect(result.ok).toBe(true);
  });

  test('A2 stub rejects when schemaBytes do not match canonical', async () => {
    const r = new SchemaRegistry({ authorityVerifier: new StubSchemaAuthorityVerifier() });
    const tampered = makeSchema({ schemaBytes: new Uint8Array([9, 9, 9]) });
    const result = await r.register(tampered);
    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.code).toBe('INVALID_AUTHORITY');
    expect(result.message).toContain('schema_signature_invalid');
  });

  test('A3 stub rejects missing signature', async () => {
    const r = new SchemaRegistry({ authorityVerifier: new StubSchemaAuthorityVerifier() });
    const noSig = makeSchema({ schemaSignature: '' });
    const result = await r.register(noSig);
    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.message).toContain('schema_signature_missing');
  });

  test('A4 stub rejects missing certId', async () => {
    const r = new SchemaRegistry({ authorityVerifier: new StubSchemaAuthorityVerifier() });
    const badCert = makeSchema({
      cert: { certId: '', subjectPublicKey: '02'.padEnd(66, 'a') },
    });
    const result = await r.register(badCert);
    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.message).toContain('authority_cert_invalid');
  });

  test('A5 reject verifier (default) refuses signed schemas', async () => {
    // No verifier supplied → RejectSchemaAuthorityVerifier kicks in.
    const r = new SchemaRegistry();
    const result = await r.register(makeSchema());
    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.code).toBe('INVALID_AUTHORITY');
  });

  test('A6 unsigned schemas pass through without authority verification', async () => {
    const r = new SchemaRegistry(); // Reject verifier by default
    const unsigned: DomainSchema = {
      domainFlag: 0x00010111,
      version: 1,
      commitmentMode: 'payload-digest',
      fields: [{ name: 'x', offset: 0, size: 1, type: 'u8' }],
    };
    const result = await r.register(unsigned);
    expect(result.ok).toBe(true);
  });

  test('A7 verify() dry-run does not register', async () => {
    const r = new SchemaRegistry({ authorityVerifier: new StubSchemaAuthorityVerifier() });
    const v = await r.verify(makeSchema());
    expect(v.ok).toBe(true);
    expect(r.list()).toHaveLength(0);
  });

  test('A8 verifier can be a custom adapter', async () => {
    let seen = 0;
    const verifier: SchemaAuthorityVerifier = {
      verifyAuthority() {
        seen += 1;
        return { ok: false, code: 'authority_cert_invalid', message: 'custom-refuse' };
      },
    };
    const r = new SchemaRegistry({ authorityVerifier: verifier });
    const result = await r.register(makeSchema());
    expect(result.ok).toBe(false);
    expect(seen).toBe(1);
    if (result.ok) return;
    expect(result.message).toContain('custom-refuse');
  });
});

describe('versioning rules (H §6.4)', () => {
  test('V1 same (flag, version) rejected as DUPLICATE_VERSION', async () => {
    const r = new SchemaRegistry();
    const s: DomainSchema = {
      domainFlag: 1,
      version: 1,
      commitmentMode: 'payload-digest',
      fields: [{ name: 'x', offset: 0, size: 1, type: 'u8' }],
    };
    await r.register(s);
    const dup = await r.register(s);
    expect(dup.ok).toBe(false);
    if (dup.ok) return;
    expect(dup.code).toBe('DUPLICATE_VERSION');
  });

  test('V2 appending fields produces a new compatible version', async () => {
    const r = new SchemaRegistry();
    const v1: DomainSchema = {
      domainFlag: 1,
      version: 1,
      commitmentMode: 'payload-digest',
      fields: [{ name: 'a', offset: 0, size: 1, type: 'u8' }],
    };
    const v2: DomainSchema = {
      domainFlag: 1,
      version: 2,
      commitmentMode: 'payload-digest',
      fields: [
        { name: 'a', offset: 0, size: 1, type: 'u8' },
        { name: 'b', offset: 1, size: 1, type: 'u8' },
      ],
    };
    expect((await r.register(v1)).ok).toBe(true);
    expect((await r.register(v2)).ok).toBe(true);
  });

  test('V3 reordering existing fields → BREAKING_CHANGE', async () => {
    const r = new SchemaRegistry();
    const v1: DomainSchema = {
      domainFlag: 1,
      version: 1,
      commitmentMode: 'payload-digest',
      fields: [
        { name: 'a', offset: 0, size: 1, type: 'u8' },
        { name: 'b', offset: 1, size: 1, type: 'u8' },
      ],
    };
    const v2Reordered: DomainSchema = {
      domainFlag: 1,
      version: 2,
      commitmentMode: 'payload-digest',
      fields: [
        { name: 'b', offset: 0, size: 1, type: 'u8' },
        { name: 'a', offset: 1, size: 1, type: 'u8' },
      ],
    };
    await r.register(v1);
    const result = await r.register(v2Reordered);
    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.code).toBe('BREAKING_CHANGE');
  });

  test('V4 changing existing field type → BREAKING_CHANGE', async () => {
    const r = new SchemaRegistry();
    const v1: DomainSchema = {
      domainFlag: 1,
      version: 1,
      commitmentMode: 'payload-digest',
      fields: [{ name: 'a', offset: 0, size: 1, type: 'u8' }],
    };
    const v2BadType: DomainSchema = {
      domainFlag: 1,
      version: 2,
      commitmentMode: 'payload-digest',
      fields: [{ name: 'a', offset: 0, size: 2, type: 'u16' }],
    };
    await r.register(v1);
    const result = await r.register(v2BadType);
    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.code).toBe('BREAKING_CHANGE');
  });

  test('V5 overlapping field offsets → INVALID_SCHEMA at register time', async () => {
    const r = new SchemaRegistry();
    const bad: DomainSchema = {
      domainFlag: 99,
      version: 1,
      commitmentMode: 'payload-digest',
      fields: [
        { name: 'a', offset: 0, size: 4, type: 'u32' },
        { name: 'b', offset: 2, size: 4, type: 'u32' }, // overlaps a
      ],
    };
    const result = await r.register(bad);
    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.code).toBe('INVALID_SCHEMA');
  });
});

```
