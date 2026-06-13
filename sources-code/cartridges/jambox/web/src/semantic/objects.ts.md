---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/jambox/web/src/semantic/objects.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.610852+00:00
---

# cartridges/jambox/web/src/semantic/objects.ts

```ts
/**
 * Semantic object vocabulary for the jambox world.
 *
 * The current UI still renders the classic workbench controls, but these
 * shapes are the durable contract underneath it: every instrument, skin,
 * patch, snapshot, and world placement can become a cell-owned object under
 * an identity. Marketplace, remix, licensing, and anchoring can attach here
 * without rewriting the audio engine.
 */

import type { Clip } from '../clip';
import type { Patch } from '../core/dag';
import type { SerializedCell } from '../core/sync';
import {
  TRACK_KIND, TRACK_NAMES, type Scene, type TrackName,
} from '../sequencer';

export type JamboxObjectKind =
  // existing 13 kinds
  | 'jam.world'
  | 'jam.instrument'
  | 'jam.skin'
  | 'jam.patch'
  | 'jam.snapshot'
  | 'jam.crate'
  | 'jam.track'
  | 'jam.sample-pack'
  | 'jam.sample'
  | 'jam.clock-calibration'
  | 'jam.drum-track'
  | 'jam.pattern'
  | 'jam.arrangement'
  // added in Phase A (9 new kinds)
  | 'jam.rack'
  | 'jam.macro'
  | 'jam.clip'
  | 'jam.scene'
  | 'jam.take'
  | 'jam.contribution'
  | 'jam.player'
  | 'jam.gesture'
  | 'jam.mapping'
  | 'jam.permission'
  // Phase B: extension marketplace
  | 'jam.extension';

export type JamboxLinearity = 'linear' | 'affine' | 'relevant' | 'debug';

export interface SemanticObjectHeader {
  version: 1;
  objectType: JamboxObjectKind;
  /** Semantic namespace path. Stable enough for marketplace indexing. */
  semanticPath: string;
  /** Cell-engine linearity class for lifecycle semantics. */
  linearity: JamboxLinearity;
  /** Identity/hat that owns or authored this object. */
  ownerIdentity: string;
  /** Optional cert id once the jam-room is backed by a real node identity. */
  ownerCertId?: string;
  /** Hash of the previous object state, if this is a state transition. */
  previousStateHash?: string;
  /** Parent object ids, used for remix/fork/skin inheritance. */
  parents: string[];
  /** Marketplace-readiness without committing to payments yet. */
  commercial?: {
    listed: boolean;
    priceSats?: number;
    royaltyBps?: number;
    license: 'personal' | 'remixable' | 'commercial';
  };
  /** Visual skin slot. Skins are semantic objects too. */
  skinObjectId?: string;
  createdAt: number;
}

export interface JamboxSemanticObject<TPayload> {
  id: string;
  header: SemanticObjectHeader;
  payload: TPayload;
}

// ─── Phase A: ViewportPlan ────────────────────────────────────────────────────

/**
 * Renderer guidance for the CSD (Conscious Stack) compression gradient.
 * Phase A ships the contract; Phase G ships the mobile renderer.
 */
export interface ViewportPlan {
  /** Which Conscious Stack layers are surfaced at this viewport size. */
  surfacedLayers: ('L1' | 'L2' | 'L3' | 'L4')[];
  placements: {
    anchor: 'top-band' | 'hero' | 'sticky-top';
    active: 'left-wall' | 'tab-row' | 'bottom-tab-bar';
    support: 'right-wall' | 'bottom-sheet' | 'overflow-menu';
    infrastructure: 'hover-hud' | 'hidden';
  };
  activeSlots: { rhythm: string; melody: string; bassline: string };
}

export interface JamboxWorldPayload {
  room: string;
  title: string;
  bpm: number;
  scene: Scene;
  modules: Array<{
    id: string;
    instrumentObjectId: string;
    track: TrackName;
    position: [number, number, number];
  }>;
  /** Renderer guidance for CSD compression gradient (Phase A+). */
  viewportPlan?: ViewportPlan;
  /** Colour palette for the scale channel in Note mode. Default: 'boomwhacker'. */
  palette?: 'boomwhacker' | 'newton' | 'scriabin';
  /** Default label mode for melodic surfaces. Default: 'off'. */
  labelMode?: 'off' | 'number' | 'solfege' | 'note-name' | 'fingering';
}

export interface JamboxInstrumentPayload {
  track: TrackName;
  label: string;
  family: 'drum' | 'synth' | 'acid' | 'sampler';
  engine: 'builtin-audio' | 'sample' | 'strudel' | 'puredata' | 'external';
  controls: string[];
  factoryClipIds: string[];
}

export interface JamboxSkinPayload {
  targetKind: 'world' | 'instrument';
  label: string;
  palette: {
    body: string;
    emissive: string;
    accent: string;
  };
  material: 'matte' | 'glass' | 'chrome' | 'hologram';
}

export interface JamboxPatchPayload {
  room: string;
  patch: Patch;
  cellHashHex: string;
  appliesToObjectIds: string[];
}

export interface JamboxSnapshotPayload {
  room: string;
  bpm: number;
  scene: Scene;
  identities: string[];
  cells: SerializedCell[];
  headHashHex: string | null;
}

export interface JamboxCratePayload {
  source: 'rekordbox';
  label: string;
  trackObjectIds: string[];
  playlistPath: string[];
}

export interface JamboxTrackPayload {
  source: 'rekordbox';
  sourceTrackId: string;
  title: string;
  artist?: string;
  album?: string;
  location?: string;
  bpm?: number;
  key?: string;
  totalTimeSeconds?: number;
  bridgeAudioId?: string;
  cues: Array<{
    name?: string;
    type?: string;
    startSeconds?: number;
  }>;
}

export interface JamboxSamplePackPayload {
  source: 'splice-folder';
  label: string;
  sampleObjectIds: string[];
  relativePath: string;
}

export interface JamboxSamplePayload {
  source: 'splice-folder';
  name: string;
  relativePath: string;
  pack: string;
  sizeBytes: number;
  extension: string;
  bridgeAudioId?: string;
}

// ─── Drum-track / Pattern / Arrangement ──────────────────────────────────────

/** Drum voices that have their own parameter vocabulary. */
export type DrumVoiceType =
  | 'kick' | 'snare' | 'hat' | 'clap' | 'cb'
  | 'tom'  | 'sub'   | 'perc' | 'shaker';

/**
 * Flat parameter bag for a drum track.  Only the params meaningful to each
 * voice type are used; the rest are ignored by the audio engine.
 *
 * Every field maps 1-to-1 to an audio.ts function so a pushCell that patches
 * a single key can be applied without re-reading the whole object.
 */
export interface JamboxDrumTrackPayload {
  /** Which drum voice this track drives. */
  voiceType: DrumVoiceType;
  /** 16 on/off steps. */
  steps: boolean[];
  /** Per-step velocity 0–127. */
  velocities: number[];
  /** Active loop length; sequencer reads this for polymetric patterns. */
  loopLength: 16 | 32 | 64;
  // ── params (0–1 unless noted) ──────────────────────────────────────────────
  /** Semitone offset −12..+12.  Used by kick/snare/cb/tom/sub/perc. */
  tune: number;
  /** Envelope decay time. */
  decay: number;
  /** Attack transient emphasis (kick). */
  punch: number;
  /** Snare shell crack character (snare). */
  crack: number;
  /** Clave-style ringing (cb). */
  ring: number;
  /** Filter cutoff for metallic tones (hat/perc/shaker), normalised 0–1. */
  tone: number;
  /** Waveshaper drive amount. */
  drive: number;
  /** Pre-fader reverb send. */
  reverb: number;
  /** Pre-fader delay send. */
  delay: number;
  // ── channel ───────────────────────────────────────────────────────────────
  volume: number;   // 0–1
  pan: number;      // −1..+1
  mute: boolean;
  /**
   * Phase A (D-A.6): optional rack ids this track plays through.
   * Defaults to `['jam.rack.drum-808']` for drum voices.
   */
  racks?: string[];
}

export type JamboxDrumTrackObject = JamboxSemanticObject<JamboxDrumTrackPayload>;

/** Default parameter values per voice type. */
export const DRUM_PARAM_DEFAULTS: Record<DrumVoiceType, Omit<JamboxDrumTrackPayload, 'voiceType' | 'steps' | 'velocities' | 'loopLength'>> = {
  kick:   { tune: 0, decay: 0.4, punch: 0.7, crack: 0, ring: 0, tone: 0.5, drive: 0.2, reverb: 0,   delay: 0,   volume: 0.85, pan: 0,    mute: false },
  snare:  { tune: 0, decay: 0.3, punch: 0,   crack: 0.6, ring: 0, tone: 0.5, drive: 0.1, reverb: 0.2, delay: 0,   volume: 0.8,  pan: 0,    mute: false },
  hat:    { tune: 0, decay: 0.15,punch: 0,   crack: 0,   ring: 0, tone: 0.7, drive: 0,   reverb: 0,   delay: 0,   volume: 0.7,  pan: 0,    mute: false },
  clap:   { tune: 0, decay: 0.25,punch: 0,   crack: 0,   ring: 0, tone: 0.5, drive: 0,   reverb: 0.3, delay: 0,   volume: 0.75, pan: 0,    mute: false },
  cb:     { tune: 0, decay: 0.5, punch: 0,   crack: 0,   ring: 0.5, tone: 0.5, drive: 0.3, reverb: 0, delay: 0,   volume: 0.65, pan: 0,    mute: false },
  tom:    { tune: 0, decay: 0.35,punch: 0.3, crack: 0,   ring: 0, tone: 0.5, drive: 0.1, reverb: 0.15,delay: 0,   volume: 0.75, pan: 0,    mute: false },
  sub:    { tune: 0, decay: 0.6, punch: 0.5, crack: 0,   ring: 0, tone: 0.3, drive: 0.15,reverb: 0,   delay: 0,   volume: 0.9,  pan: 0,    mute: false },
  perc:   { tune: 0, decay: 0.2, punch: 0,   crack: 0,   ring: 0, tone: 0.6, drive: 0.1, reverb: 0.1, delay: 0,   volume: 0.65, pan: 0,    mute: false },
  shaker: { tune: 0, decay: 0.1, punch: 0,   crack: 0,   ring: 0, tone: 0.8, drive: 0,   reverb: 0,   delay: 0,   volume: 0.6,  pan: 0,    mute: false },
};

/** Which params each voice type exposes in the HUD (ordered for display). */
export const DRUM_VOICE_PARAMS: Record<DrumVoiceType, Array<keyof typeof DRUM_PARAM_DEFAULTS.kick>> = {
  kick:   ['tune', 'decay', 'punch', 'drive', 'volume', 'pan'],
  snare:  ['tune', 'decay', 'crack', 'reverb', 'volume', 'pan'],
  hat:    ['decay', 'tone', 'drive', 'reverb', 'volume', 'pan'],
  clap:   ['decay', 'tone', 'reverb', 'delay', 'volume', 'pan'],
  cb:     ['tune', 'decay', 'ring', 'drive', 'volume', 'pan'],
  tom:    ['tune', 'decay', 'punch', 'reverb', 'volume', 'pan'],
  sub:    ['tune', 'decay', 'punch', 'drive', 'volume', 'pan'],
  perc:   ['tune', 'decay', 'tone', 'reverb', 'volume', 'pan'],
  shaker: ['decay', 'tone', 'drive', 'delay', 'volume', 'pan'],
};

export function createDrumTrackObject(args: {
  ownerIdentity: string;
  voiceType: DrumVoiceType;
  room: string;
}): JamboxDrumTrackObject {
  const defaults = DRUM_PARAM_DEFAULTS[args.voiceType];
  return {
    id: semanticObjectId('jam.drum-track', args.ownerIdentity, `${args.room}-${args.voiceType}`),
    header: baseHeader({
      objectType: 'jam.drum-track',
      semanticPath: `/jam/v1/drum-track/${args.room}/${args.voiceType}`,
      linearity: 'affine',
      ownerIdentity: args.ownerIdentity,
      parents: [],
    }),
    payload: {
      voiceType: args.voiceType,
      steps: Array(16).fill(false) as boolean[],
      velocities: Array(16).fill(100) as number[],
      loopLength: 16,
      ...defaults,
    },
  };
}

// ─── Pattern ─────────────────────────────────────────────────────────────────

export interface JamboxPatternPayload {
  name: string;
  bpm: number;
  bars: number;
  scene: Scene;
  /** IDs of jam.drum-track objects that make up this pattern. */
  trackObjectIds: string[];
  /**
   * Phase A (D-A.6): optional rack ids that play this pattern.
   * Defaults to `['jam.rack.poly-keys']` for melodic patterns.
   */
  racks?: string[];
}

export type JamboxPatternObject = JamboxSemanticObject<JamboxPatternPayload>;

export function createPatternObject(args: {
  ownerIdentity: string;
  room: string;
  name: string;
  bpm: number;
  bars: number;
  scene: Scene;
  trackObjectIds: string[];
}): JamboxPatternObject {
  const localId = `${args.room}-pattern-${slug(args.name)}`;
  return {
    id: semanticObjectId('jam.pattern', args.ownerIdentity, localId),
    header: baseHeader({
      objectType: 'jam.pattern',
      semanticPath: `/jam/v1/pattern/${slug(args.room)}/${slug(args.name)}`,
      linearity: 'affine',
      ownerIdentity: args.ownerIdentity,
      parents: args.trackObjectIds,
    }),
    payload: {
      name: args.name,
      bpm: args.bpm,
      bars: args.bars,
      scene: args.scene,
      trackObjectIds: args.trackObjectIds,
    },
  };
}

// ─── Arrangement ─────────────────────────────────────────────────────────────

export interface JamboxArrangementSection {
  patternObjectId: string;
  startBar: number;
  lengthBars: number;
}

export interface JamboxArrangementPayload {
  name: string;
  sections: JamboxArrangementSection[];
  /**
   * Phase A (D-A.6): optional rack ids used in this arrangement.
   * Defaults to `['jam.rack.drum-808', 'jam.rack.poly-keys']`.
   */
  racks?: string[];
}

export type JamboxArrangementObject = JamboxSemanticObject<JamboxArrangementPayload>;

export function createArrangementObject(args: {
  ownerIdentity: string;
  room: string;
  name: string;
  sections?: JamboxArrangementSection[];
}): JamboxArrangementObject {
  const localId = `${args.room}-arr-${slug(args.name)}`;
  return {
    id: semanticObjectId('jam.arrangement', args.ownerIdentity, localId),
    header: baseHeader({
      objectType: 'jam.arrangement',
      semanticPath: `/jam/v1/arrangement/${slug(args.room)}/${slug(args.name)}`,
      linearity: 'affine',
      ownerIdentity: args.ownerIdentity,
      parents: [],
    }),
    payload: {
      name: args.name,
      sections: args.sections ?? [],
    },
  };
}

// ─── Clock calibration ───────────────────────────────────────────────────────

export interface JamboxClockCalibrationPayload {
  /** Median RTT to the BEAM clock server in ms. */
  rttMs: number;
  /** Measured server-to-local clock offset in ms (server ≈ local + offsetMs). */
  offsetMs: number;
  /** Manual nudge applied by the DJ in ms (+ve = push beat later). */
  nudgeMs: number;
  /** Combined offset the sequencer applies: offsetMs - nudgeMs. */
  totalOffsetMs: number;
  bpm: number;
  sampledAt: string;
}

export type JamboxWorldObject = JamboxSemanticObject<JamboxWorldPayload>;
export type JamboxInstrumentObject = JamboxSemanticObject<JamboxInstrumentPayload>;
export type JamboxSkinObject = JamboxSemanticObject<JamboxSkinPayload>;
export type JamboxPatchObject = JamboxSemanticObject<JamboxPatchPayload>;
export type JamboxSnapshotObject = JamboxSemanticObject<JamboxSnapshotPayload>;
export type JamboxCrateObject = JamboxSemanticObject<JamboxCratePayload>;
export type JamboxTrackObject = JamboxSemanticObject<JamboxTrackPayload>;
export type JamboxSamplePackObject = JamboxSemanticObject<JamboxSamplePackPayload>;
export type JamboxSampleObject = JamboxSemanticObject<JamboxSamplePayload>;
export type JamboxClockCalibrationObject = JamboxSemanticObject<JamboxClockCalibrationPayload>;
export type JamboxImportObject =
  | JamboxCrateObject
  | JamboxTrackObject
  | JamboxSamplePackObject
  | JamboxSampleObject;

export function semanticObjectId(kind: JamboxObjectKind, owner: string, localId: string): string {
  return `${kind}:${slug(owner)}:${slug(localId)}`;
}

export function createDefaultSkin(ownerIdentity: string): JamboxSkinObject {
  return {
    id: semanticObjectId('jam.skin', ownerIdentity, 'factory-carbon-glow'),
    header: baseHeader({
      objectType: 'jam.skin',
      semanticPath: '/jam/v1/skin/factory-carbon-glow',
      linearity: 'relevant',
      ownerIdentity,
      parents: [],
    }),
    payload: {
      targetKind: 'world',
      label: 'Factory carbon glow',
      palette: { body: '#161922', emissive: '#65d6f5', accent: '#ffd166' },
      material: 'matte',
    },
  };
}

export function createTrackInstrumentObjects(
  ownerIdentity: string,
  clips: Clip[],
): JamboxInstrumentObject[] {
  return TRACK_NAMES.map((track) => {
    const factoryClipIds = clips
      .filter((clip) => clip.track === track)
      .map((clip) => clip.id);
    const family = TRACK_KIND[track];
    return {
      id: semanticObjectId('jam.instrument', ownerIdentity, track),
      header: baseHeader({
        objectType: 'jam.instrument',
        semanticPath: `/jam/v1/instrument/${track}`,
        linearity: 'affine',
        ownerIdentity,
        parents: [],
        commercial: {
          listed: false,
          license: 'remixable',
          royaltyBps: 500,
        },
      }),
      payload: {
        track,
        label: track,
        family,
        engine: family === 'sampler' ? 'sample' : 'builtin-audio',
        controls: controlsForFamily(family),
        factoryClipIds,
      },
    };
  });
}

export function createDefaultWorldObject(args: {
  ownerIdentity: string;
  room: string;
  bpm: number;
  scene: Scene;
  instruments: JamboxInstrumentObject[];
  skinObjectId: string;
  /** Phase A (D-A.7): optional viewport plan. Auto-selected from viewportWidthPx if omitted. */
  viewportPlan?: ViewportPlan;
  /** Phase A (D-A.7): viewport width in px for auto-selecting a plan. Defaults to 1280 (desktop). */
  viewportWidthPx?: number;
  /** Phase A (D-A.7): colour palette. Defaults to 'boomwhacker'. */
  palette?: JamboxWorldPayload['palette'];
  /** Phase A (D-A.7): label mode. Defaults to 'off'. */
  labelMode?: JamboxWorldPayload['labelMode'];
}): JamboxWorldObject {
  // Lazy-import to avoid circular dependency; viewport-plans only uses types from objects.ts.
  const width = args.viewportWidthPx ?? 1280;
  let viewportPlan = args.viewportPlan;
  if (!viewportPlan) {
    if (width <= 600) {
      viewportPlan = MOBILE_PLAN_STUB;
    } else if (width <= 1024) {
      viewportPlan = TABLET_PLAN_STUB;
    } else {
      viewportPlan = DESKTOP_PLAN_STUB;
    }
  }
  return {
    id: semanticObjectId('jam.world', args.ownerIdentity, args.room),
    header: baseHeader({
      objectType: 'jam.world',
      semanticPath: `/jam/v1/world/${slug(args.room)}`,
      linearity: 'relevant',
      ownerIdentity: args.ownerIdentity,
      parents: [],
      skinObjectId: args.skinObjectId,
    }),
    payload: {
      room: args.room,
      title: `${args.room} jambox`,
      bpm: args.bpm,
      scene: args.scene,
      modules: args.instruments.map((instrument, index) => ({
        id: semanticObjectId('jam.world', args.ownerIdentity, `${args.room}-${instrument.payload.track}`),
        instrumentObjectId: instrument.id,
        track: instrument.payload.track,
        position: modulePosition(index, args.instruments.length),
      })),
      viewportPlan,
      palette: args.palette ?? 'boomwhacker',
      labelMode: args.labelMode ?? 'off',
    },
  };
}

// Minimal viewport plan stubs embedded here to avoid a circular import with
// src/world/viewport-plans.ts. The actual full constants live there.
const DESKTOP_PLAN_STUB: ViewportPlan = {
  surfacedLayers: ['L1', 'L2', 'L3', 'L4'],
  placements: { anchor: 'top-band', active: 'left-wall', support: 'right-wall', infrastructure: 'hover-hud' },
  activeSlots: { rhythm: 'jam.rack.drum-808', melody: 'jam.rack.poly-keys', bassline: 'jam.rack.bass-mono' },
};
const TABLET_PLAN_STUB: ViewportPlan = {
  surfacedLayers: ['L1', 'L2', 'L3'],
  placements: { anchor: 'hero', active: 'tab-row', support: 'bottom-sheet', infrastructure: 'hidden' },
  activeSlots: { rhythm: 'jam.rack.drum-808', melody: 'jam.rack.poly-keys', bassline: 'jam.rack.bass-mono' },
};
const MOBILE_PLAN_STUB: ViewportPlan = {
  surfacedLayers: ['L1', 'L2'],
  placements: { anchor: 'sticky-top', active: 'bottom-tab-bar', support: 'overflow-menu', infrastructure: 'hidden' },
  activeSlots: { rhythm: 'jam.rack.drum-808', melody: 'jam.rack.poly-keys', bassline: 'jam.rack.bass-mono' },
};

export function createPatchObject(args: {
  ownerIdentity: string;
  room: string;
  cell: SerializedCell;
  appliesToObjectIds: string[];
}): JamboxPatchObject {
  return {
    id: semanticObjectId('jam.patch', args.ownerIdentity, args.cell.stateHashHex),
    header: baseHeader({
      objectType: 'jam.patch',
      semanticPath: `/jam/v1/patch/${args.cell.patch.op}`,
      linearity: 'linear',
      ownerIdentity: args.ownerIdentity,
      previousStateHash: args.cell.parentHashes.at(-1),
      parents: args.cell.parentHashes,
    }),
    payload: {
      room: args.room,
      patch: args.cell.patch,
      cellHashHex: args.cell.stateHashHex,
      appliesToObjectIds: args.appliesToObjectIds,
    },
  };
}

export function createSnapshotObject(args: {
  ownerIdentity: string;
  room: string;
  bpm: number;
  scene: Scene;
  identities: string[];
  cells: SerializedCell[];
  headHashHex: string | null;
}): JamboxSnapshotObject {
  const localId = `${args.room}-${args.headHashHex ?? 'empty'}-${args.cells.length}`;
  return {
    id: semanticObjectId('jam.snapshot', args.ownerIdentity, localId),
    header: baseHeader({
      objectType: 'jam.snapshot',
      semanticPath: `/jam/v1/snapshot/${slug(args.room)}`,
      linearity: 'relevant',
      ownerIdentity: args.ownerIdentity,
      previousStateHash: args.headHashHex ?? undefined,
      parents: args.headHashHex ? [args.headHashHex] : [],
    }),
    payload: {
      room: args.room,
      bpm: args.bpm,
      scene: args.scene,
      identities: args.identities,
      cells: args.cells,
      headHashHex: args.headHashHex,
    },
  };
}

export function createRekordboxTrackObject(args: {
  ownerIdentity: string;
  sourceTrackId: string;
  title: string;
  artist?: string;
  album?: string;
  location?: string;
  bpm?: number;
  key?: string;
  totalTimeSeconds?: number;
  cues: JamboxTrackPayload['cues'];
}): JamboxTrackObject {
  return {
    id: semanticObjectId('jam.track', args.ownerIdentity, `rekordbox-${args.sourceTrackId}-${args.title}`),
    header: baseHeader({
      objectType: 'jam.track',
      semanticPath: `/jam/v1/import/rekordbox/track/${slug(args.sourceTrackId)}`,
      linearity: 'relevant',
      ownerIdentity: args.ownerIdentity,
      parents: [],
      commercial: { listed: false, license: 'personal' },
    }),
    payload: {
      source: 'rekordbox',
      sourceTrackId: args.sourceTrackId,
      title: args.title,
      artist: args.artist,
      album: args.album,
      location: args.location,
      bpm: args.bpm,
      key: args.key,
      totalTimeSeconds: args.totalTimeSeconds,
      cues: args.cues,
    },
  };
}

export function createRekordboxCrateObject(args: {
  ownerIdentity: string;
  label: string;
  playlistPath: string[];
  trackObjectIds: string[];
}): JamboxCrateObject {
  const localId = `rekordbox-${args.playlistPath.join('-') || args.label}`;
  return {
    id: semanticObjectId('jam.crate', args.ownerIdentity, localId),
    header: baseHeader({
      objectType: 'jam.crate',
      semanticPath: `/jam/v1/import/rekordbox/crate/${args.playlistPath.map(slug).join('/')}`,
      linearity: 'relevant',
      ownerIdentity: args.ownerIdentity,
      parents: args.trackObjectIds,
      commercial: { listed: false, license: 'personal' },
    }),
    payload: {
      source: 'rekordbox',
      label: args.label,
      trackObjectIds: args.trackObjectIds,
      playlistPath: args.playlistPath,
    },
  };
}

export function createSpliceSampleObject(args: {
  ownerIdentity: string;
  name: string;
  relativePath: string;
  pack: string;
  sizeBytes: number;
  extension: string;
}): JamboxSampleObject {
  return {
    id: semanticObjectId('jam.sample', args.ownerIdentity, `splice-${args.relativePath}`),
    header: baseHeader({
      objectType: 'jam.sample',
      semanticPath: `/jam/v1/import/splice/sample/${slug(args.relativePath)}`,
      linearity: 'affine',
      ownerIdentity: args.ownerIdentity,
      parents: [],
      commercial: { listed: false, license: 'personal' },
    }),
    payload: {
      source: 'splice-folder',
      name: args.name,
      relativePath: args.relativePath,
      pack: args.pack,
      sizeBytes: args.sizeBytes,
      extension: args.extension,
    },
  };
}

export function createSpliceSamplePackObject(args: {
  ownerIdentity: string;
  label: string;
  relativePath: string;
  sampleObjectIds: string[];
}): JamboxSamplePackObject {
  return {
    id: semanticObjectId('jam.sample-pack', args.ownerIdentity, `splice-${args.relativePath || args.label}`),
    header: baseHeader({
      objectType: 'jam.sample-pack',
      semanticPath: `/jam/v1/import/splice/pack/${slug(args.relativePath || args.label)}`,
      linearity: 'relevant',
      ownerIdentity: args.ownerIdentity,
      parents: args.sampleObjectIds,
      commercial: { listed: false, license: 'personal' },
    }),
    payload: {
      source: 'splice-folder',
      label: args.label,
      sampleObjectIds: args.sampleObjectIds,
      relativePath: args.relativePath,
    },
  };
}

function baseHeader(args: Omit<SemanticObjectHeader, 'version' | 'createdAt'>): SemanticObjectHeader {
  return { version: 1, createdAt: Date.now(), ...args };
}

function controlsForFamily(family: JamboxInstrumentPayload['family']): string[] {
  if (family === 'drum') return ['level', 'pan', 'filter', 'drive', 'send-delay'];
  if (family === 'acid') return ['level', 'pan', 'cutoff', 'resonance', 'accent', 'slide'];
  if (family === 'sampler') return ['level', 'pan', 'start', 'length', 'pitch', 'reverse'];
  return ['level', 'pan', 'voice', 'filter', 'reverb', 'delay'];
}

function modulePosition(index: number, total: number): [number, number, number] {
  const angle = (Math.PI * 2 * index) / total;
  const radius = 3.2;
  return [
    Math.cos(angle) * radius,
    Math.sin((index / Math.max(1, total - 1)) * Math.PI) * 0.7,
    Math.sin(angle) * radius,
  ];
}

export function createClockCalibrationObject(args: {
  ownerIdentity: string;
  rttMs: number;
  offsetMs: number;
  nudgeMs: number;
  totalOffsetMs: number;
  bpm: number;
  sampledAt: string;
}): JamboxClockCalibrationObject {
  const id = semanticObjectId('jam.clock-calibration', args.ownerIdentity, args.sampledAt);
  return {
    id,
    header: baseHeader({
      objectType: 'jam.clock-calibration',
      semanticPath: `${slug(args.ownerIdentity)}/clock-calibration/${args.sampledAt}`,
      linearity: 'affine',
      ownerIdentity: args.ownerIdentity,
      parents: [],
    }),
    payload: {
      rttMs: args.rttMs,
      offsetMs: args.offsetMs,
      nudgeMs: args.nudgeMs,
      totalOffsetMs: args.totalOffsetMs,
      bpm: args.bpm,
      sampledAt: args.sampledAt,
    },
  };
}

function slug(value: string): string {
  return value.toLowerCase().replace(/[^a-z0-9_-]+/g, '-').replace(/^-+|-+$/g, '') || 'object';
}

// ─── Phase A: new kind payloads ───────────────────────────────────────────────

// jam.rack — linearity: linear
export interface JamboxRackPayload {
  /** Stable rack id, e.g. 'jam.rack.drum-808'. */
  rackId: string;
  name: string;
  engine: 'webaudio' | 'puredata' | 'strudel' | 'midi' | 'hybrid';
  /** Ordered macro names (exactly 8, indices 0-7). */
  macroNames: [string, string, string, string, string, string, string, string];
  /** Current macro values (0-1 each). */
  macroValues: [number, number, number, number, number, number, number, number];
  presetId?: string;
}

export type JamboxRackObject = JamboxSemanticObject<JamboxRackPayload>;

/** Create a rack object. Linearity: linear (singleton in a world slot). */
export function createRack(args: {
  ownerIdentity: string;
  rackId: string;
  name: string;
  engine: JamboxRackPayload['engine'];
  macroNames?: JamboxRackPayload['macroNames'];
}): JamboxRackObject {
  const macroNames = args.macroNames ?? [
    'brightness', 'dirt', 'wobble', 'space', 'snap', 'body', 'chaos', 'tension',
  ] as JamboxRackPayload['macroNames'];
  return {
    id: semanticObjectId('jam.rack', args.ownerIdentity, args.rackId),
    header: baseHeader({
      objectType: 'jam.rack',
      semanticPath: `/jam/v1/rack/${slug(args.rackId)}`,
      linearity: 'linear',
      ownerIdentity: args.ownerIdentity,
      parents: [],
    }),
    payload: {
      rackId: args.rackId,
      name: args.name,
      engine: args.engine,
      macroNames,
      macroValues: [0.5, 0, 0, 0.2, 0.5, 0.5, 0, 0.5],
    },
  };
}

// jam.macro — linearity: debug
export interface JamboxMacroPayload {
  /** Index 0-7. */
  index: number;
  /** Canonical macro name. */
  name: string;
  /** Current value 0-1. */
  value: number;
  /** The rack this macro belongs to. */
  rackId: string;
}

export type JamboxMacroObject = JamboxSemanticObject<JamboxMacroPayload>;

// jam.clip — linearity: affine
export interface JamboxClipPayload {
  name: string;
  /** The pattern object this clip launches. */
  patternObjectId: string;
  /** Whether this clip is armed for recording. */
  armed: boolean;
  /** Clip launch state. */
  state: 'empty' | 'recorded' | 'muted' | 'playing' | 'queued';
  /** The rack id that plays this clip. Defaults to 'jam.rack.poly-keys'. */
  rackId?: string;
}

export type JamboxClipObject = JamboxSemanticObject<JamboxClipPayload>;

/** Create a clip object. Linearity: affine. */
export function createClip(args: {
  ownerIdentity: string;
  room: string;
  name: string;
  patternObjectId: string;
  rackId?: string;
}): JamboxClipObject {
  const localId = `${args.room}-clip-${slug(args.name)}`;
  return {
    id: semanticObjectId('jam.clip', args.ownerIdentity, localId),
    header: baseHeader({
      objectType: 'jam.clip',
      semanticPath: `/jam/v1/clip/${slug(args.room)}/${slug(args.name)}`,
      linearity: 'affine',
      ownerIdentity: args.ownerIdentity,
      parents: [args.patternObjectId],
    }),
    payload: {
      name: args.name,
      patternObjectId: args.patternObjectId,
      armed: false,
      state: 'empty',
      rackId: args.rackId,
    },
  };
}

// jam.scene — linearity: affine
export interface JamboxScenePayload {
  name: string;
  /** Ordered clip object ids that launch together. */
  clipObjectIds: string[];
  /** Scene index 0-3 in the sequencer grid. */
  sceneIndex: 0 | 1 | 2 | 3;
  color?: string;
}

export type JamboxSceneObject = JamboxSemanticObject<JamboxScenePayload>;

/** Create a scene object. Linearity: affine. */
export function createScene(args: {
  ownerIdentity: string;
  room: string;
  name: string;
  sceneIndex: 0 | 1 | 2 | 3;
  clipObjectIds?: string[];
}): JamboxSceneObject {
  const localId = `${args.room}-scene-${args.sceneIndex}-${slug(args.name)}`;
  return {
    id: semanticObjectId('jam.scene', args.ownerIdentity, localId),
    header: baseHeader({
      objectType: 'jam.scene',
      semanticPath: `/jam/v1/scene/${slug(args.room)}/${args.sceneIndex}`,
      linearity: 'affine',
      ownerIdentity: args.ownerIdentity,
      parents: args.clipObjectIds ?? [],
    }),
    payload: {
      name: args.name,
      clipObjectIds: args.clipObjectIds ?? [],
      sceneIndex: args.sceneIndex,
    },
  };
}

// jam.take — linearity: linear
export interface JamboxTakePayload {
  name: string;
  /** The scene or arrangement this take captures. */
  sourceObjectId: string;
  /** Wall-clock start time (ms). */
  startMs: number;
  /** Duration in ms. */
  durationMs: number;
  /** Take capture state. */
  state: 'capturing' | 'captured' | 'promoted';

  // ─── Phase F extensions (F.1) ────────────────────────────────────────────
  /** Room the take was captured in. */
  room?: string;
  /** Start and end of the captured range, in room time. */
  range?: { startRoomTimeMs: number; endRoomTimeMs: number };
  /** Bar count if the take is a clean musical range. */
  lengthBars?: number;
  /** Cell-stream slice (or a content reference if large). */
  cells?: SerializedCell[] | { ref: string; sha256: string };
  /** Players who contributed to this take. */
  players?: string[];
  /** Bound rack ids at capture time. */
  racks?: string[];
  /** Bound mapping ids at capture time. */
  mappings?: string[];
  /** Optional audio bounce (m4a / opus) of the take. */
  audio?: { ref: string; sha256: string; sampleRate: number; channels: number };
  /** Snapshot of room state at capture start, for deterministic replay. */
  startSnapshotHash?: string;
}

export type JamboxTakeObject = JamboxSemanticObject<JamboxTakePayload>;

/** Create a take object. Linearity: linear (once-only capture). */
export function createTake(args: {
  ownerIdentity: string;
  room: string;
  name: string;
  sourceObjectId: string;
  startMs: number;
  durationMs: number;
}): JamboxTakeObject {
  const localId = `${args.room}-take-${slug(args.name)}-${args.startMs}`;
  return {
    id: semanticObjectId('jam.take', args.ownerIdentity, localId),
    header: baseHeader({
      objectType: 'jam.take',
      semanticPath: `/jam/v1/take/${slug(args.room)}/${slug(args.name)}`,
      linearity: 'linear',
      ownerIdentity: args.ownerIdentity,
      parents: [args.sourceObjectId],
    }),
    payload: {
      name: args.name,
      sourceObjectId: args.sourceObjectId,
      startMs: args.startMs,
      durationMs: args.durationMs,
      state: 'capturing',
    },
  };
}

// jam.contribution — linearity: relevant
export interface JamboxContributionPayload {
  /** The player identity making the contribution. */
  playerIdentity: string;
  /** Object ids contributed to (patterns, clips, etc.). */
  objectIds: string[];
  /** Contribution share in basis points (0-10000). */
  shareBps: number;
  /** Timestamp of contribution start. */
  startMs: number;
  /** Timestamp of contribution end (optional if ongoing). */
  endMs?: number;

  // ─── Phase F extensions (F.2) ────────────────────────────────────────────
  /** Cell range within the parent take (room time ms). */
  cellRange?: { from: number; to: number };
  /** Action category — informational, not authoritative. */
  category?: 'pattern.edit' | 'note.play' | 'macro.twist' | 'gesture' | 'mapping.fork' | 'launch' | 'arrangement.edit' | 'capture';
  /** Suggested split, in basis points. Default policy fills these in. */
  splitBps?: number;
  /** License this contribution flows under. */
  license?: 'personal' | 'remixable' | 'commercial';
  /** Player identity alias. */
  player?: string;
}

export type JamboxContributionObject = JamboxSemanticObject<JamboxContributionPayload>;

/** Create a contribution object. Linearity: relevant (contributions accrete). */
export function createContribution(args: {
  ownerIdentity: string;
  room: string;
  playerIdentity: string;
  objectIds: string[];
  shareBps: number;
  startMs: number;
  // Phase F optional extensions
  cellRange?: { from: number; to: number };
  category?: JamboxContributionPayload['category'];
  license?: JamboxContributionPayload['license'];
}): JamboxContributionObject {
  const localId = `${args.room}-contrib-${slug(args.playerIdentity)}-${args.startMs}`;
  return {
    id: semanticObjectId('jam.contribution', args.ownerIdentity, localId),
    header: baseHeader({
      objectType: 'jam.contribution',
      semanticPath: `/jam/v1/contribution/${slug(args.room)}/${slug(args.playerIdentity)}`,
      linearity: 'relevant',
      ownerIdentity: args.ownerIdentity,
      parents: args.objectIds,
    }),
    payload: {
      playerIdentity: args.playerIdentity,
      objectIds: args.objectIds,
      shareBps: args.shareBps,
      splitBps: args.shareBps,
      startMs: args.startMs,
      cellRange: args.cellRange,
      category: args.category ?? 'capture',
      license: args.license ?? 'personal',
      player: args.playerIdentity,
    },
  };
}

// jam.player — linearity: affine
export interface JamboxPlayerPayload {
  /** The player's identity string. */
  identity: string;
  displayName: string;
  /** Peer color hex used in audio routing. */
  colorHex: string;
  /** Player join state in the room. */
  state: 'joining' | 'active' | 'left';
  /** ISO timestamp when the player joined. */
  joinedAt: string;
}

export type JamboxPlayerObject = JamboxSemanticObject<JamboxPlayerPayload>;

/** Create a player object. Linearity: affine (can join/leave). */
export function createPlayer(args: {
  ownerIdentity: string;
  room: string;
  identity: string;
  displayName: string;
  colorHex: string;
}): JamboxPlayerObject {
  const localId = `${args.room}-player-${slug(args.identity)}`;
  return {
    id: semanticObjectId('jam.player', args.ownerIdentity, localId),
    header: baseHeader({
      objectType: 'jam.player',
      semanticPath: `/jam/v1/player/${slug(args.room)}/${slug(args.identity)}`,
      linearity: 'affine',
      ownerIdentity: args.ownerIdentity,
      parents: [],
    }),
    payload: {
      identity: args.identity,
      displayName: args.displayName,
      colorHex: args.colorHex,
      state: 'joining',
      joinedAt: new Date().toISOString(),
    },
  };
}

// jam.gesture — linearity: debug
export interface JamboxGesturePayload {
  /** Gesture kind: filter sweep, riser, pitch bend, etc. */
  kind: 'filter-sweep' | 'riser' | 'pitch-bend' | 'mod-wheel' | 'aftertouch' | 'custom';
  /** Player identity originating this gesture. */
  playerIdentity: string;
  /** Target rack id. */
  rackId: string;
  /** Gesture parameters (kind-specific). */
  params: Record<string, number | string | boolean>;
  /** Gesture start timestamp (ms). */
  startMs: number;
  /** Gesture end timestamp (ms). Optional if ongoing. */
  endMs?: number;
}

export type JamboxGestureObject = JamboxSemanticObject<JamboxGesturePayload>;

/** Create a gesture object. Linearity: debug (transient performance event). */
export function createGesture(args: {
  ownerIdentity: string;
  room: string;
  kind: JamboxGesturePayload['kind'];
  playerIdentity: string;
  rackId: string;
  params?: Record<string, number | string | boolean>;
  startMs?: number;
}): JamboxGestureObject {
  const startMs = args.startMs ?? Date.now();
  const localId = `${args.room}-gesture-${slug(args.kind)}-${startMs}`;
  return {
    id: semanticObjectId('jam.gesture', args.ownerIdentity, localId),
    header: baseHeader({
      objectType: 'jam.gesture',
      semanticPath: `/jam/v1/gesture/${slug(args.room)}/${slug(args.kind)}`,
      linearity: 'debug',
      ownerIdentity: args.ownerIdentity,
      parents: [],
    }),
    payload: {
      kind: args.kind,
      playerIdentity: args.playerIdentity,
      rackId: args.rackId,
      params: args.params ?? {},
      startMs,
    },
  };
}

// ─── Phase C: jam.mapping full payload ───────────────────────────────────────

/**
 * Value transform applied to a continuous input before it drives a target.
 * All transforms are declarative JSON — no eval, no embedded scripts.
 */
export interface MappingTransform {
  kind: 'linear' | 'exp' | 'log' | 'clamp';
  min?: number;
  max?: number;
  /** Exponent for 'exp' and 'log' curves. */
  gamma?: number;
}

/**
 * A single input binding: one surface element → one target.
 */
export interface MappingInput {
  /** Class of the surface element. */
  type: 'pad' | 'key' | 'knob' | 'fader' | 'touch' | 'xy'
      | 'gamepad-axis' | 'gamepad-button' | 'transport'
      | 'gesture';
  /** Identifier on that surface (pad index, key string, CC number, etc.). */
  selector: string | number;
  /** Optional continuous-value transform. */
  transform?: MappingTransform;
  /** What this input drives. */
  target: MappingTarget;
}

/**
 * What a surface input drives.  Discriminated union so the router can dispatch
 * without reflection.
 */
export type MappingTarget =
  | { kind: 'mode'; mode: GridModeKind }
  | { kind: 'rack.macro'; rackId: string; macro: number }
  | { kind: 'rack.note'; rackId: string }
  | { kind: 'rack.trigger'; rackId: string; voiceId: string }
  | { kind: 'pattern.step'; patternId: string; lane: string; step: number }
  | { kind: 'clip.launch'; clipId: string }
  | { kind: 'scene.launch'; sceneId: string }
  | {
      kind: 'transport';
      verb: 'play' | 'stop' | 'record' | 'overdub' | 'tap'
           | 'metronome' | 'undo' | 'redo' | 'capture' | 'quantize';
    }
  | {
      /** D-G.7: gesture target — dispatches a jam.gesture cell. */
      kind: 'gesture';
      gestureKind: 'propose' | 'confirm' | 'cancel' | 'sync-drop';
    };

/**
 * Device feedback output: room-state → device LED / label / motor fader / haptic.
 *
 * The `source: 'scale.degree'` path (§C.2a) reads `colourForPitch` from the
 * Phase A scale-colour module and pushes the resulting hue/saturation into the
 * device-specific LED protocol.
 */
export interface MappingOutput {
  type: 'led' | 'label' | 'motor-fader' | 'haptic';
  selector: string | number;
  source: 'clip.state' | 'scene.state' | 'rack.macro' | 'pattern.playhead'
        | 'transport.state' | 'player.colour' | 'scale.degree';
  projection?: 'colour' | 'brightness' | 'pulse' | 'flash' | 'value' | 'label';
}

/**
 * A constraint declaration attached to a mapping.
 * The router enforces these before applying the mapping.
 *
 * `requires-permission: chromatic` lets a mapping bypass Note-mode's
 * chromatic-note guardrail and emit pitches outside the current scale.
 */
export interface MappingConstraint {
  kind: 'requires-mode' | 'requires-rack' | 'requires-permission';
  value: string;
}

/**
 * Colour rule: a predicate on room state → a pad colour for visual feedback.
 * Predicates are simple strings (e.g. 'clip.state == playing') evaluated by
 * the feedback layer without eval().
 */
export interface MappingColourRule {
  when: string;
  colour: PadColor;
}

/**
 * PadColor is needed by MappingColourRule.  It lives in surface.ts but we
 * redeclare it here to break the circular dependency; must stay in sync.
 */
export type PadColor =
  | 'off' | 'white' | 'red' | 'orange' | 'yellow'
  | 'green' | 'cyan' | 'blue' | 'purple' | 'pink' | 'dim';

/**
 * GridModeKind is needed by MappingTarget.  It lives in surface.ts but we
 * redeclare the type here to break the circular dependency; the router asserts
 * type-level compatibility.
 */
export type GridModeKind =
  | 'global' | 'step' | 'param' | 'session' | 'arrangement'
  | 'note' | 'mix' | 'custom';

// jam.mapping — linearity: linear
/**
 * Full Phase-C payload for a jam.mapping semantic object.
 *
 * A mapping is a declarative description of how one physical surface (or device)
 * drives the jam room.  It is versioned, content-addressed, and shareable.
 */
export interface JamboxMappingPayload {
  /** Stable human-readable name. */
  name: string;
  /** Author identity (ownerIdentity of the header is the current holder; author is the original creator). */
  author: string;
  /** The surface shape this mapping targets. */
  surfaceShape:
    | 'grid-8x8' | 'grid-4x8' | 'grid-16x8'
    | 'keyboard' | 'dj-deck' | 'mpk49' | 'launchpad' | 'push'
    | 'circuit' | 'qwerty' | 'touch' | 'gamepad' | 'phone'
    | 'phone-with-controller' | 'three-room' | 'custom';
  /** Map every input element to a target. */
  inputs: MappingInput[];
  /** Map device feedback channels to room-state subscriptions. */
  outputs: MappingOutput[];
  /** Optional constraints (mode requirements, permission flags). */
  constraints?: MappingConstraint[];
  /** Optional colour rules for visual feedback. */
  colourRules?: MappingColourRule[];
  /** Semantic version string (e.g. '1.0.0'). */
  version: string;
  /** License — propagates through fork lineage. */
  license: 'personal' | 'remixable' | 'commercial';
}

export type JamboxMappingObject = JamboxSemanticObject<JamboxMappingPayload>;

/** Create a mapping object. Linearity: linear (content-addressed; never mutated in place). */
export function createMapping(args: {
  ownerIdentity: string;
  room: string;
  name: string;
  author?: string;
  surfaceShape: JamboxMappingPayload['surfaceShape'];
  inputs?: MappingInput[];
  outputs?: MappingOutput[];
  constraints?: MappingConstraint[];
  colourRules?: MappingColourRule[];
  version?: string;
  license?: JamboxMappingPayload['license'];
  parents?: string[];
}): JamboxMappingObject {
  const localId = `${args.room}-mapping-${slug(args.name)}-${slug(args.surfaceShape)}`;
  return {
    id: semanticObjectId('jam.mapping', args.ownerIdentity, localId),
    header: baseHeader({
      objectType: 'jam.mapping',
      semanticPath: `/jam/v1/mapping/${slug(args.room)}/${slug(args.name)}`,
      linearity: 'linear',
      ownerIdentity: args.ownerIdentity,
      parents: args.parents ?? [],
    }),
    payload: {
      name: args.name,
      author: args.author ?? args.ownerIdentity,
      surfaceShape: args.surfaceShape,
      inputs: args.inputs ?? [],
      outputs: args.outputs ?? [],
      constraints: args.constraints,
      colourRules: args.colourRules,
      version: args.version ?? '1.0.0',
      license: args.license ?? 'personal',
    },
  };
}

// jam.permission — linearity: linear
export interface JamboxPermissionPayload {
  /** Object id this permission grants access to. */
  objectId: string;
  /** The grantee identity. */
  granteeIdentity: string;
  /** What the grantee can do. */
  grants: Array<'read' | 'write' | 'launch' | 'fork' | 'admin'>;
  /** Whether this permission is currently active. */
  active: boolean;
  /** Expiry timestamp (ms) if time-limited. */
  expiresMs?: number;
}

export type JamboxPermissionObject = JamboxSemanticObject<JamboxPermissionPayload>;

// ── jam.extension ─────────────────────────────────────────────────────────────

/**
 * An extension is a pluggable intent reducer that augments the overlay grammar.
 *
 * Ownership model:
 *   - ownerIdentity: the creator's identity hash (or 'jam.system' for built-ins).
 *   - commercial.listed: true to appear in the marketplace.
 *   - commercial.priceSats: one-time purchase price in satoshis (0 = free).
 *   - commercial.royaltyBps: basis points of a session's revenue the extension
 *     owner earns when the extension fires during that session.
 *   - commercial.license: personal | remixable | commercial.
 *
 * The reducer code itself is not stored here (it's loaded from the extension
 * bundle). This object is the marketplace manifest and accounting anchor.
 */
export interface JamboxExtensionPayload {
  /** Matches JamExtensionReducer.extensionId. */
  extensionId: string;
  /** Display name shown in marketplace and HintStrip. */
  name: string;
  /** Semver string of the extension bundle. */
  version: string;
  /**
   * Which overlay primitives this extension declares.
   * Used for conflict-detection at install time.
   */
  primitives: Array<'momentary' | 'latched' | 'compound' | 'emit'>;
  /**
   * Priority the reducer will be installed at (must be ≥ 100).
   * Lower = runs earlier in the chain.
   */
  priority: number;
  /**
   * URL or CID of the extension bundle (ESM module).
   * Resolved at install time; never auto-loaded.
   */
  bundleUrl: string;
  /** SHA-256 hash of the bundle for integrity verification. */
  bundleHash: string;
  /** Human-readable changelog for this version. */
  changelog?: string;
}

export type JamboxExtensionObject = JamboxSemanticObject<JamboxExtensionPayload>;

/** Create an extension manifest object. */
export function createExtension(args: {
  ownerIdentity: string;
  extensionId: string;
  name: string;
  version: string;
  primitives: JamboxExtensionPayload['primitives'];
  priority: number;
  bundleUrl: string;
  bundleHash: string;
  priceSats?: number;
  royaltyBps?: number;
  license?: 'personal' | 'remixable' | 'commercial';
  changelog?: string;
}): JamboxExtensionObject {
  if (args.priority < 100) {
    throw new Error(`Extension priority must be ≥ 100 (got ${args.priority}). Built-ins use 0–99.`);
  }
  const localId = `ext-${slug(args.extensionId)}-${args.version.replace(/\./g, '-')}`;
  return {
    id: semanticObjectId('jam.extension', args.ownerIdentity, localId),
    header: {
      ...baseHeader({
        objectType: 'jam.extension',
        semanticPath: `/jam/v1/extension/${slug(args.extensionId)}/${args.version}`,
        linearity: 'affine',
        ownerIdentity: args.ownerIdentity,
        parents: [],
      }),
      commercial: {
        listed: (args.priceSats ?? 0) > 0 || (args.royaltyBps ?? 0) > 0,
        priceSats: args.priceSats ?? 0,
        royaltyBps: args.royaltyBps ?? 0,
        license: args.license ?? 'commercial',
      },
    },
    payload: {
      extensionId: args.extensionId,
      name: args.name,
      version: args.version,
      primitives: args.primitives,
      priority: args.priority,
      bundleUrl: args.bundleUrl,
      bundleHash: args.bundleHash,
      changelog: args.changelog,
    },
  };
}

// ─────────────────────────────────────────────────────────────────────────────

/** Create a permission object. Linearity: linear (revocable token). */
export function createPermission(args: {
  ownerIdentity: string;
  room: string;
  objectId: string;
  granteeIdentity: string;
  grants: JamboxPermissionPayload['grants'];
  expiresMs?: number;
}): JamboxPermissionObject {
  const localId = `${args.room}-perm-${slug(args.objectId)}-${slug(args.granteeIdentity)}`;
  return {
    id: semanticObjectId('jam.permission', args.ownerIdentity, localId),
    header: baseHeader({
      objectType: 'jam.permission',
      semanticPath: `/jam/v1/permission/${slug(args.room)}/${slug(args.objectId)}`,
      linearity: 'linear',
      ownerIdentity: args.ownerIdentity,
      parents: [args.objectId],
    }),
    payload: {
      objectId: args.objectId,
      granteeIdentity: args.granteeIdentity,
      grants: args.grants,
      active: true,
      expiresMs: args.expiresMs,
    },
  };
}

```
