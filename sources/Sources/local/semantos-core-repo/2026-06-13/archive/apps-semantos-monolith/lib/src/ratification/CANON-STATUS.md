---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/lib/src/ratification/CANON-STATUS.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.873636+00:00
---

# `apps/semantos/lib/src/ratification/` — CANON STATUS: OFF-SLICE / MONOLITH DEAD CODE

Per `docs/canon/canonicalization-matrix.yml` C2-A aggressive-excision policy. See `apps/semantos/lib/src/helm/CANON-STATUS.md` for the full framing.

## Files here

- `ratification_card_controller.dart`
- `ratification_queue_client.dart`
- `ratification_route.dart`

## Disposition

Ratification is the **lead-tray accept/reject** flow for the oddjobz pipeline. Explicitly listed in C2-A's "off-path monolith features" set:

> Off-path monolith features (lead-tray ratification UI, attachment capture choreography, calendar surface, etc.) are NOT preserved by default — they get re-built against the clean substrate in a later phase if and when the operator needs them.

**Default disposition: DROP**. The substrate-level pattern (verb.dispatch with capability gates + brain-side walker) supersedes the card-controller/queue-client/route trio. If lead-tray is rebuilt, it'll be a thinner, intent-grammar-driven flow.

**Deletion timing**: removed as part of C3 monolith delete.
