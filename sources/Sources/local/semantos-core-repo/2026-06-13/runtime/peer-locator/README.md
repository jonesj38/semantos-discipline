---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/peer-locator/README.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.026778+00:00
---

# @semantos/peer-locator

BCA → WSS endpoint resolution for Phase 35B federation. Two implementations
ship today; a third (operator-run federated registry) lands in 35B.3.

```
┌──────────────────────────────────────────────────────────┐
│  Dialer (WsNodeAdapter, bootstrap scripts, …)            │
│                      │                                   │
│                      │  resolve(bca) → NodeEndpoint      │
│                      ▼                                   │
│  ┌────────────────────────────────────────────────────┐  │
│  │  PeerLocator  (common interface)                   │  │
│  ├────────────────────────────────────────────────────┤  │
│  │  StaticPeerLocator       map-backed                │  │
│  │  DnsPeerLocator          _semantos-node.<host> TXT │  │
│  │  FederatedPeerLocator    35B.3 — operator registry │  │
│  └────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────┘
```

## The contract

```ts
export interface NodeEndpoint {
  bca: string;                // IPv6 BCA of the node
  wssUrl: string;             // wss://host:port/session
  pubkey?: Uint8Array;        // optional — 33-byte compressed secp256k1
  licenseCertId?: string;     // optional — "sha256:<hex>"
}

export interface PeerLocator {
  resolve(bca: string): Promise<NodeEndpoint | null>;
  register(endpoint: NodeEndpoint): Promise<void>;
}
```

`pubkey` + `licenseCertId` let a dialer *pin* the identity without trusting
the returned endpoint alone — a locator that lies about the wss URL still
can't substitute a peer whose license cert differs from what was advertised.

## StaticPeerLocator

Map-backed, synchronous, deterministic. Use for tests, for a node's
bootstrap list, and for small private federations where DNS isn't worth
setting up.

```ts
import { StaticPeerLocator } from "@semantos/peer-locator";

const locator = new StaticPeerLocator({
  endpoints: [
    { bca: "2602:f9f8::b0b", wssUrl: "wss://bob.example.com:443/session" },
  ],
});
```

`register()` extends the map at runtime. `all()` dumps the current view
(handy in tests).

## DnsPeerLocator

DNS TXT-backed. For each configured hostname, the locator queries
`_semantos-node.<hostname>` and parses records of the form:

```
bca=<ipv6>;wss=<url>;licenseCertId=<id>;pubkey=<hex>
```

`bca` and `wss` are required; `licenseCertId` and `pubkey` are optional
pinning fields.

```ts
import { DnsPeerLocator, NodeDnsTxtResolver } from "@semantos/peer-locator";

const locator = new DnsPeerLocator({
  txtResolver: new NodeDnsTxtResolver(),
  hostnames: ["bob.example.com", "alice.example.com"],
  cacheTtlMs: 60_000,
});

const ep = await locator.resolve("2602:f9f8::b0b");
// → { bca: "2602:f9f8::b0b", wssUrl: "wss://bob.example.com:443/session", ... }
```

**Behaviour:**

- Iterates configured hostnames in order; returns the first whose TXT
  record matches the queried BCA.
- Caches hits for `cacheTtlMs` (default 60s). Nulls are *not* cached —
  transient DNS failures shouldn't stick.
- Swallows resolver errors on individual hostnames and continues to the
  next, so one broken NS doesn't break the whole lookup.
- `register()` is a no-op. DNS is the source of truth; there's no local
  cache to populate.

`resolveByHostname(hostname)` is a non-interface convenience for trusted-
hostname lookups that skip the BCA-match guard — useful when you trust
the hostname and just want to learn its BCA.

### Testing seam

`TxtResolver` is ctor-injected so tests never hit the network:

```ts
const fake: TxtResolver = {
  async resolveTxt(hostname) {
    return hostname === "_semantos-node.bob.example.com"
      ? ["bca=2602:f9f8::b0b;wss=wss://bob:443/session"]
      : [];
  },
};

const locator = new DnsPeerLocator({ txtResolver: fake, hostnames: ["bob.example.com"] });
```

## Record format

```
parseNodeEndpointTxt(hostname, "bca=2602:f9f8::b0b;wss=wss://bob:443/session")
  → { bca: "2602:f9f8::b0b", wssUrl: "wss://bob:443/session" }
```

- Whitespace around `=` and `;` is tolerated.
- Missing `bca` or `wss` → parser returns `null` (record ignored).
- Malformed `pubkey` hex → parser returns `null`. All-or-nothing on
  required fields.

## Tests

```
bun test runtime/peer-locator/__tests__/
```

17 tests covering `StaticPeerLocator` behaviour, `parseNodeEndpointTxt`
edge cases, `DnsPeerLocator` resolution + multi-hostname iteration +
resolver-error-swallowing, cache TTL, and the register no-op invariant.

G35B.7 ("DNS-only reachability") is the gate test for this package and
lives in [tests/gates/phase35b-gate.test.ts](../../tests/gates/phase35b-gate.test.ts).
