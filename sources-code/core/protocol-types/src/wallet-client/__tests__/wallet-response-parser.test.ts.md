---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/wallet-client/__tests__/wallet-response-parser.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.912864+00:00
---

# core/protocol-types/src/wallet-client/__tests__/wallet-response-parser.test.ts

```ts
/**
 * Per-method response-parser tests. Pure functions over JSON.
 */

import { describe, expect, test } from 'bun:test';
import {
  parseCreateAction,
  parseCreateSignature,
  parseGetHeight,
  parseGetNetwork,
  parseGetPublicKey,
  parseInternalizeAction,
  parseIsAuthenticated,
  parseListOutputs,
  parseSignAction,
} from '../wallet-response-parser';

describe('parseIsAuthenticated', () => {
  test('1. accepts a bare boolean response', () => {
    expect(parseIsAuthenticated(true)).toBe(true);
    expect(parseIsAuthenticated(false)).toBe(false);
  });

  test('2. accepts {authenticated: true}', () => {
    expect(parseIsAuthenticated({ authenticated: true })).toBe(true);
  });

  test('3. coerces missing fields to false', () => {
    expect(parseIsAuthenticated({})).toBe(false);
    expect(parseIsAuthenticated(null)).toBe(false);
  });
});

describe('parseGetHeight', () => {
  test('4. accepts a bare number', () => {
    expect(parseGetHeight(800000)).toBe(800000);
  });

  test('5. accepts {height: …}', () => {
    expect(parseGetHeight({ height: 800001 })).toBe(800001);
  });

  test('6. defaults to 0 when missing', () => {
    expect(parseGetHeight({})).toBe(0);
  });
});

describe('parseGetNetwork', () => {
  test('7. accepts a bare "mainnet" / "testnet"', () => {
    expect(parseGetNetwork('mainnet')).toBe('mainnet');
    expect(parseGetNetwork('testnet')).toBe('testnet');
  });

  test('8. accepts {network: …}', () => {
    expect(parseGetNetwork({ network: 'testnet' })).toBe('testnet');
  });

  test('9. defaults to "mainnet" on garbage', () => {
    expect(parseGetNetwork({})).toBe('mainnet');
  });
});

describe('parseGetPublicKey', () => {
  test('10. accepts a bare string', () => {
    expect(parseGetPublicKey('02abc')).toBe('02abc');
  });

  test('11. accepts {publicKey: …}', () => {
    expect(parseGetPublicKey({ publicKey: '02def' })).toBe('02def');
  });
});

describe('parseListOutputs', () => {
  test('12. unwraps arrays directly', () => {
    expect(parseListOutputs([{ outpoint: 't.0', satoshis: 1 }])).toHaveLength(1);
  });

  test('13. unwraps {outputs: [...]} envelopes', () => {
    expect(parseListOutputs({ outputs: [{ outpoint: 't.0', satoshis: 5 }] })).toHaveLength(1);
  });

  test('14. yields [] on unknown shape', () => {
    expect(parseListOutputs({})).toEqual([]);
  });
});

describe('parseCreateAction / parseSignAction', () => {
  test('15. parseCreateAction copies all five optional fields', () => {
    const out = parseCreateAction({
      txid: 'abc',
      tx: 'beef',
      rawTx: '',
      proof: 'p',
      signableTransaction: 'ref',
    });
    expect(out).toEqual({
      txid: 'abc',
      tx: 'beef',
      rawTx: '',
      proof: 'p',
      signableTransaction: 'ref',
    });
  });

  test('16. parseCreateAction omits absent optional fields', () => {
    expect(parseCreateAction({ txid: 'abc' })).toEqual({ txid: 'abc' });
  });

  test('17. parseSignAction reuses parseCreateAction shape sans signableTransaction', () => {
    const out = parseSignAction({ txid: 'abc', tx: 'beef', proof: 'p' });
    expect(out).toEqual({ txid: 'abc', tx: 'beef', proof: 'p' });
  });
});

describe('parseCreateSignature / parseInternalizeAction', () => {
  test('18. parseCreateSignature returns {signature: number[]}', () => {
    expect(parseCreateSignature({ signature: [1, 2, 3] })).toEqual({ signature: [1, 2, 3] });
  });

  test('19. parseCreateSignature handles bare array fallback', () => {
    expect(parseCreateSignature([4, 5])).toEqual({ signature: [4, 5] });
  });

  test('20. parseInternalizeAction defaults accepted=true when missing', () => {
    expect(parseInternalizeAction({})).toEqual({ accepted: true });
    expect(parseInternalizeAction({ accepted: false })).toEqual({ accepted: false });
  });
});

```
