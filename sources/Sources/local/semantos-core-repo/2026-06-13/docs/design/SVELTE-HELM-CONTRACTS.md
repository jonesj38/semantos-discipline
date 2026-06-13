---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/design/SVELTE-HELM-CONTRACTS.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.743052+00:00
---

# Svelte-Helm — HTTP / WSS Contracts (SH0)

**Status**: LOCKED (SH0 entry gate)
**Matrix**: docs/canon/svelte-helm-matrix.yml
**Companions**: SVELTE-HELM-GOLDEN-SLICE.md, SVELTE-HELM-DECISIONS.md

---

## 0. Why this doc exists

`apps/loom-svelte` (the brain's always-on web helm) has **no in-process
GrammarRegistry** — that is a Flutter/Dart construct in `apps/semantos`. So
everything the Flutter shell reads from an in-process registry, the Svelte
helm must read from the brain **over HTTP/WSS**. This doc locks those wire
contracts so SH1–SH10 implement against a fixed shape rather than drifting.

All shapes below are **observed from the current tree** where a seam exists,
and **proposed (NET-NEW)** where it does not. Each is tagged accordingly.

Auth on every endpoint: `Authorization: Bearer <token>` (issued via
`brain bearer issue`). Cert+capability auth (`cert_request_auth.zig`, T7 /
PR #885) is the forward path; bearer is the SH-era contract.

---

## 1. Cartridge manifest list — served via `GET /api/v1/info` (SH1, IMPLEMENTED)

> **REVISED (D3, 2026-06-07):** there is **no** separate `/api/v1/cartridges`
> route. `GET /api/v1/info` already serves a `cartridges[]` array
> (`info_http.CartridgeInfo`, CC2b Brain→PWA discovery); SH1 **enriched each
> entry** with `surfacingMode` + `verbs[]` rather than duplicate the list.
> The web helm's substitute for the Flutter GrammarRegistry is the
> `cartridges[]` block of `/api/v1/info`. Source: `cartridge.json`'s `ui`
> block, parsed by `extension_manifest_loader.zig` (SH1-A) and projected by
> `info_http.handle()` (SH1-B).

### Request
```
GET /api/v1/info
Authorization: Bearer <token>
```

### Response `200` (cartridges[] portion; full body also carries theme/hat/mesh)
As IMPLEMENTED in SH1-B, the declarative UI fields are **flat on the
cartridge object** (siblings of `id`/`role`/`experiencePackage`), not nested
under a `ui` key:
```jsonc
{
  "cartridges": [
    {
      "id": "oddjobz",                    // manifest.id
      "role": "experience",              // "experience" | "domain" | …
      "experiencePackage": "oddjobz_experience",
      "surfacingMode": "default",        // "" (helm treats as default) | "dedicated" | "passive"
      "verbs": [                         // canonical shape — matches the Flutter manifest (DECISIONS D9)
        {
          "modal": "do",                 // "do" | "talk" | "find" (lowercase, semantic bucket)
          "label": "New job",
          "intentType": "oddjobz.job.create",  // what the helm dispatches (REPL / POST cells)
          "subtitle": "log a new job",   // "" when absent
          "icon": "build",               // "" when absent — named glyph, not a pixel position
          "role": "operator"             // SH14/D12 — "operator" (default) | "admin"; helm filters by active hat role
        }
      ]
    }
  ]
  // NOTE: per-verb `dispatch` (HelmUiVerbDispatch: cellType/triple/
  // defaultPayload, canon #725) and per-cartridge attention.namespaces[]
  // (SH6) are NOT yet emitted by SH1-B — added when SH6/SH3 need them.
}
```

### Contract notes
- **Pure-shell case** (`extensions/` empty) ⇒ `{ "cartridges": [] }`. The helm
  must render the neutral shell from an empty list (no crash, no oddjobz).
- `ui.verbs[]` mirrors the Flutter manifest schema landed in canon PR #719
  (`ui.verbs[]` + `ui.surfacingMode`) and PR #725 (`HelmUiVerbDispatch`).
- The helm renders the DO/TALK/FIND shelf by filtering `verbs[]` on `modal`
  for the **active** cartridge — the web analog of
  `GrammarRegistry.verbsForModalAndExtension(modal, activeCartridge)`.
- `role` distinguishes a UI-owning **experience** from a logic/data
  **domain** cartridge (oddjobz = experience, betterment = domain today).
- **Hat block (SH14/D12).** `/api/v1/info` also carries a `hat` block:
  `{ "id", "name", "cert_id", "role" }` where `role` is the active hat's
  `"operator"` (default) | `"admin"` (SH-era source = the bearer token; see
  DECISION D12). The helm reads `hat.role` (via `fetchActiveHatRole`) and the
  Dock hat-gates the verb shelf: operator sees operator-role verbs only, admin
  sees operator + admin (the managerial verbs). Each `verbs[]` entry carries
  its own `role` (`"operator"` default | `"admin"`).

### Implementation seam
Today `GET /api/v1/info` exists (theme/tenant branding only). SH1 either
extends `/info` with a `cartridges[]` block or adds a sibling
`cartridges_http.zig` route via `http_route_registry`. **Decision (locked in
DECISIONS §3): separate route `/api/v1/cartridges`** — keeps `/info`
GET-only-branding stable and avoids overloading it.

---

## 2. `GET /api/v1/info` — tenant branding (EXISTS)

```jsonc
{ "theme": { /* CSS custom-property values */ }, "tenant": { /* … */ } }
```
Consumed by `loom-svelte/src/lib/theme-store.ts` post-auth; reapplied on
`hat-switched`. **Stays branding-only** — manifests move to §1.

---

## 3. Attention contracts

Signal wire shape is owned by `attention_source_registry.zig` and emitted by
each source's `CollectFn` as a JSON array. The helm renders it.

### 3.1 Signal item (EXISTS — `attention_source_registry.zig`)
```jsonc
{
  "kind":      "dispatch",      // short source label
  "score":     0.82,            // 0..1 relevance after scoring
  "ref":       "<cellId|opaque ref>",
  "summary":   "Quote #123 unanswered 4 days",
  "expiresAt": 1779920150423,   // optional (ms epoch)
  "raw":       { /* source-defined */ }
}
```

### 3.2 `GET /api/v1/attention/snapshot` (EXISTS, EXTEND in SH8)
```
GET /api/v1/attention/snapshot?ns=shell,oddjobz       ← ?ns= is NET-NEW (SH8)
Authorization: Bearer <token>
```
Response `200`:
```jsonc
{ "items": [ /* §3.1 items, ranked desc by score */ ] }
```
- **Today**: bearer-only, **no `ns` param**; returns a global snapshot
  (`attention_http.zig` `get_snapshot` fn). The namespace-scoped path
  currently lives only on the WSS `attention.poll` method
  (`attention_poll_handler.zig`, `namespaceInList`).
- **SH8 unifies them**: the REST snapshot accepts `?ns=<csv>` and routes
  through the scoped poll. Absent `ns` ⇒ a documented default
  (DECISIONS §4: default scope = `shell` only).
- **Isolation invariant**: in-cartridge scope passes just that namespace ⇒
  cross-cartridge signals never leak (matches the registry's stated default).

### 3.3 `POST /api/v1/attention/interact` (EXISTS)
Fire-and-forget telemetry; `200` even if no recorder wired (`record_interact`
optional). Body (the SH11/AS1 learner's input):
```jsonc
{ "kind": "tapped"|"opened"|"dismissed"|"acted-on"|"ignored",
  "itemId": "<ref>", "rank": 0, "relevance": 0.82,
  "verb": "do"|"find"|"talk", "secondsViewed": 0, "explicit": true }
```

### 3.4 `GET|PUT /api/v1/attention/weights` (EXISTS — stub)
- `GET` returns the current scoring weights. **Today: hardcoded constants.**
- `PUT` **today is a no-op returning `200`**. SH10 makes it persist
  (signed cell, operator hat) and the scorer apply them; adds per-class
  boost/suppress (`"trades.job.* +0.2"`, `"newsletter.* suppress"`).

---

## 4. REPL + cells — body-view data (EXISTS)

The Svelte views are driven by the **bearer-gated line REPL** over
`/api/v1/*`, not bespoke REST per resource:
- `find <resource> [--flag v]` → list/detail data (`repl-client.ts`,
  `find jobs`, `find customers`, `find invoices --job-id <id>`).
- `do`/verb dispatch → `POST /api/v1/cells` (mint) using the manifest's
  `ui.verbs[].dispatch.defaultPayload` + `cellType` (generic
  `dispatchByName`, **no cartridge-class import** in the shell).

The shell therefore needs **zero per-cartridge REST knowledge** — a new
cartridge's `find`/`do` verbs work the moment its `registerInto` registers
them brain-side (REPL is the universal access layer, canon C5-B note).

---

## 5. WSS `/api/v1/wallet` — live events (EXISTS)

Same-origin WSS (`App.svelte:155`): the helm derives
`${proto}//${window.location.host}/api/v1/wallet`. The brain emits a fixed
set of `<type>.created` / `<type>.updated` events from `helm_event_broker`;
the helm refreshes the affected view/attention feed on receipt.

**Caddy**: `handle /api/v1/* { reverse_proxy brain:8080 }` covers this WSS
(auto-upgrade). Operators must NOT route `/api/v1/wallet` away from the
brain.

---

## 6. Surfacing modes (LOCKED enum)

From `apps/semantos/lib/shell/helm_scaffold.dart:14-15` +
`cartridge_picker.dart:82-84`:

| mode        | helm behaviour                                              |
|-------------|-------------------------------------------------------------|
| `default`   | renders in the shared helm body; shelf scoped to active     |
| `dedicated` | own full-screen surface — **total takeover** (ecommerce)    |
| `passive`   | excluded from the picker (no operator-facing surface)       |

The Svelte `SurfacingRouter` (SH3) mounts exactly one `dedicated` surface
when active, or the shared body for `default`. This is the mechanism behind
"load the ecommerce cartridge and it totally switches, no evidence of
oddjobz."

---

## 7. Summary: what each SH track consumes

| Track | Consumes |
|-------|----------|
| SH1   | produces §1 |
| SH2   | §1 (manifests) + §4 (REPL/cells) |
| SH3   | §1 `ui.surfacingMode` (§6) |
| SH5   | identity/cert/contacts endpoints + §5 WSS wallet |
| SH6   | §3.1 (cartridge-registered sources) |
| SH7   | §3.1 under `shell` namespace |
| SH8   | §3.2 `?ns=` |
| SH9   | §3.2 + §3.3 + §5 |
| SH10  | §3.4 |
| SH11  | §3.3 telemetry → learned §3.4 weights |
