---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/SEMANTOS-SITES-MATRIX.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.664252+00:00
---

# Semantos Sites 1.0 — Progress Matrix

**PRD:** `SEMANTOS-SITES-1.0.md`
**Reference implementations:** `oddjobtodd.info` (Oddjobz) · `semantos.me` (platform)
**Last updated:** 2026-05-11

Legend: `done` · `in_progress` · `pending` · `blocked`

---

## Layer 0 — Foundation (no external dependencies)

| ID | Task | Status | Files | Notes |
|---|---|---|---|---|
| S1 | Operator profile types (`OperatorProfile`, `Service`, `Pricing`, `QuotePolicy`) | done | `src/operator_profile.zig` | Default profile = oddjobtodd.info data |
| S3 | Site renderer — HTML generation from `OperatorProfile` | done | `src/operator_site_renderer.zig` | Nav + hero + services + how-it-works + pricing + footer + analytics snippet |
| S4 | Analytics event parser (`parseEvent`, `eventToJson`, funnel depth) | done | `src/analytics_handler.zig` | Arena-safe string duping; 4/4 tests green |
| S5 | Wizard system prompt — Oddjobz flavour | done | `extensions/sites/wizard/oddjobz_wizard_prompt.md` | 4-phase conv; hero h1/lede/widget config generation rules |

## Layer 1 — Data layer (independent of W7.4)

| ID | Task | Status | Files | Notes |
|---|---|---|---|---|
| S7 | A/B session resolution — cookie → variant, `data-variant` on `<html>` | done | `src/operator_site_renderer.zig` | `resolveVariant` + `abCookieHeader` + `renderSiteWithAb`; 2 new tests green |
| S8 | Postgres migration — `operator_profile` JSONB on operators table | done | `db/postgres/migrations/020_operator_profile.sql` | Columns: `profile_lbc`, `profile_icp`, `profile_services`, `profile_pricing`, `site_status`; partial index on `site_status='live'` |
| S11 | `operator_profile_loader.zig` — read profile JSON from data dir, assemble `OperatorProfile` | done | `src/operator_profile_loader.zig` | `loadFromFile`, `loadForDomain`, `parseProfileJson`; falls back to defaultProfile |

## Layer 2 — HTTP layer (depends on S3, S4, S7)

| ID | Task | Status | Files | Notes |
|---|---|---|---|---|
| S10a | `RouteType.operator_home` — new site_config route type | done | `src/site_config.zig` | GET / and GET /index.html → operator site renderer |
| S10b | `operator_home` handler wired into `site_server.handleRequest` | done | `src/site_server.zig` | Load profile.json → renderSite → stream HTML; falls back to defaultProfile |
| S10c | `POST /api/v1/analytics` route + handler | done | `src/site_server.zig` + `src/analytics_handler.zig` | Parses body → appends to `analytics.jsonl` (v1 file log; v2: LMDB) |
| S10d | `operator_home` + `analytics` added to `build.zig` imports on `site_server_mod` | done | `build.zig` | `operator_profile`, `operator_site_renderer`, `operator_profile_loader`, `analytics_handler` wired |

## Layer 3 — CLI + tooling (depends on S10, S11)

| ID | Task | Status | Files | Notes |
|---|---|---|---|---|
| S12 | `brain site-preview <op_pkh_or_domain>` — render operator site to stdout | done | `src/cli.zig` | Renders from profile.json (via loader) or defaultProfile; `--output <path>` supported |
| S13 | `brain site-publish <domain>` — write profile JSON to data dir | done | `src/cli.zig` | `--from <file>` or stdin; validates via parseProfileJson; writes `$data_dir/sites/<domain>/profile.json` |
| S14 | End-to-end smoke test: profile JSON → `renderSite` → valid HTML | done | `src/operator_site_renderer.zig` | 12 tests: default, variant, phone_only, resolveVariant, S14 multi-service/single/empty/pricing edge cases; all green |

## Layer 4 — App layer (blocked on W7.4 → W7.9)

| ID | Task | Status | Files | Notes |
|---|---|---|---|---|
| S6 | Flutter wizard UI — in-app conversation → profile cells | blocked | oddjobz Flutter app | Depends on W7.9 provisioning endpoint |
| S9 | Flutter dashboard — section editor + variant preview + analytics summary | blocked | oddjobz Flutter app | Depends on W7.9 |

## Layer 5 — Deploy + live (depends on S10, S12, S13)

| ID | Task | Status | Files | Notes |
|---|---|---|---|---|
| S15 | oddjobtodd.info: deploy via brain site renderer (replace hand-coded HTML) | done | `deploy/oddjobtodd-site-s15.json` · `deploy/oddjobtodd-profile.json` · `deploy/README.md` | operator_home route + profile.json; end-to-end smoke tested; deploy runbook in README |
| S16 | Semantos.me: add wizard CTA section pointing to Oddjobz onboarding | pending | `semantos-explainer.html` | Cross-sell: "Build your own → start with Oddjobz" |

---

## Dependency graph

```
S1 (profile types) ──┬── S3 (renderer) ──┬── S10a/b (HTTP route)
                     │                   └── S7 (A/B resolution)
S4 (analytics) ──────┼── S10c (analytics route)
S5 (wizard prompt) ──┘
                         S8 (Postgres migration)
                         S11 (profile loader) ── S10b (serve live)

S10a/b + S11 ─────────── S12 (site-preview CLI)
                          S13 (site-publish CLI)
S10 + S12 + S13 ─────── S15 (oddjobtodd.info live)

W7.4 → W7.9 ──────────── S6, S9 (Flutter app)
```

---

## W7.x integration points (parallel brain work — do not conflict)

| W7 item | Status | Semantos Sites touch point |
|---|---|---|
| W7.4 — WSS auth | in_progress (other session) | Unblocks S6/S9 (Flutter provisioning) |
| W7.9 — provisioning endpoint | pending (depends W7.4) | Unblocks S6/S9 |
| W7.14 — BYOD TLS | done | Already wired; S10 routes land on top of it |
| W7.15 — SNI → op_pkh map | done | S10b reads the SNI map to resolve op_pkh from Host header |

---

## Current sprint focus (2026-05-11)

**S15 done — Semantos Sites 1.0 Layers 0–3 + 5 complete.** Layer 4 (S6/S9 Flutter) blocked on W7.9. S16 (semantos.me CTA) pending.

- **S16** — semantos.me: add wizard CTA section pointing to Oddjobz onboarding
- **S6/S9** — Flutter wizard + dashboard (blocked on W7.4 → W7.9)
