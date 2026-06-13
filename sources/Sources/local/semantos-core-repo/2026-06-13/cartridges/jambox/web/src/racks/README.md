---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/jambox/web/src/racks/README.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.612170+00:00
---

# JamRack — Starter Racks and How to Add a Fifth

## What is a JamRack?

A `JamRack` is the unified instrument contract for the jam-room. Every engine
(WebAudio, Strudel, PureData, MIDI) exposes the same five verbs:

```ts
play(event: JamNoteOn | JamTrigger): void
stop(event: JamNoteOff | JamStop): void
setMacro(index: number, value: number): void  // 0..7, 0..1
setPreset(presetId: string): void
getState(): JamRackState
setState(state: JamRackState): void
getMeters(): JamMeters
getMappingHints(): JamMappingHint[]
```

See `contract.ts` for the full interface definition.

---

## The Four Starter Racks

All four starter racks wrap existing `audio.ts` functions — no new audio code.

### `jam.rack.drum-808` — `webaudio/drum808.ts`

Voices: kick / snare / hat / clap / cb / tom / sub / perc / shaker

Trigger via `JamTrigger` events with `voiceId` set to the drum voice name.
Can also receive `JamNoteOn` events where pitch maps to voice by index.

Macro fan-out:
| # | Name       | Routes to                                     |
|---|------------|-----------------------------------------------|
| 0 | brightness | hat/perc/shaker tone filter cutoff            |
| 1 | dirt       | drive on snare/hat/clap                       |
| 2 | wobble     | (reserved for swing hint to sequencer)        |
| 3 | space      | reverb send on snare/clap/tom                 |
| 4 | snap       | drive-based punch on kick/snare               |
| 5 | body       | filter on kick/sub for low-end shaping        |
| 6 | chaos      | (hint; actual randomisation in sequencer)     |
| 7 | tension    | sidechain duck from kick on bass/lead         |

---

### `jam.rack.acid-303` — `webaudio/acid303.ts`

Voice: acid lead (sawtooth + resonant LP filter with 303-style envelope)

Play via `JamNoteOn` events with MIDI pitch. Slide probability and accent
character are driven by macros 6 (chaos) and 7 (tension).

Macro fan-out:
| # | Name       | Routes to                                     |
|---|------------|-----------------------------------------------|
| 0 | brightness | filter cutoff base frequency                  |
| 1 | dirt       | waveshaper drive on acid track bus            |
| 2 | wobble     | (hint: LFO depth for filter mod, phase C)     |
| 3 | space      | reverb send                                   |
| 4 | snap       | attack character (accent envelope)            |
| 5 | body       | output level shaping                          |
| 6 | chaos      | slide probability (0=never, 1=always slide)   |
| 7 | tension    | resonance Q + accent trigger at > 0.7         |

---

### `jam.rack.bass-mono` — `webaudio/bassMono.ts`

Voice: monophonic bass (routed through 'bass' track bus)

Supports all SynthVoice types (saw/fm/square/pulse/sub/epiano/pad).
Call `setVoice()` or use `setPreset('deep-sub' | 'moog-square' | 'fm-bass')`.

Macro fan-out:
| # | Name       | Routes to                                     |
|---|------------|-----------------------------------------------|
| 0 | brightness | filter cutoff                                 |
| 1 | dirt       | drive + bitcrush on bass track                |
| 2 | wobble     | (hint: LFO filter mod depth, phase C)         |
| 3 | space      | reverb send                                   |
| 4 | snap       | (attack shaping; used in note duration)       |
| 5 | body       | filter boost for sub presence                 |
| 6 | chaos      | (hint; random semitone drift)                 |
| 7 | tension    | sidechain duck from kick                      |

---

### `jam.rack.poly-keys` — `webaudio/polyKeys.ts`

Voices: lead + keys (polyphonic; all SynthVoice types)

Play via `JamNoteOn`. Polyphonic — multiple notes can ring simultaneously.
Presets: `'saw-lead' | 'fm-bell' | 'epiano' | 'lush-pad' | 'pulse-arp' | 'square-lead'`.

Macro fan-out:
| # | Name       | Routes to                                     |
|---|------------|-----------------------------------------------|
| 0 | brightness | filter cutoff                                 |
| 1 | dirt       | drive on lead track                           |
| 2 | wobble     | (hint: LFO filter mod, phase C)               |
| 3 | space      | reverb + delay send (delay at > 0.7)          |
| 4 | snap       | (attack shaping; used in note duration)       |
| 5 | body       | (voice blend hint)                            |
| 6 | chaos      | (hint: random detune)                         |
| 7 | tension    | sidechain duck from kick                      |

---

## How to Add a Fifth Rack

1. Create a new file in `src/racks/webaudio/` (or `src/racks/strudel/`, etc.):

```ts
// src/racks/webaudio/myRack.ts
import type { JamRack, JamNoteOn, JamTrigger, /* ... */ } from '../contract';
import { rackRegistry } from '../registry';

export class MyRack implements JamRack {
  readonly id = 'jam.rack.my-rack';       // unique stable id
  readonly name = 'My Rack';
  readonly engine = 'webaudio' as const;  // or strudel, puredata, midi, hybrid

  // ... implement the 8 methods from contract.ts
  // macros MUST use canonical names: brightness / dirt / wobble / space /
  //                                  snap / body / chaos / tension

  constructor() {
    rackRegistry.register(this);  // auto-registers on construction
  }
}
```

2. Add a `createRack` call in `src/semantic/objects.ts` (or your init code):

```ts
createRack({
  ownerIdentity: 'my-identity',
  rackId: 'jam.rack.my-rack',
  name: 'My Rack',
  engine: 'webaudio',
})
```

3. Write a structural type-check test (copy from `__tests__/phase-a-gate.test.ts`).

4. The macro names are the contract. Phases C (mapping editor) and D (Strudel/PureData)
   both rely on `brightness / dirt / wobble / space / snap / body / chaos / tension`
   being meaningful and stable. Map your internal parameters to these names.

---

## Macro Vocabulary Reference

```
0  brightness   high-shelf gain | filter cutoff       | spectral tilt
1  dirt         drive | bitcrush | saturator          | wavefolder
2  wobble       LFO depth | filter mod | rate stir    | mod-wheel mirror
3  space        reverb send | early-reflection time   | size
4  snap         envelope attack ↘ | transient gain ↗
5  body         low-shelf gain | sub mix | compressor make-up
6  chaos        constrained random source for the rack
7  tension      filter ↘ + resonance ↗ + sidechain ↗ + pitch drift
```
