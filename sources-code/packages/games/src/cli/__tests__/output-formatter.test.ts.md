---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/games/src/cli/__tests__/output-formatter.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.416813+00:00
---

# packages/games/src/cli/__tests__/output-formatter.test.ts

```ts
/**
 * Pure-formatter tests — `rankName`, `suitChar`, `formatCard`, `formatCards`.
 *
 * These mirror the inline helpers the legacy game-commands.ts used in the
 * poker handlers. Pinning them here means the per-command snapshots can
 * focus on dispatch + payload shape.
 */

import { describe, expect, test } from 'bun:test';
import type { Card } from '../../cards/types';
import type { GameEntity } from '../../../../game-sdk/src/types';
import { formatCard, formatCards, rankName, suitChar } from '../output-formatter';

const stubEntity: GameEntity = {
  id: 'stub',
  type: 'card',
  zone: 'deck',
  owner: 'test',
} as unknown as GameEntity;

function card(rank: Card['rank'], suit: Card['suit']): Card {
  return { entity: stubEntity, rank, suit, faceUp: true };
}

describe('rankName', () => {
  test('1 → A, 11..13 → J/Q/K, 10 → T, pip cards as digits', () => {
    expect(rankName(1)).toBe('A');
    expect(rankName(2)).toBe('2');
    expect(rankName(10)).toBe('T');
    expect(rankName(11)).toBe('J');
    expect(rankName(12)).toBe('Q');
    expect(rankName(13)).toBe('K');
    expect(rankName(99)).toBe('?');
  });
});

describe('suitChar', () => {
  test('canonical glyphs', () => {
    expect(suitChar('hearts')).toBe('\u2665');
    expect(suitChar('diamonds')).toBe('\u2666');
    expect(suitChar('clubs')).toBe('\u2663');
    expect(suitChar('spades')).toBe('\u2660');
    expect(suitChar('rocks' as never)).toBe('?');
  });
});

describe('formatCard / formatCards', () => {
  test('one card', () => {
    expect(formatCard(card(1, 'spades'))).toBe('[A\u2660]');
  });

  test('list joined with single space', () => {
    expect(formatCards([card(1, 'hearts'), card(11, 'clubs')])).toBe('[A\u2665] [J\u2663]');
  });

  test('empty list', () => {
    expect(formatCards([])).toBe('');
  });
});

```
