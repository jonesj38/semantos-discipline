---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/services/src/services/config-store/intent-taxonomy-manager.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.113072+00:00
---

# runtime/services/src/services/config-store/intent-taxonomy-manager.ts

```ts
/**
 * Intent-taxonomy manager — loads the bundled taxonomy JSON for a
 * given extension and registers it with the runtime's IntentTaxonomy
 * singleton via the registrar port. Behaviour preserved 1:1 from the
 * pre-split monolith:
 *
 *   1. Load + apply the core domain nodes once.
 *   2. Unregister the previously active extension (if any).
 *   3. Always register the generic catch-all taxonomy.
 *   4. Register the extension-specific taxonomy if present.
 *
 * Errors are swallowed because intent classification has a flat-
 * fallback path; a missing taxonomy must not bring the shell down.
 */

import { get, set } from '@semantos/state';

import type { ExtensionConfig } from '../../config/extensionConfig';
import type { IntentTaxonomyNode, TaxonomyConfig } from '../IntentTaxonomy';
import {
  activeIntentTaxonomyExtensionAtom,
  coreTaxonomyLoadedAtom,
} from './atoms';
import {
  getBundledExtensions,
  getIntentTaxonomyRegistrar,
} from './ports';

export async function loadIntentTaxonomy(
  extensionId: string,
  config: ExtensionConfig,
): Promise<void> {
  try {
    const bundled = getBundledExtensions();
    const registrar = getIntentTaxonomyRegistrar();

    if (!get(coreTaxonomyLoadedAtom) && bundled.hasTaxonomy('core')) {
      const coreMod = await bundled.loadTaxonomy('core');
      const coreData = (coreMod as { default: { nodes: IntentTaxonomyNode[] } }).default;
      registrar.loadCoreTaxonomy(coreData.nodes);
      set(coreTaxonomyLoadedAtom, true);
    }

    const previous = get(activeIntentTaxonomyExtensionAtom);
    if (previous && previous !== extensionId) {
      registrar.unregisterTaxonomy(previous);
    }

    if (bundled.hasTaxonomy('generic')) {
      const genericMod = await bundled.loadTaxonomy('generic');
      const genericData = (genericMod as { default: TaxonomyConfig }).default;
      registrar.registerTaxonomy(genericData, config.flows ?? []);
    }

    if (bundled.hasTaxonomy(extensionId)) {
      const extensionMod = await bundled.loadTaxonomy(extensionId);
      const extensionData = (extensionMod as { default: TaxonomyConfig }).default;
      registrar.registerTaxonomy(extensionData, config.flows ?? []);
      set(activeIntentTaxonomyExtensionAtom, extensionId);
    } else {
      set(activeIntentTaxonomyExtensionAtom, null);
    }
  } catch {
    // Intent taxonomy is non-critical — swallow errors so the flat
    // classification fallback still works.
  }
}

```
