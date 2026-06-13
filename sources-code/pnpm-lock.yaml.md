---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/pnpm-lock.yaml
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.312158+00:00
---

# pnpm-lock.yaml

```yaml
lockfileVersion: '9.0'

settings:
  autoInstallPeers: true
  excludeLinksFromLockfile: false

importers:

  .:
    dependencies:
      '@anthropic-ai/sdk':
        specifier: ^0.99.0
        version: 0.99.0
      geotiff:
        specifier: ^3.0.5
        version: 3.0.5
      yaml:
        specifier: ^2.9.0
        version: 2.9.0
    devDependencies:
      '@bsv/sdk':
        specifier: ^2.0.0
        version: 2.0.13
      '@changesets/changelog-github':
        specifier: ^0.6.0
        version: 0.6.0
      '@changesets/cli':
        specifier: ^2.31.0
        version: 2.31.0(@types/node@20.19.39)
      '@types/node':
        specifier: ^20.0.0
        version: 20.19.39
      glob:
        specifier: ^13.0.6
        version: 13.0.6
      ts-morph:
        specifier: ^28.0.0
        version: 28.0.0
      typescript:
        specifier: ~5.8.0
        version: 5.8.3

  apps/loom-svelte:
    dependencies:
      svelte:
        specifier: ^5.0.0
        version: 5.55.4
    devDependencies:
      '@sveltejs/vite-plugin-svelte':
        specifier: ^4.0.0
        version: 4.0.4(svelte@5.55.4)(vite@5.4.21(@types/node@20.19.39))
      '@tsconfig/svelte':
        specifier: ^5.0.0
        version: 5.0.8
      svelte-check:
        specifier: ^4.0.0
        version: 4.4.6(picomatch@4.0.4)(svelte@5.55.4)(typescript@5.8.3)
      tsx:
        specifier: ^4.7.0
        version: 4.21.0
      typescript:
        specifier: ~5.8.0
        version: 5.8.3
      vite:
        specifier: ^5.4.0
        version: 5.4.21(@types/node@20.19.39)

  apps/oddjobtodd:
    dependencies:
      react:
        specifier: ^19.0.0
        version: 19.2.5
      react-dom:
        specifier: ^19.0.0
        version: 19.2.5(react@19.2.5)
    devDependencies:
      '@types/react':
        specifier: ^19.0.0
        version: 19.2.14
      '@types/react-dom':
        specifier: ^19.0.0
        version: 19.2.3(@types/react@19.2.14)
      '@vitejs/plugin-react':
        specifier: ^4.3.0
        version: 4.7.0(vite@6.4.2(@types/node@20.19.39)(jiti@1.21.7)(tsx@4.21.0)(yaml@2.9.0))
      typescript:
        specifier: ^5.4.0
        version: 5.8.3
      vite:
        specifier: ^6.0.0
        version: 6.4.2(@types/node@20.19.39)(jiti@1.21.7)(tsx@4.21.0)(yaml@2.9.0)

  archive/apps-demo-wasm-threejs:
    dependencies:
      '@semantos/cube-object':
        specifier: workspace:*
        version: link:../../core/cube-object
      '@semantos/identity-ports':
        specifier: workspace:*
        version: link:../../core/identity-ports
      three:
        specifier: ^0.165.0
        version: 0.165.0
    devDependencies:
      '@types/three':
        specifier: ^0.165.0
        version: 0.165.0
      typescript:
        specifier: ~5.8.0
        version: 5.8.3
      vite:
        specifier: ^5.4.0
        version: 5.4.21(@types/node@20.19.39)
      vitest:
        specifier: ^1.6.0
        version: 1.6.1(@types/node@20.19.39)(jsdom@25.0.1)

  archive/apps-legacy-cli:
    dependencies:
      '@semantos/legacy-ingest':
        specifier: workspace:*
        version: link:../../runtime/legacy-ingest
      '@semantos/oddjobz':
        specifier: workspace:*
        version: link:../../cartridges/oddjobz/brain
      '@semantos/protocol-types':
        specifier: workspace:*
        version: link:../../core/protocol-types
      '@semantos/semantic-objects':
        specifier: workspace:*
        version: link:../../core/semantic-objects
    devDependencies:
      '@electric-sql/pglite':
        specifier: ^0.4.1
        version: 0.4.4
      bun-types:
        specifier: ^1.3.13
        version: 1.3.13
      drizzle-orm:
        specifier: ^0.33.0
        version: 0.33.0(@electric-sql/pglite@0.4.4)(@types/react@19.2.14)(bun-types@1.3.13)(postgres@3.4.9)(react@19.2.5)
      typescript:
        specifier: ~5.8.0
        version: 5.8.3

  archive/apps-loom-react:
    dependencies:
      '@codemirror/commands':
        specifier: ^6.10.3
        version: 6.10.3
      '@codemirror/lang-markdown':
        specifier: ^6.5.0
        version: 6.5.0
      '@codemirror/state':
        specifier: ^6.6.0
        version: 6.6.0
      '@codemirror/theme-one-dark':
        specifier: ^6.1.3
        version: 6.1.3
      '@codemirror/view':
        specifier: ^6.41.0
        version: 6.41.1
      '@plexus/contracts':
        specifier: workspace:*
        version: link:../../core/plexus-contracts
      '@plexus/vendor-sdk':
        specifier: workspace:*
        version: link:../../core/plexus-vendor-sdk
      '@semantos/protocol-types':
        specifier: workspace:*
        version: link:../../core/protocol-types
      '@semantos/runtime-services':
        specifier: workspace:*
        version: link:../../runtime/services
      '@semantos/shell':
        specifier: workspace:*
        version: link:../../runtime/shell
      '@semantos/state':
        specifier: workspace:*
        version: link:../../core/state
      d3-force:
        specifier: ^3.0.0
        version: 3.0.0
      d3-scale:
        specifier: ^4.0.0
        version: 4.0.2
      react:
        specifier: ^19.0.0
        version: 19.2.5
      react-dom:
        specifier: ^19.0.0
        version: 19.2.5(react@19.2.5)
    devDependencies:
      '@testing-library/jest-dom':
        specifier: ^6.0.0
        version: 6.9.1
      '@testing-library/react':
        specifier: ^16.0.0
        version: 16.3.2(@testing-library/dom@10.4.1)(@types/react-dom@19.2.3(@types/react@19.2.14))(@types/react@19.2.14)(react-dom@19.2.5(react@19.2.5))(react@19.2.5)
      '@types/d3-force':
        specifier: ^3.0.0
        version: 3.0.10
      '@types/d3-scale':
        specifier: ^4.0.0
        version: 4.0.9
      '@types/react':
        specifier: ^19.0.0
        version: 19.2.14
      '@types/react-dom':
        specifier: ^19.0.0
        version: 19.2.3(@types/react@19.2.14)
      '@vitejs/plugin-react':
        specifier: ^4.3.0
        version: 4.7.0(vite@6.4.2(@types/node@20.19.39)(jiti@1.21.7)(tsx@4.21.0)(yaml@2.9.0))
      autoprefixer:
        specifier: ^10.4.0
        version: 10.4.27(postcss@8.5.9)
      jsdom:
        specifier: ^25.0.0
        version: 25.0.1
      postcss:
        specifier: ^8.4.0
        version: 8.5.9
      tailwindcss:
        specifier: ^3.4.0
        version: 3.4.19(tsx@4.21.0)(yaml@2.9.0)
      typescript:
        specifier: ^5.4.0
        version: 5.8.3
      vite:
        specifier: ^6.0.0
        version: 6.4.2(@types/node@20.19.39)(jiti@1.21.7)(tsx@4.21.0)(yaml@2.9.0)
      vite-plugin-node-polyfills:
        specifier: ^0.25.0
        version: 0.25.0(rollup@4.60.1)(vite@6.4.2(@types/node@20.19.39)(jiti@1.21.7)(tsx@4.21.0)(yaml@2.9.0))
      vitest:
        specifier: ^3.0.0
        version: 3.2.4(@types/node@20.19.39)(jiti@1.21.7)(jsdom@25.0.1)(tsx@4.21.0)(yaml@2.9.0)

  archive/apps-mud:
    dependencies:
      '@semantos/cell-engine':
        specifier: workspace:*
        version: link:../../core/cell-engine
      '@semantos/game-sdk':
        specifier: workspace:*
        version: link:../../packages/game-sdk
      '@semantos/games':
        specifier: workspace:*
        version: link:../../packages/games
      '@semantos/protocol-types':
        specifier: workspace:*
        version: link:../../core/protocol-types
      '@semantos/state':
        specifier: workspace:*
        version: link:../../core/state
      rot-js:
        specifier: ^2.2.0
        version: 2.2.1

  archive/apps-piggybank:
    dependencies:
      '@bsv/sdk':
        specifier: ^2.0.0
        version: 2.0.13
      '@semantos/core':
        specifier: file:../../
        version: file:(@bsv/sdk@2.0.13)

  archive/apps-poker-agent:
    dependencies:
      '@anthropic-ai/sdk':
        specifier: ^0.39.0
        version: 0.39.0
      '@bsv/sdk':
        specifier: ^2.0.0
        version: 2.0.13
      '@semantos/cell-engine':
        specifier: workspace:*
        version: link:../../core/cell-engine
      '@semantos/protocol-types':
        specifier: workspace:*
        version: link:../../core/protocol-types
      '@semantos/session-protocol':
        specifier: workspace:*
        version: link:../../runtime/session-protocol
      '@semantos/state':
        specifier: workspace:*
        version: link:../../core/state
    devDependencies:
      bun-types:
        specifier: ^1.3.13
        version: 1.3.13

  archive/apps-settlement:
    dependencies:
      '@semantos/cell-ops':
        specifier: workspace:*
        version: link:../../core/cell-ops
      '@semantos/game-sdk':
        specifier: workspace:*
        version: link:../../packages/game-sdk
      '@semantos/poker-agent':
        specifier: workspace:*
        version: link:../apps-poker-agent
      '@semantos/protocol-types':
        specifier: workspace:*
        version: link:../../core/protocol-types
      cbor-x:
        specifier: ^1.5.0
        version: 1.6.4
      cors:
        specifier: ^2.8.5
        version: 2.8.6
      express:
        specifier: ^4.18.0
        version: 4.22.1
      ws:
        specifier: ^8.16.0
        version: 8.20.0
    devDependencies:
      '@types/cors':
        specifier: ^2.8.0
        version: 2.8.19
      '@types/express':
        specifier: ^4.17.0
        version: 4.17.25
      '@types/ws':
        specifier: ^8.5.0
        version: 8.18.1

  archive/apps-world-client:
    dependencies:
      '@bsv/sdk':
        specifier: ^2.0.13
        version: 2.0.13
      '@semantos/cube-object':
        specifier: workspace:*
        version: link:../../core/cube-object
      '@semantos/identity-ports':
        specifier: workspace:*
        version: link:../../core/identity-ports
      '@semantos/protocol-types':
        specifier: workspace:*
        version: link:../../core/protocol-types
      '@semantos/world-sdk':
        specifier: workspace:*
        version: link:../packages-world-sdk
      '@sqlite.org/sqlite-wasm':
        specifier: ^3.53.0-build1
        version: 3.53.0-build1
      phoenix:
        specifier: ^1.7.14
        version: 1.8.5
      three:
        specifier: ^0.165.0
        version: 0.165.0
    devDependencies:
      '@types/phoenix':
        specifier: ^1.6.5
        version: 1.6.7
      '@types/three':
        specifier: ^0.165.0
        version: 0.165.0
      typescript:
        specifier: ~5.8.0
        version: 5.8.3
      vite:
        specifier: ^5.4.0
        version: 5.4.21(@types/node@20.19.39)
      vitest:
        specifier: ^1.6.0
        version: 1.6.1(@types/node@20.19.39)(jsdom@25.0.1)

  archive/packages-world-sdk:
    dependencies:
      '@bsv/sdk':
        specifier: ^2.0.13
        version: 2.0.13
      '@semantos/protocol-types':
        specifier: workspace:*
        version: link:../../core/protocol-types
    devDependencies:
      typescript:
        specifier: ~5.8.0
        version: 5.8.3

  cartridges/betterment/brain:
    dependencies:
      '@semantos/protocol-types':
        specifier: workspace:*
        version: link:../../../core/protocol-types
      '@semantos/semantos-sir':
        specifier: workspace:*
        version: link:../../../core/semantos-sir
    devDependencies:
      bun-types:
        specifier: ^1.3.13
        version: 1.3.13
      typescript:
        specifier: ~5.8.0
        version: 5.8.3

  cartridges/bsv-anchor-bundle/brain:
    dependencies:
      '@plexus/vendor-sdk':
        specifier: workspace:*
        version: link:../../../core/plexus-vendor-sdk
      '@semantos/anchor-attestation':
        specifier: workspace:*
        version: link:../../../core/anchor-attestation
      '@semantos/protocol-types':
        specifier: workspace:*
        version: link:../../../core/protocol-types
    devDependencies:
      '@bsv/sdk':
        specifier: ^1.7.6
        version: 1.10.4

  cartridges/chess/web:
    dependencies:
      '@noble/hashes':
        specifier: ^1.4.0
        version: 1.8.0
      '@semantos/cube-object':
        specifier: workspace:*
        version: link:../../../core/cube-object
      '@semantos/world-sdk':
        specifier: workspace:*
        version: link:../../../archive/packages-world-sdk
      svelte:
        specifier: ^5.55.4
        version: 5.55.4
      three:
        specifier: ^0.165.0
        version: 0.165.0
    devDependencies:
      '@sveltejs/vite-plugin-svelte':
        specifier: ^5.1.1
        version: 5.1.1(svelte@5.55.4)(vite@6.4.2(@types/node@20.19.39)(jiti@1.21.7)(tsx@4.21.0)(yaml@2.9.0))
      '@types/three':
        specifier: ^0.165.0
        version: 0.165.0
      typescript:
        specifier: ~5.8.0
        version: 5.8.3
      vite:
        specifier: ^6.4.2
        version: 6.4.2(@types/node@20.19.39)(jiti@1.21.7)(tsx@4.21.0)(yaml@2.9.0)
      vitest:
        specifier: ^1.6.0
        version: 1.6.1(@types/node@20.19.39)(jsdom@25.0.1)

  cartridges/jambox/web:
    dependencies:
      '@bsv/sdk':
        specifier: ^1.4.0
        version: 1.10.4
      '@semantos/world-sdk':
        specifier: workspace:*
        version: link:../../../archive/packages-world-sdk
      phoenix:
        specifier: ^1.7.0
        version: 1.8.5
      svelte:
        specifier: ^5.55.4
        version: 5.55.4
      three:
        specifier: ^0.165.0
        version: 0.165.0
    devDependencies:
      '@sveltejs/vite-plugin-svelte':
        specifier: ^5.1.1
        version: 5.1.1(svelte@5.55.4)(vite@6.4.2(@types/node@20.19.39)(jiti@1.21.7)(tsx@4.21.0)(yaml@2.9.0))
      '@types/three':
        specifier: ^0.165.0
        version: 0.165.0
      '@vitest/snapshot':
        specifier: ^1.6.0
        version: 1.6.1
      typescript:
        specifier: ~5.8.0
        version: 5.8.3
      vite:
        specifier: ^6.4.2
        version: 6.4.2(@types/node@20.19.39)(jiti@1.21.7)(tsx@4.21.0)(yaml@2.9.0)
      vitest:
        specifier: ^1.6.0
        version: 1.6.1(@types/node@20.19.39)(jsdom@25.0.1)

  cartridges/oddjobz/brain:
    dependencies:
      '@anthropic-ai/sdk':
        specifier: ^0.37.0
        version: 0.37.0
      '@semantos/conversation-graph':
        specifier: workspace:*
        version: link:../../../core/conversation-graph
      '@semantos/intent':
        specifier: workspace:*
        version: link:../../../runtime/intent
      '@semantos/legacy-ingest':
        specifier: workspace:*
        version: link:../../../runtime/legacy-ingest
      '@semantos/protocol-types':
        specifier: workspace:*
        version: link:../../../core/protocol-types
      '@semantos/scg-relations':
        specifier: workspace:*
        version: link:../../../core/scg-relations
      '@semantos/semantic-objects':
        specifier: workspace:*
        version: link:../../../core/semantic-objects
      '@semantos/semantos-sir':
        specifier: workspace:*
        version: link:../../../core/semantos-sir
      drizzle-orm:
        specifier: ^0.33.0
        version: 0.33.0(@electric-sql/pglite@0.4.4)(@types/react@19.2.14)(bun-types@1.3.13)(postgres@3.4.9)(react@19.2.5)
      postgres:
        specifier: ^3.4.0
        version: 3.4.9
    devDependencies:
      bun-types:
        specifier: ^1.3.13
        version: 1.3.13
      typescript:
        specifier: ~5.8.0
        version: 5.8.3

  cartridges/scg/brain:
    dependencies:
      '@plexus/contracts':
        specifier: workspace:*
        version: link:../../../core/plexus-contracts
      '@semantos/experience-cartridge':
        specifier: workspace:*
        version: link:../../../core/experience-cartridge
      '@semantos/lexicon-core':
        specifier: workspace:*
        version: link:../../../core/lexicon-core
      '@semantos/scg-relations':
        specifier: workspace:*
        version: link:../../../core/scg-relations
    devDependencies:
      bun-types:
        specifier: ^1.3.13
        version: 1.3.13
      typescript:
        specifier: ~5.8.0
        version: 5.8.3

  cartridges/tessera/brain: {}

  cartridges/wallet-headers/brain:
    dependencies:
      '@noble/hashes':
        specifier: ^1.7.1
        version: 1.8.0
      '@noble/secp256k1':
        specifier: ^2.2.3
        version: 2.3.0
    devDependencies:
      bun-types:
        specifier: ^1.3.13
        version: 1.3.13
      fake-indexeddb:
        specifier: ^6.0.0
        version: 6.2.5
      typescript:
        specifier: ~5.8.0
        version: 5.8.3

  core/anchor-attestation:
    dependencies:
      '@plexus/vendor-sdk':
        specifier: workspace:*
        version: link:../plexus-vendor-sdk
      '@semantos/plexus-schema-registry':
        specifier: workspace:*
        version: link:../plexus-schema-registry
    devDependencies:
      '@bsv/sdk':
        specifier: ^1.7.6
        version: 1.10.4
      bun-types:
        specifier: ^1.3.13
        version: 1.3.13
      typescript:
        specifier: ~5.8.0
        version: 5.8.3

  core/cell-engine:
    dependencies:
      '@semantos/cell-ops':
        specifier: workspace:*
        version: link:../cell-ops
      '@semantos/core':
        specifier: file:../../
        version: file:(@bsv/sdk@2.0.13)
      '@semantos/plexus-schema-registry':
        specifier: workspace:*
        version: link:../plexus-schema-registry
      '@semantos/protocol-types':
        specifier: workspace:*
        version: link:../protocol-types
    devDependencies:
      '@bsv/sdk':
        specifier: ^2.0.0
        version: 2.0.13
      typescript:
        specifier: ^5.4.0
        version: 5.8.3

  core/cell-ops:
    devDependencies:
      '@semantos/plexus-schema-registry':
        specifier: workspace:*
        version: link:../plexus-schema-registry
      typescript:
        specifier: ~5.8.0
        version: 5.8.3

  core/constants: {}

  core/contact-book:
    dependencies:
      '@semantos/identity-ports':
        specifier: workspace:*
        version: link:../identity-ports
      '@semantos/protocol-types':
        specifier: workspace:*
        version: link:../protocol-types
      '@semantos/state':
        specifier: workspace:*
        version: link:../state
    devDependencies:
      bun-types:
        specifier: ^1.3.13
        version: 1.3.13
      typescript:
        specifier: ~5.8.0
        version: 5.8.3

  core/conversation-graph:
    dependencies:
      '@semantos/scg-relations':
        specifier: workspace:*
        version: link:../scg-relations
      '@semantos/semantic-objects':
        specifier: workspace:*
        version: link:../semantic-objects
      drizzle-orm:
        specifier: ^0.33.0
        version: 0.33.0(@electric-sql/pglite@0.4.4)(@types/react@19.2.14)(bun-types@1.3.13)(postgres@3.4.9)(react@19.2.5)
    devDependencies:
      '@electric-sql/pglite':
        specifier: ^0.4.1
        version: 0.4.4
      '@semantos/intent':
        specifier: workspace:*
        version: link:../../runtime/intent
      '@semantos/semantos-ir':
        specifier: workspace:*
        version: link:../semantos-ir
      '@semantos/semantos-sir':
        specifier: workspace:*
        version: link:../semantos-sir
      bun-types:
        specifier: ^1.3.13
        version: 1.3.13
      typescript:
        specifier: ~5.8.0
        version: 5.8.3

  core/cube-object:
    dependencies:
      '@semantos/identity-ports':
        specifier: workspace:*
        version: link:../identity-ports
      '@semantos/state':
        specifier: workspace:*
        version: link:../state
    devDependencies:
      '@types/three':
        specifier: ^0.165.0
        version: 0.165.0
      bun-types:
        specifier: ^1.3.13
        version: 1.3.13
      three:
        specifier: ^0.165.0
        version: 0.165.0
      typescript:
        specifier: ~5.8.0
        version: 5.8.3

  core/experience-cartridge:
    dependencies:
      '@semantos/lexicon-core':
        specifier: workspace:*
        version: link:../lexicon-core
      '@semantos/protocol-types':
        specifier: workspace:*
        version: link:../protocol-types
    devDependencies:
      '@semantos/oddjobz':
        specifier: workspace:*
        version: link:../../cartridges/oddjobz/brain
      bun-types:
        specifier: ^1.3.13
        version: 1.3.13
      typescript:
        specifier: ~5.8.0
        version: 5.8.3

  core/hrr:
    dependencies:
      '@semantos/semantos-ir':
        specifier: workspace:*
        version: link:../semantos-ir
    devDependencies:
      typescript:
        specifier: ~5.8.0
        version: 5.8.3

  core/identity-ports:
    dependencies:
      '@plexus/contracts':
        specifier: workspace:*
        version: link:../plexus-contracts
      '@plexus/vendor-sdk':
        specifier: workspace:*
        version: link:../plexus-vendor-sdk
      '@semantos/state':
        specifier: workspace:*
        version: link:../state
    devDependencies:
      bun-types:
        specifier: ^1.3.13
        version: 1.3.13
      typescript:
        specifier: ~5.8.0
        version: 5.8.3

  core/lexicon-core:
    devDependencies:
      bun-types:
        specifier: ^1.3.13
        version: 1.3.13
      typescript:
        specifier: ~5.8.0
        version: 5.8.3

  core/pask/bindings/ts: {}

  core/plexus-contracts:
    dependencies:
      '@semantos/protocol-types':
        specifier: workspace:*
        version: link:../protocol-types

  core/plexus-schema-registry:
    devDependencies:
      bun-types:
        specifier: ^1.3.13
        version: 1.3.13
      typescript:
        specifier: ~5.8.0
        version: 5.8.3

  core/plexus-vendor-sdk:
    dependencies:
      '@bsv/sdk':
        specifier: ^2.0.0
        version: 2.0.13
      '@plexus/contracts':
        specifier: workspace:*
        version: link:../plexus-contracts

  core/protocol-types:
    dependencies:
      '@bsv/sdk':
        specifier: ^2.0.0
        version: 2.0.13
      '@semantos/cell-ops':
        specifier: workspace:*
        version: link:../cell-ops
      '@semantos/core':
        specifier: file:../..
        version: file:(@bsv/sdk@2.0.13)
      '@semantos/state':
        specifier: workspace:*
        version: link:../state
      cbor-x:
        specifier: ^1.6.0
        version: 1.6.4
    devDependencies:
      '@semantos/plexus-schema-registry':
        specifier: workspace:*
        version: link:../plexus-schema-registry
      bun-types:
        specifier: ^1.3.13
        version: 1.3.13
      typescript:
        specifier: ~5.8.0
        version: 5.8.3

  core/scg-relations:
    dependencies:
      '@plexus/contracts':
        specifier: workspace:*
        version: link:../plexus-contracts
      '@semantos/identity-ports':
        specifier: workspace:*
        version: link:../identity-ports
      '@semantos/lexicon-core':
        specifier: workspace:*
        version: link:../lexicon-core
      '@semantos/semantic-objects':
        specifier: workspace:*
        version: link:../semantic-objects
      drizzle-orm:
        specifier: ^0.33.0
        version: 0.33.0(@electric-sql/pglite@0.4.4)(@types/react@19.2.14)(bun-types@1.3.13)(postgres@3.4.9)(react@19.2.5)
    devDependencies:
      '@electric-sql/pglite':
        specifier: ^0.4.1
        version: 0.4.4
      bun-types:
        specifier: ^1.3.13
        version: 1.3.13
      typescript:
        specifier: ~5.8.0
        version: 5.8.3

  core/semantic-objects:
    dependencies:
      drizzle-orm:
        specifier: ^0.33.0
        version: 0.33.0(@electric-sql/pglite@0.4.4)(@types/react@19.2.14)(bun-types@1.3.13)(postgres@3.4.9)(react@19.2.5)
      postgres:
        specifier: ^3.4.0
        version: 3.4.9
    devDependencies:
      '@electric-sql/pglite':
        specifier: ^0.4.1
        version: 0.4.4
      bun-types:
        specifier: ^1.3.13
        version: 1.3.13
      drizzle-kit:
        specifier: ^0.24.0
        version: 0.24.2
      typescript:
        specifier: ~5.8.0
        version: 5.8.3

  core/semantos-ir:
    devDependencies:
      typescript:
        specifier: ~5.8.0
        version: 5.8.3

  core/semantos-sir:
    dependencies:
      '@semantos/lexicon-core':
        specifier: workspace:*
        version: link:../lexicon-core
      '@semantos/scg-relations':
        specifier: workspace:*
        version: link:../scg-relations
      '@semantos/semantos-ir':
        specifier: workspace:*
        version: link:../semantos-ir
    devDependencies:
      typescript:
        specifier: ~5.8.0
        version: 5.8.3

  core/state:
    devDependencies:
      bun-types:
        specifier: ^1.3.13
        version: 1.3.13
      typescript:
        specifier: ~5.8.0
        version: 5.8.3

  docs/canon/render:
    dependencies:
      yaml:
        specifier: ^2.6.0
        version: 2.9.0
    devDependencies:
      bun-types:
        specifier: ^1.3.13
        version: 1.3.13
      typescript:
        specifier: ~5.8.0
        version: 5.8.3

  packages/calendar:
    dependencies:
      '@plexus/contracts':
        specifier: workspace:*
        version: link:../../core/plexus-contracts
      '@semantos/intent':
        specifier: workspace:*
        version: link:../../runtime/intent
      '@semantos/semantic-objects':
        specifier: workspace:*
        version: link:../../core/semantic-objects
      '@semantos/semantos-sir':
        specifier: workspace:*
        version: link:../../core/semantos-sir
      drizzle-orm:
        specifier: ^0.33.0
        version: 0.33.0(@electric-sql/pglite@0.4.4)(@types/react@19.2.14)(bun-types@1.3.13)(postgres@3.4.9)(react@19.2.5)
      postgres:
        specifier: ^3.4.0
        version: 3.4.9
    devDependencies:
      '@electric-sql/pglite':
        specifier: ^0.4.1
        version: 0.4.4
      '@types/react':
        specifier: ^19
        version: 19.2.14
      bun-types:
        specifier: ^1.3.13
        version: 1.3.13
      drizzle-kit:
        specifier: ^0.24.0
        version: 0.24.2
      fast-check:
        specifier: ^3.23.0
        version: 3.23.2
      react:
        specifier: ^19.0.0
        version: 19.2.5
      typescript:
        specifier: ~5.8.0
        version: 5.8.3

  packages/cell-relay: {}

  packages/content-store-local-fs:
    dependencies:
      '@semantos/protocol-types':
        specifier: workspace:*
        version: link:../../core/protocol-types
    devDependencies:
      '@types/node':
        specifier: ^20.0.0
        version: 20.19.39
      typescript:
        specifier: ~5.8.0
        version: 5.8.3

  packages/content-store-uhrp-http:
    dependencies:
      '@bsv/sdk':
        specifier: ^2.0.0
        version: 2.0.13
      '@semantos/protocol-types':
        specifier: workspace:*
        version: link:../../core/protocol-types
    devDependencies:
      '@types/node':
        specifier: ^20.0.0
        version: 20.19.39
      typescript:
        specifier: ~5.8.0
        version: 5.8.3

  packages/content-store-usb-cdn:
    dependencies:
      '@bsv/sdk':
        specifier: ^2.0.0
        version: 2.0.13
      '@semantos/protocol-types':
        specifier: workspace:*
        version: link:../../core/protocol-types
    devDependencies:
      '@types/node':
        specifier: ^20.0.0
        version: 20.19.39
      typescript:
        specifier: ~5.8.0
        version: 5.8.3

  packages/extraction:
    dependencies:
      '@anthropic-ai/sdk':
        specifier: ^0.37.0
        version: 0.37.0
      '@semantos/intent':
        specifier: workspace:*
        version: link:../../runtime/intent
      '@semantos/protocol-types':
        specifier: workspace:*
        version: link:../../core/protocol-types
      '@semantos/runtime-services':
        specifier: workspace:*
        version: link:../../runtime/services
      '@semantos/semantos-sir':
        specifier: workspace:*
        version: link:../../core/semantos-sir
      '@semantos/shell':
        specifier: workspace:*
        version: link:../../runtime/shell
    devDependencies:
      typescript:
        specifier: ^5.3.3
        version: 5.8.3

  packages/game-sdk:
    dependencies:
      '@semantos/cell-ops':
        specifier: workspace:*
        version: link:../../core/cell-ops
      '@semantos/plexus-schema-registry':
        specifier: workspace:*
        version: link:../../core/plexus-schema-registry
      '@semantos/protocol-types':
        specifier: workspace:*
        version: link:../../core/protocol-types
      '@semantos/state':
        specifier: workspace:*
        version: link:../../core/state
      bitecs:
        specifier: ^0.4.0
        version: 0.4.0

  packages/games:
    dependencies:
      '@semantos/cell-engine':
        specifier: workspace:*
        version: link:../../core/cell-engine
      '@semantos/game-sdk':
        specifier: workspace:*
        version: link:../game-sdk
      '@semantos/policy-runtime':
        specifier: workspace:*
        version: link:../policy-runtime
      '@semantos/protocol-types':
        specifier: workspace:*
        version: link:../../core/protocol-types
      '@semantos/runtime-services':
        specifier: workspace:*
        version: link:../../runtime/services
      '@semantos/shell':
        specifier: workspace:*
        version: link:../../runtime/shell
      '@semantos/state':
        specifier: workspace:*
        version: link:../../core/state
      rot-js:
        specifier: ^2.2.0
        version: 2.2.1

  packages/navigator:
    dependencies:
      '@semantos/core':
        specifier: file:../../
        version: file:(@bsv/sdk@2.0.13)

  packages/pask-ga: {}

  packages/policy-runtime:
    dependencies:
      '@bsv/sdk':
        specifier: ^2.0.0
        version: 2.0.13
      '@semantos/cell-engine':
        specifier: workspace:*
        version: link:../../core/cell-engine
      '@semantos/protocol-types':
        specifier: workspace:*
        version: link:../../core/protocol-types

  packages/re-desk-stub:
    dependencies:
      '@semantos/oddjobz':
        specifier: workspace:*
        version: link:../../cartridges/oddjobz/brain
    devDependencies:
      bun-types:
        specifier: ^1.3.13
        version: 1.3.13
      typescript:
        specifier: ~5.8.0
        version: 5.8.3

  runtime/hrr-library:
    dependencies:
      '@semantos/hrr':
        specifier: workspace:*
        version: link:../../core/hrr
      '@semantos/semantos-ir':
        specifier: workspace:*
        version: link:../../core/semantos-ir
    devDependencies:
      typescript:
        specifier: ~5.8.0
        version: 5.8.3

  runtime/intent:
    dependencies:
      '@semantos/hrr':
        specifier: workspace:*
        version: link:../../core/hrr
      '@semantos/protocol-types':
        specifier: workspace:*
        version: link:../../core/protocol-types
      '@semantos/scg-relations':
        specifier: workspace:*
        version: link:../../core/scg-relations
      '@semantos/semantos-sir':
        specifier: workspace:*
        version: link:../../core/semantos-sir
    devDependencies:
      typescript:
        specifier: ~5.8.0
        version: 5.8.3

  runtime/legacy-ingest:
    dependencies:
      '@semantos/protocol-types':
        specifier: workspace:*
        version: link:../../core/protocol-types
      '@semantos/runtime-services':
        specifier: workspace:*
        version: link:../services
      sharp:
        specifier: ^0.34.0
        version: 0.34.5
    devDependencies:
      bun-types:
        specifier: ^1.3.13
        version: 1.3.13
      typescript:
        specifier: ~5.8.0
        version: 5.8.3

  runtime/node:
    dependencies:
      '@semantos/peer-locator':
        specifier: workspace:*
        version: link:../peer-locator
      '@semantos/protocol-types':
        specifier: workspace:*
        version: link:../../core/protocol-types
      '@semantos/session-protocol':
        specifier: workspace:*
        version: link:../session-protocol
      '@semantos/shell':
        specifier: workspace:*
        version: link:../shell
      '@semantos/ws-node-adapter':
        specifier: workspace:*
        version: link:../ws-node-adapter
    devDependencies:
      typescript:
        specifier: ~5.8.0
        version: 5.8.3

  runtime/peer-locator:
    devDependencies:
      typescript:
        specifier: ~5.8.0
        version: 5.8.3

  runtime/services:
    dependencies:
      '@plexus/contracts':
        specifier: workspace:*
        version: link:../../core/plexus-contracts
      '@plexus/vendor-sdk':
        specifier: workspace:*
        version: link:../../core/plexus-vendor-sdk
      '@semantos/pask':
        specifier: workspace:*
        version: link:../../core/pask/bindings/ts
      '@semantos/protocol-types':
        specifier: workspace:*
        version: link:../../core/protocol-types
      '@semantos/semantos-sir':
        specifier: workspace:*
        version: link:../../core/semantos-sir
      '@semantos/state':
        specifier: workspace:*
        version: link:../../core/state
    devDependencies:
      bun-types:
        specifier: ^1.3.13
        version: 1.3.13
      typescript:
        specifier: ~5.8.0
        version: 5.8.3

  runtime/session-protocol:
    dependencies:
      '@semantos/identity-ports':
        specifier: workspace:*
        version: link:../../core/identity-ports
      '@semantos/protocol-types':
        specifier: workspace:*
        version: link:../../core/protocol-types
    devDependencies:
      '@bsv/sdk':
        specifier: ^2.0.0
        version: 2.0.13
      bun-types:
        specifier: ^1.3.13
        version: 1.3.13
      typescript:
        specifier: ~5.8.0
        version: 5.8.3

  runtime/shell:
    dependencies:
      '@semantos/cell-engine':
        specifier: workspace:*
        version: link:../../core/cell-engine
      '@semantos/intent':
        specifier: workspace:*
        version: link:../intent
      '@semantos/runtime-services':
        specifier: workspace:*
        version: link:../services
      '@semantos/semantos-ir':
        specifier: workspace:*
        version: link:../../core/semantos-ir
      '@semantos/session-protocol':
        specifier: workspace:*
        version: link:../session-protocol
      '@semantos/state':
        specifier: workspace:*
        version: link:../../core/state
    devDependencies:
      bun-types:
        specifier: ^1.3.13
        version: 1.3.13
      typescript:
        specifier: ^5.3.3
        version: 5.8.3

  runtime/verifier-sidecar:
    dependencies:
      '@plexus/contracts':
        specifier: workspace:*
        version: link:../../core/plexus-contracts
      '@semantos/protocol-types':
        specifier: workspace:*
        version: link:../../core/protocol-types
    devDependencies:
      '@bsv/sdk':
        specifier: ^2.0.0
        version: 2.0.13
      bun-types:
        specifier: ^1.3.13
        version: 1.3.13
      typescript:
        specifier: ~5.8.0
        version: 5.8.3

  runtime/world-beam: {}

  runtime/ws-node-adapter:
    dependencies:
      '@semantos/peer-locator':
        specifier: workspace:*
        version: link:../peer-locator
      '@semantos/protocol-types':
        specifier: workspace:*
        version: link:../../core/protocol-types
      '@semantos/session-protocol':
        specifier: workspace:*
        version: link:../session-protocol
      cbor-x:
        specifier: ^1.6.0
        version: 1.6.4
    devDependencies:
      typescript:
        specifier: ~5.8.0
        version: 5.8.3

packages:

  '@adobe/css-tools@4.4.4':
    resolution: {integrity: sha512-Elp+iwUx5rN5+Y8xLt5/GRoG20WGoDCQ/1Fb+1LiGtvwbDavuSk0jhD/eZdckHAuzcDzccnkv+rEjyWfRx18gg==}

  '@alloc/quick-lru@5.2.0':
    resolution: {integrity: sha512-UrcABB+4bUrFABwbluTIBErXwvbsU/V7TZWfmbgJfbkwiBuziS9gxdODUyuiecfdGQ85jglMW6juS3+z5TsKLw==}
    engines: {node: '>=10'}

  '@anthropic-ai/sdk@0.37.0':
    resolution: {integrity: sha512-tHjX2YbkUBwEgg0JZU3EFSSAQPoK4qQR/NFYa8Vtzd5UAyXzZksCw2In69Rml4R/TyHPBfRYaLK35XiOe33pjw==}

  '@anthropic-ai/sdk@0.39.0':
    resolution: {integrity: sha512-eMyDIPRZbt1CCLErRCi3exlAvNkBtRe+kW5vvJyef93PmNr/clstYgHhtvmkxN82nlKgzyGPCyGxrm0JQ1ZIdg==}

  '@anthropic-ai/sdk@0.99.0':
    resolution: {integrity: sha512-vdicFA9YjtvgpG8rxp39hqW4oxpkdRGPTq0QEts5TZhr2GkLozDduK/GiXrLQ7PzrKYBtIkQFdRW+QBjzlsABg==}
    hasBin: true
    peerDependencies:
      zod: ^3.25.0 || ^4.0.0
    peerDependenciesMeta:
      zod:
        optional: true

  '@asamuzakjp/css-color@3.2.0':
    resolution: {integrity: sha512-K1A6z8tS3XsmCMM86xoWdn7Fkdn9m6RSVtocUrJYIwZnFVkng/PvkEoWtOWmP+Scc6saYWHWZYbndEEXxl24jw==}

  '@babel/code-frame@7.29.0':
    resolution: {integrity: sha512-9NhCeYjq9+3uxgdtp20LSiJXJvN0FeCtNGpJxuMFZ1Kv3cWUNb6DOhJwUvcVCzKGR66cw4njwM6hrJLqgOwbcw==}
    engines: {node: '>=6.9.0'}

  '@babel/compat-data@7.29.0':
    resolution: {integrity: sha512-T1NCJqT/j9+cn8fvkt7jtwbLBfLC/1y1c7NtCeXFRgzGTsafi68MRv8yzkYSapBnFA6L3U2VSc02ciDzoAJhJg==}
    engines: {node: '>=6.9.0'}

  '@babel/core@7.29.0':
    resolution: {integrity: sha512-CGOfOJqWjg2qW/Mb6zNsDm+u5vFQ8DxXfbM09z69p5Z6+mE1ikP2jUXw+j42Pf1XTYED2Rni5f95npYeuwMDQA==}
    engines: {node: '>=6.9.0'}

  '@babel/generator@7.29.1':
    resolution: {integrity: sha512-qsaF+9Qcm2Qv8SRIMMscAvG4O3lJ0F1GuMo5HR/Bp02LopNgnZBC/EkbevHFeGs4ls/oPz9v+Bsmzbkbe+0dUw==}
    engines: {node: '>=6.9.0'}

  '@babel/helper-compilation-targets@7.28.6':
    resolution: {integrity: sha512-JYtls3hqi15fcx5GaSNL7SCTJ2MNmjrkHXg4FSpOA/grxK8KwyZ5bubHsCq8FXCkua6xhuaaBit+3b7+VZRfcA==}
    engines: {node: '>=6.9.0'}

  '@babel/helper-globals@7.28.0':
    resolution: {integrity: sha512-+W6cISkXFa1jXsDEdYA8HeevQT/FULhxzR99pxphltZcVaugps53THCeiWA8SguxxpSp3gKPiuYfSWopkLQ4hw==}
    engines: {node: '>=6.9.0'}

  '@babel/helper-module-imports@7.28.6':
    resolution: {integrity: sha512-l5XkZK7r7wa9LucGw9LwZyyCUscb4x37JWTPz7swwFE/0FMQAGpiWUZn8u9DzkSBWEcK25jmvubfpw2dnAMdbw==}
    engines: {node: '>=6.9.0'}

  '@babel/helper-module-transforms@7.28.6':
    resolution: {integrity: sha512-67oXFAYr2cDLDVGLXTEABjdBJZ6drElUSI7WKp70NrpyISso3plG9SAGEF6y7zbha/wOzUByWWTJvEDVNIUGcA==}
    engines: {node: '>=6.9.0'}
    peerDependencies:
      '@babel/core': ^7.0.0

  '@babel/helper-plugin-utils@7.28.6':
    resolution: {integrity: sha512-S9gzZ/bz83GRysI7gAD4wPT/AI3uCnY+9xn+Mx/KPs2JwHJIz1W8PZkg2cqyt3RNOBM8ejcXhV6y8Og7ly/Dug==}
    engines: {node: '>=6.9.0'}

  '@babel/helper-string-parser@7.27.1':
    resolution: {integrity: sha512-qMlSxKbpRlAridDExk92nSobyDdpPijUq2DW6oDnUqd0iOGxmQjyqhMIihI9+zv4LPyZdRje2cavWPbCbWm3eA==}
    engines: {node: '>=6.9.0'}

  '@babel/helper-validator-identifier@7.28.5':
    resolution: {integrity: sha512-qSs4ifwzKJSV39ucNjsvc6WVHs6b7S03sOh2OcHF9UHfVPqWWALUsNUVzhSBiItjRZoLHx7nIarVjqKVusUZ1Q==}
    engines: {node: '>=6.9.0'}

  '@babel/helper-validator-option@7.27.1':
    resolution: {integrity: sha512-YvjJow9FxbhFFKDSuFnVCe2WxXk1zWc22fFePVNEaWJEu8IrZVlda6N0uHwzZrUM1il7NC9Mlp4MaJYbYd9JSg==}
    engines: {node: '>=6.9.0'}

  '@babel/helpers@7.29.2':
    resolution: {integrity: sha512-HoGuUs4sCZNezVEKdVcwqmZN8GoHirLUcLaYVNBK2J0DadGtdcqgr3BCbvH8+XUo4NGjNl3VOtSjEKNzqfFgKw==}
    engines: {node: '>=6.9.0'}

  '@babel/parser@7.29.2':
    resolution: {integrity: sha512-4GgRzy/+fsBa72/RZVJmGKPmZu9Byn8o4MoLpmNe1m8ZfYnz5emHLQz3U4gLud6Zwl0RZIcgiLD7Uq7ySFuDLA==}
    engines: {node: '>=6.0.0'}
    hasBin: true

  '@babel/plugin-transform-react-jsx-self@7.27.1':
    resolution: {integrity: sha512-6UzkCs+ejGdZ5mFFC/OCUrv028ab2fp1znZmCZjAOBKiBK2jXD1O+BPSfX8X2qjJ75fZBMSnQn3Rq2mrBJK2mw==}
    engines: {node: '>=6.9.0'}
    peerDependencies:
      '@babel/core': ^7.0.0-0

  '@babel/plugin-transform-react-jsx-source@7.27.1':
    resolution: {integrity: sha512-zbwoTsBruTeKB9hSq73ha66iFeJHuaFkUbwvqElnygoNbj/jHRsSeokowZFN3CZ64IvEqcmmkVe89OPXc7ldAw==}
    engines: {node: '>=6.9.0'}
    peerDependencies:
      '@babel/core': ^7.0.0-0

  '@babel/runtime@7.29.2':
    resolution: {integrity: sha512-JiDShH45zKHWyGe4ZNVRrCjBz8Nh9TMmZG1kh4QTK8hCBTWBi8Da+i7s1fJw7/lYpM4ccepSNfqzZ/QvABBi5g==}
    engines: {node: '>=6.9.0'}

  '@babel/template@7.28.6':
    resolution: {integrity: sha512-YA6Ma2KsCdGb+WC6UpBVFJGXL58MDA6oyONbjyF/+5sBgxY/dwkhLogbMT2GXXyU84/IhRw/2D1Os1B/giz+BQ==}
    engines: {node: '>=6.9.0'}

  '@babel/traverse@7.29.0':
    resolution: {integrity: sha512-4HPiQr0X7+waHfyXPZpWPfWL/J7dcN1mx9gL6WdQVMbPnF3+ZhSMs8tCxN7oHddJE9fhNE7+lxdnlyemKfJRuA==}
    engines: {node: '>=6.9.0'}

  '@babel/types@7.29.0':
    resolution: {integrity: sha512-LwdZHpScM4Qz8Xw2iKSzS+cfglZzJGvofQICy7W7v4caru4EaAmyUuO6BGrbyQ2mYV11W0U8j5mBhd14dd3B0A==}
    engines: {node: '>=6.9.0'}

  '@bsv/sdk@1.10.4':
    resolution: {integrity: sha512-NuEXWwtuZ3WbER9wLtm33QCfhVwLyTyAzGholOeHo1imNDLLe7d2HADmf8hlSqAkNud3Y03S2poRc6aJMRWDrA==}

  '@bsv/sdk@2.0.13':
    resolution: {integrity: sha512-VV25sV6oB1Piu7tTEMta+B29IRcq7Xpj1ohuk8RZRT656onop1YbA3oTnYf6stleWnbvsZeOciwH7Xppvs1QWw==}

  '@cbor-extract/cbor-extract-darwin-arm64@2.2.2':
    resolution: {integrity: sha512-ZKZ/F8US7JR92J4DMct6cLW/Y66o2K576+zjlEN/MevH70bFIsB10wkZEQPLzl2oNh2SMGy55xpJ9JoBRl5DOA==}
    cpu: [arm64]
    os: [darwin]

  '@cbor-extract/cbor-extract-darwin-x64@2.2.2':
    resolution: {integrity: sha512-32b1mgc+P61Js+KW9VZv/c+xRw5EfmOcPx990JbCBSkYJFY0l25VinvyyWfl+3KjibQmAcYwmyzKF9J4DyKP/Q==}
    cpu: [x64]
    os: [darwin]

  '@cbor-extract/cbor-extract-linux-arm64@2.2.2':
    resolution: {integrity: sha512-wfqgzqCAy/Vn8i6WVIh7qZd0DdBFaWBjPdB6ma+Wihcjv0gHqD/mw3ouVv7kbbUNrab6dKEx/w3xQZEdeXIlzg==}
    cpu: [arm64]
    os: [linux]

  '@cbor-extract/cbor-extract-linux-arm@2.2.2':
    resolution: {integrity: sha512-tNg0za41TpQfkhWjptD+0gSD2fggMiDCSacuIeELyb2xZhr7PrhPe5h66Jc67B/5dmpIhI2QOUtv4SBsricyYQ==}
    cpu: [arm]
    os: [linux]

  '@cbor-extract/cbor-extract-linux-x64@2.2.2':
    resolution: {integrity: sha512-rpiLnVEsqtPJ+mXTdx1rfz4RtUGYIUg2rUAZgd1KjiC1SehYUSkJN7Yh+aVfSjvCGtVP0/bfkQkXpPXKbmSUaA==}
    cpu: [x64]
    os: [linux]

  '@cbor-extract/cbor-extract-win32-x64@2.2.2':
    resolution: {integrity: sha512-dI+9P7cfWxkTQ+oE+7Aa6onEn92PHgfWXZivjNheCRmTBDBf2fx6RyTi0cmgpYLnD1KLZK9ZYrMxaPZ4oiXhGA==}
    cpu: [x64]
    os: [win32]

  '@changesets/apply-release-plan@7.1.1':
    resolution: {integrity: sha512-9qPCm/rLx/xoOFXIHGB229+4GOL76S4MC+7tyOuTsR6+1jYlfFDQORdvwR5hDA6y4FL2BPt3qpbcQIS+dW85LA==}

  '@changesets/assemble-release-plan@6.0.10':
    resolution: {integrity: sha512-rSDcqdJ9KbVyjpBIuCidhvZNIiVt1XaIYp73ycVQRIA5n/j6wQaEk0ChRLMUQ1vkxZe51PTQ9OIhbg6HQMW45A==}

  '@changesets/changelog-git@0.2.1':
    resolution: {integrity: sha512-x/xEleCFLH28c3bQeQIyeZf8lFXyDFVn1SgcBiR2Tw/r4IAWlk1fzxCEZ6NxQAjF2Nwtczoen3OA2qR+UawQ8Q==}

  '@changesets/changelog-github@0.6.0':
    resolution: {integrity: sha512-wA2/y4hR/A1K411cCT75rz0d46Iezxp1WYRFoFJDIUpkQ6oDBAIUiU7BZkDCmYgz0NBl94X1lgcZO+mHoiHnFg==}

  '@changesets/cli@2.31.0':
    resolution: {integrity: sha512-AhI4enNTgHu2IZr6K4WZyf0EPch4XVMn1yOMFmCD9gsfBGqMYaHXls5HyDv6/CL5axVQABz68eG30eCtbr2wFg==}
    hasBin: true

  '@changesets/config@3.1.4':
    resolution: {integrity: sha512-pf0bvD/v6WI2cRlZ6hzpjtZdSlXDXMAJ+Iz7xfFzV4ZxJ8OGGAON+1qYc99ZPrijnt4xp3VGG7eNvAOGS24V1Q==}

  '@changesets/errors@0.2.0':
    resolution: {integrity: sha512-6BLOQUscTpZeGljvyQXlWOItQyU71kCdGz7Pi8H8zdw6BI0g3m43iL4xKUVPWtG+qrrL9DTjpdn8eYuCQSRpow==}

  '@changesets/get-dependents-graph@2.1.4':
    resolution: {integrity: sha512-ZsS00x6WvmHq3sQv8oCMwL0f/z3wbXCVuSVTJwCnnmbC/iBdNJGFx1EcbMG4PC6sXRyH69liM4A2WKXzn/kRPg==}

  '@changesets/get-github-info@0.8.0':
    resolution: {integrity: sha512-cRnC+xdF0JIik7coko3iUP9qbnfi1iJQ3sAa6dE+Tx3+ET8bjFEm63PA4WEohgjYcmsOikPHWzPsMWWiZmntOQ==}

  '@changesets/get-release-plan@4.0.16':
    resolution: {integrity: sha512-2K5Om6CrMPm45rtvckfzWo7e9jOVCKLCnXia5eUPaURH7/LWzri7pK1TycdzAuAtehLkW7VPbWLCSExTHmiI6g==}

  '@changesets/get-version-range-type@0.4.0':
    resolution: {integrity: sha512-hwawtob9DryoGTpixy1D3ZXbGgJu1Rhr+ySH2PvTLHvkZuQ7sRT4oQwMh0hbqZH1weAooedEjRsbrWcGLCeyVQ==}

  '@changesets/git@3.0.4':
    resolution: {integrity: sha512-BXANzRFkX+XcC1q/d27NKvlJ1yf7PSAgi8JG6dt8EfbHFHi4neau7mufcSca5zRhwOL8j9s6EqsxmT+s+/E6Sw==}

  '@changesets/logger@0.1.1':
    resolution: {integrity: sha512-OQtR36ZlnuTxKqoW4Sv6x5YIhOmClRd5pWsjZsddYxpWs517R0HkyiefQPIytCVh4ZcC5x9XaG8KTdd5iRQUfg==}

  '@changesets/parse@0.4.3':
    resolution: {integrity: sha512-ZDmNc53+dXdWEv7fqIUSgRQOLYoUom5Z40gmLgmATmYR9NbL6FJJHwakcCpzaeCy+1D0m0n7mT4jj2B/MQPl7A==}

  '@changesets/pre@2.0.2':
    resolution: {integrity: sha512-HaL/gEyFVvkf9KFg6484wR9s0qjAXlZ8qWPDkTyKF6+zqjBe/I2mygg3MbpZ++hdi0ToqNUF8cjj7fBy0dg8Ug==}

  '@changesets/read@0.6.7':
    resolution: {integrity: sha512-D1G4AUYGrBEk8vj8MGwf75k9GpN6XL3wg8i42P2jZZwFLXnlr2Pn7r9yuQNbaMCarP7ZQWNJbV6XLeysAIMhTA==}

  '@changesets/should-skip-package@0.1.2':
    resolution: {integrity: sha512-qAK/WrqWLNCP22UDdBTMPH5f41elVDlsNyat180A33dWxuUDyNpg6fPi/FyTZwRriVjg0L8gnjJn2F9XAoF0qw==}

  '@changesets/types@4.1.0':
    resolution: {integrity: sha512-LDQvVDv5Kb50ny2s25Fhm3d9QSZimsoUGBsUioj6MC3qbMUCuC8GPIvk/M6IvXx3lYhAs0lwWUQLb+VIEUCECw==}

  '@changesets/types@6.1.0':
    resolution: {integrity: sha512-rKQcJ+o1nKNgeoYRHKOS07tAMNd3YSN0uHaJOZYjBAgxfV7TUE7JE+z4BzZdQwb5hKaYbayKN5KrYV7ODb2rAA==}

  '@changesets/write@0.4.0':
    resolution: {integrity: sha512-CdTLvIOPiCNuH71pyDu3rA+Q0n65cmAbXnwWH84rKGiFumFzkmHNT8KHTMEchcxN+Kl8I54xGUhJ7l3E7X396Q==}

  '@codemirror/autocomplete@6.20.1':
    resolution: {integrity: sha512-1cvg3Vz1dSSToCNlJfRA2WSI4ht3K+WplO0UMOgmUYPivCyy2oueZY6Lx7M9wThm7SDUBViRmuT+OG/i8+ON9A==}

  '@codemirror/commands@6.10.3':
    resolution: {integrity: sha512-JFRiqhKu+bvSkDLI+rUhJwSxQxYb759W5GBezE8Uc8mHLqC9aV/9aTC7yJSqCtB3F00pylrLCwnyS91Ap5ej4Q==}

  '@codemirror/lang-css@6.3.1':
    resolution: {integrity: sha512-kr5fwBGiGtmz6l0LSJIbno9QrifNMUusivHbnA1H6Dmqy4HZFte3UAICix1VuKo0lMPKQr2rqB+0BkKi/S3Ejg==}

  '@codemirror/lang-html@6.4.11':
    resolution: {integrity: sha512-9NsXp7Nwp891pQchI7gPdTwBuSuT3K65NGTHWHNJ55HjYcHLllr0rbIZNdOzas9ztc1EUVBlHou85FFZS4BNnw==}

  '@codemirror/lang-javascript@6.2.5':
    resolution: {integrity: sha512-zD4e5mS+50htS7F+TYjBPsiIFGanfVqg4HyUz6WNFikgOPf2BgKlx+TQedI1w6n/IqRBVBbBWmGFdLB/7uxO4A==}

  '@codemirror/lang-markdown@6.5.0':
    resolution: {integrity: sha512-0K40bZ35jpHya6FriukbgaleaqzBLZfOh7HuzqbMxBXkbYMJDxfF39c23xOgxFezR+3G+tR2/Mup+Xk865OMvw==}

  '@codemirror/language@6.12.3':
    resolution: {integrity: sha512-QwCZW6Tt1siP37Jet9Tb02Zs81TQt6qQrZR2H+eGMcFsL1zMrk2/b9CLC7/9ieP1fjIUMgviLWMmgiHoJrj+ZA==}

  '@codemirror/lint@6.9.5':
    resolution: {integrity: sha512-GElsbU9G7QT9xXhpUg1zWGmftA/7jamh+7+ydKRuT0ORpWS3wOSP0yT1FOlIZa7mIJjpVPipErsyvVqB9cfTFA==}

  '@codemirror/state@6.6.0':
    resolution: {integrity: sha512-4nbvra5R5EtiCzr9BTHiTLc+MLXK2QGiAVYMyi8PkQd3SR+6ixar/Q/01Fa21TBIDOZXgeWV4WppsQolSreAPQ==}

  '@codemirror/theme-one-dark@6.1.3':
    resolution: {integrity: sha512-NzBdIvEJmx6fjeremiGp3t/okrLPYT0d9orIc7AFun8oZcRk58aejkqhv6spnz4MLAevrKNPMQYXEWMg4s+sKA==}

  '@codemirror/view@6.41.1':
    resolution: {integrity: sha512-ToDnWKbBnke+ZLrP6vgTTDScGi5H37YYuZGniQaBzxMVdtCxMrslsmtnOvbPZk4RX9bvkQqnWR/WS/35tJA0qg==}

  '@csstools/color-helpers@5.1.0':
    resolution: {integrity: sha512-S11EXWJyy0Mz5SYvRmY8nJYTFFd1LCNV+7cXyAgQtOOuzb4EsgfqDufL+9esx72/eLhsRdGZwaldu/h+E4t4BA==}
    engines: {node: '>=18'}

  '@csstools/css-calc@2.1.4':
    resolution: {integrity: sha512-3N8oaj+0juUw/1H3YwmDDJXCgTB1gKU6Hc/bB502u9zR0q2vd786XJH9QfrKIEgFlZmhZiq6epXl4rHqhzsIgQ==}
    engines: {node: '>=18'}
    peerDependencies:
      '@csstools/css-parser-algorithms': ^3.0.5
      '@csstools/css-tokenizer': ^3.0.4

  '@csstools/css-color-parser@3.1.0':
    resolution: {integrity: sha512-nbtKwh3a6xNVIp/VRuXV64yTKnb1IjTAEEh3irzS+HkKjAOYLTGNb9pmVNntZ8iVBHcWDA2Dof0QtPgFI1BaTA==}
    engines: {node: '>=18'}
    peerDependencies:
      '@csstools/css-parser-algorithms': ^3.0.5
      '@csstools/css-tokenizer': ^3.0.4

  '@csstools/css-parser-algorithms@3.0.5':
    resolution: {integrity: sha512-DaDeUkXZKjdGhgYaHNJTV9pV7Y9B3b644jCLs9Upc3VeNGg6LWARAT6O+Q+/COo+2gg/bM5rhpMAtf70WqfBdQ==}
    engines: {node: '>=18'}
    peerDependencies:
      '@csstools/css-tokenizer': ^3.0.4

  '@csstools/css-tokenizer@3.0.4':
    resolution: {integrity: sha512-Vd/9EVDiu6PPJt9yAh6roZP6El1xHrdvIVGjyBsHR0RYwNHgL7FJPyIIW4fANJNG6FtyZfvlRPpFI4ZM/lubvw==}
    engines: {node: '>=18'}

  '@drizzle-team/brocli@0.10.2':
    resolution: {integrity: sha512-z33Il7l5dKjUgGULTqBsQBQwckHh5AbIuxhdsIxDDiZAzBOrZO6q9ogcWC65kU382AfynTfgNumVcNIjuIua6w==}

  '@electric-sql/pglite@0.4.4':
    resolution: {integrity: sha512-g/6CWAJ4XOkObWCWAQ2IReZD8VvsDy3poRHSKvpRR2F96F8WJ3HVbjpso3gN7l0q6QPPgvxSSpl/qo5k8a7mkQ==}

  '@emnapi/runtime@1.10.0':
    resolution: {integrity: sha512-ewvYlk86xUoGI0zQRNq/mC+16R1QeDlKQy21Ki3oSYXNgLb45GV1P6A0M+/s6nyCuNDqe5VpaY84BzXGwVbwFA==}

  '@esbuild-kit/core-utils@3.3.2':
    resolution: {integrity: sha512-sPRAnw9CdSsRmEtnsl2WXWdyquogVpB3yZ3dgwJfe8zrOzTsV7cJvmwrKVa+0ma5BoiGJ+BoqkMvawbayKUsqQ==}
    deprecated: 'Merged into tsx: https://tsx.is'

  '@esbuild-kit/esm-loader@2.6.5':
    resolution: {integrity: sha512-FxEMIkJKnodyA1OaCUoEvbYRkoZlLZ4d/eXFu9Fh8CbBBgP5EmZxrfTRyN0qpXZ4vOvqnE5YdRdcrmUUXuU+dA==}
    deprecated: 'Merged into tsx: https://tsx.is'

  '@esbuild/aix-ppc64@0.19.12':
    resolution: {integrity: sha512-bmoCYyWdEL3wDQIVbcyzRyeKLgk2WtWLTWz1ZIAZF/EGbNOwSA6ew3PftJ1PqMiOOGu0OyFMzG53L0zqIpPeNA==}
    engines: {node: '>=12'}
    cpu: [ppc64]
    os: [aix]

  '@esbuild/aix-ppc64@0.21.5':
    resolution: {integrity: sha512-1SDgH6ZSPTlggy1yI6+Dbkiz8xzpHJEVAlF/AM1tHPLsf5STom9rwtjE4hKAF20FfXXNTFqEYXyJNWh1GiZedQ==}
    engines: {node: '>=12'}
    cpu: [ppc64]
    os: [aix]

  '@esbuild/aix-ppc64@0.25.12':
    resolution: {integrity: sha512-Hhmwd6CInZ3dwpuGTF8fJG6yoWmsToE+vYgD4nytZVxcu1ulHpUQRAB1UJ8+N1Am3Mz4+xOByoQoSZf4D+CpkA==}
    engines: {node: '>=18'}
    cpu: [ppc64]
    os: [aix]

  '@esbuild/aix-ppc64@0.27.7':
    resolution: {integrity: sha512-EKX3Qwmhz1eMdEJokhALr0YiD0lhQNwDqkPYyPhiSwKrh7/4KRjQc04sZ8db+5DVVnZ1LmbNDI1uAMPEUBnQPg==}
    engines: {node: '>=18'}
    cpu: [ppc64]
    os: [aix]

  '@esbuild/android-arm64@0.18.20':
    resolution: {integrity: sha512-Nz4rJcchGDtENV0eMKUNa6L12zz2zBDXuhj/Vjh18zGqB44Bi7MBMSXjgunJgjRhCmKOjnPuZp4Mb6OKqtMHLQ==}
    engines: {node: '>=12'}
    cpu: [arm64]
    os: [android]

  '@esbuild/android-arm64@0.19.12':
    resolution: {integrity: sha512-P0UVNGIienjZv3f5zq0DP3Nt2IE/3plFzuaS96vihvD0Hd6H/q4WXUGpCxD/E8YrSXfNyRPbpTq+T8ZQioSuPA==}
    engines: {node: '>=12'}
    cpu: [arm64]
    os: [android]

  '@esbuild/android-arm64@0.21.5':
    resolution: {integrity: sha512-c0uX9VAUBQ7dTDCjq+wdyGLowMdtR/GoC2U5IYk/7D1H1JYC0qseD7+11iMP2mRLN9RcCMRcjC4YMclCzGwS/A==}
    engines: {node: '>=12'}
    cpu: [arm64]
    os: [android]

  '@esbuild/android-arm64@0.25.12':
    resolution: {integrity: sha512-6AAmLG7zwD1Z159jCKPvAxZd4y/VTO0VkprYy+3N2FtJ8+BQWFXU+OxARIwA46c5tdD9SsKGZ/1ocqBS/gAKHg==}
    engines: {node: '>=18'}
    cpu: [arm64]
    os: [android]

  '@esbuild/android-arm64@0.27.7':
    resolution: {integrity: sha512-62dPZHpIXzvChfvfLJow3q5dDtiNMkwiRzPylSCfriLvZeq0a1bWChrGx/BbUbPwOrsWKMn8idSllklzBy+dgQ==}
    engines: {node: '>=18'}
    cpu: [arm64]
    os: [android]

  '@esbuild/android-arm@0.18.20':
    resolution: {integrity: sha512-fyi7TDI/ijKKNZTUJAQqiG5T7YjJXgnzkURqmGj13C6dCqckZBLdl4h7bkhHt/t0WP+zO9/zwroDvANaOqO5Sw==}
    engines: {node: '>=12'}
    cpu: [arm]
    os: [android]

  '@esbuild/android-arm@0.19.12':
    resolution: {integrity: sha512-qg/Lj1mu3CdQlDEEiWrlC4eaPZ1KztwGJ9B6J+/6G+/4ewxJg7gqj8eVYWvao1bXrqGiW2rsBZFSX3q2lcW05w==}
    engines: {node: '>=12'}
    cpu: [arm]
    os: [android]

  '@esbuild/android-arm@0.21.5':
    resolution: {integrity: sha512-vCPvzSjpPHEi1siZdlvAlsPxXl7WbOVUBBAowWug4rJHb68Ox8KualB+1ocNvT5fjv6wpkX6o/iEpbDrf68zcg==}
    engines: {node: '>=12'}
    cpu: [arm]
    os: [android]

  '@esbuild/android-arm@0.25.12':
    resolution: {integrity: sha512-VJ+sKvNA/GE7Ccacc9Cha7bpS8nyzVv0jdVgwNDaR4gDMC/2TTRc33Ip8qrNYUcpkOHUT5OZ0bUcNNVZQ9RLlg==}
    engines: {node: '>=18'}
    cpu: [arm]
    os: [android]

  '@esbuild/android-arm@0.27.7':
    resolution: {integrity: sha512-jbPXvB4Yj2yBV7HUfE2KHe4GJX51QplCN1pGbYjvsyCZbQmies29EoJbkEc+vYuU5o45AfQn37vZlyXy4YJ8RQ==}
    engines: {node: '>=18'}
    cpu: [arm]
    os: [android]

  '@esbuild/android-x64@0.18.20':
    resolution: {integrity: sha512-8GDdlePJA8D6zlZYJV/jnrRAi6rOiNaCC/JclcXpB+KIuvfBN4owLtgzY2bsxnx666XjJx2kDPUmnTtR8qKQUg==}
    engines: {node: '>=12'}
    cpu: [x64]
    os: [android]

  '@esbuild/android-x64@0.19.12':
    resolution: {integrity: sha512-3k7ZoUW6Q6YqhdhIaq/WZ7HwBpnFBlW905Fa4s4qWJyiNOgT1dOqDiVAQFwBH7gBRZr17gLrlFCRzF6jFh7Kew==}
    engines: {node: '>=12'}
    cpu: [x64]
    os: [android]

  '@esbuild/android-x64@0.21.5':
    resolution: {integrity: sha512-D7aPRUUNHRBwHxzxRvp856rjUHRFW1SdQATKXH2hqA0kAZb1hKmi02OpYRacl0TxIGz/ZmXWlbZgjwWYaCakTA==}
    engines: {node: '>=12'}
    cpu: [x64]
    os: [android]

  '@esbuild/android-x64@0.25.12':
    resolution: {integrity: sha512-5jbb+2hhDHx5phYR2By8GTWEzn6I9UqR11Kwf22iKbNpYrsmRB18aX/9ivc5cabcUiAT/wM+YIZ6SG9QO6a8kg==}
    engines: {node: '>=18'}
    cpu: [x64]
    os: [android]

  '@esbuild/android-x64@0.27.7':
    resolution: {integrity: sha512-x5VpMODneVDb70PYV2VQOmIUUiBtY3D3mPBG8NxVk5CogneYhkR7MmM3yR/uMdITLrC1ml/NV1rj4bMJuy9MCg==}
    engines: {node: '>=18'}
    cpu: [x64]
    os: [android]

  '@esbuild/darwin-arm64@0.18.20':
    resolution: {integrity: sha512-bxRHW5kHU38zS2lPTPOyuyTm+S+eobPUnTNkdJEfAddYgEcll4xkT8DB9d2008DtTbl7uJag2HuE5NZAZgnNEA==}
    engines: {node: '>=12'}
    cpu: [arm64]
    os: [darwin]

  '@esbuild/darwin-arm64@0.19.12':
    resolution: {integrity: sha512-B6IeSgZgtEzGC42jsI+YYu9Z3HKRxp8ZT3cqhvliEHovq8HSX2YX8lNocDn79gCKJXOSaEot9MVYky7AKjCs8g==}
    engines: {node: '>=12'}
    cpu: [arm64]
    os: [darwin]

  '@esbuild/darwin-arm64@0.21.5':
    resolution: {integrity: sha512-DwqXqZyuk5AiWWf3UfLiRDJ5EDd49zg6O9wclZ7kUMv2WRFr4HKjXp/5t8JZ11QbQfUS6/cRCKGwYhtNAY88kQ==}
    engines: {node: '>=12'}
    cpu: [arm64]
    os: [darwin]

  '@esbuild/darwin-arm64@0.25.12':
    resolution: {integrity: sha512-N3zl+lxHCifgIlcMUP5016ESkeQjLj/959RxxNYIthIg+CQHInujFuXeWbWMgnTo4cp5XVHqFPmpyu9J65C1Yg==}
    engines: {node: '>=18'}
    cpu: [arm64]
    os: [darwin]

  '@esbuild/darwin-arm64@0.27.7':
    resolution: {integrity: sha512-5lckdqeuBPlKUwvoCXIgI2D9/ABmPq3Rdp7IfL70393YgaASt7tbju3Ac+ePVi3KDH6N2RqePfHnXkaDtY9fkw==}
    engines: {node: '>=18'}
    cpu: [arm64]
    os: [darwin]

  '@esbuild/darwin-x64@0.18.20':
    resolution: {integrity: sha512-pc5gxlMDxzm513qPGbCbDukOdsGtKhfxD1zJKXjCCcU7ju50O7MeAZ8c4krSJcOIJGFR+qx21yMMVYwiQvyTyQ==}
    engines: {node: '>=12'}
    cpu: [x64]
    os: [darwin]

  '@esbuild/darwin-x64@0.19.12':
    resolution: {integrity: sha512-hKoVkKzFiToTgn+41qGhsUJXFlIjxI/jSYeZf3ugemDYZldIXIxhvwN6erJGlX4t5h417iFuheZ7l+YVn05N3A==}
    engines: {node: '>=12'}
    cpu: [x64]
    os: [darwin]

  '@esbuild/darwin-x64@0.21.5':
    resolution: {integrity: sha512-se/JjF8NlmKVG4kNIuyWMV/22ZaerB+qaSi5MdrXtd6R08kvs2qCN4C09miupktDitvh8jRFflwGFBQcxZRjbw==}
    engines: {node: '>=12'}
    cpu: [x64]
    os: [darwin]

  '@esbuild/darwin-x64@0.25.12':
    resolution: {integrity: sha512-HQ9ka4Kx21qHXwtlTUVbKJOAnmG1ipXhdWTmNXiPzPfWKpXqASVcWdnf2bnL73wgjNrFXAa3yYvBSd9pzfEIpA==}
    engines: {node: '>=18'}
    cpu: [x64]
    os: [darwin]

  '@esbuild/darwin-x64@0.27.7':
    resolution: {integrity: sha512-rYnXrKcXuT7Z+WL5K980jVFdvVKhCHhUwid+dDYQpH+qu+TefcomiMAJpIiC2EM3Rjtq0sO3StMV/+3w3MyyqQ==}
    engines: {node: '>=18'}
    cpu: [x64]
    os: [darwin]

  '@esbuild/freebsd-arm64@0.18.20':
    resolution: {integrity: sha512-yqDQHy4QHevpMAaxhhIwYPMv1NECwOvIpGCZkECn8w2WFHXjEwrBn3CeNIYsibZ/iZEUemj++M26W3cNR5h+Tw==}
    engines: {node: '>=12'}
    cpu: [arm64]
    os: [freebsd]

  '@esbuild/freebsd-arm64@0.19.12':
    resolution: {integrity: sha512-4aRvFIXmwAcDBw9AueDQ2YnGmz5L6obe5kmPT8Vd+/+x/JMVKCgdcRwH6APrbpNXsPz+K653Qg8HB/oXvXVukA==}
    engines: {node: '>=12'}
    cpu: [arm64]
    os: [freebsd]

  '@esbuild/freebsd-arm64@0.21.5':
    resolution: {integrity: sha512-5JcRxxRDUJLX8JXp/wcBCy3pENnCgBR9bN6JsY4OmhfUtIHe3ZW0mawA7+RDAcMLrMIZaf03NlQiX9DGyB8h4g==}
    engines: {node: '>=12'}
    cpu: [arm64]
    os: [freebsd]

  '@esbuild/freebsd-arm64@0.25.12':
    resolution: {integrity: sha512-gA0Bx759+7Jve03K1S0vkOu5Lg/85dou3EseOGUes8flVOGxbhDDh/iZaoek11Y8mtyKPGF3vP8XhnkDEAmzeg==}
    engines: {node: '>=18'}
    cpu: [arm64]
    os: [freebsd]

  '@esbuild/freebsd-arm64@0.27.7':
    resolution: {integrity: sha512-B48PqeCsEgOtzME2GbNM2roU29AMTuOIN91dsMO30t+Ydis3z/3Ngoj5hhnsOSSwNzS+6JppqWsuhTp6E82l2w==}
    engines: {node: '>=18'}
    cpu: [arm64]
    os: [freebsd]

  '@esbuild/freebsd-x64@0.18.20':
    resolution: {integrity: sha512-tgWRPPuQsd3RmBZwarGVHZQvtzfEBOreNuxEMKFcd5DaDn2PbBxfwLcj4+aenoh7ctXcbXmOQIn8HI6mCSw5MQ==}
    engines: {node: '>=12'}
    cpu: [x64]
    os: [freebsd]

  '@esbuild/freebsd-x64@0.19.12':
    resolution: {integrity: sha512-EYoXZ4d8xtBoVN7CEwWY2IN4ho76xjYXqSXMNccFSx2lgqOG/1TBPW0yPx1bJZk94qu3tX0fycJeeQsKovA8gg==}
    engines: {node: '>=12'}
    cpu: [x64]
    os: [freebsd]

  '@esbuild/freebsd-x64@0.21.5':
    resolution: {integrity: sha512-J95kNBj1zkbMXtHVH29bBriQygMXqoVQOQYA+ISs0/2l3T9/kj42ow2mpqerRBxDJnmkUDCaQT/dfNXWX/ZZCQ==}
    engines: {node: '>=12'}
    cpu: [x64]
    os: [freebsd]

  '@esbuild/freebsd-x64@0.25.12':
    resolution: {integrity: sha512-TGbO26Yw2xsHzxtbVFGEXBFH0FRAP7gtcPE7P5yP7wGy7cXK2oO7RyOhL5NLiqTlBh47XhmIUXuGciXEqYFfBQ==}
    engines: {node: '>=18'}
    cpu: [x64]
    os: [freebsd]

  '@esbuild/freebsd-x64@0.27.7':
    resolution: {integrity: sha512-jOBDK5XEjA4m5IJK3bpAQF9/Lelu/Z9ZcdhTRLf4cajlB+8VEhFFRjWgfy3M1O4rO2GQ/b2dLwCUGpiF/eATNQ==}
    engines: {node: '>=18'}
    cpu: [x64]
    os: [freebsd]

  '@esbuild/linux-arm64@0.18.20':
    resolution: {integrity: sha512-2YbscF+UL7SQAVIpnWvYwM+3LskyDmPhe31pE7/aoTMFKKzIc9lLbyGUpmmb8a8AixOL61sQ/mFh3jEjHYFvdA==}
    engines: {node: '>=12'}
    cpu: [arm64]
    os: [linux]

  '@esbuild/linux-arm64@0.19.12':
    resolution: {integrity: sha512-EoTjyYyLuVPfdPLsGVVVC8a0p1BFFvtpQDB/YLEhaXyf/5bczaGeN15QkR+O4S5LeJ92Tqotve7i1jn35qwvdA==}
    engines: {node: '>=12'}
    cpu: [arm64]
    os: [linux]

  '@esbuild/linux-arm64@0.21.5':
    resolution: {integrity: sha512-ibKvmyYzKsBeX8d8I7MH/TMfWDXBF3db4qM6sy+7re0YXya+K1cem3on9XgdT2EQGMu4hQyZhan7TeQ8XkGp4Q==}
    engines: {node: '>=12'}
    cpu: [arm64]
    os: [linux]

  '@esbuild/linux-arm64@0.25.12':
    resolution: {integrity: sha512-8bwX7a8FghIgrupcxb4aUmYDLp8pX06rGh5HqDT7bB+8Rdells6mHvrFHHW2JAOPZUbnjUpKTLg6ECyzvas2AQ==}
    engines: {node: '>=18'}
    cpu: [arm64]
    os: [linux]

  '@esbuild/linux-arm64@0.27.7':
    resolution: {integrity: sha512-RZPHBoxXuNnPQO9rvjh5jdkRmVizktkT7TCDkDmQ0W2SwHInKCAV95GRuvdSvA7w4VMwfCjUiPwDi0ZO6Nfe9A==}
    engines: {node: '>=18'}
    cpu: [arm64]
    os: [linux]

  '@esbuild/linux-arm@0.18.20':
    resolution: {integrity: sha512-/5bHkMWnq1EgKr1V+Ybz3s1hWXok7mDFUMQ4cG10AfW3wL02PSZi5kFpYKrptDsgb2WAJIvRcDm+qIvXf/apvg==}
    engines: {node: '>=12'}
    cpu: [arm]
    os: [linux]

  '@esbuild/linux-arm@0.19.12':
    resolution: {integrity: sha512-J5jPms//KhSNv+LO1S1TX1UWp1ucM6N6XuL6ITdKWElCu8wXP72l9MM0zDTzzeikVyqFE6U8YAV9/tFyj0ti+w==}
    engines: {node: '>=12'}
    cpu: [arm]
    os: [linux]

  '@esbuild/linux-arm@0.21.5':
    resolution: {integrity: sha512-bPb5AHZtbeNGjCKVZ9UGqGwo8EUu4cLq68E95A53KlxAPRmUyYv2D6F0uUI65XisGOL1hBP5mTronbgo+0bFcA==}
    engines: {node: '>=12'}
    cpu: [arm]
    os: [linux]

  '@esbuild/linux-arm@0.25.12':
    resolution: {integrity: sha512-lPDGyC1JPDou8kGcywY0YILzWlhhnRjdof3UlcoqYmS9El818LLfJJc3PXXgZHrHCAKs/Z2SeZtDJr5MrkxtOw==}
    engines: {node: '>=18'}
    cpu: [arm]
    os: [linux]

  '@esbuild/linux-arm@0.27.7':
    resolution: {integrity: sha512-RkT/YXYBTSULo3+af8Ib0ykH8u2MBh57o7q/DAs3lTJlyVQkgQvlrPTnjIzzRPQyavxtPtfg0EopvDyIt0j1rA==}
    engines: {node: '>=18'}
    cpu: [arm]
    os: [linux]

  '@esbuild/linux-ia32@0.18.20':
    resolution: {integrity: sha512-P4etWwq6IsReT0E1KHU40bOnzMHoH73aXp96Fs8TIT6z9Hu8G6+0SHSw9i2isWrD2nbx2qo5yUqACgdfVGx7TA==}
    engines: {node: '>=12'}
    cpu: [ia32]
    os: [linux]

  '@esbuild/linux-ia32@0.19.12':
    resolution: {integrity: sha512-Thsa42rrP1+UIGaWz47uydHSBOgTUnwBwNq59khgIwktK6x60Hivfbux9iNR0eHCHzOLjLMLfUMLCypBkZXMHA==}
    engines: {node: '>=12'}
    cpu: [ia32]
    os: [linux]

  '@esbuild/linux-ia32@0.21.5':
    resolution: {integrity: sha512-YvjXDqLRqPDl2dvRODYmmhz4rPeVKYvppfGYKSNGdyZkA01046pLWyRKKI3ax8fbJoK5QbxblURkwK/MWY18Tg==}
    engines: {node: '>=12'}
    cpu: [ia32]
    os: [linux]

  '@esbuild/linux-ia32@0.25.12':
    resolution: {integrity: sha512-0y9KrdVnbMM2/vG8KfU0byhUN+EFCny9+8g202gYqSSVMonbsCfLjUO+rCci7pM0WBEtz+oK/PIwHkzxkyharA==}
    engines: {node: '>=18'}
    cpu: [ia32]
    os: [linux]

  '@esbuild/linux-ia32@0.27.7':
    resolution: {integrity: sha512-GA48aKNkyQDbd3KtkplYWT102C5sn/EZTY4XROkxONgruHPU72l+gW+FfF8tf2cFjeHaRbWpOYa/uRBz/Xq1Pg==}
    engines: {node: '>=18'}
    cpu: [ia32]
    os: [linux]

  '@esbuild/linux-loong64@0.18.20':
    resolution: {integrity: sha512-nXW8nqBTrOpDLPgPY9uV+/1DjxoQ7DoB2N8eocyq8I9XuqJ7BiAMDMf9n1xZM9TgW0J8zrquIb/A7s3BJv7rjg==}
    engines: {node: '>=12'}
    cpu: [loong64]
    os: [linux]

  '@esbuild/linux-loong64@0.19.12':
    resolution: {integrity: sha512-LiXdXA0s3IqRRjm6rV6XaWATScKAXjI4R4LoDlvO7+yQqFdlr1Bax62sRwkVvRIrwXxvtYEHHI4dm50jAXkuAA==}
    engines: {node: '>=12'}
    cpu: [loong64]
    os: [linux]

  '@esbuild/linux-loong64@0.21.5':
    resolution: {integrity: sha512-uHf1BmMG8qEvzdrzAqg2SIG/02+4/DHB6a9Kbya0XDvwDEKCoC8ZRWI5JJvNdUjtciBGFQ5PuBlpEOXQj+JQSg==}
    engines: {node: '>=12'}
    cpu: [loong64]
    os: [linux]

  '@esbuild/linux-loong64@0.25.12':
    resolution: {integrity: sha512-h///Lr5a9rib/v1GGqXVGzjL4TMvVTv+s1DPoxQdz7l/AYv6LDSxdIwzxkrPW438oUXiDtwM10o9PmwS/6Z0Ng==}
    engines: {node: '>=18'}
    cpu: [loong64]
    os: [linux]

  '@esbuild/linux-loong64@0.27.7':
    resolution: {integrity: sha512-a4POruNM2oWsD4WKvBSEKGIiWQF8fZOAsycHOt6JBpZ+JN2n2JH9WAv56SOyu9X5IqAjqSIPTaJkqN8F7XOQ5Q==}
    engines: {node: '>=18'}
    cpu: [loong64]
    os: [linux]

  '@esbuild/linux-mips64el@0.18.20':
    resolution: {integrity: sha512-d5NeaXZcHp8PzYy5VnXV3VSd2D328Zb+9dEq5HE6bw6+N86JVPExrA6O68OPwobntbNJ0pzCpUFZTo3w0GyetQ==}
    engines: {node: '>=12'}
    cpu: [mips64el]
    os: [linux]

  '@esbuild/linux-mips64el@0.19.12':
    resolution: {integrity: sha512-fEnAuj5VGTanfJ07ff0gOA6IPsvrVHLVb6Lyd1g2/ed67oU1eFzL0r9WL7ZzscD+/N6i3dWumGE1Un4f7Amf+w==}
    engines: {node: '>=12'}
    cpu: [mips64el]
    os: [linux]

  '@esbuild/linux-mips64el@0.21.5':
    resolution: {integrity: sha512-IajOmO+KJK23bj52dFSNCMsz1QP1DqM6cwLUv3W1QwyxkyIWecfafnI555fvSGqEKwjMXVLokcV5ygHW5b3Jbg==}
    engines: {node: '>=12'}
    cpu: [mips64el]
    os: [linux]

  '@esbuild/linux-mips64el@0.25.12':
    resolution: {integrity: sha512-iyRrM1Pzy9GFMDLsXn1iHUm18nhKnNMWscjmp4+hpafcZjrr2WbT//d20xaGljXDBYHqRcl8HnxbX6uaA/eGVw==}
    engines: {node: '>=18'}
    cpu: [mips64el]
    os: [linux]

  '@esbuild/linux-mips64el@0.27.7':
    resolution: {integrity: sha512-KabT5I6StirGfIz0FMgl1I+R1H73Gp0ofL9A3nG3i/cYFJzKHhouBV5VWK1CSgKvVaG4q1RNpCTR2LuTVB3fIw==}
    engines: {node: '>=18'}
    cpu: [mips64el]
    os: [linux]

  '@esbuild/linux-ppc64@0.18.20':
    resolution: {integrity: sha512-WHPyeScRNcmANnLQkq6AfyXRFr5D6N2sKgkFo2FqguP44Nw2eyDlbTdZwd9GYk98DZG9QItIiTlFLHJHjxP3FA==}
    engines: {node: '>=12'}
    cpu: [ppc64]
    os: [linux]

  '@esbuild/linux-ppc64@0.19.12':
    resolution: {integrity: sha512-nYJA2/QPimDQOh1rKWedNOe3Gfc8PabU7HT3iXWtNUbRzXS9+vgB0Fjaqr//XNbd82mCxHzik2qotuI89cfixg==}
    engines: {node: '>=12'}
    cpu: [ppc64]
    os: [linux]

  '@esbuild/linux-ppc64@0.21.5':
    resolution: {integrity: sha512-1hHV/Z4OEfMwpLO8rp7CvlhBDnjsC3CttJXIhBi+5Aj5r+MBvy4egg7wCbe//hSsT+RvDAG7s81tAvpL2XAE4w==}
    engines: {node: '>=12'}
    cpu: [ppc64]
    os: [linux]

  '@esbuild/linux-ppc64@0.25.12':
    resolution: {integrity: sha512-9meM/lRXxMi5PSUqEXRCtVjEZBGwB7P/D4yT8UG/mwIdze2aV4Vo6U5gD3+RsoHXKkHCfSxZKzmDssVlRj1QQA==}
    engines: {node: '>=18'}
    cpu: [ppc64]
    os: [linux]

  '@esbuild/linux-ppc64@0.27.7':
    resolution: {integrity: sha512-gRsL4x6wsGHGRqhtI+ifpN/vpOFTQtnbsupUF5R5YTAg+y/lKelYR1hXbnBdzDjGbMYjVJLJTd2OFmMewAgwlQ==}
    engines: {node: '>=18'}
    cpu: [ppc64]
    os: [linux]

  '@esbuild/linux-riscv64@0.18.20':
    resolution: {integrity: sha512-WSxo6h5ecI5XH34KC7w5veNnKkju3zBRLEQNY7mv5mtBmrP/MjNBCAlsM2u5hDBlS3NGcTQpoBvRzqBcRtpq1A==}
    engines: {node: '>=12'}
    cpu: [riscv64]
    os: [linux]

  '@esbuild/linux-riscv64@0.19.12':
    resolution: {integrity: sha512-2MueBrlPQCw5dVJJpQdUYgeqIzDQgw3QtiAHUC4RBz9FXPrskyyU3VI1hw7C0BSKB9OduwSJ79FTCqtGMWqJHg==}
    engines: {node: '>=12'}
    cpu: [riscv64]
    os: [linux]

  '@esbuild/linux-riscv64@0.21.5':
    resolution: {integrity: sha512-2HdXDMd9GMgTGrPWnJzP2ALSokE/0O5HhTUvWIbD3YdjME8JwvSCnNGBnTThKGEB91OZhzrJ4qIIxk/SBmyDDA==}
    engines: {node: '>=12'}
    cpu: [riscv64]
    os: [linux]

  '@esbuild/linux-riscv64@0.25.12':
    resolution: {integrity: sha512-Zr7KR4hgKUpWAwb1f3o5ygT04MzqVrGEGXGLnj15YQDJErYu/BGg+wmFlIDOdJp0PmB0lLvxFIOXZgFRrdjR0w==}
    engines: {node: '>=18'}
    cpu: [riscv64]
    os: [linux]

  '@esbuild/linux-riscv64@0.27.7':
    resolution: {integrity: sha512-hL25LbxO1QOngGzu2U5xeXtxXcW+/GvMN3ejANqXkxZ/opySAZMrc+9LY/WyjAan41unrR3YrmtTsUpwT66InQ==}
    engines: {node: '>=18'}
    cpu: [riscv64]
    os: [linux]

  '@esbuild/linux-s390x@0.18.20':
    resolution: {integrity: sha512-+8231GMs3mAEth6Ja1iK0a1sQ3ohfcpzpRLH8uuc5/KVDFneH6jtAJLFGafpzpMRO6DzJ6AvXKze9LfFMrIHVQ==}
    engines: {node: '>=12'}
    cpu: [s390x]
    os: [linux]

  '@esbuild/linux-s390x@0.19.12':
    resolution: {integrity: sha512-+Pil1Nv3Umes4m3AZKqA2anfhJiVmNCYkPchwFJNEJN5QxmTs1uzyy4TvmDrCRNT2ApwSari7ZIgrPeUx4UZDg==}
    engines: {node: '>=12'}
    cpu: [s390x]
    os: [linux]

  '@esbuild/linux-s390x@0.21.5':
    resolution: {integrity: sha512-zus5sxzqBJD3eXxwvjN1yQkRepANgxE9lgOW2qLnmr8ikMTphkjgXu1HR01K4FJg8h1kEEDAqDcZQtbrRnB41A==}
    engines: {node: '>=12'}
    cpu: [s390x]
    os: [linux]

  '@esbuild/linux-s390x@0.25.12':
    resolution: {integrity: sha512-MsKncOcgTNvdtiISc/jZs/Zf8d0cl/t3gYWX8J9ubBnVOwlk65UIEEvgBORTiljloIWnBzLs4qhzPkJcitIzIg==}
    engines: {node: '>=18'}
    cpu: [s390x]
    os: [linux]

  '@esbuild/linux-s390x@0.27.7':
    resolution: {integrity: sha512-2k8go8Ycu1Kb46vEelhu1vqEP+UeRVj2zY1pSuPdgvbd5ykAw82Lrro28vXUrRmzEsUV0NzCf54yARIK8r0fdw==}
    engines: {node: '>=18'}
    cpu: [s390x]
    os: [linux]

  '@esbuild/linux-x64@0.18.20':
    resolution: {integrity: sha512-UYqiqemphJcNsFEskc73jQ7B9jgwjWrSayxawS6UVFZGWrAAtkzjxSqnoclCXxWtfwLdzU+vTpcNYhpn43uP1w==}
    engines: {node: '>=12'}
    cpu: [x64]
    os: [linux]

  '@esbuild/linux-x64@0.19.12':
    resolution: {integrity: sha512-B71g1QpxfwBvNrfyJdVDexenDIt1CiDN1TIXLbhOw0KhJzE78KIFGX6OJ9MrtC0oOqMWf+0xop4qEU8JrJTwCg==}
    engines: {node: '>=12'}
    cpu: [x64]
    os: [linux]

  '@esbuild/linux-x64@0.21.5':
    resolution: {integrity: sha512-1rYdTpyv03iycF1+BhzrzQJCdOuAOtaqHTWJZCWvijKD2N5Xu0TtVC8/+1faWqcP9iBCWOmjmhoH94dH82BxPQ==}
    engines: {node: '>=12'}
    cpu: [x64]
    os: [linux]

  '@esbuild/linux-x64@0.25.12':
    resolution: {integrity: sha512-uqZMTLr/zR/ed4jIGnwSLkaHmPjOjJvnm6TVVitAa08SLS9Z0VM8wIRx7gWbJB5/J54YuIMInDquWyYvQLZkgw==}
    engines: {node: '>=18'}
    cpu: [x64]
    os: [linux]

  '@esbuild/linux-x64@0.27.7':
    resolution: {integrity: sha512-hzznmADPt+OmsYzw1EE33ccA+HPdIqiCRq7cQeL1Jlq2gb1+OyWBkMCrYGBJ+sxVzve2ZJEVeePbLM2iEIZSxA==}
    engines: {node: '>=18'}
    cpu: [x64]
    os: [linux]

  '@esbuild/netbsd-arm64@0.25.12':
    resolution: {integrity: sha512-xXwcTq4GhRM7J9A8Gv5boanHhRa/Q9KLVmcyXHCTaM4wKfIpWkdXiMog/KsnxzJ0A1+nD+zoecuzqPmCRyBGjg==}
    engines: {node: '>=18'}
    cpu: [arm64]
    os: [netbsd]

  '@esbuild/netbsd-arm64@0.27.7':
    resolution: {integrity: sha512-b6pqtrQdigZBwZxAn1UpazEisvwaIDvdbMbmrly7cDTMFnw/+3lVxxCTGOrkPVnsYIosJJXAsILG9XcQS+Yu6w==}
    engines: {node: '>=18'}
    cpu: [arm64]
    os: [netbsd]

  '@esbuild/netbsd-x64@0.18.20':
    resolution: {integrity: sha512-iO1c++VP6xUBUmltHZoMtCUdPlnPGdBom6IrO4gyKPFFVBKioIImVooR5I83nTew5UOYrk3gIJhbZh8X44y06A==}
    engines: {node: '>=12'}
    cpu: [x64]
    os: [netbsd]

  '@esbuild/netbsd-x64@0.19.12':
    resolution: {integrity: sha512-3ltjQ7n1owJgFbuC61Oj++XhtzmymoCihNFgT84UAmJnxJfm4sYCiSLTXZtE00VWYpPMYc+ZQmB6xbSdVh0JWA==}
    engines: {node: '>=12'}
    cpu: [x64]
    os: [netbsd]

  '@esbuild/netbsd-x64@0.21.5':
    resolution: {integrity: sha512-Woi2MXzXjMULccIwMnLciyZH4nCIMpWQAs049KEeMvOcNADVxo0UBIQPfSmxB3CWKedngg7sWZdLvLczpe0tLg==}
    engines: {node: '>=12'}
    cpu: [x64]
    os: [netbsd]

  '@esbuild/netbsd-x64@0.25.12':
    resolution: {integrity: sha512-Ld5pTlzPy3YwGec4OuHh1aCVCRvOXdH8DgRjfDy/oumVovmuSzWfnSJg+VtakB9Cm0gxNO9BzWkj6mtO1FMXkQ==}
    engines: {node: '>=18'}
    cpu: [x64]
    os: [netbsd]

  '@esbuild/netbsd-x64@0.27.7':
    resolution: {integrity: sha512-OfatkLojr6U+WN5EDYuoQhtM+1xco+/6FSzJJnuWiUw5eVcicbyK3dq5EeV/QHT1uy6GoDhGbFpprUiHUYggrw==}
    engines: {node: '>=18'}
    cpu: [x64]
    os: [netbsd]

  '@esbuild/openbsd-arm64@0.25.12':
    resolution: {integrity: sha512-fF96T6KsBo/pkQI950FARU9apGNTSlZGsv1jZBAlcLL1MLjLNIWPBkj5NlSz8aAzYKg+eNqknrUJ24QBybeR5A==}
    engines: {node: '>=18'}
    cpu: [arm64]
    os: [openbsd]

  '@esbuild/openbsd-arm64@0.27.7':
    resolution: {integrity: sha512-AFuojMQTxAz75Fo8idVcqoQWEHIXFRbOc1TrVcFSgCZtQfSdc1RXgB3tjOn/krRHENUB4j00bfGjyl2mJrU37A==}
    engines: {node: '>=18'}
    cpu: [arm64]
    os: [openbsd]

  '@esbuild/openbsd-x64@0.18.20':
    resolution: {integrity: sha512-e5e4YSsuQfX4cxcygw/UCPIEP6wbIL+se3sxPdCiMbFLBWu0eiZOJ7WoD+ptCLrmjZBK1Wk7I6D/I3NglUGOxg==}
    engines: {node: '>=12'}
    cpu: [x64]
    os: [openbsd]

  '@esbuild/openbsd-x64@0.19.12':
    resolution: {integrity: sha512-RbrfTB9SWsr0kWmb9srfF+L933uMDdu9BIzdA7os2t0TXhCRjrQyCeOt6wVxr79CKD4c+p+YhCj31HBkYcXebw==}
    engines: {node: '>=12'}
    cpu: [x64]
    os: [openbsd]

  '@esbuild/openbsd-x64@0.21.5':
    resolution: {integrity: sha512-HLNNw99xsvx12lFBUwoT8EVCsSvRNDVxNpjZ7bPn947b8gJPzeHWyNVhFsaerc0n3TsbOINvRP2byTZ5LKezow==}
    engines: {node: '>=12'}
    cpu: [x64]
    os: [openbsd]

  '@esbuild/openbsd-x64@0.25.12':
    resolution: {integrity: sha512-MZyXUkZHjQxUvzK7rN8DJ3SRmrVrke8ZyRusHlP+kuwqTcfWLyqMOE3sScPPyeIXN/mDJIfGXvcMqCgYKekoQw==}
    engines: {node: '>=18'}
    cpu: [x64]
    os: [openbsd]

  '@esbuild/openbsd-x64@0.27.7':
    resolution: {integrity: sha512-+A1NJmfM8WNDv5CLVQYJ5PshuRm/4cI6WMZRg1by1GwPIQPCTs1GLEUHwiiQGT5zDdyLiRM/l1G0Pv54gvtKIg==}
    engines: {node: '>=18'}
    cpu: [x64]
    os: [openbsd]

  '@esbuild/openharmony-arm64@0.25.12':
    resolution: {integrity: sha512-rm0YWsqUSRrjncSXGA7Zv78Nbnw4XL6/dzr20cyrQf7ZmRcsovpcRBdhD43Nuk3y7XIoW2OxMVvwuRvk9XdASg==}
    engines: {node: '>=18'}
    cpu: [arm64]
    os: [openharmony]

  '@esbuild/openharmony-arm64@0.27.7':
    resolution: {integrity: sha512-+KrvYb/C8zA9CU/g0sR6w2RBw7IGc5J2BPnc3dYc5VJxHCSF1yNMxTV5LQ7GuKteQXZtspjFbiuW5/dOj7H4Yw==}
    engines: {node: '>=18'}
    cpu: [arm64]
    os: [openharmony]

  '@esbuild/sunos-x64@0.18.20':
    resolution: {integrity: sha512-kDbFRFp0YpTQVVrqUd5FTYmWo45zGaXe0X8E1G/LKFC0v8x0vWrhOWSLITcCn63lmZIxfOMXtCfti/RxN/0wnQ==}
    engines: {node: '>=12'}
    cpu: [x64]
    os: [sunos]

  '@esbuild/sunos-x64@0.19.12':
    resolution: {integrity: sha512-HKjJwRrW8uWtCQnQOz9qcU3mUZhTUQvi56Q8DPTLLB+DawoiQdjsYq+j+D3s9I8VFtDr+F9CjgXKKC4ss89IeA==}
    engines: {node: '>=12'}
    cpu: [x64]
    os: [sunos]

  '@esbuild/sunos-x64@0.21.5':
    resolution: {integrity: sha512-6+gjmFpfy0BHU5Tpptkuh8+uw3mnrvgs+dSPQXQOv3ekbordwnzTVEb4qnIvQcYXq6gzkyTnoZ9dZG+D4garKg==}
    engines: {node: '>=12'}
    cpu: [x64]
    os: [sunos]

  '@esbuild/sunos-x64@0.25.12':
    resolution: {integrity: sha512-3wGSCDyuTHQUzt0nV7bocDy72r2lI33QL3gkDNGkod22EsYl04sMf0qLb8luNKTOmgF/eDEDP5BFNwoBKH441w==}
    engines: {node: '>=18'}
    cpu: [x64]
    os: [sunos]

  '@esbuild/sunos-x64@0.27.7':
    resolution: {integrity: sha512-ikktIhFBzQNt/QDyOL580ti9+5mL/YZeUPKU2ivGtGjdTYoqz6jObj6nOMfhASpS4GU4Q/Clh1QtxWAvcYKamA==}
    engines: {node: '>=18'}
    cpu: [x64]
    os: [sunos]

  '@esbuild/win32-arm64@0.18.20':
    resolution: {integrity: sha512-ddYFR6ItYgoaq4v4JmQQaAI5s7npztfV4Ag6NrhiaW0RrnOXqBkgwZLofVTlq1daVTQNhtI5oieTvkRPfZrePg==}
    engines: {node: '>=12'}
    cpu: [arm64]
    os: [win32]

  '@esbuild/win32-arm64@0.19.12':
    resolution: {integrity: sha512-URgtR1dJnmGvX864pn1B2YUYNzjmXkuJOIqG2HdU62MVS4EHpU2946OZoTMnRUHklGtJdJZ33QfzdjGACXhn1A==}
    engines: {node: '>=12'}
    cpu: [arm64]
    os: [win32]

  '@esbuild/win32-arm64@0.21.5':
    resolution: {integrity: sha512-Z0gOTd75VvXqyq7nsl93zwahcTROgqvuAcYDUr+vOv8uHhNSKROyU961kgtCD1e95IqPKSQKH7tBTslnS3tA8A==}
    engines: {node: '>=12'}
    cpu: [arm64]
    os: [win32]

  '@esbuild/win32-arm64@0.25.12':
    resolution: {integrity: sha512-rMmLrur64A7+DKlnSuwqUdRKyd3UE7oPJZmnljqEptesKM8wx9J8gx5u0+9Pq0fQQW8vqeKebwNXdfOyP+8Bsg==}
    engines: {node: '>=18'}
    cpu: [arm64]
    os: [win32]

  '@esbuild/win32-arm64@0.27.7':
    resolution: {integrity: sha512-7yRhbHvPqSpRUV7Q20VuDwbjW5kIMwTHpptuUzV+AA46kiPze5Z7qgt6CLCK3pWFrHeNfDd1VKgyP4O+ng17CA==}
    engines: {node: '>=18'}
    cpu: [arm64]
    os: [win32]

  '@esbuild/win32-ia32@0.18.20':
    resolution: {integrity: sha512-Wv7QBi3ID/rROT08SABTS7eV4hX26sVduqDOTe1MvGMjNd3EjOz4b7zeexIR62GTIEKrfJXKL9LFxTYgkyeu7g==}
    engines: {node: '>=12'}
    cpu: [ia32]
    os: [win32]

  '@esbuild/win32-ia32@0.19.12':
    resolution: {integrity: sha512-+ZOE6pUkMOJfmxmBZElNOx72NKpIa/HFOMGzu8fqzQJ5kgf6aTGrcJaFsNiVMH4JKpMipyK+7k0n2UXN7a8YKQ==}
    engines: {node: '>=12'}
    cpu: [ia32]
    os: [win32]

  '@esbuild/win32-ia32@0.21.5':
    resolution: {integrity: sha512-SWXFF1CL2RVNMaVs+BBClwtfZSvDgtL//G/smwAc5oVK/UPu2Gu9tIaRgFmYFFKrmg3SyAjSrElf0TiJ1v8fYA==}
    engines: {node: '>=12'}
    cpu: [ia32]
    os: [win32]

  '@esbuild/win32-ia32@0.25.12':
    resolution: {integrity: sha512-HkqnmmBoCbCwxUKKNPBixiWDGCpQGVsrQfJoVGYLPT41XWF8lHuE5N6WhVia2n4o5QK5M4tYr21827fNhi4byQ==}
    engines: {node: '>=18'}
    cpu: [ia32]
    os: [win32]

  '@esbuild/win32-ia32@0.27.7':
    resolution: {integrity: sha512-SmwKXe6VHIyZYbBLJrhOoCJRB/Z1tckzmgTLfFYOfpMAx63BJEaL9ExI8x7v0oAO3Zh6D/Oi1gVxEYr5oUCFhw==}
    engines: {node: '>=18'}
    cpu: [ia32]
    os: [win32]

  '@esbuild/win32-x64@0.18.20':
    resolution: {integrity: sha512-kTdfRcSiDfQca/y9QIkng02avJ+NCaQvrMejlsB3RRv5sE9rRoeBPISaZpKxHELzRxZyLvNts1P27W3wV+8geQ==}
    engines: {node: '>=12'}
    cpu: [x64]
    os: [win32]

  '@esbuild/win32-x64@0.19.12':
    resolution: {integrity: sha512-T1QyPSDCyMXaO3pzBkF96E8xMkiRYbUEZADd29SyPGabqxMViNoii+NcK7eWJAEoU6RZyEm5lVSIjTmcdoB9HA==}
    engines: {node: '>=12'}
    cpu: [x64]
    os: [win32]

  '@esbuild/win32-x64@0.21.5':
    resolution: {integrity: sha512-tQd/1efJuzPC6rCFwEvLtci/xNFcTZknmXs98FYDfGE4wP9ClFV98nyKrzJKVPMhdDnjzLhdUyMX4PsQAPjwIw==}
    engines: {node: '>=12'}
    cpu: [x64]
    os: [win32]

  '@esbuild/win32-x64@0.25.12':
    resolution: {integrity: sha512-alJC0uCZpTFrSL0CCDjcgleBXPnCrEAhTBILpeAp7M/OFgoqtAetfBzX0xM00MUsVVPpVjlPuMbREqnZCXaTnA==}
    engines: {node: '>=18'}
    cpu: [x64]
    os: [win32]

  '@esbuild/win32-x64@0.27.7':
    resolution: {integrity: sha512-56hiAJPhwQ1R4i+21FVF7V8kSD5zZTdHcVuRFMW0hn753vVfQN8xlx4uOPT4xoGH0Z/oVATuR82AiqSTDIpaHg==}
    engines: {node: '>=18'}
    cpu: [x64]
    os: [win32]

  '@img/colour@1.1.0':
    resolution: {integrity: sha512-Td76q7j57o/tLVdgS746cYARfSyxk8iEfRxewL9h4OMzYhbW4TAcppl0mT4eyqXddh6L/jwoM75mo7ixa/pCeQ==}
    engines: {node: '>=18'}

  '@img/sharp-darwin-arm64@0.34.5':
    resolution: {integrity: sha512-imtQ3WMJXbMY4fxb/Ndp6HBTNVtWCUI0WdobyheGf5+ad6xX8VIDO8u2xE4qc/fr08CKG/7dDseFtn6M6g/r3w==}
    engines: {node: ^18.17.0 || ^20.3.0 || >=21.0.0}
    cpu: [arm64]
    os: [darwin]

  '@img/sharp-darwin-x64@0.34.5':
    resolution: {integrity: sha512-YNEFAF/4KQ/PeW0N+r+aVVsoIY0/qxxikF2SWdp+NRkmMB7y9LBZAVqQ4yhGCm/H3H270OSykqmQMKLBhBJDEw==}
    engines: {node: ^18.17.0 || ^20.3.0 || >=21.0.0}
    cpu: [x64]
    os: [darwin]

  '@img/sharp-libvips-darwin-arm64@1.2.4':
    resolution: {integrity: sha512-zqjjo7RatFfFoP0MkQ51jfuFZBnVE2pRiaydKJ1G/rHZvnsrHAOcQALIi9sA5co5xenQdTugCvtb1cuf78Vf4g==}
    cpu: [arm64]
    os: [darwin]

  '@img/sharp-libvips-darwin-x64@1.2.4':
    resolution: {integrity: sha512-1IOd5xfVhlGwX+zXv2N93k0yMONvUlANylbJw1eTah8K/Jtpi15KC+WSiaX/nBmbm2HxRM1gZ0nSdjSsrZbGKg==}
    cpu: [x64]
    os: [darwin]

  '@img/sharp-libvips-linux-arm64@1.2.4':
    resolution: {integrity: sha512-excjX8DfsIcJ10x1Kzr4RcWe1edC9PquDRRPx3YVCvQv+U5p7Yin2s32ftzikXojb1PIFc/9Mt28/y+iRklkrw==}
    cpu: [arm64]
    os: [linux]

  '@img/sharp-libvips-linux-arm@1.2.4':
    resolution: {integrity: sha512-bFI7xcKFELdiNCVov8e44Ia4u2byA+l3XtsAj+Q8tfCwO6BQ8iDojYdvoPMqsKDkuoOo+X6HZA0s0q11ANMQ8A==}
    cpu: [arm]
    os: [linux]

  '@img/sharp-libvips-linux-ppc64@1.2.4':
    resolution: {integrity: sha512-FMuvGijLDYG6lW+b/UvyilUWu5Ayu+3r2d1S8notiGCIyYU/76eig1UfMmkZ7vwgOrzKzlQbFSuQfgm7GYUPpA==}
    cpu: [ppc64]
    os: [linux]

  '@img/sharp-libvips-linux-riscv64@1.2.4':
    resolution: {integrity: sha512-oVDbcR4zUC0ce82teubSm+x6ETixtKZBh/qbREIOcI3cULzDyb18Sr/Wcyx7NRQeQzOiHTNbZFF1UwPS2scyGA==}
    cpu: [riscv64]
    os: [linux]

  '@img/sharp-libvips-linux-s390x@1.2.4':
    resolution: {integrity: sha512-qmp9VrzgPgMoGZyPvrQHqk02uyjA0/QrTO26Tqk6l4ZV0MPWIW6LTkqOIov+J1yEu7MbFQaDpwdwJKhbJvuRxQ==}
    cpu: [s390x]
    os: [linux]

  '@img/sharp-libvips-linux-x64@1.2.4':
    resolution: {integrity: sha512-tJxiiLsmHc9Ax1bz3oaOYBURTXGIRDODBqhveVHonrHJ9/+k89qbLl0bcJns+e4t4rvaNBxaEZsFtSfAdquPrw==}
    cpu: [x64]
    os: [linux]

  '@img/sharp-libvips-linuxmusl-arm64@1.2.4':
    resolution: {integrity: sha512-FVQHuwx1IIuNow9QAbYUzJ+En8KcVm9Lk5+uGUQJHaZmMECZmOlix9HnH7n1TRkXMS0pGxIJokIVB9SuqZGGXw==}
    cpu: [arm64]
    os: [linux]

  '@img/sharp-libvips-linuxmusl-x64@1.2.4':
    resolution: {integrity: sha512-+LpyBk7L44ZIXwz/VYfglaX/okxezESc6UxDSoyo2Ks6Jxc4Y7sGjpgU9s4PMgqgjj1gZCylTieNamqA1MF7Dg==}
    cpu: [x64]
    os: [linux]

  '@img/sharp-linux-arm64@0.34.5':
    resolution: {integrity: sha512-bKQzaJRY/bkPOXyKx5EVup7qkaojECG6NLYswgktOZjaXecSAeCWiZwwiFf3/Y+O1HrauiE3FVsGxFg8c24rZg==}
    engines: {node: ^18.17.0 || ^20.3.0 || >=21.0.0}
    cpu: [arm64]
    os: [linux]

  '@img/sharp-linux-arm@0.34.5':
    resolution: {integrity: sha512-9dLqsvwtg1uuXBGZKsxem9595+ujv0sJ6Vi8wcTANSFpwV/GONat5eCkzQo/1O6zRIkh0m/8+5BjrRr7jDUSZw==}
    engines: {node: ^18.17.0 || ^20.3.0 || >=21.0.0}
    cpu: [arm]
    os: [linux]

  '@img/sharp-linux-ppc64@0.34.5':
    resolution: {integrity: sha512-7zznwNaqW6YtsfrGGDA6BRkISKAAE1Jo0QdpNYXNMHu2+0dTrPflTLNkpc8l7MUP5M16ZJcUvysVWWrMefZquA==}
    engines: {node: ^18.17.0 || ^20.3.0 || >=21.0.0}
    cpu: [ppc64]
    os: [linux]

  '@img/sharp-linux-riscv64@0.34.5':
    resolution: {integrity: sha512-51gJuLPTKa7piYPaVs8GmByo7/U7/7TZOq+cnXJIHZKavIRHAP77e3N2HEl3dgiqdD/w0yUfiJnII77PuDDFdw==}
    engines: {node: ^18.17.0 || ^20.3.0 || >=21.0.0}
    cpu: [riscv64]
    os: [linux]

  '@img/sharp-linux-s390x@0.34.5':
    resolution: {integrity: sha512-nQtCk0PdKfho3eC5MrbQoigJ2gd1CgddUMkabUj+rBevs8tZ2cULOx46E7oyX+04WGfABgIwmMC0VqieTiR4jg==}
    engines: {node: ^18.17.0 || ^20.3.0 || >=21.0.0}
    cpu: [s390x]
    os: [linux]

  '@img/sharp-linux-x64@0.34.5':
    resolution: {integrity: sha512-MEzd8HPKxVxVenwAa+JRPwEC7QFjoPWuS5NZnBt6B3pu7EG2Ge0id1oLHZpPJdn3OQK+BQDiw9zStiHBTJQQQQ==}
    engines: {node: ^18.17.0 || ^20.3.0 || >=21.0.0}
    cpu: [x64]
    os: [linux]

  '@img/sharp-linuxmusl-arm64@0.34.5':
    resolution: {integrity: sha512-fprJR6GtRsMt6Kyfq44IsChVZeGN97gTD331weR1ex1c1rypDEABN6Tm2xa1wE6lYb5DdEnk03NZPqA7Id21yg==}
    engines: {node: ^18.17.0 || ^20.3.0 || >=21.0.0}
    cpu: [arm64]
    os: [linux]

  '@img/sharp-linuxmusl-x64@0.34.5':
    resolution: {integrity: sha512-Jg8wNT1MUzIvhBFxViqrEhWDGzqymo3sV7z7ZsaWbZNDLXRJZoRGrjulp60YYtV4wfY8VIKcWidjojlLcWrd8Q==}
    engines: {node: ^18.17.0 || ^20.3.0 || >=21.0.0}
    cpu: [x64]
    os: [linux]

  '@img/sharp-wasm32@0.34.5':
    resolution: {integrity: sha512-OdWTEiVkY2PHwqkbBI8frFxQQFekHaSSkUIJkwzclWZe64O1X4UlUjqqqLaPbUpMOQk6FBu/HtlGXNblIs0huw==}
    engines: {node: ^18.17.0 || ^20.3.0 || >=21.0.0}
    cpu: [wasm32]

  '@img/sharp-win32-arm64@0.34.5':
    resolution: {integrity: sha512-WQ3AgWCWYSb2yt+IG8mnC6Jdk9Whs7O0gxphblsLvdhSpSTtmu69ZG1Gkb6NuvxsNACwiPV6cNSZNzt0KPsw7g==}
    engines: {node: ^18.17.0 || ^20.3.0 || >=21.0.0}
    cpu: [arm64]
    os: [win32]

  '@img/sharp-win32-ia32@0.34.5':
    resolution: {integrity: sha512-FV9m/7NmeCmSHDD5j4+4pNI8Cp3aW+JvLoXcTUo0IqyjSfAZJ8dIUmijx1qaJsIiU+Hosw6xM5KijAWRJCSgNg==}
    engines: {node: ^18.17.0 || ^20.3.0 || >=21.0.0}
    cpu: [ia32]
    os: [win32]

  '@img/sharp-win32-x64@0.34.5':
    resolution: {integrity: sha512-+29YMsqY2/9eFEiW93eqWnuLcWcufowXewwSNIT6UwZdUUCrM3oFjMWH/Z6/TMmb4hlFenmfAVbpWeup2jryCw==}
    engines: {node: ^18.17.0 || ^20.3.0 || >=21.0.0}
    cpu: [x64]
    os: [win32]

  '@inquirer/external-editor@1.0.3':
    resolution: {integrity: sha512-RWbSrDiYmO4LbejWY7ttpxczuwQyZLBUyygsA9Nsv95hpzUWwnNTVQmAq3xuh7vNwCp07UTmE5i11XAEExx4RA==}
    engines: {node: '>=18'}
    peerDependencies:
      '@types/node': '>=18'
    peerDependenciesMeta:
      '@types/node':
        optional: true

  '@jest/schemas@29.6.3':
    resolution: {integrity: sha512-mo5j5X+jIZmJQveBKeS/clAueipV7KgiX1vMgCxam1RNYiqE1w62n0/tJJnHtjW8ZHcQco5gY85jA3mi0L+nSA==}
    engines: {node: ^14.15.0 || ^16.10.0 || >=18.0.0}

  '@jridgewell/gen-mapping@0.3.13':
    resolution: {integrity: sha512-2kkt/7niJ6MgEPxF0bYdQ6etZaA+fQvDcLKckhy1yIQOzaoKjBBjSj63/aLVjYE3qhRt5dvM+uUyfCg6UKCBbA==}

  '@jridgewell/remapping@2.3.5':
    resolution: {integrity: sha512-LI9u/+laYG4Ds1TDKSJW2YPrIlcVYOwi2fUC6xB43lueCjgxV4lffOCZCtYFiH6TNOX+tQKXx97T4IKHbhyHEQ==}

  '@jridgewell/resolve-uri@3.1.2':
    resolution: {integrity: sha512-bRISgCIjP20/tbWSPWMEi54QVPRZExkuD9lJL+UIxUKtwVJA8wW1Trb1jMs1RFXo1CBTNZ/5hpC9QvmKWdopKw==}
    engines: {node: '>=6.0.0'}

  '@jridgewell/sourcemap-codec@1.5.5':
    resolution: {integrity: sha512-cYQ9310grqxueWbl+WuIUIaiUaDcj7WOq5fVhEljNVgRfOUhY9fy2zTvfoqWsnebh8Sl70VScFbICvJnLKB0Og==}

  '@jridgewell/trace-mapping@0.3.31':
    resolution: {integrity: sha512-zzNR+SdQSDJzc8joaeP8QQoCQr8NuYx2dIIytl1QeBEZHJ9uW6hebsrYgbz8hJwUQao3TWCMtmfV8Nu1twOLAw==}

  '@lezer/common@1.5.2':
    resolution: {integrity: sha512-sxQE460fPZyU3sdc8lafxiPwJHBzZRy/udNFynGQky1SePYBdhkBl1kOagA9uT3pxR8K09bOrmTUqA9wb/PjSQ==}

  '@lezer/css@1.3.3':
    resolution: {integrity: sha512-RzBo8r+/6QJeow7aPHIpGVIH59xTcJXp399820gZoMo9noQDRVpJLheIBUicYwKcsbOYoBRoLZlf2720dG/4Tg==}

  '@lezer/highlight@1.2.3':
    resolution: {integrity: sha512-qXdH7UqTvGfdVBINrgKhDsVTJTxactNNxLk7+UMwZhU13lMHaOBlJe9Vqp907ya56Y3+ed2tlqzys7jDkTmW0g==}

  '@lezer/html@1.3.13':
    resolution: {integrity: sha512-oI7n6NJml729m7pjm9lvLvmXbdoMoi2f+1pwSDJkl9d68zGr7a9Btz8NdHTGQZtW2DA25ybeuv/SyDb9D5tseg==}

  '@lezer/javascript@1.5.4':
    resolution: {integrity: sha512-vvYx3MhWqeZtGPwDStM2dwgljd5smolYD2lR2UyFcHfxbBQebqx8yjmFmxtJ/E6nN6u1D9srOiVWm3Rb4tmcUA==}

  '@lezer/lr@1.4.10':
    resolution: {integrity: sha512-rnCpTIBafOx4mRp43xOxDJbFipJm/c0cia/V5TiGlhmMa+wsSdoGmUN3w5Bqrks/09Q/D4tNAmWaT8p6NRi77A==}

  '@lezer/markdown@1.6.3':
    resolution: {integrity: sha512-jpGm5Ps+XErS+xA4urw7ogEGkeZOahVQF21Z6oECF0sj+2liwZopd2+I8uH5I/vZsRuuze3OxBREIANLf6KKUw==}

  '@manypkg/find-root@1.1.0':
    resolution: {integrity: sha512-mki5uBvhHzO8kYYix/WRy2WX8S3B5wdVSc9D6KcU5lQNglP2yt58/VfLuAK49glRXChosY8ap2oJ1qgma3GUVA==}

  '@manypkg/get-packages@1.1.3':
    resolution: {integrity: sha512-fo+QhuU3qE/2TQMQmbVMqaQ6EWbMhi4ABWP+O4AM1NqPBuy0OrApV5LO6BrrgnhtAHS2NH6RrVk9OL181tTi8A==}

  '@marijn/find-cluster-break@1.0.2':
    resolution: {integrity: sha512-l0h88YhZFyKdXIFNfSWpyjStDjGHwZ/U7iobcK1cQQD8sejsONdQtTVU+1wVN1PBw40PiiHB1vA5S7VTfQiP9g==}

  '@noble/hashes@1.8.0':
    resolution: {integrity: sha512-jCs9ldd7NwzpgXDIf6P3+NrHh9/sD6CQdxHyjQI+h/6rDNo88ypBxxz45UDuZHz9r3tNz7N/VInSVoVdtXEI4A==}
    engines: {node: ^14.21.3 || >=16}

  '@noble/secp256k1@2.3.0':
    resolution: {integrity: sha512-0TQed2gcBbIrh7Ccyw+y/uZQvbJwm7Ao4scBUxqpBCcsOlZG0O4KGfjtNAy/li4W8n1xt3dxrwJ0beZ2h2G6Kw==}

  '@nodelib/fs.scandir@2.1.5':
    resolution: {integrity: sha512-vq24Bq3ym5HEQm2NKCr3yXDwjc7vTsEThRDnkp2DK9p1uqLR+DHurm/NOTo0KG7HYHU7eppKZj3MyqYuMBf62g==}
    engines: {node: '>= 8'}

  '@nodelib/fs.stat@2.0.5':
    resolution: {integrity: sha512-RkhPPp2zrqDAQA/2jNhnztcPAlv64XdhIp7a7454A5ovI7Bukxgt7MX7udwAu3zg1DcpPU0rz3VV1SeaqvY4+A==}
    engines: {node: '>= 8'}

  '@nodelib/fs.walk@1.2.8':
    resolution: {integrity: sha512-oGB+UxlgWcgQkgwo8GcEGwemoTFt3FIO9ababBmaGwXIoBKZ+GTy0pP185beGg7Llih/NSHSV2XAs1lnznocSg==}
    engines: {node: '>= 8'}

  '@petamoriken/float16@3.9.3':
    resolution: {integrity: sha512-8awtpHXCx/bNpFt4mt2xdkgtgVvKqty8VbjHI/WWWQuEw+KLzFot3f4+LkQY9YmOtq7A5GdOnqoIC8Pdygjk2g==}

  '@rolldown/pluginutils@1.0.0-beta.27':
    resolution: {integrity: sha512-+d0F4MKMCbeVUJwG96uQ4SgAznZNSq93I3V+9NHA4OpvqG8mRCpGdKmK8l/dl02h2CCDHwW2FqilnTyDcAnqjA==}

  '@rollup/plugin-inject@5.0.5':
    resolution: {integrity: sha512-2+DEJbNBoPROPkgTDNe8/1YXWcqxbN5DTjASVIOx8HS+pITXushyNiBV56RB08zuptzz8gT3YfkqriTBVycepg==}
    engines: {node: '>=14.0.0'}
    peerDependencies:
      rollup: ^1.20.0||^2.0.0||^3.0.0||^4.0.0
    peerDependenciesMeta:
      rollup:
        optional: true

  '@rollup/pluginutils@5.3.0':
    resolution: {integrity: sha512-5EdhGZtnu3V88ces7s53hhfK5KSASnJZv8Lulpc04cWO3REESroJXg73DFsOmgbU2BhwV0E20bu2IDZb3VKW4Q==}
    engines: {node: '>=14.0.0'}
    peerDependencies:
      rollup: ^1.20.0||^2.0.0||^3.0.0||^4.0.0
    peerDependenciesMeta:
      rollup:
        optional: true

  '@rollup/rollup-android-arm-eabi@4.60.1':
    resolution: {integrity: sha512-d6FinEBLdIiK+1uACUttJKfgZREXrF0Qc2SmLII7W2AD8FfiZ9Wjd+rD/iRuf5s5dWrr1GgwXCvPqOuDquOowA==}
    cpu: [arm]
    os: [android]

  '@rollup/rollup-android-arm64@4.60.1':
    resolution: {integrity: sha512-YjG/EwIDvvYI1YvYbHvDz/BYHtkY4ygUIXHnTdLhG+hKIQFBiosfWiACWortsKPKU/+dUwQQCKQM3qrDe8c9BA==}
    cpu: [arm64]
    os: [android]

  '@rollup/rollup-darwin-arm64@4.60.1':
    resolution: {integrity: sha512-mjCpF7GmkRtSJwon+Rq1N8+pI+8l7w5g9Z3vWj4T7abguC4Czwi3Yu/pFaLvA3TTeMVjnu3ctigusqWUfjZzvw==}
    cpu: [arm64]
    os: [darwin]

  '@rollup/rollup-darwin-x64@4.60.1':
    resolution: {integrity: sha512-haZ7hJ1JT4e9hqkoT9R/19XW2QKqjfJVv+i5AGg57S+nLk9lQnJ1F/eZloRO3o9Scy9CM3wQ9l+dkXtcBgN5Ew==}
    cpu: [x64]
    os: [darwin]

  '@rollup/rollup-freebsd-arm64@4.60.1':
    resolution: {integrity: sha512-czw90wpQq3ZsAVBlinZjAYTKduOjTywlG7fEeWKUA7oCmpA8xdTkxZZlwNJKWqILlq0wehoZcJYfBvOyhPTQ6w==}
    cpu: [arm64]
    os: [freebsd]

  '@rollup/rollup-freebsd-x64@4.60.1':
    resolution: {integrity: sha512-KVB2rqsxTHuBtfOeySEyzEOB7ltlB/ux38iu2rBQzkjbwRVlkhAGIEDiiYnO2kFOkJp+Z7pUXKyrRRFuFUKt+g==}
    cpu: [x64]
    os: [freebsd]

  '@rollup/rollup-linux-arm-gnueabihf@4.60.1':
    resolution: {integrity: sha512-L+34Qqil+v5uC0zEubW7uByo78WOCIrBvci69E7sFASRl0X7b/MB6Cqd1lky/CtcSVTydWa2WZwFuWexjS5o6g==}
    cpu: [arm]
    os: [linux]

  '@rollup/rollup-linux-arm-musleabihf@4.60.1':
    resolution: {integrity: sha512-n83O8rt4v34hgFzlkb1ycniJh7IR5RCIqt6mz1VRJD6pmhRi0CXdmfnLu9dIUS6buzh60IvACM842Ffb3xd6Gg==}
    cpu: [arm]
    os: [linux]

  '@rollup/rollup-linux-arm64-gnu@4.60.1':
    resolution: {integrity: sha512-Nql7sTeAzhTAja3QXeAI48+/+GjBJ+QmAH13snn0AJSNL50JsDqotyudHyMbO2RbJkskbMbFJfIJKWA6R1LCJQ==}
    cpu: [arm64]
    os: [linux]

  '@rollup/rollup-linux-arm64-musl@4.60.1':
    resolution: {integrity: sha512-+pUymDhd0ys9GcKZPPWlFiZ67sTWV5UU6zOJat02M1+PiuSGDziyRuI/pPue3hoUwm2uGfxdL+trT6Z9rxnlMA==}
    cpu: [arm64]
    os: [linux]

  '@rollup/rollup-linux-loong64-gnu@4.60.1':
    resolution: {integrity: sha512-VSvgvQeIcsEvY4bKDHEDWcpW4Yw7BtlKG1GUT4FzBUlEKQK0rWHYBqQt6Fm2taXS+1bXvJT6kICu5ZwqKCnvlQ==}
    cpu: [loong64]
    os: [linux]

  '@rollup/rollup-linux-loong64-musl@4.60.1':
    resolution: {integrity: sha512-4LqhUomJqwe641gsPp6xLfhqWMbQV04KtPp7/dIp0nzPxAkNY1AbwL5W0MQpcalLYk07vaW9Kp1PBhdpZYYcEw==}
    cpu: [loong64]
    os: [linux]

  '@rollup/rollup-linux-ppc64-gnu@4.60.1':
    resolution: {integrity: sha512-tLQQ9aPvkBxOc/EUT6j3pyeMD6Hb8QF2BTBnCQWP/uu1lhc9AIrIjKnLYMEroIz/JvtGYgI9dF3AxHZNaEH0rw==}
    cpu: [ppc64]
    os: [linux]

  '@rollup/rollup-linux-ppc64-musl@4.60.1':
    resolution: {integrity: sha512-RMxFhJwc9fSXP6PqmAz4cbv3kAyvD1etJFjTx4ONqFP9DkTkXsAMU4v3Vyc5BgzC+anz7nS/9tp4obsKfqkDHg==}
    cpu: [ppc64]
    os: [linux]

  '@rollup/rollup-linux-riscv64-gnu@4.60.1':
    resolution: {integrity: sha512-QKgFl+Yc1eEk6MmOBfRHYF6lTxiiiV3/z/BRrbSiW2I7AFTXoBFvdMEyglohPj//2mZS4hDOqeB0H1ACh3sBbg==}
    cpu: [riscv64]
    os: [linux]

  '@rollup/rollup-linux-riscv64-musl@4.60.1':
    resolution: {integrity: sha512-RAjXjP/8c6ZtzatZcA1RaQr6O1TRhzC+adn8YZDnChliZHviqIjmvFwHcxi4JKPSDAt6Uhf/7vqcBzQJy0PDJg==}
    cpu: [riscv64]
    os: [linux]

  '@rollup/rollup-linux-s390x-gnu@4.60.1':
    resolution: {integrity: sha512-wcuocpaOlaL1COBYiA89O6yfjlp3RwKDeTIA0hM7OpmhR1Bjo9j31G1uQVpDlTvwxGn2nQs65fBFL5UFd76FcQ==}
    cpu: [s390x]
    os: [linux]

  '@rollup/rollup-linux-x64-gnu@4.60.1':
    resolution: {integrity: sha512-77PpsFQUCOiZR9+LQEFg9GClyfkNXj1MP6wRnzYs0EeWbPcHs02AXu4xuUbM1zhwn3wqaizle3AEYg5aeoohhg==}
    cpu: [x64]
    os: [linux]

  '@rollup/rollup-linux-x64-musl@4.60.1':
    resolution: {integrity: sha512-5cIATbk5vynAjqqmyBjlciMJl1+R/CwX9oLk/EyiFXDWd95KpHdrOJT//rnUl4cUcskrd0jCCw3wpZnhIHdD9w==}
    cpu: [x64]
    os: [linux]

  '@rollup/rollup-openbsd-x64@4.60.1':
    resolution: {integrity: sha512-cl0w09WsCi17mcmWqqglez9Gk8isgeWvoUZ3WiJFYSR3zjBQc2J5/ihSjpl+VLjPqjQ/1hJRcqBfLjssREQILw==}
    cpu: [x64]
    os: [openbsd]

  '@rollup/rollup-openharmony-arm64@4.60.1':
    resolution: {integrity: sha512-4Cv23ZrONRbNtbZa37mLSueXUCtN7MXccChtKpUnQNgF010rjrjfHx3QxkS2PI7LqGT5xXyYs1a7LbzAwT0iCA==}
    cpu: [arm64]
    os: [openharmony]

  '@rollup/rollup-win32-arm64-msvc@4.60.1':
    resolution: {integrity: sha512-i1okWYkA4FJICtr7KpYzFpRTHgy5jdDbZiWfvny21iIKky5YExiDXP+zbXzm3dUcFpkEeYNHgQ5fuG236JPq0g==}
    cpu: [arm64]
    os: [win32]

  '@rollup/rollup-win32-ia32-msvc@4.60.1':
    resolution: {integrity: sha512-u09m3CuwLzShA0EYKMNiFgcjjzwqtUMLmuCJLeZWjjOYA3IT2Di09KaxGBTP9xVztWyIWjVdsB2E9goMjZvTQg==}
    cpu: [ia32]
    os: [win32]

  '@rollup/rollup-win32-x64-gnu@4.60.1':
    resolution: {integrity: sha512-k+600V9Zl1CM7eZxJgMyTUzmrmhB/0XZnF4pRypKAlAgxmedUA+1v9R+XOFv56W4SlHEzfeMtzujLJD22Uz5zg==}
    cpu: [x64]
    os: [win32]

  '@rollup/rollup-win32-x64-msvc@4.60.1':
    resolution: {integrity: sha512-lWMnixq/QzxyhTV6NjQJ4SFo1J6PvOX8vUx5Wb4bBPsEb+8xZ89Bz6kOXpfXj9ak9AHTQVQzlgzBEc1SyM27xQ==}
    cpu: [x64]
    os: [win32]

  '@semantos/core@file:':
    resolution: {directory: '', type: directory}
    engines: {node: '>=18.0.0'}
    peerDependencies:
      '@bsv/sdk': ^2.0.0

  '@sinclair/typebox@0.27.10':
    resolution: {integrity: sha512-MTBk/3jGLNB2tVxv6uLlFh1iu64iYOQ2PbdOSK3NW8JZsmlaOh2q6sdtKowBhfw8QFLmYNzTW4/oK4uATIi6ZA==}

  '@sqlite.org/sqlite-wasm@3.53.0-build1':
    resolution: {integrity: sha512-PfWPWN2n+/37doa8oh2/oUXk4OOsRYZsxc1W1sDXIGb/Pu5Yrb+f2eyYpgQMGITVX7HVgxhs9P18Rc6I97ym/g==}
    engines: {node: '>=22'}

  '@stablelib/base64@1.0.1':
    resolution: {integrity: sha512-1bnPQqSxSuc3Ii6MhBysoWCg58j97aUjuCSZrGSmDxNqtytIi0k8utUenAwTZN4V5mXXYGsVUI9zeBqy+jBOSQ==}

  '@sveltejs/acorn-typescript@1.0.9':
    resolution: {integrity: sha512-lVJX6qEgs/4DOcRTpo56tmKzVPtoWAaVbL4hfO7t7NVwl9AAXzQR6cihesW1BmNMPl+bK6dreu2sOKBP2Q9CIA==}
    peerDependencies:
      acorn: ^8.9.0

  '@sveltejs/vite-plugin-svelte-inspector@3.0.1':
    resolution: {integrity: sha512-2CKypmj1sM4GE7HjllT7UKmo4Q6L5xFRd7VMGEWhYnZ+wc6AUVU01IBd7yUi6WnFndEwWoMNOd6e8UjoN0nbvQ==}
    engines: {node: ^18.0.0 || ^20.0.0 || >=22}
    peerDependencies:
      '@sveltejs/vite-plugin-svelte': ^4.0.0-next.0||^4.0.0
      svelte: ^5.0.0-next.96 || ^5.0.0
      vite: ^5.0.0

  '@sveltejs/vite-plugin-svelte-inspector@4.0.1':
    resolution: {integrity: sha512-J/Nmb2Q2y7mck2hyCX4ckVHcR5tu2J+MtBEQqpDrrgELZ2uvraQcK/ioCV61AqkdXFgriksOKIceDcQmqnGhVw==}
    engines: {node: ^18.0.0 || ^20.0.0 || >=22}
    peerDependencies:
      '@sveltejs/vite-plugin-svelte': ^5.0.0
      svelte: ^5.0.0
      vite: ^6.0.0

  '@sveltejs/vite-plugin-svelte@4.0.4':
    resolution: {integrity: sha512-0ba1RQ/PHen5FGpdSrW7Y3fAMQjrXantECALeOiOdBdzR5+5vPP6HVZRLmZaQL+W8m++o+haIAKq5qT+MiZ7VA==}
    engines: {node: ^18.0.0 || ^20.0.0 || >=22}
    peerDependencies:
      svelte: ^5.0.0-next.96 || ^5.0.0
      vite: ^5.0.0

  '@sveltejs/vite-plugin-svelte@5.1.1':
    resolution: {integrity: sha512-Y1Cs7hhTc+a5E9Va/xwKlAJoariQyHY+5zBgCZg4PFWNYQ1nMN9sjK1zhw1gK69DuqVP++sht/1GZg1aRwmAXQ==}
    engines: {node: ^18.0.0 || ^20.0.0 || >=22}
    peerDependencies:
      svelte: ^5.0.0
      vite: ^6.0.0

  '@testing-library/dom@10.4.1':
    resolution: {integrity: sha512-o4PXJQidqJl82ckFaXUeoAW+XysPLauYI43Abki5hABd853iMhitooc6znOnczgbTYmEP6U6/y1ZyKAIsvMKGg==}
    engines: {node: '>=18'}

  '@testing-library/jest-dom@6.9.1':
    resolution: {integrity: sha512-zIcONa+hVtVSSep9UT3jZ5rizo2BsxgyDYU7WFD5eICBE7no3881HGeb/QkGfsJs6JTkY1aQhT7rIPC7e+0nnA==}
    engines: {node: '>=14', npm: '>=6', yarn: '>=1'}

  '@testing-library/react@16.3.2':
    resolution: {integrity: sha512-XU5/SytQM+ykqMnAnvB2umaJNIOsLF3PVv//1Ew4CTcpz0/BRyy/af40qqrt7SjKpDdT1saBMc42CUok5gaw+g==}
    engines: {node: '>=18'}
    peerDependencies:
      '@testing-library/dom': ^10.0.0
      '@types/react': ^18.0.0 || ^19.0.0
      '@types/react-dom': ^18.0.0 || ^19.0.0
      react: ^18.0.0 || ^19.0.0
      react-dom: ^18.0.0 || ^19.0.0
    peerDependenciesMeta:
      '@types/react':
        optional: true
      '@types/react-dom':
        optional: true

  '@ts-morph/common@0.29.0':
    resolution: {integrity: sha512-35oUmphHbJvQ/+UTwFNme/t2p3FoKiGJ5auTjjpNTop2dyREspirjMy82PLSC1pnDJ8ah1GU98hwpVt64YXQsg==}

  '@tsconfig/svelte@5.0.8':
    resolution: {integrity: sha512-UkNnw1/oFEfecR8ypyHIQuWYdkPvHiwcQ78sh+ymIiYoF+uc5H1UBetbjyqT+vgGJ3qQN6nhucJviX6HesWtKQ==}

  '@tweenjs/tween.js@23.1.3':
    resolution: {integrity: sha512-vJmvvwFxYuGnF2axRtPYocag6Clbb5YS7kLL+SO/TeVFzHqDIWrNKYtcsPMibjDx9O+bu+psAy9NKfWklassUA==}

  '@types/aria-query@5.0.4':
    resolution: {integrity: sha512-rfT93uj5s0PRL7EzccGMs3brplhcrghnDoV26NqKhCAS1hVo+WdNsPvE/yb6ilfr5hi2MEk6d5EWJTKdxg8jVw==}

  '@types/babel__core@7.20.5':
    resolution: {integrity: sha512-qoQprZvz5wQFJwMDqeseRXWv3rqMvhgpbXFfVyWhbx9X47POIA6i/+dXefEmZKoAgOaTdaIgNSMqMIU61yRyzA==}

  '@types/babel__generator@7.27.0':
    resolution: {integrity: sha512-ufFd2Xi92OAVPYsy+P4n7/U7e68fex0+Ee8gSG9KX7eo084CWiQ4sdxktvdl0bOPupXtVJPY19zk6EwWqUQ8lg==}

  '@types/babel__template@7.4.4':
    resolution: {integrity: sha512-h/NUaSyG5EyxBIp8YRxo4RMe2/qQgvyowRwVMzhYhBCONbW8PUsg4lkFMrhgZhUe5z3L3MiLDuvyJ/CaPa2A8A==}

  '@types/babel__traverse@7.28.0':
    resolution: {integrity: sha512-8PvcXf70gTDZBgt9ptxJ8elBeBjcLOAcOtoO/mPJjtji1+CdGbHgm77om1GrsPxsiE+uXIpNSK64UYaIwQXd4Q==}

  '@types/body-parser@1.19.6':
    resolution: {integrity: sha512-HLFeCYgz89uk22N5Qg3dvGvsv46B8GLvKKo1zKG4NybA8U2DiEO3w9lqGg29t/tfLRJpJ6iQxnVw4OnB7MoM9g==}

  '@types/chai@5.2.3':
    resolution: {integrity: sha512-Mw558oeA9fFbv65/y4mHtXDs9bPnFMZAL/jxdPFUpOHHIXX91mcgEHbS5Lahr+pwZFR8A7GQleRWeI6cGFC2UA==}

  '@types/connect@3.4.38':
    resolution: {integrity: sha512-K6uROf1LD88uDQqJCktA4yzL1YYAK6NgfsI0v/mTgyPKWsX1CnJ0XPSDhViejru1GcRkLWb8RlzFYJRqGUbaug==}

  '@types/cors@2.8.19':
    resolution: {integrity: sha512-mFNylyeyqN93lfe/9CSxOGREz8cpzAhH+E93xJ4xWQf62V8sQ/24reV2nyzUWM6H6Xji+GGHpkbLe7pVoUEskg==}

  '@types/d3-force@3.0.10':
    resolution: {integrity: sha512-ZYeSaCF3p73RdOKcjj+swRlZfnYpK1EbaDiYICEEp5Q6sUiqFaFQ9qgoshp5CzIyyb/yD09kD9o2zEltCexlgw==}

  '@types/d3-scale@4.0.9':
    resolution: {integrity: sha512-dLmtwB8zkAeO/juAMfnV+sItKjlsw2lKdZVVy6LRr0cBmegxSABiLEpGVmSJJ8O08i4+sGR6qQtb6WtuwJdvVw==}

  '@types/d3-time@3.0.4':
    resolution: {integrity: sha512-yuzZug1nkAAaBlBBikKZTgzCeA+k1uy4ZFwWANOfKw5z5LRhV0gNA7gNkKm7HoK+HRN0wX3EkxGk0fpbWhmB7g==}

  '@types/deep-eql@4.0.2':
    resolution: {integrity: sha512-c9h9dVVMigMPc4bwTvC5dxqtqJZwQPePsWjPlpSOnojbor6pGqdk541lfA7AqFQr5pB1BRdq0juY9db81BwyFw==}

  '@types/estree@1.0.8':
    resolution: {integrity: sha512-dWHzHa2WqEXI/O1E9OjrocMTKJl2mSrEolh1Iomrv6U+JuNwaHXsXx9bLu5gG7BUWFIN0skIQJQ/L1rIex4X6w==}

  '@types/express-serve-static-core@4.19.8':
    resolution: {integrity: sha512-02S5fmqeoKzVZCHPZid4b8JH2eM5HzQLZWN2FohQEy/0eXTq8VXZfSN6Pcr3F6N9R/vNrj7cpgbhjie6m/1tCA==}

  '@types/express@4.17.25':
    resolution: {integrity: sha512-dVd04UKsfpINUnK0yBoYHDF3xu7xVH4BuDotC/xGuycx4CgbP48X/KF/586bcObxT0HENHXEU8Nqtu6NR+eKhw==}

  '@types/http-errors@2.0.5':
    resolution: {integrity: sha512-r8Tayk8HJnX0FztbZN7oVqGccWgw98T/0neJphO91KkmOzug1KkofZURD4UaD5uH8AqcFLfdPErnBod0u71/qg==}

  '@types/mime@1.3.5':
    resolution: {integrity: sha512-/pyBZWSLD2n0dcHE3hq8s8ZvcETHtEuF+3E7XVt0Ig2nvsVQXdghHVcEkIWjy9A0wKfTn97a/PSDYohKIlnP/w==}

  '@types/node-fetch@2.6.13':
    resolution: {integrity: sha512-QGpRVpzSaUs30JBSGPjOg4Uveu384erbHBoT1zeONvyCfwQxIkUshLAOqN/k9EjGviPRmWTTe6aH2qySWKTVSw==}

  '@types/node@12.20.55':
    resolution: {integrity: sha512-J8xLz7q2OFulZ2cyGTLE1TbbZcjpno7FaN6zdJNrgAdrJ+DZzh/uFR6YrTb4C+nXakvud8Q4+rbhoIWlYQbUFQ==}

  '@types/node@18.19.130':
    resolution: {integrity: sha512-GRaXQx6jGfL8sKfaIDD6OupbIHBr9jv7Jnaml9tB7l4v068PAOXqfcujMMo5PhbIs6ggR1XODELqahT2R8v0fg==}

  '@types/node@20.19.39':
    resolution: {integrity: sha512-orrrD74MBUyK8jOAD/r0+lfa1I2MO6I+vAkmAWzMYbCcgrN4lCrmK52gRFQq/JRxfYPfonkr4b0jcY7Olqdqbw==}

  '@types/phoenix@1.6.7':
    resolution: {integrity: sha512-oN9ive//QSBkf19rfDv45M7eZPi0eEXylht2OLEXicu5b4KoQ1OzXIw+xDSGWxSxe1JmepRR/ZH283vsu518/Q==}

  '@types/qs@6.15.0':
    resolution: {integrity: sha512-JawvT8iBVWpzTrz3EGw9BTQFg3BQNmwERdKE22vlTxawwtbyUSlMppvZYKLZzB5zgACXdXxbD3m1bXaMqP/9ow==}

  '@types/range-parser@1.2.7':
    resolution: {integrity: sha512-hKormJbkJqzQGhziax5PItDUTMAM9uE2XXQmM37dyd4hVM+5aVl7oVxMVUiVQn2oCQFN/LKCZdvSM0pFRqbSmQ==}

  '@types/react-dom@19.2.3':
    resolution: {integrity: sha512-jp2L/eY6fn+KgVVQAOqYItbF0VY/YApe5Mz2F0aykSO8gx31bYCZyvSeYxCHKvzHG5eZjc+zyaS5BrBWya2+kQ==}
    peerDependencies:
      '@types/react': ^19.2.0

  '@types/react@19.2.14':
    resolution: {integrity: sha512-ilcTH/UniCkMdtexkoCN0bI7pMcJDvmQFPvuPvmEaYA/NSfFTAgdUSLAoVjaRJm7+6PvcM+q1zYOwS4wTYMF9w==}

  '@types/send@0.17.6':
    resolution: {integrity: sha512-Uqt8rPBE8SY0RK8JB1EzVOIZ32uqy8HwdxCnoCOsYrvnswqmFZ/k+9Ikidlk/ImhsdvBsloHbAlewb2IEBV/Og==}

  '@types/send@1.2.1':
    resolution: {integrity: sha512-arsCikDvlU99zl1g69TcAB3mzZPpxgw0UQnaHeC1Nwb015xp8bknZv5rIfri9xTOcMuaVgvabfIRA7PSZVuZIQ==}

  '@types/serve-static@1.15.10':
    resolution: {integrity: sha512-tRs1dB+g8Itk72rlSI2ZrW6vZg0YrLI81iQSTkMmOqnqCaNr/8Ek4VwWcN5vZgCYWbg/JJSGBlUaYGAOP73qBw==}

  '@types/stats.js@0.17.4':
    resolution: {integrity: sha512-jIBvWWShCvlBqBNIZt0KAshWpvSjhkwkEu4ZUcASoAvhmrgAUI2t1dXrjSL4xXVLB4FznPrIsX3nKXFl/Dt4vA==}

  '@types/three@0.165.0':
    resolution: {integrity: sha512-AJK8JZAFNBF0kBXiAIl5pggYlzAGGA8geVYQXAcPCEDRbyA+oEjkpUBcJJrtNz6IiALwzGexFJGZG2yV3WsYBw==}

  '@types/trusted-types@2.0.7':
    resolution: {integrity: sha512-ScaPdn1dQczgbl0QFTeTOmVHFULt394XJgOQNoyVhZ6r2vLnMLJfBPd53SB52T/3G36VI1/g2MZaX0cwDuXsfw==}

  '@types/webxr@0.5.24':
    resolution: {integrity: sha512-h8fgEd/DpoS9CBrjEQXR+dIDraopAEfu4wYVNY2tEPwk60stPWhvZMf4Foo5FakuQ7HFZoa8WceaWFervK2Ovg==}

  '@types/ws@8.18.1':
    resolution: {integrity: sha512-ThVF6DCVhA8kUGy+aazFQ4kXQ7E1Ty7A3ypFOe0IcJV8O/M511G99AW24irKrW56Wt44yG9+ij8FaqoBGkuBXg==}

  '@vitejs/plugin-react@4.7.0':
    resolution: {integrity: sha512-gUu9hwfWvvEDBBmgtAowQCojwZmJ5mcLn3aufeCsitijs3+f2NsrPtlAWIR6OPiqljl96GVCUbLe0HyqIpVaoA==}
    engines: {node: ^14.18.0 || >=16.0.0}
    peerDependencies:
      vite: ^4.2.0 || ^5.0.0 || ^6.0.0 || ^7.0.0

  '@vitest/expect@1.6.1':
    resolution: {integrity: sha512-jXL+9+ZNIJKruofqXuuTClf44eSpcHlgj3CiuNihUF3Ioujtmc0zIa3UJOW5RjDK1YLBJZnWBlPuqhYycLioog==}

  '@vitest/expect@3.2.4':
    resolution: {integrity: sha512-Io0yyORnB6sikFlt8QW5K7slY4OjqNX9jmJQ02QDda8lyM6B5oNgVWoSoKPac8/kgnCUzuHQKrSLtu/uOqqrig==}

  '@vitest/mocker@3.2.4':
    resolution: {integrity: sha512-46ryTE9RZO/rfDd7pEqFl7etuyzekzEhUbTW3BvmeO/BcCMEgq59BKhek3dXDWgAj4oMK6OZi+vRr1wPW6qjEQ==}
    peerDependencies:
      msw: ^2.4.9
      vite: ^5.0.0 || ^6.0.0 || ^7.0.0-0
    peerDependenciesMeta:
      msw:
        optional: true
      vite:
        optional: true

  '@vitest/pretty-format@3.2.4':
    resolution: {integrity: sha512-IVNZik8IVRJRTr9fxlitMKeJeXFFFN0JaB9PHPGQ8NKQbGpfjlTx9zO4RefN8gp7eqjNy8nyK3NZmBzOPeIxtA==}

  '@vitest/runner@1.6.1':
    resolution: {integrity: sha512-3nSnYXkVkf3mXFfE7vVyPmi3Sazhb/2cfZGGs0JRzFsPFvAMBEcrweV1V1GsrstdXeKCTXlJbvnQwGWgEIHmOA==}

  '@vitest/runner@3.2.4':
    resolution: {integrity: sha512-oukfKT9Mk41LreEW09vt45f8wx7DordoWUZMYdY/cyAk7w5TWkTRCNZYF7sX7n2wB7jyGAl74OxgwhPgKaqDMQ==}

  '@vitest/snapshot@1.6.1':
    resolution: {integrity: sha512-WvidQuWAzU2p95u8GAKlRMqMyN1yOJkGHnx3M1PL9Raf7AQ1kwLKg04ADlCa3+OXUZE7BceOhVZiuWAbzCKcUQ==}

  '@vitest/snapshot@3.2.4':
    resolution: {integrity: sha512-dEYtS7qQP2CjU27QBC5oUOxLE/v5eLkGqPE0ZKEIDGMs4vKWe7IjgLOeauHsR0D5YuuycGRO5oSRXnwnmA78fQ==}

  '@vitest/spy@1.6.1':
    resolution: {integrity: sha512-MGcMmpGkZebsMZhbQKkAf9CX5zGvjkBTqf8Zx3ApYWXr3wG+QvEu2eXWfnIIWYSJExIp4V9FCKDEeygzkYrXMw==}

  '@vitest/spy@3.2.4':
    resolution: {integrity: sha512-vAfasCOe6AIK70iP5UD11Ac4siNUNJ9i/9PZ3NKx07sG6sUxeag1LWdNrMWeKKYBLlzuK+Gn65Yd5nyL6ds+nw==}

  '@vitest/utils@1.6.1':
    resolution: {integrity: sha512-jOrrUvXM4Av9ZWiG1EajNto0u96kWAhJ1LmPmJhXXQx/32MecEKd10pOLYgS2BQx1TgkGhloPU1ArDW2vvaY6g==}

  '@vitest/utils@3.2.4':
    resolution: {integrity: sha512-fB2V0JFrQSMsCo9HiSq3Ezpdv4iYaXRG1Sx8edX3MwxfyNn83mKiGzOcH+Fkxt4MHxr3y42fQi1oeAInqgX2QA==}

  abort-controller@3.0.0:
    resolution: {integrity: sha512-h8lQ8tacZYnR3vNQTgibj+tODHI5/+l06Au2Pcriv/Gmet0eaj4TwWH41sO9wnHDiQsEj19q0drzdWdeAHtweg==}
    engines: {node: '>=6.5'}

  accepts@1.3.8:
    resolution: {integrity: sha512-PYAthTa2m2VKxuvSD3DPC/Gy+U+sOA1LAuT8mkmRuvw+NACSaeXEQ+NHcVF7rONl6qcaxV3Uuemwawk+7+SJLw==}
    engines: {node: '>= 0.6'}

  acorn-walk@8.3.5:
    resolution: {integrity: sha512-HEHNfbars9v4pgpW6SO1KSPkfoS0xVOM/9UzkJltjlsHZmJasxg8aXkuZa7SMf8vKGIBhpUsPluQSqhJFCqebw==}
    engines: {node: '>=0.4.0'}

  acorn@8.16.0:
    resolution: {integrity: sha512-UVJyE9MttOsBQIDKw1skb9nAwQuR5wuGD3+82K6JgJlm/Y+KI92oNsMNGZCYdDsVtRHSak0pcV5Dno5+4jh9sw==}
    engines: {node: '>=0.4.0'}
    hasBin: true

  agent-base@7.1.4:
    resolution: {integrity: sha512-MnA+YT8fwfJPgBx3m60MNqakm30XOkyIoH1y6huTQvC0PwZG7ki8NacLBcrPbNoo8vEZy7Jpuk7+jMO+CUovTQ==}
    engines: {node: '>= 14'}

  agentkeepalive@4.6.0:
    resolution: {integrity: sha512-kja8j7PjmncONqaTsB8fQ+wE2mSU2DJ9D4XKoJ5PFWIdRMa6SLSN1ff4mOr4jCbfRSsxR4keIiySJU0N9T5hIQ==}
    engines: {node: '>= 8.0.0'}

  ansi-colors@4.1.3:
    resolution: {integrity: sha512-/6w/C21Pm1A7aZitlI5Ni/2J6FFQN8i1Cvz3kHABAAbw93v/NlvKdVOqz7CCWz/3iv/JplRSEEZ83XION15ovw==}
    engines: {node: '>=6'}

  ansi-regex@5.0.1:
    resolution: {integrity: sha512-quJQXlTSUGL2LH9SUXo8VwsY4soanhgo6LNSm84E1LBcE8s3O0wpdiRzyR9z/ZZJMlMWv37qOOb9pdJlMUEKFQ==}
    engines: {node: '>=8'}

  ansi-styles@5.2.0:
    resolution: {integrity: sha512-Cxwpt2SfTzTtXcfOlzGEee8O+c+MmUgGrNiBcXnuWxuFJHe6a5Hz7qwhwe5OgaSYI0IJvkLqWX1ASG+cJOkEiA==}
    engines: {node: '>=10'}

  any-promise@1.3.0:
    resolution: {integrity: sha512-7UvmKalWRt1wgjL1RrGxoSJW/0QZFIegpeGvZG9kjp8vrRu55XTHbwnqq2GpXm9uLbcuhxm3IqX9OB4MZR1b2A==}

  anymatch@3.1.3:
    resolution: {integrity: sha512-KMReFUr0B4t+D+OBkjR3KYqvocp2XaSzO55UcB6mgQMd3KbcE+mWTyvVV7D/zsdEbNnV6acZUutkiHQXvTr1Rw==}
    engines: {node: '>= 8'}

  arg@5.0.2:
    resolution: {integrity: sha512-PYjyFOLKQ9y57JvQ6QLo8dAgNqswh8M1RMJYdQduT6xbWSgK36P/Z/v+p888pM69jMMfS8Xd8F6I1kQ/I9HUGg==}

  argparse@1.0.10:
    resolution: {integrity: sha512-o5Roy6tNG4SL/FOkCAN6RzjiakZS25RLYFrcMttJqbdd8BWrnA+fGz57iN5Pb06pvBGvl5gQ0B48dJlslXvoTg==}

  argparse@2.0.1:
    resolution: {integrity: sha512-8+9WqebbFzpX9OR+Wa6O29asIogeRMzcGtAINdpMHHyAg10f05aSFVBbcEqGf/PXw1EjAZ+q2/bEBg3DvurK3Q==}

  aria-query@5.3.0:
    resolution: {integrity: sha512-b0P0sZPKtyu8HkeRAfCq0IfURZK+SuwMjY1UXGBU27wpAiTwQAIlq56IbIO+ytk/JjS1fMR14ee5WBBfKi5J6A==}

  aria-query@5.3.1:
    resolution: {integrity: sha512-Z/ZeOgVl7bcSYZ/u/rh0fOpvEpq//LZmdbkXyc7syVzjPAhfOa9ebsdTSjEBDU4vs5nC98Kfduj1uFo0qyET3g==}
    engines: {node: '>= 0.4'}

  aria-query@5.3.2:
    resolution: {integrity: sha512-COROpnaoap1E2F000S62r6A60uHZnmlvomhfyT2DlTcrY1OrBKn2UhH7qn5wTC9zMvD0AY7csdPSNwKP+7WiQw==}
    engines: {node: '>= 0.4'}

  array-flatten@1.1.1:
    resolution: {integrity: sha512-PCVAQswWemu6UdxsDFFX/+gVeYqKAod3D3UVm91jHwynguOwAvYPhx8nNlM++NqRcK6CxxpUafjmhIdKiHibqg==}

  array-union@2.1.0:
    resolution: {integrity: sha512-HGyxoOTYUyCM6stUe6EJgnd4EoewAI7zMdfqO+kGjnlZmBDz/cR5pf8r/cR4Wq60sL/p0IkcjUEEPwS3GFrIyw==}
    engines: {node: '>=8'}

  asn1.js@4.10.1:
    resolution: {integrity: sha512-p32cOF5q0Zqs9uBiONKYLm6BClCoBCM5O9JfeUSlnQLBTxYdTK+pW+nXflm8UkKd2UYlEbYz5qEi0JuZR9ckSw==}

  assert@2.1.0:
    resolution: {integrity: sha512-eLHpSK/Y4nhMJ07gDaAzoX/XAKS8PSaojml3M0DM4JpV1LAi5JOJ/p6H/XWrl8L+DzVEvVCW1z3vWAaB9oTsQw==}

  assertion-error@1.1.0:
    resolution: {integrity: sha512-jgsaNduz+ndvGyFt3uSuWqvy4lCnIJiovtouQN5JZHOKCS2QuhEdbcQHFhVksz2N2U9hXJo8odG7ETyWlEeuDw==}

  assertion-error@2.0.1:
    resolution: {integrity: sha512-Izi8RQcffqCeNVgFigKli1ssklIbpHnCYc6AknXGYoB6grJqyeby7jv12JUQgmTAnIDnbck1uxksT4dzN3PWBA==}
    engines: {node: '>=12'}

  asynckit@0.4.0:
    resolution: {integrity: sha512-Oei9OH4tRh0YqU3GxhX79dM/mwVgvbZJaSNaRk+bshkj0S5cfHcgYakreBjrHwatXKbz+IoIdYLxrKim2MjW0Q==}

  autoprefixer@10.4.27:
    resolution: {integrity: sha512-NP9APE+tO+LuJGn7/9+cohklunJsXWiaWEfV3si4Gi/XHDwVNgkwr1J3RQYFIvPy76GmJ9/bW8vyoU1LcxwKHA==}
    engines: {node: ^10 || ^12 || >=14}
    hasBin: true
    peerDependencies:
      postcss: ^8.1.0

  available-typed-arrays@1.0.7:
    resolution: {integrity: sha512-wvUjBtSGN7+7SjNpq/9M2Tg350UZD3q62IFZLbRAR1bSMlCo1ZaeW+BJ+D090e4hIIZLBcTDWe4Mh4jvUDajzQ==}
    engines: {node: '>= 0.4'}

  axobject-query@4.1.0:
    resolution: {integrity: sha512-qIj0G9wZbMGNLjLmg1PT6v2mE9AH2zlnADJD/2tC6E00hgmhUOfEB6greHPAfLRSufHqROIUTkw6E+M3lH0PTQ==}
    engines: {node: '>= 0.4'}

  balanced-match@4.0.4:
    resolution: {integrity: sha512-BLrgEcRTwX2o6gGxGOCNyMvGSp35YofuYzw9h1IMTRmKqttAZZVU67bdb9Pr2vUHA8+j3i2tJfjO6C6+4myGTA==}
    engines: {node: 18 || 20 || >=22}

  base64-js@1.5.1:
    resolution: {integrity: sha512-AKpaYlHn8t4SVbOHCy+b5+KKgvR4vrsD8vbvrbiQJps7fKDTkjkDry6ji0rUJjC0kzbNePLwzxq8iypo41qeWA==}

  baseline-browser-mapping@2.10.18:
    resolution: {integrity: sha512-VSnGQAOLtP5mib/DPyg2/t+Tlv65NTBz83BJBJvmLVHHuKJVaDOBvJJykiT5TR++em5nfAySPccDZDa4oSrn8A==}
    engines: {node: '>=6.0.0'}
    hasBin: true

  better-path-resolve@1.0.0:
    resolution: {integrity: sha512-pbnl5XzGBdrFU/wT4jqmJVPn2B6UHPBOhzMQkY/SPUPB6QtUXtmBHBIwCbXJol93mOpGMnQyP/+BB19q04xj7g==}
    engines: {node: '>=4'}

  binary-extensions@2.3.0:
    resolution: {integrity: sha512-Ceh+7ox5qe7LJuLHoY0feh3pHuUDHAcRUeyL2VYghZwfpkNIy/+8Ocg0a3UuSoYzavmylwuLWQOf3hl0jjMMIw==}
    engines: {node: '>=8'}

  bitecs@0.4.0:
    resolution: {integrity: sha512-ho6Zop/L79DRTnBAfakPpGPuX7y0+lAjX06CpaAW+5tnAc7BH3L3RlSrWAXAqwnQGDZ10GsoxaxyTTsddlun3g==}

  bn.js@4.12.3:
    resolution: {integrity: sha512-fGTi3gxV/23FTYdAoUtLYp6qySe2KE3teyZitipKNRuVYcBkoP/bB3guXN/XVKUe9mxCHXnc9C4ocyz8OmgN0g==}

  bn.js@5.2.3:
    resolution: {integrity: sha512-EAcmnPkxpntVL+DS7bO1zhcZNvCkxqtkd0ZY53h06GNQ3DEkkGZ/gKgmDv6DdZQGj9BgfSPKtJJ7Dp1GPP8f7w==}

  body-parser@1.20.4:
    resolution: {integrity: sha512-ZTgYYLMOXY9qKU/57FAo8F+HA2dGX7bqGc71txDRC1rS4frdFI5R7NhluHxH6M0YItAP0sHB4uqAOcYKxO6uGA==}
    engines: {node: '>= 0.8', npm: 1.2.8000 || >= 1.4.16}

  brace-expansion@5.0.5:
    resolution: {integrity: sha512-VZznLgtwhn+Mact9tfiwx64fA9erHH/MCXEUfB/0bX/6Fz6ny5EGTXYltMocqg4xFAQZtnO3DHWWXi8RiuN7cQ==}
    engines: {node: 18 || 20 || >=22}

  braces@3.0.3:
    resolution: {integrity: sha512-yQbXgO/OSZVD2IsiLlro+7Hf6Q18EJrKSEsdoMzKePKXct3gvD8oLcOQdIzGupr5Fj+EDe8gO/lxc1BzfMpxvA==}
    engines: {node: '>=8'}

  brorand@1.1.0:
    resolution: {integrity: sha512-cKV8tMCEpQs4hK/ik71d6LrPOnpkpGBR0wzxqr68g2m/LB2GxVYQroAjMJZRVM1Y4BCjCKc3vAamxSzOY2RP+w==}

  browser-resolve@2.0.0:
    resolution: {integrity: sha512-7sWsQlYL2rGLy2IWm8WL8DCTJvYLc/qlOnsakDac87SOoCd16WLsaAMdCiAqsTNHIe+SXfaqyxyo6THoWqs8WQ==}

  browserify-aes@1.2.0:
    resolution: {integrity: sha512-+7CHXqGuspUn/Sl5aO7Ea0xWGAtETPXNSAjHo48JfLdPWcMng33Xe4znFvQweqc/uzk5zSOI3H52CYnjCfb5hA==}

  browserify-cipher@1.0.1:
    resolution: {integrity: sha512-sPhkz0ARKbf4rRQt2hTpAHqn47X3llLkUGn+xEJzLjwY8LRs2p0v7ljvI5EyoRO/mexrNunNECisZs+gw2zz1w==}

  browserify-des@1.0.2:
    resolution: {integrity: sha512-BioO1xf3hFwz4kc6iBhI3ieDFompMhrMlnDFC4/0/vd5MokpuAc3R+LYbwTA9A5Yc9pq9UYPqffKpW2ObuwX5A==}

  browserify-rsa@4.1.1:
    resolution: {integrity: sha512-YBjSAiTqM04ZVei6sXighu679a3SqWORA3qZTEqZImnlkDIFtKc6pNutpjyZ8RJTjQtuYfeetkxM11GwoYXMIQ==}
    engines: {node: '>= 0.10'}

  browserify-sign@4.2.5:
    resolution: {integrity: sha512-C2AUdAJg6rlM2W5QMp2Q4KGQMVBwR1lIimTsUnutJ8bMpW5B52pGpR2gEnNBNwijumDo5FojQ0L9JrXA8m4YEw==}
    engines: {node: '>= 0.10'}

  browserify-zlib@0.2.0:
    resolution: {integrity: sha512-Z942RysHXmJrhqk88FmKBVq/v5tqmSkDz7p54G/MGyjMnCFFnC79XWNbg+Vta8W6Wb2qtSZTSxIGkJrRpCFEiA==}

  browserslist@4.28.2:
    resolution: {integrity: sha512-48xSriZYYg+8qXna9kwqjIVzuQxi+KYWp2+5nCYnYKPTr0LvD89Jqk2Or5ogxz0NUMfIjhh2lIUX/LyX9B4oIg==}
    engines: {node: ^6 || ^7 || ^8 || ^9 || ^10 || ^11 || ^12 || >=13.7}
    hasBin: true

  buffer-from@1.1.2:
    resolution: {integrity: sha512-E+XQCRwSbaaiChtv6k6Dwgc+bx+Bs6vuKJHHl5kox/BaKbhiXzqQOwK4cO22yElGp2OCmjwVhT3HmxgyPGnJfQ==}

  buffer-xor@1.0.3:
    resolution: {integrity: sha512-571s0T7nZWK6vB67HI5dyUF7wXiNcfaPPPTl6zYCNApANjIvYJTg7hlud/+cJpdAhS7dVzqMLmfhfHR3rAcOjQ==}

  buffer@5.7.1:
    resolution: {integrity: sha512-EHcyIPBQ4BSGlvjB16k5KgAJ27CIsHY/2JBmCRReo48y9rQ3MaUzWX3KVlBa4U7MyX02HdVj0K7C3WaB3ju7FQ==}

  builtin-status-codes@3.0.0:
    resolution: {integrity: sha512-HpGFw18DgFWlncDfjTa2rcQ4W88O1mC8e8yZ2AvQY5KDaktSTwo+KRf6nHK6FRI5FyRyb/5T6+TSxfP7QyGsmQ==}

  bun-types@1.3.13:
    resolution: {integrity: sha512-QXKeHLlOLqQX9LgYaHJfzdBaV21T63HhFJnvuRCcjZiaUDpbs5ED1MgxbMra71CsryN/1dAoXuJJJwIv/2drVA==}

  bytes@3.1.2:
    resolution: {integrity: sha512-/Nf7TyzTx6S3yRJObOAV7956r8cr2+Oj8AC5dt8wSP3BQAoeX58NoHyCU8P8zGkNXStjTSi6fzO6F0pBdcYbEg==}
    engines: {node: '>= 0.8'}

  cac@6.7.14:
    resolution: {integrity: sha512-b6Ilus+c3RrdDk+JhLKUAQfzzgLEPy6wcXqS7f/xe1EETvsDP6GORG7SFuOs6cID5YkqchW/LXZbX5bc8j7ZcQ==}
    engines: {node: '>=8'}

  call-bind-apply-helpers@1.0.2:
    resolution: {integrity: sha512-Sp1ablJ0ivDkSzjcaJdxEunN5/XvksFJ2sMBFfq6x0ryhQV/2b/KwFe21cMpmHtPOSij8K99/wSfoEuTObmuMQ==}
    engines: {node: '>= 0.4'}

  call-bind@1.0.9:
    resolution: {integrity: sha512-a/hy+pNsFUTR+Iz8TCJvXudKVLAnz/DyeSUo10I5yvFDQJBFU2s9uqQpoSrJlroHUKoKqzg+epxyP9lqFdzfBQ==}
    engines: {node: '>= 0.4'}

  call-bound@1.0.4:
    resolution: {integrity: sha512-+ys997U96po4Kx/ABpBCqhA9EuxJaQWDQg7295H4hBphv3IZg0boBKuwYpt4YXp6MZ5AmZQnU/tyMTlRpaSejg==}
    engines: {node: '>= 0.4'}

  camelcase-css@2.0.1:
    resolution: {integrity: sha512-QOSvevhslijgYwRx6Rv7zKdMF8lbRmx+uQGx2+vDc+KI/eBnsy9kit5aj23AgGu3pa4t9AgwbnXWqS+iOY+2aA==}
    engines: {node: '>= 6'}

  caniuse-lite@1.0.30001787:
    resolution: {integrity: sha512-mNcrMN9KeI68u7muanUpEejSLghOKlVhRqS/Za2IeyGllJ9I9otGpR9g3nsw7n4W378TE/LyIteA0+/FOZm4Kg==}

  cbor-extract@2.2.2:
    resolution: {integrity: sha512-hlSxxI9XO2yQfe9g6msd3g4xCfDqK5T5P0fRMLuaLHhxn4ViPrm+a+MUfhrvH2W962RGxcBwEGzLQyjbDG1gng==}
    hasBin: true

  cbor-x@1.6.4:
    resolution: {integrity: sha512-UGKHjp6RHC6QuZ2yy5LCKm7MojM4716DwoSaqwQpaH4DvZvbBTGcoDNTiG9Y2lByXZYFEs9WRkS5tLl96IrF1Q==}

  chai@4.5.0:
    resolution: {integrity: sha512-RITGBfijLkBddZvnn8jdqoTypxvqbOLYQkGGxXzeFjVHvudaPw0HNFD9x928/eUwYWd2dPCugVqspGALTZZQKw==}
    engines: {node: '>=4'}

  chai@5.3.3:
    resolution: {integrity: sha512-4zNhdJD/iOjSH0A05ea+Ke6MU5mmpQcbQsSOkgdaUMJ9zTlDTD/GYlwohmIE2u0gaxHYiVHEn1Fw9mZ/ktJWgw==}
    engines: {node: '>=18'}

  chardet@2.1.1:
    resolution: {integrity: sha512-PsezH1rqdV9VvyNhxxOW32/d75r01NY7TQCmOqomRo15ZSOKbpTFVsfjghxo6JloQUCGnH4k1LGu0R4yCLlWQQ==}

  check-error@1.0.3:
    resolution: {integrity: sha512-iKEoDYaRmd1mxM90a2OEfWhjsjPpYPuQ+lMYsoxB126+t8fw7ySEO48nmDg5COTjxDI65/Y2OWpeEHk3ZOe8zg==}

  check-error@2.1.3:
    resolution: {integrity: sha512-PAJdDJusoxnwm1VwW07VWwUN1sl7smmC3OKggvndJFadxxDRyFJBX/ggnu/KE4kQAB7a3Dp8f/YXC1FlUprWmA==}
    engines: {node: '>= 16'}

  chokidar@3.6.0:
    resolution: {integrity: sha512-7VT13fmjotKpGipCW9JEQAusEPE+Ei8nl6/g4FBAmIm0GOOLMua9NDDo/DWp0ZAxCr3cPq5ZpBqmPAQgDda2Pw==}
    engines: {node: '>= 8.10.0'}

  chokidar@4.0.3:
    resolution: {integrity: sha512-Qgzu8kfBvo+cA4962jnP1KkS6Dop5NS6g7R5LFYJr4b8Ub94PPQXUksCw9PvXoeXPRRddRNC5C1JQUR2SMGtnA==}
    engines: {node: '>= 14.16.0'}

  cipher-base@1.0.7:
    resolution: {integrity: sha512-Mz9QMT5fJe7bKI7MH31UilT5cEK5EHHRCccw/YRFsRY47AuNgaV6HY3rscp0/I4Q+tTW/5zoqpSeRRI54TkDWA==}
    engines: {node: '>= 0.10'}

  clsx@2.1.1:
    resolution: {integrity: sha512-eYm0QWBtUrBWZWG0d386OGAw16Z995PiOVo2B7bjWSbHedGl5e0ZWaq65kOGgUSNesEIDkB9ISbTg/JK9dhCZA==}
    engines: {node: '>=6'}

  code-block-writer@13.0.3:
    resolution: {integrity: sha512-Oofo0pq3IKnsFtuHqSF7TqBfr71aeyZDVJ0HpmqB7FBM2qEigL0iPONSCZSO9pE9dZTAxANe5XHG9Uy0YMv8cg==}

  combined-stream@1.0.8:
    resolution: {integrity: sha512-FQN4MRfuJeHf7cBbBMJFXhKSDq+2kAArBlmRBvcvFE5BB1HZKXtSFASDhdlz9zOYwxh8lDdnvmMOe/+5cdoEdg==}
    engines: {node: '>= 0.8'}

  commander@4.1.1:
    resolution: {integrity: sha512-NOKm8xhkzAjzFx8B2v5OAHT+u5pRQc2UCa2Vq9jYL/31o2wi9mxBA7LIFs3sV5VSC49z6pEhfbMULvShKj26WA==}
    engines: {node: '>= 6'}

  confbox@0.1.8:
    resolution: {integrity: sha512-RMtmw0iFkeR4YV+fUOSucriAQNb9g8zFR52MWCtl+cCZOFRNL6zeB395vPzFhEjjn4fMxXudmELnl/KF/WrK6w==}

  console-browserify@1.2.0:
    resolution: {integrity: sha512-ZMkYO/LkF17QvCPqM0gxw8yUzigAOZOSWSHg91FH6orS7vcEj5dVZTidN2fQ14yBSdg97RqhSNwLUXInd52OTA==}

  constants-browserify@1.0.0:
    resolution: {integrity: sha512-xFxOwqIzR/e1k1gLiWEophSCMqXcwVHIH7akf7b/vxcUeGunlj3hvZaaqxwHsTgn+IndtkQJgSztIDWeumWJDQ==}

  content-disposition@0.5.4:
    resolution: {integrity: sha512-FveZTNuGw04cxlAiWbzi6zTAL/lhehaWbTtgluJh4/E95DqMwTmha3KZN1aAWA8cFIhHzMZUvLevkw5Rqk+tSQ==}
    engines: {node: '>= 0.6'}

  content-type@1.0.5:
    resolution: {integrity: sha512-nTjqfcBFEipKdXCv4YDQWCfmcLZKm81ldF0pAopTvyrFGVbcR6P/VAAd5G7N+0tTr8QqiU0tFadD6FK4NtJwOA==}
    engines: {node: '>= 0.6'}

  convert-source-map@2.0.0:
    resolution: {integrity: sha512-Kvp459HrV2FEJ1CAsi1Ku+MY3kasH19TFykTz2xWmMeq6bk2NU3XXvfJ+Q61m0xktWwt+1HSYf3JZsTms3aRJg==}

  cookie-signature@1.0.7:
    resolution: {integrity: sha512-NXdYc3dLr47pBkpUCHtKSwIOQXLVn8dZEuywboCOJY/osA0wFSLlSawr3KN8qXJEyX66FcONTH8EIlVuK0yyFA==}

  cookie@0.7.2:
    resolution: {integrity: sha512-yki5XnKuf750l50uGTllt6kKILY4nQ1eNIQatoXEByZ5dWgnKqbnqmTrBE5B4N7lrMJKQ2ytWMiTO2o0v6Ew/w==}
    engines: {node: '>= 0.6'}

  core-util-is@1.0.3:
    resolution: {integrity: sha512-ZQBvi1DcpJ4GDqanjucZ2Hj3wEO5pZDS89BWbkcrvdxksJorwUDDZamX9ldFkp9aw2lmBDLgkObEA4DWNJ9FYQ==}

  cors@2.8.6:
    resolution: {integrity: sha512-tJtZBBHA6vjIAaF6EnIaq6laBBP9aq/Y3ouVJjEfoHbRBcHBAHYcMh/w8LDrk2PvIMMq8gmopa5D4V8RmbrxGw==}
    engines: {node: '>= 0.10'}

  create-ecdh@4.0.4:
    resolution: {integrity: sha512-mf+TCx8wWc9VpuxfP2ht0iSISLZnt0JgWlrOKZiNqyUZWnjIaCIVNQArMHnCZKfEYRg6IM7A+NeJoN8gf/Ws0A==}

  create-hash@1.2.0:
    resolution: {integrity: sha512-z00bCGNHDG8mHAkP7CtT1qVu+bFQUPjYq/4Iv3C3kWjTFV10zIjfSoeqXo9Asws8gwSHDGj/hl2u4OGIjapeCg==}

  create-hmac@1.1.7:
    resolution: {integrity: sha512-MJG9liiZ+ogc4TzUwuvbER1JRdgvUFSB5+VR/g5h82fGaIRWMWddtKBHi7/sVhfjQZ6SehlyhvQYrcYkaUIpLg==}

  create-require@1.1.1:
    resolution: {integrity: sha512-dcKFX3jn0MpIaXjisoRvexIJVEKzaq7z2rZKxf+MSr9TkdmHmsU4m2lcLojrj/FHl8mk5VxMmYA+ftRkP/3oKQ==}

  crelt@1.0.6:
    resolution: {integrity: sha512-VQ2MBenTq1fWZUH9DJNGti7kKv6EeAuYr3cLwxUWhIu1baTaXh4Ib5W2CqHVqib4/MqbYGJqiL3Zb8GJZr3l4g==}

  cross-spawn@7.0.6:
    resolution: {integrity: sha512-uV2QOWP2nWzsy2aMp8aRibhi9dlzF5Hgh5SHaB9OiTGEyDTiJJyx0uy51QXdyWbtAHNua4XJzUKca3OzKUd3vA==}
    engines: {node: '>= 8'}

  crypto-browserify@3.12.1:
    resolution: {integrity: sha512-r4ESw/IlusD17lgQi1O20Fa3qNnsckR126TdUuBgAu7GBYSIPvdNyONd3Zrxh0xCwA4+6w/TDArBPsMvhur+KQ==}
    engines: {node: '>= 0.10'}

  css.escape@1.5.1:
    resolution: {integrity: sha512-YUifsXXuknHlUsmlgyY0PKzgPOr7/FjCePfHNt0jxm83wHZi44VDMQ7/fGNkjY3/jV1MC+1CmZbaHzugyeRtpg==}

  cssesc@3.0.0:
    resolution: {integrity: sha512-/Tb/JcjK111nNScGob5MNtsntNM1aCNUDipB/TkwZFhyDrrE47SOx/18wF2bbjgc3ZzCSKW1T5nt5EbFoAz/Vg==}
    engines: {node: '>=4'}
    hasBin: true

  cssstyle@4.6.0:
    resolution: {integrity: sha512-2z+rWdzbbSZv6/rhtvzvqeZQHrBaqgogqt85sqFNbabZOuFbCVFb8kPeEtZjiKkbrm395irpNKiYeFeLiQnFPg==}
    engines: {node: '>=18'}

  csstype@3.2.3:
    resolution: {integrity: sha512-z1HGKcYy2xA8AGQfwrn0PAy+PB7X/GSj3UVJW9qKyn43xWa+gl5nXmU4qqLMRzWVLFC8KusUX8T/0kCiOYpAIQ==}

  d3-array@3.2.4:
    resolution: {integrity: sha512-tdQAmyA18i4J7wprpYq8ClcxZy3SC31QMeByyCFyRt7BVHdREQZ5lpzoe5mFEYZUWe+oq8HBvk9JjpibyEV4Jg==}
    engines: {node: '>=12'}

  d3-color@3.1.0:
    resolution: {integrity: sha512-zg/chbXyeBtMQ1LbD/WSoW2DpC3I0mpmPdW+ynRTj/x2DAWYrIY7qeZIHidozwV24m4iavr15lNwIwLxRmOxhA==}
    engines: {node: '>=12'}

  d3-dispatch@3.0.1:
    resolution: {integrity: sha512-rzUyPU/S7rwUflMyLc1ETDeBj0NRuHKKAcvukozwhshr6g6c5d8zh4c2gQjY2bZ0dXeGLWc1PF174P2tVvKhfg==}
    engines: {node: '>=12'}

  d3-force@3.0.0:
    resolution: {integrity: sha512-zxV/SsA+U4yte8051P4ECydjD/S+qeYtnaIyAs9tgHCqfguma/aAQDjo85A9Z6EKhBirHRJHXIgJUlffT4wdLg==}
    engines: {node: '>=12'}

  d3-format@3.1.2:
    resolution: {integrity: sha512-AJDdYOdnyRDV5b6ArilzCPPwc1ejkHcoyFarqlPqT7zRYjhavcT3uSrqcMvsgh2CgoPbK3RCwyHaVyxYcP2Arg==}
    engines: {node: '>=12'}

  d3-interpolate@3.0.1:
    resolution: {integrity: sha512-3bYs1rOD33uo8aqJfKP3JWPAibgw8Zm2+L9vBKEHJ2Rg+viTR7o5Mmv5mZcieN+FRYaAOWX5SJATX6k1PWz72g==}
    engines: {node: '>=12'}

  d3-quadtree@3.0.1:
    resolution: {integrity: sha512-04xDrxQTDTCFwP5H6hRhsRcb9xxv2RzkcsygFzmkSIOJy3PeRJP7sNk3VRIbKXcog561P9oU0/rVH6vDROAgUw==}
    engines: {node: '>=12'}

  d3-scale@4.0.2:
    resolution: {integrity: sha512-GZW464g1SH7ag3Y7hXjf8RoUuAFIqklOAq3MRl4OaWabTFJY9PN/E1YklhXLh+OQ3fM9yS2nOkCoS+WLZ6kvxQ==}
    engines: {node: '>=12'}

  d3-time-format@4.1.0:
    resolution: {integrity: sha512-dJxPBlzC7NugB2PDLwo9Q8JiTR3M3e4/XANkreKSUxF8vvXKqm1Yfq4Q5dl8budlunRVlUUaDUgFt7eA8D6NLg==}
    engines: {node: '>=12'}

  d3-time@3.1.0:
    resolution: {integrity: sha512-VqKjzBLejbSMT4IgbmVgDjpkYrNWUYJnbCGo874u7MMKIWsILRX+OpX/gTk8MqjpT1A/c6HY2dCA77ZN0lkQ2Q==}
    engines: {node: '>=12'}

  d3-timer@3.0.1:
    resolution: {integrity: sha512-ndfJ/JxxMd3nw31uyKoY2naivF+r29V+Lc0svZxe1JvvIRmi8hUsrMvdOwgS1o6uBHmiz91geQ0ylPP0aj1VUA==}
    engines: {node: '>=12'}

  data-urls@5.0.0:
    resolution: {integrity: sha512-ZYP5VBHshaDAiVZxjbRVcFJpc+4xGgT0bK3vzy1HLN8jTO975HEbuYzZJcHoQEY5K1a0z8YayJkyVETa08eNTg==}
    engines: {node: '>=18'}

  dataloader@1.4.0:
    resolution: {integrity: sha512-68s5jYdlvasItOJnCuI2Q9s4q98g0pCyL3HrcKJu8KNugUl8ahgmZYg38ysLTgQjjXX3H8CJLkAvWrclWfcalw==}

  debug@2.6.9:
    resolution: {integrity: sha512-bC7ElrdJaJnPbAP+1EotYvqZsb3ecl5wi6Bfi6BJTUcNowp6cvspg0jXznRTKDjm/E7AdgFBVeAPVMNcKGsHMA==}
    peerDependencies:
      supports-color: '*'
    peerDependenciesMeta:
      supports-color:
        optional: true

  debug@4.4.3:
    resolution: {integrity: sha512-RGwwWnwQvkVfavKVt22FGLw+xYSdzARwm0ru6DhTVA3umU5hZc28V3kO4stgYryrTlLpuvgI9GiijltAjNbcqA==}
    engines: {node: '>=6.0'}
    peerDependencies:
      supports-color: '*'
    peerDependenciesMeta:
      supports-color:
        optional: true

  decimal.js@10.6.0:
    resolution: {integrity: sha512-YpgQiITW3JXGntzdUmyUR1V812Hn8T1YVXhCu+wO3OpS4eU9l4YdD3qjyiKdV6mvV29zapkMeD390UVEf2lkUg==}

  deep-eql@4.1.4:
    resolution: {integrity: sha512-SUwdGfqdKOwxCPeVYjwSyRpJ7Z+fhpwIAtmCUdZIWZ/YP5R9WAsyuSgpLVDi9bjWoN2LXHNss/dk3urXtdQxGg==}
    engines: {node: '>=6'}

  deep-eql@5.0.2:
    resolution: {integrity: sha512-h5k/5U50IJJFpzfL6nO9jaaumfjO/f2NjK/oYB2Djzm4p9L+3T9qWpZqZ2hAbLPuuYq9wrU08WQyBTL5GbPk5Q==}
    engines: {node: '>=6'}

  deepmerge@4.3.1:
    resolution: {integrity: sha512-3sUqbMEc77XqpdNO7FRyRog+eW3ph+GYCbj+rK+uYyRMuwsVy0rMiVtPn+QJlKFvWP/1PYpapqYn0Me2knFn+A==}
    engines: {node: '>=0.10.0'}

  define-data-property@1.1.4:
    resolution: {integrity: sha512-rBMvIzlpA8v6E+SJZoo++HAYqsLrkg7MSfIinMPFhmkorw7X+dOXVJQs+QT69zGkzMyfDnIMN2Wid1+NbL3T+A==}
    engines: {node: '>= 0.4'}

  define-properties@1.2.1:
    resolution: {integrity: sha512-8QmQKqEASLd5nx0U1B1okLElbUuuttJ/AnYmRXbbbGDWh6uS208EjD4Xqq/I9wK7u0v6O08XhTWnt5XtEbR6Dg==}
    engines: {node: '>= 0.4'}

  delayed-stream@1.0.0:
    resolution: {integrity: sha512-ZySD7Nf91aLB0RxL4KGrKHBXl7Eds1DAmEdcoVawXnLD7SDhpNgtuII2aAkg7a7QS41jxPSZ17p4VdGnMHk3MQ==}
    engines: {node: '>=0.4.0'}

  depd@2.0.0:
    resolution: {integrity: sha512-g7nH6P6dyDioJogAAGprGpCtVImJhpPk/roCzdb3fIh61/s/nPsfR6onyMwkCAR/OlC3yBC0lESvUoQEAssIrw==}
    engines: {node: '>= 0.8'}

  dequal@2.0.3:
    resolution: {integrity: sha512-0je+qPKHEMohvfRTCEo3CrPG6cAzAYgmzKyxRiYSSDkS6eGJdyVJm7WaYA5ECaAD9wLB2T4EEeymA5aFVcYXCA==}
    engines: {node: '>=6'}

  des.js@1.1.0:
    resolution: {integrity: sha512-r17GxjhUCjSRy8aiJpr8/UadFIzMzJGexI3Nmz4ADi9LYSFx4gTBp80+NaX/YsXWWLhpZ7v/v/ubEc/bCNfKwg==}

  destroy@1.2.0:
    resolution: {integrity: sha512-2sJGJTaXIIaR1w4iJSNoN0hnMY7Gpc/n8D4qSCJw8QqFWXf7cuAgnEHxBpweaVcPevC2l3KpjYCx3NypQQgaJg==}
    engines: {node: '>= 0.8', npm: 1.2.8000 || >= 1.4.16}

  detect-indent@6.1.0:
    resolution: {integrity: sha512-reYkTUJAZb9gUuZ2RvVCNhVHdg62RHnJ7WJl8ftMi4diZ6NWlciOzQN88pUhSELEwflJht4oQDv0F0BMlwaYtA==}
    engines: {node: '>=8'}

  detect-libc@2.1.2:
    resolution: {integrity: sha512-Btj2BOOO83o3WyH59e8MgXsxEQVcarkUOpEYrubB0urwnN10yQ364rsiByU11nZlqWYZm05i/of7io4mzihBtQ==}
    engines: {node: '>=8'}

  devalue@5.7.1:
    resolution: {integrity: sha512-MUbZ586EgQqdRnC4yDrlod3BEdyvE4TapGYHMW2CiaW+KkkFmWEFqBUaLltEZCGi0iFXCEjRF0OjF0DV2QHjOA==}

  didyoumean@1.2.2:
    resolution: {integrity: sha512-gxtyfqMg7GKyhQmb056K7M3xszy/myH8w+B4RT+QXBQsvAOdc3XymqDDPHx1BgPgsdAA5SIifona89YtRATDzw==}

  diff-sequences@29.6.3:
    resolution: {integrity: sha512-EjePK1srD3P08o2j4f0ExnylqRs5B9tJjcp9t1krH2qRi8CCdsYfwe9JgSLurFBWwq4uOlipzfk5fHNvwFKr8Q==}
    engines: {node: ^14.15.0 || ^16.10.0 || >=18.0.0}

  diffie-hellman@5.0.3:
    resolution: {integrity: sha512-kqag/Nl+f3GwyK25fhUMYj81BUOrZ9IuJsjIcDE5icNM9FJHAVm3VcUDxdLPoQtTuUylWm6ZIknYJwwaPxsUzg==}

  dir-glob@3.0.1:
    resolution: {integrity: sha512-WkrWp9GR4KXfKGYzOLmTuGVi1UWFfws377n9cc55/tb6DuqyF6pcQ5AbiHEshaDpY9v6oaSr2XCDidGmMwdzIA==}
    engines: {node: '>=8'}

  dlv@1.1.3:
    resolution: {integrity: sha512-+HlytyjlPKnIG8XuRG8WvmBP8xs8P71y+SKKS6ZXWoEgLuePxtDoUEiH7WkdePWrQ5JBpE6aoVqfZfJUQkjXwA==}

  dom-accessibility-api@0.5.16:
    resolution: {integrity: sha512-X7BJ2yElsnOJ30pZF4uIIDfBEVgF4XEBxL9Bxhy6dnrm5hkzqmsWHGTiHqRiITNhMyFLyAiWndIJP7Z1NTteDg==}

  dom-accessibility-api@0.6.3:
    resolution: {integrity: sha512-7ZgogeTnjuHbo+ct10G9Ffp0mif17idi0IyWNVA/wcwcm7NPOD/WEHVP3n7n3MhXqxoIYm8d6MuZohYWIZ4T3w==}

  domain-browser@4.22.0:
    resolution: {integrity: sha512-IGBwjF7tNk3cwypFNH/7bfzBcgSCbaMOD3GsaY1AU/JRrnHnYgEM0+9kQt52iZxjNsjBtJYtao146V+f8jFZNw==}
    engines: {node: '>=10'}

  dotenv@8.6.0:
    resolution: {integrity: sha512-IrPdXQsk2BbzvCBGBOTmmSH5SodmqZNt4ERAZDmW4CT+tL8VtvinqywuANaFu4bOMWki16nqf0e4oC0QIaDr/g==}
    engines: {node: '>=10'}

  drizzle-kit@0.24.2:
    resolution: {integrity: sha512-nXOaTSFiuIaTMhS8WJC2d4EBeIcN9OSt2A2cyFbQYBAZbi7lRsVGJNqDpEwPqYfJz38yxbY/UtbvBBahBfnExQ==}
    hasBin: true

  drizzle-orm@0.33.0:
    resolution: {integrity: sha512-SHy72R2Rdkz0LEq0PSG/IdvnT3nGiWuRk+2tXZQ90GVq/XQhpCzu/EFT3V2rox+w8MlkBQxifF8pCStNYnERfA==}
    peerDependencies:
      '@aws-sdk/client-rds-data': '>=3'
      '@cloudflare/workers-types': '>=3'
      '@electric-sql/pglite': '>=0.1.1'
      '@libsql/client': '*'
      '@neondatabase/serverless': '>=0.1'
      '@op-engineering/op-sqlite': '>=2'
      '@opentelemetry/api': ^1.4.1
      '@planetscale/database': '>=1'
      '@prisma/client': '*'
      '@tidbcloud/serverless': '*'
      '@types/better-sqlite3': '*'
      '@types/pg': '*'
      '@types/react': '>=18'
      '@types/sql.js': '*'
      '@vercel/postgres': '>=0.8.0'
      '@xata.io/client': '*'
      better-sqlite3: '>=7'
      bun-types: '*'
      expo-sqlite: '>=13.2.0'
      knex: '*'
      kysely: '*'
      mysql2: '>=2'
      pg: '>=8'
      postgres: '>=3'
      prisma: '*'
      react: '>=18'
      sql.js: '>=1'
      sqlite3: '>=5'
    peerDependenciesMeta:
      '@aws-sdk/client-rds-data':
        optional: true
      '@cloudflare/workers-types':
        optional: true
      '@electric-sql/pglite':
        optional: true
      '@libsql/client':
        optional: true
      '@neondatabase/serverless':
        optional: true
      '@op-engineering/op-sqlite':
        optional: true
      '@opentelemetry/api':
        optional: true
      '@planetscale/database':
        optional: true
      '@prisma/client':
        optional: true
      '@tidbcloud/serverless':
        optional: true
      '@types/better-sqlite3':
        optional: true
      '@types/pg':
        optional: true
      '@types/react':
        optional: true
      '@types/sql.js':
        optional: true
      '@vercel/postgres':
        optional: true
      '@xata.io/client':
        optional: true
      better-sqlite3:
        optional: true
      bun-types:
        optional: true
      expo-sqlite:
        optional: true
      knex:
        optional: true
      kysely:
        optional: true
      mysql2:
        optional: true
      pg:
        optional: true
      postgres:
        optional: true
      prisma:
        optional: true
      react:
        optional: true
      sql.js:
        optional: true
      sqlite3:
        optional: true

  dunder-proto@1.0.1:
    resolution: {integrity: sha512-KIN/nDJBQRcXw0MLVhZE9iQHmG68qAVIBg9CqmUYjmQIhgij9U5MFvrqkUL5FbtyyzZuOeOt0zdeRe4UY7ct+A==}
    engines: {node: '>= 0.4'}

  ee-first@1.1.1:
    resolution: {integrity: sha512-WMwm9LhRUo+WUaRN+vRuETqG89IgZphVSNkdFgeb6sS/E4OrDIN7t48CAewSHXc6C8lefD8KKfr5vY61brQlow==}

  electron-to-chromium@1.5.335:
    resolution: {integrity: sha512-q9n5T4BR4Xwa2cwbrwcsDJtHD/enpQ5S1xF1IAtdqf5AAgqDFmR/aakqH3ChFdqd/QXJhS3rnnXFtexU7rax6Q==}

  elliptic@6.6.1:
    resolution: {integrity: sha512-RaddvvMatK2LJHqFJ+YA4WysVN5Ita9E35botqIYspQ4TkRAlCicdzKOjlyv/1Za5RyTNn7di//eEV0uTAfe3g==}

  encodeurl@2.0.0:
    resolution: {integrity: sha512-Q0n9HRi4m6JuGIV1eFlmvJB7ZEVxu93IrMyiMsGC0lrMJMWzRgx6WGquyfQgZVb31vhGgXnfmPNNXmxnOkRBrg==}
    engines: {node: '>= 0.8'}

  enquirer@2.4.1:
    resolution: {integrity: sha512-rRqJg/6gd538VHvR3PSrdRBb/1Vy2YfzHqzvbhGIQpDRKIa4FgV/54b5Q1xYSxOOwKvjXweS26E0Q+nAMwp2pQ==}
    engines: {node: '>=8.6'}

  entities@6.0.1:
    resolution: {integrity: sha512-aN97NXWF6AWBTahfVOIrB/NShkzi5H7F9r1s9mD3cDj4Ko5f2qhhVoYMibXF7GlLveb/D2ioWay8lxI97Ven3g==}
    engines: {node: '>=0.12'}

  es-define-property@1.0.1:
    resolution: {integrity: sha512-e3nRfgfUZ4rNGL232gUgX06QNyyez04KdjFrF+LTRoOXmrOgFKDg4BCdsjW8EnT69eqdYGmRpJwiPVYNrCaW3g==}
    engines: {node: '>= 0.4'}

  es-errors@1.3.0:
    resolution: {integrity: sha512-Zf5H2Kxt2xjTvbJvP2ZWLEICxA6j+hAmMzIlypy4xcBg1vKVnx89Wy0GbS+kf5cwCVFFzdCFh2XSCFNULS6csw==}
    engines: {node: '>= 0.4'}

  es-module-lexer@1.7.0:
    resolution: {integrity: sha512-jEQoCwk8hyb2AZziIOLhDqpm5+2ww5uIE6lkO/6jcOCusfk6LhMHpXXfBLXTZ7Ydyt0j4VoUQv6uGNYbdW+kBA==}

  es-object-atoms@1.1.1:
    resolution: {integrity: sha512-FGgH2h8zKNim9ljj7dankFPcICIK9Cp5bm+c2gQSYePhpaG5+esrLODihIorn+Pe6FGJzWhXQotPv73jTaldXA==}
    engines: {node: '>= 0.4'}

  es-set-tostringtag@2.1.0:
    resolution: {integrity: sha512-j6vWzfrGVfyXxge+O0x5sh6cvxAog0a/4Rdd2K36zCMV5eJ+/+tOAngRO8cODMNWbVRdVlmGZQL2YS3yR8bIUA==}
    engines: {node: '>= 0.4'}

  esbuild-register@3.6.0:
    resolution: {integrity: sha512-H2/S7Pm8a9CL1uhp9OvjwrBh5Pvx0H8qVOxNu8Wed9Y7qv56MPtq+GGM8RJpq6glYJn9Wspr8uw7l55uyinNeg==}
    peerDependencies:
      esbuild: '>=0.12 <1'

  esbuild@0.18.20:
    resolution: {integrity: sha512-ceqxoedUrcayh7Y7ZX6NdbbDzGROiyVBgC4PriJThBKSVPWnnFHZAkfI1lJT8QFkOwH4qOS2SJkS4wvpGl8BpA==}
    engines: {node: '>=12'}
    hasBin: true

  esbuild@0.19.12:
    resolution: {integrity: sha512-aARqgq8roFBj054KvQr5f1sFu0D65G+miZRCuJyJ0G13Zwx7vRar5Zhn2tkQNzIXcBrNVsv/8stehpj+GAjgbg==}
    engines: {node: '>=12'}
    hasBin: true

  esbuild@0.21.5:
    resolution: {integrity: sha512-mg3OPMV4hXywwpoDxu3Qda5xCKQi+vCTZq8S9J/EpkhB2HzKXq4SNFZE3+NK93JYxc8VMSep+lOUSC/RVKaBqw==}
    engines: {node: '>=12'}
    hasBin: true

  esbuild@0.25.12:
    resolution: {integrity: sha512-bbPBYYrtZbkt6Os6FiTLCTFxvq4tt3JKall1vRwshA3fdVztsLAatFaZobhkBC8/BrPetoa0oksYoKXoG4ryJg==}
    engines: {node: '>=18'}
    hasBin: true

  esbuild@0.27.7:
    resolution: {integrity: sha512-IxpibTjyVnmrIQo5aqNpCgoACA/dTKLTlhMHihVHhdkxKyPO1uBBthumT0rdHmcsk9uMonIWS0m4FljWzILh3w==}
    engines: {node: '>=18'}
    hasBin: true

  escalade@3.2.0:
    resolution: {integrity: sha512-WUj2qlxaQtO4g6Pq5c29GTcWGDyd8itL8zTlipgECz3JesAiiOKotd8JU6otB3PACgG6xkJUyVhboMS+bje/jA==}
    engines: {node: '>=6'}

  escape-html@1.0.3:
    resolution: {integrity: sha512-NiSupZ4OeuGwr68lGIeym/ksIZMJodUGOSCZ/FSnTxcrekbvqrgdUxlJOMpijaKZVjAJrWrGs/6Jy8OMuyj9ow==}

  esm-env@1.2.2:
    resolution: {integrity: sha512-Epxrv+Nr/CaL4ZcFGPJIYLWFom+YeV1DqMLHJoEd9SYRxNbaFruBwfEX/kkHUJf55j2+TUbmDcmuilbP1TmXHA==}

  esprima@4.0.1:
    resolution: {integrity: sha512-eGuFFw7Upda+g4p+QHvnW0RyTX/SVeJBDM/gCtMARO0cLuT2HcEKnTPvhjV6aGeqrCB/sbNop0Kszm0jsaWU4A==}
    engines: {node: '>=4'}
    hasBin: true

  esrap@2.2.5:
    resolution: {integrity: sha512-/yLB1538mag+dn0wsePTe8C0rDIjUOaJpMs2McodSzmM2msWcZsBSdRtg6HOBt0A/r82BN+Md3pgwSc/uWt2Ig==}
    peerDependencies:
      '@typescript-eslint/types': ^8.2.0
    peerDependenciesMeta:
      '@typescript-eslint/types':
        optional: true

  estree-walker@2.0.2:
    resolution: {integrity: sha512-Rfkk/Mp/DL7JVje3u18FxFujQlTNR2q6QfMSMB7AvCBx91NGj/ba3kCfza0f6dVDbw7YlRf/nDrn7pQrCCyQ/w==}

  estree-walker@3.0.3:
    resolution: {integrity: sha512-7RUKfXgSMMkzt6ZuXmqapOurLGPPfgj6l9uRZ7lRGolvk0y2yocc35LdcxKC5PQZdn2DMqioAQ2NoWcrTKmm6g==}

  etag@1.8.1:
    resolution: {integrity: sha512-aIL5Fx7mawVa300al2BnEE4iNvo1qETxLrPI/o05L7z6go7fCw1J6EQmbK4FmJ2AS7kgVF/KEZWufBfdClMcPg==}
    engines: {node: '>= 0.6'}

  event-target-shim@5.0.1:
    resolution: {integrity: sha512-i/2XbnSz/uxRCU6+NdVJgKWDTM427+MqYbkQzD321DuCQJUqOuJKIA0IM2+W2xtYHdKOmZ4dR6fExsd4SXL+WQ==}
    engines: {node: '>=6'}

  events@3.3.0:
    resolution: {integrity: sha512-mQw+2fkQbALzQ7V0MY0IqdnXNOeTtP4r0lN9z7AAawCXgqea7bDii20AYrIBrFd/Hx0M2Ocz6S111CaFkUcb0Q==}
    engines: {node: '>=0.8.x'}

  evp_bytestokey@1.0.3:
    resolution: {integrity: sha512-/f2Go4TognH/KvCISP7OUsHn85hT9nUkxxA9BEWxFn+Oj9o8ZNLm/40hdlgSLyuOimsrTKLUMEorQexp/aPQeA==}

  execa@8.0.1:
    resolution: {integrity: sha512-VyhnebXciFV2DESc+p6B+y0LjSm0krU4OgJN44qFAhBY0TJ+1V61tYD2+wHusZ6F9n5K+vl8k0sTy7PEfV4qpg==}
    engines: {node: '>=16.17'}

  expect-type@1.3.0:
    resolution: {integrity: sha512-knvyeauYhqjOYvQ66MznSMs83wmHrCycNEN6Ao+2AeYEfxUIkuiVxdEa1qlGEPK+We3n0THiDciYSsCcgW/DoA==}
    engines: {node: '>=12.0.0'}

  express@4.22.1:
    resolution: {integrity: sha512-F2X8g9P1X7uCPZMA3MVf9wcTqlyNp7IhH5qPCI0izhaOIYXaW9L535tGA3qmjRzpH+bZczqq7hVKxTR4NWnu+g==}
    engines: {node: '>= 0.10.0'}

  extendable-error@0.1.7:
    resolution: {integrity: sha512-UOiS2in6/Q0FK0R0q6UY9vYpQ21mr/Qn1KOnte7vsACuNJf514WvCCUHSRCPcgjPT2bAhNIJdlE6bVap1GKmeg==}

  fake-indexeddb@6.2.5:
    resolution: {integrity: sha512-CGnyrvbhPlWYMngksqrSSUT1BAVP49dZocrHuK0SvtR0D5TMs5wP0o3j7jexDJW01KSadjBp1M/71o/KR3nD1w==}
    engines: {node: '>=18'}

  fast-check@3.23.2:
    resolution: {integrity: sha512-h5+1OzzfCC3Ef7VbtKdcv7zsstUQwUDlYpUTvjeUsJAssPgLn7QzbboPtL5ro04Mq0rPOsMzl7q5hIbRs2wD1A==}
    engines: {node: '>=8.0.0'}

  fast-glob@3.3.3:
    resolution: {integrity: sha512-7MptL8U0cqcFdzIzwOTHoilX9x5BrNqye7Z/LuC7kCMRio1EMSyqRK3BEAUD7sXRq4iT4AzTVuZdhgQ2TCvYLg==}
    engines: {node: '>=8.6.0'}

  fast-sha256@1.3.0:
    resolution: {integrity: sha512-n11RGP/lrWEFI/bWdygLxhI+pVeo1ZYIVwvvPkW7azl/rOy+F3HYRZ2K5zeE9mmkhQppyv9sQFx0JM9UabnpPQ==}

  fastq@1.20.1:
    resolution: {integrity: sha512-GGToxJ/w1x32s/D2EKND7kTil4n8OVk/9mycTc4VDza13lOvpUZTGX3mFSCtV9ksdGBVzvsyAVLM6mHFThxXxw==}

  fdir@6.5.0:
    resolution: {integrity: sha512-tIbYtZbucOs0BRGqPJkshJUYdL+SDH7dVM8gjy+ERp3WAUjLEFJE+02kanyHtwjWOnwrKYBiwAmM0p4kLJAnXg==}
    engines: {node: '>=12.0.0'}
    peerDependencies:
      picomatch: ^3 || ^4
    peerDependenciesMeta:
      picomatch:
        optional: true

  fflate@0.8.2:
    resolution: {integrity: sha512-cPJU47OaAoCbg0pBvzsgpTPhmhqI5eJjh/JIu8tPj5q+T7iLvW/JAYUqmE7KOB4R1ZyEhzBaIQpQpardBF5z8A==}

  fill-range@7.1.1:
    resolution: {integrity: sha512-YsGpe3WHLK8ZYi4tWDg2Jy3ebRz2rXowDxnld4bkQB00cc/1Zw9AWnC0i9ztDJitivtQvaI9KaLyKrc+hBW0yg==}
    engines: {node: '>=8'}

  finalhandler@1.3.2:
    resolution: {integrity: sha512-aA4RyPcd3badbdABGDuTXCMTtOneUCAYH/gxoYRTZlIJdF0YPWuGqiAsIrhNnnqdXGswYk6dGujem4w80UJFhg==}
    engines: {node: '>= 0.8'}

  find-up@4.1.0:
    resolution: {integrity: sha512-PpOwAdQ/YlXQ2vj8a3h8IipDuYRi3wceVQQGYWxNINccq40Anw7BlsEXCMbt1Zt+OLA6Fq9suIpIWD0OsnISlw==}
    engines: {node: '>=8'}

  find-up@5.0.0:
    resolution: {integrity: sha512-78/PXT1wlLLDgTzDs7sjq9hzz0vXD+zn+7wypEe4fXQxCmdmqfGsEPQxmiCSQI3ajFV91bVSsvNtrJRiW6nGng==}
    engines: {node: '>=10'}

  for-each@0.3.5:
    resolution: {integrity: sha512-dKx12eRCVIzqCxFGplyFKJMPvLEWgmNtUrpTiJIR5u97zEhRG8ySrtboPHZXx7daLxQVrl643cTzbab2tkQjxg==}
    engines: {node: '>= 0.4'}

  form-data-encoder@1.7.2:
    resolution: {integrity: sha512-qfqtYan3rxrnCk1VYaA4H+Ms9xdpPqvLZa6xmMgFvhO32x7/3J/ExcTd6qpxM0vH2GdMI+poehyBZvqfMTto8A==}

  form-data@4.0.5:
    resolution: {integrity: sha512-8RipRLol37bNs2bhoV67fiTEvdTrbMUYcFTiy3+wuuOnUog2QBHCZWXDRijWQfAkhBj2Uf5UnVaiWwA5vdd82w==}
    engines: {node: '>= 6'}

  formdata-node@4.4.1:
    resolution: {integrity: sha512-0iirZp3uVDjVGt9p49aTaqjk84TrglENEDuqfdlZQ1roC9CWlPk6Avf8EEnZNcAqPonwkG35x4n3ww/1THYAeQ==}
    engines: {node: '>= 12.20'}

  forwarded@0.2.0:
    resolution: {integrity: sha512-buRG0fpBtRHSTCOASe6hD258tEubFoRLb4ZNA6NxMVHNw2gOcwHo9wyablzMzOA5z9xA9L1KNjk/Nt6MT9aYow==}
    engines: {node: '>= 0.6'}

  fraction.js@5.3.4:
    resolution: {integrity: sha512-1X1NTtiJphryn/uLQz3whtY6jK3fTqoE3ohKs0tT+Ujr1W59oopxmoEh7Lu5p6vBaPbgoM0bzveAW4Qi5RyWDQ==}

  fresh@0.5.2:
    resolution: {integrity: sha512-zJ2mQYM18rEFOudeV4GShTGIQ7RbzA7ozbU9I/XBpm7kqgMywgmylMwXHxZJmkVoYkna9d2pVXVXPdYTP9ej8Q==}
    engines: {node: '>= 0.6'}

  fs-extra@7.0.1:
    resolution: {integrity: sha512-YJDaCJZEnBmcbw13fvdAM9AwNOJwOzrE4pqMqBq5nFiEqXUqHwlK4B+3pUw6JNvfSPtX05xFHtYy/1ni01eGCw==}
    engines: {node: '>=6 <7 || >=8'}

  fs-extra@8.1.0:
    resolution: {integrity: sha512-yhlQgA6mnOJUKOsRUFsgJdQCvkKhcz8tlZG5HBQfReYZy46OwLcY+Zia0mtdHsOo9y/hP+CxMN0TU9QxoOtG4g==}
    engines: {node: '>=6 <7 || >=8'}

  fsevents@2.3.3:
    resolution: {integrity: sha512-5xoDfX+fL7faATnagmWPpbFtwh/R77WmMMqqHGS65C3vvB0YHrgF+B1YmZ3441tMj5n63k0212XNoJwzlhffQw==}
    engines: {node: ^8.16.0 || ^10.6.0 || >=11.0.0}
    os: [darwin]

  function-bind@1.1.2:
    resolution: {integrity: sha512-7XHNxH7qX9xG5mIwxkhumTox/MIRNcOgDrxWsMt2pAr23WHp6MrRlN7FBSFpCpr+oVO0F744iUgR82nJMfG2SA==}

  generator-function@2.0.1:
    resolution: {integrity: sha512-SFdFmIJi+ybC0vjlHN0ZGVGHc3lgE0DxPAT0djjVg+kjOnSqclqmj0KQ7ykTOLP6YxoqOvuAODGdcHJn+43q3g==}
    engines: {node: '>= 0.4'}

  gensync@1.0.0-beta.2:
    resolution: {integrity: sha512-3hN7NaskYvMDLQY55gnW3NQ+mesEAepTqlg+VEbj7zzqEMBVNhzcGYYeqFo/TlYz6eQiFcp1HcsCZO+nGgS8zg==}
    engines: {node: '>=6.9.0'}

  geotiff@3.0.5:
    resolution: {integrity: sha512-OWcL9S9+yDZ6iAlXMt32T1iwUApJM8UiD47xbm6ZP1h33d10fqkPs14EG/ttT5EnefpZSx3G15iDFC5FxUNUwA==}
    engines: {node: '>=10.19'}

  get-func-name@2.0.2:
    resolution: {integrity: sha512-8vXOvuE167CtIc3OyItco7N/dpRtBbYOsPsXCz7X/PMnlGjYjSGuZJgM1Y7mmew7BKf9BqvLX2tnOVy1BBUsxQ==}

  get-intrinsic@1.3.0:
    resolution: {integrity: sha512-9fSjSaos/fRIVIp+xSJlE6lfwhES7LNtKaCBIamHsjr2na1BiABJPo0mOjjz8GJDURarmCPGqaiVg5mfjb98CQ==}
    engines: {node: '>= 0.4'}

  get-proto@1.0.1:
    resolution: {integrity: sha512-sTSfBjoXBp89JvIKIefqw7U2CCebsc74kiY6awiGogKtoSGbgjYE/G/+l9sF3MWFPNc9IcoOC4ODfKHfxFmp0g==}
    engines: {node: '>= 0.4'}

  get-stream@8.0.1:
    resolution: {integrity: sha512-VaUJspBffn/LMCJVoMvSAdmscJyS1auj5Zulnn5UoYcY531UWmdwhRWkcGKnGU93m5HSXP9LP2usOryrBtQowA==}
    engines: {node: '>=16'}

  get-tsconfig@4.14.0:
    resolution: {integrity: sha512-yTb+8DXzDREzgvYmh6s9vHsSVCHeC0G3PI5bEXNBHtmshPnO+S5O7qgLEOn0I5QvMy6kpZN8K1NKGyilLb93wA==}

  glob-parent@5.1.2:
    resolution: {integrity: sha512-AOIgSQCepiJYwP3ARnGx+5VnTu2HBYdzbGP45eLw1vr3zB3vZLeyed1sC9hnbcOc9/SrMyM5RPQrkGz4aS9Zow==}
    engines: {node: '>= 6'}

  glob-parent@6.0.2:
    resolution: {integrity: sha512-XxwI8EOhVQgWp6iDL+3b0r86f4d6AX6zSU55HfB4ydCEuXLXc5FcYeOu+nnGftS4TEju/11rt4KJPTMgbfmv4A==}
    engines: {node: '>=10.13.0'}

  glob@13.0.6:
    resolution: {integrity: sha512-Wjlyrolmm8uDpm/ogGyXZXb1Z+Ca2B8NbJwqBVg0axK9GbBeoS7yGV6vjXnYdGm6X53iehEuxxbyiKp8QmN4Vw==}
    engines: {node: 18 || 20 || >=22}

  globby@11.1.0:
    resolution: {integrity: sha512-jhIXaOzy1sb8IyocaruWSn1TjmnBVs8Ayhcy83rmxNJ8q2uWKCAj3CnJY+KpGSXCueAPc0i05kVvVKtP1t9S3g==}
    engines: {node: '>=10'}

  gopd@1.2.0:
    resolution: {integrity: sha512-ZUKRh6/kUFoAiTAtTYPZJ3hw9wNxx+BIBOijnlG9PnrJsCcSjs1wyyD6vJpaYtgnzDrKYRSqf3OO6Rfa93xsRg==}
    engines: {node: '>= 0.4'}

  graceful-fs@4.2.11:
    resolution: {integrity: sha512-RbJ5/jmFcNNCcDV5o9eTnBLJ/HszWV0P73bc+Ff4nS/rJj+YaS6IGyiOL0VoBYX+l1Wrl3k63h/KrH+nhJ0XvQ==}

  has-property-descriptors@1.0.2:
    resolution: {integrity: sha512-55JNKuIW+vq4Ke1BjOTjM2YctQIvCT7GFzHwmfZPGo5wnrgkid0YQtnAleFSqumZm4az3n2BS+erby5ipJdgrg==}

  has-symbols@1.1.0:
    resolution: {integrity: sha512-1cDNdwJ2Jaohmb3sg4OmKaMBwuC48sYni5HUw2DvsC8LjGTLK9h+eb1X6RyuOHe4hT0ULCW68iomhjUoKUqlPQ==}
    engines: {node: '>= 0.4'}

  has-tostringtag@1.0.2:
    resolution: {integrity: sha512-NqADB8VjPFLM2V0VvHUewwwsw0ZWBaIdgo+ieHtK3hasLz4qeCRjYcqfB6AQrBggRKppKF8L52/VqdVsO47Dlw==}
    engines: {node: '>= 0.4'}

  hash-base@3.0.5:
    resolution: {integrity: sha512-vXm0l45VbcHEVlTCzs8M+s0VeYsB2lnlAaThoLKGXr3bE/VWDOelNUnycUPEhKEaXARL2TEFjBOyUiM6+55KBg==}
    engines: {node: '>= 0.10'}

  hash-base@3.1.2:
    resolution: {integrity: sha512-Bb33KbowVTIj5s7Ked1OsqHUeCpz//tPwR+E2zJgJKo9Z5XolZ9b6bdUgjmYlwnWhoOQKoTd1TYToZGn5mAYOg==}
    engines: {node: '>= 0.8'}

  hash.js@1.1.7:
    resolution: {integrity: sha512-taOaskGt4z4SOANNseOviYDvjEJinIkRgmp7LbKP2YTTmVxWBl87s/uzK9r+44BclBSp2X7K1hqeNfz9JbBeXA==}

  hasown@2.0.2:
    resolution: {integrity: sha512-0hJU9SCPvmMzIBdZFqNPXWa6dqh7WdH0cII9y+CyS8rG3nL48Bclra9HmKhVVUHyPWNH5Y7xDwAB7bfgSjkUMQ==}
    engines: {node: '>= 0.4'}

  hmac-drbg@1.0.1:
    resolution: {integrity: sha512-Tti3gMqLdZfhOQY1Mzf/AanLiqh1WTiJgEj26ZuYQ9fbkLomzGchCws4FyrSd4VkpBfiNhaE1On+lOz894jvXg==}

  html-encoding-sniffer@4.0.0:
    resolution: {integrity: sha512-Y22oTqIU4uuPgEemfz7NDJz6OeKf12Lsu+QC+s3BVpda64lTiMYCyGwg5ki4vFxkMwQdeZDl2adZoqUgdFuTgQ==}
    engines: {node: '>=18'}

  http-errors@2.0.1:
    resolution: {integrity: sha512-4FbRdAX+bSdmo4AUFuS0WNiPz8NgFt+r8ThgNWmlrjQjt1Q7ZR9+zTlce2859x4KSXrwIsaeTqDoKQmtP8pLmQ==}
    engines: {node: '>= 0.8'}

  http-proxy-agent@7.0.2:
    resolution: {integrity: sha512-T1gkAiYYDWYx3V5Bmyu7HcfcvL7mUrTWiM6yOfa3PIphViJ/gFPbvidQ+veqSOHci/PxBcDabeUNCzpOODJZig==}
    engines: {node: '>= 14'}

  https-browserify@1.0.0:
    resolution: {integrity: sha512-J+FkSdyD+0mA0N+81tMotaRMfSL9SGi+xpD3T6YApKsc3bGSXJlfXri3VyFOeYkfLRQisDk1W+jIFFKBeUBbBg==}

  https-proxy-agent@7.0.6:
    resolution: {integrity: sha512-vK9P5/iUfdl95AI+JVyUuIcVtd4ofvtrOr3HNtM2yxC9bnMbEdp3x01OhQNnjb8IJYi38VlTE3mBXwcfvywuSw==}
    engines: {node: '>= 14'}

  human-id@4.1.3:
    resolution: {integrity: sha512-tsYlhAYpjCKa//8rXZ9DqKEawhPoSytweBC2eNvcaDK+57RZLHGqNs3PZTQO6yekLFSuvA6AlnAfrw1uBvtb+Q==}
    hasBin: true

  human-signals@5.0.0:
    resolution: {integrity: sha512-AXcZb6vzzrFAUE61HnN4mpLqd/cSIwNQjtNWR0euPm6y0iqx3G4gOXaIDdtdDwZmhwe82LA6+zinmW4UBWVePQ==}
    engines: {node: '>=16.17.0'}

  humanize-ms@1.2.1:
    resolution: {integrity: sha512-Fl70vYtsAFb/C06PTS9dZBo7ihau+Tu/DNCk/OyHhea07S+aeMWpFFkUaXRa8fI+ScZbEI8dfSxwY7gxZ9SAVQ==}

  iconv-lite@0.4.24:
    resolution: {integrity: sha512-v3MXnZAcvnywkTUEZomIActle7RXXeedOR31wwl7VlyoXO4Qi9arvSenNQWne1TcRwhCL1HwLI21bEqdpj8/rA==}
    engines: {node: '>=0.10.0'}

  iconv-lite@0.6.3:
    resolution: {integrity: sha512-4fCk79wshMdzMp2rH06qWrJE4iolqLhCUH+OiuIgU++RB0+94NlDL81atO7GX55uUKueo0txHNtvEyI6D7WdMw==}
    engines: {node: '>=0.10.0'}

  iconv-lite@0.7.2:
    resolution: {integrity: sha512-im9DjEDQ55s9fL4EYzOAv0yMqmMBSZp6G0VvFyTMPKWxiSBHUj9NW/qqLmXUwXrrM7AvqSlTCfvqRb0cM8yYqw==}
    engines: {node: '>=0.10.0'}

  ieee754@1.2.1:
    resolution: {integrity: sha512-dcyqhDvX1C46lXZcVqCpK+FtMRQVdIMN6/Df5js2zouUsqG7I6sFxitIC+7KYK29KdXOLHdu9zL4sFnoVQnqaA==}

  ignore@5.3.2:
    resolution: {integrity: sha512-hsBTNUqQTDwkWtcdYI2i06Y/nUBEsNEDJKjWdigLvegy8kDuJAS8uRlpkkcQpyEXL0Z/pjDy5HBmMjRCJ2gq+g==}
    engines: {node: '>= 4'}

  indent-string@4.0.0:
    resolution: {integrity: sha512-EdDDZu4A2OyIK7Lr/2zG+w5jmbuk1DVBnEwREQvBzspBJkCEbRa8GxU1lghYcaGJCnRWibjDXlq779X1/y5xwg==}
    engines: {node: '>=8'}

  inherits@2.0.4:
    resolution: {integrity: sha512-k/vGaX4/Yla3WzyMCvTQOXYeIHvqOKtnqBduzTHpzpQZzAskKMhZ2K+EnBiSM9zGSoIFeMpXKxa4dYeZIQqewQ==}

  internmap@2.0.3:
    resolution: {integrity: sha512-5Hh7Y1wQbvY5ooGgPbDaL5iYLAPzMTUrjMulskHLH6wnv/A+1q5rgEaiuqEjB+oxGXIVZs1FF+R/KPN3ZSQYYg==}
    engines: {node: '>=12'}

  ipaddr.js@1.9.1:
    resolution: {integrity: sha512-0KI/607xoxSToH7GjN1FfSbLoU0+btTicjsQSWQlh/hZykN8KpmMf7uYwPW3R+akZ6R/w18ZlXSHBYXiYUPO3g==}
    engines: {node: '>= 0.10'}

  is-arguments@1.2.0:
    resolution: {integrity: sha512-7bVbi0huj/wrIAOzb8U1aszg9kdi3KN/CyU19CTI7tAoZYEZoL9yCDXpbXN+uPsuWnP02cyug1gleqq+TU+YCA==}
    engines: {node: '>= 0.4'}

  is-binary-path@2.1.0:
    resolution: {integrity: sha512-ZMERYes6pDydyuGidse7OsHxtbI7WVeUEozgR/g7rd0xUimYNlvZRE/K2MgZTjWy725IfelLeVcEM97mmtRGXw==}
    engines: {node: '>=8'}

  is-callable@1.2.7:
    resolution: {integrity: sha512-1BC0BVFhS/p0qtw6enp8e+8OD0UrK0oFLztSjNzhcKA3WDuJxxAPXzPuPtKkjEY9UUoEWlX/8fgKeu2S8i9JTA==}
    engines: {node: '>= 0.4'}

  is-core-module@2.16.1:
    resolution: {integrity: sha512-UfoeMA6fIJ8wTYFEUjelnaGI67v6+N7qXJEvQuIGa99l4xsCruSYOVSQ0uPANn4dAzm8lkYPaKLrrijLq7x23w==}
    engines: {node: '>= 0.4'}

  is-extglob@2.1.1:
    resolution: {integrity: sha512-SbKbANkN603Vi4jEZv49LeVJMn4yGwsbzZworEoyEiutsN3nJYdbO36zfhGJ6QEDpOZIFkDtnq5JRxmvl3jsoQ==}
    engines: {node: '>=0.10.0'}

  is-generator-function@1.1.2:
    resolution: {integrity: sha512-upqt1SkGkODW9tsGNG5mtXTXtECizwtS2kA161M+gJPc1xdb/Ax629af6YrTwcOeQHbewrPNlE5Dx7kzvXTizA==}
    engines: {node: '>= 0.4'}

  is-glob@4.0.3:
    resolution: {integrity: sha512-xelSayHH36ZgE7ZWhli7pW34hNbNl8Ojv5KVmkJD4hBdD3th8Tfk9vYasLM+mXWOZhFkgZfxhLSnrwRr4elSSg==}
    engines: {node: '>=0.10.0'}

  is-nan@1.3.2:
    resolution: {integrity: sha512-E+zBKpQ2t6MEo1VsonYmluk9NxGrbzpeeLC2xIViuO2EjU2xsXsBPwTr3Ykv9l08UYEVEdWeRZNouaZqF6RN0w==}
    engines: {node: '>= 0.4'}

  is-number@7.0.0:
    resolution: {integrity: sha512-41Cifkg6e8TylSpdtTpeLVMqvSBEVzTttHvERD741+pnZ8ANv0004MRL43QKPDlK9cGvNp6NZWZUBlbGXYxxng==}
    engines: {node: '>=0.12.0'}

  is-potential-custom-element-name@1.0.1:
    resolution: {integrity: sha512-bCYeRA2rVibKZd+s2625gGnGF/t7DSqDs4dP7CrLA1m7jKWz6pps0LpYLJN8Q64HtmPKJ1hrN3nzPNKFEKOUiQ==}

  is-reference@3.0.3:
    resolution: {integrity: sha512-ixkJoqQvAP88E6wLydLGGqCJsrFUnqoH6HnaczB8XmDH1oaWU+xxdptvikTgaEhtZ53Ky6YXiBuUI2WXLMCwjw==}

  is-regex@1.2.1:
    resolution: {integrity: sha512-MjYsKHO5O7mCsmRGxWcLWheFqN9DJ/2TmngvjKXihe6efViPqc274+Fx/4fYj/r03+ESvBdTXK0V6tA3rgez1g==}
    engines: {node: '>= 0.4'}

  is-stream@3.0.0:
    resolution: {integrity: sha512-LnQR4bZ9IADDRSkvpqMGvt/tEJWclzklNgSw48V5EAaAeDd6qGvN8ei6k5p0tvxSR171VmGyHuTiAOfxAbr8kA==}
    engines: {node: ^12.20.0 || ^14.13.1 || >=16.0.0}

  is-subdir@1.2.0:
    resolution: {integrity: sha512-2AT6j+gXe/1ueqbW6fLZJiIw3F8iXGJtt0yDrZaBhAZEG1raiTxKWU+IPqMCzQAXOUCKdA4UDMgacKH25XG2Cw==}
    engines: {node: '>=4'}

  is-typed-array@1.1.15:
    resolution: {integrity: sha512-p3EcsicXjit7SaskXHs1hA91QxgTw46Fv6EFKKGS5DRFLD8yKnohjF3hxoju94b/OcMZoQukzpPpBE9uLVKzgQ==}
    engines: {node: '>= 0.4'}

  is-windows@1.0.2:
    resolution: {integrity: sha512-eXK1UInq2bPmjyX6e3VHIzMLobc4J94i4AWn+Hpq3OU5KkrRC96OAcR3PRJ/pGu6m8TRnBHP9dkXQVsT/COVIA==}
    engines: {node: '>=0.10.0'}

  isarray@1.0.0:
    resolution: {integrity: sha512-VLghIWNM6ELQzo7zwmcg0NmTVyWKYjvIeM83yjp0wRDTmUnrM678fQbcKBo6n2CJEF0szoG//ytg+TKla89ALQ==}

  isarray@2.0.5:
    resolution: {integrity: sha512-xHjhDr3cNBK0BzdUJSPXZntQUx/mwMS5Rw4A7lPJ90XGAO6ISP/ePDNuo0vhqOZU+UD5JoodwCAAoZQd3FeAKw==}

  isexe@2.0.0:
    resolution: {integrity: sha512-RHxMLp9lnKHGHRng9QFhRCMbYAcVpn69smSGcq3f36xjgVVWThj4qqLbTLlq7Ssj8B+fIQ1EuCEGI2lKsyQeIw==}

  isomorphic-timers-promises@1.0.1:
    resolution: {integrity: sha512-u4sej9B1LPSxTGKB/HiuzvEQnXH0ECYkSVQU39koSwmFAxhlEAFl9RdTvLv4TOTQUgBS5O3O5fwUxk6byBZ+IQ==}
    engines: {node: '>=10'}

  jiti@1.21.7:
    resolution: {integrity: sha512-/imKNG4EbWNrVjoNC/1H5/9GFy+tqjGBHCaSsN+P2RnPqjsLmv6UD3Ej+Kj8nBWaRAwyk7kK5ZUc+OEatnTR3A==}
    hasBin: true

  js-tokens@4.0.0:
    resolution: {integrity: sha512-RdJUflcE3cUzKiMqQgsCu06FPu9UdIJO0beYbPhHN4k6apgJtifcoCtT9bcxOpYBtpD2kCM6Sbzg4CausW/PKQ==}

  js-tokens@9.0.1:
    resolution: {integrity: sha512-mxa9E9ITFOt0ban3j6L5MpjwegGz6lBQmM1IJkWeBZGcMxto50+eWdjC/52xDbS2vy0k7vIMK0Fe2wfL9OQSpQ==}

  js-yaml@3.14.2:
    resolution: {integrity: sha512-PMSmkqxr106Xa156c2M265Z+FTrPl+oxd/rgOQy2tijQeK5TxQ43psO1ZCwhVOSdnn+RzkzlRz/eY4BgJBYVpg==}
    hasBin: true

  js-yaml@4.1.1:
    resolution: {integrity: sha512-qQKT4zQxXl8lLwBtHMWwaTcGfFOZviOJet3Oy/xmGk2gZH677CJM9EvtfdSkgWcATZhj/55JZ0rmy3myCT5lsA==}
    hasBin: true

  jsdom@25.0.1:
    resolution: {integrity: sha512-8i7LzZj7BF8uplX+ZyOlIz86V6TAsSs+np6m1kpW9u0JWi4z/1t+FzcK1aek+ybTnAC4KhBL4uXCNT0wcUIeCw==}
    engines: {node: '>=18'}
    peerDependencies:
      canvas: ^2.11.2
    peerDependenciesMeta:
      canvas:
        optional: true

  jsesc@3.1.0:
    resolution: {integrity: sha512-/sM3dO2FOzXjKQhJuo0Q173wf2KOo8t4I8vHy6lF9poUp7bKT0/NHE8fPX23PwfhnykfqnC2xRxOnVw5XuGIaA==}
    engines: {node: '>=6'}
    hasBin: true

  json-schema-to-ts@3.1.1:
    resolution: {integrity: sha512-+DWg8jCJG2TEnpy7kOm/7/AxaYoaRbjVB4LFZLySZlWn8exGs3A4OLJR966cVvU26N7X9TWxl+Jsw7dzAqKT6g==}
    engines: {node: '>=16'}

  json5@2.2.3:
    resolution: {integrity: sha512-XmOWe7eyHYH14cLdVPoyg+GOH3rYX++KpzrylJwSW98t3Nk+U8XOl8FWKOgwtzdb8lXGf6zYwDUzeHMWfxasyg==}
    engines: {node: '>=6'}
    hasBin: true

  jsonfile@4.0.0:
    resolution: {integrity: sha512-m6F1R3z8jjlf2imQHS2Qez5sjKWQzbuuhuJ/FKYFRZvPE3PuHcSMVZzfsLhGVOkfd20obL5SWEBew5ShlquNxg==}

  kleur@4.1.5:
    resolution: {integrity: sha512-o+NO+8WrRiQEE4/7nwRJhN1HWpVmJm511pBHUxPLtp0BUISzlBplORYSmTclCnJvQq2tKu/sgl3xVpkc7ZWuQQ==}
    engines: {node: '>=6'}

  lerc@3.0.0:
    resolution: {integrity: sha512-Rm4J/WaHhRa93nCN2mwWDZFoRVF18G1f47C+kvQWyHGEZxFpTUi73p7lMVSAndyxGt6lJ2/CFbOcf9ra5p8aww==}

  lilconfig@3.1.3:
    resolution: {integrity: sha512-/vlFKAoH5Cgt3Ie+JLhRbwOsCQePABiU3tJ1egGvyQ+33R/vcwM2Zl2QR/LzjsBeItPt3oSVXapn+m4nQDvpzw==}
    engines: {node: '>=14'}

  lines-and-columns@1.2.4:
    resolution: {integrity: sha512-7ylylesZQ/PV29jhEDl3Ufjo6ZX7gCqJr5F7PKrqc93v7fzSymt1BpwEU8nAUXs8qzzvqhbjhK5QZg6Mt/HkBg==}

  local-pkg@0.5.1:
    resolution: {integrity: sha512-9rrA30MRRP3gBD3HTGnC6cDFpaE1kVDWxWgqWJUN0RvDNAo+Nz/9GxB+nHOH0ifbVFy0hSA1V6vFDvnx54lTEQ==}
    engines: {node: '>=14'}

  locate-character@3.0.0:
    resolution: {integrity: sha512-SW13ws7BjaeJ6p7Q6CO2nchbYEc3X3J6WrmTTDto7yMPqVSZTUyY5Tjbid+Ab8gLnATtygYtiDIJGQRRn2ZOiA==}

  locate-path@5.0.0:
    resolution: {integrity: sha512-t7hw9pI+WvuwNJXwk5zVHpyhIqzg2qTlklJOf0mVxGSbe3Fp2VieZcduNYjaLDoy6p9uGpQEGWG87WpMKlNq8g==}
    engines: {node: '>=8'}

  locate-path@6.0.0:
    resolution: {integrity: sha512-iPZK6eYjbxRu3uB4/WZ3EsEIMJFMqAoopl3R+zuq0UjcAm/MO6KCweDgPfP3elTztoKP3KtnVHxTn2NHBSDVUw==}
    engines: {node: '>=10'}

  lodash.startcase@4.4.0:
    resolution: {integrity: sha512-+WKqsK294HMSc2jEbNgpHpd0JfIBhp7rEV4aqXWqFr6AlXov+SlcgB1Fv01y2kGe3Gc8nMW7VA0SrGuSkRfIEg==}

  loupe@2.3.7:
    resolution: {integrity: sha512-zSMINGVYkdpYSOBmLi0D1Uo7JU9nVdQKrHxC8eYlV+9YKK9WePqAlL7lSlorG/U2Fw1w0hTBmaa/jrQ3UbPHtA==}

  loupe@3.2.1:
    resolution: {integrity: sha512-CdzqowRJCeLU72bHvWqwRBBlLcMEtIvGrlvef74kMnV2AolS9Y8xUv1I0U/MNAWMhBlKIoyuEgoJ0t/bbwHbLQ==}

  lru-cache@10.4.3:
    resolution: {integrity: sha512-JNAzZcXrCt42VGLuYz0zfAzDfAvJWW6AfYlDBQyDV5DClI2m5sAmK+OIO7s59XfsRsWHp02jAJrRadPRGTt6SQ==}

  lru-cache@11.3.5:
    resolution: {integrity: sha512-NxVFwLAnrd9i7KUBxC4DrUhmgjzOs+1Qm50D3oF1/oL+r1NpZ4gA7xvG0/zJ8evR7zIKn4vLf7qTNduWFtCrRw==}
    engines: {node: 20 || >=22}

  lru-cache@5.1.1:
    resolution: {integrity: sha512-KpNARQA3Iwv+jTA0utUVVbrh+Jlrr1Fv0e56GGzAFOXN7dk/FviaDW8LHmK52DlcH4WP2n6gI8vN1aesBFgo9w==}

  lz-string@1.5.0:
    resolution: {integrity: sha512-h5bgJWpxJNswbU7qCrV0tIKQCaS3blPDrqKWx+QxzuzL1zGUzij9XCWLrSLsJPu5t+eWA/ycetzYAO5IOMcWAQ==}
    hasBin: true

  magic-string@0.30.21:
    resolution: {integrity: sha512-vd2F4YUyEXKGcLHoq+TEyCjxueSeHnFxyyjNp80yg0XV4vUhnDer/lvvlqM/arB5bXQN5K2/3oinyCRyx8T2CQ==}

  math-intrinsics@1.1.0:
    resolution: {integrity: sha512-/IXtbwEk5HTPyEwyKX6hGkYXxM9nbj64B+ilVJnC/R6B0pH5G4V3b0pVbL7DBj4tkhBAppbQUlf6F6Xl9LHu1g==}
    engines: {node: '>= 0.4'}

  md5.js@1.3.5:
    resolution: {integrity: sha512-xitP+WxNPcTTOgnTJcrhM0xvdPepipPSf3I8EIpGKeFLjt3PlJLIDG3u8EX53ZIubkb+5U2+3rELYpEhHhzdkg==}

  media-typer@0.3.0:
    resolution: {integrity: sha512-dq+qelQ9akHpcOl/gUVRTxVIOkAJ1wR3QAvb4RsVjS8oVoFjDGTc679wJYmUmknUF5HwMLOgb5O+a3KxfWapPQ==}
    engines: {node: '>= 0.6'}

  merge-descriptors@1.0.3:
    resolution: {integrity: sha512-gaNvAS7TZ897/rVaZ0nMtAyxNyi/pdbjbAwUpFQpN70GqnVfOiXpeUUMKRBmzXaSQ8DdTX4/0ms62r2K+hE6mQ==}

  merge-stream@2.0.0:
    resolution: {integrity: sha512-abv/qOcuPfk3URPfDzmZU1LKmuw8kT+0nIHvKrKgFrwifol/doWcdA4ZqsWQ8ENrFKkd67Mfpo/LovbIUsbt3w==}

  merge2@1.4.1:
    resolution: {integrity: sha512-8q7VEgMJW4J8tcfVPy8g09NcQwZdbwFEqhe/WZkoIzjn/3TGDwtOCYtXGxA3O8tPzpczCCDgv+P2P5y00ZJOOg==}
    engines: {node: '>= 8'}

  meshoptimizer@0.18.1:
    resolution: {integrity: sha512-ZhoIoL7TNV4s5B6+rx5mC//fw8/POGyNxS/DZyCJeiZ12ScLfVwRE/GfsxwiTkMYYD5DmK2/JXnEVXqL4rF+Sw==}

  methods@1.1.2:
    resolution: {integrity: sha512-iclAHeNqNm68zFtnZ0e+1L2yUIdvzNoauKU4WBA3VvH/vPFieF7qfRlwUZU+DA9P9bPXIS90ulxoUoCH23sV2w==}
    engines: {node: '>= 0.6'}

  micromatch@4.0.8:
    resolution: {integrity: sha512-PXwfBhYu0hBCPw8Dn0E+WDYb7af3dSLVWKi3HGv84IdF4TyFoC0ysxFd0Goxw7nSv4T/PzEJQxsYsEiFCKo2BA==}
    engines: {node: '>=8.6'}

  miller-rabin@4.0.1:
    resolution: {integrity: sha512-115fLhvZVqWwHPbClyntxEVfVDfl9DLLTuJvq3g2O/Oxi8AiNouAHvDSzHS0viUJc+V5vm3eq91Xwqn9dp4jRA==}
    hasBin: true

  mime-db@1.52.0:
    resolution: {integrity: sha512-sPU4uV7dYlvtWJxwwxHD0PuihVNiE7TyAbQ5SWxDCB9mUYvOgroQOwYQQOKPJ8CIbE+1ETVlOoK1UC2nU3gYvg==}
    engines: {node: '>= 0.6'}

  mime-types@2.1.35:
    resolution: {integrity: sha512-ZDY+bPm5zTTF+YpCrAU9nK0UgICYPT0QtT1NZWFv4s++TNkcgVaT0g6+4R2uI4MjQjzysHB1zxuWL50hzaeXiw==}
    engines: {node: '>= 0.6'}

  mime@1.6.0:
    resolution: {integrity: sha512-x0Vn8spI+wuJ1O6S7gnbaQg8Pxh4NNHb7KSINmEWKiPE4RKOplvijn+NkmYmmRgP68mc70j2EbeTFRsrswaQeg==}
    engines: {node: '>=4'}
    hasBin: true

  mimic-fn@4.0.0:
    resolution: {integrity: sha512-vqiC06CuhBTUdZH+RYl8sFrL096vA45Ok5ISO6sE/Mr1jRbGH4Csnhi8f3wKVl7x8mO4Au7Ir9D3Oyv1VYMFJw==}
    engines: {node: '>=12'}

  min-indent@1.0.1:
    resolution: {integrity: sha512-I9jwMn07Sy/IwOj3zVkVik2JTvgpaykDZEigL6Rx6N9LbMywwUSMtxET+7lVoDLLd3O3IXwJwvuuns8UB/HeAg==}
    engines: {node: '>=4'}

  minimalistic-assert@1.0.1:
    resolution: {integrity: sha512-UtJcAD4yEaGtjPezWuO9wC4nwUnVH/8/Im3yEHQP4b67cXlD/Qr9hdITCU1xDbSEXg2XKNaP8jsReV7vQd00/A==}

  minimalistic-crypto-utils@1.0.1:
    resolution: {integrity: sha512-JIYlbt6g8i5jKfJ3xz7rF0LXmv2TkDxBLUkiBeZ7bAx4GnnNMr8xFpGnOxn6GhTEHx3SjRrZEoU+j04prX1ktg==}

  minimatch@10.2.5:
    resolution: {integrity: sha512-MULkVLfKGYDFYejP07QOurDLLQpcjk7Fw+7jXS2R2czRQzR56yHRveU5NDJEOviH+hETZKSkIk5c+T23GjFUMg==}
    engines: {node: 18 || 20 || >=22}

  minipass@7.1.3:
    resolution: {integrity: sha512-tEBHqDnIoM/1rXME1zgka9g6Q2lcoCkxHLuc7ODJ5BxbP5d4c2Z5cGgtXAku59200Cx7diuHTOYfSBD8n6mm8A==}
    engines: {node: '>=16 || 14 >=14.17'}

  mlly@1.8.2:
    resolution: {integrity: sha512-d+ObxMQFmbt10sretNDytwt85VrbkhhUA/JBGm1MPaWJ65Cl4wOgLaB1NYvJSZ0Ef03MMEU/0xpPMXUIQ29UfA==}

  mri@1.2.0:
    resolution: {integrity: sha512-tzzskb3bG8LvYGFF/mDTpq3jpI6Q9wc3LEmBaghu+DdCssd1FakN7Bc0hVNmEyGq1bq3RgfkCb3cmQLpNPOroA==}
    engines: {node: '>=4'}

  ms@2.0.0:
    resolution: {integrity: sha512-Tpp60P6IUJDTuOq/5Z8cdskzJujfwqfOTkrwIwj7IRISpnkJnT6SyJ4PCPnGMoFjC9ddhal5KVIYtAt97ix05A==}

  ms@2.1.3:
    resolution: {integrity: sha512-6FlzubTLZG3J2a/NVCAleEhjzq5oxgHyaCU9yYXvcLsvoVaHJq/s5xXI6/XXP6tz7R9xAOtHnSO/tXtF3WRTlA==}

  mz@2.7.0:
    resolution: {integrity: sha512-z81GNO7nnYMEhrGh9LeymoE4+Yr0Wn5McHIZMK5cfQCl+NDX08sCZgUc9/6MHni9IWuFLm1Z3HTCXu2z9fN62Q==}

  nanoid@3.3.11:
    resolution: {integrity: sha512-N8SpfPUnUp1bK+PMYW8qSWdl9U+wwNWI4QKxOYDy9JAro3WMX7p2OeVRF9v+347pnakNevPmiHhNmZ2HbFA76w==}
    engines: {node: ^10 || ^12 || ^13.7 || ^14 || >=15.0.1}
    hasBin: true

  negotiator@0.6.3:
    resolution: {integrity: sha512-+EUsqGPLsM+j/zdChZjsnX51g4XrHFOIXwfnCVPGlQk/k5giakcKsuxCObBRu6DSm9opw/O6slWbJdghQM4bBg==}
    engines: {node: '>= 0.6'}

  node-domexception@1.0.0:
    resolution: {integrity: sha512-/jKZoMpw0F8GRwl4/eLROPA3cfcXtLApP0QzLmUT/HuPCZWyB7IY9ZrMeKw2O/nFIqPQB3PVM9aYm0F312AXDQ==}
    engines: {node: '>=10.5.0'}
    deprecated: Use your platform's native DOMException instead

  node-fetch@2.7.0:
    resolution: {integrity: sha512-c4FRfUm/dbcWZ7U+1Wq0AwCyFL+3nt2bEw05wfxSz+DWpWsitgmSgYmy2dQdWyKC1694ELPqMs/YzUSNozLt8A==}
    engines: {node: 4.x || >=6.0.0}
    peerDependencies:
      encoding: ^0.1.0
    peerDependenciesMeta:
      encoding:
        optional: true

  node-gyp-build-optional-packages@5.1.1:
    resolution: {integrity: sha512-+P72GAjVAbTxjjwUmwjVrqrdZROD4nf8KgpBoDxqXXTiYZZt/ud60dE5yvCSr9lRO8e8yv6kgJIC0K0PfZFVQw==}
    hasBin: true

  node-releases@2.0.37:
    resolution: {integrity: sha512-1h5gKZCF+pO/o3Iqt5Jp7wc9rH3eJJ0+nh/CIoiRwjRxde/hAHyLPXYN4V3CqKAbiZPSeJFSWHmJsbkicta0Eg==}

  node-stdlib-browser@1.3.1:
    resolution: {integrity: sha512-X75ZN8DCLftGM5iKwoYLA3rjnrAEs97MkzvSd4q2746Tgpg8b8XWiBGiBG4ZpgcAqBgtgPHTiAc8ZMCvZuikDw==}
    engines: {node: '>=10'}

  normalize-path@3.0.0:
    resolution: {integrity: sha512-6eZs5Ls3WtCisHWp9S2GUy8dqkpGi4BVSz3GaqiE6ezub0512ESztXUwUB6C6IKbQkY2Pnb/mD4WYojCRwcwLA==}
    engines: {node: '>=0.10.0'}

  npm-run-path@5.3.0:
    resolution: {integrity: sha512-ppwTtiJZq0O/ai0z7yfudtBpWIoxM8yE6nHi1X47eFR2EWORqfbu6CnPlNsjeN683eT0qG6H/Pyf9fCcvjnnnQ==}
    engines: {node: ^12.20.0 || ^14.13.1 || >=16.0.0}

  nwsapi@2.2.23:
    resolution: {integrity: sha512-7wfH4sLbt4M0gCDzGE6vzQBo0bfTKjU7Sfpqy/7gs1qBfYz2vEJH6vXcBKpO3+6Yu1telwd0t9HpyOoLEQQbIQ==}

  object-assign@4.1.1:
    resolution: {integrity: sha512-rJgTQnkUnH1sFw8yT6VSU3zD3sWmu6sZhIseY8VX+GRu3P6F7Fu+JNDoXfklElbLJSnc3FUQHVe4cU5hj+BcUg==}
    engines: {node: '>=0.10.0'}

  object-hash@3.0.0:
    resolution: {integrity: sha512-RSn9F68PjH9HqtltsSnqYC1XXoWe9Bju5+213R98cNGttag9q9yAOTzdbsqvIa7aNm5WffBZFpWYr2aWrklWAw==}
    engines: {node: '>= 6'}

  object-inspect@1.13.4:
    resolution: {integrity: sha512-W67iLl4J2EXEGTbfeHCffrjDfitvLANg0UlX3wFUUSTx92KXRFegMHUVgSqE+wvhAbi4WqjGg9czysTV2Epbew==}
    engines: {node: '>= 0.4'}

  object-is@1.1.6:
    resolution: {integrity: sha512-F8cZ+KfGlSGi09lJT7/Nd6KJZ9ygtvYC0/UYYLI9nmQKLMnydpB9yvbv9K1uSkEu7FU9vYPmVwLg328tX+ot3Q==}
    engines: {node: '>= 0.4'}

  object-keys@1.1.1:
    resolution: {integrity: sha512-NuAESUOUMrlIXOfHKzD6bpPu3tYt3xvjNdRIQ+FeT0lNb4K8WR70CaDxhuNguS2XG+GjkyMwOzsN5ZktImfhLA==}
    engines: {node: '>= 0.4'}

  object.assign@4.1.7:
    resolution: {integrity: sha512-nK28WOo+QIjBkDduTINE4JkF/UJJKyf2EJxvJKfblDpyg0Q+pkOHNTL0Qwy6NP6FhE/EnzV73BxxqcJaXY9anw==}
    engines: {node: '>= 0.4'}

  on-finished@2.4.1:
    resolution: {integrity: sha512-oVlzkg3ENAhCk2zdv7IJwd/QUD4z2RxRwpkcGY8psCVcCYZNq4wYnVWALHM+brtuJjePWiYF/ClmuDr8Ch5+kg==}
    engines: {node: '>= 0.8'}

  onetime@6.0.0:
    resolution: {integrity: sha512-1FlR+gjXK7X+AsAHso35MnyN5KqGwJRi/31ft6x0M194ht7S+rWAvd7PHss9xSKMzE0asv1pyIHaJYq+BbacAQ==}
    engines: {node: '>=12'}

  os-browserify@0.3.0:
    resolution: {integrity: sha512-gjcpUc3clBf9+210TRaDWbf+rZZZEshZ+DlXMRCeAjp0xhTrnQsKHypIy1J3d5hKdUzj69t708EHtU8P6bUn0A==}

  outdent@0.5.0:
    resolution: {integrity: sha512-/jHxFIzoMXdqPzTaCpFzAAWhpkSjZPF4Vsn6jAfNpmbH/ymsmd7Qc6VE9BGn0L6YMj6uwpQLxCECpus4ukKS9Q==}

  p-filter@2.1.0:
    resolution: {integrity: sha512-ZBxxZ5sL2HghephhpGAQdoskxplTwr7ICaehZwLIlfL6acuVgZPm8yBNuRAFBGEqtD/hmUeq9eqLg2ys9Xr/yw==}
    engines: {node: '>=8'}

  p-limit@2.3.0:
    resolution: {integrity: sha512-//88mFWSJx8lxCzwdAABTJL2MyWB12+eIY7MDL2SqLmAkeKU9qxRvWuSyTjm3FUmpBEMuFfckAIqEaVGUDxb6w==}
    engines: {node: '>=6'}

  p-limit@3.1.0:
    resolution: {integrity: sha512-TYOanM3wGwNGsZN2cVTYPArw454xnXj5qmWF1bEoAc4+cU/ol7GVh7odevjp1FNHduHc3KZMcFduxU5Xc6uJRQ==}
    engines: {node: '>=10'}

  p-limit@5.0.0:
    resolution: {integrity: sha512-/Eaoq+QyLSiXQ4lyYV23f14mZRQcXnxfHrN0vCai+ak9G0pp9iEQukIIZq5NccEvwRB8PUnZT0KsOoDCINS1qQ==}
    engines: {node: '>=18'}

  p-locate@4.1.0:
    resolution: {integrity: sha512-R79ZZ/0wAxKGu3oYMlz8jy/kbhsNrS7SKZ7PxEHBgJ5+F2mtFW2fK2cOtBh1cHYkQsbzFV7I+EoRKe6Yt0oK7A==}
    engines: {node: '>=8'}

  p-locate@5.0.0:
    resolution: {integrity: sha512-LaNjtRWUBY++zB5nE/NwcaoMylSPk+S+ZHNB1TzdbMJMny6dynpAGt7X/tl/QYq3TIeE6nxHppbo2LGymrG5Pw==}
    engines: {node: '>=10'}

  p-map@2.1.0:
    resolution: {integrity: sha512-y3b8Kpd8OAN444hxfBbFfj1FY/RjtTd8tzYwhUqNYXx0fXx2iX4maP4Qr6qhIKbQXI02wTLAda4fYUbDagTUFw==}
    engines: {node: '>=6'}

  p-try@2.2.0:
    resolution: {integrity: sha512-R4nPAVTAU0B9D35/Gk3uJf/7XYbQcyohSKdvAxIRSNghFl4e71hVoGnBNQz9cWaXxO2I10KTC+3jMdvvoKw6dQ==}
    engines: {node: '>=6'}

  package-manager-detector@0.2.11:
    resolution: {integrity: sha512-BEnLolu+yuz22S56CU1SUKq3XC3PkwD5wv4ikR4MfGvnRVcmzXR9DwSlW2fEamyTPyXHomBJRzgapeuBvRNzJQ==}

  pako@1.0.11:
    resolution: {integrity: sha512-4hLB8Py4zZce5s4yd9XzopqwVv/yGNhV1Bl8NTmCq1763HeK2+EwVTv+leGeL13Dnh2wfbqowVPXCIO0z4taYw==}

  pako@2.1.0:
    resolution: {integrity: sha512-w+eufiZ1WuJYgPXbV/PO3NCMEc3xqylkKHzp8bxp1uW4qaSNQUkwmLLEc3kKsfz8lpV1F8Ht3U1Cm+9Srog2ug==}

  parse-asn1@5.1.9:
    resolution: {integrity: sha512-fIYNuZ/HastSb80baGOuPRo1O9cf4baWw5WsAp7dBuUzeTD/BoaG8sVTdlPFksBE2lF21dN+A1AnrpIjSWqHHg==}
    engines: {node: '>= 0.10'}

  parse-headers@2.0.6:
    resolution: {integrity: sha512-Tz11t3uKztEW5FEVZnj1ox8GKblWn+PvHY9TmJV5Mll2uHEwRdR/5Li1OlXoECjLYkApdhWy44ocONwXLiKO5A==}

  parse5@7.3.0:
    resolution: {integrity: sha512-IInvU7fabl34qmi9gY8XOVxhYyMyuH2xUNpb2q8/Y+7552KlejkRvqvD19nMoUW/uQGGbqNpA6Tufu5FL5BZgw==}

  parseurl@1.3.3:
    resolution: {integrity: sha512-CiyeOxFT/JZyN5m0z9PfXw4SCBJ6Sygz1Dpl0wqjlhDEGGBP1GnsUVEL0p63hoG1fcj3fHynXi9NYO4nWOL+qQ==}
    engines: {node: '>= 0.8'}

  path-browserify@1.0.1:
    resolution: {integrity: sha512-b7uo2UCUOYZcnF/3ID0lulOJi/bafxa1xPe7ZPsammBSpjSWQkjNxlt635YGS2MiR9GjvuXCtz2emr3jbsz98g==}

  path-exists@4.0.0:
    resolution: {integrity: sha512-ak9Qy5Q7jYb2Wwcey5Fpvg2KoAc/ZIhLSLOSBmRmygPsGwkVVt0fZa0qrtMz+m6tJTAHfZQ8FnmB4MG4LWy7/w==}
    engines: {node: '>=8'}

  path-key@3.1.1:
    resolution: {integrity: sha512-ojmeN0qd+y0jszEtoY48r0Peq5dwMEkIlCOu6Q5f41lfkswXuKtYrhgoTpLnyIcHm24Uhqx+5Tqm2InSwLhE6Q==}
    engines: {node: '>=8'}

  path-key@4.0.0:
    resolution: {integrity: sha512-haREypq7xkM7ErfgIyA0z+Bj4AGKlMSdlQE2jvJo6huWD1EdkKYV+G/T4nq0YEF2vgTT8kqMFKo1uHn950r4SQ==}
    engines: {node: '>=12'}

  path-parse@1.0.7:
    resolution: {integrity: sha512-LDJzPVEEEPR+y48z93A0Ed0yXb8pAByGWo/k5YYdYgpY2/2EsOsksJrq7lOHxryrVOn1ejG6oAp8ahvOIQD8sw==}

  path-scurry@2.0.2:
    resolution: {integrity: sha512-3O/iVVsJAPsOnpwWIeD+d6z/7PmqApyQePUtCndjatj/9I5LylHvt5qluFaBT3I5h3r1ejfR056c+FCv+NnNXg==}
    engines: {node: 18 || 20 || >=22}

  path-to-regexp@0.1.13:
    resolution: {integrity: sha512-A/AGNMFN3c8bOlvV9RreMdrv7jsmF9XIfDeCd87+I8RNg6s78BhJxMu69NEMHBSJFxKidViTEdruRwEk/WIKqA==}

  path-type@4.0.0:
    resolution: {integrity: sha512-gDKb8aZMDeD/tZWs9P6+q0J9Mwkdl6xMV8TjnGP3qJVJ06bdMgkbBlLU8IdfOsIsFz2BW1rNVT3XuNEl8zPAvw==}
    engines: {node: '>=8'}

  pathe@1.1.2:
    resolution: {integrity: sha512-whLdWMYL2TwI08hn8/ZqAbrVemu0LNaNNJZX73O6qaIdCTfXutsLhMkjdENX0qhsQ9uIimo4/aQOmXkoon2nDQ==}

  pathe@2.0.3:
    resolution: {integrity: sha512-WUjGcAqP1gQacoQe+OBJsFA7Ld4DyXuUIjZ5cc75cLHvJ7dtNsTugphxIADwspS+AraAUePCKrSVtPLFj/F88w==}

  pathval@1.1.1:
    resolution: {integrity: sha512-Dp6zGqpTdETdR63lehJYPeIOqpiNBNtc7BpWSLrOje7UaIsE5aY92r/AunQA7rsXvet3lrJ3JnZX29UPTKXyKQ==}

  pathval@2.0.1:
    resolution: {integrity: sha512-//nshmD55c46FuFw26xV/xFAaB5HF9Xdap7HJBBnrKdAd6/GxDBaNA1870O79+9ueg61cZLSVc+OaFlfmObYVQ==}
    engines: {node: '>= 14.16'}

  pbkdf2@3.1.5:
    resolution: {integrity: sha512-Q3CG/cYvCO1ye4QKkuH7EXxs3VC/rI1/trd+qX2+PolbaKG0H+bgcZzrTt96mMyRtejk+JMCiLUn3y29W8qmFQ==}
    engines: {node: '>= 0.10'}

  phoenix@1.8.5:
    resolution: {integrity: sha512-Oj5nlRV/NKXkjBx8uMgCMmgMf1twd/B2qOcO30cHLH1PCGR8149o4T1lRIaqN4nq2KQJAeMqPiLdh1Asd0wQFg==}

  picocolors@1.1.1:
    resolution: {integrity: sha512-xceH2snhtb5M9liqDsmEw56le376mTZkEX/jEb/RxNFyegNul7eNslCXP9FDj/Lcu0X8KEyMceP2ntpaHrDEVA==}

  picomatch@2.3.2:
    resolution: {integrity: sha512-V7+vQEJ06Z+c5tSye8S+nHUfI51xoXIXjHQ99cQtKUkQqqO1kO/KCJUfZXuB47h/YBlDhah2H3hdUGXn8ie0oA==}
    engines: {node: '>=8.6'}

  picomatch@4.0.4:
    resolution: {integrity: sha512-QP88BAKvMam/3NxH6vj2o21R6MjxZUAd6nlwAS/pnGvN9IVLocLHxGYIzFhg6fUQ+5th6P4dv4eW9jX3DSIj7A==}
    engines: {node: '>=12'}

  pify@2.3.0:
    resolution: {integrity: sha512-udgsAY+fTnvv7kI7aaxbqwWNb0AHiB0qBO89PZKPkoTmGOgdbrHDKD+0B2X4uTfJ/FT1R09r9gTsjUjNJotuog==}
    engines: {node: '>=0.10.0'}

  pify@4.0.1:
    resolution: {integrity: sha512-uB80kBFb/tfd68bVleG9T5GGsGPjJrLAUpR5PZIrhBnIaRTQRjqdJSsIKkOP6OAIFbj7GOrcudc5pNjZ+geV2g==}
    engines: {node: '>=6'}

  pirates@4.0.7:
    resolution: {integrity: sha512-TfySrs/5nm8fQJDcBDuUng3VOUKsd7S+zqvbOTiGXHfxX4wK31ard+hoNuvkicM/2YFzlpDgABOevKSsB4G/FA==}
    engines: {node: '>= 6'}

  pkg-dir@5.0.0:
    resolution: {integrity: sha512-NPE8TDbzl/3YQYY7CSS228s3g2ollTFnc+Qi3tqmqJp9Vg2ovUpixcJEo2HJScN2Ez+kEaal6y70c0ehqJBJeA==}
    engines: {node: '>=10'}

  pkg-types@1.3.1:
    resolution: {integrity: sha512-/Jm5M4RvtBFVkKWRu2BLUTNP8/M2a+UwuAX+ae4770q1qVGtfjG+WTCupoZixokjmHiry8uI+dlY8KXYV5HVVQ==}

  possible-typed-array-names@1.1.0:
    resolution: {integrity: sha512-/+5VFTchJDoVj3bhoqi6UeymcD00DAwb1nJwamzPvHEszJ4FpF6SNNbUbOS8yI56qHzdV8eK0qEfOSiodkTdxg==}
    engines: {node: '>= 0.4'}

  postcss-import@15.1.0:
    resolution: {integrity: sha512-hpr+J05B2FVYUAXHeK1YyI267J/dDDhMU6B6civm8hSY1jYJnBXxzKDKDswzJmtLHryrjhnDjqqp/49t8FALew==}
    engines: {node: '>=14.0.0'}
    peerDependencies:
      postcss: ^8.0.0

  postcss-js@4.1.0:
    resolution: {integrity: sha512-oIAOTqgIo7q2EOwbhb8UalYePMvYoIeRY2YKntdpFQXNosSu3vLrniGgmH9OKs/qAkfoj5oB3le/7mINW1LCfw==}
    engines: {node: ^12 || ^14 || >= 16}
    peerDependencies:
      postcss: ^8.4.21

  postcss-load-config@6.0.1:
    resolution: {integrity: sha512-oPtTM4oerL+UXmx+93ytZVN82RrlY/wPUV8IeDxFrzIjXOLF1pN+EmKPLbubvKHT2HC20xXsCAH2Z+CKV6Oz/g==}
    engines: {node: '>= 18'}
    peerDependencies:
      jiti: '>=1.21.0'
      postcss: '>=8.0.9'
      tsx: ^4.8.1
      yaml: ^2.4.2
    peerDependenciesMeta:
      jiti:
        optional: true
      postcss:
        optional: true
      tsx:
        optional: true
      yaml:
        optional: true

  postcss-nested@6.2.0:
    resolution: {integrity: sha512-HQbt28KulC5AJzG+cZtj9kvKB93CFCdLvog1WFLf1D+xmMvPGlBstkpTEZfK5+AN9hfJocyBFCNiqyS48bpgzQ==}
    engines: {node: '>=12.0'}
    peerDependencies:
      postcss: ^8.2.14

  postcss-selector-parser@6.1.2:
    resolution: {integrity: sha512-Q8qQfPiZ+THO/3ZrOrO0cJJKfpYCagtMUkXbnEfmgUjwXg6z/WBeOyS9APBBPCTSiDV+s4SwQGu8yFsiMRIudg==}
    engines: {node: '>=4'}

  postcss-value-parser@4.2.0:
    resolution: {integrity: sha512-1NNCs6uurfkVbeXG4S8JFT9t19m45ICnif8zWLd5oPSZ50QnwMfK+H3jv408d4jw/7Bttv5axS5IiHoLaVNHeQ==}

  postcss@8.5.9:
    resolution: {integrity: sha512-7a70Nsot+EMX9fFU3064K/kdHWZqGVY+BADLyXc8Dfv+mTLLVl6JzJpPaCZ2kQL9gIJvKXSLMHhqdRRjwQeFtw==}
    engines: {node: ^10 || ^12 || >=14}

  postgres@3.4.9:
    resolution: {integrity: sha512-GD3qdB0x1z9xgFI6cdRD6xu2Sp2WCOEoe3mtnyB5Ee0XrrL5Pe+e4CCnJrRMnL1zYtRDZmQQVbvOttLnKDLnaw==}
    engines: {node: '>=12'}

  prettier@2.8.8:
    resolution: {integrity: sha512-tdN8qQGvNjw4CHbY+XXk0JgCXn9QiF21a55rBe5LJAU+kDyC4WQn4+awm2Xfk2lQMk5fKup9XgzTZtGkjBdP9Q==}
    engines: {node: '>=10.13.0'}
    hasBin: true

  pretty-format@27.5.1:
    resolution: {integrity: sha512-Qb1gy5OrP5+zDf2Bvnzdl3jsTf1qXVMazbvCoKhtKqVs4/YK4ozX4gKQJJVyNe+cajNPn0KoC0MC3FUmaHWEmQ==}
    engines: {node: ^10.13.0 || ^12.13.0 || ^14.15.0 || >=15.0.0}

  pretty-format@29.7.0:
    resolution: {integrity: sha512-Pdlw/oPxN+aXdmM9R00JVC9WVFoCLTKJvDVLgmJ+qAffBMxsV85l/Lu7sNx4zSzPyoL2euImuEwHhOXdEgNFZQ==}
    engines: {node: ^14.15.0 || ^16.10.0 || >=18.0.0}

  process-nextick-args@2.0.1:
    resolution: {integrity: sha512-3ouUOpQhtgrbOa17J7+uxOTpITYWaGP7/AhoR3+A+/1e9skrzelGi/dXzEYyvbxubEF6Wn2ypscTKiKJFFn1ag==}

  process@0.11.10:
    resolution: {integrity: sha512-cdGef/drWFoydD1JsMzuFf8100nZl+GT+yacc2bEced5f9Rjk4z+WtFUTBu9PhOi9j/jfmBPu0mMEY4wIdAF8A==}
    engines: {node: '>= 0.6.0'}

  proxy-addr@2.0.7:
    resolution: {integrity: sha512-llQsMLSUDUPT44jdrU/O37qlnifitDP+ZwrmmZcoSKyLKvtZxpyV0n2/bD/N4tBAAZ/gJEdZU7KMraoK1+XYAg==}
    engines: {node: '>= 0.10'}

  public-encrypt@4.0.3:
    resolution: {integrity: sha512-zVpa8oKZSz5bTMTFClc1fQOnyyEzpl5ozpi1B5YcvBrdohMjH2rfsBtyXcuNuwjsDIXmBYlF2N5FlJYhR29t8Q==}

  punycode@1.4.1:
    resolution: {integrity: sha512-jmYNElW7yvO7TV33CjSmvSiE2yco3bV2czu/OzDKdMNVZQWfxCblURLhf+47syQRBntjfLdd/H0egrzIG+oaFQ==}

  punycode@2.3.1:
    resolution: {integrity: sha512-vYt7UD1U9Wg6138shLtLOvdAu+8DsC/ilFtEVHcH+wydcSpNE20AfSOduf6MkRFahL5FY7X1oU7nKVZFtfq8Fg==}
    engines: {node: '>=6'}

  pure-rand@6.1.0:
    resolution: {integrity: sha512-bVWawvoZoBYpp6yIoQtQXHZjmz35RSVHnUOTefl8Vcjr8snTPY1wnpSPMWekcFwbxI6gtmT7rSYPFvz71ldiOA==}

  qs@6.14.2:
    resolution: {integrity: sha512-V/yCWTTF7VJ9hIh18Ugr2zhJMP01MY7c5kh4J870L7imm6/DIzBsNLTXzMwUA3yZ5b/KBqLx8Kp3uRvd7xSe3Q==}
    engines: {node: '>=0.6'}

  qs@6.15.1:
    resolution: {integrity: sha512-6YHEFRL9mfgcAvql/XhwTvf5jKcOiiupt2FiJxHkiX1z4j7WL8J/jRHYLluORvc1XxB5rV20KoeK00gVJamspg==}
    engines: {node: '>=0.6'}

  quansync@0.2.11:
    resolution: {integrity: sha512-AifT7QEbW9Nri4tAwR5M/uzpBuqfZf+zwaEM/QkzEjj7NBuFD2rBuy0K3dE+8wltbezDV7JMA0WfnCPYRSYbXA==}

  querystring-es3@0.2.1:
    resolution: {integrity: sha512-773xhDQnZBMFobEiztv8LIl70ch5MSF/jUQVlhwFyBILqq96anmoctVIYz+ZRp0qbCKATTn6ev02M3r7Ga5vqA==}
    engines: {node: '>=0.4.x'}

  queue-microtask@1.2.3:
    resolution: {integrity: sha512-NuaNSa6flKT5JaSYQzJok04JzTL1CA6aGhv5rfLW3PgqA+M2ChpZQnAC8h8i4ZFkBS8X5RqkDBHA7r4hej3K9A==}

  quick-lru@6.1.2:
    resolution: {integrity: sha512-AAFUA5O1d83pIHEhJwWCq/RQcRukCkn/NSm2QsTEMle5f2hP0ChI2+3Xb051PZCkLryI/Ir1MVKviT2FIloaTQ==}
    engines: {node: '>=12'}

  randombytes@2.1.0:
    resolution: {integrity: sha512-vYl3iOX+4CKUWuxGi9Ukhie6fsqXqS9FE2Zaic4tNFD2N2QQaXOMFbuKK4QmDHC0JO6B1Zp41J0LpT0oR68amQ==}

  randomfill@1.0.4:
    resolution: {integrity: sha512-87lcbR8+MhcWcUiQ+9e+Rwx8MyR2P7qnt15ynUlbm3TU/fjbgz4GsvfSUDTemtCCtVCqb4ZcEFlyPNTh9bBTLw==}

  range-parser@1.2.1:
    resolution: {integrity: sha512-Hrgsx+orqoygnmhFbKaHE6c296J+HTAQXoxEF6gNupROmmGJRoyzfG3ccAveqCBrwr/2yxQ5BVd/GTl5agOwSg==}
    engines: {node: '>= 0.6'}

  raw-body@2.5.3:
    resolution: {integrity: sha512-s4VSOf6yN0rvbRZGxs8Om5CWj6seneMwK3oDb4lWDH0UPhWcxwOWw5+qk24bxq87szX1ydrwylIOp2uG1ojUpA==}
    engines: {node: '>= 0.8'}

  react-dom@19.2.5:
    resolution: {integrity: sha512-J5bAZz+DXMMwW/wV3xzKke59Af6CHY7G4uYLN1OvBcKEsWOs4pQExj86BBKamxl/Ik5bx9whOrvBlSDfWzgSag==}
    peerDependencies:
      react: ^19.2.5

  react-is@17.0.2:
    resolution: {integrity: sha512-w2GsyukL62IJnlaff/nRegPQR94C/XXamvMWmSHRJ4y7Ts/4ocGRmTHvOs8PSE6pB3dWOrD/nueuU5sduBsQ4w==}

  react-is@18.3.1:
    resolution: {integrity: sha512-/LLMVyas0ljjAtoYiPqYiL8VWXzUUdThrmU5+n20DZv+a+ClRoevUzw5JxU+Ieh5/c87ytoTBV9G1FiKfNJdmg==}

  react-refresh@0.17.0:
    resolution: {integrity: sha512-z6F7K9bV85EfseRCp2bzrpyQ0Gkw1uLoCel9XBVWPg/TjRj94SkJzUTGfOa4bs7iJvBWtQG0Wq7wnI0syw3EBQ==}
    engines: {node: '>=0.10.0'}

  react@19.2.5:
    resolution: {integrity: sha512-llUJLzz1zTUBrskt2pwZgLq59AemifIftw4aB7JxOqf1HY2FDaGDxgwpAPVzHU1kdWabH7FauP4i1oEeer2WCA==}
    engines: {node: '>=0.10.0'}

  read-cache@1.0.0:
    resolution: {integrity: sha512-Owdv/Ft7IjOgm/i0xvNDZ1LrRANRfew4b2prF3OWMQLxLfu3bS8FVhCsrSCMK4lR56Y9ya+AThoTpDCTxCmpRA==}

  read-yaml-file@1.1.0:
    resolution: {integrity: sha512-VIMnQi/Z4HT2Fxuwg5KrY174U1VdUIASQVWXXyqtNRtxSr9IYkn1rsI6Tb6HsrHCmB7gVpNwX6JxPTHcH6IoTA==}
    engines: {node: '>=6'}

  readable-stream@2.3.8:
    resolution: {integrity: sha512-8p0AUk4XODgIewSi0l8Epjs+EVnWiK7NoDIEGU0HhE7+ZyY8D1IMY7odu5lRrFXGg71L15KG8QrPmum45RTtdA==}

  readable-stream@3.6.2:
    resolution: {integrity: sha512-9u/sniCrY3D5WdsERHzHE4G2YCXqoG5FTHUiCC4SIbr6XcLZBY05ya9EKjYek9O5xOAwjGq+1JdGBAS7Q9ScoA==}
    engines: {node: '>= 6'}

  readdirp@3.6.0:
    resolution: {integrity: sha512-hOS089on8RduqdbhvQ5Z37A0ESjsqz6qnRcffsMU3495FuTdqSm+7bhJ29JvIOsBDEEnan5DPu9t3To9VRlMzA==}
    engines: {node: '>=8.10.0'}

  readdirp@4.1.2:
    resolution: {integrity: sha512-GDhwkLfywWL2s6vEjyhri+eXmfH6j1L7JE27WhqLeYzoh/A3DBaYGEj2H/HFZCn/kMfim73FXxEJTw06WtxQwg==}
    engines: {node: '>= 14.18.0'}

  redent@3.0.0:
    resolution: {integrity: sha512-6tDA8g98We0zd0GvVeMT9arEOnTw9qM03L9cJXaCjrip1OO764RDBLBfrB4cwzNGDj5OA5ioymC9GkizgWJDUg==}
    engines: {node: '>=8'}

  resolve-from@5.0.0:
    resolution: {integrity: sha512-qYg9KP24dD5qka9J47d0aVky0N+b4fTU89LN9iDnjB5waksiC49rvMB0PrUJQGoTmH50XPiqOvAjDfaijGxYZw==}
    engines: {node: '>=8'}

  resolve-pkg-maps@1.0.0:
    resolution: {integrity: sha512-seS2Tj26TBVOC2NIc2rOe2y2ZO7efxITtLZcGSOnHHNOQ7CkiUBfw0Iw2ck6xkIhPwLhKNLS8BO+hEpngQlqzw==}

  resolve@1.22.11:
    resolution: {integrity: sha512-RfqAvLnMl313r7c9oclB1HhUEAezcpLjz95wFH4LVuhk9JF/r22qmVP9AMmOU4vMX7Q8pN8jwNg/CSpdFnMjTQ==}
    engines: {node: '>= 0.4'}
    hasBin: true

  reusify@1.1.0:
    resolution: {integrity: sha512-g6QUff04oZpHs0eG5p83rFLhHeV00ug/Yf9nZM6fLeUrPguBTkTQOdpAWWspMh55TZfVQDPaN3NQJfbVRAxdIw==}
    engines: {iojs: '>=1.0.0', node: '>=0.10.0'}

  ripemd160@2.0.3:
    resolution: {integrity: sha512-5Di9UC0+8h1L6ZD2d7awM7E/T4uA1fJRlx6zk/NvdCCVEoAnFqvHmCuNeIKoCeIixBX/q8uM+6ycDvF8woqosA==}
    engines: {node: '>= 0.8'}

  rollup@4.60.1:
    resolution: {integrity: sha512-VmtB2rFU/GroZ4oL8+ZqXgSA38O6GR8KSIvWmEFv63pQ0G6KaBH9s07PO8XTXP4vI+3UJUEypOfjkGfmSBBR0w==}
    engines: {node: '>=18.0.0', npm: '>=8.0.0'}
    hasBin: true

  rot-js@2.2.1:
    resolution: {integrity: sha512-lItXH31vj4ebdypayCx9dh98qPr57E7jGW2lVMKxtBHooU3xpGRtLS8kdJIni232tvPJ8Sl0+aqXZj8c6W0MGw==}

  rrweb-cssom@0.7.1:
    resolution: {integrity: sha512-TrEMa7JGdVm0UThDJSx7ddw5nVm3UJS9o9CCIZ72B1vSyEZoziDqBYP3XIoi/12lKrJR8rE3jeFHMok2F/Mnsg==}

  rrweb-cssom@0.8.0:
    resolution: {integrity: sha512-guoltQEx+9aMf2gDZ0s62EcV8lsXR+0w8915TC3ITdn2YueuNjdAYh/levpU9nFaoChh9RUS5ZdQMrKfVEN9tw==}

  run-parallel@1.2.0:
    resolution: {integrity: sha512-5l4VyZR86LZ/lDxZTR6jqL8AFE2S0IFLMP26AbjsLVADxHdhB/c0GUsH+y39UfCi3dzz8OlQuPmnaJOMoDHQBA==}

  sade@1.8.1:
    resolution: {integrity: sha512-xal3CZX1Xlo/k4ApwCFrHVACi9fBqJ7V+mwhBsuf/1IOKbBy098Fex+Wa/5QMubw09pSZ/u8EY8PWgevJsXp1A==}
    engines: {node: '>=6'}

  safe-buffer@5.1.2:
    resolution: {integrity: sha512-Gd2UZBJDkXlY7GbJxfsE8/nvKkUEU1G38c1siN6QP6a9PT9MmHB8GnpscSmMJSoF8LOIrt8ud/wPtojys4G6+g==}

  safe-buffer@5.2.1:
    resolution: {integrity: sha512-rp3So07KcdmmKbGvgaNxQSJr7bGVSVk5S9Eq1F+ppbRo70+YeaDxkw5Dd8NPN+GD6bjnYm2VuPuCXmpuYvmCXQ==}

  safe-regex-test@1.1.0:
    resolution: {integrity: sha512-x/+Cz4YrimQxQccJf5mKEbIa1NzeCRNI5Ecl/ekmlYaampdNLPalVyIcCZNNH3MvmqBugV5TMYZXv0ljslUlaw==}
    engines: {node: '>= 0.4'}

  safer-buffer@2.1.2:
    resolution: {integrity: sha512-YZo3K82SD7Riyi0E1EQPojLz7kpepnSQI9IyPbHHg1XXXevb5dJI7tpyN2ADxGcQbHG7vcyRHk0cbwqcQriUtg==}

  saxes@6.0.0:
    resolution: {integrity: sha512-xAg7SOnEhrm5zI3puOOKyy1OMcMlIJZYNJY7xLBwSze0UjhPLnWfj2GF2EpT0jmzaJKIWKHLsaSSajf35bcYnA==}
    engines: {node: '>=v12.22.7'}

  scheduler@0.27.0:
    resolution: {integrity: sha512-eNv+WrVbKu1f3vbYJT/xtiF5syA5HPIMtf9IgY/nKg0sWqzAUEvqY/xm7OcZc/qafLx/iO9FgOmeSAp4v5ti/Q==}

  semver@6.3.1:
    resolution: {integrity: sha512-BR7VvDCVHO+q2xBEWskxS6DJE1qRnb7DxzUrogb71CWoSficBxYsiAGd+Kl0mmq/MprG9yArRkyrQxTO6XjMzA==}
    hasBin: true

  semver@7.7.4:
    resolution: {integrity: sha512-vFKC2IEtQnVhpT78h1Yp8wzwrf8CM+MzKMHGJZfBtzhZNycRFnXsHk6E5TxIkkMsgNS7mdX3AGB7x2QM2di4lA==}
    engines: {node: '>=10'}
    hasBin: true

  send@0.19.2:
    resolution: {integrity: sha512-VMbMxbDeehAxpOtWJXlcUS5E8iXh6QmN+BkRX1GARS3wRaXEEgzCcB10gTQazO42tpNIya8xIyNx8fll1OFPrg==}
    engines: {node: '>= 0.8.0'}

  serve-static@1.16.3:
    resolution: {integrity: sha512-x0RTqQel6g5SY7Lg6ZreMmsOzncHFU7nhnRWkKgWuMTu5NN0DR5oruckMqRvacAN9d5w6ARnRBXl9xhDCgfMeA==}
    engines: {node: '>= 0.8.0'}

  set-function-length@1.2.2:
    resolution: {integrity: sha512-pgRc4hJ4/sNjWCSS9AmnS40x3bNMDTknHgL5UaMBTMyJnU90EgWh1Rz+MC9eFu4BuN/UwZjKQuY/1v3rM7HMfg==}
    engines: {node: '>= 0.4'}

  setimmediate@1.0.5:
    resolution: {integrity: sha512-MATJdZp8sLqDl/68LfQmbP8zKPLQNV6BIZoIgrscFDQ+RsvK/BxeDQOgyxKKoh0y/8h3BqVFnCqQ/gd+reiIXA==}

  setprototypeof@1.2.0:
    resolution: {integrity: sha512-E5LDX7Wrp85Kil5bhZv46j8jOeboKq5JMmYM3gVGdGH8xFpPWXUMsNrlODCrkoxMEeNi/XZIwuRvY4XNwYMJpw==}

  sha.js@2.4.12:
    resolution: {integrity: sha512-8LzC5+bvI45BjpfXU8V5fdU2mfeKiQe1D1gIMn7XUlF3OTUrpdJpPPH4EMAnF0DsHHdSZqCdSss5qCmJKuiO3w==}
    engines: {node: '>= 0.10'}
    hasBin: true

  sharp@0.34.5:
    resolution: {integrity: sha512-Ou9I5Ft9WNcCbXrU9cMgPBcCK8LiwLqcbywW3t4oDV37n1pzpuNLsYiAV8eODnjbtQlSDwZ2cUEeQz4E54Hltg==}
    engines: {node: ^18.17.0 || ^20.3.0 || >=21.0.0}

  shebang-command@2.0.0:
    resolution: {integrity: sha512-kHxr2zZpYtdmrN1qDjrrX/Z1rR1kG8Dx+gkpK1G4eXmvXswmcE1hTWBWYUzlraYw1/yZp6YuDY77YtvbN0dmDA==}
    engines: {node: '>=8'}

  shebang-regex@3.0.0:
    resolution: {integrity: sha512-7++dFhtcx3353uBaq8DDR4NuxBetBzC7ZQOhmTQInHEd6bSrXdiEyzCvG07Z44UYdLShWUyXt5M/yhz8ekcb1A==}
    engines: {node: '>=8'}

  side-channel-list@1.0.1:
    resolution: {integrity: sha512-mjn/0bi/oUURjc5Xl7IaWi/OJJJumuoJFQJfDDyO46+hBWsfaVM65TBHq2eoZBhzl9EchxOijpkbRC8SVBQU0w==}
    engines: {node: '>= 0.4'}

  side-channel-map@1.0.1:
    resolution: {integrity: sha512-VCjCNfgMsby3tTdo02nbjtM/ewra6jPHmpThenkTYh8pG9ucZ/1P8So4u4FGBek/BjpOVsDCMoLA/iuBKIFXRA==}
    engines: {node: '>= 0.4'}

  side-channel-weakmap@1.0.2:
    resolution: {integrity: sha512-WPS/HvHQTYnHisLo9McqBHOJk2FkHO/tlpvldyrnem4aeQp4hai3gythswg6p01oSoTl58rcpiFAjF2br2Ak2A==}
    engines: {node: '>= 0.4'}

  side-channel@1.1.0:
    resolution: {integrity: sha512-ZX99e6tRweoUXqR+VBrslhda51Nh5MTQwou5tnUDgbtyM0dBgmhEDtWGP/xbKn6hqfPRHujUNwz5fy/wbbhnpw==}
    engines: {node: '>= 0.4'}

  siginfo@2.0.0:
    resolution: {integrity: sha512-ybx0WO1/8bSBLEWXZvEd7gMW3Sn3JFlW3TvX1nREbDLRNQNaeNN8WK0meBwPdAaOI7TtRRRJn/Es1zhrrCHu7g==}

  signal-exit@4.1.0:
    resolution: {integrity: sha512-bzyZ1e88w9O1iNJbKnOlvYTrWPDl46O1bG0D3XInv+9tkPrxrN8jUUTiFlDkkmKWgn1M6CfIA13SuGqOa9Korw==}
    engines: {node: '>=14'}

  slash@3.0.0:
    resolution: {integrity: sha512-g9Q1haeby36OSStwb4ntCGGGaKsaVSjQ68fBxoQcutl5fS1vuY18H3wSt3jFyFtrkx+Kz0V1G85A4MyAdDMi2Q==}
    engines: {node: '>=8'}

  source-map-js@1.2.1:
    resolution: {integrity: sha512-UXWMKhLOwVKb728IUtQPXxfYU+usdybtUrK/8uGE8CQMvrhOpwvzDBwj0QhSL7MQc7vIsISBG8VQ8+IDQxpfQA==}
    engines: {node: '>=0.10.0'}

  source-map-support@0.5.21:
    resolution: {integrity: sha512-uBHU3L3czsIyYXKX88fdrGovxdSCoTGDRZ6SYXtSRxLZUzHg5P/66Ht6uoUlHu9EZod+inXhKo3qQgwXUT/y1w==}

  source-map@0.6.1:
    resolution: {integrity: sha512-UjgapumWlbMhkBgzT7Ykc5YXUT46F0iKu8SGXq0bcwP5dz/h0Plj6enJqjz1Zbq2l5WaqYnrVbwWOWMyF3F47g==}
    engines: {node: '>=0.10.0'}

  spawndamnit@3.0.1:
    resolution: {integrity: sha512-MmnduQUuHCoFckZoWnXsTg7JaiLBJrKFj9UI2MbRPGaJeVpsLcVBu6P/IGZovziM/YBsellCmsprgNA+w0CzVg==}

  sprintf-js@1.0.3:
    resolution: {integrity: sha512-D9cPgkvLlV3t3IzL0D0YLvGA9Ahk4PcvVwUbN0dSGr1aP0Nrt4AEnTUbuGvquEC0mA64Gqt1fzirlRs5ibXx8g==}

  stackback@0.0.2:
    resolution: {integrity: sha512-1XMJE5fQo1jGH6Y/7ebnwPOBEkIEnT4QF32d5R1+VXdXveM0IBMJt8zfaxX1P3QhVwrYe+576+jkANtSS2mBbw==}

  standardwebhooks@1.0.0:
    resolution: {integrity: sha512-BbHGOQK9olHPMvQNHWul6MYlrRTAOKn03rOe4A8O3CLWhNf4YHBqq2HJKKC+sfqpxiBY52pNeesD6jIiLDz8jg==}

  statuses@2.0.2:
    resolution: {integrity: sha512-DvEy55V3DB7uknRo+4iOGT5fP1slR8wQohVdknigZPMpMstaKJQWhwiYBACJE3Ul2pTnATihhBYnRhZQHGBiRw==}
    engines: {node: '>= 0.8'}

  std-env@3.10.0:
    resolution: {integrity: sha512-5GS12FdOZNliM5mAOxFRg7Ir0pWz8MdpYm6AY6VPkGpbA7ZzmbzNcBJQ0GPvvyWgcY7QAhCgf9Uy89I03faLkg==}

  stream-browserify@3.0.0:
    resolution: {integrity: sha512-H73RAHsVBapbim0tU2JwwOiXUj+fikfiaoYAKHF3VJfA0pe2BCzkhAHBlLG6REzE+2WNZcxOXjK7lkso+9euLA==}

  stream-http@3.2.0:
    resolution: {integrity: sha512-Oq1bLqisTyK3TSCXpPbT4sdeYNdmyZJv1LxpEm2vu1ZhK89kSE5YXwZc3cWk0MagGaKriBh9mCFbVGtO+vY29A==}

  string_decoder@1.1.1:
    resolution: {integrity: sha512-n/ShnvDi6FHbbVfviro+WojiFzv+s8MPMHBczVePfUpDJLwoLT0ht1l4YwBCbi8pJAveEEdnkHyPyTP/mzRfwg==}

  string_decoder@1.3.0:
    resolution: {integrity: sha512-hkRX8U1WjJFd8LsDJ2yQ/wWWxaopEsABU1XfkM8A+j0+85JAGppt16cr1Whg6KIbb4okU6Mql6BOj+uup/wKeA==}

  strip-ansi@6.0.1:
    resolution: {integrity: sha512-Y38VPSHcqkFrCpFnQ9vuSXmquuv5oXOKpGeT6aGrr3o3Gc9AlVa6JBfUSOCnbxGGZF+/0ooI7KrPuUSztUdU5A==}
    engines: {node: '>=8'}

  strip-bom@3.0.0:
    resolution: {integrity: sha512-vavAMRXOgBVNF6nyEEmL3DBK19iRpDcoIwW+swQ+CbGiu7lju6t+JklA1MHweoWtadgt4ISVUsXLyDq34ddcwA==}
    engines: {node: '>=4'}

  strip-final-newline@3.0.0:
    resolution: {integrity: sha512-dOESqjYr96iWYylGObzd39EuNTa5VJxyvVAEm5Jnh7KGo75V43Hk1odPQkNDyXNmUR6k+gEiDVXnjB8HJ3crXw==}
    engines: {node: '>=12'}

  strip-indent@3.0.0:
    resolution: {integrity: sha512-laJTa3Jb+VQpaC6DseHhF7dXVqHTfJPCRDaEbid/drOhgitgYku/letMUqOXFoWV0zIIUbjpdH2t+tYj4bQMRQ==}
    engines: {node: '>=8'}

  strip-literal@2.1.1:
    resolution: {integrity: sha512-631UJ6O00eNGfMiWG78ck80dfBab8X6IVFB51jZK5Icd7XAs60Z5y7QdSd/wGIklnWvRbUNloVzhOKKmutxQ6Q==}

  strip-literal@3.1.0:
    resolution: {integrity: sha512-8r3mkIM/2+PpjHoOtiAW8Rg3jJLHaV7xPwG+YRGrv6FP0wwk/toTpATxWYOW0BKdWwl82VT2tFYi5DlROa0Mxg==}

  style-mod@4.1.3:
    resolution: {integrity: sha512-i/n8VsZydrugj3Iuzll8+x/00GH2vnYsk1eomD8QiRrSAeW6ItbCQDtfXCeJHd0iwiNagqjQkvpvREEPtW3IoQ==}

  sucrase@3.35.1:
    resolution: {integrity: sha512-DhuTmvZWux4H1UOnWMB3sk0sbaCVOoQZjv8u1rDoTV0HTdGem9hkAZtl4JZy8P2z4Bg0nT+YMeOFyVr4zcG5Tw==}
    engines: {node: '>=16 || 14 >=14.17'}
    hasBin: true

  supports-preserve-symlinks-flag@1.0.0:
    resolution: {integrity: sha512-ot0WnXS9fgdkgIcePe6RHNk1WA8+muPa6cSjeR3V8K27q9BB1rTE3R1p7Hv0z1ZyAc8s6Vvv8DIyWf681MAt0w==}
    engines: {node: '>= 0.4'}

  svelte-check@4.4.6:
    resolution: {integrity: sha512-kP1zG81EWaFe9ZyTv4ZXv44Csi6Pkdpb7S3oj6m+K2ec/IcDg/a8LsFsnVLqm2nxtkSwsd5xPj/qFkTBgXHXjg==}
    engines: {node: '>= 18.0.0'}
    hasBin: true
    peerDependencies:
      svelte: ^4.0.0 || ^5.0.0-next.0
      typescript: '>=5.0.0'

  svelte@5.55.4:
    resolution: {integrity: sha512-q8DFohk6vUswSng95IZb9nzWJnbINZsK7OiM1snAa3qCjJBL0ZQpvMyAaVXjUukdM75J/m8UE8xwqat8Ors/zQ==}
    engines: {node: '>=18'}

  symbol-tree@3.2.4:
    resolution: {integrity: sha512-9QNk5KwDF+Bvz+PyObkmSYjI5ksVUYtjW7AU22r2NKcfLJcXp96hkDWU3+XndOsUb+AQ9QhfzfCT2O+CNWT5Tw==}

  tailwindcss@3.4.19:
    resolution: {integrity: sha512-3ofp+LL8E+pK/JuPLPggVAIaEuhvIz4qNcf3nA1Xn2o/7fb7s/TYpHhwGDv1ZU3PkBluUVaF8PyCHcm48cKLWQ==}
    engines: {node: '>=14.0.0'}
    hasBin: true

  term-size@2.2.1:
    resolution: {integrity: sha512-wK0Ri4fOGjv/XPy8SBHZChl8CM7uMc5VML7SqiQ0zG7+J5Vr+RMQDoHa2CNT6KHUnTGIXH34UDMkPzAUyapBZg==}
    engines: {node: '>=8'}

  thenify-all@1.6.0:
    resolution: {integrity: sha512-RNxQH/qI8/t3thXJDwcstUO4zeqo64+Uy/+sNVRBx4Xn2OX+OZ9oP+iJnNFqplFra2ZUVeKCSa2oVWi3T4uVmA==}
    engines: {node: '>=0.8'}

  thenify@3.3.1:
    resolution: {integrity: sha512-RVZSIV5IG10Hk3enotrhvz0T9em6cyHBLkH/YAZuKqd8hRkKhSfCGIcP2KUY0EPxndzANBmNllzWPwak+bheSw==}

  three@0.165.0:
    resolution: {integrity: sha512-cc96IlVYGydeceu0e5xq70H8/yoVT/tXBxV/W8A/U6uOq7DXc4/s1Mkmnu6SqoYGhSRWWYFOhVwvq6V0VtbplA==}

  timers-browserify@2.0.12:
    resolution: {integrity: sha512-9phl76Cqm6FhSX9Xe1ZUAMLtm1BLkKj2Qd5ApyWkXzsMRaA7dgr81kf4wJmQf/hAvg8EEyJxDo3du/0KlhPiKQ==}
    engines: {node: '>=0.6.0'}

  tinybench@2.9.0:
    resolution: {integrity: sha512-0+DUvqWMValLmha6lr4kD8iAMK1HzV0/aKnCtWb9v9641TnP/MFb7Pc2bxoxQjTXAErryXVgUOfv2YqNllqGeg==}

  tinyexec@0.3.2:
    resolution: {integrity: sha512-KQQR9yN7R5+OSwaK0XQoj22pwHoTlgYqmUscPYoknOoWCWfj/5/ABTMRi69FrKU5ffPVh5QcFikpWJI/P1ocHA==}

  tinyglobby@0.2.16:
    resolution: {integrity: sha512-pn99VhoACYR8nFHhxqix+uvsbXineAasWm5ojXoN8xEwK5Kd3/TrhNn1wByuD52UxWRLy8pu+kRMniEi6Eq9Zg==}
    engines: {node: '>=12.0.0'}

  tinypool@0.8.4:
    resolution: {integrity: sha512-i11VH5gS6IFeLY3gMBQ00/MmLncVP7JLXOw1vlgkytLmJK7QnEr7NXf0LBdxfmNPAeyetukOk0bOYrJrFGjYJQ==}
    engines: {node: '>=14.0.0'}

  tinypool@1.1.1:
    resolution: {integrity: sha512-Zba82s87IFq9A9XmjiX5uZA/ARWDrB03OHlq+Vw1fSdt0I+4/Kutwy8BP4Y/y/aORMo61FQ0vIb5j44vSo5Pkg==}
    engines: {node: ^18.0.0 || >=20.0.0}

  tinyrainbow@2.0.0:
    resolution: {integrity: sha512-op4nsTR47R6p0vMUUoYl/a+ljLFVtlfaXkLQmqfLR1qHma1h/ysYk4hEXZ880bf2CYgTskvTa/e196Vd5dDQXw==}
    engines: {node: '>=14.0.0'}

  tinyspy@2.2.1:
    resolution: {integrity: sha512-KYad6Vy5VDWV4GH3fjpseMQ/XU2BhIYP7Vzd0LG44qRWm/Yt2WCOTicFdvmgo6gWaqooMQCawTtILVQJupKu7A==}
    engines: {node: '>=14.0.0'}

  tinyspy@4.0.4:
    resolution: {integrity: sha512-azl+t0z7pw/z958Gy9svOTuzqIk6xq+NSheJzn5MMWtWTFywIacg2wUlzKFGtt3cthx0r2SxMK0yzJOR0IES7Q==}
    engines: {node: '>=14.0.0'}

  tldts-core@6.1.86:
    resolution: {integrity: sha512-Je6p7pkk+KMzMv2XXKmAE3McmolOQFdxkKw0R8EYNr7sELW46JqnNeTX8ybPiQgvg1ymCoF8LXs5fzFaZvJPTA==}

  tldts@6.1.86:
    resolution: {integrity: sha512-WMi/OQ2axVTf/ykqCQgXiIct+mSQDFdH2fkwhPwgEwvJ1kSzZRiinb0zF2Xb8u4+OqPChmyI6MEu4EezNJz+FQ==}
    hasBin: true

  to-buffer@1.2.2:
    resolution: {integrity: sha512-db0E3UJjcFhpDhAF4tLo03oli3pwl3dbnzXOUIlRKrp+ldk/VUxzpWYZENsw2SZiuBjHAk7DfB0VU7NKdpb6sw==}
    engines: {node: '>= 0.4'}

  to-regex-range@5.0.1:
    resolution: {integrity: sha512-65P7iz6X5yEr1cwcgvQxbbIw7Uk3gOy5dIdtZ4rDveLqhrdJP+Li/Hx6tyK0NEb+2GCyneCMJiGqrADCSNk8sQ==}
    engines: {node: '>=8.0'}

  toidentifier@1.0.1:
    resolution: {integrity: sha512-o5sSPKEkg/DIQNmH43V0/uerLrpzVedkUh8tGNvaeXpfpuwjKenlSox/2O/BTlZUtEe+JG7s5YhEz608PlAHRA==}
    engines: {node: '>=0.6'}

  tough-cookie@5.1.2:
    resolution: {integrity: sha512-FVDYdxtnj0G6Qm/DhNPSb8Ju59ULcup3tuJxkFb5K8Bv2pUXILbf0xZWU8PX8Ov19OXljbUyveOFwRMwkXzO+A==}
    engines: {node: '>=16'}

  tr46@0.0.3:
    resolution: {integrity: sha512-N3WMsuqV66lT30CrXNbEjx4GEwlow3v6rr4mCcv6prnfwhS01rkgyFdjPNBYd9br7LpXV1+Emh01fHnq2Gdgrw==}

  tr46@5.1.1:
    resolution: {integrity: sha512-hdF5ZgjTqgAntKkklYw0R03MG2x/bSzTtkxmIRw/sTNV8YXsCJ1tfLAX23lhxhHJlEf3CRCOCGGWw3vI3GaSPw==}
    engines: {node: '>=18'}

  ts-algebra@2.0.0:
    resolution: {integrity: sha512-FPAhNPFMrkwz76P7cdjdmiShwMynZYN6SgOujD1urY4oNm80Ou9oMdmbR45LotcKOXoy7wSmHkRFE6Mxbrhefw==}

  ts-interface-checker@0.1.13:
    resolution: {integrity: sha512-Y/arvbn+rrz3JCKl9C4kVNfTfSm2/mEp5FSz5EsZSANGPSlQrpRI5M4PKF+mJnE52jOO90PnPSc3Ur3bTQw0gA==}

  ts-morph@28.0.0:
    resolution: {integrity: sha512-Wp3tnZ2bzwxyTZMtgWVzXDfm7lB1Drz+y9DmmYH/L702PQhPyVrp3pkou3yIz4qjS14GY9kcpmLiOOMvl8oG1g==}

  tslib@2.8.1:
    resolution: {integrity: sha512-oJFu94HQb+KVduSUQL7wnpmqnfmLsOA/nAh6b6EH0wCEoK0/mPeXU6c3wKDV83MkOuHPRHtSXKKU99IBazS/2w==}

  tsx@4.21.0:
    resolution: {integrity: sha512-5C1sg4USs1lfG0GFb2RLXsdpXqBSEhAaA/0kPL01wxzpMqLILNxIxIOKiILz+cdg/pLnOUxFYOR5yhHU666wbw==}
    engines: {node: '>=18.0.0'}
    hasBin: true

  tty-browserify@0.0.1:
    resolution: {integrity: sha512-C3TaO7K81YvjCgQH9Q1S3R3P3BtN3RIM8n+OvX4il1K1zgE8ZhI0op7kClgkxtutIE8hQrcrHBXvIheqKUUCxw==}

  type-detect@4.1.0:
    resolution: {integrity: sha512-Acylog8/luQ8L7il+geoSxhEkazvkslg7PSNKOX59mbB9cOveP5aq9h74Y7YU8yDpJwetzQQrfIwtf4Wp4LKcw==}
    engines: {node: '>=4'}

  type-is@1.6.18:
    resolution: {integrity: sha512-TkRKr9sUTxEH8MdfuCSP7VizJyzRNMjj2J2do2Jr3Kym598JVdEksuzPQCnlFPW4ky9Q+iA+ma9BGm06XQBy8g==}
    engines: {node: '>= 0.6'}

  typed-array-buffer@1.0.3:
    resolution: {integrity: sha512-nAYYwfY3qnzX30IkA6AQZjVbtK6duGontcQm1WSG1MD94YLqK0515GNApXkoxKOWMusVssAHWLh9SeaoefYFGw==}
    engines: {node: '>= 0.4'}

  typescript@5.8.3:
    resolution: {integrity: sha512-p1diW6TqL9L07nNxvRMM7hMMw4c5XOo/1ibL4aAIGmSAt9slTE1Xgw5KWuof2uTOvCg9BY7ZRi+GaF+7sfgPeQ==}
    engines: {node: '>=14.17'}
    hasBin: true

  ufo@1.6.3:
    resolution: {integrity: sha512-yDJTmhydvl5lJzBmy/hyOAA0d+aqCBuwl818haVdYCRrWV84o7YyeVm4QlVHStqNrrJSTb6jKuFAVqAFsr+K3Q==}

  undici-types@5.26.5:
    resolution: {integrity: sha512-JlCMO+ehdEIKqlFxk6IfVoAUVmgz7cU7zD/h9XZ0qzeosSHmUJVOzSQvvYSYWXkFXC+IfLKSIffhv0sVZup6pA==}

  undici-types@6.21.0:
    resolution: {integrity: sha512-iwDZqg0QAGrg9Rav5H4n0M64c3mkR59cJ6wQp+7C4nI0gsmExaedaYLNO44eT4AtBBwjbTiGPMlt2Md0T9H9JQ==}

  universalify@0.1.2:
    resolution: {integrity: sha512-rBJeI5CXAlmy1pV+617WB9J63U6XcazHHF2f2dbJix4XzpUF0RS3Zbj0FGIOCAva5P/d/GBOYaACQ1w+0azUkg==}
    engines: {node: '>= 4.0.0'}

  unpipe@1.0.0:
    resolution: {integrity: sha512-pjy2bYhSsufwWlKwPc+l3cN7+wuJlK6uz0YdJEOlQDbl6jo/YlPi4mb8agUkVC8BF7V8NuzeyPNqRksA3hztKQ==}
    engines: {node: '>= 0.8'}

  update-browserslist-db@1.2.3:
    resolution: {integrity: sha512-Js0m9cx+qOgDxo0eMiFGEueWztz+d4+M3rGlmKPT+T4IS/jP4ylw3Nwpu6cpTTP8R1MAC1kF4VbdLt3ARf209w==}
    hasBin: true
    peerDependencies:
      browserslist: '>= 4.21.0'

  url@0.11.4:
    resolution: {integrity: sha512-oCwdVC7mTuWiPyjLUz/COz5TLk6wgp0RCsN+wHZ2Ekneac9w8uuV0njcbbie2ME+Vs+d6duwmYuR3HgQXs1fOg==}
    engines: {node: '>= 0.4'}

  util-deprecate@1.0.2:
    resolution: {integrity: sha512-EPD5q1uXyFxJpCrLnCc1nHnq3gOa6DZBocAIiI2TaSCA7VCJ1UJDMagCzIkXNsUYfD1daK//LTEQ8xiIbrHtcw==}

  util@0.12.5:
    resolution: {integrity: sha512-kZf/K6hEIrWHI6XqOFUiiMa+79wE/D8Q+NCNAWclkyg3b4d2k7s0QGepNjiABc+aR3N1PAyHL7p6UcLY6LmrnA==}

  utils-merge@1.0.1:
    resolution: {integrity: sha512-pMZTvIkT1d+TFGvDOqodOclx0QWkkgi6Tdoa8gC8ffGAAqz9pzPTZWAybbsHHoED/ztMtkv/VoYTYyShUn81hA==}
    engines: {node: '>= 0.4.0'}

  vary@1.1.2:
    resolution: {integrity: sha512-BNGbWLfd0eUPabhkXUVm0j8uuvREyTh5ovRa/dyow/BqAbZJyC+5fU+IzQOzmAKzYqYRAISoRhdQr3eIZ/PXqg==}
    engines: {node: '>= 0.8'}

  vite-node@1.6.1:
    resolution: {integrity: sha512-YAXkfvGtuTzwWbDSACdJSg4A4DZiAqckWe90Zapc/sEX3XvHcw1NdurM/6od8J207tSDqNbSsgdCacBgvJKFuA==}
    engines: {node: ^18.0.0 || >=20.0.0}
    hasBin: true

  vite-node@3.2.4:
    resolution: {integrity: sha512-EbKSKh+bh1E1IFxeO0pg1n4dvoOTt0UDiXMd/qn++r98+jPO1xtJilvXldeuQ8giIB5IkpjCgMleHMNEsGH6pg==}
    engines: {node: ^18.0.0 || ^20.0.0 || >=22.0.0}
    hasBin: true

  vite-plugin-node-polyfills@0.25.0:
    resolution: {integrity: sha512-rHZ324W3LhfGPxWwQb2N048TThB6nVvnipsqBUJEzh3R9xeK9KI3si+GMQxCuAcpPJBVf0LpDtJ+beYzB3/chg==}
    peerDependencies:
      vite: ^2.0.0 || ^3.0.0 || ^4.0.0 || ^5.0.0 || ^6.0.0 || ^7.0.0

  vite@5.4.21:
    resolution: {integrity: sha512-o5a9xKjbtuhY6Bi5S3+HvbRERmouabWbyUcpXXUA1u+GNUKoROi9byOJ8M0nHbHYHkYICiMlqxkg1KkYmm25Sw==}
    engines: {node: ^18.0.0 || >=20.0.0}
    hasBin: true
    peerDependencies:
      '@types/node': ^18.0.0 || >=20.0.0
      less: '*'
      lightningcss: ^1.21.0
      sass: '*'
      sass-embedded: '*'
      stylus: '*'
      sugarss: '*'
      terser: ^5.4.0
    peerDependenciesMeta:
      '@types/node':
        optional: true
      less:
        optional: true
      lightningcss:
        optional: true
      sass:
        optional: true
      sass-embedded:
        optional: true
      stylus:
        optional: true
      sugarss:
        optional: true
      terser:
        optional: true

  vite@6.4.2:
    resolution: {integrity: sha512-2N/55r4JDJ4gdrCvGgINMy+HH3iRpNIz8K6SFwVsA+JbQScLiC+clmAxBgwiSPgcG9U15QmvqCGWzMbqda5zGQ==}
    engines: {node: ^18.0.0 || ^20.0.0 || >=22.0.0}
    hasBin: true
    peerDependencies:
      '@types/node': ^18.0.0 || ^20.0.0 || >=22.0.0
      jiti: '>=1.21.0'
      less: '*'
      lightningcss: ^1.21.0
      sass: '*'
      sass-embedded: '*'
      stylus: '*'
      sugarss: '*'
      terser: ^5.16.0
      tsx: ^4.8.1
      yaml: ^2.4.2
    peerDependenciesMeta:
      '@types/node':
        optional: true
      jiti:
        optional: true
      less:
        optional: true
      lightningcss:
        optional: true
      sass:
        optional: true
      sass-embedded:
        optional: true
      stylus:
        optional: true
      sugarss:
        optional: true
      terser:
        optional: true
      tsx:
        optional: true
      yaml:
        optional: true

  vitefu@1.1.3:
    resolution: {integrity: sha512-ub4okH7Z5KLjb6hDyjqrGXqWtWvoYdU3IGm/NorpgHncKoLTCfRIbvlhBm7r0YstIaQRYlp4yEbFqDcKSzXSSg==}
    peerDependencies:
      vite: ^3.0.0 || ^4.0.0 || ^5.0.0 || ^6.0.0 || ^7.0.0 || ^8.0.0
    peerDependenciesMeta:
      vite:
        optional: true

  vitest@1.6.1:
    resolution: {integrity: sha512-Ljb1cnSJSivGN0LqXd/zmDbWEM0RNNg2t1QW/XUhYl/qPqyu7CsqeWtqQXHVaJsecLPuDoak2oJcZN2QoRIOag==}
    engines: {node: ^18.0.0 || >=20.0.0}
    hasBin: true
    peerDependencies:
      '@edge-runtime/vm': '*'
      '@types/node': ^18.0.0 || >=20.0.0
      '@vitest/browser': 1.6.1
      '@vitest/ui': 1.6.1
      happy-dom: '*'
      jsdom: '*'
    peerDependenciesMeta:
      '@edge-runtime/vm':
        optional: true
      '@types/node':
        optional: true
      '@vitest/browser':
        optional: true
      '@vitest/ui':
        optional: true
      happy-dom:
        optional: true
      jsdom:
        optional: true

  vitest@3.2.4:
    resolution: {integrity: sha512-LUCP5ev3GURDysTWiP47wRRUpLKMOfPh+yKTx3kVIEiu5KOMeqzpnYNsKyOoVrULivR8tLcks4+lga33Whn90A==}
    engines: {node: ^18.0.0 || ^20.0.0 || >=22.0.0}
    hasBin: true
    peerDependencies:
      '@edge-runtime/vm': '*'
      '@types/debug': ^4.1.12
      '@types/node': ^18.0.0 || ^20.0.0 || >=22.0.0
      '@vitest/browser': 3.2.4
      '@vitest/ui': 3.2.4
      happy-dom: '*'
      jsdom: '*'
    peerDependenciesMeta:
      '@edge-runtime/vm':
        optional: true
      '@types/debug':
        optional: true
      '@types/node':
        optional: true
      '@vitest/browser':
        optional: true
      '@vitest/ui':
        optional: true
      happy-dom:
        optional: true
      jsdom:
        optional: true

  vm-browserify@1.1.2:
    resolution: {integrity: sha512-2ham8XPWTONajOR0ohOKOHXkm3+gaBmGut3SRuu75xLd/RRaY6vqgh8NBYYk7+RW3u5AtzPQZG8F10LHkl0lAQ==}

  w3c-keyname@2.2.8:
    resolution: {integrity: sha512-dpojBhNsCNN7T82Tm7k26A6G9ML3NkhDsnw9n/eoxSRlVBB4CEtIQ/KTCLI2Fwf3ataSXRhYFkQi3SlnFwPvPQ==}

  w3c-xmlserializer@5.0.0:
    resolution: {integrity: sha512-o8qghlI8NZHU1lLPrpi2+Uq7abh4GGPpYANlalzWxyWteJOCsr/P+oPBA49TOLu5FTZO4d3F9MnWJfiMo4BkmA==}
    engines: {node: '>=18'}

  web-streams-polyfill@4.0.0-beta.3:
    resolution: {integrity: sha512-QW95TCTaHmsYfHDybGMwO5IJIM93I/6vTRk+daHTWFPhwh+C8Cg7j7XyKrwrj8Ib6vYXe0ocYNrmzY4xAAN6ug==}
    engines: {node: '>= 14'}

  web-worker@1.5.0:
    resolution: {integrity: sha512-RiMReJrTAiA+mBjGONMnjVDP2u3p9R1vkcGz6gDIrOMT3oGuYwX2WRMYI9ipkphSuE5XKEhydbhNEJh4NY9mlw==}

  webidl-conversions@3.0.1:
    resolution: {integrity: sha512-2JAn3z8AR6rjK8Sm8orRC0h/bcl/DqL7tRPdGZ4I1CjdF+EaMLmYxBHyXuKL849eucPFhvBoxMsflfOb8kxaeQ==}

  webidl-conversions@7.0.0:
    resolution: {integrity: sha512-VwddBukDzu71offAQR975unBIGqfKZpM+8ZX6ySk8nYhVoo5CYaZyzt3YBvYtRtO+aoGlqxPg/B87NGVZ/fu6g==}
    engines: {node: '>=12'}

  whatwg-encoding@3.1.1:
    resolution: {integrity: sha512-6qN4hJdMwfYBtE3YBTTHhoeuUrDBPZmbQaxWAqSALV/MeEnR5z1xd8UKud2RAkFoPkmB+hli1TZSnyi84xz1vQ==}
    engines: {node: '>=18'}
    deprecated: Use @exodus/bytes instead for a more spec-conformant and faster implementation

  whatwg-mimetype@4.0.0:
    resolution: {integrity: sha512-QaKxh0eNIi2mE9p2vEdzfagOKHCcj1pJ56EEHGQOVxp8r9/iszLUUV7v89x9O1p/T+NlTM5W7jW6+cz4Fq1YVg==}
    engines: {node: '>=18'}

  whatwg-url@14.2.0:
    resolution: {integrity: sha512-De72GdQZzNTUBBChsXueQUnPKDkg/5A5zp7pFDuQAj5UFoENpiACU0wlCvzpAGnTkj++ihpKwKyYewn/XNUbKw==}
    engines: {node: '>=18'}

  whatwg-url@5.0.0:
    resolution: {integrity: sha512-saE57nupxk6v3HY35+jzBwYa0rKSy0XR8JSxZPwgLr7ys0IBzhGviA1/TUGJLmSVqs8pb9AnvICXEuOHLprYTw==}

  which-typed-array@1.1.20:
    resolution: {integrity: sha512-LYfpUkmqwl0h9A2HL09Mms427Q1RZWuOHsukfVcKRq9q95iQxdw0ix1JQrqbcDR9PH1QDwf5Qo8OZb5lksZ8Xg==}
    engines: {node: '>= 0.4'}

  which@2.0.2:
    resolution: {integrity: sha512-BLI3Tl1TW3Pvl70l3yq3Y64i+awpwXqsGBYWkkqMtnbXgrMD+yj7rhW0kuEDxzJaYXGjEW5ogapKNMEKNMjibA==}
    engines: {node: '>= 8'}
    hasBin: true

  why-is-node-running@2.3.0:
    resolution: {integrity: sha512-hUrmaWBdVDcxvYqnyh09zunKzROWjbZTiNy8dBEjkS7ehEDQibXJ7XvlmtbwuTclUiIyN+CyXQD4Vmko8fNm8w==}
    engines: {node: '>=8'}
    hasBin: true

  ws@8.20.0:
    resolution: {integrity: sha512-sAt8BhgNbzCtgGbt2OxmpuryO63ZoDk/sqaB/znQm94T4fCEsy/yV+7CdC1kJhOU9lboAEU7R3kquuycDoibVA==}
    engines: {node: '>=10.0.0'}
    peerDependencies:
      bufferutil: ^4.0.1
      utf-8-validate: '>=5.0.2'
    peerDependenciesMeta:
      bufferutil:
        optional: true
      utf-8-validate:
        optional: true

  xml-name-validator@5.0.0:
    resolution: {integrity: sha512-EvGK8EJ3DhaHfbRlETOWAS5pO9MZITeauHKJyb8wyajUfQUenkIg2MvLDTZ4T/TgIcm3HU0TFBgWWboAZ30UHg==}
    engines: {node: '>=18'}

  xml-utils@1.10.2:
    resolution: {integrity: sha512-RqM+2o1RYs6T8+3DzDSoTRAUfrvaejbVHcp3+thnAtDKo8LskR+HomLajEy5UjTz24rpka7AxVBRR3g2wTUkJA==}

  xmlchars@2.2.0:
    resolution: {integrity: sha512-JZnDKK8B0RCDw84FNdDAIpZK+JuJw+s7Lz8nksI7SIuU3UXJJslUthsi+uWBUYOwPFwW7W7PRLRfUKpxjtjFCw==}

  xtend@4.0.2:
    resolution: {integrity: sha512-LKYU1iAXJXUgAXn9URjiu+MWhyUXHsvfp7mcuYm9dSUKK0/CjtrUwFAxD82/mCWbtLsGjFIad0wIsod4zrTAEQ==}
    engines: {node: '>=0.4'}

  yallist@3.1.1:
    resolution: {integrity: sha512-a4UGQaWPH59mOXUYnAG2ewncQS4i4F43Tv3JoAM+s2VDAmS9NsK8GpDMLrCHPksFT7h3K6TOoUNn2pb7RoXx4g==}

  yaml@2.9.0:
    resolution: {integrity: sha512-2AvhNX3mb8zd6Zy7INTtSpl1F15HW6Wnqj0srWlkKLcpYl/gMIMJiyuGq2KeI2YFxUPjdlB+3Lc10seMLtL4cA==}
    engines: {node: '>= 14.6'}
    hasBin: true

  yocto-queue@0.1.0:
    resolution: {integrity: sha512-rVksvsnNCdJ/ohGc6xgPwyN8eheCxsiLM8mxuE/t/mOVqJewPuO1miLpTHQiRgTKCLexL4MeAFVagts7HmNZ2Q==}
    engines: {node: '>=10'}

  yocto-queue@1.2.2:
    resolution: {integrity: sha512-4LCcse/U2MHZ63HAJVE+v71o7yOdIe4cZ70Wpf8D/IyjDKYQLV5GD46B+hSTjJsvV5PztjvHoU580EftxjDZFQ==}
    engines: {node: '>=12.20'}

  zimmerframe@1.1.4:
    resolution: {integrity: sha512-B58NGBEoc8Y9MWWCQGl/gq9xBCe4IiKM0a2x7GZdQKOW5Exr8S1W24J6OgM1njK8xCRGvAJIL/MxXHf6SkmQKQ==}

  zstddec@0.2.0:
    resolution: {integrity: sha512-oyPnDa1X5c13+Y7mA/FDMNJrn4S8UNBe0KCqtDmor40Re7ALrPN6npFwyYVRRh+PqozZQdeg23QtbcamZnG5rA==}

snapshots:

  '@adobe/css-tools@4.4.4': {}

  '@alloc/quick-lru@5.2.0': {}

  '@anthropic-ai/sdk@0.37.0':
    dependencies:
      '@types/node': 18.19.130
      '@types/node-fetch': 2.6.13
      abort-controller: 3.0.0
      agentkeepalive: 4.6.0
      form-data-encoder: 1.7.2
      formdata-node: 4.4.1
      node-fetch: 2.7.0
    transitivePeerDependencies:
      - encoding

  '@anthropic-ai/sdk@0.39.0':
    dependencies:
      '@types/node': 18.19.130
      '@types/node-fetch': 2.6.13
      abort-controller: 3.0.0
      agentkeepalive: 4.6.0
      form-data-encoder: 1.7.2
      formdata-node: 4.4.1
      node-fetch: 2.7.0
    transitivePeerDependencies:
      - encoding

  '@anthropic-ai/sdk@0.99.0':
    dependencies:
      json-schema-to-ts: 3.1.1
      standardwebhooks: 1.0.0

  '@asamuzakjp/css-color@3.2.0':
    dependencies:
      '@csstools/css-calc': 2.1.4(@csstools/css-parser-algorithms@3.0.5(@csstools/css-tokenizer@3.0.4))(@csstools/css-tokenizer@3.0.4)
      '@csstools/css-color-parser': 3.1.0(@csstools/css-parser-algorithms@3.0.5(@csstools/css-tokenizer@3.0.4))(@csstools/css-tokenizer@3.0.4)
      '@csstools/css-parser-algorithms': 3.0.5(@csstools/css-tokenizer@3.0.4)
      '@csstools/css-tokenizer': 3.0.4
      lru-cache: 10.4.3

  '@babel/code-frame@7.29.0':
    dependencies:
      '@babel/helper-validator-identifier': 7.28.5
      js-tokens: 4.0.0
      picocolors: 1.1.1

  '@babel/compat-data@7.29.0': {}

  '@babel/core@7.29.0':
    dependencies:
      '@babel/code-frame': 7.29.0
      '@babel/generator': 7.29.1
      '@babel/helper-compilation-targets': 7.28.6
      '@babel/helper-module-transforms': 7.28.6(@babel/core@7.29.0)
      '@babel/helpers': 7.29.2
      '@babel/parser': 7.29.2
      '@babel/template': 7.28.6
      '@babel/traverse': 7.29.0
      '@babel/types': 7.29.0
      '@jridgewell/remapping': 2.3.5
      convert-source-map: 2.0.0
      debug: 4.4.3
      gensync: 1.0.0-beta.2
      json5: 2.2.3
      semver: 6.3.1
    transitivePeerDependencies:
      - supports-color

  '@babel/generator@7.29.1':
    dependencies:
      '@babel/parser': 7.29.2
      '@babel/types': 7.29.0
      '@jridgewell/gen-mapping': 0.3.13
      '@jridgewell/trace-mapping': 0.3.31
      jsesc: 3.1.0

  '@babel/helper-compilation-targets@7.28.6':
    dependencies:
      '@babel/compat-data': 7.29.0
      '@babel/helper-validator-option': 7.27.1
      browserslist: 4.28.2
      lru-cache: 5.1.1
      semver: 6.3.1

  '@babel/helper-globals@7.28.0': {}

  '@babel/helper-module-imports@7.28.6':
    dependencies:
      '@babel/traverse': 7.29.0
      '@babel/types': 7.29.0
    transitivePeerDependencies:
      - supports-color

  '@babel/helper-module-transforms@7.28.6(@babel/core@7.29.0)':
    dependencies:
      '@babel/core': 7.29.0
      '@babel/helper-module-imports': 7.28.6
      '@babel/helper-validator-identifier': 7.28.5
      '@babel/traverse': 7.29.0
    transitivePeerDependencies:
      - supports-color

  '@babel/helper-plugin-utils@7.28.6': {}

  '@babel/helper-string-parser@7.27.1': {}

  '@babel/helper-validator-identifier@7.28.5': {}

  '@babel/helper-validator-option@7.27.1': {}

  '@babel/helpers@7.29.2':
    dependencies:
      '@babel/template': 7.28.6
      '@babel/types': 7.29.0

  '@babel/parser@7.29.2':
    dependencies:
      '@babel/types': 7.29.0

  '@babel/plugin-transform-react-jsx-self@7.27.1(@babel/core@7.29.0)':
    dependencies:
      '@babel/core': 7.29.0
      '@babel/helper-plugin-utils': 7.28.6

  '@babel/plugin-transform-react-jsx-source@7.27.1(@babel/core@7.29.0)':
    dependencies:
      '@babel/core': 7.29.0
      '@babel/helper-plugin-utils': 7.28.6

  '@babel/runtime@7.29.2': {}

  '@babel/template@7.28.6':
    dependencies:
      '@babel/code-frame': 7.29.0
      '@babel/parser': 7.29.2
      '@babel/types': 7.29.0

  '@babel/traverse@7.29.0':
    dependencies:
      '@babel/code-frame': 7.29.0
      '@babel/generator': 7.29.1
      '@babel/helper-globals': 7.28.0
      '@babel/parser': 7.29.2
      '@babel/template': 7.28.6
      '@babel/types': 7.29.0
      debug: 4.4.3
    transitivePeerDependencies:
      - supports-color

  '@babel/types@7.29.0':
    dependencies:
      '@babel/helper-string-parser': 7.27.1
      '@babel/helper-validator-identifier': 7.28.5

  '@bsv/sdk@1.10.4': {}

  '@bsv/sdk@2.0.13': {}

  '@cbor-extract/cbor-extract-darwin-arm64@2.2.2':
    optional: true

  '@cbor-extract/cbor-extract-darwin-x64@2.2.2':
    optional: true

  '@cbor-extract/cbor-extract-linux-arm64@2.2.2':
    optional: true

  '@cbor-extract/cbor-extract-linux-arm@2.2.2':
    optional: true

  '@cbor-extract/cbor-extract-linux-x64@2.2.2':
    optional: true

  '@cbor-extract/cbor-extract-win32-x64@2.2.2':
    optional: true

  '@changesets/apply-release-plan@7.1.1':
    dependencies:
      '@changesets/config': 3.1.4
      '@changesets/get-version-range-type': 0.4.0
      '@changesets/git': 3.0.4
      '@changesets/should-skip-package': 0.1.2
      '@changesets/types': 6.1.0
      '@manypkg/get-packages': 1.1.3
      detect-indent: 6.1.0
      fs-extra: 7.0.1
      lodash.startcase: 4.4.0
      outdent: 0.5.0
      prettier: 2.8.8
      resolve-from: 5.0.0
      semver: 7.7.4

  '@changesets/assemble-release-plan@6.0.10':
    dependencies:
      '@changesets/errors': 0.2.0
      '@changesets/get-dependents-graph': 2.1.4
      '@changesets/should-skip-package': 0.1.2
      '@changesets/types': 6.1.0
      '@manypkg/get-packages': 1.1.3
      semver: 7.7.4

  '@changesets/changelog-git@0.2.1':
    dependencies:
      '@changesets/types': 6.1.0

  '@changesets/changelog-github@0.6.0':
    dependencies:
      '@changesets/get-github-info': 0.8.0
      '@changesets/types': 6.1.0
      dotenv: 8.6.0
    transitivePeerDependencies:
      - encoding

  '@changesets/cli@2.31.0(@types/node@20.19.39)':
    dependencies:
      '@changesets/apply-release-plan': 7.1.1
      '@changesets/assemble-release-plan': 6.0.10
      '@changesets/changelog-git': 0.2.1
      '@changesets/config': 3.1.4
      '@changesets/errors': 0.2.0
      '@changesets/get-dependents-graph': 2.1.4
      '@changesets/get-release-plan': 4.0.16
      '@changesets/git': 3.0.4
      '@changesets/logger': 0.1.1
      '@changesets/pre': 2.0.2
      '@changesets/read': 0.6.7
      '@changesets/should-skip-package': 0.1.2
      '@changesets/types': 6.1.0
      '@changesets/write': 0.4.0
      '@inquirer/external-editor': 1.0.3(@types/node@20.19.39)
      '@manypkg/get-packages': 1.1.3
      ansi-colors: 4.1.3
      enquirer: 2.4.1
      fs-extra: 7.0.1
      mri: 1.2.0
      package-manager-detector: 0.2.11
      picocolors: 1.1.1
      resolve-from: 5.0.0
      semver: 7.7.4
      spawndamnit: 3.0.1
      term-size: 2.2.1
    transitivePeerDependencies:
      - '@types/node'

  '@changesets/config@3.1.4':
    dependencies:
      '@changesets/errors': 0.2.0
      '@changesets/get-dependents-graph': 2.1.4
      '@changesets/logger': 0.1.1
      '@changesets/should-skip-package': 0.1.2
      '@changesets/types': 6.1.0
      '@manypkg/get-packages': 1.1.3
      fs-extra: 7.0.1
      micromatch: 4.0.8

  '@changesets/errors@0.2.0':
    dependencies:
      extendable-error: 0.1.7

  '@changesets/get-dependents-graph@2.1.4':
    dependencies:
      '@changesets/types': 6.1.0
      '@manypkg/get-packages': 1.1.3
      picocolors: 1.1.1
      semver: 7.7.4

  '@changesets/get-github-info@0.8.0':
    dependencies:
      dataloader: 1.4.0
      node-fetch: 2.7.0
    transitivePeerDependencies:
      - encoding

  '@changesets/get-release-plan@4.0.16':
    dependencies:
      '@changesets/assemble-release-plan': 6.0.10
      '@changesets/config': 3.1.4
      '@changesets/pre': 2.0.2
      '@changesets/read': 0.6.7
      '@changesets/types': 6.1.0
      '@manypkg/get-packages': 1.1.3

  '@changesets/get-version-range-type@0.4.0': {}

  '@changesets/git@3.0.4':
    dependencies:
      '@changesets/errors': 0.2.0
      '@manypkg/get-packages': 1.1.3
      is-subdir: 1.2.0
      micromatch: 4.0.8
      spawndamnit: 3.0.1

  '@changesets/logger@0.1.1':
    dependencies:
      picocolors: 1.1.1

  '@changesets/parse@0.4.3':
    dependencies:
      '@changesets/types': 6.1.0
      js-yaml: 4.1.1

  '@changesets/pre@2.0.2':
    dependencies:
      '@changesets/errors': 0.2.0
      '@changesets/types': 6.1.0
      '@manypkg/get-packages': 1.1.3
      fs-extra: 7.0.1

  '@changesets/read@0.6.7':
    dependencies:
      '@changesets/git': 3.0.4
      '@changesets/logger': 0.1.1
      '@changesets/parse': 0.4.3
      '@changesets/types': 6.1.0
      fs-extra: 7.0.1
      p-filter: 2.1.0
      picocolors: 1.1.1

  '@changesets/should-skip-package@0.1.2':
    dependencies:
      '@changesets/types': 6.1.0
      '@manypkg/get-packages': 1.1.3

  '@changesets/types@4.1.0': {}

  '@changesets/types@6.1.0': {}

  '@changesets/write@0.4.0':
    dependencies:
      '@changesets/types': 6.1.0
      fs-extra: 7.0.1
      human-id: 4.1.3
      prettier: 2.8.8

  '@codemirror/autocomplete@6.20.1':
    dependencies:
      '@codemirror/language': 6.12.3
      '@codemirror/state': 6.6.0
      '@codemirror/view': 6.41.1
      '@lezer/common': 1.5.2

  '@codemirror/commands@6.10.3':
    dependencies:
      '@codemirror/language': 6.12.3
      '@codemirror/state': 6.6.0
      '@codemirror/view': 6.41.1
      '@lezer/common': 1.5.2

  '@codemirror/lang-css@6.3.1':
    dependencies:
      '@codemirror/autocomplete': 6.20.1
      '@codemirror/language': 6.12.3
      '@codemirror/state': 6.6.0
      '@lezer/common': 1.5.2
      '@lezer/css': 1.3.3

  '@codemirror/lang-html@6.4.11':
    dependencies:
      '@codemirror/autocomplete': 6.20.1
      '@codemirror/lang-css': 6.3.1
      '@codemirror/lang-javascript': 6.2.5
      '@codemirror/language': 6.12.3
      '@codemirror/state': 6.6.0
      '@codemirror/view': 6.41.1
      '@lezer/common': 1.5.2
      '@lezer/css': 1.3.3
      '@lezer/html': 1.3.13

  '@codemirror/lang-javascript@6.2.5':
    dependencies:
      '@codemirror/autocomplete': 6.20.1
      '@codemirror/language': 6.12.3
      '@codemirror/lint': 6.9.5
      '@codemirror/state': 6.6.0
      '@codemirror/view': 6.41.1
      '@lezer/common': 1.5.2
      '@lezer/javascript': 1.5.4

  '@codemirror/lang-markdown@6.5.0':
    dependencies:
      '@codemirror/autocomplete': 6.20.1
      '@codemirror/lang-html': 6.4.11
      '@codemirror/language': 6.12.3
      '@codemirror/state': 6.6.0
      '@codemirror/view': 6.41.1
      '@lezer/common': 1.5.2
      '@lezer/markdown': 1.6.3

  '@codemirror/language@6.12.3':
    dependencies:
      '@codemirror/state': 6.6.0
      '@codemirror/view': 6.41.1
      '@lezer/common': 1.5.2
      '@lezer/highlight': 1.2.3
      '@lezer/lr': 1.4.10
      style-mod: 4.1.3

  '@codemirror/lint@6.9.5':
    dependencies:
      '@codemirror/state': 6.6.0
      '@codemirror/view': 6.41.1
      crelt: 1.0.6

  '@codemirror/state@6.6.0':
    dependencies:
      '@marijn/find-cluster-break': 1.0.2

  '@codemirror/theme-one-dark@6.1.3':
    dependencies:
      '@codemirror/language': 6.12.3
      '@codemirror/state': 6.6.0
      '@codemirror/view': 6.41.1
      '@lezer/highlight': 1.2.3

  '@codemirror/view@6.41.1':
    dependencies:
      '@codemirror/state': 6.6.0
      crelt: 1.0.6
      style-mod: 4.1.3
      w3c-keyname: 2.2.8

  '@csstools/color-helpers@5.1.0': {}

  '@csstools/css-calc@2.1.4(@csstools/css-parser-algorithms@3.0.5(@csstools/css-tokenizer@3.0.4))(@csstools/css-tokenizer@3.0.4)':
    dependencies:
      '@csstools/css-parser-algorithms': 3.0.5(@csstools/css-tokenizer@3.0.4)
      '@csstools/css-tokenizer': 3.0.4

  '@csstools/css-color-parser@3.1.0(@csstools/css-parser-algorithms@3.0.5(@csstools/css-tokenizer@3.0.4))(@csstools/css-tokenizer@3.0.4)':
    dependencies:
      '@csstools/color-helpers': 5.1.0
      '@csstools/css-calc': 2.1.4(@csstools/css-parser-algorithms@3.0.5(@csstools/css-tokenizer@3.0.4))(@csstools/css-tokenizer@3.0.4)
      '@csstools/css-parser-algorithms': 3.0.5(@csstools/css-tokenizer@3.0.4)
      '@csstools/css-tokenizer': 3.0.4

  '@csstools/css-parser-algorithms@3.0.5(@csstools/css-tokenizer@3.0.4)':
    dependencies:
      '@csstools/css-tokenizer': 3.0.4

  '@csstools/css-tokenizer@3.0.4': {}

  '@drizzle-team/brocli@0.10.2': {}

  '@electric-sql/pglite@0.4.4': {}

  '@emnapi/runtime@1.10.0':
    dependencies:
      tslib: 2.8.1
    optional: true

  '@esbuild-kit/core-utils@3.3.2':
    dependencies:
      esbuild: 0.18.20
      source-map-support: 0.5.21

  '@esbuild-kit/esm-loader@2.6.5':
    dependencies:
      '@esbuild-kit/core-utils': 3.3.2
      get-tsconfig: 4.14.0

  '@esbuild/aix-ppc64@0.19.12':
    optional: true

  '@esbuild/aix-ppc64@0.21.5':
    optional: true

  '@esbuild/aix-ppc64@0.25.12':
    optional: true

  '@esbuild/aix-ppc64@0.27.7':
    optional: true

  '@esbuild/android-arm64@0.18.20':
    optional: true

  '@esbuild/android-arm64@0.19.12':
    optional: true

  '@esbuild/android-arm64@0.21.5':
    optional: true

  '@esbuild/android-arm64@0.25.12':
    optional: true

  '@esbuild/android-arm64@0.27.7':
    optional: true

  '@esbuild/android-arm@0.18.20':
    optional: true

  '@esbuild/android-arm@0.19.12':
    optional: true

  '@esbuild/android-arm@0.21.5':
    optional: true

  '@esbuild/android-arm@0.25.12':
    optional: true

  '@esbuild/android-arm@0.27.7':
    optional: true

  '@esbuild/android-x64@0.18.20':
    optional: true

  '@esbuild/android-x64@0.19.12':
    optional: true

  '@esbuild/android-x64@0.21.5':
    optional: true

  '@esbuild/android-x64@0.25.12':
    optional: true

  '@esbuild/android-x64@0.27.7':
    optional: true

  '@esbuild/darwin-arm64@0.18.20':
    optional: true

  '@esbuild/darwin-arm64@0.19.12':
    optional: true

  '@esbuild/darwin-arm64@0.21.5':
    optional: true

  '@esbuild/darwin-arm64@0.25.12':
    optional: true

  '@esbuild/darwin-arm64@0.27.7':
    optional: true

  '@esbuild/darwin-x64@0.18.20':
    optional: true

  '@esbuild/darwin-x64@0.19.12':
    optional: true

  '@esbuild/darwin-x64@0.21.5':
    optional: true

  '@esbuild/darwin-x64@0.25.12':
    optional: true

  '@esbuild/darwin-x64@0.27.7':
    optional: true

  '@esbuild/freebsd-arm64@0.18.20':
    optional: true

  '@esbuild/freebsd-arm64@0.19.12':
    optional: true

  '@esbuild/freebsd-arm64@0.21.5':
    optional: true

  '@esbuild/freebsd-arm64@0.25.12':
    optional: true

  '@esbuild/freebsd-arm64@0.27.7':
    optional: true

  '@esbuild/freebsd-x64@0.18.20':
    optional: true

  '@esbuild/freebsd-x64@0.19.12':
    optional: true

  '@esbuild/freebsd-x64@0.21.5':
    optional: true

  '@esbuild/freebsd-x64@0.25.12':
    optional: true

  '@esbuild/freebsd-x64@0.27.7':
    optional: true

  '@esbuild/linux-arm64@0.18.20':
    optional: true

  '@esbuild/linux-arm64@0.19.12':
    optional: true

  '@esbuild/linux-arm64@0.21.5':
    optional: true

  '@esbuild/linux-arm64@0.25.12':
    optional: true

  '@esbuild/linux-arm64@0.27.7':
    optional: true

  '@esbuild/linux-arm@0.18.20':
    optional: true

  '@esbuild/linux-arm@0.19.12':
    optional: true

  '@esbuild/linux-arm@0.21.5':
    optional: true

  '@esbuild/linux-arm@0.25.12':
    optional: true

  '@esbuild/linux-arm@0.27.7':
    optional: true

  '@esbuild/linux-ia32@0.18.20':
    optional: true

  '@esbuild/linux-ia32@0.19.12':
    optional: true

  '@esbuild/linux-ia32@0.21.5':
    optional: true

  '@esbuild/linux-ia32@0.25.12':
    optional: true

  '@esbuild/linux-ia32@0.27.7':
    optional: true

  '@esbuild/linux-loong64@0.18.20':
    optional: true

  '@esbuild/linux-loong64@0.19.12':
    optional: true

  '@esbuild/linux-loong64@0.21.5':
    optional: true

  '@esbuild/linux-loong64@0.25.12':
    optional: true

  '@esbuild/linux-loong64@0.27.7':
    optional: true

  '@esbuild/linux-mips64el@0.18.20':
    optional: true

  '@esbuild/linux-mips64el@0.19.12':
    optional: true

  '@esbuild/linux-mips64el@0.21.5':
    optional: true

  '@esbuild/linux-mips64el@0.25.12':
    optional: true

  '@esbuild/linux-mips64el@0.27.7':
    optional: true

  '@esbuild/linux-ppc64@0.18.20':
    optional: true

  '@esbuild/linux-ppc64@0.19.12':
    optional: true

  '@esbuild/linux-ppc64@0.21.5':
    optional: true

  '@esbuild/linux-ppc64@0.25.12':
    optional: true

  '@esbuild/linux-ppc64@0.27.7':
    optional: true

  '@esbuild/linux-riscv64@0.18.20':
    optional: true

  '@esbuild/linux-riscv64@0.19.12':
    optional: true

  '@esbuild/linux-riscv64@0.21.5':
    optional: true

  '@esbuild/linux-riscv64@0.25.12':
    optional: true

  '@esbuild/linux-riscv64@0.27.7':
    optional: true

  '@esbuild/linux-s390x@0.18.20':
    optional: true

  '@esbuild/linux-s390x@0.19.12':
    optional: true

  '@esbuild/linux-s390x@0.21.5':
    optional: true

  '@esbuild/linux-s390x@0.25.12':
    optional: true

  '@esbuild/linux-s390x@0.27.7':
    optional: true

  '@esbuild/linux-x64@0.18.20':
    optional: true

  '@esbuild/linux-x64@0.19.12':
    optional: true

  '@esbuild/linux-x64@0.21.5':
    optional: true

  '@esbuild/linux-x64@0.25.12':
    optional: true

  '@esbuild/linux-x64@0.27.7':
    optional: true

  '@esbuild/netbsd-arm64@0.25.12':
    optional: true

  '@esbuild/netbsd-arm64@0.27.7':
    optional: true

  '@esbuild/netbsd-x64@0.18.20':
    optional: true

  '@esbuild/netbsd-x64@0.19.12':
    optional: true

  '@esbuild/netbsd-x64@0.21.5':
    optional: true

  '@esbuild/netbsd-x64@0.25.12':
    optional: true

  '@esbuild/netbsd-x64@0.27.7':
    optional: true

  '@esbuild/openbsd-arm64@0.25.12':
    optional: true

  '@esbuild/openbsd-arm64@0.27.7':
    optional: true

  '@esbuild/openbsd-x64@0.18.20':
    optional: true

  '@esbuild/openbsd-x64@0.19.12':
    optional: true

  '@esbuild/openbsd-x64@0.21.5':
    optional: true

  '@esbuild/openbsd-x64@0.25.12':
    optional: true

  '@esbuild/openbsd-x64@0.27.7':
    optional: true

  '@esbuild/openharmony-arm64@0.25.12':
    optional: true

  '@esbuild/openharmony-arm64@0.27.7':
    optional: true

  '@esbuild/sunos-x64@0.18.20':
    optional: true

  '@esbuild/sunos-x64@0.19.12':
    optional: true

  '@esbuild/sunos-x64@0.21.5':
    optional: true

  '@esbuild/sunos-x64@0.25.12':
    optional: true

  '@esbuild/sunos-x64@0.27.7':
    optional: true

  '@esbuild/win32-arm64@0.18.20':
    optional: true

  '@esbuild/win32-arm64@0.19.12':
    optional: true

  '@esbuild/win32-arm64@0.21.5':
    optional: true

  '@esbuild/win32-arm64@0.25.12':
    optional: true

  '@esbuild/win32-arm64@0.27.7':
    optional: true

  '@esbuild/win32-ia32@0.18.20':
    optional: true

  '@esbuild/win32-ia32@0.19.12':
    optional: true

  '@esbuild/win32-ia32@0.21.5':
    optional: true

  '@esbuild/win32-ia32@0.25.12':
    optional: true

  '@esbuild/win32-ia32@0.27.7':
    optional: true

  '@esbuild/win32-x64@0.18.20':
    optional: true

  '@esbuild/win32-x64@0.19.12':
    optional: true

  '@esbuild/win32-x64@0.21.5':
    optional: true

  '@esbuild/win32-x64@0.25.12':
    optional: true

  '@esbuild/win32-x64@0.27.7':
    optional: true

  '@img/colour@1.1.0': {}

  '@img/sharp-darwin-arm64@0.34.5':
    optionalDependencies:
      '@img/sharp-libvips-darwin-arm64': 1.2.4
    optional: true

  '@img/sharp-darwin-x64@0.34.5':
    optionalDependencies:
      '@img/sharp-libvips-darwin-x64': 1.2.4
    optional: true

  '@img/sharp-libvips-darwin-arm64@1.2.4':
    optional: true

  '@img/sharp-libvips-darwin-x64@1.2.4':
    optional: true

  '@img/sharp-libvips-linux-arm64@1.2.4':
    optional: true

  '@img/sharp-libvips-linux-arm@1.2.4':
    optional: true

  '@img/sharp-libvips-linux-ppc64@1.2.4':
    optional: true

  '@img/sharp-libvips-linux-riscv64@1.2.4':
    optional: true

  '@img/sharp-libvips-linux-s390x@1.2.4':
    optional: true

  '@img/sharp-libvips-linux-x64@1.2.4':
    optional: true

  '@img/sharp-libvips-linuxmusl-arm64@1.2.4':
    optional: true

  '@img/sharp-libvips-linuxmusl-x64@1.2.4':
    optional: true

  '@img/sharp-linux-arm64@0.34.5':
    optionalDependencies:
      '@img/sharp-libvips-linux-arm64': 1.2.4
    optional: true

  '@img/sharp-linux-arm@0.34.5':
    optionalDependencies:
      '@img/sharp-libvips-linux-arm': 1.2.4
    optional: true

  '@img/sharp-linux-ppc64@0.34.5':
    optionalDependencies:
      '@img/sharp-libvips-linux-ppc64': 1.2.4
    optional: true

  '@img/sharp-linux-riscv64@0.34.5':
    optionalDependencies:
      '@img/sharp-libvips-linux-riscv64': 1.2.4
    optional: true

  '@img/sharp-linux-s390x@0.34.5':
    optionalDependencies:
      '@img/sharp-libvips-linux-s390x': 1.2.4
    optional: true

  '@img/sharp-linux-x64@0.34.5':
    optionalDependencies:
      '@img/sharp-libvips-linux-x64': 1.2.4
    optional: true

  '@img/sharp-linuxmusl-arm64@0.34.5':
    optionalDependencies:
      '@img/sharp-libvips-linuxmusl-arm64': 1.2.4
    optional: true

  '@img/sharp-linuxmusl-x64@0.34.5':
    optionalDependencies:
      '@img/sharp-libvips-linuxmusl-x64': 1.2.4
    optional: true

  '@img/sharp-wasm32@0.34.5':
    dependencies:
      '@emnapi/runtime': 1.10.0
    optional: true

  '@img/sharp-win32-arm64@0.34.5':
    optional: true

  '@img/sharp-win32-ia32@0.34.5':
    optional: true

  '@img/sharp-win32-x64@0.34.5':
    optional: true

  '@inquirer/external-editor@1.0.3(@types/node@20.19.39)':
    dependencies:
      chardet: 2.1.1
      iconv-lite: 0.7.2
    optionalDependencies:
      '@types/node': 20.19.39

  '@jest/schemas@29.6.3':
    dependencies:
      '@sinclair/typebox': 0.27.10

  '@jridgewell/gen-mapping@0.3.13':
    dependencies:
      '@jridgewell/sourcemap-codec': 1.5.5
      '@jridgewell/trace-mapping': 0.3.31

  '@jridgewell/remapping@2.3.5':
    dependencies:
      '@jridgewell/gen-mapping': 0.3.13
      '@jridgewell/trace-mapping': 0.3.31

  '@jridgewell/resolve-uri@3.1.2': {}

  '@jridgewell/sourcemap-codec@1.5.5': {}

  '@jridgewell/trace-mapping@0.3.31':
    dependencies:
      '@jridgewell/resolve-uri': 3.1.2
      '@jridgewell/sourcemap-codec': 1.5.5

  '@lezer/common@1.5.2': {}

  '@lezer/css@1.3.3':
    dependencies:
      '@lezer/common': 1.5.2
      '@lezer/highlight': 1.2.3
      '@lezer/lr': 1.4.10

  '@lezer/highlight@1.2.3':
    dependencies:
      '@lezer/common': 1.5.2

  '@lezer/html@1.3.13':
    dependencies:
      '@lezer/common': 1.5.2
      '@lezer/highlight': 1.2.3
      '@lezer/lr': 1.4.10

  '@lezer/javascript@1.5.4':
    dependencies:
      '@lezer/common': 1.5.2
      '@lezer/highlight': 1.2.3
      '@lezer/lr': 1.4.10

  '@lezer/lr@1.4.10':
    dependencies:
      '@lezer/common': 1.5.2

  '@lezer/markdown@1.6.3':
    dependencies:
      '@lezer/common': 1.5.2
      '@lezer/highlight': 1.2.3

  '@manypkg/find-root@1.1.0':
    dependencies:
      '@babel/runtime': 7.29.2
      '@types/node': 12.20.55
      find-up: 4.1.0
      fs-extra: 8.1.0

  '@manypkg/get-packages@1.1.3':
    dependencies:
      '@babel/runtime': 7.29.2
      '@changesets/types': 4.1.0
      '@manypkg/find-root': 1.1.0
      fs-extra: 8.1.0
      globby: 11.1.0
      read-yaml-file: 1.1.0

  '@marijn/find-cluster-break@1.0.2': {}

  '@noble/hashes@1.8.0': {}

  '@noble/secp256k1@2.3.0': {}

  '@nodelib/fs.scandir@2.1.5':
    dependencies:
      '@nodelib/fs.stat': 2.0.5
      run-parallel: 1.2.0

  '@nodelib/fs.stat@2.0.5': {}

  '@nodelib/fs.walk@1.2.8':
    dependencies:
      '@nodelib/fs.scandir': 2.1.5
      fastq: 1.20.1

  '@petamoriken/float16@3.9.3': {}

  '@rolldown/pluginutils@1.0.0-beta.27': {}

  '@rollup/plugin-inject@5.0.5(rollup@4.60.1)':
    dependencies:
      '@rollup/pluginutils': 5.3.0(rollup@4.60.1)
      estree-walker: 2.0.2
      magic-string: 0.30.21
    optionalDependencies:
      rollup: 4.60.1

  '@rollup/pluginutils@5.3.0(rollup@4.60.1)':
    dependencies:
      '@types/estree': 1.0.8
      estree-walker: 2.0.2
      picomatch: 4.0.4
    optionalDependencies:
      rollup: 4.60.1

  '@rollup/rollup-android-arm-eabi@4.60.1':
    optional: true

  '@rollup/rollup-android-arm64@4.60.1':
    optional: true

  '@rollup/rollup-darwin-arm64@4.60.1':
    optional: true

  '@rollup/rollup-darwin-x64@4.60.1':
    optional: true

  '@rollup/rollup-freebsd-arm64@4.60.1':
    optional: true

  '@rollup/rollup-freebsd-x64@4.60.1':
    optional: true

  '@rollup/rollup-linux-arm-gnueabihf@4.60.1':
    optional: true

  '@rollup/rollup-linux-arm-musleabihf@4.60.1':
    optional: true

  '@rollup/rollup-linux-arm64-gnu@4.60.1':
    optional: true

  '@rollup/rollup-linux-arm64-musl@4.60.1':
    optional: true

  '@rollup/rollup-linux-loong64-gnu@4.60.1':
    optional: true

  '@rollup/rollup-linux-loong64-musl@4.60.1':
    optional: true

  '@rollup/rollup-linux-ppc64-gnu@4.60.1':
    optional: true

  '@rollup/rollup-linux-ppc64-musl@4.60.1':
    optional: true

  '@rollup/rollup-linux-riscv64-gnu@4.60.1':
    optional: true

  '@rollup/rollup-linux-riscv64-musl@4.60.1':
    optional: true

  '@rollup/rollup-linux-s390x-gnu@4.60.1':
    optional: true

  '@rollup/rollup-linux-x64-gnu@4.60.1':
    optional: true

  '@rollup/rollup-linux-x64-musl@4.60.1':
    optional: true

  '@rollup/rollup-openbsd-x64@4.60.1':
    optional: true

  '@rollup/rollup-openharmony-arm64@4.60.1':
    optional: true

  '@rollup/rollup-win32-arm64-msvc@4.60.1':
    optional: true

  '@rollup/rollup-win32-ia32-msvc@4.60.1':
    optional: true

  '@rollup/rollup-win32-x64-gnu@4.60.1':
    optional: true

  '@rollup/rollup-win32-x64-msvc@4.60.1':
    optional: true

  '@semantos/core@file:(@bsv/sdk@2.0.13)':
    dependencies:
      '@anthropic-ai/sdk': 0.99.0
      '@bsv/sdk': 2.0.13
      geotiff: 3.0.5
      yaml: 2.9.0
    transitivePeerDependencies:
      - zod

  '@sinclair/typebox@0.27.10': {}

  '@sqlite.org/sqlite-wasm@3.53.0-build1': {}

  '@stablelib/base64@1.0.1': {}

  '@sveltejs/acorn-typescript@1.0.9(acorn@8.16.0)':
    dependencies:
      acorn: 8.16.0

  '@sveltejs/vite-plugin-svelte-inspector@3.0.1(@sveltejs/vite-plugin-svelte@4.0.4(svelte@5.55.4)(vite@5.4.21(@types/node@20.19.39)))(svelte@5.55.4)(vite@5.4.21(@types/node@20.19.39))':
    dependencies:
      '@sveltejs/vite-plugin-svelte': 4.0.4(svelte@5.55.4)(vite@5.4.21(@types/node@20.19.39))
      debug: 4.4.3
      svelte: 5.55.4
      vite: 5.4.21(@types/node@20.19.39)
    transitivePeerDependencies:
      - supports-color

  '@sveltejs/vite-plugin-svelte-inspector@4.0.1(@sveltejs/vite-plugin-svelte@5.1.1(svelte@5.55.4)(vite@6.4.2(@types/node@20.19.39)(jiti@1.21.7)(tsx@4.21.0)(yaml@2.9.0)))(svelte@5.55.4)(vite@6.4.2(@types/node@20.19.39)(jiti@1.21.7)(tsx@4.21.0)(yaml@2.9.0))':
    dependencies:
      '@sveltejs/vite-plugin-svelte': 5.1.1(svelte@5.55.4)(vite@6.4.2(@types/node@20.19.39)(jiti@1.21.7)(tsx@4.21.0)(yaml@2.9.0))
      debug: 4.4.3
      svelte: 5.55.4
      vite: 6.4.2(@types/node@20.19.39)(jiti@1.21.7)(tsx@4.21.0)(yaml@2.9.0)
    transitivePeerDependencies:
      - supports-color

  '@sveltejs/vite-plugin-svelte@4.0.4(svelte@5.55.4)(vite@5.4.21(@types/node@20.19.39))':
    dependencies:
      '@sveltejs/vite-plugin-svelte-inspector': 3.0.1(@sveltejs/vite-plugin-svelte@4.0.4(svelte@5.55.4)(vite@5.4.21(@types/node@20.19.39)))(svelte@5.55.4)(vite@5.4.21(@types/node@20.19.39))
      debug: 4.4.3
      deepmerge: 4.3.1
      kleur: 4.1.5
      magic-string: 0.30.21
      svelte: 5.55.4
      vite: 5.4.21(@types/node@20.19.39)
      vitefu: 1.1.3(vite@5.4.21(@types/node@20.19.39))
    transitivePeerDependencies:
      - supports-color

  '@sveltejs/vite-plugin-svelte@5.1.1(svelte@5.55.4)(vite@6.4.2(@types/node@20.19.39)(jiti@1.21.7)(tsx@4.21.0)(yaml@2.9.0))':
    dependencies:
      '@sveltejs/vite-plugin-svelte-inspector': 4.0.1(@sveltejs/vite-plugin-svelte@5.1.1(svelte@5.55.4)(vite@6.4.2(@types/node@20.19.39)(jiti@1.21.7)(tsx@4.21.0)(yaml@2.9.0)))(svelte@5.55.4)(vite@6.4.2(@types/node@20.19.39)(jiti@1.21.7)(tsx@4.21.0)(yaml@2.9.0))
      debug: 4.4.3
      deepmerge: 4.3.1
      kleur: 4.1.5
      magic-string: 0.30.21
      svelte: 5.55.4
      vite: 6.4.2(@types/node@20.19.39)(jiti@1.21.7)(tsx@4.21.0)(yaml@2.9.0)
      vitefu: 1.1.3(vite@6.4.2(@types/node@20.19.39)(jiti@1.21.7)(tsx@4.21.0)(yaml@2.9.0))
    transitivePeerDependencies:
      - supports-color

  '@testing-library/dom@10.4.1':
    dependencies:
      '@babel/code-frame': 7.29.0
      '@babel/runtime': 7.29.2
      '@types/aria-query': 5.0.4
      aria-query: 5.3.0
      dom-accessibility-api: 0.5.16
      lz-string: 1.5.0
      picocolors: 1.1.1
      pretty-format: 27.5.1

  '@testing-library/jest-dom@6.9.1':
    dependencies:
      '@adobe/css-tools': 4.4.4
      aria-query: 5.3.2
      css.escape: 1.5.1
      dom-accessibility-api: 0.6.3
      picocolors: 1.1.1
      redent: 3.0.0

  '@testing-library/react@16.3.2(@testing-library/dom@10.4.1)(@types/react-dom@19.2.3(@types/react@19.2.14))(@types/react@19.2.14)(react-dom@19.2.5(react@19.2.5))(react@19.2.5)':
    dependencies:
      '@babel/runtime': 7.29.2
      '@testing-library/dom': 10.4.1
      react: 19.2.5
      react-dom: 19.2.5(react@19.2.5)
    optionalDependencies:
      '@types/react': 19.2.14
      '@types/react-dom': 19.2.3(@types/react@19.2.14)

  '@ts-morph/common@0.29.0':
    dependencies:
      minimatch: 10.2.5
      path-browserify: 1.0.1
      tinyglobby: 0.2.16

  '@tsconfig/svelte@5.0.8': {}

  '@tweenjs/tween.js@23.1.3': {}

  '@types/aria-query@5.0.4': {}

  '@types/babel__core@7.20.5':
    dependencies:
      '@babel/parser': 7.29.2
      '@babel/types': 7.29.0
      '@types/babel__generator': 7.27.0
      '@types/babel__template': 7.4.4
      '@types/babel__traverse': 7.28.0

  '@types/babel__generator@7.27.0':
    dependencies:
      '@babel/types': 7.29.0

  '@types/babel__template@7.4.4':
    dependencies:
      '@babel/parser': 7.29.2
      '@babel/types': 7.29.0

  '@types/babel__traverse@7.28.0':
    dependencies:
      '@babel/types': 7.29.0

  '@types/body-parser@1.19.6':
    dependencies:
      '@types/connect': 3.4.38
      '@types/node': 20.19.39

  '@types/chai@5.2.3':
    dependencies:
      '@types/deep-eql': 4.0.2
      assertion-error: 2.0.1

  '@types/connect@3.4.38':
    dependencies:
      '@types/node': 20.19.39

  '@types/cors@2.8.19':
    dependencies:
      '@types/node': 20.19.39

  '@types/d3-force@3.0.10': {}

  '@types/d3-scale@4.0.9':
    dependencies:
      '@types/d3-time': 3.0.4

  '@types/d3-time@3.0.4': {}

  '@types/deep-eql@4.0.2': {}

  '@types/estree@1.0.8': {}

  '@types/express-serve-static-core@4.19.8':
    dependencies:
      '@types/node': 20.19.39
      '@types/qs': 6.15.0
      '@types/range-parser': 1.2.7
      '@types/send': 1.2.1

  '@types/express@4.17.25':
    dependencies:
      '@types/body-parser': 1.19.6
      '@types/express-serve-static-core': 4.19.8
      '@types/qs': 6.15.0
      '@types/serve-static': 1.15.10

  '@types/http-errors@2.0.5': {}

  '@types/mime@1.3.5': {}

  '@types/node-fetch@2.6.13':
    dependencies:
      '@types/node': 20.19.39
      form-data: 4.0.5

  '@types/node@12.20.55': {}

  '@types/node@18.19.130':
    dependencies:
      undici-types: 5.26.5

  '@types/node@20.19.39':
    dependencies:
      undici-types: 6.21.0

  '@types/phoenix@1.6.7': {}

  '@types/qs@6.15.0': {}

  '@types/range-parser@1.2.7': {}

  '@types/react-dom@19.2.3(@types/react@19.2.14)':
    dependencies:
      '@types/react': 19.2.14

  '@types/react@19.2.14':
    dependencies:
      csstype: 3.2.3

  '@types/send@0.17.6':
    dependencies:
      '@types/mime': 1.3.5
      '@types/node': 20.19.39

  '@types/send@1.2.1':
    dependencies:
      '@types/node': 20.19.39

  '@types/serve-static@1.15.10':
    dependencies:
      '@types/http-errors': 2.0.5
      '@types/node': 20.19.39
      '@types/send': 0.17.6

  '@types/stats.js@0.17.4': {}

  '@types/three@0.165.0':
    dependencies:
      '@tweenjs/tween.js': 23.1.3
      '@types/stats.js': 0.17.4
      '@types/webxr': 0.5.24
      fflate: 0.8.2
      meshoptimizer: 0.18.1

  '@types/trusted-types@2.0.7': {}

  '@types/webxr@0.5.24': {}

  '@types/ws@8.18.1':
    dependencies:
      '@types/node': 20.19.39

  '@vitejs/plugin-react@4.7.0(vite@6.4.2(@types/node@20.19.39)(jiti@1.21.7)(tsx@4.21.0)(yaml@2.9.0))':
    dependencies:
      '@babel/core': 7.29.0
      '@babel/plugin-transform-react-jsx-self': 7.27.1(@babel/core@7.29.0)
      '@babel/plugin-transform-react-jsx-source': 7.27.1(@babel/core@7.29.0)
      '@rolldown/pluginutils': 1.0.0-beta.27
      '@types/babel__core': 7.20.5
      react-refresh: 0.17.0
      vite: 6.4.2(@types/node@20.19.39)(jiti@1.21.7)(tsx@4.21.0)(yaml@2.9.0)
    transitivePeerDependencies:
      - supports-color

  '@vitest/expect@1.6.1':
    dependencies:
      '@vitest/spy': 1.6.1
      '@vitest/utils': 1.6.1
      chai: 4.5.0

  '@vitest/expect@3.2.4':
    dependencies:
      '@types/chai': 5.2.3
      '@vitest/spy': 3.2.4
      '@vitest/utils': 3.2.4
      chai: 5.3.3
      tinyrainbow: 2.0.0

  '@vitest/mocker@3.2.4(vite@6.4.2(@types/node@20.19.39)(jiti@1.21.7)(tsx@4.21.0)(yaml@2.9.0))':
    dependencies:
      '@vitest/spy': 3.2.4
      estree-walker: 3.0.3
      magic-string: 0.30.21
    optionalDependencies:
      vite: 6.4.2(@types/node@20.19.39)(jiti@1.21.7)(tsx@4.21.0)(yaml@2.9.0)

  '@vitest/pretty-format@3.2.4':
    dependencies:
      tinyrainbow: 2.0.0

  '@vitest/runner@1.6.1':
    dependencies:
      '@vitest/utils': 1.6.1
      p-limit: 5.0.0
      pathe: 1.1.2

  '@vitest/runner@3.2.4':
    dependencies:
      '@vitest/utils': 3.2.4
      pathe: 2.0.3
      strip-literal: 3.1.0

  '@vitest/snapshot@1.6.1':
    dependencies:
      magic-string: 0.30.21
      pathe: 1.1.2
      pretty-format: 29.7.0

  '@vitest/snapshot@3.2.4':
    dependencies:
      '@vitest/pretty-format': 3.2.4
      magic-string: 0.30.21
      pathe: 2.0.3

  '@vitest/spy@1.6.1':
    dependencies:
      tinyspy: 2.2.1

  '@vitest/spy@3.2.4':
    dependencies:
      tinyspy: 4.0.4

  '@vitest/utils@1.6.1':
    dependencies:
      diff-sequences: 29.6.3
      estree-walker: 3.0.3
      loupe: 2.3.7
      pretty-format: 29.7.0

  '@vitest/utils@3.2.4':
    dependencies:
      '@vitest/pretty-format': 3.2.4
      loupe: 3.2.1
      tinyrainbow: 2.0.0

  abort-controller@3.0.0:
    dependencies:
      event-target-shim: 5.0.1

  accepts@1.3.8:
    dependencies:
      mime-types: 2.1.35
      negotiator: 0.6.3

  acorn-walk@8.3.5:
    dependencies:
      acorn: 8.16.0

  acorn@8.16.0: {}

  agent-base@7.1.4: {}

  agentkeepalive@4.6.0:
    dependencies:
      humanize-ms: 1.2.1

  ansi-colors@4.1.3: {}

  ansi-regex@5.0.1: {}

  ansi-styles@5.2.0: {}

  any-promise@1.3.0: {}

  anymatch@3.1.3:
    dependencies:
      normalize-path: 3.0.0
      picomatch: 2.3.2

  arg@5.0.2: {}

  argparse@1.0.10:
    dependencies:
      sprintf-js: 1.0.3

  argparse@2.0.1: {}

  aria-query@5.3.0:
    dependencies:
      dequal: 2.0.3

  aria-query@5.3.1: {}

  aria-query@5.3.2: {}

  array-flatten@1.1.1: {}

  array-union@2.1.0: {}

  asn1.js@4.10.1:
    dependencies:
      bn.js: 4.12.3
      inherits: 2.0.4
      minimalistic-assert: 1.0.1

  assert@2.1.0:
    dependencies:
      call-bind: 1.0.9
      is-nan: 1.3.2
      object-is: 1.1.6
      object.assign: 4.1.7
      util: 0.12.5

  assertion-error@1.1.0: {}

  assertion-error@2.0.1: {}

  asynckit@0.4.0: {}

  autoprefixer@10.4.27(postcss@8.5.9):
    dependencies:
      browserslist: 4.28.2
      caniuse-lite: 1.0.30001787
      fraction.js: 5.3.4
      picocolors: 1.1.1
      postcss: 8.5.9
      postcss-value-parser: 4.2.0

  available-typed-arrays@1.0.7:
    dependencies:
      possible-typed-array-names: 1.1.0

  axobject-query@4.1.0: {}

  balanced-match@4.0.4: {}

  base64-js@1.5.1: {}

  baseline-browser-mapping@2.10.18: {}

  better-path-resolve@1.0.0:
    dependencies:
      is-windows: 1.0.2

  binary-extensions@2.3.0: {}

  bitecs@0.4.0: {}

  bn.js@4.12.3: {}

  bn.js@5.2.3: {}

  body-parser@1.20.4:
    dependencies:
      bytes: 3.1.2
      content-type: 1.0.5
      debug: 2.6.9
      depd: 2.0.0
      destroy: 1.2.0
      http-errors: 2.0.1
      iconv-lite: 0.4.24
      on-finished: 2.4.1
      qs: 6.14.2
      raw-body: 2.5.3
      type-is: 1.6.18
      unpipe: 1.0.0
    transitivePeerDependencies:
      - supports-color

  brace-expansion@5.0.5:
    dependencies:
      balanced-match: 4.0.4

  braces@3.0.3:
    dependencies:
      fill-range: 7.1.1

  brorand@1.1.0: {}

  browser-resolve@2.0.0:
    dependencies:
      resolve: 1.22.11

  browserify-aes@1.2.0:
    dependencies:
      buffer-xor: 1.0.3
      cipher-base: 1.0.7
      create-hash: 1.2.0
      evp_bytestokey: 1.0.3
      inherits: 2.0.4
      safe-buffer: 5.2.1

  browserify-cipher@1.0.1:
    dependencies:
      browserify-aes: 1.2.0
      browserify-des: 1.0.2
      evp_bytestokey: 1.0.3

  browserify-des@1.0.2:
    dependencies:
      cipher-base: 1.0.7
      des.js: 1.1.0
      inherits: 2.0.4
      safe-buffer: 5.2.1

  browserify-rsa@4.1.1:
    dependencies:
      bn.js: 5.2.3
      randombytes: 2.1.0
      safe-buffer: 5.2.1

  browserify-sign@4.2.5:
    dependencies:
      bn.js: 5.2.3
      browserify-rsa: 4.1.1
      create-hash: 1.2.0
      create-hmac: 1.1.7
      elliptic: 6.6.1
      inherits: 2.0.4
      parse-asn1: 5.1.9
      readable-stream: 2.3.8
      safe-buffer: 5.2.1

  browserify-zlib@0.2.0:
    dependencies:
      pako: 1.0.11

  browserslist@4.28.2:
    dependencies:
      baseline-browser-mapping: 2.10.18
      caniuse-lite: 1.0.30001787
      electron-to-chromium: 1.5.335
      node-releases: 2.0.37
      update-browserslist-db: 1.2.3(browserslist@4.28.2)

  buffer-from@1.1.2: {}

  buffer-xor@1.0.3: {}

  buffer@5.7.1:
    dependencies:
      base64-js: 1.5.1
      ieee754: 1.2.1

  builtin-status-codes@3.0.0: {}

  bun-types@1.3.13:
    dependencies:
      '@types/node': 20.19.39

  bytes@3.1.2: {}

  cac@6.7.14: {}

  call-bind-apply-helpers@1.0.2:
    dependencies:
      es-errors: 1.3.0
      function-bind: 1.1.2

  call-bind@1.0.9:
    dependencies:
      call-bind-apply-helpers: 1.0.2
      es-define-property: 1.0.1
      get-intrinsic: 1.3.0
      set-function-length: 1.2.2

  call-bound@1.0.4:
    dependencies:
      call-bind-apply-helpers: 1.0.2
      get-intrinsic: 1.3.0

  camelcase-css@2.0.1: {}

  caniuse-lite@1.0.30001787: {}

  cbor-extract@2.2.2:
    dependencies:
      node-gyp-build-optional-packages: 5.1.1
    optionalDependencies:
      '@cbor-extract/cbor-extract-darwin-arm64': 2.2.2
      '@cbor-extract/cbor-extract-darwin-x64': 2.2.2
      '@cbor-extract/cbor-extract-linux-arm': 2.2.2
      '@cbor-extract/cbor-extract-linux-arm64': 2.2.2
      '@cbor-extract/cbor-extract-linux-x64': 2.2.2
      '@cbor-extract/cbor-extract-win32-x64': 2.2.2
    optional: true

  cbor-x@1.6.4:
    optionalDependencies:
      cbor-extract: 2.2.2

  chai@4.5.0:
    dependencies:
      assertion-error: 1.1.0
      check-error: 1.0.3
      deep-eql: 4.1.4
      get-func-name: 2.0.2
      loupe: 2.3.7
      pathval: 1.1.1
      type-detect: 4.1.0

  chai@5.3.3:
    dependencies:
      assertion-error: 2.0.1
      check-error: 2.1.3
      deep-eql: 5.0.2
      loupe: 3.2.1
      pathval: 2.0.1

  chardet@2.1.1: {}

  check-error@1.0.3:
    dependencies:
      get-func-name: 2.0.2

  check-error@2.1.3: {}

  chokidar@3.6.0:
    dependencies:
      anymatch: 3.1.3
      braces: 3.0.3
      glob-parent: 5.1.2
      is-binary-path: 2.1.0
      is-glob: 4.0.3
      normalize-path: 3.0.0
      readdirp: 3.6.0
    optionalDependencies:
      fsevents: 2.3.3

  chokidar@4.0.3:
    dependencies:
      readdirp: 4.1.2

  cipher-base@1.0.7:
    dependencies:
      inherits: 2.0.4
      safe-buffer: 5.2.1
      to-buffer: 1.2.2

  clsx@2.1.1: {}

  code-block-writer@13.0.3: {}

  combined-stream@1.0.8:
    dependencies:
      delayed-stream: 1.0.0

  commander@4.1.1: {}

  confbox@0.1.8: {}

  console-browserify@1.2.0: {}

  constants-browserify@1.0.0: {}

  content-disposition@0.5.4:
    dependencies:
      safe-buffer: 5.2.1

  content-type@1.0.5: {}

  convert-source-map@2.0.0: {}

  cookie-signature@1.0.7: {}

  cookie@0.7.2: {}

  core-util-is@1.0.3: {}

  cors@2.8.6:
    dependencies:
      object-assign: 4.1.1
      vary: 1.1.2

  create-ecdh@4.0.4:
    dependencies:
      bn.js: 4.12.3
      elliptic: 6.6.1

  create-hash@1.2.0:
    dependencies:
      cipher-base: 1.0.7
      inherits: 2.0.4
      md5.js: 1.3.5
      ripemd160: 2.0.3
      sha.js: 2.4.12

  create-hmac@1.1.7:
    dependencies:
      cipher-base: 1.0.7
      create-hash: 1.2.0
      inherits: 2.0.4
      ripemd160: 2.0.3
      safe-buffer: 5.2.1
      sha.js: 2.4.12

  create-require@1.1.1: {}

  crelt@1.0.6: {}

  cross-spawn@7.0.6:
    dependencies:
      path-key: 3.1.1
      shebang-command: 2.0.0
      which: 2.0.2

  crypto-browserify@3.12.1:
    dependencies:
      browserify-cipher: 1.0.1
      browserify-sign: 4.2.5
      create-ecdh: 4.0.4
      create-hash: 1.2.0
      create-hmac: 1.1.7
      diffie-hellman: 5.0.3
      hash-base: 3.0.5
      inherits: 2.0.4
      pbkdf2: 3.1.5
      public-encrypt: 4.0.3
      randombytes: 2.1.0
      randomfill: 1.0.4

  css.escape@1.5.1: {}

  cssesc@3.0.0: {}

  cssstyle@4.6.0:
    dependencies:
      '@asamuzakjp/css-color': 3.2.0
      rrweb-cssom: 0.8.0

  csstype@3.2.3: {}

  d3-array@3.2.4:
    dependencies:
      internmap: 2.0.3

  d3-color@3.1.0: {}

  d3-dispatch@3.0.1: {}

  d3-force@3.0.0:
    dependencies:
      d3-dispatch: 3.0.1
      d3-quadtree: 3.0.1
      d3-timer: 3.0.1

  d3-format@3.1.2: {}

  d3-interpolate@3.0.1:
    dependencies:
      d3-color: 3.1.0

  d3-quadtree@3.0.1: {}

  d3-scale@4.0.2:
    dependencies:
      d3-array: 3.2.4
      d3-format: 3.1.2
      d3-interpolate: 3.0.1
      d3-time: 3.1.0
      d3-time-format: 4.1.0

  d3-time-format@4.1.0:
    dependencies:
      d3-time: 3.1.0

  d3-time@3.1.0:
    dependencies:
      d3-array: 3.2.4

  d3-timer@3.0.1: {}

  data-urls@5.0.0:
    dependencies:
      whatwg-mimetype: 4.0.0
      whatwg-url: 14.2.0

  dataloader@1.4.0: {}

  debug@2.6.9:
    dependencies:
      ms: 2.0.0

  debug@4.4.3:
    dependencies:
      ms: 2.1.3

  decimal.js@10.6.0: {}

  deep-eql@4.1.4:
    dependencies:
      type-detect: 4.1.0

  deep-eql@5.0.2: {}

  deepmerge@4.3.1: {}

  define-data-property@1.1.4:
    dependencies:
      es-define-property: 1.0.1
      es-errors: 1.3.0
      gopd: 1.2.0

  define-properties@1.2.1:
    dependencies:
      define-data-property: 1.1.4
      has-property-descriptors: 1.0.2
      object-keys: 1.1.1

  delayed-stream@1.0.0: {}

  depd@2.0.0: {}

  dequal@2.0.3: {}

  des.js@1.1.0:
    dependencies:
      inherits: 2.0.4
      minimalistic-assert: 1.0.1

  destroy@1.2.0: {}

  detect-indent@6.1.0: {}

  detect-libc@2.1.2: {}

  devalue@5.7.1: {}

  didyoumean@1.2.2: {}

  diff-sequences@29.6.3: {}

  diffie-hellman@5.0.3:
    dependencies:
      bn.js: 4.12.3
      miller-rabin: 4.0.1
      randombytes: 2.1.0

  dir-glob@3.0.1:
    dependencies:
      path-type: 4.0.0

  dlv@1.1.3: {}

  dom-accessibility-api@0.5.16: {}

  dom-accessibility-api@0.6.3: {}

  domain-browser@4.22.0: {}

  dotenv@8.6.0: {}

  drizzle-kit@0.24.2:
    dependencies:
      '@drizzle-team/brocli': 0.10.2
      '@esbuild-kit/esm-loader': 2.6.5
      esbuild: 0.19.12
      esbuild-register: 3.6.0(esbuild@0.19.12)
    transitivePeerDependencies:
      - supports-color

  drizzle-orm@0.33.0(@electric-sql/pglite@0.4.4)(@types/react@19.2.14)(bun-types@1.3.13)(postgres@3.4.9)(react@19.2.5):
    optionalDependencies:
      '@electric-sql/pglite': 0.4.4
      '@types/react': 19.2.14
      bun-types: 1.3.13
      postgres: 3.4.9
      react: 19.2.5

  dunder-proto@1.0.1:
    dependencies:
      call-bind-apply-helpers: 1.0.2
      es-errors: 1.3.0
      gopd: 1.2.0

  ee-first@1.1.1: {}

  electron-to-chromium@1.5.335: {}

  elliptic@6.6.1:
    dependencies:
      bn.js: 4.12.3
      brorand: 1.1.0
      hash.js: 1.1.7
      hmac-drbg: 1.0.1
      inherits: 2.0.4
      minimalistic-assert: 1.0.1
      minimalistic-crypto-utils: 1.0.1

  encodeurl@2.0.0: {}

  enquirer@2.4.1:
    dependencies:
      ansi-colors: 4.1.3
      strip-ansi: 6.0.1

  entities@6.0.1: {}

  es-define-property@1.0.1: {}

  es-errors@1.3.0: {}

  es-module-lexer@1.7.0: {}

  es-object-atoms@1.1.1:
    dependencies:
      es-errors: 1.3.0

  es-set-tostringtag@2.1.0:
    dependencies:
      es-errors: 1.3.0
      get-intrinsic: 1.3.0
      has-tostringtag: 1.0.2
      hasown: 2.0.2

  esbuild-register@3.6.0(esbuild@0.19.12):
    dependencies:
      debug: 4.4.3
      esbuild: 0.19.12
    transitivePeerDependencies:
      - supports-color

  esbuild@0.18.20:
    optionalDependencies:
      '@esbuild/android-arm': 0.18.20
      '@esbuild/android-arm64': 0.18.20
      '@esbuild/android-x64': 0.18.20
      '@esbuild/darwin-arm64': 0.18.20
      '@esbuild/darwin-x64': 0.18.20
      '@esbuild/freebsd-arm64': 0.18.20
      '@esbuild/freebsd-x64': 0.18.20
      '@esbuild/linux-arm': 0.18.20
      '@esbuild/linux-arm64': 0.18.20
      '@esbuild/linux-ia32': 0.18.20
      '@esbuild/linux-loong64': 0.18.20
      '@esbuild/linux-mips64el': 0.18.20
      '@esbuild/linux-ppc64': 0.18.20
      '@esbuild/linux-riscv64': 0.18.20
      '@esbuild/linux-s390x': 0.18.20
      '@esbuild/linux-x64': 0.18.20
      '@esbuild/netbsd-x64': 0.18.20
      '@esbuild/openbsd-x64': 0.18.20
      '@esbuild/sunos-x64': 0.18.20
      '@esbuild/win32-arm64': 0.18.20
      '@esbuild/win32-ia32': 0.18.20
      '@esbuild/win32-x64': 0.18.20

  esbuild@0.19.12:
    optionalDependencies:
      '@esbuild/aix-ppc64': 0.19.12
      '@esbuild/android-arm': 0.19.12
      '@esbuild/android-arm64': 0.19.12
      '@esbuild/android-x64': 0.19.12
      '@esbuild/darwin-arm64': 0.19.12
      '@esbuild/darwin-x64': 0.19.12
      '@esbuild/freebsd-arm64': 0.19.12
      '@esbuild/freebsd-x64': 0.19.12
      '@esbuild/linux-arm': 0.19.12
      '@esbuild/linux-arm64': 0.19.12
      '@esbuild/linux-ia32': 0.19.12
      '@esbuild/linux-loong64': 0.19.12
      '@esbuild/linux-mips64el': 0.19.12
      '@esbuild/linux-ppc64': 0.19.12
      '@esbuild/linux-riscv64': 0.19.12
      '@esbuild/linux-s390x': 0.19.12
      '@esbuild/linux-x64': 0.19.12
      '@esbuild/netbsd-x64': 0.19.12
      '@esbuild/openbsd-x64': 0.19.12
      '@esbuild/sunos-x64': 0.19.12
      '@esbuild/win32-arm64': 0.19.12
      '@esbuild/win32-ia32': 0.19.12
      '@esbuild/win32-x64': 0.19.12

  esbuild@0.21.5:
    optionalDependencies:
      '@esbuild/aix-ppc64': 0.21.5
      '@esbuild/android-arm': 0.21.5
      '@esbuild/android-arm64': 0.21.5
      '@esbuild/android-x64': 0.21.5
      '@esbuild/darwin-arm64': 0.21.5
      '@esbuild/darwin-x64': 0.21.5
      '@esbuild/freebsd-arm64': 0.21.5
      '@esbuild/freebsd-x64': 0.21.5
      '@esbuild/linux-arm': 0.21.5
      '@esbuild/linux-arm64': 0.21.5
      '@esbuild/linux-ia32': 0.21.5
      '@esbuild/linux-loong64': 0.21.5
      '@esbuild/linux-mips64el': 0.21.5
      '@esbuild/linux-ppc64': 0.21.5
      '@esbuild/linux-riscv64': 0.21.5
      '@esbuild/linux-s390x': 0.21.5
      '@esbuild/linux-x64': 0.21.5
      '@esbuild/netbsd-x64': 0.21.5
      '@esbuild/openbsd-x64': 0.21.5
      '@esbuild/sunos-x64': 0.21.5
      '@esbuild/win32-arm64': 0.21.5
      '@esbuild/win32-ia32': 0.21.5
      '@esbuild/win32-x64': 0.21.5

  esbuild@0.25.12:
    optionalDependencies:
      '@esbuild/aix-ppc64': 0.25.12
      '@esbuild/android-arm': 0.25.12
      '@esbuild/android-arm64': 0.25.12
      '@esbuild/android-x64': 0.25.12
      '@esbuild/darwin-arm64': 0.25.12
      '@esbuild/darwin-x64': 0.25.12
      '@esbuild/freebsd-arm64': 0.25.12
      '@esbuild/freebsd-x64': 0.25.12
      '@esbuild/linux-arm': 0.25.12
      '@esbuild/linux-arm64': 0.25.12
      '@esbuild/linux-ia32': 0.25.12
      '@esbuild/linux-loong64': 0.25.12
      '@esbuild/linux-mips64el': 0.25.12
      '@esbuild/linux-ppc64': 0.25.12
      '@esbuild/linux-riscv64': 0.25.12
      '@esbuild/linux-s390x': 0.25.12
      '@esbuild/linux-x64': 0.25.12
      '@esbuild/netbsd-arm64': 0.25.12
      '@esbuild/netbsd-x64': 0.25.12
      '@esbuild/openbsd-arm64': 0.25.12
      '@esbuild/openbsd-x64': 0.25.12
      '@esbuild/openharmony-arm64': 0.25.12
      '@esbuild/sunos-x64': 0.25.12
      '@esbuild/win32-arm64': 0.25.12
      '@esbuild/win32-ia32': 0.25.12
      '@esbuild/win32-x64': 0.25.12

  esbuild@0.27.7:
    optionalDependencies:
      '@esbuild/aix-ppc64': 0.27.7
      '@esbuild/android-arm': 0.27.7
      '@esbuild/android-arm64': 0.27.7
      '@esbuild/android-x64': 0.27.7
      '@esbuild/darwin-arm64': 0.27.7
      '@esbuild/darwin-x64': 0.27.7
      '@esbuild/freebsd-arm64': 0.27.7
      '@esbuild/freebsd-x64': 0.27.7
      '@esbuild/linux-arm': 0.27.7
      '@esbuild/linux-arm64': 0.27.7
      '@esbuild/linux-ia32': 0.27.7
      '@esbuild/linux-loong64': 0.27.7
      '@esbuild/linux-mips64el': 0.27.7
      '@esbuild/linux-ppc64': 0.27.7
      '@esbuild/linux-riscv64': 0.27.7
      '@esbuild/linux-s390x': 0.27.7
      '@esbuild/linux-x64': 0.27.7
      '@esbuild/netbsd-arm64': 0.27.7
      '@esbuild/netbsd-x64': 0.27.7
      '@esbuild/openbsd-arm64': 0.27.7
      '@esbuild/openbsd-x64': 0.27.7
      '@esbuild/openharmony-arm64': 0.27.7
      '@esbuild/sunos-x64': 0.27.7
      '@esbuild/win32-arm64': 0.27.7
      '@esbuild/win32-ia32': 0.27.7
      '@esbuild/win32-x64': 0.27.7

  escalade@3.2.0: {}

  escape-html@1.0.3: {}

  esm-env@1.2.2: {}

  esprima@4.0.1: {}

  esrap@2.2.5:
    dependencies:
      '@jridgewell/sourcemap-codec': 1.5.5

  estree-walker@2.0.2: {}

  estree-walker@3.0.3:
    dependencies:
      '@types/estree': 1.0.8

  etag@1.8.1: {}

  event-target-shim@5.0.1: {}

  events@3.3.0: {}

  evp_bytestokey@1.0.3:
    dependencies:
      md5.js: 1.3.5
      safe-buffer: 5.2.1

  execa@8.0.1:
    dependencies:
      cross-spawn: 7.0.6
      get-stream: 8.0.1
      human-signals: 5.0.0
      is-stream: 3.0.0
      merge-stream: 2.0.0
      npm-run-path: 5.3.0
      onetime: 6.0.0
      signal-exit: 4.1.0
      strip-final-newline: 3.0.0

  expect-type@1.3.0: {}

  express@4.22.1:
    dependencies:
      accepts: 1.3.8
      array-flatten: 1.1.1
      body-parser: 1.20.4
      content-disposition: 0.5.4
      content-type: 1.0.5
      cookie: 0.7.2
      cookie-signature: 1.0.7
      debug: 2.6.9
      depd: 2.0.0
      encodeurl: 2.0.0
      escape-html: 1.0.3
      etag: 1.8.1
      finalhandler: 1.3.2
      fresh: 0.5.2
      http-errors: 2.0.1
      merge-descriptors: 1.0.3
      methods: 1.1.2
      on-finished: 2.4.1
      parseurl: 1.3.3
      path-to-regexp: 0.1.13
      proxy-addr: 2.0.7
      qs: 6.14.2
      range-parser: 1.2.1
      safe-buffer: 5.2.1
      send: 0.19.2
      serve-static: 1.16.3
      setprototypeof: 1.2.0
      statuses: 2.0.2
      type-is: 1.6.18
      utils-merge: 1.0.1
      vary: 1.1.2
    transitivePeerDependencies:
      - supports-color

  extendable-error@0.1.7: {}

  fake-indexeddb@6.2.5: {}

  fast-check@3.23.2:
    dependencies:
      pure-rand: 6.1.0

  fast-glob@3.3.3:
    dependencies:
      '@nodelib/fs.stat': 2.0.5
      '@nodelib/fs.walk': 1.2.8
      glob-parent: 5.1.2
      merge2: 1.4.1
      micromatch: 4.0.8

  fast-sha256@1.3.0: {}

  fastq@1.20.1:
    dependencies:
      reusify: 1.1.0

  fdir@6.5.0(picomatch@4.0.4):
    optionalDependencies:
      picomatch: 4.0.4

  fflate@0.8.2: {}

  fill-range@7.1.1:
    dependencies:
      to-regex-range: 5.0.1

  finalhandler@1.3.2:
    dependencies:
      debug: 2.6.9
      encodeurl: 2.0.0
      escape-html: 1.0.3
      on-finished: 2.4.1
      parseurl: 1.3.3
      statuses: 2.0.2
      unpipe: 1.0.0
    transitivePeerDependencies:
      - supports-color

  find-up@4.1.0:
    dependencies:
      locate-path: 5.0.0
      path-exists: 4.0.0

  find-up@5.0.0:
    dependencies:
      locate-path: 6.0.0
      path-exists: 4.0.0

  for-each@0.3.5:
    dependencies:
      is-callable: 1.2.7

  form-data-encoder@1.7.2: {}

  form-data@4.0.5:
    dependencies:
      asynckit: 0.4.0
      combined-stream: 1.0.8
      es-set-tostringtag: 2.1.0
      hasown: 2.0.2
      mime-types: 2.1.35

  formdata-node@4.4.1:
    dependencies:
      node-domexception: 1.0.0
      web-streams-polyfill: 4.0.0-beta.3

  forwarded@0.2.0: {}

  fraction.js@5.3.4: {}

  fresh@0.5.2: {}

  fs-extra@7.0.1:
    dependencies:
      graceful-fs: 4.2.11
      jsonfile: 4.0.0
      universalify: 0.1.2

  fs-extra@8.1.0:
    dependencies:
      graceful-fs: 4.2.11
      jsonfile: 4.0.0
      universalify: 0.1.2

  fsevents@2.3.3:
    optional: true

  function-bind@1.1.2: {}

  generator-function@2.0.1: {}

  gensync@1.0.0-beta.2: {}

  geotiff@3.0.5:
    dependencies:
      '@petamoriken/float16': 3.9.3
      lerc: 3.0.0
      pako: 2.1.0
      parse-headers: 2.0.6
      quick-lru: 6.1.2
      web-worker: 1.5.0
      xml-utils: 1.10.2
      zstddec: 0.2.0

  get-func-name@2.0.2: {}

  get-intrinsic@1.3.0:
    dependencies:
      call-bind-apply-helpers: 1.0.2
      es-define-property: 1.0.1
      es-errors: 1.3.0
      es-object-atoms: 1.1.1
      function-bind: 1.1.2
      get-proto: 1.0.1
      gopd: 1.2.0
      has-symbols: 1.1.0
      hasown: 2.0.2
      math-intrinsics: 1.1.0

  get-proto@1.0.1:
    dependencies:
      dunder-proto: 1.0.1
      es-object-atoms: 1.1.1

  get-stream@8.0.1: {}

  get-tsconfig@4.14.0:
    dependencies:
      resolve-pkg-maps: 1.0.0

  glob-parent@5.1.2:
    dependencies:
      is-glob: 4.0.3

  glob-parent@6.0.2:
    dependencies:
      is-glob: 4.0.3

  glob@13.0.6:
    dependencies:
      minimatch: 10.2.5
      minipass: 7.1.3
      path-scurry: 2.0.2

  globby@11.1.0:
    dependencies:
      array-union: 2.1.0
      dir-glob: 3.0.1
      fast-glob: 3.3.3
      ignore: 5.3.2
      merge2: 1.4.1
      slash: 3.0.0

  gopd@1.2.0: {}

  graceful-fs@4.2.11: {}

  has-property-descriptors@1.0.2:
    dependencies:
      es-define-property: 1.0.1

  has-symbols@1.1.0: {}

  has-tostringtag@1.0.2:
    dependencies:
      has-symbols: 1.1.0

  hash-base@3.0.5:
    dependencies:
      inherits: 2.0.4
      safe-buffer: 5.2.1

  hash-base@3.1.2:
    dependencies:
      inherits: 2.0.4
      readable-stream: 2.3.8
      safe-buffer: 5.2.1
      to-buffer: 1.2.2

  hash.js@1.1.7:
    dependencies:
      inherits: 2.0.4
      minimalistic-assert: 1.0.1

  hasown@2.0.2:
    dependencies:
      function-bind: 1.1.2

  hmac-drbg@1.0.1:
    dependencies:
      hash.js: 1.1.7
      minimalistic-assert: 1.0.1
      minimalistic-crypto-utils: 1.0.1

  html-encoding-sniffer@4.0.0:
    dependencies:
      whatwg-encoding: 3.1.1

  http-errors@2.0.1:
    dependencies:
      depd: 2.0.0
      inherits: 2.0.4
      setprototypeof: 1.2.0
      statuses: 2.0.2
      toidentifier: 1.0.1

  http-proxy-agent@7.0.2:
    dependencies:
      agent-base: 7.1.4
      debug: 4.4.3
    transitivePeerDependencies:
      - supports-color

  https-browserify@1.0.0: {}

  https-proxy-agent@7.0.6:
    dependencies:
      agent-base: 7.1.4
      debug: 4.4.3
    transitivePeerDependencies:
      - supports-color

  human-id@4.1.3: {}

  human-signals@5.0.0: {}

  humanize-ms@1.2.1:
    dependencies:
      ms: 2.1.3

  iconv-lite@0.4.24:
    dependencies:
      safer-buffer: 2.1.2

  iconv-lite@0.6.3:
    dependencies:
      safer-buffer: 2.1.2

  iconv-lite@0.7.2:
    dependencies:
      safer-buffer: 2.1.2

  ieee754@1.2.1: {}

  ignore@5.3.2: {}

  indent-string@4.0.0: {}

  inherits@2.0.4: {}

  internmap@2.0.3: {}

  ipaddr.js@1.9.1: {}

  is-arguments@1.2.0:
    dependencies:
      call-bound: 1.0.4
      has-tostringtag: 1.0.2

  is-binary-path@2.1.0:
    dependencies:
      binary-extensions: 2.3.0

  is-callable@1.2.7: {}

  is-core-module@2.16.1:
    dependencies:
      hasown: 2.0.2

  is-extglob@2.1.1: {}

  is-generator-function@1.1.2:
    dependencies:
      call-bound: 1.0.4
      generator-function: 2.0.1
      get-proto: 1.0.1
      has-tostringtag: 1.0.2
      safe-regex-test: 1.1.0

  is-glob@4.0.3:
    dependencies:
      is-extglob: 2.1.1

  is-nan@1.3.2:
    dependencies:
      call-bind: 1.0.9
      define-properties: 1.2.1

  is-number@7.0.0: {}

  is-potential-custom-element-name@1.0.1: {}

  is-reference@3.0.3:
    dependencies:
      '@types/estree': 1.0.8

  is-regex@1.2.1:
    dependencies:
      call-bound: 1.0.4
      gopd: 1.2.0
      has-tostringtag: 1.0.2
      hasown: 2.0.2

  is-stream@3.0.0: {}

  is-subdir@1.2.0:
    dependencies:
      better-path-resolve: 1.0.0

  is-typed-array@1.1.15:
    dependencies:
      which-typed-array: 1.1.20

  is-windows@1.0.2: {}

  isarray@1.0.0: {}

  isarray@2.0.5: {}

  isexe@2.0.0: {}

  isomorphic-timers-promises@1.0.1: {}

  jiti@1.21.7: {}

  js-tokens@4.0.0: {}

  js-tokens@9.0.1: {}

  js-yaml@3.14.2:
    dependencies:
      argparse: 1.0.10
      esprima: 4.0.1

  js-yaml@4.1.1:
    dependencies:
      argparse: 2.0.1

  jsdom@25.0.1:
    dependencies:
      cssstyle: 4.6.0
      data-urls: 5.0.0
      decimal.js: 10.6.0
      form-data: 4.0.5
      html-encoding-sniffer: 4.0.0
      http-proxy-agent: 7.0.2
      https-proxy-agent: 7.0.6
      is-potential-custom-element-name: 1.0.1
      nwsapi: 2.2.23
      parse5: 7.3.0
      rrweb-cssom: 0.7.1
      saxes: 6.0.0
      symbol-tree: 3.2.4
      tough-cookie: 5.1.2
      w3c-xmlserializer: 5.0.0
      webidl-conversions: 7.0.0
      whatwg-encoding: 3.1.1
      whatwg-mimetype: 4.0.0
      whatwg-url: 14.2.0
      ws: 8.20.0
      xml-name-validator: 5.0.0
    transitivePeerDependencies:
      - bufferutil
      - supports-color
      - utf-8-validate

  jsesc@3.1.0: {}

  json-schema-to-ts@3.1.1:
    dependencies:
      '@babel/runtime': 7.29.2
      ts-algebra: 2.0.0

  json5@2.2.3: {}

  jsonfile@4.0.0:
    optionalDependencies:
      graceful-fs: 4.2.11

  kleur@4.1.5: {}

  lerc@3.0.0: {}

  lilconfig@3.1.3: {}

  lines-and-columns@1.2.4: {}

  local-pkg@0.5.1:
    dependencies:
      mlly: 1.8.2
      pkg-types: 1.3.1

  locate-character@3.0.0: {}

  locate-path@5.0.0:
    dependencies:
      p-locate: 4.1.0

  locate-path@6.0.0:
    dependencies:
      p-locate: 5.0.0

  lodash.startcase@4.4.0: {}

  loupe@2.3.7:
    dependencies:
      get-func-name: 2.0.2

  loupe@3.2.1: {}

  lru-cache@10.4.3: {}

  lru-cache@11.3.5: {}

  lru-cache@5.1.1:
    dependencies:
      yallist: 3.1.1

  lz-string@1.5.0: {}

  magic-string@0.30.21:
    dependencies:
      '@jridgewell/sourcemap-codec': 1.5.5

  math-intrinsics@1.1.0: {}

  md5.js@1.3.5:
    dependencies:
      hash-base: 3.1.2
      inherits: 2.0.4
      safe-buffer: 5.2.1

  media-typer@0.3.0: {}

  merge-descriptors@1.0.3: {}

  merge-stream@2.0.0: {}

  merge2@1.4.1: {}

  meshoptimizer@0.18.1: {}

  methods@1.1.2: {}

  micromatch@4.0.8:
    dependencies:
      braces: 3.0.3
      picomatch: 2.3.2

  miller-rabin@4.0.1:
    dependencies:
      bn.js: 4.12.3
      brorand: 1.1.0

  mime-db@1.52.0: {}

  mime-types@2.1.35:
    dependencies:
      mime-db: 1.52.0

  mime@1.6.0: {}

  mimic-fn@4.0.0: {}

  min-indent@1.0.1: {}

  minimalistic-assert@1.0.1: {}

  minimalistic-crypto-utils@1.0.1: {}

  minimatch@10.2.5:
    dependencies:
      brace-expansion: 5.0.5

  minipass@7.1.3: {}

  mlly@1.8.2:
    dependencies:
      acorn: 8.16.0
      pathe: 2.0.3
      pkg-types: 1.3.1
      ufo: 1.6.3

  mri@1.2.0: {}

  ms@2.0.0: {}

  ms@2.1.3: {}

  mz@2.7.0:
    dependencies:
      any-promise: 1.3.0
      object-assign: 4.1.1
      thenify-all: 1.6.0

  nanoid@3.3.11: {}

  negotiator@0.6.3: {}

  node-domexception@1.0.0: {}

  node-fetch@2.7.0:
    dependencies:
      whatwg-url: 5.0.0

  node-gyp-build-optional-packages@5.1.1:
    dependencies:
      detect-libc: 2.1.2
    optional: true

  node-releases@2.0.37: {}

  node-stdlib-browser@1.3.1:
    dependencies:
      assert: 2.1.0
      browser-resolve: 2.0.0
      browserify-zlib: 0.2.0
      buffer: 5.7.1
      console-browserify: 1.2.0
      constants-browserify: 1.0.0
      create-require: 1.1.1
      crypto-browserify: 3.12.1
      domain-browser: 4.22.0
      events: 3.3.0
      https-browserify: 1.0.0
      isomorphic-timers-promises: 1.0.1
      os-browserify: 0.3.0
      path-browserify: 1.0.1
      pkg-dir: 5.0.0
      process: 0.11.10
      punycode: 1.4.1
      querystring-es3: 0.2.1
      readable-stream: 3.6.2
      stream-browserify: 3.0.0
      stream-http: 3.2.0
      string_decoder: 1.3.0
      timers-browserify: 2.0.12
      tty-browserify: 0.0.1
      url: 0.11.4
      util: 0.12.5
      vm-browserify: 1.1.2

  normalize-path@3.0.0: {}

  npm-run-path@5.3.0:
    dependencies:
      path-key: 4.0.0

  nwsapi@2.2.23: {}

  object-assign@4.1.1: {}

  object-hash@3.0.0: {}

  object-inspect@1.13.4: {}

  object-is@1.1.6:
    dependencies:
      call-bind: 1.0.9
      define-properties: 1.2.1

  object-keys@1.1.1: {}

  object.assign@4.1.7:
    dependencies:
      call-bind: 1.0.9
      call-bound: 1.0.4
      define-properties: 1.2.1
      es-object-atoms: 1.1.1
      has-symbols: 1.1.0
      object-keys: 1.1.1

  on-finished@2.4.1:
    dependencies:
      ee-first: 1.1.1

  onetime@6.0.0:
    dependencies:
      mimic-fn: 4.0.0

  os-browserify@0.3.0: {}

  outdent@0.5.0: {}

  p-filter@2.1.0:
    dependencies:
      p-map: 2.1.0

  p-limit@2.3.0:
    dependencies:
      p-try: 2.2.0

  p-limit@3.1.0:
    dependencies:
      yocto-queue: 0.1.0

  p-limit@5.0.0:
    dependencies:
      yocto-queue: 1.2.2

  p-locate@4.1.0:
    dependencies:
      p-limit: 2.3.0

  p-locate@5.0.0:
    dependencies:
      p-limit: 3.1.0

  p-map@2.1.0: {}

  p-try@2.2.0: {}

  package-manager-detector@0.2.11:
    dependencies:
      quansync: 0.2.11

  pako@1.0.11: {}

  pako@2.1.0: {}

  parse-asn1@5.1.9:
    dependencies:
      asn1.js: 4.10.1
      browserify-aes: 1.2.0
      evp_bytestokey: 1.0.3
      pbkdf2: 3.1.5
      safe-buffer: 5.2.1

  parse-headers@2.0.6: {}

  parse5@7.3.0:
    dependencies:
      entities: 6.0.1

  parseurl@1.3.3: {}

  path-browserify@1.0.1: {}

  path-exists@4.0.0: {}

  path-key@3.1.1: {}

  path-key@4.0.0: {}

  path-parse@1.0.7: {}

  path-scurry@2.0.2:
    dependencies:
      lru-cache: 11.3.5
      minipass: 7.1.3

  path-to-regexp@0.1.13: {}

  path-type@4.0.0: {}

  pathe@1.1.2: {}

  pathe@2.0.3: {}

  pathval@1.1.1: {}

  pathval@2.0.1: {}

  pbkdf2@3.1.5:
    dependencies:
      create-hash: 1.2.0
      create-hmac: 1.1.7
      ripemd160: 2.0.3
      safe-buffer: 5.2.1
      sha.js: 2.4.12
      to-buffer: 1.2.2

  phoenix@1.8.5: {}

  picocolors@1.1.1: {}

  picomatch@2.3.2: {}

  picomatch@4.0.4: {}

  pify@2.3.0: {}

  pify@4.0.1: {}

  pirates@4.0.7: {}

  pkg-dir@5.0.0:
    dependencies:
      find-up: 5.0.0

  pkg-types@1.3.1:
    dependencies:
      confbox: 0.1.8
      mlly: 1.8.2
      pathe: 2.0.3

  possible-typed-array-names@1.1.0: {}

  postcss-import@15.1.0(postcss@8.5.9):
    dependencies:
      postcss: 8.5.9
      postcss-value-parser: 4.2.0
      read-cache: 1.0.0
      resolve: 1.22.11

  postcss-js@4.1.0(postcss@8.5.9):
    dependencies:
      camelcase-css: 2.0.1
      postcss: 8.5.9

  postcss-load-config@6.0.1(jiti@1.21.7)(postcss@8.5.9)(tsx@4.21.0)(yaml@2.9.0):
    dependencies:
      lilconfig: 3.1.3
    optionalDependencies:
      jiti: 1.21.7
      postcss: 8.5.9
      tsx: 4.21.0
      yaml: 2.9.0

  postcss-nested@6.2.0(postcss@8.5.9):
    dependencies:
      postcss: 8.5.9
      postcss-selector-parser: 6.1.2

  postcss-selector-parser@6.1.2:
    dependencies:
      cssesc: 3.0.0
      util-deprecate: 1.0.2

  postcss-value-parser@4.2.0: {}

  postcss@8.5.9:
    dependencies:
      nanoid: 3.3.11
      picocolors: 1.1.1
      source-map-js: 1.2.1

  postgres@3.4.9: {}

  prettier@2.8.8: {}

  pretty-format@27.5.1:
    dependencies:
      ansi-regex: 5.0.1
      ansi-styles: 5.2.0
      react-is: 17.0.2

  pretty-format@29.7.0:
    dependencies:
      '@jest/schemas': 29.6.3
      ansi-styles: 5.2.0
      react-is: 18.3.1

  process-nextick-args@2.0.1: {}

  process@0.11.10: {}

  proxy-addr@2.0.7:
    dependencies:
      forwarded: 0.2.0
      ipaddr.js: 1.9.1

  public-encrypt@4.0.3:
    dependencies:
      bn.js: 4.12.3
      browserify-rsa: 4.1.1
      create-hash: 1.2.0
      parse-asn1: 5.1.9
      randombytes: 2.1.0
      safe-buffer: 5.2.1

  punycode@1.4.1: {}

  punycode@2.3.1: {}

  pure-rand@6.1.0: {}

  qs@6.14.2:
    dependencies:
      side-channel: 1.1.0

  qs@6.15.1:
    dependencies:
      side-channel: 1.1.0

  quansync@0.2.11: {}

  querystring-es3@0.2.1: {}

  queue-microtask@1.2.3: {}

  quick-lru@6.1.2: {}

  randombytes@2.1.0:
    dependencies:
      safe-buffer: 5.2.1

  randomfill@1.0.4:
    dependencies:
      randombytes: 2.1.0
      safe-buffer: 5.2.1

  range-parser@1.2.1: {}

  raw-body@2.5.3:
    dependencies:
      bytes: 3.1.2
      http-errors: 2.0.1
      iconv-lite: 0.4.24
      unpipe: 1.0.0

  react-dom@19.2.5(react@19.2.5):
    dependencies:
      react: 19.2.5
      scheduler: 0.27.0

  react-is@17.0.2: {}

  react-is@18.3.1: {}

  react-refresh@0.17.0: {}

  react@19.2.5: {}

  read-cache@1.0.0:
    dependencies:
      pify: 2.3.0

  read-yaml-file@1.1.0:
    dependencies:
      graceful-fs: 4.2.11
      js-yaml: 3.14.2
      pify: 4.0.1
      strip-bom: 3.0.0

  readable-stream@2.3.8:
    dependencies:
      core-util-is: 1.0.3
      inherits: 2.0.4
      isarray: 1.0.0
      process-nextick-args: 2.0.1
      safe-buffer: 5.1.2
      string_decoder: 1.1.1
      util-deprecate: 1.0.2

  readable-stream@3.6.2:
    dependencies:
      inherits: 2.0.4
      string_decoder: 1.3.0
      util-deprecate: 1.0.2

  readdirp@3.6.0:
    dependencies:
      picomatch: 2.3.2

  readdirp@4.1.2: {}

  redent@3.0.0:
    dependencies:
      indent-string: 4.0.0
      strip-indent: 3.0.0

  resolve-from@5.0.0: {}

  resolve-pkg-maps@1.0.0: {}

  resolve@1.22.11:
    dependencies:
      is-core-module: 2.16.1
      path-parse: 1.0.7
      supports-preserve-symlinks-flag: 1.0.0

  reusify@1.1.0: {}

  ripemd160@2.0.3:
    dependencies:
      hash-base: 3.1.2
      inherits: 2.0.4

  rollup@4.60.1:
    dependencies:
      '@types/estree': 1.0.8
    optionalDependencies:
      '@rollup/rollup-android-arm-eabi': 4.60.1
      '@rollup/rollup-android-arm64': 4.60.1
      '@rollup/rollup-darwin-arm64': 4.60.1
      '@rollup/rollup-darwin-x64': 4.60.1
      '@rollup/rollup-freebsd-arm64': 4.60.1
      '@rollup/rollup-freebsd-x64': 4.60.1
      '@rollup/rollup-linux-arm-gnueabihf': 4.60.1
      '@rollup/rollup-linux-arm-musleabihf': 4.60.1
      '@rollup/rollup-linux-arm64-gnu': 4.60.1
      '@rollup/rollup-linux-arm64-musl': 4.60.1
      '@rollup/rollup-linux-loong64-gnu': 4.60.1
      '@rollup/rollup-linux-loong64-musl': 4.60.1
      '@rollup/rollup-linux-ppc64-gnu': 4.60.1
      '@rollup/rollup-linux-ppc64-musl': 4.60.1
      '@rollup/rollup-linux-riscv64-gnu': 4.60.1
      '@rollup/rollup-linux-riscv64-musl': 4.60.1
      '@rollup/rollup-linux-s390x-gnu': 4.60.1
      '@rollup/rollup-linux-x64-gnu': 4.60.1
      '@rollup/rollup-linux-x64-musl': 4.60.1
      '@rollup/rollup-openbsd-x64': 4.60.1
      '@rollup/rollup-openharmony-arm64': 4.60.1
      '@rollup/rollup-win32-arm64-msvc': 4.60.1
      '@rollup/rollup-win32-ia32-msvc': 4.60.1
      '@rollup/rollup-win32-x64-gnu': 4.60.1
      '@rollup/rollup-win32-x64-msvc': 4.60.1
      fsevents: 2.3.3

  rot-js@2.2.1: {}

  rrweb-cssom@0.7.1: {}

  rrweb-cssom@0.8.0: {}

  run-parallel@1.2.0:
    dependencies:
      queue-microtask: 1.2.3

  sade@1.8.1:
    dependencies:
      mri: 1.2.0

  safe-buffer@5.1.2: {}

  safe-buffer@5.2.1: {}

  safe-regex-test@1.1.0:
    dependencies:
      call-bound: 1.0.4
      es-errors: 1.3.0
      is-regex: 1.2.1

  safer-buffer@2.1.2: {}

  saxes@6.0.0:
    dependencies:
      xmlchars: 2.2.0

  scheduler@0.27.0: {}

  semver@6.3.1: {}

  semver@7.7.4: {}

  send@0.19.2:
    dependencies:
      debug: 2.6.9
      depd: 2.0.0
      destroy: 1.2.0
      encodeurl: 2.0.0
      escape-html: 1.0.3
      etag: 1.8.1
      fresh: 0.5.2
      http-errors: 2.0.1
      mime: 1.6.0
      ms: 2.1.3
      on-finished: 2.4.1
      range-parser: 1.2.1
      statuses: 2.0.2
    transitivePeerDependencies:
      - supports-color

  serve-static@1.16.3:
    dependencies:
      encodeurl: 2.0.0
      escape-html: 1.0.3
      parseurl: 1.3.3
      send: 0.19.2
    transitivePeerDependencies:
      - supports-color

  set-function-length@1.2.2:
    dependencies:
      define-data-property: 1.1.4
      es-errors: 1.3.0
      function-bind: 1.1.2
      get-intrinsic: 1.3.0
      gopd: 1.2.0
      has-property-descriptors: 1.0.2

  setimmediate@1.0.5: {}

  setprototypeof@1.2.0: {}

  sha.js@2.4.12:
    dependencies:
      inherits: 2.0.4
      safe-buffer: 5.2.1
      to-buffer: 1.2.2

  sharp@0.34.5:
    dependencies:
      '@img/colour': 1.1.0
      detect-libc: 2.1.2
      semver: 7.7.4
    optionalDependencies:
      '@img/sharp-darwin-arm64': 0.34.5
      '@img/sharp-darwin-x64': 0.34.5
      '@img/sharp-libvips-darwin-arm64': 1.2.4
      '@img/sharp-libvips-darwin-x64': 1.2.4
      '@img/sharp-libvips-linux-arm': 1.2.4
      '@img/sharp-libvips-linux-arm64': 1.2.4
      '@img/sharp-libvips-linux-ppc64': 1.2.4
      '@img/sharp-libvips-linux-riscv64': 1.2.4
      '@img/sharp-libvips-linux-s390x': 1.2.4
      '@img/sharp-libvips-linux-x64': 1.2.4
      '@img/sharp-libvips-linuxmusl-arm64': 1.2.4
      '@img/sharp-libvips-linuxmusl-x64': 1.2.4
      '@img/sharp-linux-arm': 0.34.5
      '@img/sharp-linux-arm64': 0.34.5
      '@img/sharp-linux-ppc64': 0.34.5
      '@img/sharp-linux-riscv64': 0.34.5
      '@img/sharp-linux-s390x': 0.34.5
      '@img/sharp-linux-x64': 0.34.5
      '@img/sharp-linuxmusl-arm64': 0.34.5
      '@img/sharp-linuxmusl-x64': 0.34.5
      '@img/sharp-wasm32': 0.34.5
      '@img/sharp-win32-arm64': 0.34.5
      '@img/sharp-win32-ia32': 0.34.5
      '@img/sharp-win32-x64': 0.34.5

  shebang-command@2.0.0:
    dependencies:
      shebang-regex: 3.0.0

  shebang-regex@3.0.0: {}

  side-channel-list@1.0.1:
    dependencies:
      es-errors: 1.3.0
      object-inspect: 1.13.4

  side-channel-map@1.0.1:
    dependencies:
      call-bound: 1.0.4
      es-errors: 1.3.0
      get-intrinsic: 1.3.0
      object-inspect: 1.13.4

  side-channel-weakmap@1.0.2:
    dependencies:
      call-bound: 1.0.4
      es-errors: 1.3.0
      get-intrinsic: 1.3.0
      object-inspect: 1.13.4
      side-channel-map: 1.0.1

  side-channel@1.1.0:
    dependencies:
      es-errors: 1.3.0
      object-inspect: 1.13.4
      side-channel-list: 1.0.1
      side-channel-map: 1.0.1
      side-channel-weakmap: 1.0.2

  siginfo@2.0.0: {}

  signal-exit@4.1.0: {}

  slash@3.0.0: {}

  source-map-js@1.2.1: {}

  source-map-support@0.5.21:
    dependencies:
      buffer-from: 1.1.2
      source-map: 0.6.1

  source-map@0.6.1: {}

  spawndamnit@3.0.1:
    dependencies:
      cross-spawn: 7.0.6
      signal-exit: 4.1.0

  sprintf-js@1.0.3: {}

  stackback@0.0.2: {}

  standardwebhooks@1.0.0:
    dependencies:
      '@stablelib/base64': 1.0.1
      fast-sha256: 1.3.0

  statuses@2.0.2: {}

  std-env@3.10.0: {}

  stream-browserify@3.0.0:
    dependencies:
      inherits: 2.0.4
      readable-stream: 3.6.2

  stream-http@3.2.0:
    dependencies:
      builtin-status-codes: 3.0.0
      inherits: 2.0.4
      readable-stream: 3.6.2
      xtend: 4.0.2

  string_decoder@1.1.1:
    dependencies:
      safe-buffer: 5.1.2

  string_decoder@1.3.0:
    dependencies:
      safe-buffer: 5.2.1

  strip-ansi@6.0.1:
    dependencies:
      ansi-regex: 5.0.1

  strip-bom@3.0.0: {}

  strip-final-newline@3.0.0: {}

  strip-indent@3.0.0:
    dependencies:
      min-indent: 1.0.1

  strip-literal@2.1.1:
    dependencies:
      js-tokens: 9.0.1

  strip-literal@3.1.0:
    dependencies:
      js-tokens: 9.0.1

  style-mod@4.1.3: {}

  sucrase@3.35.1:
    dependencies:
      '@jridgewell/gen-mapping': 0.3.13
      commander: 4.1.1
      lines-and-columns: 1.2.4
      mz: 2.7.0
      pirates: 4.0.7
      tinyglobby: 0.2.16
      ts-interface-checker: 0.1.13

  supports-preserve-symlinks-flag@1.0.0: {}

  svelte-check@4.4.6(picomatch@4.0.4)(svelte@5.55.4)(typescript@5.8.3):
    dependencies:
      '@jridgewell/trace-mapping': 0.3.31
      chokidar: 4.0.3
      fdir: 6.5.0(picomatch@4.0.4)
      picocolors: 1.1.1
      sade: 1.8.1
      svelte: 5.55.4
      typescript: 5.8.3
    transitivePeerDependencies:
      - picomatch

  svelte@5.55.4:
    dependencies:
      '@jridgewell/remapping': 2.3.5
      '@jridgewell/sourcemap-codec': 1.5.5
      '@sveltejs/acorn-typescript': 1.0.9(acorn@8.16.0)
      '@types/estree': 1.0.8
      '@types/trusted-types': 2.0.7
      acorn: 8.16.0
      aria-query: 5.3.1
      axobject-query: 4.1.0
      clsx: 2.1.1
      devalue: 5.7.1
      esm-env: 1.2.2
      esrap: 2.2.5
      is-reference: 3.0.3
      locate-character: 3.0.0
      magic-string: 0.30.21
      zimmerframe: 1.1.4
    transitivePeerDependencies:
      - '@typescript-eslint/types'

  symbol-tree@3.2.4: {}

  tailwindcss@3.4.19(tsx@4.21.0)(yaml@2.9.0):
    dependencies:
      '@alloc/quick-lru': 5.2.0
      arg: 5.0.2
      chokidar: 3.6.0
      didyoumean: 1.2.2
      dlv: 1.1.3
      fast-glob: 3.3.3
      glob-parent: 6.0.2
      is-glob: 4.0.3
      jiti: 1.21.7
      lilconfig: 3.1.3
      micromatch: 4.0.8
      normalize-path: 3.0.0
      object-hash: 3.0.0
      picocolors: 1.1.1
      postcss: 8.5.9
      postcss-import: 15.1.0(postcss@8.5.9)
      postcss-js: 4.1.0(postcss@8.5.9)
      postcss-load-config: 6.0.1(jiti@1.21.7)(postcss@8.5.9)(tsx@4.21.0)(yaml@2.9.0)
      postcss-nested: 6.2.0(postcss@8.5.9)
      postcss-selector-parser: 6.1.2
      resolve: 1.22.11
      sucrase: 3.35.1
    transitivePeerDependencies:
      - tsx
      - yaml

  term-size@2.2.1: {}

  thenify-all@1.6.0:
    dependencies:
      thenify: 3.3.1

  thenify@3.3.1:
    dependencies:
      any-promise: 1.3.0

  three@0.165.0: {}

  timers-browserify@2.0.12:
    dependencies:
      setimmediate: 1.0.5

  tinybench@2.9.0: {}

  tinyexec@0.3.2: {}

  tinyglobby@0.2.16:
    dependencies:
      fdir: 6.5.0(picomatch@4.0.4)
      picomatch: 4.0.4

  tinypool@0.8.4: {}

  tinypool@1.1.1: {}

  tinyrainbow@2.0.0: {}

  tinyspy@2.2.1: {}

  tinyspy@4.0.4: {}

  tldts-core@6.1.86: {}

  tldts@6.1.86:
    dependencies:
      tldts-core: 6.1.86

  to-buffer@1.2.2:
    dependencies:
      isarray: 2.0.5
      safe-buffer: 5.2.1
      typed-array-buffer: 1.0.3

  to-regex-range@5.0.1:
    dependencies:
      is-number: 7.0.0

  toidentifier@1.0.1: {}

  tough-cookie@5.1.2:
    dependencies:
      tldts: 6.1.86

  tr46@0.0.3: {}

  tr46@5.1.1:
    dependencies:
      punycode: 2.3.1

  ts-algebra@2.0.0: {}

  ts-interface-checker@0.1.13: {}

  ts-morph@28.0.0:
    dependencies:
      '@ts-morph/common': 0.29.0
      code-block-writer: 13.0.3

  tslib@2.8.1:
    optional: true

  tsx@4.21.0:
    dependencies:
      esbuild: 0.27.7
      get-tsconfig: 4.14.0
    optionalDependencies:
      fsevents: 2.3.3

  tty-browserify@0.0.1: {}

  type-detect@4.1.0: {}

  type-is@1.6.18:
    dependencies:
      media-typer: 0.3.0
      mime-types: 2.1.35

  typed-array-buffer@1.0.3:
    dependencies:
      call-bound: 1.0.4
      es-errors: 1.3.0
      is-typed-array: 1.1.15

  typescript@5.8.3: {}

  ufo@1.6.3: {}

  undici-types@5.26.5: {}

  undici-types@6.21.0: {}

  universalify@0.1.2: {}

  unpipe@1.0.0: {}

  update-browserslist-db@1.2.3(browserslist@4.28.2):
    dependencies:
      browserslist: 4.28.2
      escalade: 3.2.0
      picocolors: 1.1.1

  url@0.11.4:
    dependencies:
      punycode: 1.4.1
      qs: 6.15.1

  util-deprecate@1.0.2: {}

  util@0.12.5:
    dependencies:
      inherits: 2.0.4
      is-arguments: 1.2.0
      is-generator-function: 1.1.2
      is-typed-array: 1.1.15
      which-typed-array: 1.1.20

  utils-merge@1.0.1: {}

  vary@1.1.2: {}

  vite-node@1.6.1(@types/node@20.19.39):
    dependencies:
      cac: 6.7.14
      debug: 4.4.3
      pathe: 1.1.2
      picocolors: 1.1.1
      vite: 5.4.21(@types/node@20.19.39)
    transitivePeerDependencies:
      - '@types/node'
      - less
      - lightningcss
      - sass
      - sass-embedded
      - stylus
      - sugarss
      - supports-color
      - terser

  vite-node@3.2.4(@types/node@20.19.39)(jiti@1.21.7)(tsx@4.21.0)(yaml@2.9.0):
    dependencies:
      cac: 6.7.14
      debug: 4.4.3
      es-module-lexer: 1.7.0
      pathe: 2.0.3
      vite: 6.4.2(@types/node@20.19.39)(jiti@1.21.7)(tsx@4.21.0)(yaml@2.9.0)
    transitivePeerDependencies:
      - '@types/node'
      - jiti
      - less
      - lightningcss
      - sass
      - sass-embedded
      - stylus
      - sugarss
      - supports-color
      - terser
      - tsx
      - yaml

  vite-plugin-node-polyfills@0.25.0(rollup@4.60.1)(vite@6.4.2(@types/node@20.19.39)(jiti@1.21.7)(tsx@4.21.0)(yaml@2.9.0)):
    dependencies:
      '@rollup/plugin-inject': 5.0.5(rollup@4.60.1)
      node-stdlib-browser: 1.3.1
      vite: 6.4.2(@types/node@20.19.39)(jiti@1.21.7)(tsx@4.21.0)(yaml@2.9.0)
    transitivePeerDependencies:
      - rollup

  vite@5.4.21(@types/node@20.19.39):
    dependencies:
      esbuild: 0.21.5
      postcss: 8.5.9
      rollup: 4.60.1
    optionalDependencies:
      '@types/node': 20.19.39
      fsevents: 2.3.3

  vite@6.4.2(@types/node@20.19.39)(jiti@1.21.7)(tsx@4.21.0)(yaml@2.9.0):
    dependencies:
      esbuild: 0.25.12
      fdir: 6.5.0(picomatch@4.0.4)
      picomatch: 4.0.4
      postcss: 8.5.9
      rollup: 4.60.1
      tinyglobby: 0.2.16
    optionalDependencies:
      '@types/node': 20.19.39
      fsevents: 2.3.3
      jiti: 1.21.7
      tsx: 4.21.0
      yaml: 2.9.0

  vitefu@1.1.3(vite@5.4.21(@types/node@20.19.39)):
    optionalDependencies:
      vite: 5.4.21(@types/node@20.19.39)

  vitefu@1.1.3(vite@6.4.2(@types/node@20.19.39)(jiti@1.21.7)(tsx@4.21.0)(yaml@2.9.0)):
    optionalDependencies:
      vite: 6.4.2(@types/node@20.19.39)(jiti@1.21.7)(tsx@4.21.0)(yaml@2.9.0)

  vitest@1.6.1(@types/node@20.19.39)(jsdom@25.0.1):
    dependencies:
      '@vitest/expect': 1.6.1
      '@vitest/runner': 1.6.1
      '@vitest/snapshot': 1.6.1
      '@vitest/spy': 1.6.1
      '@vitest/utils': 1.6.1
      acorn-walk: 8.3.5
      chai: 4.5.0
      debug: 4.4.3
      execa: 8.0.1
      local-pkg: 0.5.1
      magic-string: 0.30.21
      pathe: 1.1.2
      picocolors: 1.1.1
      std-env: 3.10.0
      strip-literal: 2.1.1
      tinybench: 2.9.0
      tinypool: 0.8.4
      vite: 5.4.21(@types/node@20.19.39)
      vite-node: 1.6.1(@types/node@20.19.39)
      why-is-node-running: 2.3.0
    optionalDependencies:
      '@types/node': 20.19.39
      jsdom: 25.0.1
    transitivePeerDependencies:
      - less
      - lightningcss
      - sass
      - sass-embedded
      - stylus
      - sugarss
      - supports-color
      - terser

  vitest@3.2.4(@types/node@20.19.39)(jiti@1.21.7)(jsdom@25.0.1)(tsx@4.21.0)(yaml@2.9.0):
    dependencies:
      '@types/chai': 5.2.3
      '@vitest/expect': 3.2.4
      '@vitest/mocker': 3.2.4(vite@6.4.2(@types/node@20.19.39)(jiti@1.21.7)(tsx@4.21.0)(yaml@2.9.0))
      '@vitest/pretty-format': 3.2.4
      '@vitest/runner': 3.2.4
      '@vitest/snapshot': 3.2.4
      '@vitest/spy': 3.2.4
      '@vitest/utils': 3.2.4
      chai: 5.3.3
      debug: 4.4.3
      expect-type: 1.3.0
      magic-string: 0.30.21
      pathe: 2.0.3
      picomatch: 4.0.4
      std-env: 3.10.0
      tinybench: 2.9.0
      tinyexec: 0.3.2
      tinyglobby: 0.2.16
      tinypool: 1.1.1
      tinyrainbow: 2.0.0
      vite: 6.4.2(@types/node@20.19.39)(jiti@1.21.7)(tsx@4.21.0)(yaml@2.9.0)
      vite-node: 3.2.4(@types/node@20.19.39)(jiti@1.21.7)(tsx@4.21.0)(yaml@2.9.0)
      why-is-node-running: 2.3.0
    optionalDependencies:
      '@types/node': 20.19.39
      jsdom: 25.0.1
    transitivePeerDependencies:
      - jiti
      - less
      - lightningcss
      - msw
      - sass
      - sass-embedded
      - stylus
      - sugarss
      - supports-color
      - terser
      - tsx
      - yaml

  vm-browserify@1.1.2: {}

  w3c-keyname@2.2.8: {}

  w3c-xmlserializer@5.0.0:
    dependencies:
      xml-name-validator: 5.0.0

  web-streams-polyfill@4.0.0-beta.3: {}

  web-worker@1.5.0: {}

  webidl-conversions@3.0.1: {}

  webidl-conversions@7.0.0: {}

  whatwg-encoding@3.1.1:
    dependencies:
      iconv-lite: 0.6.3

  whatwg-mimetype@4.0.0: {}

  whatwg-url@14.2.0:
    dependencies:
      tr46: 5.1.1
      webidl-conversions: 7.0.0

  whatwg-url@5.0.0:
    dependencies:
      tr46: 0.0.3
      webidl-conversions: 3.0.1

  which-typed-array@1.1.20:
    dependencies:
      available-typed-arrays: 1.0.7
      call-bind: 1.0.9
      call-bound: 1.0.4
      for-each: 0.3.5
      get-proto: 1.0.1
      gopd: 1.2.0
      has-tostringtag: 1.0.2

  which@2.0.2:
    dependencies:
      isexe: 2.0.0

  why-is-node-running@2.3.0:
    dependencies:
      siginfo: 2.0.0
      stackback: 0.0.2

  ws@8.20.0: {}

  xml-name-validator@5.0.0: {}

  xml-utils@1.10.2: {}

  xmlchars@2.2.0: {}

  xtend@4.0.2: {}

  yallist@3.1.1: {}

  yaml@2.9.0: {}

  yocto-queue@0.1.0: {}

  yocto-queue@1.2.2: {}

  zimmerframe@1.1.4: {}

  zstddec@0.2.0: {}

```
