---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/rtc/ice.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.040127+00:00
---

# runtime/session-protocol/src/rtc/ice.ts

```ts
/**
 * rtc.ice — S2 ICE / transport configuration (RTC matrix row S2).
 *
 * STUN reflexive-candidate discovery + TURN relay fallback config. ICE itself
 * is performed by the WebRTC runtime (browser-native or werift in node/bun);
 * this module owns the *configuration* surface — which STUN/TURN servers a
 * PeerConnection gathers candidates against — plus the brain-hosted-TURN
 * helper. The roadmap's note: the brain can host coturn for the ~10-20% of
 * peers behind symmetric NAT; once an SFU (S4) is in play its public IP is the
 * rendezvous and obviates separate TURN for group flows.
 *
 * Cross-reference: docs/canon/rtc-matrix.yml row S2, media.ts (the
 * PeerConnection the config drives).
 */

export interface RtcIceServer {
  /** A STUN/TURN URL or list, e.g. `stun:stun.l.google.com:19302` or `turn:host:3478`. */
  urls: string | string[];
  /** TURN long-term-credential username. */
  username?: string;
  /** TURN long-term-credential secret. */
  credential?: string;
}

export interface RtcIceConfig {
  iceServers?: RtcIceServer[];
  /** Gather only relay candidates (force TURN) — for the symmetric-NAT path. */
  iceTransportPolicy?: 'all' | 'relay';
}

/** A public STUN-only default (pure P2P; no relay). Fine for the dev mesh + most home NATs. */
export const DEFAULT_ICE_CONFIG: RtcIceConfig = {
  iceServers: [{ urls: 'stun:stun.l.google.com:19302' }],
};

/**
 * ICE config pointing at a brain-hosted TURN/STUN endpoint (coturn). `secret`
 * is the TURN long-term credential the brain issues per session. Use when peers
 * may be behind symmetric NAT (relay fallback).
 */
export function brainIceConfig(opts: {
  /** TURN host:port, e.g. `brain.example.com:3478`. */
  turnHost: string;
  username: string;
  credential: string;
  /** Also advertise a STUN URL on the same host (default true). */
  stun?: boolean;
}): RtcIceConfig {
  const servers: RtcIceServer[] = [
    { urls: `turn:${opts.turnHost}`, username: opts.username, credential: opts.credential },
  ];
  if (opts.stun ?? true) servers.unshift({ urls: `stun:${opts.turnHost}` });
  return { iceServers: servers };
}

```
