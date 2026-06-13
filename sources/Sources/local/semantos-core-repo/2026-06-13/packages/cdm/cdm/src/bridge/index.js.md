---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/cdm/cdm/src/bridge/index.js
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.501658+00:00
---

# packages/cdm/cdm/src/bridge/index.js

```js
/**
 * CDM Bridge — unified import/export for CDM JSON and FpML XML.
 *
 * Phase 28 / D28.5
 */
import { importProduct, exportProduct, importEvent, exportEvent } from './cdm-json';
import { importFpML, exportFpML } from './fpml';
export class CDMBridge {
    /** Import a CDM JSON product into a CDMProduct. */
    importProduct(cdmJson) {
        return importProduct(cdmJson);
    }
    /** Export a CDMProduct as CDM JSON. */
    exportProduct(product) {
        return exportProduct(product);
    }
    /** Import FpML XML into CDMProduct(s). */
    importFpML(fpmlXml) {
        return importFpML(fpmlXml);
    }
    /** Export CDMProduct(s) as FpML XML. */
    exportFpML(products) {
        return exportFpML(products);
    }
    /** Import a CDM lifecycle event from JSON. */
    importEvent(cdmEventJson) {
        return importEvent(cdmEventJson);
    }
    /** Export a CDM lifecycle event as JSON. */
    exportEvent(event) {
        return exportEvent(event);
    }
}
export { importProduct, exportProduct, importEvent, exportEvent } from './cdm-json';
export { importFpML, exportFpML } from './fpml';
//# sourceMappingURL=index.js.map
```
