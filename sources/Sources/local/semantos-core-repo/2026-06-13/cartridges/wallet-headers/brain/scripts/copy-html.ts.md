---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/wallet-headers/brain/scripts/copy-html.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.643198+00:00
---

# cartridges/wallet-headers/brain/scripts/copy-html.ts

```ts
// HTML files live alongside the bundled JS under `dist/`. They are
// hand-authored (kept in `dist/` directly) — this script is a no-op for
// now but exists so `bun run build:html` always succeeds and so future
// templating (per-tld substitution, etc.) has a hook.

async function main(): Promise<void> {
  const targets = ['dist/index.html', 'dist/popup.html', 'dist/signup.html', 'dist/wallet.html'];
  for (const t of targets) {
    const f = Bun.file(t);
    if (!(await f.exists())) {
      throw new Error(`copy-html: missing ${t} — re-run from cartridges/wallet-headers/brain/`);
    }
  }
  console.log(`copy-html: verified ${targets.length} files in dist/`);
}

await main();
export {};

```
