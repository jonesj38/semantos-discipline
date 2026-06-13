---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/wallet-headers/brain/test/push-tx.spec.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.671586+00:00
---

# cartridges/wallet-headers/brain/test/push-tx.spec.ts

```ts
// push-tx spec — Brendogg's verbatim OP_PUSH_TX block assembles byte-exact.
//
// The same assembled bytes are pinned as core/cell-engine/tests/
// brendogg-pushtx.hex and structurally checked in the engine
// (tile_script_equivalence.zig). This test guards: (a) fromAsm parses his block
// with no unknown tokens, (b) the three baked constants survive verbatim, and
// (c) the output equals the committed fixture (so TS + Zig can't drift).

import { describe, expect, test } from 'bun:test';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { compile, toHex, toAsm, fromAsm, OP } from '../src/script-macro';
import {
  pushTxIntrospect, pushTxAuth, BRENDOGG_PUSHTX_ASM,
  PUSHTX_GROUP_ORDER_CONST, PUSHTX_R_GX_DER, PUSHTX_PUBKEY,
} from '../src/push-tx';

const FIXTURE = join(import.meta.dir, '../../../../core/cell-engine/tests/brendogg-pushtx.hex');

describe('fromAsm — assemble ASM (opcodes + bare-hex data pushes)', () => {
  test('opcodes map to bytes, bare hex becomes a data push', () => {
    expect(toHex(compile(fromAsm('OP_DUP OP_HASH256')))).toBe('76aa');
    expect(toHex(compile(fromAsm('00 OP_CAT')))).toBe('01007e'); // push 0x00 then OP_CAT
    expect(toHex(compile(fromAsm('deadbeef')))).toBe('04deadbeef');
  });
  test('ignores // and # comments', () => {
    expect(toHex(compile(fromAsm('OP_DUP // dup it\nOP_HASH256 # hash')))).toBe('76aa');
  });
  test('throws on an unknown token', () => {
    expect(() => fromAsm('OP_NOTAREALOP')).toThrow();
  });
});

describe('Brendogg OP_PUSH_TX block', () => {
  test('assembles to 430 bytes, leads with OP_HASH256', () => {
    const b = compile(pushTxIntrospect());
    expect(b.length).toBe(430);
    expect(b[0]).toBe(OP.OP_HASH256);
  });
  test('the three verbatim constants are present and end with the pubkey push', () => {
    const asm = toAsm(compile(pushTxIntrospect()));
    expect(asm.includes(PUSHTX_GROUP_ORDER_CONST)).toBe(true);
    expect(asm.includes(PUSHTX_R_GX_DER.slice(4, 68))).toBe(true); // the Gx bytes
    expect(asm.endsWith(`PUSH(33) ${PUSHTX_PUBKEY}`)).toBe(true);
  });
  test('pushTxAuth appends OP_CHECKSIG', () => {
    const b = compile(pushTxAuth());
    expect(b[b.length - 1]).toBe(OP.OP_CHECKSIG);
  });
  test('matches the committed fixture the engine test pins (no drift)', () => {
    expect(toHex(compile(pushTxIntrospect()))).toBe(readFileSync(FIXTURE, 'utf8').trim());
  });
  test('ASM constant carries no stray tokens (round-trips through fromAsm)', () => {
    // re-assembling the documented ASM is deterministic
    expect(toHex(compile(fromAsm(BRENDOGG_PUSHTX_ASM)))).toBe(toHex(compile(pushTxIntrospect())));
  });
});

```
