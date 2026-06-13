---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/src/types/semantic-objects.js
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.399297+00:00
---

# src/types/semantic-objects.js

```js
/**
 * Semantic Object Type System
 *
 * The core innovation of Plexus: a classification system that enforces
 * consumption rules on stored cryptographic objects.
 */
/**
 * SemanticType enum classifies objects by their consumption semantics.
 */
export var SemanticType;
(function (SemanticType) {
    /** Must be consumed exactly once. No reuse. */
    SemanticType["LINEAR"] = "LINEAR";
    /** Can be consumed (acknowledged) or discarded. Optional consumption. */
    SemanticType["AFFINE"] = "AFFINE";
    /** Always accessible, never consumed, can be revoked separately. */
    SemanticType["RELEVANT"] = "RELEVANT";
})(SemanticType || (SemanticType = {}));
/**
 * Type guard: Check if object is LINEAR.
 */
export function isLinear(obj) {
    return obj.semanticType === SemanticType.LINEAR;
}
/**
 * Type guard: Check if object is AFFINE.
 */
export function isAffine(obj) {
    return obj.semanticType === SemanticType.AFFINE;
}
/**
 * Type guard: Check if object is RELEVANT.
 */
export function isRelevant(obj) {
    return obj.semanticType === SemanticType.RELEVANT;
}
//# sourceMappingURL=semantic-objects.js.map
```
