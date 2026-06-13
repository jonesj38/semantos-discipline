---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/extraction/src/manifest-wrapper.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.452847+00:00
---

# packages/extraction/src/manifest-wrapper.ts

```ts
/**
 * G-6 — AFFINE manifest wrapper.
 *
 * Wraps a composed ExtensionGrammar in an ExtensionManifest with draft
 * governance defaults. All auto-generated grammars start AFFINE — promotion
 * to RELEVANT requires human review, gate test, and L1 ballot.
 *
 * The manifest is intentionally minimal: it carries only the fields needed
 * for the loader to recognise the extension and for the governance engine to
 * enforce the draft trust tier. Filesystem paths are set to conventional
 * defaults that the author fills in during human review.
 *
 * See docs/textbook/33-automated-grammar-synthesis.md §Stage 6 (Manifest)
 */

import type { ExtensionManifest } from '@semantos/protocol-types';
import type { ExtensionGrammar } from '@semantos/protocol-types';

// ---------------------------------------------------------------------------
// Options
// ---------------------------------------------------------------------------

export interface ManifestWrapOptions {
  /**
   * Author hat ID (stored in metadata). Defaults to 'auto' to indicate
   * the grammar was machine-generated and has not yet been claimed.
   */
  authorHat?: string;

  /**
   * Metadata to embed in the manifest (displayed in the extension browser).
   * All fields are optional — reviewers fill in before promotion.
   */
  metadata?: {
    icon?: string;
    description?: string;
    documentation?: string;
  };

  /**
   * Taxonomy path (relative) — defaults to 'taxonomy/auto.json'.
   * Reviewer renames during the human-review stage.
   */
  taxonomyPath?: string;

  /**
   * Flows directory — defaults to 'flows/'. Auto-generated grammars have
   * no flows yet; the directory is a placeholder for the reviewer.
   */
  flowsDir?: string;

  /**
   * Prompts directory — defaults to 'prompts/'. Same as flowsDir.
   */
  promptsDir?: string;

  /**
   * Objects directory — defaults to 'objects/'.
   */
  objectsDir?: string;
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

/**
 * Wrap a composed ExtensionGrammar in an AFFINE ExtensionManifest.
 *
 * The grammar's grammarId and displayName drive the manifest's id/name.
 * The governance config is set to the most conservative defaults:
 *   - patchAcceptancePolicy: 'author_only'
 *   - trustClass: 'cosmetic'
 *   - proofRequirement: 'none'
 *   - executionAuthority: 'local_facet'
 *
 * These defaults keep the manifest safely below every governance enforcement
 * threshold until a human reviewer explicitly relaxes them.
 */
export function wrapInManifest(
  grammar: ExtensionGrammar,
  options: ManifestWrapOptions = {},
): ExtensionManifest {
  const {
    authorHat = 'auto',
    metadata,
    taxonomyPath = 'taxonomy/auto.json',
    flowsDir = 'flows/',
    promptsDir = 'prompts/',
    objectsDir = 'objects/',
  } = options;

  const manifest: ExtensionManifest = {
    id: grammar.grammarId,
    name: grammar.displayName,
    version: grammar.grammarVersion,

    taxonomyPath,
    flowsDir,
    promptsDir,
    objectsDir,

    manifestLinearity: 'AFFINE',

    governanceConfig: {
      patchAcceptancePolicy: 'author_only',
      versionBumpRules: {
        major: 'contributor_ballot',
        minor: 'author_only',
        patch: 'author_only',
      },
      contributorHats: [],
      deprecationTimelineMinDays: 30,
      trustClass: 'cosmetic',
      proofRequirement: 'none',
      executionAuthority: 'local_facet',
    },

    grammar,

    metadata: {
      author: authorHat,
      ...metadata,
    },
  };

  return manifest;
}

// ---------------------------------------------------------------------------
// Serialise
// ---------------------------------------------------------------------------

/**
 * Serialise a manifest to the JSON string that would be written as
 * config.json in the extension directory.
 */
export function serialiseManifest(manifest: ExtensionManifest): string {
  return JSON.stringify(manifest, null, 2);
}

```
