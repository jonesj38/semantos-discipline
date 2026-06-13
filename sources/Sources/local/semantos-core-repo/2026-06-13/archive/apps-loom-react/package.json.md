---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-loom-react/package.json
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.695999+00:00
---

# archive/apps-loom-react/package.json

```json
{
  "name": "@semantos/loom-react",
  "version": "0.1.0",
  "private": true,
  "type": "module",
  "description": "DEPRECATED 2026-05-25 — helm shell ported to apps/loom-svelte. This package is frozen; see README.md for migration table and removal timeline.",
  "scripts": {
    "dev": "vite",
    "dev:full": "bun server/index.ts & vite",
    "server": "bun server/index.ts",
    "build": "vite build",
    "preview": "vite preview",
    "test": "vitest run",
    "test:watch": "vitest"
  },
  "main": "src/services/index.ts",
  "exports": {
    ".": {
      "bun": "./src/services/index.ts",
      "import": "./src/services/index.ts",
      "default": "./src/services/index.ts"
    },
    "./types": {
      "bun": "./src/types/loom.ts",
      "import": "./src/types/loom.ts",
      "default": "./src/types/loom.ts"
    },
    "./config": {
      "bun": "./src/config/extensionConfig.ts",
      "import": "./src/config/extensionConfig.ts",
      "default": "./src/config/extensionConfig.ts"
    },
    "./config/verticalConfig": {
      "bun": "./src/config/verticalConfig.js",
      "import": "./src/config/verticalConfig.js",
      "default": "./src/config/verticalConfig.js"
    },
    "./*": {
      "bun": "./src/*",
      "import": "./src/*",
      "default": "./src/*"
    }
  },
  "dependencies": {
    "@codemirror/commands": "^6.10.3",
    "@codemirror/lang-markdown": "^6.5.0",
    "@codemirror/state": "^6.6.0",
    "@codemirror/theme-one-dark": "^6.1.3",
    "@codemirror/view": "^6.41.0",
    "@plexus/contracts": "workspace:*",
    "@plexus/vendor-sdk": "workspace:*",
    "@semantos/protocol-types": "workspace:*",
    "@semantos/runtime-services": "workspace:*",
    "@semantos/shell": "workspace:*",
    "@semantos/state": "workspace:*",
    "d3-force": "^3.0.0",
    "d3-scale": "^4.0.0",
    "react": "^19.0.0",
    "react-dom": "^19.0.0"
  },
  "devDependencies": {
    "@testing-library/jest-dom": "^6.0.0",
    "@testing-library/react": "^16.0.0",
    "@types/d3-force": "^3.0.0",
    "@types/d3-scale": "^4.0.0",
    "@types/react": "^19.0.0",
    "@types/react-dom": "^19.0.0",
    "@vitejs/plugin-react": "^4.3.0",
    "autoprefixer": "^10.4.0",
    "jsdom": "^25.0.0",
    "postcss": "^8.4.0",
    "tailwindcss": "^3.4.0",
    "typescript": "^5.4.0",
    "vite": "^6.0.0",
    "vite-plugin-node-polyfills": "^0.25.0",
    "vitest": "^3.0.0"
  }
}

```
