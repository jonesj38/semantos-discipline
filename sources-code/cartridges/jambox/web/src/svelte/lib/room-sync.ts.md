---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/jambox/web/src/svelte/lib/room-sync.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.622262+00:00
---

# cartridges/jambox/web/src/svelte/lib/room-sync.ts

```ts
/**
 * RoomSync — thin wrapper around RelayClient + BEAMClock for use in Svelte.
 *
 * Responsibilities:
 *  • Open (and auto-reconnect) the WebSocket room connection.
 *  • Run BEAMClock NTP sync once the socket opens.
 *  • Fire onBeat when the server emits a beat message (quarter note).
 *  • Relay jam.trigger live payloads to onRemoteTrigger (skipping echoes).
 *  • Expose sendTrigger() so the local sequencer can broadcast each step fire.
 *  • Convert presence identity strings to PeerInfo objects for the PeerRail.
 *
 * Usage (App.svelte):
 *   const roomSync = new RoomSync(roomId, handle, callbacks);
 *   roomSync.connect();   // call once after tap-to-start
 *   roomSync.sendTrigger('kick', 0.9);
 *   roomSync.disconnect();
 */

import { JamSync } from '../../core/sync.js';
import { BEAMClock, type BeatInfo } from '../../core/beam-clock.js';
import type { LiveTrigger } from '../../core/sync.js';

// ── Public peer model (matches PeerRail's Peer interface) ─────────────────────

export interface PeerInfo {
  id: string;
  name: string;
  role: string;
  color: string;
  drift: number;
  rack: string;
}

// Deterministic hue from an arbitrary identity string
function hueFromIdentity(id: string): number {
  let h = 0;
  for (let i = 0; i < id.length; i++) h = (h * 31 + id.charCodeAt(i)) & 0xffff;
  return h % 360;
}

const PEER_COLORS = [
  '#65d6f5', // cyan
  '#82e2a8', // green
  '#c466ff', // purple
  '#e28a4a', // orange
  '#f47eb2', // pink
  '#7ec8e3', // sky
  '#f1c876', // brass-bright
];

function peerColor(identity: string, idx: number): string {
  // Prefer deterministic palette slot over hue to match design system
  return PEER_COLORS[idx % PEER_COLORS.length] ?? `hsl(${hueFromIdentity(identity)} 65% 62%)`;
}

function toPeerInfo(identity: string, idx: number, myIdentity: string): PeerInfo {
  const isMe = identity === myIdentity;
  return {
    id: identity,
    name: isMe ? 'you' : (identity.split(':')[0] ?? identity).slice(0, 8),
    role: isMe ? 'host' : 'guest',
    color: isMe ? '#d4a655' : peerColor(identity, idx),
    drift: 0,   // updated by BEAMClock nudge data when available
    rack: '—',
  };
}

// ── Callbacks ─────────────────────────────────────────────────────────────────

export interface RoomSyncCallbacks {
  onStatus(s: 'connecting' | 'open' | 'closed' | 'error'): void;
  /** Fires on each server beat (quarter note). info.beat is a running counter. */
  onBeat(info: BeatInfo): void;
  /** Fires when a remote player's drum step fires. */
  onRemoteTrigger(track: string, vel: number): void;
  /** Fires when a remote player plays a melody or bass note. */
  onRemoteNote?(pitch: number, vel: number, duration: number, mode: 'melody' | 'bass'): void;
  /** Full peer list whenever presence changes. */
  onPresence(peers: PeerInfo[]): void;
}

// ── RoomSync ──────────────────────────────────────────────────────────────────

export class RoomSync {
  private client: InstanceType<typeof JamSync> | null = null;
  private clock: BEAMClock | null = null;
  private myIdentity = '';
  private presenceList: string[] = [];

  constructor(
    private readonly roomId: string,
    private readonly handle: string,
    private readonly cb: RoomSyncCallbacks,
  ) {}

  connect(): void {
    if (this.client) return; // already connected / connecting

    // VITE_RELAY_URL can be set at build time (e.g. wss://jam.semantos.me).
    // Falls back to same-host:5178 for local dev.
    const relayBase = (import.meta.env?.VITE_RELAY_URL as string | undefined)
      ?? (() => {
           const proto = location.protocol === 'https:' ? 'wss:' : 'ws:';
           return `${proto}//${location.hostname}:5178`;
         })();
    const url = `${relayBase}/?room=${encodeURIComponent(this.roomId)}&as=${encodeURIComponent(this.handle)}`;

    // BEAMClock must be created before the client so sendRaw is available,
    // but we pass a lazy closure so clock is captured after assignment.
    const clock = new BEAMClock((msg) => this.client?.sendRaw(msg));
    clock.onBeat = (info) => this.cb.onBeat(info);
    this.clock = clock;

    this.client = new JamSync(url, {
      onStatus: (s) => {
        this.cb.onStatus(s);
        if (s === 'open') {
          clock.sync().catch(() => { /* clock sync failure is non-fatal */ });
        }
      },

      onSnapshot: (_cells, your, presence) => {
        this.myIdentity = your.identity;
        this.presenceList = presence;
        this.emitPresence();
      },

      onCell: () => { /* pattern cells handled separately if needed */ },

      onPresence: (identities, change) => {
        this.presenceList = identities;
        void change; // joined/left labels available if needed
        this.emitPresence();
      },

      onLive: (payload, from) => {
        if (from.identity === this.myIdentity) return; // don't echo our own

        const raw = payload as unknown as Record<string, unknown>;
        if (raw.kind === 'trigger') {
          const track = String(raw.track ?? 'kick');
          const vel   = typeof raw.vel === 'number' ? raw.vel : 0.8;

          if (track === 'melody' || track === 'bass') {
            // Note trigger — carry pitch and duration
            const pitch    = typeof raw.pitch    === 'number' ? raw.pitch    : 60;
            const duration = typeof raw.duration === 'number' ? raw.duration : 0.4;
            this.cb.onRemoteNote?.(pitch, vel, duration, track);
          } else {
            this.cb.onRemoteTrigger(track, vel);
          }
        }
      },

      onReset: () => {
        // Server requested state reset — reload gracefully
        if (typeof location !== 'undefined') location.reload();
      },

      onRawMessage: (msg) => {
        // Route clock protocol messages (clock_pong, beat) to BEAMClock
        clock.handleMessage(msg as Record<string, unknown>);
      },
    });

    this.client.connect();
  }

  /**
   * Tell the server which BPM this room should clock at.
   * Call once after connect, and again whenever the user changes BPM.
   * This starts CellRelay.Clock which broadcasts beat messages to all peers.
   */
  sendBpm(bpm: number): void {
    this.client?.sendRaw({ type: 'set_bpm', bpm: Math.round(bpm) });
  }

  /**
   * Broadcast a drum trigger to all peers in the room.
   * Call this whenever a step fires locally.
   */
  sendTrigger(track: string, vel: number): void {
    if (!this.client) return;
    const payload: LiveTrigger = { kind: 'trigger', track, vel, semitone: 0 };
    this.client.sendLive(payload);
  }

  /**
   * Broadcast a melody or bass note to all peers.
   * pitch is the absolute MIDI note number; mode is 'melody' | 'bass'.
   * The relay passes live payloads through verbatim, so extra fields are fine.
   */
  sendNote(pitch: number, vel: number, duration: number, mode: 'melody' | 'bass'): void {
    if (!this.client) return;
    // Cast required because LiveTrigger type doesn't carry pitch/duration,
    // but the relay is transparent and peers read these fields directly.
    (this.client.sendLive as (p: unknown) => void)({
      kind: 'trigger', track: mode, vel, pitch, duration,
    });
  }

  disconnect(): void {
    this.client?.disconnect();
    this.client = null;
    this.clock = null;
    this.presenceList = [];
    this.myIdentity = '';
  }

  /** BEAMClock calibration snapshot (for debug display). */
  calibration() {
    return this.clock?.calibration() ?? null;
  }

  // ── private ─────────────────────────────────────────────────────────────────

  private emitPresence(): void {
    const peers = this.presenceList.map((id, i) => toPeerInfo(id, i, this.myIdentity));
    this.cb.onPresence(peers);
  }
}

```
