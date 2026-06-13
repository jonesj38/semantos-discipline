---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-world-client/vite.config.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.690588+00:00
---

# archive/apps-world-client/vite.config.ts

```ts
import { defineConfig } from "vite";
import { resolve } from "node:path";
import { copyFileSync, existsSync, mkdirSync } from "node:fs";

const ROOT = resolve(__dirname);
const REPO_ROOT = resolve(__dirname, "..", "..");
const WASM_SRC = resolve(REPO_ROOT, "core/cell-engine/zig-out/bin/cell-engine.wasm");
const WASM_DEST_DIR = resolve(ROOT, "public");
const WASM_DEST = resolve(WASM_DEST_DIR, "cell-engine.wasm");

function ensureWasmCopied() {
  if (!existsSync(WASM_SRC)) {
    console.warn(
      `[world-client] cell-engine.wasm not found at ${WASM_SRC}. Build it first: cd core/cell-engine && zig build`,
    );
    return;
  }
  if (!existsSync(WASM_DEST_DIR)) mkdirSync(WASM_DEST_DIR, { recursive: true });
  copyFileSync(WASM_SRC, WASM_DEST);
}
ensureWasmCopied();

export default defineConfig({
  root: ROOT,
  publicDir: "public",
  server: {
    port: 5175,
    proxy: {
      "/socket": { target: "ws://localhost:4000", ws: true, changeOrigin: true },
      "/api": { target: "http://localhost:4000", changeOrigin: true },
    },
  },
  build: {
    target: "es2022",
    outDir: "dist",
    emptyOutDir: true,
  },
});

```
