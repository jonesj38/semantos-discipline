---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/loom-svelte/CANON-STATUS.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.048687+00:00
---

# loom-svelte — canon status

**Role:** the always-on Brain's lean **Svelte web helm** (the DO|TALK|FIND
operator console). Resurrected from `archive/` and inverted into a neutral,
manifest-driven cartridge loader.

**Tracked by:** [`docs/canon/svelte-helm-matrix.yml`](../../docs/canon/svelte-helm-matrix.yml)
(rendered → [`docs/prd/SVELTE-HELM-ROADMAP.md`](../../docs/prd/SVELTE-HELM-ROADMAP.md)).
Decisions: [`docs/design/SVELTE-HELM-DECISIONS.md`](../../docs/design/SVELTE-HELM-DECISIONS.md);
contracts: [`docs/design/SVELTE-HELM-CONTRACTS.md`](../../docs/design/SVELTE-HELM-CONTRACTS.md).

## Why this exists (D10)

`apps/loom-svelte` was archived in canon C8, and canon Q2 said the Brain's
web helm should be `flutter build web` of `apps/semantos`. Per **DECISION
D10** (2026-06-07) the operator chose instead to resurrect loom-svelte as a
**deliberately lean, separate Svelte web helm** that talks to the Brain purely
over HTTP/REPL/WSS. This diverges from Q2 and reverses the C8 archival for
this one app; it is reversible.

## What's built (gated: 154 helm tests, svelte-check 0 errors, vite build)

- **Manifest-driven shell (SH1–SH4).** The Brain serves each loaded
  cartridge's declarative UI (`surfacingMode` + `verbs[]`) on `/api/v1/info`.
  The Dock renders the CSD 1-3-5-3-1 pyramid as the DEFAULT shell, with each
  cartridge's `verbs[]` OVERLAID per modal (D11). `surfacingMode` drives the
  body route (dedicated takeover / default / passive). Cartridge surfaces load
  via a registry (`src/shell/surface-registry.ts`) with a graceful placeholder.
- **Hat-gating (SH14, D12).** Verbs and hats carry an `operator|admin` role;
  the shelf hides admin (managerial) verbs unless the active hat is admin.
  Source: the bearer token (`/api/v1/info` hat block); mint via
  `brain bearer issue --role admin`.
- **Me panel (SH5, D13).** `src/shell/me/MePanel.svelte` consolidates the
  identity surface — cert in effect + the relocated hat switcher (with role) +
  wallet + contacts — opened from an AppBar affordance and a `view:me` dispatch.

## Known gaps / pending

- **SH2-H verb dispatch** — overlay verb tiles render but don't yet act
  (`handleDockInvoke` stubs non-`view:*` commands). Blocked on a design
  decision (REPL-line vs cell-mint vs open-surface); see matrix SH2-H.
- **Attention surface (SH6–SH11)** — not started in this helm; shell-native
  attention sources + scope + weights are brain-side work.
- **SH5 residuals** — wallet is surfaced but not deep-booted (F); recovery
  envelope not in the panel yet (G).
- **SH4-J** — oddjobz views still physically live in the shell tree; the
  registry gives functional neutrality, physical package extraction deferred.
