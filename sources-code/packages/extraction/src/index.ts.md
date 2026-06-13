---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/extraction/src/index.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.451754+00:00
---

# packages/extraction/src/index.ts

```ts
/**
 * @semantos/extraction
 *
 * Semantic extraction pipeline — five-stage flow for turning
 * Extension Grammar declarations into semantic objects:
 *   Fetch → Parse → Typecheck → Infer → Commit
 */

export * from './stages';
export * from './context';
export * from './evidence';
export { selectFetchAdapter, type FetchAdapter } from './fetch/adapter';
export { RestFetchAdapter } from './fetch/rest';
export { GraphQLFetchAdapter } from './fetch/graphql';
export { FileFetchAdapter } from './fetch/file';
export { StubFetchAdapter, createStubResponse } from './fetch/stub';
export { applyTransform, resolveNestedField, extractRecordsFromResponse } from './transforms';
export { parseResponses, findEntityMapping } from './parse';
export { typecheckRecords, findObjectType, isValidTaxonomyPath } from './typecheck';
export { inferRecords } from './infer';
export { commitRecords, buildSourceKey } from './commit';
export { ExtractionPipeline, type ProgressCallback, type ProgressEvent } from './pipeline';

// ── Governance (Phase 36D) ──
export * from './governance/index';

// ── Schema Inference (Phase 36C) ──
export * from './inference/index';

// ── Grammar Automation (Workstream G) ──
export { autoGrammar } from './auto-grammar';
export type { AutoGrammarOptions, AutoGrammarResult } from './auto-grammar';
export { wrapInManifest, serialiseManifest } from './manifest-wrapper';
export type { ManifestWrapOptions } from './manifest-wrapper';

```
