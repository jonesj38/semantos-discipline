---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/legacy-ingest/package.json
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.026227+00:00
---

# runtime/legacy-ingest/package.json

```json
{
  "name": "@semantos/legacy-ingest",
  "version": "0.1.0",
  "private": true,
  "type": "module",
  "description": "Legacy-ingest pack — Paskian migration from Gmail / Meta / WhatsApp / Google Calendar / Xero into the substrate. LI1+LI2 land the OAuth + provider-adapter scaffold and the Gmail vertical slice.",
  "main": "src/index.ts",
  "exports": {
    ".": {
      "bun": "./src/index.ts",
      "import": "./src/index.ts",
      "default": "./src/index.ts"
    },
    "./*": {
      "bun": "./src/*",
      "import": "./src/*",
      "default": "./src/*"
    }
  },
  "scripts": {
    "check": "tsc --noEmit",
    "test": "bun test src/__tests__"
  },
  "dependencies": {
    "@semantos/protocol-types": "workspace:*",
    "@semantos/runtime-services": "workspace:*",
    "sharp": "^0.34.0"
  },
  "devDependencies": {
    "bun-types": "^1.3.13",
    "typescript": "~5.8.0"
  },
  "license": "UNLICENSED"
}

```
