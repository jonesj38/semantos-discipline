---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-demo-wasm-threejs/vite.config.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.687421+00:00
---

# archive/apps-demo-wasm-threejs/vite.config.ts

```ts
import { defineConfig } from "vite";
import { resolve } from "node:path";
import { copyFileSync, existsSync, mkdirSync } from "node:fs";

const ROOT = resolve(__dirname);
const REPO_ROOT = resolve(__dirname, "..", "..");
const WASM_SRC = resolve(REPO_ROOT, "core/cell-engine/zig-out/bin/cell-engine.wasm");
const WASM_DEST_DIR = resolve(ROOT, "public");
const WASM_DEST = resolve(WASM_DEST_DIR, "cell-engine.wasm");

// Copy the WASM artifact into public/ so vite serves it from /cell-engine.wasm.
// Run before dev/build; no-op if the file is missing (will surface as a clear runtime error).
function ensureWasmCopied() {
  if (!existsSync(WASM_SRC)) {
    console.warn(
      `[demo-wasm-threejs] cell-engine.wasm not found at ${WASM_SRC}. ` +
      `Build it first: cd core/cell-engine && zig build`,
    );
    return;
  }
  if (!existsSync(WASM_DEST_DIR)) mkdirSync(WASM_DEST_DIR, { recursive: true });
  copyFileSync(WASM_SRC, WASM_DEST);
}
ensureWasmCopied();

// Workspace package aliases — resolve TypeScript source directly so vite/rollup
// can bundle workspace packages without a prior build step. Packages use the
// "bun" condition in their exports map (for bun test), which Vite/Rollup
// does not pick up automatically.
const workspaceAlias: Record<string, string> = {
  "@semantos/identity-ports/stub": resolve(REPO_ROOT, "core/identity-ports/src/stub-binding.ts"),
  "@semantos/identity-ports": resolve(REPO_ROOT, "core/identity-ports/src/index.ts"),
  "@semantos/cube-object/linearity": resolve(REPO_ROOT, "core/cube-object/src/linearity.ts"),
  "@semantos/cube-object/mesh": resolve(REPO_ROOT, "core/cube-object/src/cube-mesh.ts"),
  "@semantos/cube-object": resolve(REPO_ROOT, "core/cube-object/src/index.ts"),
  "@semantos/state": resolve(REPO_ROOT, "core/state/src/index.ts"),
  "@plexus/contracts": resolve(REPO_ROOT, "core/plexus-contracts/src/index.ts"),
  "@plexus/vendor-sdk": resolve(REPO_ROOT, "core/plexus-vendor-sdk/src/index.ts"),
};

export default defineConfig({
  root: ROOT,
  publicDir: "public",
  resolve: {
    alias: workspaceAlias,
  },
  server: {
    port: 5174,
  },
  build: {
    target: "es2022",
    outDir: "dist",
    emptyOutDir: true,
  },
});

```
