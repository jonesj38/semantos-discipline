---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/node/tsconfig.json
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.030460+00:00
---

# runtime/node/tsconfig.json

```json
{
  "extends": "../../tsconfig.base.json",
  "compilerOptions": {
    "rootDir": "src",
    "outDir": "dist",
    "paths": {
      "@semantos/protocol-types": ["../protocol-types/src"],
      "@semantos/protocol-types/*": ["../protocol-types/src/*"],
      "@semantos/shell": ["../shell/src"],
      "@semantos/shell/*": ["../shell/src/*"],
      "@semantos/core": ["../../src"],
      "@semantos/core/src/*": ["../../src/*"]
    }
  },
  "include": ["src/**/*.ts"]
}

```
