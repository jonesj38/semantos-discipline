---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/jambox/web/src/racks/midi/macros.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.623965+00:00
---

# ExternalMidiRack — Macro Fan-out Table

Engine: `midi`
Source: `src/racks/midi/ExternalMidiRack.ts`
CC Map: `src/racks/midi/cc-map.ts`

The eight canonical macros map to MIDI CC numbers. The default
assignments use GM "undefined" CC range (20–27) to avoid conflicts
with standard controller assignments.

| Index | Macro Name | Default CC | MIDI Range | Notes |
|-------|------------|-----------|------------|-------|
| 0 | `brightness` | CC 20 | 0–127 | Filter cutoff / spectral tilt |
| 1 | `dirt` | CC 21 | 0–127 | Drive / distortion / bitcrush |
| 2 | `wobble` | CC 22 | 0–127 | LFO depth / mod-wheel mirror |
| 3 | `space` | CC 23 | 0–127 | Reverb send / room size |
| 4 | `snap` | CC 24 | 0–127 | Envelope attack / transient |
| 5 | `body` | CC 25 | 0–127 | Low-shelf gain / sub mix |
| 6 | `chaos` | CC 26 | 0–127 | Randomisation seed |
| 7 | `tension` | CC 27 | 0–127 | Filter resonance / sidechain depth |

## Value conversion

Normalised macro values (0–1) are converted to MIDI CC values (0–127)
by `normalToMidiValue(value) = Math.round(value * 127)`.

Incoming CC feedback (SysEx or CC echo) is converted back via
`midiValueToNormal(midiValue) = midiValue / 127`.

## Note events

- `play(JamNoteOn)` → sends `0x9{ch} pitch velocity`
- `play(JamTrigger)` → maps voice name to GM drum pitch, sends note-on + auto note-off after 20 ms
- `stop(JamNoteOff)` → sends `0x8{ch} pitch 0`
- `stop(JamStop{reason:'panic'})` → sends note-off for all active voices + CC 123 (All Notes Off) + CC 120 (All Sound Off) + STOP

## MIDI Clock

When `sendClock: true` (default), the rack derives MIDI clock from
BEAMClock ticks and sends MIDI clock bytes (0xF8) at 24 ppq.
A MIDI START (0xFA) byte is sent at beat 0/1. A MIDI STOP (0xFC) byte
is sent on panic stop.

The rack NEVER authors its own tempo — BEAMClock is the clock authority.

## Meter no-op

`getMeters()` always returns `{ peakL: 0, peakR: 0, rmsL: 0, rmsR: 0 }`.
External MIDI devices do not report audio levels to the host browser.
The conformance harness runs with `{ skipMeters: true }` for this rack.

## Drum voice → MIDI pitch map

| Voice | MIDI Pitch | GM Name |
|-------|-----------|---------|
| kick | 36 | Bass Drum 1 |
| snare | 38 | Acoustic Snare |
| hat | 42 | Closed Hi-Hat |
| clap | 39 | Hand Clap |
| cb | 56 | Cowbell |
| tom | 45 | Low Tom |
| sub | 35 | Bass Drum 2 |
| perc | 60 | Hi Bongo |
| shaker | 70 | Maracas |
