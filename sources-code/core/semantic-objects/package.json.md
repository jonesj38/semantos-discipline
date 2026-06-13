---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/semantic-objects/package.json
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.799037+00:00
---

# core/semantic-objects/package.json

```json
{
  "name": "@semantos/semantic-objects",
  "version": "0.6.0",
  "type": "module",
  "description": "Canonical patch substrate: sem_objects, sem_object_patches, sem_object_states, sem_participants. The 'loom' that every domain extension writes to.",
  "publishConfig": {
    "registry": "https://npm.pkg.github.com",
    "access": "restricted"
  },
  "repository": {
    "type": "git",
    "url": "git+https://github.com/semantos/semantos-core.git",
    "directory": "core/semantic-objects"
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
    "./migrations/*": "./migrations/*",
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
    "migrations",
    "README.md"
  ],
  "scripts": {
    "build": "tsc -p tsconfig.build.json",
    "check": "tsc --noEmit",
    "clean": "rm -rf dist",
    "test": "bun test",
    "db:generate": "drizzle-kit generate --config drizzle.config.ts"
  },
  "dependencies": {
    "drizzle-orm": "^0.33.0",
    "postgres": "^3.4.0"
  },
  "devDependencies": {
    "@electric-sql/pglite": "^0.4.1",
    "bun-types": "^1.3.13",
    "drizzle-kit": "^0.24.0",
    "typescript": "~5.8.0"
  },
  "license": "UNLICENSED"
}

```
