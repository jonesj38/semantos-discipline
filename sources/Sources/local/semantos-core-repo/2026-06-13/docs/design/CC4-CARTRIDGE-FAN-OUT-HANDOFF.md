---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/design/CC4-CARTRIDGE-FAN-OUT-HANDOFF.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.731981+00:00
---

# CC4 — Cartridge Fan-Out & Directory Collapse: Implementer Handoff

**Status:** Handoff (CC0a–CC3 landed; CC4 is the remaining row of Wave
Canonical-Cartridge). Author: Todd. Date: 2026-05-18.
**Read first:** `docs/design/CANONICAL-CARTRIDGE-MODEL.md` (RATIFIED
C1–C6), `docs/canon/commissions/wave-canonical-cartridge.md` (the
commission), `docs/textbook/37-the-canonical-cartridge-model.md` (the
narrative). Constraining ratified decisions: `CARTRIDGE-MARKETPLACE-
OWNERSHIP.md` A/B/C, `SELLABLE-NODE-LICENSE.md` N1–N4.

This document is the practical handoff for whoever executes CC4. It
states what the cartridge pattern *is* (as built, with file/commit
references), what must be excised, how to declare a cartridge, how N
cartridges run under one Brain shell + one PWA shell, how cartridges
call each other (e.g. the wallet), and the per-cartridge migration
recipe + gates + STOP conditions.

---

## 1. The cartridge pattern, as actually built

One unit — the **cartridge**. "app", "extension", "world-app",
"adapter" are dead concepts (glossary canonical entry `cartridge`,
docs branch `docs/textbook-cartridge-rework`). A cartridge is:

- **One manifest** — `cartridge.json` (the evolved `ExtensionManifest`,
  `core/protocol-types/src/extension-manifest.ts`). CC0a added `role`,
  `experience.flutterPackage`, `lexicon`; CC1 added the `role: infra`
  exemption from `taxonomy/flows/prompts`. Legacy `manifest.json` is
  still accepted (back-compat) but `cartridge.json` is canonical and
  preferred by the loaders.
- **Role-classified** — `infra` (declares `provides`; e.g.
  wallet/headers, bsv-anchor), `experience` (a vertical with a PWA
  surface; e.g. oddjobz, jam-room, tessera), `grammar-lexicon` (pure
  vocabulary). Validation enforces `role: infra ⇒ provides` and
  exempts infra from taxonomy/flows/prompts.
- **Two parts, one binding** — the Brain part (cells/flows/handlers)
  and the PWA-experience part (`experience.flutterPackage`). This
  field is the linchpin that collapses the old `extensions/<id>` ↔
  `packages/<id>_experience` split.
- **Composed, not inherited** — typed `consumes`/`provides` only; no
  cartridge `extends` cartridge (Decision B). `extendsInterfaces` is a
  typed-interface field, not a cartridge-id edge.
- **License-owned** — `licenseOutpointRef`/`licenseLinearity` (affine
  PushDrop UTXO; Decision A/C). Load is gated by the proven
  K15/SW2 SPV path; CC1's `HeadersSpvVerifier`
  (`apps/wallet-browser/src/spv-verifier.ts`) is the real verifier.

**Two loaders, one model (proven end-to-end in CC3, `60522dd`):**

- **Brain shell** — `runtime/semantos-brain` (Zig). DLO.1c
  `enumerateUserInstalled` (disk registry, prefers `cartridge.json`);
  `ExtensionLoader.resolveCartridgeOrder` + `loadCartridges`
  (`core/protocol-types/src/extension-loader.ts`, CC2a) orders
  infra→experience, builds the provides-registry, fail-closes on
  unmet cartridge-consumes; the cartridge-license gate
  (`identity-adapters/cartridge-license.ts`, `setLicenseGate`)
  license-gates each; verbs/handlers register into the dispatcher +
  hat registry; the served set is advertised at `GET /api/v1/info`
  `cartridges[]` (CC2b — `info_http.zig` + `extension_manifest_loader.zig`
  grown to `cartridge.json` parity + `serve.zig` population).
- **PWA shell** — `apps/semantos` (Flutter). Each
  `*_experience` self-registers a `CartridgeEntry` into
  `CartridgeRegistry` (`packages/cartridge_sdk`, CC2c); the
  Flutter-free identity half is `CartridgeDescriptor` in
  `platforms/flutter/semantos_core`. `semantos_router.dart` is generic
  — routes built from the registry filtered by the Brain's
  `/api/v1/info` served ids; adding a cartridge needs no router/main
  logic edit.

The cross-shell seam is the **shared cartridge id**: the Brain serves
it (`/api/v1/info cartridges[].id`), the PWA registry routes the same
id. CC3 asserts both sides against `oddjobz`.

## 2. What CC4 must excise

| Excise | Replace with |
|---|---|
| The 5-home split: `extensions/<id>`, `apps/world-apps/<id>`, `packages/<id>_experience` (+ the `apps/` grab-bag) | one `cartridges/<id>/` per cartridge: `cartridge.json` + `brain/` + `experience/` |
| Legacy `manifest.json` filename | `cartridge.json` (loaders already prefer it) |
| Hand-kept `lexicons.yml` as a parallel truth | rendered/derivation-gated from the Lean/TS source (CC0b gate already enforces no-drift) |
| The §9 hand-maintained Zig cap mirror (`extensions.zig ODDJOBZ_CAPS`) | generated from the cartridge's `capabilitiesPath`; the §9 conformance rebased to manifest→generated |
| `apps/` as a cartridge home | `apps/` keeps ONLY non-cartridges: the shell binary (`semantos-shell`), `legacy-cli`, demos, dev tooling |
| "app/extension/adapter" in code/comments/docs vocabulary | "cartridge" (informal English aliases only) |

**Already retired / do not reintroduce:** the legacy bearer token
(deleted, P2 `387e5cd`); `mintFirstBootCapabilities` as authority
(NL-2 — corrected, deferred to D-O5p; it is *device-pair cap
provisioning* only, not dispatch-load-bearing); the deferred
manifest cap-schema "Option A" (dropped).

## 3. How to declare a cartridge

### Infra cartridge (provides an adapter interface) — e.g. wallet/headers

```jsonc
// cartridges/wallet-headers/cartridge.json   (live example:
//   apps/wallet-browser/cartridge.json, CC1 065e322)
{
  "id": "wallet-headers",
  "name": "Wallet & Headers",
  "version": "0.1.0",
  "role": "infra",                         // ⇒ MUST declare `provides`
  "provides": ["@semantos/protocol-types/ports#SpvVerifier"],
  "consumes": { "StorageAdapter": "required — header/output store" }
  // infra is EXEMPT from taxonomyPath/flowsDir/promptsDir
}
```
Brain part implements the provided port (e.g.
`spv-verifier.ts HeadersSpvVerifier implements SpvVerifier`,
dependency-clean: the port is in `core/protocol-types`, the impl in
the cartridge). No PWA `experience` unless it has UI.

### Experience cartridge (a vertical) — e.g. oddjobz

```jsonc
// cartridges/oddjobz/cartridge.json  (live: extensions/oddjobz/manifest.json
//   post-CC3 60522dd — role/experience added)
{
  "id": "oddjobz",
  "name": "Oddjobz",
  "version": "0.1.0",
  "role": "experience",
  "experience": { "flutterPackage": "packages/oddjobz_experience" },
  "taxonomyPath": "...", "flowsDir": "...", "promptsDir": "...",
  "capabilitiesPath": "src/capabilities.ts",
  "verbs": [ { "name": "jobs.transition", "capability_required": "cap.oddjobz.dispatch" } ],
  "consumes": { "StorageAdapter": "required", "IdentityAdapter": "required" },
  "licenseOutpointRef": "<txid>:<vout>",   // omit ⇒ unlicensed unless
  "licenseLinearity": "AFFINE"             //   first-party escape hatch
}
```

### The PWA-experience side (Flutter)

The experience package declares one `CartridgeEntry` + a
`register<X>Cartridge()` and self-registers (live:
`packages/oddjobz_experience/lib/src/cartridge.dart`, CC2c):

```dart
import 'package:cartridge_sdk/cartridge_sdk.dart';
const oddjobzCartridge = CartridgeEntry(
  descriptor: CartridgeDescriptor(
    id: 'oddjobz', role: 'experience',
    routePath: '/oddjobz', title: 'Oddjobz'),
  icon: Icons.work_outline,
  buildScreen: (_) => const OddjobzScreen());
void registerOddjobzCartridge() =>
  CartridgeRegistry.instance.register(oddjobzCartridge);
```
pubspec adds `cartridge_sdk` (path dep). The shell `main.dart`
bootstrap calls `register<X>Cartridge()` once (the single
manifest-like list; router LOGIC never edited per cartridge — a future
step may codegen this list from the installed manifests). **The
Flutter `id` MUST equal the Brain `cartridge.json` `id`** — that is
the cross-shell contract (CC3 asserts it both sides).

## 4. Multiple cartridges, one Brain + one PWA shell

There is exactly one Brain shell process and one PWA shell app; both
load N cartridges from the *same* `cartridge.json` set:

- **Brain:** `enumerateUserInstalled(data_dir)` discovers every
  `cartridges/<id>/cartridge.json`; `resolveCartridgeOrder` topologically
  orders them (all `infra` before `experience`; unmet
  cartridge-consume ⇒ fail-closed; runtime adapters
  Storage/Identity/Anchor/Network exempt as host-injected); each is
  license-gated then its verbs/handlers register into the one
  dispatcher + hat registry; `/api/v1/info cartridges[]` lists the
  served set. Adding a cartridge = drop a directory; no Brain code
  change.
- **PWA:** every experience self-registers into the one
  `CartridgeRegistry`; the generic router renders
  `registry.served(brainServedIds)` — only cartridges the Brain
  actually serves (and that are licensed) route/appear. Adding a
  cartridge = pubspec dep + one register call; no router/main logic
  edit.

Multi-tenancy/hats compose across cartridges via the existing hat
registry (unchanged). N cartridges, one shell each, zero per-cartridge
shell logic.

## 5. Inter-cartridge calls (e.g. calling the wallet)

**Rule (Decision B): cartridges interact only through typed
`provides`/`consumes` adapter interfaces — never by reaching into
another cartridge's internals, and never via a cartridge `extends`
edge.**

- An **infra cartridge** (wallet/headers) `provides` a typed port
  (`@semantos/protocol-types/ports#SpvVerifier`, and similarly a
  wallet/UTXO port). The Brain resolver binds it into the
  provides-registry at load.
- A consumer (an experience cartridge, or the cartridge-license gate
  itself) names the interface in `consumes` and receives the bound
  implementation — e.g. the cartridge-license gate consumes the
  wallet/headers `SpvVerifier` to verify a license UTXO is unspent
  (CC1+CC3: the gate calls the *real* `HeadersSpvVerifier`, not a
  stub).
- **Runtime adapters** (`StorageAdapter`, `IdentityAdapter`,
  `AnchorAdapter`, `NetworkAdapter`, `wssSubprotocolRegistry`) are
  host-injected by the shell, not cartridge-provided — they are exempt
  from the unmet-consume check; a cartridge just declares it consumes
  them and the shell wires the concrete adapter (the existing
  NodeConfig adapter resolution; PWA: `SemantosPlatform.of(context)`).
- On the **PWA side**, an experience never imports another
  experience; shared services come from `SemantosPlatform.of(context)`
  (wallet/conversation/grammar/hat) — the same composition rule as the
  Brain side.

Net: "call the wallet" = declare `consumes` the wallet/headers
provided port; the shell binds the concrete infra cartridge's
implementation. No direct cross-cartridge imports.

## 6. CC4 execution recipe (per cartridge, one PR each)

Commission discipline: **one PR per cartridge, gates green every
commit, golden-path-first** (oddjobz already done — CC3 is the
template). Per cartridge:

1. `mkdir cartridges/<id>/`; write `cartridge.json` (role-correct;
   experience ⇒ `experience.flutterPackage`; infra ⇒ `provides`,
   no taxonomy/flows/prompts).
2. Move the Brain part → `cartridges/<id>/brain/`; move/point the
   Flutter part (keep the `_experience` package, just bind it via
   `experience.flutterPackage`; physical move optional/last).
3. Repoint pubspec/build paths; add the `register<X>Cartridge()`
   bootstrap line if experience.
4. Delete the old `extensions/<id>` / `apps/world-apps/<id>` location.
5. Run gates (§7). Commit scoped. Owner sign-off = the cartridge's
   license-UTXO holder (first-party = brain-core/Todd, in-PR).

**Inventory (triage required — NOT all are cartridges):**
- `extensions/` (22): only `oddjobz`✓(done) + `bsv-anchor-bundle`
  carry a manifest today; the other 20 (calendar, cdm, scada, scg,
  metering, navigation, recovery, …) need a triage pass — is each a
  cartridge (gets a `cartridge.json` + role) or library/tooling
  (stays, not a cartridge)? **This triage is a STOP-worthy decision
  per cartridge family — get the owner/Todd call; do not guess.**
- `apps/world-apps/`: jam-room, swarm-pso-chess → experience
  cartridges (jam-room ↔ `jam_experience`).
- `packages/*_experience`: oddjobz✓, jam, tessera → the PWA halves;
  bind via `experience.flutterPackage`, then collapse.
- `apps/` grab-bag (~17): triage — `wallet-browser`→infra cartridge
  (CC1 done, relocate), `semantos-shell`=the shell (NOT a cartridge),
  `legacy-cli`/demos/`loom-*`/`mud`/`piggybank`/`poker-agent`/`world-client`
  = non-cartridge tooling/clients (stay) or their own cartridges —
  **another triage decision, surface it.**

## 7. Gates that MUST stay green every CC4 commit

- Greenfield: `no-tessera-in-brain-core`, `namespace-partition-single-source`,
  `domain-flag-page-registry`.
- CC0b `lexicon-canon-derivation` (no canon drift).
- `cartridge-manifest` / `cartridge-resolver` / `cartridge-license` /
  `cc3-oddjobz-golden-path` (the model conformances).
- K15 / K3 / NL-1 license-policy suites (the proven substrate).
- `dart analyze` on every touched Flutter package; `zig build test -j1`
  if brain Zig touched; `bun run check` where TS touched.
- The cross-shell id contract (Brain manifest id == PWA registry id).

## 8. STOP conditions for the CC4 executor

Per the commission, STOP + write the note + an actionable question
when: a per-cartridge triage needs an owner/Todd call (which
`extensions/*` and `apps/*` are cartridges vs tooling); the
`unification-matrix.yml` row (it is a **schema-bound renderer file —
do NOT blind-edit**; the matrix row is an explicit canon task done
with the renderer in the loop); a cartridge has no §9 cap mirror and
its caps' source-of-truth is unclear; a directory move breaks a
greenfield gate and the fix needs a design call. Do **not** force a
sprawling multi-cartridge move in one PR or fake a binding.

---

*The model is proven end-to-end (CC3, both shells, real seams). CC4 is
mechanical-but-broad: per-cartridge, gates-green, owner-signed,
golden-path-first — with the triage + matrix-renderer + cap-mirror
items explicitly surfaced for decisions rather than guessed.*
