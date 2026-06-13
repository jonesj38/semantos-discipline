---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/jambox/web/src/racks/midi/cc-map.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.623359+00:00
---

# cartridges/jambox/web/src/racks/midi/cc-map.ts

```ts
/**
 * ExternalMidiRack — MIDI CC map for the 8 canonical macros.
 *
 * CC numbers follow the General MIDI 2 extended controller map,
 * choosing performance-safe CCs (not reserved for standard functions).
 *
 * These are the default assignments. A user can override per-device
 * via the Phase C mapping editor (jam.mapping).
 */

export interface MacroCcEntry {
  /** Macro index (0–7) */
  macroIndex: number;
  /** Canonical macro name */
  macroName: string;
  /** Default MIDI CC number */
  cc: number;
  /** Human-readable description of the CC assignment */
  description: string;
}

/**
 * Default CC map for the 8 canonical macros.
 * CC numbers 20–27 are "undefined" in GM spec — safe for custom use.
 */
export const MACRO_CC_MAP: MacroCcEntry[] = [
  { macroIndex: 0, macroName: 'brightness', cc: 20, description: 'Filter cutoff / spectral tilt' },
  { macroIndex: 1, macroName: 'dirt',       cc: 21, description: 'Drive / distortion / bitcrush' },
  { macroIndex: 2, macroName: 'wobble',     cc: 22, description: 'LFO depth / mod-wheel mirror (also CC 1)' },
  { macroIndex: 3, macroName: 'space',      cc: 23, description: 'Reverb send / room size' },
  { macroIndex: 4, macroName: 'snap',       cc: 24, description: 'Envelope attack / transient emphasis' },
  { macroIndex: 5, macroName: 'body',       cc: 25, description: 'Low-shelf gain / sub mix' },
  { macroIndex: 6, macroName: 'chaos',      cc: 26, description: 'Randomisation / stochastic source' },
  { macroIndex: 7, macroName: 'tension',    cc: 27, description: 'Filter resonance / sidechain depth' },
];

/** Look up the CC number for a macro index. Returns undefined if invalid. */
export function ccForMacro(macroIndex: number): number | undefined {
  return MACRO_CC_MAP[macroIndex]?.cc;
}

/** Look up the macro index for a CC number. Returns undefined if not in the map. */
export function macroForCc(cc: number): number | undefined {
  return MACRO_CC_MAP.find((e) => e.cc === cc)?.macroIndex;
}

/**
 * Convert a normalised macro value (0–1) to a MIDI CC value (0–127).
 */
export function normalToMidiValue(value: number): number {
  return Math.max(0, Math.min(127, Math.round(value * 127)));
}

/**
 * Convert a MIDI CC value (0–127) to a normalised macro value (0–1).
 */
export function midiValueToNormal(midiValue: number): number {
  return Math.max(0, Math.min(1, midiValue / 127));
}

```
