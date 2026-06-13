---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/types/semantos-node.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.882703+00:00
---

# core/protocol-types/src/types/semantos-node.ts

```ts
/**
 * SemantosNode — handle to a running Semantos node.
 *
 * Represents all four adapters, the node configuration, and the node
 * self-object. The node is the unit of deployment and administration.
 *
 * Use createNode() to instantiate — do not construct directly.
 *
 * Cross-references:
 *   node-config.ts    → NodeConfig
 *   cell-store.ts     → CellStore, CellRef
 *   semantic-fs.ts    → SemanticFS
 *   node.ts           → createNode(), SemantosNodeImpl
 */

import type { CellRef } from '../cell-store';
import type { CellStore } from '../cell-store';
import type { SemanticFS } from '../semantic-fs';
import type { StorageAdapter } from '../storage';
import type { IdentityAdapter } from '../identity';
import type { AnchorAdapter } from '../anchor';
import type { NetworkAdapter } from '../network';
import type { NodeConfig } from '../node-config';

/**
 * Public handle to a Semantos node.
 *
 * Exposes configuration, adapters, core services, and lifecycle methods.
 * Implementation is private (SemantosNodeImpl in node.ts).
 */
export interface SemantosNode {
  // === Configuration ===

  /** The NodeConfig used to create this node. */
  readonly config: NodeConfig;

  /** The node self-object ref (sovereignty.node.{cert_id}). Updated on lifecycle events. */
  readonly nodeObject: CellRef;

  // === Adapters ===

  readonly storage: StorageAdapter;
  readonly identity: IdentityAdapter;
  readonly anchor: AnchorAdapter;
  readonly network: NetworkAdapter;

  // === Core Services ===

  readonly cellStore: CellStore;
  readonly semanticFs: SemanticFS;

  // === Lifecycle ===

  /** Start the node: set running, start anchor scheduler, update self-object. */
  start(): Promise<void>;

  /** Graceful shutdown: stop scheduler, update self-object, clear state. */
  stop(): Promise<void>;

  /** Get current node status snapshot. */
  getStatus(): NodeStatus;

  /** Refresh the self-object at objects/sovereignty/node/{cert_id} with current status. */
  updateNodeObject(): Promise<void>;
}

/**
 * Snapshot of node state, returned by getStatus().
 */
export interface NodeStatus {
  /** Node certificate ID. */
  nodeCert: string;

  /** BCA address if deployed, null otherwise. */
  bcaAddress: string | null;

  /** Whether the node is currently running. */
  running: boolean;

  /** Milliseconds since start() was called. 0 if stopped. */
  uptime: number;

  /** Epoch ms when start() was called. Null if never started or stopped. */
  startedAt: number | null;

  /** Epoch ms of the most recent anchor. Null if no anchor yet. */
  lastAnchor: number | null;

  /** Extension names from config. */
  installedExtensions: string[];

  /** Adapter implementation class names. */
  adapters: {
    storage: string;
    identity: string;
    anchor: string;
    network: string;
  };

  /** Errors or warnings from the last cycle. */
  diagnostics: string[];
}

```
