---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/cdm/cdm/src/bridge/index.d.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.502990+00:00
---

# packages/cdm/cdm/src/bridge/index.d.ts

```ts
/**
 * CDM Bridge — unified import/export for CDM JSON and FpML XML.
 *
 * Phase 28 / D28.5
 */
import type { CDMProduct, CDMLifecycleEvent, Result } from '../types';
export declare class CDMBridge {
    /** Import a CDM JSON product into a CDMProduct. */
    importProduct(cdmJson: Record<string, unknown>): Result<CDMProduct>;
    /** Export a CDMProduct as CDM JSON. */
    exportProduct(product: CDMProduct): Record<string, unknown>;
    /** Import FpML XML into CDMProduct(s). */
    importFpML(fpmlXml: string): Result<CDMProduct[]>;
    /** Export CDMProduct(s) as FpML XML. */
    exportFpML(products: CDMProduct[]): string;
    /** Import a CDM lifecycle event from JSON. */
    importEvent(cdmEventJson: Record<string, unknown>): Result<CDMLifecycleEvent>;
    /** Export a CDM lifecycle event as JSON. */
    exportEvent(event: CDMLifecycleEvent): Record<string, unknown>;
}
export { importProduct, exportProduct, importEvent, exportEvent } from './cdm-json';
export { importFpML, exportFpML } from './fpml';
//# sourceMappingURL=index.d.ts.map
```
