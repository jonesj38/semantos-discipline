---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/jambox/web/src/svelte/lib/phoenix-sync.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.622614+00:00
---

# cartridges/jambox/web/src/svelte/lib/phoenix-sync.ts

```ts
/**
 * PhoenixSync — Phoenix channel client for the jam-room world connection.
 *
 * Replaces the bespoke TypeScript JamSync/RelayClient for durable cell state.
 * Connects to `WorldHostWeb.JamSocket` at `/jam/websocket` and joins the
 * `jam:<room_id>` channel.
 *
 * Responsibilities:
 *  • Open the Phoenix WebSocket and join the jam channel.
 *  • Push committed cells (drum patterns, BPM) to the durable NATS-backed store.
 *  • Receive cell snapshots on join (late-join replay from JetStream).
 *  • Receive remote triggers (live drum steps, notes) from peers.
 *  • Fire onBeat from the server clock (BEAMClock via Phoenix messages).
 *  • Track presence (peers in the channel).
 *
 * Usage (App.svelte):
 *   const sync = new PhoenixSync(worldUrl, roomId, handle, callbacks);
 *   sync.connect();
 *   sync.sendTrigger('kick', 0.9);
 *   sync.commitCell(cell);
 *   sync.disconnect();
 */

import { Socket, Channel } from 'phoenix';

export interface BeatInfo {
  beat: number;
  bpm: number;
  server_time: number;
}

export interface PeerInfo {
  id: string;
  name: string;
  role: string;
  color: string;
  drift: number;
  rack: string;
}

export interface PhoenixSyncCallbacks {
  onStatus(s: 'connecting' | 'open' | 'closed' | 'error'): void;
  onBeat(info: BeatInfo): void;
  onRemoteTrigger(track: string, vel: number): void;
  onRemoteNote?(pitch: number, vel: number, duration: number, mode: string): void;
  onPresence(peers: PeerInfo[]): void;
  onSnapshot?(cells: unknown[]): void;
}

const PEER_COLORS = [
  '#65d6f5', '#82e2a8', '#c466ff', '#e28a4a',
  '#f47eb2', '#7ec8e3', '#f1c876',
];

export class PhoenixSync {
  private socket: InstanceType<typeof Socket> | null = null;
  private channel: InstanceType<typeof Channel> | null = null;
  private peers = new Map<string, PeerInfo>();

  constructor(
    private readonly roomId: string,
    private readonly handle: string,
    private readonly cb: PhoenixSyncCallbacks,
  ) {}

  connect(): void {
    if (this.socket) return;

    const socketUrl = this.resolveSocketUrl();
    this.cb.onStatus('connecting');

    this.socket = new Socket(socketUrl, {
      params: { handle: this.handle },
    });

    this.socket.onOpen(() => this.cb.onStatus('open'));
    this.socket.onClose(() => this.cb.onStatus('closed'));
    this.socket.onError(() => this.cb.onStatus('error'));

    this.socket.connect();

    this.channel = this.socket.channel(`jam:${this.roomId}`, {});

    this.channel.on('cell', (_payload: unknown) => {
      // Durable cell committed by a peer — App.svelte can watch onSnapshot
      // for pattern merges; individual cells are handled separately.
    });

    this.channel.on('snapshot', ({ cells }: { cells: unknown[] }) => {
      this.cb.onSnapshot?.(cells);
    });

    this.channel.on('trigger', ({ track, vel, from }: { track: string; vel: number; from: string }) => {
      if (from === this.handle) return;

      if (track === 'melody' || track === 'bass') {
        // Note triggers have pitch/duration embedded
        const raw = arguments[0] as Record<string, unknown>;
        const pitch    = typeof raw['pitch']    === 'number' ? raw['pitch']    : 60;
        const duration = typeof raw['duration'] === 'number' ? raw['duration'] : 0.4;
        this.cb.onRemoteNote?.(pitch, vel, duration, track);
      } else {
        this.cb.onRemoteTrigger(track, vel);
      }
    });

    this.channel.on('bpm', ({ bpm }: { bpm: number }) => {
      // Synthesise a BeatInfo so BEAMClock-style callers work
      this.cb.onBeat({ beat: 0, bpm, server_time: Date.now() });
    });

    // BEAMClock NTP — Phoenix channel carries the ping/pong
    this.channel.on('clock_pong', (msg: Record<string, unknown>) => {
      this._handleClockPong(msg);
    });

    // Presence — Phoenix tracks joins/leaves server-side
    this.channel.on('presence_state', (state: Record<string, unknown>) => {
      this._syncPresence(state);
    });

    this.channel.on('presence_diff', ({ joins, leaves }: { joins: Record<string, unknown>; leaves: Record<string, unknown> }) => {
      this._applyPresenceDiff(joins, leaves);
    });

    this.channel
      .join()
      .receive('ok', () => {
        this._startClockSync();
      })
      .receive('error', (err: unknown) => {
        console.warn('[PhoenixSync] channel join failed', err);
        this.cb.onStatus('error');
      });
  }

  /** Push a committed cell (drum pattern, settings) to NATS-backed store. */
  commitCell(cell: Record<string, unknown>): void {
    this.channel?.push('commit', { cell });
  }

  /** Broadcast an ephemeral live trigger to peers (not persisted). */
  sendTrigger(track: string, vel: number): void {
    this.channel?.push('trigger', { track, vel, from: this.handle });
  }

  /** Broadcast a note trigger (melody/bass). */
  sendNote(pitch: number, vel: number, duration: number, mode: string): void {
    this.channel?.push('trigger', { track: mode, vel, pitch, duration, from: this.handle });
  }

  /** Tell the server to update the room BPM (starts/updates CellRelay.Clock). */
  sendBpm(bpm: number): void {
    this.channel?.push('set_bpm', { bpm: Math.round(bpm) });
  }

  disconnect(): void {
    this.channel?.leave();
    this.socket?.disconnect();
    this.socket = null;
    this.channel = null;
    this.peers.clear();
  }

  // ── Clock sync ────────────────────────────────────────────────────────────

  private _clockOffset = 0;
  private _startClockSync(): void {
    const ping = () => {
      const cs = Date.now();
      this.channel?.push('clock_ping', { client_send: cs })
        .receive('ok', () => {});
    };
    // 8 rounds at 500ms intervals (mirrors BEAMClock NTP)
    let n = 0;
    const id = setInterval(() => {
      ping();
      if (++n >= 8) clearInterval(id);
    }, 500);
  }

  private _handleClockPong(msg: Record<string, unknown>): void {
    const now       = Date.now();
    const cs        = msg['client_send']  as number;
    const sr        = msg['server_recv']  as number;
    const ss        = msg['server_send']  as number;
    const rtt       = now - cs;
    this._clockOffset = ((sr - cs) + (ss - now)) / 2;
    // Synthesise a beat from server_time + offset (rough; full BEAM clock omitted for now)
    void rtt;
    void this._clockOffset;
  }

  // ── Presence ──────────────────────────────────────────────────────────────

  private _syncPresence(state: Record<string, unknown>): void {
    this.peers.clear();
    Object.entries(state).forEach(([id, info], idx) => {
      const metas  = (info as { metas?: Array<{ handle?: string }> }).metas ?? [];
      const handle = metas[0]?.handle ?? id.slice(0, 8);
      const isMe   = handle === this.handle;
      this.peers.set(id, {
        id,
        name:  isMe ? 'you' : handle,
        role:  isMe ? 'host' : 'guest',
        color: isMe ? '#d4a655' : (PEER_COLORS[idx % PEER_COLORS.length] ?? '#888'),
        drift: 0,
        rack:  '—',
      });
    });
    this.cb.onPresence(Array.from(this.peers.values()));
  }

  private _applyPresenceDiff(
    joins: Record<string, unknown>,
    leaves: Record<string, unknown>,
  ): void {
    const baseIdx = this.peers.size;
    Object.entries(joins).forEach(([id, info], i) => {
      const metas  = (info as { metas?: Array<{ handle?: string }> }).metas ?? [];
      const handle = metas[0]?.handle ?? id.slice(0, 8);
      const isMe   = handle === this.handle;
      this.peers.set(id, {
        id,
        name:  isMe ? 'you' : handle,
        role:  isMe ? 'host' : 'guest',
        color: isMe ? '#d4a655' : (PEER_COLORS[(baseIdx + i) % PEER_COLORS.length] ?? '#888'),
        drift: 0,
        rack:  '—',
      });
    });
    Object.keys(leaves).forEach((id) => this.peers.delete(id));
    this.cb.onPresence(Array.from(this.peers.values()));
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  private resolveSocketUrl(): string {
    // VITE_WORLD_URL can be set at build time (e.g. wss://world.semantos.me)
    // Vite replaces import.meta.env at build time; cast via unknown for TS strict mode
    const meta = import.meta as unknown as { env?: Record<string, string> };
    const envUrl = meta.env?.['VITE_WORLD_URL'];
    if (envUrl) return `${envUrl}/jam/websocket`;

    // Local dev: world_host runs on port 4000
    const proto = location.protocol === 'https:' ? 'wss:' : 'ws:';
    return `${proto}//${location.hostname}:4000/jam/websocket`;
  }
}

```
