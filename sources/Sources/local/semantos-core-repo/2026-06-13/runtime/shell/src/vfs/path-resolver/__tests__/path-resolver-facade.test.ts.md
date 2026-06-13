---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/shell/src/vfs/path-resolver/__tests__/path-resolver-facade.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.394443+00:00
---

# runtime/shell/src/vfs/path-resolver/__tests__/path-resolver-facade.test.ts

```ts
/**
 * VfsPathResolver facade integration test — drives every prefix
 * through the public class with stub stores. Pin the dispatch
 * behaviour the legacy resolver emitted.
 */

import { describe, expect, test } from 'bun:test';
import { VfsPathResolver } from '../path-resolver-facade';
import type { ConfigStore, IdentityStore, LoomStore } from '@semantos/runtime-services';

function makeStore(objects: Array<{ id: string; obj: unknown }>): LoomStore {
  return {
    getState: () => ({
      objects: new Map(objects.map(({ id, obj }) => [id, obj])),
    }),
  } as unknown as LoomStore;
}

function makeIdentity(hats: Array<{ certId?: string }>): IdentityStore {
  return {
    getIdentity: () => ({
      certId: 'me',
      hats,
    }),
  } as unknown as IdentityStore;
}

function makeConfig(taxonomy: unknown, flows: Array<{ id: string }> = []): ConfigStore {
  return {
    getConfig: () => ({ taxonomy, flows }),
  } as unknown as ConfigStore;
}

describe('VfsPathResolver — root + unknown paths', () => {
  const resolver = new VfsPathResolver(
    makeStore([]),
    makeIdentity([]),
    makeConfig(null),
  );

  test('1. root readdir lists all five top-level prefixes', () => {
    expect(resolver.readdir('/')?.sort()).toEqual([
      'flows',
      'governance',
      'identities',
      'objects',
      'taxonomy',
    ]);
  });

  test('2. root getattr returns a directory entry', () => {
    expect(resolver.getattr('/')).toEqual({ type: 'directory', name: '', size: 0 });
  });

  test('3. unknown top-level prefix → null on read/readdir/getattr', () => {
    expect(resolver.readdir('/garbage')).toBeNull();
    expect(resolver.read('/garbage/file')).toBeNull();
    expect(resolver.getattr('/garbage')).toBeNull();
  });

  test('4. each known top-level prefix is a directory', () => {
    for (const p of ['objects', 'identities', 'taxonomy', 'governance', 'flows']) {
      expect(resolver.getattr(`/${p}`)).toEqual({ type: 'directory', name: p, size: 0 });
    }
  });
});

describe('VfsPathResolver — objects', () => {
  const resolver = new VfsPathResolver(
    makeStore([
      {
        id: 'obj-1',
        obj: {
          payload: { foo: 'bar' },
          patches: [],
          packedCell: null,
          typeDefinition: { category: 'governance.ballot' },
          visibility: 'published',
          header: {
            magic: new Uint8Array(16),
            linearity: 1,
            version: 1,
            flags: 0,
            refCount: 1,
            typeHash: new Uint8Array(32),
            ownerId: new Uint8Array(16),
            timestamp: 0n,
            cellCount: 1,
            totalSize: 0,
            parentHash: new Uint8Array(32),
            prevStateHash: new Uint8Array(32),
            domainPayloadRoot: new Uint8Array(32),
          },
        },
      },
    ]),
    makeIdentity([]),
    makeConfig(null),
  );

  test('5. objects/ root lists ids', () => {
    expect(resolver.readdir('/objects')).toEqual(['obj-1']);
  });

  test('6. objects/<id> lists header.bin + payload.json', () => {
    expect(resolver.readdir('/objects/obj-1')?.sort()).toEqual(['header.bin', 'payload.json']);
  });

  test('7. payload.json content is valid JSON of the payload', () => {
    const out = resolver.read('/objects/obj-1/payload.json');
    expect(JSON.parse(out!.data.toString('utf-8'))).toEqual({ foo: 'bar' });
  });

  test('8. header.bin is exactly 256 bytes', () => {
    expect(resolver.read('/objects/obj-1/header.bin')!.size).toBe(256);
  });
});

describe('VfsPathResolver — identities', () => {
  const resolver = new VfsPathResolver(
    makeStore([]),
    makeIdentity([
      { certId: 'cert-A', name: 'admin', displayName: 'Admin', publicKey: 'pk', capabilities: [], derivationPath: '0' } as never,
    ]),
    makeConfig(null),
  );

  test('9. identities/ lists certIds', () => {
    expect(resolver.readdir('/identities')).toEqual(['cert-A']);
  });

  test('10. identities/<cert>/cert.json round-trips', () => {
    const out = resolver.read('/identities/cert-A/cert.json');
    const body = JSON.parse(out!.data.toString('utf-8'));
    expect(body.certId).toBe('cert-A');
    expect(body.name).toBe('admin');
  });
});

describe('VfsPathResolver — taxonomy + flows + governance', () => {
  const resolver = new VfsPathResolver(
    makeStore([
      {
        id: 'b1',
        obj: {
          payload: { motion: 'm' },
          patches: [],
          typeDefinition: { category: 'governance.ballot' },
          visibility: 'draft',
        },
      },
    ]),
    makeIdentity([]),
    makeConfig({
      dimensions: [
        {
          id: 'how',
          nodes: [{ path: 'how.x', name: 'x', axis: 'how' }],
        },
      ],
    }, [{ id: 'f1' }]),
  );

  test('11. taxonomy/ lists dimensions', () => {
    expect(resolver.readdir('/taxonomy')).toEqual(['how']);
  });

  test('12. taxonomy/<dim>/<node>.json reads the node JSON', () => {
    const out = resolver.read('/taxonomy/how/x.json');
    expect(out).not.toBeNull();
    expect(JSON.parse(out!.data.toString('utf-8')).path).toBe('how.x');
  });

  test('13. governance/ballots lists ids by category', () => {
    expect(resolver.readdir('/governance/ballots')).toEqual(['b1.json']);
  });

  test('14. flows/ lists ids', () => {
    expect(resolver.readdir('/flows')).toEqual(['f1']);
  });

  test('15. flows/<id>/active is an empty directory', () => {
    expect(resolver.readdir('/flows/f1/active')).toEqual([]);
    expect(resolver.getattr('/flows/f1/active')).toEqual({
      type: 'directory',
      name: 'active',
      size: 0,
    });
  });
});

```
