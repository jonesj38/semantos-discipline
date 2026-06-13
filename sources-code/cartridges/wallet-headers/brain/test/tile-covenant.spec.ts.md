---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/wallet-headers/brain/test/tile-covenant.spec.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.666982+00:00
---

# cartridges/wallet-headers/brain/test/tile-covenant.spec.ts

```ts
// tile-covenant spec — the cell_N → cell_{N+1} covenant pieces.
//
// The TRANSITION clause + unsignedByte are proven equal to the native rule in
// the engine (core/cell-engine/tests/tile_script_equivalence.zig). Here we pin
// the compiler output (so it can't drift from the proven bytes), check the
// assembler composition, and verify the BIP143 preimage refactor round-trips.

import { describe, expect, test } from 'bun:test';
import { compile, toHex, toAsm, op, OP } from '../src/script-macro';
import {
  unsignedByte, compileTransitionClause, compileTileCovenant, DEFAULT_RULE,
  spliceCentreByte, compileBindClause,
  compileRegionToNextCentre, compileCovenantBody, compileCovenantScript,
} from '../src/tile-covenant';
import { buildSighashPreimage, computeSighash, type TxInput, type TxOutput } from '../src/tx-builder';
import { hash256 } from '../src/beef-codec';

describe('unsignedByte — raw state byte → unsigned 0..255', () => {
  test('emits the engine-proven bytecode (<0x00> OP_CAT OP_BIN2NUM)', () => {
    expect(toHex(compile(unsignedByte()))).toBe('01007e81');
    expect(toAsm(compile(unsignedByte()))).toBe('PUSH(1) 00 OP_CAT OP_BIN2NUM');
  });
});

describe('compileTransitionClause — enforce next == stepTile(current)', () => {
  test('radius-1 form (8,8) emits the engine-proven bytecode', () => {
    expect(toHex(compile(compileTransitionClause(DEFAULT_RULE, 8, 8)))).toBe(
      '6b028000a26b028000a26b028000a26b028000a26b028000a26b028000a26b028000a26b028000a26b00' +
      '6c936c936c936c936c936c936c936c936b028000a26b028000a26b028000a26b028000a26b028000a26b' +
      '028000a26b028000a26b028000a26b006c936c936c936c936c936c936c936c936c7c765254a57c5354a5' +
      '5379028000a26b6b6b6c6c766b946c7c6c9593028000950140947c5ca2014095939300a402ff00a36c9d51',
    );
  });
  test('ends with OP_NUMEQUALVERIFY then the OP_1 success marker', () => {
    const s = compile(compileTransitionClause(DEFAULT_RULE, 8, 8));
    expect(s[0]).toBe(OP.OP_TOALTSTACK);     // parks claimedNext
    expect(s[s.length - 2]).toBe(OP.OP_NUMEQUALVERIFY);
    expect(s[s.length - 1]).toBe(OP.OP_1);
  });
  test('default (8,48) covers the real two-radius rule', () => {
    const s = compile(compileTransitionClause()); // innerK=8, outerK=48
    expect(s.includes(OP.OP_IF)).toBe(false);  // branch-free
    expect(s[s.length - 1]).toBe(OP.OP_1);
  });
});

describe('compileTileCovenant — AUTH ‖ TRANSITION ‖ BIND assembly', () => {
  test('sandwiches the transition clause between the injected blocks', () => {
    const pushTxBlock = [op(0xde), op(0xad)]; // stand-in for Brendogg's OP_PUSH_TX block
    const bindBlock = [op(0xbe), op(0xef)];
    const cov = compileTileCovenant({ pushTxBlock, bindBlock, innerK: 8, outerK: 8 });
    const transition = compile(compileTransitionClause(DEFAULT_RULE, 8, 8));
    expect(cov[0]).toBe(0xde);
    expect(cov[1]).toBe(0xad);
    expect(cov[cov.length - 2]).toBe(0xbe);
    expect(cov[cov.length - 1]).toBe(0xef);
    // the proven transition clause sits verbatim in the middle
    expect(toHex(cov).includes(toHex(transition))).toBe(true);
  });
  test('with no bind block it is just AUTH ‖ TRANSITION', () => {
    const cov = compileTileCovenant({ pushTxBlock: [op(0x6a)], innerK: 8, outerK: 8 });
    expect(cov[0]).toBe(0x6a);
    expect(cov[cov.length - 1]).toBe(OP.OP_1);
  });
  test('defaults to Brendogg\'s real OP_PUSH_TX AUTH block (HASH256 … CHECKSIG)', () => {
    const cov = compileTileCovenant({ innerK: 8, outerK: 8 }); // no pushTxBlock → default
    expect(cov[0]).toBe(OP.OP_HASH256); // AUTH leads with the preimage hash
    // the transition clause's success marker is still the final opcode
    expect(cov[cov.length - 1]).toBe(OP.OP_1);
    // and the AUTH block's CHECKSIG sits before the transition clause
    const transition = compile(compileTransitionClause(DEFAULT_RULE, 8, 8));
    expect(toHex(cov).includes('ac' + toHex(transition))).toBe(true);
  });
});

describe('BIND / quine clause — engine-proven byte surgery', () => {
  test('spliceCentreByte emits the engine-proven bytecode', () => {
    expect(toHex(compile(spliceCentreByte()))).toBe('5280517f757c547f517f776b7c7e6c7e');
  });
  test('compileBindClause emits the engine-proven bytecode (ends HASH256 EQUALVERIFY 1)', () => {
    expect(toHex(compile(compileBindClause()))).toBe(
      '597c7e6b01687f77537f7c6b820134947f7c5a7f776b587f7c6b547f7701207f756c6c6c6c527a7e7e7eaa8851',
    );
    const b = compile(compileBindClause());
    expect(b[b.length - 3]).toBe(OP.OP_HASH256);
    expect(b[b.length - 2]).toBe(OP.OP_EQUALVERIFY);
    expect(b[b.length - 1]).toBe(OP.OP_1);
  });
  test('full covenant: AUTH (default) ‖ TRANSITION ‖ BIND assembles', () => {
    const cov = compileTileCovenant({ bindBlock: compileBindClause(), innerK: 8, outerK: 8 });
    expect(cov[0]).toBe(OP.OP_HASH256);        // AUTH leads
    expect(cov[cov.length - 1]).toBe(OP.OP_1); // BIND's success marker is last
    expect(toHex(cov).includes(toHex(compile(compileBindClause())))).toBe(true);
  });
});

describe('covenant composition — read state, evolve, assemble full lock', () => {
  test('compileRegionToNextCentre emits the engine-proven bytecode', () => {
    expect(toHex(compile(compileRegionToNextCentre(DEFAULT_RULE)))).toBe(
      '547f517f7c01007e816b7e517f517f517f517f517f517f517f01007e81028000a26b01007e81028000a26b01007e81' +
      '028000a26b01007e81028000a26b01007e81028000a26b01007e81028000a26b01007e81028000a26b01007e810280' +
      '00a26b006c936c936c936c936c936c936c936c936c7c76765254a57c5354a55379028000a26b6b6b6c6c766b946c7c' +
      '6c9593028000950140947c5ca2014095939300a402ff00a3',
    );
  });
  test('compileCovenantBody = DUP ‖ region→centre ‖ splice ‖ bind (engine-proven)', () => {
    const body = compile(compileCovenantBody(DEFAULT_RULE));
    expect(body[0]).toBe(OP.OP_DUP);             // duplicate region (need it for splice)
    expect(body[body.length - 1]).toBe(OP.OP_1); // bind's success marker
    expect(toHex(body).includes(toHex(compile(compileRegionToNextCentre())))).toBe(true);
    expect(toHex(body).includes(toHex(compile(compileBindClause())))).toBe(true);
  });
  test('compileCovenantScript: statePush ‖ AUTH ‖ FROMALTSTACK ‖ body, > 252 bytes', () => {
    const region = new Uint8Array([130, 0, 130, 0, 200, 0, 0, 0, 0]);
    const lock = compileCovenantScript(region, DEFAULT_RULE);
    expect(lock[0]).toBe(0x09);                  // statePush length (0x09 ‖ 9 region bytes)
    expect(lock.slice(1, 10)).toEqual(region);   // the seed state is embedded
    expect(lock[10]).toBe(OP.OP_TOALTSTACK);     // park region
    expect(lock.length).toBeGreaterThan(252);    // ⇒ 3-byte scriptCode varint (BIND assumption)
    expect(lock[lock.length - 1]).toBe(OP.OP_1); // ends with the success marker
    // AUTH block (OP_PUSH_TX) is present
    expect(toHex(lock).includes(toHex(compile(compileRegionToNextCentre())))).toBe(true);
  });
  test('compileCovenantScript rejects a non-9-byte region', () => {
    expect(() => compileCovenantScript(new Uint8Array(8))).toThrow();
  });
});

describe('buildSighashPreimage — the bytes OP_PUSH_TX introspects', () => {
  const inputs: TxInput[] = [{
    txid: new Uint8Array(32).fill(0x11),
    vout: 0,
    value: 1000n,
    script: new Uint8Array([0x51]), // trivial scriptCode
    sequence: 0xffffffff,
  }];
  const outputs: TxOutput[] = [{ script: new Uint8Array([0x52]), satoshis: 999n }];

  test('computeSighash == hash256(preimage) (refactor is consistent)', () => {
    const preimage = buildSighashPreimage(inputs, outputs, 0);
    expect(toHex(computeSighash(inputs, outputs, 0))).toBe(toHex(hash256(preimage)));
  });
  test('preimage embeds the scriptCode (current cell state lives here)', () => {
    const inp2: TxInput[] = [{ ...inputs[0]!, script: new Uint8Array([0xAA, 0xBB, 0xCC]) }];
    const preimage = buildSighashPreimage(inp2, outputs, 0);
    expect(toHex(preimage).includes('aabbcc')).toBe(true);
  });
});

```
