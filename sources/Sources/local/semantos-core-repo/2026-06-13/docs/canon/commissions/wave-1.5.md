---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/canon/commissions/wave-1.5.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.757895+00:00
---

# Wave 1.5 — Foundational Identity Contract (engineering)

**Audience:** Claude Code (orchestrator) and the parallel-agent fleet it dispatches.
**Author:** Todd Price, RBS.
**Date:** 2026-04-26.
**Companion to:** `docs/canon/commissions/wave-1.md` (documentation, in flight).
**Milestone:** Wave 1.5 unified landing — both this commission and Wave 1 docs merged.

---

## 1. Mission

Land the engineering work that closes axis A (Identity) of the Unification Matrix across every adapter surface. When this commission completes, every cross-process and cross-node message in the substrate is BRC-100-signed and BRC-52-cert-bound; the per-node sidecar topology decision (per Roadmap §8 Q3) is in production; and boot-sequence steps 1–8 advance from "feasibility" to "enforced under proper BRC verification."

**This is the engineering twin of Wave 1.** The two run in parallel. Wave 1 (documentation) drafts a snapshot of the substrate as it stands today. Wave 1.5 (this commission) advances the substrate to the next milestone. The two merge into a unified Wave 1.5 milestone:

- All 31 Wave 1 docs PRs merged.
- All 12 Wave 1.5 engineering PRs merged.
- Matrix `unification-matrix.yml` shows axis A ✓ for every adapter row.
- Boot sequence steps 1–3 (identity) and step 8 (Verifier Sidecar) are enforced under proper BRC verification.
- A milestone tag (`wave-1.5-landed`) is cut on `main`.

The wave is **mostly parallelisable**. Phase 0.5 + Phase 1a are sequential prerequisites (~3–5 days of focused single-thread engineering). Once they land, Phase 1b's seven per-surface deliverables run fully in parallel — same shape as the 7+7 monolith refactor wave Todd has already proven.

---

## 2. Canonical inputs (read-only by every agent)

Same input set as Wave 1, with added authority for `core/` and `runtime/` source. Engineering agents may read more broadly than docs agents (they need to understand the surface they are modifying), but the canonical specification of what they are building is fixed.

| Doc | Path | Role |
|---|---|---|
| Doc plan | `docs/SEMANTOS-DOC-PLAN.md` | Strategic context for the documentation track this engineering work pairs with. |
| Unification Roadmap (v0.3) | `docs/prd/UNIFICATION-ROADMAP.md` | The matrix, §5 deliverables (authoritative for IDs, scope, acceptance), §8 governance resolutions, §9 file-path crosswalk. |
| Canon | `docs/canon/` | `glossary.yml` is normative for terminology. `unification-matrix.yml` is the live state-tracker every PR must update. `deliverables.yml` is the structured per-deliverable record (currently empty — populated by this wave). |
| Protocol Spec v0.5 | `docs/spec/protocol-v0.5.md` | Authoritative for wire formats, identity protocol (§4), capability tokens (§5), Verifier Sidecar (§9.5), SignedBundle envelope (§12.1). Engineering MUST conform to this spec; deviations require a spec amendment first. |
| Whitepaper v3 | `docs/Semantos-Whitepaper-v3-DRAFT.md` | Voice template + headline architecture; cite when explaining adapter surfaces. |
| Plexus Tech v1.3 | (in user's local archive; PDFs at `~/Library/.../uploads/` if needed) | Source for any identity-protocol detail not absorbed into spec v0.5. |

Engineering agents may additionally read source code under:

- `core/cell-engine/src/` (Zig 2-PDA, BCA, opcodes, linearity)
- `core/protocol-types/src/` (TypeScript type contracts; new `namespace.ts` lands here per §8 Q2)
- `core/plexus-vendor-sdk/src/` (BRC-42 client crypto)
- `core/plexus-contracts/src/` (BRC-52 cert types, transport types)
- `runtime/session-protocol/src/` (the six-piece session skeleton)
- `runtime/intent/src/` (the intent pipeline)
- `runtime/shell/src/` (shell verbs, intent adapter)
- `runtime/services/src/` (Loom services)
- `extensions/calendar/src/domain/hat.ts` (the hat / facet implementation)
- `apps/world-host/lib/world_host_web/user_socket.ex` (Phoenix socket; D-A1 target)
- `apps/world-client/src/socket.ts` (TS client; D-A2 target — note post-refactor path per §9 of roadmap)
- `apps/loom-react/src/canvas/` (Helm; D-A3 target)
- `apps/settlement/` (D-A6 target — note the matrix has Settlement at A6 ✓ on identity, so D-A6 in §5 of the roadmap actually targets Extensions/Policy at A7×A)
- `tests/gates/` (CI architectural gates)

Anything not in the canonical or supporting lists is OUT OF SCOPE for the agent's input set. Each agent's brief specifies the exact paths in scope.

**Wave 0 prerequisite:** Wave 1.5 dispatches ON TOP OF the canon snapshot dated 2026-04-26 (post canonical-decision pass + protocol v0.5 cut + Roadmap v0.3 §8 resolutions). All those artifacts exist on disk on branch `chore/docs-wave-1-landing` (or wherever it merges). Confirm before dispatch.

---

## 3. Per-agent brief template

Every agent in this wave receives a brief in the following shape. The orchestrator generates one brief per row of the §7 manifest by filling the placeholders.

```
DELIVERABLE:     <D-V1 | D-V2 | D-V3 | D-A0 | D-A0b | D-A1 | D-A2 | D-A3 | D-A4 | D-A5 | D-A6 | D-A7>
TITLE:           <from §7>
PHASE:           <0.5 | 1a | 1b>
SEQUENCING:      <sequential — must land before <X> | parallel after <Y> lands>

CANON DISCIPLINE (binding):
  - Use only the canonical alias for every term in docs/canon/glossary.yml.
  - Cite K-invariants (K1–K10) by canonical id.
  - Cite BRC standards (BRC-100, BRC-108, …) by canonical id.
  - PR description includes a "Canon discipline: passed" line confirming
    the glossary check.

INPUTS (closed set — do not read outside this list):
  - <ordered list from §7 manifest>

WHAT TO BUILD: <verbatim from §7 manifest>

ACCEPTANCE CRITERIA (the orchestrator enforces these before merge):
  1. Implementation lands at the path(s) listed in §7.
  2. Tests for the deliverable land in the corresponding test path(s).
  3. CI gate `bun run check` passes (TS type check).
  4. CI gate `bun run build` passes.
  5. CI gate `bun test tests/gates/import-boundaries.test.ts` passes
     (architectural import boundaries).
  6. Deliverable-specific tests listed in §7 pass.
  7. The deliverable's matrix cell is updated in the SAME PR:
     `docs/canon/unification-matrix.yml` for the (surface, axis)
     pair moves from ⚠ or ✗ to ✓.
  8. The deliverable's structured record is added in the SAME PR:
     `docs/canon/deliverables.yml` gains an entry with
     {id, title, phase, status: completed, owner, deps, pr_url}.
  9. PR description cites the documentation chapter / spec section
     that describes this surface (cross-reference to Wave 1 docs).
 10. PR description names every BLOCKED: item if any.

DELIVERABLE PR:
  base:    <main | post-1a-base for 1b deliverables>
  branch:  <feat/D-XX-short-slug>
  title:   <feat(D-XX): short slug>
```

---

## 4. Voice and style constraints (binding on every agent)

Engineering agents inherit Wave 1's discipline plus engineering-specific conventions:

- **Code style** matches the surface being modified. Zig conventions for `core/cell-engine/`. TypeScript strict mode for `core/`, `runtime/`, `extensions/`, `apps/`. Elixir / OTP idioms for `apps/world-host/`. Prettier defaults already enforced via the workspace.
- **Test discipline:** every deliverable lands with tests. New TypeScript code uses `bun test` with the existing test layout (`__tests__/` co-located with source). New Elixir code uses ExUnit per the existing world-host conventions.
- **Type safety:** TypeScript code MUST compile under `bun run check` with no errors. New types go in `core/protocol-types/` if shared across tiers; per-package types stay in the package.
- **Import-boundary respect:** the `tests/gates/import-boundaries.test.ts` gate enforces tier rules (`core/` imports nothing outside `core/`, etc.). Deliverables that need to bend a rule must update the gate's allowlist with a `TODO:` migration note.
- **No new third-party runtime dependencies** without explicit approval. The substrate already vendors `@bsv/sdk`, `wallet-toolbox`, and the BRC suite — that's the surface for cryptographic work.
- **No competitor naming** in code comments or PR descriptions (same rule as Wave 1).
- **Conformance-first:** if a deliverable corresponds to a section of the protocol spec v0.5, it MUST conform to that section. Spec deviations require amending the spec first (a separate PR), not silently diverging in code.

---

## 5. Glossary discipline (mandatory)

Same rules as Wave 1. The drift-pair auto-fail list (cell vs object, hat vs facet, capability vs permission, governance domain vs trust domain, Helm vs Loom) applies to commit messages, PR descriptions, code comments, and any new documentation written as part of this commission.

Code identifiers in existing source MAY use legacy names (e.g., `LoomObject`, `loom-react`) where they are part of the established codebase and a rename is out of scope for the deliverable. New code MUST use canonical aliases.

---

## 6. Coordination rules

**One PR per deliverable.** No agent merges its own; the human owner reviews and merges.

**Branch naming:** `feat/D-XX-<short-slug>` (e.g., `feat/D-V1-verifier-stub`, `feat/D-A1-world-host-cert`). Branch off `main` for Phase 0.5 + 1a; branch off the post-1a base (the merge commit of D-A0 + D-A0b) for Phase 1b.

**Sequencing — strict for Phase 0.5 + 1a:**

```
D-V1  ──┐
D-V2  ──┼─→ merge as Phase-0.5 base ──┐
D-V3  ──┘                             │
                                      │
                                      ├─→ post-1a base
D-A0  ──┐                             │   ↓
D-A0b ──┴─→ merge as Phase-1a base ───┘   Phase-1b parallel dispatch:
                                          D-A1, D-A2, D-A3, D-A4, D-A5, D-A6, D-A7
```

The orchestrator MUST block Phase-1b dispatch until Phase 0.5 and Phase 1a are both merged into the post-1a base. Phase-1b agents branch off the post-1a base, not off `main`.

**Within Phase 0.5:** D-V1 (the interface + reference impl) lands first; D-V2 (topology decision — already resolved per §8 Q3 as "per-node sidecar process default") is documentation + deployment-config work; D-V3 (first integration into World Host) lands last in this phase, after D-V1.

**Within Phase 1a:** D-A0 (shared BCA library) and D-A0b (BRC-52 cert flow contract) can land in either order; both must merge before Phase 1b dispatches.

**Within Phase 1b:** all seven deliverables run fully in parallel. Each touches its own surface; no cross-surface conflicts expected.

**File ownership:** each PR touches its own surface plus `docs/canon/unification-matrix.yml` and `docs/canon/deliverables.yml`. Only one PR may modify the matrix or deliverables YAML per merge — handle conflicts via rebase, not by holding the merge.

**Failure handling:** an agent that cannot satisfy a deliverable (e.g., spec v0.5 is silent on a needed detail, or a test gate is incompatible with the implementation pattern) MUST submit a `BLOCKED:` PR with the specific blocker. The human owner resolves blockers; the agent is then re-dispatched.

**Coordination with Wave 1 docs:** PRs in this commission MUST cite the Wave 1 chapter that describes the surface they modify (e.g., `feat/D-A1-world-host-cert` cites `docs/textbook/16-world-host-regions.md`). When a Wave 1.5 deliverable lands first, the docs chapter may need a touch-up to reflect the new surface state — this is handled in a small post-wave docs cleanup pass, not blocked here.

---

## 7. Wave 1.5 manifest

12 deliverables. 5 sequential (Phase 0.5 + 1a). 7 parallel (Phase 1b).

### 7.1 Phase 0.5 — Verifier Sidecar (sequential, blocking)

| ID | Title | Inputs | What to build | Tests | Matrix cell |
|---|---|---|---|---|---|
| **D-V1** | VerifierStub interface + reference implementation | `docs/spec/protocol-v0.5.md` §9.5; `core/protocol-types/src/transport.ts`; `core/plexus-contracts/src/identity.ts`; `core/plexus-vendor-sdk/` | Define the BRC-100 verification interface as a TS interface in a new `packages/verifier-sidecar/` (or `runtime/verifier-sidecar/` per tier — engineering judgment, see §9 of roadmap). Reference impl performs BRC-100 signature check, BRC-52 cert authenticity, identity binding (signing key matches `certificate.subject`), and SPV checks for capability UTXOs via `@bsv/sdk`. | `__tests__/verifier-sidecar.test.ts` covers: valid signed-bundle accepted; bad signature rejected; bad cert authenticity rejected; identity-binding mismatch rejected; SPV-spent capability rejected; constant-time comparison enforced. Minimum 12 unit tests. | U5×A becomes ✓ |
| **D-V2** | Deployment topology decision (codification) | `docs/prd/UNIFICATION-ROADMAP.md` §8 Q3 (resolved: per-node sidecar process default); `docker-compose.yml` | Ship a `docker-compose.sidecar.yml` for the per-node default; document in-process and edge-gateway alternatives in `runtime/verifier-sidecar/README.md`. Topology decision was already made (§8 Q3); this deliverable codifies it in deployable form. | Integration test: stand the sidecar up via docker-compose; assert health-check response. | (no matrix cell — deployment artefact) |
| **D-V3** | First integration: World Host consumes VerifierStub | `apps/world-host/lib/world_host_web/user_socket.ex`; the new `runtime/verifier-sidecar/` package from D-V1; `docs/canon/glossary.yml` § verifier-sidecar | Wire the VerifierStub into the World Host's `UserSocket.connect/3`. Replace the random `session_id` with BRC-52-cert-bound identity. Derive BCA from the cert and expose as `socket.assigns.bca`. This is the integration template every other adapter follows. | Existing world-host tests pass with stub in test mode. New test: connection without a valid BRC-52 cert is rejected; connection with a valid cert sets `socket.assigns.bca` deterministically. | A1×A status moves from ⚠ to "in flight" (not ✓ until D-A1 lands) |

| ID | Branch | PR title | Sequencing |
|---|---|---|---|
| D-V1 | `feat/D-V1-verifier-stub` | `feat(D-V1): VerifierStub interface + reference implementation` | First — blocks D-V3 |
| D-V2 | `feat/D-V2-sidecar-topology` | `feat(D-V2): codify per-node sidecar topology default` | Parallel with D-V1 |
| D-V3 | `feat/D-V3-world-host-verifier-integration` | `feat(D-V3): integrate VerifierStub into World Host UserSocket` | After D-V1 — establishes the integration template |

### 7.2 Phase 1a — Foundational identity contract (sequential)

| ID | Title | Inputs | What to build | Tests | Matrix cell |
|---|---|---|---|---|---|
| **D-A0** | Shared BCA library (TypeScript) | `core/cell-engine/src/bca.zig`; `core/cell-engine/tests/vectors/bca_*.json`; `docs/spec/protocol-v0.5.md` §4.3 | TS package implementing BCA derivation byte-for-byte identical to the Zig reference. Used by every adapter that needs to derive identity. Lives in `core/protocol-types/src/bca.ts` (or as its own package per engineering judgment). | Conformance: every vector in `bca_*.json` passes. Property test: 1000 random certs produce IPv6 strings within the BCA spec format. | U3×A enriched (TS mirror of Zig BCA); enables every D-A* deliverable |
| **D-A0b** | BRC-52 cert flow contract (canonical types) | `docs/spec/protocol-v0.5.md` §4.2; Plexus Tech v1.3 §15; existing `core/plexus-contracts/src/identity.ts` | Canonical TS types for cert payloads, registration flow, and verification headers. Mirror to Elixir for world-host consumers via a `lib/plexus_contracts/identity.ex` (or similar). Lock the canonical preimage serialisation so `cert_id = SHA-256(canonical_preimage)` is deterministic across both languages. | TS: 100 random certs round-trip through the canonical preimage; `cert_id` is byte-identical across re-serialisation. Elixir: same vectors produce byte-identical `cert_id`. | U3×A complete (cross-language cert contract sealed) |

| ID | Branch | PR title | Sequencing |
|---|---|---|---|
| D-A0 | `feat/D-A0-bca-ts-library` | `feat(D-A0): shared BCA library (TypeScript mirror of Zig)` | After Phase 0.5 |
| D-A0b | `feat/D-A0b-cert-flow-contract` | `feat(D-A0b): BRC-52 cert flow contract (TS + Elixir)` | After Phase 0.5; parallel with D-A0 |

### 7.3 Phase 1b — Per-surface identity (parallel after Phase 1a)

Every Phase 1b deliverable follows the integration template established by D-V3 (World Host → VerifierStub). Each surface gets cert-bound identity at its session-establishment point.

| ID | Surface | Title | Inputs | What to build | Tests |
|---|---|---|---|---|---|
| **D-A1** | A1 World Host | World Host accepts BRC-52 cert at WS connect | `apps/world-host/lib/world_host_web/user_socket.ex`; D-V3 integration template; D-A0b cert flow contract | Replace the random `session_id` in `UserSocket.connect/3` with BRC-52 verification via the VerifierStub sidecar. Derive BCA from `cert_id`. Expose as `socket.assigns.bca`. (D-V3 may have already done part of this; this deliverable completes the production path.) | Existing world-host tests pass. New: connection without cert → reject; cert with bad signature → reject; valid cert → `socket.assigns.bca` deterministically derived. `grep -r "session_id\|random_bytes" apps/world-host/lib/world_host_web/user_socket.ex` returns zero matches in identity paths. |
| **D-A2** | A2 World Client | World Client signs every action with the user's cert | `apps/world-client/src/socket.ts` (or post-refactor: `apps/navigation-app/world-client/src/socket.ts` — verify via §9 of roadmap); D-A0 BCA library | Replace random `session_id` in TS client with cert-based signing using the Plexus Network SDK. Sign every outbound action; verify the server's response signature. | Unit tests: every emitted action carries a valid BRC-100 signature. Integration test (against D-A1 server): client connects with cert, server accepts, ping-pong of signed actions. |
| **D-A3** | A3 Helm | Helm wires to Plexus identity | `apps/loom-react/` (post-refactor: `apps/navigation-app/chat-shell/`); D-A0 BCA library; `runtime/services/src/services/IdentityStore.ts` | Helm boots after Plexus identity has issued a cert; Helm uses the cert to authorise its own backend calls. The intent pipeline already has `buildHatContext`; D-A3 extends it to require a real cert (currently uses a stub in dev mode). | Existing intent-pipeline tests pass. New: dev-mode stub is gated behind an explicit env flag; production path requires a real cert; cert absence → boot fails fast with a clear error. |
| **D-A4** | A4 Md Editor | Md Editor identifies authors via `cert_id` | (Md Editor is in design — first stub this if necessary, then add cert binding); D-A0b cert flow contract | Every patch in a markdown doc carries the author's `cert_id`. Replaces any opaque user-id field. If the Md Editor surface is not yet built, this deliverable lands the cert-bound stub interface that future Md Editor work consumes. | Unit tests: patch creation requires a cert; patches carry verifiable author signatures; cert absence → patch rejected. |
| **D-A5** | A5 Calendar | Calendar Hat → BRC-52 migration | `extensions/calendar/src/domain/hat.ts`; D-A0b cert flow contract; canon `glossary.yml` § hat | Migrate `HatPayload` / `HatRecord` to BRC-52 cert backing: `cert_id` replaces the opaque `hatId`; `HatPayload` becomes a BRC-52 schema attached to the `cert_id`. Preserves existing semantics, gains cryptographic provenance. | Existing calendar tests pass. New: HatPayload round-trips through cert_id derivation; cross-context hat isolation per §4.4 of spec v0.5 holds (keys derived in two contexts are not mathematically related). |
| **D-A6** | A7 Extensions | Extensions runtime certs lexicon-authority via `cert_id` | `extensions/policy-runtime/`; `core/semantos-sir/`; D-A0b cert flow contract | Extensions that mint capabilities or define lexicons MUST do so under a BRC-52-anchored authority cert. Replace any current "trusted issuer" string with cryptographic binding. The active extension's domain grammar (per intent-pipeline) is signed by the issuer's cert; lowering refuses extensions whose authority cert fails verification. | New: extension load path requires authority cert; cert absence or invalid signature → extension load rejected. Existing extension tests pass with valid certs supplied. |
| **D-A7** | A8 Voice | Voice input session identifies via BRC-52 (placeholder) | `runtime/intent/src/intent-adapters/llm-classifier.ts`; D-A0b cert flow contract | Voice (A8) is a placeholder surface in the matrix; this deliverable lands the cert-bound interface that future voice work consumes. Sessions are cert-bound; transcripts carry the speaker's `cert_id`. If voice transcription is not yet wired, the deliverable is a stub interface + unit tests. | Unit tests: voice-session producer rejects sessions without a cert; transcript outputs carry the cert_id. |

| ID | Branch | PR title | Matrix cell |
|---|---|---|---|
| D-A1 | `feat/D-A1-world-host-cert-binding` | `feat(D-A1): World Host cert-bound identity` | A1×A → ✓ |
| D-A2 | `feat/D-A2-world-client-cert-signing` | `feat(D-A2): World Client signs every action` | A2×A → ✓ |
| D-A3 | `feat/D-A3-helm-plexus-identity` | `feat(D-A3): Helm wires to Plexus identity` | A3×A → ✓ |
| D-A4 | `feat/D-A4-md-editor-cert-authors` | `feat(D-A4): Md Editor patches identify authors via cert_id` | A4×A → ✓ |
| D-A5 | `feat/D-A5-calendar-hat-brc52` | `feat(D-A5): Calendar Hat → BRC-52 migration` | A5×A → ✓ |
| D-A6 | `feat/D-A6-extensions-lexicon-authority` | `feat(D-A6): Extensions lexicon-authority via cert_id` | A7×A → ✓ |
| D-A7 | `feat/D-A7-voice-cert-session` | `feat(D-A7): Voice input session identifies via BRC-52` | A8×A → ✓ |

---

## 8. Summary tally

| Block | Deliverables | Phase | Sequencing |
|---|---|---|---|
| Phase 0.5 (Verifier Sidecar) | D-V1, D-V2, D-V3 | 0.5 | sequential (~3 days) |
| Phase 1a (foundational identity contract) | D-A0, D-A0b | 1a | sequential after 0.5 (~2 days) |
| Phase 1b (per-surface identity) | D-A1, D-A2, D-A3, D-A4, D-A5, D-A6, D-A7 | 1b | parallel after 1a (~2–4 days bounded by slowest) |
| **Wave 1.5 total** | **12 deliverables** | | **~7–9 days end-to-end** |

When all 12 land:

- Matrix axis A (Identity) is ✓ for U1, U2, U3, U4, U5, U6, U7, U8, U9, U10 (substrate) AND A1, A2, A3, A4, A5, A6, A7, A8 (every adapter).
- Boot sequence steps 1, 2, 3 (root key derivation, BRC-52 cert, BCA) and step 8 (Verifier Sidecar) are enforced under proper BRC verification.
- The Verifier Sidecar is in production at the per-node default topology.
- Every cross-process or cross-node message carries a verifiable BRC-100 signed envelope.
- The substrate has cert-bound identity end-to-end. Phase 2 (Transport — `SignedBundle` on every message) becomes parallelizable per surface.

---

## 9. Acceptance gate (orchestrator-runnable, per PR)

For each PR, the orchestrator runs the 10-item acceptance check from §3 verbatim. Concrete checks:

```sh
# Gates 1–6: build + test + architectural

bun install
bun run check                                   # gate 3
bun run build                                   # gate 4
bun test tests/gates/import-boundaries.test.ts  # gate 5
bun test ${DELIVERABLE_TEST_PATHS}              # gate 6

# Gate 7: matrix update in the PR

git diff main..HEAD -- docs/canon/unification-matrix.yml \
  | grep -q "${MATRIX_CELL}" \
  || fail "matrix cell ${MATRIX_CELL} not updated in this PR"

# Gate 8: deliverables.yml entry in the PR

git diff main..HEAD -- docs/canon/deliverables.yml \
  | grep -q "id: ${DELIVERABLE_ID}" \
  || fail "deliverables.yml entry for ${DELIVERABLE_ID} not added in this PR"

# Gate 9: PR description cites the documentation chapter or spec section

# (orchestrator parses PR description for a "Cites:" line containing
#  the Wave 1 chapter path or the spec v0.5 section number)

# Gate 10: glossary discipline (same as Wave 1's gate 2)

bun docs/canon/render/glossary-to-md.ts > /tmp/canonical-list.md
# (exception-aware grep against the modified files in the PR)
```

A PR that passes all gates is queued for human review. A failed PR is held with the specific failure surfaced; the agent gets one revision; double-fail escalates to the human owner.

---

## 10. Execution

To dispatch this wave:

1. Confirm the canonical inputs (§2) all exist on disk on the branch `chore/docs-wave-1-landing` (or wherever the canon snapshot lives at dispatch time).
2. Confirm Wave 1 docs commission has dispatched (so the two waves run in parallel).
3. **Phase 0.5 dispatch (sequential):**
   - Dispatch D-V1 first; wait for merge.
   - Dispatch D-V2 in parallel with D-V1 (no shared files).
   - Dispatch D-V3 after D-V1 merges.
   - Merge all three; this is the post-0.5 base.
4. **Phase 1a dispatch (sequential):**
   - Dispatch D-A0 and D-A0b in parallel against the post-0.5 base.
   - Merge both; this is the post-1a base.
5. **Phase 1b dispatch (fully parallel):**
   - Dispatch all seven of D-A1, D-A2, D-A3, D-A4, D-A5, D-A6, D-A7 simultaneously against the post-1a base.
   - Each agent opens its own PR; each PR updates `unification-matrix.yml` and `deliverables.yml`.
6. The orchestrator runs the §9 gate on each PR; failed PRs are returned for one revision.
7. The human owner reviews and merges in any order (no cross-PR dependencies in Phase 1b).

Expected end-to-end duration: ~7–9 days. Phase 0.5 + 1a are bounded by the slowest sequential step (~5 days); Phase 1b is bounded by the slowest single deliverable (~2–4 days).

---

## 11. The Wave 1.5 unified milestone

When BOTH this commission AND Wave 1 docs are merged, cut a milestone tag and a PR description that records the unified state:

```sh
# After all 12 Wave 1.5 PRs and all 31 Wave 1 docs PRs are merged on main:
git checkout main && git pull
git tag -a wave-1.5-landed -m "Wave 1.5 unified milestone

Documentation (Wave 1):
  - 30 textbook chapters drafted (docs/textbook/01..30)
  - Paper A2 drafted (docs/papers/Semantos-A2-Two-IR-Architecture-DRAFT.md)
  - Paper A1 drafted earlier; both papers ready for arXiv submission

Engineering (Wave 1.5):
  - Verifier Sidecar in production at per-node default topology
  - Shared BCA library (TS) ships
  - BRC-52 cert flow contract canonical (TS + Elixir mirror)
  - Every adapter (World Host, World Client, Helm, Md Editor,
    Calendar, Settlement, Extensions, Voice) has cert-bound identity
  - Matrix axis A complete across all surfaces
  - Boot sequence steps 1–3 and 8 enforced under proper BRC verification

Next: Wave 2 — Transport (axis C) + Type (axis D) + Storage (axis B)
parallelisable per surface, paired with chapter touch-ups."

git push origin wave-1.5-landed
```

Update `docs/canon/unification-matrix.yml` to reflect the new state. Update the whitepaper v3's "boot sequence currently halts at step 7" line to "boot sequence currently runs end-to-end through step 8 with full BRC enforcement; steps 9 onward in design for Wave 2." Optionally cut a v3.1 of the whitepaper.

---

## 12. Post-wave

When Wave 1.5 lands, the next obvious commissions:

- **Wave 2 — Transport + Type + Time + Storage (axes B, C, D, E)** — fully integrated docs + engineering, parallel per surface, on top of the post-1.5 cert-bound substrate.
- **Wave 1.5 docs cleanup** — small touch-up pass on the chapters affected by axis A landing (chapters 4, 5, 14, 16, 17, 18 in particular). Probably 6–8 PRs, fast.
- **Whitepaper v3.1** — refresh the production-readiness lines now that boot steps 1–8 are enforced.

A Wave 2 manifest will be drafted after Wave 1.5 completes the unified milestone — the experience of running the first integrated wave will inform refinements to the brief template, the gate, and the parallelisation envelope.

---

*End of Wave 1.5 commission.*
