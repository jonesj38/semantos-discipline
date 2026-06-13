---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/game-sdk/src/bindings/unity/index.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.532907+00:00
---

# packages/game-sdk/src/bindings/unity/index.ts

```ts
/**
 * Unity Native Plugin Binding Scaffold
 *
 * Defines TypeScript interfaces for Unity native plugin integration.
 * This is a SCAFFOLD — it defines the interface contract and
 * demonstrates the binding pattern. It does NOT compile to a
 * working Unity plugin (that requires the Unity toolchain).
 */

import type { GameEntity, Inventory, TradeProposal, TradeResult } from '../../types';

// ── Scaffold Version ────────────────────────────────────────────

export const UNITY_BINDING_VERSION = '0.1.0-scaffold';

// ── Unity-Specific Types ────────────────────────────────────────

export interface UnityGameObjectData {
  name: string;
  tag: string;
  layer: number;
  components: Record<string, Record<string, unknown>>;
}

export interface UnityEvent {
  name: string;
  parameterTypes: string[];
}

// ── SemanticInventory (maps to MonoBehaviour) ───────────────────

/**
 * Manages inventory cells as a Unity MonoBehaviour.
 * In a real plugin, this is a C# MonoBehaviour using P/Invoke to call the WASM.
 */
export interface SemanticInventory {
  /** Add a cell to a named slot. Fires OnItemAdded UnityEvent. */
  AddItem(slot: string, entity: GameEntity): void;
  /** Remove a cell from a named slot. Fires OnItemRemoved UnityEvent. */
  RemoveItem(slot: string): GameEntity | null;
  /** Transfer a cell to another inventory. Fires OnItemTransferred UnityEvent. */
  TransferItem(slot: string, target: SemanticInventory, destSlot: string): boolean;
  /** Get entity at slot (null if empty). */
  GetItem(slot: string): GameEntity | null;
  /** List all occupied slot names. */
  GetSlots(): string[];
  /** Get the underlying inventory. */
  GetInventory(): Inventory;
}

/** UnityEvents fired by SemanticInventory. */
export const INVENTORY_EVENTS: UnityEvent[] = [
  { name: 'OnItemAdded', parameterTypes: ['string', 'string'] },
  { name: 'OnItemRemoved', parameterTypes: ['string', 'string'] },
  { name: 'OnItemTransferred', parameterTypes: ['string', 'string'] },
];

// ── SemanticEntity (maps to ScriptableObject) ───────────────────

/**
 * Wraps a GameEntity as a Unity ScriptableObject.
 * In a real plugin, this is a C# ScriptableObject with custom inspector.
 */
export interface SemanticEntity {
  /** The underlying game entity. */
  readonly Entity: GameEntity;
  /** Entity ID (hex typeHash). */
  readonly Id: string;
  /** Entity type name. */
  readonly TypeName: string;
  /** Current state label. */
  readonly State: string;
  /** Linearity mode as string. */
  readonly LinearityName: string;
  /** Export metadata as Unity-compatible serialized form. */
  ToSerializedDict(): Record<string, unknown>;
}

// ── SemanticTradeManager (maps to singleton MonoBehaviour) ──────

/**
 * Singleton trade manager as a MonoBehaviour.
 * Manages trade lifecycle and fires events.
 */
export interface SemanticTradeManager {
  /** Propose a trade between two inventories. */
  ProposeTrade(proposal: TradeProposal): void;
  /** Accept the current trade proposal. */
  AcceptTrade(): TradeResult;
  /** Cancel the current trade proposal. */
  CancelTrade(): void;
}

/** UnityEvents fired by SemanticTradeManager. */
export const TRADE_EVENTS: UnityEvent[] = [
  { name: 'OnTradeProposed', parameterTypes: [] },
  { name: 'OnTradeCompleted', parameterTypes: [] },
  { name: 'OnTradeFailed', parameterTypes: ['string'] },
  { name: 'OnTradeCancelled', parameterTypes: [] },
];

// ── SemanticPolicyAsset (maps to custom asset type) ─────────────

/**
 * Custom asset type for compiled policy bytes.
 * In a real plugin, this is a C# ScriptableObject with a custom editor.
 */
export interface SemanticPolicyAsset {
  /** Load a .policy file from Unity's asset database. */
  LoadPolicy(assetPath: string): string;
  /** Compile a policy source string. */
  CompilePolicy(source: string): { Success: boolean; Bytes?: Uint8Array; Error?: string };
  /** Validate a policy against entity metadata schema. */
  ValidatePolicy(source: string, schema: Record<string, string>): string[];
}

/** UnityEvents fired by SemanticPolicyAsset. */
export const POLICY_EVENTS: UnityEvent[] = [
  { name: 'OnPolicyCompiled', parameterTypes: ['string'] },
  { name: 'OnPolicyError', parameterTypes: ['string'] },
];

```
