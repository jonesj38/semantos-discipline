---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/wallet-headers/brain/src/script-macro.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.645386+00:00
---

# cartridges/wallet-headers/brain/src/script-macro.ts

```ts
// script-macro.ts — a deterministic Bitcoin Script macro / loop-unroll compiler.
//
// Implements the `--macro-unroll-loops` model: bounded loops + parametric
// macros are expanded at COMPILE TIME into a flat, branch-free opcode stream
// (temporal iteration → spatial repetition). The emitted script is a static,
// auditable artefact a node evaluates left-to-right with zero runtime control
// flow. Reference: Craig Wright, "Macro Compiler Option: --macro-unroll-loops"
// (2PDA / finite-space Turing completeness over bounded tapes).
//
// This is the compiler layer the Script-enforced cell transition rides on:
// `stepTile` (and other contracts) get written as macros over the cell bytes,
// `LOOP`-unrolled into raw Script. Pure TS, no deps — runs in the wallet
// (browser) and in tests.
//
// Correctness focus: canonical minimal ScriptNum push encoding (Appendix B) —
// the load-bearing piece, since a non-minimal push is non-standard / fails
// policy. Everything is built from `Uint8Array` chunks and concatenated.

// ── Standard opcodes (subset we emit; values are consensus-canonical) ──────
export const OP = {
  OP_0: 0x00, OP_FALSE: 0x00,
  OP_PUSHDATA1: 0x4c, OP_PUSHDATA2: 0x4d, OP_PUSHDATA4: 0x4e,
  OP_1NEGATE: 0x4f,
  OP_1: 0x51, OP_TRUE: 0x51,
  OP_2: 0x52, OP_3: 0x53, OP_4: 0x54, OP_5: 0x55, OP_6: 0x56, OP_7: 0x57,
  OP_8: 0x58, OP_9: 0x59, OP_10: 0x5a, OP_11: 0x5b, OP_12: 0x5c, OP_13: 0x5d,
  OP_14: 0x5e, OP_15: 0x5f, OP_16: 0x60,
  OP_NOP: 0x61, OP_IF: 0x63, OP_NOTIF: 0x64, OP_ELSE: 0x67, OP_ENDIF: 0x68,
  OP_VERIFY: 0x69, OP_RETURN: 0x6a,
  OP_TOALTSTACK: 0x6b, OP_FROMALTSTACK: 0x6c,
  OP_2DROP: 0x6d, OP_2DUP: 0x6e, OP_DROP: 0x75, OP_DUP: 0x76,
  OP_NIP: 0x77, OP_OVER: 0x78, OP_PICK: 0x79, OP_ROLL: 0x7a,
  OP_ROT: 0x7b, OP_SWAP: 0x7c, OP_TUCK: 0x7d,
  OP_CAT: 0x7e, OP_SPLIT: 0x7f, OP_NUM2BIN: 0x80, OP_BIN2NUM: 0x81, OP_SIZE: 0x82,
  OP_AND: 0x84, OP_OR: 0x85, OP_XOR: 0x86,
  OP_EQUAL: 0x87, OP_EQUALVERIFY: 0x88,
  OP_1ADD: 0x8b, OP_1SUB: 0x8c, OP_NEGATE: 0x8f, OP_ABS: 0x90,
  OP_NOT: 0x91, OP_0NOTEQUAL: 0x92,
  OP_ADD: 0x93, OP_SUB: 0x94, OP_MUL: 0x95, OP_DIV: 0x96, OP_MOD: 0x97,
  OP_LSHIFT: 0x98, OP_RSHIFT: 0x99,
  OP_BOOLAND: 0x9a, OP_BOOLOR: 0x9b,
  OP_NUMEQUAL: 0x9c, OP_NUMEQUALVERIFY: 0x9d, OP_NUMNOTEQUAL: 0x9e,
  OP_LESSTHAN: 0x9f, OP_GREATERTHAN: 0xa0,
  OP_LESSTHANOREQUAL: 0xa1, OP_GREATERTHANOREQUAL: 0xa2,
  OP_MIN: 0xa3, OP_MAX: 0xa4, OP_WITHIN: 0xa5,
  OP_RIPEMD160: 0xa6, OP_SHA1: 0xa7, OP_SHA256: 0xa8, OP_HASH160: 0xa9,
  OP_HASH256: 0xaa, OP_CODESEPARATOR: 0xab,
  OP_CHECKSIG: 0xac, OP_CHECKSIGVERIFY: 0xad,
  OP_CHECKMULTISIG: 0xae, OP_CHECKMULTISIGVERIFY: 0xaf,
} as const;

const OP_NAME: Record<number, string> = Object.fromEntries(
  Object.entries(OP).map(([k, v]) => [v, k]),
) as Record<number, string>;

/** A macro fragment is a list of byte chunks (opcodes and/or pushes). */
export type Frag = Uint8Array[];

/** A single opcode byte as a fragment chunk. */
export function op(code: number): Uint8Array {
  if (code < 0 || code > 0xff) throw new Error(`op: byte out of range ${code}`);
  return Uint8Array.of(code);
}

// ── Canonical minimal ScriptNum integer push (Appendix B push_int) ─────────

/** Little-endian minimal magnitude bytes of |v| (>=1 byte, no trailing zeros). */
function leMagnitude(v: bigint): Uint8Array {
  if (v === 0n) return Uint8Array.of(0);
  const out: number[] = [];
  let n = v;
  while (n > 0n) { out.push(Number(n & 0xffn)); n >>= 8n; }
  return Uint8Array.from(out);
}

/** Length-prefix a data payload with the minimal push opcode. */
export function pushBytes(data: Uint8Array): Uint8Array {
  const n = data.length;
  if (n === 0) return Uint8Array.of(OP.OP_0); // empty push == OP_0
  let prefix: Uint8Array;
  if (n <= 75) prefix = Uint8Array.of(n);
  else if (n <= 0xff) prefix = Uint8Array.of(OP.OP_PUSHDATA1, n);
  else if (n <= 0xffff) prefix = Uint8Array.of(OP.OP_PUSHDATA2, n & 0xff, (n >> 8) & 0xff);
  else prefix = Uint8Array.of(OP.OP_PUSHDATA4, n & 0xff, (n >> 8) & 0xff, (n >> 16) & 0xff, (n >>> 24) & 0xff);
  return concatBytes(prefix, data);
}

/**
 * Canonical push of an integer as a minimal ScriptNum (Appendix B):
 *  - 0..16 → OP_0..OP_16; -1 → OP_1NEGATE
 *  - else  → minimal little-endian magnitude with the sign bit handled
 *            (positive: pad 0x00 if top bit set; negative: set/append 0x80),
 *            length-prefixed with the minimal push opcode.
 */
export function pushInt(value: number | bigint): Uint8Array {
  const v = typeof value === 'bigint' ? value : BigInt(value);
  if (v >= 0n && v <= 16n) return v === 0n ? op(OP.OP_0) : op(0x50 + Number(v));
  if (v === -1n) return op(OP.OP_1NEGATE);

  const mag = Array.from(leMagnitude(v < 0n ? -v : v));
  const top = mag[mag.length - 1]!;
  if (v < 0n) {
    if (top & 0x80) mag.push(0x80);
    else mag[mag.length - 1] = top | 0x80;
  } else if (top & 0x80) {
    mag.push(0x00);
  }
  return pushBytes(Uint8Array.from(mag));
}

/** Push raw hex (data — NOT interpreted as opcodes). For pasted constants. */
export function pushHex(hex: string): Uint8Array {
  return pushBytes(fromHex(hex));
}

/**
 * Push pre-assembled opcode bytes verbatim (NOT length-prefixed) — for
 * dropping in a hand-written macro like Brendogg's OP_PUSH_TX block, where
 * the hex IS the opcode/data stream, not a single push payload.
 */
export function raw(hex: string): Uint8Array {
  return fromHex(hex);
}

// ── Loop unrolling (the --macro-unroll-loops core) ─────────────────────────

/**
 * LOOP(n, body) ⇝ body(0) ‖ body(1) ‖ … ‖ body(n-1).
 * Temporal iteration becomes spatial repetition; `i` is a compile-time
 * constant in each expansion. `n` must be a known non-negative integer.
 */
export function LOOP(n: number, body: (i: number) => Frag): Frag {
  if (!Number.isInteger(n) || n < 0) throw new Error(`LOOP: bound must be a non-negative integer (got ${n})`);
  const out: Uint8Array[] = [];
  for (let i = 0; i < n; i++) out.push(...body(i));
  return out;
}

/** REPEAT(n, frag) ⇝ frag repeated n times (index-free LOOP). */
export function REPEAT(n: number, frag: Frag): Frag {
  return LOOP(n, () => frag);
}

// ── Canonical macro family — LEGACY LOWERING of the cell-engine's native
//    Craig macro opcodes (Craig Wright, "A Two-Stack Automaton Framework"). ────
//
// IMPORTANT — alignment with the 2PDA:
// The AUTHORITATIVE definitions live in Zig: `core/cell-engine/src/opcodes/
// macro.zig` implements XSWAP/XDROP/XROT/HASHCAT as NATIVE single-byte opcodes
// (0xB0–0xB8) executing directly against the two-stack PDA (`pda.zig`). Our own
// engine runs those natively (SPV-on-every-spend) — no unrolling needed.
//
// The functions below are the *on-chain lowering* of those exact semantics into
// LEGACY post-Genesis opcodes, for when PUBLIC miners (who see 0xB0+ as OP_NOP)
// must enforce the same covenant. They are NOT a free reinterpretation — every
// expansion is cross-checked against the native macro in the engine
// (`tests/macro_legacy_equivalence.zig`: native 0xB0 vs this bytecode ⇒
// identical stack). Keep them faithful to macro.zig; do not edit one without
// the other.
//
// `n` is the 1-based depth of the target item (top of stack = position 1). The
// depth literal uses the same canonical minimal-ScriptNum push, so `<n-1>` for
// small n collapses to OP_0..OP_16 and the script stays branch-free + auditable.

function requireDepth(n: number, who: string, min: number): void {
  if (!Number.isInteger(n) || n < min) throw new Error(`${who}: depth must be an integer >= ${min} (got ${n})`);
}

/**
 * XROT-N — rotate the top N elements, bringing the N-th to the top.
 * Native: macro.zig xrot. Lowering: `<n-1> OP_ROLL`. (N=3 ⇒ OP_ROT.)
 */
export function xRot(n: number): Frag {
  requireDepth(n, 'xRot', 2);
  return [pushInt(n - 1), op(OP.OP_ROLL)];
}

/**
 * XDROP-N — drop the top N elements.
 * Native: macro.zig xdrop. Lowering: N × OP_DROP. (N=2 ≡ OP_2DROP.)
 */
export function xDrop(n: number): Frag {
  requireDepth(n, 'xDrop', 1);
  return REPEAT(n, [op(OP.OP_DROP)]);
}

/**
 * XSWAP-N — swap the top item with the N-th item (the N-2 middle items stay).
 * Native: macro.zig xswap. Lowerings (all verified equal to native in-engine):
 *   N=2 → OP_SWAP
 *   N=3 → OP_SWAP OP_ROT
 *   N≥4 → `<n-1> OP_ROLL` ‖ OP_TOALTSTACK ‖ (n-2)×`<n-2> OP_ROLL` ‖ OP_FROMALTSTACK
 * The N≥4 form lifts the swapped target to the top, parks it on the alt stack,
 * left-rotates the remaining (n-1)-window so the old top sinks to the bottom,
 * then restores the target — a transposition that fixes the middle, using only
 * legacy ROLL + alt ops. (The alt stack is save/restore-neutral.)
 */
export function xSwap(n: number): Frag {
  requireDepth(n, 'xSwap', 2);
  if (n === 2) return [op(OP.OP_SWAP)];
  if (n === 3) return [op(OP.OP_SWAP), op(OP.OP_ROT)];
  return seq(
    [pushInt(n - 1), op(OP.OP_ROLL), op(OP.OP_TOALTSTACK)],
    REPEAT(n - 2, [pushInt(n - 2), op(OP.OP_ROLL)]),
    [op(OP.OP_FROMALTSTACK)],
  );
}

/**
 * HASHCAT — pop two items, push SHA256(a ‖ b) (the merkle/commit fold step).
 * Native: macro.zig hashcat. Lowering: `OP_CAT OP_SHA256`.
 */
export function hashCat(): Frag {
  return [op(OP.OP_CAT), op(OP.OP_SHA256)];
}

/** Concatenate fragments into one fragment. */
export function seq(...frags: Frag[]): Frag {
  return frags.flat();
}

/** Compile a fragment to the final flat Bitcoin Script bytecode. */
export function compile(frag: Frag): Uint8Array {
  return concatBytes(...frag);
}

// ── Disassembly (auditability — the essay's "execution becomes audit") ─────

/** Render bytecode as human-readable assembly for audit/debug. */
export function toAsm(script: Uint8Array): string {
  const out: string[] = [];
  let i = 0;
  while (i < script.length) {
    const b = script[i]!;
    if (b >= 0x01 && b <= 0x4b) {
      const data = script.slice(i + 1, i + 1 + b);
      out.push(`PUSH(${b}) ${toHex(data)}`);
      i += 1 + b;
    } else if (b === OP.OP_PUSHDATA1) {
      const n = script[i + 1]!;
      out.push(`PUSHDATA1(${n}) ${toHex(script.slice(i + 2, i + 2 + n))}`);
      i += 2 + n;
    } else if (b === OP.OP_PUSHDATA2) {
      const n = script[i + 1]! | (script[i + 2]! << 8);
      out.push(`PUSHDATA2(${n}) ${toHex(script.slice(i + 3, i + 3 + n))}`);
      i += 3 + n;
    } else {
      out.push(OP_NAME[b] ?? `0x${b.toString(16).padStart(2, '0')}`);
      i += 1;
    }
  }
  return out.join(' ');
}

/**
 * Assemble a whitespace-separated ASM string into bytecode. A token that names
 * a known opcode (`OP_*`) emits that opcode byte; any other token is treated as
 * a hex DATA push (`pushBytes`). This is how a hand-written, paste-exact macro
 * — e.g. Brendogg's OP_PUSH_TX block, where the constants (group order, R = Gx,
 * the pubkey) are bare hex literals interleaved with opcodes — is turned into
 * runnable Script verbatim. Comments (`# …` / `// …`) and blank tokens are
 * ignored so a documented block can be pasted as-is.
 */
export function fromAsm(asm: string): Frag {
  const frag: Frag = [];
  for (const raw of asm.replace(/\/\/.*$|#.*$/gm, ' ').split(/\s+/)) {
    const tok = raw.trim();
    if (tok === '') continue;
    const code = (OP as Record<string, number>)[tok];
    if (code !== undefined) {
      frag.push(op(code));
    } else if (/^[0-9a-fA-F]+$/.test(tok) && tok.length % 2 === 0) {
      frag.push(pushBytes(fromHex(tok)));
    } else {
      throw new Error(`fromAsm: unknown token "${tok}"`);
    }
  }
  return frag;
}

// ── byte helpers ───────────────────────────────────────────────────────────
function concatBytes(...parts: Uint8Array[]): Uint8Array {
  let len = 0;
  for (const p of parts) len += p.length;
  const out = new Uint8Array(len);
  let off = 0;
  for (const p of parts) { out.set(p, off); off += p.length; }
  return out;
}
export function fromHex(hex: string): Uint8Array {
  const h = hex.startsWith('0x') ? hex.slice(2) : hex;
  if (h.length % 2 !== 0) throw new Error(`fromHex: odd length ${h.length}`);
  const out = new Uint8Array(h.length / 2);
  for (let i = 0; i < out.length; i++) out[i] = parseInt(h.slice(i * 2, i * 2 + 2), 16);
  return out;
}
export function toHex(b: Uint8Array): string {
  let s = '';
  for (const x of b) s += x.toString(16).padStart(2, '0');
  return s;
}

```
