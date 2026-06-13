---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/taxonomy-resolver.js
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.849568+00:00
---

# core/protocol-types/src/taxonomy-resolver.js

```js
/**
 * TaxonomyResolver — minimal interface for taxonomy path validation.
 *
 * Decouples SemanticFS (protocol-types) from IntentTaxonomy (workbench)
 * to avoid a circular package dependency. IntentTaxonomy structurally
 * satisfies this interface — no adapter code needed.
 *
 * Cross-references:
 *   workbench/src/services/IntentTaxonomy.ts  → concrete implementation
 *   proofs/lean/Semantos/Category.lean        → refines relation (prefix ordering)
 *   Phase 25C SemanticFS                      → consumer of this interface
 */
export {};
//# sourceMappingURL=taxonomy-resolver.js.map
```
