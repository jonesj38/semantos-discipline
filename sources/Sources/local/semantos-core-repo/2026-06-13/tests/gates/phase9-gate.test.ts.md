---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/tests/gates/phase9-gate.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.572389+00:00
---

# tests/gates/phase9-gate.test.ts

```ts
/**
 * Phase 9 Gate: Intent Classification + Flow Routing
 *
 * Every test uses real extension configs and real service implementations.
 * No stubs, no mocks, no canned responses.
 *
 * NOTE: Tests avoid importing objectFactory/LoomStore/IdentityStore
 * directly because they chain through @semantos/protocol-types which has
 * a pre-existing self-reference resolution issue with Bun. These modules
 * are validated indirectly (correct typeHash hex → correct Uint8Array conversion)
 * and through the loom vite build.
 */

import { describe, test, expect } from "bun:test";
import { readFileSync, readdirSync } from "fs";
import { join } from "path";

const ROOT = join(import.meta.dir, "../..");
const CONFIGS_DIR = join(ROOT, "configs/extensions");
const WORKBENCH_SRC = join(ROOT, "runtime/services/src");

// ── Gate 1: typeHash pre-computation ──────────────────────────

describe("Gate 1: typeHash pre-computation", () => {
  const configFiles = ["core.json", "trades-services.json", "blockchain-risk.json", "development.json"];

  for (const file of configFiles) {
    test(`all objectTypes in ${file} have non-empty 64-char hex typeHash`, () => {
      const config = JSON.parse(readFileSync(join(CONFIGS_DIR, file), "utf-8"));
      for (const ot of config.objectTypes) {
        expect(ot.typeHash).toBeTruthy();
        expect(ot.typeHash.length).toBe(64);
        expect(/^[0-9a-f]{64}$/.test(ot.typeHash)).toBe(true);
      }
    });
  }

  test("typeHash is deterministic (same category = same hash)", () => {
    const { createHash } = require("crypto");
    const hash1 = createHash("sha256").update("services.trades", "utf-8").digest("hex");
    const hash2 = createHash("sha256").update("services.trades", "utf-8").digest("hex");
    expect(hash1).toBe(hash2);
    expect(hash1.length).toBe(64);
  });

  test("different categories produce different hashes", () => {
    const ts = JSON.parse(readFileSync(join(CONFIGS_DIR, "trades-services.json"), "utf-8"));
    const hashes = ts.objectTypes.map((ot: { typeHash: string }) => ot.typeHash);
    const unique = new Set(hashes);
    expect(unique.size).toBe(hashes.length);
  });

  test("objectFactory hexToUint8Array converts typeHash correctly", () => {
    // Verify the hex conversion logic directly (same as in objectFactory)
    const hex = "9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08";
    expect(hex.length).toBe(64);
    const bytes = new Uint8Array(32);
    for (let i = 0; i < 32; i++) {
      bytes[i] = parseInt(hex.substring(i * 2, i * 2 + 2), 16);
    }
    expect(bytes[0]).toBe(0x9f);
    expect(bytes[1]).toBe(0x86);
    expect(bytes[31]).toBe(0x08);
    // Verify it's not all zeros
    expect(bytes.every(b => b === 0)).toBe(false);
  });

  test("objectFactory source uses hexToUint8Array for typeHash", () => {
    const source = readFileSync(join(WORKBENCH_SRC, "state/objectFactory.ts"), "utf-8");
    expect(source).toContain("hexToUint8Array(typeDef.typeHash)");
    expect(source).not.toContain("new Uint8Array(32), // TODO");
  });
});

// ── Gate 2: Service layer extraction ──────────────────────────

describe("Gate 2: Service layer works without React", () => {
  test("TypedEventEmitter emits and unsubscribes", () => {
    const { TypedEventEmitter } = require("../../runtime/services/src/services/TypedEventEmitter");
    class TestEmitter extends TypedEventEmitter<{ test: [string] }> {
      fire(val: string) { this.emit("test", val); }
    }
    const emitter = new TestEmitter();
    const received: string[] = [];
    const unsub = emitter.on("test", (val: string) => received.push(val));
    emitter.fire("hello");
    emitter.fire("world");
    expect(received).toEqual(["hello", "world"]);
    unsub();
    emitter.fire("ignored");
    expect(received).toEqual(["hello", "world"]);
  });

  test("SettingsStore persists and retrieves settings", () => {
    const { SettingsStore } = require("../../runtime/services/src/services/SettingsStore");
    const store = new SettingsStore();
    expect(store.hasApiKey()).toBe(false);
    store.setApiKey("test-key-123");
    expect(store.hasApiKey()).toBe(true);
    expect(store.getSettings().openRouterApiKey).toBe("test-key-123");
    store.setModel("openai/gpt-4o");
    expect(store.getSettings().modelId).toBe("openai/gpt-4o");
    // Cleanup
    store.setApiKey(null);
  });

  test("LoomStore source imports from services (renderer agnostic)", () => {
    const source = readFileSync(join(WORKBENCH_SRC, "services/LoomStore.ts"), "utf-8");
    expect(source).toContain("TypedEventEmitter");
    expect(source).toContain("loomReducer");
    expect(source).not.toContain("from 'react'");
    expect(source).not.toContain("useReducer");
  });

  test("IdentityStore source is renderer agnostic", () => {
    const source = readFileSync(join(WORKBENCH_SRC, "services/IdentityStore.ts"), "utf-8");
    expect(source).toContain("TypedEventEmitter");
    expect(source).toContain("createIdentity");
    expect(source).toContain("IdentityTraits");
    expect(source).not.toContain("from 'react'");
    expect(source).not.toContain("useState");
  });

  test("ConfigStore source is renderer agnostic", () => {
    const source = readFileSync(join(WORKBENCH_SRC, "services/ConfigStore.ts"), "utf-8");
    expect(source).toContain("TypedEventEmitter");
    expect(source).toContain("switchExtension");
    expect(source).toContain("mergeExtensions");
    expect(source).not.toContain("from 'react'");
  });

  test("React providers are thin wrappers", () => {
    const wp = readFileSync(join(WORKBENCH_SRC, "state/LoomProvider.tsx"), "utf-8");
    expect(wp).toContain("useSyncExternalStore");
    expect(wp).toContain("loomStore");
    expect(wp).not.toContain("useReducer");

    const ip = readFileSync(join(WORKBENCH_SRC, "identity/IdentityProvider.tsx"), "utf-8");
    expect(ip).toContain("useSyncExternalStore");
    expect(ip).toContain("identityStore");

    const vp = readFileSync(join(WORKBENCH_SRC, "config/ExtensionProvider.tsx"), "utf-8");
    expect(vp).toContain("useSyncExternalStore");
    expect(vp).toContain("configStore");
  });
});

// ── Gate 3: Intent classification ──────────────────────────────

describe("Gate 3: Intent classification", () => {
  test("classifyIntent returns unknown when no API key configured", async () => {
    const { classifyIntent } = require("../../runtime/services/src/services/IntentClassifier");
    const result = await classifyIntent("I need a plumber", {
      extensionName: "Test",
      objectTypes: ["Job"],
      taxonomyPaths: ["services.trades.plumbing"],
      flowIds: ["create-job"],
    }, { openRouterApiKey: null, modelId: "test", temperature: 0 });

    expect(result.intent).toBe("unknown");
    expect(result.confidence).toBe(0);
  });

  test("IntentClassification shape is valid", async () => {
    const { classifyIntent } = require("../../runtime/services/src/services/IntentClassifier");
    const result = await classifyIntent("test", {
      extensionName: "Test",
      objectTypes: [],
      taxonomyPaths: [],
      flowIds: [],
    }, { openRouterApiKey: null, modelId: "test", temperature: 0 });

    expect(typeof result.intent).toBe("string");
    expect(typeof result.confidence).toBe("number");
    expect(result.confidence).toBeGreaterThanOrEqual(0);
    expect(result.confidence).toBeLessThanOrEqual(1);
  });

  test("buildContextFromConfig correctly extracts taxonomy paths from trades-services", () => {
    const { buildContextFromConfig } = require("../../runtime/services/src/services/IntentClassifier");
    const ts = JSON.parse(readFileSync(join(CONFIGS_DIR, "trades-services.json"), "utf-8"));
    const context = buildContextFromConfig(ts);

    expect(context.extensionName).toBe("Trades & Services (OddJobTodd)");
    expect(context.objectTypes).toContain("Job");
    expect(context.objectTypes).toContain("Quote/ROM");
    expect(context.objectTypes).toContain("Visit");
    expect(context.objectTypes).toContain("Customer");
    expect(context.taxonomyPaths).toContain("services.trades");
    expect(context.taxonomyPaths).toContain("services.trades.plumbing");
    expect(context.taxonomyPaths).toContain("services.trades.carpentry");
    expect(context.taxonomyPaths).toContain("services.trades.electrical");
    expect(context.taxonomyPaths).toContain("tx.hire");
    expect(context.taxonomyPaths).toContain("inst.quote");
    expect(context.taxonomyPaths).toContain("inst.quote.rom");
    expect(context.flowIds).toContain("create-job");
    expect(context.flowIds).toContain("generate-estimate");
    expect(context.flowIds).toContain("schedule-visit");
  });

  test("buildContextFromConfig works with blockchain-risk", () => {
    const { buildContextFromConfig } = require("../../runtime/services/src/services/IntentClassifier");
    const br = JSON.parse(readFileSync(join(CONFIGS_DIR, "blockchain-risk.json"), "utf-8"));
    const context = buildContextFromConfig(br);

    expect(context.extensionName).toBe("Blockchain Risk (BREM-Agent)");
    expect(context.objectTypes).toContain("Project");
    expect(context.objectTypes).toContain("CellState");
    expect(context.flowIds).toContain("new-assessment");
    expect(context.flowIds).toContain("extract-evidence");
  });
});

// ── Gate 4: Flow registry + runner ──────────────────────────────

describe("Gate 4: Flow registry + runner", () => {
  test("findFlow matches create.job on trades-services", () => {
    const { findFlow } = require("../../runtime/services/src/services/FlowRegistry");
    const { validateExtensionConfig } = require("../../runtime/services/src/config/extensionConfig");
    const ts = JSON.parse(readFileSync(join(CONFIGS_DIR, "trades-services.json"), "utf-8"));
    const config = validateExtensionConfig(ts);

    const flow = findFlow("create.job", [4, 5], config);
    expect(flow).toBeTruthy();
    expect(flow!.id).toBe("create-job");
    expect(flow!.steps.length).toBe(3);
    expect(flow!.onComplete.type).toBe("create");
    expect(flow!.onComplete.objectType).toBe("Job");
  });

  test("findFlow matches need.service (alias trigger)", () => {
    const { findFlow } = require("../../runtime/services/src/services/FlowRegistry");
    const { validateExtensionConfig } = require("../../runtime/services/src/config/extensionConfig");
    const ts = JSON.parse(readFileSync(join(CONFIGS_DIR, "trades-services.json"), "utf-8"));
    const config = validateExtensionConfig(ts);

    const flow = findFlow("need.service", [4, 5], config);
    expect(flow).toBeTruthy();
    expect(flow!.id).toBe("create-job");
  });

  test("findFlow rejects when capabilities insufficient", () => {
    const { findFlow } = require("../../runtime/services/src/services/FlowRegistry");
    const { validateExtensionConfig } = require("../../runtime/services/src/config/extensionConfig");
    const ts = JSON.parse(readFileSync(join(CONFIGS_DIR, "trades-services.json"), "utf-8"));
    const config = validateExtensionConfig(ts);

    const flow = findFlow("create.job", [1], config);
    expect(flow).toBeNull();
  });

  test("findFlow works on blockchain-risk extension", () => {
    const { findFlow } = require("../../runtime/services/src/services/FlowRegistry");
    const { validateExtensionConfig } = require("../../runtime/services/src/config/extensionConfig");
    const br = JSON.parse(readFileSync(join(CONFIGS_DIR, "blockchain-risk.json"), "utf-8"));
    const config = validateExtensionConfig(br);

    const flow = findFlow("create.project", [5, 8], config);
    expect(flow).toBeTruthy();
    expect(flow!.id).toBe("new-assessment");
    expect(flow!.onComplete.objectType).toBe("Project");
  });

  test("FlowRunner processes all steps and completes with correct data", () => {
    const { FlowRunner } = require("../../runtime/services/src/services/FlowRunner");
    const { findFlow } = require("../../runtime/services/src/services/FlowRegistry");
    const { validateExtensionConfig } = require("../../runtime/services/src/config/extensionConfig");
    const ts = JSON.parse(readFileSync(join(CONFIGS_DIR, "trades-services.json"), "utf-8"));
    const config = validateExtensionConfig(ts);

    const flow = findFlow("create.job", [4, 5], config)!;
    const runner = new FlowRunner();

    // Start flow
    const firstStep = runner.startFlow(flow, "test-obj-1");
    expect(firstStep.id).toBe("ask-service-type");
    expect(firstStep.prompt).toContain("service");
    expect(runner.isActive()).toBe(true);
    expect(runner.getState().currentStepIndex).toBe(0);
    expect(runner.getState().totalSteps).toBe(3);

    // Step 1: provide service type
    const step2 = runner.advanceFlow("plumbing", { categoryPath: "services.trades.plumbing" });
    expect(step2).toBeTruthy();
    expect(step2!.id).toBe("ask-urgency");

    // Step 2: provide urgency
    const step3 = runner.advanceFlow("next week", { urgency: "next_week" });
    expect(step3).toBeTruthy();
    expect(step3!.id).toBe("ask-details");

    // Step 3: provide details (optional)
    const step4 = runner.advanceFlow("leaking tap in kitchen");
    expect(step4).toBeNull(); // Flow complete

    expect(runner.isFlowComplete()).toBe(true);

    const result = runner.completeFlow();
    expect(result.status).toBe("complete");
    expect(result.flowId).toBe("create-job");
    expect(result.collectedData.categoryPath).toBe("services.trades.plumbing");
    expect(result.collectedData.urgency).toBe("next_week");
    expect(result.collectedData.description).toBe("leaking tap in kitchen");
    expect(result.onComplete.type).toBe("create");
    expect(result.onComplete.objectType).toBe("Job");
  });

  test("FlowRunner emits events on step and complete", () => {
    const { FlowRunner } = require("../../runtime/services/src/services/FlowRunner");
    const { findFlow } = require("../../runtime/services/src/services/FlowRegistry");
    const { validateExtensionConfig } = require("../../runtime/services/src/config/extensionConfig");
    const br = JSON.parse(readFileSync(join(CONFIGS_DIR, "blockchain-risk.json"), "utf-8"));
    const config = validateExtensionConfig(br);

    const flow = findFlow("create.project", [5, 8], config)!;
    const runner = new FlowRunner();

    const steps: string[] = [];
    let completed = false;
    runner.on("step", (step: any) => steps.push(step.id));
    runner.on("complete", () => completed = true);

    runner.startFlow(flow);
    runner.advanceFlow("Uniswap Clone", { projectName: "Uniswap Clone" });
    runner.advanceFlow("DeFi", { protocolFamily: "defi" });

    expect(steps).toEqual(["ask-project-name", "ask-protocol-family"]);
    expect(completed).toBe(true);
    expect(runner.completeFlow().collectedData.projectName).toBe("Uniswap Clone");
    expect(runner.completeFlow().collectedData.protocolFamily).toBe("defi");
  });

  test("FlowRunner cancel works", () => {
    const { FlowRunner } = require("../../runtime/services/src/services/FlowRunner");
    const { findFlow } = require("../../runtime/services/src/services/FlowRegistry");
    const { validateExtensionConfig } = require("../../runtime/services/src/config/extensionConfig");
    const ts = JSON.parse(readFileSync(join(CONFIGS_DIR, "trades-services.json"), "utf-8"));
    const config = validateExtensionConfig(ts);

    const flow = findFlow("create.job", [4, 5], config)!;
    const runner = new FlowRunner();
    runner.startFlow(flow);
    expect(runner.isActive()).toBe(true);

    runner.cancelFlow();
    expect(runner.isActive()).toBe(false);
    expect(runner.getState().status).toBe("cancelled");
  });
});

// ── Gate 5: Extension config flows present ──────────────────────

describe("Gate 5: Extension config flows present", () => {
  test("trades-services.json has >= 3 flows with valid structure", () => {
    const ts = JSON.parse(readFileSync(join(CONFIGS_DIR, "trades-services.json"), "utf-8"));
    expect(ts.flows).toBeTruthy();
    expect(ts.flows.length).toBeGreaterThanOrEqual(3);
    for (const flow of ts.flows) {
      expect(flow.id).toBeTruthy();
      expect(flow.name).toBeTruthy();
      expect(Array.isArray(flow.triggerIntents)).toBe(true);
      expect(flow.triggerIntents.length).toBeGreaterThan(0);
      expect(Array.isArray(flow.steps)).toBe(true);
      expect(flow.steps.length).toBeGreaterThan(0);
      expect(flow.onComplete).toBeTruthy();
      expect(flow.onComplete.type).toBeTruthy();
      // Every step has an id and prompt
      for (const step of flow.steps) {
        expect(step.id).toBeTruthy();
        expect(step.prompt).toBeTruthy();
      }
    }
  });

  test("blockchain-risk.json has >= 2 flows", () => {
    const br = JSON.parse(readFileSync(join(CONFIGS_DIR, "blockchain-risk.json"), "utf-8"));
    expect(br.flows).toBeTruthy();
    expect(br.flows.length).toBeGreaterThanOrEqual(2);
  });

  test("extension config validates with flows", () => {
    const { validateExtensionConfig } = require("../../runtime/services/src/config/extensionConfig");
    const ts = JSON.parse(readFileSync(join(CONFIGS_DIR, "trades-services.json"), "utf-8"));
    const config = validateExtensionConfig(ts);
    expect(config.flows).toBeTruthy();
    expect(config.flows!.length).toBeGreaterThanOrEqual(3);
  });
});

// ── Gate 6: Anti-regression ──────────────────────────────────

describe("Gate 6: Anti-regression", () => {
  test("no NOT_IMPLEMENTED in workbench source", () => {
    const searchDir = (dir: string): string[] => {
      const results: string[] = [];
      for (const entry of readdirSync(dir, { withFileTypes: true })) {
        if (entry.isDirectory()) {
          results.push(...searchDir(join(dir, entry.name)));
        } else if (entry.name.endsWith('.ts') || entry.name.endsWith('.tsx')) {
          const content = readFileSync(join(dir, entry.name), "utf-8");
          if (content.includes("NOT_IMPLEMENTED") || content.match(/throw\s+new\s+Error\s*\(\s*['"]not\s+implemented/i)) {
            results.push(join(dir, entry.name));
          }
        }
      }
      return results;
    };
    const offending = searchDir(WORKBENCH_SRC);
    expect(offending).toEqual([]);
  });

  test("no hardcoded classifications in IntentClassifier", () => {
    const content = readFileSync(join(WORKBENCH_SRC, "services/IntentClassifier.ts"), "utf-8");
    // Should contain the OpenRouter URL (real API call, not mocked)
    expect(content).toContain("openrouter.ai");
    // Should NOT have a hardcoded return of a specific intent outside of UNKNOWN_INTENT
    // (examples in the system prompt template are OK — those are for the LLM, not canned responses)
    const lines = content.split('\n');
    const returnLines = lines.filter(l => l.trim().startsWith('return') && l.includes('intent:'));
    for (const line of returnLines) {
      // Only UNKNOWN_INTENT return is allowed
      if (line.includes('UNKNOWN_INTENT') || line.includes('"unknown"')) continue;
      // parseClassification returns from parsed LLM response — that's fine
      if (line.includes('parsed.intent')) continue;
      throw new Error(`Hardcoded classification return found: ${line.trim()}`);
    }
  });

  test.skip("command parser handles new command types (loom command parser removed in PR #74)", () => {
    const { parseCommand } = require("../../packages/loom/src/commands/parser");

    const settings = parseCommand("settings");
    expect(settings.type).toBe("settings");
    expect(settings.action).toBe("show");

    const setKey = parseCommand("settings set apikey sk-test-123");
    expect(setKey.type).toBe("settings");
    expect(setKey.action).toBe("set");
    expect(setKey.key).toBe("apikey");
    expect(setKey.value).toBe("sk-test-123");

    const flowList = parseCommand("flow list");
    expect(flowList.type).toBe("flow");
    expect(flowList.action).toBe("list");

    const flowStart = parseCommand("flow start create-job");
    expect(flowStart.type).toBe("flow");
    expect(flowStart.action).toBe("start");
    expect(flowStart.flowId).toBe("create-job");

    const intent = parseCommand("intent I need a plumber");
    expect(intent.type).toBe("intent");
    expect(intent.message).toBe("I need a plumber");
  });

  test.skip("existing commands still parse correctly (loom command parser removed in PR #74)", () => {
    const { parseCommand } = require("../../packages/loom/src/commands/parser");

    expect(parseCommand("help").type).toBe("help");
    expect(parseCommand("create object --type Job").type).toBe("create");
    expect(parseCommand("list objects --type Job").type).toBe("list");
    expect(parseCommand("inspect obj-123").type).toBe("inspect");
    expect(parseCommand("switch extension trades-services").type).toBe("switch");
    expect(parseCommand("show taxonomy").type).toBe("show");
    expect(parseCommand("step").type).toBe("step");
  });

  test("ConversationPanel imports intent classifier and flow services", () => {
    const content = readFileSync(join(WORKBENCH_SRC, "canvas/ConversationPanel.tsx"), "utf-8");
    expect(content).toContain("classifyIntent");
    expect(content).toContain("findFlow");
    expect(content).toContain("FlowRunner");
    expect(content).toContain("settingsStore");
    // Graceful degradation present
    expect(content).toContain("hasApiKey");
    expect(content).toContain("no classifier");
  });

  test("IdentityStore supports selective disclosure traits", () => {
    const content = readFileSync(join(WORKBENCH_SRC, "services/IdentityStore.ts"), "utf-8");
    expect(content).toContain("IdentityTraits");
    expect(content).toContain("disclosed");
    expect(content).toContain("hashed");
    expect(content).toContain("semantos.identity");
    expect(content).toContain("linkedIdentities");
  });
});

```
