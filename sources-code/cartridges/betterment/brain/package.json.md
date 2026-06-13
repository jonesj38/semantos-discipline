---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/betterment/brain/package.json
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.561300+00:00
---

# cartridges/betterment/brain/package.json

```json
{
  "name": "@semantos/betterment",
  "version": "0.1.0",
  "type": "module",
  "description": "Betterment cartridge brain layer — personal practice + Paskian narrative substrate for self-development. T7.a MVP: 8 practice cell-type validators (release, session, intention, insight, pattern, connection, vacuum, seal) + capability manifest. Per T6: pask stays kernel-side; this cartridge declares cell shapes pask reads and emits over personal data. Renamed from @semantos/self 2026-05-29 to free 'self' for the shell identity primitive.",
  "publishConfig": {
    "registry": "https://npm.pkg.github.com",
    "access": "restricted"
  },
  "repository": {
    "type": "git",
    "url": "git+https://github.com/semantos/semantos-core.git",
    "directory": "cartridges/betterment/brain"
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
    "./cell-types": {
      "bun": "./src/cell-types/index.ts",
      "types": "./dist/cell-types/index.d.ts",
      "import": "./dist/cell-types/index.js",
      "default": "./dist/cell-types/index.js"
    }
  },
  "files": ["dist", "src", "README.md"],
  "scripts": {
    "build": "tsc -p tsconfig.json",
    "check": "tsc --noEmit",
    "clean": "rm -rf dist",
    "test": "bun test"
  },
  "dependencies": {
    "@semantos/protocol-types": "workspace:*",
    "@semantos/semantos-sir": "workspace:*"
  },
  "devDependencies": {
    "bun-types": "^1.3.13",
    "typescript": "~5.8.0"
  },
  "license": "UNLICENSED"
}

```
