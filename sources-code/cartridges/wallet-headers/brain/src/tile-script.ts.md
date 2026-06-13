---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/wallet-headers/brain/src/tile-script.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.649416+00:00
---

# cartridges/wallet-headers/brain/src/tile-script.ts

```ts
// tile-script.ts — the MNCA `stepTile` rule, compiled to branch-free Bitcoin
// Script via the macro/loop-unroll compiler (script-macro.ts).
//
// This is the compute axis expressed AS Script: the same integer rule the
// cell-engine runs natively (core/cell-engine/src/mnca_tile.zig,
// core/protocol-types/src/mnca/tile.ts) lowered into a flat opcode stream a
// node evaluates left-to-right. It is the kernel a cell_N → cell_{N+1}
// covenant verifies: "the spend is valid iff the next state = stepTile(this
// state)". Faithfulness is PROVEN, not asserted — every fragment is
// cross-checked against mnca_tile.zig in the executor
// (core/cell-engine/tests/tile_script_equivalence.zig: run this bytecode on a
// PDA vs the native rule ⇒ identical result).
//
// The rule (per interior cell) is a function of three integers only:
//   self        the cell's current state (0..255)
//   innerAlive  # of inner-neighbourhood cells with state >= aliveThreshold
//   outerAlive  # of outer-neighbourhood cells with state >= aliveThreshold
// and is branch-free by construction (selection is arithmetic, not OP_IF):
//   aliveBit  = self >= aliveThreshold                       ∈ {0,1}
//   surviveIn = surviveLo <= innerAlive <= surviveHi         ∈ {0,1}
//   birthIn   = birthLo   <= innerAlive <= birthHi           ∈ {0,1}
//   inRange   = aliveBit ? surviveIn : birthIn = birthIn + aliveBit*(surviveIn-birthIn)
//   baseDelta = inRange ? grow : -decay        = inRange*(grow+decay) - decay
//   delta     = baseDelta + (outerAlive >= outerBoost) * grow
//   next      = clampU8(self + delta) = min(max(self+delta, 0), 255)

import { OP, op, pushInt, REPEAT, seq, type Frag } from './script-macro';

/** Integer MNCA rule params (mirror of mnca_tile.zig / tile.ts DEFAULT_MNCA_RULE). */
export interface RuleParams {
  aliveThreshold: number;
  birthLo: number;
  birthHi: number;
  surviveLo: number;
  surviveHi: number;
  growStep: number;
  decayStep: number;
  outerBoost: number;
}

export const DEFAULT_RULE: RuleParams = {
  aliveThreshold: 128,
  birthLo: 3,
  birthHi: 3,
  surviveLo: 2,
  surviveHi: 3,
  growStep: 64,
  decayStep: 64,
  outerBoost: 12,
};

/**
 * Count how many of the top `k` stack items are "alive" (>= threshold),
 * consuming them and leaving the count on top.
 *
 * Each item is reduced to a 0/1 alive-bit (`<thresh> OP_GREATERTHANOREQUAL`,
 * which computes item >= thresh) and parked on the alt stack; then a 0 seed is
 * pushed and the k bits are summed back. Branch-free; alt stack is left clean.
 */
export function compileAliveCount(threshold: number, k: number): Frag {
  if (!Number.isInteger(k) || k < 0) throw new Error(`compileAliveCount: k must be >= 0 (got ${k})`);
  return seq(
    REPEAT(k, [pushInt(threshold), op(OP.OP_GREATERTHANOREQUAL), op(OP.OP_TOALTSTACK)]),
    [pushInt(0)],
    REPEAT(k, [op(OP.OP_FROMALTSTACK), op(OP.OP_ADD)]),
  );
}

/**
 * The per-cell MNCA update, branch-free.
 *
 * Stack contract — input (top on the right):  self  outerAlive  innerAlive
 *                  output:                     next
 *
 * (innerAlive on top, then outerAlive, then self at depth 2.) Leaves exactly
 * one value: the clamped next state. See the algebra in the file header.
 */
export function compileCellRule(p: RuleParams = DEFAULT_RULE): Frag {
  const growPlusDecay = p.growStep + p.decayStep;
  return seq(
    // ── inner range bits: surviveIn = WITHIN(inner, surviveLo, surviveHi+1),
    //    birthIn = WITHIN(inner, birthLo, birthHi+1). Consumes innerAlive. ──
    [op(OP.OP_DUP)],                                                      // S O I I
    [pushInt(p.surviveLo), pushInt(p.surviveHi + 1), op(OP.OP_WITHIN)],   // S O I SV
    [op(OP.OP_SWAP)],                                                     // S O SV I
    [pushInt(p.birthLo), pushInt(p.birthHi + 1), op(OP.OP_WITHIN)],       // S O SV BI
    // ── aliveBit = self >= aliveThreshold (self copied up from depth 3) ──
    [pushInt(3), op(OP.OP_PICK)],                                         // S O SV BI S
    [pushInt(p.aliveThreshold), op(OP.OP_GREATERTHANOREQUAL)],            // S O SV BI A
    // ── inRange = BI + A*(SV-BI), via the alt stack as scratch registers ──
    [op(OP.OP_TOALTSTACK), op(OP.OP_TOALTSTACK), op(OP.OP_TOALTSTACK)],   // main S O ; alt[A,BI,SV]
    [op(OP.OP_FROMALTSTACK), op(OP.OP_FROMALTSTACK)],                     // S O SV BI ; alt[A]
    [op(OP.OP_DUP), op(OP.OP_TOALTSTACK)],                                // S O SV BI ; alt[A,BI]
    [op(OP.OP_SUB)],                                                      // S O (SV-BI=D) ; alt[A,BI]
    [op(OP.OP_FROMALTSTACK), op(OP.OP_SWAP)],                             // S O BI D ; alt[A]
    [op(OP.OP_FROMALTSTACK), op(OP.OP_MUL)],                              // S O BI (A*D)
    [op(OP.OP_ADD)],                                                      // S O inRange
    // ── baseDelta = inRange*(grow+decay) - decay ──
    [pushInt(growPlusDecay), op(OP.OP_MUL)],                              // S O X
    [pushInt(p.decayStep), op(OP.OP_SUB)],                               // S O baseDelta
    // ── delta = baseDelta + (outerAlive >= outerBoost) * grow ──
    [op(OP.OP_SWAP)],                                                     // S baseDelta O
    [pushInt(p.outerBoost), op(OP.OP_GREATERTHANOREQUAL)],                // S baseDelta boost
    [pushInt(p.growStep), op(OP.OP_MUL), op(OP.OP_ADD)],                  // S delta
    // ── next = clampU8(self + delta) ──
    [op(OP.OP_ADD)],                                                      // self+delta
    [pushInt(0), op(OP.OP_MAX)],                                          // max(.,0)
    [pushInt(255), op(OP.OP_MIN)],                                        // min(.,255) = next
  );
}

/**
 * One full interior-cell step from raw neighbourhood VALUES on the stack.
 *
 * Stack contract — input (top on the right):
 *     self  <innerVals × innerK>  <outerVals × outerK>
 * output:
 *     next
 *
 * Counts the outer values, parks the count, counts the inner values, then
 * orders them as (self, outerAlive, innerAlive) for `compileCellRule`. The
 * caller (the unrolled `stepTile`, or the covenant) is responsible for placing
 * the neighbourhood values — at compile time their positions in the flat cell
 * payload are known, so they become a fixed sequence of OP_PICK loads.
 */
export function compileCellStep(p: RuleParams, innerK: number, outerK: number): Frag {
  return seq(
    compileAliveCount(p.aliveThreshold, outerK),  // self innerVals outerAlive
    [op(OP.OP_TOALTSTACK)],                        // self innerVals ; alt[outerAlive]
    compileAliveCount(p.aliveThreshold, innerK),   // self innerAlive ; alt[outerAlive]
    [op(OP.OP_FROMALTSTACK), op(OP.OP_SWAP)],      // self outerAlive innerAlive
    compileCellRule(p),                            // next
  );
}

```
