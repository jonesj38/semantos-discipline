---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/chess/web/src/svelte/components/Board.svelte
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.432232+00:00
---

# cartridges/chess/web/src/svelte/components/Board.svelte

```svelte
<script lang="ts">
  import { parseFen, squareToUci } from '../../chess/fen.js';
  import type { Piece } from '../../chess/fen.js';
  import type { Color } from '../../chess/types.js';

  interface Props {
    fen: string;
    sideToMove: Color;
    myColor: Color | null;
    /** UCI strings for every legal move from the current FEN. */
    legalMoves: readonly string[];
    onMove: (uci: string) => void;
  }

  let { fen, sideToMove, myColor, legalMoves, onMove }: Props = $props();

  // Legal-destination index: from-square (e.g. "e2") → set of to-squares
  // (e.g. {"e3", "e4"}). Rebuilds whenever legalMoves changes; lets
  // square clicks check legality in O(1) and the renderer highlight
  // destinations for the selected piece.
  let legalIndex = $derived.by(() => {
    const m = new Map<string, Set<string>>();
    for (const uci of legalMoves) {
      const from = uci.slice(0, 2);
      const to = uci.slice(2, 4);
      let set = m.get(from);
      if (!set) { set = new Set(); m.set(from, set); }
      set.add(to);
    }
    return m;
  });

  let selectedDests = $derived.by<Set<string>>(() => {
    if (!selected) return new Set();
    const fromUci = squareToUci(selected.rank, selected.file);
    return legalIndex.get(fromUci) ?? new Set();
  });

  const PIECE_GLYPH: Record<Piece, string> = {
    '': '',
    P: '♙', N: '♘', B: '♗', R: '♖', Q: '♕', K: '♔',
    p: '♟', n: '♞', b: '♝', r: '♜', q: '♛', k: '♚',
  };

  let board = $derived.by(() => {
    try { return parseFen(fen).board; }
    catch { return [] as readonly (readonly Piece[])[]; }
  });

  let selected = $state<{ rank: number; file: number } | null>(null);
  let promotionPending = $state<string | null>(null);
  // From-piece kind for the promotion-rank check.
  let promotionFromPiece = $state<Piece>('');
  // Drag-and-drop: UCI square currently hovered as a drop target ("e4" etc).
  let dragTarget = $state<string | null>(null);

  // Flip the board when I'm playing black so my pieces are at the bottom.
  let flipped = $derived(myColor === 'black');

  function clickSquare(rank: number, file: number): void {
    if (!isMyTurn()) return;
    if (selected) {
      if (selected.rank === rank && selected.file === file) {
        selected = null;
        return;
      }
      // Reselect onto another own piece — switch selection rather than
      // attempting an illegal move.
      const clickedPiece = board[rank]?.[file] ?? '';
      if (clickedPiece !== '') {
        const clickedIsWhite = clickedPiece === clickedPiece.toUpperCase();
        if ((myColor === 'white') === clickedIsWhite) {
          selected = { rank, file };
          return;
        }
      }
      const fromUci = squareToUci(selected.rank, selected.file);
      const toUci = squareToUci(rank, file);
      // Drop the click if it's not a legal destination — saves a server
      // roundtrip + rejection log entry.
      if (!selectedDests.has(toUci)) {
        selected = null;
        return;
      }
      const fromPiece = board[selected.rank]![selected.file]!;
      const isWhitePawnToBack = fromPiece === 'P' && rank === 0;
      const isBlackPawnToBack = fromPiece === 'p' && rank === 7;
      if (isWhitePawnToBack || isBlackPawnToBack) {
        promotionFromPiece = fromPiece;
        promotionPending = `${fromUci}${toUci}`;
        selected = null;
        return;
      }
      onMove(`${fromUci}${toUci}`);
      selected = null;
    } else {
      const piece = board[rank]?.[file] ?? '';
      if (piece === '') return;
      const isWhite = piece === piece.toUpperCase();
      if ((myColor === 'white') !== isWhite) return;
      // Only allow selecting a piece that has at least one legal move.
      // If the legalMoves index hasn't loaded yet (initial render),
      // permit selection so the UI doesn't feel frozen.
      const fromUci = squareToUci(rank, file);
      if (legalIndex.size > 0 && !legalIndex.has(fromUci)) return;
      selected = { rank, file };
    }
  }

  function pickPromotion(p: 'q'|'r'|'b'|'n'): void {
    if (!promotionPending) return;
    onMove(`${promotionPending}${p}`);
    promotionPending = null;
    promotionFromPiece = '';
  }

  function isMyTurn(): boolean {
    if (!myColor) return false;
    return (sideToMove === 'white' && myColor === 'white')
        || (sideToMove === 'black' && myColor === 'black');
  }

  // ── Drag-and-drop ─────────────────────────────────────────────────────
  // startDrag: called on the dragged piece's square. Sets `selected` so
  // the existing legal-dest highlighting immediately lights up.
  function startDrag(e: DragEvent, rank: number, file: number): void {
    if (!isMyTurn()) { e.preventDefault(); return; }
    const piece = board[rank]?.[file] ?? '';
    if (!piece) { e.preventDefault(); return; }
    const isWhitePiece = piece === piece.toUpperCase();
    if ((myColor === 'white') !== isWhitePiece) { e.preventDefault(); return; }
    const fromUci = squareToUci(rank, file);
    if (legalIndex.size > 0 && !legalIndex.has(fromUci)) { e.preventDefault(); return; }
    selected = { rank, file };
    e.dataTransfer!.effectAllowed = 'move';
    e.dataTransfer!.setData('text/plain', fromUci);
  }

  // enterDrag: called on every square while dragging over it. preventDefault
  // is what tells the browser "this is a valid drop target" (otherwise ondrop
  // never fires and the cursor shows the no-drop icon).
  function enterDrag(e: DragEvent, rank: number, file: number): void {
    if (!selected) return;
    const toUci = squareToUci(rank, file);
    if (selectedDests.has(toUci)) {
      e.preventDefault();
      e.dataTransfer!.dropEffect = 'move';
      dragTarget = toUci;
    }
  }

  function leaveDrag(rank: number, file: number): void {
    if (dragTarget === squareToUci(rank, file)) dragTarget = null;
  }

  function dropPiece(e: DragEvent, rank: number, file: number): void {
    e.preventDefault();
    dragTarget = null;
    if (!selected) return;
    const toUci = squareToUci(rank, file);
    if (!selectedDests.has(toUci)) { selected = null; return; }
    const fromUci = squareToUci(selected.rank, selected.file);
    const fromPiece = board[selected.rank]![selected.file]!;
    if ((fromPiece === 'P' && rank === 0) || (fromPiece === 'p' && rank === 7)) {
      promotionFromPiece = fromPiece;
      promotionPending = `${fromUci}${toUci}`;
      selected = null;
      return;
    }
    onMove(`${fromUci}${toUci}`);
    selected = null;
  }

  // endDrag fires on the source square after any drag ends (drop or cancel).
  // Clear selection so a cancelled drag doesn't leave the piece "selected".
  function endDrag(): void {
    dragTarget = null;
    selected = null;
  }

  // Visual indices: when flipped, render rank/file in reverse.
  let visualRanks = $derived(flipped ? [7,6,5,4,3,2,1,0] : [0,1,2,3,4,5,6,7]);
  let visualFiles = $derived(flipped ? [7,6,5,4,3,2,1,0] : [0,1,2,3,4,5,6,7]);
</script>

<div class="board" class:my-turn={isMyTurn()}>
  {#each visualRanks as rank}
    {#each visualFiles as file}
      {@const piece = board[rank]?.[file] ?? ''}
      {@const isLight = (rank + file) % 2 === 0}
      {@const isSelected = selected?.rank === rank && selected?.file === file}
      {@const toUci = squareToUci(rank, file)}
      {@const isLegalDest = selectedDests.has(toUci)}
      {@const isCapture = isLegalDest && piece !== ''}
      {@const isMine = piece !== '' && ((myColor === 'white') === (piece === piece.toUpperCase()))}
      {@const canDrag = isMyTurn() && isMine && (legalIndex.size === 0 || legalIndex.has(toUci))}
      <button
        class="sq"
        class:light={isLight}
        class:dark={!isLight}
        class:selected={isSelected}
        class:legal={isLegalDest && !isCapture}
        class:capture={isCapture}
        class:drag-over={dragTarget === toUci}
        draggable={canDrag}
        onclick={() => clickSquare(rank, file)}
        ondragstart={(e) => startDrag(e, rank, file)}
        ondragover={(e) => enterDrag(e, rank, file)}
        ondragleave={() => leaveDrag(rank, file)}
        ondrop={(e) => dropPiece(e, rank, file)}
        ondragend={endDrag}
        aria-label={toUci}
      >
        <span class="glyph" class:white={piece && piece === piece.toUpperCase()}>{PIECE_GLYPH[piece]}</span>
      </button>
    {/each}
  {/each}
</div>

{#if promotionPending}
  <div class="promo">
    <span>Promote to:</span>
    {#each (['q','r','b','n'] as const) as p}
      <button onclick={() => pickPromotion(p)}>{PIECE_GLYPH[promotionFromPiece === 'P' ? (p.toUpperCase() as Piece) : (p as Piece)]}</button>
    {/each}
  </div>
{/if}

<style>
  .board {
    display: grid;
    grid-template-columns: repeat(8, 1fr);
    /* Pin rows too — without this, rows are auto-sized by content
       (the piece glyph + line-height), so the middle 4 empty ranks
       collapse to a single tall row and the populated ranks stack
       short. aspect-ratio on the board only constrains the outer
       container, not the row heights. */
    grid-template-rows: repeat(8, 1fr);
    width: min(80vmin, 640px);
    aspect-ratio: 1 / 1;
    border: 2px solid #2a2f3a;
    border-radius: 4px;
    overflow: hidden;
    user-select: none;
  }
  .sq {
    border: 0;
    padding: 0;
    font-size: clamp(20px, 5vmin, 44px);
    line-height: 1;
    cursor: pointer;
    display: flex;
    align-items: center;
    justify-content: center;
    /* min-height: 0 lets the 1fr row honour the parent aspect-ratio
       instead of being padded out by the button's default content-box. */
    min-height: 0;
  }
  .sq.light { background: #ebecd0; color: #1a1c20; }
  .sq.dark  { background: #739552; color: #1a1c20; }
  .sq.selected { outline: 3px solid #4f8cff; outline-offset: -3px; z-index: 1; }
  .sq.legal { position: relative; }
  .sq.legal::after {
    content: '';
    position: absolute;
    left: 50%;
    top: 50%;
    width: 28%;
    height: 28%;
    transform: translate(-50%, -50%);
    background: rgba(79, 140, 255, 0.55);
    border-radius: 50%;
    pointer-events: none;
  }
  .sq.capture { box-shadow: inset 0 0 0 4px rgba(231, 76, 60, 0.85); }
  /* Pulsing blue ring on the square you're hovering over during a drag. */
  .sq.drag-over { box-shadow: inset 0 0 0 4px rgba(79, 140, 255, 0.9); }
  .glyph.white { color: #fafafa; text-shadow: 0 0 2px #0b0d12, 0 0 4px #0b0d12; }
  .board:not(.my-turn) .sq { cursor: not-allowed; opacity: 0.85; }
  .promo {
    margin-top: 0.6em;
    display: flex;
    gap: 0.4em;
    align-items: center;
    color: var(--fg, #e8eaed);
  }
  .promo button {
    font-size: 28px;
    width: 1.6em;
    height: 1.6em;
    background: #1a1d24;
    color: #fafafa;
    border: 1px solid #2a2f3a;
    border-radius: 4px;
    cursor: pointer;
  }
</style>

```
