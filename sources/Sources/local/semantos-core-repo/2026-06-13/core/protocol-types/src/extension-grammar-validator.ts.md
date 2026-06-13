---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/extension-grammar-validator.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.851786+00:00
---

# core/protocol-types/src/extension-grammar-validator.ts

```ts
/**
 * @deprecated Import from `./grammar/grammar-validator` instead.
 *
 * Extension Grammar Validator — preserved as a re-export shim for
 * backwards compatibility after the prompt-43 split. The validator
 * was decomposed into per-section modules:
 *
 *   - `grammar/error-collector.ts`     ValidationErrorCollector
 *   - `grammar/validators/manifest.ts` top-level identity + migrations
 *   - `grammar/validators/verbs.ts`    source-protocol declaration
 *   - `grammar/validators/schemas.ts`  objectTypes / payload schemas
 *   - `grammar/validators/bindings.ts` entityMappings / fieldMappings
 *   - `grammar/validators/capabilities.ts`
 *   - `grammar/validators/policy.ts`   taxonomyExtensions
 *   - `grammar/validator-registry.ts`  ordered section dispatcher
 *   - `grammar/grammar-validator.ts`   orchestrator (public entry)
 *
 * This file will be removed once all downstream imports migrate.
 */

export { validateExtensionGrammar } from './grammar/grammar-validator';

```
