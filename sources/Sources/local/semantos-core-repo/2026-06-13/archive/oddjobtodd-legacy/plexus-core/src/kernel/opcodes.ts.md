---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/oddjobtodd-legacy/plexus-core/src/kernel/opcodes.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.978630+00:00
---

# archive/oddjobtodd-legacy/plexus-core/src/kernel/opcodes.ts

```ts
/**
 * Opcodes for the Plexus 2-PDA script engine (Zig/WASM implementation).
 * Includes standard Bitcoin Script opcodes plus Plexus-specific extensions.
 */

export enum Opcode {
  // Stack operations
  OP_PUSH = 0x00,
  OP_DUP = 0x76,
  OP_DROP = 0x75,
  OP_SWAP = 0x7c,
  OP_ROT = 0x7a,
  OP_OVER = 0x78,
  OP_NIP = 0x77,
  OP_PICK = 0x79,
  OP_ROLL = 0x7b,
  OP_TOALTSTACK = 0x6b,
  OP_FROMALTSTACK = 0x6c,

  // Arithmetic operations
  OP_ADD = 0x93,
  OP_SUB = 0x94,
  OP_MUL = 0x95,
  OP_EQUAL = 0x87,
  OP_EQUALVERIFY = 0x88,
  OP_LESSTHAN = 0x9f,
  OP_GREATERTHAN = 0xa0,
  OP_WITHIN = 0xa5,

  // Cryptographic operations (delegated to host via imports)
  OP_HASH160 = 0xa9,
  OP_HASH256 = 0xaa,
  OP_SHA256 = 0xa8,
  OP_CHECKSIG = 0xac,
  OP_CHECKMULTISIG = 0xae,

  // Control flow
  OP_IF = 0x63,
  OP_NOTIF = 0x64,
  OP_ELSE = 0x67,
  OP_ENDIF = 0x68,
  OP_VERIFY = 0x69,
  OP_RETURN = 0x6a,

  // Lock time operations
  OP_CHECKLOCKTIMEVERIFY = 0xb1,
  OP_CHECKSEQUENCEVERIFY = 0xb2,

  // Logic operations
  OP_NOT = 0x91,
  OP_AND = 0x84,
  OP_OR = 0x85,

  // Plexus-specific opcodes (custom range 0xc0-0xcf)
  OP_CHECKLINEARTYPE = 0xc0,     // Verify object is LINEAR, pop type tag
  OP_CHECKAFFINETYPE = 0xc1,     // Verify object is AFFINE
  OP_CHECKRELEVANTTYPE = 0xc2,   // Verify object is RELEVANT
  OP_CHECKCAPABILITY = 0xc3,     // Verify capability token is unspent
  OP_CHECKIDENTITY = 0xc4,       // Verify BRC-52 cert binding
  OP_ASSERTLINEAR = 0xc5,        // Assert + verify linear consumption
}

/**
 * Constants for the Plexus kernel engine.
 */
export const MAIN_STACK_SIZE = 1024;
export const AUX_STACK_SIZE = 256;
export const MAX_SCRIPT_SIZE = 10000; // bytes

/**
 * Checks if an opcode is a Plexus-specific opcode (0xc0-0xcf range).
 */
export function isPlexusOpcode(op: number): boolean {
  return op >= 0xc0 && op <= 0xcf;
}

```
