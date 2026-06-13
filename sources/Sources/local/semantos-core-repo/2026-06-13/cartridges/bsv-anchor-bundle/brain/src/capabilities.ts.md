---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/bsv-anchor-bundle/brain/src/capabilities.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.444637+00:00
---

# cartridges/bsv-anchor-bundle/brain/src/capabilities.ts

```ts
/**
 * BSV Anchor Bundle — capability declarations.
 *
 * Page-aligned canonical domain-flag assignments per the scheme
 * documented in `extensions/oddjobz/src/capabilities.ts`:
 *
 *   0x000100xx — semantos loom-shell verbs (claimed: 0x00010001..0x0001000B)
 *   0x000101xx — oddjobz canonical caps    (claimed: 0x00010101..0x00010106)
 *   0x000102xx — bsv-anchor-bundle caps    (claimed: 0x00010201..0x00010208) ← THIS EXTENSION
 *   0x000103xx — next canonical extension  (reserved)
 *
 * Per the oddjobz capabilities.ts rationale:
 *   1. Canonical and repeatable — every deployment uses identical numbers.
 *   2. Audit-comparable across deployments.
 *   3. Pre-allocated low-bits page prevents collision with other shipping extensions.
 *
 * Eight capabilities — one per declared verb in manifest.json.
 *
 * SCAFFOLD STATUS: these declarations exist to establish the canonical
 * page allocation. The capabilities are not yet wired into the operator-
 * root cert mint pass — that lands once DLO.1b (capability mint pass
 * generalization) ships per docs/prd/D-LIFT-ODDJOBZ.md.
 */

export interface BsvAnchorCapability {
  /** Stable cap name — used by the dispatcher's CapabilitySet at the operator-surface seam. */
  readonly name: string;
  /** Stable uint32 domain flag — enforced by OP_CHECKDOMAINFLAG on the presented cap UTXO. */
  readonly domain_flag: number;
  /** Operator-readable role. */
  readonly description: string;
  /** Which holder carries the cap UTXO in steady state. */
  readonly holder: 'operator-root' | 'node-service';
}

export const BSV_ANCHOR_CAPABILITIES = [
  {
    name: 'cap.bsv-anchor.write',
    domain_flag: 0x00010201,
    description: 'Emit an anchor (commit a cell stateHash to the BSV chain).',
    holder: 'node-service',
  },
  {
    name: 'cap.bsv-anchor.read',
    domain_flag: 0x00010202,
    description: 'Verify a previously-anchored proof against the BSV chain.',
    holder: 'node-service',
  },
  {
    name: 'cap.bsv-anchor.wallet.sign',
    domain_flag: 0x00010203,
    description: 'Sign a BSV transaction under the operator-root identity cert.',
    holder: 'operator-root',
  },
  {
    name: 'cap.bsv-anchor.wallet.derive',
    domain_flag: 0x00010204,
    description: 'BRC-42 derivation under the operator-root identity cert.',
    holder: 'operator-root',
  },
  {
    name: 'cap.bsv-anchor.payment.verify',
    domain_flag: 0x00010205,
    description: 'Verify a cited payment txid via the PoW-verified header store.',
    holder: 'node-service',
  },
  {
    name: 'cap.bsv-anchor.payment.refund',
    domain_flag: 0x00010206,
    description: 'Construct + broadcast a refund tx (per WSITE5.5).',
    holder: 'operator-root',
  },
  {
    name: 'cap.bsv-anchor.headers.sync',
    domain_flag: 0x00010207,
    description: 'Sync BSV headers from a P2P peer with PoW verification.',
    holder: 'node-service',
  },
  {
    name: 'cap.bsv-anchor.headers.serve',
    domain_flag: 0x00010208,
    description: 'Long-running BHS-compatible header server (read-only HTTP).',
    holder: 'node-service',
  },
] as const satisfies readonly BsvAnchorCapability[];

export const BSV_ANCHOR_CAP_NAMES = BSV_ANCHOR_CAPABILITIES.map((c) => c.name);

export const BSV_ANCHOR_DOMAIN_FLAG_RANGE = {
  /** Inclusive low bound — first claimed flag on the 0x000102xx page. */
  low: 0x00010200,
  /** Inclusive high bound — last reserved flag on the 0x000102xx page. */
  high: 0x000102ff,
} as const;

```
