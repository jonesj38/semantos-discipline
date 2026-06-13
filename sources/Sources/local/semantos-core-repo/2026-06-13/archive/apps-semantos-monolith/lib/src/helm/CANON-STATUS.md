---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/lib/src/helm/CANON-STATUS.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.895347+00:00
---

# `apps/semantos/lib/src/helm/` — CANON STATUS: OFF-SLICE / MONOLITH DEAD CODE

**Status as of 2026-05-28**: This directory is **off the canonicalization slice critical path**. Per `docs/canon/canonicalization-matrix.yml` C2-A aggressive-excision policy (user 2026-05-27, "oddjobz NOT in production"), the contents here will be **re-built against the clean substrate post-canon** rather than forklifted into `packages/oddjobz_experience/`.

## Why this isn't being moved

The C7 golden slice (per `docs/canon/canonicalization-golden-slice.md`) exercises:

> operator types `self.practice.release` utterance → PWA `IntentDispatcher.dispatch` → `BrainHttpClient.mintCell` → live brain → helm card

NONE of the 48 files in this directory are on that path. They are all part of the **oddjobz** vertical's job/customer/quote/invoice/visit UI — a different (high-priority but post-canon) workstream.

## Naming clash resolution

The directory is named `helm/` but its contents are oddjobz's **job dashboard**, not the canonical shell **helm primitive** (which now lives in `apps/semantos-shell/lib/shell/helm_*.dart`). The naming clash will dissolve when this monolith is deleted in C3.

## What replaces this

- **Substrate-level helm primitive** (the canonical DO|TALK|FIND surface): `apps/semantos-shell/lib/shell/helm_home_screen.dart` + `helm_scaffold.dart` — landed via canon/c1-primitives wire ticks 4b + 5 (commits d2dcf43, 5b80f0b).
- **Oddjobz cartridge UI** (when oddjobz becomes a canonical priority): `packages/oddjobz_experience/` — currently bearer-login + minimal job-list view. Full UI re-build is a post-canonicalization workstream, not C2.

## File-by-file disposition (for the eventual rebuild)

When oddjobz_experience does get a full UI build-out, these files document the surfaces operators expected:

| File group | What it was | Post-canon disposition |
|---|---|---|
| `job_*.dart` (4 files) | Job list, detail, thread, row | **Rebuild** against canonical IntentDispatcher + brain query primitives |
| `customer_*.dart` (3 files) | Customer list/detail/screen | **Rebuild** |
| `quote_*.dart` (5 files) | Quote catalogue/list/detail/editor/document | **Rebuild** |
| `invoice_*.dart` (4 files) | Invoice list/detail/editor/document | **Rebuild** |
| `visit_*.dart` (2 files) | Visit list/detail | **Rebuild** |
| `conversation_*.dart`, `contact_conversation_screen.dart`, `messages_screen.dart`, `talk_*.dart` (5 files) | Conversation/messaging | **Rebuild** on top of streams-shell-native (per memory [[streams-conversation-shell-native]]) |
| `attention_*.dart`, `attention_feed_section.dart` (2 files) | Attention surface | **Rebuild** as substrate-level surface in shell (C9), not cartridge-level |
| `ratification_*.dart`, `ratify_tray_screen.dart` (2 files) | Lead-tray ratification UI | **Drop** by default per C2 aggressive-excision; re-add only if operator demands |
| `attachment_screen.dart`, `receipt_ocr_service.dart` | Attachment capture | **Rebuild** simpler (current OCR + capture choreography is over-fit) |
| `calendar_screen.dart`, `schedule_sheet.dart`, `site_screen.dart`, `settings_screen.dart`, `pairing_screen.dart` | Misc screens | **Drop** by default; pairing lives in shell substrate now |
| `do_node.dart`, `find_node.dart`, `home_node.dart`, `talk_node.dart`, `home_screen.dart` | Old "node" navigation pattern | **Drop** — superseded by HelmScaffold + IntentDispatcher |
| `voice_*.dart`, `slide_to_commit.dart`, `stage_trail.dart`, `leads_list_screen.dart`, `conflicts_screen.dart`, `quote_extractor.dart`, `job_conversation_classifier.dart` | Specialized affordances | **Triage on rebuild** — most likely drop |

## Deletion timing

This directory is deleted as part of **C3** (the monolith-rename + delete pass), once:
- C1 primitives forklift is fully landed
- C2 cartridge-extraction (or aggressive-excision-only path) decision is locked
- C7 golden slice is fully green on the canonical shell

Until then, the directory is preserved so the monolith app still builds (some shared lib/src/ imports cross-reference these files).

## Do not edit

If you find yourself wanting to fix a bug or add a feature here: **stop**. Either:
- The functionality belongs in the canonical shell (`apps/semantos-shell/`) — add it there
- The functionality belongs in `packages/oddjobz_experience/` — add it there
- It's truly off-slice and can wait for the post-canon rebuild

Edits to this directory will be lost when C3 lands.
