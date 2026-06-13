---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/tests/gates/phase26f-extension-loading.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.562365+00:00
---

# tests/gates/phase26f-extension-loading.test.ts

```ts
/**
 * Phase 26F Gate: Extension Configuration Loading
 *
 * Validates:
 * 1. ExtensionManifest validation (T1–T4)
 * 2. ExtensionLoader load and merge (T5–T8)
 * 3. ExtensionRegistry activation/deactivation (T9–T12)
 * 4. Extension merging correctness (T13–T16)
 * 5. Backward compatibility (T17–T20)
 */

import { describe, test, expect } from "bun:test";
import { readFileSync } from "fs";
import { join } from "path";

const ROOT = join(import.meta.dir, "../..");

// ── Helpers ──────────────────────────────────────────────────────

function requireModule(path: string) {
  return require(join(ROOT, path));
}

/**
 * Populate a MemoryAdapter with a realistic extension package.
 *
 * Creates config.json, taxonomy, flows, and prompts at the given prefix.
 */
async function populateExtension(
  adapter: InstanceType<typeof MemoryAdapter>,
  prefix: string,
  manifest: Record<string, unknown>,
  taxonomy: Record<string, unknown>,
  flows?: Array<Record<string, unknown>>,
  prompts?: string[],
) {
  const enc = new TextEncoder();
  await adapter.write(`${prefix}/config.json`, enc.encode(JSON.stringify(manifest)));
  const taxPath = (manifest.taxonomyPath as string) ?? "taxonomy/main.json";
  await adapter.write(`${prefix}/${taxPath}`, enc.encode(JSON.stringify(taxonomy)));

  if (flows) {
    const flowsDir = (manifest.flowsDir as string) ?? "flows";
    for (let i = 0; i < flows.length; i++) {
      await adapter.write(
        `${prefix}/${flowsDir}/flow-${i}.json`,
        enc.encode(JSON.stringify(flows[i])),
      );
    }
  }

  if (prompts) {
    const promptsDir = (manifest.promptsDir as string) ?? "prompts";
    for (let i = 0; i < prompts.length; i++) {
      await adapter.write(
        `${prefix}/${promptsDir}/prompt-${i}.md`,
        enc.encode(prompts[i]),
      );
    }
  }
}

// ── Lazy imports ─────────────────────────────────────────────────

const { MemoryAdapter } = requireModule("core/protocol-types/src/adapters/memory-adapter.ts");
const { validateExtensionManifest } = requireModule("core/protocol-types/src/extension-manifest.ts");
const { ExtensionLoader, ExtensionLoadError } = requireModule("core/protocol-types/src/extension-loader.ts");
const { ExtensionRegistry } = requireModule("core/protocol-types/src/extension-registry.ts");
const { validateExtensionConfig } = requireModule("runtime/services/src/config/extensionConfig.ts");

// ── Test Data ────────────────────────────────────────────────────

const VALID_MANIFEST = {
  id: "trades",
  name: "Trades & Services",
  version: "1.0.0",
  taxonomyPath: "taxonomy/trades.json",
  flowsDir: "flows",
  promptsDir: "prompts",
  objectsDir: "objects",
  requiredCapabilities: [0x00010002],
  hatRoles: ["admin", "governor"],
  metadata: { icon: "wrench", description: "Trade services extension" },
};

const VALID_TAXONOMY = {
  dimensions: [
    {
      id: "create",
      name: "Job Creation",
      rootPath: "create",
      nodes: [
        { path: "create/job", name: "Job" },
        { path: "create/job/plumbing", name: "Plumbing" },
        { path: "create/job/electrical", name: "Electrical" },
      ],
    },
  ],
};

const SOVEREIGNTY_MANIFEST = {
  id: "sovereignty",
  name: "Sovereignty",
  version: "1.0.0",
  taxonomyPath: "taxonomy/sovereignty.json",
  flowsDir: "flows",
  promptsDir: "prompts",
};

const SOVEREIGNTY_TAXONOMY = {
  dimensions: [
    {
      id: "govern",
      name: "Governance",
      rootPath: "govern",
      nodes: [
        { path: "govern/node", name: "Node" },
        { path: "govern/extension", name: "Extension" },
      ],
    },
  ],
};

const SAMPLE_FLOW = {
  id: "job-intake",
  name: "Post a Job",
  triggerIntents: ["create.job"],
  steps: [
    { id: "step1", prompt: "What kind of job?", field: "category", validation: "required" },
  ],
  onComplete: { type: "create", objectType: "Job" },
};

const SAMPLE_FLOW_2 = {
  id: "quote-review",
  name: "Review Quotes",
  triggerIntents: ["review.quotes"],
  steps: [
    { id: "step1", prompt: "Which quotes?", validation: "required" },
  ],
  onComplete: { type: "navigate", targetPath: "/quotes" },
};

// ── Gate 1: ExtensionManifest Validation (T1–T4) ─────────────────

describe("Phase 26F — ExtensionManifest validation", () => {
  test("T1: valid manifest passes validation", () => {
    const result = validateExtensionManifest(VALID_MANIFEST);
    expect(result.id).toBe("trades");
    expect(result.name).toBe("Trades & Services");
    expect(result.version).toBe("1.0.0");
    expect(result.taxonomyPath).toBe("taxonomy/trades.json");
    expect(result.flowsDir).toBe("flows");
    expect(result.promptsDir).toBe("prompts");
    expect(result.objectsDir).toBe("objects");
    expect(result.requiredCapabilities).toEqual([0x00010002]);
    expect(result.hatRoles).toEqual(["admin", "governor"]);
  });

  test("T2: missing id throws error", () => {
    const bad = { ...VALID_MANIFEST, id: undefined };
    expect(() => validateExtensionManifest(bad)).toThrow("manifest.id");
  });

  test("T3: missing taxonomyPath throws error", () => {
    const bad = { ...VALID_MANIFEST, taxonomyPath: undefined };
    expect(() => validateExtensionManifest(bad)).toThrow("manifest.taxonomyPath");
  });

  test("T4: empty version string throws error", () => {
    const bad = { ...VALID_MANIFEST, version: "" };
    expect(() => validateExtensionManifest(bad)).toThrow("manifest.version");
  });
});

// ── Gate 2: ExtensionLoader (T5–T8) ──────────────────────────────

describe("Phase 26F — ExtensionLoader", () => {
  test("T5: loadExtension() reads manifest, taxonomy, flows, prompts", async () => {
    const adapter = new MemoryAdapter();
    await populateExtension(
      adapter,
      "extensions/trades",
      VALID_MANIFEST,
      VALID_TAXONOMY,
      [SAMPLE_FLOW, SAMPLE_FLOW_2],
      ["You are a trades assistant.", "Handle job intake carefully."],
    );

    const loader = new ExtensionLoader(adapter);
    const config = await loader.loadExtension("extensions/trades");

    expect(config.id).toBe("trades");
    expect(config.name).toBe("Trades & Services");
    expect(config.manifestPath).toBe("extensions/trades");
    expect(config.taxonomy).toBeDefined();
    expect(config.taxonomy!.dimensions).toHaveLength(1);
    expect(config.taxonomy!.dimensions[0].id).toBe("create");
    expect(config.taxonomy!.dimensions[0].nodes).toHaveLength(3);
    expect(config.flows).toHaveLength(2);
    expect(config.flows![0].id).toBe("job-intake");
    expect(config.flows![1].id).toBe("quote-review");
  });

  test("T6: loadExtension() throws MANIFEST_MISSING when config.json absent", async () => {
    const adapter = new MemoryAdapter();
    const loader = new ExtensionLoader(adapter);

    try {
      await loader.loadExtension("extensions/nonexistent");
      throw new Error("Should have thrown");
    } catch (err: unknown) {
      expect(err).toBeInstanceOf(ExtensionLoadError);
      const vle = err as InstanceType<typeof ExtensionLoadError>;
      expect(vle.code).toBe("MANIFEST_MISSING");
      expect(vle.extensionPath).toBe("extensions/nonexistent");
    }
  });

  test("T7: loadExtension() throws TAXONOMY_INVALID when taxonomy is bad JSON", async () => {
    const adapter = new MemoryAdapter();
    const enc = new TextEncoder();
    await adapter.write(
      "extensions/bad/config.json",
      enc.encode(JSON.stringify(VALID_MANIFEST)),
    );
    await adapter.write(
      "extensions/bad/taxonomy/trades.json",
      enc.encode("not valid json {{{"),
    );

    const loader = new ExtensionLoader(adapter);

    try {
      await loader.loadExtension("extensions/bad");
      throw new Error("Should have thrown");
    } catch (err: unknown) {
      expect(err).toBeInstanceOf(ExtensionLoadError);
      const vle = err as InstanceType<typeof ExtensionLoadError>;
      expect(vle.code).toBe("TAXONOMY_INVALID");
      expect(vle.extensionPath).toBe("extensions/bad");
    }
  });

  test("T8: loadExtension() skips missing flow/prompt files, continues", async () => {
    const adapter = new MemoryAdapter();
    // Populate manifest and taxonomy only — no flows or prompts directories
    const enc = new TextEncoder();
    await adapter.write(
      "extensions/minimal/config.json",
      enc.encode(JSON.stringify(VALID_MANIFEST)),
    );
    await adapter.write(
      "extensions/minimal/taxonomy/trades.json",
      enc.encode(JSON.stringify(VALID_TAXONOMY)),
    );
    // No flows/ or prompts/ entries — list() returns empty

    const loader = new ExtensionLoader(adapter);
    const config = await loader.loadExtension("extensions/minimal");

    expect(config.id).toBe("trades");
    expect(config.taxonomy).toBeDefined();
    expect(config.flows).toHaveLength(0);
  });
});

// ── Gate 3: ExtensionRegistry (T9–T12) ───────────────────────────

describe("Phase 26F — ExtensionRegistry", () => {
  test("T9: activate() loads extension and adds to registry", async () => {
    const adapter = new MemoryAdapter();
    await populateExtension(adapter, "v/trades", VALID_MANIFEST, VALID_TAXONOMY, [SAMPLE_FLOW]);

    const loader = new ExtensionLoader(adapter);
    const registry = new ExtensionRegistry({ extensions: ["v/trades"] } as any);

    const config = await registry.activate("trades", "v/trades", loader);
    expect(config.id).toBe("trades");
    expect(registry.isActive("trades")).toBe(true);
    expect(registry.getExtension("trades")).toBe(config);
  });

  test("T10: deactivate() removes extension, returns false on second call", async () => {
    const adapter = new MemoryAdapter();
    await populateExtension(adapter, "v/trades", VALID_MANIFEST, VALID_TAXONOMY);

    const loader = new ExtensionLoader(adapter);
    const registry = new ExtensionRegistry({ extensions: [] } as any);

    await registry.activate("trades", "v/trades", loader);
    expect(registry.deactivate("trades")).toBe(true);
    expect(registry.isActive("trades")).toBe(false);
    expect(registry.getExtension("trades")).toBeUndefined();
    expect(registry.deactivate("trades")).toBe(false);
  });

  test("T11: activate trades + sovereignty → both active", async () => {
    const adapter = new MemoryAdapter();
    await populateExtension(adapter, "v/trades", VALID_MANIFEST, VALID_TAXONOMY);
    await populateExtension(adapter, "v/sovereignty", SOVEREIGNTY_MANIFEST, SOVEREIGNTY_TAXONOMY);

    const loader = new ExtensionLoader(adapter);
    const registry = new ExtensionRegistry({ extensions: [] } as any);

    await registry.activate("trades", "v/trades", loader);
    await registry.activate("sovereignty", "v/sovereignty", loader);

    expect(registry.isActive("trades")).toBe(true);
    expect(registry.isActive("sovereignty")).toBe(true);
    expect(registry.getAllActive()).toHaveLength(2);
  });

  test("T12: getAllActive() returns extensions in activation order", async () => {
    const adapter = new MemoryAdapter();
    await populateExtension(adapter, "v/trades", VALID_MANIFEST, VALID_TAXONOMY);
    await populateExtension(adapter, "v/sovereignty", SOVEREIGNTY_MANIFEST, SOVEREIGNTY_TAXONOMY);

    const loader = new ExtensionLoader(adapter);
    const registry = new ExtensionRegistry({ extensions: [] } as any);

    await registry.activate("trades", "v/trades", loader);
    await registry.activate("sovereignty", "v/sovereignty", loader);

    const all = registry.getAllActive();
    expect(all[0].id).toBe("trades");
    expect(all[1].id).toBe("sovereignty");
  });
});

// ── Gate 4: Extension Merging (T13–T16) ──────────────────────────

describe("Phase 26F — Extension merging", () => {
  test("T13: mergeExtensions([trades, sovereignty]) → union of objectTypes by typeHash", () => {
    const loader = new ExtensionLoader(new MemoryAdapter());

    const tradesConfig = {
      id: "trades",
      name: "Trades",
      objectTypes: [
        { typeHash: "aaa111", name: "Job", icon: "briefcase", linearity: "AFFINE", defaultCapabilities: [], fields: [] },
      ],
      capabilities: [{ id: 1, name: "View", description: "View access" }],
      scripts: [],
      commercePhases: [],
      taxonomy: VALID_TAXONOMY,
      flows: [SAMPLE_FLOW],
    };

    const sovereigntyConfig = {
      id: "sovereignty",
      name: "Sovereignty",
      objectTypes: [
        { typeHash: "bbb222", name: "Node", icon: "server", linearity: "RELEVANT", defaultCapabilities: [], fields: [] },
      ],
      capabilities: [{ id: 2, name: "Govern", description: "Governance" }],
      scripts: [],
      commercePhases: [],
      taxonomy: SOVEREIGNTY_TAXONOMY,
      flows: [],
    };

    const merged = loader.mergeExtensions([tradesConfig as any, sovereigntyConfig as any]);

    expect(merged.objectTypes).toHaveLength(2);
    expect(merged.objectTypes[0].typeHash).toBe("aaa111");
    expect(merged.objectTypes[1].typeHash).toBe("bbb222");
    expect(merged.capabilities).toHaveLength(2);
    expect(merged.flows).toHaveLength(1);
    expect(merged.name).toBe("Trades + Sovereignty");
  });

  test("T14: mergeExtensions() with duplicate typeHash keeps first", () => {
    const loader = new ExtensionLoader(new MemoryAdapter());

    const config1 = {
      id: "a", name: "A",
      objectTypes: [{ typeHash: "same-hash", name: "First", icon: "a", linearity: "AFFINE", defaultCapabilities: [], fields: [] }],
      capabilities: [], scripts: [], commercePhases: [],
    };
    const config2 = {
      id: "b", name: "B",
      objectTypes: [{ typeHash: "same-hash", name: "Second", icon: "b", linearity: "LINEAR", defaultCapabilities: [], fields: [] }],
      capabilities: [], scripts: [], commercePhases: [],
    };

    const merged = loader.mergeExtensions([config1 as any, config2 as any]);
    expect(merged.objectTypes).toHaveLength(1);
    expect(merged.objectTypes[0].name).toBe("First");
  });

  test("T15: mergeExtensions() merges taxonomy dimensions by id, nodes by path", () => {
    const loader = new ExtensionLoader(new MemoryAdapter());

    const config1 = {
      id: "a", name: "A",
      objectTypes: [], capabilities: [], scripts: [], commercePhases: [],
      taxonomy: {
        dimensions: [{
          id: "create", name: "Create", rootPath: "create",
          nodes: [
            { path: "create/job", name: "Job" },
            { path: "create/job/plumbing", name: "Plumbing" },
          ],
        }],
      },
    };
    const config2 = {
      id: "b", name: "B",
      objectTypes: [], capabilities: [], scripts: [], commercePhases: [],
      taxonomy: {
        dimensions: [
          {
            id: "create", name: "Create", rootPath: "create",
            nodes: [
              { path: "create/job/plumbing", name: "Plumbing (Override)" },
              { path: "create/job/electrical", name: "Electrical" },
            ],
          },
          {
            id: "govern", name: "Govern", rootPath: "govern",
            nodes: [{ path: "govern/node", name: "Node" }],
          },
        ],
      },
    };

    const merged = loader.mergeExtensions([config1 as any, config2 as any]);
    expect(merged.taxonomy!.dimensions).toHaveLength(2);

    const createDim = merged.taxonomy!.dimensions.find((d: any) => d.id === "create")!;
    expect(createDim.nodes).toHaveLength(3);
    const plumbingNode = createDim.nodes.find((n: any) => n.path === "create/job/plumbing")!;
    expect(plumbingNode.name).toBe("Plumbing (Override)");

    const governDim = merged.taxonomy!.dimensions.find((d: any) => d.id === "govern")!;
    expect(governDim.nodes).toHaveLength(1);
  });

  test("T16: full startup flow — adapter, loader, registry, activate from NodeConfig.extensions", async () => {
    const adapter = new MemoryAdapter();
    await populateExtension(adapter, "v/trades", VALID_MANIFEST, VALID_TAXONOMY, [SAMPLE_FLOW]);
    await populateExtension(adapter, "v/sovereignty", SOVEREIGNTY_MANIFEST, SOVEREIGNTY_TAXONOMY);

    const loader = new ExtensionLoader(adapter);
    const nodeConfig = {
      extensions: ["v/trades", "v/sovereignty"],
    } as any;

    const registry = new ExtensionRegistry(nodeConfig);

    // Simulate startup: activate each extension from config
    for (const extensionPath of nodeConfig.extensions) {
      const manifestData = await adapter.read(`${extensionPath}/config.json`);
      const manifest = JSON.parse(new TextDecoder().decode(manifestData!));
      await registry.activate(manifest.id, extensionPath, loader);
    }

    expect(registry.getAllActive()).toHaveLength(2);
    expect(registry.isActive("trades")).toBe(true);
    expect(registry.isActive("sovereignty")).toBe(true);

    // Merge and verify
    const merged = loader.mergeExtensions(registry.getAllActive());
    expect(merged.taxonomy!.dimensions).toHaveLength(2);
    expect(merged.flows).toHaveLength(1);
    expect(merged.flows![0].id).toBe("job-intake");
  });
});

// ── Gate 5: Backward Compatibility (T17–T20) ────────────────────

describe("Phase 26F — Backward compatibility", () => {
  test("T17: existing bundled extension configs still pass validateExtensionConfig", () => {
    const tradesJson = JSON.parse(
      readFileSync(join(ROOT, "configs/extensions/trades-services.json"), "utf-8"),
    );
    const coreJson = JSON.parse(
      readFileSync(join(ROOT, "configs/extensions/core.json"), "utf-8"),
    );

    expect(() => validateExtensionConfig(tradesJson)).not.toThrow();
    expect(() => validateExtensionConfig(coreJson)).not.toThrow();
  });

  test("T18: ExtensionConfig with manifestPath is backward-compatible", () => {
    const coreJson = JSON.parse(
      readFileSync(join(ROOT, "configs/extensions/core.json"), "utf-8"),
    );

    // Add manifestPath — should not break validation
    coreJson.manifestPath = "/var/semantos/extensions/core";
    expect(() => validateExtensionConfig(coreJson)).not.toThrow();

    // Without manifestPath — also fine
    delete coreJson.manifestPath;
    expect(() => validateExtensionConfig(coreJson)).not.toThrow();
  });

  test("T19: buildSystemPromptFromExtensions preserves base prompt when no extensions", () => {
    const { buildSystemPromptFromExtensions } = requireModule("runtime/shell/src/prompt-injection.ts");

    const base = "You are a Semantos kernel assistant.";
    const result = buildSystemPromptFromExtensions(base, []);
    expect(result).toBe(base);
  });

  test("T20: mergeExtensions does not mutate input arrays", () => {
    const loader = new ExtensionLoader(new MemoryAdapter());

    const config1 = {
      id: "a", name: "A",
      objectTypes: [{ typeHash: "hash1", name: "T1", icon: "a", linearity: "AFFINE", defaultCapabilities: [], fields: [] }],
      capabilities: [{ id: 1, name: "Cap1", description: "c1" }],
      scripts: [], commercePhases: [],
      flows: [SAMPLE_FLOW],
      taxonomy: { dimensions: [{ id: "d1", name: "D1", rootPath: "d1", nodes: [{ path: "d1/a", name: "A" }] }] },
    };
    const config2 = {
      id: "b", name: "B",
      objectTypes: [{ typeHash: "hash2", name: "T2", icon: "b", linearity: "LINEAR", defaultCapabilities: [], fields: [] }],
      capabilities: [{ id: 2, name: "Cap2", description: "c2" }],
      scripts: [], commercePhases: [],
      flows: [SAMPLE_FLOW_2],
      taxonomy: { dimensions: [{ id: "d2", name: "D2", rootPath: "d2", nodes: [{ path: "d2/b", name: "B" }] }] },
    };

    // Snapshot original lengths
    const origOt1 = config1.objectTypes.length;
    const origOt2 = config2.objectTypes.length;
    const origFlows1 = config1.flows.length;
    const origFlows2 = config2.flows.length;
    const origDims1 = config1.taxonomy.dimensions.length;
    const origDims2 = config2.taxonomy.dimensions.length;

    loader.mergeExtensions([config1 as any, config2 as any]);

    // Inputs must not be mutated
    expect(config1.objectTypes.length).toBe(origOt1);
    expect(config2.objectTypes.length).toBe(origOt2);
    expect(config1.flows.length).toBe(origFlows1);
    expect(config2.flows.length).toBe(origFlows2);
    expect(config1.taxonomy.dimensions.length).toBe(origDims1);
    expect(config2.taxonomy.dimensions.length).toBe(origDims2);
  });
});

```
