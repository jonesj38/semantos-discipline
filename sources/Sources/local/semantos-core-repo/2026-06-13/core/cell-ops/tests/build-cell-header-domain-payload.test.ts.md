---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-ops/tests/build-cell-header-domain-payload.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.823692+00:00
---

# core/cell-ops/tests/build-cell-header-domain-payload.test.ts

```ts
/**
 * RM-032 (partial) — `buildCellHeader` accepts a new `domainPayload`
 * arg that writes a 32B SHA-256 payload root at header offset 224.
 * Legacy `phase`/`dimension`/`parentHash`/`prevStateHash` args
 * continue to work alongside (full strip deferred to RM-032b).
 */
import { describe, expect, test } from 'bun:test';
import {
  buildCellHeader,
  packCell,
  unpackCell,
  computeTypeHash,
  LINEARITY,
} from '../src/cellHeader';
import {
  computeDomainPayloadRoot,
  commerceSchemaV1,
  commercePayload,
} from '@semantos/plexus-schema-registry';

const TYPE_HASH = computeTypeHash('test.example', 'lifecycle', 'inst.test');

describe('buildCellHeader — domainPayload (RM-032 partial)', () => {
  test('B1 domainPayload arg writes 32B root at header offset 224', () => {
    const root = Buffer.from(
      computeDomainPayloadRoot(
        commerceSchemaV1,
        commercePayload({ phase: 'action', dimension: 'composite' }),
      ),
    );
    const header = buildCellHeader({
      typeHash: TYPE_HASH,
      linearity: LINEARITY.LINEAR,
      ownerId: Buffer.alloc(16, 0),
      phase: 'action',
      dimension: 'composite',
      payloadSize: 0,
      domainPayload: root,
    });
    expect(header.length).toBe(256);
    expect(header.subarray(224, 256).equals(root)).toBe(true);
  });

  test('B2 unpackCell exposes domainPayloadRoot on the returned header', () => {
    const root = Buffer.from(
      computeDomainPayloadRoot(
        commerceSchemaV1,
        commercePayload({
          phase: 'outcome',
          dimension: 'what',
          parentHash: Buffer.alloc(32, 0xaa),
          prevStateHash: Buffer.alloc(32, 0xbb),
        }),
      ),
    );
    const header = buildCellHeader({
      typeHash: TYPE_HASH,
      linearity: LINEARITY.RELEVANT,
      ownerId: Buffer.alloc(16, 0),
      phase: 'outcome',
      dimension: 'what',
      payloadSize: 0,
      domainPayload: root,
    });
    const cell = packCell(header, Buffer.alloc(0));
    const { header: parsed } = unpackCell(cell);
    expect(parsed.domainPayloadRoot.equals(root)).toBe(true);
  });

  test('B3 omitted domainPayload → 32 zero bytes at offset 224', () => {
    const header = buildCellHeader({
      typeHash: TYPE_HASH,
      linearity: LINEARITY.LINEAR,
      ownerId: Buffer.alloc(16, 0),
      phase: 'parse',
      dimension: 'what',
      payloadSize: 0,
    });
    expect(header.subarray(224, 256).equals(Buffer.alloc(32, 0))).toBe(true);
  });

  test('B4 legacy commerce args still work alongside domainPayload', () => {
    // Both paths populated; both should be readable after unpack.
    const parentHash = Buffer.alloc(32, 0xcc);
    const prevState = Buffer.alloc(32, 0xdd);
    const root = Buffer.from(
      computeDomainPayloadRoot(commerceSchemaV1, commercePayload({ phase: 'codegen', dimension: 'how' })),
    );
    const header = buildCellHeader({
      typeHash: TYPE_HASH,
      linearity: LINEARITY.LINEAR,
      ownerId: Buffer.alloc(16, 0),
      phase: 'codegen',
      dimension: 'how',
      parentHash,
      prevStateHash: prevState,
      payloadSize: 0,
      domainPayload: root,
    });
    const cell = packCell(header, Buffer.alloc(0));
    const { header: parsed } = unpackCell(cell);
    expect(parsed.phase).toBe(0x05); // codegen byte
    expect(parsed.dimension).toBe(0x02); // how byte
    expect(parsed.parentHash.equals(parentHash)).toBe(true);
    expect(parsed.prevStateHash.equals(prevState)).toBe(true);
    expect(parsed.domainPayloadRoot.equals(root)).toBe(true);
  });
});

```
