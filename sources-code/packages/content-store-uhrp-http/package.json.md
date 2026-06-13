---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/content-store-uhrp-http/package.json
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.395378+00:00
---

# packages/content-store-uhrp-http/package.json

```json
{
  "name": "@semantos/content-store-uhrp-http",
  "version": "0.6.0",
  "type": "module",
  "description": "UHRP HTTP ContentStore adapter — POST /quote, POST /upload, GET /find, POST /renew with optional BRC-31 signing.",
  "publishConfig": {
    "registry": "https://npm.pkg.github.com",
    "access": "restricted"
  },
  "repository": {
    "type": "git",
    "url": "git+https://github.com/semantos/semantos-core.git",
    "directory": "packages/content-store-uhrp-http"
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
    "@bsv/sdk": "^2.0.0",
    "@semantos/protocol-types": "workspace:*"
  },
  "devDependencies": {
    "@types/node": "^20.0.0",
    "typescript": "~5.8.0"
  },
  "license": "UNLICENSED"
}

```
