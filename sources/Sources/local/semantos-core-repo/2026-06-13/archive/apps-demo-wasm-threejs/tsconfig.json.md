---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-demo-wasm-threejs/tsconfig.json
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.688793+00:00
---

# archive/apps-demo-wasm-threejs/tsconfig.json

```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "ESNext",
    "moduleResolution": "bundler",
    "strict": true,
    "noUnusedLocals": true,
    "noUnusedParameters": true,
    "noImplicitReturns": true,
    "skipLibCheck": true,
    "esModuleInterop": true,
    "allowSyntheticDefaultImports": true,
    "lib": ["ES2022", "DOM", "DOM.Iterable"],
    "types": ["vite/client"],
    "isolatedModules": true,
    "resolveJsonModule": true,
    "jsx": "preserve",
    "paths": {
      "@semantos/identity-ports": ["../../core/identity-ports/src/index.ts"],
      "@semantos/identity-ports/stub": ["../../core/identity-ports/src/stub-binding.ts"],
      "@semantos/cube-object": ["../../core/cube-object/src/index.ts"],
      "@semantos/cube-object/linearity": ["../../core/cube-object/src/linearity.ts"],
      "@semantos/cube-object/mesh": ["../../core/cube-object/src/cube-mesh.ts"],
      "@semantos/state": ["../../core/state/src/index.ts"],
      "@plexus/contracts": ["../../core/plexus-contracts/src/index.ts"],
      "@plexus/vendor-sdk": ["../../core/plexus-vendor-sdk/src/index.ts"]
    }
  },
  "include": ["src/**/*"]
}

```
