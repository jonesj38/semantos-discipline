---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/wallet-headers/brain/src/script-interp.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.662930+00:00
---

# cartridges/wallet-headers/brain/src/script-interp.ts

```ts
// script-interp.ts — a minimal BSV Script interpreter with BIGNUM ScriptNums
// (BigInt) and real ECDSA, used to validate the covenant spend OFFLINE before
// broadcasting. The cell-engine is i64-only, so it can prove TRANSITION+BIND
// but NOT the OP_PUSH_TX AUTH clause (256-bit modular arithmetic). This runs
// the WHOLE script — AUTH + TRANSITION + BIND — exactly as a node would, so a
// `true` result here means the on-chain spend is script-valid.
//
// Scope: the opcodes the covenant uses. ScriptNums are arbitrary-precision
// BigInt (post-Genesis semantics). OP_CHECKSIG does a genuine secp256k1 verify
// of the script-built signature against the supplied sighash.

import * as secp from '@noble/secp256k1';
import { sha256 } from '@noble/hashes/sha2';

const OP = {
  PUSHDATA1: 0x4c, PUSHDATA2: 0x4d, PUSHDATA4: 0x4e, ONEGATE: 0x4f,
  IF: 0x63, NOTIF: 0x64, ELSE: 0x67, ENDIF: 0x68, VERIFY: 0x69,
  TOALT: 0x6b, FROMALT: 0x6c,
  DROP: 0x75, DUP: 0x76, NIP: 0x77, OVER: 0x78, PICK: 0x79, ROLL: 0x7a,
  ROT: 0x7b, SWAP: 0x7c, TUCK: 0x7d,
  CAT: 0x7e, SPLIT: 0x7f, NUM2BIN: 0x80, BIN2NUM: 0x81, SIZE: 0x82,
  EQUAL: 0x87, EQUALVERIFY: 0x88,
  ZERONOTEQUAL: 0x92,
  ADD: 0x93, SUB: 0x94, MUL: 0x95, DIV: 0x96, MOD: 0x97,
  NUMEQUAL: 0x9c, NUMEQUALVERIFY: 0x9d,
  LESSTHAN: 0x9f, GREATERTHAN: 0xa0, LTE: 0xa1, GTE: 0xa2,
  MIN: 0xa3, MAX: 0xa4, WITHIN: 0xa5,
  SHA256: 0xa8, HASH256: 0xaa, CHECKSIG: 0xac,
};

// ── ScriptNum (BigInt, minimal little-endian, sign bit in MSB) ──
export function decodeNum(b: Uint8Array): bigint {
  if (b.length === 0) return 0n;
  let r = 0n;
  for (let i = 0; i < b.length; i++) r |= BigInt(b[i]!) << BigInt(8 * i);
  if (b[b.length - 1]! & 0x80) {
    r &= ~(0x80n << BigInt(8 * (b.length - 1)));
    return -r;
  }
  return r;
}
export function encodeNum(v: bigint): Uint8Array {
  if (v === 0n) return new Uint8Array(0);
  const neg = v < 0n;
  let a = neg ? -v : v;
  const out: number[] = [];
  while (a > 0n) { out.push(Number(a & 0xffn)); a >>= 8n; }
  if (out[out.length - 1]! & 0x80) out.push(neg ? 0x80 : 0x00);
  else if (neg) out[out.length - 1]! |= 0x80;
  return Uint8Array.from(out);
}
function num2bin(v: bigint, size: number): Uint8Array {
  const neg = v < 0n;
  let a = neg ? -v : v;
  const out = new Uint8Array(size);
  let i = 0;
  while (a > 0n) { if (i >= size) throw new Error('NUM2BIN overflow'); out[i] = Number(a & 0xffn); a >>= 8n; i++; }
  if (neg) out[size - 1]! |= 0x80;
  return out;
}
const truthy = (b: Uint8Array): boolean => {
  for (let i = 0; i < b.length; i++) {
    if (b[i] !== 0) return !(i === b.length - 1 && b[i] === 0x80); // negative zero is false
  }
  return false;
};

function decodeDer(sig: Uint8Array): { r: bigint; s: bigint } {
  // 0x30 len 0x02 rlen r 0x02 slen s
  let i = 2;
  if (sig[0] !== 0x30 || sig[i] !== 0x02) throw new Error('bad DER');
  const rlen = sig[i + 1]!; i += 2;
  let r = 0n; for (let k = 0; k < rlen; k++) r = (r << 8n) | BigInt(sig[i + k]!); i += rlen;
  if (sig[i] !== 0x02) throw new Error('bad DER s');
  const slen = sig[i + 1]!; i += 2;
  let s = 0n; for (let k = 0; k < slen; k++) s = (s << 8n) | BigInt(sig[i + k]!);
  return { r, s };
}

function cat(a: Uint8Array, b: Uint8Array): Uint8Array {
  const out = new Uint8Array(a.length + b.length); out.set(a); out.set(b, a.length); return out;
}

export interface InterpResult {
  ok: boolean;
  finalTrue: boolean;
  error?: string;
  opcount: number;
  trace?: string[];
}

/**
 * Evaluate `unlock ‖ lock`. `sighash` is the 32-byte message OP_CHECKSIG checks
 * the script-built signature against (the input's BIP143 sighash). Returns
 * whether evaluation completed with a truthy top — i.e. the spend is valid.
 */
export function evalScript(
  script: Uint8Array,
  sighash: Uint8Array,
  opts: { trace?: boolean } = {},
): InterpResult {
  const main: Uint8Array[] = [];
  const alt: Uint8Array[] = [];
  const cond: boolean[] = []; // condition stack for IF/ELSE/ENDIF
  const trace: string[] = [];
  const exec = (): boolean => cond.every((c) => c);
  let opcount = 0;
  const popN = (): bigint => decodeNum(main.pop()!);
  const push = (b: Uint8Array): void => { main.push(b); };
  const pushN = (v: bigint): void => main.push(encodeNum(v));

  let i = 0;
  try {
    while (i < script.length) {
      const op = script[i++]!;
      opcount++;
      // data pushes — enforce MINIMALDATA (relay policy: "Data push larger than necessary")
      if (op >= 0x01 && op <= 0x4b) {
        const data = script.slice(i, i + op);
        if (exec()) {
          if (op === 1 && ((data[0]! >= 1 && data[0]! <= 16) || data[0]! === 0x81)) {
            return { ok: false, finalTrue: false, error: `non-minimal push: 1-byte ${data[0]} should be OP_N @op ${opcount}`, opcount, trace };
          }
          push(data);
        }
        i += op; continue;
      }
      if (op === OP.PUSHDATA1) {
        const n = script[i++]!;
        if (exec()) {
          if (n <= 75) return { ok: false, finalTrue: false, error: `non-minimal PUSHDATA1(${n}) @op ${opcount}`, opcount, trace };
          push(script.slice(i, i + n));
        }
        i += n; continue;
      }
      if (op === OP.PUSHDATA2) {
        const n = script[i]! | (script[i + 1]! << 8); i += 2;
        if (exec()) {
          if (n <= 0xff) return { ok: false, finalTrue: false, error: `non-minimal PUSHDATA2(${n}) @op ${opcount}`, opcount, trace };
          push(script.slice(i, i + n));
        }
        i += n; continue;
      }
      if (op === 0x00) { if (exec()) push(new Uint8Array(0)); continue; } // OP_0
      if (op === OP.ONEGATE) { if (exec()) pushN(-1n); continue; }
      if (op >= 0x51 && op <= 0x60) { if (exec()) pushN(BigInt(op - 0x50)); continue; } // OP_1..16

      // control flow (must run even when not executing)
      if (op === OP.IF) { cond.push(exec() ? truthy(main.pop()!) : false); continue; }
      if (op === OP.NOTIF) { cond.push(exec() ? !truthy(main.pop()!) : false); continue; }
      if (op === OP.ELSE) { cond[cond.length - 1] = !cond[cond.length - 1]!; continue; }
      if (op === OP.ENDIF) { cond.pop(); continue; }
      if (!exec()) continue;

      if (opts.trace) trace.push(`0x${op.toString(16)} depth=${main.length}`);

      switch (op) {
        case OP.TOALT: alt.push(main.pop()!); break;
        case OP.FROMALT: main.push(alt.pop()!); break;
        case OP.DROP: main.pop(); break;
        case OP.DUP: main.push(main[main.length - 1]!); break;
        case OP.NIP: { const t = main.pop()!; main.pop(); main.push(t); break; }
        case OP.OVER: main.push(main[main.length - 2]!); break;
        case OP.PICK: { const n = Number(popN()); main.push(main[main.length - 1 - n]!); break; }
        case OP.ROLL: { const n = Number(popN()); main.push(main.splice(main.length - 1 - n, 1)[0]!); break; }
        case OP.ROT: { const c = main.splice(main.length - 3, 1)[0]!; main.push(c); break; }
        case OP.SWAP: { const a = main.pop()!, b = main.pop()!; main.push(a, b); break; }
        case OP.TUCK: { const a = main.pop()!, b = main.pop()!; main.push(a, b, a); break; }
        case OP.CAT: { const b = main.pop()!, a = main.pop()!; main.push(cat(a, b)); break; }
        case OP.SPLIT: { const n = Number(popN()); const d = main.pop()!; main.push(d.slice(0, n), d.slice(n)); break; }
        case OP.NUM2BIN: { const sz = Number(popN()); const v = popN(); main.push(num2bin(v, sz)); break; }
        case OP.BIN2NUM: main.push(encodeNum(decodeNum(main.pop()!))); break;
        case OP.SIZE: main.push(encodeNum(BigInt(main[main.length - 1]!.length))); break;
        case OP.EQUAL: { const b = main.pop()!, a = main.pop()!; main.push(encodeNum(a.length === b.length && a.every((x, k) => x === b[k]) ? 1n : 0n)); break; }
        case OP.EQUALVERIFY: { const b = main.pop()!, a = main.pop()!; if (!(a.length === b.length && a.every((x, k) => x === b[k]))) return { ok: false, finalTrue: false, error: 'EQUALVERIFY failed', opcount, trace }; break; }
        case OP.ZERONOTEQUAL: pushN(popN() !== 0n ? 1n : 0n); break;
        case OP.ADD: { const b = popN(), a = popN(); pushN(a + b); break; }
        case OP.SUB: { const b = popN(), a = popN(); pushN(a - b); break; }
        case OP.MUL: { const b = popN(), a = popN(); pushN(a * b); break; }
        case OP.DIV: { const b = popN(), a = popN(); pushN(a / b); break; }
        case OP.MOD: { const b = popN(), a = popN(); pushN(a % b); break; }
        case OP.NUMEQUAL: { const b = popN(), a = popN(); pushN(a === b ? 1n : 0n); break; }
        case OP.NUMEQUALVERIFY: { const b = popN(), a = popN(); if (a !== b) return { ok: false, finalTrue: false, error: 'NUMEQUALVERIFY failed', opcount, trace }; break; }
        case OP.LESSTHAN: { const b = popN(), a = popN(); pushN(a < b ? 1n : 0n); break; }
        case OP.GREATERTHAN: { const b = popN(), a = popN(); pushN(a > b ? 1n : 0n); break; }
        case OP.LTE: { const b = popN(), a = popN(); pushN(a <= b ? 1n : 0n); break; }
        case OP.GTE: { const b = popN(), a = popN(); pushN(a >= b ? 1n : 0n); break; }
        case OP.MIN: { const b = popN(), a = popN(); pushN(a < b ? a : b); break; }
        case OP.MAX: { const b = popN(), a = popN(); pushN(a > b ? a : b); break; }
        case OP.WITHIN: { const mx = popN(), mn = popN(), x = popN(); pushN(x >= mn && x < mx ? 1n : 0n); break; }
        case OP.VERIFY: if (!truthy(main.pop()!)) return { ok: false, finalTrue: false, error: 'VERIFY failed', opcount, trace }; break;
        case OP.SHA256: main.push(sha256(main.pop()!)); break;
        case OP.HASH256: main.push(sha256(sha256(main.pop()!))); break;
        case OP.CHECKSIG: {
          const pub = main.pop()!;
          const sig = main.pop()!;
          if (sig.length === 0) { push(encodeNum(0n)); break; }
          try {
            const { r, s } = decodeDer(sig.slice(0, sig.length - 1)); // strip sighash-type byte
            const ok = secp.verify(new secp.Signature(r, s), sighash, pub);
            push(encodeNum(ok ? 1n : 0n));
          } catch (e) {
            push(encodeNum(0n));
            if (opts.trace) trace.push(`CHECKSIG err: ${(e as Error).message}`);
          }
          break;
        }
        default:
          return { ok: false, finalTrue: false, error: `unsupported opcode 0x${op.toString(16)}`, opcount, trace };
      }
    }
  } catch (e) {
    return { ok: false, finalTrue: false, error: `${(e as Error).message} @op ${opcount}`, opcount, trace };
  }
  const finalTrue = main.length > 0 && truthy(main[main.length - 1]!);
  return { ok: true, finalTrue, opcount, trace };
}

```
