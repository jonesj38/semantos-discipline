---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/mnca/srv6.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.898355+00:00
---

# core/protocol-types/src/mnca/srv6.ts

```ts
/**
 * SNS multicast-group derivation for MNCA cell types.
 *
 * Implements Phase 34A (docs/prd/PHASE-34-SRV6-TYPE-NETWORK-MASTER.md §2):
 *
 *   ff<scope>:WHAT[0:4]:HOW[0:4]:INST[0:4]:0000
 *
 *   WHAT[0:4] = SHA-256("what." + whatPath)[0..3]   (32 bits)
 *   HOW[0:4]  = SHA-256("how."  + howSlug)[0..3]    (32 bits)
 *   INST[0:4] = SHA-256("inst." + instPath)[0..3]   (32 bits, zeros if absent)
 *
 * This makes the cell's type path *visible at the network layer* — a node
 * subscribing to `mnca.tile.*` joins `ff15:4ed1:aabd::` and receives every
 * `mnca.tile.tick`, `mnca.tile`, and `mnca.tile.injection` broadcast
 * without additional filtering. IPv6 longest-prefix match = hierarchical
 * semantic routing. No central registry; no DHT lookup.
 *
 * Scope byte:
 *   0x15 = site-local — used for the Pi LAN / loopback demo.
 *   0x03 = realm-local — Phase 34 spec default; switch at deploy time.
 *
 * Self-contained Web Crypto only (no Node `crypto` dependency) so this
 * module runs identically on: Bun / Node, browser viz, and the Pi relay.
 *
 * D-SRS deliverable: D-SRS-sns-multicast-wire (docs/canon/deliverables.yml).
 */

import { MncaCellTypeName } from './cell-types';

// ── Type definitions ──────────────────────────────────────────────────────────

/** WHAT / HOW / optional INST axes for a semantic type triple. */
export interface TypeAxes {
  /** Domain / object class, e.g. `"mnca.tile"`. Prefix: SHA-256(`"what." + what`). */
  what: string;
  /** Operation / lifecycle phase, e.g. `"tick"`. Prefix: SHA-256(`"how." + how`). */
  how: string;
  /** Optional per-instrument qualifier. Prefix: SHA-256(`"inst." + inst`). Zeros if absent. */
  inst?: string;
}

// ── Axis decomposition table ──────────────────────────────────────────────────

/**
 * Canonical WHAT/HOW axis decomposition for every MNCA cell type.
 *
 * Rules:
 *   WHAT = the object domain that owns / emits this cell class.
 *   HOW  = the operation or lifecycle stage.
 *   INST = absent for MNCA types (no per-instrument qualifier needed).
 *
 * The WHAT grouping is deliberate — all three `mnca.tile.*` types share
 * `what: "mnca.tile"`, so any node subscribing to the WHAT-prefix group
 * `ff15:4ed1:aabd::` receives all tile-level broadcasts without re-joining.
 */
export const MNCA_TYPE_AXES: Record<MncaCellTypeName, TypeAxes> = {
  [MncaCellTypeName.TILE_TICK]:      { what: 'mnca.tile', how: 'tick'      },
  // TILE renamed from TILE_V0 under D12 / Q13-A — base-tile cell, the
  // C6-firmware-emitted propagation shape.  HOW axis stays semantically
  // meaningful ('propagate') even though segment4 in the typeHash triple
  // is empty (Q13-A: base-tile shape).
  [MncaCellTypeName.TILE]:           { what: 'mnca.tile', how: 'propagate' },
  [MncaCellTypeName.TILE_INJECTION]: { what: 'mnca.tile', how: 'injection' },
  [MncaCellTypeName.SNAPSHOT]:       { what: 'mnca',      how: 'snapshot'  },
  [MncaCellTypeName.PERTURB]:        { what: 'mnca',      how: 'perturb'   },
};

// ── Derivation ────────────────────────────────────────────────────────────────

/**
 * Site-local multicast scope byte (0x15) — the default for the Pi LAN demo.
 * Phase 34 spec uses realm-local (0x03); pass `scope` to override.
 */
export const MNCA_MULTICAST_SCOPE = 0x15 as const;

/** Return the first 4 bytes of SHA-256(`prefix.value`). */
async function axisPrefix(prefix: string, value: string): Promise<Uint8Array> {
  const data = new TextEncoder().encode(`${prefix}.${value}`);
  const digest = await globalThis.crypto.subtle.digest('SHA-256', data);
  return new Uint8Array(digest, 0, 4);
}

/**
 * Derive the IPv6 multicast group address for a WHAT/HOW/INST type triple.
 *
 * @param axes  Semantic type axes.
 * @param scope IPv6 multicast scope byte (default 0x15 = site-local).
 * @returns     Fully-expanded 8-group IPv6 address, e.g.
 *              `"ff15:4ed1:aabd:873d:e970:0000:0000:0000"`.
 *
 * @example
 * // Subscribe to all mnca.tile.tick broadcasts
 * const group = await deriveMulticastGroup({ what: 'mnca.tile', how: 'tick' });
 * // → "ff15:4ed1:aabd:873d:e970:0000:0000:0000"
 *
 * // Subscribe to ALL mnca.tile.* types via WHAT prefix
 * const prefix = await whatPrefixGroup('mnca.tile');
 * // → "ff15:4ed1:aabd::"
 */
export async function deriveMulticastGroup(
  axes: TypeAxes,
  scope: number = MNCA_MULTICAST_SCOPE,
): Promise<string> {
  const ZERO4 = new Uint8Array(4);
  const [w, h, i] = await Promise.all([
    axisPrefix('what', axes.what),
    axisPrefix('how', axes.how),
    axes.inst ? axisPrefix('inst', axes.inst) : Promise.resolve(ZERO4),
  ]);

  const hex2 = (b: number) => b.toString(16).padStart(2, '0');
  const group = (b: Uint8Array) =>
    `${hex2(b[0]!)}${hex2(b[1]!)}:${hex2(b[2]!)}${hex2(b[3]!)}`;
  const sc = hex2(scope & 0xff);

  return `ff${sc}:${group(w)}:${group(h)}:${group(i)}:0000`;
}

/**
 * Derive the IPv6 multicast group for a canonical MNCA cell type name.
 * Convenience wrapper over `deriveMulticastGroup` + `MNCA_TYPE_AXES`.
 *
 * @example
 * const group = await multicastGroupForMncaType(MncaCellTypeName.TILE_TICK);
 * // → "ff15:4ed1:aabd:873d:e970:0000:0000:0000"
 */
export async function multicastGroupForMncaType(
  name: MncaCellTypeName,
  scope: number = MNCA_MULTICAST_SCOPE,
): Promise<string> {
  return deriveMulticastGroup(MNCA_TYPE_AXES[name], scope);
}

/**
 * Derive the WHAT-axis prefix group that covers all types sharing a domain.
 *
 * Nodes subscribing to this group join `ff<scope>:WHAT[0:4]::` and receive
 * cells from *every* HOW/INST variant under that WHAT domain via IPv6
 * longest-prefix match. This is the semantic "subscribe to a topic tree"
 * primitive — no explicit enumeration of subtypes required.
 *
 * @example
 * const prefix = await whatPrefixGroup('mnca.tile');
 * // → "ff15:4ed1:aabd::"
 * // Covers TILE_TICK, TILE_V0, TILE_INJECTION — all share what="mnca.tile"
 */
export async function whatPrefixGroup(
  whatPath: string,
  scope: number = MNCA_MULTICAST_SCOPE,
): Promise<string> {
  const w = await axisPrefix('what', whatPath);
  const hex2 = (b: number) => b.toString(16).padStart(2, '0');
  const sc = hex2(scope & 0xff);
  return `ff${sc}:${hex2(w[0]!)}${hex2(w[1]!)}:${hex2(w[2]!)}${hex2(w[3]!)}::`;
}

// ── Pinned known-answer table ─────────────────────────────────────────────────

/**
 * Pinned multicast group addresses for all MNCA cell types at scope 0x15.
 *
 * Computed by `deriveMulticastGroup` on 2026-05-23 and frozen. These are
 * the addresses mesh-nodes join and the bridge listens to.
 *
 * If any value changes, nodes on the old group stop receiving cells from
 * nodes on the new group — treat this table as append-only.
 *
 * Structure of each address:
 *   ff15 : WHAT[0:2] : WHAT[2:4] : HOW[0:2] : HOW[2:4] : 0000 : 0000 : 0000
 */
export const MNCA_MULTICAST_GROUPS: Record<MncaCellTypeName, string> = {
  [MncaCellTypeName.TILE_TICK]:      'ff15:4ed1:aabd:873d:e970:0000:0000:0000',
  // TILE renamed from TILE_V0 under D12/Q13-A; HOW axis is now 'propagate'
  // (was 'v0' pre-T3.b).  New address derived from sha256("how.propagate")[0:4].
  [MncaCellTypeName.TILE]:           'ff15:4ed1:aabd:87fb:29bc:0000:0000:0000',
  [MncaCellTypeName.TILE_INJECTION]: 'ff15:4ed1:aabd:52a2:420c:0000:0000:0000',
  [MncaCellTypeName.SNAPSHOT]:       'ff15:60d4:edd5:7b2a:8222:0000:0000:0000',
  [MncaCellTypeName.PERTURB]:        'ff15:60d4:edd5:1064:77f5:0000:0000:0000',
};

/**
 * The WHAT-prefix group for all `mnca.tile.*` types.
 * Join this group to receive TILE_TICK + TILE + TILE_INJECTION broadcasts
 * on a router that supports IPv6 SSM longest-prefix match.
 * On the demo mesh (Bun / Pi), join the individual type groups instead
 * (most IPv6 stacks don't expose SSM prefix matching at the socket level).
 */
export const MNCA_TILE_WHAT_PREFIX_GROUP = 'ff15:4ed1:aabd::';

/**
 * The canonical mesh-node broadcast group for `mnca.tile.tick`.
 *
 * This replaces the legacy `ff15::5e:1` convention — the address is now
 * derived from the cell type's semantic axes, not a hand-assigned suffix.
 * Write this into `multicast.group` in node configs to wire D-SRS-sns-multicast-wire.
 */
export const MNCA_TILE_TICK_GROUP = MNCA_MULTICAST_GROUPS[MncaCellTypeName.TILE_TICK];

```
