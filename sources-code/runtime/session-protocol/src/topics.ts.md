---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/topics.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.037132+00:00
---

# runtime/session-protocol/src/topics.ts

```ts
/**
 * Topic → multicast-group mapping.
 *
 * The hackathon `DockerMulticastAdapter` joins one well-known group
 * (`ff02::1`) and demultiplexes topics in software. Phase 34 will replace
 * this with a type-hash-derived group per topic. The `TopicToGroup` hook
 * lets us swap strategies without touching the adapter call sites.
 */

import type { TopicToGroup } from "./types.js";

/** The default mapping: every topic joins the hackathon well-known group. */
export const defaultTopicToGroup: TopicToGroup = () => "ff02::1";

```
