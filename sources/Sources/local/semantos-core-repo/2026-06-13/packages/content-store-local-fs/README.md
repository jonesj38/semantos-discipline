---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/content-store-local-fs/README.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.391113+00:00
---

# @semantos/content-store-local-fs

Filesystem implementation of the `ContentStore` interface from
`@semantos/protocol-types`. Each blob lives at
`{root}/<hex(hash)[0:2]>/<hex(hash)>` — the same content-addressed
layout the USB-CDN adapter uses, so a directory that one adapter
writes is readable by the other.

## When to choose this adapter

- Single-machine development and tests where you want real on-disk
  persistence without network or USB hardware.
- The on-disk side of a node that uploads to UHRP elsewhere — keep
  the canonical bytes locally, mirror to UHRP for advertisement.
- Anywhere `find` and `get` should be cheap and `put` should be
  free of network IO.

Skip when you need cross-host fetchability (use UHRP HTTP) or
shareable read-only media (use USB-CDN).

## Quickstart

```ts
import { LocalFsContentStore } from "@semantos/content-store-local-fs";

const store = new LocalFsContentStore({ root: "/var/lib/semantos/blobs" });

const ref = await store.put(new TextEncoder().encode("hello"));
const got = await store.get(ref.hash); // throws ContentHashMismatchError on corruption
```

`advertise` is intentionally unimplemented — local-fs has no
on-chain or network half. Pair this adapter with one that does
(e.g. uhrp-http) when you need advertisement.
