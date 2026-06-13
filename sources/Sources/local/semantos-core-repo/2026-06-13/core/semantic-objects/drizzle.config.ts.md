---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/semantic-objects/drizzle.config.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.799298+00:00
---

# core/semantic-objects/drizzle.config.ts

```ts
import type { Config } from 'drizzle-kit';

export default {
  dialect: 'postgresql',
  schema: './src/schema.ts',
  out: './migrations',
  dbCredentials: {
    url: process.env.SEMANTIC_OBJECTS_DATABASE_URL ?? 'postgresql://localhost/semantic_objects_dev',
  },
  verbose: true,
  strict: true,
} satisfies Config;

```
