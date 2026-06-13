---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/betterment/brain/src/lexicon.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.562619+00:00
---

# cartridges/betterment/brain/src/lexicon.ts

```ts
/**
 * Betterment-lexicon re-export.
 *
 * The canonical lexicon value lives upstream in `@semantos/semantos-sir`
 * (alongside Trades, Tessera, BRAP, etc. per the CC0b registration
 * pattern). This module re-exports it for consumers who only pull in
 * `@semantos/betterment`.
 *
 * RENAME (2026-05-29 → completed 2026-06-03): cartridge previously
 * `@semantos/self`. The upstream registry in `core/semantos-sir` now
 * exports the lexicon under its canonical name `BettermentLexicon`
 * (the deferred upstream rename has landed), so this is a direct
 * re-export — no alias.
 *
 * Mirrors `cartridges/oddjobz/brain/src/lexicon.ts` — same one-line
 * shim pattern.
 */
export {
  BettermentLexicon,
  type BettermentCategory,
} from '@semantos/semantos-sir';

```
