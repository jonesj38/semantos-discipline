---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/design/SRS-XMPP-IDENTITY-TRANSPORT.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.722781+00:00
---

# SRS × XMPP — Identity-Bound Transport over the Semantic Routing Substrate

**Version:** 0.1 (binding draft)
**Date:** 2026-06-04
**Status:** Design — binds XMPP/Jabber onto the SRS address plane + the existing identity/PKI stack
**Owners / prior art:**
- `docs/design/SEMANTIC-ROUTING-SUBSTRATE.md` (SNS / SRv6 type-network — the address plane)
- `docs/prd/PHASE-34-SRV6-TYPE-NETWORK-MASTER.md` (multicast + SID derivation, segment functions)
- `core/contact-book/src/{types,contact-store}.ts` (Contact + EdgeRecord — the roster)
- `runtime/session-protocol/src/signer.ts` (`deriveBCABytes`, `bcaBytesToIPv6`)
- `cartridges/oddjobz/brain/tools/send-bundle.ts` + `runtime/semantos-brain/src/transport/signed_bundle.zig` (brain-to-brain wire shape)
- `cartridges/wallet-headers/brain/src/ecdh42.ts` (BRC-42 per-edge key rotation)
- `core/protocol-types/src/network.ts` (NetworkAdapter interface)
- `core/protocol-types/src/overlay/relay-advertisement.ts` (signed, priced type-path advertisement)

**Canon home:** singularity-matrix **L3-G** (paid-pubsub); unification-matrix **U14** (Semantic Routing) consuming **U3** (identity/BCA).

---

## 0. Thesis

XMPP is not a new transport to *replace* the SRS — it is the **presence + discovery + offline-delivery
skin** that sits on top of two things the SRS already produces: the **BCA** (identity-derived unicast
IPv6) and the **type-multicast group** (typehash-derived IPv6). Both are 128-bit IPv6 addresses, and
XMPP has exactly two delivery modes — directed `<message>` (unicast) and PubSub/MUC (multicast). The
binding is therefore an *address-plane alignment*, not a protocol bolt-on.

The trust model does **not** move into XMPP. Identity stays in the cert chain: every stanza body carries
an unchanged `SignedBundle`. XMPP carries bytes and liveness; the cell/cert layer carries trust and
payment. This is the same layering discipline as the SRS itself (network forwards on structure; the
application decides intent; BSV anchors the proof).

> **The one correction baked into this doc.** The BCA is derived from the node *pubkey*
> (`deriveBCABytes` over the Plexus cert key), **not** from the typehash. The typehash drives the
> *multicast* address (`computeWhatHash/HowHash/InstHash` → `ff03:WWWW:WWWW:HHHH:HHHH:IIII:IIII`).
> Routing *pairs* the two (the `(BCA_i, TYPE_HASH_i)` segment tuple). XMPP inherits that pairing:
> unicast JID-domain = BCA; pubsub node = type-multicast group.

---

## 1. The address-plane split → XMPP's two delivery modes

The SRS produces two kinds of IPv6 address. XMPP has two kinds of delivery. They line up 1:1.

| SRS address | Derived from | Bits / format | XMPP construct |
|---|---|---|---|
| **BCA unicast** | node pubkey (`deriveBCABytes`) | `PPPP:PPPP:CCCC:CCCC` (prefix + 8-byte IID) | directed `<message to="certId@[BCA]/hat">` |
| **Type multicast** | `computeWhatHash/HowHash/InstHash` | `ff03:WWWW:WWWW:HHHH:HHHH:IIII:IIII:0000` | PubSub node (XEP-0060) / MUC |

Consequence: the **PubSub node identifier can *be* the type-multicast group**. A brain subscribing to a
type-path joins the `ff03:…` group and the pubsub node name is the same 128 bits — one naming scheme,
not two. Hierarchical subscription (the SNS longest-prefix-match trie) maps onto **XEP-0248 collection
nodes**: the WHAT/HOW/INST nesting *is* the collection hierarchy.

```
ff03:WWWW:WWWW::                          → collection node: all of this WHAT
ff03:WWWW:WWWW:HHHH:HHHH::                → child collection: this WHAT + HOW
ff03:WWWW:WWWW:HHHH:HHHH:IIII:IIII:0000   → leaf node: exact composite type
ff03::HHHH:HHHH::                          → HOW-collection (every "settle"), cross-WHAT
```

The last (cross-WHAT "all settle events") wildcard is the one XMPP can't express with a single
collection subtree — it's an orthogonal axis. Handle it as a separate HOW-rooted collection
hierarchy, or fall back to a saved-search subscription. (Open question §10.2.)

---

## 2. The JID grammar — identity + route + hat in one address

```
<certId>@[<BCA-or-multicast-IPv6>]/<context-tag>
```

| JID part | Primitive | Source |
|---|---|---|
| **localpart** | `certId` — `SHA-256(BRC-52 cert preimage)[0:16]` (32-hex) | `core/contact-book/src/types.ts` |
| **domain** | BCA IPv6 literal (unicast) **or** type-multicast group (pubsub) | `signer.ts` / Phase-34A `deriveMulticastGroup` |
| **resource** | `context_tag` / hat (root=0, carpenter=0x10, musician=0x11) | `CertRef.context_tag` in `send-bundle.ts` |

Every field is cryptographically derived. The XMPP `resource` — normally "which device/session" — is
repurposed as the **hat**: one resource per context, each with its own presence and its own BRC-42
per-context signing key. `<presence>` per-resource then means "musician brain online, carpenter brain
offline" natively.

**Domain-is-the-route (future unlock).** Standard XMPP s2s resolves the domain via DNS SRV. If the BCA
is a *routable* v6 address (the SRv6 locator plane), the IP-literal domain is directly dialable and DNS
is bypassed entirely — serverless, self-certifying federation. Today the BCA is identity-only (Skyminer
is link/realm-local `ff15::` multicast; SRv6 locators are designed, not deployed), so s2s rides over the
existing peer-locator until the routable prefix lands. (Open question §10.1.)

---

## 3. Auth binding — SignedBundle as the payload, not the stream

There are two layers at which XMPP could bind to our PKI. **Bind at the payload; treat stream auth as
optional hardening.**

**Payload binding (authoritative).** Each stanza body carries the existing `SignedBundle`, byte-for-byte
unchanged:

```
<message to="<recipientCertId>@[<BCA>]/<hat>"
         from="<senderCertId>@[<BCA>]/<hat>">
  <bundle xmlns="urn:semantos:signed-bundle:1">
    { v, sender_cert_chain[], recipient_cert_id, payload_type,
      payload, signature, signature_metadata{ algorithm, nonce_hex, timestamp_unix } }
  </bundle>
</message>
```

- `recipient_cert_id` → JID localpart; recipient BCA → JID domain; `payload_type` (e.g.
  `dispatch.request`) → the bundle's own field (XMPP `type` stays `chat`/`normal`).
- Verification is the **unchanged brain receive flow**: decode → verify cert chain (leaf in local
  `CertStore`, trust prefix) → recover pubkey from ECDSA sig, match leaf cert → dispatch.
- `signature_metadata.nonce_hex` + `timestamp_unix` give **anti-replay**, which XMPP does not provide
  natively — keep them; they are the reason payload binding wins.

**Stream binding (optional).** For s2s between our own nodes, present a TLS cert whose secp256k1 key is
the node's identity key and authenticate the stream via **SASL EXTERNAL** — the cert *is* the BCA. This
hardens the connection but is never the source of truth; a node that trusts only stream auth and skips
`SignedBundle` verification is misconfigured.

Net effect: adopting XMPP **never forks the wire format**. `POST /api/v1/bundle` and an XMPP `<message>`
carry the identical bundle; XMPP just adds queueing, presence, and pubsub around it.

---

## 4. Roster = ContactStore, with *signed* subscriptions

The `ContactStore` is the XMPP roster, and it is strictly stronger than the vanilla version.

| XMPP roster concept | SRS primitive |
|---|---|
| roster item (`jid`, name) | `Contact { certId, publicKey, displayName, nodeType }` |
| presence subscription (`none/to/from/both`) | `EdgeRecord { initiatorCertId, responderCertId, edgeType: MESSAGING }` |
| subscription approval (server-vouched) | **signed** edge with `signingKeyIndex` (cryptographic, not server-asserted) |
| roster push | `addContact`/`updateContact`/`removeContact` → presence-subscription state change |
| unsubscribe | `EdgeRecord.revokedAt` (soft-delete, audit-preserving) |

A presence subscription is **a signed `MESSAGING` edge**. This closes the "XMPP auth ≠ our trust model"
gap directly: the thing that authorises seeing a peer's presence and receiving its stanzas is a
contact-book edge with cryptographic weight, not a server's say-so.

---

## 5. PubSub = type-multicast, RelayAdvertisement = signed/priced affiliation

XEP-0060 pubsub maps onto the SRS overlay, upgraded with signing + pricing:

| PubSub concept | SRS primitive |
|---|---|
| pubsub node | type-multicast group `ff03:WWWW:HHHH:IIII…` (= `deriveMulticastGroup`) |
| collection node hierarchy (XEP-0248) | SNS longest-prefix-match trie (WHAT ⊃ HOW ⊃ INST) |
| publisher affiliation / capability | `RelayAdvertisement { relayBca, typeHashPath, pricePerCellSats, subscriberSetReach, validNotBefore/After, sig }` |
| item (published payload) | a cell (`SignedBundle` body) |
| subscriber set | the `ff03` group membership (self-selected, no registry) |

Two things vanilla pubsub lacks and the SRS supplies for free:
1. **Price.** `pricePerCellSats` + `End.S.TICK` per hop — paid pubsub, not free fan-out.
2. **Signed reach commitment.** `subscriberSetReach` is a cryptographic claim about downstream
   subscribers, signed ECDSA-secp256k1 by `relayBca`.

So a `RelayAdvertisement` *is* "node X is an authorised, priced publisher/forwarder for this pubsub
node," carried on the overlay topic rather than asserted by a pubsub service.

---

## 6. Per-edge key rotation (BRC-42)

Each subscription/messaging edge carries a `signingKeyIndex` (BKDS invoice number, monotonic). Stanza
bodies between two parties are signed/locked under the **BRC-42 edge-domain rotated key**, not the root
identity key:

```
invoice  = protocolHash("BRC-42-edge-creation")[0:16] ‖ signingKeyIndex_le(8)
child_pk = recipientPk + HMAC-SHA256(ECDH(senderSk, recipientPk), invoice)·G
```

→ `deriveEdgeSk` / `buildRotatedLock` in `ecdh42.ts`. Privacy-per-edge and key rotation per stream fall
out of the existing primitive; no XMPP-specific key management.

---

## 7. NetworkAdapter conformance

`XmppNetworkAdapter implements NetworkAdapter` (`core/protocol-types/src/network.ts`):

| Method | XMPP realisation |
|---|---|
| `sendToNode(targetBCA, bytes)` | directed `<message to="…@[BCA]">` with `SignedBundle` body |
| `publish(object, opts)` | XEP-0060 publish to the type-multicast pubsub node |
| `subscribe(topic, cb)` | join the `ff03:…` group / subscribe to the (collection) node |
| `resolve(query)` | pubsub node discovery (XEP-0030) over the type-path prefix |
| `resolveBCA(address)` | JID-domain-as-IP-literal (routable case) or peer-locator lookup |
| `getNodeBCA()` | own BCA from `deriveBCABytes(identityPubkey, …)` |
| `isConnected()` | XMPP stream state |

This slots beside the existing `StubNetworkAdapter`, `BsvOverlayNetworkAdapter`, and the UDP-multicast
adapter. Per Phase-34's own note, the adapter interface stays the boundary — XMPP *adds* a transport,
it doesn't break the abstraction.

---

## 8. Where XMPP stops and SRv6 begins (layering discipline)

```
┌───────────────────────────────────────────────────────────────────────┐
│ IDENTITY/AUTH   SignedBundle: cert chain + ECDSA + nonce/timestamp      │  ← payload, unchanged
├───────────────────────────────────────────────────────────────────────┤
│ XMPP            presence (roster=ContactStore, sub=signed edge),        │  ← liveness + discovery
│                 directed <message> (unicast), PubSub (type-multicast),  │     + offline (MAM)
│                 MAM offline queue, Carbons multi-hat                    │
├───────────────────────────────────────────────────────────────────────┤
│ ROUTE (SRS)     unicast BCA SID ‖ type-multicast group;                 │  ← physical delivery
│                 SRv6 segment list = (BCA_i, TYPE_HASH_i) contracts      │
├───────────────────────────────────────────────────────────────────────┤
│ PROOF (BSV)     pushdrop anchors: routing decisions, per-hop ticks      │  ← audit
└───────────────────────────────────────────────────────────────────────┘
```

The SRv6 source route — the `(BCA_i, TYPE_HASH_i)` segment list and `End.S.*` functions — lives
*beneath* XMPP, not inside it. XMPP addresses *what* (JID/pubsub node = the meeting point: a type-
multicast address is simultaneously a routable group and a pubsub topic); SRv6 decides *the path and the
per-hop contract*. They meet exactly at the type-multicast address.

---

## 9. What XMPP adds that the SRS lacks today

- **Presence** → closes the documented *PeerStreamRegistry gap* (peers could deliver but not advertise
  streams). Presence + pubsub-node-advertisement is a 20-year-old standardised solution to precisely
  that gap.
- **Offline delivery (MAM, XEP-0313).** `POST /bundle` is synchronous — a sleeping brain drops the
  message. XMPP queues and delivers on reconnect. Directly relevant to brain-to-brain when one brain is
  intermittently online.
- **Carbons (XEP-0280)** → multi-hat / multi-resource sync without bespoke fan-out.

## 9b. What XMPP must NOT take over

- **Payment.** No payment leg in XMPP pubsub. Paid type-path routing stays on the BSV-overlay
  RelayAdvertisement plane + `End.S.TICK`.
- **Trust.** SASL/server trust is not our trust. `SignedBundle` cert-chain verification is mandatory and
  authoritative even when stream auth is present.
- **The path.** SRv6 segment contracts are not expressible as XMPP routing; keep them at the network
  layer.

---

## 10. Open questions

1. **Routable vs identity-only BCA.** The JID-domain-is-the-route unlock requires the BCA's subnet
   prefix to be a real allocation on the SRv6 locator plane. Until then, `resolveBCA` rides the existing
   peer-locator. Resolve alongside SRS open-question §10.1 (`ff15` scope reconciliation).
2. **Cross-WHAT (HOW-only) subscription.** `ff03::HHHH:HHHH::` ("every settle") is orthogonal to the
   WHAT⊃HOW⊃INST collection tree. Decide: parallel HOW-rooted collection hierarchy vs saved-search
   subscription vs a second pubsub service keyed on HOW.
3. **secp256k1 in TLS for SASL EXTERNAL.** s2s peers are our own nodes (both ends controlled), so a
   secp256k1 leaf cert is fine; confirm the chosen XMPP server/library accepts it, or run s2s plaintext
   and rely solely on payload `SignedBundle`.
4. **Server-ful vs serverless.** Start with a conventional XMPP server (ejabberd/Prosody) for the
   Bridget brain-to-brain test, or go straight to library-level s2s between brains? The HTTPS
   `brain.utxoengineer.com/api/v1/bundle` path stays primary for first contact; XMPP is the evolution.

---

## 11. Deliverables (`D-XMPP-*`)

Status: ✅ built + tested · ▢ designed, not yet built. Code lives in
`core/protocol-types/src/xmpp/` (+ wire types in `core/protocol-types/src/signed-bundle/types.ts`).
Test suite landed 2026-06-10: **50 tests across 5 files** in `xmpp/__tests__/`
(`bun test src/xmpp/__tests__/`, all green), validated under strict TS 5 +
`exactOptionalPropertyTypes`. The earlier "tested" claims are now backed by
real test files rather than aspirational.

- ✅ **`D-XMPP-jid-binding`** — `xmpp/jid.ts`. `jidForNode`/`parseJid` (`certId@[BCA]/hat`) +
  `bareJidForNode`/`parseBareJid` + `contextTagToResource` + `pubsubAddressForType`. String-only (caller
  formats the BCA via `bcaBytesToIPv6`, avoiding a layering inversion). Round-trip + validation +
  IPv6-case-normalisation tested (`__tests__/jid.test.ts`).
- ✅ **`D-XMPP-bundle-stanza`** — `xmpp/bundle-stanza.ts`. encode/decode `SignedBundle` ↔ `<message>`
  body (`urn:semantos:signed-bundle:1`). Transport uses ordinary JSON (canonical order only matters for
  the signature preimage, re-derived on receive). Adversarial-payload round-trip tested — literal
  `</bundle>`/`</message>` + the five XML entities in the payload survive byte-for-byte
  (`__tests__/bundle-stanza.test.ts`). v0.1 self-parser marked for `@xmpp/xml` swap at integration.
- ✅ **`D-XMPP-network-adapter`** — `xmpp/xmpp-network-adapter.ts`. `XmppNetworkAdapter implements
  NetworkAdapter` (§7) over an injected `XmppTransport` port; no stream-lib/`@bsv/sdk` dependency.
  End-to-end tested on the in-memory `StubXmppTransport` bus — directed-message routing by `[BCA]` host,
  pubsub publish→subscribe with 1024-byte cell round-trip, resolve over retained item history, and the
  housekeeping surface (`__tests__/xmpp-network-adapter.test.ts`). Honest limits: flat-node default group
  is now overridable (see `D-XMPP-pubsub-type`); `txid` = contentHash (no chain txid on the XMPP plane).
- ✅ **`D-XMPP-roster-bridge`** — `xmpp/roster-bridge.ts`. `buildRoster` (Contact → bare-JID item),
  active `MESSAGING` `EdgeRecord` → `subscription:"both"`, `decidePresenceSubscription`
  (approve/defer/deny — signed edge is the authoriser), `edgeRevocationTeardown`. Pure; type-only
  dependency on contact-book (no runtime cycle). Tested against a fake book — approve/defer/deny matrix +
  BCA-unresolvable routing + revocation teardown (`__tests__/roster-bridge.test.ts`).
- ✅ **`StubXmppTransport`** — `xmpp/stub-xmpp-transport.ts`. In-memory `XmppTransport` (the development
  tier, analogous to `StubNetworkAdapter`): an `InMemoryXmppBus` routes directed stanzas by `[BCA]` host
  and fans pubsub items out to joined subscribers, with retained item history for `resolve`. No stream
  lib, server, or socket — this is what makes the adapter end-to-end runnable + testable headless.
- ✅ **`D-XMPP-pubsub-type`** — `xmpp/pubsub-group-strategy.ts`. `buildTypeGroupTable` pre-derives the
  *real* Phase-34A `deriveMulticastGroup`/`whatPrefixGroup` (`mnca/srv6.ts`) so a pubsub node id IS the
  `ff<scope>:W:W:H:H:I:I:0000` type-multicast group, and a WHAT-prefix query joins the
  `ff<scope>:W:W::` collection node (subscribe to the whole domain). `makeTypeGroupStrategies` returns the
  sync `groupForObject`/`groupForQuery` the adapter accepts; unknown typeHashes degrade to the flat
  `urn:type:` node rather than dropping (`__tests__/pubsub-group-strategy.test.ts`). Remaining gap: the
  decomposition needs a `typeHash → TypeAxes` table supplied by the caller, because `PublishableObject`
  still carries only the composite typeHash — full XEP-0248 collection nesting awaits per-axis paths on
  the object.
- ▢ **`D-XMPP-relay-affiliation`** — surface `RelayAdvertisement` as the signed/priced pubsub publisher
  capability (overlay topic ↔ pubsub affiliation view).
- ▢ **real `XmppTransport` port** — a concrete `@xmpp/client` (or brain-native s2s) implementation of the
  same port `StubXmppTransport` already satisfies, so the adapter runs against a real ejabberd/Prosody
  for the Bridget brain-to-brain test. Needs infra + the SASL-EXTERNAL secp256k1 decision (§10.3); the
  in-memory stub above de-risks everything up to the wire.

The existing Phase-34 (`D34A.*`) and SRS (`D-SRS-*`) deliverables remain canonical; the `D-XMPP-*` set
is the identity-transport glue binding them to a federated, presence-aware, offline-capable messaging
surface.

---

## 12. Build tracker — brain-native s2s transport (serverless-first)

**Decision (2026-06-11): serverless-first.** No ejabberd/Prosody in the brain build. The brain already
owns every stateful thing a conventional XMPP server would provide — roster (ContactBook), trust
(SignedBundle cert chain), identity (BCA/cert), storage (cells) — so a server would duplicate four
subsystems and fork the trust model (§9b). A conventional server, if ever needed, is a SEPARATE sidecar
demoted to a dumb relay + offline-mailbox + presence-hub; never a build dependency. First contact between
two known brains with public endpoints needs no server at all — it's a persistent-connection upgrade of
the HTTPS `POST /api/v1/bundle` path that already works.

### 12.1 The four locked defaults

| # | Decision | Choice | Why |
|---|---|---|---|
| 1 | Framing | **XMPP-over-WebSocket** (RFC 7395-style) | Reuses the brain's existing WSS (`/api/v1/rpc`); no raw-socket handling in the Zig poll reactor. |
| 2 | Library | **Thin codec over the runtime's native WebSocket** (bun WS today; `ws` for a node host) | Keeps XMPP as dumb transport; `@xmpp/client` is c2s/server-shaped. Reuse the §3 `bundle-stanza` codec; swap to `@xmpp/xml` (ltx) only when the wire needs richer stanzas. |
| 3 | Stream auth | **Payload-only for v1** | `wss://` gives transport encryption; the `SignedBundle` cert chain + ECDSA IS the trust. Defers the SASL-EXTERNAL secp256k1 question (§10.3). |
| 4 | Placement | **TS runtime host** (`runtime/session-protocol`), brain reached over its bundle seam | Keeps the Zig brain pure; avoids the single-threaded-reactor self-call deadlock (inbound stanzas are processed arms-length, never re-entering the reactor synchronously). `createXmppNode` already lives here. |

### 12.2 Deliverables (`D-XMPP-s2s-*`)

Status: ✅ built + tested · ◐ minimal slice landed · ▢ designed, not yet built.

- ◐ **`D-XMPP-s2s-ws`** — `WsXmppTransport`: a real `XmppTransport` over the runtime's native WebSocket
  (server-accept + client-dial), a hello-handshake connection registry keyed by host literal,
  directed-`<message>` routing by `to="[BCA]"`, presence/liveness, and a gossip pubsub fan-out — reusing
  the `bundle-stanza` codec, no new deps. `createXmppNode` runs unchanged against it. Two-peer real-socket
  loopback integration tested.
- ▢ **`D-XMPP-s2s-bridget`** — point a `WsXmppTransport` at Bridget's brain
  (`brain.utxoengineer.com`, cert `a2a3ea74…`), exchange a real signed dispatch + response. The gating
  live test. Needs both brains online in one window + the brain-side inbound verify (`signed_bundle.zig`)
  wired to the WS arrival path.
- ▢ **`D-XMPP-s2s-mam`** — cell-backed offline mailbox + `fetchItems` history (MAM-equivalent) so a
  dispatch to a sleeping brain queues and flushes on reconnect.
- ▢ **`D-XMPP-s2s-sasl`** — OPTIONAL SASL-EXTERNAL secp256k1 stream auth, only if stream-level auth is
  ever wanted on top of payload trust.

### 12.3 The arc

minimal slice (`D-XMPP-s2s-ws`, ◐) → run Bridget (`D-XMPP-s2s-bridget`) → cell-backed MAM/offline →
SASL-EXTERNAL only if needed. The in-memory `StubXmppTransport` de-risked everything up to the wire; the
`WsXmppTransport` is the same port over real sockets; the only delta to go live is pointing it at a peer.
