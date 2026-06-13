---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/game-sdk/src/kernel-provider.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.522924+00:00
---

# packages/game-sdk/src/kernel-provider.ts

```ts
/**
 * Game SDK HostFunctionProvider — registers board/entity/inventory
 * primitives for PolicyRuntime integration.
 *
 * Phase 29.5 kernel enforcement sweep.
 */

import type { HostFunctionRegistry, HostFunctionContext } from '../../cell-engine/bindings/host-functions';
import type { HostFunctionProvider } from '../../../packages/policy-runtime/src/types';

/**
 * Core game-sdk host functions that any game can use.
 * These correspond to the primitives defined in policies/primitives.ts.
 */
export class GameSDKHostFunctionProvider implements HostFunctionProvider {
  register(registry: HostFunctionRegistry): void {
    // ── Board primitives ──────────────────────────────────────

    registry.register('square-empty?', (ctx: HostFunctionContext) =>
      (ctx.squareEmpty as boolean) ? 1 : 0,
    );

    registry.register('path-clear?', (ctx: HostFunctionContext) =>
      (ctx.pathClear as boolean) ? 1 : 0,
    );

    registry.register('adjacent?', (ctx: HostFunctionContext) =>
      (ctx.adjacent as boolean) ? 1 : 0,
    );

    // ── Entity primitives ─────────────────────────────────────

    registry.register('has-tag?', (ctx: HostFunctionContext) =>
      (ctx.hasTag as boolean) ? 1 : 0,
    );

    registry.register('rarity-eq?', (ctx: HostFunctionContext) =>
      (ctx.rarityMatch as boolean) ? 1 : 0,
    );

    registry.register('level-gte?', (ctx: HostFunctionContext) =>
      (ctx.levelGte as boolean) ? 1 : 0,
    );

    // ── Inventory primitives ──────────────────────────────────

    registry.register('inventory-full?', (ctx: HostFunctionContext) =>
      (ctx.inventoryFull as boolean) ? 1 : 0,
    );

    registry.register('inventory-contains?', (ctx: HostFunctionContext) =>
      (ctx.inventoryContains as boolean) ? 1 : 0,
    );

    // ── Capability primitives (used by .policy template files) ──

    registry.register('has-capability', (ctx: HostFunctionContext) => {
      const caps = ctx.capabilities as number[] | undefined;
      const required = ctx.requiredCapability as number | undefined;
      if (!caps || required === undefined) return 0;
      return caps.includes(required) ? 1 : 0;
    });
  }
}

export function createGameSDKHostFunctionProvider(): HostFunctionProvider {
  return new GameSDKHostFunctionProvider();
}

```
