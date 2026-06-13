---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/loom-svelte/package.json
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.048427+00:00
---

# apps/loom-svelte/package.json

```json
{
  "name": "@semantos/loom-svelte",
  "version": "0.2.0",
  "private": true,
  "type": "module",
  "description": "Helm — desktop SPA operator console for the Semantos Brain oddjobz extension. D-O5: SPA bundle served from /helm/* via brain's RouteType.directory; talks to brain's REPL HTTP + (eventually) WSS endpoints.",
  "scripts": {
    "dev": "vite",
    "build": "vite build",
    "preview": "vite preview",
    "check": "svelte-check --tsconfig ./tsconfig.json",
    "test": "node --test --import tsx tests/repl-client.test.ts tests/job-list-parse.test.ts tests/job-detail-parse.test.ts tests/customer-list-parse.test.ts tests/calendar-parse.test.ts tests/attention-parse.test.ts tests/joblist-graph.test.ts tests/joblist-fetch.test.ts tests/oddjobz-query.test.ts tests/customer-pivot.test.ts tests/site-pivot.test.ts tests/job-detail-graph.test.ts tests/extensions-api.test.ts tests/shelf-compose.test.ts tests/body-route.test.ts tests/surface-registry.test.ts tests/me-format.test.ts tests/verb-intent.test.ts tests/attention-poll.test.ts tests/jobs-store.test.ts tests/customers-store.test.ts tests/job-source.test.ts tests/identity-api.test.ts"
  },
  "dependencies": {
    "svelte": "^5.0.0"
  },
  "devDependencies": {
    "@sveltejs/vite-plugin-svelte": "^4.0.0",
    "@tsconfig/svelte": "^5.0.0",
    "svelte-check": "^4.0.0",
    "tsx": "^4.7.0",
    "typescript": "~5.8.0",
    "vite": "^5.4.0"
  },
  "license": "UNLICENSED"
}

```
