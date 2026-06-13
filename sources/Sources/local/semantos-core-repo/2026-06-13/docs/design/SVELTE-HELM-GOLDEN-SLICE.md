---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/design/SVELTE-HELM-GOLDEN-SLICE.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.724108+00:00
---

# Svelte-Helm — Golden Slice (SH0 → SH12 acceptance tape)

**Status**: LOCKED (SH0 entry gate)
**Matrix**: docs/canon/svelte-helm-matrix.yml (track SH12)
**Companions**: SVELTE-HELM-CONTRACTS.md, SVELTE-HELM-DECISIONS.md

---

## 0. What the slice proves

ONE operator session that demonstrates the entire vision: a neutral
always-on brain helm that boots useful with zero cartridges, gains a
business surface when one is activated, and **wholesale switches** when a
second is activated — with a cross-business attention view available from
the shell. If this tape runs green on the canonical `loom-svelte` build
against a live brain, the matrix is complete (SH11 learning may trail).

The slice is the SH12 deliverable; it also defines "done" for SH2–SH10 by
example. It does **not** require SH11 (learning) — static-tunable weights
(SH10) are sufficient for step 5.

---

## 1. Preconditions

- A brain built from this branch, running `serve <domain> --enable-repl`,
  data dir with **empty `extensions/`**.
- Caddy (or proxy) fronting it: static `loom-svelte/dist` at the webroot +
  `/api/v1/*` (incl. `/api/v1/wallet` WSS) reverse-proxied to `:8080`.
- A bearer token (`brain bearer issue --label slice`).
- Two cartridges staged but NOT yet in `extensions/`: `oddjobz` and a
  second **`dedicated`-mode experience** cartridge (the "ecommerce" stand-in
  — a fixture cartridge is acceptable for the slice; it only needs a
  manifest with `surfacingMode: dedicated`, a couple of `ui.verbs[]`, and
  one attention source).

---

## 2. The tape

### Step 1 — Pure brain shell boots useful
1. Open the helm; authenticate with the bearer.
2. `GET /api/v1/cartridges` ⇒ `{ "cartridges": [] }`.
3. **Assert**: the helm renders the neutral DO|TALK|FIND shelf — **no
   oddjobz tabs, no job/quote/invoice views** (SH4 proof).
4. **Assert**: the **TALK tab** shows the root BRC-52 cert, contacts, and
   PKI/key access; a **"me" affordance** is also present (SH5, BOTH).
5. **Assert**: the attention surface shows a **non-empty shell-native feed**
   (`?ns=shell`) — e.g. a recovery-envelope-missing nudge or a pending
   ratification (SH7). NOT empty `{items:[]}`.

### Step 2 — Activate oddjobz (default mode)
1. Stage `oddjobz` into `extensions/`; restart brain.
2. `GET /api/v1/cartridges` ⇒ one entry, `surfacingMode: default`,
   `ui.verbs[]` populated, `attention.namespaces: ["oddjobz"]`.
3. In the picker, select oddjobz.
4. **Assert**: the DO shelf shows **oddjobz verbs only**; the body renders
   oddjobz's surface (jobs/quotes/etc.) — fed by `find jobs` over the REPL
   (SH2/SH3).
5. **Assert**: with scope `?ns=shell,oddjobz`, the attention feed merges
   shell-native + oddjobz signals (SH8).

### Step 3 — Activate the second (ecommerce, dedicated) cartridge — TAKEOVER
1. Stage the ecommerce cartridge into `extensions/`; restart brain.
2. `GET /api/v1/cartridges` ⇒ two entries; ecommerce `surfacingMode:
   dedicated`.
3. In the picker, select ecommerce.
4. **Assert (the headline)**: the surface **totally switches** to the
   ecommerce dedicated surface. **ZERO evidence of oddjobz** — no oddjobz
   tabs, no oddjobz verbs in the shelf, no oddjobz rows (SH3 dedicated
   routing + SH4 neutral shell).
5. **Assert**: attention scoped to ecommerce shows **only ecommerce**
   signals (oddjobz namespace not in scope ⇒ invisible).

### Step 4 — Cross-business operational view from the shell
1. Deselect into the neutral shell (or a "shell" scope).
2. Set attention scope `?ns=shell,oddjobz,ecommerce`.
3. **Assert**: the attention feed shows signals from **both businesses +
   shell-native**, ranked together — the "manage my whole operation from one
   surface" view (SH8). This is the dual to step 3's isolation.

### Step 5 — Tunable attention (static)
1. Open the weight editor; boost one class (e.g. `oddjobz.lead.* +0.3`) or
   adjust a factor weight; `PUT /api/v1/attention/weights`.
2. **Assert**: `PUT` persists (re-`GET` returns the new weights; survives a
   reload) and the ranking **visibly responds**; the "why is X above Y"
   inspector reflects the change; the change is roll-back-able (SH10).

---

## 3. Pass criteria

All five steps assert green on the **canonical** `loom-svelte` build (not a
dev fixture page) against a **live** brain. The single hardest assertion —
the one the whole matrix exists to satisfy — is **Step 3.4: no oddjobz
leakage in the ecommerce dedicated surface.**

## 4. Out of slice (tracked, not gating)

- SH11 learning loop (AS1–AS5) — drift/learning is verified separately; the
  slice only needs SH10 static-tunable weights.
- The Docker image build gap (canon C4-carve / Dockerfile `../../cartridges`)
  — the slice brain is built via local `zig build` in the worktree, not the
  image.
