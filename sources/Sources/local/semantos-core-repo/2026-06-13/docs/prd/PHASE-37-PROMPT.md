---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-37-PROMPT.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.683538+00:00
---

# Phase 37 Execution Prompt — Kernel Bridge Adapter Wiring

> Paste this prompt into a fresh session to execute Phase 37.

## Context

You are working in the `semantos-core` repo. The Navigator PWA (`packages/navigation_app/bsv-app/`) currently runs a fake kernel — two extension configs statically imported at build time, objects stored in an ephemeral in-memory Map, no identity, no BSV anchoring, no network discovery. Meanwhile, the real adapter stack (Storage, Identity, Anchor, Network) exists in `packages/protocol-types/src/` and is tested.

Phase 37 wires the kernel bridge to the real adapters so that:
- Objects persist across page reloads (OpfsAdapter / IndexedDbAdapter)
- User identity is managed offline (LocalIdentityAdapter with cert chains)
- Extensions are discovered at runtime via ConsumerBindings, not hardcoded
- BSV anchoring activates when a wallet connects (BsvAnchorAdapter)
- Network overlay activates when online (BsvOverlayNetworkAdapter)

**Why this matters**: Without real adapters, the Navigator is a demo. With them, it becomes a sovereign node running in the browser — objects are real, identity is cryptographic, anchoring is on-chain, and extension discovery is dynamic.

Your task is Phase 37: wire the kernel bridge to the four adapter interfaces.

---

## CRITICAL: READ THESE FILES FIRST

Before writing a single line of code, read every file listed below.

**Read first** (the PRD):
- `docs/prd/PHASE-37-KERNEL-BRIDGE-ADAPTER-WIRING.md` — Complete spec with deliverables D37.1–D37.10, architecture, boot sequence, migration path

**Read second** (the current kernel bridge and app):
- `packages/navigation_app/bsv-app/kernel-bridge.ts` — Current shim to rewrite
- `packages/navigation_app/bsv-app/navigator.js` — Vanilla JS app, needs async boot
- `packages/navigation_app/bsv-app/index.html` — Status bar, script loading

**Read third** (the four adapter interfaces):
- `packages/protocol-types/src/storage.ts` — StorageAdapter interface
- `packages/protocol-types/src/identity.ts` — IdentityAdapter interface
- `packages/protocol-types/src/anchor.ts` — AnchorAdapter interface + createAnchorAdapter()
- `packages/protocol-types/src/network.ts` — NetworkAdapter interface

**Read fourth** (adapter factories and implementations):
- `packages/protocol-types/src/adapters/create-adapter.ts` — Storage factory (auto-detects OPFS/IndexedDB)
- `packages/protocol-types/src/adapters/create-identity-adapter.ts` — Identity factory
- `packages/protocol-types/src/adapters/opfs-adapter.ts` — Browser OPFS storage
- `packages/protocol-types/src/adapters/indexed-db-adapter.ts` — Browser IndexedDB fallback
- `packages/protocol-types/src/adapters/stub-anchor-adapter.ts` — Default anchor (no wallet)
- `packages/protocol-types/src/adapters/bsv-anchor-adapter.ts` — BSV anchor (with wallet)
- `packages/protocol-types/src/adapters/stub-network-adapter.ts` — Default network (offline)
- `packages/protocol-types/src/adapters/bsv-overlay-network-adapter.ts` — BSV overlay network

**Read fifth** (extension discovery):
- `packages/protocol-types/src/extension-loader.ts` — ExtensionLoader (reads configs from StorageAdapter)
- `packages/protocol-types/src/extension-registry.ts` — ExtensionRegistry (activate/deactivate)
- `packages/protocol-types/src/identity-adapters/LocalIdentityAdapter.ts` — Offline identity

**Read sixth** (governance — keep constraint checks working):
- `packages/extraction/src/governance/constraint-engine.ts` — enforceL0Constraints, enforceL1Constraints
- `packages/extraction/src/governance/version-compat.ts` — checkCompatibility

**Read seventh** (existing configs that get seeded on first boot):
- `configs/extensions/navigator.json` — Navigator core config (1 type: ConsumerBinding)
- `configs/extensions/consciousness.json` — Consciousness extension (14 types, 12 flows)

---

## Execution Order

Follow the phased migration path from the PRD:

### Phase 37A — Storage + Persistence (Week 1)
1. Wire `createAdapter()` into kernel-bridge.ts
2. Replace in-memory `ObjectStore` with `PersistentObjectStore` backed by StorageAdapter
3. Implement first-boot seeding (write bundled configs into storage)
4. Update navigator.js for async boot (`await window.SemantosKernel`)
5. Tests T1–T8

### Phase 37B — Identity + Extension Discovery (Week 2)
1. Wire `createIdentityAdapter('local')` with StorageAdapter
2. Implement extension discovery via ConsumerBindings
3. Remove static config imports from kernel-bridge.ts
4. Replace hardcoded extensions array with ExtensionRegistry
5. Tests T5, T13, T14

### Phase 37C — Anchor + Network (Week 3)
1. Wire StubAnchorAdapter with runtime upgrade to BsvAnchorAdapter
2. Wire StubNetworkAdapter with runtime upgrade to BsvOverlayNetworkAdapter
3. Implement CWI detection → adapter upgrade hooks
4. Update status bar to reflect real adapter states
5. Tests T9–T12

---

## Critical Constraints

1. **Browser target**: The bundle runs in the browser. No `fs`, `path`, `process` references in the output. Use dynamic imports and tree-shaking.
2. **Async boot**: `KernelBridge.boot()` is async. navigator.js must handle the loading → ready transition gracefully (show loading state, not a blank screen).
3. **Public API stability**: The API surface exposed on `window.SemantosKernel` (createObject, listObjects, listExtensions, etc.) must remain identical. Only the internal implementation changes.
4. **Governance stays**: L0 and L1 constraint enforcement on `createObject()` must still work. Don't bypass it.
5. **No vendor type leakage**: BSV SDK types stay inside adapter implementations. The kernel bridge never imports `@bsv/sdk` directly.
6. **Build command**: `bun build packages/navigation_app/bsv-app/kernel-bridge.ts --outfile packages/navigation_app/bsv-app/kernel-bridge.js --target=browser --minify`
7. **Branch**: `phase-37-kernel-bridge-adapter-wiring`, commits as `phase-37/D37.N:`
