---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/games/src/chess/pgn.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.397731+00:00
---

# packages/games/src/chess/pgn.ts

```ts
/**
 * PGN export — generate Portable Game Notation from move history.
 */

export interface PGNMove {
  moveNumber: number;
  white: string;
  black?: string;
}

/** Export a move list to PGN format. */
export function toPGN(
  moves: string[],
  headers?: Record<string, string>,
): string {
  const lines: string[] = [];

  // Headers
  const defaultHeaders: Record<string, string> = {
    Event: 'Semantos Game',
    Site: 'Semantic Shell',
    Date: new Date().toISOString().slice(0, 10).replace(/-/g, '.'),
    Round: '1',
    White: 'Player 1',
    Black: 'Player 2',
    Result: '*',
    ...headers,
  };
  for (const [key, value] of Object.entries(defaultHeaders)) {
    lines.push(`[${key} "${value}"]`);
  }
  lines.push('');

  // Moves
  const moveText: string[] = [];
  for (let i = 0; i < moves.length; i++) {
    if (i % 2 === 0) {
      moveText.push(`${Math.floor(i / 2) + 1}. ${moves[i]}`);
    } else {
      moveText.push(moves[i]);
    }
  }
  lines.push(moveText.join(' '));

  return lines.join('\n');
}

```
