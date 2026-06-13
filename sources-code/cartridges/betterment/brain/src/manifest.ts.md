---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/betterment/brain/src/manifest.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.563810+00:00
---

# cartridges/betterment/brain/src/manifest.ts

```ts
/**
 * Betterment cartridge brain manifest — TS-side re-statement of the
 * bits the brain's boot hook needs to read at first boot. Mirrors the
 * oddjobz manifest.ts shape (see
 * `cartridges/oddjobz/brain/src/manifest.ts`).
 *
 * Identity (typeHash + triple per cellType) lives in
 * `cartridges/betterment/cartridge.json`; this module just re-states
 * the capability that the operator-root cert needs in its allowlist.
 *
 * RENAME (2026-05-29): file previously declared SelfManifest +
 * SelfCapability + SELF_CAPABILITIES + selfManifest with extensionId
 * 'self' and capability name 'SELF_INQUIRY'. Renamed to free "self"
 * for the shell-level identity primitive.
 */

/** Capability the operator cert needs to mint, release, and receive
 *  within the betterment cartridge. Single capability — betterment
 *  practice is authored by the operator themselves; there's no
 *  multi-party authorisation surface in v0.1.0. */
export interface BettermentCapability {
  /** Stable name — matches cartridge.json capabilities[].name. */
  readonly name: string;
  /** Human description. */
  readonly description: string;
}

export const BETTERMENT_CAPABILITIES: readonly BettermentCapability[] = Object.freeze([
  Object.freeze({
    name: 'BETTERMENT_INQUIRY',
    description: 'Authority to create, release, and receive within the consciousness process',
  }),
]);

/** Manifest shape the brain first-boot hook reads (mirrors oddjobz's
 *  `ExtensionManifest` interface — kept local to avoid a cross-cartridge
 *  type dep for v0.1.0). */
export interface BettermentManifest {
  readonly extensionId: 'betterment';
  readonly capabilities: readonly BettermentCapability[];
}

export const bettermentManifest: BettermentManifest = Object.freeze({
  extensionId: 'betterment',
  capabilities: BETTERMENT_CAPABILITIES,
});

```
