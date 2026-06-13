---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-legacy-cli/package.json
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.682960+00:00
---

# archive/apps-legacy-cli/package.json

```json
{
  "name": "@semantos/legacy-cli",
  "version": "0.1.0",
  "private": true,
  "type": "module",
  "description": "Phase 1 CLI for legacy-ingest. Bun-runnable single-file dispatcher that wires the @semantos/legacy-ingest crate against filesystem persistence + a passphrase-derived KEK. Designed for the operator to ssh into their VPS (rbs) and run `bun run legacy <verb> ...`. Phase 2 collapses this into a Semantos Brain-managed Bun service; Phase 1's code is ~80% of Phase 2's.",
  "bin": {
    "legacy": "./src/cli.ts"
  },
  "scripts": {
    "check": "tsc --noEmit",
    "test": "bun test src/__tests__"
  },
  "dependencies": {
    "@semantos/legacy-ingest": "workspace:*",
    "@semantos/oddjobz": "workspace:*",
    "@semantos/protocol-types": "workspace:*",
    "@semantos/semantic-objects": "workspace:*"
  },
  "devDependencies": {
    "@electric-sql/pglite": "^0.4.1",
    "bun-types": "^1.3.13",
    "drizzle-orm": "^0.33.0",
    "typescript": "~5.8.0"
  },
  "license": "UNLICENSED"
}

```
