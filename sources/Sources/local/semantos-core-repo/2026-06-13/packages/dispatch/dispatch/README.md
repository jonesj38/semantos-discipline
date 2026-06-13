---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/dispatch/dispatch/README.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.510658+00:00
---

# @semantos/dispatch

Dispatch envelope **bridge primitive**. The cross-vertical federation
seam — what chapter 29 of the textbook is about. Defines three cell
types and a transport-agnostic handler:

- `dispatch.envelope.v1` (LINEAR) — the envelope itself. Carries a
  payload cell signed by the originating hat, addressed to a
  receiving `tenant-domain#hat-id`.
- `dispatch.accepted.v1` (LINEAR) — the receive-side acknowledgement
  patch flowing back to the originator after the receiving extension
  successfully materialises the envelope.
- `dispatch.completion.v1` (LINEAR) — completion-and-billing patch
  flowing back from the receiving vertical when the work-of-record
  reaches its terminal state.

Ships D-O11 phase O11b per
`docs/design/ODDJOBZ-EXTENSION-PLAN.md` §3 phase O11.

## Architectural posture

The handler is **payload-agnostic**. It knows nothing about the
shape of the inner cell — it routes by `payload_type` (a string
identifier of the payload cell's canonical name like
`re-desk.maintenance-request.v1`) to a registered accept-handler
contributed by the receiving extension at boot.

This is the load-bearing claim that chapter 29's federation primitive
composes. The dispatch extension is the universal bridge; verticals
plug in by registering their own accept-handler. Adding a new
vertical (chapter 31's accountant, chapter 32's lender, etc.) does
not require modifying this extension — only registering the new
payload type.

## Transport

The bridge primitive is transport-agnostic. In production it rides
on the SignedBundle mesh transport from D-W1 Phase 4
(`runtime/semantos-brain/src/transport/signed_bundle.zig`). The receiving brain
brain decodes the SignedBundle, verifies the cert chain, and hands
the dispatch.envelope.v1 cell to this extension's handler.

For the smoke test (D-O11 phase O11c) the SignedBundle wire is
replaced with an in-process `BundleTransport`. The handler logic is
identical; what differs is the bytes-on-the-wire layer. That
substitutability is the seam D-W1 Phase 4 was designed for.

## What's NOT in this extension

- No FSM advancement on the receiving extension's cells. The
  handler routes the payload; the receiving extension's
  accept-handler is responsible for materialising it (typically by
  calling its own `genesisX` followed by an FSM transition under
  its own caps).
- No cap minting. The dispatch handler verifies that the envelope's
  signature comes from a hat that holds the originating extension's
  cap (e.g. `cap.re-desk.dispatch` for a re-desk envelope), but the
  cap itself lives in the originating extension.
- No replay protection beyond what the substrate provides. The
  `envelopeId` is the K1-protected idempotency key; a duplicate
  envelope arriving twice is rejected on the second post (see
  `tests/handler/replay-protection.test.ts`).

## Tenant-hat references

Targets are `<tenant-domain>#<hat-id>` — see
`@semantos/re-desk-stub`'s `parseTenantHatRef`. The dispatch
extension re-exports the parser so consumers don't need to depend on
re-desk-stub directly.
