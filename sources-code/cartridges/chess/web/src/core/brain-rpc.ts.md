---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/chess/web/src/core/brain-rpc.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.431213+00:00
---

# cartridges/chess/web/src/core/brain-rpc.ts

```ts
/**
 * Brain JSON-RPC client over WSS — `verb.dispatch` only.
 *
 * Mirrors the per-request transport posture from
 * `apps/loom-svelte/src/lib/oddjobz-query.ts::WssJsonRpcTransport`: one
 * WebSocket per request, settle on first matching id, close. The chess
 * UI's request rate is tiny (a click per move) so multiplexing onto a
 * long-lived socket buys nothing yet.
 *
 * Wire shape (mirrors `cartridges/bsv-anchor-bundle/brain/zig/src/wss_wallet/
 * handlers.zig::handleVerbDispatch`):
 *
 *   request  → {jsonrpc:"2.0", id, method:"verb.dispatch",
 *               params:{extensionId, verb, params}}
 *   response → {jsonrpc:"2.0", id, result:<walker-encoded JSON>}
 *   error    → {jsonrpc:"2.0", id, error:{code, message}}
 *
 * Bearer rides as `?bearer=<hex64>` because `new WebSocket(url)` can't set
 * request headers — same convention `wss_wallet.zig::extractBearer` honours.
 */

export interface VerbResult {
  /** Walker-shaped response — `{ok:true,gameId,game?}` or `{ok:false,reason}`. */
  readonly result?: unknown;
  /** JSON-RPC error if the brain rejected before the walker ran. */
  readonly error?: { code: number; message: string };
}

export class BrainRpc {
  private nextId = 1;
  private readonly timeoutMs: number;

  constructor(
    private readonly wssUrl: string,
    private readonly bearer: string,
    opts?: { timeoutMs?: number },
  ) {
    this.timeoutMs = opts?.timeoutMs ?? 10_000;
  }

  /** Dispatch a chess-cartridge verb. */
  dispatch(verb: string, params: Record<string, unknown>): Promise<VerbResult> {
    return this.call('verb.dispatch', {
      extensionId: 'chess',
      verb,
      params,
    });
  }

  private call(method: string, params: Record<string, unknown>): Promise<VerbResult> {
    return new Promise((resolve, reject) => {
      const id = this.nextId++;
      const url = `${this.wssUrl}${this.wssUrl.includes('?') ? '&' : '?'}bearer=${encodeURIComponent(this.bearer)}`;
      let ws: WebSocket;
      try {
        ws = new WebSocket(url);
      } catch (e) {
        reject(e);
        return;
      }

      let settled = false;
      const settle = (action: { ok: true; v: VerbResult } | { ok: false; e: Error }) => {
        if (settled) return;
        settled = true;
        clearTimeout(timer);
        try { ws.close(); } catch { /* already closed */ }
        if (action.ok) resolve(action.v);
        else reject(action.e);
      };

      const timer = setTimeout(() => {
        settle({ ok: false, e: new Error(`brain rpc timeout: ${method}`) });
      }, this.timeoutMs);

      ws.addEventListener('open', () => {
        try {
          ws.send(JSON.stringify({ jsonrpc: '2.0', id, method, params }));
        } catch (e) {
          settle({ ok: false, e: e instanceof Error ? e : new Error(String(e)) });
        }
      });

      ws.addEventListener('message', (ev) => {
        let text: string;
        if (typeof ev.data === 'string') text = ev.data;
        else if (ev.data instanceof ArrayBuffer) text = new TextDecoder().decode(ev.data);
        else return;
        let msg: { id?: number; result?: unknown; error?: { code: number; message: string } };
        try {
          msg = JSON.parse(text);
        } catch {
          return;
        }
        if (msg.id !== id) return;
        settle({ ok: true, v: { result: msg.result, error: msg.error } });
      });

      ws.addEventListener('error', () => {
        settle({ ok: false, e: new Error(`brain rpc websocket error: ${method}`) });
      });

      ws.addEventListener('close', () => {
        settle({ ok: false, e: new Error(`brain rpc socket closed before reply: ${method}`) });
      });
    });
  }
}

/**
 * Brain WSS URL resolution order:
 *   1. `localStorage.chess.brainUrl` — operator override at runtime
 *   2. `import.meta.env.VITE_BRAIN_WSS_URL` — set at build time per
 *      target (see .env.production for doublemate.app)
 *   3. localhost fallback — `ws://<hostname>:7777/api/v1/wallet`
 *
 * No more hostname-prefix munging. Production builds bake the target
 * brain URL via Vite envs so the binary on disk knows where to talk
 * without depending on the deployed origin's domain shape.
 */
export function defaultBrainWssUrl(): string {
  if (typeof localStorage !== 'undefined') {
    const override = localStorage.getItem('chess.brainUrl');
    if (override) return override;
  }
  const fromEnv = (import.meta as ImportMeta & { env?: Record<string, string> }).env?.VITE_BRAIN_WSS_URL;
  if (fromEnv) return fromEnv;
  // Dev fallback — assume the brain is on loopback.
  const host = location.hostname === 'localhost' || location.hostname.endsWith('.local')
    ? `${location.hostname}:7777`
    : `${location.hostname}:7777`;
  const proto = location.protocol === 'https:' ? 'wss' : 'ws';
  return `${proto}://${host}/api/v1/wallet`;
}

```
