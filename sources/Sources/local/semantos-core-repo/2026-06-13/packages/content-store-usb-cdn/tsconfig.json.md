---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/content-store-usb-cdn/tsconfig.json
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.396704+00:00
---

# packages/content-store-usb-cdn/tsconfig.json

```json
{
  "extends": "../../tsconfig.base.json",
  "compilerOptions": {
    "rootDir": "src",
    "outDir": "dist",
    "paths": {
      "@semantos/protocol-types": ["../../core/protocol-types/src"],
      "@semantos/protocol-types/*": ["../../core/protocol-types/src/*"]
    }
  },
  "include": ["src/**/*.ts"]
}

```
