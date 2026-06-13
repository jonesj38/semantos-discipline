---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/extension-registry.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.843003+00:00
---

# core/protocol-types/src/extension-registry.ts

```ts
/**
 * ExtensionRegistry — tracks which extensions are installed and active on a node.
 *
 * An extension is "installed" if its path appears in NodeConfig.extensions.
 * An extension is "active" if it has been loaded via activate() and is integrated
 * into the taxonomy and prompt context.
 *
 * Capability tokens optionally gate extension activation (Phase 27).
 *
 * Cross-references:
 *   node-config.ts     → NodeConfig (extensions, extensionCapabilities)
 *   extension-loader.ts → ExtensionLoader (loadExtension)
 *   extensionConfig.ts  → ExtensionConfig
 */

import type { NodeConfig } from './node-config';
import type { ExtensionConfig, ExtensionTier } from './extension-config-types';
import type { ExtensionLoader } from './extension-loader';

/**
 * Manages extension activation and deactivation for a node.
 *
 * Maintains an ordered map of active extensions and an optional capability
 * token store. The activation order is preserved for deterministic prompt
 * injection ordering.
 */
export class ExtensionRegistry {
  private activeExtensions: Map<string, ExtensionConfig> = new Map();
  private capabilities: Map<string, Uint8Array> = new Map();

  constructor(nodeConfig: NodeConfig) {
    if (nodeConfig.extensionCapabilities) {
      for (const [id, token] of Object.entries(nodeConfig.extensionCapabilities)) {
        this.capabilities.set(id, token);
      }
    }
  }

  /**
   * Activate an extension: load from disk, validate, register.
   *
   * @param extensionId — expected extension ID (must match manifest.id)
   * @param extensionPath — filesystem path to the extension directory
   * @param loader — ExtensionLoader instance to use for loading
   * @returns the loaded ExtensionConfig
   * @throws ExtensionLoadError if loading fails
   * @throws Error if manifest ID doesn't match extensionId
   */
  async activate(
    extensionId: string,
    extensionPath: string,
    loader: ExtensionLoader,
  ): Promise<ExtensionConfig> {
    const config = await loader.loadExtension(extensionPath);
    if (config.id !== extensionId) {
      throw new Error(
        `Extension ID mismatch: expected "${extensionId}", got "${config.id}"`,
      );
    }
    this.activeExtensions.set(extensionId, config);
    return config;
  }

  /**
   * Deactivate an extension: remove from registry.
   *
   * @param extensionId — extension ID to deactivate
   * @returns true if the extension was active and removed, false if not found
   */
  deactivate(extensionId: string): boolean {
    return this.activeExtensions.delete(extensionId);
  }

  /**
   * Get all active extensions in activation order.
   *
   * @returns array of ExtensionConfigs
   */
  getAllActive(): ExtensionConfig[] {
    return Array.from(this.activeExtensions.values());
  }

  /**
   * Get a single active extension by ID.
   *
   * @param extensionId — extension ID
   * @returns ExtensionConfig or undefined if not active
   */
  getExtension(extensionId: string): ExtensionConfig | undefined {
    return this.activeExtensions.get(extensionId);
  }

  /**
   * Check if an extension is currently active.
   *
   * @param extensionId — extension ID
   * @returns true if active
   */
  isActive(extensionId: string): boolean {
    return this.activeExtensions.has(extensionId);
  }

  /**
   * Store or update a capability token for an extension.
   *
   * @param extensionId — extension ID
   * @param token — capability token bytes
   */
  setCapability(extensionId: string, token: Uint8Array): void {
    this.capabilities.set(extensionId, token);
  }

  /**
   * Retrieve the capability token for an extension.
   *
   * @param extensionId — extension ID
   * @returns token bytes or undefined if no token exists
   */
  getCapability(extensionId: string): Uint8Array | undefined {
    return this.capabilities.get(extensionId);
  }

  /**
   * Get the extension tier for an active extension.
   *
   * @param extensionId — extension ID
   * @returns ExtensionTier or undefined if not active or no tier set
   */
  getExtensionTier(extensionId: string): ExtensionTier | undefined {
    return this.activeExtensions.get(extensionId)?.extensionTier;
  }

  /**
   * Get all active extensions of a specific tier.
   *
   * @param tier — the tier to filter by
   * @returns array of matching ExtensionConfigs
   */
  getExtensionsByTier(tier: ExtensionTier): ExtensionConfig[] {
    return this.getAllActive().filter(ext => ext.extensionTier === tier);
  }
}

```
