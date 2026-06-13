---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/cdm/cdm/src/bridge/index.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.502316+00:00
---

# packages/cdm/cdm/src/bridge/index.ts

```ts
/**
 * CDM Bridge — unified import/export for CDM JSON and FpML XML.
 *
 * Phase 28 / D28.5
 */

import type { CDMProduct, CDMLifecycleEvent, Result } from '../types';
import { importProduct, exportProduct, importEvent, exportEvent } from './cdm-json';
import { importFpML, exportFpML } from './fpml';

export class CDMBridge {
  /** Import a CDM JSON product into a CDMProduct. */
  importProduct(cdmJson: Record<string, unknown>): Result<CDMProduct> {
    return importProduct(cdmJson);
  }

  /** Export a CDMProduct as CDM JSON. */
  exportProduct(product: CDMProduct): Record<string, unknown> {
    return exportProduct(product);
  }

  /** Import FpML XML into CDMProduct(s). */
  importFpML(fpmlXml: string): Result<CDMProduct[]> {
    return importFpML(fpmlXml);
  }

  /** Export CDMProduct(s) as FpML XML. */
  exportFpML(products: CDMProduct[]): string {
    return exportFpML(products);
  }

  /** Import a CDM lifecycle event from JSON. */
  importEvent(cdmEventJson: Record<string, unknown>): Result<CDMLifecycleEvent> {
    return importEvent(cdmEventJson);
  }

  /** Export a CDM lifecycle event as JSON. */
  exportEvent(event: CDMLifecycleEvent): Record<string, unknown> {
    return exportEvent(event);
  }
}

export { importProduct, exportProduct, importEvent, exportEvent } from './cdm-json';
export { importFpML, exportFpML } from './fpml';

```
