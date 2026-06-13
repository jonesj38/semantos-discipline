---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/extraction/src/inference/__tests__/cc6-1-canonical-bootstrap.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.466297+00:00
---

# packages/extraction/src/inference/__tests__/cc6-1-canonical-bootstrap.test.ts

```ts
/**
 * CC6.1 — Inference pipeline as the canonical adapter bootstrap.
 *
 * Per `docs/design/CC6-SOURCE-ADAPTER-IMPL-SPEC.md` v0.2 §3 row CC6.1:
 *
 *   > Ratify the inference pipeline as the canonical bootstrap: doc + a
 *   > conformance test asserting `infer()` yields an AFFINE draft (never
 *   > auto-published) for a fixture source.
 *
 * Operational invariant this test pins:
 *   - Every `InferenceAgent.infer()` execution produces an `InferredGrammar`
 *     cell with `linearity: 'AFFINE'` — never RELEVANT/LINEAR/FUNGIBLE.
 *   - The pipeline never auto-publishes: the `createObjectFromType` call
 *     passes the auto-publish flag as `false`, and the pipeline source
 *     contains no `transitionVisibility(*, 'published', *)` call inside
 *     `InferenceAgent.infer()`. Publication to canonical (`'published'`)
 *     visibility is an explicit operator-ratification action handled by
 *     the shell-handler (`shell-handlers/infer.ts`), gated by hatCaps —
 *     never by the inference pipeline.
 *
 * This is the substrate-AI boundary in test form (per
 * `CARTRIDGE-CANONICAL-SCHEMA-SPINE.md` §5 "intelligence at the edges,
 * none in the substrate"): the inference pipeline runs LLM-assisted
 * mapping (`mapTaxonomy`) but its output is always a *draft* that an
 * operator must ratify. This invariant must hold for `verb.dispatch`
 * configs-as-intents (CC6.2/CC6.3) to be the only path to canonical
 * adapter state.
 *
 * If this test ever fails, the inference pipeline has acquired an
 * auto-promotion path — that is a STOP-worthy regression of the
 * no-AI-in-substrate boundary, not an acceptable spec drift.
 */

import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { describe, expect, test } from 'bun:test';

import { INFERRED_GRAMMAR_TYPE } from '../pipeline';

const PIPELINE_PATH = resolve(
  dirname(fileURLToPath(import.meta.url)),
  '..',
  'pipeline.ts',
);

describe('CC6.1 — InferenceAgent is the canonical, AFFINE-only adapter bootstrap', () => {
  test('INFERRED_GRAMMAR_TYPE.linearity is AFFINE (typing invariant)', () => {
    // The type itself is bound to AFFINE — no inference output can have
    // a different linearity without first mutating this constant. That
    // is the static contract guaranteeing the substrate-AI boundary.
    expect(INFERRED_GRAMMAR_TYPE.linearity).toBe('AFFINE');
  });

  test('INFERRED_GRAMMAR_TYPE is named "InferredGrammar" (canonical type name)', () => {
    expect(INFERRED_GRAMMAR_TYPE.name).toBe('InferredGrammar');
  });

  test('pipeline.ts creates the inferred-grammar object with auto-publish = false', () => {
    // `store.createObjectFromType` accepts a trailing `published` boolean.
    // The pipeline MUST pass it as `false` — the cell starts as a draft,
    // never auto-promoted to canonical visibility.
    const src = readFileSync(PIPELINE_PATH, 'utf-8');
    expect(src).toContain(
      'createObjectFromType(INFERRED_GRAMMAR_TYPE, undefined, undefined, undefined, false)',
    );
  });

  test('pipeline.ts contains NO transitionVisibility(*, "published", *) call (no auto-promotion path)', () => {
    // Negative invariant: the inference pipeline must never reach into
    // visibility-promotion. That action belongs solely to the shell-handler
    // (`shell-handlers/infer.ts`), gated by hatCaps + the explicit
    // `--publish` flag. Any occurrence of the publication call inside
    // `pipeline.ts` is a regression of the substrate-AI boundary.
    const src = readFileSync(PIPELINE_PATH, 'utf-8');
    // Match `transitionVisibility(<anything>, 'published', <anything>)` —
    // both single- and double-quoted literals; either argument order is
    // also rejected for safety.
    expect(src).not.toMatch(/transitionVisibility\s*\([^)]*['"]published['"]/);
  });

  test('pipeline.ts uses status:"draft" for the freshly-inferred cell payload', () => {
    // Positive invariant: the cell's payload `status` field is set to
    // `'draft'`. Operator-ratification flips this to `'approved'` or
    // `'published'`; the pipeline MUST emit `'draft'`. This is a
    // belt-and-braces check alongside the auto-publish=false invariant.
    const src = readFileSync(PIPELINE_PATH, 'utf-8');
    expect(src).toMatch(/field:\s*['"]status['"][^}]*value:\s*['"]draft['"]/);
  });
});

```
