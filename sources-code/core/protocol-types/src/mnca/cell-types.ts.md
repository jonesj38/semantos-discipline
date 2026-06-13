---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/mnca/cell-types.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.898914+00:00
---

# core/protocol-types/src/mnca/cell-types.ts

```ts
/**
 * MNCA cell-type names + transform graph.
 *
 * Identity (typeHash, triple, linearity) lives in
 * `cartridges/mnca/cartridge.json` `cellTypes[]` per T3.b — read at
 * brain-load time via `loadCartridgeFromManifest` from
 * `@semantos/experience-cartridge`.  This module retains:
 *
 *   - The canonical name constants (`MncaCellTypeName`) — used by
 *     `srv6.ts`, `cell-journey.ts`, etc. as readable handles.
 *   - The transform graph (`MncaTransformEdges`, `isMncaTransform`) —
 *     orthogonal to typeHash; describes which cell type can be emitted
 *     from which other cell type.  The relay-advertisement
 *     `typeHashPath` is a walk over this graph.
 *
 * Pre-T3.b history: this module also owned `computeMncaTypeHash`,
 * `buildMncaTypeHashRegistry`, and `mncaTypeHashHex` — all three were
 * deleted because the canonical typeHash for each name is now computed
 * by `buildTypeHash(s1, s2, s3, s4)` from `@semantos/protocol-types`
 * applied to the manifest triples.  Callers that need the bytes look
 * them up by name via the cartridge registry.  `MNCA_TYPE_HASH_SIZE`
 * remains for back-compat (= 32).
 *
 * D12 update: TILE_V0 was renamed to TILE (Q13-A resolution — base-tile
 * shape, operations live in segment4).
 */

export const MNCA_TYPE_HASH_SIZE = 32 as const;

/**
 * Canonical cell-type names for MNCA, matching `cartridges/mnca/cartridge.json`
 * cellTypes[].name.  Treat as append-only — changing a value changes its
 * type-hash and breaks every cell minted under the old name.
 */
export const MncaCellTypeName = {
  /** A full grid snapshot at a given tick — the durable state cell. */
  SNAPSHOT: 'mnca.snapshot',
  /** An external perturbation request (e.g. from a C6 button press). */
  PERTURB: 'mnca.perturb',
  /** A perturbation resolved into a concrete tile-local injection event. */
  TILE_INJECTION: 'mnca.tile.injection',
  /** A single tile's advance-one-step result. */
  TILE_TICK: 'mnca.tile.tick',
  /**
   * On-device tile propagation cell.  Emitted by C6 firmware after each
   * MNCA rule application.  Carries the full tile state as inner payload
   * of a forward.v1 cell so each hop pays a routing fee.
   *
   * Renamed from `mnca.tile.v0` under D12 (no version suffixes).
   * Q13-A resolution: base-tile shape — INJECTION/TICK are operations
   * on the base tile, distinguished by segment4 in the triple.
   *
   * Payload layout (matches cell_mnca.h CM_MNCA_TILE_V0_* constants):
   *   0    u16 LE  x             tile column in global grid
   *   2    u16 LE  y             tile row
   *   4    u32 LE  generation    MNCA tick counter (u32 — enough for demo)
   *   8    u8[4]   rule_id       identifies which MNCA rule was applied
   *   12   u32 LE  state_len     number of bytes in state_bytes
   *   16   u8[N]   state_bytes   row-major, 1B per grid-cell (N = state_len)
   *
   * Quorum consensus: when 2-of-3 devices emit matching tile hashes
   * (same x, y, generation, SHA-256(state_bytes)), the mesh fires a
   * cellmesh.channel_settle.v0 cell — the economic signal that the
   * generation was reached by consensus.
   */
  TILE: 'mnca.tile',

  // ── On-chain anchor state machine (PR-8 of LOCKSCRIPT-CLEAVAGE §7.2) ──

  /**
   * EPHEMERAL. The operator's request to bring a fresh MNCA computation
   * on-chain. Carries (initial_snapshot_hash, initiator_pubkey,
   * workflow_id). Handler validates + emits the initial LINEAR anchor.
   *
   * Wire format: `./anchor.ts` → `encodeMncaAnchorCreateIntent`.
   */
  ANCHOR_CREATE_INTENT: 'mnca.anchor.create.intent',

  /**
   * LINEAR. The durable anchor state. Carries (current_snapshot_hash,
   * prev_anchor_hash, generation, owner_pubkey, status). One-shot
   * destructor: consumed by a successor anchor minted from the next
   * transition.
   *
   * Wire format: `./anchor.ts` → `encodeMncaAnchor`.
   */
  ANCHOR: 'mnca.anchor',

  /**
   * EPHEMERAL. Operator's request to advance the anchor chain by one
   * tick. Carries (predecessor_anchor_hash, next_snapshot_hash,
   * next_generation, computation_proof). Handler verifies determinism,
   * emits bsv.tx.sign.request + new LINEAR anchor (status=Pending),
   * broker drives the broadcast.
   *
   * Wire format: `./anchor.ts` → `encodeMncaAnchorTransitionIntent`.
   */
  ANCHOR_TRANSITION_INTENT: 'mnca.anchor.transition.intent',

  /**
   * EPHEMERAL. Handler-emitted outcome of a transition attempt:
   * { outcome (Pending/Accepted/Rejected), txid, error_tag,
   * confirmed_generation }.
   *
   * Wire format: `./anchor.ts` → `encodeMncaAnchorTransitionResult`.
   */
  ANCHOR_TRANSITION_RESULT: 'mnca.anchor.transition.result',
} as const;
export type MncaCellTypeName = (typeof MncaCellTypeName)[keyof typeof MncaCellTypeName];

/** All canonical names, in declaration order. */
export const MNCA_CELL_TYPE_NAMES: readonly MncaCellTypeName[] = Object.freeze(
  Object.values(MncaCellTypeName),
) as readonly MncaCellTypeName[];

/**
 * Directed transform edges of the MNCA type graph. Each edge
 * `(from → to)` means: a node that holds a `from`-typed cell and a
 * registered handler can emit a `to`-typed cell. The relay-advertisement
 * `typeHashPath` is a walk over this graph.
 *
 *   perturb ──────────► tile.injection ──────► tile.tick ──────► snapshot
 *      │                                                            ▲
 *      └─────────────── (a tick may also re-perturb) ──────────────┘
 *
 * The demo's headline path is `mnca.perturb → mnca.tile.injection`
 * (§13.7): a perturbation cell minted on a C6 finds the tile owner that
 * can accept it, without the originator computing the route.
 */
export const MncaTransformEdges: ReadonlyArray<readonly [MncaCellTypeName, MncaCellTypeName]> =
  Object.freeze([
    [MncaCellTypeName.PERTURB, MncaCellTypeName.TILE_INJECTION],
    [MncaCellTypeName.TILE_INJECTION, MncaCellTypeName.TILE_TICK],
    [MncaCellTypeName.TILE_TICK, MncaCellTypeName.SNAPSHOT],
    [MncaCellTypeName.TILE_TICK, MncaCellTypeName.PERTURB],

    // PR-8: on-chain anchor state machine (LOCKSCRIPT-CLEAVAGE §7.2).
    //   create.intent → anchor              (handler emits initial anchor)
    //   anchor → anchor                     (transition: successor anchor
    //                                         with prev_anchor_hash linked)
    //   transition.intent → anchor          (handler emits the new anchor)
    //   transition.intent → transition.result (handler-emitted outcome)
    //
    // Cross-cartridge edges (NOT recorded here — those cell types live in
    // bsv-anchor-bundle, not mnca; the brain doesn't gate on cartridge
    // boundaries at typeHash level):
    //   transition.intent → bsv.tx.sign.request
    //   transition.intent → bsv.tx.broadcast.intent
    [MncaCellTypeName.ANCHOR_CREATE_INTENT, MncaCellTypeName.ANCHOR],
    [MncaCellTypeName.ANCHOR, MncaCellTypeName.ANCHOR],
    [MncaCellTypeName.ANCHOR_TRANSITION_INTENT, MncaCellTypeName.ANCHOR],
    [MncaCellTypeName.ANCHOR_TRANSITION_INTENT, MncaCellTypeName.ANCHOR_TRANSITION_RESULT],
  ]);

/** True when `(from → to)` is a declared transform edge. */
export function isMncaTransform(from: MncaCellTypeName, to: MncaCellTypeName): boolean {
  return MncaTransformEdges.some(([f, t]) => f === from && t === to);
}

/**
 * Canonical (segment1, segment2, segment3, segment4) triples for each
 * MNCA cell type.  Mirrors `cartridges/mnca/cartridge.json` cellTypes[]
 * — keep in sync (the parity test in
 * `cartridges/mnca/brain/mnca_cell_specs.zig` asserts both sides match).
 *
 * Use with `buildTypeHash` from `@semantos/protocol-types` to get the
 * 32-byte typeHash for any name, or use the `mncaTypeHash` shorthand
 * below.
 */
export const MNCA_TRIPLES: Readonly<Record<MncaCellTypeName, readonly [string, string, string, string]>> =
  Object.freeze({
    [MncaCellTypeName.SNAPSHOT]:                  ['mnca', 'standalone', 'snapshot', ''],
    [MncaCellTypeName.PERTURB]:                   ['mnca', 'standalone', 'perturb',  ''],
    [MncaCellTypeName.TILE_INJECTION]:            ['mnca', 'standalone', 'tile',     'injection'],
    [MncaCellTypeName.TILE_TICK]:                 ['mnca', 'standalone', 'tile',     'tick'],
    [MncaCellTypeName.TILE]:                      ['mnca', 'standalone', 'tile',     ''],
    [MncaCellTypeName.ANCHOR_CREATE_INTENT]:      ['mnca', 'anchor',     'create',   'intent'],
    [MncaCellTypeName.ANCHOR]:                    ['mnca', 'anchor',     '',         ''],
    [MncaCellTypeName.ANCHOR_TRANSITION_INTENT]:  ['mnca', 'anchor',     'transition', 'intent'],
    [MncaCellTypeName.ANCHOR_TRANSITION_RESULT]:  ['mnca', 'anchor',     'transition', 'result'],
  } as const);

/**
 * Synchronous 32-byte typeHash for a canonical MNCA cell type.
 *
 * Shorthand for `const [s1,s2,s3,s4] = MNCA_TRIPLES[name];
 * buildTypeHash(s1,s2,s3,s4)`.  Self-contained helper — imports
 * `buildTypeHash` lazily to keep the module tree-shake-friendly for
 * consumers that only need the names + transform graph.
 *
 * Replaces the pre-T3.b async `computeMncaTypeHash(name)`.
 */
export function mncaTypeHash(name: MncaCellTypeName): Uint8Array {
  // Lazy import via require would dodge the circular-dep risk if any,
  // but @semantos/protocol-types is self-contained — direct import is fine.
  // Doing it here at module top would force a circular-import workaround
  // if cell-types.ts were ever imported from type-hash.ts.  Static import
  // resolved at this scope:
  const [s1, s2, s3, s4] = MNCA_TRIPLES[name];
  return buildTypeHashImpl(s1!, s2!, s3!, s4!);
}

// Local re-import to dodge any circular-dep ordering issue with the
// module-level `import { buildTypeHash }` in callers.
import { buildTypeHash as buildTypeHashImpl } from '../type-hash';

```
