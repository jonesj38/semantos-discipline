---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/cdm/cdm/src/bridge/cdm-json.d.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.503873+00:00
---

# packages/cdm/cdm/src/bridge/cdm-json.d.ts

```ts
/**
 * CDM JSON Import/Export — maps between ISDA CDM JSON and Semantos CDMProduct.
 *
 * CDM JSON is an import/export format, NOT the source of truth.
 * The cell IS the product. CDM JSON is a view.
 *
 * Unknown fields in CDM JSON are preserved in _extensions for round-trip fidelity.
 *
 * Phase 28 / D28.5
 */
import { type CDMProduct, type CDMLifecycleEvent, type Result } from '../types';
/**
 * Import a CDM JSON object into a CDMProduct.
 * Unknown fields are preserved in _extensions.
 */
export declare function importProduct(json: Record<string, unknown>): Result<CDMProduct>;
/**
 * Export a CDMProduct to CDM JSON.
 * Round-trips _extensions back into the output.
 */
export declare function exportProduct(product: CDMProduct): Record<string, unknown>;
/** Import a CDM lifecycle event from JSON. */
export declare function importEvent(json: Record<string, unknown>): Result<CDMLifecycleEvent>;
/** Export a CDM lifecycle event to JSON. */
export declare function exportEvent(event: CDMLifecycleEvent): Record<string, unknown>;
//# sourceMappingURL=cdm-json.d.ts.map
```
