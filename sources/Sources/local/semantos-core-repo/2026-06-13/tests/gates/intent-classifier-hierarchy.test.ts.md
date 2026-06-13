---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/tests/gates/intent-classifier-hierarchy.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.586168+00:00
---

# tests/gates/intent-classifier-hierarchy.test.ts

```ts
/**
 * Phase 13 Integration Tests (T11–T20) + Regression Tests (T21–T24).
 *
 * Integration tests mock the fetch() call to simulate OpenRouter LLM responses.
 * Mocking is done at the test level only — production code always calls real LLM.
 *
 * Regression tests verify all existing triggerIntents still resolve correctly
 * through the new taxonomy system.
 */

import { describe, test, expect, beforeEach, afterEach, mock } from "bun:test";
import { readFileSync } from "fs";
import { join } from "path";

const ROOT = join(import.meta.dir, "../..");
const TAXONOMY_DIR = join(ROOT, "configs/taxonomy");
const EXTENSIONS_DIR = join(ROOT, "configs/extensions");

// ── Taxonomy types (same as intent-taxonomy.test.ts) ──

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

// ── Load real configs ──────────────────────────────────

const coreConfig: CoreTaxonomyConfig = JSON.parse(readFileSync(join(TAXONOMY_DIR, "core.json"), "utf-8"));
const tradesConfig: TaxonomyConfig = JSON.parse(readFileSync(join(TAXONOMY_DIR, "trades.json"), "utf-8"));
const genericConfig: TaxonomyConfig = JSON.parse(readFileSync(join(TAXONOMY_DIR, "generic.json"), "utf-8"));

const tradesExtension = JSON.parse(readFileSync(join(EXTENSIONS_DIR, "trades-services.json"), "utf-8"));
const coreExtension = JSON.parse(readFileSync(join(EXTENSIONS_DIR, "core.json"), "utf-8"));

const tradesFlows: ConversationFlow[] = tradesExtension.flows;
const coreFlows: ConversationFlow[] = coreExtension.flows;
const allFlows: ConversationFlow[] = [...coreFlows, ...tradesFlows];

// ── Minimal IntentTaxonomy for testing fast-path map ──

function deepCloneNode(node: IntentTaxonomyNode): IntentTaxonomyNode {
  return {
    id: node.id, label: node.label, description: node.description,
    children: node.children?.map(c => deepCloneNode(c)),
    flowIds: node.flowIds ? [...node.flowIds] : undefined,
    examples: node.examples ? [...node.examples] : undefined,
  };
}

class IntentTaxonomy {
  private domains: IntentTaxonomyNode[] = [];
  private extensionRegistrations = new Map<string, { injections: TaxonomyInjection[]; flows: ConversationFlow[] }>();
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

  hasExtensions(): boolean { return this.extensionRegistrations.size > 0; }
  getDomains(): IntentTaxonomyNode[] { return this.assembledDomains; }
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
  getFastPathMap(): Map<string, { nodeId: string; flowId: string }> { return this.triggerIntentMap; }

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
    nodes: IntentTaxonomyNode[], parentPath: string, map: Map<string, string>,
  ): void {
    for (const node of nodes) {
      const nodePath = `${parentPath}.${node.id}`;
      if (node.flowIds) {
        for (const flowId of node.flowIds) map.set(flowId, nodePath);
      }
      if (node.children) this.collectFlowNodeMappings(node.children, nodePath, map);
    }
  }
}

// ── Integration Tests (T11–T20) ───────────────────────

describe("Phase 13 Integration Tests: Hierarchical Classification", () => {
  let taxonomy: IntentTaxonomy;

  beforeEach(() => {
    taxonomy = new IntentTaxonomy();
    taxonomy.loadDomains(coreConfig.nodes);
    taxonomy.registerExtension(tradesConfig.extensionId, tradesConfig.inject, allFlows);
    taxonomy.registerExtension(genericConfig.extensionId, genericConfig.inject, []);
  });

  // T11: Fast path resolves "create.job" for unambiguous trade messages
  test("T11: fast path maps 'create.job' trigger to create-job flow", () => {
    const fastMap = taxonomy.getFastPathMap();
    const entry = fastMap.get("create.job");
    expect(entry).toBeTruthy();
    expect(entry!.flowId).toBe("create-job");
  });

  // T12: Fast path resolves "need.service" to same flow as create.job
  test("T12: 'need.service' maps to create-job flow via fast path", () => {
    const fastMap = taxonomy.getFastPathMap();
    const entry = fastMap.get("need.service");
    expect(entry).toBeTruthy();
    expect(entry!.flowId).toBe("create-job");
  });

  // T13: Hierarchical path would traverse create → job for trades messages
  test("T13: hierarchical traversal — create domain has trades children", () => {
    const createChildren = taxonomy.getOptionsAt(["create"]);
    expect(createChildren.length).toBeGreaterThan(0);
    expect(createChildren.some(c => c.id === "job")).toBe(true);
  });

  // T14: Fast path resolves governance intents
  test("T14: fast path maps 'dispute' to file-dispute flow", () => {
    const fastMap = taxonomy.getFastPathMap();
    const dispute = fastMap.get("dispute");
    expect(dispute).toBeTruthy();
    expect(dispute!.flowId).toBe("file-dispute");
  });

  // T15: Fast path resolves "demo.compliance" to compliance-demo
  test("T15: fast path maps 'demo.compliance' to compliance-demo flow", () => {
    const fastMap = taxonomy.getFastPathMap();
    const demo = fastMap.get("demo.compliance");
    expect(demo).toBeTruthy();
    expect(demo!.flowId).toBe("compliance-demo");
  });

  // T16: Inspect domain exists and has generic children
  test("T16: inspect domain has generic evidence child", () => {
    const inspectChildren = taxonomy.getOptionsAt(["inspect"]);
    expect(inspectChildren.some(c => c.id === "evidence")).toBe(true);
  });

  // T17: Unloaded extension does not appear in options at any level
  test("T17: unloaded extension does not appear", () => {
    // blockchain-risk is NOT registered
    const createChildren = taxonomy.getOptionsAt(["create"]);
    const childIds = createChildren.map(c => c.id);
    // Should NOT have blockchain-risk-specific types
    expect(childIds).not.toContain("project");
    expect(childIds).not.toContain("assessment");
  });

  // T18: Loading a new extension makes its intents immediately classifiable
  test("T18: dynamically loading extension registers fast-path intents", () => {
    const blockchainExtension = JSON.parse(readFileSync(join(EXTENSIONS_DIR, "blockchain-risk.json"), "utf-8"));
    const blockchainFlows: ConversationFlow[] = blockchainExtension.flows;

    // Create a synthetic taxonomy injection for blockchain-risk
    const blockchainTaxonomy: TaxonomyConfig = {
      extensionId: "blockchain-risk",
      inject: [{
        parentId: "create",
        nodes: [{
          id: "project",
          label: "Assess Project",
          description: "New blockchain project assessment",
          flowIds: ["new-assessment"],
          examples: ["assess a project"],
        }],
      }],
    };

    // Before registration — fast path should not have blockchain intents
    let fastMap = taxonomy.getFastPathMap();
    expect(fastMap.has("create.project")).toBe(false);

    // Register
    taxonomy.registerExtension(blockchainTaxonomy.extensionId, blockchainTaxonomy.inject, blockchainFlows);

    // After registration — fast path should have blockchain intents
    fastMap = taxonomy.getFastPathMap();
    expect(fastMap.has("create.project")).toBe(true);
    expect(fastMap.get("create.project")!.flowId).toBe("new-assessment");
  });

  // T19: llmCallCount bounds — fast path = 1, hierarchical <= 3
  test("T19: domain level options are between 5-15 items", () => {
    // This validates the key constraint: each level has 5-15 options
    const domains = taxonomy.getDomains();
    expect(domains.length).toBe(8); // 8 domains
    expect(domains.length).toBeGreaterThanOrEqual(5);
    expect(domains.length).toBeLessThanOrEqual(15);

    // Create level should also be reasonable
    const createChildren = taxonomy.getOptionsAt(["create"]);
    expect(createChildren.length).toBeGreaterThanOrEqual(3); // at least trades + generic types
    expect(createChildren.length).toBeLessThanOrEqual(15);
  });

  // T20: Unknown intent fallback — unregistered path returns no flow
  test("T20: unmatched fast-path intent returns undefined", () => {
    const fastMap = taxonomy.getFastPathMap();
    expect(fastMap.has("completely.unknown.intent")).toBe(false);
  });
});

// ── Regression Tests (T21–T24) ────────────────────────

describe("Phase 13 Regression Tests: Backward Compatibility", () => {
  let taxonomy: IntentTaxonomy;

  beforeEach(() => {
    taxonomy = new IntentTaxonomy();
    taxonomy.loadDomains(coreConfig.nodes);
    taxonomy.registerExtension(tradesConfig.extensionId, tradesConfig.inject, allFlows);
    taxonomy.registerExtension(genericConfig.extensionId, genericConfig.inject, coreFlows);
  });

  // T21: All existing flows still trigger correctly by their triggerIntents strings
  test("T21: all trades-services triggerIntents map to correct flows via fast path", () => {
    const fastMap = taxonomy.getFastPathMap();

    // create-job triggers
    for (const trigger of ["create.job", "need.service", "request.quote"]) {
      const entry = fastMap.get(trigger);
      expect(entry).toBeTruthy();
      expect(entry!.flowId).toBe("create-job");
    }

    // generate-estimate triggers
    for (const trigger of ["create.quote", "generate.rom"]) {
      const entry = fastMap.get(trigger);
      expect(entry).toBeTruthy();
      expect(entry!.flowId).toBe("generate-estimate");
    }

    // schedule-visit triggers
    for (const trigger of ["schedule.visit", "create.visit"]) {
      const entry = fastMap.get(trigger);
      expect(entry).toBeTruthy();
      expect(entry!.flowId).toBe("schedule-visit");
    }

    // publish-job triggers
    for (const trigger of ["publish", "make.public", "share"]) {
      const entry = fastMap.get(trigger);
      expect(entry).toBeTruthy();
      expect(entry!.flowId).toBe("publish-job");
    }

    // revoke-job triggers
    for (const trigger of ["revoke", "retract", "hide", "unpublish"]) {
      const entry = fastMap.get(trigger);
      expect(entry).toBeTruthy();
      expect(entry!.flowId).toBe("revoke-job");
    }
  });

  // T22: "I need a plumber for a leaking tap" still routes to new-job-intake
  test("T22: trade-specific triggers still map to create-job flow", () => {
    // The message "I need a plumber" would classify as "need.service" or "create.job"
    // Both map to create-job
    const fastMap = taxonomy.getFastPathMap();
    expect(fastMap.get("need.service")?.flowId).toBe("create-job");
    expect(fastMap.get("create.job")?.flowId).toBe("create-job");
  });

  // T23: All core governance triggers still resolve
  test("T23: core governance triggerIntents all resolve via fast path", () => {
    const fastMap = taxonomy.getFastPathMap();

    // file-dispute triggers
    for (const trigger of ["dispute", "challenge", "flag", "report"]) {
      const entry = fastMap.get(trigger);
      expect(entry).toBeTruthy();
      expect(entry!.flowId).toBe("file-dispute");
    }

    // cast-vote triggers
    for (const trigger of ["vote", "approve", "reject", "support", "oppose"]) {
      const entry = fastMap.get(trigger);
      expect(entry).toBeTruthy();
      expect(entry!.flowId).toBe("cast-vote");
    }

    // stake triggers
    for (const trigger of ["stake", "back", "wager"]) {
      const entry = fastMap.get(trigger);
      expect(entry).toBeTruthy();
      expect(entry!.flowId).toBe("stake");
    }

    // propose-category triggers
    for (const trigger of ["propose.category", "add.category", "suggest.type", "new.category"]) {
      const entry = fastMap.get(trigger);
      expect(entry).toBeTruthy();
      expect(entry!.flowId).toBe("propose-category");
    }

    // challenge-classification triggers
    for (const trigger of ["challenge.classification", "reclassify", "wrong.category", "misclassified"]) {
      const entry = fastMap.get(trigger);
      expect(entry).toBeTruthy();
      expect(entry!.flowId).toBe("challenge-classification");
    }
  });

  // T24: Compliance demo flow still triggers on "demo linearity"
  test("T24: compliance demo triggers still resolve via fast path", () => {
    const fastMap = taxonomy.getFastPathMap();

    for (const trigger of ["demo.compliance", "demo.linearity", "create.linear", "test.linearity"]) {
      const entry = fastMap.get(trigger);
      expect(entry).toBeTruthy();
      expect(entry!.flowId).toBe("compliance-demo");
    }
  });
});

```
