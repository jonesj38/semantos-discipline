---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/SVELTE-HELM-ROADMAP.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.708659+00:00
---

# Svelte-Helm Roadmap

> Generated from `docs/canon/svelte-helm-matrix.yml` by
> `docs/canon/render/svelte-helm-to-roadmap.ts` — do not edit by hand.

**Progress:** 52 ✓ · 10 ⚠ · 26 ✗ (of 88 live axes) — **59% complete**.

## Track × axis status

| Track | Name | A | B | C | D | E | F | G | H | I | J |
|---|---|---|---|---|---|---|---|---|---|---|---|
| SH0 | Contracts + Decision Locks + Golden Slice | ✓ | · | · | · | · | · | · | · | ✓ | · |
| SH1 | Brain: manifest-list endpoint (/api/v1/cartridges) | ✓ | ✓ | ✓ | ✓ | · | · | · | · | ✓ | · |
| SH2 | Svelte shell chrome (neutral cartridge loader) | ✓ | ✓ | ✓ | · | ✓ | · | · | ✓ | ✗ | ⚠ |
| SH3 | surfacingMode surface routing (the takeover) | ✓ | ✓ | ✓ | · | ✓ | · | · | · | ✓ | · |
| SH4 | Oddjobz surface extraction (shell goes cartridge-neutral) | ✓ | ✓ | ✓ | · | ✓ | · | · | · | ✓ | ⚠ |
| SH5 | Identity surface — cert / contacts / PKI in TALK + 'me' (both) | ✓ | ✓ | ⚠ | ⚠ | ✓ | ⚠ | ✗ | · | ⚠ | · |
| SH6 | Brain: finish attention-source carve into registerInto | ✗ | ⚠ | ✗ | ✗ | · | · | · | · | ✗ | ✗ |
| SH7 | Brain: shell-native attention sources (pure-brain mode) | ✓ | ✓ | ✓ | ✓ | · | · | · | · | ✗ | · |
| SH8 | Brain: attention scope config + unify snapshot↔poll | ⚠ | ✓ | ✗ | ✗ | · | · | · | · | ✗ | · |
| SH9 | Svelte AttentionSurface render + interaction telemetry | ✓ | ✓ | ✓ | · | ✓ | · | · | · | ✗ | · |
| SH10 | Brain+helm: tunable static attention weights | · | ⚠ | ✗ | ✗ | ✗ | · | · | · | ✗ | · |
| SH11 | Attention learning loop (AS1–AS5) | · | ✗ | ✗ | ✗ | ✗ | · | · | ✗ | ✗ | · |
| SH12 | Golden slice — operator acceptance of the whole vision | · | ✗ | ✗ | · | · | · | · | ✗ | ✗ | · |
| SH13 | Docs / render / autonomous-loop entry | ✓ | ✓ | · | · | · | · | · | · | ✓ | · |
| SH14 | Hat-gated verbs (operator vs admin) | ✓ | ✓ | ✓ | ✓ | ✓ | · | · | · | ⚠ | · |
| SH15 | Core read-path re-wire — oddjobz reads onto generic cell.query/cell.get | · | ✓ | ✓ | ✓ | ✓ | · | · | · | ✓ | ✓ |
| SH16 | Helm live UX — cell.created/customer.upserted refresh + lead source pill | · | ✓ | ✓ | · | ✓ | · | · | · | ✓ | · |

Legend: ✓ done · ⚠ partial/in-progress · ✗ not started · · n/a.
Axes: A source · B wired · C tests · D brain · E helm · F wallet · G recovery · H intent · I docs · J old-code-deleted.

## Done-when per track

- **SH0** — All three SH0 artifacts committed; contracts referenced by SH1/SH8; slice tape agreed.
- **SH1** — GET /api/v1/info cartridges[] carries surfacingMode + verbs[] for 0..N loaded cartridges; bearer-gated; tests green.
- **SH2** — loom-svelte boots a manifest-driven DO|TALK|FIND shell with zero cartridge imports; picker switches active cartridge.
- **SH3** — Switching to a dedicated-mode cartridge replaces the whole surface; default-mode coexists scoped; passive is hidden.
- **SH4** — Cartridge body renders via the surface registry (✓); unregistered ids show a placeholder (✓); dedicated takeover supported for a 2nd registered surface (mechanism ✓ — needs a real 2nd cartridge surface to demo). Physical view-package extraction (J) deferred as organizational.
- **SH5** — Pure-shell boot shows root cert + contacts + PKI from BOTH the TALK tab and a 'me' affordance; wallet boots; recovery envelope downloadable.
- **SH6** — Dropping/removing a cartridge adds/removes its attention sources with no serve.zig edit; oddjobz sources gone from serve.zig.
- **SH7** — A brain with empty extensions/ returns a non-empty, scored shell-native attention feed covering the named signal kinds.
- **SH8** — One snapshot path honours an operator-supplied namespace scope; isolation default holds (in-cartridge ⇒ just that namespace).
- **SH9** — The shell renders a live scoped attention feed with working scope toggle; interactions POST telemetry; updates over WSS.
- **SH10** — Operator edits weights + per-class boost/suppress; PUT persists (signed, audit-trailed); ranking respects them and is inspectable/rollback-able.
- **SH11** — Operator behaviour drifts weights legibly (inspect + rollback via REPL); AS1-AS5 each shipped or explicitly deferred with a note.
- **SH12** — All five tape steps pass on the canonical loom-svelte build against a live brain; no oddjobz leakage in the ecommerce surface.
- **SH13** — Roadmap renders from this matrix; loop_protocol verified against the live worktree.
- **SH14** — Switching operator↔admin hat changes the shelf: admin reveals the managerial verbs (website/widget/policy), operator hides them; verbs carry role end-to-end (cartridge.json → brain → helm).
- **SH15** — All oddjobz cell reads in the helm flow through cell.query/cell.get on oddjobz.*.v2; no old graph-walk verb strings in src/; helm gate green. (Live refresh + source pill + live round-trip verify are follow-ups.)
- **SH16** — Newly-minted leads appear in the helm without reload (cell.created); customer changes refresh (customer.upserted); job rows show a source pill distinguishing email vs widget leads; helm gate green.
