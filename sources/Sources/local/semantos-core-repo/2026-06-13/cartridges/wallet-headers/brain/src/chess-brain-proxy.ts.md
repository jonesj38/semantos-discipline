---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/wallet-headers/brain/src/chess-brain-proxy.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.652510+00:00
---

# cartridges/wallet-headers/brain/src/chess-brain-proxy.ts

```ts
/**
 * chess-brain-proxy — wallet-side proxy for chess cartridge verbs.
 *
 * The chess SPA at doublemate.app embeds the wallet iframe at
 * wallet.semantos.me, hands it a MessageChannel, and dispatches
 * brain calls through it. Bearer tokens never cross to the SPA
 * process — the wallet holds them, opens the WSS to the brain,
 * and returns just the result.
 *
 * Wire shape (mirrors `cartridges/bsv-anchor-bundle/brain/zig/src/
 * wss_wallet/handlers.zig::handleVerbDispatch`):
 *
 *   request  → {jsonrpc:"2.0", id, method:"verb.dispatch",
 *               params:{extensionId:"chess", verb, params}}
 *   response → {jsonrpc:"2.0", id, result:<walker-encoded JSON>}
 *   error    → {jsonrpc:"2.0", id, error:{code, message}}
 *
 * Bearer rides as `?bearer=<hex64>` query param (browser WS can't
 * set arbitrary headers on `new WebSocket(url)`).
 *
 * v0.1 transport posture: open one fresh WebSocket per request,
 * close after the matching id arrives. Same as the loom-svelte
 * WssJsonRpcTransport pattern; multiplexing onto a long-lived
 * socket is a future optimisation when call volume justifies it.
 */

export interface ChessDispatchParams {
  /** Chess walker name (create_game / submit_move / get_game / …). */
  readonly verb: string;
  /** Walker-specific JSON params. */
  readonly params: Record<string, unknown>;
  /** Brain JSON-RPC endpoint (wss://brain.<host>/api/v1/wallet). */
  readonly brainUrl: string;
  /** 64-char hex operator bearer. */
  readonly bearer: string;
  /** Per-request timeout (default 15s). */
  readonly timeoutMs?: number;
}

export interface ChessDispatchResult {
  /** Brain's JSON-RPC result — walker-encoded `{ok, gameId, …}` shape. */
  readonly result?: unknown;
  /** JSON-RPC error returned by the brain (verb walker rejection or
   *  transport-layer error). */
  readonly error?: { code: number; message: string };
}

const BEARER_RE = /^[0-9a-f]{64}$/i;

/** Validate the call params. Returns null on success or a string error. */
export function validateDispatchParams(p: Partial<ChessDispatchParams>): string | null {
  if (typeof p.verb !== 'string' || p.verb.length === 0) return 'verb: missing or empty';
  if (!/^[a-z][a-z0-9_]{0,63}$/i.test(p.verb)) return 'verb: must be [a-z][a-z0-9_]{0,63}';
  if (typeof p.params !== 'object' || p.params === null) return 'params: must be an object';
  if (typeof p.brainUrl !== 'string' || p.brainUrl.length === 0) return 'brainUrl: missing';
  let u: URL;
  try { u = new URL(p.brainUrl); } catch { return 'brainUrl: not a URL'; }
  if (u.protocol !== 'wss:' && u.protocol !== 'ws:') return 'brainUrl: must be ws:/wss:';
  if (typeof p.bearer !== 'string' || !BEARER_RE.test(p.bearer)) return 'bearer: must be 64 hex chars';
  return null;
}

/**
 * Dispatch a chess verb against the brain. Opens a fresh WSS, sends one
 * JSON-RPC verb.dispatch call, resolves with the result.
 *
 * Injectable WebSocket factory for tests — production passes
 * `(url) => new WebSocket(url)`.
 */
export function dispatchChessVerb(
  p: ChessDispatchParams,
  socketFactory: (url: string) => WebSocket = (url) => new WebSocket(url),
): Promise<ChessDispatchResult> {
  return new Promise((resolve) => {
    const id = Math.floor(Math.random() * 0xffffffff);
    const sep = p.brainUrl.includes('?') ? '&' : '?';
    const url = `${p.brainUrl}${sep}bearer=${encodeURIComponent(p.bearer)}`;
    let ws: WebSocket;
    try {
      ws = socketFactory(url);
    } catch (e) {
      resolve({ error: { code: -32603, message: `socket open: ${(e as Error).message}` } });
      return;
    }

    let settled = false;
    const settle = (out: ChessDispatchResult) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      try { ws.close(); } catch { /* already closed */ }
      resolve(out);
    };

    const timer = setTimeout(() => {
      settle({ error: { code: -32603, message: `brain rpc timeout: ${p.verb}` } });
    }, p.timeoutMs ?? 15_000);

    ws.addEventListener('open', () => {
      try {
        ws.send(JSON.stringify({
          jsonrpc: '2.0',
          id,
          method: 'verb.dispatch',
          params: {
            extensionId: 'chess',
            verb: p.verb,
            params: p.params,
          },
        }));
      } catch (e) {
        settle({ error: { code: -32603, message: `send: ${(e as Error).message}` } });
      }
    });

    ws.addEventListener('message', (ev) => {
      let text: string;
      if (typeof ev.data === 'string') text = ev.data;
      else if (ev.data instanceof ArrayBuffer) text = new TextDecoder().decode(ev.data);
      else return;
      let msg: { id?: number; result?: unknown; error?: { code: number; message: string } };
      try { msg = JSON.parse(text); }
      catch { return; }
      if (msg.id !== id) return;
      settle({ result: msg.result, error: msg.error });
    });

    ws.addEventListener('error', () => {
      settle({ error: { code: -32603, message: 'websocket error' } });
    });

    ws.addEventListener('close', () => {
      settle({ error: { code: -32603, message: 'socket closed before reply' } });
    });
  });
}

```
