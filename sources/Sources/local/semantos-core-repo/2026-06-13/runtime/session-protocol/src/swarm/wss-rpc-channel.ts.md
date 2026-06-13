---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/swarm/wss-rpc-channel.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.055257+00:00
---

# runtime/session-protocol/src/swarm/wss-rpc-channel.ts

```ts
/**
 * WssRpcChannel — the production RpcChannel: JSON-RPC 2.0 over a WebSocket to
 * the brain's unified `/api/v1/rpc`. Backs RpcSwarmBrainClient so the brain
 * becomes the live tracker / settlement layer (replacing FileBrainClient).
 *
 *   request:  {"jsonrpc":"2.0","id":N,"method":"verb.dispatch","params":{extensionId,verb,params}}
 *   response: {"jsonrpc":"2.0","id":N,"result":...}  |  {"jsonrpc":"2.0","id":N,"error":{code,message}}
 *
 * Auth: a bearer token is appended as `?bearer=` (the brain's web-auth query).
 * Lazy connect on first call, request/response id-correlation, per-request
 * timeout, reconnect on the next call after a drop (in-flight requests reject).
 *
 * NOTE: the exact envelope (method name, result-as-string vs object) should be
 * confirmed against the deployed brain during integration; `result` is parsed
 * if it arrives as a JSON string, so both forms work.
 */

import type { RpcChannel } from './rpc-brain-client';

/** Minimal structural type for the WHATWG WebSocket the channel drives. */
export interface WebSocketLike {
  readyState: number;
  send(data: string): void;
  close(): void;
  addEventListener(type: 'open' | 'close' | 'error', cb: () => void, opts?: { once?: boolean }): void;
  addEventListener(type: 'message', cb: (ev: { data: unknown }) => void): void;
}
export type WebSocketFactory = (url: string) => WebSocketLike;

export interface WssRpcChannelOptions {
  /** Bearer token → appended as `?bearer=` (brain web auth). */
  bearer?: string;
  /** Per-request timeout in ms (default 10000). */
  timeoutMs?: number;
  /** Inject a WebSocket factory (defaults to the global WebSocket). */
  webSocketFactory?: WebSocketFactory;
}

interface Pending {
  resolve: (v: unknown) => void;
  reject: (e: Error) => void;
  timer: ReturnType<typeof setTimeout>;
}

const WS_OPEN = 1;

export class WssRpcChannel implements RpcChannel {
  private readonly url: string;
  private readonly timeoutMs: number;
  private readonly factory: WebSocketFactory;
  private ws: WebSocketLike | null = null;
  private connecting: Promise<WebSocketLike> | null = null;
  private nextId = 1;
  private readonly pending = new Map<number, Pending>();
  private closed = false;

  constructor(url: string, opts: WssRpcChannelOptions = {}) {
    const u = new URL(url);
    if (opts.bearer) u.searchParams.set('bearer', opts.bearer);
    this.url = u.toString();
    this.timeoutMs = opts.timeoutMs ?? 10_000;
    const def = (globalThis as { WebSocket?: new (url: string) => WebSocketLike }).WebSocket;
    this.factory = opts.webSocketFactory ?? (def ? (url2: string) => new def(url2) : () => {
      throw new Error('WssRpcChannel: no WebSocket implementation; pass webSocketFactory');
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
        reject(new Error('WssRpcChannel: connection failed'));
      }, { once: true });
      ws.addEventListener('message', ev => this.onMessage(ev.data));
      ws.addEventListener('close', () => this.onClose());
    });
    return this.connecting;
  }

  private onMessage(data: unknown): void {
    let msg: { id?: number; result?: unknown; error?: { code?: number; message?: string } };
    try {
      msg = JSON.parse(typeof data === 'string' ? data : String(data));
    } catch {
      return; // not a JSON frame
    }
    if (typeof msg.id !== 'number') return;
    const p = this.pending.get(msg.id);
    if (!p) return;
    this.pending.delete(msg.id);
    clearTimeout(p.timer);
    if (msg.error) {
      p.reject(new Error(`rpc error ${msg.error.code ?? ''}: ${msg.error.message ?? 'unknown'}`));
      return;
    }
    let result = msg.result;
    if (typeof result === 'string') {
      try { result = JSON.parse(result); } catch { /* leave as string */ }
    }
    p.resolve(result);
  }

  private onClose(): void {
    this.ws = null;
    this.connecting = null;
    for (const [, p] of this.pending) {
      clearTimeout(p.timer);
      p.reject(new Error('WssRpcChannel: socket closed'));
    }
    this.pending.clear();
  }

  async call(method: string, params: unknown): Promise<unknown> {
    if (this.closed) throw new Error('WssRpcChannel: channel closed');
    const ws = await this.ensureSocket();
    const id = this.nextId++;
    const frame = JSON.stringify({ jsonrpc: '2.0', id, method, params });
    return new Promise<unknown>((resolve, reject) => {
      const timer = setTimeout(() => {
        this.pending.delete(id);
        reject(new Error(`WssRpcChannel: timeout waiting for ${method} (#${id})`));
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

  /** Close the socket and reject any in-flight requests. */
  close(): void {
    this.closed = true;
    const ws = this.ws;
    this.onClose();
    ws?.close();
  }
}

```
