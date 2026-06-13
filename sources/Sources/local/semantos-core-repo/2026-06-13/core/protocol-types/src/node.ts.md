---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/node.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.846139+00:00
---

# core/protocol-types/src/node.ts

```ts
/**
 * Node bootstrap — createNode() factory and SemantosNodeImpl.
 *
 * Assembles four adapters into a deployable Semantos node. On creation,
 * writes a sovereignty.node.{cert_id} RELEVANT semantic object describing
 * the node. The returned SemantosNode handle provides lifecycle methods
 * (start/stop) and status introspection.
 *
 * Cross-references:
 *   node-config.ts           → NodeConfig
 *   types/semantos-node.ts   → SemantosNode, NodeStatus interfaces
 *   cell-store.ts            → CellStore, CellRef
 *   semantic-fs.ts           → SemanticFS
 *   taxonomy-resolver.ts     → TaxonomyResolver, TaxonomyNode
 *   anchor-scheduler.ts      → AnchorScheduler
 *   constants.ts             → Linearity
 */

import type { NodeConfig } from './node-config';
import type { SemantosNode, NodeStatus } from './types/semantos-node';
import { CellStore, type CellRef } from './cell-store';
import { SemanticFS } from './semantic-fs';
import type { TaxonomyResolver, TaxonomyNode } from './taxonomy-resolver';
import { AnchorScheduler } from './anchor-scheduler';
import { Linearity } from './constants';

// ── Config Validation ─────────────────────────────────────────────

function validateConfig(config: NodeConfig): void {
  if (!config.nodeCert) {
    throw new Error('NodeConfig.nodeCert is required');
  }
  if (!config.storage) {
    throw new Error('NodeConfig.storage adapter is required');
  }
  if (!config.identity) {
    throw new Error('NodeConfig.identity adapter is required');
  }
  if (!config.anchor) {
    throw new Error('NodeConfig.anchor adapter is required');
  }
  if (!config.network) {
    throw new Error('NodeConfig.network adapter is required');
  }
  if (!config.extensions || !Array.isArray(config.extensions) || config.extensions.length === 0) {
    throw new Error('NodeConfig.extensions must include at least one extension');
  }
}

// ── Taxonomy Placeholder ──────────────────────────────────────────

/**
 * Placeholder taxonomy resolver for node bootstrap.
 *
 * Recognizes the `sovereignty.node` path needed for the node self-object.
 * Phase 26F will replace this with full extension config loading from disk.
 */
function loadTaxonomy(): TaxonomyResolver {
  const nodeLeaf: TaxonomyNode = { id: 'node', label: 'Node' };
  const sovereigntyRoot: TaxonomyNode = {
    id: 'sovereignty',
    label: 'Sovereignty',
    children: [nodeLeaf],
  };

  return {
    getNodeAt(path: string[]): TaxonomyNode | null {
      if (path.length === 0) return null;
      if (path[0] !== 'sovereignty') return null;
      if (path.length === 1) return sovereigntyRoot;
      if (path.length === 2 && path[1] === 'node') return nodeLeaf;
      return null;
    },
    getOptionsAt(path: string[]): TaxonomyNode[] {
      if (path.length === 0) return [sovereigntyRoot];
      if (path.length === 1 && path[0] === 'sovereignty') return [nodeLeaf];
      return [];
    },
  };
}

// ── Self-Object Builder ───────────────────────────────────────────

function buildSelfObjectPayload(
  config: NodeConfig,
  running: boolean,
  startedAt: number | null,
  lastAnchor: number | null,
  diagnostics: string[],
): Uint8Array {
  const payload = {
    nodeCert: config.nodeCert,
    bcaAddress: config.bcaAddress ?? null,
    extensions: config.extensions,
    version: '0.0.1',
    running,
    startedAt,
    uptime: running && startedAt ? Date.now() - startedAt : 0,
    lastAnchor,
    timestamp: Date.now(),
    adapters: {
      storage: config.storage.constructor.name,
      identity: config.identity.constructor.name,
      anchor: config.anchor.constructor.name,
      network: config.network.constructor.name,
    },
    diagnostics,
  };
  return new TextEncoder().encode(JSON.stringify(payload));
}

// ── createNode ────────────────────────────────────────────────────

/**
 * Instantiate and bootstrap a Semantos node.
 *
 * 1. Validates NodeConfig (all four adapters present, required fields set)
 * 2. Initializes CellStore and SemanticFS from storage adapter
 * 3. Creates the node self-object (sovereignty.node.{cert_id}) as RELEVANT
 * 4. Returns SemantosNode handle (ready to call start())
 *
 * @throws Error if config is invalid
 */
export async function createNode(config: NodeConfig): Promise<SemantosNode> {
  validateConfig(config);

  const cellStore = new CellStore(config.storage);
  const taxonomy = loadTaxonomy();
  const semanticFs = new SemanticFS({
    cellStore,
    adapter: config.storage,
    taxonomy,
  });

  const selfPath = `objects/sovereignty/node/${config.nodeCert}`;
  const selfData = buildSelfObjectPayload(config, false, null, null, []);
  const nodeObject = await semanticFs.put(selfPath, selfData, {
    linearity: Linearity.RELEVANT,
  });

  return new SemantosNodeImpl(config, cellStore, semanticFs, nodeObject);
}

// ── SemantosNodeImpl ──────────────────────────────────────────────

/**
 * Private implementation of SemantosNode.
 *
 * Use createNode() to instantiate. Not exported.
 */
class SemantosNodeImpl implements SemantosNode {
  readonly config: NodeConfig;
  readonly storage;
  readonly identity;
  readonly anchor;
  readonly network;
  readonly cellStore: CellStore;
  readonly semanticFs: SemanticFS;

  private _nodeObject: CellRef;
  private _running = false;
  private _startedAt: number | null = null;
  private _lastAnchor: number | null = null;
  private _diagnostics: string[] = [];
  private _scheduler: AnchorScheduler | null = null;

  constructor(
    config: NodeConfig,
    cellStore: CellStore,
    semanticFs: SemanticFS,
    nodeObject: CellRef,
  ) {
    this.config = config;
    this.storage = config.storage;
    this.identity = config.identity;
    this.anchor = config.anchor;
    this.network = config.network;
    this.cellStore = cellStore;
    this.semanticFs = semanticFs;
    this._nodeObject = nodeObject;
  }

  get nodeObject(): CellRef {
    return this._nodeObject;
  }

  async start(): Promise<void> {
    if (this._running) return;

    this._running = true;
    this._startedAt = Date.now();
    this._diagnostics = [];

    const interval = this.config.anchorIntervalMs ?? 600_000;
    if (interval > 0) {
      this.config.anchor.setAnchorInterval(interval);
      this._scheduler = new AnchorScheduler(this.config.anchor, this.config.storage);
      this._scheduler.start();
    }

    await this.updateNodeObject();
  }

  async stop(): Promise<void> {
    if (!this._running) return;

    this._running = false;

    if (this._scheduler) {
      this._scheduler.stop();
      this._scheduler = null;
    }

    await this.updateNodeObject();

    this._startedAt = null;
  }

  getStatus(): NodeStatus {
    return {
      nodeCert: this.config.nodeCert,
      bcaAddress: this.config.bcaAddress ?? null,
      running: this._running,
      uptime: this._running && this._startedAt ? Date.now() - this._startedAt : 0,
      startedAt: this._startedAt,
      lastAnchor: this._lastAnchor,
      installedExtensions: this.config.extensions,
      adapters: {
        storage: this.config.storage.constructor.name,
        identity: this.config.identity.constructor.name,
        anchor: this.config.anchor.constructor.name,
        network: this.config.network.constructor.name,
      },
      diagnostics: [...this._diagnostics],
    };
  }

  async updateNodeObject(): Promise<void> {
    const selfPath = `objects/sovereignty/node/${this.config.nodeCert}`;
    const selfData = buildSelfObjectPayload(
      this.config,
      this._running,
      this._startedAt,
      this._lastAnchor,
      this._diagnostics,
    );
    this._nodeObject = await this.semanticFs.put(selfPath, selfData, {
      linearity: Linearity.RELEVANT,
    });
  }
}

```
