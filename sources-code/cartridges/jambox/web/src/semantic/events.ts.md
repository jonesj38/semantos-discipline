---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/jambox/web/src/semantic/events.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.611491+00:00
---

# cartridges/jambox/web/src/semantic/events.ts

```ts
/**
 * Event-cell family type union for the jam-room.
 *
 * These families are the canonical wire format for all events emitted
 * by surfaces, sequencers, clocks, racks, and room actors.
 *
 * Every cell carries a `SemanticObjectHeader` envelope plus the family
 * payload below. The families are frozen — do not add new families here;
 * new families require a new Phase PRD.
 *
 * Families defined in Phase A §A.4:
 *
 *   jam.input.*        — surface input events (pad, knob, key, fader, touch, gamepad)
 *   jam.clock.*        — transport/clock events (tick, start, stop, nudge)
 *   jam.note.*         — note events (on, off, expression)
 *   jam.trigger        — drum/percussive trigger
 *   jam.control.*      — control-change and gesture
 *   jam.pattern.*      — pattern editing (step toggle, velocity, probability, lane select)
 *   jam.clip.*         — clip lifecycle (arm, record, launch, stop)
 *   jam.scene.*        — scene launch
 *   jam.arrangement.*  — arrangement editing
 *   jam.rack.*         — rack parameter changes
 *   jam.mapping.*      — mapping install/uninstall/fork
 *   jam.room.*         — room presence and broadcast
 */

// ─── jam.input family ─────────────────────────────────────────────────────────

export interface JamInputPad {
  family: 'jam.input.pad';
  surfaceId: string;
  x: number;
  y: number;
  pressure: number;
  velocity: number;
  aftertouch: number;
  ts: number;
  mode: string;
  target?: string;
}

export interface JamInputKnob {
  family: 'jam.input.knob';
  surfaceId: string;
  index: number;
  value: number;
  delta: number;
  target?: string;
}

export interface JamInputKey {
  family: 'jam.input.key';
  surfaceId: string;
  keyCode: string;
  value: number;
  target?: string;
}

export interface JamInputFader {
  family: 'jam.input.fader';
  surfaceId: string;
  index: number;
  value: number;
  target?: string;
}

export interface JamInputTouch {
  family: 'jam.input.touch';
  surfaceId: string;
  x: number;
  y: number;
  pressure: number;
  area: number;
  target?: string;
}

export interface JamInputGamepad {
  family: 'jam.input.gamepad';
  surfaceId: string;
  axisOrButton: string;
  value: number;
  target?: string;
}

// ─── jam.clock family ─────────────────────────────────────────────────────────

export interface JamClockTick {
  family: 'jam.clock.tick';
  roomTime: number;
  beat: number;
  bar: number;
  bpm: number;
}

export interface JamClockStart {
  family: 'jam.clock.start';
  roomTime: number;
}

export interface JamClockStop {
  family: 'jam.clock.stop';
  roomTime: number;
}

export interface JamClockNudge {
  family: 'jam.clock.nudge';
  ms: number;
}

// ─── jam.note family ──────────────────────────────────────────────────────────

export interface JamNoteOnEvent {
  family: 'jam.note.on';
  rackId: string;
  pitch: number;
  velocity: number;
  voiceId?: string;
  ts: number;
  gestureId?: string;
}

export interface JamNoteOffEvent {
  family: 'jam.note.off';
  rackId: string;
  pitch: number;
  voiceId?: string;
  ts: number;
}

export interface JamNoteExpression {
  family: 'jam.note.expression';
  rackId: string;
  voiceId: string;
  parameter: string;
  value: number;
}

// ─── jam.trigger ──────────────────────────────────────────────────────────────

export interface JamTriggerEvent {
  family: 'jam.trigger';
  rackId: string;
  voiceId: string;
  velocity: number;
  probability?: number;
  microOffset?: number;
  ratchet?: number;
  ts: number;
}

// ─── jam.control family ───────────────────────────────────────────────────────

export interface JamControlChange {
  family: 'jam.control.change';
  target: string;
  value: number;
  curve?: 'linear' | 'log' | 'exp';
  ts: number;
  gestureId?: string;
}

export interface JamControlGesture {
  family: 'jam.control.gesture';
  gestureId: string;
  kind: string;
  params: Record<string, unknown>;
  ts: number;
}

// ─── jam.pattern family ───────────────────────────────────────────────────────

export interface JamPatternStepToggle {
  family: 'jam.pattern.step.toggle';
  patternId: string;
  lane: string;
  step: number;
  on: boolean;
}

export interface JamPatternStepSetVelocity {
  family: 'jam.pattern.step.setVelocity';
  patternId: string;
  lane: string;
  step: number;
  velocity: number;
}

export interface JamPatternStepSetProbability {
  family: 'jam.pattern.step.setProbability';
  patternId: string;
  lane: string;
  step: number;
  probability: number;
}

export interface JamPatternLaneSelect {
  family: 'jam.pattern.lane.select';
  patternId: string;
  lane: string;
}

// ─── jam.clip family ──────────────────────────────────────────────────────────

export interface JamClipArm {
  family: 'jam.clip.arm';
  clipId: string;
  owner: string;
}

export interface JamClipRecordStart {
  family: 'jam.clip.record.start';
  clipId: string;
  ts: number;
}

export interface JamClipRecordStop {
  family: 'jam.clip.record.stop';
  clipId: string;
  ts: number;
}

export interface JamClipLaunchQueue {
  family: 'jam.clip.launch.queue';
  clipId: string;
  quantum: number;
  ts: number;
}

export interface JamClipStopQueue {
  family: 'jam.clip.stop.queue';
  clipId: string;
  quantum: number;
  ts: number;
}

// ─── jam.scene family ─────────────────────────────────────────────────────────

export interface JamSceneLaunch {
  family: 'jam.scene.launch';
  sceneId: string;
  quantum: number;
  ts: number;
}

// ─── jam.arrangement family ───────────────────────────────────────────────────

export interface JamArrangementSectionAdd {
  family: 'jam.arrangement.section.add';
  arrangementId: string;
  section: { patternObjectId: string; startBar: number; lengthBars: number };
}

export interface JamArrangementSectionMove {
  family: 'jam.arrangement.section.move';
  arrangementId: string;
  sectionId: string;
  to: number;
}

export interface JamArrangementSectionResize {
  family: 'jam.arrangement.section.resize';
  arrangementId: string;
  sectionId: string;
  lengthBars: number;
}

export interface JamArrangementTakeCapture {
  family: 'jam.arrangement.take.capture';
  arrangementId: string;
  takeId: string;
  range: { startBar: number; lengthBars: number };
}

export interface JamArrangementTakePromote {
  family: 'jam.arrangement.take.promote';
  arrangementId: string;
  takeId: string;
}

// ─── jam.rack family ──────────────────────────────────────────────────────────

export interface JamRackMacroSet {
  family: 'jam.rack.macro.set';
  rackId: string;
  index: number;
  value: number;
}

export interface JamRackPresetLoad {
  family: 'jam.rack.preset.load';
  rackId: string;
  presetId: string;
}

export interface JamRackStateSave {
  family: 'jam.rack.state.save';
  rackId: string;
  stateHash: string;
}

// ─── jam.mapping family ───────────────────────────────────────────────────────

export interface JamMappingInstall {
  family: 'jam.mapping.install';
  mappingId: string;
  surfaceId: string;
}

export interface JamMappingUninstall {
  family: 'jam.mapping.uninstall';
  mappingId: string;
  surfaceId: string;
}

export interface JamMappingFork {
  family: 'jam.mapping.fork';
  fromMappingId: string;
  toMappingId: string;
}

// ─── jam.extension family ─────────────────────────────────────────────────────

/** Emitted when a marketplace extension is installed into a session. */
export interface JamExtensionInstall {
  family: 'jam.extension.install';
  extensionId: string;
  ownerIdentity: string;
  version: string;
  ts: number;
}

/** Emitted when an extension is removed from a session. */
export interface JamExtensionUninstall {
  family: 'jam.extension.uninstall';
  extensionId: string;
  ts: number;
}

/**
 * Emitted each time an extension reducer handles an event and produces output.
 *
 * Weight: 0 in the contribution scoring (infrastructure).
 * Used separately to attribute royaltyBps to the extension owner at
 * session-close time: extensionFires / totalFires × royaltyBps × sessionRevenue.
 */
export interface JamExtensionFire {
  family: 'jam.extension.fire';
  extensionId: string;
  ownerIdentity: string;
  /** Named intent produced (e.g. 'step.chain', 'mute.toggle'). */
  intent: string;
  surfaceId: string;
  ts: number;
}

// ─── jam.room family ──────────────────────────────────────────────────────────

export interface JamRoomPlayerJoin {
  family: 'jam.room.player.join';
  playerId: string;
}

export interface JamRoomPlayerLeave {
  family: 'jam.room.player.leave';
  playerId: string;
}

export interface JamRoomBroadcastStatePatch {
  family: 'jam.room.broadcast.statePatch';
  hash: string;
  range: { from: number; to: number };
}

// ─── Full union ───────────────────────────────────────────────────────────────

export type JamEvent =
  // extension
  | JamExtensionInstall
  | JamExtensionUninstall
  | JamExtensionFire
  // input
  | JamInputPad
  | JamInputKnob
  | JamInputKey
  | JamInputFader
  | JamInputTouch
  | JamInputGamepad
  // clock
  | JamClockTick
  | JamClockStart
  | JamClockStop
  | JamClockNudge
  // note
  | JamNoteOnEvent
  | JamNoteOffEvent
  | JamNoteExpression
  // trigger
  | JamTriggerEvent
  // control
  | JamControlChange
  | JamControlGesture
  // pattern
  | JamPatternStepToggle
  | JamPatternStepSetVelocity
  | JamPatternStepSetProbability
  | JamPatternLaneSelect
  // clip
  | JamClipArm
  | JamClipRecordStart
  | JamClipRecordStop
  | JamClipLaunchQueue
  | JamClipStopQueue
  // scene
  | JamSceneLaunch
  // arrangement
  | JamArrangementSectionAdd
  | JamArrangementSectionMove
  | JamArrangementSectionResize
  | JamArrangementTakeCapture
  | JamArrangementTakePromote
  // rack
  | JamRackMacroSet
  | JamRackPresetLoad
  | JamRackStateSave
  // mapping
  | JamMappingInstall
  | JamMappingUninstall
  | JamMappingFork
  // room
  | JamRoomPlayerJoin
  | JamRoomPlayerLeave
  | JamRoomBroadcastStatePatch;

/** All event family name strings, useful for exhaustive matching. */
export type JamEventFamily = JamEvent['family'];

```
