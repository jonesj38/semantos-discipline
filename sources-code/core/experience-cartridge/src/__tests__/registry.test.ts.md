---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/experience-cartridge/src/__tests__/registry.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.953484+00:00
---

# core/experience-cartridge/src/__tests__/registry.test.ts

```ts
/**
 * RM-011 registry tests — `cartridgeRegistry.register / list / byName`.
 *
 * Acceptance: registry rejects a second registration of the same id
 * with an incompatible major version.
 */
import { afterEach, describe, expect, test } from 'bun:test';
import { cartridgeRegistry } from '../registry.js';
import { loadCartridge } from '../loader.js';
import { CartridgeRegistrationError } from '../types.js';

function cartridge(id: string, version: string) {
  return loadCartridge({
    manifest: { id, version, description: '' },
  });
}

afterEach(() => cartridgeRegistry.clear());

describe('cartridgeRegistry', () => {
  test('R1 register + list + byName', () => {
    const c = cartridge('a', '0.1.0');
    cartridgeRegistry.register(c);
    expect(cartridgeRegistry.list()).toHaveLength(1);
    expect(cartridgeRegistry.byName('a')?.manifest.version).toBe('0.1.0');
  });

  test('R2 different ids coexist', () => {
    cartridgeRegistry.register(cartridge('a', '0.1.0'));
    cartridgeRegistry.register(cartridge('b', '0.1.0'));
    expect(cartridgeRegistry.list()).toHaveLength(2);
  });

  test('R3 same major + higher minor replaces (in-process upgrade)', () => {
    cartridgeRegistry.register(cartridge('a', '0.1.0'));
    cartridgeRegistry.register(cartridge('a', '0.2.0'));
    expect(cartridgeRegistry.byName('a')?.manifest.version).toBe('0.2.0');
    expect(cartridgeRegistry.list()).toHaveLength(1);
  });

  test('R4 incompatible major rejects with INCOMPATIBLE_VERSION', () => {
    cartridgeRegistry.register(cartridge('a', '0.1.0'));
    try {
      cartridgeRegistry.register(cartridge('a', '1.0.0'));
      throw new Error('expected rejection');
    } catch (e) {
      expect(e).toBeInstanceOf(CartridgeRegistrationError);
      if (!(e instanceof CartridgeRegistrationError)) return;
      expect(e.code).toBe('INCOMPATIBLE_VERSION');
      expect(e.cartridgeId).toBe('a');
      expect(e.existing).toBe('0.1.0');
      expect(e.attempted).toBe('1.0.0');
    }
    // The earlier registration is preserved.
    expect(cartridgeRegistry.byName('a')?.manifest.version).toBe('0.1.0');
  });

  test('R5 exact-version re-registration rejects with DUPLICATE_REGISTRATION', () => {
    cartridgeRegistry.register(cartridge('a', '0.1.0'));
    try {
      cartridgeRegistry.register(cartridge('a', '0.1.0'));
      throw new Error('expected rejection');
    } catch (e) {
      expect(e).toBeInstanceOf(CartridgeRegistrationError);
      if (!(e instanceof CartridgeRegistrationError)) return;
      expect(e.code).toBe('DUPLICATE_REGISTRATION');
    }
  });

  test('R6 malformed version rejects with INVALID_VERSION', () => {
    try {
      cartridgeRegistry.register(cartridge('a', 'not-a-semver'));
      throw new Error('expected rejection');
    } catch (e) {
      expect(e).toBeInstanceOf(CartridgeRegistrationError);
      if (!(e instanceof CartridgeRegistrationError)) return;
      expect(e.code).toBe('INVALID_VERSION');
      expect(e.attempted).toBe('not-a-semver');
    }
  });

  test('R7 list() returns a fresh array (cannot mutate internal state)', () => {
    cartridgeRegistry.register(cartridge('a', '0.1.0'));
    const list = cartridgeRegistry.list();
    (list as unknown as { length: number }).length = 0;
    expect(cartridgeRegistry.list()).toHaveLength(1);
  });
});

```
