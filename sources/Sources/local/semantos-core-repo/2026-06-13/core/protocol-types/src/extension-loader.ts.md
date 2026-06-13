---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/extension-loader.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.851509+00:00
---

# core/protocol-types/src/extension-loader.ts

```ts
/**
 * ExtensionLoader — loads, validates, and merges extensions from filesystem.
 *
 * Renderer-agnostic service. Reads extension packages via StorageAdapter,
 * validates manifests, loads taxonomy trees, flow definitions, and prompt
 * scripts. Returns merged ExtensionConfig ready for the kernel.
 *
 * Cross-references:
 *   extension-manifest.ts → ExtensionManifest, validateExtensionManifest
 *   storage.ts           → StorageAdapter (read, list)
 *   extensionConfig.ts    → ExtensionConfig, TaxonomyTree, ConversationFlow
 */

import type { StorageAdapter } from './storage';
import type { ExtensionManifest } from './extension-manifest';
import { validateExtensionManifest } from './extension-manifest';
import type {
  ExtensionConfig,
  TaxonomyTree,
  TaxonomyNode,
  TaxonomyDimensionDef,
  ConversationFlow,
} from './extension-config-types';

// ── Error Type ───────────────────────────────────────────────────

export type ExtensionLoadErrorCode =
  | 'MANIFEST_MISSING'
  | 'MANIFEST_INVALID'
  | 'TAXONOMY_MISSING'
  | 'TAXONOMY_INVALID';

/**
 * Error thrown when loading an extension fails.
 *
 * The `code` field identifies the failure category.
 * The `extensionPath` field identifies which extension failed.
 */
export class ExtensionLoadError extends Error {
  constructor(
    message: string,
    public readonly code: ExtensionLoadErrorCode,
    public readonly extensionPath: string,
  ) {
    super(message);
    this.name = 'ExtensionLoadError';
  }
}

// ── ExtensionLoader ───────────────────────────────────────────────

/**
 * Loads extensions from filesystem via StorageAdapter.
 *
 * Responsibilities:
 *  1. Read manifest from path/config.json
 *  2. Validate manifest against schema
 *  3. Load taxonomy JSON from path/manifest.taxonomyPath
 *  4. Load all .json files in path/manifest.flowsDir
 *  5. Load all .md files in path/manifest.promptsDir
 *  6. Return merged ExtensionConfig
 *
 * Error handling:
 *  - Manifest missing or invalid → throw ExtensionLoadError
 *  - Taxonomy file missing or invalid → throw ExtensionLoadError
 *  - Flows/prompts directory missing or individual files fail → warn, continue
 */
/**
 * Wave Cap-Substrate Decision-A loader hook. When set, `loadExtension`
 * invokes it after manifest validation and BEFORE loading any
 * taxonomy/flows — a cartridge whose affine PushDrop license fails the
 * check never activates. Default unset = current behaviour (non-breaking;
 * mandatory enforcement for non-first-party cartridges is sequenced
 * after DLO.1c — marketplace doc §4). Implemented by
 * `verifyCartridgeLicense` (identity-adapters/cartridge-license.ts).
 */
export type CartridgeLicenseGate = (
  manifest: ExtensionManifest,
  extensionPath: string,
) => Promise<void>;

export class ExtensionLoader {
  constructor(private storage: StorageAdapter) {}

  private licenseGate?: CartridgeLicenseGate;

  /** Install the Decision-A license gate (opt-in). The gate MUST throw
   *  (an `ExtensionLoadError`) to reject an unlicensed cartridge. */
  setLicenseGate(gate: CartridgeLicenseGate): void {
    this.licenseGate = gate;
  }

  // ── CC2a — consumes/provides resolver (Wave Canonical-Cartridge) ───
  //
  // docs/design/CANONICAL-CARTRIDGE-MODEL.md (Decision-B composition).
  // The Brain shell must load cartridges in dependency order — infra
  // (which `provides` adapter interfaces) before experience (which
  // `consumes` them) — and reject an experience cartridge whose
  // *cartridge-provided* consumed interface is unmet. Runtime adapters
  // (Storage/Identity/Anchor/Network/wss…) are injected by the host,
  // not by a cartridge, so they are exempt from the unmet check.

  /**
   * Topologically order cartridges infra-before-experience and build
   * the provides registry. Pure (no I/O) so it is unit-testable.
   *
   * @throws ExtensionLoadError on a duplicate provided interface, or
   *   an experience cartridge consuming a cartridge-interface nothing
   *   provides (Decision-B fail-closed — a clean capability failure).
   */
  static resolveCartridgeOrder(
    entries: ReadonlyArray<{
      id: string;
      role?: 'infra' | 'experience' | 'grammar-lexicon';
      provides?: readonly string[];
      consumes?: Record<string, unknown>;
    }>,
  ): { order: string[]; providesRegistry: Map<string, string> } {
    const EXEMPT_RUNTIME = new Set([
      'StorageAdapter',
      'IdentityAdapter',
      'AnchorAdapter',
      'NetworkAdapter',
      'wssSubprotocolRegistry',
    ]);
    const providesRegistry = new Map<string, string>();
    for (const e of entries) {
      if (e.role !== 'infra') continue;
      for (const iface of e.provides ?? []) {
        if (providesRegistry.has(iface)) {
          throw new ExtensionLoadError(
            `duplicate provided interface "${iface}" (${providesRegistry.get(iface)} and ${e.id})`,
            'MANIFEST_INVALID',
            e.id,
          );
        }
        providesRegistry.set(iface, e.id);
      }
    }
    for (const e of entries) {
      if (e.role === 'infra') continue;
      for (const iface of Object.keys(e.consumes ?? {})) {
        if (EXEMPT_RUNTIME.has(iface)) continue; // host-injected
        if (!providesRegistry.has(iface)) {
          throw new ExtensionLoadError(
            `cartridge "${e.id}" consumes "${iface}" but no infra cartridge provides it (Decision-B)`,
            'MANIFEST_INVALID',
            e.id,
          );
        }
      }
    }
    // infra first (stable), then everything else (stable).
    const infra = entries.filter((e) => e.role === 'infra').map((e) => e.id);
    const rest = entries.filter((e) => e.role !== 'infra').map((e) => e.id);
    return { order: [...infra, ...rest], providesRegistry };
  }

  /** Peek a cartridge manifest (prefers `cartridge.json`, falls back
   *  to legacy `config.json`) without loading taxonomy/flows. */
  private async peekManifest(path: string): Promise<ExtensionManifest> {
    for (const name of ['cartridge.json', 'config.json']) {
      const data = await this.storage.read(`${path}/${name}`);
      if (data) {
        try {
          return validateExtensionManifest(JSON.parse(new TextDecoder().decode(data)));
        } catch (err) {
          if (err instanceof ExtensionLoadError) throw err;
          throw new ExtensionLoadError(
            `Failed to parse manifest at ${path}/${name}: ${err instanceof Error ? err.message : String(err)}`,
            'MANIFEST_INVALID',
            path,
          );
        }
      }
    }
    throw new ExtensionLoadError(`Manifest not found at ${path}`, 'MANIFEST_MISSING', path);
  }

  /**
   * CC2a — the canonical Brain-shell load: resolve consumes/provides,
   * order infra→experience, then `loadExtension` each in order (the
   * license gate already applies per-cartridge inside loadExtension).
   * Returns the load order + provides registry alongside the configs.
   */
  async loadCartridges(
    paths: string[],
  ): Promise<{
    configs: ExtensionConfig[];
    order: string[];
    providesRegistry: Map<string, string>;
  }> {
    const peeked = await Promise.all(
      paths.map(async (p) => ({ path: p, m: await this.peekManifest(p) })),
    );
    const idToPath = new Map(
      peeked.map(({ path, m }) => [m.id, path]),
    );
    const { order, providesRegistry } = ExtensionLoader.resolveCartridgeOrder(
      peeked.map(({ m }) => ({
        id: m.id,
        role: (m as { role?: 'infra' | 'experience' | 'grammar-lexicon' }).role,
        provides: (m as { provides?: readonly string[] }).provides,
        consumes: (m as { consumes?: Record<string, unknown> }).consumes,
      })),
    );
    const configs: ExtensionConfig[] = [];
    for (const id of order) {
      const path = idToPath.get(id)!;
      configs.push(await this.loadExtension(path));
    }
    return { configs, order, providesRegistry };
  }

  /**
   * Load a single extension from a filesystem directory.
   *
   * @param extensionPath — storage key prefix for the extension directory
   * @returns ExtensionConfig with taxonomy, flows, and prompts loaded
   * @throws ExtensionLoadError if manifest invalid or critical files missing
   */
  async loadExtension(extensionPath: string): Promise<ExtensionConfig> {
    // 1. Read and validate manifest
    const manifestKey = `${extensionPath}/config.json`;
    const manifestData = await this.storage.read(manifestKey);
    if (!manifestData) {
      throw new ExtensionLoadError(
        `Manifest not found at ${manifestKey}`,
        'MANIFEST_MISSING',
        extensionPath,
      );
    }

    let manifest: ExtensionManifest;
    try {
      const json = new TextDecoder().decode(manifestData);
      manifest = validateExtensionManifest(JSON.parse(json));
    } catch (err) {
      if (err instanceof ExtensionLoadError) throw err;
      throw new ExtensionLoadError(
        `Failed to parse manifest at ${manifestKey}: ${err instanceof Error ? err.message : String(err)}`,
        'MANIFEST_INVALID',
        extensionPath,
      );
    }

    // 1.5 Decision-A license gate (opt-in). A cartridge whose affine
    // PushDrop license fails the K15 check never loads its taxonomy.
    if (this.licenseGate) {
      try {
        await this.licenseGate(manifest, extensionPath);
      } catch (err) {
        if (err instanceof ExtensionLoadError) throw err;
        throw new ExtensionLoadError(
          `Cartridge license check failed for ${extensionPath}: ${err instanceof Error ? err.message : String(err)}`,
          'MANIFEST_INVALID',
          extensionPath,
        );
      }
    }

    // 2. Load taxonomy
    const taxonomyKey = `${extensionPath}/${manifest.taxonomyPath}`;
    const taxonomyData = await this.storage.read(taxonomyKey);
    if (!taxonomyData) {
      throw new ExtensionLoadError(
        `Taxonomy file not found at ${taxonomyKey}`,
        'TAXONOMY_MISSING',
        extensionPath,
      );
    }

    let taxonomy: TaxonomyTree;
    try {
      const json = new TextDecoder().decode(taxonomyData);
      taxonomy = JSON.parse(json) as TaxonomyTree;
    } catch (err) {
      throw new ExtensionLoadError(
        `Failed to parse taxonomy at ${taxonomyKey}: ${err instanceof Error ? err.message : String(err)}`,
        'TAXONOMY_INVALID',
        extensionPath,
      );
    }

    // 3. Load flows — list() returns relative keys
    const flowsDir = `${extensionPath}/${manifest.flowsDir}`;
    const flows: ConversationFlow[] = [];
    try {
      const flowKeys = await this.storage.list(flowsDir);
      for (const relKey of flowKeys) {
        if (!relKey.endsWith('.json')) continue;
        try {
          const fullKey = `${flowsDir}/${relKey}`;
          const data = await this.storage.read(fullKey);
          if (data) {
            const json = new TextDecoder().decode(data);
            flows.push(JSON.parse(json) as ConversationFlow);
          }
        } catch (err) {
          console.warn(`Skipping flow ${relKey}: ${err instanceof Error ? err.message : String(err)}`);
        }
      }
    } catch (err) {
      console.warn(`Could not list flows directory ${flowsDir}: ${err instanceof Error ? err.message : String(err)}`);
    }

    // 4. Load prompts — list() returns relative keys
    const promptsDir = `${extensionPath}/${manifest.promptsDir}`;
    const prompts: string[] = [];
    try {
      const promptKeys = await this.storage.list(promptsDir);
      for (const relKey of promptKeys) {
        if (!relKey.endsWith('.md')) continue;
        try {
          const fullKey = `${promptsDir}/${relKey}`;
          const data = await this.storage.read(fullKey);
          if (data) {
            prompts.push(new TextDecoder().decode(data));
          }
        } catch (err) {
          console.warn(`Skipping prompt ${relKey}: ${err instanceof Error ? err.message : String(err)}`);
        }
      }
    } catch (err) {
      console.warn(`Could not list prompts directory ${promptsDir}: ${err instanceof Error ? err.message : String(err)}`);
    }

    // 5. Return merged ExtensionConfig
    return {
      id: manifest.id,
      name: manifest.name,
      objectTypes: [],
      capabilities: [],
      scripts: [],
      commercePhases: [],
      taxonomy,
      flows,
      manifestPath: extensionPath,
    };
  }

  /**
   * Load all extensions from a list of paths.
   *
   * @param extensionPaths — array of storage key prefixes
   * @returns array of ExtensionConfigs
   */
  async loadAllExtensions(extensionPaths: string[]): Promise<ExtensionConfig[]> {
    return Promise.all(extensionPaths.map((p) => this.loadExtension(p)));
  }

  /**
   * Merge multiple ExtensionConfigs into a single unified config.
   *
   * Does NOT mutate the input configs or their arrays.
   *
   * Merging rules:
   *  - id/name: from first (primary) extension, name concatenated with " + "
   *  - objectTypes: union by typeHash (first wins on duplicate)
   *  - capabilities: union by id (first wins on duplicate)
   *  - flows: concatenate in order
   *  - taxonomy: merge dimensions by id; within each dimension, merge nodes by path (later overrides)
   *
   * @param configs — array of ExtensionConfigs to merge
   * @returns unified ExtensionConfig
   */
  mergeExtensions(configs: ExtensionConfig[]): ExtensionConfig {
    if (configs.length === 0) {
      throw new Error('Cannot merge zero extensions');
    }

    const primary = configs[0];
    const merged: ExtensionConfig = {
      id: primary.id,
      name: primary.name,
      objectTypes: [...(primary.objectTypes ?? [])],
      capabilities: [...(primary.capabilities ?? [])],
      scripts: [...(primary.scripts ?? [])],
      commercePhases: [...(primary.commercePhases ?? [])],
      taxonomy: primary.taxonomy
        ? { dimensions: primary.taxonomy.dimensions.map((d) => ({ ...d, nodes: [...d.nodes] })) }
        : undefined,
      flows: [...(primary.flows ?? [])],
    };

    const typeHashSet = new Set(merged.objectTypes.map((ot) => ot.typeHash));
    const capIdSet = new Set(merged.capabilities.map((c) => c.id));

    for (let i = 1; i < configs.length; i++) {
      const cfg = configs[i];
      merged.name += ` + ${cfg.name}`;

      // Union objectTypes by typeHash (first wins)
      for (const ot of cfg.objectTypes ?? []) {
        if (!typeHashSet.has(ot.typeHash)) {
          merged.objectTypes.push(ot);
          typeHashSet.add(ot.typeHash);
        }
      }

      // Union capabilities by id (first wins)
      for (const cap of cfg.capabilities ?? []) {
        if (!capIdSet.has(cap.id)) {
          merged.capabilities.push(cap);
          capIdSet.add(cap.id);
        }
      }

      // Concatenate flows
      for (const flow of cfg.flows ?? []) {
        merged.flows!.push(flow);
      }

      // Merge taxonomy dimensions
      if (cfg.taxonomy?.dimensions) {
        if (!merged.taxonomy) {
          merged.taxonomy = { dimensions: [] };
        }
        for (const dim of cfg.taxonomy.dimensions) {
          const existing = merged.taxonomy.dimensions.find((d) => d.id === dim.id);
          if (existing) {
            existing.nodes = mergeTaxonomyNodes(existing.nodes, dim.nodes);
          } else {
            merged.taxonomy.dimensions.push({ ...dim, nodes: [...dim.nodes] });
          }
        }
      }
    }

    return merged;
  }
}

/**
 * Merge two arrays of TaxonomyNodes by path.
 * Later nodes override earlier ones with the same path.
 */
export function mergeTaxonomyNodes(
  earlier: TaxonomyNode[],
  later: TaxonomyNode[],
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

```
