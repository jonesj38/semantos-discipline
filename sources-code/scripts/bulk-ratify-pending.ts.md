---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/scripts/bulk-ratify-pending.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.322634+00:00
---

# scripts/bulk-ratify-pending.ts

```ts
#!/usr/bin/env bun
/**
 * Bulk-ratify all pending proposals.
 * Run: bun run scripts/bulk-ratify-pending.ts [--dry-run]
 */

import { bootstrap } from '../apps/legacy-cli/src/bootstrap.ts';
import { dispatch } from '../runtime/legacy-ingest/src/verb.ts';

const dryRun = process.argv.includes('--dry-run');

const { ctx, shutdown } = await bootstrap();

try {
  const result = await dispatch(
    ctx,
    { positional: dryRun ? ['bulk-ratify', '--dry-run'] : ['bulk-ratify'] },
    null,
  );
  console.log(JSON.stringify(result, null, 2));
} finally {
  await shutdown();
}

```
