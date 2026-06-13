---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/canon/rtc-matrix.yml
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.630528+00:00
---

# docs/canon/rtc-matrix.yml

```yml
# The RTC Matrix — tracking artifact for real-time communication
# (voice / video / metered streaming) as a shell-native substrate.
#
# Schema parallel to docs/canon/unification-matrix.yml and
# docs/canon/singularity-matrix.yml. Rendered via
# docs/canon/render/rtc-to-roadmap.ts into the §2 tables of
# docs/prd/RTC-ROADMAP.md. Edit THIS file; never hand-edit the rendered
# block in the roadmap. The tests/gates/rtc-matrix-render-freshness.test.ts
# gate re-runs the renderer at test-time and asserts no drift.
#
# Companion design document: docs/prd/RTC-ROADMAP.md.
#
# ── Thesis ───────────────────────────────────────────────────────────
# Real-time calling is NOT a cartridge. It is a shell-native primitive
# (like streams + the conversation engine) that many cartridges import:
# 1:1 calls, group rooms, telehealth, betterment check-ins, oddjobz site
# walk-throughs, a jam-room video layer, etc. The substrate rows below
# are the importable kernel (`runtime/session-protocol/src/rtc/`); the
# adapter rows are cartridges that bind a typed surface INTO it and never
# reimplement the media stack.
#
# The architecture splits cleanly along the signalling/media seam:
#   • signalling  → Jingle (XEP-0166/0167/0176) over the existing
#                   WsXmppNode (WSS). Low-volume, reliable, TCP-friendly.
#   • media       → WebRTC SRTP over UDP, established by ICE/STUN/TURN.
#                   NEVER on WSS (TCP head-of-line blocking wrecks RTT);
#                   TURN-TCP is the degraded fallback only.
#   • auth        → the call's DTLS fingerprint is pinned into the
#                   SignedBundle, so the PKI authenticates the media
#                   session end-to-end and the brain can be a dumb relay
#                   it cannot MITM. This is the distinguishing property.
#   • fan-out     → topology is a choice, not a constant: mesh (small),
#                   SFU (scale, = paid-pubsub-for-RTP relay), broadcast
#                   /VOD (latency-tolerant, rides the existing paid swarm).
#   • money       → an SFU is a forwarding relay; metering forwarded bytes
#                   and settling on the cell/BSV rail reuses the swarm's
#                   metering pattern. Paid SFU on BSV is the novel combo.
#
# ── Axes (columns) ───────────────────────────────────────────────────
#   A. PKI       — DTLS a=fingerprint pinned into the SignedBundle; the
#                  call is authenticated by the contacts/cert system, not
#                  by trust in the signalling server.
#   B. Signal    — Jingle/SDP offer-answer + ICE-candidate trickle carried
#                  over the WsXmppNode (WSS).
#   C. ICE       — STUN reflexive discovery + TURN relay fallback; a real
#                  UDP media path is established across NATs.
#   D. Media     — SRTP audio/video pipeline; codec negotiation
#                  (Opus / VP8 / VP9 / AV1 / H.264); congestion control.
#   E. Topo      — correct fan-out shape realised for the surface
#                  (mesh / SFU forward / broadcast distribution).
#   F. E2EE      — MLS (RFC 9420) group key + SFrame per-frame encryption,
#                  so an SFU forwards ciphertext it cannot read.
#   G. Meter     — per-byte / per-second settlement on the cell/BSV rail
#                  (paid SFU forwarding; paid swarm chunk delivery).
#   H. ShellAPI  — exposed via the shell-native import surface
#                  (`runtime/session-protocol/src/rtc/`); cartridges bind
#                  a typed surface, they do NOT reimplement the stack.
#   I. Test      — conformance test / live verification.
#   J. Docs      — design doc section + glossary entry.
#
# ── Status legend ────────────────────────────────────────────────────
#   ✓   — implemented, tested, verifiable
#   ⚠   — partial / in progress / existing substrate gives a head start
#   ✗   — not started
#   n/a — not applicable for this surface/axis pair
#
# Deliverable IDs use the D-RTC-{S|A}{n}-{axis} pattern. Cross-reference
# existing deliverable IDs from other matrices where a head start exists.

# ─────────────────────────────────────────────────────────────────────
# SUBSTRATE — the shell-native primitives. ✓-by-construction is the goal;
# each row owns one axis and is a bug against its own spec if that axis
# is not ✓. Cartridges import these; they are not cartridges themselves.
# ─────────────────────────────────────────────────────────────────────
substrate:
  - id: S1
    name: Signalling Plane (rtc.signal)
    note: |
      Jingle (XEP-0166 session / -0167 RTP / -0176 ICE-UDP) carried as
      stanzas over the existing WsXmppNode. This is the call-setup channel:
      SDP offer/answer + trickled ICE candidates. The carrier already
      exists (WsXmppNode, brain-native s2s over WSS, merged main #974);
      what is missing is the Jingle stanza vocabulary and the
      offer/answer/candidate state machine. The DTLS fingerprint that
      rides in the SDP is pinned into the SignedBundle here — that wiring
      is what makes axis A meaningful on every downstream row.
    axes:
      A:
        status: "⚠"
        deliverable: D-RTC-S1-A
        note: "Pin store + fail-closed verify gate built + tested (RTC-1 #984); fingerprint rides as the rtc.jingle SignedBundle payload (xmpp-signal-channel). End-to-end enforcement still pending — the observed DTLS fingerprint comes from S3's real handshake, and the bundle signature/cert-chain verify is the live brain's (signed_bundle.zig)."
      B:
        status: "✓"
        deliverable: D-RTC-S1-B
        note: "Jingle stanza codec + offer/answer/trickle FSM built + tested over an in-memory channel (RTC-1 #984), carried on the WsXmppNode WSS carrier (#974)."
      C:
        status: "n/a"
        note: "ICE candidate exchange is signalled here but established by S2."
      D:
        status: "n/a"
        note: "No media on the signalling plane — setup only."
      E:
        status: "n/a"
        note: "Topology is negotiated in signalling but realised by S3/S4."
      F:
        status: "n/a"
        note: "E2EE key agreement is signalled but owned by S5."
      G:
        status: "n/a"
        note: "Signalling is not metered (low volume)."
      H:
        status: "✓"
        deliverable: D-RTC-S1-H
        note: "rtc.signal surface (placeCall / answer / addCandidate / hangup) shipped on the shell import module (RTC-1 #984)."
      I:
        status: "✓"
        deliverable: D-RTC-S1-I
        note: "Full offer/answer/trickle/hangup round-trip + fingerprint-pin tests over an in-memory channel pair (RTC-1 #984, 22 unit tests)."
      J:
        status: "⚠"
        deliverable: D-RTC-S1-J
        note: "This roadmap §3 documents the Jingle mapping; glossary entry for 'Jingle session' pending."

  - id: S2
    name: ICE / Transport (rtc.ice)
    note: |
      STUN server-reflexive candidate discovery + TURN relay fallback for
      the ~10-20% of peers behind symmetric NAT. Establishes the actual
      UDP media path between endpoints. The brain can host coturn (or an
      equivalent) as the TURN/STUN endpoint; once group mode (S4 SFU) is
      in play the SFU's public IP is itself the rendezvous and obviates a
      separate TURN for those flows.
    axes:
      A:
        status: "n/a"
        note: "Identity binding happens in S1/S5, not at the ICE layer."
      B:
        status: "n/a"
        note: "Candidates are signalled by S1; S2 gathers and validates them."
      C:
        status: "✗"
        deliverable: D-RTC-S2-C
        note: "STUN reflexive gathering + TURN relay; coturn (or equiv) hosted on the brain. The core unbuilt transport primitive."
      D:
        status: "n/a"
        note: "ICE carries media but does not encode it (S3)."
      E:
        status: "n/a"
      F:
        status: "n/a"
      G:
        status: "n/a"
        note: "TURN relay bytes COULD be metered later; out of scope for the primitive."
      H:
        status: "✗"
        deliverable: D-RTC-S2-H
        note: "rtc.ice config surface (STUN/TURN URLs, credentials) on the shell module."
      I:
        status: "✗"
        deliverable: D-RTC-S2-I
        note: "Candidate-gathering test against a local STUN; symmetric-NAT TURN-fallback test."
      J:
        status: "✗"
        deliverable: D-RTC-S2-J

  - id: S3
    name: Media Pipeline (rtc.media)
    note: |
      The WebRTC PeerConnection itself: SRTP audio/video, codec
      negotiation (Opus for audio; VP8/VP9/AV1/H.264 for video), and
      congestion control (transport-cc / GCC). Media rides native SRTP
      over the UDP path from S2 — it is NEVER wrapped per-packet in the
      1024-byte cell format (too much overhead; the cell is a
      storage/content/payment quantum, not a media-frame container). The
      cell layer carries signalling, the fingerprint commitment, and
      metering receipts — not video frames.
    axes:
      A:
        status: "n/a"
        note: "DTLS handshake exposes the fingerprint; pinning is S1's job."
      B:
        status: "n/a"
      C:
        status: "n/a"
        note: "Consumes the path from S2."
      D:
        status: "✗"
        deliverable: D-RTC-S3-D
        note: "PeerConnection lifecycle, SRTP, codec negotiation, getUserMedia capture. The core media primitive."
      E:
        status: "n/a"
        note: "A single PeerConnection is point-to-point; fan-out is S4."
      F:
        status: "⚠"
        deliverable: D-RTC-S3-F
        note: "DTLS-SRTP gives hop encryption for free; group E2EE-through-relay (SFrame insertable streams) is S5."
      G:
        status: "n/a"
      H:
        status: "✗"
        deliverable: D-RTC-S3-H
        note: "rtc.media surface (localStream / addTrack / onRemoteTrack) on the shell module."
      I:
        status: "✗"
        deliverable: D-RTC-S3-I
        note: "Loopback PeerConnection media-flow test."
      J:
        status: "✗"
        deliverable: D-RTC-S3-J

  - id: S4
    name: SFU Relay (rtc.sfu)
    note: |
      A Selective Forwarding Unit as a brain cartridge: each participant
      uploads ONE stream; the SFU forwards it to the others without
      decode/re-encode (no transcoding cost). This is the scale topology
      (dozens) and is structurally identical to the paid swarm relay — an
      SFU is paid-pubsub for RTP. The relay self-selects on the call's
      type-path (the 'cell routing is paid pubsub' model). With SFrame
      (S5) the relay forwards ciphertext it cannot read. Metering forwarded
      bytes (G) reuses the swarm's per-chunk settlement pattern.
    axes:
      A:
        status: "n/a"
        note: "The SFU never sees plaintext (S5); auth is end-to-end via S1/S5."
      B:
        status: "n/a"
      C:
        status: "⚠"
        deliverable: D-RTC-S4-C
        note: "SFU public IP is its own rendezvous (obviates separate TURN for group flows); ingest/egress RTP plumbing unbuilt."
      D:
        status: "✗"
        deliverable: D-RTC-S4-D
        note: "RTP ingest + selective forward (simulcast/SVC layer selection) without transcode."
      E:
        status: "✗"
        deliverable: D-RTC-S4-E
        note: "The forward fan-out itself. Owns the SFU topology axis."
      F:
        status: "n/a"
        note: "Relay forwards SFrame ciphertext; keying is S5."
      G:
        status: "⚠"
        deliverable: D-RTC-S4-G
        note: "Swarm metering pattern (paid-swarm M0-M9) is reusable; metering forwarded RTP bytes onto the cell/BSV rail is unbuilt."
      H:
        status: "✗"
        deliverable: D-RTC-S4-H
        note: "rtc.sfu surface (joinRoom / publish / subscribe) on the shell module; brain-side cartridge mirrors swarm/brain."
      I:
        status: "✗"
        deliverable: D-RTC-S4-I
        note: "3-party forward test; metering-receipt assertion."
      J:
        status: "✗"
        deliverable: D-RTC-S4-J

  - id: S5
    name: E2EE Group Keying (rtc.crypto)
    note: |
      MLS (RFC 9420) for group key agreement + SFrame for per-frame media
      encryption, so an SFU (S4) forwards ciphertext. The contacts/PKI
      supply membership and authentication; MLS supplies the ratcheting
      group key; SFrame applies it per frame via WebRTC insertable streams.
      This is where 1:1 DTLS-SRTP (free in S3) extends to authenticated,
      relay-blind group calls.
    axes:
      A:
        status: "⚠"
        deliverable: D-RTC-S5-A
        note: |
          Membership + auth source for the MLS group. Canonical form is the
          engine-checked access.grant (DATA_ACCESS / a SESSION_ACCESS sibling)
          evaluated on the real 2-PDA — NOT an app-layer cert check. The grant
          (grantee = contact's edge-derived key) is the admission decision that
          seeds the MLS group; see docs/canon/cross-matrix-index.md cross-cutting
          deferrals (Engine-Checked DATA_ACCESS access-grant). Binding unbuilt.
      B:
        status: "n/a"
        note: "MLS handshake messages are signalled via S1."
      C:
        status: "n/a"
      D:
        status: "n/a"
        note: "Encrypts media from S3; does not produce it."
      E:
        status: "n/a"
      F:
        status: "✗"
        deliverable: D-RTC-S5-F
        note: "MLS group + SFrame per-frame encryption via insertable streams. Owns the E2EE axis."
      G:
        status: "n/a"
      H:
        status: "✗"
        deliverable: D-RTC-S5-H
        note: "rtc.crypto surface (createGroup / addMember / removeMember / frameKey) on the shell module."
      I:
        status: "✗"
        deliverable: D-RTC-S5-I
        note: "Member add/remove ratchet test; relay-cannot-decode assertion."
      J:
        status: "✗"
        deliverable: D-RTC-S5-J

  - id: S6
    name: Metering Rail (rtc.meter)
    note: |
      Per-byte / per-second settlement of relayed media on the cell/BSV
      micropayment rail. The paid swarm already proves the pattern (meter
      chunk delivery, settle per chunk); S6 applies it to two flows: SFU
      forwarded RTP bytes (interactive) and swarm media chunks (broadcast
      /VOD). Per Craig's stance, the source pre-signs commitments for
      whole routes rather than per-hop minting on relays.
    axes:
      A:
        status: "n/a"
      B:
        status: "n/a"
      C:
        status: "n/a"
      D:
        status: "n/a"
      E:
        status: "n/a"
      F:
        status: "n/a"
      G:
        status: "⚠"
        deliverable: D-RTC-S6-G
        note: "Cell/BSV payment rail + swarm per-chunk receipts exist; a metering meter for RTP-bytes/seconds + the pre-signed-route commitment shape is unbuilt. Owns the metering axis."
      H:
        status: "✗"
        deliverable: D-RTC-S6-H
        note: "rtc.meter surface (openMeter / report / settle) on the shell module."
      I:
        status: "✗"
        deliverable: D-RTC-S6-I
        note: "Metered-second accounting test; settlement-receipt round-trip."
      J:
        status: "✗"
        deliverable: D-RTC-S6-J

  - id: S7
    name: Shell RTC API (rtc/index.ts)
    note: |
      THE import surface. A single shell-native module at
      `runtime/session-protocol/src/rtc/` that re-exports the typed
      surfaces of S1-S6 (signal / ice / media / sfu / crypto / meter) as
      one coherent contract. Cartridges import THIS; they never reach into
      a media library directly. Mirrors how streams + the conversation
      engine are shell-native (cartridges expose typed surfaces INTO them).
      A one-way-dependency gate (cartridge → rtc, never rtc → cartridge)
      is the structural guarantee, parallel to the xmpp substrate gate.
    axes:
      A:
        status: "n/a"
        note: "Aggregates the substrate surfaces; owns no protocol axis itself."
      B:
        status: "n/a"
      C:
        status: "n/a"
      D:
        status: "n/a"
      E:
        status: "n/a"
      F:
        status: "n/a"
      G:
        status: "n/a"
      H:
        status: "⚠"
        deliverable: D-RTC-S7-H
        note: "The `rtc/` import module exists with the S1 signal surface re-exported (RTC-1 #984); the ice/media/sfu/crypto/meter surfaces are not yet present. Seam + barrel established."
      I:
        status: "✓"
        deliverable: D-RTC-S7-I
        note: "Substrate one-way-dep gate shipped + passing (tests/gates/rtc-substrate-one-way-dep.test.ts): cartridge → rtc allowed, rtc → cartridge rejected (RTC-1 #984)."
      J:
        status: "⚠"
        deliverable: D-RTC-S7-J
        note: "This roadmap §4 specifies the import contract; module README pending."

# ─────────────────────────────────────────────────────────────────────
# ADAPTERS — cartridges that consume the substrate to deliver a
# user-facing calling capability. This is where ⚠ and ✗ cluster and
# where most product work lands. None reimplement the media stack; each
# binds a typed surface from S7.
# ─────────────────────────────────────────────────────────────────────
adapters:
  - id: A1
    name: 1:1 Call
    note: |
      Phase-1 deliverable. Pure peer-to-peer: Jingle signalling (S1) +
      one PeerConnection (S3) + ICE (S2), DTLS fingerprint pinned to the
      SignedBundle (the PKI-authenticated-call differentiator). No media
      server. Ships the auth story immediately on the smallest surface.
    axes:
      A:
        status: "⚠"
        deliverable: D-RTC-A1-A
        note: "Depends on S1-A fingerprint pinning; cert system ready."
      B:
        status: "✗"
        deliverable: D-RTC-A1-B
        note: "Depends on S1 Jingle FSM."
      C:
        status: "✗"
        deliverable: D-RTC-A1-C
      D:
        status: "✗"
        deliverable: D-RTC-A1-D
      E:
        status: "n/a"
        note: "Point-to-point; no fan-out."
      F:
        status: "⚠"
        deliverable: D-RTC-A1-F
        note: "DTLS-SRTP hop encryption suffices for 1:1; no SFU to blind."
      G:
        status: "n/a"
        note: "No relay to meter in pure P2P."
      H:
        status: "✗"
        deliverable: D-RTC-A1-H
        note: "Binds rtc.signal + rtc.media; the cartridge's call UI."
      I:
        status: "✗"
        deliverable: D-RTC-A1-I
      J:
        status: "✗"
        deliverable: D-RTC-A1-J

  - id: A2
    name: Small-Group Mesh (<=4)
    note: |
      Phase-2 deliverable. Full P2P mesh: each participant opens a
      PeerConnection to every other (the literal 'everyone sends to
      everyone' shape). Naturally E2E-encrypted, no server. Dies above
      ~4-5 peers on upload/encode load — appropriate at this size only.
    axes:
      A:
        status: "⚠"
        deliverable: D-RTC-A2-A
        note: "Per-peer fingerprint pinning; inherits S1-A."
      B:
        status: "✗"
        deliverable: D-RTC-A2-B
      C:
        status: "✗"
        deliverable: D-RTC-A2-C
      D:
        status: "✗"
        deliverable: D-RTC-A2-D
      E:
        status: "✗"
        deliverable: D-RTC-A2-E
        note: "N*(N-1) connection mesh; the small-group fan-out shape."
      F:
        status: "⚠"
        deliverable: D-RTC-A2-F
        note: "Mesh is E2EE by construction (per-pair DTLS-SRTP)."
      G:
        status: "n/a"
        note: "No relay in mesh."
      H:
        status: "✗"
        deliverable: D-RTC-A2-H
      I:
        status: "✗"
        deliverable: D-RTC-A2-I
      J:
        status: "✗"
        deliverable: D-RTC-A2-J

  - id: A3
    name: SFU Room (group)
    note: |
      Phase-3 deliverable. Larger groups via the S4 SFU relay, metered on
      the cell/BSV rail (S6), kept relay-blind by MLS+SFrame (S5). The
      paid-pubsub-for-RTP play; the flagship 'paid SFU on BSV' surface.
    axes:
      A:
        status: "✗"
        deliverable: D-RTC-A3-A
        note: "Inherits S5-A MLS membership from contact certs."
      B:
        status: "✗"
        deliverable: D-RTC-A3-B
      C:
        status: "✗"
        deliverable: D-RTC-A3-C
      D:
        status: "✗"
        deliverable: D-RTC-A3-D
      E:
        status: "✗"
        deliverable: D-RTC-A3-E
        note: "SFU forward fan-out; inherits S4-E."
      F:
        status: "✗"
        deliverable: D-RTC-A3-F
        note: "MLS+SFrame so the SFU forwards ciphertext; inherits S5-F."
      G:
        status: "✗"
        deliverable: D-RTC-A3-G
        note: "Per-byte forwarding settlement; inherits S6-G."
      H:
        status: "✗"
        deliverable: D-RTC-A3-H
      I:
        status: "✗"
        deliverable: D-RTC-A3-I
      J:
        status: "✗"
        deliverable: D-RTC-A3-J

  - id: A4
    name: Broadcast / VOD (swarm-backed)
    note: |
      The latency-tolerant one-to-many regime — a talk, a livestream, a
      recording — where 1-2s delay is fine. This is chunked media segments
      paid per chunk: paid HLS/DASH over the EXISTING paid swarm. Mostly a
      media-segmenter feeding the swarm rather than new transport. The
      head-start row: the swarm chunk-distribution + metering already ship
      (paid-swarm M0-M9). Do NOT route interactive calls through this
      (store-and-forward + per-cell payment latency is wrong for <150ms).
    axes:
      A:
        status: "⚠"
        deliverable: D-RTC-A4-A
        note: |
          Serve gate BUILT (#987): AccessGrantServePolicy on the swarm ServePolicy
          seam; SwarmGrantProof on the request; one broadcast-level access.grant
          (binds to broadcastContentHash, expiry = subscription window) gates ALL
          segments (#988). Admission-time per subscription, not per frame.
          STILL ⚠: enforcement runs through an AccessGrantVerifier PORT whose real
          impl (BrainAccessGrantVerifier → the live 2-PDA verify .handler) is the
          next slice; today's tests use a labeled 2-PDA stand-in. Crypto is proven
          in the Zig handler + the accessChallengeDigest vector.
      B:
        status: "n/a"
        note: "No Jingle/WebRTC signalling — swarm subscription, not a call."
      C:
        status: "n/a"
        note: "Rides the swarm data plane, not ICE/WebRTC."
      D:
        status: "✓"
        deliverable: D-RTC-A4-D
        note: "Media segmenter built + tested (#988): segmentBuffer (VOD) + MediaSegmenter (live push/flush) → publishBroadcast feeds each segment to the swarm as a file."
      E:
        status: "✓"
        deliverable: D-RTC-A4-E
        note: "One-to-many distribution realised: the BroadcastPlaylist (HLS .m3u8 analogue, segment URIs = swarm infohashes) + consumeBroadcast (in-order fetch + verify + reassemble) over the proven swarm fan-out (#988)."
      F:
        status: "⚠"
        deliverable: D-RTC-A4-F
        note: "Per-stream key from PKI; chunk encryption rides the swarm's existing scheme."
      G:
        status: "⚠"
        deliverable: D-RTC-A4-G
        note: "Per-chunk paid delivery already exists in the swarm + segments are swarm files (so metering applies); binding metering to broadcast segments end-to-end not yet tested."
      H:
        status: "✓"
        deliverable: D-RTC-A4-H
        note: "rtc.broadcast re-exports the segmenter/playlist/publish/consume helper on the shell rtc surface (#988); rtc → swarm sibling allowed by the one-way-dep gate."
      I:
        status: "✓"
        deliverable: D-RTC-A4-I
        note: "30 A4 conformance tests (#987 serve gate 15 + #988 broadcast 15): segmenter VOD/live, playlist codec, publish/consume in-order+verify, one-grant-gates-all."
      J:
        status: "✗"
        deliverable: D-RTC-A4-J

  - id: A5
    name: Skyminer Local Multicast (mesh demo)
    note: |
      The honest home of the 'spin up a VPN and everyone multicasts' idea.
      True IP multicast does NOT traverse the public internet (no inter-AS
      multicast routing) — over the internet it collapses into mesh
      (replicated unicast at the sender) or SFU (replicated at a relay),
      which A2/A3 already cover better than a per-call WireGuard overlay.
      BUT on the skyminer N=8 IPv6 multicast mesh it genuinely works and is
      a distinctive demo: real multicast video over the proven local mesh.
      Different regime from internet calls; tracked separately on purpose.
    axes:
      A:
        status: "✗"
        deliverable: D-RTC-A5-A
        note: "Per-device identity on the mesh (singularity L5 cross-ref)."
      B:
        status: "n/a"
        note: "Local multicast discovery, not Jingle signalling."
      C:
        status: "⚠"
        deliverable: D-RTC-A5-C
        note: "IPv6 site-multicast transport proven on the N=8 mesh (skyminer); carrying media frames over it is the gap."
      D:
        status: "✗"
        deliverable: D-RTC-A5-D
        note: "Real-time video encode/decode on the Orange Pi tier over multicast."
      E:
        status: "⚠"
        deliverable: D-RTC-A5-E
        note: "Multicast-and-filter fan-out exists on the mesh; the genuine multicast topology, not emulated."
      F:
        status: "✗"
        deliverable: D-RTC-A5-F
      G:
        status: "n/a"
        note: "Local mesh demo; metering out of scope for the showcase."
      H:
        status: "✗"
        deliverable: D-RTC-A5-H
      I:
        status: "✗"
        deliverable: D-RTC-A5-I
      J:
        status: "✗"
        deliverable: D-RTC-A5-J

```
