---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-loom-react/src/stubs/extraction-browser.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.946666+00:00
---

# archive/apps-loom-react/src/stubs/extraction-browser.ts

```ts
/**
 * Browser stub for @semantos/extraction.
 *
 * The shell router imports from this package for the `infer` and `extract`
 * verbs, which are Node-only (they read grammar files from disk and run
 * inference agents). The browser build never dispatches those verbs, so
 * we export inert stubs that throw if accidentally invoked.
 */

export class InferenceAgent {
  constructor() {
    throw new Error('InferenceAgent is not available in the browser build');
  }
}

export class ExtractionPipeline {
  constructor() {
    throw new Error('ExtractionPipeline is not available in the browser build');
  }
}

```
