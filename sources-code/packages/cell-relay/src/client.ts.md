---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/cell-relay/src/client.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.440015+00:00
---

# packages/cell-relay/src/client.ts

```ts
/**
 * RelayClient — minimal WebSocket client for the cell-relay wire
 * protocol. Browser and Node/Bun compatible (uses the platform's
 * native WebSocket).
 *
 * Anything that wants to subscribe to a cell-stream room and commit
 * cells to it talks through this. The room can be a jam room, a
 * release-tracking room, any future per-room append-only DAG.
 *
 *   const c = new RelayClient({ url: 'ws://localhost:5178', room: 'jam', identity: 'todd' });
 *   const snap = await c.connect();
 *   c.on('commit', (m) => console.log('peer commit:', m.cell.stateHashHex));
 *   c.commit(myCell);
 *   c.disconnect();
 */

import type {
  ClientMsg,
  CommitMsg,
  ConnectOptions,
  LiveMsg,
  PresenceMsg,
  ResetMsg,
  SerializedCell,
  ServerMsg,
  SnapshotMsg,
} from './types';

type EventMap = {
  commit: CommitMsg;
  live: LiveMsg;
  presence: PresenceMsg;
  reset: ResetMsg;
  /** Connection closed — payload is { code, reason }. */
  close: { code: number; reason: string };
  /** Underlying socket error. */
  error: Event;
};

type Handler<K extends keyof EventMap> = (msg: EventMap[K]) => void;

export class RelayClient {
  private ws: WebSocket | null = null;
  private handlers: Partial<{ [K in keyof EventMap]: Set<Handler<K>> }> = {};
  private snapshot: SnapshotMsg | null = null;
  /** Resolves on first snapshot. */
  private connectResolve: ((s: SnapshotMsg) => void) | null = null;
  private connectReject: ((err: Error) => void) | null = null;

  constructor(public readonly opts: ConnectOptions) {}

  /**
   * Open the WebSocket and resolve when the server's first message
   * (a SnapshotMsg) arrives. Rejects if the connection closes before
   * the snapshot lands.
   */
  connect(): Promise<SnapshotMsg> {
    if (this.ws) throw new Error('already connecting/connected');
    const url = new URL(this.opts.url.replace(/\/+$/, '') + '/');
    url.searchParams.set('room', this.opts.room);
    url.searchParams.set('as', this.opts.identity);

    return new Promise<SnapshotMsg>((resolve, reject) => {
      this.connectResolve = resolve;
      this.connectReject = reject;
      const ws = new WebSocket(url.toString());
      this.ws = ws;
      ws.addEventListener('message', (ev: MessageEvent) => this.onMessage(ev));
      ws.addEventListener('error', (ev: Event) => this.emit('error', ev));
      ws.addEventListener('close', (ev: CloseEvent) => {
        this.emit('close', { code: ev.code, reason: ev.reason });
        if (this.connectReject) {
          this.connectReject(new Error(`socket closed before snapshot: ${ev.code} ${ev.reason}`));
          this.connectResolve = null;
          this.connectReject = null;
        }
      });
    });
  }

  /** The snapshot received on connect, or null if not yet connected. */
  currentSnapshot(): SnapshotMsg | null {
    return this.snapshot;
  }

  commit(cell: SerializedCell): void {
    this.send({ type: 'commit', cell });
  }

  live(payload: unknown): void {
    this.send({ type: 'live', payload });
  }

  reset(): void {
    this.send({ type: 'reset' });
  }

  on<K extends keyof EventMap>(event: K, handler: Handler<K>): () => void {
    let set = this.handlers[event] as Set<Handler<K>> | undefined;
    if (!set) {
      set = new Set<Handler<K>>();
      // @ts-expect-error — heterogeneous map; runtime is fine.
      this.handlers[event] = set;
    }
    set.add(handler);
    return () => set!.delete(handler);
  }

  disconnect(code = 1000, reason = 'client disconnect'): void {
    if (!this.ws) return;
    try {
      this.ws.close(code, reason);
    } finally {
      this.ws = null;
    }
  }

  // ── Internals ──────────────────────────────────────────────────────

  private send(msg: ClientMsg): void {
    if (!this.ws || this.ws.readyState !== WebSocket.OPEN) {
      throw new Error('not connected');
    }
    this.ws.send(JSON.stringify(msg));
  }

  private onMessage(ev: MessageEvent): void {
    const data = typeof ev.data === 'string' ? ev.data : '';
    if (!data) return;
    let msg: ServerMsg;
    try {
      msg = JSON.parse(data) as ServerMsg;
    } catch {
      return;
    }
    switch (msg.type) {
      case 'snapshot': {
        this.snapshot = msg;
        if (this.connectResolve) {
          this.connectResolve(msg);
          this.connectResolve = null;
          this.connectReject = null;
        }
        break;
      }
      case 'commit':
        this.emit('commit', msg);
        break;
      case 'live':
        this.emit('live', msg);
        break;
      case 'presence':
        this.emit('presence', msg);
        break;
      case 'reset':
        this.emit('reset', msg);
        break;
    }
  }

  private emit<K extends keyof EventMap>(event: K, payload: EventMap[K]): void {
    const set = this.handlers[event] as Set<Handler<K>> | undefined;
    if (!set) return;
    for (const h of set) {
      try {
        h(payload);
      } catch (err) {
        // eslint-disable-next-line no-console
        console.error(`RelayClient handler for ${String(event)} threw:`, err);
      }
    }
  }
}

```
