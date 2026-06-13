---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/tools/smoke/prod-chess-smoke.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.543858+00:00
---

# tools/smoke/prod-chess-smoke.ts

```ts
#!/usr/bin/env bun
/**
 * prod-chess-smoke — defensive end-to-end smoke against the production
 * brain at brain.oddjobtodd.info. Runs after every deploy to catch
 * regressions in the chess walker stack, the WSS auth path, or the
 * verb-dispatcher routing without needing a real BSV anchor.
 *
 * What it exercises (Phase 1 state machine, no money):
 *
 *   chess.create_game  →  chess.get_game           (assert: waiting)
 *   chess.join_game    →  chess.list_legal_moves   (assert: 20 moves from startpos)
 *   chess.submit_move  ×4 (Fool's Mate)            (assert: black_won + checkmate)
 *   chess.resolve                                  (assert: terminal status sticks)
 *
 * Uses a one-shot WSS per call, same posture as the chess-game SPA's
 * BrainRpc and the wallet's chess-brain-proxy. Self-contained so it
 * has no workspace cross-imports — paste-portable to CI.
 *
 * Usage:
 *
 *   BRAIN_BEARER=<hex64> bun run tools/smoke/prod-chess-smoke.ts
 *   BRAIN_BEARER=<hex64> BRAIN_URL=wss://brain.example/api/v1/wallet bun run tools/smoke/prod-chess-smoke.ts
 *
 * Exit codes: 0 on full green, 1 on any assertion failure.
 *
 * To issue a fresh bearer on rbs:
 *
 *   ssh rbs 'sudo -u semantos BRAIN_DATA_DIR=/var/lib/semantos \
 *     /opt/semantos/brain bearer issue --label smoke --ttl-seconds 600'
 */

const BRAIN_URL = process.env.BRAIN_URL ?? 'wss://brain.oddjobtodd.info/api/v1/wallet';
const BRAIN_BEARER = process.env.BRAIN_BEARER;
const TIMEOUT_MS = Number(process.env.SMOKE_TIMEOUT_MS ?? 15_000);

if (!BRAIN_BEARER || !/^[0-9a-f]{64}$/i.test(BRAIN_BEARER)) {
  console.error('BRAIN_BEARER env var required (64-char hex). Issue one with:');
  console.error('  ssh rbs \'sudo -u semantos BRAIN_DATA_DIR=/var/lib/semantos \\');
  console.error('    /opt/semantos/brain bearer issue --label smoke --ttl-seconds 600\'');
  process.exit(2);
}

interface RpcResult {
  result?: unknown;
  error?: { code: number; message: string };
}

let nextId = 1;
async function dispatch(verb: string, params: Record<string, unknown>): Promise<RpcResult> {
  return new Promise((resolve) => {
    const id = nextId++;
    const sep = BRAIN_URL.includes('?') ? '&' : '?';
    const url = `${BRAIN_URL}${sep}bearer=${encodeURIComponent(BRAIN_BEARER!)}`;
    let ws: WebSocket;
    try {
      ws = new WebSocket(url);
    } catch (e) {
      resolve({ error: { code: -32603, message: `socket open: ${(e as Error).message}` } });
      return;
    }
    let settled = false;
    const settle = (r: RpcResult) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      try { ws.close(); } catch { /* ignore */ }
      resolve(r);
    };
    const timer = setTimeout(() => settle({ error: { code: -32603, message: `timeout: ${verb}` } }), TIMEOUT_MS);
    ws.addEventListener('open', () => {
      ws.send(JSON.stringify({
        jsonrpc: '2.0',
        id,
        method: 'verb.dispatch',
        params: { extensionId: 'chess', verb, params },
      }));
    });
    ws.addEventListener('message', (ev) => {
      const data = typeof ev.data === 'string' ? ev.data : new TextDecoder().decode(ev.data as ArrayBuffer);
      let msg: { id?: number; result?: unknown; error?: { code: number; message: string } };
      try { msg = JSON.parse(data); } catch { return; }
      if (msg.id !== id) return;
      settle({ result: msg.result, error: msg.error });
    });
    ws.addEventListener('error', () => settle({ error: { code: -32603, message: 'ws error' } }));
    ws.addEventListener('close', () => settle({ error: { code: -32603, message: 'socket closed before reply' } }));
  });
}

// ─── Assertion helpers ───────────────────────────────────────────────

let pass = 0;
let fail = 0;

function check(label: string, ok: boolean, detail?: string): void {
  if (ok) {
    console.log(`  \x1b[32m✓\x1b[0m ${label}`);
    pass++;
  } else {
    console.error(`  \x1b[31m✗\x1b[0m ${label}${detail ? ': ' + detail : ''}`);
    fail++;
  }
}

function isGame(r: unknown): r is { ok: true; gameId: string; status: string; fen: string; multiplier: number } {
  return typeof r === 'object' && r !== null && (r as { ok?: unknown }).ok === true;
}

// ─── The smoke run ───────────────────────────────────────────────────

async function run(): Promise<void> {
  const gameId = `smoke-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 6)}`;
  console.log(`prod-chess-smoke · brain=${BRAIN_URL} · gameId=${gameId}\n`);

  // create_game
  {
    const r = await dispatch('create_game', {
      gameId, creator: 'smoke-white', color: 'white', stakeSats: 1, clockMs: 600_000,
    });
    check('create_game returns ok:true', isGame(r.result), JSON.stringify(r));
    check('  status=waiting', isGame(r.result) && r.result.status === 'waiting');
    check('  multiplier=1', isGame(r.result) && r.result.multiplier === 1);
    check('  fen has startpos prefix', isGame(r.result) && r.result.fen.startsWith('rnbqkbnr/pppppppp/'));
  }

  // get_game (read-only)
  {
    const r = await dispatch('get_game', { gameId });
    check(
      'get_game returns same record',
      isGame(r.result) && r.result.gameId === gameId,
      r.error ? `brain error: ${r.error.message}` : `result: ${JSON.stringify(r.result)}`,
    );
  }

  // join_game
  {
    const r = await dispatch('join_game', { gameId, joiner: 'smoke-black' });
    check('join_game returns ok:true', isGame(r.result));
    check('  status=active', isGame(r.result) && r.result.status === 'active');
  }

  // list_legal_moves from startpos
  {
    const r = await dispatch('list_legal_moves', { gameId });
    const m = (r.result as { ok?: boolean; moves?: string[] } | undefined)?.moves;
    check(
      'list_legal_moves returns 20 moves from startpos',
      Array.isArray(m) && m.length === 20,
      r.error ? `brain error: ${r.error.message}` : m ? `got ${m.length}` : 'no moves array',
    );
    check('  e2e4 is legal', Array.isArray(m) && m.includes('e2e4'));
    check('  g1f3 is legal', Array.isArray(m) && m.includes('g1f3'));
  }

  // Fool's mate
  const moves: Array<[player: 'smoke-white' | 'smoke-black', uci: string]> = [
    ['smoke-white', 'f2f3'],
    ['smoke-black', 'e7e5'],
    ['smoke-white', 'g2g4'],
    ['smoke-black', 'd8h4'],
  ];
  for (let i = 0; i < moves.length; i++) {
    const [player, uci] = moves[i]!;
    const r = await dispatch('submit_move', { gameId, player, uci });
    check(`submit_move[${i}] ${player} ${uci}`, isGame(r.result), JSON.stringify(r).slice(0, 120));
  }

  // After mate, resolve confirms terminal state
  {
    const r = await dispatch('resolve', { gameId });
    const g = r.result as { ok?: boolean; status?: string; endReason?: string; winner?: string };
    check('resolve returns terminal status', g.ok === true);
    check('  status=black_won', g.status === 'black_won', `got ${g.status}`);
    check('  endReason=checkmate', g.endReason === 'checkmate', `got ${g.endReason}`);
    check('  winner=black', g.winner === 'black', `got ${g.winner}`);
  }

  // get_game post-resolve confirms the terminal state stuck
  {
    const r = await dispatch('get_game', { gameId });
    const g = (r.result ?? {}) as { ok?: boolean; status?: string };
    check(
      'get_game post-resolve still terminal',
      g.ok === true && g.status === 'black_won',
      r.error ? `brain error: ${r.error.message}` : `result: ${JSON.stringify(r.result)}`,
    );
  }

  console.log(`\n${pass} passed, ${fail} failed`);
  process.exit(fail === 0 ? 0 : 1);
}

run().catch((e) => {
  console.error('smoke crashed:', e);
  process.exit(1);
});

```
