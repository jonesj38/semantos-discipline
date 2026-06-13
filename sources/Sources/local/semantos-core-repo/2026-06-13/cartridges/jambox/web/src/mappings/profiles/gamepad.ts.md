---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/jambox/web/src/mappings/profiles/gamepad.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.629569+00:00
---

# cartridges/jambox/web/src/mappings/profiles/gamepad.ts

```ts
/**
 * D-C.3 Gamepad built-in profile.
 *
 * Layout:
 *   Left stick (axis0, axis1)  = XY pad → rack macro 0/1 (brightness/dirt)
 *   Right stick (axis2, axis3) = XY pad → rack macro 2/3 (wobble/space)
 *   D-pad (btn12-15)          = mode nav (step/note/mix/session)
 *   Face buttons A/B/X/Y (btn0-3) = transport (play/stop/record/capture)
 *   Shoulders L1/R1 (btn4/5)  = scene launch prev/next
 *   Triggers L2/R2 (btn6/7)   = macro 6/7 (chaos/tension)
 *
 * Activates when a gamepad connects.
 */

import type { JamboxMappingPayload, MappingInput, MappingOutput } from '../../semantic/objects';

function stickInputs(): MappingInput[] {
  return [
    // Left stick X → brightness
    {
      type: 'gamepad-axis',
      selector: 'axis0',
      target: { kind: 'rack.macro', rackId: 'jam.rack.poly-keys', macro: 0 },
      transform: { kind: 'linear', min: 0, max: 1 },
    },
    // Left stick Y → dirt
    {
      type: 'gamepad-axis',
      selector: 'axis1',
      target: { kind: 'rack.macro', rackId: 'jam.rack.poly-keys', macro: 1 },
      transform: { kind: 'linear', min: 0, max: 1 },
    },
    // Right stick X → wobble
    {
      type: 'gamepad-axis',
      selector: 'axis2',
      target: { kind: 'rack.macro', rackId: 'jam.rack.poly-keys', macro: 2 },
      transform: { kind: 'linear', min: 0, max: 1 },
    },
    // Right stick Y → space
    {
      type: 'gamepad-axis',
      selector: 'axis3',
      target: { kind: 'rack.macro', rackId: 'jam.rack.poly-keys', macro: 3 },
      transform: { kind: 'linear', min: 0, max: 1 },
    },
  ];
}

function dpadInputs(): MappingInput[] {
  const modes: Array<import('../../semantic/objects').GridModeKind> = [
    'step', 'note', 'mix', 'session',
  ];
  return [
    { type: 'gamepad-button', selector: 'btn12', target: { kind: 'mode', mode: modes[0]! } },
    { type: 'gamepad-button', selector: 'btn13', target: { kind: 'mode', mode: modes[1]! } },
    { type: 'gamepad-button', selector: 'btn14', target: { kind: 'mode', mode: modes[2]! } },
    { type: 'gamepad-button', selector: 'btn15', target: { kind: 'mode', mode: modes[3]! } },
  ];
}

function faceButtonInputs(): MappingInput[] {
  return [
    { type: 'gamepad-button', selector: 'btn0', target: { kind: 'transport', verb: 'play' } },
    { type: 'gamepad-button', selector: 'btn1', target: { kind: 'transport', verb: 'stop' } },
    { type: 'gamepad-button', selector: 'btn2', target: { kind: 'transport', verb: 'record' } },
    { type: 'gamepad-button', selector: 'btn3', target: { kind: 'transport', verb: 'capture' } },
  ];
}

function shoulderInputs(): MappingInput[] {
  return [
    { type: 'gamepad-button', selector: 'btn4', target: { kind: 'scene.launch', sceneId: 'scene-prev' } },
    { type: 'gamepad-button', selector: 'btn5', target: { kind: 'scene.launch', sceneId: 'scene-next' } },
    {
      type: 'gamepad-button',
      selector: 'btn6',
      target: { kind: 'rack.macro', rackId: 'jam.rack.poly-keys', macro: 6 },
      transform: { kind: 'linear', min: 0, max: 1 },
    },
    {
      type: 'gamepad-button',
      selector: 'btn7',
      target: { kind: 'rack.macro', rackId: 'jam.rack.poly-keys', macro: 7 },
      transform: { kind: 'linear', min: 0, max: 1 },
    },
  ];
}

function hapticOutputs(): MappingOutput[] {
  return [
    { type: 'haptic', selector: 'transport.state', source: 'transport.state', projection: 'pulse' },
  ];
}

export const GAMEPAD_PROFILE: JamboxMappingPayload = {
  name: 'Gamepad',
  author: 'semantos-built-in',
  surfaceShape: 'gamepad',
  inputs: [
    ...stickInputs(),
    ...dpadInputs(),
    ...faceButtonInputs(),
    ...shoulderInputs(),
  ],
  outputs: hapticOutputs(),
  version: '1.0.0',
  license: 'personal',
};

```
