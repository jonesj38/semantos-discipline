---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/services/src/services/IntentTaxonomy.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.096154+00:00
---

# runtime/services/src/services/IntentTaxonomy.ts

```ts
/**
 * IntentTaxonomy — hierarchical intent registry assembled from extension configs.
 *
 * The SNS type path and the intent path are the same tree. Registering an extension's
 * object types automatically registers its classifiable intents. No dual maintenance.
 *
 * Domains (level 1) come from configs/taxonomy/core.json and are always present.
 * Extensions inject subtrees under specific domains. The fast-path map enables O(1)
 * lookup of known triggerIntents without any LLM call.
 */

import type { ConversationFlow } from '../config/extensionConfig';

/** A node in the intent taxonomy tree. */
export interface IntentTaxonomyNode {
  /** Segment id, e.g. "create", "job", "carpentry" */
  id: string;
  /** Human-readable label for LLM prompts */
  label: string;
  /** Description that helps the LLM classify correctly */
  description: string;
  /** Sub-nodes (absent or empty at leaves) */
  children?: IntentTaxonomyNode[];
  /** Flow IDs triggered at this leaf */
  flowIds?: string[];
  /** Example user utterances that map to this node */
  examples?: string[];
}

/** An extension's taxonomy injection — nodes to merge under a domain parent. */
export interface TaxonomyInjection {
  parentId: string;
  nodes: IntentTaxonomyNode[];
}

/** Parsed taxonomy config file for an extension. */
export interface TaxonomyConfig {
  extensionId: string;
  inject: TaxonomyInjection[];
}

/** Fast-path entry: maps a triggerIntent string to its node and flow. */
export interface FastPathEntry {
  intent: string;
  nodeId: string;
  flowId: string;
  examples: string[];
}

/**
 * IntentTaxonomy — the assembled taxonomy tree from all loaded extensions.
 *
 * Thread-safe for single-threaded JS. All mutations are synchronous.
 */
export class IntentTaxonomy {
  /** Level-1 domain nodes (create, navigate, query, etc.) */
  private domains: IntentTaxonomyNode[] = [];

  /** Extension registrations: extensionId → injections + flows */
  private extensionRegistrations = new Map<
    string,
    { injections: TaxonomyInjection[]; flows: ConversationFlow[] }
  >();

  /** Fast-path map: triggerIntent string → { nodeId, flowId } */
  private triggerIntentMap = new Map<string, { nodeId: string; flowId: string }>();

  /** Assembled tree (domains + injected extension nodes). Rebuilt on register/unregister. */
  private assembledDomains: IntentTaxonomyNode[] = [];

  /**
   * Load the core domain nodes. Called once when core.json taxonomy is loaded.
   * These are the level-1 options: create, navigate, query, consume, inspect, govern, demo, transition.
   */
  loadDomains(nodes: IntentTaxonomyNode[]): void {
    this.domains = nodes.map(n => deepCloneNode(n));
    this.rebuild();
  }

  /**
   * Register an extension's taxonomy subtree and flows.
   * Merges the extension's nodes under the specified domain parents.
   * Rebuilds the fast-path map from all registered flows.
   */
  registerExtension(
    extensionId: string,
    injections: TaxonomyInjection[],
    flows: ConversationFlow[],
  ): void {
    this.extensionRegistrations.set(extensionId, { injections, flows });
    this.rebuild();
  }

  /** Remove an extension's contributions from the taxonomy. */
  unregisterExtension(extensionId: string): void {
    this.extensionRegistrations.delete(extensionId);
    this.rebuild();
  }

  /** Whether any extensions have been registered. */
  hasExtensions(): boolean {
    return this.extensionRegistrations.size > 0;
  }

  /** Returns the level-1 domain nodes (with injected children). */
  getDomains(): IntentTaxonomyNode[] {
    return this.assembledDomains;
  }

  /**
   * Get the children at a given path in the assembled tree.
   *
   * - `[]` → domain nodes
   * - `["create"]` → children of the "create" domain (extension-injected + core children)
   * - `["create", "job"]` → children of "job" under "create"
   */
  getOptionsAt(path: string[]): IntentTaxonomyNode[] {
    if (path.length === 0) return this.assembledDomains;

    let current: IntentTaxonomyNode[] = this.assembledDomains;
    for (const segment of path) {
      const found = current.find(n => n.id === segment);
      if (!found) return [];
      current = found.children ?? [];
    }
    return current;
  }

  /**
   * Walk the tree to a specific node by path segments.
   * Returns null if any segment is not found.
   */
  getNodeAt(path: string[]): IntentTaxonomyNode | null {
    if (path.length === 0) return null;

    let current: IntentTaxonomyNode[] = this.assembledDomains;
    let node: IntentTaxonomyNode | undefined;
    for (const segment of path) {
      node = current.find(n => n.id === segment);
      if (!node) return null;
      current = node.children ?? [];
    }
    return node ?? null;
  }

  /**
   * Resolve a path to its first flow ID.
   * Walks the tree to the deepest node in the path and returns the first flowId found,
   * or walks back up the path if the leaf has none.
   */
  resolveToFlow(path: string[]): string | null {
    if (path.length === 0) return null;

    // Walk the path, collecting nodes
    const nodesOnPath: IntentTaxonomyNode[] = [];
    let current: IntentTaxonomyNode[] = this.assembledDomains;
    for (const segment of path) {
      const found = current.find(n => n.id === segment);
      if (!found) break;
      nodesOnPath.push(found);
      current = found.children ?? [];
    }

    // Walk back from deepest to shallowest looking for a flowId
    for (let i = nodesOnPath.length - 1; i >= 0; i--) {
      const flowIds = nodesOnPath[i].flowIds;
      if (flowIds && flowIds.length > 0) return flowIds[0];
    }

    return null;
  }

  /**
   * Get the top-N fast-path intents from the trigger intent map.
   * Returns entries sorted by node depth (leaves first) for LLM prompt construction.
   */
  getFastPathIntents(n = 20): FastPathEntry[] {
    const entries: FastPathEntry[] = [];

    for (const [intent, { nodeId, flowId }] of this.triggerIntentMap) {
      const node = this.findNodeById(nodeId, this.assembledDomains);
      entries.push({
        intent,
        nodeId,
        flowId,
        examples: node?.examples ?? [],
      });
    }

    // Sort by specificity (longer nodeId = more specific = higher priority)
    entries.sort((a, b) => b.nodeId.length - a.nodeId.length);
    return entries.slice(0, n);
  }

  /**
   * Get the raw fast-path map for direct O(1) lookups.
   */
  getFastPathMap(): Map<string, { nodeId: string; flowId: string }> {
    return this.triggerIntentMap;
  }

  /**
   * Build a focused LLM prompt for classification at a specific tree level.
   * Shows only the options at the given path, with descriptions and examples.
   */
  buildPrompt(path: string[], userMessage: string): string {
    const options = this.getOptionsAt(path);
    if (options.length === 0) {
      return `No options available at path [${path.join(' > ')}].`;
    }

    const levelLabel = path.length === 0
      ? 'domain'
      : path.length === 1
        ? 'category'
        : 'type';

    const parts: string[] = [
      `You are an intent classifier. Classify the user message into one of the following ${levelLabel} options.`,
      '',
      'Options:',
    ];

    for (const opt of options) {
      let line = `- "${opt.id}": ${opt.label} — ${opt.description}`;
      if (opt.examples && opt.examples.length > 0) {
        line += ` (examples: ${opt.examples.slice(0, 3).map(e => `"${e}"`).join(', ')})`;
      }
      parts.push(line);
    }

    parts.push('');
    parts.push('Respond with valid JSON only: { "selected": "<option_id>", "confidence": <0.0-1.0> }');
    parts.push('If none of the options match, respond with: { "selected": "unknown", "confidence": 0.0 }');

    return parts.join('\n');
  }

  /**
   * Build a fast-path prompt that lists the top-N most common intents.
   * Used for a single LLM call that can short-circuit the full hierarchy.
   */
  buildFastPathPrompt(intents: FastPathEntry[], userMessage: string): string {
    const parts: string[] = [
      'You are an intent classifier. Classify the user message into one of the following intents.',
      'Only select an intent if you are very confident (>0.90). If uncertain, select "unknown".',
      '',
      'Intents:',
    ];

    for (const entry of intents) {
      let line = `- "${entry.intent}": flow=${entry.flowId}`;
      if (entry.examples.length > 0) {
        line += ` (examples: ${entry.examples.slice(0, 2).map(e => `"${e}"`).join(', ')})`;
      }
      parts.push(line);
    }

    parts.push('');
    parts.push('Respond with valid JSON only: { "intent": "<intent_string>", "confidence": <0.0-1.0>, "flowId": "<flow_id>" }');
    parts.push('If none match confidently, respond with: { "intent": "unknown", "confidence": 0.0 }');

    return parts.join('\n');
  }

  /**
   * Build a classification prompt with options ordered by embedding similarity.
   * Rankings are pre-computed by the intent classifier using embedding similarity.
   *
   * Options are presented in descending similarity order with scores as hints.
   * The LLM is instructed to use scores as a prior but override if it disagrees.
   *
   * Falls back to buildPrompt() if rankings is empty.
   */
  buildEmbeddingRankedPrompt(
    path: string[],
    userMessage: string,
    rankings: Array<{ id: string; score: number }>,
  ): string {
    if (rankings.length === 0) {
      return this.buildPrompt(path, userMessage);
    }

    const options = this.getOptionsAt(path);
    if (options.length === 0) {
      return `No options available at path [${path.join(' > ')}].`;
    }

    const levelLabel = path.length === 0
      ? 'domain'
      : path.length === 1
        ? 'category'
        : 'type';

    const parts: string[] = [
      `You are an intent classifier. Classify the user message into one of the following ${levelLabel} options.`,
      'Options are pre-ranked by semantic similarity (scores shown). Use these as a prior, but override if your understanding of the message disagrees.',
      '',
      'Options (ranked by relevance):',
    ];

    // Build a score lookup from rankings
    const scoreMap = new Map(rankings.map(r => [r.id, r.score]));

    // Separate ranked and unranked options
    const ranked: IntentTaxonomyNode[] = [];
    const unranked: IntentTaxonomyNode[] = [];
    for (const opt of options) {
      if (scoreMap.has(opt.id)) {
        ranked.push(opt);
      } else {
        unranked.push(opt);
      }
    }

    // Sort ranked options by descending score
    ranked.sort((a, b) => (scoreMap.get(b.id) ?? 0) - (scoreMap.get(a.id) ?? 0));

    // Emit ranked options with scores
    for (const opt of ranked) {
      const score = scoreMap.get(opt.id) ?? 0;
      let line = `- "${opt.id}" (${score.toFixed(2)}): ${opt.label} — ${opt.description}`;
      if (opt.examples && opt.examples.length > 0) {
        line += ` (examples: ${opt.examples.slice(0, 3).map(e => `"${e}"`).join(', ')})`;
      }
      parts.push(line);
    }

    // Emit unranked options without scores
    for (const opt of unranked) {
      let line = `- "${opt.id}": ${opt.label} — ${opt.description}`;
      if (opt.examples && opt.examples.length > 0) {
        line += ` (examples: ${opt.examples.slice(0, 3).map(e => `"${e}"`).join(', ')})`;
      }
      parts.push(line);
    }

    parts.push('');
    parts.push('Respond with valid JSON only: { "selected": "<option_id>", "confidence": <0.0-1.0> }');
    parts.push('If none of the options match, respond with: { "selected": "unknown", "confidence": 0.0 }');

    return parts.join('\n');
  }

  // ── Private ──────────────────────────────────────────

  /**
   * Rebuild the assembled tree and fast-path map from domains + all extension registrations.
   */
  private rebuild(): void {
    // Start with deep clone of core domains
    this.assembledDomains = this.domains.map(n => deepCloneNode(n));

    // Inject each extension's nodes under the appropriate domain parents
    for (const [, { injections }] of this.extensionRegistrations) {
      for (const injection of injections) {
        const parent = this.assembledDomains.find(d => d.id === injection.parentId);
        if (parent) {
          if (!parent.children) parent.children = [];
          for (const node of injection.nodes) {
            // Avoid duplicates: skip if a child with the same id already exists
            if (!parent.children.some(c => c.id === node.id)) {
              parent.children.push(deepCloneNode(node));
            }
          }
        }
      }
    }

    // Rebuild fast-path map from all registered flows
    this.triggerIntentMap.clear();
    for (const [, { injections, flows }] of this.extensionRegistrations) {
      // Build a flowId → nodeId lookup from injections
      const flowToNode = new Map<string, string>();
      for (const injection of injections) {
        this.collectFlowNodeMappings(injection.nodes, injection.parentId, flowToNode);
      }
      // Also collect from core domain children (govern, demo, etc.)
      for (const domain of this.assembledDomains) {
        if (domain.children) {
          this.collectFlowNodeMappings(domain.children, domain.id, flowToNode);
        }
      }

      // Map each flow's triggerIntents to the fast-path map
      for (const flow of flows) {
        const nodeId = flowToNode.get(flow.id);
        if (!nodeId) continue;
        for (const trigger of flow.triggerIntents) {
          this.triggerIntentMap.set(trigger, { nodeId, flowId: flow.id });
        }
      }
    }
  }

  /** Recursively collect flowId → nodeId mappings from a subtree. */
  private collectFlowNodeMappings(
    nodes: IntentTaxonomyNode[],
    parentPath: string,
    map: Map<string, string>,
  ): void {
    for (const node of nodes) {
      const nodePath = `${parentPath}.${node.id}`;
      if (node.flowIds) {
        for (const flowId of node.flowIds) {
          map.set(flowId, nodePath);
        }
      }
      if (node.children) {
        this.collectFlowNodeMappings(node.children, nodePath, map);
      }
    }
  }

  /** Find a node by its full dotted id path in the assembled tree. */
  private findNodeById(
    nodeId: string,
    nodes: IntentTaxonomyNode[],
    currentPath = '',
  ): IntentTaxonomyNode | null {
    for (const node of nodes) {
      const path = currentPath ? `${currentPath}.${node.id}` : node.id;
      if (path === nodeId) return node;
      if (node.children) {
        const found = this.findNodeById(nodeId, node.children, path);
        if (found) return found;
      }
    }
    return null;
  }
}

/** Deep clone a taxonomy node to avoid mutation across registrations. */
function deepCloneNode(node: IntentTaxonomyNode): IntentTaxonomyNode {
  return {
    id: node.id,
    label: node.label,
    description: node.description,
    children: node.children?.map(c => deepCloneNode(c)),
    flowIds: node.flowIds ? [...node.flowIds] : undefined,
    examples: node.examples ? [...node.examples] : undefined,
  };
}

/** Singleton instance — assembled from all loaded extensions. */
export const intentTaxonomy = new IntentTaxonomy();

```
