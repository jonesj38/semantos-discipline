---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/semantos-sir/tsconfig.json
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.792168+00:00
---

# core/semantos-sir/tsconfig.json

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
