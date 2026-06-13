---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/jambox/web/src/core/beam-clock.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.609208+00:00
---

# cartridges/jambox/web/src/core/beam-clock.ts

```ts
/**
 * BEAMClock — NTP-style clock sync against the CellRelay BEAM server.
 *
 * Protocol (all JSON over the existing WS connection):
 *
 *   client → server   { type: "clock_ping",  seq: N,  client_time: T1 }
 *   server → client   { type: "clock_pong",  seq: N,  client_time: T1, server_time: T2 }
 *
 * From a round of N pings the client computes:
 *   rtt_i    = T3_i - T1_i          (pure local clock — accurate)
 *   offset_i = T2_i - T1_i - rtt_i/2   (server_time relative to local mid-point)
 *
 * Outlier rejection: drop samples with rtt > 1.5× median rtt, then
 * average the remaining offsets.  This mirrors the NTP filtering algorithm.
 *
 * Beat messages from the server:
 *   { type: "beat", bpm, beat, bar, beats_per_bar, server_time }
 *
 * The clock converts server_time to local-equivalent time and schedules
 * the beat callback precisely, accounting for transit latency and nudge.
 *
 * Usage:
 *   const clock = new BEAMClock(ws)
 *   await clock.sync()          // 8 round trips, ~400 ms on LAN
 *   clock.onBeat = (b) => ...   // fires on each incoming beat
 *   clock.setNudge(+10)         // push beat perception +10 ms
 */

import type { JamClockTick } from '../semantic/events';

export interface BeatInfo {
  beat: number
  bar: number
  bpm: number
  beatsPerBar: number
  /** local time when this beat logically landed (corrected for latency + nudge) */
  localTime: number
}

export interface ClockCalibration {
  rttMs: number
  offsetMs: number
  nudgeMs: number
  /** offsetMs + nudgeMs — apply this to convert server_time to local */
  totalOffsetMs: number
  sampledAt: string
}

interface PingSample {
  rtt: number
  /** server_time - local_midpoint: positive → server clock ahead of local */
  offset: number
}

export class BEAMClock {
  onBeat?: (info: BeatInfo) => void
  /**
   * Phase A (D-A.4): Canonical jam.clock.tick event emitted on every beat.
   * Additive — existing onBeat callback continues to work unchanged.
   */
  onClockTick?: (event: JamClockTick) => void

  private seq = 0
  private pending = new Map<number, { t1: number; resolve: () => void }>()
  private samples: PingSample[] = []
  /** server_time ≈ local_time + offsetMs */
  private offsetMs = 0
  private rttMs = 0
  private nudgeMs = 0
  private lastBeat: BeatInfo | null = null

  constructor(private sendRaw: (msg: unknown) => void) {}

  /**
   * Run `rounds` ping-pong exchanges and compute the stable offset.
   * Resolves when sync is complete. Call once after the WS opens.
   */
  async sync(rounds = 8): Promise<void> {
    this.samples = []
    for (let i = 0; i < rounds; i++) {
      await this.ping()
      // Brief gap so bursted pings don't all share the same queued path.
      await sleep(20)
    }
    this.computeOffset()
  }

  /**
   * Handle a message from the WS. Call this from the jam-room message
   * dispatcher for all incoming messages.
   */
  handleMessage(msg: Record<string, unknown>): boolean {
    if (msg.type === "clock_pong") {
      this.handlePong(msg as unknown as ClockPong)
      return true
    }
    if (msg.type === "beat") {
      this.handleBeat(msg as unknown as BeatMsg)
      return true
    }
    return false
  }

  /** Adjust the perceived beat timing by ±N ms (positive = push beat later). */
  setNudge(ms: number) {
    this.nudgeMs = ms
  }

  getNudge(): number {
    return this.nudgeMs
  }

  /**
   * Convert a server timestamp (ms since epoch) to the equivalent local
   * time, accounting for measured offset, one-way latency, and nudge.
   */
  serverToLocal(serverMs: number): number {
    // offset: server ≈ local + offsetMs  →  local ≈ server - offsetMs
    // transit: beat was broadcast rttMs/2 ago, so logical fire time is earlier
    return serverMs - this.offsetMs - this.rttMs / 2 + this.nudgeMs
  }

  /** Export the current calibration (save as a semantic object). */
  calibration(): ClockCalibration {
    return {
      rttMs: Math.round(this.rttMs),
      offsetMs: Math.round(this.offsetMs),
      nudgeMs: Math.round(this.nudgeMs),
      totalOffsetMs: Math.round(this.offsetMs - this.nudgeMs),
      sampledAt: new Date().toISOString(),
    }
  }

  /** Apply a previously exported calibration without running sync. */
  applySavedCalibration(cal: ClockCalibration) {
    this.offsetMs = cal.offsetMs
    this.rttMs = cal.rttMs
    this.nudgeMs = cal.nudgeMs
  }

  get lastBeatInfo(): BeatInfo | null {
    return this.lastBeat
  }

  // ── private ────────────────────────────────────────────────────────────────

  private ping(): Promise<void> {
    return new Promise((resolve) => {
      const seq = this.seq++
      const t1 = Date.now()
      this.pending.set(seq, { t1, resolve })
      this.sendRaw({ type: "clock_ping", seq, client_time: t1 })
    })
  }

  private handlePong(msg: ClockPong) {
    const t3 = Date.now()
    const entry = this.pending.get(msg.seq)
    if (!entry) return
    this.pending.delete(msg.seq)

    const rtt = t3 - entry.t1
    // offset = server_time - local_midpoint
    const offset = msg.server_time - (entry.t1 + rtt / 2)
    this.samples.push({ rtt, offset })
    entry.resolve()
  }

  private handleBeat(msg: BeatMsg) {
    const localTime = this.serverToLocal(msg.server_time)
    const info: BeatInfo = {
      beat: msg.beat,
      bar: msg.bar,
      bpm: msg.bpm,
      beatsPerBar: msg.beats_per_bar,
      localTime,
    }
    this.lastBeat = info
    this.onBeat?.(info)
    // Phase A (D-A.4): emit canonical jam.clock.tick event alongside onBeat.
    this.onClockTick?.({
      family: 'jam.clock.tick',
      roomTime: localTime,
      beat: msg.beat,
      bar: msg.bar,
      bpm: msg.bpm,
    })
  }

  private computeOffset() {
    if (this.samples.length === 0) return

    const rtts = this.samples.map((s) => s.rtt).sort((a, b) => a - b)
    const medianRtt = rtts[Math.floor(rtts.length / 2)]
    const threshold = medianRtt * 1.5

    const good = this.samples.filter((s) => s.rtt <= threshold)
    if (good.length === 0) return

    this.rttMs = good.reduce((acc, s) => acc + s.rtt, 0) / good.length
    this.offsetMs = good.reduce((acc, s) => acc + s.offset, 0) / good.length
  }
}

// ── wire types ────────────────────────────────────────────────────────────────

interface ClockPong {
  type: "clock_pong"
  seq: number
  client_time: number
  server_time: number
}

interface BeatMsg {
  type: "beat"
  bpm: number
  beat: number
  bar: number
  beats_per_bar: number
  server_time: number
}

function sleep(ms: number) {
  return new Promise<void>((r) => setTimeout(r, ms))
}

```
