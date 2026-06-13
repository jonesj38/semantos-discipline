---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/semantos-ir/src/emit.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.003710+00:00
---

# core/semantos-ir/src/emit.ts

```ts
/**
 * Nanopass 2: Emit — IRProgram → opcode bytes
 *
 * Walks bindings in order and emits cell engine opcodes for each.
 * Must produce byte-for-byte identical output to LispCompiler.compileConstraint()
 * for the same input expression.
 *
 * Opcode constants and encoding helpers are copied from compiler.ts —
 * they're small, pure, and stateless.
 */

import type { IRBinding, IRProgram } from './types';

// ── Opcode Constants ──────────────────────────────────────────
// Sourced from packages/cell-engine/src/opcodes/standard.zig and plexus.zig

const OP_PUSHDATA1 = 0x4C;
const OP_EQUAL = 0x87;
const OP_NOT = 0x91;
const OP_NUMNOTEQUAL = 0x9E;
const OP_BOOLAND = 0x9A;
const OP_BOOLOR = 0x9B;
const OP_LESSTHAN = 0x9F;
const OP_GREATERTHAN = 0xA0;
const OP_LESSTHANOREQUAL = 0xA1;
const OP_GREATERTHANOREQUAL = 0xA2;
const OP_CHECKCAPABILITY = 0xC3;
const OP_CHECKDOMAINFLAG = 0xC6;
const OP_CHECKTYPEHASH = 0xC7;
const OP_DEREF_POINTER = 0xC8;
const OP_CALLHOST = 0xD0;
const OP_LOADFIELD = 0xB0;

// ── Byte Encoding (copied from compiler.ts) ───────────────────

function encodeScriptNumber(n: number): Uint8Array {
  if (n === 0) return new Uint8Array([0]);

  const negative = n < 0;
  let abs = Math.abs(n);
  const bytes: number[] = [];

  while (abs > 0) {
    bytes.push(abs & 0xFF);
    abs >>= 8;
  }

  if (bytes[bytes.length - 1] & 0x80) {
    bytes.push(negative ? 0x80 : 0x00);
  } else if (negative) {
    bytes[bytes.length - 1] |= 0x80;
  }

  return new Uint8Array(bytes);
}

function encodePushData(data: Uint8Array): Uint8Array {
  if (data.length <= 75) {
    const result = new Uint8Array(1 + data.length);
    result[0] = data.length;
    result.set(data, 1);
    return result;
  }
  const result = new Uint8Array(2 + data.length);
  result[0] = OP_PUSHDATA1;
  result[1] = data.length;
  result.set(data, 2);
  return result;
}

function encodePushNumber(n: number): Uint8Array {
  return encodePushData(encodeScriptNumber(n));
}

function encodePushString(s: string): Uint8Array {
  return encodePushData(new TextEncoder().encode(s));
}

function hexToBytes(hex: string): Uint8Array {
  const bytes = new Uint8Array(hex.length / 2);
  for (let i = 0; i < hex.length; i += 2) {
    bytes[i / 2] = parseInt(hex.substring(i, i + 2), 16);
  }
  return bytes;
}

// ── Comparison op → opcode mapping ────────────────────────────

const COMPARISON_OPCODES: Record<string, number> = {
  '>':  OP_GREATERTHAN,
  '<':  OP_LESSTHAN,
  '>=': OP_GREATERTHANOREQUAL,
  '<=': OP_LESSTHANOREQUAL,
  '=':  OP_EQUAL,
  '!=': OP_NUMNOTEQUAL,
};

// ── Emit ──────────────────────────────────────────────────────

function emitBinding(binding: IRBinding): number[] {
  switch (binding.kind) {
    case 'comparison': {
      const opcode = COMPARISON_OPCODES[binding.op!];
      if (opcode === undefined) throw new Error(`Unknown comparison op: ${binding.op}`);

      const pushBytes = typeof binding.value === 'number'
        ? [...encodePushNumber(binding.value)]
        : [...encodePushString(binding.value as string)];

      const fieldBytes = [...encodePushString(binding.field!), OP_LOADFIELD];

      return [...pushBytes, ...fieldBytes, opcode];
    }

    case 'logical_not': {
      // NOT is emitted after its operand (which was already emitted)
      return [OP_NOT];
    }

    case 'logical_and': {
      // Chain (n-1) BOOLAND opcodes after all operands
      const count = binding.operands!.length - 1;
      return Array(count).fill(OP_BOOLAND);
    }

    case 'logical_or': {
      const count = binding.operands!.length - 1;
      return Array(count).fill(OP_BOOLOR);
    }

    case 'capability': {
      return [...encodePushNumber(binding.capabilityNumber!), OP_CHECKCAPABILITY];
    }

    case 'domainCheck': {
      const flag = typeof binding.domainFlag === 'number'
        ? binding.domainFlag
        : parseInt(binding.domainFlag as string, 16) || 0;
      return [...encodePushNumber(flag), OP_CHECKDOMAINFLAG];
    }

    case 'timeConstraint': {
      const opcode = binding.timeOp === 'timeAfter' ? OP_GREATERTHAN : OP_LESSTHAN;
      return [...encodePushNumber(binding.timestamp!), opcode];
    }

    case 'hostCall': {
      return [...encodePushString(binding.functionName!), OP_CALLHOST];
    }

    case 'typeHashCheck': {
      const hashBytes = hexToBytes(binding.expectedHash!);
      return [...encodePushData(hashBytes), OP_CHECKTYPEHASH];
    }

    case 'deref': {
      return [OP_DEREF_POINTER];
    }
  }
}

/**
 * Emit an IRProgram as cell engine opcode bytes.
 *
 * Walks bindings in order (topological — operands before combinators)
 * and concatenates their opcode sequences.
 *
 * The output is byte-for-byte identical to LispCompiler.compileConstraint()
 * for the same input ConstraintExpr.
 */
export function emit(program: IRProgram): Uint8Array {
  const bytes: number[] = [];
  for (const binding of program.bindings) {
    bytes.push(...emitBinding(binding));
  }
  return new Uint8Array(bytes);
}

```
