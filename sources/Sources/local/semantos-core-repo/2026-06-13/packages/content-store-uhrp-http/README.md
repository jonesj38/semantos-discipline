---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/content-store-uhrp-http/README.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.394875+00:00
---

# @semantos/content-store-uhrp-http

UHRP HTTP client implementation of the `ContentStore` interface from
`@semantos/protocol-types`. The base URL is configurable so the same
adapter works against `nanostore.babbage.systems`, a self-hosted
`bsv-storage-cloudflare` deploy, or a local dev server.

## When to choose this adapter

- The node needs to publish content that other nodes can fetch
  cross-network without prearrangement.
- You want pricing + retention semantics (`/quote`, `/renew`) so
  uploads are paid for and persisted with a known TTL.
- BRC-31 request signing is desirable but optional — pass a `signer`
  in the config to enable it.

Skip when fetches must work offline (use local-fs or usb-cdn) or
when you can't tolerate the latency / cost of a network round trip
on every `put` and `get`.

## Quickstart

```ts
import { UhrpHttpContentStore } from "@semantos/content-store-uhrp-http";

const store = new UhrpHttpContentStore({
  baseUrl: "https://nanostore.babbage.systems",
  // signer: myBrc31Signer,                  // optional
  // defaultRetentionMinutes: 60 * 24 * 7,   // optional
});

const ref = await store.put(bytes, { mimeType: "application/json" });
const got = await store.get(ref.hash); // server-supplied bytes are hash-verified
const adv = await store.advertise!(ref, 60 * 60 * 24); // extends retention
```

Wire ops the adapter exercises:

| Op            | Endpoint    | Purpose                                      |
| ------------- | ----------- | -------------------------------------------- |
| `put`         | POST `/quote` + POST `/upload` | quote then upload        |
| `get`         | GET `/blob/<hex>` | download (verified)                |
| `find`        | GET `/find?hashHex=…`        | metadata                  |
| `advertise`   | POST `/renew`                | extend retention          |
