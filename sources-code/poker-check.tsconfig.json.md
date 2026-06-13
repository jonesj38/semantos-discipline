---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/poker-check.tsconfig.json
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.308906+00:00
---

# poker-check.tsconfig.json

```json
{
  "extends": "./tsconfig.base.json",
  "compilerOptions": {
    "rootDir": ".",
    "outDir": "/tmp/poker-out",
    "noEmit": true,
    "skipLibCheck": true,
    "lib": ["ES2022", "DOM"],
    "types": ["node"],
    "baseUrl": ".",
    "paths": {
      "@semantos/core": ["src"],
      "@semantos/core/src/*": ["src/*"],
      "@semantos/cell-ops": ["packages/cell-ops/src"],
      "@semantos/cell-ops/*": ["packages/cell-ops/src/*"],
      "@semantos/protocol-types": ["packages/protocol-types/src"],
      "@semantos/protocol-types/*": ["packages/protocol-types/src/*"],
      "@semantos/poker-agent": ["packages/poker-agent/src"],
      "@semantos/poker-agent/*": ["packages/poker-agent/src/*"]
    }
  },
  "include": [
    "packages/poker-agent/src/payment-channel.ts",
    "packages/protocol-types/src/transition-validator.ts",
    "packages/protocol-types/src/cell-store.ts",
    "packages/protocol-types/src/cell-header.ts",
    "packages/__tests__/transition-validator.test.ts"
  ]
}

```
