---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-loom-react/tsconfig.json
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.696512+00:00
---

# archive/apps-loom-react/tsconfig.json

```json
{
  "compilerOptions": {
    "target": "ES2022",
    "lib": ["ES2022", "DOM", "DOM.Iterable"],
    "module": "ESNext",
    "moduleResolution": "bundler",
    "jsx": "react-jsx",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "forceConsistentCasingInFileNames": true,
    "resolveJsonModule": true,
    "isolatedModules": true,
    "noEmit": true,
    "paths": {
      "@semantos/core": ["../../src"],
      "@semantos/core/*": ["../../src/*"],
      "@semantos/cell-ops": ["../cell-ops/src"],
      "@semantos/cell-ops/*": ["../cell-ops/src/*"],
      "@semantos/protocol-types": ["../protocol-types/src"],
      "@semantos/protocol-types/*": ["../protocol-types/src/*"],
      "@semantos/cell-engine": ["../cell-engine/bindings"],
      "@semantos/cell-engine/*": ["../cell-engine/bindings/*"],
      "@configs/*": ["../../configs/*"],
      "@plexus/contracts": ["../plexus-contracts/src"],
      "@plexus/vendor-sdk": ["../plexus-vendor-sdk/src"]
    }
  },
  "include": ["src"]
}

```
