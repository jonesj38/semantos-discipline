---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/UDP-MESH-DIRECTION.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.685700+00:00
---

# UDP Mesh Direction — sovereign transport, contacts-book PKI

**Status**: forward-looking PRD captured 2026-05-07 from operator's late-night direction note.
**Origin**: operator: "we are leaning more UDP too btw" + a chat extract laying out why UDP-with-cell-layer-crypto is structurally cleaner than HTTPS for the job-site mesh use case.
**Scope**: this is the vision + phasing. Implementation briefs are siblings (`UDP-DATAGRAM-DISPATCH-BRIEF.md`, `CONTACTS-BOOK-PKI-BRIEF.md`, `NODE-PROTOCOL-BRING-FORWARD-PLAN.md`).

---

## §1 — Why UDP

The operator's job-site reality:
- Workers + foremen + sub-tradies + property managers, all on phones
- Spotty cell coverage, intermittent Wi-Fi, occasional concrete pillars
- High-volume short messages (status updates, photos, voice memos, FSM events)
- Already-trusted entities (people you've worked with for years, not random strangers)
- No central server is desirable in steady-state — the cellular network is the reliability bottleneck, not the brain

HTTPS imposes three taxes that don't fit this profile:

### 1.1 — CA cartel tax
Domain-name-bound TLS certs require Let's Encrypt or equivalent + DNS dependency + Caddy/nginx in front of every brain. Bridget paid this tax tonight (2026-05-07) standing up `brain.utxoengineer.com` so her phone could pair through ngrok-replacement TLS. Solved her demo, but it's accidental complexity for a mesh of known peers.

### 1.2 — Handshake tax
TCP 3-way SYN/SYN-ACK/ACK + TLS ClientHello/ServerHello/KeyExchange = hundreds of milliseconds before a single byte of payload moves. On flaky cell connections, the handshake itself can fail → user sees "network error" with no clue whether their actual operation went through.

### 1.3 — Head-of-line blocking
TCP semantics: packet 4 drops → packets 5+ wait in the buffer until packet 4 is retransmitted, even if 5+ are usable on their own. Catastrophic for a stream of independent cells (each cell is its own DAG node; loss of one doesn't invalidate the rest).

UDP has none of these. **And the security primitive that HTTPS provides at the transport layer (encryption + authentication of bytes-in-flight) is already provided in the data layer** by the existing infrastructure:
- **BRC-52 Identity Certificates** (already in the wallet) — cryptographic identity per peer
- **BKDS per-cell signing** (PR #390, recently shipped) — per-cell-content key derivation under the operator-root scope; cell payload + header HMAC'd
- **Cell-DAG schema** (D-DOG.1.0c, recently shipped) — content-addressed cells, no tamper window

So a UDP datagram carrying one signed cell IS the security primitive. The transport just delivers bytes; the bytes are self-authenticating.

---

## §2 — Architecture

### 2.1 — Two transports, one brain

Brain continues to serve TCP/HTTPS for:
- The wallet-browser admin UI (browser-bound, can't speak UDP)
- Cross-machine REPL access from operator/Bridget Macs (curl-friendly)
- Phone pairing first-run (fetches the child cert via HTTPS)

Brain adds UDP datagram dispatch alongside:
- Cell-DAG sync between paired devices (signed cells in datagrams)
- Pub/sub topic delivery (broadcast or unicast cell deltas)
- Eventually: real-time message + dispatch decision streaming for the mobile attention surface (replacing or supplementing the WSS poll loop)

The reactor pattern from the Semantos Brain-wedge fix (PR pending — `BRAIN-WEDGE-FIX-IMPLEMENTATION-BRIEF.md`) extends naturally: UDP socket goes in the same `poll_fds` array, `recvfrom()` returns a complete datagram per call, no per-connection state machine even needed (each datagram is its own complete unit). The TLA+ `ReactorIsolation` proof's `IsolationFromStalledConnections` property holds without modification — it never depended on TCP-specific semantics.

### 2.2 — Contacts-book as PKI

Currently the customers store (`runtime/semantos-brain/src/customers_store_fs.zig`, post-D-DOG.1.0c §2A.2) stores customer cells with name + role + ref-to-job. It needs a sibling concept: **peer contact** — a cell that stores a person's BRC-52 public key + display name + last-seen address.

Cell shape sketch (deferred to `CONTACTS-BOOK-PKI-BRIEF.md` for full schema):

```
oddjobz.peer.v1 {
  cellId: <content-hash>
  typeHash: <oddjobz.peer.v1>
  displayName: "Bridget Doran"
  brc52PubKey: <hex>
  brc52CertChain: [<root-cert>, <child-cert>] // optional, for transitive trust
  lastSeenAddr: "10.42.0.7:5050"            // optional, for mesh discovery
  trustEstablishedAt: <timestamp>
  trustEstablishedVia: "qr-scan" | "bca-handshake" | "transitive"
}
```

When operator adds Bridget to contacts (one-time via QR code on the job site OR via BCA-mediated cert exchange), the cell is minted in the operator's local cell-DAG. From that point forward:

- **ECDH derivation is local + offline**: operator-priv × Bridget-pub = shared symmetric key. No network round-trip. Computed once, cached.
- **Mesh discovery is broadcast**: when both phones join the same Wi-Fi (or BLE, or future LoRa), each broadcasts a UDP heartbeat carrying `oddjobz.peer.v1.cellId`. Receiving phone checks its contacts cell-DAG for that cellId; if present, the ECDH key is already derivable.
- **Datagram authentication is HMAC-over-shared-key**: every UDP packet carries `HMAC-SHA256(shared_key, packet_payload)`. Forgery-resistant; replay-resistant via nonce/timestamp in the packet header.

This is the same end-to-end-encryption topology as Signal/WhatsApp, but running over UDP without a centralised signaling server.

### 2.3 — Trust expansion graph

Operator's trust graph isn't flat. He has:
- **Direct** peers (Bridget, sub-tradies he's met, property managers he's invoiced)
- **Transitive** peers (workers Bridget vouches for, sub-sub-tradies introduced via direct peers)
- **Public** peers (random property-management bots, social channels — these get NO ECDH, only signed cells via existing BCA flows)

The contacts cell schema's `trustEstablishedVia` field captures provenance. UI shows "added by you" vs "introduced by Bridget" vs "public" tier.

For Tier 2P attention surface integration: dispatch decisions can use the trust tier as a confidence bump. A message from a direct-trust peer might score higher than from a public peer.

---

## §3 — Phasing

### Phase U.1 — Bring `node-protocol` to main ✅ COMPLETE (2026-05-07)

Status: complete via PR #417, on top of previously-undiscovered PR #108 which had already squash-merged the 14 Wave-35-Phase-A commits. My initial triage missed that #108 existed; U.1's rebase correctly identified the commits as already-upstream and dropped them. PR #417 records the formal history with the conflict resolutions documented per pattern A/B/C.

**Architectural surprises** (worth noting for U.2 + U.3):
- `UdpTransport` is at `core/protocol-types/src/adapters/udp-transport.ts` with `LoopbackUdpTransport` + `NodeUdpTransport` — NOT as a standalone `runtime/udp-transport/` package as the original brief assumed. Brain-side U.2 implementation uses Zig stdlib (`std.posix`) directly; the TS-side UdpTransport interface remains for TS consumers (jam-room, etc.).
- session-protocol's `multicast-adapter.ts` is now a 60-line shim into `./multicast/` (18-file split refactored in prompt-38, post-Codex). Anyone importing `MulticastAdapter` from session-protocol gets the new split form.

### Phase U.2 — Brain UDP datagram dispatch

After brain-wedge reactor lands, add a UDP socket to its poll set. Each `recvfrom()` returns a datagram; dispatch by datagram type:
- Cell-DAG sync (incoming cell, verify HMAC, append to graph if novel)
- Topic broadcast (emit to local pub/sub broker)
- Heartbeat (peer presence — update `lastSeenAddr` on the contact cell)

Implementation brief: `UDP-DATAGRAM-DISPATCH-BRIEF.md`.

**Effort**: 2-3 days. Mostly straightforward — UDP is simpler than TCP (no per-connection state machine).

### Phase U.3 — Contacts-book cell type + ECDH adapter

New cell type `oddjobz.peer.v1` + view store + minting verb (`add peer <name> <pubkey>`). ECDH adapter on both brain-side (for cell sync) and mobile-side (for datagram authentication). Mobile UI: contacts list, add-peer-via-QR, peer-tier indicators.

Implementation brief: `CONTACTS-BOOK-PKI-BRIEF.md`.

**Effort**: 4-6 days (split: 2 days schema/store, 2 days ECDH adapter both sides, 2 days mobile UI).

### Phase U.4 — Mesh discovery + UDP transport on mobile

Phone-side: when Wi-Fi/BLE associates with a known network, broadcast a presence beacon with own peer cellId. Listen for matching beacons; on match, derive ECDH key, open UDP "session" (just a remembered shared-key + remote-addr pair). Routes outbound `oddjobz.message.v1` patches via UDP-to-peer when peer is reachable; falls back to brain-via-WSS otherwise.

**Effort**: 5-7 days. Mobile mesh discovery has platform-specific quirks (iOS Wi-Fi peer-to-peer constraints, Android background restrictions).

### Phase U.5 — Replace WSS poll for attention surface (optional, longer-term)

Once UDP transport is reliable, the mobile attention surface (Tier 2P D.2 + D.3) can subscribe to brain-side topic broadcasts via UDP instead of HTTP polling. Lower latency, lower battery drain.

**Effort**: 2-3 days. Builds on U.2 + U.3 + U.4.

---

## §4 — Existing infrastructure inventory

What's already in place vs what's needed:

| Capability | Status | Notes |
|---|---|---|
| BRC-52 cert chains | ✅ shipped | Used today for wallet identity + child-cert pairing |
| BKDS per-cell signing | ✅ shipped (#390) | Per-cell content-hash → derived signing key under domain/protocol scope |
| Cell-DAG primitives | ✅ shipped (D-DOG.1.0c) | Content-addressed sites/customers/jobs/attachments cells |
| `runtime/udp-transport/` package | ⚠ on `node-protocol` branch only | Codex's Wave 35 Phase A; needs U.1 bring-forward |
| Brain poll-based reactor | ⏳ in flight | brain-wedge fix; landing tonight |
| `oddjobz.peer.v1` cell type | ❌ not started | U.3 |
| Mobile UDP transport adapter | ❌ not started | U.4 |
| Mesh discovery (BLE/Wi-Fi) | ❌ not started | U.4 |
| Phone-to-phone direct messaging | ❌ not started | U.4 |
| HTTPS/TLS path (brain serve, Caddy in front) | ✅ shipped | Stays for browser admin UI + cross-machine REPL |

---

## §5 — Open architecture questions

To resolve before Phase U.3 begins:

### 5.1 — Datagram size + fragmentation

UDP MTU is typically 1500 bytes (Ethernet) - 28 bytes (UDP header) = 1472 bytes per datagram. The operator's chat noted "1024-byte cells" — that fits comfortably in one datagram with headers + HMAC + nonce. Larger payloads (PDF attachments, voice memos) need fragmentation OR fallback-to-TCP-via-brain. Decision needed: does U.2 implement fragmentation, or only support cells ≤ N bytes per datagram?

**Recommendation**: U.2 supports cells ≤ 1024 bytes; fragmentation deferred. PDF/voice attachments continue to flow via brain HTTPS for now (operator's current pattern).

### 5.2 — NAT traversal for mobile-to-mobile

Two phones on the same Wi-Fi: trivial — direct UDP works. Two phones on different cellular networks: NAT in the way. Need either STUN-like hole-punching, a relay node (the brain CAN serve this purpose via TURN-ish forwarding), or accept that mobile-to-mobile UDP only works on shared Wi-Fi.

**Recommendation**: U.4 supports same-network UDP only. Cross-network falls back to brain-relayed UDP (brain forwards datagrams between paired phones). Hole-punching deferred — its own phase if scale demands.

### 5.3 — Replay protection

UDP packets can be captured + replayed. Each authenticated datagram needs:
- A monotonic nonce OR timestamp window (5s)
- Receiver-side anti-replay cache (recently-seen nonces)

The session-protocol package on `node-protocol` branch already has some of this (`SessionRuntime` per the commit log). Worth auditing for replay-safety once U.1 lands.

### 5.4 — Multicast for broadcast topics

The session-protocol package's `MulticastAdapter` (also on `node-protocol`) suggests Codex already designed for IP multicast. Useful for "broadcast to all peers in a job-site mesh" — e.g., an emergency-stop or shift-end notification reaches everyone with one datagram.

**Recommendation**: U.2 adopts the existing `MulticastAdapter` shape. Operator's "leaning more UDP" message specifically calls out the broadcast use case (emergency notification reaches everyone), so this is high-value.

---

## §6 — Cross-references

- `docs/prd/BRAIN-WSS-WEDGE-ARCHITECTURAL-OPTIONS.md` — current reactor work (TCP focus, but pattern extends to UDP)
- `docs/prd/BRAIN-WEDGE-FIX-IMPLEMENTATION-BRIEF.md` — brain-wedge implementation, foundation for U.2
- `docs/prd/CODEX-INTEGRATION-MAP.md` §2.1 — `node-protocol` branch state (14 commits, 11 conflicts)
- `docs/prd/NODE-PROTOCOL-BRING-FORWARD-PLAN.md` (sibling) — U.1 detail
- `docs/prd/UDP-DATAGRAM-DISPATCH-BRIEF.md` (sibling) — U.2 detail
- `docs/prd/CONTACTS-BOOK-PKI-BRIEF.md` (sibling) — U.3 detail
- `runtime/semantos-brain/src/hat_bkds.zig` — BKDS primitive used for ECDH domain scoping
- `runtime/semantos-brain/src/customers_store_fs.zig` — pattern for the new `oddjobz.peer.v1` store

---

## §7 — Summary for the morning runbook

When operator wakes:
1. `node-protocol` branch still has 14 unmerged commits (no change since previous handoff). Phase U.1 brings them to main. Plan: `NODE-PROTOCOL-BRING-FORWARD-PLAN.md`.
2. Brain-wedge reactor PR is in flight (agent working as of handoff). When it lands, U.2 (UDP datagram dispatch) becomes possible — the reactor's poll set just needs UDP added.
3. The TLA+ `ReactorIsolation` property holds for UDP without modification (datagrams are atomic; no per-connection state machine; same isolation guarantee).
4. Three implementation briefs sit ready (`UDP-DATAGRAM-DISPATCH-BRIEF.md`, `CONTACTS-BOOK-PKI-BRIEF.md`) for whoever ships next.
5. Operator's "leaning more UDP" doesn't replace HTTPS — TCP/HTTPS path stays for browser admin + cross-machine REPL + iOS Simulator (which can't easily speak UDP from app sandbox). UDP is additive.
