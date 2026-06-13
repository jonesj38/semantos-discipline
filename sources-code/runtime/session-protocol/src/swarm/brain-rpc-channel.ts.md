---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/swarm/brain-rpc-channel.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.057259+00:00
---

# runtime/session-protocol/src/swarm/brain-rpc-channel.ts

```ts
/**
 * BrainRpcChannel — an `RpcChannel` speaking the brain's WSS `/api/v1/rpc`
 * frame format (the `t`-tagged codec in
 * runtime/semantos-brain/src/wss_rpc_registry.zig), not JSON-RPC 2.0.
 *
 *   request   {"t":"req","id":"<string>","method":"<m>","params":<obj>}
 *   response  {"t":"res","id":"<string>","result":<body>}
 *             {"t":"err","id":"<string>","code":"<code>","message":"<msg>"}
 *
 * (The sibling `WssRpcChannel` frames JSON-RPC 2.0 for a different server; the
 * brain reactor rejects that as "unsupported frame", so the live brain needs
 * this codec.) Auth is a bearer appended as `?bearer=` at the WSS upgrade.
 *
 * `.call(method, params)` resolves with the `result` body, or rejects with an
 * Error carrying the brain's `code`/`message` (a handler trap surfaces here —
 * e.g. `handler_rejected` / `verify_failed`), which is exactly what
 * BrainAccessGrantVerifier reads as the engine verdict.
 */

import type { RpcChannel } from './rpc-brain-client';
import type { WebSocketLike, WebSocketFactory } from './wss-rpc-channel';

export interface BrainRpcChannelOptions {
  bearer?: string;
  timeoutMs?: number;
  webSocketFactory?: WebSocketFactory;
}

interface Pending {
  resolve: (v: unknown) => void;
  reject: (e: Error) => void;
  timer: ReturnType<typeof setTimeout>;
}

const WS_OPEN = 1;

export class BrainRpcChannel implements RpcChannel {
  private readonly url: string;
  private readonly timeoutMs: number;
  private readonly factory: WebSocketFactory;
  private ws: WebSocketLike | null = null;
  private connecting: Promise<WebSocketLike> | null = null;
  private nextId = 1;
  private readonly pending = new Map<string, Pending>();
  private closed = false;

  constructor(url: string, opts: BrainRpcChannelOptions = {}) {
    const u = new URL(url);
    if (opts.bearer) u.searchParams.set('bearer', opts.bearer);
    this.url = u.toString();
    this.timeoutMs = opts.timeoutMs ?? 10_000;
    const def = (globalThis as { WebSocket?: new (url: string) => WebSocketLike }).WebSocket;
    this.factory =
      opts.webSocketFactory ??
      (def
        ? (url2: string) => new def(url2)
        : () => {
            throw new Error('BrainRpcChannel: no WebSocket implementation; pass webSocketFactory');
          });
  }

  private ensureSocket(): Promise<WebSocketLike> {
    if (this.ws && this.ws.readyState === WS_OPEN) return Promise.resolve(this.ws);
    if (this.connecting) return this.connecting;
    this.connecting = new Promise<WebSocketLike>((resolve, reject) => {
      let settled = false;
      const ws = this.factory(this.url);
      ws.addEventListener('open', () => {
        if (settled) return;
        settled = true;
        this.ws = ws;
        this.connecting = null;
        resolve(ws);
      }, { once: true });
      ws.addEventListener('error', () => {
        if (settled) return;
        settled = true;
        this.connecting = null;
        reject(new Error('BrainRpcChannel: connection failed'));
      }, { once: true });
      ws.addEventListener('message', (ev) => this.onMessage(ev.data));
      ws.addEventListener('close', () => this.onClose());
    });
    return this.connecting;
  }

  private onMessage(data: unknown): void {
    let msg: { t?: string; id?: string; result?: unknown; code?: string; message?: string };
    try {
      msg = JSON.parse(typeof data === 'string' ? data : String(data));
    } catch {
      return;
    }
    if (typeof msg.id !== 'string') return;
    const p = this.pending.get(msg.id);
    if (!p) return;
    this.pending.delete(msg.id);
    clearTimeout(p.timer);
    if (msg.t === 'res') p.resolve(msg.result);
    else if (msg.t === 'err') p.reject(new Error(`brain rpc ${msg.code ?? 'error'}: ${msg.message ?? ''}`));
    else p.reject(new Error(`brain rpc: unexpected frame t=${String(msg.t)}`));
  }

  private onClose(): void {
    this.ws = null;
    for (const [, p] of this.pending) {
      clearTimeout(p.timer);
      p.reject(new Error('BrainRpcChannel: socket closed'));
    }
    this.pending.clear();
  }

  async call(method: string, params: unknown): Promise<unknown> {
    if (this.closed) throw new Error('BrainRpcChannel: channel closed');
    const ws = await this.ensureSocket();
    const id = String(this.nextId++);
    const frame = JSON.stringify({ t: 'req', id, method, params });
    return new Promise<unknown>((resolve, reject) => {
      const timer = setTimeout(() => {
        this.pending.delete(id);
        reject(new Error(`BrainRpcChannel: timeout waiting for ${method} (#${id})`));
      }, this.timeoutMs);
      this.pending.set(id, { resolve, reject, timer });
      try {
        ws.send(frame);
      } catch (e) {
        clearTimeout(timer);
        this.pending.delete(id);
        reject(e as Error);
      }
    });
  }

  close(): void {
    this.closed = true;
    const ws = this.ws;
    this.onClose();
    ws?.close();
  }
}

```
