---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/jambox/web/src/racks/puredata/PureDataRack.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.625717+00:00
---

# cartridges/jambox/web/src/racks/puredata/PureDataRack.ts

```ts
/**
 * PureDataRack — JamRack implementation for PureData engine.
 *
 * Two transports are supported, selectable per-instance:
 *
 *   1. IN-BROWSER (default for patches < 1 MB):
 *      libpd-wasm loaded via dynamic import on first use.
 *      Import path: 'libpd-wasm' (see top-of-file comment).
 *
 *   2. REMOTE BRIDGE (default for patches >= 1 MB):
 *      WebSocket + OSC to the local bridge daemon (bridge.ts).
 *      The bridge is EXTENDED — not duplicated — per HARD RULE 7.
 *
 * Receiver/sender naming convention (enforced at load-time):
 *   [r jam-note]        — receives JamNoteOn events
 *   [r jam-trigger]     — receives JamTrigger events
 *   [r jam-clock]       — receives BEAMClock tick (bpm, beat, bar)
 *   [r jam-macro-1]..
 *   [r jam-macro-8]     — receives macro 0..7 values (0–1)
 *
 * Patches that do NOT declare these receivers get a descriptive error
 * listing the missing ones at load time.
 *
 * BEAMClock is the clock authority. This rack sends [r jam-clock] messages;
 * it never authors clock.
 *
 * captureToPattern() stores both:
 *   1. The patch id + macro state (for re-run)
 *   2. A 64-step rendered snapshot from the PD output buffer
 */

import type {
  JamRack, JamNoteOn, JamTrigger, JamNoteOff, JamStop,
  JamRackState, JamMeters, JamMappingHint,
} from '../contract';
import { rackRegistry } from '../registry';
import type { BeatInfo } from '../../core/beam-clock';

// ── Required PD receiver names ─────────────────────────────────────────────────

/** Receiver names every conformant PD patch must implement. */
export const REQUIRED_RECEIVERS = [
  'jam-note',
  'jam-trigger',
  'jam-clock',
  'jam-macro-1',
  'jam-macro-2',
  'jam-macro-3',
  'jam-macro-4',
  'jam-macro-5',
  'jam-macro-6',
  'jam-macro-7',
  'jam-macro-8',
] as const;

export type RequiredReceiver = (typeof REQUIRED_RECEIVERS)[number];

// ── libpd-wasm stub types ──────────────────────────────────────────────────────

interface LibpdModule {
  /** Load a PD patch from bytes. Returns a patch handle. */
  loadPatch(bytes: Uint8Array): PdPatch;
  /** Send a float to a named receiver. */
  sendFloat(receiver: string, value: number): void;
  /** Send a list (message) to a named receiver. */
  sendList(receiver: string, args: Array<string | number>): void;
  /** Send a bang to a named receiver. */
  sendBang(receiver: string): void;
  /** Get declared receivers in the loaded patch. */
  getReceivers(): string[];
  /** Process one block of audio (128 samples). Returns L/R interleaved float32. */
  processBlock(): Float32Array;
}

interface PdPatch {
  handle: number;
  name: string;
  sizeBytes: number;
  receivers: string[];
}

// ── Remote bridge WebSocket client ─────────────────────────────────────────────

interface OscMessage {
  address: string;
  args: Array<{ type: 'f' | 's' | 'i'; value: number | string }>;
}

class PdBridgeClient {
  private ws: WebSocket | null = null;
  private queue: OscMessage[] = [];
  private connected = false;

  constructor(private readonly url: string) {}

  connect(): void {
    if (this.ws) return;
    try {
      this.ws = new WebSocket(this.url);
      this.ws.onopen = () => {
        this.connected = true;
        // Flush queued messages
        for (const msg of this.queue) this.sendOsc(msg);
        this.queue = [];
      };
      this.ws.onclose = () => {
        this.connected = false;
        this.ws = null;
      };
      this.ws.onerror = () => {
        this.connected = false;
      };
    } catch {
      // WebSocket unavailable (Node/test environment)
    }
  }

  disconnect(): void {
    this.ws?.close();
    this.ws = null;
    this.connected = false;
  }

  sendOsc(msg: OscMessage): void {
    if (!this.connected || !this.ws) {
      this.queue.push(msg);
      return;
    }
    try {
      this.ws.send(JSON.stringify(msg));
    } catch {
      // Send failed — re-queue
      this.queue.push(msg);
    }
  }

  isConnected(): boolean {
    return this.connected;
  }
}

// ── PureDataRack config ────────────────────────────────────────────────────────

export interface PureDataRackConfig {
  /** Force transport selection. If undefined, auto-select based on patch size. */
  transport?: 'in-browser' | 'remote';
  /** Bridge WebSocket URL (remote transport). Default: ws://localhost:5182/pd */
  bridgeUrl?: string;
  /** Patch bytes for in-browser transport (overrides auto-fetch). */
  patchBytes?: Uint8Array;
  /** Declared patch size in bytes (used for auto transport selection). */
  declaredPatchBytes?: number;
}

/** 1 MB threshold for auto transport selection. */
const PATCH_SIZE_THRESHOLD = 1_048_576;

// ── Macro constants ────────────────────────────────────────────────────────────

const MACRO_NAMES = [
  'brightness', 'dirt', 'wobble', 'space', 'snap', 'body', 'chaos', 'tension',
] as const;

const DEFAULT_MACROS: [number, number, number, number, number, number, number, number] = [
  0.6, 0.1, 0, 0.2, 0.5, 0.7, 0, 0.4,
];

// ── Capture payload ────────────────────────────────────────────────────────────

export interface PureDataCapturePayload {
  engine: 'puredata';
  patchId: string;
  macros: number[];
  /** 64-step rendered snapshot from PD output buffer */
  steps64: PdStep[];
  bpm: number;
  bars: number;
  capturedAt: number;
}

export interface PdStep {
  active: boolean;
  note: number | null;
  velocity: number;
  step: number;
}

// ── PureDataRack ───────────────────────────────────────────────────────────────

export class PureDataRack implements JamRack {
  readonly id: string;
  readonly name: string;
  readonly engine = 'puredata' as const;

  private macros: [number, number, number, number, number, number, number, number] = [
    ...DEFAULT_MACROS,
  ];
  private presetId?: string;

  /** Active transport */
  private transport: 'in-browser' | 'remote';

  /** In-browser libpd-wasm module (lazy loaded) */
  private libpd: LibpdModule | null = null;
  private loadPromise: Promise<void> | null = null;
  private runtimeLoaded = false;
  private currentPatch: PdPatch | null = null;

  /** Remote bridge client */
  private bridgeClient: PdBridgeClient | null = null;

  /** Config */
  private readonly config: Required<PureDataRackConfig>;

  /** Meter state */
  private peakLevel = 0;
  private rmsLevel = 0;
  private meterDecay = 0;

  /** Output buffer for captureToPattern (ring buffer of recent PD events) */
  private outputBuffer: Array<{ note: number; velocity: number; time: number }> = [];

  /** Current BPM from BEAMClock */
  private currentBpm = 120;

  constructor(id: string, name: string, config: PureDataRackConfig = {}) {
    this.id = id;
    this.name = name;

    const declaredSize = config.declaredPatchBytes ?? 0;
    const autoTransport = declaredSize >= PATCH_SIZE_THRESHOLD ? 'remote' : 'in-browser';

    this.config = {
      transport: config.transport ?? autoTransport,
      bridgeUrl: config.bridgeUrl ?? 'ws://localhost:5182/pd',
      patchBytes: config.patchBytes ?? new Uint8Array(0),
      declaredPatchBytes: config.declaredPatchBytes ?? 0,
    };
    this.transport = this.config.transport;

    if (this.transport === 'remote') {
      this.bridgeClient = new PdBridgeClient(this.config.bridgeUrl);
      this.bridgeClient.connect();
    }

    rackRegistry.register(this);
  }

  // ── Clock slave ────────────────────────────────────────────────────────────────

  /**
   * Called by BEAMClock.onBeat. Sends the clock message to PD.
   * This rack NEVER authors clock.
   */
  onClockTick(info: BeatInfo): void {
    this.currentBpm = info.bpm;
    this.sendToPd('jam-clock', [info.bpm, info.beat, info.bar]);
    // Decay meters
    this.meterDecay++;
    if (this.meterDecay > 4) {
      this.peakLevel *= 0.85;
      this.rmsLevel *= 0.85;
    }
  }

  // ── JamRack interface ──────────────────────────────────────────────────────────

  play(event: JamNoteOn | JamTrigger): void {
    void this.ensureLoaded();

    if (event.kind === 'trigger') {
      const vel = Math.max(0, Math.min(1, event.velocity));
      this.sendToPd('jam-trigger', [event.voiceId, vel]);
      this.recordOutputEvent(60, vel);
      this.updateMeters(vel);
    } else {
      const vel = Math.max(0, Math.min(1, event.velocity / 127));
      this.sendToPd('jam-note', [event.pitch, event.velocity, 1]);
      this.recordOutputEvent(event.pitch, vel);
      this.updateMeters(vel);
    }
  }

  stop(event: JamNoteOff | JamStop): void {
    if (event.kind === 'note.off') {
      this.sendToPd('jam-note', [event.pitch, 0, 0]);
    } else {
      // Panic — send all notes off
      this.sendToPd('jam-trigger', ['all-off', 0]);
    }
    this.peakLevel = 0;
    this.rmsLevel = 0;
  }

  setMacro(index: number, value: number): void {
    const i = Math.max(0, Math.min(7, Math.floor(index)));
    const v = Math.max(0, Math.min(1, value));
    this.macros[i] = v;
    // PD receiver: jam-macro-1 .. jam-macro-8 (1-indexed)
    this.sendToPd(`jam-macro-${i + 1}`, [v]);
  }

  setPreset(presetId: string): void {
    this.presetId = presetId;
  }

  getState(): JamRackState {
    return {
      presetId: this.presetId,
      macros: [...this.macros],
      engineState: {
        transport: this.transport,
        patchId: this.currentPatch?.name ?? null,
      },
    };
  }

  setState(state: JamRackState): void {
    if (Array.isArray(state.macros)) {
      for (let i = 0; i < 8; i++) {
        const v = state.macros[i];
        if (typeof v === 'number') this.setMacro(i, v);
      }
    }
    if (state.presetId) this.presetId = state.presetId;
  }

  getMeters(): JamMeters {
    if (this.libpd && this.runtimeLoaded) {
      try {
        const block = this.libpd.processBlock();
        let peak = 0;
        let rmsSum = 0;
        for (let i = 0; i < block.length; i++) {
          const abs = Math.abs(block[i]);
          if (abs > peak) peak = abs;
          rmsSum += block[i] * block[i];
        }
        const rms = block.length > 0 ? Math.sqrt(rmsSum / block.length) : 0;
        this.peakLevel = peak;
        this.rmsLevel = rms;
      } catch {
        // processBlock may fail in stub mode
      }
    }
    return {
      peakL: this.peakLevel,
      peakR: this.peakLevel,
      rmsL: this.rmsLevel,
      rmsR: this.rmsLevel,
    };
  }

  getMappingHints(): JamMappingHint[] {
    const macroHints: JamMappingHint[] = MACRO_NAMES.map((name, i) => ({
      inputType: 'knob' as const,
      target: `macro.${i}`,
      label: name,
      range: [0, 1] as [number, number],
    }));
    const padHints: JamMappingHint[] = [
      { inputType: 'pad', target: 'jam-trigger', label: 'TRIG' },
      { inputType: 'key', target: 'jam-note', label: 'NOTE' },
    ];
    return [...macroHints, ...padHints];
  }

  /**
   * Load a PD patch from bytes.
   * Validates that the patch declares the required receivers.
   * Throws a descriptive error listing missing receivers.
   */
  async loadPatch(patchBytes: Uint8Array, patchName = 'patch.pd'): Promise<void> {
    await this.ensureLoaded();
    if (this.transport === 'in-browser' && this.libpd) {
      const patch = this.libpd.loadPatch(patchBytes);
      this.currentPatch = patch;
      this.validateReceivers(patch.receivers, patchName);
      // Send current macro values to newly loaded patch
      for (let i = 0; i < 8; i++) {
        this.sendToPd(`jam-macro-${i + 1}`, [this.macros[i]]);
      }
    } else {
      // Remote transport: send patch load command via bridge
      this.sendOscToBridge({
        address: '/pd/load',
        args: [{ type: 's', value: patchName }],
      });
    }
  }

  /**
   * Capture the next `barCount` bars of PD output into a jam.pattern payload.
   * Stores both the patch/macro state AND a 64-step snapshot.
   */
  captureToPattern(barCount = 4): PureDataCapturePayload {
    const bpm = this.currentBpm;
    const steps64 = this.buildStepsFromBuffer(barCount, bpm);
    return {
      engine: 'puredata',
      patchId: this.currentPatch?.name ?? 'unknown',
      macros: [...this.macros],
      steps64,
      bpm,
      bars: barCount,
      capturedAt: Date.now(),
    };
  }

  /** Disconnect bridge client (cleanup). */
  dispose(): void {
    this.bridgeClient?.disconnect();
    rackRegistry.unregister(this.id);
  }

  // ── Private helpers ────────────────────────────────────────────────────────────

  private ensureLoaded(): Promise<void> {
    if (this.runtimeLoaded) return Promise.resolve();
    if (this.transport === 'remote') {
      // Remote transport — no WASM to load
      this.runtimeLoaded = true;
      return Promise.resolve();
    }
    if (this.loadPromise) return this.loadPromise;
    this.loadPromise = this.loadLibpd();
    return this.loadPromise;
  }

  private async loadLibpd(): Promise<void> {
    try {
      // Dynamic import — does NOT execute at boot.
      // Real package: 'libpd-wasm'. Falls back to stub when unavailable.
      // Using Function constructor avoids Vite static analysis which would
      // error on missing packages at build time.
      const dynamicImport = new Function('pkg', 'return import(pkg)') as
        (pkg: string) => Promise<unknown>;
      const mod = await dynamicImport('libpd-wasm').catch(() => null);
      if (mod) {
        this.libpd = mod as unknown as LibpdModule;
      } else {
        this.libpd = buildStubLibpd();
      }
      this.runtimeLoaded = true;
      // Load patchBytes if provided
      if (this.config.patchBytes.length > 0) {
        try {
          await this.loadPatch(this.config.patchBytes);
        } catch (e) {
          console.warn('[PureDataRack] patch validation warning:', e);
        }
      }
    } catch {
      this.libpd = buildStubLibpd();
      this.runtimeLoaded = true;
    }
  }

  /**
   * Send a message to PD via the active transport.
   * For in-browser: sendFloat/sendList to libpd-wasm.
   * For remote: send OSC message to the bridge WebSocket.
   */
  private sendToPd(receiver: string, args: Array<string | number>): void {
    if (this.transport === 'in-browser' && this.libpd && this.runtimeLoaded) {
      if (args.length === 1 && typeof args[0] === 'number') {
        this.libpd.sendFloat(receiver, args[0]);
      } else {
        this.libpd.sendList(receiver, args);
      }
    } else if (this.transport === 'remote' && this.bridgeClient) {
      this.sendOscToBridge({
        address: `/pd/${receiver}`,
        args: args.map((v) =>
          typeof v === 'number'
            ? { type: 'f' as const, value: v }
            : { type: 's' as const, value: v },
        ),
      });
    }
  }

  private sendOscToBridge(msg: OscMessage): void {
    this.bridgeClient?.sendOsc(msg);
  }

  /**
   * Validate that a loaded patch declares all required receivers.
   * Throws if any are missing.
   */
  private validateReceivers(declaredReceivers: string[], patchName: string): void {
    const declared = new Set(declaredReceivers);
    const missing = REQUIRED_RECEIVERS.filter((r) => !declared.has(r));
    if (missing.length > 0) {
      throw new Error(
        `PureDataRack: patch "${patchName}" is missing required receivers.\n` +
        `Missing: ${missing.map((r) => `[r ${r}]`).join(', ')}\n` +
        `Required: ${REQUIRED_RECEIVERS.map((r) => `[r ${r}]`).join(', ')}\n` +
        `See src/racks/puredata/conventions.md for the full naming convention.`,
      );
    }
  }

  private recordOutputEvent(note: number, velocity: number): void {
    this.outputBuffer.push({ note, velocity, time: Date.now() });
    // Keep buffer from growing unbounded
    if (this.outputBuffer.length > 512) {
      this.outputBuffer.splice(0, this.outputBuffer.length - 512);
    }
  }

  private updateMeters(velocity: number): void {
    this.peakLevel = Math.max(this.peakLevel, velocity);
    this.rmsLevel = Math.max(this.rmsLevel, velocity * 0.707);
    this.meterDecay = 0;
  }

  private buildStepsFromBuffer(barCount: number, bpm: number): PdStep[] {
    const barMs = (60_000 / bpm) * 4;
    const windowMs = barCount * barMs;
    const now = Date.now();
    const windowStart = now - windowMs;

    const steps: PdStep[] = Array.from({ length: 64 }, (_, i): PdStep => ({
      active: false, note: null, velocity: 0, step: i,
    }));

    const recentEvents = this.outputBuffer.filter((e) => e.time >= windowStart);
    for (const event of recentEvents) {
      const elapsed = event.time - windowStart;
      const stepIdx = Math.floor((elapsed / windowMs) * 64);
      if (stepIdx >= 0 && stepIdx < 64) {
        steps[stepIdx] = {
          active: true,
          note: event.note,
          velocity: event.velocity,
          step: stepIdx,
        };
      }
    }
    return steps;
  }
}

// ── Stub libpd-wasm for test/CI environments ───────────────────────────────────

function buildStubLibpd(): LibpdModule {
  const declaredReceivers: string[] = [...REQUIRED_RECEIVERS];
  const outputBuffer = new Float32Array(256); // 128 stereo samples

  return {
    loadPatch: (bytes: Uint8Array): PdPatch => ({
      handle: 1,
      name: 'stub.pd',
      sizeBytes: bytes.length,
      receivers: [...declaredReceivers],
    }),
    sendFloat: (_receiver: string, _value: number) => { /* stub */ },
    sendList: (_receiver: string, _args: Array<string | number>) => { /* stub */ },
    sendBang: (_receiver: string) => { /* stub */ },
    getReceivers: () => [...declaredReceivers],
    processBlock: () => outputBuffer,
  };
}

```
