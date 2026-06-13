---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/content-store-local-fs/package.json
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.391647+00:00
---

# packages/content-store-local-fs/package.json

```json
{
  "name": "@semantos/content-store-local-fs",
  "version": "0.6.0",
  "type": "module",
  "description": "Filesystem ContentStore adapter — content-addressed layout {root}/<hex[0:2]>/<hex>.",
  "publishConfig": {
    "registry": "https://npm.pkg.github.com",
    "access": "restricted"
  },
  "repository": {
    "type": "git",
    "url": "git+https://github.com/semantos/semantos-core.git",
    "directory": "packages/content-store-local-fs"
  },
  "main": "./dist/index.js",
  "types": "./dist/index.d.ts",
  "exports": {
    ".": {
      "bun": "./src/index.ts",
      "types": "./dist/index.d.ts",
      "import": "./dist/index.js",
      "default": "./dist/index.js"
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
    "clean": "rm -rf dist"
  },
  "dependencies": {
    "@semantos/protocol-types": "workspace:*"
  },
  "devDependencies": {
    "@types/node": "^20.0.0",
    "typescript": "~5.8.0"
  },
  "license": "UNLICENSED"
}

```
