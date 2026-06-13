---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/prototypes/chess-stakes-viewer.html
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.686752+00:00
---

# archive/prototypes/chess-stakes-viewer.html

```html
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Double Mate</title>
<style>
  * { margin: 0; padding: 0; box-sizing: border-box; }
  body { font-family: 'SF Mono', 'Fira Code', 'Consolas', monospace; background: #1a1a2e; color: #e0e0e0; min-height: 100vh; display: flex; flex-direction: column; align-items: center; padding: 20px; }
  h1 { font-size: 1.4em; color: #e94560; margin-bottom: 4px; letter-spacing: 2px; }
  .subtitle { font-size: 0.75em; color: #555; margin-bottom: 18px; }

  .main { display: flex; gap: 24px; flex-wrap: wrap; justify-content: center; }

  /* Board */
  .board-area { display: flex; flex-direction: column; align-items: center; }
  .board { display: grid; grid-template-columns: repeat(8, 56px); grid-template-rows: repeat(8, 56px); border: 3px solid #333; border-radius: 4px; overflow: hidden; }
  .sq { width: 56px; height: 56px; display: flex; align-items: center; justify-content: center; font-size: 38px; cursor: default; user-select: none; position: relative; line-height: 1; }
  .sq.light { background: #f0d9b5; }
  .sq.dark { background: #b58863; }
  .sq .white-piece { color: #fff; text-shadow: 0 0 2px #000, 0 0 2px #000, 1px 1px 1px rgba(0,0,0,0.6); }
  .sq .black-piece { color: #222; text-shadow: 0 0 1px rgba(255,255,255,0.3); }
  .sq.highlight { box-shadow: inset 0 0 0 3px #e94560; }
  .sq.last-from { background: #c8a84e !important; }
  .sq.last-to { background: #d4b94e !important; }

  /* Cube display */
  .cube-area { display: flex; flex-direction: column; align-items: center; margin-top: 16px; gap: 8px; }
  .cube-display { width: 64px; height: 64px; background: #2a2a4a; border: 2px solid #e94560; border-radius: 10px; display: flex; align-items: center; justify-content: center; font-size: 28px; font-weight: bold; color: #e94560; transition: all 0.3s; }
  .cube-display.offered { animation: pulse 0.6s infinite alternate; border-color: #ffcc00; color: #ffcc00; }
  @keyframes pulse { from { transform: scale(1); } to { transform: scale(1.12); } }
  .cube-label { font-size: 0.7em; color: #888; }
  .cube-holder { font-size: 0.72em; color: #aaa; }

  /* Side panel */
  .panel { width: 340px; display: flex; flex-direction: column; gap: 12px; }
  .panel-section { background: #16213e; border: 1px solid #2a2a4a; border-radius: 6px; padding: 12px; }
  .panel-section h3 { font-size: 0.8em; color: #e94560; margin-bottom: 8px; text-transform: uppercase; letter-spacing: 1px; }

  /* Strategy selectors */
  .strategy-row { display: flex; align-items: center; gap: 8px; margin-bottom: 8px; }
  .strategy-row label { font-size: 0.75em; width: 50px; color: #aaa; }
  .strategy-row select { flex: 1; background: #1a1a2e; color: #e0e0e0; border: 1px solid #333; border-radius: 4px; padding: 4px 8px; font-family: inherit; font-size: 0.75em; }

  /* Log */
  .log { max-height: 320px; overflow-y: auto; font-size: 0.72em; line-height: 1.6; }
  .log-entry { padding: 3px 0; border-bottom: 1px solid #1a1a2e; }
  .log-entry.white-move { color: #f0d9b5; }
  .log-entry.black-move { color: #b58863; }
  .log-entry.cube-action { color: #e94560; font-weight: bold; }
  .log-entry.reasoning { color: #666; font-style: italic; padding-left: 12px; font-size: 0.92em; }
  .log-entry.game-over { color: #ffcc00; font-weight: bold; font-size: 1.1em; }

  /* Score */
  .score-display { display: flex; justify-content: space-between; font-size: 0.85em; }
  .score-display .label { color: #888; }
  .score-display .value { color: #e94560; font-weight: bold; }

  /* Controls */
  .controls { display: flex; gap: 8px; align-items: center; flex-wrap: wrap; }
  .controls button { background: #e94560; color: white; border: none; border-radius: 4px; padding: 6px 14px; font-family: inherit; font-size: 0.75em; cursor: pointer; transition: background 0.2s; }
  .controls button:hover { background: #c73450; }
  .controls button:disabled { background: #444; cursor: not-allowed; }
  .controls button.secondary { background: #2a2a4a; border: 1px solid #444; }
  .controls button.secondary:hover { background: #333; }
  .speed-control { display: flex; align-items: center; gap: 6px; font-size: 0.72em; color: #888; }
  .speed-control input { width: 80px; }

  /* Status bar */
  .status-bar { margin-top: 12px; font-size: 0.78em; color: #aaa; text-align: center; min-height: 20px; }
  .status-bar.active { color: #e94560; }

  /* Match score */
  .match-score { display: flex; gap: 20px; justify-content: center; margin-top: 8px; font-size: 0.8em; }
  .match-score .side { text-align: center; }
  .match-score .side .pts { font-size: 1.6em; font-weight: bold; color: #e94560; }
</style>
</head>
<body>

<h1>DOUBLE MATE</h1>
<div class="subtitle">chess with backgammon doubling cube</div>

<div class="main">
  <div class="board-area">
    <div class="board" id="board"></div>
    <div class="cube-area">
      <div class="cube-label">DOUBLING CUBE</div>
      <div class="cube-display" id="cube-display">1</div>
      <div class="cube-holder" id="cube-holder">centered</div>
    </div>
    <div class="match-score">
      <div class="side"><div style="color:#f0d9b5">White</div><div class="pts" id="white-score">0</div></div>
      <div class="side"><div style="color:#b58863">Black</div><div class="pts" id="black-score">0</div></div>
    </div>
    <div class="status-bar" id="status-bar">Select strategies and press Play</div>
  </div>

  <div class="panel">
    <div class="panel-section">
      <h3>Strategies</h3>
      <div class="strategy-row">
        <label>White:</label>
        <select id="white-strategy">
          <option value="optimal">Optimal (by-the-book)</option>
          <option value="bluffer">Bluffer (aggressive bluffs)</option>
          <option value="shark" selected>Shark (pressure + timing)</option>
          <option value="turtle">Turtle (conservative)</option>
        </select>
      </div>
      <div class="strategy-row">
        <label>Black:</label>
        <select id="black-strategy">
          <option value="optimal">Optimal (by-the-book)</option>
          <option value="bluffer" selected>Bluffer (aggressive bluffs)</option>
          <option value="shark">Shark (pressure + timing)</option>
          <option value="turtle">Turtle (conservative)</option>
        </select>
      </div>
    </div>

    <div class="panel-section">
      <h3>Controls</h3>
      <div class="controls">
        <button id="btn-play" onclick="startMatch()">Play</button>
        <button id="btn-pause" onclick="togglePause()" disabled>Pause</button>
        <button id="btn-step" onclick="stepOnce()" class="secondary">Step</button>
        <button id="btn-reset" onclick="resetGame()" class="secondary">Reset</button>
      </div>
      <div class="speed-control" style="margin-top:8px;">
        <span>Speed:</span>
        <input type="range" id="speed" min="100" max="2000" value="700" step="100">
        <span id="speed-label">700ms</span>
      </div>
    </div>

    <div class="panel-section">
      <h3>Game Log</h3>
      <div class="log" id="log"></div>
    </div>
  </div>
</div>

<script>
// ═══════════════════════════════════════════════════════════════
// CHESS ENGINE (self-contained, no dependencies)
// ═══════════════════════════════════════════════════════════════

const PIECES = { K:'king', Q:'queen', R:'rook', B:'bishop', N:'knight', P:'pawn' };
const PIECE_CHARS = { king:'K', queen:'Q', rook:'R', bishop:'B', knight:'N', pawn:'P' };
const UNICODE = {
  white: { king:'\u2654', queen:'\u2655', rook:'\u2656', bishop:'\u2657', knight:'\u2658', pawn:'\u2659' },
  black: { king:'\u265A', queen:'\u265B', rook:'\u265C', bishop:'\u265D', knight:'\u265E', pawn:'\u265F' },
};

const VALUES = { pawn:100, knight:320, bishop:330, rook:500, queen:900, king:0 };

function file(sq) { return sq % 8; }
function rank(sq) { return Math.floor(sq / 8); }
function toSq(f, r) { return r * 8 + f; }
function sqName(sq) { return String.fromCharCode(97 + file(sq)) + (8 - rank(sq)); }

function initBoard() {
  const b = new Array(64).fill(null);
  const back = ['rook','knight','bishop','queen','king','bishop','knight','rook'];
  for (let i = 0; i < 8; i++) {
    b[i] = { type: back[i], color: 'black', moved: false };
    b[8+i] = { type: 'pawn', color: 'black', moved: false };
    b[48+i] = { type: 'pawn', color: 'white', moved: false };
    b[56+i] = { type: back[i], color: 'white', moved: false };
  }
  return b;
}

function cloneBoard(b) { return b.map(p => p ? {...p} : null); }

function isAttacked(sq, byColor, board) {
  for (let s = 0; s < 64; s++) {
    const p = board[s];
    if (!p || p.color !== byColor) continue;
    if (canAttack(p, s, sq, board)) return true;
  }
  return false;
}

function canAttack(piece, from, to, board) {
  if (from === to) return false;
  const df = file(to) - file(from), dr = rank(to) - rank(from);
  const adf = Math.abs(df), adr = Math.abs(dr);

  switch (piece.type) {
    case 'pawn': {
      const dir = piece.color === 'white' ? -1 : 1;
      return dr === dir && adf === 1;
    }
    case 'knight': return (adf === 1 && adr === 2) || (adf === 2 && adr === 1);
    case 'king': return adf <= 1 && adr <= 1;
    case 'bishop': return adf === adr && pathClear(from, to, board);
    case 'rook': return (df === 0 || dr === 0) && pathClear(from, to, board);
    case 'queen': return ((adf === adr) || (df === 0 || dr === 0)) && pathClear(from, to, board);
  }
  return false;
}

function pathClear(from, to, board) {
  const df = Math.sign(file(to) - file(from)), dr = Math.sign(rank(to) - rank(from));
  let s = toSq(file(from) + df, rank(from) + dr);
  while (s !== to) {
    if (board[s]) return false;
    s = toSq(file(s) + df, rank(s) + dr);
  }
  return true;
}

function findKing(color, board) {
  for (let s = 0; s < 64; s++) {
    if (board[s]?.type === 'king' && board[s].color === color) return s;
  }
  return -1;
}

function inCheck(color, board) {
  const kSq = findKing(color, board);
  if (kSq < 0) return false;
  const opp = color === 'white' ? 'black' : 'white';
  return isAttacked(kSq, opp, board);
}

function generateMoves(color, board, enPassant, castling) {
  const moves = [];
  for (let from = 0; from < 64; from++) {
    const p = board[from];
    if (!p || p.color !== color) continue;
    for (let to = 0; to < 64; to++) {
      if (from === to) continue;
      const target = board[to];
      if (target && target.color === color) continue;
      if (isLegalRaw(p, from, to, board, enPassant, castling)) {
        // Check if move leaves own king in check
        const sim = simulateMove(board, from, to, enPassant);
        if (!inCheck(color, sim)) {
          const isPromo = p.type === 'pawn' && (rank(to) === 0 || rank(to) === 7);
          if (isPromo) {
            for (const promo of ['queen','rook','bishop','knight']) {
              moves.push({ from, to, promotion: promo });
            }
          } else {
            moves.push({ from, to, promotion: null });
          }
        }
      }
    }
  }
  return moves;
}

function isLegalRaw(piece, from, to, board, enPassant, castling) {
  const df = file(to) - file(from), dr = rank(to) - rank(from);
  const adf = Math.abs(df), adr = Math.abs(dr);
  const target = board[to];

  switch (piece.type) {
    case 'pawn': {
      const dir = piece.color === 'white' ? -1 : 1;
      const startRank = piece.color === 'white' ? 6 : 1;
      if (df === 0 && dr === dir && !target) return true;
      if (df === 0 && dr === 2*dir && rank(from) === startRank && !target && !board[toSq(file(from), rank(from)+dir)]) return true;
      if (adf === 1 && dr === dir && target && target.color !== piece.color) return true;
      if (adf === 1 && dr === dir && to === enPassant) return true;
      return false;
    }
    case 'knight': return (adf === 1 && adr === 2) || (adf === 2 && adr === 1);
    case 'bishop': return adf === adr && adf > 0 && pathClear(from, to, board);
    case 'rook': return (df === 0 || dr === 0) && (adf + adr > 0) && pathClear(from, to, board);
    case 'queen': return ((adf === adr && adf > 0) || ((df === 0 || dr === 0) && (adf + adr > 0))) && pathClear(from, to, board);
    case 'king': {
      if (adf <= 1 && adr <= 1) return true;
      // Castling
      if (!piece.moved && dr === 0 && adf === 2) {
        const opp = piece.color === 'white' ? 'black' : 'white';
        if (inCheck(piece.color, board)) return false;
        if (df === 2) { // kingside
          const rk = piece.color === 'white' ? 'K' : 'k';
          if (!castling.includes(rk)) return false;
          const rookSq = piece.color === 'white' ? 63 : 7;
          if (!board[rookSq] || board[rookSq].type !== 'rook') return false;
          const between1 = toSq(file(from)+1, rank(from));
          const between2 = toSq(file(from)+2, rank(from));
          if (board[between1] || board[between2]) return false;
          if (isAttacked(between1, opp, board) || isAttacked(between2, opp, board)) return false;
          return true;
        }
        if (df === -2) { // queenside
          const rk = piece.color === 'white' ? 'Q' : 'q';
          if (!castling.includes(rk)) return false;
          const rookSq = piece.color === 'white' ? 56 : 0;
          if (!board[rookSq] || board[rookSq].type !== 'rook') return false;
          const b1 = toSq(file(from)-1, rank(from));
          const b2 = toSq(file(from)-2, rank(from));
          const b3 = toSq(file(from)-3, rank(from));
          if (board[b1] || board[b2] || board[b3]) return false;
          if (isAttacked(b1, opp, board) || isAttacked(b2, opp, board)) return false;
          return true;
        }
      }
      return false;
    }
  }
  return false;
}

function simulateMove(board, from, to, enPassant) {
  const b = cloneBoard(board);
  const p = b[from];
  // En passant capture
  if (p.type === 'pawn' && to === enPassant) {
    const capSq = toSq(file(to), rank(from));
    b[capSq] = null;
  }
  // Castling rook move
  if (p.type === 'king' && Math.abs(file(to) - file(from)) === 2) {
    const kingSide = file(to) > file(from);
    const rookFrom = kingSide ? toSq(7, rank(from)) : toSq(0, rank(from));
    const rookTo = kingSide ? toSq(file(from)+1, rank(from)) : toSq(file(from)-1, rank(from));
    b[rookTo] = b[rookFrom];
    if (b[rookTo]) b[rookTo].moved = true;
    b[rookFrom] = null;
  }
  b[to] = { ...p, moved: true };
  b[from] = null;
  // Promotion
  if (p.type === 'pawn' && (rank(to) === 0 || rank(to) === 7)) {
    b[to] = { ...b[to], type: 'queen' }; // default
  }
  return b;
}

// ═══════════════════════════════════════════════════════════════
// GAME STATE
// ═══════════════════════════════════════════════════════════════

let game = null;
let running = false;
let paused = false;
let timer = null;
let matchScore = { white: 0, black: 0 };

function newGame() {
  return {
    board: initBoard(),
    active: 'white',
    enPassant: null,
    castling: 'KQkq',
    halfMove: 0,
    fullMove: 1,
    cube: { value: 1, state: 'centered', holder: null, offeredBy: null },
    phase: 'cube-or-move', // cube-or-move | awaiting-response | must-move
    status: 'playing', // playing | check | checkmate | stalemate | draw | forfeited
    winner: null,
    lastFrom: -1,
    lastTo: -1,
    moveNum: 0,
    opponentModels: {
      white: { riskTolerance: 0.5, tiltFactor: 0, evalAccuracy: 0.7 },
      black: { riskTolerance: 0.5, tiltFactor: 0, evalAccuracy: 0.7 },
    },
    sharkPressure: { white: 0, black: 0 },
  };
}

// ═══════════════════════════════════════════════════════════════
// POSITION EVALUATION
// ═══════════════════════════════════════════════════════════════

function evaluatePosition(g, perspective) {
  let material = 0;
  let pieceCount = 0, queenCount = 0, pawnCount = 0;
  for (let s = 0; s < 64; s++) {
    const p = g.board[s];
    if (!p) continue;
    pieceCount++;
    if (p.type === 'queen') queenCount++;
    if (p.type === 'pawn') pawnCount++;
    const sign = p.color === perspective ? 1 : -1;
    material += sign * (VALUES[p.type] || 0);
  }

  // Centipawns to win probability (logistic)
  const rawWin = 1.0 / (1.0 + Math.pow(10, -material * 0.004));
  const evalMag = Math.abs(material);
  const drawProb = 0.28 * Math.exp(-evalMag * 0.003);
  const contested = 1.0 - drawProb;

  // Volatility
  let vol = pieceCount * 0.04 + queenCount * 0.3 + (16 - pawnCount) * 0.05;
  vol = Math.max(0.1, Math.min(5.0, vol));

  // Add some randomness to make games varied
  const noise = (Math.random() - 0.5) * 0.06;

  return {
    winProb: clamp(contested * rawWin + noise, 0.01, 0.99),
    lossProb: clamp(contested * (1 - rawWin) - noise, 0.01, 0.99),
    drawProb: clamp(drawProb, 0.01, 0.5),
    volatility: vol + (Math.random() - 0.5) * 0.3,
    centipawns: material,
    trend: (Math.random() - 0.5) * 0.4,
  };
}

function clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)); }

// ═══════════════════════════════════════════════════════════════
// CUBE STRATEGIES
// ═══════════════════════════════════════════════════════════════

function getStrategy(name) {
  switch (name) {
    case 'optimal': return strategyOptimal;
    case 'bluffer': return strategyBluffer;
    case 'shark': return strategyShark;
    case 'turtle': return strategyTurtle;
  }
  return strategyOptimal;
}

const strategyOptimal = {
  name: 'Optimal',
  shouldDouble(g, pos, opp) {
    if (pos.winProb >= 0.78 && pos.volatility < 0.8) {
      return { action: 'no-double', reason: `${(pos.winProb*100).toFixed(0)}% — too good to double, play on` };
    }
    if (pos.winProb >= 0.68) {
      return { action: 'double', reason: `Win prob ${(pos.winProb*100).toFixed(0)}% — correct double` };
    }
    return { action: 'no-double', reason: `${(pos.winProb*100).toFixed(0)}% — below doubling threshold` };
  },
  shouldTake(g, pos, opp) {
    const ourWin = pos.lossProb + pos.drawProb * 0.5;
    if (ourWin >= 0.20) {
      return { action: 'take', reason: `${(ourWin*100).toFixed(0)}% equity — correct take` };
    }
    return { action: 'drop', reason: `Only ${(ourWin*100).toFixed(0)}% equity — correct drop` };
  },
};

const strategyBluffer = {
  name: 'Bluffer',
  shouldDouble(g, pos, opp) {
    if (pos.winProb >= 0.65) {
      return { action: 'double', reason: `Genuine double at ${(pos.winProb*100).toFixed(0)}%` };
    }
    if (pos.winProb >= 0.36) {
      const bluffChance = 0.28 * (1 + (1 - opp.riskTolerance) * 0.5) + pos.volatility * 0.08;
      if (Math.random() < bluffChance) {
        return { action: 'double', reason: `BLUFF at ${(pos.winProb*100).toFixed(0)}% — vol ${pos.volatility.toFixed(1)}, opp timid ${(1-opp.riskTolerance).toFixed(1)}` };
      }
    }
    return { action: 'no-double', reason: `Holding at ${(pos.winProb*100).toFixed(0)}%, no bluff this time` };
  },
  shouldTake(g, pos, opp) {
    const ourWin = pos.lossProb + pos.drawProb * 0.5;
    if (ourWin >= 0.14) {
      return { action: 'take', reason: `Liberal take at ${(ourWin*100).toFixed(0)}% — can't fold or bluffs lose cred` };
    }
    return { action: 'drop', reason: `Even a bluffer folds at ${(ourWin*100).toFixed(0)}%` };
  },
};

const strategyShark = {
  name: 'Shark',
  shouldDouble(g, pos, opp) {
    const color = g.active;
    g.sharkPressure[color] += pos.volatility * 0.7 + Math.max(0, pos.trend) * 0.5 + opp.tiltFactor * 0.4;

    if (pos.winProb >= 0.72) {
      const p = g.sharkPressure[color];
      g.sharkPressure[color] = 0;
      return { action: 'double', reason: `Standard strike at ${(pos.winProb*100).toFixed(0)}% (pressure was ${p.toFixed(1)})` };
    }
    if (pos.winProb >= 0.52 && g.sharkPressure[color] >= 3.0 && pos.volatility >= 0.7) {
      const p = g.sharkPressure[color];
      g.sharkPressure[color] = 0;
      return { action: 'double', reason: `SHARK STRIKE at ${(pos.winProb*100).toFixed(0)}% — pressure ${p.toFixed(1)}, vol ${pos.volatility.toFixed(1)}, tilt ${opp.tiltFactor.toFixed(1)}` };
    }
    return { action: 'no-double', reason: `Pressure ${g.sharkPressure[color].toFixed(1)}/3.0, wp ${(pos.winProb*100).toFixed(0)}%` };
  },
  shouldTake(g, pos, opp) {
    const ourWin = pos.lossProb + pos.drawProb * 0.5;
    const adj = Math.min(pos.volatility * 0.03, 0.06);
    if (ourWin >= 0.22 - adj) {
      return { action: 'take', reason: `Shark takes at ${(ourWin*100).toFixed(0)}% — counterplay exists (vol ${pos.volatility.toFixed(1)})` };
    }
    return { action: 'drop', reason: `${(ourWin*100).toFixed(0)}% — no counterplay, drop` };
  },
};

const strategyTurtle = {
  name: 'Turtle',
  shouldDouble(g, pos, opp) {
    if (pos.winProb >= 0.82 && pos.volatility < 1.0) {
      return { action: 'double', reason: `Even turtles double at ${(pos.winProb*100).toFixed(0)}% in a quiet position` };
    }
    return { action: 'no-double', reason: `Turtle plays chess, not dice — ${(pos.winProb*100).toFixed(0)}%` };
  },
  shouldTake(g, pos, opp) {
    const ourWin = pos.lossProb + pos.drawProb * 0.5;
    if (ourWin >= 0.10) {
      return { action: 'take', reason: `Turtle ALWAYS takes at ${(ourWin*100).toFixed(0)}% — prove it on the board` };
    }
    return { action: 'drop', reason: `Shell cracked at ${(ourWin*100).toFixed(0)}% — even turtles have limits` };
  },
};

// ═══════════════════════════════════════════════════════════════
// AI MOVE SELECTION
// ═══════════════════════════════════════════════════════════════

/** Static material evaluation from perspective of `color`. */
function materialEval(board, color) {
  let score = 0;
  for (let s = 0; s < 64; s++) {
    const p = board[s];
    if (!p) continue;
    const v = VALUES[p.type] || 0;
    score += p.color === color ? v : -v;
  }
  return score;
}

/** Is square `sq` attacked by `byColor`? (uses existing isAttacked) */
function isSafe(sq, forColor, board) {
  const opp = forColor === 'white' ? 'black' : 'white';
  return !isAttacked(sq, opp, board);
}

/** Least valuable attacker of `sq` by `byColor`. Returns piece value or 0. */
function leastValuableAttacker(sq, byColor, board) {
  let minVal = Infinity;
  for (let s = 0; s < 64; s++) {
    const p = board[s];
    if (!p || p.color !== byColor) continue;
    if (canAttack(p, s, sq, board)) {
      const v = VALUES[p.type] || 0;
      if (v < minVal) minVal = v;
    }
  }
  return minVal === Infinity ? 0 : minVal;
}

/**
 * Static Exchange Evaluation (simplified).
 * Returns a rough score for capturing on `sq` with piece from `from`.
 * Positive = good trade, negative = bad trade.
 */
function seeCapture(from, to, board, capturedVal) {
  const attacker = board[from];
  if (!attacker) return 0;
  const attackerVal = VALUES[attacker.type] || 0;
  const opp = attacker.color === 'white' ? 'black' : 'white';

  // If nothing defends the square, the capture is free
  if (!isAttacked(to, opp, board)) return capturedVal;

  // Rough heuristic: capture is good if we take something more valuable,
  // or equal value, or if we take something and nothing else defends
  return capturedVal - attackerVal;
}

function pickMove(g) {
  const moves = generateMoves(g.active, g.board, g.enPassant, g.castling);
  if (moves.length === 0) return null;

  const us = g.active;
  const opp = us === 'white' ? 'black' : 'white';
  const stratName = us === 'white'
    ? document.getElementById('white-strategy').value
    : document.getElementById('black-strategy').value;

  let best = null, bestScore = -99999;

  for (const m of moves) {
    let score = 0;
    const piece = g.board[m.from];
    const target = g.board[m.to];
    const pieceVal = VALUES[piece.type] || 0;

    // ── 1. Captures (with exchange evaluation) ──────────────
    if (target) {
      const captureVal = VALUES[target.type] || 0;
      // MVV-LVA: prefer capturing valuable pieces with cheap pieces
      score += captureVal * 10 + (1000 - pieceVal);
      // Penalize bad trades (capturing a pawn with a queen when defended)
      const see = seeCapture(m.from, m.to, g.board, captureVal);
      if (see < 0) score += see * 3; // penalize losing trades
    }

    // ── 2. Promotion (huge bonus) ───────────────────────────
    if (m.promotion) {
      score += VALUES[m.promotion] * 10;
      if (m.promotion === 'queen') score += 5000; // ALWAYS promote
    }

    // ── 3. Piece safety — don't move to attacked squares ────
    // Simulate the move and check if the piece is safe there
    const simBoard = simulateMove(g.board, m.from, m.to, g.enPassant);
    if (m.promotion) {
      simBoard[m.to] = { ...simBoard[m.to], type: m.promotion };
    }

    if (!isSafe(m.to, us, simBoard)) {
      // Piece is hanging on destination
      if (!target) {
        // Moving to an attacked empty square — bad
        score -= pieceVal * 2;
      } else {
        // Capture but piece hangs — ok if we won material
        const captureVal = VALUES[target.type] || 0;
        if (captureVal < pieceVal) score -= (pieceVal - captureVal);
      }
    }

    // ── 4. Don't leave pieces hanging at origin ─────────────
    // Check if we were defending something at the from-square
    // (Skip this for now — too expensive)

    // ── 5. Check bonus ──────────────────────────────────────
    if (inCheck(opp, simBoard)) {
      score += 200; // giving check is usually good
    }

    // ── 6. Pawn advancement (pushed pawns toward promotion) ─
    if (piece.type === 'pawn') {
      const promRank = us === 'white' ? 0 : 7;
      const distToPromo = Math.abs(rank(m.to) - promRank);
      score += (7 - distToPromo) * 25; // closer to promotion = better
      // Passed-ish pawn bonus (no enemy pawn directly ahead)
      const ahead = us === 'white' ? m.to - 8 : m.to + 8;
      if (ahead >= 0 && ahead < 64 && !g.board[ahead]) score += 15;
    }

    // ── 7. Center control ───────────────────────────────────
    const cf = file(m.to), cr = rank(m.to);
    score += (3.5 - Math.abs(cf - 3.5)) * 3 + (3.5 - Math.abs(cr - 3.5)) * 3;

    // ── 8. Development (unmoved minor pieces) ───────────────
    if (!piece.moved && (piece.type === 'knight' || piece.type === 'bishop')) {
      score += 60;
    }

    // ── 9. Castling bonus ───────────────────────────────────
    if (piece.type === 'king' && Math.abs(file(m.to) - file(m.from)) === 2) {
      score += 150; // castling is great
    }

    // ── 10. King safety — penalize early king moves ─────────
    if (piece.type === 'king' && g.moveNum < 30 && Math.abs(file(m.to) - file(m.from)) < 2) {
      score -= 120; // don't wander the king in the opening/middlegame
    }

    // ── 11. Strategy personality tweaks ─────────────────────
    if (stratName === 'shark' && target) score += 30; // sharks like captures
    if (stratName === 'turtle') score += (piece.type === 'pawn' ? 8 : 0); // turtles push pawns

    // ── 12. Small randomness for variety ────────────────────
    score += Math.random() * 12;

    if (score > bestScore) { bestScore = score; best = m; }
  }
  return best;
}

// ═══════════════════════════════════════════════════════════════
// GAME EXECUTION
// ═══════════════════════════════════════════════════════════════

function executeMove(g, move) {
  const b = g.board;
  const p = b[move.from];
  const captured = b[move.to];
  const isEP = p.type === 'pawn' && move.to === g.enPassant;
  const isCastle = p.type === 'king' && Math.abs(file(move.to) - file(move.from)) === 2;

  // En passant capture
  if (isEP) {
    b[toSq(file(move.to), rank(move.from))] = null;
  }

  // Castling
  if (isCastle) {
    const ks = file(move.to) > file(move.from);
    const rf = ks ? toSq(7, rank(move.from)) : toSq(0, rank(move.from));
    const rt = ks ? toSq(file(move.from)+1, rank(move.from)) : toSq(file(move.from)-1, rank(move.from));
    b[rt] = { ...b[rf], moved: true };
    b[rf] = null;
  }

  // Move piece
  b[move.to] = { ...p, moved: true };
  b[move.from] = null;

  // Promotion
  if (move.promotion) {
    b[move.to].type = move.promotion;
  }

  // En passant target
  g.enPassant = null;
  if (p.type === 'pawn' && Math.abs(rank(move.to) - rank(move.from)) === 2) {
    g.enPassant = toSq(file(move.from), (rank(move.from) + rank(move.to)) / 2);
  }

  // Castling rights
  if (p.type === 'king') {
    if (p.color === 'white') g.castling = g.castling.replace(/[KQ]/g, '');
    else g.castling = g.castling.replace(/[kq]/g, '');
  }
  if (p.type === 'rook') {
    if (move.from === 63) g.castling = g.castling.replace('K', '');
    if (move.from === 56) g.castling = g.castling.replace('Q', '');
    if (move.from === 7) g.castling = g.castling.replace('k', '');
    if (move.from === 0) g.castling = g.castling.replace('q', '');
  }

  // Half-move clock
  g.halfMove = (p.type === 'pawn' || captured || isEP) ? 0 : g.halfMove + 1;
  if (g.active === 'black') g.fullMove++;

  g.lastFrom = move.from;
  g.lastTo = move.to;
  g.moveNum++;

  // Switch turn
  g.active = g.active === 'white' ? 'black' : 'white';
  g.phase = 'cube-or-move';

  // Check game status
  const moves = generateMoves(g.active, g.board, g.enPassant, g.castling);
  const check = inCheck(g.active, g.board);
  if (moves.length === 0) {
    g.status = check ? 'checkmate' : 'stalemate';
    g.winner = check ? (g.active === 'white' ? 'black' : 'white') : null;
  } else if (check) {
    g.status = 'check';
  } else if (g.halfMove >= 100) {
    g.status = 'draw';
  } else {
    g.status = 'playing';
  }

  // Build notation
  let notation = '';
  if (isCastle) {
    notation = file(move.to) > file(move.from) ? 'O-O' : 'O-O-O';
  } else {
    if (p.type !== 'pawn') notation += PIECE_CHARS[p.type];
    if (captured || isEP) {
      if (p.type === 'pawn') notation += String.fromCharCode(97 + file(move.from));
      notation += 'x';
    }
    notation += sqName(move.to);
    if (move.promotion) notation += '=' + PIECE_CHARS[move.promotion];
  }
  if (g.status === 'checkmate') notation += '#';
  else if (g.status === 'check') notation += '+';

  return { notation, captured: !!captured || isEP };
}

// ═══════════════════════════════════════════════════════════════
// GAME LOOP
// ═══════════════════════════════════════════════════════════════

function stepOnce() {
  if (!game) { game = newGame(); renderBoard(); }
  if (game.status !== 'playing' && game.status !== 'check') return;

  const color = game.active;
  const opp = color === 'white' ? 'black' : 'white';
  const stratName = color === 'white' ? document.getElementById('white-strategy').value : document.getElementById('black-strategy').value;
  const oppStratName = opp === 'white' ? document.getElementById('white-strategy').value : document.getElementById('black-strategy').value;
  const strategy = getStrategy(stratName);
  const oppStrategy = getStrategy(oppStratName);

  // Phase: cube-or-move — decide whether to double
  if (game.phase === 'cube-or-move') {
    const canDouble = game.cube.value < 64 &&
      game.cube.state !== 'offered' &&
      (game.cube.state === 'centered' || game.cube.holder === color) &&
      (game.status === 'playing' || game.status === 'check');

    if (canDouble) {
      const pos = evaluatePosition(game, color);
      const oppModel = game.opponentModels[opp];
      const decision = strategy.shouldDouble(game, pos, oppModel);

      if (decision.action === 'double') {
        const nextVal = game.cube.value * 2;
        game.cube.state = 'offered';
        game.cube.offeredBy = color;
        game.phase = 'awaiting-response';

        logEntry(`${icon(color)} ${strategy.name} doubles to ${nextVal}!`, 'cube-action');
        logEntry(decision.reason, 'reasoning');
        renderBoard();
        return; // next step will handle response
      } else {
        // Log non-doubling reasoning occasionally
        if (Math.random() < 0.15) {
          logEntry(`${icon(color)} ${strategy.name}: ${decision.reason}`, 'reasoning');
        }
      }
    }

    // No double — make a chess move
    game.phase = 'must-move';
  }

  // Phase: awaiting-response — opponent must take or drop
  if (game.phase === 'awaiting-response') {
    const responder = opp === color ? color : (color === 'white' ? 'black' : 'white');
    // The responder is the opponent of whoever offered
    const actualResponder = game.cube.offeredBy === 'white' ? 'black' : 'white';
    const respStratName = actualResponder === 'white' ? document.getElementById('white-strategy').value : document.getElementById('black-strategy').value;
    const respStrategy = getStrategy(respStratName);

    const pos = evaluatePosition(game, actualResponder);
    const offererModel = game.opponentModels[game.cube.offeredBy];
    const decision = respStrategy.shouldTake(game, pos, offererModel);

    if (decision.action === 'take') {
      game.cube.value *= 2;
      game.cube.state = 'held';
      game.cube.holder = actualResponder;
      game.cube.offeredBy = null;
      game.phase = 'must-move'; // offerer now moves

      logEntry(`${icon(actualResponder)} ${respStrategy.name} TAKES — stakes now ${game.cube.value}`, 'cube-action');
      logEntry(decision.reason, 'reasoning');

      // Update opponent model (offerer observes the take)
      game.opponentModels[actualResponder].riskTolerance = Math.min(1, game.opponentModels[actualResponder].riskTolerance + 0.03);
      game.opponentModels[actualResponder].tiltFactor = Math.max(0, game.opponentModels[actualResponder].tiltFactor - 0.05);

      renderBoard();
      return;
    } else {
      // DROP — game over!
      game.status = 'forfeited';
      game.winner = game.cube.offeredBy;

      logEntry(`${icon(actualResponder)} ${respStrategy.name} DROPS — forfeits!`, 'cube-action');
      logEntry(decision.reason, 'reasoning');
      logEntry(`${icon(game.winner)} wins ${game.cube.value} point${game.cube.value > 1 ? 's' : ''} by forfeit`, 'game-over');

      matchScore[game.winner] += game.cube.value;
      game.opponentModels[actualResponder].tiltFactor = Math.min(1, game.opponentModels[actualResponder].tiltFactor + 0.1);

      renderBoard();
      updateMatchScore();
      endGame();
      return;
    }
  }

  // Phase: must-move — make the chess move
  if (game.phase === 'must-move') {
    const move = pickMove(game);
    if (!move) {
      game.status = 'stalemate';
      renderBoard();
      endGame();
      return;
    }

    const result = executeMove(game, move);
    const moveStr = `${Math.ceil(game.moveNum/2)}${color === 'black' ? '...' : '.'} ${result.notation}`;
    logEntry(`${icon(color)} ${moveStr}`, color === 'white' ? 'white-move' : 'black-move');

    if (game.status === 'checkmate') {
      const pts = game.cube.value;
      logEntry(`CHECKMATE! ${icon(game.winner)} wins ${pts} point${pts > 1 ? 's' : ''}`, 'game-over');
      matchScore[game.winner] += pts;
      updateMatchScore();
      endGame();
    } else if (game.status === 'stalemate' || game.status === 'draw') {
      logEntry(`Draw — 0 points`, 'game-over');
      endGame();
    }

    renderBoard();
  }
}

function icon(color) { return color === 'white' ? '\u2654' : '\u265A'; }

function startMatch() {
  if (running && !paused) return;
  if (!game || game.status !== 'playing' && game.status !== 'check') {
    game = newGame();
    clearLog();
    const ws = document.getElementById('white-strategy');
    const bs = document.getElementById('black-strategy');
    logEntry(`${getStrategy(ws.value).name} (white) vs ${getStrategy(bs.value).name} (black)`, 'cube-action');
    logEntry('─'.repeat(40), 'reasoning');
  }
  running = true;
  paused = false;
  document.getElementById('btn-play').disabled = true;
  document.getElementById('btn-pause').disabled = false;
  renderBoard();
  scheduleNext();
}

function scheduleNext() {
  if (!running || paused) return;
  const speed = parseInt(document.getElementById('speed').value);
  timer = setTimeout(() => {
    if (!running || paused) return;
    stepOnce();
    if (game.status === 'playing' || game.status === 'check') {
      scheduleNext();
    }
  }, speed);
}

function togglePause() {
  if (paused) {
    paused = false;
    document.getElementById('btn-pause').textContent = 'Pause';
    scheduleNext();
  } else {
    paused = true;
    document.getElementById('btn-pause').textContent = 'Resume';
    if (timer) clearTimeout(timer);
  }
}

function endGame() {
  running = false;
  paused = false;
  if (timer) clearTimeout(timer);
  document.getElementById('btn-play').disabled = false;
  document.getElementById('btn-play').textContent = 'New Game';
  document.getElementById('btn-pause').disabled = true;
}

function resetGame() {
  running = false;
  paused = false;
  if (timer) clearTimeout(timer);
  game = null;
  matchScore = { white: 0, black: 0 };
  clearLog();
  document.getElementById('btn-play').disabled = false;
  document.getElementById('btn-play').textContent = 'Play';
  document.getElementById('btn-pause').disabled = true;
  document.getElementById('btn-pause').textContent = 'Pause';
  document.getElementById('white-score').textContent = '0';
  document.getElementById('black-score').textContent = '0';
  renderBoard();
}

// ═══════════════════════════════════════════════════════════════
// RENDERING
// ═══════════════════════════════════════════════════════════════

function renderBoard() {
  const boardEl = document.getElementById('board');
  boardEl.innerHTML = '';
  const b = game ? game.board : initBoard();

  for (let sq = 0; sq < 64; sq++) {
    const div = document.createElement('div');
    const isLight = (file(sq) + rank(sq)) % 2 === 0;
    div.className = 'sq ' + (isLight ? 'light' : 'dark');
    if (game && sq === game.lastFrom) div.classList.add('last-from');
    if (game && sq === game.lastTo) div.classList.add('last-to');
    const p = b[sq];
    if (p) {
      const span = document.createElement('span');
      span.className = p.color === 'white' ? 'white-piece' : 'black-piece';
      span.textContent = UNICODE[p.color][p.type];
      div.appendChild(span);
    }
    boardEl.appendChild(div);
  }

  // Cube
  const cubeEl = document.getElementById('cube-display');
  const holderEl = document.getElementById('cube-holder');
  if (game) {
    cubeEl.textContent = game.cube.value;
    cubeEl.className = 'cube-display' + (game.cube.state === 'offered' ? ' offered' : '');
    if (game.cube.state === 'centered') holderEl.textContent = 'centered — either can double';
    else if (game.cube.state === 'offered') holderEl.textContent = `${game.cube.offeredBy} offers ${game.cube.value * 2}`;
    else holderEl.textContent = `held by ${game.cube.holder}`;
  } else {
    cubeEl.textContent = '1';
    cubeEl.className = 'cube-display';
    holderEl.textContent = 'centered';
  }

  // Status
  const statusEl = document.getElementById('status-bar');
  if (!game) {
    statusEl.textContent = 'Select strategies and press Play';
    statusEl.className = 'status-bar';
  } else if (game.status === 'checkmate') {
    statusEl.textContent = `Checkmate — ${game.winner} wins (${game.cube.value} pts)`;
    statusEl.className = 'status-bar active';
  } else if (game.status === 'forfeited') {
    statusEl.textContent = `Forfeit — ${game.winner} wins (${game.cube.value} pts)`;
    statusEl.className = 'status-bar active';
  } else if (game.status === 'stalemate' || game.status === 'draw') {
    statusEl.textContent = 'Draw';
    statusEl.className = 'status-bar';
  } else {
    const phaseText = game.phase === 'awaiting-response' ? ' — DOUBLE OFFERED' : '';
    statusEl.textContent = `${game.active} to play${phaseText} (cube: ${game.cube.value})`;
    statusEl.className = 'status-bar' + (game.phase === 'awaiting-response' ? ' active' : '');
  }
}

function updateMatchScore() {
  document.getElementById('white-score').textContent = matchScore.white;
  document.getElementById('black-score').textContent = matchScore.black;
}

function logEntry(text, cls) {
  const log = document.getElementById('log');
  const div = document.createElement('div');
  div.className = 'log-entry ' + (cls || '');
  div.textContent = text;
  log.appendChild(div);
  log.scrollTop = log.scrollHeight;
}

function clearLog() {
  document.getElementById('log').innerHTML = '';
}

// Speed label
document.getElementById('speed').addEventListener('input', (e) => {
  document.getElementById('speed-label').textContent = e.target.value + 'ms';
});

// Init
renderBoard();
</script>
</body>
</html>

```
