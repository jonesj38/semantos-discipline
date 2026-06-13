---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/lexicon-core/tsconfig.build.json
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.793267+00:00
---

# core/lexicon-core/tsconfig.build.json

```json
{
  "extends": "./tsconfig.json",
  "compilerOptions": {
    "outDir": "./dist",
    "rootDir": "./src",
    "lib": ["ES2022"],
    "declaration": true,
    "declarationMap": true,
    "sourceMap": true,
    "noEmit": false
  },
  "include": ["src/**/*.ts"],
  "exclude": ["node_modules", "dist", "src/**/__tests__/**", "src/**/*.test.ts", "src/**/*.spec.ts"]
}

```
