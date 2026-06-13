---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/jambox/web/src/racks/webaudio/macros.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.626701+00:00
---

# WebAudio Racks — Macro Fan-out Tables

Engine: `webaudio`
Sources: `src/racks/webaudio/{drum808,acid303,bassMono,polyKeys}.ts`

All four WebAudio racks use the same 8 canonical macro names.
Fan-out to audio.ts parameters differs per rack.

---

## Drum808Rack (`jam.rack.drum-808`)

Voices: kick / snare / hat / clap / cb / tom / sub / perc / shaker

| Index | Macro | audio.ts fan-out | Default |
|-------|-------|-----------------|---------|
| 0 | `brightness` | `setTrackFilter(hat/perc/shaker, 1000+v*17000)` — tone filter cutoff | 0.6 |
| 1 | `dirt` | `setTrackDrive(snare*0.8, hat*0.5, clap*0.6)` — waveshaper drive | 0.15 |
| 2 | `wobble` | reserved — routes to swing via sequencer hint | 0.0 |
| 3 | `space` | `setTrackReverb(snare*0.6, clap*0.7, tom*0.5)` — reverb send | 0.2 |
| 4 | `snap` | `setTrackDrive(kick*0.5, snare*0.3)` — punch/transient emphasis | 0.5 |
| 5 | `body` | `setTrackFilter(kick 60+v*140, sub 40+v*120)` — low-end shaping | 0.5 |
| 6 | `chaos` | hint-only — actual step probability randomisation in sequencer | 0.0 |
| 7 | `tension` | `setTrackSidechain(bass>0.5, lead>0.3)` — sidechain depth | 0.4 |

---

## Acid303Rack (`jam.rack.acid-303`)

Voices: acid lead (sawtooth with resonant 303-style filter envelope)

| Index | Macro | audio.ts fan-out | Default |
|-------|-------|-----------------|---------|
| 0 | `brightness` | `setTrackFilter(acid, 200+v*3800)` — filter cutoff multiplier | 0.5 |
| 1 | `dirt` | `setTrackDrive(acid, v*0.9)` — waveshaper drive | 0.1 |
| 2 | `wobble` | mod-wheel mirror — LFO depth hint for phase C mapping | 0.0 |
| 3 | `space` | `setTrackReverb(acid, v*0.5)` — reverb send | 0.1 |
| 4 | `snap` | attack duration `0.003 + (1-v)*0.017 s` — envelope character | 0.4 |
| 5 | `body` | `setEntityGain(acid, 0.4 + v*0.8)` — output level | 0.8 |
| 6 | `chaos` | slide probability `[0=never, 1=always]` — sequencer hint | 0.0 |
| 7 | `tension` | `setTrackFilter(resonance Q: 6+v*16)` — resonance + accent at >0.7 | 0.6 |

---

## BassMonoRack (`jam.rack.bass-mono`)

Voices: bass (monophonic synth)

| Index | Macro | audio.ts fan-out | Default |
|-------|-------|-----------------|---------|
| 0 | `brightness` | `setTrackFilter(bass, 60+v*3940)` — filter cutoff | 0.5 |
| 1 | `dirt` | `setTrackDrive(bass, v*0.7)` — saturation/drive | 0.1 |
| 2 | `wobble` | mod-wheel hint — LFO filter depth via phase C mapping | 0.0 |
| 3 | `space` | `setTrackReverb(bass, v*0.3)` — reverb send (subtle on bass) | 0.0 |
| 4 | `snap` | portamento/glide time `0.01 + (1-v)*0.19 s` | 0.5 |
| 5 | `body` | `setEntityGain(bass, 0.5 + v*0.7)` — output level | 0.85 |
| 6 | `chaos` | step probability nudge — sequencer hint | 0.0 |
| 7 | `tension` | `setTrackFilter(bass, resonance)` + sidechain duck depth | 0.3 |

---

## PolyKeysRack (`jam.rack.poly-keys`)

Voices: lead / keys / pad (polyphonic, up to 8 voices)

| Index | Macro | audio.ts fan-out | Default |
|-------|-------|-----------------|---------|
| 0 | `brightness` | `setTrackFilter(lead, 200+v*15800)` — filter cutoff | 0.7 |
| 1 | `dirt` | `setTrackDrive(lead, v*0.5)` — waveshaper amount | 0.05 |
| 2 | `wobble` | `setTrackDelay(lead, v*0.4)` + LFO depth hint | 0.0 |
| 3 | `space` | `setTrackReverb(lead, v*0.8)` — reverb send | 0.3 |
| 4 | `snap` | attack `0.002 + (1-v)*0.098 s` — envelope | 0.3 |
| 5 | `body` | `setEntityGain(lead, 0.4 + v*0.8)` — output level | 0.7 |
| 6 | `chaos` | step probability / arp randomisation hint | 0.0 |
| 7 | `tension` | `setTrackFilter(lead, resonance Q 1+v*12)` — tension build | 0.2 |

---

## Notes

- All macros accept values in [0, 1]; out-of-range values are clamped.
- Macro index is clamped to [0, 7] before application.
- `wobble` (index 2) and `chaos` (index 6) are "hint-only" for drum racks —
  they store the value but have no direct WebAudio fan-out, relying on phase C
  mappings to route them to sequencer parameters.
- Macro 7 (`tension`) drives sidechain in the drum rack (duck bass/lead on kick).
