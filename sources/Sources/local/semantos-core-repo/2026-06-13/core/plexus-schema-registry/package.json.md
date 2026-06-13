---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/plexus-schema-registry/package.json
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.802744+00:00
---

# core/plexus-schema-registry/package.json

```json
{
  "name": "@semantos/plexus-schema-registry",
  "version": "0.1.0",
  "type": "module",
  "description": "Plexus domain-schema registry (Phase H RM-012). Maps domain_flag → DomainSchema; encodes/decodes payload bytes per the schema; computes domainPayloadRoot; persists schemas under the vendor identity for recovery; verifies signed schemas under a SchemaAuthority. Replaces the commerce-shaped header fields with a generic per-domain payload layout.",
  "publishConfig": {
    "registry": "https://npm.pkg.github.com",
    "access": "restricted"
  },
  "repository": {
    "type": "git",
    "url": "git+https://github.com/semantos/semantos-core.git",
    "directory": "core/plexus-schema-registry"
  },
  "main": "./dist/index.js",
  "types": "./dist/index.d.ts",
  "exports": {
    ".": {
      "bun": "./src/index.ts",
      "types": "./dist/index.d.ts",
      "import": "./dist/index.js",
      "default": "./dist/index.js"
    },
    "./*": {
      "bun": "./src/*",
      "types": "./dist/*.d.ts",
      "import": "./dist/*",
      "default": "./dist/*"
    }
  },
  "files": [
    "dist",
    "src",
    "README.md"
  ],
  "scripts": {
    "build": "tsc -p tsconfig.build.json",
    "check": "tsc --noEmit",
    "clean": "rm -rf dist",
    "test": "bun test"
  },
  "dependencies": {},
  "devDependencies": {
    "bun-types": "^1.3.13",
    "typescript": "~5.8.0"
  },
  "license": "UNLICENSED"
}

```
