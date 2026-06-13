---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/scg/brain/src/manifest.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.557196+00:00
---

# cartridges/scg/brain/src/manifest.ts

```ts
/**
 * SCG extension manifest (RM-021).
 *
 * The cartridge-registry-shaped record that the boot path (or test
 * harness) registers via
 * `cartridgeRegistry.register(loadCartridge({ manifest: scgManifest, … }))`.
 *
 * Production signing identity comes from RM-005 (deferred — no real
 * RBS cert yet). Test/dev environments register without an authority
 * via `StubAuthorityVerifier`. When RM-005 lands, this manifest gets
 * paired with a real `LexiconAuthority` cert + grammar signature.
 */
import { scgGrammar } from './grammar.js';

export interface ScgManifest {
  readonly id: 'scg';
  readonly version: string;
  readonly description: string;
  /** Reference to the grammar artefact (kept on the manifest for
   *  symmetry with how oddjobz exposes its FSM tables). */
  readonly grammarId: typeof scgGrammar.grammarId;
  readonly grammarVersion: string;
  /** RM-021 / §3.6 — when the conversation hook lifts into
   *  `core/conversation-graph` more fully, this is the slot to
   *  declare hooks the cartridge contributes. RM-031a ships only the
   *  generic `autoEmitReplyRelation` helper; cartridge-declared hooks
   *  are an RM-031b concern. */
  readonly conversationHooks: 'auto-emit-reply-relation';
}

export const scgManifest: ScgManifest = Object.freeze({
  id: 'scg',
  version: '0.1.0',
  description:
    'Semantos Conversation Graph extension — typed conversation-graph entities and capabilities for substrate-level discourse moves.',
  grammarId: scgGrammar.grammarId,
  grammarVersion: scgGrammar.grammarVersion,
  conversationHooks: 'auto-emit-reply-relation',
});

```
