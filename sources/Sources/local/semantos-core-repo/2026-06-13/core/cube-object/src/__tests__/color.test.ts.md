---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cube-object/src/__tests__/color.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.011467+00:00
---

# core/cube-object/src/__tests__/color.test.ts

```ts
import { describe, test, expect } from 'bun:test';
import type { PlexusCert } from '@plexus/contracts';
import { pickCubeColor, certColor, AVATAR_PALETTE } from '../color.js';
import { linearityColor } from '../linearity.js';

function fakeCert(publicKey: string): PlexusCert {
  return {
    certId: '00'.repeat(32),
    publicKey,
    parentCertId: null,
    childIndex: 0,
    derivationPath: 'root',
    createdAt: 0,
  };
}

describe('color — pickCubeColor priority', () => {
  test('explicit overrides cert and linearity', () => {
    const cert = fakeCert('02deadbeef');
    expect(
      pickCubeColor({ explicit: 0xff00ff, cert, linearity: 0 }),
    ).toBe(0xff00ff);
  });

  test('cert overrides linearity when explicit is null', () => {
    const cert = fakeCert('02aabbccdd');
    const result = pickCubeColor({ explicit: null, cert, linearity: 0 });
    expect(result).not.toBe(linearityColor(0));
    expect(AVATAR_PALETTE).toContain(result);
  });

  test('linearity is the fallback when explicit is null and cert is null', () => {
    expect(pickCubeColor({ explicit: null, cert: null, linearity: 0 })).toBe(linearityColor(0));
    expect(pickCubeColor({ explicit: null, cert: null, linearity: 1 })).toBe(linearityColor(1));
    expect(pickCubeColor({ explicit: null, cert: null, linearity: 2 })).toBe(linearityColor(2));
    expect(pickCubeColor({ explicit: null, cert: null, linearity: 3 })).toBe(linearityColor(3));
  });

  test('explicit=0x000000 (black) is honored, not treated as falsy', () => {
    const cert = fakeCert('02aabbccdd');
    expect(pickCubeColor({ explicit: 0x000000, cert, linearity: 1 })).toBe(0x000000);
  });
});

describe('color — certColor determinism + spread', () => {
  test('same publicKey → same color', () => {
    const c = fakeCert('02aabbccddeeff00');
    expect(certColor(c)).toBe(certColor(c));
  });

  test('different publicKeys generally produce different colors', () => {
    const distinct = new Set<number>();
    for (let i = 0; i < 50; i++) {
      distinct.add(certColor(fakeCert(`02${i.toString(16).padStart(64, '0')}`)));
    }
    // 50 inputs → expect to hit most of the 12-color palette.
    expect(distinct.size).toBeGreaterThan(8);
  });

  test('every certColor result is in the AVATAR_PALETTE', () => {
    for (let i = 0; i < 30; i++) {
      const c = certColor(fakeCert(`02${i.toString(16).padStart(64, '0')}`));
      expect(AVATAR_PALETTE).toContain(c);
    }
  });
});

```
