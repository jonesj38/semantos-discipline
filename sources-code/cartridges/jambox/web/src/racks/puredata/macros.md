---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/jambox/web/src/racks/puredata/macros.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.625418+00:00
---

# PureDataRack — Macro Fan-out Table

Engine: `puredata`
Source: `src/racks/puredata/PureDataRack.ts`

The eight canonical macros are sent to PD as float messages to
`[r jam-macro-N]` receivers (1-based indexing).

| Index | Macro Name | PD Receiver | Value Range | Notes |
|-------|------------|-------------|-------------|-------|
| 0 | `brightness` | `[r jam-macro-1]` | 0–1 | Patch-defined; typically filter cutoff or spectral tilt |
| 1 | `dirt` | `[r jam-macro-2]` | 0–1 | Patch-defined; typically drive/wavefolder/bitcrush |
| 2 | `wobble` | `[r jam-macro-3]` | 0–1 | Patch-defined; typically LFO depth/rate |
| 3 | `space` | `[r jam-macro-4]` | 0–1 | Patch-defined; typically reverb send/size |
| 4 | `snap` | `[r jam-macro-5]` | 0–1 | Patch-defined; typically attack/transient |
| 5 | `body` | `[r jam-macro-6]` | 0–1 | Patch-defined; typically low-shelf gain/sub mix |
| 6 | `chaos` | `[r jam-macro-7]` | 0–1 | Patch-defined; typically randomisation seed |
| 7 | `tension` | `[r jam-macro-8]` | 0–1 | Patch-defined; typically filter resonance/sidechain depth |

## Fan-out rationale

PD patches are DSP black boxes; the exact fan-out of each macro is
**patch-defined**. The conventions document specifies the receiver names and
value ranges; each patch author documents the semantic mapping in their patch.

The macro names carry musical intent — patches SHOULD honour the intent
(e.g. `[r jam-macro-1]` controlling brightness means a filter cutoff or
spectral brightening operation). Misuse is technically possible but breaks
the room UX.

## Macro values are sent on every setMacro() call

When `rack.setMacro(index, value)` is called:
1. The value is clamped to [0, 1]
2. The value is stored in the rack's internal state
3. `[r jam-macro-{index+1}]` receives the float value

Initial macro values are also broadcast when a patch is first loaded.
