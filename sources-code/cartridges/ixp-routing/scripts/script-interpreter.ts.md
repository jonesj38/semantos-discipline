---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/ixp-routing/scripts/script-interpreter.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.559655+00:00
---

# cartridges/ixp-routing/scripts/script-interpreter.ts

```ts
// Minimal Bitcoin Script interpreter — handles the opcode subset our
// AEMO dispatch predicates use.  Lets the backtest run the EXACT
// Rúnar-compiled hex bytes the brain would execute, not a TS port.
//
// Supported opcodes (extend as new predicates need them):
//   0x00          OP_FALSE         push 0
//   0x01..0x4B    PUSHDATA<n>      push next n bytes as a number (LE)
//   0x51          OP_1             push 1
//   0x6d          OP_2DROP
//   0x69          OP_VERIFY        pop; abort if not truthy
//   0x75          OP_DROP
//   0x76          OP_DUP
//   0x77          OP_NIP
//   0x78          OP_OVER
//   0x7c          OP_SWAP
//   0x87          OP_EQUAL
//   0x8b          OP_1ADD
//   0x95          OP_MUL
//   0x9a          OP_BOOLAND
//   0x9c          OP_NUMEQUAL
//   0xa0          OP_GREATERTHAN
//   0xa1          OP_LESSTHANOREQUAL
//   0xa2          OP_GREATERTHANOREQUAL
//
// Numbers are treated as JS bigint to match Bitcoin Script's arbitrary-
// precision semantics on BSV.  Push values are read as little-endian
// signed integers per CScriptNum convention (high-bit-sign).  Stack
// entries that are 0 or empty-string are FALSE, everything else TRUE
// for OP_VERIFY's truthy check.

export type ScriptStack = bigint[];

export interface ExecResult {
  ok: boolean;
  /** Reason when ok === false. */
  reason?: 'verify_failed' | 'invalid_opcode' | 'stack_underflow' | 'invalid_pushdata' | 'invalid_script';
  /** Final stack — useful for asserting test outputs. */
  stack: ScriptStack;
  /** Opcodes consumed (gas equivalent). */
  opcount: number;
}

function readCScriptNum(buf: Uint8Array): bigint {
  if (buf.length === 0) return 0n;
  // Negative bit on highest byte → flip + negate
  const hi = buf[buf.length - 1]!;
  const negative = (hi & 0x80) !== 0;
  let acc = 0n;
  for (let i = 0; i < buf.length; i++) {
    let b = BigInt(buf[i]!);
    if (i === buf.length - 1 && negative) b = BigInt(hi & 0x7f);
    acc |= b << BigInt(8 * i);
  }
  return negative ? -acc : acc;
}

function isTruthy(n: bigint): boolean {
  return n !== 0n;
}

/** Run a Bitcoin Script byte stream against an empty stack.
 *  Equivalent to PolicyRuntime.evaluateReal under .real_executor mode
 *  for the opcode subset listed above.
 *
 *  Returns ok === true iff the script terminates without an
 *  unsatisfied OP_VERIFY AND the top-of-stack is truthy.
 */
export function execute(script: Uint8Array): ExecResult {
  const stack: ScriptStack = [];
  let pc = 0;
  let opcount = 0;
  while (pc < script.length) {
    const op = script[pc++]!;
    opcount++;
    // Pushdata (1..0x4B inclusive: push next N bytes).
    if (op >= 0x01 && op <= 0x4b) {
      const n = op;
      if (pc + n > script.length) return { ok: false, reason: 'invalid_pushdata', stack, opcount };
      stack.push(readCScriptNum(script.subarray(pc, pc + n)));
      pc += n;
      continue;
    }
    switch (op) {
      case 0x00: stack.push(0n); break;                       // OP_FALSE / OP_0
      case 0x51: stack.push(1n); break;                       // OP_1
      case 0x6d: {                                            // OP_2DROP
        if (stack.length < 2) return { ok: false, reason: 'stack_underflow', stack, opcount };
        stack.pop(); stack.pop(); break;
      }
      case 0x69: {                                            // OP_VERIFY
        if (stack.length < 1) return { ok: false, reason: 'stack_underflow', stack, opcount };
        const v = stack.pop()!;
        if (!isTruthy(v)) return { ok: false, reason: 'verify_failed', stack, opcount };
        break;
      }
      case 0x75: {                                            // OP_DROP
        if (stack.length < 1) return { ok: false, reason: 'stack_underflow', stack, opcount };
        stack.pop(); break;
      }
      case 0x76: {                                            // OP_DUP
        if (stack.length < 1) return { ok: false, reason: 'stack_underflow', stack, opcount };
        stack.push(stack[stack.length - 1]!); break;
      }
      case 0x77: {                                            // OP_NIP — pop second-from-top
        if (stack.length < 2) return { ok: false, reason: 'stack_underflow', stack, opcount };
        const top = stack.pop()!;
        stack.pop();
        stack.push(top);
        break;
      }
      case 0x78: {                                            // OP_OVER — copy second-to-top onto top
        if (stack.length < 2) return { ok: false, reason: 'stack_underflow', stack, opcount };
        stack.push(stack[stack.length - 2]!);
        break;
      }
      case 0x7c: {                                            // OP_SWAP
        if (stack.length < 2) return { ok: false, reason: 'stack_underflow', stack, opcount };
        const a = stack.pop()!;
        const b = stack.pop()!;
        stack.push(a);
        stack.push(b);
        break;
      }
      case 0x87: case 0x9c: {                                 // OP_EQUAL / OP_NUMEQUAL
        if (stack.length < 2) return { ok: false, reason: 'stack_underflow', stack, opcount };
        const b = stack.pop()!;
        const a = stack.pop()!;
        stack.push(a === b ? 1n : 0n);
        break;
      }
      case 0x8b: {                                            // OP_1ADD
        if (stack.length < 1) return { ok: false, reason: 'stack_underflow', stack, opcount };
        const a = stack.pop()!;
        stack.push(a + 1n);
        break;
      }
      case 0x95: {                                            // OP_MUL
        if (stack.length < 2) return { ok: false, reason: 'stack_underflow', stack, opcount };
        const b = stack.pop()!;
        const a = stack.pop()!;
        stack.push(a * b);
        break;
      }
      case 0x9a: {                                            // OP_BOOLAND
        if (stack.length < 2) return { ok: false, reason: 'stack_underflow', stack, opcount };
        const b = stack.pop()!;
        const a = stack.pop()!;
        stack.push(isTruthy(a) && isTruthy(b) ? 1n : 0n);
        break;
      }
      case 0xa0: {                                            // OP_GREATERTHAN
        if (stack.length < 2) return { ok: false, reason: 'stack_underflow', stack, opcount };
        const b = stack.pop()!;
        const a = stack.pop()!;
        stack.push(a > b ? 1n : 0n);
        break;
      }
      case 0xa1: {                                            // OP_LESSTHANOREQUAL
        if (stack.length < 2) return { ok: false, reason: 'stack_underflow', stack, opcount };
        const b = stack.pop()!;
        const a = stack.pop()!;
        stack.push(a <= b ? 1n : 0n);
        break;
      }
      case 0xa2: {                                            // OP_GREATERTHANOREQUAL
        if (stack.length < 2) return { ok: false, reason: 'stack_underflow', stack, opcount };
        const b = stack.pop()!;
        const a = stack.pop()!;
        stack.push(a >= b ? 1n : 0n);
        break;
      }
      default:
        return { ok: false, reason: 'invalid_opcode', stack, opcount };
    }
  }
  if (stack.length === 0) return { ok: false, reason: 'invalid_script', stack, opcount };
  return { ok: isTruthy(stack[stack.length - 1]!), stack, opcount };
}

/** Encode a small integer as a minimal CScriptNum push opcode sequence:
 *  - 0 → OP_FALSE
 *  - 1..16 → OP_1..OP_16 (single byte 0x51..0x60)
 *  - else → PUSHDATA<n> + LE bytes
 *  For the backtest we use the generic path so the produced script
 *  matches what an unlock builder would emit. */
export function pushSmallInt(n: number | bigint): Uint8Array {
  if (n === 0 || n === 0n) return new Uint8Array([0x00]);
  let v = typeof n === 'bigint' ? n : BigInt(n);
  const negative = v < 0n;
  if (negative) v = -v;
  const bytes: number[] = [];
  while (v > 0n) {
    bytes.push(Number(v & 0xffn));
    v >>= 8n;
  }
  if ((bytes[bytes.length - 1]! & 0x80) !== 0) bytes.push(negative ? 0x80 : 0x00);
  else if (negative) bytes[bytes.length - 1]! |= 0x80;
  if (bytes.length > 0x4b) throw new Error(`pushSmallInt: value needs PUSHDATA1+, not supported in demo (${bytes.length} bytes)`);
  return new Uint8Array([bytes.length, ...bytes]);
}

export function hexToBytes(hex: string): Uint8Array {
  const trimmed = hex.trim();
  const out = new Uint8Array(trimmed.length / 2);
  for (let i = 0; i < out.length; i++) {
    out[i] = parseInt(trimmed.slice(i * 2, i * 2 + 2), 16);
  }
  return out;
}

export function concat(...parts: Uint8Array[]): Uint8Array {
  let total = 0;
  for (const p of parts) total += p.length;
  const out = new Uint8Array(total);
  let off = 0;
  for (const p of parts) { out.set(p, off); off += p.length; }
  return out;
}

```
