---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/cdm/cdm/src/bridge/fpml.d.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.502652+00:00
---

# packages/cdm/cdm/src/bridge/fpml.d.ts

```ts
/**
 * FpML Import/Export — maps between FpML XML (subset) and Semantos CDMProduct.
 *
 * Supports vanilla products only:
 * - Interest Rate Swaps (<swap>)
 * - Single-Name CDS (<creditDefaultSwap>)
 * - Deliverable FX Forwards (<fxSingleLeg>)
 *
 * Uses string-based extraction — no external XML dependency.
 *
 * Phase 28 / D28.5
 */
import { type CDMProduct, type Result } from '../types';
/**
 * Import FpML XML into CDMProduct(s).
 * Supports: <swap>, <creditDefaultSwap>, <fxSingleLeg>
 */
export declare function importFpML(xml: string): Result<CDMProduct[]>;
/**
 * Export CDMProduct(s) to FpML XML.
 * Only supports vanilla IRS, CDS, and FX forwards.
 */
export declare function exportFpML(products: CDMProduct[]): string;
//# sourceMappingURL=fpml.d.ts.map
```
