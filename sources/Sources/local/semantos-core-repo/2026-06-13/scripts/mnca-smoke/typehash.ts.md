---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/scripts/mnca-smoke/typehash.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.383159+00:00
---

# scripts/mnca-smoke/typehash.ts

```ts
#!/usr/bin/env bun
// scripts/mnca-smoke/typehash.ts — compute the structured |8|8|8|8|
// typeHash for a 4-segment triple. Used by docs/runbooks/MNCA-ANCHOR-
// REAL-TXID.md to derive the typeHashHex strings the brain's mint
// endpoint expects.
//
// Usage:
//   bun run scripts/mnca-smoke/typehash.ts mnca anchor transition intent
//   bun run scripts/mnca-smoke/typehash.ts bsv  tx     sign       request
//
// Mirrors `core/protocol-types/zig/bsv/spv_verify.zig::buildTypeHash`
// and `core/cell-engine/src/type_hash.zig::buildTypeHash`:
//
//     out[0..8]   = sha256(s1)[0..8]
//     out[8..16]  = sha256(s2)[0..8]
//     out[16..24] = sha256(s3)[0..8]
//     out[24..32] = sha256(s4)[0..8]

import { createHash } from "crypto";

function sha256First8(s: string): string {
  return createHash("sha256").update(s).digest("hex").slice(0, 16);
}

const segments = process.argv.slice(2);
if (segments.length !== 4) {
  console.error(
    "usage: bun run scripts/mnca-smoke/typehash.ts <s1> <s2> <s3> <s4>",
  );
  console.error("  Empty segments may be passed as '' (e.g. mnca anchor '' '').");
  process.exit(2);
}

const hex = segments.map(sha256First8).join("");
console.log(hex);

```
