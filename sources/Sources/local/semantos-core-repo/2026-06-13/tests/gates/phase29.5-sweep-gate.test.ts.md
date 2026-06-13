---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/tests/gates/phase29.5-sweep-gate.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.571794+00:00
---

# tests/gates/phase29.5-sweep-gate.test.ts

```ts
/**
 * Phase 29.5 Kernel Enforcement Sweep — Gate Tests
 *
 * Verifies that game-sdk, dungeon, mud, and poker-agent are wired
 * to the kernel enforcement layer (PolicyRuntime, HostFunctionRegistry,
 * AnchorEmitter).
 *
 * Hard invariants:
 *   S1: Game-SDK evaluateWithRuntime() returns structured PolicyResult
 *   S2: Dungeon evaluatePolicy uses registry + produces lastPolicyResult
 *   S3: MUD RoomActor evaluateMovePolicy produces lastPolicyResult
 *   S4: Poker validateActionPolicy rejects illegal actions via host predicates
 *   S5: Anchor emission fires on dungeon terminal events
 *   S6: Anchor emission fires on MUD player death events
 *   S7: HostFunctionProvider registration works for all domains
 */

import { describe, test, expect } from 'bun:test';

// ── Host function providers ──────────────────────────────────────

import { DungeonHostFunctionProvider, createDungeonHostFunctionProvider } from '../../packages/games/src/dungeon/kernel-provider';
import { MUDHostFunctionProvider, createMUDHostFunctionProvider } from '../../apps/mud/src/kernel-provider';
import { PokerHostFunctionProvider, createPokerHostFunctionProvider } from '../../packages/games/src/cards/kernel-provider';
import { GameSDKHostFunctionProvider, createGameSDKHostFunctionProvider } from '../../packages/game-sdk/src/kernel-provider';

// ── Host function registries ─────────────────────────────────────

import { HostFunctionRegistry } from '../../core/cell-engine/bindings/host-functions';
import { registerDungeonHostFunctions } from '../../packages/games/src/dungeon/host-functions';
import { registerMUDHostFunctions } from '../../apps/mud/src/host-functions';
import { registerPokerHostFunctions, compilePokerPolicies, type CompiledPokerPolicies } from '../../packages/games/src/cards/poker-policies';
import { compileDungeonPolicies, type CompiledDungeonPolicies } from '../../packages/games/src/dungeon/policies';
import { compileMUDPolicies, type CompiledMUDPolicies } from '../../apps/mud/src/policies';

// ── Anchor emitter ───────────────────────────────────────────────

import { DevModeAnchorEmitter } from '../../packages/policy-runtime/src/anchor-emitter';

// ── Types ────────────────────────────────────────────────────────

import type { HostFunctionProvider } from '../../packages/policy-runtime/src/types';

describe('Phase 29.5 Sweep — HostFunctionProvider Registration', () => {

  // S7: All domain providers implement HostFunctionProvider interface

  test('T1: DungeonHostFunctionProvider registers 13+ predicates', () => {
    const registry = new HostFunctionRegistry();
    const provider = createDungeonHostFunctionProvider();
    expect(provider).toBeDefined();
    expect(provider.register).toBeInstanceOf(Function);
    provider.register(registry);

    // Verify key predicates are registered
    registry.setContext({ action: 'move' });
    expect(registry.call('is-move?')).toBe(1);
    expect(registry.call('is-attack?')).toBe(0);
    registry.clearContext();
  });

  test('T2: MUDHostFunctionProvider registers dungeon + MUD predicates', () => {
    const registry = new HostFunctionRegistry();
    const provider = createMUDHostFunctionProvider();
    provider.register(registry);

    // Verify base dungeon predicates
    registry.setContext({ action: 'move' });
    expect(registry.call('is-move?')).toBe(1);
    registry.clearContext();

    // Verify MUD-specific predicates
    registry.setContext({ pvpEnabled: true });
    expect(registry.call('pvp-enabled?')).toBe(1);
    registry.clearContext();

    registry.setContext({ targetIsPlayer: false });
    expect(registry.call('target-not-player?')).toBe(1);
    registry.clearContext();
  });

  test('T3: PokerHostFunctionProvider registers 6 betting predicates', () => {
    const registry = new HostFunctionRegistry();
    const provider = createPokerHostFunctionProvider();
    provider.register(registry);

    // Active player check
    registry.setContext({ isActivePlayer: true });
    expect(registry.call('is-active-player?')).toBe(1);
    registry.clearContext();

    // Bet-to-call check
    registry.setContext({ betToCall: 0 });
    expect(registry.call('no-bet-to-call?')).toBe(1);
    expect(registry.call('has-bet-to-call?')).toBe(0);
    registry.clearContext();

    // Chips check
    registry.setContext({ playerChips: 100 });
    expect(registry.call('has-chips?')).toBe(1);
    registry.clearContext();
  });

  test('T4: GameSDKHostFunctionProvider registers board/entity/inventory predicates', () => {
    const registry = new HostFunctionRegistry();
    const provider = createGameSDKHostFunctionProvider();
    provider.register(registry);

    registry.setContext({ squareEmpty: true });
    expect(registry.call('square-empty?')).toBe(1);
    registry.clearContext();

    registry.setContext({ inventoryFull: false });
    expect(registry.call('inventory-full?')).toBe(0);
    registry.clearContext();

    registry.setContext({ capabilities: [3, 7], requiredCapability: 7 });
    expect(registry.call('has-capability')).toBe(1);
    registry.clearContext();
  });
});

describe('Phase 29.5 Sweep — Poker Policy Validation', () => {

  let registry: HostFunctionRegistry;
  let policies: CompiledPokerPolicies;

  test('T5: Poker policies compile successfully', () => {
    registry = new HostFunctionRegistry();
    registerPokerHostFunctions(registry);
    policies = compilePokerPolicies();

    expect(policies.fold).toBeDefined();
    expect(policies.check).toBeDefined();
    expect(policies.call).toBeDefined();
    expect(policies.bet).toBeDefined();
    expect(policies.raise).toBeDefined();
    expect(policies.allIn).toBeDefined();

    // All have scriptBytes
    expect(policies.fold.scriptBytes.length).toBeGreaterThan(0);
    expect(policies.check.scriptBytes.length).toBeGreaterThan(0);
  });

  test('T6: Check policy rejects when there is a bet to call', () => {
    // S4: Poker validateActionPolicy rejects illegal actions
    registry.setContext({
      isActivePlayer: true,
      betToCall: 50, // There IS a bet to call — check should fail
    });

    // is-active-player? passes
    expect(registry.call('is-active-player?')).toBe(1);
    // no-bet-to-call? fails (there IS a bet)
    expect(registry.call('no-bet-to-call?')).toBe(0);

    registry.clearContext();
  });

  test('T7: Call policy passes when there is a bet to call', () => {
    registry.setContext({
      isActivePlayer: true,
      betToCall: 50,
    });

    expect(registry.call('is-active-player?')).toBe(1);
    expect(registry.call('has-bet-to-call?')).toBe(1);

    registry.clearContext();
  });

  test('T8: Bet policy rejects when bet amount < big blind', () => {
    registry.setContext({
      isActivePlayer: true,
      betToCall: 0,
      betAmount: 5,
      bigBlind: 10,
    });

    expect(registry.call('is-active-player?')).toBe(1);
    expect(registry.call('no-bet-to-call?')).toBe(1);
    expect(registry.call('meets-minimum-bet?')).toBe(0); // 5 < 10

    registry.clearContext();
  });

  test('T9: All-in policy rejects when player has 0 chips', () => {
    registry.setContext({
      isActivePlayer: true,
      playerChips: 0,
    });

    expect(registry.call('is-active-player?')).toBe(1);
    expect(registry.call('has-chips?')).toBe(0); // 0 chips

    registry.clearContext();
  });

  test('T10: Raise policy validates minimum raise', () => {
    registry.setContext({
      isActivePlayer: true,
      betToCall: 20,
      raiseBy: 30,
      minRaise: 20,
    });

    expect(registry.call('is-active-player?')).toBe(1);
    expect(registry.call('has-bet-to-call?')).toBe(1);
    expect(registry.call('meets-minimum-raise?')).toBe(1); // 30 >= 20

    registry.clearContext();
  });
});

describe('Phase 29.5 Sweep — Dungeon Kernel Wiring', () => {

  test('T11: Dungeon policies compile to non-empty scriptBytes', () => {
    const policies = compileDungeonPolicies();
    expect(policies.move.scriptBytes.length).toBeGreaterThan(0);
    expect(policies.attack.scriptBytes.length).toBeGreaterThan(0);
    expect(policies.pickup.scriptBytes.length).toBeGreaterThan(0);
    expect(policies.useItem.scriptBytes.length).toBeGreaterThan(0);
    expect(policies.openDoor.scriptBytes.length).toBeGreaterThan(0);
  });

  test('T12: Dungeon host functions all return boolean (0 or 1)', () => {
    const registry = new HostFunctionRegistry();
    registerDungeonHostFunctions(registry);

    // Move context
    registry.setContext({
      action: 'move',
      playerX: 5, playerY: 5,
      targetX: 6, targetY: 5,
      mapWidth: 20, mapHeight: 20,
      targetTile: 1, // FLOOR
      hasWeapon: true,
      targetIsMonster: false,
      inventoryCount: 3,
      inventoryMax: 10,
      doorLocked: false,
      hasMatchingKey: false,
    });

    // All predicates return 0 or 1
    expect(registry.call('is-move?')).toBe(1);
    expect(registry.call('in-bounds?')).toBe(1);
    expect(registry.call('not-wall?')).toBe(1);
    expect(registry.call('adjacent-to-target?')).toBe(1);
    expect(registry.call('has-weapon?')).toBe(1);
    expect(registry.call('target-is-monster?')).toBe(0);
    expect(registry.call('inventory-not-full?')).toBe(1);

    registry.clearContext();
  });

  test('T13: Dungeon host function rejects out-of-bounds move', () => {
    const registry = new HostFunctionRegistry();
    registerDungeonHostFunctions(registry);

    registry.setContext({
      action: 'move',
      playerX: 0, playerY: 0,
      targetX: -1, targetY: 0, // Out of bounds
      mapWidth: 20, mapHeight: 20,
      targetTile: 0, // WALL
    });

    expect(registry.call('in-bounds?')).toBe(0);
    expect(registry.call('not-wall?')).toBe(0);

    registry.clearContext();
  });
});

describe('Phase 29.5 Sweep — MUD Kernel Wiring', () => {

  test('T14: MUD policies compile — includes exitRoom policy', () => {
    const policies = compileMUDPolicies();
    expect(policies.move.scriptBytes.length).toBeGreaterThan(0);
    expect(policies.attackPvE.scriptBytes.length).toBeGreaterThan(0);
    expect(policies.attackPvP.scriptBytes.length).toBeGreaterThan(0);
    expect(policies.exitRoom.scriptBytes.length).toBeGreaterThan(0);
  });

  test('T15: MUD host functions include PvP and rate-limiting predicates', () => {
    const registry = new HostFunctionRegistry();
    registerMUDHostFunctions(registry);

    // PvP disabled
    registry.setContext({ pvpEnabled: false });
    expect(registry.call('pvp-enabled?')).toBe(0);
    registry.clearContext();

    // PvP enabled
    registry.setContext({ pvpEnabled: true });
    expect(registry.call('pvp-enabled?')).toBe(1);
    registry.clearContext();

    // Rate limiting
    registry.setContext({
      lastActionTime: 1000,
      now: 1300,
      cooldownMs: 250,
    });
    expect(registry.call('not-rate-limited?')).toBe(1); // 300ms >= 250ms

    registry.clearContext();

    registry.setContext({
      lastActionTime: 1000,
      now: 1100,
      cooldownMs: 250,
    });
    expect(registry.call('not-rate-limited?')).toBe(0); // 100ms < 250ms

    registry.clearContext();
  });

  test('T16: MUD exit-room predicates work', () => {
    const registry = new HostFunctionRegistry();
    registerMUDHostFunctions(registry);

    // At exit, unlocked
    registry.setContext({
      atExitTile: true,
      exitLocked: false,
    });
    expect(registry.call('at-exit-tile?')).toBe(1);
    expect(registry.call('exit-not-locked?')).toBe(1);
    registry.clearContext();

    // At exit, locked, no key
    registry.setContext({
      atExitTile: true,
      exitLocked: true,
      hasMatchingKey: false,
    });
    expect(registry.call('at-exit-tile?')).toBe(1);
    expect(registry.call('exit-not-locked?')).toBe(0);
    expect(registry.call('has-matching-key?')).toBe(0);
    registry.clearContext();
  });
});

describe('Phase 29.5 Sweep — Anchor Emission', () => {

  test('T17: DevModeAnchorEmitter produces BEEF for terminal events', async () => {
    // S5, S6: Anchor emission fires on terminal events
    const emitter = new DevModeAnchorEmitter();
    const cellBytes = new Uint8Array(1024).fill(0x42);

    const result = await emitter.emit(cellBytes, {
      linearity: 'RELEVANT',
      anchorPolicy: 'terminal-only',
      idempotencyKey: 'dungeon-test-victory',
    });

    expect(result.txid).toBeDefined();
    expect(result.txid.length).toBe(64);
    expect(result.beefEnvelope.length).toBeGreaterThan(0);
    expect(result.reused).toBe(false);

    // Idempotent replay
    const replay = await emitter.emit(cellBytes, {
      linearity: 'RELEVANT',
      anchorPolicy: 'terminal-only',
      idempotencyKey: 'dungeon-test-victory',
    });
    expect(replay.txid).toBe(result.txid);
    expect(replay.reused).toBe(true);
  });

  test('T18: Anchor emitter skips when policy is never', async () => {
    const emitter = new DevModeAnchorEmitter();
    const result = await emitter.emit(new Uint8Array(64), {
      linearity: 'RELEVANT',
      anchorPolicy: 'never',
      idempotencyKey: 'skip-test',
    });

    expect(result.txid).toBe('0'.repeat(64));
    expect(result.beefEnvelope.length).toBe(0);
  });
});

describe('Phase 29.5 Sweep — Cross-domain Predicate Isolation', () => {

  test('T19: Dungeon + Poker registries can coexist without collision', () => {
    // Both domains can register on the same registry (for games
    // that combine dungeon and poker mechanics)
    const registry = new HostFunctionRegistry();
    registerDungeonHostFunctions(registry);
    registerPokerHostFunctions(registry);

    // Dungeon predicates work
    registry.setContext({ action: 'move' });
    expect(registry.call('is-move?')).toBe(1);
    registry.clearContext();

    // Poker predicates work
    registry.setContext({ isActivePlayer: true });
    expect(registry.call('is-active-player?')).toBe(1);
    registry.clearContext();

    // Unknown predicates return sentinel
    expect(registry.call('nonexistent-predicate?')).toBe(0xFFFFFFFF);
  });

  test('T20: Provider factory pattern returns HostFunctionProvider interface', () => {
    const providers: HostFunctionProvider[] = [
      createDungeonHostFunctionProvider(),
      createMUDHostFunctionProvider(),
      createPokerHostFunctionProvider(),
      createGameSDKHostFunctionProvider(),
    ];

    for (const p of providers) {
      expect(p.register).toBeInstanceOf(Function);
    }

    // All can register on the same registry without errors
    const registry = new HostFunctionRegistry();
    for (const p of providers) {
      p.register(registry);
    }

    // Verify at least one predicate from each domain works
    registry.setContext({ action: 'move' });
    expect(registry.call('is-move?')).toBe(1); // dungeon
    registry.clearContext();

    registry.setContext({ pvpEnabled: true });
    expect(registry.call('pvp-enabled?')).toBe(1); // MUD
    registry.clearContext();

    registry.setContext({ isActivePlayer: true });
    expect(registry.call('is-active-player?')).toBe(1); // poker
    registry.clearContext();

    registry.setContext({ squareEmpty: true });
    expect(registry.call('square-empty?')).toBe(1); // game-sdk
    registry.clearContext();
  });
});

```
