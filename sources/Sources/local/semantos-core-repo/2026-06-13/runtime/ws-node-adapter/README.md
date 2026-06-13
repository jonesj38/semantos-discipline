---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/ws-node-adapter/README.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.032311+00:00
---

# @semantos/ws-node-adapter

NetworkAdapter over WSS with license-handshake envelope auth. The node-to-
node federation transport for Phase 35B.

```
┌──────────────────────────────────────────────────────────┐
│  NetworkAdapter consumer (SessionRuntime, publish/subscribe) │
└────────────────────┬─────────────────────────────────────┘
                     │
┌────────────────────▼─────────────────────────────────────┐
│  WsNodeAdapter                                           │
│  ┌──────────────┬──────────────┬──────────────────────┐  │
│  │  Bun.serve   │  connect(bca)│  publish / subscribe │  │
│  │  /session    │  via locator │  (topic fan-out)     │  │
│  └──────┬───────┴───────┬──────┴──────────────────────┘  │
│         │               │                                │
│         ▼               ▼                                │
│  ┌───────────────────────────────────────────────────┐   │
│  │  WsPeerConnection   (per-peer state machine)      │   │
│  │  authenticating → authenticated → closing → closed│   │
│  └──────────────────┬────────────────────────────────┘   │
│                     │                                    │
│  ┌──────────────────▼────────────────────────────────┐   │
│  │  license-handshake  ←  codec  ←  types            │   │
│  │  (verify frame)   (CBOR)    (FRAME_KIND enum)     │   │
│  └───────────────────────────────────────────────────┘   │
└──────────────────────────────────────────────────────────┘
```

## Wire format

Every frame is a CBOR map with a leading `kind` discriminator. Four kinds
in Phase 35B.1:

| Kind | Direction | Role |
|---|---|---|
| `license_handshake`  | bidirectional, first frame | Identity + authorisation proof |
| `session_envelope`   | post-handshake            | Carries PublishableObject payload |
| `heartbeat`          | post-handshake            | Idle filler (30s) to keep NATs happy |
| `bye`                | post-handshake, optional  | Graceful shutdown announcement |

**LicenseHandshake** proves three things:

1. The sender holds a valid License signed by an issuer the recipient
   accepts (via `verifyLicense` + `isAcceptableIssuer` policy).
2. The sender actually controls the holder private key — sig is over
   `challenge || sha256(licenseBytes)` by `license.pubkey`.
3. The sender's `claimedBca` matches the derivation from `license.pubkey`
   (`bca-mismatch` otherwise).

Replay protection comes from TLS at transport. The 32-byte challenge
prevents signature caching — each connection signs a fresh payload.

## Five-minute worked example

```ts
import {
  WsNodeAdapter,
  buildHandshakeFrame,
  verifyHandshakeFrame,
} from "@semantos/ws-node-adapter";
import { BsvSdkVerifier } from "@semantos/session-protocol";
import { StaticPeerLocator } from "@semantos/peer-locator";
import { encodeLicense } from "@semantos/protocol-types/license";

const adapter = new WsNodeAdapter({
  identity: myBcaProvider,            // Signer + BCA deriver
  license: myLicense,                 // decoded License cell
  locator: new StaticPeerLocator({ endpoints: [...bootstrapPeers] }),
  verifier: new BsvSdkVerifier(),
  deriveBcaFromPubkey: async (pk) => derivedBca(pk),
  serverPort: 443,
  serverHost: "0.0.0.0",
  tls: { cert, key },                 // wss; omit for ws (tests / LAN)
});

await adapter.start();

// Dial a known peer
const conn = await adapter.connect("2602:f9f8::b0b");
// Publish to topic — broadcast to all authenticated peers + local subscribers
await adapter.publish(obj, { topic: "tm_semantos_objects" });
// Subscribe to incoming
adapter.subscribe("tm_semantos_objects", (ev) => handle(ev));

await adapter.stop();
```

## `/.well-known/semantos-node`

Auto-served on the same port as `/session`. Returns JSON with the auto-
filled fields (bca, pubkeyHex, licenseCertId) plus whatever
`wellKnownExtras` contributes:

```ts
new WsNodeAdapter({
  ...,
  wellKnownExtras: () => ({
    version: "0.1.0",
    adapters: { storage: "node-fs", network: "ws-node" },
    advertised: { wssUrl: "wss://alice.example.com:443/session" },
  }),
});
```

```
$ curl https://alice.example.com:443/.well-known/semantos-node
{
  "bca":            "2602:f9f8::a11ce",
  "pubkeyHex":      "02aa...",
  "licenseCertId":  "sha256:00dc485924...",
  "version":        "0.1.0",
  "adapters":       { ... },
  "advertised":     { "wssUrl": "wss://alice.example.com:443/session" }
}
```

Used by peer discovery: a dialer resolves via PeerLocator, then `curl`s
the advertised URL to pin the specific license cert before dialing.

## State machine (WsPeerConnection)

```
                 start()          valid handshake from peer
authenticating ────────▶ send     ───────────────────▶ authenticated
      │ ▲                                                   │
      │ └─ receive our ────────┐                           │
      │                        │                           │
      │ invalid handshake      │ (idle timeout, goodbye,   │
      ▼                        │  or local close())        ▼
      failHandshake (4001-4004)└────────────────────▶ closing
                                                         │
                                                         ▼
                                                       closed
```

Transport-agnostic — takes `sendBytes` / `closeSocket` callbacks so
`Bun.serve`'s `ServerWebSocket` (listener) and the standard `WebSocket`
constructor (dialer) both drop in. See [ws-peer-connection.ts](src/ws-peer-connection.ts).

## NetworkAdapter placeholders

Phase 35B.1 implements the critical flow (publish / subscribe / connect).
These are opt-in placeholders for 35B.2:

- `resolve(query)` returns `[]` — no remote index yet. 35B.2 maintains one.
- `resolveBCA(bca)` returns a minimal `NodeInfo` for authenticated peers,
  `null` otherwise. 35B.2 enriches with extension list + metadata.
- `sendToNode(bca, bytes)` returns delivery-by-presence. 35B.2 adds a
  typed direct-message frame kind.
- Envelope `sig` is an empty `Uint8Array`. Transport auth already comes
  from the handshake; wire-sig enforcement ships in 35B.2.

## Tests

```
bun test runtime/ws-node-adapter/__tests__/
```

- `codec.test.ts` (17) — frame roundtrip, decode error paths,
  `canonicalEnvelopeBytesForSigning` determinism, `handshakeSigPayload`
  shape.
- `license-handshake.test.ts` (9) — real ECDSA via `BsvSdkSigner`:
  G35B.8 (BCA binding), G35B.8b (expiry), G35B.8c (issuer policy), plus
  sig-tamper + replay + malformed variants.
- `ws-node-adapter.test.ts` (11) — G35B.1 federation integration: two
  adapters on local ws, handshake, publish/subscribe, `/.well-known`
  shape, peers() lifecycle, connect-unknown rejection.

The consolidated gate lives in [tests/gates/phase35b-gate.test.ts](../../tests/gates/phase35b-gate.test.ts).
