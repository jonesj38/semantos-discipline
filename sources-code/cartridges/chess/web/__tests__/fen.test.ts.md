---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/chess/web/__tests__/fen.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.427772+00:00
---

# cartridges/chess/web/__tests__/fen.test.ts

```ts
import { describe, expect, it } from 'vitest';
import { parseFen, squareToUci, uciToSquare } from '../src/chess/fen.js';
import { multiplierToLinearity } from '../src/chess/types.js';

describe('parseFen', () => {
  it('parses the starting position', () => {
    const s = parseFen('rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1');
    expect(s.sideToMove).toBe('w');
    expect(s.board[0][0]).toBe('r');
    expect(s.board[7][4]).toBe('K');
    expect(s.board[3][3]).toBe('');
  });

  it('round-trips square coordinates', () => {
    expect(squareToUci(0, 4)).toBe('e8');
    expect(squareToUci(7, 4)).toBe('e1');
    expect(uciToSquare('e4')).toEqual({ rank: 4, file: 4 });
    expect(uciToSquare('a1')).toEqual({ rank: 7, file: 0 });
  });

  it('rejects malformed FEN', () => {
    expect(() => parseFen('garbage')).toThrow();
    expect(() => parseFen('8/8/8/8/8/8/8/8')).toThrow();
  });
});

describe('multiplierToLinearity', () => {
  it('maps the cube ladder onto kernel linearity classes', () => {
    expect(multiplierToLinearity(1)).toBe(1); // AFFINE
    expect(multiplierToLinearity(2)).toBe(0); // LINEAR
    expect(multiplierToLinearity(4)).toBe(2); // RELEVANT
    expect(multiplierToLinearity(8)).toBe(2); // RELEVANT
  });
});

```
