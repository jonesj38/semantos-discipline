---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/content-store-usb-cdn/README.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.395925+00:00
---

# @semantos/content-store-usb-cdn

USB-mounted content-addressed CDN implementation of the `ContentStore`
interface from `@semantos/protocol-types`. Uses the same on-disk
layout as `content-store-local-fs` (`{root}/<hex(hash)[0:2]>/<hex(hash)>`)
plus an optional `manifest.json` at the root that lists cached
hashes, signed by a BRC-52 certificate.

## When to choose this adapter

- Sneakernet / air-gap scenarios where blobs ship on physical media
  rather than over the network.
- Read-mostly content packs prepared by a trusted publisher and
  consumed by many nodes — the manifest gives `find()` an O(1)
  index without requiring a directory scan.
- Replacing local-fs when the same disk needs to be cryptographically
  attestable as the publisher's.

Skip when you want network fetchability (uhrp-http) or when no
publisher / signer exists (local-fs is simpler).

## Quickstart

```ts
import { UsbCdnContentStore } from "@semantos/content-store-usb-cdn";

const store = new UsbCdnContentStore({
  root: "/Volumes/SemantosCDN",
  trustedSignerPubKeysHex: [
    "0312deadbeef…",
  ],
});

const ref = await store.find(hash);
if (ref) {
  const bytes = await store.get(ref.hash); // hash-verified on read
}
```

Manifest semantics:

| Manifest state                | `find()` behaviour                       |
| ----------------------------- | ---------------------------------------- |
| present, signature valid, signer trusted | consults manifest first then disk |
| present, signature invalid    | manifest silently ignored, disk fallback |
| signer not in trusted list    | manifest silently ignored, disk fallback |
| absent                        | behaves identically to local-fs          |

Verification failure never breaks disk fallback — even a sabotaged
manifest can't render the USB drive unreadable.
