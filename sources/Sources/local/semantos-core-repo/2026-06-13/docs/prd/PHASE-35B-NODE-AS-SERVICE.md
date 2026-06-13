---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-35B-NODE-AS-SERVICE.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.666195+00:00
---

# Phase 35B — Node as Service (Sovereign Media Host)

**Version**: 1.0
**Date**: April 2026
**Status**: Ready for implementation
**Duration**: 3–5 weeks
**Prerequisites**: Phase 35A (session-protocol package), Phase 26E (NodeConfig, SemantosNode lifecycle), Phase 26G (Node packaging & Dockerfile)
**Branch prefix**: `phase-35b-`
**Master document**: `PHASE-35-USER-NODE-SERVICE.md` (35A + 35B together)

---

## Context

Phase 35A ships the domain-neutral session-protocol skeleton. Phase 35B puts it to work as a user-facing product: a sovereign media-session host that a single user runs on a VPS (or at home with IPv6), reachable by their BCA, able to federate directly with other users' nodes for any media session — two-party voice/video calls, one-to-many live streams, group conferences, file transfers, pay-gated broadcasts — all with built-in micropayment channels.

The pitch is: **your own sovereign box instead of StreamYard, Twitch, Zoom, Discord, or SendSpace, with identity from your pubkey and payment channels as a first-class citizen.** No platform rake. No de-platforming. No AdSense algorithm. The node is yours, the identity is cryptographic, the viewers pay you directly.

This is achievable as a small MVP because the hardest usual bottleneck — NAT traversal and reachability — collapses when the deployment model is "node runs on a VPS with a public IPv6." You get direct node-to-node reachability, TLS for free via Let's Encrypt, and no relay infrastructure as a mandatory dependency. Home deployment still works for users with IPv6 ISPs. IPv4-only users get an optional relay adapter in Phase 35C.

### Reachability — what actually counts as a node endpoint

The "VPS" framing throughout this PRD is operator-typical, not architectural. The federation only requires **two endpoints with reachable WSS URLs** — i.e. the dialer can `new WebSocket(url)` and reach the listener. That's it. A VPS is one realisation. Equally valid:

- A **cloud VM** (DigitalOcean, Hetzner, Linode, Fly.io, Railway, EC2, BinaryLane $4/mo, etc.)
- A **home server** with port-forwarding + dynamic DNS (Cloudflare DDNS, NoIP)
- A **Tailscale** (or Nebula, or other overlay) endpoint with a stable address
- A **Cloudflare tunnel** sidecar terminating TLS — zero port forwarding, zero exposure
- A **Pi in a closet** behind any of the above
- Anything else that resolves to a `wss://...` your peer can dial

The architecture only cares about: (a) a wssUrl the dialer can reach, (b) TLS termination at the listener (or plain `ws://` for trusted-LAN / smoke-test deployments), (c) a way to find peers (DNS, static config, or 35B.3's federated registry — all on the same `PeerLocator` interface).

What 35B does **not** handle: two peers both behind unrelated NATs, neither reachable. That needs STUN/TURN/hole-punching, deferred to **Phase 35C**. Until then at least one side must be addressable — but with $4/mo VPSs available everywhere this is rarely a practical constraint.

For the operator-style smoke test that gets two nodes federating from `semantos start` alone, see [docs/35b/SMOKE-TEST.md](../35b/SMOKE-TEST.md).

### Why This Is a Separate Phase from 35A

Phase 35A establishes the session skeleton and refactors poker as its first consumer. Phase 35B is about *productising* that skeleton: a new `NetworkAdapter` implementation suited to WAN federation between VPS-hosted nodes, a set of media-session state machines, the minimum webserver surface to make a node reachable-by-name, and the peer-locator that maps BCA → endpoint. 35A is a refactor. 35B is a new product surface.

### Why "Media Session" Rather Than "Call"

An earlier draft framed this phase around a `call-protocol`. That framing is too narrow. Voice is one media type; once you have the underlying session plumbing, you also get:

- **Video calls** (1:1 or small group) — same substrate, different codecs
- **Live streams** (1:N, one publisher, many viewers) — same formation, different fan-out
- **Conferences** (N:N) — combine the above
- **File transfer** (1:1 or 1:N, bounded duration) — different state machine, same session
- **Pay-gated broadcasts** (1:∞, access gate via payment channel) — streaming + metering tightened

All of these are the same six-piece skeleton from 35A plus a different state machine and different content-type tag. Shipping them as one abstraction means the user gets a Twitch-replacement *and* a Zoom-replacement *and* a Discord-replacement from the same infrastructure, and the product differentiation becomes about UX skins, not about rebuilding plumbing.

### Prior Art in the Codebase

| Concept | Source | Status |
|---------|--------|--------|
| Session-protocol skeleton | `packages/session-protocol/` | Built — Phase 35A |
| Node daemon | `packages/node/` with `api/{server,routes,tls}.ts` | Built — admin API only |
| Metering FSM | `packages/metering/` | Built |
| Settlement batching | `packages/settlement/` | Built |
| Loom UI | `packages/loom/` | Built — three-panel React UI with voice input |
| PokerSessionFactory | `packages/poker-agent/` | Built — first session-protocol consumer |

### What Does Not Exist Yet

- Any `NetworkAdapter` implementation optimised for WAN federation (multicast adapter is LAN/Docker-bridge).
- Any peer-locator / BCA-to-endpoint resolution.
- Any media-session state machines (call, stream, conference, transfer).
- Any browser-facing signalling surface on the node.
- Any pay-gated access layer for streams.

---

## Architecture

### Deployment Topology

```
Public internet (IPv6-first)
  │
  ├─ todd.semantos.net  →  VPS #1 (IPv6: 2a01:....)
  │    semantos-node
  │    ├─ HTTPS (443)    — admin, loom UI, public profile
  │    ├─ WSS (/session) — session-protocol signalling
  │    ├─ WSS (/media)   — WebRTC signalling relay
  │    └─ metering channel to alice.semantos.net
  │
  ├─ alice.semantos.net  →  VPS #2 (IPv6: 2a02:....)
  │    semantos-node
  │    └─ …identical shape
  │
  └─ locator.semantos.net  →  peer-locator (operator-run OR self-hosted OR federated)
       BCA registry, signed heartbeat, reachable endpoint lookup

Users reach each other by:
  - DNS name (todd.semantos.net)             — zero infrastructure, owns own domain
  - BCA hex (2a01:...::0042)                  — raw cryptographic identity
  - Handle (@todd@semantos.net)              — fediverse-style, via locator
```

### Four Adapter Implementations After This Phase

After 35B, the `NetworkAdapter` interface has four shipping implementations:

| Adapter | Substrate | Use case | Ships in |
|---------|-----------|----------|----------|
| `MulticastAdapter` | IPv6 UDP multicast | LAN / Docker bridge / poker swarm | 35A (promoted from hackathon) |
| `WsNodeAdapter` | WSS over public internet | Node-to-node WAN federation | 35B |
| `WebRtcAdapter` | RTCPeerConnection + RTCDataChannel | Browser clients calling into a node | 35B |
| `LoopbackAdapter` | In-memory | Tests | 35A |

A node typically runs `MulticastAdapter` (LAN peers) + `WsNodeAdapter` (WAN peers) + `WebRtcAdapter` (browser clients) simultaneously. The session-protocol multiplexes over whichever is appropriate for each peer.

### The Media-Session Abstraction

A media-session is a session-protocol instance parameterised by:

```typescript
export interface MediaSessionDescriptor {
  kind: MediaKind;                      // voice | video | stream | conference | file | broadcast
  fanOut: FanOutPattern;                // 1:1 | 1:N | N:N | public
  formation: FormationPolicy;           // min/max party, invite-only, open-join, etc.
  stateMachine: StateMachine<MediaEvent, MediaState>;
  mediaPlane: MediaPlaneDescriptor;     // WebRTC | SRTP | file-stream | raw-bytes
  metering?: MediaMeteringPolicy;       // per-minute | per-view | subscription | free
  access?: AccessPolicy;                // open | invite | paywall | token-gated
}

export type MediaKind =
  | 'voice'       // audio-only, 1:1 or small N
  | 'video'       // audio+video call, 1:1 or small N
  | 'stream'      // live 1:N, viewer fan-out, optional paywall
  | 'conference'  // N:N multi-party
  | 'file'        // bounded-duration bulk transfer, 1:1 or 1:N
  | 'broadcast';  // public 1:∞, tips/micropayments for access or tips
```

Each `kind` comes with a default `stateMachine` and default `mediaPlane`, but both can be overridden. Voice and video share most of the call state machine; `stream` and `broadcast` share most of the publisher-fan-out state machine.

### Media Plane — WebRTC as Primary

For all real-time media (voice, video, stream, conference), the node uses WebRTC as the media plane. Rationale:

1. **Codecs, jitter buffer, FEC, congestion control are free** — the browser stack handles them.
2. **ICE handles edge cases** — if both parties happen to be behind NAT (home deployment), ICE's STUN/TURN flow just works.
3. **Browser and native symmetry** — browsers connect via native WebRTC; native nodes use a headless WebRTC library (`wrtc`, `@roamhq/wrtc`, or Pion via IPC).
4. **SFU for fan-out** — a node acting as a stream host runs a lightweight SFU (Selective Forwarding Unit) pattern: one incoming publisher stream, N outgoing viewer streams. Libraries like mediasoup or go-based pion-sfu run in-process.

For file transfer, the media plane is WebSocket binary frames or RTCDataChannel (larger files), with CRC per chunk and resume support.

### Access & Micropayments — Paywall as a Session Preamble

The access-control story fits into session formation:

```
1. Viewer discovers stream:
   GET https://todd.semantos.net/streams
   → [{ id, title, kind, accessPolicy, meteringPolicy, ... }]

2. Viewer initiates join:
   POST /sessions/<streamId>/join { viewerBca, payment? }
   → If accessPolicy = paywall, node responds 402 Payment Required
     with { channelOpenQuote: { satsPerMinute, channelOpenSatsMin, ... } }

3. Viewer opens metering channel:
   Opens a 2-of-2 multisig channel via packages/metering
   Sends signed channel-open commitment to host node

4. Host node issues join token:
   Token = { streamId, viewerBca, channelId, signedByHost }

5. Viewer presents token to WebSocket /session endpoint:
   WSS upgrade with token
   → Host joins viewer to the session, media plane negotiates RTC
   → Metering ticks fire per second of received media
   → Viewer presents signed incrementing commitments; host validates

6. Session end:
   Final commitment signed
   Host submits batch via packages/settlement border-router
```

This flow is identical for voice/video calls (billed per-minute), live streams (pay-per-view), and file transfers (one-shot charge). Only the `MediaMeteringPolicy` and `stateMachine` differ.

### Peer Locator

Three complementary resolution mechanisms, any combination:

1. **DNS** — owner controls a domain. `todd.semantos.net` publishes AAAA record and a `TXT` record containing the BCA hex. Node verifies the BCA during TLS handshake. Zero new infrastructure.

2. **Locator Registry** — operator-run or self-hosted HTTP service. BCA → `{ endpoint, lastHeartbeat, pubkey, services }`. Federated: a node can push its record to multiple locators and viewers can query multiple locators in parallel.

3. **Handle Directory** — fediverse-style `@todd@semantos.net` webfinger. The domain's locator serves the full record.

Node config declares which to publish to. Minimum-viable is DNS-only: zero new infrastructure, works immediately for anyone with a domain.

---

## Source Files / References

| Alias | Path | What to reference |
|-------|------|------------------|
| `SP:PKG` | `packages/session-protocol/` | Phase 35A session skeleton |
| `NODE:API` | `packages/node/src/api/{server,routes,tls}.ts` | Existing HTTPS surface |
| `NODE:CFG` | `packages/node/src/commands/node-config.ts` | NodeConfig schema |
| `METERING` | `packages/metering/` | Channel FSM for media metering |
| `SETTLE` | `packages/settlement/` | Border-router for batched settlement |
| `LOOM` | `packages/loom/` | React UI — stream viewer panel, call UI |
| `TYPES:NET` | `packages/protocol-types/src/network.ts` | NetworkAdapter interface |
| `BCA:ZIG` | `packages/cell-engine/src/bca.zig` | BCA derivation |
| `EXTERNAL:WRTC` | https://github.com/WonderInventions/node-webrtc | Headless WebRTC for native node |
| `EXTERNAL:MEDIASOUP` | https://mediasoup.org | SFU library for stream fan-out |
| `PHASE:35A` | `docs/prd/PHASE-35A-SESSION-PROTOCOL-PROMOTION.md` | Prerequisite |

---

## Deliverables

### D35B.1 — `packages/ws-node-adapter/` (WAN NetworkAdapter)

A `NetworkAdapter` implementation that federates semantos nodes over WSS. Much simpler than the multicast adapter: no CoAP framing, no broadcast — direct WebSocket between peer node pairs carrying framed CBOR.

```typescript
export class WsNodeAdapter implements NetworkAdapter {
  // Outbound — dials peers by resolved endpoint
  async connect(peerBca: string, endpoint: string): Promise<WsPeerConnection>;

  // Inbound — mounts on node's HTTPS server at /session
  mountOn(app: WebSocketRouteTarget, path: string): void;

  // NetworkAdapter interface
  async publish(object: PublishableObject, options?: PublishOptions): Promise<PublishResult>;
  subscribe(topic: string, cb: (e: NetworkEvent) => void): () => void;
  async resolve(query: NetworkQuery): Promise<NetworkResult[]>;
  async resolveBCA(addr: string): Promise<NodeInfo | null>;
  async sendToNode(targetBca: string, message: Uint8Array): Promise<{ delivered: boolean }>;
}
```

Wire format: CBOR-framed session-protocol messages over WSS, one frame per message. BCA-signed envelope for auth. Heartbeat every 30s, idle-close after 5min with auto-reconnect on activity.

### D35B.2 — `packages/webrtc-adapter/` (Browser-Client NetworkAdapter)

`NetworkAdapter` implementation backed by `RTCPeerConnection` + `RTCDataChannel`. The data channel carries session-protocol messages; media tracks carry audio/video.

Two modes:
- **Browser-side** — consumed by `loom` UI for calling into a node
- **Native-side** — node hosts WebRTC via headless wrtc library, accepts browser connections

Signalling happens over `ws-node-adapter`'s `/media` WSS endpoint (SDP offer/answer + ICE candidates).

### D35B.3 — `packages/media-protocol/` (Media-Session Consumer)

New package that composes session-protocol + the set of media-session state machines:

```
packages/media-protocol/src/
├── descriptors/
│   ├── voice.ts           — VoiceCallDescriptor, two-party, metered per minute
│   ├── video.ts           — VideoCallDescriptor, two-party or small group
│   ├── stream.ts          — LiveStreamDescriptor, 1:N with SFU fan-out
│   ├── conference.ts      — ConferenceDescriptor, N:N
│   ├── file.ts            — FileTransferDescriptor, bounded
│   └── broadcast.ts       — PublicBroadcastDescriptor, 1:∞ with tip jar
├── state-machines/
│   ├── call-fsm.ts        — idle→inviting→ringing→connected→on-hold→terminating→done
│   ├── stream-fsm.ts      — idle→going-live→live→ending→archived
│   ├── transfer-fsm.ts    — idle→proposing→accepted→transferring→complete | aborted
│   └── conference-fsm.ts  — idle→assembling→active→empty→closed (N-party state)
├── media-plane/
│   ├── webrtc-plane.ts    — SDP negotiation, ICE, codec selection, track management
│   ├── sfu-plane.ts       — SFU for 1:N fan-out using mediasoup
│   └── file-plane.ts      — binary-chunked transfer over RTCDataChannel
├── access/
│   ├── open.ts            — no gating
│   ├── invite.ts          — invite-token-gated
│   └── paywall.ts         — metering-channel-gated
└── metering-policies.ts   — per-minute, per-byte, per-view, tip-jar
```

### D35B.4 — `packages/peer-locator/` and `packages/peer-locator-service/`

Two siblings:

- **`peer-locator`** — client library consumed by every node. Resolves BCA → endpoint via DNS, local cache, and configured locator services. Verifies resolved record against cryptographic proof (TLS cert pubkey matches BCA derivation).

- **`peer-locator-service`** — optional operator-run server implementing the registry API:

```
POST   /peers           { bca, endpoint, pubkey, signature }  — register / heartbeat
GET    /peers/:bca                                             — lookup
GET    /peers                                                  — listing (paginated, filterable)
GET    /.well-known/webfinger?resource=acct:todd@example.net   — fediverse-style handle lookup
GET    /peers/:bca/services                                    — what kinds of sessions this node advertises
```

Self-hostable (anyone can run their own locator), federated (a node can publish to multiple locators), and permissionless (no gating on registration, but spam handled via heartbeat decay + optional rate-limit).

### D35B.5 — Node Surface Extensions (`packages/node/`)

Extend existing `packages/node/src/api/` with:

```typescript
// New WebSocket routes
router.ws('/session', sessionProtocolHandler);         // session-protocol over WSS
router.ws('/media',   webRtcSignallingHandler);        // WebRTC SDP/ICE relay
router.ws('/calls',   incomingCallHandler);            // browser client initiates call

// New HTTPS routes
router.get ('/',                profilePageHandler);    // public profile, linkable
router.get ('/streams',         streamListHandler);     // live and scheduled streams
router.post('/streams',         streamCreateHandler);   // authenticated — owner only
router.get ('/streams/:id',     streamDetailHandler);   // viewer-facing detail
router.post('/sessions/:id/join', sessionJoinHandler);  // paywall check + token issue
router.get ('/.well-known/semantos-node', wellKnownHandler);  // BCA, advertised kinds, version
router.get ('/.well-known/webfinger',      webfingerHandler); // fediverse interop
```

`wellKnownHandler` returns:

```json
{
  "bca": "2a01:db8::abcd",
  "pubkey": "03a1...",
  "node_cert_id": "plexus-cert-sha256",
  "version": "0.35.0",
  "adapters": {
    "ws_node": { "endpoint": "wss://todd.semantos.net/session" },
    "webrtc":  { "signalling": "wss://todd.semantos.net/media" }
  },
  "advertised": ["voice", "video", "stream", "file"],
  "metering": "enabled",
  "settle_to": "bsv:1AbCd..."
}
```

### D35B.6 — Config, CLI, and Docker Packaging

Extend `NodeConfig`:

```typescript
export interface NodeConfig {
  // ...existing fields...
  public?: {
    hostname: string;              // todd.semantos.net
    tls: {
      provider: 'letsencrypt' | 'file';
      email?: string;              // for Let's Encrypt
      certPath?: string;
      keyPath?: string;
    };
  };
  locator?: {
    publish_to: string[];          // e.g. ["https://locator.semantos.net"]
    heartbeat_interval_s: number;  // default 300
  };
  media?: {
    enabled_kinds: MediaKind[];    // ["voice", "stream"]
    webrtc: {
      stun_servers: string[];
      turn_servers?: string[];     // optional, for Phase 35C NAT fallback
    };
    sfu?: {
      provider: 'mediasoup' | 'pion';
      max_concurrent_streams: number;
    };
  };
  settle?: {
    bsv_address: string;
    border_router_batch_interval_s: number;
  };
}
```

New CLI subcommands in `packages/node/src/cli.ts`:

```
semantos node serve                      # runs the full node daemon
semantos node provision-tls              # obtains Let's Encrypt cert
semantos node register-with-locator URL  # push record to locator
semantos node call BCA --kind voice      # initiate a call from CLI
semantos node stream create --title ...  # create a stream session
```

New docker-compose profile `docker-compose.node-service.yml` — single-user VPS-ready deployment, single service, reads `NodeConfig` from `/etc/semantos/node.toml`, exposes 443 only.

### D35B.7 — Loom UI — Viewer and Caller Panels

Extend `packages/loom/`:

- **Caller panel** — enter a BCA / handle / hostname, click call, select media kind (voice/video), UI shows ringing → connected → duration → end with cost breakdown.
- **Stream viewer panel** — browse a node's `/streams`, see paywall quote, confirm channel-open, watch with live cost display.
- **Stream producer panel** (node owner only) — "Go Live" with title, description, pricing, kind. Same plumbing as caller but one-to-many with SFU enabled.
- **Contact book** — local map of BCA → human-readable label. Signed-import from friends' public handles.
- **Channel ledger** — all open and closed metering channels, with settle-status from border-router.

### D35B.8 — Gate Tests `packages/__tests__/phase35b-gate.test.ts`

| ID | Scenario | Assertion |
|----|----------|-----------|
| G35B.1 | Two `WsNodeAdapter` instances federate over local loopback HTTPS | Publish/subscribe round-trip in <50ms |
| G35B.2 | `WebRtcAdapter` SDP exchange via `ws-node-adapter` signalling | `RTCPeerConnection.connectionState` reaches `'connected'` |
| G35B.3 | Voice call end-to-end (CallStateMachine) | Audio track received at callee, metering tick every 1s, settlement commitment at hangup |
| G35B.4 | Stream with SFU fan-out, 1 producer + 3 viewers | All viewers receive media, each has independent metering channel |
| G35B.5 | Paywall enforcement | Join attempt without channel-open receives 402; with channel-open receives 200 + join token |
| G35B.6 | Peer-locator round-trip | Node A registers, Node B resolves A's BCA and gets correct endpoint |
| G35B.7 | DNS-only reachability | Node at `a.test.lan` resolvable by hostname with no locator configured |
| G35B.8 | TLS ↔ BCA binding | TLS handshake verifies cert pubkey matches advertised BCA; mismatch rejects |
| G35B.9 | File transfer, 10MB over RTCDataChannel | Completes, hashes match, metering tick per MB |
| G35B.10 | Conference 4-party video | All pairs see each other, N-1 channels each, stable for 60s |
| G35B.11 | Cold-start to connected | New install → provision TLS → register with locator → accept inbound call: under 15 minutes for operator |
| G35B.12 | Session-protocol interoperability with poker | PokerSessionFactory still works unchanged — no regression from 35A |

### D35B.9 — Documentation and Demo

- New: `packages/media-protocol/README.md` with descriptor examples for each MediaKind.
- New: `docs/operator-guide.md` — how to stand up a node on a VPS, from fresh Ubuntu to first inbound call. Target: 15 minutes, copy-pasteable.
- New: `docs/user-node-architecture.md` — end-to-end diagrams matching this PRD.
- Demo deploy: `demo.semantos.net` hosting a demo node. Any reader can call into it, see the loom UI, create a test stream.
- Update: root `README.md` — add `media-protocol`, `ws-node-adapter`, `webrtc-adapter`, `peer-locator*` to the Apps/Runtime/Extensions tables.

---

## Definition of Done

1. All D35B.1–D35B.7 packages build, type-check, and pass their unit tests.
2. `packages/__tests__/phase35b-gate.test.ts` passes 12/12.
3. Two VPS-hosted nodes at different providers can complete a voice call, a video call, a 1:3 stream, and a file transfer with metering ticks and settlement commitments verified end-to-end.
4. Operator-guide walkthrough succeeds end-to-end on a fresh Ubuntu 24.04 VPS in under 15 minutes of hands-on time.
5. Loom UI renders all four new panels (caller, stream viewer, stream producer, contact book, channel ledger) and they're exercised by the E2E tests.
6. DNS-only reachability works: a node with no configured locator but a published AAAA + TXT record is callable by hostname.
7. `semantos node call BCA --kind voice` from a fresh terminal completes a round-trip call within 30 seconds.
8. No regression in poker-agent tests or any Phase 35A gate.

---

## Economics and Product Surface (Informational)

The service layer produces a commercial surface without requiring platform-style hosting:

| Product | Delivered by | Who can sell it | Revenue model |
|---------|--------------|-----------------|---------------|
| Self-hosted sovereign node | Open-source semantos-node | Anyone (self-serve) | Free |
| Managed node hosting | Operator-provided VPS + node | You, or third parties | Monthly fee per node |
| Peer-locator as a service | `peer-locator-service` | You, or federated operators | Freemium (free listing, paid features) |
| NAT-relay service (Phase 35C) | Relay adapter + hosted relay | You, or third parties | Per-GB or monthly |
| Content monetisation | Built into media-protocol metering | The node owner | Direct, no rake |

This is "protocol open, services optional" — the revenue opportunity is infrastructure, not gatekeeping.

---

## Out of Scope (Deferred)

- **Phase 35C — Relay Adapter**: WebSocket-relay adapter + hosted relay for IPv4-only/NAT'd users who can't run on a public-IP VPS.
- **Phase 35D — Recording and Archive**: stream archival to cell-packed storage, replay with replay-metering.
- **Phase 35E — Content Moderation**: cross-node abuse reports, BCA blocklists as RELEVANT cells, reputation as a separate vertical.
- **Phase 36 — Federated Discovery**: cross-locator discovery, search, trending, recommendation. Requires deliberate design to avoid central-platform dynamics.
- **Phase 37 — Mobile Clients**: iOS/Android companions using the same `webrtc-adapter` pattern.
- **Native SIP/RTP**: remains out of scope in favour of WebRTC as the primary media plane. Revisit only if a compelling telephony integration arises.

---

## Follow-on Phases

- Phase 35C (relay, 1–2 weeks): optional hosted relay for residual NAT cases.
- Phase 35D (archive, 2 weeks): stream recording + replay + cell-packed archive.
- Phase 36 (discovery, 3 weeks): federation between locators, cross-locator search.
- Phase 37 (mobile, 4–6 weeks): native iOS/Android clients.
- Phase 38 (agent-as-service, 2 weeks): pre-packaged agents for a hosted node (auto-answer, voicemail, scheduling secretary, paid-expert broker).
