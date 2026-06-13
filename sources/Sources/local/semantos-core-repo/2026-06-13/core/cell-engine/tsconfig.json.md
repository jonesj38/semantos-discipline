---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-engine/tsconfig.json
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.806097+00:00
---

# core/cell-engine/tsconfig.json

```json
{
  "extends": "../../tsconfig.base.json",
  "compilerOptions": {
    "rootDir": ".",
    "outDir": "dist",
    "paths": {
      "@semantos/core": ["../../src"],
      "@semantos/core/*": ["../../src/*"],
      "@semantos/cell-ops": ["../cell-ops/src"],
      "@semantos/cell-ops/*": ["../cell-ops/src/*"],
      "@semantos/protocol-types": ["../protocol-types/src"],
      "@semantos/protocol-types/*": ["../protocol-types/src/*"]
    }
  },
  "include": ["bindings/**/*.ts", "tests-bun/**/*.ts", "__tests__/**/*.ts"]
}

```
