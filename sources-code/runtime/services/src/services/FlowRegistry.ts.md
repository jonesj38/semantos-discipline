---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/services/src/services/FlowRegistry.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.090560+00:00
---

# runtime/services/src/services/FlowRegistry.ts

```ts
/**
 * FlowRegistry — looks up conversation flows by intent and capabilities.
 *
 * Pure lookup functions (findFlow, listFlows) remain stateless.
 * New taxonomy functions delegate to the IntentTaxonomy singleton for
 * hierarchical intent resolution (Phase 13).
 */

import type { ConversationFlow, ExtensionConfig } from '../config/extensionConfig';
import { intentTaxonomy } from './IntentTaxonomy';
import type { IntentTaxonomyNode, TaxonomyConfig, FastPathEntry } from './IntentTaxonomy';

/**
 * Find a flow matching the given intent, checking that the hat has sufficient capabilities.
 *
 * Returns the first matching flow, or null if no match.
 */
export function findFlow(
  intent: string,
  facetCapabilities: number[],
  config: ExtensionConfig,
): ConversationFlow | null {
  if (!config.flows || config.flows.length === 0) return null;

  const capSet = new Set(facetCapabilities);

  for (const flow of config.flows) {
    if (!flow.triggerIntents.includes(intent)) continue;

    if (flow.requiredCapabilities) {
      const hasAll = flow.requiredCapabilities.every(cap => capSet.has(cap));
      if (!hasAll) continue;
    }

    return flow;
  }

  return null;
}

/** List all flows from a config. */
export function listFlows(config: ExtensionConfig): ConversationFlow[] {
  return config.flows ?? [];
}

// ── Taxonomy functions (Phase 13) ──────────────────────────

/**
 * Load core domain nodes into the taxonomy. Called once when core.json taxonomy is first loaded.
 */
export function loadCoreTaxonomy(nodes: IntentTaxonomyNode[]): void {
  intentTaxonomy.loadDomains(nodes);
}

/**
 * Register an extension's taxonomy subtree and flows into the intent taxonomy.
 *
 * @param taxonomyConfig - Parsed taxonomy JSON with extensionId and inject array
 * @param flows - The extension's conversation flows (used to build triggerIntent → flowId map)
 */
export function registerTaxonomy(
  taxonomyConfig: TaxonomyConfig,
  flows: ConversationFlow[],
): void {
  intentTaxonomy.registerExtension(taxonomyConfig.extensionId, taxonomyConfig.inject, flows);
}

/** Remove an extension's taxonomy registration. */
export function unregisterTaxonomy(extensionId: string): void {
  intentTaxonomy.unregisterExtension(extensionId);
}

/** Get taxonomy options at a given path in the assembled tree. */
export function getTaxonomyAt(path: string[]): IntentTaxonomyNode[] {
  return intentTaxonomy.getOptionsAt(path);
}

/**
 * Get the top-N fast-path intents across all registered extensions.
 * Used by the hierarchical classifier to build a single-call fast-path prompt.
 */
export function getFastPathIntents(n = 20): FastPathEntry[] {
  return intentTaxonomy.getFastPathIntents(n);
}

```
