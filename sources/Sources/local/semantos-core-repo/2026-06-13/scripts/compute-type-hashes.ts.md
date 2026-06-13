---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/scripts/compute-type-hashes.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.317094+00:00
---

# scripts/compute-type-hashes.ts

```ts
/**
 * Build-time script: compute and stamp typeHash values for all extension configs.
 *
 * Run: bun run scripts/compute-type-hashes.ts
 *
 * Hash rules:
 * - Types with a `category` field: SHA256(category) → 64-char hex string
 * - Types without `category`: SHA256(typeName) → 64-char hex string
 *
 * This ensures every ObjectTypeDefinition has a deterministic, non-zero typeHash
 * that can be decoded into a Uint8Array at runtime.
 */

import { createHash } from "crypto";
import { readFileSync, writeFileSync } from "fs";
import { join } from "path";

const CONFIGS_DIR = join(import.meta.dir, "../configs/extensions");

const CONFIG_FILES = [
  "core.json",
  "trades-services.json",
  "blockchain-risk.json",
  "development.json",
];

function sha256Hex(input: string): string {
  return createHash("sha256").update(input, "utf-8").digest("hex");
}

let totalStamped = 0;

for (const file of CONFIG_FILES) {
  const path = join(CONFIGS_DIR, file);
  const config = JSON.parse(readFileSync(path, "utf-8"));

  for (const ot of config.objectTypes) {
    const hashInput = ot.category || ot.name;
    ot.typeHash = sha256Hex(hashInput);
    totalStamped++;
  }

  writeFileSync(path, JSON.stringify(config, null, 2) + "\n");
  console.log(`Stamped ${config.objectTypes.length} typeHash values in ${file}`);
}

console.log(`Done. ${totalStamped} total typeHash values stamped.`);

```
