---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/experience-cartridge/src/registry.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.951970+00:00
---

# core/experience-cartridge/src/registry.ts

```ts
/**
 * Cartridge registry — RM-011.
 *
 * In-memory store of registered cartridges keyed by manifest `id`. The
 * registry enforces semver major-version compatibility: registering a
 * second cartridge under the same id with a different major rejects
 * with `CartridgeRegistrationError { code: 'INCOMPATIBLE_VERSION' }`.
 *
 * The registry is intentionally global / package-scoped so any boot
 * path can register cartridges from anywhere in the app. Tests can
 * `clear()` between cases.
 */
import {
  CartridgeRegistrationError,
  type CellTypeRegistryEntry,
  type LoadedCartridge,
} from './types.js';

interface RegistryState {
  byId: Map<string, LoadedCartridge>;
}

const STATE: RegistryState = {
  byId: new Map(),
};

/** Parse a semver-ish string into [major, minor, patch]. Throws on malformed. */
function parseVersion(v: string): { major: number; minor: number; patch: number } {
  const m = /^(\d+)\.(\d+)\.(\d+)(?:[-+].*)?$/.exec(v);
  if (!m) {
    throw new CartridgeRegistrationError({
      code: 'INVALID_VERSION',
      cartridgeId: '<unknown>',
      attempted: v,
      message: `Cartridge version '${v}' is not semver (expected MAJOR.MINOR.PATCH)`,
    });
  }
  return { major: Number(m[1]), minor: Number(m[2]), patch: Number(m[3]) };
}

export interface CartridgeRegistry {
  register(cartridge: LoadedCartridge): void;
  list(): ReadonlyArray<LoadedCartridge>;
  byName(id: string): LoadedCartridge | undefined;
  /**
   * Find a cell type by its 32-byte typeHash (hex-encoded) across all
   * registered cartridges.  Returns the owning cartridge id alongside
   * the entry so consumers can attribute routing decisions.
   */
  cellTypeByHash(typeHashHex: string):
    | { cartridgeId: string; entry: CellTypeRegistryEntry }
    | undefined;
  /** Test-only: empty the registry. */
  clear(): void;
}

export const cartridgeRegistry: CartridgeRegistry = {
  register(cartridge) {
    const id = cartridge.manifest.id;
    const incoming = parseVersion(cartridge.manifest.version);
    const existing = STATE.byId.get(id);
    if (existing) {
      const existingV = parseVersion(existing.manifest.version);
      if (existingV.major !== incoming.major) {
        throw new CartridgeRegistrationError({
          code: 'INCOMPATIBLE_VERSION',
          cartridgeId: id,
          existing: existing.manifest.version,
          attempted: cartridge.manifest.version,
          message:
            `Cartridge '${id}' already registered at v${existing.manifest.version}; ` +
            `attempted v${cartridge.manifest.version} has incompatible major. ` +
            `Major-version changes require a new cartridge id.`,
        });
      }
      // Same major version — treat as a re-registration; refuse if
      // the version is identical (idempotency would mask the actual
      // boot-time duplicate). Higher minor/patch is permitted as an
      // in-process upgrade.
      if (existing.manifest.version === cartridge.manifest.version) {
        throw new CartridgeRegistrationError({
          code: 'DUPLICATE_REGISTRATION',
          cartridgeId: id,
          existing: existing.manifest.version,
          attempted: cartridge.manifest.version,
          message:
            `Cartridge '${id}' v${cartridge.manifest.version} already registered; ` +
            `re-registering the same exact version is a programming error.`,
        });
      }
    }

    // Q3 / T2.c — cross-cartridge typeHash collision check.
    //
    // Within-cartridge collisions are already rejected by
    // `loadCartridgeFromManifest`.  Here we guard the cross-cartridge
    // case: if cartridge A is already loaded with cellTypes[X] whose
    // typeHash matches cellTypes[Y] in incoming cartridge B, the
    // global registry would have two competing handlers for the same
    // 32-byte identity.  Reject the incoming cartridge with full
    // attribution so the operator knows which name claimed which side.
    //
    // Skipped when cartridge has no cellTypes (legacy/test fixtures).
    // Also skipped during in-process upgrade (same id replacing itself)
    // because the existing entries are about to be evicted.
    if (cartridge.cellTypes && cartridge.cellTypes.length > 0) {
      const incomingHashes = new Map<string, string>();
      for (const ct of cartridge.cellTypes) {
        incomingHashes.set(ct.typeHashHex, ct.manifest.name);
      }
      for (const [otherId, other] of STATE.byId.entries()) {
        if (otherId === id) continue; // in-process upgrade — about to evict
        if (!other.cellTypes) continue;
        for (const otherCt of other.cellTypes) {
          const incomingName = incomingHashes.get(otherCt.typeHashHex);
          if (incomingName !== undefined) {
            throw new CartridgeRegistrationError({
              code: 'DUPLICATE_TYPE_HASH',
              cartridgeId: id,
              existing: `${otherId}:${otherCt.manifest.name}`,
              attempted: `${id}:${incomingName}`,
              message:
                `Cartridge '${id}' cellTypes['${incomingName}'] produces typeHash ` +
                `${otherCt.typeHashHex} which is already claimed by cartridge ` +
                `'${otherId}' cellTypes['${otherCt.manifest.name}']. ` +
                `Pick a different triple — typeHashes must be globally unique ` +
                `across loaded cartridges.`,
            });
          }
        }
      }
    }

    STATE.byId.set(id, cartridge);
  },

  list() {
    return [...STATE.byId.values()];
  },

  byName(id) {
    return STATE.byId.get(id);
  },

  cellTypeByHash(typeHashHex) {
    for (const [cartridgeId, cartridge] of STATE.byId.entries()) {
      if (!cartridge.cellTypes) continue;
      for (const entry of cartridge.cellTypes) {
        if (entry.typeHashHex === typeHashHex) {
          return { cartridgeId, entry };
        }
      }
    }
    return undefined;
  },

  clear() {
    STATE.byId.clear();
  },
};

```
