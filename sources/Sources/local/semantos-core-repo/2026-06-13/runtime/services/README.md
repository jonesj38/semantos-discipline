---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/services/README.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.025422+00:00
---

# @semantos/runtime-services

Renderer-agnostic stores and services for Semantos. Extracted from `@semantos/loom` so that React-, Svelte-, and headless consumers can share one source of truth.

> Until the Phase 3 directory move (`core/runtime/extensions/apps`), this package lives at `packages/runtime-services/`. Afterwards it becomes `runtime/services/`.

## What's in here

```
src/
├── services/      LoomStore, FlowRunner, IdentityStore, ConfigStore,
│                  EmbeddingService, IntentClassifier, AttentionEngine, …
├── plexus/        PlexusService + CashLanesService (BSV identity / payment)
├── state/         loomReducer, objectFactory (framework-free state primitives)
├── config/        extensionConfig types + verticalConfig artifacts
├── types/         loom.ts — LoomObject, LoomCard, ObjectPatch, Identity, Hat, …
└── index.ts       barrel re-export
```

Everything in this package is **renderer-agnostic** — pure TypeScript with no React, DOM, or framework dependencies. Import directly from a Bun CLI, a Vite/Svelte app, a Web Worker, a Node test harness, or a React component via `useSyncExternalStore`.

## Use it

```ts
import { LoomStore, FlowRunner, IdentityStore } from "@semantos/runtime-services";
import type { LoomObject, ObjectPatch } from "@semantos/runtime-services/types";
import { extensionConfig } from "@semantos/runtime-services/config";
```

The deep-import surface (`./services/*`, `./state/*`, `./plexus/*`, `./types`, `./config`) mirrors the on-disk layout — useful for code-splitting in browser apps that don't want to pull the whole barrel.

## Backwards compatibility

`@semantos/loom`'s public exports re-export from this package, so existing consumers (`@semantos/shell`, `@semantos/loom`'s own UI) keep working without import changes. Migration to `@semantos/runtime-services` is opt-in.

## Related

- [packages/loom/](../loom/) — the React UI that wraps these services via `useSyncExternalStore`
- [packages/demo-wasm-threejs/](../demo-wasm-threejs/) — the Three.js demo that proves the cell engine alone is browser-portable (does *not* depend on this package; uses an inline minimal loader)
- (Phase 2c, in progress) `packages/loom-svelte/` — minimal Svelte UI that consumes this package, demonstrating framework portability
