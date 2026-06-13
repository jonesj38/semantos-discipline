---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/src/manifest.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.475376+00:00
---

# cartridges/oddjobz/brain/src/manifest.ts

```ts
/**
 * D-O3 — Oddjobz extension manifest.
 *
 * See `docs/design/ODDJOBZ-EXTENSION-PLAN.md` §O3 (capability mints), §7
 * (boot-sequence integration: "no new top-level boot step"); D-W1 plan
 * §3 (extension-defined resources are first-class — the brain has no
 * special case for "core" vs "extension" resources).
 *
 * ── Shape ────────────────────────────────────────────────────────────
 *
 * The manifest is a plain TS record so brain's first-boot hook can read
 * `extension.capabilities` (six entries; their names + domain_flags)
 * without having extension-specific code paths in brain core. The Zig
 * counterpart at `runtime/semantos-brain/src/extensions.zig` mirrors the
 * `extensionId` and the cap-name list verbatim — keeping that mirror
 * in sync is the §O3 acceptance gate's "consistent first-boot mint"
 * constraint.
 *
 * Today the manifest is consumed by:
 *
 *   1. brain first-boot in `cmdServe`'s post-cert-init pass: the cap
 *      names below are added to the operator-root cert's allowlist
 *      via the dispatcher's `identity_certs.issue_root` (root cert
 *      carries the operator-held cap names) at boot.
 *   2. The §O4 state machines (D-O4 territory) — they read this
 *      manifest at extension load to build the FSM-edge → cap-mint
 *      lookup.
 *   3. The §9.4 recovery roundtrip — the cap set encoded in the
 *      recovery payload is exactly the entries here.
 *
 * Tomorrow (post-D-W1 Phase 2) brain will load extension manifests via
 * `extensions/<id>/manifest.json` artefacts shipped in the bundle the
 * provisioning CLI (D-O10) drops into a tenant's data dir. Today the
 * Zig side just hard-codes the oddjobz id and reads the same six cap
 * names from a Zig-mirrored constant block — kept in sync via the §9
 * acceptance gate.
 */

import {
  ODDJOBZ_CAPABILITIES,
  ODDJOBZ_CAP_TYPE_HASH_HEX,
  type OddjobzCapability,
} from './capabilities.js';

/* ══════════════════════════════════════════════════════════════════════
 * Manifest types
 * ══════════════════════════════════════════════════════════════════════ */

export interface ExtensionManifest {
  /** Stable extension id; matches the npm package suffix and the
   *  `extensions/<id>/` path. */
  readonly id: string;
  /** Semver version of the extension; used for migration detection
   *  by future provisioning + extension upgrade flows. */
  readonly version: string;
  /** Human-readable description for ops dashboards. */
  readonly description: string;
  /** Capabilities the extension declares — both the name (operator
   *  surface) and the domain flag (kernel-gate enforcement). */
  readonly capabilities: readonly OddjobzCapability[];
  /** SHA-256 of the canonical capability cell type-hash input
   *  (`oddjobz.capability:capability-mint:inst.capability.cap-token`)
   *  — fingerprinted so brain can fail loudly on a manifest/typesystem
   *  mismatch. */
  readonly capabilityTypeHashHex: string;
  /** Lexicon id this extension's caps gate over. The trades-lexicon
   *  is the home of the Job/Quote/Visit/Invoice/Customer/Site domain
   *  vocabulary the §O4 transitions consume. */
  readonly lexiconId: 'trades';
  /** Plan reference — for audit-log entries on first-boot mint. */
  readonly planRef: string;
  /** Boot-sequence hook the manifest plugs into per §7 — explicitly
   *  "step 6 — capability mint" (no new top-level step). The brain
   *  first-boot integration cites this verbatim. */
  readonly bootStep: 'step-6-capability-mint';
}

/* ══════════════════════════════════════════════════════════════════════
 * The oddjobz manifest
 * ══════════════════════════════════════════════════════════════════════ */

/**
 * The canonical oddjobz extension manifest. Frozen — every consumer
 * (brain first-boot, D-O4 FSMs, D-O5p pairing allowlist defaults,
 * recovery payload, glossary entries) reads this object verbatim.
 */
export const oddjobzManifest: ExtensionManifest = Object.freeze({
  id: 'oddjobz',
  version: '0.1.0',
  description:
    'Trades / services vertical extension — Job, Quote, Visit, Invoice, ' +
    'Customer, Site cell types (D-O2) plus the six oddjobz capabilities ' +
    '(D-O3) gating the §O4 state machines.',
  capabilities: ODDJOBZ_CAPABILITIES,
  capabilityTypeHashHex: ODDJOBZ_CAP_TYPE_HASH_HEX,
  lexiconId: 'trades',
  planRef: 'docs/design/ODDJOBZ-EXTENSION-PLAN.md §O3',
  bootStep: 'step-6-capability-mint',
});

/* ══════════════════════════════════════════════════════════════════════
 * Wire format — what brain's first-boot hook reads
 *
 * The Zig side at `runtime/semantos-brain/src/extensions.zig` doesn't read TS;
 * the manifest is mirrored in Zig as a constant block keyed by the
 * same `id` string. The two sides stay in sync via the §9 acceptance
 * gates — the `extensions.test.ts` and the Zig
 * `extensions.zig`-internal tests both iterate the same list.
 *
 * The function below produces the wire-format JSON the Semantos Brain CLI / RPC
 * layer might use post-D-O10 when extension bundles are dropped into
 * a tenant data dir.
 * ══════════════════════════════════════════════════════════════════════ */

/**
 * Serialise the manifest to the wire format brain's first-boot reads.
 * Useful for CI fixtures and the gen-vectors path.
 */
export function manifestToWire(manifest: ExtensionManifest): string {
  return JSON.stringify(
    {
      v: 1,
      id: manifest.id,
      version: manifest.version,
      description: manifest.description,
      lexiconId: manifest.lexiconId,
      planRef: manifest.planRef,
      bootStep: manifest.bootStep,
      capabilityTypeHashHex: manifest.capabilityTypeHashHex,
      capabilities: manifest.capabilities.map((c) => ({
        name: c.name,
        domainFlag: c.domainFlag,
        domainFlagHex: `0x${c.domainFlag.toString(16).padStart(8, '0')}`,
        description: c.description,
        roleInFsm: c.roleInFsm,
        gates: c.gates,
        holder: c.holder,
      })),
    },
    null,
    2,
  );
}

```
