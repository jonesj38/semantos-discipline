---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/tessera/brain/src/capabilities.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.639653+00:00
---

# cartridges/tessera/brain/src/capabilities.ts

```ts
/**
 * Tessera — capability declarations.
 *
 * Page-aligned canonical domain-flag assignments per the scheme
 * documented in `extensions/oddjobz/src/capabilities.ts` and the
 * V0.1 page allocation in `core/constants/constants.json`:
 *
 *   0x000100xx — semantos loom-shell verbs (claimed: 0x00010001..0x0001000B)
 *   0x000101xx — oddjobz canonical caps    (claimed: 0x00010101..0x00010106)
 *   0x000102xx — bsv-anchor-bundle caps    (claimed: 0x00010201..0x00010208)
 *   0x000103xx — next canonical extension  (reserved)
 *   0x000104xx — TESSERA                   ← THIS EXTENSION
 *
 * Within the tessera page (0x000104xx), the low byte partitions:
 *
 *   0x00       — TESSERA_PAGE base / cartridge-wide BYTEA prefix scan
 *   0x01..0x05 — primary hats (producer, distributor, retailer,
 *                club-member, consumer) per V0.1 page allocation
 *   0x1A, 0x2A — sub-hats (field-worker, dock-handler)
 *   0x10..0x17 — eight cartridge capabilities (THIS FILE)
 *   0x18..0xFF — reserved
 *
 * Eight capabilities — one per non-null `capability_required` entry in
 * `manifest.json`. Three verbs (`tessera.tamper`, `tessera.add-tasting-note`,
 * `tessera.report-quality-issue`) have `null` capability_required because
 * they are self-authorising — see TESSERA-CARTRIDGE.md §3.2.
 *
 * SCAFFOLD STATUS: these declarations establish the canonical page
 * allocation only. The capabilities are not yet wired into the
 * operator-root cert mint pass — that lands once DLO.1b (capability
 * mint pass generalisation) ships per docs/prd/D-LIFT-ODDJOBZ.md.
 */

export interface TesseraCapability {
  /** Stable cap name — used by the dispatcher's CapabilitySet at the operator-surface seam. */
  readonly name: string;
  /** Stable uint32 domain flag — enforced by OP_CHECKDOMAINFLAG on the presented cap UTXO. */
  readonly domain_flag: number;
  /** Operator-readable role. */
  readonly description: string;
  /** Which holder carries the cap UTXO in steady state. */
  readonly holder: 'operator-root' | 'node-service' | 'hat-rooted';
}

export const TESSERA_CAPABILITIES = [
  {
    name: 'cap.tessera.harvest',
    domain_flag: 0x00010410,
    description: 'Record a harvest event for a grape lot (or analogue origin cell).',
    holder: 'hat-rooted',
  },
  {
    name: 'cap.tessera.rack',
    domain_flag: 0x00010411,
    description: 'Record a racking / cellar transfer between barrels.',
    holder: 'hat-rooted',
  },
  {
    name: 'cap.tessera.blend-declare',
    domain_flag: 0x00010412,
    description: 'Declare a blend transition consuming N barrels into one. Subject to K15 conservation.',
    holder: 'hat-rooted',
  },
  {
    name: 'cap.tessera.bottle',
    domain_flag: 0x00010413,
    description: 'Bottling — produce N LINEAR bottle cells from one barrel.',
    holder: 'hat-rooted',
  },
  {
    name: 'cap.tessera.assemble',
    domain_flag: 0x00010414,
    description: 'Assemble a case from N bottles (typed SemanticRelation references).',
    holder: 'hat-rooted',
  },
  {
    name: 'cap.tessera.custody',
    domain_flag: 0x00010415,
    description: 'Transfer or confirm receipt of custody for a case / pallet / shipment.',
    holder: 'hat-rooted',
  },
  {
    name: 'cap.tessera.care-record',
    domain_flag: 0x00010416,
    description: 'Record an AFFINE care event (temp-logger reading, thermo-sticker flag).',
    holder: 'hat-rooted',
  },
  {
    name: 'cap.tessera.scan',
    domain_flag: 0x00010417,
    description: 'Anonymous consumer scan — produces a RELEVANT scan-event cell on the bottle chain.',
    holder: 'node-service',
  },
] as const satisfies readonly TesseraCapability[];

export const TESSERA_CAP_NAMES = TESSERA_CAPABILITIES.map((c) => c.name);

export const TESSERA_DOMAIN_FLAG_RANGE = {
  /** Inclusive low bound — first claimed flag on the 0x000104xx page (TESSERA_PAGE base). */
  low: 0x00010400,
  /** Inclusive high bound — last reserved flag on the 0x000104xx page. */
  high: 0x000104ff,
} as const;

```
