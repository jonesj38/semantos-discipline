---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/RTC-ROADMAP.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.712514+00:00
---

# Semantos RTC Roadmap — voice / video / metered streaming

**Version**: 0.1 (draft)
**Date**: 2026-06-11
**Status**: Living progress tracker. Update `docs/canon/rtc-matrix.yml` as cells move ✗ → ⚠ → ✓; the §2 tables below regenerate from it.
**Matrix**: `docs/canon/rtc-matrix.yml` · **Renderer**: `docs/canon/render/rtc-to-roadmap.ts` · **Gate**: `tests/gates/rtc-matrix-render-freshness.test.ts`
**Source materials**: the XMPP/Jingle integration (`core/protocol-types/src/xmpp/`, `runtime/session-protocol/src/xmpp-node/`, SRS §12), the paid swarm cartridge (`runtime/session-protocol/src/swarm`, `cartridges/swarm/brain`), the contacts/PKI + SignedBundle trust payload, and the skyminer N=8 IPv6 multicast mesh.

> **North star** — real-time calling is a *shell-native primitive*, not a cartridge. One importable RTC substrate (signalling / transport / media / fan-out / E2EE / metering) that every calling surface binds into: 1:1, group rooms, telehealth, betterment check-ins, oddjobz site walk-throughs, a jam-room video layer. The same way streams + the conversation engine ship native in the shell and cartridges expose typed surfaces *into* them — never reimplementing the primitive.

---

## 1. What this document is

A single-page picture of where each RTC surface stands against each conformance axis, plus the phased ordering that closes the gaps. Read it before any calling/streaming work; update the matrix after.

The thesis the matrix exists to defend: **the distinguishing property is not the transport — WebRTC is standard — it is (a) PKI-authenticated media sessions and (b) an SFU that is really a paid pubsub relay settled on BSV.** Everything else is assembling well-understood parts in the right topology.

The matrix is split into two groups, exactly like the unification matrix:

- **Substrate (S1–S7)** — the shell-native primitives whose job *is* to implement an axis. ✓-by-construction is the goal; a non-✓ owned axis is a bug against the primitive's own spec. Cartridges import these.
- **Adapters (A1–A5)** — cartridges that consume the substrate to deliver a user-facing calling capability. This is where ⚠/✗ cluster and where product work lands. None reimplement the media stack.

Status legend: **✓** done & verifiable · **⚠** partial / existing substrate gives a head start · **✗** not started · **n/a** not meaningful for this (surface, axis) pair.

---

## 2a. The signalling / media seam (read this before the matrix)

The single load-bearing design decision, which the row structure encodes:

| Concern | Carrier | Why |
|---|---|---|
| **Signalling** (SDP offer/answer + ICE trickle) | **Jingle over the WsXmppNode (WSS)** | Low-volume, reliable, bursty — TCP-friendly. Jingle (XEP-0166/0167/0176) is the standardised mapping. The carrier already exists. |
| **Media** (audio/video) | **WebRTC SRTP over UDP**, established by ICE | Real-time media wants loss-tolerant UDP + its own congestion control. **Never WSS** — TCP head-of-line blocking wrecks latency. TURN-TCP is the degraded fallback only. |
| **Auth** | **DTLS `a=fingerprint` pinned into the SignedBundle** | The PKI authenticates the media session end-to-end; the brain is a relay it cannot MITM. The differentiator. |
| **Fan-out** | **topology is a choice** | mesh (small) · SFU (scale = paid-pubsub-for-RTP) · broadcast/VOD (latency-tolerant = the existing paid swarm). |
| **Money** | **per-byte settlement on the cell/BSV rail** | An SFU is a forwarding relay; metering forwarded bytes reuses the swarm's per-chunk pattern. Paid SFU on BSV is the novel combination. |

"RTC over WSS" is therefore only true of *signalling*. Media leaves WSS by design.

---

<!-- GENERATED:matrix-start (rtc renderer-in-loop; do not edit between markers) -->
## §2. The matrix

> Rendered from `docs/canon/rtc-matrix.yml`. Do not edit this section
> directly — edit the YAML and re-run
> `bun docs/canon/render/rtc-to-roadmap.ts`.
### §2a. Substrate (the shell-native primitives — ✓ by construction is the goal)

| Surface | A. PKI | B. Signal | C. ICE | D. Media | E. Topo | F. E2EE | G. Meter | H. ShellAPI | I. Test | J. Docs |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| **S1 Signalling Plane (rtc.signal)** | ⚠ D-RTC-S1-A | ✓ D-RTC-S1-B | n/a | n/a | n/a | n/a | n/a | ✓ D-RTC-S1-H | ✓ D-RTC-S1-I | ⚠ D-RTC-S1-J |
| **S2 ICE / Transport (rtc.ice)** | n/a | n/a | ✗ D-RTC-S2-C | n/a | n/a | n/a | n/a | ✗ D-RTC-S2-H | ✗ D-RTC-S2-I | ✗ D-RTC-S2-J |
| **S3 Media Pipeline (rtc.media)** | n/a | n/a | n/a | ✗ D-RTC-S3-D | n/a | ⚠ D-RTC-S3-F | n/a | ✗ D-RTC-S3-H | ✗ D-RTC-S3-I | ✗ D-RTC-S3-J |
| **S4 SFU Relay (rtc.sfu)** | n/a | n/a | ⚠ D-RTC-S4-C | ✗ D-RTC-S4-D | ✗ D-RTC-S4-E | n/a | ⚠ D-RTC-S4-G | ✗ D-RTC-S4-H | ✗ D-RTC-S4-I | ✗ D-RTC-S4-J |
| **S5 E2EE Group Keying (rtc.crypto)** | ⚠ D-RTC-S5-A | n/a | n/a | n/a | n/a | ✗ D-RTC-S5-F | n/a | ✗ D-RTC-S5-H | ✗ D-RTC-S5-I | ✗ D-RTC-S5-J |
| **S6 Metering Rail (rtc.meter)** | n/a | n/a | n/a | n/a | n/a | n/a | ⚠ D-RTC-S6-G | ✗ D-RTC-S6-H | ✗ D-RTC-S6-I | ✗ D-RTC-S6-J |
| **S7 Shell RTC API (rtc/index.ts)** | n/a | n/a | n/a | n/a | n/a | n/a | n/a | ⚠ D-RTC-S7-H | ✓ D-RTC-S7-I | ⚠ D-RTC-S7-J |

### §2b. Adapters (cartridges that import the substrate — where the work concentrates)

| Surface | A. PKI | B. Signal | C. ICE | D. Media | E. Topo | F. E2EE | G. Meter | H. ShellAPI | I. Test | J. Docs |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| **A1 1:1 Call** | ⚠ D-RTC-A1-A | ✗ D-RTC-A1-B | ✗ D-RTC-A1-C | ✗ D-RTC-A1-D | n/a | ⚠ D-RTC-A1-F | n/a | ✗ D-RTC-A1-H | ✗ D-RTC-A1-I | ✗ D-RTC-A1-J |
| **A2 Small-Group Mesh (<=4)** | ⚠ D-RTC-A2-A | ✗ D-RTC-A2-B | ✗ D-RTC-A2-C | ✗ D-RTC-A2-D | ✗ D-RTC-A2-E | ⚠ D-RTC-A2-F | n/a | ✗ D-RTC-A2-H | ✗ D-RTC-A2-I | ✗ D-RTC-A2-J |
| **A3 SFU Room (group)** | ✗ D-RTC-A3-A | ✗ D-RTC-A3-B | ✗ D-RTC-A3-C | ✗ D-RTC-A3-D | ✗ D-RTC-A3-E | ✗ D-RTC-A3-F | ✗ D-RTC-A3-G | ✗ D-RTC-A3-H | ✗ D-RTC-A3-I | ✗ D-RTC-A3-J |
| **A4 Broadcast / VOD (swarm-backed)** | ⚠ D-RTC-A4-A | n/a | n/a | ✓ D-RTC-A4-D | ✓ D-RTC-A4-E | ⚠ D-RTC-A4-F | ⚠ D-RTC-A4-G | ✓ D-RTC-A4-H | ✓ D-RTC-A4-I | ✗ D-RTC-A4-J |
| **A5 Skyminer Local Multicast (mesh demo)** | ✗ D-RTC-A5-A | n/a | ⚠ D-RTC-A5-C | ✗ D-RTC-A5-D | ⚠ D-RTC-A5-E | ✗ D-RTC-A5-F | n/a | ✗ D-RTC-A5-H | ✗ D-RTC-A5-I | ✗ D-RTC-A5-J |

---

_7 substrate rows, 5 adapter rows._
_Cells: 8 ✓ · 18 ⚠ · 50 ✗ · 44 n/a — 11% done, 34% started (of 76 in-scope cells)._
<!-- GENERATED:matrix-end -->

---

## 3. The signalling mapping (S1 in detail)

Jingle is the standardised WebRTC-over-XMPP signalling vocabulary; the WsXmppNode already carries arbitrary stanzas, so S1 is a codec + a small state machine, not new transport.

| Jingle action (XEP-0166) | Carries | Maps to WebRTC |
|---|---|---|
| `session-initiate` | SDP offer + initial ICE candidates + `a=fingerprint` | `setLocalDescription(offer)` on the caller; fingerprint pinned into the SignedBundle |
| `session-accept` | SDP answer + candidates + callee fingerprint | `setRemoteDescription(answer)` |
| `transport-info` | one trickled ICE candidate | `addIceCandidate(...)` |
| `session-terminate` | reason | `close()` |

**The pin (axis A).** When `session-initiate` arrives, S1 verifies the sender's contact cert from the SignedBundle and records the SDP `a=fingerprint`. Media only proceeds if the DTLS handshake's certificate fingerprint equals the pinned value. This removes trust in the signalling server: a tampered relay cannot substitute its own media endpoint without breaking the fingerprint match.

---

## 4. The shell import contract (S7 — "part of the shell, cartridges import it")

The deliverable Todd called out: **this lives in the shell and cartridges import it.** Concretely, a single module:

```
runtime/session-protocol/src/rtc/
  index.ts          # the public surface — re-exports the six below
  signal.ts         # S1  rtc.signal   — placeCall / answer / addCandidate / hangup
  ice.ts            # S2  rtc.ice      — STUN/TURN config, candidate gathering
  media.ts          # S3  rtc.media    — localStream / addTrack / onRemoteTrack
  sfu.ts            # S4  rtc.sfu      — joinRoom / publish / subscribe (brain cartridge client)
  crypto.ts         # S5  rtc.crypto   — createGroup / addMember / removeMember / frameKey
  meter.ts          # S6  rtc.meter    — openMeter / report / settle
```

The contract cartridges bind (sketch — the actual seam is D-RTC-S7-H):

```ts
import { rtc } from '@semantos/session-protocol/rtc';

// 1:1 — A1
const call = await rtc.signal.placeCall(contactCert, { audio: true, video: true });
call.onRemoteTrack(track => attach(track));

// group room — A3
const room = await rtc.sfu.joinRoom(roomCert);   // metered + MLS/SFrame under the hood
room.publish(rtc.media.localStream());
room.onParticipant(p => attach(p.track));
```

**The structural guarantee (axis H + D-RTC-S7-I).** A one-way-dependency gate: `cartridges/* → rtc`, never `rtc → cartridges/*`. This is the exact pattern the XMPP substrate one-way-dep gate already enforces — RTC reuses it. Cartridges express *what* (typed surfaces, UI, FSM verbs); the shell owns *how* (the media stack). No cartridge re-implements signalling, ICE, SRTP, the SFU client, MLS, or metering.

This is why it is substrate, not a cartridge: telehealth, betterment check-ins, oddjobz walk-throughs, and a jam-room video layer are all *different cartridges* that need the *same* calling primitive. Building it once in the shell is the whole point.

---

## 5. Phased ordering (the work plan)

Each phase is a coherent slice that ships a usable capability and lights up a band of cells.

| Phase | Ships | Rows advanced | New infra |
|---|---|---|---|
| **P1 — 1:1 calls** | Jingle signalling + one PeerConnection + ICE; fingerprint pinned to the SignedBundle. Pure P2P. | S1, S2, S3, **A1** | none (brain hosts STUN/TURN) |
| **P2 — small group mesh (≤4)** | N peer connections, same signalling. The "everyone sends to everyone" shape, at the size where it's correct. | **A2** | none |
| **P3 — SFU room** | SFU brain cartridge (forward fan-out), metered on the cell/BSV rail, relay-blind via MLS+SFrame. The flagship paid-SFU-on-BSV surface. | S4, S5, S6, **A3** | SFU cartridge (mirrors `cartridges/swarm/brain`) |
| **P4 — broadcast / VOD** | Media-segmenter feeding the existing paid swarm; paid HLS/DASH chunks. Latency-tolerant one-to-many. | **A4** | media segmenter only (swarm exists) |
| **P5 — skyminer multicast demo** | Real IPv6 multicast video over the proven N=8 mesh. Local-mesh showcase. | **A5** | none (mesh exists) |

Sequencing notes:
- **P1 first** because it ships the PKI-authenticated-call differentiator on the smallest possible surface — and S1/S2/S3 are reused by every later phase.
- **TURN** is still needed for the ~10–20% of P1/P2 flows behind symmetric NAT (brain can host coturn). P3's SFU public IP becomes the rendezvous and obviates separate TURN for group flows.
- **P4 is mostly already built** — the swarm chunk distribution + per-chunk metering ship today (paid-swarm M0–M9); the gap is a media segmenter and a thin broadcast helper on the `rtc` surface. It can run in parallel with P1–P3 since it shares no WebRTC code.
- **P3 carries the most novelty and the most risk** (SFU + MLS + SFrame + metering); do not start it before P1's S1/S2/S3 are green.

---

## 6. The VPN-multicast idea — where it lands and where it doesn't

Todd's instinct — "spin up a quick VPN and everyone multicasts" — is captured honestly as row **A5**, scoped to the local mesh:

- **True IP multicast does not traverse the public internet** (no inter-AS multicast routing). For geographically distributed participants, "multicast" collapses into either **mesh** (replicated unicast at the sender = A2) or **SFU** (replicated at a relay = A3). A per-call WireGuard overlay gives a flat address space but **does not change the bandwidth math** — replicated unicast at the sender is still mesh — and adds NAT-traversal + key-exchange overhead that WebRTC's ICE already solves better for media.
- **On the skyminer N=8 IPv6 multicast mesh it genuinely works** and is a distinctive demo: real multicast video over the proven local mesh. That is row A5's scope — a *different regime* from internet calls, tracked separately on purpose.

So: don't build the VPN for internet calls (ICE + SFU strictly dominate it and reuse infrastructure). Do build multicast video on the skyminer mesh as a showcase.

---

## 7. What this matrix deliberately does NOT claim

- **No media in cells.** Audio/video frames ride native SRTP. The 1024-byte cell carries signalling, the fingerprint commitment, and metering receipts — never video frames (the cell is a storage/content/payment quantum; per-frame wrapping is wrong overhead). Inverse of the usual "cell is fine for bulk" point.
- **No interactive calls over the swarm.** The swarm's store-and-forward + per-cell payment latency is correct for A4 (broadcast/VOD, 1–2s tolerable) and wrong for A1–A3 (sub-150ms interactive).
- **No ✓ yet.** Nothing RTC-specific is built and tested; the ⚠ cells mark existing substrate (WsXmppNode, paid swarm, SignedBundle/PKI, skyminer mesh) that gives a head start, not completed RTC work.

---

## 8. Cross-references

- **Signalling carrier**: the XMPP/Jingle integration — SRS §12, `core/protocol-types/src/xmpp/`, `runtime/session-protocol/src/xmpp-node/`.
- **Metering + broadcast substrate**: the paid swarm — `runtime/session-protocol/src/swarm`, `cartridges/swarm/brain`.
- **Auth payload**: contacts/PKI + SignedBundle (the trust payload that the fingerprint pins into).
- **Local multicast**: the skyminer N=8 IPv6 mesh (Phase U.2 reference).
- **Authorization substrate**: the Engine-Checked Data Access plan (`access.grant` cell-type family + verify `.handler` on the real 2-PDA via the `ScriptContextBuilder` seam). This is the *authorization* half of axis A: a contact is **admitted** to a stream/room by an engine-checked grant against their edge-derived key, evaluated at subscribe/join time. A4's swarm serve gate is literally that plan's deferred Transfer-integration slice; S5's MLS membership source is the grant. Interactive calls want a `SESSION_ACCESS` sibling to file-share's `DATA_ACCESS`. See `docs/canon/cross-matrix-index.md` cross-cutting deferrals.
- **Cross-matrix index**: `docs/canon/cross-matrix-index.md` (RTC is the sixth matrix lens).
