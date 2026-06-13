---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-poker-agent/src/shared/beef-codec.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.770624+00:00
---

# archive/apps-poker-agent/src/shared/beef-codec.ts

```ts
/**
 * BEEF codec — single source of truth for the conversion pattern
 * sprinkled across poker-state-machine.ts (7 inline copies):
 *
 *   const beefBytes = Array.isArray(x)
 *     ? x
 *     : Array.from(Buffer.from(x as string, 'hex'));
 *
 * The pattern handles two BEEF representations the wallet stack
 * passes around: raw `number[]` byte arrays (post-decode) and hex
 * strings (over-the-wire). Either form is accepted; output is always
 * a fresh `number[]`.
 *
 * Symmetric helpers:
 *
 *   - `toArray`     : Beef|number[]|hex → number[]
 *   - `fromArray`   : number[] → hex string
 *   - `isBeefArray` : type guard for `unknown` → `number[]`
 *   - `isHexBeef`   : type guard for `unknown` → `string` (hex)
 */

/** Anything the codec accepts as input. */
export type BeefInput = number[] | string;

/**
 * Normalize either a `number[]` or a hex string to `number[]`. The
 * input is **not** validated — passing garbage in will produce
 * garbage out. The pattern is meant to be a quick disambiguator
 * around the wallet API surface where both forms are legal.
 */
export function toArray(beef: BeefInput): number[] {
  return Array.isArray(beef) ? beef : Array.from(Buffer.from(beef, 'hex'));
}

/** Lossless inverse — `number[]` → hex string. */
export function fromArray(arr: number[]): string {
  return Buffer.from(arr).toString('hex');
}

export function isBeefArray(value: unknown): value is number[] {
  return Array.isArray(value);
}

export function isHexBeef(value: unknown): value is string {
  return typeof value === 'string' && /^[0-9a-fA-F]*$/.test(value);
}

```
