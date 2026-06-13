---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/lib/src/attachments/CANON-STATUS.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.877892+00:00
---

# `apps/semantos/lib/src/attachments/` — CANON STATUS: OFF-SLICE / MONOLITH DEAD CODE

Per `docs/canon/canonicalization-matrix.yml` C2-A aggressive-excision policy. See `apps/semantos/lib/src/helm/CANON-STATUS.md` for the full framing.

## Files here

- `attachment_builder.dart`
- `attachment_capture_service.dart`

## Disposition

Attachment capture is an **oddjobz-specific** affordance (photos/receipts attached to jobs/visits). Not on the C7 self-slice critical path.

**Post-canon rebuild**: when oddjobz_experience gets its full UI build-out, attachment capture re-emerges as a thinner, manifest-driven affordance — likely a single cell-type `attachment.captured` rather than the current builder + service split.

**Deletion timing**: removed as part of C3 monolith delete.
