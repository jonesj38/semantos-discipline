---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/jambox/web/src/racks/strudel/macros.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.624318+00:00
---

# StrudelRack — Macro Fan-out Table

Engine: `strudel`
Source: `src/racks/strudel/StrudelRack.ts`

The eight canonical macro names and their Strudel transform fan-out.
Macros are applied as method-chain suffixes to the base pattern string
at compile-time. BEAMClock is the clock authority; this rack never
authors clock.

| Index | Macro Name | Strudel Transform | Range | Notes |
|-------|------------|-------------------|-------|-------|
| 0 | `brightness` | `.lpf(freq)` | freq 500–18000 Hz | Low-pass filter; 0=dark, 1=bright |
| 1 | `dirt` | `.coarse(n).shape(x)` | coarse 1–16, shape 0–1 | Bit-reduction + waveshaper; 0=clean, 1=destroyed |
| 2 | `wobble` | `.lfo(rate)` | rate 0–8 Hz | LFO envelope-mod depth; 0=static, 1=fast wobble |
| 3 | `space` | `.room(x)` | x 0–1 | Reverb room size/send; 0=dry, 1=drowned |
| 4 | `snap` | `.attack(t)` | t 0–0.1 s | Envelope attack; 0=percussive (attack(0)), 1=soft |
| 5 | `body` | `.gain(g)` | g 0.3–1.5 | Output gain / low-shelf analogue; 0=thin, 1=full |
| 6 | `chaos` | `.degradeBy(x)` + `.jux(rev)` | x 0–0.8 | Random step drop-out; above 0.5 also applies jux(rev) |
| 7 | `tension` | `.lpf(↘).hpf(↗)` | blend 0–1 | Dual-filter squeeze: 0=full spectrum, 1=narrow band |

## Usage example

```js
// In the StrudelRack the pattern string is assembled as:
// basePattern + .lpf(x) + .coarse(n).shape(x) + ...
// The result is passed to strudel.evaluate() on each macro change.

rack.setPattern('s("bd sd hh hh").fast(2)');
rack.setMacro(0, 0.8); // brightness → .lpf(14500)
rack.setMacro(3, 0.4); // space      → .room(0.40)
rack.setMacro(6, 0.6); // chaos      → .degradeBy(0.48).jux(rev)
```

## Clock contract

`StrudelRack.onClockTick(BeatInfo)` must be wired to the `BEAMClock.onBeat`
callback. The rack queries `pattern.queryArc(beat, beat+1)` on each tick
and forwards events to the Strudel runtime. It never sets BPM internally.
