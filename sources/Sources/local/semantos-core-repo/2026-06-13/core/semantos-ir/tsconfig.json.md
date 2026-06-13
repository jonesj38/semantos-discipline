---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/semantos-ir/tsconfig.json
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.807189+00:00
---

# core/semantos-ir/tsconfig.json

```json
{
  "extends": "../../tsconfig.base.json",
  "compilerOptions": {
    "rootDir": "src",
    "outDir": "dist",
    "paths": {
      "@semantos/core": ["../../src"],
      "@semantos/core/*": ["../../src/*"]
    }
  },
  "include": ["src/**/*.ts"]
}

```
