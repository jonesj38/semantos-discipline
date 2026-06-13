---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/calendar/package.json
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.390531+00:00
---

# packages/calendar/package.json

```json
{
  "name": "@semantos/calendar-ext",
  "version": "0.6.0",
  "type": "module",
  "description": "Calendar as a semantic object: one schedule owns a single append-only patch stream of hold/book/release/cancel operations. Hats are metadata attribution. Conflict detection = fold + filter.",
  "publishConfig": {
    "registry": "https://npm.pkg.github.com",
    "access": "restricted"
  },
  "repository": {
    "type": "git",
    "url": "git+https://github.com/semantos/semantos-core.git",
    "directory": "packages/calendar"
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
    "./ui": {
      "bun": "./src/ui/index.ts",
      "types": "./dist/ui/index.d.ts",
      "import": "./dist/ui/index.js",
      "default": "./dist/ui/index.js"
    },
    "./lexicon": {
      "bun": "./src/lexicon/index.ts",
      "types": "./dist/lexicon/index.d.ts",
      "import": "./dist/lexicon/index.js",
      "default": "./dist/lexicon/index.js"
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
    "test": "bun test"
  },
  "dependencies": {
    "@plexus/contracts": "workspace:*",
    "@semantos/intent": "workspace:*",
    "@semantos/semantic-objects": "workspace:*",
    "@semantos/semantos-sir": "workspace:*",
    "drizzle-orm": "^0.33.0",
    "postgres": "^3.4.0"
  },
  "peerDependencies": {
    "react": "^18 || ^19"
  },
  "peerDependenciesMeta": {
    "react": {
      "optional": true
    }
  },
  "devDependencies": {
    "@electric-sql/pglite": "^0.4.1",
    "@types/react": "^19",
    "bun-types": "^1.3.13",
    "drizzle-kit": "^0.24.0",
    "fast-check": "^3.23.0",
    "react": "^19.0.0",
    "typescript": "~5.8.0"
  },
  "license": "UNLICENSED"
}

```
