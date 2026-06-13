---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/experience-cartridge/package.json
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.803545+00:00
---

# core/experience-cartridge/package.json

```json
{
  "name": "@semantos/experience-cartridge",
  "version": "0.1.0",
  "type": "module",
  "description": "Cartridge loader + registry. Wraps an ExtensionManifest with the optional surfaces an experience can contribute (grammar, lexicons, FSM edges, reducer passes, conversation hooks) and enforces version-compatibility at registration.",
  "publishConfig": {
    "registry": "https://npm.pkg.github.com",
    "access": "restricted"
  },
  "repository": {
    "type": "git",
    "url": "git+https://github.com/semantos/semantos-core.git",
    "directory": "core/experience-cartridge"
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
  "dependencies": {
    "@semantos/lexicon-core": "workspace:*",
    "@semantos/protocol-types": "workspace:*"
  },
  "devDependencies": {
    "@semantos/oddjobz": "workspace:*",
    "bun-types": "^1.3.13",
    "typescript": "~5.8.0"
  },
  "license": "UNLICENSED"
}

```
