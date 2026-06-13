---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/wallet-headers/brain/src/push-tx.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.651649+00:00
---

# cartridges/wallet-headers/brain/src/push-tx.ts

```ts
// push-tx.ts — Brendogg's verbatim "optimal OP_PUSH_TX" construction, the AUTH
// clause of the MNCA covenant. This is the standard nChain/sCrypt technique:
// the unlocking script pushes the BIP143 sighash PREIMAGE; this block hashes it
// (OP_HASH256 → e), then DERIVES a low-S ECDSA signature with the ephemeral
// k = 1 (so R = G, r = Gx), DER-encodes it, appends the SIGHASH flag (taken
// from the alt stack), and pushes a precomputed pubkey. A trailing OP_CHECKSIG
// then passes IFF the node's own sighash equals e — i.e. the pushed preimage is
// genuinely THIS spend's. That lets the covenant introspect the spend (read its
// scriptCode / hashOutputs) trustlessly.
//
// STACK CONTRACT before this block runs:
//   main: … <preimage>        (preimage on top)
//   alt:  <sighashFlag>        (e.g. 0x41 = SIGHASH_ALL | FORKID)
// After OP_CHECKSIG: pushes 1 (valid) — chain it into the covenant's verifies.
//
// VERBATIM — Brendogg (10 Jul 2025): "as long as they are pasted in exactly as
// is hex, it should work 100% of the time. none of this transaction revisions
// shit." The three baked constants are: the group-order reduction value, the
// R = Gx DER component, and the matching pubkey. DO NOT edit them.
//
// WHERE IT RUNS: a real BSV node (post-Genesis arbitrary-precision ScriptNum +
// native ECDSA). The cell-engine is i64-bounded, so it runs the compute clause
// (stepTile), not this — see core/cell-engine/tests/tile_script_equivalence.zig.

import { OP, op, fromAsm, type Frag } from './script-macro';

/** Brendogg's exact OP_PUSH_TX assembly (preimage → [DER sig, pubkey]). */
export const BRENDOGG_PUSHTX_ASM = `
OP_HASH256 OP_TRUE OP_SPLIT OP_TRUE OP_SPLIT OP_TRUE OP_SPLIT OP_TRUE OP_SPLIT OP_TRUE OP_SPLIT
OP_TRUE OP_SPLIT OP_TRUE OP_SPLIT OP_TRUE OP_SPLIT OP_TRUE OP_SPLIT OP_TRUE OP_SPLIT OP_TRUE
OP_SPLIT OP_TRUE OP_SPLIT OP_TRUE OP_SPLIT OP_TRUE OP_SPLIT OP_TRUE OP_SPLIT OP_TRUE OP_SPLIT
OP_TRUE OP_SPLIT OP_TRUE OP_SPLIT OP_TRUE OP_SPLIT OP_TRUE OP_SPLIT OP_TRUE OP_SPLIT OP_TRUE
OP_SPLIT OP_TRUE OP_SPLIT OP_TRUE OP_SPLIT OP_TRUE OP_SPLIT OP_TRUE OP_SPLIT OP_TRUE OP_SPLIT
OP_TRUE OP_SPLIT OP_TRUE OP_SPLIT OP_TRUE OP_SPLIT OP_TRUE OP_SPLIT OP_SWAP OP_CAT OP_SWAP
OP_CAT OP_SWAP OP_CAT OP_SWAP OP_CAT OP_SWAP OP_CAT OP_SWAP OP_CAT OP_SWAP OP_CAT OP_SWAP OP_CAT
OP_SWAP OP_CAT OP_SWAP OP_CAT OP_SWAP OP_CAT OP_SWAP OP_CAT OP_SWAP OP_CAT OP_SWAP OP_CAT
OP_SWAP OP_CAT OP_SWAP OP_CAT OP_SWAP OP_CAT OP_SWAP OP_CAT OP_SWAP OP_CAT OP_SWAP OP_CAT
OP_SWAP OP_CAT OP_SWAP OP_CAT OP_SWAP OP_CAT OP_SWAP OP_CAT OP_SWAP OP_CAT OP_SWAP OP_CAT
OP_SWAP OP_CAT OP_SWAP OP_CAT OP_SWAP OP_CAT OP_SWAP OP_CAT OP_SWAP OP_CAT 00 OP_CAT OP_BIN2NUM
OP_0 1f OP_NUM2BIN OP_1 OP_CAT OP_ADD
414136d08c5ed2bf3ba048afe6dcaebafeffffffffffffffffffffffffffffff00 OP_TUCK OP_2 OP_DIV OP_OVER
OP_LESSTHAN OP_IF OP_OVER OP_MOD OP_OVER OP_2 OP_DIV OP_OVER OP_LESSTHAN OP_IF OP_SUB OP_ELSE
OP_NIP OP_ENDIF OP_ELSE OP_NIP OP_ENDIF OP_DUP OP_0NOTEQUAL OP_SPLIT OP_DUP OP_0NOTEQUAL
OP_SPLIT OP_DUP OP_0NOTEQUAL OP_SPLIT OP_DUP OP_0NOTEQUAL OP_SPLIT OP_DUP OP_0NOTEQUAL OP_SPLIT
OP_DUP OP_0NOTEQUAL OP_SPLIT OP_DUP OP_0NOTEQUAL OP_SPLIT OP_DUP OP_0NOTEQUAL OP_SPLIT OP_DUP
OP_0NOTEQUAL OP_SPLIT OP_DUP OP_0NOTEQUAL OP_SPLIT OP_DUP OP_0NOTEQUAL OP_SPLIT OP_DUP
OP_0NOTEQUAL OP_SPLIT OP_DUP OP_0NOTEQUAL OP_SPLIT OP_DUP OP_0NOTEQUAL OP_SPLIT OP_DUP
OP_0NOTEQUAL OP_SPLIT OP_DUP OP_0NOTEQUAL OP_SPLIT OP_DUP OP_0NOTEQUAL OP_SPLIT OP_DUP
OP_0NOTEQUAL OP_SPLIT OP_DUP OP_0NOTEQUAL OP_SPLIT OP_DUP OP_0NOTEQUAL OP_SPLIT OP_DUP
OP_0NOTEQUAL OP_SPLIT OP_DUP OP_0NOTEQUAL OP_SPLIT OP_DUP OP_0NOTEQUAL OP_SPLIT OP_DUP
OP_0NOTEQUAL OP_SPLIT OP_DUP OP_0NOTEQUAL OP_SPLIT OP_DUP OP_0NOTEQUAL OP_SPLIT OP_DUP
OP_0NOTEQUAL OP_SPLIT OP_DUP OP_0NOTEQUAL OP_SPLIT OP_DUP OP_0NOTEQUAL OP_SPLIT OP_DUP
OP_0NOTEQUAL OP_SPLIT OP_DUP OP_0NOTEQUAL OP_SPLIT OP_SWAP OP_CAT OP_SWAP OP_CAT OP_SWAP OP_CAT
OP_SWAP OP_CAT OP_SWAP OP_CAT OP_SWAP OP_CAT OP_SWAP OP_CAT OP_SWAP OP_CAT OP_SWAP OP_CAT
OP_SWAP OP_CAT OP_SWAP OP_CAT OP_SWAP OP_CAT OP_SWAP OP_CAT OP_SWAP OP_CAT OP_SWAP OP_CAT
OP_SWAP OP_CAT OP_SWAP OP_CAT OP_SWAP OP_CAT OP_SWAP OP_CAT OP_SWAP OP_CAT OP_SWAP OP_CAT
OP_SWAP OP_CAT OP_SWAP OP_CAT OP_SWAP OP_CAT OP_SWAP OP_CAT OP_SWAP OP_CAT OP_SWAP OP_CAT
OP_SWAP OP_CAT OP_SWAP OP_CAT OP_SWAP OP_CAT OP_SWAP OP_CAT OP_SIZE OP_SWAP OP_CAT
022079be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f8179802 OP_SWAP OP_CAT OP_SIZE
OP_SWAP OP_CAT 30 OP_SWAP OP_CAT OP_FROMALTSTACK OP_CAT
02b405d7f0322a89d0f9f3a98e6f938fdc1c969a8d1382a2bf66a71ae74a1e83b0
`;

/** The baked constants (exposed for audit; never edit — paste-exact). */
export const PUSHTX_GROUP_ORDER_CONST = '414136d08c5ed2bf3ba048afe6dcaebafeffffffffffffffffffffffffffffff00';
export const PUSHTX_R_GX_DER = '022079be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f8179802';
export const PUSHTX_PUBKEY = '02b405d7f0322a89d0f9f3a98e6f938fdc1c969a8d1382a2bf66a71ae74a1e83b0';

/**
 * The OP_PUSH_TX introspection block: preimage (main) + sighash flag (alt) →
 * [DER sig, pubkey]. Append OP_CHECKSIG to authenticate (see pushTxAuth).
 */
export function pushTxIntrospect(): Frag {
  return fromAsm(BRENDOGG_PUSHTX_ASM);
}

/** pushTxIntrospect + OP_CHECKSIG — the full AUTH clause (true iff preimage authentic). */
export function pushTxAuth(): Frag {
  return [...pushTxIntrospect(), op(OP.OP_CHECKSIG)];
}

```
