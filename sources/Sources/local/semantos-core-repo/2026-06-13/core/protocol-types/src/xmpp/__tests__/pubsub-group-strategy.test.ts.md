---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/xmpp/__tests__/pubsub-group-strategy.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.903551+00:00
---

# core/protocol-types/src/xmpp/__tests__/pubsub-group-strategy.test.ts

```ts
/**
 * D-XMPP-pubsub-type tests — type-multicast group strategy backed by the real
 * Phase-34A deriveMulticastGroup / whatPrefixGroup.
 *
 *   1. buildTypeGroupTable pre-derives the leaf + WHAT-prefix groups
 *   2. groupForObject publishes to the exact-type leaf multicast node
 *   3. groupForQuery with a whatPath resolves to the WHAT-prefix collection node
 *      (subscribe to the whole domain)
 *   4. unknown typeHash degrades to the flat urn:type: node, never drops
 */

import { describe, it, expect } from '@jest/globals';
import { buildTypeGroupTable, makeTypeGroupStrategies } from '../pubsub-group-strategy';
import { deriveMulticastGroup, whatPrefixGroup, type TypeAxes } from '../../mnca/srv6';
import type { NetworkQuery, PublishableObject } from '../../network';

const TICK_AXES: TypeAxes = { what: 'mnca.tile', how: 'tick' };
const INJ_AXES: TypeAxes = { what: 'mnca.tile', how: 'injection' };
const TICK_HASH = 'hash-tile-tick';
const INJ_HASH = 'hash-tile-injection';

function obj(typeHash: string): PublishableObject {
  return {
    cellBytes: new Uint8Array(1024),
    semanticPath: 'mnca/tile',
    contentHash: '00'.repeat(32),
    ownerCert: 'a'.repeat(32),
    typeHash,
  };
}

describe('buildTypeGroupTable + makeTypeGroupStrategies', () => {
  it('publishes an object to its exact-type leaf multicast node', async () => {
    const table = await buildTypeGroupTable([{ typeHash: TICK_HASH, axes: TICK_AXES }]);
    const { groupForObject } = makeTypeGroupStrategies(table, 'pubsub.home');

    const expected = await deriveMulticastGroup(TICK_AXES);
    const addr = groupForObject(obj(TICK_HASH));
    expect(addr.service).toBe('pubsub.home');
    expect(addr.node).toBe(expected);
    expect(addr.node).toMatch(/^ff15:/); // site-local scope, real IPv6 group
  });

  it('resolves a whatPath query to the WHAT-prefix collection node', async () => {
    const table = await buildTypeGroupTable([
      { typeHash: TICK_HASH, axes: TICK_AXES },
      { typeHash: INJ_HASH, axes: INJ_AXES },
    ]);
    const { groupForQuery } = makeTypeGroupStrategies(table, 'pubsub.home', {
      whatPathFor: (q: NetworkQuery) => q.path, // test maps query.path → WHAT axis
    });

    const expectedPrefix = await whatPrefixGroup('mnca.tile');
    const addr = groupForQuery({ path: 'mnca.tile' });
    expect(addr).not.toBeNull();
    expect(addr!.node).toBe(expectedPrefix);
    expect(addr!.node.endsWith('::')).toBe(true); // collection prefix, not a leaf
  });

  it('falls back to the leaf node for a typeHash-only query', async () => {
    const table = await buildTypeGroupTable([{ typeHash: TICK_HASH, axes: TICK_AXES }]);
    const { groupForQuery } = makeTypeGroupStrategies(table, 'pubsub.home');
    const expected = await deriveMulticastGroup(TICK_AXES);
    expect(groupForQuery({ typeHash: TICK_HASH })!.node).toBe(expected);
  });

  it('degrades an unknown typeHash to the flat urn:type node (never drops)', async () => {
    const table = await buildTypeGroupTable([{ typeHash: TICK_HASH, axes: TICK_AXES }]);
    const { groupForObject, groupForQuery } = makeTypeGroupStrategies(table, 'pubsub.home');
    expect(groupForObject(obj('unknown-hash')).node).toBe('urn:type:unknown-hash');
    expect(groupForQuery({ typeHash: 'unknown-hash' })!.node).toBe('urn:type:unknown-hash');
  });

  it('returns null for a query naming neither whatPath nor typeHash', async () => {
    const table = await buildTypeGroupTable([]);
    const { groupForQuery } = makeTypeGroupStrategies(table, 'pubsub.home');
    expect(groupForQuery({})).toBeNull();
  });
});

```
