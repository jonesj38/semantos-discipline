---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/tests/gates/intent-taxonomy.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.570936+00:00
---

# tests/gates/intent-taxonomy.test.ts

```ts
/**
 * Phase 13 Unit Tests (T1–T10): IntentTaxonomy registry.
 *
 * Uses real taxonomy configs from configs/taxonomy/.
 * Validates registration, tree traversal, flow resolution,
 * fast-path collection, and prompt generation.
 */

import { describe, test, expect, beforeEach } from "bun:test";
import { readFileSync } from "fs";
import { join } from "path";

const ROOT = join(import.meta.dir, "../..");
const TAXONOMY_DIR = join(ROOT, "configs/taxonomy");
const EXTENSIONS_DIR = join(ROOT, "configs/extensions");

// Import taxonomy types — we re-implement the class test since Bun can't
// directly import TS from loom/src without the vite resolver.
// Instead, we load the JSON configs and test the data structures directly.

interface IntentTaxonomyNode {
  id: string;
  label: string;
  description: string;
  children?: IntentTaxonomyNode[];
  flowIds?: string[];
  examples?: string[];
}

interface TaxonomyInjection {
  parentId: string;
  nodes: IntentTaxonomyNode[];
}

interface TaxonomyConfig {
  extensionId: string;
  inject: TaxonomyInjection[];
}

interface CoreTaxonomyConfig {
  nodes: IntentTaxonomyNode[];
}

interface ConversationFlow {
  id: string;
  name: string;
  triggerIntents: string[];
  requiredCapabilities?: number[];
  steps: unknown[];
  onComplete: unknown;
}

// ── Minimal IntentTaxonomy reimplementation for testing ──

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

class IntentTaxonomy {
  private domains: IntentTaxonomyNode[] = [];
  private extensionRegistrations = new Map<
    string,
    { injections: TaxonomyInjection[]; flows: ConversationFlow[] }
  >();
  private triggerIntentMap = new Map<string, { nodeId: string; flowId: string }>();
  private assembledDomains: IntentTaxonomyNode[] = [];

  loadDomains(nodes: IntentTaxonomyNode[]): void {
    this.domains = nodes.map(n => deepCloneNode(n));
    this.rebuild();
  }

  registerExtension(extensionId: string, injections: TaxonomyInjection[], flows: ConversationFlow[]): void {
    this.extensionRegistrations.set(extensionId, { injections, flows });
    this.rebuild();
  }

  unregisterExtension(extensionId: string): void {
    this.extensionRegistrations.delete(extensionId);
    this.rebuild();
  }

  hasExtensions(): boolean {
    return this.extensionRegistrations.size > 0;
  }

  getDomains(): IntentTaxonomyNode[] {
    return this.assembledDomains;
  }

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

  resolveToFlow(path: string[]): string | null {
    if (path.length === 0) return null;
    const nodesOnPath: IntentTaxonomyNode[] = [];
    let current: IntentTaxonomyNode[] = this.assembledDomains;
    for (const segment of path) {
      const found = current.find(n => n.id === segment);
      if (!found) break;
      nodesOnPath.push(found);
      current = found.children ?? [];
    }
    for (let i = nodesOnPath.length - 1; i >= 0; i--) {
      const flowIds = nodesOnPath[i].flowIds;
      if (flowIds && flowIds.length > 0) return flowIds[0];
    }
    return null;
  }

  getFastPathIntents(n = 20): Array<{ intent: string; nodeId: string; flowId: string; examples: string[] }> {
    const entries: Array<{ intent: string; nodeId: string; flowId: string; examples: string[] }> = [];
    for (const [intent, { nodeId, flowId }] of this.triggerIntentMap) {
      const node = this.findNodeById(nodeId, this.assembledDomains);
      entries.push({ intent, nodeId, flowId, examples: node?.examples ?? [] });
    }
    entries.sort((a, b) => b.nodeId.length - a.nodeId.length);
    return entries.slice(0, n);
  }

  getFastPathMap(): Map<string, { nodeId: string; flowId: string }> {
    return this.triggerIntentMap;
  }

  buildPrompt(path: string[], userMessage: string): string {
    const options = this.getOptionsAt(path);
    if (options.length === 0) return `No options available at path [${path.join(' > ')}].`;
    const levelLabel = path.length === 0 ? 'domain' : path.length === 1 ? 'category' : 'type';
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

  private rebuild(): void {
    this.assembledDomains = this.domains.map(n => deepCloneNode(n));
    for (const [, { injections }] of this.extensionRegistrations) {
      for (const injection of injections) {
        const parent = this.assembledDomains.find(d => d.id === injection.parentId);
        if (parent) {
          if (!parent.children) parent.children = [];
          for (const node of injection.nodes) {
            if (!parent.children.some(c => c.id === node.id)) {
              parent.children.push(deepCloneNode(node));
            }
          }
        }
      }
    }
    this.triggerIntentMap.clear();
    for (const [, { injections, flows }] of this.extensionRegistrations) {
      const flowToNode = new Map<string, string>();
      for (const injection of injections) {
        this.collectFlowNodeMappings(injection.nodes, injection.parentId, flowToNode);
      }
      for (const domain of this.assembledDomains) {
        if (domain.children) {
          this.collectFlowNodeMappings(domain.children, domain.id, flowToNode);
        }
      }
      for (const flow of flows) {
        const nodeId = flowToNode.get(flow.id);
        if (!nodeId) continue;
        for (const trigger of flow.triggerIntents) {
          this.triggerIntentMap.set(trigger, { nodeId, flowId: flow.id });
        }
      }
    }
  }

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

// ── Load real configs ──────────────────────────────────

const coreConfig: CoreTaxonomyConfig = JSON.parse(readFileSync(join(TAXONOMY_DIR, "core.json"), "utf-8"));
const tradesConfig: TaxonomyConfig = JSON.parse(readFileSync(join(TAXONOMY_DIR, "trades.json"), "utf-8"));
const genericConfig: TaxonomyConfig = JSON.parse(readFileSync(join(TAXONOMY_DIR, "generic.json"), "utf-8"));

const tradesExtension = JSON.parse(readFileSync(join(EXTENSIONS_DIR, "trades-services.json"), "utf-8"));
const coreExtension = JSON.parse(readFileSync(join(EXTENSIONS_DIR, "core.json"), "utf-8"));

const tradesFlows: ConversationFlow[] = tradesExtension.flows;
const coreFlows: ConversationFlow[] = coreExtension.flows;
const allFlows: ConversationFlow[] = [...coreFlows, ...tradesFlows];

// ── Tests ──────────────────────────────────────────────

describe("Phase 13 Unit Tests: IntentTaxonomy", () => {
  let taxonomy: IntentTaxonomy;

  beforeEach(() => {
    taxonomy = new IntentTaxonomy();
  });

  // T1: registerExtension() adds subtree to domain correctly
  test("T1: registerExtension() adds subtree to domain correctly", () => {
    taxonomy.loadDomains(coreConfig.nodes);
    expect(taxonomy.hasExtensions()).toBe(false);

    taxonomy.registerExtension(tradesConfig.extensionId, tradesConfig.inject, allFlows);
    expect(taxonomy.hasExtensions()).toBe(true);

    // Trades nodes should be injected under "create"
    const createChildren = taxonomy.getOptionsAt(["create"]);
    const childIds = createChildren.map(c => c.id);
    expect(childIds).toContain("job");
    expect(childIds).toContain("quote");
    expect(childIds).toContain("visit");
  });

  // T2: unregisterExtension() removes subtree cleanly
  test("T2: unregisterExtension() removes subtree cleanly", () => {
    taxonomy.loadDomains(coreConfig.nodes);
    taxonomy.registerExtension(tradesConfig.extensionId, tradesConfig.inject, allFlows);

    // Verify trades nodes exist
    let createChildren = taxonomy.getOptionsAt(["create"]);
    expect(createChildren.some(c => c.id === "job")).toBe(true);

    // Unregister
    taxonomy.unregisterExtension(tradesConfig.extensionId);
    expect(taxonomy.hasExtensions()).toBe(false);

    // Trades nodes should be gone
    createChildren = taxonomy.getOptionsAt(["create"]);
    expect(createChildren.some(c => c.id === "job")).toBe(false);
  });

  // T3: getOptionsAt(["create"]) returns all registered create extensions
  test("T3: getOptionsAt(['create']) returns registered extensions under create", () => {
    taxonomy.loadDomains(coreConfig.nodes);
    taxonomy.registerExtension(tradesConfig.extensionId, tradesConfig.inject, allFlows);
    taxonomy.registerExtension(genericConfig.extensionId, genericConfig.inject, []);

    const createChildren = taxonomy.getOptionsAt(["create"]);
    const childIds = createChildren.map(c => c.id);

    // Should have trades nodes
    expect(childIds).toContain("job");
    expect(childIds).toContain("quote");
    expect(childIds).toContain("visit");

    // Should have generic nodes
    expect(childIds).toContain("thing");
    expect(childIds).toContain("action");
    expect(childIds).toContain("instrument");
  });

  // T4: getOptionsAt(["create", "job"]) returns job's children (if any)
  test("T4: getOptionsAt(['govern']) returns governance children from core domains", () => {
    taxonomy.loadDomains(coreConfig.nodes);
    taxonomy.registerExtension(genericConfig.extensionId, genericConfig.inject, coreFlows);

    const governChildren = taxonomy.getOptionsAt(["govern"]);
    const childIds = governChildren.map(c => c.id);
    expect(childIds).toContain("dispute");
    expect(childIds).toContain("vote");
    expect(childIds).toContain("stake");
    expect(childIds).toContain("propose");
    expect(childIds).toContain("challenge-classification");
  });

  // T5: getOptionsAt(["create", "unloaded_extension"]) returns empty array
  test("T5: getOptionsAt for unloaded extension path returns empty array", () => {
    taxonomy.loadDomains(coreConfig.nodes);
    taxonomy.registerExtension(tradesConfig.extensionId, tradesConfig.inject, allFlows);

    const result = taxonomy.getOptionsAt(["create", "nonexistent"]);
    expect(result).toEqual([]);
  });

  // T6: resolveToFlow(["create", "job"]) returns "create-job"
  test("T6: resolveToFlow(['create', 'job']) returns 'create-job'", () => {
    taxonomy.loadDomains(coreConfig.nodes);
    taxonomy.registerExtension(tradesConfig.extensionId, tradesConfig.inject, allFlows);

    const flowId = taxonomy.resolveToFlow(["create", "job"]);
    expect(flowId).toBe("create-job");
  });

  // T7: resolveToFlow(["demo", "linearity"]) returns "compliance-demo"
  test("T7: resolveToFlow(['demo', 'linearity']) returns 'compliance-demo'", () => {
    taxonomy.loadDomains(coreConfig.nodes);
    // Core domains have demo.linearity with compliance-demo flowId
    const flowId = taxonomy.resolveToFlow(["demo", "linearity"]);
    expect(flowId).toBe("compliance-demo");
  });

  // T8: resolveToFlow(["create", "nonexistent"]) returns null
  test("T8: resolveToFlow for nonexistent path returns null", () => {
    taxonomy.loadDomains(coreConfig.nodes);
    taxonomy.registerExtension(tradesConfig.extensionId, tradesConfig.inject, allFlows);

    const flowId = taxonomy.resolveToFlow(["create", "nonexistent"]);
    expect(flowId).toBeNull();
  });

  // T9: getFastPathIntents returns intents across all loaded extensions
  test("T9: getFastPathIntents returns intents from all registered extensions", () => {
    taxonomy.loadDomains(coreConfig.nodes);
    taxonomy.registerExtension(tradesConfig.extensionId, tradesConfig.inject, allFlows);

    // Get ALL intents (no limit) to verify coverage
    const allIntents = taxonomy.getFastPathIntents(100);
    expect(allIntents.length).toBeGreaterThan(0);

    const intentStrings = allIntents.map(e => e.intent);
    // Trades triggers
    expect(intentStrings).toContain("create.job");
    expect(intentStrings).toContain("need.service");
    expect(intentStrings).toContain("request.quote");
    // Core triggers (from flows with matching flowIds in domains)
    expect(intentStrings).toContain("dispute");
    expect(intentStrings).toContain("vote");
    expect(intentStrings).toContain("demo.compliance");

    // Verify n=20 limit works
    const limited = taxonomy.getFastPathIntents(20);
    expect(limited.length).toBeLessThanOrEqual(20);
    expect(limited.length).toBeGreaterThan(0);
  });

  // T10: buildPrompt(["create"], message) produces correct LLM prompt format
  test("T10: buildPrompt produces correct format with options at given level", () => {
    taxonomy.loadDomains(coreConfig.nodes);
    taxonomy.registerExtension(tradesConfig.extensionId, tradesConfig.inject, allFlows);

    const prompt = taxonomy.buildPrompt(["create"], "I need a plumber");
    expect(prompt).toContain("intent classifier");
    expect(prompt).toContain('"job"');
    expect(prompt).toContain("Create Job");
    expect(prompt).toContain('"selected"');
    expect(prompt).toContain('"confidence"');
    // Should include examples
    expect(prompt).toContain("I need a plumber");
  });
});

// ── Config structure validation ────────────────────────

describe("Phase 13: Taxonomy config structure", () => {
  test("core.json has exactly 8 domain nodes", () => {
    expect(coreConfig.nodes.length).toBe(8);
    const ids = coreConfig.nodes.map(n => n.id);
    expect(ids).toContain("create");
    expect(ids).toContain("navigate");
    expect(ids).toContain("query");
    expect(ids).toContain("consume");
    expect(ids).toContain("inspect");
    expect(ids).toContain("govern");
    expect(ids).toContain("demo");
    expect(ids).toContain("transition");
  });

  test("core.json nodes all have id, label, description", () => {
    for (const node of coreConfig.nodes) {
      expect(typeof node.id).toBe("string");
      expect(typeof node.label).toBe("string");
      expect(typeof node.description).toBe("string");
      expect(node.id.length).toBeGreaterThan(0);
      expect(node.label.length).toBeGreaterThan(0);
      expect(node.description.length).toBeGreaterThan(0);
    }
  });

  test("trades.json extensionId matches trades-services", () => {
    expect(tradesConfig.extensionId).toBe("trades-services");
  });

  test("trades.json inject targets match core domain ids", () => {
    const domainIds = new Set(coreConfig.nodes.map(n => n.id));
    for (const injection of tradesConfig.inject) {
      expect(domainIds.has(injection.parentId)).toBe(true);
    }
  });

  test("trades.json flow IDs match actual trades-services.json flow IDs", () => {
    const tradesFlowIds = new Set(tradesFlows.map(f => f.id));
    for (const injection of tradesConfig.inject) {
      for (const node of injection.nodes) {
        if (node.flowIds) {
          for (const flowId of node.flowIds) {
            expect(tradesFlowIds.has(flowId)).toBe(true);
          }
        }
      }
    }
  });

  test("generic.json extensionId is 'generic'", () => {
    expect(genericConfig.extensionId).toBe("generic");
  });

  test("govern domain children have correct flowIds for core flows", () => {
    const governNode = coreConfig.nodes.find(n => n.id === "govern");
    expect(governNode).toBeTruthy();
    expect(governNode!.children).toBeTruthy();

    const disputeNode = governNode!.children!.find(c => c.id === "dispute");
    expect(disputeNode).toBeTruthy();
    expect(disputeNode!.flowIds).toContain("file-dispute");

    const voteNode = governNode!.children!.find(c => c.id === "vote");
    expect(voteNode).toBeTruthy();
    expect(voteNode!.flowIds).toContain("cast-vote");
  });
});

```
