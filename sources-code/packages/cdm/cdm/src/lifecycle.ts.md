---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/cdm/cdm/src/lifecycle.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.494572+00:00
---

# packages/cdm/cdm/src/lifecycle.ts

```ts
/**
 * @deprecated — moved under `packages/cdm/src/lifecycle/`.
 *
 * Refactor 29 split the 523-LOC monolith into per-concern modules:
 *   - `lifecycle/event-reducer.ts`   — pure (state, event) → state
 *   - `lifecycle/trade-events.ts`    — TradeEvent union + transition table
 *   - `lifecycle/novation.ts`        — novation flow
 *   - `lifecycle/termination.ts`     — full + partial termination + close-out netting
 *   - `lifecycle/increase.ts`        — notional-increase flow
 *   - `lifecycle/decrease.ts`        — notional-decrease flow (delegates to termination)
 *   - `lifecycle/cell-builder.ts`    — cell packing
 *   - `lifecycle/policy-gate.ts`     — Phase 29.5 kernel policy gate
 *   - `lifecycle/persistence.ts`     — event bus + persistence hookup
 *   - `lifecycle/lifecycle-facade.ts` — public `CDMLifecycleEngine`
 *
 * This file remains as a re-export shim so existing imports
 * (`@semantos/cdm/lifecycle`, `packages/cdm/src/lifecycle.ts`) keep
 * working byte-identical. New code should import from
 * `@semantos/cdm/lifecycle` (the `./lifecycle/index.ts` barrel) directly.
 */

export {
  CDMLifecycleEngine,
  type CDMLifecycleOptions,
} from './lifecycle/lifecycle-facade';

```
