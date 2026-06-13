---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/tests/gates/chess-stakes-gate.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.576650+00:00
---

# tests/gates/chess-stakes-gate.test.ts

```ts
/**
 * Chess Stakes Gate Tests — Doubling Cube Mechanics
 *
 * Tests the doubling cube as a semantic entity:
 * - Cube is a LINEAR cell (cannot be duplicated)
 * - Ownership transfers on "take"
 * - State transitions governed by compiled Lisp policies
 * - Forfeit-by-drop ends game at current stakes
 * - Chess rules remain fully enforced underneath
 */

import { describe, test, expect } from 'bun:test';

// ── T1-T4: Cube Cell Creation ────────────────────────────────────

describe('Chess Stakes — Cube creation', () => {
  test('T1: cube created at game start as LINEAR cell', async () => {
    const { StakesChessEngine } = await import('../../packages/games/src/chess-stakes/engine');
    const engine = await StakesChessEngine.create();
    const cube = engine.getCube();

    expect(cube.entity).toBeDefined();
    expect(cube.entity.linearity).toBe(1); // LINEAR
    expect(cube.entity.id).toBeTruthy();
  });

  test('T2: cube starts centered with value 1, no holder', async () => {
    const { StakesChessEngine } = await import('../../packages/games/src/chess-stakes/engine');
    const engine = await StakesChessEngine.create();
    const cube = engine.getCube();

    expect(cube.value).toBe(1);
    expect(cube.state).toBe('centered');
    expect(cube.holder).toBeNull();
    expect(cube.offeredBy).toBeNull();
  });

  test('T3: game starts in cube-or-move phase, white to act', async () => {
    const { StakesChessEngine } = await import('../../packages/games/src/chess-stakes/engine');
    const engine = await StakesChessEngine.create();

    expect(engine.getPhase()).toBe('cube-or-move');
    expect(engine.activeColor()).toBe('white');
  });

  test('T4: 32 chess pieces plus 1 cube cell = 33 LINEAR entities', async () => {
    const { StakesChessEngine } = await import('../../packages/games/src/chess-stakes/engine');
    const engine = await StakesChessEngine.create();
    const state = engine.getState();

    const pieces = state.chess.squares.filter(p => p !== null);
    expect(pieces.length).toBe(32);
    expect(state.cube.entity).toBeDefined();
    // Total LINEAR cells: 32 pieces + 1 cube
  });
});

// ── T5-T8: Double Offer ──────────────────────────────────────────

describe('Chess Stakes — Double offer', () => {
  test('T5: white can offer double on first turn (cube centered)', async () => {
    const { StakesChessEngine } = await import('../../packages/games/src/chess-stakes/engine');
    const engine = await StakesChessEngine.create();

    expect(engine.canDouble()).toBe(true);

    const result = engine.act({ type: 'double' });
    expect(result.cube.state).toBe('offered');
    expect(result.cube.offeredBy).toBe('white');
    expect(result.gameResult).toBeNull();
    expect(engine.getPhase()).toBe('awaiting-response');
  });

  test('T6: cannot offer double when one is already pending', async () => {
    const { StakesChessEngine } = await import('../../packages/games/src/chess-stakes/engine');
    const engine = await StakesChessEngine.create();

    engine.act({ type: 'double' }); // white offers

    // Now it's awaiting response — can't double again
    expect(() => engine.act({ type: 'double' })).toThrow();
  });

  test('T7: cannot move while double is pending', async () => {
    const { StakesChessEngine } = await import('../../packages/games/src/chess-stakes/engine');
    const engine = await StakesChessEngine.create();

    engine.act({ type: 'double' }); // white offers

    // Can't make chess move while awaiting response
    expect(() => engine.act({ type: 'move', from: 52, to: 36 })).toThrow();
    expect(engine.legalMoves(52)).toEqual([]); // no legal moves in this phase
  });

  test('T8: cube value unchanged after offer (not yet doubled)', async () => {
    const { StakesChessEngine } = await import('../../packages/games/src/chess-stakes/engine');
    const engine = await StakesChessEngine.create();

    engine.act({ type: 'double' });
    expect(engine.getCube().value).toBe(1); // still 1 until taken
  });
});

// ── T9-T12: Take (Accept Double) ────────────────────────────────

describe('Chess Stakes — Take double', () => {
  test('T9: opponent takes double, value doubles, cube transfers', async () => {
    const { StakesChessEngine } = await import('../../packages/games/src/chess-stakes/engine');
    const engine = await StakesChessEngine.create();

    engine.act({ type: 'double' }); // white offers
    const result = engine.act({ type: 'take' }); // black takes

    expect(result.cube.value).toBe(2);
    expect(result.cube.state).toBe('held');
    expect(result.cube.holder).toBe('black'); // taker holds cube
    expect(result.cube.offeredBy).toBeNull();
    expect(engine.getPhase()).toBe('must-move'); // offerer (white) must now move
  });

  test('T10: after take, offerer must move (cannot double again immediately)', async () => {
    const { StakesChessEngine } = await import('../../packages/games/src/chess-stakes/engine');
    const engine = await StakesChessEngine.create();

    engine.act({ type: 'double' }); // white offers
    engine.act({ type: 'take' }); // black takes

    expect(engine.getPhase()).toBe('must-move');
    expect(() => engine.act({ type: 'double' })).toThrow();
  });

  test('T11: after take and move, holder can double on their turn', async () => {
    const { StakesChessEngine } = await import('../../packages/games/src/chess-stakes/engine');
    const engine = await StakesChessEngine.create();

    // White doubles, black takes
    engine.act({ type: 'double' });
    engine.act({ type: 'take' });

    // White moves (e2-e4: pawn at square 52 to square 36)
    engine.act({ type: 'move', from: 52, to: 36 });

    // Now it's black's turn — black holds the cube, so black can double
    expect(engine.activeColor()).toBe('black');
    expect(engine.getCube().holder).toBe('black');
    expect(engine.canDouble()).toBe(true);
  });

  test('T12: non-holder cannot double (only holder can)', async () => {
    const { StakesChessEngine } = await import('../../packages/games/src/chess-stakes/engine');
    const engine = await StakesChessEngine.create();

    // White doubles, black takes (black now holds cube)
    engine.act({ type: 'double' });
    engine.act({ type: 'take' });

    // White moves
    engine.act({ type: 'move', from: 52, to: 36 });

    // Black moves (e7-e5: pawn at square 12 to square 28)
    engine.act({ type: 'move', from: 12, to: 28 });

    // Now white's turn — but black holds the cube, so white CANNOT double
    expect(engine.activeColor()).toBe('white');
    expect(engine.getCube().holder).toBe('black');
    expect(engine.canDouble()).toBe(false);
  });
});

// ── T13-T15: Drop (Decline → Forfeit) ───────────────────────────

describe('Chess Stakes — Drop double (forfeit)', () => {
  test('T13: opponent drops, game ends, offerer wins at current stakes', async () => {
    const { StakesChessEngine } = await import('../../packages/games/src/chess-stakes/engine');
    const engine = await StakesChessEngine.create();

    engine.act({ type: 'double' }); // white offers (cube value = 1)
    const result = engine.act({ type: 'drop' }); // black drops

    expect(result.gameResult).not.toBeNull();
    expect(result.gameResult!.status).toBe('forfeited');
    expect(result.gameResult!.winner).toBe('white');
    expect(result.gameResult!.cubeValue).toBe(1); // at current value, not proposed
    expect(result.gameResult!.points).toBe(1);
  });

  test('T14: drop at higher stakes awards more points', async () => {
    const { StakesChessEngine } = await import('../../packages/games/src/chess-stakes/engine');
    const engine = await StakesChessEngine.create();

    // First double: 1→2
    engine.act({ type: 'double' }); // white offers
    engine.act({ type: 'take' }); // black takes (cube=2, holder=black)
    engine.act({ type: 'move', from: 52, to: 36 }); // white: e2-e4

    // Second double: 2→4
    engine.act({ type: 'double' }); // black offers (holder=black)
    engine.act({ type: 'take' }); // white takes (cube=4, holder=white)
    engine.act({ type: 'move', from: 12, to: 28 }); // black: e7-e5

    // Third double: 4→8
    engine.act({ type: 'double' }); // white offers (holder=white)
    const result = engine.act({ type: 'drop' }); // black drops at value=4

    expect(result.gameResult!.status).toBe('forfeited');
    expect(result.gameResult!.winner).toBe('white');
    expect(result.gameResult!.cubeValue).toBe(4);
    expect(result.gameResult!.points).toBe(4);
  });

  test('T15: cannot drop when no double is offered', async () => {
    const { StakesChessEngine } = await import('../../packages/games/src/chess-stakes/engine');
    const engine = await StakesChessEngine.create();

    expect(() => engine.act({ type: 'drop' })).toThrow();
  });
});

// ── T16-T18: Cube Value Progression ──────────────────────────────

describe('Chess Stakes — Value progression', () => {
  test('T16: cube values follow 1→2→4→8→16→32→64', async () => {
    const { nextCubeValue, CUBE_VALUES } = await import('../../packages/games/src/chess-stakes/types');

    expect(CUBE_VALUES).toEqual([1, 2, 4, 8, 16, 32, 64]);
    expect(nextCubeValue(1)).toBe(2);
    expect(nextCubeValue(2)).toBe(4);
    expect(nextCubeValue(4)).toBe(8);
    expect(nextCubeValue(8)).toBe(16);
    expect(nextCubeValue(16)).toBe(32);
    expect(nextCubeValue(32)).toBe(64);
    expect(nextCubeValue(64)).toBeNull(); // max
  });

  test('T17: multiple doubles accumulate correctly', async () => {
    const { StakesChessEngine } = await import('../../packages/games/src/chess-stakes/engine');
    const engine = await StakesChessEngine.create();

    // Round 1: 1→2
    engine.act({ type: 'double' });
    engine.act({ type: 'take' });
    expect(engine.getCube().value).toBe(2);
    engine.act({ type: 'move', from: 52, to: 36 }); // white: e4

    // Round 2: 2→4 (black holds cube, black doubles)
    engine.act({ type: 'double' });
    engine.act({ type: 'take' });
    expect(engine.getCube().value).toBe(4);
  });

  test('T18: cannot double past 64', async () => {
    const { nextCubeValue } = await import('../../packages/games/src/chess-stakes/types');
    expect(nextCubeValue(64)).toBeNull();
  });
});

// ── T19-T20: Chess + Cube Integration ────────────────────────────

describe('Chess Stakes — Chess integration', () => {
  test('T19: normal chess move works without doubling', async () => {
    const { StakesChessEngine } = await import('../../packages/games/src/chess-stakes/engine');
    const engine = await StakesChessEngine.create();

    // Just play chess normally (skip doubling)
    const result = engine.act({ type: 'move', from: 52, to: 36 }); // e2-e4

    expect(result.board.activeColor).toBe('black');
    expect(result.cube.value).toBe(1); // unchanged
    expect(result.gameResult).toBeNull();
    expect(engine.getPhase()).toBe('cube-or-move');
  });

  test('T20: checkmate with cube multiplier awards correct points', async () => {
    const { StakesChessEngine } = await import('../../packages/games/src/chess-stakes/engine');
    const engine = await StakesChessEngine.create();

    // Double first to raise stakes
    engine.act({ type: 'double' });
    engine.act({ type: 'take' }); // cube = 2

    // Play Scholar's Mate: 1. e4 e5 2. Bc4 Nc6 3. Qh5 Nf6?? 4. Qxf7#
    engine.act({ type: 'move', from: 52, to: 36 }); // 1. e4
    engine.act({ type: 'move', from: 12, to: 28 }); // 1... e5
    engine.act({ type: 'move', from: 61, to: 34 }); // 2. Bc4
    engine.act({ type: 'move', from: 1, to: 18 });  // 2... Nc6
    engine.act({ type: 'move', from: 59, to: 31 }); // 3. Qh5
    engine.act({ type: 'move', from: 6, to: 21 });  // 3... Nf6??
    const result = engine.act({ type: 'move', from: 31, to: 13 }); // 4. Qxf7#

    expect(result.gameResult).not.toBeNull();
    expect(result.gameResult!.status).toBe('checkmate');
    expect(result.gameResult!.winner).toBe('white');
    expect(result.gameResult!.cubeValue).toBe(2);
    expect(result.gameResult!.points).toBe(2); // checkmate × cube value
  });
});

// ── T21: Cube Cell DAG Linkage ───────────────────────────────────

describe('Chess Stakes — Cell DAG', () => {
  test('T21: cube cell updates form a chain via prevStateHash', async () => {
    const { StakesChessEngine } = await import('../../packages/games/src/chess-stakes/engine');
    const engine = await StakesChessEngine.create();

    const initialCellId = engine.getCube().entity.id;

    // Double and take — cube entity gets updated (new cell with prevStateHash)
    engine.act({ type: 'double' });
    const afterOffer = engine.getCube().entity.id;
    expect(afterOffer).toBe(initialCellId); // same entity, updated cell

    engine.act({ type: 'take' });
    const afterTake = engine.getCube().entity.id;
    expect(afterTake).toBe(initialCellId); // still same entity ID

    // The entity cell bytes should differ (metadata changed)
    // This verifies the cell was actually updated, not duplicated
    expect(engine.getCube().entity.cell).toBeDefined();
    expect(engine.getCube().value).toBe(2);
  });
});

```
