---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/loom-svelte/vite.config.mjs
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.048174+00:00
---

# apps/loom-svelte/vite.config.mjs

```mjs
// D-O5 — Helm SPA build config.
//
// Earlier (pre-D-O5) this app was a "framework boundary demo" that
// imported `@semantos/runtime-services` and a chain of workspace
// packages, each requiring an alias here so vite's resolver could
// satisfy node-only imports in a browser bundle.  D-O5 retargets the
// app: helm is a pure HTTP/WSS client to the brain substrate, so the
// runtime-services aliases (and the crypto/fs-promises stubs they
// dragged in) are gone.  Removing the `crypto` alias also fixes a
// vite crash where the alias collided with vite's own internal
// `node:crypto` use during config resolution
// (`crypto$2.getRandomValues is not a function`).
//
// D-svelte-find-network — alias for @semantos/conversation-graph/rendering.
// We alias ONLY the rendering sub-path (not the full package index) to avoid
// pulling in the package's node-only exports (pipeline, retrieve-context)
// which transitively import drizzle-orm.  rendering.ts is a pure computation
// module: its only external dep is `import type` from @semantos/scg-relations,
// which TypeScript strips before Vite sees the module.

import { defineConfig } from "vite";
import { svelte } from "@sveltejs/vite-plugin-svelte";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const ROOT = resolve(__dirname);

// D-helm-talk-call — alias the PURE rtc modules from @semantos/session-protocol
// so the helm can place real WebRTC calls without adding the whole package
// (which pulls werift / @bsv/sdk node deps). These modules are pure TS/DOM/fetch;
// their node-only imports (xmpp-node, protocol-types/signed-bundle) are
// `import type` and stripped by esbuild before Vite bundles them. Mirrors the
// conversation-graph/rendering sub-path-only approach.
const RTC = resolve(ROOT, "../../runtime/session-protocol/src/rtc");
const rtcAlias = (name) => ({
  find: `@rtc/${name}`,
  replacement: resolve(RTC, `${name}.ts`),
});

export default defineConfig({
  root: ROOT,
  base: "/helm/",
  plugins: [svelte()],
  resolve: {
    alias: [
      rtcAlias("call"),
      rtcAlias("media"),
      rtcAlias("ice"),
      rtcAlias("signal"),
      rtcAlias("jingle"),
      rtcAlias("fingerprint"),
      rtcAlias("browser-peer-connection"),
      rtcAlias("brain-rtc-signal-channel"),
      rtcAlias("brain-operator-signer"),
      // Recipient-side verify pulls @bsv/sdk (browser-safe, the PWA SDK) for
      // the ECDSA check.
      rtcAlias("bsv-signed-bundle-verifier"),
      // The signed-bundle codec is a runtime import of both the signer and the
      // verifier; alias the SUB-PATH to source (pure string/codec, no node
      // deps) so rollup resolves it without the package's exports map.
      {
        find: "@semantos/protocol-types/signed-bundle",
        replacement: resolve(ROOT, "../../core/protocol-types/src/signed-bundle/index.ts"),
      },
    ],
  },
  build: {
    target: "es2022",
    outDir: "dist",
    emptyOutDir: true,
  },
  server: {
    port: 5175,
  },
});

```
