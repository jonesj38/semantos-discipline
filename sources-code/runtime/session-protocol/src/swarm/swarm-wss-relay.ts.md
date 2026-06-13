---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/swarm/swarm-wss-relay.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.055551+00:00
---

# runtime/session-protocol/src/swarm/swarm-wss-relay.ts

```ts
/**
 * WSS swarm transport — the cross-internet data plane.
 *
 * UDP multicast is LAN-only; this makes the swarm work between peers anywhere.
 * Every peer dials OUT to a relay over WebSocket (so NAT/firewalls need no
 * inbound rules), joins a ROOM (the swarm group — e.g. the rendezvous group
 * derived from an infohash), and the relay fans frames within the room. The
 * relay is a dumb frame switch: it understands rooms + peer ids, NOT swarm
 * semantics or payments (those stay end-to-end inside the frames).
 *
 * Implements the SAME SwarmTransport port as udp/in-memory, so the engine,
 * MeteredTransfer, LayeredBrainClient, and the metered-flow channels are all
 * unchanged — only the transport swaps.
 *
 *   client→relay msg:  [op:u8][targetLen:u8][target…][frame…]   op 0=broadcast 1=unicast
 *   relay→client msg:  [fromLen:u8][fromId…][frame…]
 */

import type { SwarmTransport, FrameHandler } from './swarm-transport';

// ── wire helpers ──────────────────────────────────────────────────────────────

function encodeClientMsg(op: 0 | 1, target: string, frame: Uint8Array): Uint8Array {
  const t = new TextEncoder().encode(target);
  const buf = new Uint8Array(2 + t.length + frame.length);
  buf[0] = op;
  buf[1] = t.length;
  buf.set(t, 2);
  buf.set(frame, 2 + t.length);
  return buf;
}

function decodeClientMsg(buf: Uint8Array): { op: number; target: string; frame: Uint8Array } | null {
  if (buf.length < 2) return null;
  const op = buf[0];
  const tLen = buf[1];
  if (buf.length < 2 + tLen) return null;
  const target = new TextDecoder().decode(buf.subarray(2, 2 + tLen));
  return { op, target, frame: buf.slice(2 + tLen) };
}

function encodeRelayMsg(from: string, frame: Uint8Array): Uint8Array {
  const f = new TextEncoder().encode(from);
  const buf = new Uint8Array(1 + f.length + frame.length);
  buf[0] = f.length;
  buf.set(f, 1);
  buf.set(frame, 1 + f.length);
  return buf;
}

function decodeRelayMsg(buf: Uint8Array): { from: string; frame: Uint8Array } | null {
  if (buf.length < 1) return null;
  const fLen = buf[0];
  if (buf.length < 1 + fLen) return null;
  const from = new TextDecoder().decode(buf.subarray(1, 1 + fLen));
  return { from, frame: buf.slice(1 + fLen) };
}

function toU8(data: unknown): Uint8Array | null {
  if (data instanceof Uint8Array) return data;
  if (data instanceof ArrayBuffer) return new Uint8Array(data);
  if (typeof Buffer !== 'undefined' && data instanceof Buffer) return new Uint8Array(data);
  return null;
}

// ── relay server (Bun.serve) ───────────────────────────────────────────────────

export interface SwarmRelayHandle {
  port: number;
  /** Live peer count per room (diagnostics). */
  rooms(): Record<string, number>;
  stop(): Promise<void>;
}

/**
 * A room-fanout WSS relay. Peers connect to `ws://host:port?room=<r>&id=<peer>`.
 * Broadcasts fan to every other peer in the room; unicasts route to one peer id.
 */
export function serveSwarmRelay(port = 0): SwarmRelayHandle {
  const rooms = new Map<string, Map<string, any>>();

  const join = (room: string, id: string, ws: any) => {
    let m = rooms.get(room);
    if (!m) { m = new Map(); rooms.set(room, m); }
    m.set(id, ws);
  };
  const leave = (room: string, id: string) => {
    const m = rooms.get(room);
    if (!m) return;
    m.delete(id);
    if (m.size === 0) rooms.delete(room);
  };

  const server = Bun.serve({
    port,
    fetch(req, srv) {
      const url = new URL(req.url);
      const room = url.searchParams.get('room') ?? 'default';
      const id = url.searchParams.get('id') ?? `peer-${Math.abs(hashStr(url.search))}`;
      if (srv.upgrade(req, { data: { room, id } })) return undefined;
      return new Response('swarm relay (use WebSocket)', { status: 426 });
    },
    websocket: {
      open(ws: any) { join(ws.data.room, ws.data.id, ws); },
      close(ws: any) { leave(ws.data.room, ws.data.id); },
      message(ws: any, message: string | Buffer) {
        const bytes = toU8(message);
        if (!bytes) return;
        const msg = decodeClientMsg(bytes);
        if (!msg) return;
        const room = rooms.get(ws.data.room);
        if (!room) return;
        const out = encodeRelayMsg(ws.data.id, msg.frame);
        if (msg.op === 1) {
          room.get(msg.target)?.send(out); // unicast
        } else {
          for (const [pid, peer] of room) {       // broadcast (exclude sender)
            if (pid !== ws.data.id) peer.send(out);
          }
        }
      },
    },
  });

  return {
    port: server.port,
    rooms() {
      const out: Record<string, number> = {};
      for (const [r, m] of rooms) out[r] = m.size;
      return out;
    },
    async stop() { server.stop(true); },
  };
}

function hashStr(s: string): number {
  let h = 0;
  for (let i = 0; i < s.length; i++) h = (h * 31 + s.charCodeAt(i)) | 0;
  return h;
}

// ── client transport ────────────────────────────────────────────────────────────

/** Minimal WebSocket surface (browser/Bun global, or `ws`, or a test double). */
export interface WebSocketLike {
  binaryType: string;
  send(data: Uint8Array): void;
  close(): void;
  onopen: ((ev?: unknown) => void) | null;
  onclose: ((ev?: unknown) => void) | null;
  onerror: ((ev?: unknown) => void) | null;
  onmessage: ((ev: { data: unknown }) => void) | null;
}
export type WssFactory = (url: string) => WebSocketLike;

export interface WssSwarmTransportOptions {
  /** Relay base URL, e.g. "ws://localhost:8431". */
  url: string;
  /** Swarm group / room (e.g. multicastGroupForInfohash(infohash).group). */
  room: string;
  /** This peer's id (its transport address). Random if omitted. */
  id?: string;
  /** WebSocket constructor. Defaults to the global WebSocket. */
  factory?: WssFactory;
}

function randomId(): string {
  return 'peer-' + Buffer.from(crypto.getRandomValues(new Uint8Array(6))).toString('hex');
}

/** A SwarmTransport over a WSS relay room. */
export function wssSwarmTransport(opts: WssSwarmTransportOptions): SwarmTransport {
  const id = opts.id ?? randomId();
  const handlers: FrameHandler[] = [];
  const makeWs: WssFactory = opts.factory ?? ((u) => new (globalThis as any).WebSocket(u) as WebSocketLike);
  let ws: WebSocketLike | null = null;
  let ready: Promise<void> | null = null;

  const connectUrl = `${opts.url}?room=${encodeURIComponent(opts.room)}&id=${encodeURIComponent(id)}`;

  return {
    localAddress: () => id,

    async start() {
      if (ready) return ready;
      ready = new Promise<void>((resolve, reject) => {
        const sock = makeWs(connectUrl);
        sock.binaryType = 'arraybuffer';
        sock.onopen = () => resolve();
        sock.onerror = (e) => reject(new Error(`wss relay connect failed: ${String(e)}`));
        sock.onmessage = (ev) => {
          const bytes = toU8(ev.data);
          if (!bytes) return;
          const msg = decodeRelayMsg(bytes);
          if (!msg) return;
          for (const h of handlers) h(msg.frame, msg.from);
        };
        ws = sock;
      });
      return ready;
    },

    async stop() {
      handlers.length = 0;
      ws?.close();
      ws = null;
      ready = null;
    },

    async broadcast(frame) {
      await ready;
      ws?.send(encodeClientMsg(0, '', frame));
    },

    async sendTo(address, frame) {
      await ready;
      ws?.send(encodeClientMsg(1, address, frame));
    },

    onFrame(handler) {
      handlers.push(handler);
    },
  };
}

```
