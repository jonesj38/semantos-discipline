---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/jambox/web/src/racks/puredata/conventions.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.625125+00:00
---

# PureDataRack — Receiver/Sender Naming Convention

Engine: `puredata`
Source: `src/racks/puredata/PureDataRack.ts`

## Required Receivers

Every PD patch loaded via `PureDataRack.loadPatch()` **must** declare all
of the following receivers. Patches that are missing any receiver will fail
to load with a descriptive error that lists the missing names.

| PD Receiver | Message Format | Description |
|-------------|---------------|-------------|
| `[r jam-note]` | `pitch velocity on/off` | Note on (on=1) or note off (on=0). Pitch 0–127, velocity 0–127 |
| `[r jam-trigger]` | `voiceId velocity` | Drum/percussive trigger. voiceId is a string (e.g. "kick"). velocity 0–1 |
| `[r jam-clock]` | `bpm beat bar` | BEAMClock tick. bpm is float, beat/bar are integers. Slave your transport to this. |
| `[r jam-macro-1]` | `value` | Macro 0 (brightness). value 0–1 |
| `[r jam-macro-2]` | `value` | Macro 1 (dirt). value 0–1 |
| `[r jam-macro-3]` | `value` | Macro 2 (wobble). value 0–1 |
| `[r jam-macro-4]` | `value` | Macro 3 (space). value 0–1 |
| `[r jam-macro-5]` | `value` | Macro 4 (snap). value 0–1 |
| `[r jam-macro-6]` | `value` | Macro 5 (body). value 0–1 |
| `[r jam-macro-7]` | `value` | Macro 6 (chaos). value 0–1 |
| `[r jam-macro-8]` | `value` | Macro 7 (tension). value 0–1 |

Note: macro receivers use 1-based indexing (1–8) to match PD naming conventions.

## Optional Senders

Patches may send back any messages. The following senders are recognised
by the PureDataRack for telemetry and captureToPattern:

| PD Sender | Message Format | Description |
|-----------|---------------|-------------|
| `[s jam-out-note]` | `pitch velocity` | Emitted note events (captured for playback) |
| `[s jam-out-level]` | `peakL peakR rmsL rmsR` | Audio level metering |

## Transport Selection

The rack selects a transport per-instance based on patch size:

- `declaredPatchBytes < 1 MB` → **in-browser** (libpd-wasm, lazy loaded)
- `declaredPatchBytes >= 1 MB` → **remote** (WebSocket/OSC to bridge daemon at `ws://localhost:5182/pd`)

Override the transport by passing `transport: 'in-browser' | 'remote'` in the constructor config.

## Bridge (Remote Transport)

The remote transport uses the existing `bridge.ts` daemon, extended to handle
PD WebSocket connections. **No second bridge daemon.** The bridge listens on
`ws://localhost:5182/pd` for OSC-over-WebSocket messages.

OSC address format: `/pd/{receiver}` — e.g. `/pd/jam-note`, `/pd/jam-macro-1`.

Start the bridge: `bun run bridge`

## Macro Mapping

The eight canonical macros are sent to PD as float values via `[r jam-macro-N]`:

| Index | Macro | PD Receiver |
|-------|-------|-------------|
| 0 | brightness | `[r jam-macro-1]` |
| 1 | dirt | `[r jam-macro-2]` |
| 2 | wobble | `[r jam-macro-3]` |
| 3 | space | `[r jam-macro-4]` |
| 4 | snap | `[r jam-macro-5]` |
| 5 | body | `[r jam-macro-6]` |
| 6 | chaos | `[r jam-macro-7]` |
| 7 | tension | `[r jam-macro-8]` |

## Example Patch Fragment

```
[r jam-note]   → [unpack f f f]  → [osc~ 440]
[r jam-clock]  → [unpack f f f]  → use first atom as BPM
[r jam-macro-1] → multiply by 18000 → [bp~ 440] frequency
[s jam-out-note] emit to room after note events
```

## Clock Contract

The PD patch must **slave** to `[r jam-clock]`. It must NOT use `[metro]`
with an independent tempo — the BEAMClock is the room's clock authority.
