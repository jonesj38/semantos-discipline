---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/tests/gates/tsconfig.json
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.582067+00:00
---

# tests/gates/tsconfig.json

```json
{
  "extends": "../../tsconfig.base.json",
  "compilerOptions": {
    "lib": ["ES2022", "DOM"],
    "paths": {
      "@semantos/core": ["../../src"],
      "@semantos/core/src/*": ["../../src/*"],
      "@semantos/cell-ops": ["../cell-ops/src"],
      "@semantos/cell-ops/*": ["../cell-ops/src/*"],
      "@semantos/protocol-types": ["../protocol-types/src"],
      "@semantos/protocol-types/*": ["../protocol-types/src/*"],
      "@configs/*": ["../../configs/*"]
    }
  },
  "include": ["./**/*.ts"]
}

```
