---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/cdm/cdm/src/regulatory.d.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.494288+00:00
---

# packages/cdm/cdm/src/regulatory.d.ts

```ts
/**
 * Regulatory Report Generator — auto-generates RELEVANT cells for trade lifecycle events.
 *
 * Reports are RELEVANT linearity: they MUST be kept, CANNOT be destroyed.
 * The cell engine rejects consumption of RELEVANT cells at the opcode level.
 *
 * Each report references the source event cell, creating a verifiable audit trail.
 * UTI generation follows ISDA's identifier standards.
 *
 * Phase 28 / D28.3
 */
import { type CDMProduct, type CDMLifecycleEvent, type RegulatoryRegime, type RegulatoryReport } from './types';
export declare class RegulatoryReportGenerator {
    /**
     * Generate reports for a lifecycle event based on applicable regimes.
     * Returns one RELEVANT report cell per applicable regime.
     */
    generate(event: CDMLifecycleEvent, product: CDMProduct): RegulatoryReport[];
    /**
     * Determine which regulatory regimes apply based on party jurisdictions and currency.
     */
    applicableRegimes(product: CDMProduct): RegulatoryRegime[];
    /**
     * Format a report for a specific regime.
     * Returns a regime-specific field mapping for submission.
     */
    format(report: RegulatoryReport, regime: RegulatoryRegime): Record<string, unknown>;
    /**
     * Pack a regulatory report as a RELEVANT cell.
     * Returns the packed cell bytes.
     */
    packReportCell(report: RegulatoryReport): Uint8Array;
}
//# sourceMappingURL=regulatory.d.ts.map
```
