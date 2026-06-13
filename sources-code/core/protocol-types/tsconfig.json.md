---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/tsconfig.json
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.796792+00:00
---

# core/protocol-types/tsconfig.json

```json
{
  "extends": "../../tsconfig.base.json",
  "compilerOptions": {
    "rootDir": "src",
    "outDir": "dist",
    "paths": {
      "@semantos/core": ["../../src"],
      "@semantos/core/src/*": ["../../src/*"],
      "@semantos/cell-ops": ["../cell-ops/src"],
      "@semantos/cell-ops/*": ["../cell-ops/src/*"]
    }
  },
  "include": ["src/**/*.ts"]
}

```
