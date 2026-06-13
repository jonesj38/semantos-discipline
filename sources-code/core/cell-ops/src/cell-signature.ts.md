---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-ops/src/cell-signature.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.824014+00:00
---

# core/cell-ops/src/cell-signature.ts

```ts
/**
 * RM-096 — Typed cell signatures for cartridge authors.
 *
 * Cartridge devs compose named cells, not raw opcodes. Each cell
 * declares a pre/post stack shape; composition is type-checked at the
 * TS layer so authors get a compile-time error when one cell's `post`
 * doesn't satisfy the next cell's `pre`. The runtime is unchanged —
 * pask still emits Script — but the dev surface is finally typed.
 *
 * Stack-shape primitives are the 2-PDA's terminal types. The set here
 * is small on purpose: the trap with stack typing is over-specifying
 * (every cell author invents a new type). Eight well-known terminals
 * cover the ground today; extending is additive.
 *
 * No LLM, no autocomplete-mediated composition — the principle from
 * the DX memory rule. The substrate gives you a stack-shape contract;
 * autocomplete from your editor's TS server is the only "intelligence"
 * touching the composition loop.
 */

import type { Opcode } from './opcodes.js';

// ─── Stack-shape primitives ──────────────────────────────────────────

/** Terminal types the 2-PDA's stack can carry. Drawn from the BSV +
 *  Plexus extension surface. */
export type StackElement =
  /** Variable-length byte string — opaque payload, hash digest. */
  | 'bytes'
  /** 64-bit signed integer (Script's CScriptNum mapped to JS bigint). */
  | 'i64'
  /** Single-byte boolean (Script: 0x00 / 0x01). */
  | 'bool'
  /** 33-byte compressed secp256k1 public key. */
  | 'pubkey'
  /** ECDSA signature (DER-encoded). */
  | 'sig'
  /** Plexus BRC-108 capability token reference. */
  | 'capability'
  /** Plexus cell identifier (typeHash | linearity | header digest). */
  | 'cell-id'
  /** BRC-52 cert id (32-byte sha256 of the canonical preimage). */
  | 'cert-id';

/** Top-to-bottom stack shape. `[]` is empty; `['i64', 'bool']` means
 *  bool is the top of stack, i64 sits below. Mirror Bitcoin Script
 *  convention: leftmost is bottom, rightmost is top. Read left-to-right
 *  for "what's on the stack" — push order. */
export type StackShape = ReadonlyArray<StackElement>;

// ─── Cell-signature declaration ──────────────────────────────────────

/**
 * A named cell carries the pre/post stack shapes the kernel demands.
 * `body` is the implementation hook — opcode list, sub-cell DAG, or
 * pask intermediate. RM-096 only types the shapes; the body shape is
 * intentionally `unknown` so different downstream encoders (Script
 * emit, pask trace, mock) can plug in.
 */
export interface CellSignature<
  Pre extends StackShape = StackShape,
  Post extends StackShape = StackShape,
> {
  /** Author-facing name for traces + error messages. */
  readonly name: string;
  /** Stack shape required at entry. */
  readonly pre: Pre;
  /** Stack shape guaranteed at exit. */
  readonly post: Post;
}

export interface CellDef<
  Pre extends StackShape = StackShape,
  Post extends StackShape = StackShape,
  Body = unknown,
> extends CellSignature<Pre, Post> {
  readonly body: Body;
}

/** Declare a cell with explicit pre/post stack shapes. Pure
 *  type-tagging — no runtime cost. */
export function defineCell<
  Pre extends StackShape,
  Post extends StackShape,
  Body = unknown,
>(def: CellDef<Pre, Post, Body>): CellDef<Pre, Post, Body> {
  return def;
}

// ─── Composition ─────────────────────────────────────────────────────

/**
 * Sequentially compose two cells. The post-shape of `a` MUST equal the
 * pre-shape of `b` exactly — TypeScript rejects mis-matched
 * compositions at the call site, before any code emits.
 *
 * The result's body is `[a.body, b.body]` so downstream encoders can
 * walk the composition. We keep this minimal — chains of length > 2 use
 * `composeAll`.
 */
export function compose<
  Pa extends StackShape,
  Pm extends StackShape,
  Pb extends StackShape,
  Ba,
  Bb,
>(
  a: CellDef<Pa, Pm, Ba>,
  b: CellDef<Pm, Pb, Bb>,
): CellDef<Pa, Pb, readonly [Ba, Bb]> {
  return {
    name: `${a.name} >> ${b.name}`,
    pre: a.pre,
    post: b.post,
    body: [a.body, b.body] as const,
  };
}

/**
 * Compose a chain of 2+ cells via repeated `compose`. Adjacency is
 * checked at composition time (inside `compose`), so each adjacent pair
 * MUST match.
 *
 * The variadic shape constraint TypeScript would need to express
 * "post[i] === pre[i+1] for all i" cleanly is unstable in current TS;
 * we accept any `CellDef[]` here and let runtime callers reach for
 * `compose(compose(a, b), c)` form if they want the strictest possible
 * compile-time check across the whole chain. Pairwise composition via
 * the two-argument `compose` is the type-safest path.
 */
export function composeAll<
  First extends CellDef<StackShape, StackShape, unknown>,
  Last extends CellDef<StackShape, StackShape, unknown>,
>(
  cells: ReadonlyArray<CellDef<StackShape, StackShape, unknown>> & [
    First,
    ...ReadonlyArray<CellDef<StackShape, StackShape, unknown>>,
    Last,
  ] | [First] | [First, Last],
): CellDef<First['pre'], Last['post'], unknown> {
  if (cells.length === 0) {
    throw new Error('composeAll: at least one cell required');
  }
  let acc: CellDef<StackShape, StackShape, unknown> = cells[0]!;
  for (let i = 1; i < cells.length; i++) {
    acc = compose(acc, cells[i]!);
  }
  return acc as CellDef<First['pre'], Last['post'], unknown>;
}

// ─── Opcode signatures (types-only) ──────────────────────────────────

/**
 * Stack signatures for the kernel opcodes the cartridge author can
 * lower to. Subset — only the ones cell composition actually emits
 * are annotated; the rest are kernel-internal. Adding a new entry is
 * additive.
 */
export const OPCODE_SIGNATURES = {
  // Plexus-specific (0xC0–0xCF) — most relevant to cartridges.
  OP_CHECKCAPABILITY: { pre: ['capability'], post: ['bool'] },
  OP_CHECKIDENTITY: { pre: ['cert-id'], post: ['bool'] },
  OP_CHECKDOMAINFLAG: { pre: ['i64', 'cell-id'], post: ['bool'] },
  OP_CHECKTYPEHASH: { pre: ['bytes', 'cell-id'], post: ['bool'] },
  OP_CHECKLINEARTYPE: { pre: ['cell-id'], post: ['i64', 'bool'] },
  OP_CHECKAFFINETYPE: { pre: ['cell-id'], post: ['bool'] },
  OP_CHECKRELEVANTTYPE: { pre: ['cell-id'], post: ['bool'] },
  OP_ASSERTLINEAR: { pre: ['cell-id'], post: ['bool'] },
  OP_DEREF_POINTER: { pre: ['cell-id'], post: ['cell-id'] },

  // Classic Bitcoin Script — most-used by cartridge cells.
  OP_DUP: { pre: ['bytes'], post: ['bytes', 'bytes'] },
  OP_DROP: { pre: ['bytes'], post: [] },
  OP_HASH256: { pre: ['bytes'], post: ['bytes'] },
  OP_SHA256: { pre: ['bytes'], post: ['bytes'] },
  OP_EQUAL: { pre: ['bytes', 'bytes'], post: ['bool'] },
  OP_EQUALVERIFY: { pre: ['bytes', 'bytes'], post: [] },
  OP_VERIFY: { pre: ['bool'], post: [] },
  OP_CHECKSIG: { pre: ['sig', 'pubkey'], post: ['bool'] },
} as const satisfies Record<string, { pre: StackShape; post: StackShape }>;

/** Compile-time helper to retrieve a kernel opcode's signature. */
export type OpcodeSignature<K extends keyof typeof OPCODE_SIGNATURES> =
  (typeof OPCODE_SIGNATURES)[K];

/** Runtime accessor for callers that need to dispatch by opcode tag. */
export function signatureOf<K extends keyof typeof OPCODE_SIGNATURES>(
  op: K,
): OpcodeSignature<K> {
  return OPCODE_SIGNATURES[op];
}

/** Re-export the kernel opcode enum so authors can pin a body to its
 *  opcode without a second import. */
export type { Opcode };

```
