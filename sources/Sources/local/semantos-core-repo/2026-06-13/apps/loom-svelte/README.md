---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/loom-svelte/README.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.047848+00:00
---

# @semantos/loom-svelte

A minimal Svelte UI consuming `@semantos/runtime-services`. The point isn't feature parity with the React `loom` — it's proof that the framework-quarantine boundary established in Phase 2a holds.

> **Same stores power both UIs.** The `LoomStore`, `IdentityStore`, `ConfigStore`, `IntentTaxonomy`, etc. instances rendered by this Svelte app are byte-identical to the ones React's `LoomProvider` wraps via `useSyncExternalStore`. There is no React in this stack; there is no Svelte in `runtime-services`.

## Run

```bash
# From the repo root
bun install
cd packages/loom-svelte
bun run dev                                  # vite at http://localhost:5175
```

> **Config is `.mjs` not `.ts` on purpose.** Earlier revisions used
> `vite.config.ts`; that triggers vite to invoke esbuild to transpile the
> config at startup, and esbuild's subprocess was exiting with
> `Error: The service was stopped` on some hosts. The real fix in that
> case was a nuclear `rm -rf node_modules bun.lockb && bun install` to
> reset the esbuild native binary; keeping `.mjs` avoids the category
> of issue going forward.
>
> **`src/stubs/` directory.** The demo aliases a handful of Node built-ins
> and workspace paths to inert stubs because runtime-services transitively
> imports them (via EmbeddingService → node `crypto`, via `protocol-types`
> → `cell-ops` → `crypto`, via adapter factories → `fs/promises`). Every
> stub path is one the browser demo never reaches at runtime; the stubs
> exist purely to satisfy vite's dep scanner. When the full-framework
> decoupling lands in a later phase, these become unnecessary.

## What it shows

- **Service singletons** loaded from `@semantos/runtime-services`: `intentTaxonomy`, `loomStore`, `identityStore`, `configStore`, `settingsStore`. If they're available as instances, the boundary is real.
- **`loomStore` state** — object count, card count, active hat — read via `loomStore.getState()` and kept in sync via `loomStore.on("change", …)`. Svelte 5 runes (`$state`) bind the singleton's state into reactivity without any wrapper component or React-style provider.
- **Intent taxonomy tree** — top-level domains and their first-level children, rendered from `intentTaxonomy.getDomains()`.

## Why this exists

The plan in [docs/RESTRUCTURING-PLAN.md §6](../../docs/RESTRUCTURING-PLAN.md) called for a Svelte scaffold to validate the framework-extraction work in Phase 2a. The risk being mitigated: a "renderer-agnostic" service layer can drift toward implicit React assumptions if no non-React consumer exists. This package is the consumer.

If `@semantos/loom-svelte` ever fails to compile because a runtime-services file added a `react` import, that's the bug surfacing — exactly when we want it to.

## What it isn't

- A replacement for `@semantos/loom`. The React UI is the production workbench.
- Feature-equivalent to loom. There's no canvas, no inspector, no Helm dock, no shell REPL panel.
- A SvelteKit app. We use plain Svelte 5 + Vite. Routing, SSR, layouts — none of that is needed to make the architectural point, and adding them would obscure it.

## Stack

- [Svelte 5](https://svelte.dev) (uses runes — `$state`, etc.)
- [Vite 5](https://vitejs.dev) for the dev server and build
- TypeScript strict
- One workspace dep: `@semantos/runtime-services`

## Files

```
packages/loom-svelte/
├── index.html
├── src/
│   ├── App.svelte         single-page UI
│   ├── main.ts            Svelte mount entry
│   └── app.css            dark-mode styling
├── vite.config.mjs        workspace alias for @semantos/runtime-services
├── svelte.config.js
├── tsconfig.json
└── package.json
```

## Related

- [packages/runtime-services/](../runtime-services/) — the renderer-agnostic service layer (extracted in Phase 2a)
- [packages/loom/](../loom/) — the React UI consuming the same services
- [packages/demo-wasm-threejs/](../demo-wasm-threejs/) — Three.js + cell-engine WASM (different proof: the kernel runs without runtime-services at all)
