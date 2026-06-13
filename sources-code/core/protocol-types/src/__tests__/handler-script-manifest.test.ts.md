---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/__tests__/handler-script-manifest.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.884756+00:00
---

# core/protocol-types/src/__tests__/handler-script-manifest.test.ts

```ts
/**
 * Tests for the `cellTypes[i].handler` HandlerDeclaration schema —
 * the cell-engine bytecode handler declaration introduced as the
 * recovery follow-on to the 2PDA-WASM excise (commit edf91c1).
 *
 * Reference: `docs/design/LINEAR-CELL-SPV-STATE.md` §3 (hostcall ABI)
 * + §7 (capability gating).
 */

import { describe, expect, test } from 'bun:test';
import {
  validateCellTypeDeclaration,
  validateHandlerDeclaration,
  type HandlerDeclaration,
} from '../extension-manifest';

const VALID_HASH = 'a'.repeat(64); // 64 lowercase hex chars
const VALID_SCRIPT = '0102030405060708'; // 8-byte sample bytecode

const validHandler: HandlerDeclaration = {
  script: VALID_SCRIPT,
  scriptHash: VALID_HASH,
  capabilities: ['cap.spv.verify'],
  opcountBudget: 100000,
  emits: ['bsv.spv.verify.result'],
};

describe('validateHandlerDeclaration', () => {
  test('accepts a well-formed handler with all fields', () => {
    expect(() =>
      validateHandlerDeclaration(validHandler, 'manifest.cellTypes[0].handler'),
    ).not.toThrow();
  });

  test('accepts a well-formed handler without optional opcountBudget', () => {
    const { opcountBudget, ...minimal } = validHandler;
    expect(() => validateHandlerDeclaration(minimal, 'prefix')).not.toThrow();
  });

  test('accepts an empty capabilities array (pure stack script)', () => {
    expect(() =>
      validateHandlerDeclaration({ ...validHandler, capabilities: [] }, 'prefix'),
    ).not.toThrow();
  });

  test('accepts an empty emits array (validator-only script)', () => {
    expect(() =>
      validateHandlerDeclaration({ ...validHandler, emits: [] }, 'prefix'),
    ).not.toThrow();
  });

  test('rejects null / non-object', () => {
    expect(() => validateHandlerDeclaration(null, 'prefix')).toThrow(/non-null object/);
    expect(() => validateHandlerDeclaration(42, 'prefix')).toThrow(/non-null object/);
  });

  test('rejects missing script', () => {
    const { script, ...broken } = validHandler;
    expect(() => validateHandlerDeclaration(broken, 'prefix')).toThrow(/script.*hex string/);
  });

  test('rejects empty script', () => {
    expect(() =>
      validateHandlerDeclaration({ ...validHandler, script: '' }, 'prefix'),
    ).toThrow(/script.*non-empty hex/);
  });

  test('rejects uppercase script hex', () => {
    expect(() =>
      validateHandlerDeclaration({ ...validHandler, script: 'ABCD' }, 'prefix'),
    ).toThrow(/even-length lowercase hex/);
  });

  test('rejects odd-length script hex', () => {
    expect(() =>
      validateHandlerDeclaration({ ...validHandler, script: 'abc' }, 'prefix'),
    ).toThrow(/even-length lowercase hex/);
  });

  test('rejects missing scriptHash', () => {
    const { scriptHash, ...broken } = validHandler;
    expect(() => validateHandlerDeclaration(broken, 'prefix')).toThrow(/scriptHash.*64 lowercase hex/);
  });

  test('rejects scriptHash with wrong length', () => {
    expect(() =>
      validateHandlerDeclaration({ ...validHandler, scriptHash: 'abc123' }, 'prefix'),
    ).toThrow(/scriptHash.*64 lowercase hex/);
  });

  test('rejects scriptHash with uppercase hex', () => {
    expect(() =>
      validateHandlerDeclaration({ ...validHandler, scriptHash: 'A'.repeat(64) }, 'prefix'),
    ).toThrow(/scriptHash.*64 lowercase hex/);
  });

  test('rejects missing capabilities', () => {
    const { capabilities, ...broken } = validHandler;
    expect(() => validateHandlerDeclaration(broken, 'prefix')).toThrow(/capabilities must be an array/);
  });

  test('rejects non-array capabilities', () => {
    expect(() =>
      validateHandlerDeclaration({ ...validHandler, capabilities: 'cap.spv.verify' as unknown as string[] }, 'prefix'),
    ).toThrow(/capabilities must be an array/);
  });

  test('rejects capability tag with invalid characters', () => {
    expect(() =>
      validateHandlerDeclaration({ ...validHandler, capabilities: ['CAP.SPV.VERIFY'] }, 'prefix'),
    ).toThrow(/capabilities\[0\] must match/);
  });

  test('rejects capability tag starting with non-letter', () => {
    expect(() =>
      validateHandlerDeclaration({ ...validHandler, capabilities: ['1cap'] }, 'prefix'),
    ).toThrow(/capabilities\[0\] must match/);
  });

  test('rejects zero opcountBudget', () => {
    expect(() =>
      validateHandlerDeclaration({ ...validHandler, opcountBudget: 0 }, 'prefix'),
    ).toThrow(/opcountBudget.*positive integer/);
  });

  test('rejects negative opcountBudget', () => {
    expect(() =>
      validateHandlerDeclaration({ ...validHandler, opcountBudget: -1 }, 'prefix'),
    ).toThrow(/opcountBudget.*positive integer/);
  });

  test('rejects non-integer opcountBudget', () => {
    expect(() =>
      validateHandlerDeclaration({ ...validHandler, opcountBudget: 1.5 }, 'prefix'),
    ).toThrow(/opcountBudget.*positive integer/);
  });

  test('rejects missing emits', () => {
    const { emits, ...broken } = validHandler;
    expect(() => validateHandlerDeclaration(broken, 'prefix')).toThrow(/emits must be an array/);
  });

  test('rejects emits entry that is not a string', () => {
    expect(() =>
      validateHandlerDeclaration(
        { ...validHandler, emits: [42 as unknown as string] },
        'prefix',
      ),
    ).toThrow(/emits\[0\] must be a non-empty cell-type name string/);
  });

  test('rejects empty emits entry', () => {
    expect(() =>
      validateHandlerDeclaration({ ...validHandler, emits: [''] }, 'prefix'),
    ).toThrow(/emits\[0\] must be a non-empty/);
  });
});

describe('validateCellTypeDeclaration with handler', () => {
  const seenNames = (): Set<string> => new Set();

  const cellTypeNoHandler = {
    name: 'bsv.spv.verify.intent',
    triple: { segment1: 'bsv', segment2: 'spv', segment3: 'verify', segment4: 'intent' },
    linearity: 'EPHEMERAL',
  };

  const cellTypeWithHandler = {
    ...cellTypeNoHandler,
    handler: validHandler,
  };

  test('accepts a cellType without a handler (pure data record)', () => {
    expect(() => validateCellTypeDeclaration(cellTypeNoHandler, 0, seenNames())).not.toThrow();
  });

  test('accepts a cellType with a well-formed handler', () => {
    expect(() => validateCellTypeDeclaration(cellTypeWithHandler, 0, seenNames())).not.toThrow();
  });

  test('rejects a cellType with a malformed handler (bad scriptHash)', () => {
    expect(() =>
      validateCellTypeDeclaration(
        { ...cellTypeWithHandler, handler: { ...validHandler, scriptHash: 'short' } },
        0,
        seenNames(),
      ),
    ).toThrow(/manifest\.cellTypes\[0\]\.handler\.scriptHash/);
  });

  test('rejects a cellType with a non-object handler', () => {
    expect(() =>
      validateCellTypeDeclaration(
        { ...cellTypeNoHandler, handler: 'not-an-object' },
        0,
        seenNames(),
      ),
    ).toThrow(/manifest\.cellTypes\[0\]\.handler.*non-null object/);
  });

  test('error prefix carries the cell type index', () => {
    expect(() =>
      validateCellTypeDeclaration(
        { ...cellTypeWithHandler, handler: { ...validHandler, script: 'X' } },
        7,
        seenNames(),
      ),
    ).toThrow(/manifest\.cellTypes\[7\]\.handler\.script/);
  });
});

```
