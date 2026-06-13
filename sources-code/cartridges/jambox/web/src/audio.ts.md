---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/jambox/web/src/audio.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.598598+00:00
---

# cartridges/jambox/web/src/audio.ts

```ts
/**
 * Web Audio engine for the multi-room jam-room.
 *
 *   master gain → master limiter → analyser → destination
 *      ▲ ▲                ▲
 *      │ └── reverb return + delay return (parallel buses)
 *      │      └── delay time tap-settable via setDelayTime()
 *      │
 *      ┌─────────────────────────────────────────────────────────┐
 *      │  per-PEER channel buses                                  │
 *      │   peer X → vuAnalyser → channelGain → master            │
 *      │   self   → vuAnalyser → channelGain → master            │
 *      └─────────────────────────────────────────────────────────┘
 *
 * Per-track FX (filter / reverb / delay / drive / bitcrush) live
 * downstream of each entity bus, so each entity (self or peer) gets
 * independent track-FX shaping. A sidechain duck VCA modulates bass
 * + lead tracks any time the kick fires (toggleable per track).
 */

let ctx: AudioContext | null = null;
let master: GainNode;
let masterCut: GainNode;        // censor gate — multiplied into the chain
let reverbInput: GainNode;
let reverbFb1: GainNode;        // reverb feedback (lifted for freeze)
let reverbFb2: GainNode;
let reverbInputAttenuator: GainNode; // disconnects input on freeze
let delayInput: GainNode;
let masterDelay: DelayNode;     // tap-tempo target
let masterLimiter: DynamicsCompressorNode;
let masterAnalyser: AnalyserNode;
let masterRecordTap: MediaStreamAudioDestinationNode | null = null;
let stereoWiden: GainNode;      // master-bus haas widener pre-master
let started = false;

/** Sidechain duck control signal (0..1, 1 = open, 0 = ducked). */
let sidechainDuck: GainNode;

/** Per-entity audio bus. `entityKey` = 'self' or a peer colour hex. */
interface EntityBus {
  channelGain: GainNode;
  /** Stereo panner inserted before channelGain — the mixer pan knob. */
  pan: StereoPannerNode;
  trackFx: Map<string, TrackFx>;
  trunk: GainNode;
  vuAnalyser: AnalyserNode;
}
interface TrackFx {
  trackBus: GainNode;
  drive: WaveShaperNode;
  bitcrush: WaveShaperNode;
  filter: BiquadFilterNode;
  reverbSend: GainNode;
  delaySend: GainNode;
  /** When true, this track's gain is modulated by the sidechain duck. */
  sidechainEnabled: boolean;
  sidechainGain: GainNode;
}
const entityBuses = new Map<string, EntityBus>();

export async function startAudio(): Promise<void> {
  if (!ctx) {
    const Ctx = (window.AudioContext ?? (window as unknown as {
      webkitAudioContext: typeof AudioContext;
    }).webkitAudioContext);
    ctx = new Ctx();
    master = ctx.createGain();
    master.gain.value = 0.85;

    // Sidechain duck: a constant 1 source modulated by a one-shot
    // envelope on every kick fire. Bass + lead trackFx subscribe to
    // this signal and use it to multiply their own gain.
    sidechainDuck = ctx.createGain();
    sidechainDuck.gain.value = 1;
    // Anchor with a constant-1 source so the gain control behaves
    // like a control-rate signal even with no input feeding it.
    const sc1 = ctx.createConstantSource();
    sc1.offset.value = 1;
    sc1.connect(sidechainDuck);
    sc1.start();

    // Master limiter — hard ceiling.
    masterLimiter = ctx.createDynamicsCompressor();
    masterLimiter.threshold.value = -3;
    masterLimiter.knee.value = 0;
    masterLimiter.ratio.value = 20;
    masterLimiter.attack.value = 0.001;
    masterLimiter.release.value = 0.05;

    // Stereo widener: gentle haas (15ms left only).
    stereoWiden = ctx.createGain();
    stereoWiden.gain.value = 1;

    masterAnalyser = ctx.createAnalyser();
    masterAnalyser.fftSize = 2048;
    masterAnalyser.smoothingTimeConstant = 0.6;

    // Reverb (2-tap feedback delay) — fb gains are module-scoped so
    // setReverbFreeze() can crank them to ~0.99 for an infinite tail.
    reverbInput = ctx.createGain();
    reverbInputAttenuator = ctx.createGain();
    reverbInputAttenuator.gain.value = 1;
    const d1 = ctx.createDelay(2.0); d1.delayTime.value = 0.139;
    const d2 = ctx.createDelay(2.0); d2.delayTime.value = 0.241;
    reverbFb1 = ctx.createGain(); reverbFb1.gain.value = 0.48;
    reverbFb2 = ctx.createGain(); reverbFb2.gain.value = 0.41;
    const damp = ctx.createBiquadFilter();
    damp.type = 'lowpass'; damp.frequency.value = 4500;
    const reverbReturn = ctx.createGain(); reverbReturn.gain.value = 0.6;
    reverbInput.connect(reverbInputAttenuator).connect(d1);
    d1.connect(reverbFb1).connect(d1);
    d1.connect(d2);
    d2.connect(reverbFb2).connect(d2);
    d2.connect(damp).connect(reverbReturn);
    reverbReturn.connect(master);

    // Master delay (dotted-eighth at 124 BPM by default).
    delayInput = ctx.createGain();
    masterDelay = ctx.createDelay(2.0); masterDelay.delayTime.value = 60 / 124 * 0.75;
    const dlyFb = ctx.createGain(); dlyFb.gain.value = 0.45;
    const dlyDamp = ctx.createBiquadFilter();
    dlyDamp.type = 'lowpass'; dlyDamp.frequency.value = 3500;
    const delayReturn = ctx.createGain(); delayReturn.gain.value = 0.55;
    delayInput.connect(masterDelay);
    masterDelay.connect(dlyDamp).connect(delayReturn);
    masterDelay.connect(dlyFb).connect(masterDelay);
    delayReturn.connect(master);

    // Master cut: gate inserted right before the limiter so censor
    // / kill-switch is the very last thing in the chain.
    masterCut = ctx.createGain();
    masterCut.gain.value = 1;

    master.connect(stereoWiden);
    stereoWiden.connect(masterCut);
    masterCut.connect(masterLimiter);
    masterLimiter.connect(masterAnalyser);
    masterAnalyser.connect(ctx.destination);
  }
  if (ctx.state === 'suspended') await ctx.resume();
  started = true;
}

export function audioReady(): boolean { return started; }
export function getCtx(): AudioContext | null { return ctx; }
export function getAnalyser(): AnalyserNode | null { return ctx ? masterAnalyser : null; }
export function getMasterGain(): GainNode | null { return ctx ? master : null; }

/** Tap-tempo delay time (seconds). */
export function setDelayTime(seconds: number): void {
  if (!ctx) return;
  const t = ctx.currentTime;
  masterDelay.delayTime.cancelScheduledValues(t);
  masterDelay.delayTime.setValueAtTime(masterDelay.delayTime.value, t);
  masterDelay.delayTime.linearRampToValueAtTime(Math.max(0.01, seconds), t + 0.05);
}

/** Read VU level (RMS-ish 0..1) for an entity bus. */
export function getEntityLevel(entityKey: string): number {
  const bus = entityBuses.get(entityKey);
  if (!bus) return 0;
  const buf = new Uint8Array(bus.vuAnalyser.fftSize);
  bus.vuAnalyser.getByteTimeDomainData(buf);
  let sum = 0;
  for (let i = 0; i < buf.length; i++) {
    const x = (buf[i] - 128) / 128;
    sum += x * x;
  }
  return Math.min(1, Math.sqrt(sum / buf.length) * 2);
}

/** Get-or-create an entity-level audio bus. */
export function getEntityBus(entityKey: string): EntityBus | null {
  if (!ctx) return null;
  const cached = entityBuses.get(entityKey);
  if (cached) return cached;
  const channelGain = ctx.createGain();
  channelGain.gain.value = 1;
  const pan = ctx.createStereoPanner();
  pan.pan.value = 0;
  const vuAnalyser = ctx.createAnalyser();
  vuAnalyser.fftSize = 1024;
  vuAnalyser.smoothingTimeConstant = 0.4;
  pan.connect(channelGain);
  channelGain.connect(vuAnalyser);
  vuAnalyser.connect(master);
  const trunk = ctx.createGain();
  trunk.gain.value = 1;
  trunk.connect(pan);
  const bus: EntityBus = { channelGain, pan, trackFx: new Map(), trunk, vuAnalyser };
  entityBuses.set(entityKey, bus);
  return bus;
}

export function setEntityGain(entityKey: string, g: number, ramp = 0.05): void {
  const bus = getEntityBus(entityKey);
  if (!bus || !ctx) return;
  const t = ctx.currentTime;
  bus.channelGain.gain.cancelScheduledValues(t);
  bus.channelGain.gain.setValueAtTime(bus.channelGain.gain.value, t);
  bus.channelGain.gain.linearRampToValueAtTime(g, t + ramp);
}

/** Set the stereo pan for an entity bus (-1 = full left, 1 = full right). */
export function setEntityPan(entityKey: string, p: number, ramp = 0.05): void {
  const bus = getEntityBus(entityKey);
  if (!bus || !ctx) return;
  const t = ctx.currentTime;
  bus.pan.pan.cancelScheduledValues(t);
  bus.pan.pan.setValueAtTime(bus.pan.pan.value, t);
  bus.pan.pan.linearRampToValueAtTime(Math.max(-1, Math.min(1, p)), t + ramp);
}

// ── shapers ───────────────────────────────────────────────────

function makeDriveCurve(amount: number): Float32Array {
  // Soft clipping; amount 0..1.
  const k = 1 + amount * 25;
  const samples = 1024;
  const curve = new Float32Array(samples);
  for (let i = 0; i < samples; i++) {
    const x = (i / samples) * 2 - 1;
    curve[i] = ((Math.PI + k) * x) / (Math.PI + k * Math.abs(x)) / Math.PI;
  }
  return curve;
}

function makeBitcrushCurve(steps: number): Float32Array {
  const n = Math.max(2, Math.floor(steps));
  const samples = 1024;
  const curve = new Float32Array(samples);
  for (let i = 0; i < samples; i++) {
    const x = (i / samples) * 2 - 1;
    curve[i] = Math.round(x * n) / n;
  }
  return curve;
}

function getTrackFx(entityKey: string, trackName: string): TrackFx | null {
  if (!ctx) return null;
  const bus = getEntityBus(entityKey);
  if (!bus) return null;
  const cached = bus.trackFx.get(trackName);
  if (cached) return cached;
  const trackBus = ctx.createGain(); trackBus.gain.value = 1;
  const drive = ctx.createWaveShaper();
  drive.curve = makeDriveCurve(0);
  drive.oversample = '2x';
  const bitcrush = ctx.createWaveShaper();
  bitcrush.curve = makeBitcrushCurve(64);
  const filter = ctx.createBiquadFilter();
  filter.type = 'lowpass';
  filter.frequency.value = 18000;
  filter.Q.value = 0.7;
  const reverbSend = ctx.createGain(); reverbSend.gain.value = 0;
  const delaySend = ctx.createGain(); delaySend.gain.value = 0;
  // Sidechain VCA: by default, gain=1 and untouched. When enabled,
  // the sidechain duck signal modulates this gain.
  const sidechainGain = ctx.createGain();
  sidechainGain.gain.value = 1;

  trackBus.connect(drive);
  drive.connect(bitcrush);
  bitcrush.connect(filter);
  filter.connect(sidechainGain);
  sidechainGain.connect(bus.pan);
  filter.connect(reverbSend).connect(reverbInput);
  filter.connect(delaySend).connect(delayInput);
  const fx: TrackFx = {
    trackBus, drive, bitcrush, filter, reverbSend, delaySend,
    sidechainEnabled: false, sidechainGain,
  };
  bus.trackFx.set(trackName, fx);
  return fx;
}

export function setTrackFilter(entityKey: string, track: string, hz: number, ramp = 0.05): void {
  const fx = getTrackFx(entityKey, track);
  if (!fx || !ctx) return;
  const t = ctx.currentTime;
  fx.filter.frequency.cancelScheduledValues(t);
  fx.filter.frequency.setValueAtTime(Math.max(60, fx.filter.frequency.value), t);
  fx.filter.frequency.exponentialRampToValueAtTime(Math.max(60, hz), t + ramp);
}
export function setTrackReverb(entityKey: string, track: string, amt: number, ramp = 0.05): void {
  const fx = getTrackFx(entityKey, track);
  if (!fx || !ctx) return;
  const t = ctx.currentTime;
  fx.reverbSend.gain.cancelScheduledValues(t);
  fx.reverbSend.gain.setValueAtTime(fx.reverbSend.gain.value, t);
  fx.reverbSend.gain.linearRampToValueAtTime(Math.max(0, Math.min(1, amt)), t + ramp);
}
export function setTrackDelay(entityKey: string, track: string, amt: number, ramp = 0.05): void {
  const fx = getTrackFx(entityKey, track);
  if (!fx || !ctx) return;
  const t = ctx.currentTime;
  fx.delaySend.gain.cancelScheduledValues(t);
  fx.delaySend.gain.setValueAtTime(fx.delaySend.gain.value, t);
  fx.delaySend.gain.linearRampToValueAtTime(Math.max(0, Math.min(1, amt)), t + ramp);
}
export function setTrackDrive(entityKey: string, track: string, amt: number): void {
  const fx = getTrackFx(entityKey, track);
  if (!fx) return;
  fx.drive.curve = makeDriveCurve(Math.max(0, Math.min(1, amt)));
}
export function setTrackBitcrush(entityKey: string, track: string, steps: number): void {
  const fx = getTrackFx(entityKey, track);
  if (!fx) return;
  fx.bitcrush.curve = makeBitcrushCurve(steps);
}
export function setTrackSidechain(entityKey: string, track: string, on: boolean): void {
  const fx = getTrackFx(entityKey, track);
  if (!fx) return;
  fx.sidechainEnabled = on;
}

/** Trigger a sidechain duck; called from playDrum on `kick`. */
export function triggerSidechainDuck(): void {
  if (!ctx) return;
  const t = ctx.currentTime;
  // Walk every track that's sidechain-enabled and apply a duck envelope.
  for (const bus of entityBuses.values()) {
    for (const fx of bus.trackFx.values()) {
      if (!fx.sidechainEnabled) continue;
      const g = fx.sidechainGain.gain;
      g.cancelScheduledValues(t);
      g.setValueAtTime(g.value, t);
      g.linearRampToValueAtTime(0.15, t + 0.005);
      g.exponentialRampToValueAtTime(0.18, t + 0.01);
      g.linearRampToValueAtTime(1.0, t + 0.18);
    }
  }
}

/** Master limiter post-mix gain control (dB-ish). */
export function setMasterCeiling(db: number): void {
  if (!ctx) return;
  masterLimiter.threshold.value = Math.max(-24, Math.min(0, db));
}

/** Stereo widener amount (0..1). */
export function setStereoWiden(amt: number): void {
  if (!ctx) return;
  // Cheap: just drive the limiter slightly hotter for "wider" feel.
  // (Real haas needs splitter+merger; deferred.)
  stereoWiden.gain.value = 1 + amt * 0.4;
}

/**
 * Master "freeze" on the reverb bus: cranks the feedback gains close
 * to unity and silences the input so the existing tail rings out
 * indefinitely. Toggle off to restore normal feedback.
 */
export function setReverbFreeze(on: boolean): void {
  if (!ctx) return;
  const t = ctx.currentTime;
  const target1 = on ? 0.99 : 0.48;
  const target2 = on ? 0.99 : 0.41;
  const inputGain = on ? 0 : 1;
  for (const [g, v] of [
    [reverbFb1.gain, target1] as const,
    [reverbFb2.gain, target2] as const,
    [reverbInputAttenuator.gain, inputGain] as const,
  ]) {
    g.cancelScheduledValues(t);
    g.setValueAtTime(g.value, t);
    g.linearRampToValueAtTime(v, t + 0.05);
  }
}

/**
 * Master censor — momentary mute of everything heading to the limiter.
 * Used as a hold-to-cut button (Denon DJ "censor" / kill-switch).
 */
export function setCensor(on: boolean): void {
  if (!ctx) return;
  const t = ctx.currentTime;
  masterCut.gain.cancelScheduledValues(t);
  masterCut.gain.setValueAtTime(masterCut.gain.value, t);
  masterCut.gain.linearRampToValueAtTime(on ? 0 : 1, t + 0.008);
}

/**
 * Begin recording the master output to a MediaRecorder stream. Returns
 * a `stop()` that resolves to an audio blob (webm/opus — works in
 * Chrome/Safari/FF). Hooks into the analyser's pre-destination tap so
 * the recording matches what the user hears.
 */
export function startMasterRecorder(): { stop: () => Promise<Blob> } | null {
  if (!ctx || !masterAnalyser) return null;
  if (!masterRecordTap) {
    masterRecordTap = ctx.createMediaStreamDestination();
    masterAnalyser.connect(masterRecordTap);
  }
  const chunks: BlobPart[] = [];
  const Rec = (window as unknown as { MediaRecorder?: typeof MediaRecorder }).MediaRecorder;
  if (!Rec) return null;
  const mr = new Rec(masterRecordTap.stream);
  mr.ondataavailable = (e) => { if (e.data.size > 0) chunks.push(e.data); };
  mr.start();
  return {
    stop: () =>
      new Promise<Blob>((resolve) => {
        mr.onstop = () => resolve(new Blob(chunks, { type: mr.mimeType || 'audio/webm' }));
        mr.stop();
      }),
  };
}

// ── voice helpers ──────────────────────────────────────────────

export type DrumKind =
  | 'kick' | 'snare' | 'hat' | 'clap' | 'cb' | 'tom' | 'rim' | 'sub' | 'perc'
  | 'shaker' | 'conga' | 'wood' | 'glitch';

export function playDrum(
  kind: DrumKind, vel = 0.9, panX = 0,
  entityKey = 'self', trackName?: string,
): void {
  if (!ctx) return;
  const t = ctx.currentTime + 0.005;
  const fx = trackName ? getTrackFx(entityKey, trackName) : null;
  const bus = getEntityBus(entityKey);
  const target: AudioNode = fx ? fx.trackBus : (bus ? bus.trunk : master);

  // Kick fires the sidechain duck for any track that's enabled it.
  if (kind === 'kick') triggerSidechainDuck();

  const pan = ctx.createStereoPanner();
  pan.pan.value = panX;
  const gainOut = ctx.createGain();
  gainOut.gain.value = vel;

  switch (kind) {
    case 'kick': {
      const o = ctx.createOscillator();
      o.frequency.setValueAtTime(150, t);
      o.frequency.exponentialRampToValueAtTime(45, t + 0.10);
      const env = ctx.createGain();
      env.gain.setValueAtTime(0, t);
      env.gain.linearRampToValueAtTime(1.0, t + 0.005);
      env.gain.exponentialRampToValueAtTime(0.0001, t + 0.22);
      o.connect(env).connect(gainOut);
      o.start(t); o.stop(t + 0.25);
      break;
    }
    case 'sub': {
      const o = ctx.createOscillator();
      o.type = 'sine';
      o.frequency.setValueAtTime(80, t);
      o.frequency.exponentialRampToValueAtTime(35, t + 0.4);
      const env = ctx.createGain();
      env.gain.setValueAtTime(0, t);
      env.gain.linearRampToValueAtTime(0.85, t + 0.02);
      env.gain.exponentialRampToValueAtTime(0.0001, t + 0.55);
      o.connect(env).connect(gainOut);
      o.start(t); o.stop(t + 0.6);
      break;
    }
    default: {
      const dur = kind === 'hat' ? 0.05 : kind === 'clap' ? 0.13 : kind === 'tom' ? 0.4
        : kind === 'shaker' ? 0.10 : kind === 'conga' ? 0.18 : kind === 'wood' ? 0.06
        : kind === 'glitch' ? 0.07 : 0.15;
      const buf = ctx.createBuffer(1, Math.max(64, Math.floor(ctx.sampleRate * dur)), ctx.sampleRate);
      const data = buf.getChannelData(0);
      for (let i = 0; i < data.length; i++) data[i] = Math.random() * 2 - 1;
      const src = ctx.createBufferSource(); src.buffer = buf;
      const f = ctx.createBiquadFilter();
      const peak = kind === 'hat' ? 0.32 : kind === 'clap' ? 0.55 : kind === 'cb' ? 0.5
        : kind === 'shaker' ? 0.22 : kind === 'wood' ? 0.4 : kind === 'glitch' ? 0.4 : 0.55;
      if (kind === 'hat') { f.type = 'highpass'; f.frequency.value = 7000; f.Q.value = 0.7; }
      else if (kind === 'snare') { f.type = 'bandpass'; f.frequency.value = 1500; f.Q.value = 1.0; }
      else if (kind === 'clap') { f.type = 'bandpass'; f.frequency.value = 1800; f.Q.value = 1.5; }
      else if (kind === 'rim') { f.type = 'bandpass'; f.frequency.value = 2400; f.Q.value = 4; }
      else if (kind === 'cb') { f.type = 'bandpass'; f.frequency.value = 800; f.Q.value = 12; }
      else if (kind === 'tom') { f.type = 'lowpass'; f.frequency.value = 240; f.Q.value = 6; }
      else if (kind === 'shaker') { f.type = 'highpass'; f.frequency.value = 5500; f.Q.value = 0.5; }
      else if (kind === 'conga') { f.type = 'bandpass'; f.frequency.value = 380; f.Q.value = 8; }
      else if (kind === 'wood') { f.type = 'bandpass'; f.frequency.value = 1100; f.Q.value = 10; }
      else if (kind === 'glitch') { f.type = 'bandpass'; f.frequency.value = 3200; f.Q.value = 0.5; }
      else { f.type = 'bandpass'; f.frequency.value = 600; f.Q.value = 6; }
      const env = ctx.createGain();
      env.gain.setValueAtTime(0, t);
      env.gain.linearRampToValueAtTime(peak, t + 0.003);
      env.gain.exponentialRampToValueAtTime(0.0001, t + dur);
      if (kind === 'tom') {
        const o = ctx.createOscillator();
        o.frequency.setValueAtTime(120, t);
        o.frequency.exponentialRampToValueAtTime(60, t + 0.2);
        const oEnv = ctx.createGain();
        oEnv.gain.setValueAtTime(0, t);
        oEnv.gain.linearRampToValueAtTime(0.4, t + 0.01);
        oEnv.gain.exponentialRampToValueAtTime(0.0001, t + 0.35);
        o.connect(oEnv).connect(gainOut);
        o.start(t); o.stop(t + 0.4);
      }
      if (kind === 'cb') {
        for (const fHz of [560, 845]) {
          const o = ctx.createOscillator();
          o.type = 'square'; o.frequency.value = fHz;
          const oEnv = ctx.createGain();
          oEnv.gain.setValueAtTime(0, t);
          oEnv.gain.linearRampToValueAtTime(0.18, t + 0.005);
          oEnv.gain.exponentialRampToValueAtTime(0.0001, t + 0.12);
          o.connect(oEnv).connect(gainOut);
          o.start(t); o.stop(t + 0.13);
        }
      }
      src.connect(f).connect(env).connect(gainOut);
      src.start(t); src.stop(t + dur + 0.05);
      break;
    }
  }

  gainOut.connect(pan);
  pan.connect(target);
}

/** Sustain note voice with ADSR. Returns release fn. */
export function playNote(
  freq: number, vel = 0.7, maxDur = 4.0, panX = 0,
  entityKey = 'self', trackName?: string,
): () => void {
  if (!ctx) return () => {};
  const t = ctx.currentTime + 0.005;
  const fx = trackName ? getTrackFx(entityKey, trackName) : null;
  const bus = getEntityBus(entityKey);
  const target: AudioNode = fx ? fx.trackBus : (bus ? bus.trunk : master);

  const o1 = ctx.createOscillator(); const o2 = ctx.createOscillator();
  o1.type = 'sawtooth'; o2.type = 'sawtooth';
  o1.frequency.value = freq; o2.frequency.value = freq;
  o2.detune.value = 7;
  const f = ctx.createBiquadFilter();
  f.type = 'lowpass';
  f.frequency.value = Math.min(freq * 8, 4800);
  f.Q.value = 1.0;
  const env = ctx.createGain();
  const peak = 0.32 * vel;
  const sustain = 0.20 * vel;
  env.gain.setValueAtTime(0, t);
  env.gain.linearRampToValueAtTime(peak, t + 0.008);
  env.gain.linearRampToValueAtTime(sustain, t + 0.008 + 0.09);
  env.gain.setValueAtTime(sustain, t + 0.097);
  env.gain.exponentialRampToValueAtTime(0.0001, t + Math.max(0.5, maxDur));
  const pan = ctx.createStereoPanner();
  pan.pan.value = panX;
  o1.connect(f); o2.connect(f);
  f.connect(env).connect(pan);
  pan.connect(target);
  o1.start(t); o2.start(t);
  const stopAt = t + Math.max(0.5, maxDur) + 0.2;
  o1.stop(stopAt); o2.stop(stopAt);
  return () => {
    if (!ctx) return;
    const now = ctx.currentTime;
    env.gain.cancelScheduledValues(now);
    env.gain.setValueAtTime(Math.max(env.gain.value, 0.0001), now);
    env.gain.exponentialRampToValueAtTime(0.0001, now + 0.14);
    try { o1.stop(now + 0.2); o2.stop(now + 0.2); } catch { /* already stopped */ }
  };
}

/**
 * FM lead voice — punchy bell-like timbre, alternative to the
 * sawtooth supersaw. Two operators, modulator on carrier frequency.
 */
export function playFmNote(
  freq: number, vel = 0.7, maxDur = 4.0, panX = 0,
  entityKey = 'self', trackName?: string,
): () => void {
  if (!ctx) return () => {};
  const t = ctx.currentTime + 0.005;
  const fx = trackName ? getTrackFx(entityKey, trackName) : null;
  const bus = getEntityBus(entityKey);
  const target: AudioNode = fx ? fx.trackBus : (bus ? bus.trunk : master);

  const carrier = ctx.createOscillator(); carrier.type = 'sine';
  carrier.frequency.value = freq;
  const modulator = ctx.createOscillator(); modulator.type = 'sine';
  modulator.frequency.value = freq * 2.01;     // 2:1 ratio with detune
  const modGain = ctx.createGain(); modGain.gain.value = freq * 1.6;
  modulator.connect(modGain).connect(carrier.frequency);

  const env = ctx.createGain();
  env.gain.setValueAtTime(0, t);
  env.gain.linearRampToValueAtTime(0.3 * vel, t + 0.005);
  env.gain.exponentialRampToValueAtTime(0.05 * vel, t + 0.4);
  env.gain.exponentialRampToValueAtTime(0.0001, t + Math.max(0.6, maxDur));
  const pan = ctx.createStereoPanner();
  pan.pan.value = panX;
  carrier.connect(env).connect(pan);
  pan.connect(target);
  carrier.start(t); modulator.start(t);
  const stopAt = t + Math.max(0.6, maxDur) + 0.2;
  carrier.stop(stopAt); modulator.stop(stopAt);
  return () => {
    if (!ctx) return;
    const now = ctx.currentTime;
    env.gain.cancelScheduledValues(now);
    env.gain.setValueAtTime(Math.max(env.gain.value, 0.0001), now);
    env.gain.exponentialRampToValueAtTime(0.0001, now + 0.18);
    try { carrier.stop(now + 0.25); modulator.stop(now + 0.25); } catch { /* ok */ }
  };
}

/**
 * Chiptune square voice — single oscillator with ADSR. Sounds bright
 * and 8-bit. Good for chunky basslines or PWM-style leads.
 */
export function playSquareNote(
  freq: number, vel = 0.7, maxDur = 4.0, panX = 0,
  entityKey = 'self', trackName?: string,
): () => void {
  if (!ctx) return () => {};
  const t = ctx.currentTime + 0.005;
  const fx = trackName ? getTrackFx(entityKey, trackName) : null;
  const bus = getEntityBus(entityKey);
  const target: AudioNode = fx ? fx.trackBus : (bus ? bus.trunk : master);

  const o = ctx.createOscillator();
  o.type = 'square';
  o.frequency.value = freq;
  const env = ctx.createGain();
  env.gain.setValueAtTime(0, t);
  env.gain.linearRampToValueAtTime(0.18 * vel, t + 0.005);
  env.gain.linearRampToValueAtTime(0.13 * vel, t + 0.05);
  env.gain.exponentialRampToValueAtTime(0.0001, t + Math.max(0.5, maxDur));
  const pan = ctx.createStereoPanner(); pan.pan.value = panX;
  o.connect(env).connect(pan);
  pan.connect(target);
  o.start(t); o.stop(t + Math.max(0.5, maxDur) + 0.2);
  return () => {
    if (!ctx) return;
    const now = ctx.currentTime;
    env.gain.cancelScheduledValues(now);
    env.gain.setValueAtTime(Math.max(env.gain.value, 0.0001), now);
    env.gain.exponentialRampToValueAtTime(0.0001, now + 0.12);
    try { o.stop(now + 0.18); } catch { /* ok */ }
  };
}

/**
 * Pulse-wave voice — like square but with a duty-cycle LFO that
 * modulates the second oscillator's phase, giving an animated PWM
 * shimmer common in chiptune leads. Fakes the LFO by detuning two
 * square oscillators slightly.
 */
export function playPulseNote(
  freq: number, vel = 0.7, maxDur = 4.0, panX = 0,
  entityKey = 'self', trackName?: string,
): () => void {
  if (!ctx) return () => {};
  const t = ctx.currentTime + 0.005;
  const fx = trackName ? getTrackFx(entityKey, trackName) : null;
  const bus = getEntityBus(entityKey);
  const target: AudioNode = fx ? fx.trackBus : (bus ? bus.trunk : master);

  const o1 = ctx.createOscillator();
  const o2 = ctx.createOscillator();
  o1.type = 'square'; o2.type = 'square';
  o1.frequency.value = freq; o2.frequency.value = freq;
  // Duty-cycle illusion via LFO-modulated detune.
  const lfo = ctx.createOscillator(); lfo.type = 'sine'; lfo.frequency.value = 4.5;
  const lfoDepth = ctx.createGain(); lfoDepth.gain.value = 12;
  lfo.connect(lfoDepth).connect(o2.detune);

  const f = ctx.createBiquadFilter();
  f.type = 'lowpass';
  f.frequency.value = Math.min(freq * 6, 5500);
  f.Q.value = 0.6;
  const env = ctx.createGain();
  env.gain.setValueAtTime(0, t);
  env.gain.linearRampToValueAtTime(0.20 * vel, t + 0.005);
  env.gain.linearRampToValueAtTime(0.14 * vel, t + 0.06);
  env.gain.exponentialRampToValueAtTime(0.0001, t + Math.max(0.5, maxDur));
  const pan = ctx.createStereoPanner(); pan.pan.value = panX;
  o1.connect(f); o2.connect(f);
  f.connect(env).connect(pan);
  pan.connect(target);
  const stopAt = t + Math.max(0.5, maxDur) + 0.2;
  o1.start(t); o2.start(t); lfo.start(t);
  o1.stop(stopAt); o2.stop(stopAt); lfo.stop(stopAt);
  return () => {
    if (!ctx) return;
    const now = ctx.currentTime;
    env.gain.cancelScheduledValues(now);
    env.gain.setValueAtTime(Math.max(env.gain.value, 0.0001), now);
    env.gain.exponentialRampToValueAtTime(0.0001, now + 0.14);
    try { o1.stop(now + 0.2); o2.stop(now + 0.2); lfo.stop(now + 0.2); }
    catch { /* ok */ }
  };
}

/**
 * Sub-bass voice — pure sine + slow attack + long decay. Sits below
 * the main bass register; useful as a sub-octave layer or as the
 * dedicated low-end voice on the bass track when octave-shifted down.
 */
export function playSubNote(
  freq: number, vel = 0.7, maxDur = 4.0, panX = 0,
  entityKey = 'self', trackName?: string,
): () => void {
  if (!ctx) return () => {};
  const t = ctx.currentTime + 0.005;
  const fx = trackName ? getTrackFx(entityKey, trackName) : null;
  const bus = getEntityBus(entityKey);
  const target: AudioNode = fx ? fx.trackBus : (bus ? bus.trunk : master);

  const o = ctx.createOscillator();
  o.type = 'sine';
  o.frequency.value = freq;
  // A small dose of saturation gives a pleasant sub harmonic without
  // making it a 'bass' bass.
  const shaper = ctx.createWaveShaper();
  shaper.curve = (() => {
    const samples = 256;
    const c = new Float32Array(samples);
    for (let i = 0; i < samples; i++) {
      const x = (i / samples) * 2 - 1;
      c[i] = Math.tanh(x * 1.4);
    }
    return c;
  })();
  const env = ctx.createGain();
  env.gain.setValueAtTime(0, t);
  env.gain.linearRampToValueAtTime(0.5 * vel, t + 0.025);   // slow-ish attack
  env.gain.exponentialRampToValueAtTime(0.0001, t + Math.max(0.5, maxDur));
  const pan = ctx.createStereoPanner(); pan.pan.value = panX;
  o.connect(shaper).connect(env).connect(pan);
  pan.connect(target);
  o.start(t); o.stop(t + Math.max(0.5, maxDur) + 0.2);
  return () => {
    if (!ctx) return;
    const now = ctx.currentTime;
    env.gain.cancelScheduledValues(now);
    env.gain.setValueAtTime(Math.max(env.gain.value, 0.0001), now);
    env.gain.exponentialRampToValueAtTime(0.0001, now + 0.18);
    try { o.stop(now + 0.25); } catch { /* ok */ }
  };
}

/**
 * Electric piano voice — FM (carrier sine + modulator sine) tuned to
 * a 1:14 ratio with a tight pluck envelope so it reads as Rhodes-y
 * rather than bell-y. Light bandpass on top for tine sparkle.
 */
export function playEpianoNote(
  freq: number, vel = 0.7, maxDur = 4.0, panX = 0,
  entityKey = 'self', trackName?: string,
): () => void {
  if (!ctx) return () => {};
  const t = ctx.currentTime + 0.005;
  const fx = trackName ? getTrackFx(entityKey, trackName) : null;
  const bus = getEntityBus(entityKey);
  const target: AudioNode = fx ? fx.trackBus : (bus ? bus.trunk : master);

  const carrier = ctx.createOscillator(); carrier.type = 'sine';
  carrier.frequency.value = freq;
  const modulator = ctx.createOscillator(); modulator.type = 'sine';
  modulator.frequency.value = freq * 14;
  const modGain = ctx.createGain(); modGain.gain.value = freq * 1.2;
  modulator.connect(modGain).connect(carrier.frequency);
  // Modulator decays fast → the bell-ish attack drops to a cleaner sine body.
  const modEnv = ctx.createGain(); modEnv.gain.value = 1;
  modulator.connect(modEnv);
  modEnv.gain.setValueAtTime(1, t);
  modEnv.gain.exponentialRampToValueAtTime(0.05, t + 0.18);

  const filter = ctx.createBiquadFilter();
  filter.type = 'lowpass';
  filter.frequency.value = Math.min(freq * 8, 6500);
  const env = ctx.createGain();
  env.gain.setValueAtTime(0, t);
  env.gain.linearRampToValueAtTime(0.55 * vel, t + 0.005);
  env.gain.exponentialRampToValueAtTime(0.18 * vel, t + 0.25);
  env.gain.exponentialRampToValueAtTime(0.0001, t + Math.max(0.6, maxDur));
  const pan = ctx.createStereoPanner(); pan.pan.value = panX;
  carrier.connect(filter).connect(env).connect(pan);
  pan.connect(target);
  carrier.start(t); modulator.start(t);
  const stopAt = t + Math.max(0.6, maxDur) + 0.2;
  carrier.stop(stopAt); modulator.stop(stopAt);
  return () => {
    if (!ctx) return;
    const now = ctx.currentTime;
    env.gain.cancelScheduledValues(now);
    env.gain.setValueAtTime(Math.max(env.gain.value, 0.0001), now);
    env.gain.exponentialRampToValueAtTime(0.0001, now + 0.16);
    try { carrier.stop(now + 0.22); modulator.stop(now + 0.22); } catch { /* ok */ }
  };
}

/**
 * Pad voice — slow-attack two-saw layer + LP filter, lush and slow.
 * Good for chord beds and atmospheric backgrounds.
 */
export function playPadNote(
  freq: number, vel = 0.7, maxDur = 4.0, panX = 0,
  entityKey = 'self', trackName?: string,
): () => void {
  if (!ctx) return () => {};
  const t = ctx.currentTime + 0.005;
  const fx = trackName ? getTrackFx(entityKey, trackName) : null;
  const bus = getEntityBus(entityKey);
  const target: AudioNode = fx ? fx.trackBus : (bus ? bus.trunk : master);

  const o1 = ctx.createOscillator(); const o2 = ctx.createOscillator();
  o1.type = 'sawtooth'; o2.type = 'sawtooth';
  o1.frequency.value = freq; o2.frequency.value = freq;
  o2.detune.value = -11;
  const filter = ctx.createBiquadFilter();
  filter.type = 'lowpass';
  filter.frequency.setValueAtTime(Math.min(freq * 3, 1800), t);
  filter.frequency.linearRampToValueAtTime(Math.min(freq * 7, 5500), t + 0.4);
  filter.Q.value = 0.9;
  const env = ctx.createGain();
  env.gain.setValueAtTime(0, t);
  env.gain.linearRampToValueAtTime(0.16 * vel, t + 0.35);    // slow attack
  env.gain.linearRampToValueAtTime(0.12 * vel, t + 0.6);
  env.gain.exponentialRampToValueAtTime(0.0001, t + Math.max(1.0, maxDur));
  const pan = ctx.createStereoPanner(); pan.pan.value = panX;
  o1.connect(filter); o2.connect(filter);
  filter.connect(env).connect(pan);
  pan.connect(target);
  const stopAt = t + Math.max(1.0, maxDur) + 0.3;
  o1.start(t); o2.start(t);
  o1.stop(stopAt); o2.stop(stopAt);
  return () => {
    if (!ctx) return;
    const now = ctx.currentTime;
    env.gain.cancelScheduledValues(now);
    env.gain.setValueAtTime(Math.max(env.gain.value, 0.0001), now);
    env.gain.exponentialRampToValueAtTime(0.0001, now + 0.4);
    try { o1.stop(now + 0.5); o2.stop(now + 0.5); } catch { /* ok */ }
  };
}

/**
 * TB-303-style acid bass. Square wave, resonant LP filter sweep,
 * tight envelope on amp + cutoff. Optional accent boosts both.
 * `slide=true` glides from the previous freq instead of attacking.
 */
let lastAcidFreq = 110;
export function playAcid(
  freq: number, vel = 0.8, dur = 0.18, accent = false, slide = false,
  panX = 0, entityKey = 'self', trackName?: string,
): void {
  if (!ctx) return;
  const t = ctx.currentTime + 0.005;
  const fx = trackName ? getTrackFx(entityKey, trackName) : null;
  const bus = getEntityBus(entityKey);
  const target: AudioNode = fx ? fx.trackBus : (bus ? bus.trunk : master);

  const o = ctx.createOscillator();
  o.type = 'sawtooth';
  if (slide) {
    o.frequency.setValueAtTime(lastAcidFreq, t);
    o.frequency.exponentialRampToValueAtTime(freq, t + 0.06);
  } else {
    o.frequency.setValueAtTime(freq, t);
  }
  lastAcidFreq = freq;
  const f = ctx.createBiquadFilter();
  f.type = 'lowpass';
  const baseCut = freq * 5;
  const peakCut = baseCut * (accent ? 6 : 3);
  f.frequency.setValueAtTime(peakCut, t);
  f.frequency.exponentialRampToValueAtTime(Math.max(baseCut, 200), t + dur * 0.8);
  f.Q.value = accent ? 14 : 9;
  const env = ctx.createGain();
  const peak = (accent ? 0.7 : 0.45) * vel;
  env.gain.setValueAtTime(0, t);
  env.gain.linearRampToValueAtTime(peak, t + 0.005);
  env.gain.exponentialRampToValueAtTime(0.0001, t + dur);
  const pan = ctx.createStereoPanner(); pan.pan.value = panX;
  o.connect(f).connect(env).connect(pan);
  pan.connect(target);
  o.start(t); o.stop(t + dur + 0.05);
}

/**
 * Sample playback (for the sampler). `buffer` is an AudioBuffer.
 * `pitch` in semitones from the original. Honours per-track FX.
 */
export function playSample(
  buffer: AudioBuffer, vel = 0.9, pitch = 0, panX = 0,
  entityKey = 'self', trackName?: string,
): void {
  if (!ctx) return;
  const t = ctx.currentTime + 0.005;
  const fx = trackName ? getTrackFx(entityKey, trackName) : null;
  const bus = getEntityBus(entityKey);
  const target: AudioNode = fx ? fx.trackBus : (bus ? bus.trunk : master);
  const src = ctx.createBufferSource();
  src.buffer = buffer;
  src.playbackRate.value = Math.pow(2, pitch / 12);
  const g = ctx.createGain(); g.gain.value = vel;
  const pan = ctx.createStereoPanner(); pan.pan.value = panX;
  src.connect(g).connect(pan);
  pan.connect(target);
  src.start(t);
}

/** Theremin voice. Long-running. */
export interface ThereminVoice {
  setFreq: (hz: number, glide?: number) => void;
  setFilter: (hz: number, glide?: number) => void;
  setGain: (g: number, ramp?: number) => void;
  stop: () => void;
}
export function startTheremin(initialFreq = 220, panX = 0, entityKey = 'self'): ThereminVoice | null {
  if (!ctx) return null;
  const t = ctx.currentTime;
  const bus = getEntityBus(entityKey);
  const target: AudioNode = bus ? bus.trunk : master;
  const o = ctx.createOscillator();
  o.type = 'sine';
  o.frequency.setValueAtTime(initialFreq, t);
  const o5 = ctx.createOscillator();
  o5.type = 'triangle';
  o5.frequency.setValueAtTime(initialFreq * 1.4983, t);
  const sub = ctx.createOscillator();
  sub.type = 'sine';
  sub.frequency.setValueAtTime(initialFreq * 0.5, t);
  const fund = ctx.createGain(); fund.gain.value = 0.85;
  const fifth = ctx.createGain(); fifth.gain.value = 0.18;
  const subG = ctx.createGain(); subG.gain.value = 0.3;
  o.connect(fund); o5.connect(fifth); sub.connect(subG);
  const mix = ctx.createGain();
  fund.connect(mix); fifth.connect(mix); subG.connect(mix);
  const filter = ctx.createBiquadFilter();
  filter.type = 'lowpass';
  filter.frequency.value = 2000;
  filter.Q.value = 4;
  const env = ctx.createGain();
  env.gain.value = 0.0001;
  env.gain.linearRampToValueAtTime(0.22, t + 0.05);
  const pan = ctx.createStereoPanner();
  pan.pan.value = panX;
  mix.connect(filter).connect(env).connect(pan);
  pan.connect(target);
  const rev = ctx.createGain(); rev.gain.value = 0.4;
  pan.connect(rev).connect(reverbInput);
  o.start(t); o5.start(t); sub.start(t);
  return {
    setFreq: (hz, glide = 0.05) => {
      if (!ctx) return;
      const now = ctx.currentTime;
      o.frequency.cancelScheduledValues(now);
      o.frequency.setValueAtTime(o.frequency.value, now);
      o.frequency.exponentialRampToValueAtTime(Math.max(20, hz), now + glide);
      o5.frequency.cancelScheduledValues(now);
      o5.frequency.exponentialRampToValueAtTime(Math.max(20, hz * 1.4983), now + glide);
      sub.frequency.cancelScheduledValues(now);
      sub.frequency.exponentialRampToValueAtTime(Math.max(20, hz * 0.5), now + glide);
    },
    setFilter: (hz, glide = 0.05) => {
      if (!ctx) return;
      const now = ctx.currentTime;
      filter.frequency.cancelScheduledValues(now);
      filter.frequency.setValueAtTime(filter.frequency.value, now);
      filter.frequency.exponentialRampToValueAtTime(Math.max(80, hz), now + glide);
    },
    setGain: (g, ramp = 0.04) => {
      if (!ctx) return;
      const now = ctx.currentTime;
      env.gain.cancelScheduledValues(now);
      env.gain.setValueAtTime(env.gain.value, now);
      env.gain.linearRampToValueAtTime(Math.max(0.0001, g), now + ramp);
    },
    stop: () => {
      if (!ctx) return;
      const now = ctx.currentTime;
      env.gain.cancelScheduledValues(now);
      env.gain.setValueAtTime(env.gain.value, now);
      env.gain.linearRampToValueAtTime(0.0001, now + 0.1);
      o.stop(now + 0.15); o5.stop(now + 0.15); sub.stop(now + 0.15);
    },
  };
}

// ── Performance FX (master-level, controlled by main.ts) ──────

/** Master-bus filter sweep node — created lazily. */
let perfFilter: BiquadFilterNode | null = null;
function getPerfFilter(): BiquadFilterNode | null {
  if (!ctx) return null;
  if (perfFilter) return perfFilter;
  // Insert a bypassable filter between master and stereoWiden.
  perfFilter = ctx.createBiquadFilter();
  perfFilter.type = 'lowpass';
  perfFilter.frequency.value = 22000;
  perfFilter.Q.value = 0.7;
  master.disconnect();
  master.connect(perfFilter);
  perfFilter.connect(stereoWiden);
  return perfFilter;
}
/** value 0..1 → -1=fully highpass, 0=open, +1=fully lowpass. */
export function setPerfFilter(value: number): void {
  if (!ctx) return;
  const f = getPerfFilter();
  if (!f) return;
  // Open knob centred at 0 → no audible filtering.
  if (Math.abs(value) < 0.02) {
    f.type = 'lowpass';
    f.frequency.exponentialRampToValueAtTime(22000, ctx.currentTime + 0.02);
    return;
  }
  if (value > 0) {
    f.type = 'lowpass';
    const target = 18000 * Math.pow(0.001, value);
    f.frequency.exponentialRampToValueAtTime(Math.max(80, target), ctx.currentTime + 0.05);
  } else {
    f.type = 'highpass';
    const target = 20 * Math.pow(800, -value);
    f.frequency.exponentialRampToValueAtTime(Math.min(8000, target), ctx.currentTime + 0.05);
  }
}

/** Master-bus gate (rhythmic chop). Frequency in Hz, depth 0..1. */
let gateLfo: OscillatorNode | null = null;
let gateGain: GainNode | null = null;
let gateInsert: GainNode | null = null;
function setupGate(): void {
  if (!ctx || gateInsert) return;
  gateInsert = ctx.createGain();
  gateInsert.gain.value = 1;
  // Insert in series after perfFilter (or master if not used).
  const upstream = perfFilter ?? master;
  upstream.disconnect();
  upstream.connect(gateInsert);
  gateInsert.connect(stereoWiden);
}
export function setGate(rateHz: number, depth: number): void {
  if (!ctx) return;
  setupGate();
  if (!gateInsert) return;
  if (depth <= 0.001) {
    if (gateLfo) { try { gateLfo.stop(); } catch { /* ok */ } gateLfo = null; }
    gateInsert.gain.cancelScheduledValues(ctx.currentTime);
    gateInsert.gain.setValueAtTime(1, ctx.currentTime);
    return;
  }
  if (!gateLfo) {
    gateLfo = ctx.createOscillator();
    gateLfo.type = 'square';
    gateGain = ctx.createGain();
    gateGain.gain.value = depth * 0.5;
    const offset = ctx.createConstantSource();
    offset.offset.value = 1 - depth * 0.5;
    offset.start();
    gateInsert.gain.value = 0;
    gateLfo.connect(gateGain).connect(gateInsert.gain);
    offset.connect(gateInsert.gain);
    gateLfo.start();
  }
  if (gateGain) gateGain.gain.value = depth * 0.5;
  if (gateLfo) gateLfo.frequency.value = rateHz;
}

/** Tape-stop: ramp output gain + slow down delay tail. */
export function tapeStop(durationMs = 600): void {
  if (!ctx) return;
  const t = ctx.currentTime;
  master.gain.cancelScheduledValues(t);
  master.gain.setValueAtTime(master.gain.value, t);
  master.gain.linearRampToValueAtTime(0.0001, t + durationMs / 1000);
  setTimeout(() => {
    if (!ctx) return;
    const now = ctx.currentTime;
    master.gain.cancelScheduledValues(now);
    master.gain.setValueAtTime(0.0001, now);
    master.gain.linearRampToValueAtTime(0.85, now + 0.25);
  }, durationMs + 50);
}

/** Echo throw: spike the delay send for 1 cycle. */
export function echoThrow(): void {
  if (!ctx) return;
  const t = ctx.currentTime;
  delayInput.gain.cancelScheduledValues(t);
  delayInput.gain.setValueAtTime(1.5, t);
  delayInput.gain.linearRampToValueAtTime(1.0, t + 0.05);
  delayInput.gain.linearRampToValueAtTime(0.0, t + 0.4);
  delayInput.gain.linearRampToValueAtTime(1.0, t + 0.5);
}


```
