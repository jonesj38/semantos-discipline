---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/game-sdk/src/bindings/godot/index.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.533535+00:00
---

# packages/game-sdk/src/bindings/godot/index.ts

```ts
/**
 * Godot GDExtension Binding Scaffold
 *
 * Defines TypeScript interfaces for Godot GDExtension integration.
 * This is a SCAFFOLD — it defines the interface contract and
 * demonstrates the binding pattern. It does NOT compile to a
 * working GDExtension (that requires the Godot toolchain).
 */

import type { GameEntity, Inventory, TradeProposal, TradeResult } from '../../types';

// ── Scaffold Version ────────────────────────────────────────────

export const GODOT_BINDING_VERSION = '0.1.0-scaffold';

// ── Godot-Specific Types ────────────────────────────────────────

export interface GodotNodeData {
  name: string;
  type: string;
  properties: Record<string, string | number | boolean>;
  children?: GodotNodeData[];
}

export interface GodotSignal {
  name: string;
  args: Array<{ name: string; type: string }>;
}

// ── SemanticInventory (maps to Godot Node) ──────────────────────

/**
 * Manages inventory cells as a Godot Node.
 * In a real GDExtension, this extends godot::Node and emits signals.
 */
export interface SemanticInventory {
  /** Add a cell to a named slot. Emits 'item_added' signal. */
  addItem(slot: string, entity: GameEntity): void;
  /** Remove a cell from a named slot. Emits 'item_removed' signal. */
  removeItem(slot: string): GameEntity | null;
  /** Transfer a cell to another inventory. Emits 'item_transferred' signal. */
  transferItem(slot: string, target: SemanticInventory, destSlot: string): boolean;
  /** Get entity at slot (null if empty). */
  getItem(slot: string): GameEntity | null;
  /** List all occupied slot names. */
  getSlots(): string[];
  /** Get the underlying inventory. */
  getInventory(): Inventory;
}

/** Signals emitted by SemanticInventory. */
export const INVENTORY_SIGNALS: GodotSignal[] = [
  { name: 'item_added', args: [{ name: 'slot', type: 'String' }, { name: 'entity_id', type: 'String' }] },
  { name: 'item_removed', args: [{ name: 'slot', type: 'String' }, { name: 'entity_id', type: 'String' }] },
  { name: 'item_transferred', args: [{ name: 'slot', type: 'String' }, { name: 'target_slot', type: 'String' }] },
];

// ── SemanticEntity (maps to Godot Resource) ─────────────────────

/**
 * Wraps a GameEntity as a Godot Resource.
 * In a real GDExtension, this extends godot::Resource with custom properties.
 */
export interface SemanticEntity {
  /** The underlying game entity. */
  readonly entity: GameEntity;
  /** Entity ID (hex typeHash). */
  readonly id: string;
  /** Entity type name. */
  readonly typeName: string;
  /** Current state label. */
  readonly state: string;
  /** Linearity mode as string (LINEAR, AFFINE, RELEVANT, FUNGIBLE). */
  readonly linearityName: string;
  /** Export metadata as Godot-compatible Dictionary. */
  toGodotDict(): Record<string, unknown>;
}

// ── SemanticTradeUI (maps to Godot Control) ─────────────────────

/**
 * Trade interface scaffold mapped to a Godot Control node.
 * Emits signals on trade lifecycle events.
 */
export interface SemanticTradeUI {
  /** Propose a trade between two inventories. */
  proposeTrade(proposal: TradeProposal): void;
  /** Accept the current trade proposal. Emits 'trade_completed' or 'trade_failed'. */
  acceptTrade(): TradeResult;
  /** Cancel the current trade proposal. Emits 'trade_cancelled'. */
  cancelTrade(): void;
}

/** Signals emitted by SemanticTradeUI. */
export const TRADE_SIGNALS: GodotSignal[] = [
  { name: 'trade_proposed', args: [] },
  { name: 'trade_completed', args: [] },
  { name: 'trade_failed', args: [{ name: 'reason', type: 'String' }] },
  { name: 'trade_cancelled', args: [] },
];

// ── SemanticPolicyEditor (maps to Godot EditorPlugin) ───────────

/**
 * In-editor tool for authoring Lisp policies.
 * In a real GDExtension, this provides a custom editor panel.
 */
export interface SemanticPolicyEditor {
  /** Load a .policy file from the Godot project. */
  loadPolicy(resourcePath: string): string;
  /** Compile a policy source string. Returns compiled bytes or error. */
  compilePolicy(source: string): { success: boolean; bytes?: Uint8Array; error?: string };
  /** Validate a policy against entity metadata schema. */
  validatePolicy(source: string, schema: Record<string, string>): string[];
}

/** Signals emitted by SemanticPolicyEditor. */
export const POLICY_EDITOR_SIGNALS: GodotSignal[] = [
  { name: 'policy_compiled', args: [{ name: 'path', type: 'String' }] },
  { name: 'policy_error', args: [{ name: 'message', type: 'String' }] },
];

```
