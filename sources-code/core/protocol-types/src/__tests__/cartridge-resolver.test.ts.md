---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/__tests__/cartridge-resolver.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.886163+00:00
---

# core/protocol-types/src/__tests__/cartridge-resolver.test.ts

```ts
/**
 * CC2a conformance — the consumes/provides resolver (Decision-B).
 *
 * Ref: docs/design/CANONICAL-CARTRIDGE-MODEL.md; commission CC2.
 * The Brain shell must load infra (which `provides`) before
 * experience (which `consumes`), reject an experience cartridge whose
 * cartridge-provided consumed interface is unmet, and treat
 * host-injected runtime adapters as exempt. Tested against the pure
 * `ExtensionLoader.resolveCartridgeOrder` (no I/O).
 */

import { describe, test, expect } from 'bun:test';
import { ExtensionLoader, ExtensionLoadError } from '../extension-loader';

describe('CC2a — resolveCartridgeOrder (Decision-B composition)', () => {
  test('infra ordered before experience; provides registry built', () => {
    const { order, providesRegistry } = ExtensionLoader.resolveCartridgeOrder([
      { id: 'oddjobz', role: 'experience', consumes: { '@semantos/spv': 'required' } },
      { id: 'wallet-headers', role: 'infra', provides: ['@semantos/spv'] },
    ]);
    expect(order).toEqual(['wallet-headers', 'oddjobz']);
    expect(providesRegistry.get('@semantos/spv')).toBe('wallet-headers');
  });

  test('runtime adapters (StorageAdapter…) are exempt — not "unmet"', () => {
    expect(() =>
      ExtensionLoader.resolveCartridgeOrder([
        {
          id: 'oddjobz',
          role: 'experience',
          consumes: { StorageAdapter: 'required', IdentityAdapter: 'required' },
        },
      ]),
    ).not.toThrow();
  });

  test('experience consuming an unprovided cartridge interface ⇒ fail-closed', () => {
    expect(() =>
      ExtensionLoader.resolveCartridgeOrder([
        { id: 'oddjobz', role: 'experience', consumes: { '@semantos/spv': 'required' } },
      ]),
    ).toThrow(ExtensionLoadError);
    try {
      ExtensionLoader.resolveCartridgeOrder([
        { id: 'oddjobz', role: 'experience', consumes: { '@semantos/spv': 'required' } },
      ]);
    } catch (e) {
      expect((e as ExtensionLoadError).message).toContain('no infra cartridge provides');
    }
  });

  test('duplicate provided interface ⇒ rejected', () => {
    expect(() =>
      ExtensionLoader.resolveCartridgeOrder([
        { id: 'a', role: 'infra', provides: ['@semantos/spv'] },
        { id: 'b', role: 'infra', provides: ['@semantos/spv'] },
      ]),
    ).toThrow(/duplicate provided interface/);
  });

  test('legacy (no role) cartridges pass through, ordered after infra', () => {
    const { order } = ExtensionLoader.resolveCartridgeOrder([
      { id: 'legacy-a' },
      { id: 'wallet', role: 'infra', provides: ['@semantos/spv'] },
      { id: 'legacy-b' },
    ]);
    expect(order[0]).toBe('wallet');
    expect(order.slice(1).sort()).toEqual(['legacy-a', 'legacy-b']);
  });
});

```
