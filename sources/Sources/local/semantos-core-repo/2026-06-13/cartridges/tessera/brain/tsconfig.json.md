---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/tessera/brain/tsconfig.json
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.635584+00:00
---

# cartridges/tessera/brain/tsconfig.json

```json
{
  "extends": "../../tsconfig.base.json",
  "compilerOptions": {
    "outDir": "./dist",
    "rootDir": "./src",
    "declaration": true,
    "declarationMap": true,
    "sourceMap": true,
    "composite": true,
    "module": "esnext",
    "moduleResolution": "bundler",
    "target": "es2022",
    "strict": true
  },
  "include": ["src/**/*"],
  "exclude": ["dist", "node_modules", "zig"]
}

```
