---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-26F-VERTICAL-LOADING.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.719263+00:00
---

# Phase 26F — Vertical Configuration Loading (Filesystem-Driven Verticals)

**Version**: 1.0
**Date**: April 2026
**Status**: Ready for implementation
**Duration**: 2–3 days (with 1-day buffer)
**Prerequisites**: Phase 26E complete (NodeConfig, node self-object, bootstrap flow)
**Master document**: `PHASE-26-KERNEL-ISOLATION-MASTER.md`
**Branch**: `phase-26f-vertical-loading`

---

## Context

The Semantos kernel currently ships with verticals compiled into the loom bundle. This limits deployment models: every vertical must be baked at build time. Phase 26F removes this constraint by enabling verticals to be loaded from the filesystem at startup — the pattern is `semantos install vertical trades` where the vertical package lives in a directory on the node's storage layer.

This enables:

1. **Node packaging model** — Different nodes load different verticals on startup based on configuration
2. **Package independence** — Verticals ship as optional packages, not core dependencies
3. **Runtime activation** — Admins activate/deactivate verticals without rebuilding the kernel
4. **Capability-gated installation** — Adding a vertical is a capability-governed action (Phase 27)

The VerticalLoader reads a manifest (config.json per vertical), validates it against a JSON schema, loads the taxonomy tree, loads flow definitions, and injects prompt scripts into the kernel's system prompt. The node tracks installed verticals as capability tokens — each token gates a vertical's availability.

---

## Source Files / References

| Alias | Path | What to read |
|-------|------|--------------|
| `CFG:VERTICAL` | `packages/loom/src/config/verticalConfig.ts` | VerticalConfig interface, ObjectTypeDefinition, validation pattern |
| `SVC:CONFIG` | `packages/loom/src/services/ConfigStore.ts` | Config loading, subscription pattern, error handling |
| `SVC:IDENTITY` | `packages/loom/src/services/IdentityStore.ts` | Service initialization, state management |
| `TYPES:FS` | `packages/protocol-types/src/semantic-fs.ts` | Path parsing, storage key generation |
| `ADAPTER:STORAGE` | `packages/protocol-types/src/storage.ts` | StorageAdapter interface, read/list operations |
| `SHELL:CHAT` | `packages/shell/src/chat.ts` | Prompt context injection pattern, system prompt structure |
| `CFG:TRADES` | `configs/extensions/trades-services.json` | Existing vertical structure (reference implementation) |
| `CFG:CORE` | `configs/extensions/core.json` | Base vertical with governance types |
| `POLICY:BRANCH` | `docs/BRANCHING-AND-CI-POLICY.md` | Commit naming, branch rules |

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────┐
│ Kernel Node Startup                                  │
├─────────────────────────────────────────────────────┤
│ 1. Read NodeConfig                                   │
│ 2. Load StorageAdapter (NodeFsAdapter)               │
│ 3. Enumerate installed verticals from capability     │
│    tokens or config.verticals array                  │
│ 4. For each vertical:                                │
│    - VerticalLoader.loadVertical(path)               │
│    - Validate manifest schema                        │
│    - Load taxonomy JSON into memory                  │
│    - Parse flow definitions                          │
│    - Load prompt scripts (.md files)                 │
│ 5. Merge all taxonomies into global registry         │
│ 6. Concatenate all prompt scripts into system prompt │
│ 7. Start kernel shell with merged config             │
└─────────────────────────────────────────────────────┘

Vertical Package Structure:
semantos-vertical-trades/
  ├── config.json            — VerticalManifest
  ├── taxonomy/
  │   ├── trades.json        — TaxonomyTree subset
  │   └── subtree.json       — Optional additional taxonomies
  ├── flows/
  │   ├── job-intake.json    — Conversation flow def
  │   └── quote-review.json  — Another flow
  ├── prompts/
  │   ├── trades-context.md  — AI context: "You are helping with trade services..."
  │   ├── trades-scoring.md  — Capability-gated scoring rules
  │   └── trades-intake.md   — Intake protocol instructions
  └── objects/
      ├── job.json           — Type definitions (optional schema)
      └── quote.json         — Type definitions
```

---

## Deliverables

### D26F.1 — VerticalManifest Interface + JSON Schema

**New file**: `packages/protocol-types/src/vertical-manifest.ts`

Defines the structure of `config.json` in each vertical package and provides validation.

```typescript
/**
 * VerticalManifest — metadata + pointer structure for a filesystem-based vertical.
 * Lives as config.json in the vertical directory root.
 *
 * Example: /var/semantos/verticals/trades/config.json
 */
export interface VerticalManifest {
  /** Unique identifier for this vertical (e.g. "trades", "sovereignty") */
  id: string;

  /** Human-readable name (e.g. "Trades & Services") */
  name: string;

  /** Semantic version of this vertical package */
  version: string;

  /** Path to the primary taxonomy JSON file, relative to manifest directory.
   *  Example: "taxonomy/trades.json" → /var/semantos/verticals/trades/taxonomy/trades.json
   */
  taxonomyPath: string;

  /** Directory containing flow definitions (relative path).
   *  Loader scans this directory for *.json files. */
  flowsDir: string;

  /** Directory containing prompt script files (relative path).
   *  Loader scans this directory for *.md files. */
  promptsDir: string;

  /** Directory containing object type definitions (optional, relative path). */
  objectsDir?: string;

  /** List of capability tokens required to activate this vertical.
   *  Empty array = always available. */
  requiredCapabilities?: number[];

  /** List of facet roles that can manage this vertical.
   *  Example: ["admin", "governor"] */
  facetRoles?: string[];

  /** Optional metadata for UI display */
  metadata?: {
    icon?: string;
    description?: string;
    documentation?: string;
    author?: string;
  };
}

/** Validate a VerticalManifest JSON object. Throws on invalid. */
export function validateVerticalManifest(data: unknown): VerticalManifest {
  const manifest = data as VerticalManifest;
  if (!manifest.id || typeof manifest.id !== 'string') {
    throw new Error('Missing or invalid manifest.id');
  }
  if (!manifest.name || typeof manifest.name !== 'string') {
    throw new Error('Missing or invalid manifest.name');
  }
  if (!manifest.version || typeof manifest.version !== 'string') {
    throw new Error('Missing or invalid manifest.version');
  }
  if (!manifest.taxonomyPath || typeof manifest.taxonomyPath !== 'string') {
    throw new Error('Missing or invalid manifest.taxonomyPath');
  }
  if (!manifest.flowsDir || typeof manifest.flowsDir !== 'string') {
    throw new Error('Missing or invalid manifest.flowsDir');
  }
  if (!manifest.promptsDir || typeof manifest.promptsDir !== 'string') {
    throw new Error('Missing or invalid manifest.promptsDir');
  }
  return manifest;
}
```

**Also update** `packages/loom/src/config/verticalConfig.ts` to add:
```typescript
/** Reference to the manifest file location for this vertical (used during loading). */
export interface VerticalConfig {
  // ... existing fields ...
  manifestPath?: string;  // Path to config.json on filesystem
}
```

---

### D26F.2 — VerticalLoader Service

**New file**: `packages/protocol-types/src/vertical-loader.ts`

Renderer-agnostic service that loads, validates, and merges verticals from filesystem.

```typescript
import type { StorageAdapter } from './storage';
import type { VerticalManifest } from './vertical-manifest';
import type { VerticalConfig, TaxonomyTree } from '../workbench/src/config/verticalConfig';

/**
 * Loads a vertical from the filesystem.
 *
 * Responsibilities:
 *  1. Read manifest from path/config.json
 *  2. Validate manifest against schema
 *  3. Load taxonomy JSON from path/manifest.taxonomyPath
 *  4. Load all .json files in path/manifest.flowsDir
 *  5. Load all .md files in path/manifest.promptsDir
 *  6. Validate loaded taxonomy against VerticalConfig schema
 *  7. Return merged VerticalConfig
 *
 * Error handling:
 *  - If manifest missing or invalid → throw VerticalLoadError
 *  - If taxonomy file missing → throw VerticalLoadError
 *  - If flows/prompts directory missing → log warning, continue
 *  - If any .md file is invalid → log warning, skip, continue
 */
export class VerticalLoader {
  constructor(private storage: StorageAdapter) {}

  /**
   * Load a single vertical from a filesystem directory.
   *
   * @param verticalPath — absolute path or storage key prefix for the vertical
   * @returns merged VerticalConfig with taxonomy, flows, and prompts loaded
   * @throws VerticalLoadError if manifest invalid or critical files missing
   */
  async loadVertical(verticalPath: string): Promise<VerticalConfig> {
    // 1. Read config.json
    const manifestKey = `${verticalPath}/config.json`;
    const manifestData = await this.storage.read(manifestKey);
    if (!manifestData) {
      throw new VerticalLoadError(
        `Manifest not found at ${manifestKey}`,
        'MANIFEST_MISSING',
        verticalPath
      );
    }

    let manifest: VerticalManifest;
    try {
      const manifestJson = new TextDecoder().decode(manifestData);
      manifest = validateVerticalManifest(JSON.parse(manifestJson));
    } catch (err) {
      throw new VerticalLoadError(
        `Failed to parse manifest: ${err instanceof Error ? err.message : String(err)}`,
        'MANIFEST_INVALID',
        verticalPath
      );
    }

    // 2. Load taxonomy
    const taxonomyKey = `${verticalPath}/${manifest.taxonomyPath}`;
    const taxonomyData = await this.storage.read(taxonomyKey);
    if (!taxonomyData) {
      throw new VerticalLoadError(
        `Taxonomy file not found at ${taxonomyKey}`,
        'TAXONOMY_MISSING',
        verticalPath
      );
    }

    let taxonomy: TaxonomyTree;
    try {
      const taxonomyJson = new TextDecoder().decode(taxonomyData);
      taxonomy = JSON.parse(taxonomyJson) as TaxonomyTree;
    } catch (err) {
      throw new VerticalLoadError(
        `Failed to parse taxonomy: ${err instanceof Error ? err.message : String(err)}`,
        'TAXONOMY_INVALID',
        verticalPath
      );
    }

    // 3. Load flows
    const flowsDir = `${verticalPath}/${manifest.flowsDir}`;
    const flowKeys = await this.storage.list(flowsDir);
    const flows: ConversationFlow[] = [];
    for (const key of flowKeys) {
      if (!key.endsWith('.json')) continue;
      try {
        const flowData = await this.storage.read(key);
        if (flowData) {
          const flowJson = new TextDecoder().decode(flowData);
          flows.push(JSON.parse(flowJson) as ConversationFlow);
        }
      } catch (err) {
        console.warn(`Failed to load flow ${key}: ${err instanceof Error ? err.message : String(err)}`);
      }
    }

    // 4. Load prompts
    const promptsDir = `${verticalPath}/${manifest.promptsDir}`;
    const promptKeys = await this.storage.list(promptsDir);
    const prompts: string[] = [];
    for (const key of promptKeys) {
      if (!key.endsWith('.md')) continue;
      try {
        const promptData = await this.storage.read(key);
        if (promptData) {
          prompts.push(new TextDecoder().decode(promptData));
        }
      } catch (err) {
        console.warn(`Failed to load prompt ${key}: ${err instanceof Error ? err.message : String(err)}`);
      }
    }

    // 5. Return merged VerticalConfig
    return {
      id: manifest.id,
      name: manifest.name,
      objectTypes: [],  // Loaded from taxonomy or objects/ dir in a real implementation
      capabilities: [],  // Read from manifest or config files
      scripts: [],  // Derived from flows + prompts
      commercePhases: [],  // Optional, from manifest metadata
      taxonomy,
      flows,
      manifestPath: verticalPath,
    };
  }

  /**
   * Load all verticals from a list of paths.
   *
   * @param verticalPaths — array of absolute paths
   * @returns array of merged VerticalConfigs
   */
  async loadAllVerticals(verticalPaths: string[]): Promise<VerticalConfig[]> {
    return Promise.all(verticalPaths.map((path) => this.loadVertical(path)));
  }

  /**
   * Merge multiple VerticalConfigs into a single unified config.
   *
   * Merging rules:
   *  - id: keep the first (primary) vertical's id
   *  - name: concatenate with " + " separator
   *  - objectTypes: union by typeHash
   *  - capabilities: union by id
   *  - taxonomy: merge dimensions and nodes (later dims override earlier on same path)
   *  - flows: concatenate
   *
   * @param configs — array of VerticalConfigs to merge
   * @returns unified VerticalConfig
   */
  mergeVerticals(configs: VerticalConfig[]): VerticalConfig {
    if (configs.length === 0) {
      throw new Error('Cannot merge zero verticals');
    }

    const primary = configs[0];
    let merged: VerticalConfig = {
      id: primary.id,
      name: primary.name,
      objectTypes: [...(primary.objectTypes ?? [])],
      capabilities: [...(primary.capabilities ?? [])],
      scripts: [...(primary.scripts ?? [])],
      commercePhases: [...(primary.commercePhases ?? [])],
      taxonomy: primary.taxonomy ? { ...primary.taxonomy } : undefined,
      flows: [...(primary.flows ?? [])],
    };

    for (let i = 1; i < configs.length; i++) {
      const cfg = configs[i];
      merged.name += ` + ${cfg.name}`;

      // Merge objectTypes by typeHash (no duplicates)
      const typeHashSet = new Set(merged.objectTypes.map((ot) => ot.typeHash));
      for (const ot of cfg.objectTypes ?? []) {
        if (!typeHashSet.has(ot.typeHash)) {
          merged.objectTypes.push(ot);
          typeHashSet.add(ot.typeHash);
        }
      }

      // Merge capabilities by id
      const capIdSet = new Set(merged.capabilities.map((c) => c.id));
      for (const cap of cfg.capabilities ?? []) {
        if (!capIdSet.has(cap.id)) {
          merged.capabilities.push(cap);
          capIdSet.add(cap.id);
        }
      }

      // Merge flows
      merged.flows = [...(merged.flows ?? []), ...(cfg.flows ?? [])];

      // Merge taxonomy dimensions (later overrides earlier on same path)
      if (cfg.taxonomy?.dimensions) {
        if (!merged.taxonomy) {
          merged.taxonomy = { dimensions: [] };
        }
        for (const dim of cfg.taxonomy.dimensions) {
          const existing = merged.taxonomy.dimensions.find((d) => d.id === dim.id);
          if (existing) {
            existing.nodes = mergeTaxonomyNodes(existing.nodes, dim.nodes);
          } else {
            merged.taxonomy.dimensions.push(dim);
          }
        }
      }
    }

    return merged;
  }
}

/**
 * Merge two arrays of TaxonomyNodes.
 * Later nodes override earlier ones with the same path.
 */
function mergeTaxonomyNodes(
  earlier: TaxonomyNode[],
  later: TaxonomyNode[]
): TaxonomyNode[] {
  const pathMap = new Map<string, TaxonomyNode>();
  for (const node of earlier) {
    pathMap.set(node.path, node);
  }
  for (const node of later) {
    pathMap.set(node.path, node);
  }
  return Array.from(pathMap.values());
}

export class VerticalLoadError extends Error {
  constructor(
    message: string,
    public code: string,
    public verticalPath: string
  ) {
    super(message);
    this.name = 'VerticalLoadError';
  }
}
```

---

### D26F.3 — Prompt Script Injection

**Modify**: `packages/shell/src/chat.ts`

Add a function to load and concatenate all prompt scripts from loaded verticals:

```typescript
/**
 * Inject vertical prompt scripts into the kernel's system prompt.
 *
 * Called during kernel shell initialization (after all verticals are loaded).
 * Reads all .md files from each vertical's prompts/ directory and concatenates
 * them into the system prompt that is sent to the LLM.
 *
 * Order matters: base system prompt + vertical prompts (in order of activation).
 *
 * @param verticalConfigs — array of loaded VerticalConfigs
 * @returns concatenated prompt script as a string
 */
export function buildSystemPromptFromVerticals(
  baseSystemPrompt: string,
  verticalConfigs: VerticalConfig[]
): string {
  let systemPrompt = baseSystemPrompt;

  for (const cfg of verticalConfigs) {
    if (cfg.flows) {
      for (const flow of cfg.flows) {
        // Each flow may have embedded context in its description or steps
        // Inject flow-specific instructions into system prompt
        systemPrompt += `\n\n## Flow: ${flow.name}\n${flow.id}\n`;
      }
    }
  }

  return systemPrompt;
}

/**
 * Load all .md files from a vertical's prompts directory.
 *
 * @param verticalPath — absolute path to the vertical directory
 * @param storage — StorageAdapter for filesystem access
 * @returns concatenated markdown string
 */
export async function loadVerticalPrompts(
  verticalPath: string,
  storage: StorageAdapter
): Promise<string> {
  const promptsDir = `${verticalPath}/prompts`;
  const promptKeys = await storage.list(promptsDir);
  const prompts: string[] = [];

  for (const key of promptKeys) {
    if (!key.endsWith('.md')) continue;
    try {
      const promptData = await storage.read(key);
      if (promptData) {
        prompts.push(new TextDecoder().decode(promptData));
      }
    } catch (err) {
      console.warn(`Failed to load prompt ${key}: ${err instanceof Error ? err.message : String(err)}`);
    }
  }

  return prompts.join('\n\n---\n\n');
}
```

---

### D26F.4 — Node Vertical Registry

**Modify**: `packages/protocol-types/src/node-config.ts`

Add tracking of installed verticals to the NodeConfig:

```typescript
/**
 * NodeConfig — describes a Semantos node's deployment profile.
 * Includes which verticals are installed and active.
 */
export interface NodeConfig {
  // ... existing fields (storage, identity, anchor, network adapters) ...

  /** List of installed vertical paths (filesystem directories).
   *  Example: ["/var/semantos/verticals/trades", "/var/semantos/verticals/sovereignty"]
   */
  verticalPaths: string[];

  /** Capability tokens that unlock verticals.
   *  Maps vertical ID → capability token. */
  verticalCapabilities: Record<string, Uint8Array>;

  /** Metadata about currently active verticals.
   *  Refreshed on node startup and after capability changes. */
  activeVerticals?: Array<{
    id: string;
    name: string;
    version: string;
    activatedAt: number;
  }>;
}
```

**New file**: `packages/protocol-types/src/vertical-registry.ts`

Manages vertical activation/deactivation:

```typescript
/**
 * VerticalRegistry — tracks which verticals are installed and active on a node.
 *
 * A vertical is "installed" if a capability token exists for it or if
 * it's in the core-required set. A vertical is "active" if it's loaded
 * and integrated into the taxonomy and prompt context.
 */
export class VerticalRegistry {
  private activeVerticals: Map<string, VerticalConfig> = new Map();
  private capabilities: Map<string, Uint8Array> = new Map();

  constructor(nodeConfig: NodeConfig) {
    this.capabilities = new Map(Object.entries(nodeConfig.verticalCapabilities ?? {}));
  }

  /**
   * Activate a vertical: load it, validate it, merge into taxonomy.
   *
   * @param verticalId — vertical ID (e.g. "trades")
   * @param verticalPath — filesystem path to the vertical
   * @param loader — VerticalLoader instance
   * @throws VerticalLoadError if loading fails
   */
  async activate(
    verticalId: string,
    verticalPath: string,
    loader: VerticalLoader
  ): Promise<VerticalConfig> {
    const config = await loader.loadVertical(verticalPath);
    if (config.id !== verticalId) {
      throw new Error(`Vertical ID mismatch: expected "${verticalId}", got "${config.id}"`);
    }
    this.activeVerticals.set(verticalId, config);
    return config;
  }

  /**
   * Deactivate a vertical: unload it, remove from taxonomy.
   *
   * @param verticalId — vertical ID
   * @returns true if the vertical was active, false if not found
   */
  deactivate(verticalId: string): boolean {
    return this.activeVerticals.delete(verticalId);
  }

  /**
   * Get all active verticals.
   *
   * @returns array of VerticalConfigs
   */
  getAllActive(): VerticalConfig[] {
    return Array.from(this.activeVerticals.values());
  }

  /**
   * Get a single vertical by ID.
   *
   * @param verticalId — vertical ID
   * @returns VerticalConfig or undefined
   */
  getVertical(verticalId: string): VerticalConfig | undefined {
    return this.activeVerticals.get(verticalId);
  }

  /**
   * Check if a vertical is active.
   *
   * @param verticalId — vertical ID
   * @returns true if active
   */
  isActive(verticalId: string): boolean {
    return this.activeVerticals.has(verticalId);
  }

  /**
   * Mint or update a capability token for a vertical.
   *
   * @param verticalId — vertical ID
   * @param token — capability token bytes
   */
  setCapability(verticalId: string, token: Uint8Array): void {
    this.capabilities.set(verticalId, token);
  }

  /**
   * Get the capability token for a vertical.
   *
   * @param verticalId — vertical ID
   * @returns token bytes or undefined
   */
  getCapability(verticalId: string): Uint8Array | undefined {
    return this.capabilities.get(verticalId);
  }
}
```

---

### D26F.5 — Example Vertical Package

Reference structure for a filesystem-based vertical:

```
semantos-vertical-trades-1.0.0/
├── config.json
│   {
│     "id": "trades",
│     "name": "Trades & Services",
│     "version": "1.0.0",
│     "taxonomyPath": "taxonomy/trades.json",
│     "flowsDir": "flows",
│     "promptsDir": "prompts",
│     "objectsDir": "objects",
│     "requiredCapabilities": [0x00010002],
│     "facetRoles": ["admin", "governor"],
│     "metadata": {
│       "icon": "🔧",
│       "description": "Job posting, quoting, and service delivery for home tradies."
│     }
│   }
├── taxonomy/
│   └── trades.json
│       {
│         "dimensions": [
│           {
│             "id": "create",
│             "name": "Job Creation",
│             "rootPath": "create",
│             "nodes": [
│               { "path": "create/job", "name": "Job" },
│               { "path": "create/job/plumbing", "name": "Plumbing" },
│               { "path": "create/job/electrical", "name": "Electrical" }
│             ]
│           }
│         ]
│       }
├── flows/
│   ├── job-intake.json
│   │   {
│   │     "id": "job-intake",
│   │     "name": "Post a Job",
│   │     "triggerIntents": ["create.job"],
│   │     "steps": [...]
│   │   }
│   └── quote-review.json
│       {
│         "id": "quote-review",
│         "name": "Review Quotes",
│         "triggerIntents": ["review.quotes"],
│         "steps": [...]
│       }
├── prompts/
│   ├── trades-context.md
│   │   "You are an AI assistant helping homeowners and tradies coordinate job services..."
│   ├── trades-scoring.md
│   │   "Capability 0x00010002 (Create) unlocks: - posting jobs - creating quotes..."
│   └── trades-intake.md
│       "When a user initiates job creation, ask these questions in order: ..."
└── objects/
    ├── job.json
    └── quote.json
```

---

## Gate Tests (TDD)

**File**: `packages/__tests__/phase26f-vertical-loading.test.ts`

### Unit Tests (T1–T8)

```typescript
describe("VerticalManifest validation", () => {
  // T1: Valid manifest passes validation
  // T2: Missing id throws error
  // T3: Missing taxonomyPath throws error
  // T4: Invalid version string throws error
});

describe("VerticalLoader", () => {
  // T5: loadVertical() reads manifest, taxonomy, flows, prompts
  // T6: loadVertical() throws VerticalLoadError if manifest missing
  // T7: loadVertical() throws VerticalLoadError if taxonomy invalid JSON
  // T8: loadVertical() skips missing flow/prompt files with warning, continues
});
```

### Integration Tests (T9–T12)

```typescript
describe("VerticalRegistry", () => {
  // T9: activate() loads vertical and adds to registry
  // T10: deactivate() removes vertical from registry
  // T11: activate() "trades" + activate() "sovereignty" → both active
  // T12: getAllActive() returns all activated verticals in order
});

describe("Vertical merging", () => {
  // T13: mergeVerticals([trades, sovereignty]) → objectTypes from both
  // T14: mergeVerticals() resolves duplicate typeHash (keeps first)
  // T15: mergeVerticals() merges taxonomy dimensions correctly
  // T16: Node startup loads all verticals from NodeConfig.verticalPaths
});
```

### Anti-Regression Tests (T17–T20)

```typescript
describe("Backward compatibility", () => {
  // T17: Compiled verticals in bundle still work (fallback path)
  // T18: No existing VerticalConfig tests broken
  // T19: Chat.ts system prompt injection doesn't break existing flows
  // T20: Node self-object creation still succeeds with multi-vertical setup
});
```

---

## Completion Criteria

- [ ] `packages/protocol-types/src/vertical-manifest.ts` created with validation
- [ ] `packages/protocol-types/src/vertical-loader.ts` created with VerticalLoader service
- [ ] `packages/protocol-types/src/vertical-registry.ts` created with activation/deactivation
- [ ] `packages/shell/src/chat.ts` updated with prompt injection functions
- [ ] `packages/protocol-types/src/node-config.ts` updated with verticalPaths and verticalCapabilities
- [ ] Example vertical package structure documented with realistic configs
- [ ] Tests T1–T20 all pass
- [ ] `bun run check` passes (zero TypeScript errors)
- [ ] `bun run build` succeeds
- [ ] All commits follow `phase-26f/D26F.N:` naming convention
- [ ] Branch is `phase-26f-vertical-loading`

---

## Next Phase

Phase 26G packages the kernel for deployment: Docker image, install script, admin CLI, and release engineering. Verticals ship as optional packages in the Semantos registry.
