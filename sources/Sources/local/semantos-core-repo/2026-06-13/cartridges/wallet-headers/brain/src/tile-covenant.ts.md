---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/wallet-headers/brain/src/tile-covenant.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.647568+00:00
---

# cartridges/wallet-headers/brain/src/tile-covenant.ts

```ts
// tile-covenant.ts — the cell_N → cell_{N+1} MNCA covenant: a spend is valid
// iff the next state equals stepTile(this state). Built on the proven
// stepTile-in-Script kernel (tile-script.ts) + the macro compiler.
//
// ── Architecture / what is proven vs. what is the testnet boundary ──────────
// A self-perpetuating BSV covenant has three clauses:
//
//   (1) AUTH      — prove the witness "preimage" really is this spend's BIP143
//                   sighash preimage. Standard OP_PUSH_TX: the script appends
//                   the sighash type, OP_HASH256, then verifies an R=G (k=1)
//                   ECDSA signature with OP_CHECKSIG. This needs the malleated
//                   k=1 signature constants (generator point, R/sig prefixes) —
//                   Brendogg's verbatim block, dropped in via `raw()` and
//                   validated on TESTNET. We do NOT fabricate those constants.
//
//   (2) TRANSITION — read the current cell state, compute next = stepTile(it),
//                    require the claimed next state to equal it. THIS is our IP
//                    and IS proven in-engine (tile_covenant_equivalence.zig:
//                    accept iff next == stepTile, against the mnca_tile oracle).
//
//   (3) BIND      — the claimed next state must be the one the spend actually
//                   creates: rebuild the next output and check HASH256 ==
//                   the preimage's hashOutputs field. The output is a copy of
//                   THIS locking script with the state push swapped (the quine
//                   step). Field-offset parsing + the quine are finalized with
//                   Brendogg on testnet against a real preimage (buildSighash-
//                   Preimage gives the exact byte layout the offsets target).
//
// This module ships clause (2) fully proven, the byte-surgery primitives it
// needs, and an assembler that composes (1)+(2)+(3) with the AUTH block
// injected. It deliberately does not claim (1)/(3) work end-to-end yet.

import { OP, op, pushInt, pushBytes, REPEAT, type Frag, seq, compile } from './script-macro';
import { compileCellStep, compileCellRule, type RuleParams, DEFAULT_RULE } from './tile-script';
import { pushTxAuth, pushTxIntrospect } from './push-tx';

export { DEFAULT_RULE, type RuleParams } from './tile-script';
export { pushTxAuth, pushTxIntrospect, BRENDOGG_PUSHTX_ASM } from './push-tx';

/**
 * Convert the 1-byte string on top of the stack into its UNSIGNED value
 * (0..255). Cell state bytes are unsigned, but OP_BIN2NUM reads a minimal
 * signed ScriptNum — so a raw byte >= 0x80 (e.g. 0xC8 = 200) would be read as
 * negative. Appending a high 0x00 byte first clears the sign, giving the true
 * 0..255 value. Expansion: `<0x00> OP_CAT OP_BIN2NUM`.
 */
export function unsignedByte(): Frag {
  return [pushBytes(Uint8Array.of(0x00)), op(OP.OP_CAT), op(OP.OP_BIN2NUM)];
}

/**
 * The TRANSITION clause (clause 2), branch-free and proven in-engine.
 *
 * Stack in (top on the right):
 *     self  <innerVals × innerK>  <outerVals × outerK>  claimedNext
 * Stack out:
 *     OP_1            (and OP_NUMEQUALVERIFY aborts the script if the claimed
 *                      next state is not exactly stepTile(self, neighbourhood))
 *
 * The neighbourhood values + claimed next are supplied by clauses (1)/(3) — in
 * the full covenant they are sliced out of the authenticated preimage's
 * scriptCode (current state) and the rebuilt next output (claimed next).
 */
export function compileTransitionClause(
  params: RuleParams = DEFAULT_RULE,
  innerK = 8,
  outerK = 48,
): Frag {
  return seq(
    [op(OP.OP_TOALTSTACK)],          // park claimedNext; reveal outerVals on top
    compileCellStep(params, innerK, outerK), // → next
    [op(OP.OP_FROMALTSTACK)],        // next claimedNext
    [op(OP.OP_NUMEQUALVERIFY)],      // abort unless equal
    [op(OP.OP_1)],                   // success marker (truthy top)
  );
}

// ── BIND clause (the quine): rebuild the next output, check it == hashOutputs ──
//
// All byte-surgery (OP_SPLIT/OP_CAT/OP_SIZE/OP_HASH256) — i64-safe, so it is
// PROVEN in the engine (tile_script_equivalence.zig), unlike the bignum AUTH.

/**
 * Splice a freshly-computed centre value into a 3×3 (9-byte) region.
 * Stack in:  region(9 bytes)  nextCentre(ScriptNum 0..255)
 * Stack out: nextRegion(9 bytes) = region[0..4] ‖ lowByte(nextCentre) ‖ region[5..9]
 *
 * `nextCentre` is rendered to a single RAW byte via `OP_2 OP_NUM2BIN` (2-byte LE,
 * so values ≥128 don't overflow a signed 1-byte ScriptNum) then dropping the
 * high byte — giving the true 0..255 state byte.
 */
export function spliceCentreByte(): Frag {
  return seq(
    [op(OP.OP_2), op(OP.OP_NUM2BIN), op(OP.OP_1), op(OP.OP_SPLIT), op(OP.OP_DROP)], // → region, nbyte
    [op(OP.OP_SWAP)],                                  // nbyte, region
    [op(OP.OP_4), op(OP.OP_SPLIT)],                    // nbyte, first4, rest5
    [op(OP.OP_1), op(OP.OP_SPLIT), op(OP.OP_NIP)],     // nbyte, first4, last4 (drop old centre)
    [op(OP.OP_TOALTSTACK)],                            // nbyte, first4 ; alt:[last4]
    [op(OP.OP_SWAP), op(OP.OP_CAT)],                   // first4‖nbyte
    [op(OP.OP_FROMALTSTACK), op(OP.OP_CAT)],           // first4‖nbyte‖last4 = nextRegion
  );
}

/**
 * The BIND/quine clause: prove the spend re-creates the SAME covenant with the
 * evolved state. Single-output, value-preserving covenant.
 *
 * Stack in:  preimage(P, authenticated)  nextRegion(9 bytes)
 * Stack out: OP_1   (OP_EQUALVERIFY aborts unless HASH256(nextOutput) == the
 *            preimage's hashOutputs)
 *
 * Layout exploited (BIP143): the preimage's first 104 bytes are fixed
 * (nVersion ‖ hashPrevouts ‖ hashSequence ‖ outpoint), and its last 52 bytes
 * are fixed (value8 ‖ nSequence4 ‖ hashOutputs32 ‖ nLockTime4 ‖ sighashType4),
 * so every field is reachable by splitting from a known end — NO dependence on
 * the covenant's own byte length. The scriptCode length is a 3-byte varint
 * (`fd XXXX`) because the covenant is in [253, 65535] bytes; the next output's
 * scriptCode is the same length, so that varint is reused verbatim. The state
 * is the first push of scriptCode (`09` ‖ 9 region bytes); covenantCode is the
 * rest, copied unchanged — that is the self-replication.
 *
 *   nextOutput = value8 ‖ varint3 ‖ (0x09 ‖ nextRegion ‖ covenantCode)
 *   require HASH256(nextOutput) == hashOutputs
 */
export function compileBindClause(): Frag {
  // NOTE: all numeric operands use pushInt (minimal ScriptNum: OP_N for ≤16),
  // NOT pushBytes — a 1-byte data push of a value in 1..16 violates MINIMALDATA
  // ("Data push larger than necessary") and is rejected by relay policy.
  return seq(
    // statePush = 0x09 ‖ nextRegion, parked
    [pushInt(9), op(OP.OP_SWAP), op(OP.OP_CAT), op(OP.OP_TOALTSTACK)],        // [P], alt:[statePush]
    // drop the fixed 104-byte BIP143 head
    [pushInt(104), op(OP.OP_SPLIT), op(OP.OP_NIP)],                           // [varint3 ‖ scriptCode ‖ tail52]
    // peel the 3-byte scriptCodeLen varint
    [op(OP.OP_3), op(OP.OP_SPLIT), op(OP.OP_SWAP), op(OP.OP_TOALTSTACK)],     // [rest2], alt:[statePush, varint3]
    // peel the fixed 52-byte tail off the end → scriptCode | tail52
    [op(OP.OP_SIZE), pushInt(52), op(OP.OP_SUB), op(OP.OP_SPLIT)],            // [scriptCode, tail52]
    // covenantCode = scriptCode after the 10-byte state push
    [op(OP.OP_SWAP), pushInt(10), op(OP.OP_SPLIT), op(OP.OP_NIP), op(OP.OP_TOALTSTACK)], // [tail52], alt:[statePush, varint3, covCode]
    // tail52 → value8 (front) and hashOutputs32 (after nSequence)
    [op(OP.OP_8), op(OP.OP_SPLIT), op(OP.OP_SWAP), op(OP.OP_TOALTSTACK)],     // [tail44], alt:[…, value8]
    [op(OP.OP_4), op(OP.OP_SPLIT), op(OP.OP_NIP)],                            // drop nSequence → [tail40]
    [pushInt(32), op(OP.OP_SPLIT), op(OP.OP_DROP)],                           // [hashOutputs32]
    // pull pieces: alt top→down = value8, covCode, varint3, statePush
    [op(OP.OP_FROMALTSTACK), op(OP.OP_FROMALTSTACK), op(OP.OP_FROMALTSTACK), op(OP.OP_FROMALTSTACK)],
    //   main top→down now: statePush, varint3, covCode, value8, hashOutputs32
    [op(OP.OP_2), op(OP.OP_ROLL), op(OP.OP_CAT)],   // statePush‖covCode = nextScriptCode
    [op(OP.OP_CAT)],                                 // varint3‖nextScriptCode
    [op(OP.OP_CAT)],                                 // value8‖varint3‖nextScriptCode = nextOutput
    [op(OP.OP_HASH256)],                             // H(nextOutput)
    [op(OP.OP_EQUALVERIFY)],                          // == hashOutputs (abort otherwise)
    [op(OP.OP_1)],
  );
}

// ── Reading the covenant's own 3×3 state and evolving it ────────────────────

/**
 * Count how many bytes of the k-byte blob on top are "alive" (>= threshold),
 * consuming the blob and leaving the count. Splits into single bytes, converts
 * each to its unsigned value, reduces to a 0/1 alive-bit, sums via the alt
 * stack. Branch-free; i64-safe.
 */
export function countAliveInBlob(threshold: number, k: number): Frag {
  if (!Number.isInteger(k) || k < 1) throw new Error(`countAliveInBlob: k must be >= 1 (got ${k})`);
  return seq(
    REPEAT(k - 1, [pushInt(1), op(OP.OP_SPLIT)]),                  // → k single-byte strings
    REPEAT(k, [...unsignedByte(), pushInt(threshold), op(OP.OP_GREATERTHANOREQUAL), op(OP.OP_TOALTSTACK)]),
    [pushInt(0)],
    REPEAT(k, [op(OP.OP_FROMALTSTACK), op(OP.OP_ADD)]),
  );
}

/**
 * Evolve a 3×3 region one MNCA tick (radius-1: the inner and outer
 * neighbourhoods are the same 8 Moore cells), leaving the new CENTRE value.
 *
 * Stack in:  region(9 bytes)
 * Stack out: nextCentre(ScriptNum 0..255)
 *
 * Reads the centre as `self`, counts the 8 surrounding cells once, and feeds
 * (self, count, count) to the proven per-cell kernel. All i64-safe.
 */
export function compileRegionToNextCentre(params: RuleParams = DEFAULT_RULE): Frag {
  return seq(
    [pushInt(4), op(OP.OP_SPLIT)],          // [first4, rest5]
    [pushInt(1), op(OP.OP_SPLIT)],          // [first4, centre1, last4]
    [op(OP.OP_SWAP)],                       // [first4, last4, centre1]
    unsignedByte(),                         // [first4, last4, self]
    [op(OP.OP_TOALTSTACK)],                 // [first4, last4], alt:[self]
    [op(OP.OP_CAT)],                        // [neighbours8]  (the 8 non-centre cells)
    countAliveInBlob(params.aliveThreshold, 8), // [count8]
    [op(OP.OP_FROMALTSTACK), op(OP.OP_SWAP)],    // [self, count8]
    [op(OP.OP_DUP)],                        // [self, count8, count8]  (outer = inner)
    compileCellRule(params),                // → [nextCentre]
  );
}

/**
 * The covenant BODY (everything after AUTH): given the authenticated preimage
 * and the current region on the stack, evolve the region and bind the spend.
 *
 * Stack in:  preimage  region(9 bytes)
 * Stack out: OP_1   (or abort)
 *
 * i64-safe end-to-end — PROVEN in tile_script_equivalence.zig against the
 * mnca_tile oracle + a synthetic preimage.
 */
export function compileCovenantBody(params: RuleParams = DEFAULT_RULE): Frag {
  return seq(
    [op(OP.OP_DUP)],                     // [preimage, region, region]
    compileRegionToNextCentre(params),   // [preimage, region, nextCentre]
    spliceCentreByte(),                  // [preimage, nextRegion]
    compileBindClause(),                 // [preimage] → OP_1
  );
}

/**
 * The COMPLETE covenant locking script carrying a seed 3×3 region.
 *
 *   <statePush = 0x09 ‖ region>            ; the cell state, stored in the UTXO
 *   OP_TOALTSTACK                          ; park region; main: [preimage]
 *   OP_DUP <0x41> OP_TOALTSTACK            ; copy preimage; sighash flag → alt
 *   <AUTH: OP_PUSH_TX block> OP_CHECKSIG OP_VERIFY   ; authenticate preimage
 *   OP_FROMALTSTACK                        ; [preimage, region]
 *   <BODY: evolve + bind>                  ; → OP_1
 *
 * Unlocking script (witness) is simply `<preimage>` — the spender's BIP143
 * sighash preimage for the spend they are making (buildSighashPreimage).
 *
 * NOTE: executes fully only on a real BSV node (the AUTH block needs bignum
 * ScriptNum + ECDSA). The i64 BODY is engine-proven; AUTH is byte-exact verbatim.
 */
export function compileCovenantScript(region: Uint8Array, params: RuleParams = DEFAULT_RULE): Uint8Array {
  if (region.length !== 9) throw new Error(`compileCovenantScript: region must be 9 bytes (3×3), got ${region.length}`);
  return compile(seq(
    [pushBytes(region)],                                 // statePush (0x09 ‖ region)
    [op(OP.OP_TOALTSTACK)],                              // park region
    [op(OP.OP_DUP), pushBytes(Uint8Array.of(0x41)), op(OP.OP_TOALTSTACK)],
    pushTxIntrospect(),                                  // AUTH → [preimage, sig, pubkey]
    [op(OP.OP_CHECKSIG), op(OP.OP_VERIFY)],              // authenticate
    [op(OP.OP_FROMALTSTACK)],                            // [preimage, region]
    compileCovenantBody(params),
  ));
}

/**
 * Assemble the full covenant locking script:
 *   [AUTH: pushTxBlock] ‖ [TRANSITION] ‖ [BIND: bindBlock]
 *
 * `pushTxBlock` defaults to Brendogg's verbatim OP_PUSH_TX block + OP_CHECKSIG
 * (push-tx.ts) — it authenticates the witness preimage so the script can read
 * the spend's scriptCode / hashOutputs. `bindBlock` rebuilds the next output
 * and checks it against hashOutputs (the quine step) — still injected, since
 * the field-offset parsing + self-replication are finalized on testnet against
 * a real preimage. The proven (i64, engine-verified) transition clause is
 * sandwiched between them.
 *
 * NOTE: the AUTH block uses post-Genesis arbitrary-precision ScriptNum + real
 * ECDSA, so it runs on a BSV node, not the i64 cell-engine (which runs the
 * transition clause). Both compose into one on-chain locking script.
 */
export interface CovenantParts {
  /** AUTH clause. Defaults to Brendogg's verbatim OP_PUSH_TX block + OP_CHECKSIG. */
  pushTxBlock?: Frag;
  bindBlock?: Frag;
  params?: RuleParams;
  innerK?: number;
  outerK?: number;
}

export function compileTileCovenant(parts: CovenantParts = {}): Uint8Array {
  const {
    pushTxBlock = pushTxAuth(),
    bindBlock = [],
    params = DEFAULT_RULE,
    innerK = 8,
    outerK = 48,
  } = parts;
  return compile(seq(
    pushTxBlock,
    compileTransitionClause(params, innerK, outerK),
    bindBlock,
  ));
}

```
