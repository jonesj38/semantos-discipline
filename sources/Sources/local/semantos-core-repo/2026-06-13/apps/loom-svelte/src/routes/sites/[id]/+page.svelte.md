---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/loom-svelte/src/routes/sites/[id]/+page.svelte
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.089695+00:00
---

# apps/loom-svelte/src/routes/sites/[id]/+page.svelte

```svelte
<script lang="ts">
  // D-DOG.1.0c Phase 3 E.2 — site-pivot route shell.
  //
  // Reference: docs/prd/D-DOG-1.0c-LAYER-1-PROMOTION-MATRIX.md §4 row
  //   E.2 — `apps/loom-svelte/src/routes/sites/[id]/+page.svelte` (new).
  //
  // The PRD spec landed this file at the SvelteKit `+page.svelte` path
  // ahead of the SvelteKit migration so the future router auto-resolves
  // `/sites/<id>` to this view with zero rename.  Today the helm SPA
  // ships a Vite + plain `mount(App, ...)` shell with hash routing; the
  // hash router in App.svelte parses `#/sites/<cellId>` and mounts
  // [SiteDetail] with [siteRef] as a prop.
  //
  // This wrapper exists so:
  //   1. The PRD's exact `routes/sites/[id]/+page.svelte` path is
  //      present in the tree (forward-compat with SvelteKit).
  //   2. A single source of truth — [SiteDetail] in views/ — backs both
  //      routes (today's hash router; tomorrow's SvelteKit router).
  //
  // When the SPA migrates to SvelteKit, this file pulls the [id] param
  // out of `$page.params` and forwards it to [SiteDetail].  Until then
  // the App.svelte hash router calls SiteDetail directly and this file
  // is just a documented forwarder.

  import SiteDetail from "../../../views/SiteDetail.svelte";

  // The [id] page param is the 64-hex site cellID.  In production
  // SvelteKit will resolve this automatically; for now the wrapper
  // accepts it as a plain prop so storybook / tests can mount the
  // route file directly without spinning up a SvelteKit context.
  let { id }: { id: string } = $props();
</script>

<SiteDetail siteRef={id} />

```
