---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/betterment/brain/src/index.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.562907+00:00
---

# cartridges/betterment/brain/src/index.ts

```ts
/**
 * @semantos/betterment — personal practice cartridge brain layer.
 *
 * T7.a MVP per Todd's 2026-05-25 direction: "brain integration is light;
 * most interaction is in-app."  This module exposes:
 *
 *   - 8 practice cell-type validators (release, session, intention,
 *     insight, pattern, connection, vacuum, seal) for ratification-time
 *     payload check when the Flutter PWA mints a betterment.* cell.
 *   - The cartridge manifest re-export (capability + identity).
 *
 * Deferred from MVP (light brain integration):
 *   - state-machines/   — in-app holds practice state, brain just stores
 *   - surface-adapters/ — no inbound channels (sms/email/voice) for v0.1.0
 *   - intake-handler.ts — no external ingestion; the PWA mints directly
 *   - flow-runner.ts    — flows[] in cartridge.json are consumed in-app
 *                          by a generic Flutter FlowRunner widget (T7.b)
 *
 * Future (post-v0.1.0):
 *   - lexicon.ts        — SIR intent-grammar binding (the held-back
 *                          configs/taxonomy/consciousness.json content)
 *   - paskian.* + story.* + accountability.* + state.* cell validators
 *     when those cells start being minted (today they're declared in
 *     cartridge.json but only emitted by pask reduction)
 */

export * from './cell-types/index.js';
export { bettermentManifest, BETTERMENT_CAPABILITIES } from './manifest.js';
export { BettermentLexicon, type BettermentCategory } from './lexicon.js';

// Session FSM — pure state machine for full practice sessions.
// Deferred in v0.1.0 (brain integration is light); landed in v0.2.0
// as the conversation-native session conductor is wired.
export * from './session_fsm.js';

// Pask sweep — derive primed themes from recent practice history.
// Called between sessions (or by a scheduled brain endpoint) to
// inform the SCAN state without manual elevation entry.
export * from './pask_sweep.js';

// Transcript carriage — overflow a long release transcript across chained
// continuation cells, referenced from the canonical head cell's
// transcriptCarriageRef. Pure writer/reader over the protocol-types primitives.
export * from './carriage.js';

```
