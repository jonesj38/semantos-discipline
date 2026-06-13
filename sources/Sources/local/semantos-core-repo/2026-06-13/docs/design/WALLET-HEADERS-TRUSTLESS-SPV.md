---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/design/WALLET-HEADERS-TRUSTLESS-SPV.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.741592+00:00
---

# Trustless SPV — WH1–WH6

**Version**: 0.1 DRAFT
**Status**: Plan
**Authors**: Todd
**Related**: `docs/design/WALLET-TIER-CUSTODY.md` (v0.4), `docs/design/WALLET-ACTIVE-USE-ROADMAP.md`, `docs/design/WALLET-W6-W7-NEXT-PHASE.md`

---

## 0. Purpose

Close the last remaining trust dependency in the wallet's verification stack. Today, every BEEF the wallet validates ultimately depends on an *external indexer* (WhatsOnChain, ARC, etc.) for trusted merkle roots. Compromise the indexer, compromise the wallet's view of which transactions are confirmed.

WH replaces this with a **WASM-resident PoW verifier in the browser bundle** that downloads BSV block headers from any source the user trusts to serve real bytes (operator-run, community-run, or self-hosted), validates each header locally via SHA256d + difficulty rules, and serves verified merkle roots to the wallet's BEEF validation path. Source operators are a *delivery mechanism* — they cannot lie because the verifier rejects any header whose PoW is invalid.

After WH ships, the wallet's trust story has zero "external trusted entity" dependencies for SPV. The remaining trust is in math (SHA-256 collision resistance, secp256k1 EUF-CMA — both already axiomatized in the Lean layer).

---

## 1. Where We Are

### 1.1 Current trust map

| Layer | Trust assumption | Coverage |
|---|---|---|
| Per-opcode soundness | Lean K1–K13 (substantive after WP9) | ✅ |
| Multi-step temporal safety | TLA+ KeyCustody / TierEscalation / ReplayPrevention extended | ✅ |
| Engine implementation | Zig conformance + 372/372 fuzz/diff | ✅ |
| Crypto primitive correctness | bsvz differential test | ✅ |
| Binary-to-model linkage | WASM-MANIFEST hash pin | ✅ |
| **SPV merkle-root trust** | **External indexer (WoC, ARC, etc.) — implicit** | ❌ **Empty slot** |

The wallet calls `kernel_verify_beef_spv(beef, txid, trusted_roots)` with merkle roots that have to come from *somewhere*. That somewhere is currently un-spec'd; in practice it'd be WoC. WH closes this.

### 1.2 What block-headers-service provides

`b-open-io/block-headers-service` (Go, "Pulse") connects to BSV peers, downloads headers from genesis to tip, validates the chain (PoW + prev-hash + difficulty), persists to SQLite, and exposes HTTP/WebSocket/webhook endpoints. ~70MB of headers total, ~80 bytes per block, ~860k blocks at BSV mainnet tip.

The service is operator infrastructure — Semantos runs at least one instance as `headers.semantos.app` to provide a default endpoint for the wallet. End users never run it themselves.

### 1.3 The architectural insight

**The header source doesn't have to be trusted because the wallet validates PoW locally on every header.** A malicious operator can serve garbage but the verifier sees `sha256(header) > target` and rejects it. An honest operator can be DoS'd; the wallet falls over to another source. The source is a CDN-for-header-bytes, nothing more.

This means:
- The wallet's WASM verifier runs in every user's browser.
- The header source is configurable (default `headers.semantos.app`, fallback to community / sovereign nodes).
- Operators serve raw bytes; correctness is enforced client-side.

---

## 2. Phases

### WH1 — Zig PoW verifier (~ 2 days)

**Goal**: pure-Zig functions that parse, validate, and chain block headers per BSV consensus rules.

**Deliverables**:

1. New `core/cell-engine/src/headers.zig` (or sibling crate `core/headers/`). Pure functions:

```zig
pub const Header = struct {
    version: u32,
    prev_hash: [32]u8,
    merkle_root: [32]u8,
    timestamp: u32,
    bits: u32,
    nonce: u32,

    pub fn parseRaw(bytes: *const [80]u8) Header;
    pub fn serialize(self: *const Header, out: *[80]u8) void;
    pub fn computeHash(self: *const Header) [32]u8;       // SHA256d(serialized)
    pub fn target(self: *const Header) [32]u8;             // bits → 256-bit target
    pub fn satisfiesProofOfWork(self: *const Header) bool; // hash < target
};

pub const ChainState = struct {
    pub fn validateHeader(parent: *const Header, candidate: *const Header,
                           parent_height: u32, time_window: []const u32) ChainError!void;
    // Checks: candidate.prev_hash == parent.hash, candidate satisfies PoW,
    // candidate.bits is correct per BSV DAA over the past 144 blocks,
    // candidate.timestamp > median(time_window), etc.

    pub fn nextTarget(past_144_headers: []const Header) [32]u8;
    // BSV Genesis difficulty adjustment algorithm — per-block, work-based.
};
```

2. Test corpus: known-good BSV mainnet headers from genesis through several DAA boundaries (~50 representative headers). Cross-checked against bsvz's existing primitives for sanity.

3. Negative tests: malformed headers, prev-hash mismatch, insufficient PoW, timestamp violations, wrong difficulty after DAA — all rejected.

4. Lean spec lift (small, optional but recommended): add `theorem k14_pow_validity_preserved : ChainState.validateHeader => SHA256d(candidate) < candidate.target` to the proof library. Pure structural — single-function unfolding.

**Success criterion**: `zig build test-headers` passes ~30 conformance tests including DAA boundary cases. Differential test against bsvz's chain tracker (if it exposes header validation) on the same corpus.

### WH2 — HeaderStore vtable + LocalHeaderStore (~ 1 day)

**Goal**: pluggable storage layer for verified headers, mirroring the vtable pattern from `DerivationStateStore` / `SlotStore` / `OutputStore`.

**Deliverables**:

1. New `core/cell-engine/src/header_store.zig`:

```zig
pub const HeaderStore = struct {
    ctx: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        get_by_height: *const fn (ctx, height: u32) ?Header,
        get_by_hash: *const fn (ctx, hash: *const [32]u8) ?HeaderRecord,
        append_validated: *const fn (ctx, header: Header, height: u32) anyerror!void,
        tip: *const fn (ctx) ?HeaderRecord,
        snapshot: *const fn (ctx, allocator) anyerror![]HeaderRecord,
        replay: *const fn (ctx, headers: []const HeaderRecord) anyerror!void,
    };

    pub const HeaderRecord = struct { header: Header, height: u32, hash: [32]u8 };
};
```

2. Three planned backings; only `LocalHeaderStore` ships in WH2:
   - `LocalHeaderStore` — IndexedDB (browser) / lmdb (sovereign node), v0.1 ships
   - `PlexusHeaderStore` — v0.2 stub for paid mirroring (Plexus operator runs the headers service)
   - `FederatedSemantosHeaderStore` — v0.3 stub for cross-node header-chain replication

3. `apps/wallet-browser/src/header-store.ts` — `LocalHeaderStore` IndexedDB implementation. Object store keyed by height; secondary index on hash. `append_validated` is atomic — write fails if `prev_hash` doesn't match the current tip.

4. **Important invariant**: `append_validated` only accepts headers that have already been validated by WH1's verifier. The store is *append-only over the verified chain* — no path lets unverified bytes into the store.

**Success criterion**: round-trip a 1000-header sequence through append/get/snapshot/replay. Append-with-bad-prev-hash returns error. Storage usage measured: 1000 headers ≈ 80KB raw, ~120KB with index overhead.

### WH3 — Multi-source HTTPS fetcher (~ 2 days)

**Goal**: download header batches from any configured source, verify each via WH1 before storing. Source list is user-configurable; failover is automatic.

**Deliverables**:

1. `apps/wallet-browser/src/header-fetcher.ts`. Configurable source list (default: `headers.semantos.app`, fallback: WoC, gorillapool). Uses standard `fetch()` for HTTPS.

2. Batch fetch protocol — request `GET /api/v1/chain/header/range?from=H&to=H+N` (matching block-headers-service's API), expect 80-byte headers concatenated. Validates batch via WH1's `ChainState.validateHeader` for each header against the previous (chain-linked).

3. Concurrent multi-source mode: optionally fan out the same request to N sources, prefer the first valid response, log discrepancies. (Disagreement at the byte level is impossible under PoW — but the log surfaces operator misbehavior for transparency.)

4. Resume support: bookmark last verified height in `HeaderStore`. Restart picks up from there. Initial sync from genesis is one large `bookmark = 0` case.

5. Progress reporting via callback — `(currentHeight, tipHeight, bytesDownloaded)` updates for the UI in WH6.

6. Bandwidth budget: ~35MB compressed initial sync; expected ~1-3 minutes on broadband; ~5-15 minutes on slower connections. Document the budget.

7. **Hybrid mode**: when first BEEF validation needs a header at height H that's not in the local store, do a single-header fetch (`GET /header/{H}`) instead of triggering full sync. After N such single-header fetches OR explicit user opt-in, schedule the bulk sync as background task.

**Success criterion**: bulk sync from genesis to a known mainnet height (use a fixed test point, e.g., height 800,000) completes against `headers.semantos.app` (mocked for CI); every header passes WH1 verification; LocalHeaderStore is populated; sync is resumable after simulated interruption.

### WH4 — Tip-following WebSocket subscriber (~ 1 day)

**Goal**: keep the local chain in sync with new blocks as they're mined.

**Deliverables**:

1. `apps/wallet-browser/src/header-tip.ts`. WebSocket connection to `headers.semantos.app/ws` (centrifuge protocol per block-headers-service docs).

2. On new-header notification: receive 80-byte header, validate via WH1 against local tip, append to LocalHeaderStore. If validation fails (orphan, reorg, bad PoW), log, alert wizard banner, fall back to polling for canonical chain reconciliation.

3. Reconnect logic: exponential backoff, max 5 retries, then fall back to polling `/api/v1/chain/header/byHeight/tip` every 60s.

4. Reorg handling: if a new tip's `prev_hash` doesn't match local tip, the wallet has missed blocks. Trigger WH3's range-fetch from `local_tip - K` (K = configurable reorg depth, default 6) to new tip; revalidate; if local chain diverges, drop divergent suffix and re-append from authoritative chain. Surface to user: "Chain reorg detected — N blocks rolled back."

5. Multi-source resilience: if `headers.semantos.app` WS is down, try fallback sources' WS / SSE / poll endpoints. Don't depend on any single operator's uptime.

**Success criterion**: simulated new-block notification arrives, header is validated, appended, tip advances. Simulated reorg of 3 blocks correctly rolls back local chain and replaces.

### WH5 — bsvz chain tracker integration (~ 1 day)

**Goal**: the wallet's existing BEEF validation paths use locally-verified merkle roots from the HeaderStore, not external indexers.

**Deliverables**:

1. New `core/cell-engine/src/local_chain_tracker.zig` implementing bsvz's `chain_tracker` interface. Looks up merkle roots from the HeaderStore. Returns "unknown" (rather than failing) for heights beyond local tip — caller can fall back to WH3's hybrid single-header fetch.

2. Wire into all wallet BEEF validation call sites:
   - `wallet-ops.internalizeAction` (W4 / WA2): replaces gullible mode with `verifyBeefSpv(beef, txid, trusted_roots = LocalHeaderChainTracker.lookup(...))`
   - `wallet-ops.signAction` (W3): if it inspects incoming BEEFs, same swap
   - `wallet-ops.listOutputs` (WA2): no change (reads stored UTXOs, BEEFs already validated at receive time)
   - Any other path currently using `GullibleChainTracker`

3. Strict mode flag: `policy.spv_mode = "strict" | "hybrid" | "gullible"`. Default `"strict"` for new wallets — refuses to accept any BEEF whose merkle path can't be verified against local chain. `"hybrid"` lazy-fetches the missing header. `"gullible"` is the v0.4 escape hatch (kept for testing only, gated behind a console-flag in prod).

4. Conformance tests: every existing BEEF test in `core/cell-engine/tests/` that uses gullible mode now has a strict-mode variant that goes through LocalHeaderChainTracker.

**Success criterion**: all existing BEEF tests pass with `policy.spv_mode = "strict"` after pre-populating the HeaderStore with the relevant headers. Forging a BEEF with a fake merkle root → rejected. Forging a BEEF with a *real* merkle root for a *non-existent* tx → rejected by the per-tx verification (already covered by W4 / WA2).

### WH6 — Wizard integration + UI (~ 1 day)

**Goal**: surface the trustless-SPV story to the user without overwhelming them. Make the source list configurable. Provide the "download full chain" affordance.

**Deliverables**:

1. New SetupStatus item: `HEADERS_SYNCED` with status `NEVER_SYNCED | PARTIAL | UP_TO_DATE`. Shows in the wizard from WA1.

2. Wallet UI badge — small indicator that shows current SPV mode + tip height:
   ```
   ✓ SPV: verified locally · tip 894,231 · source: headers.semantos.app
   ```
   Click → opens the Headers settings panel.

3. Headers settings panel:
   ```
   SPV mode:    ⓘ verified locally via PoW (recommended)
                ○ Strict (refuse unverified BEEFs)
                ● Hybrid (lazy-fetch headers as needed)   ← default
                ○ Gullible (DEBUG ONLY)

   Sources:     ☑ headers.semantos.app          [primary]
                ☑ woc.bitcoin.com                [fallback]
                ☑ headers.gorillapool.io         [fallback]
                + Add custom source
                  https://node.example.com/headers

   Local chain: synced through height 894,231 (tip)
                last update: 12s ago
                
   [ Download full chain for offline use (≈35 MB) ]
   ```

4. First-time user flow:
   - Install wallet → SetupStatus shows `HEADERS_SYNCED = NEVER_SYNCED`
   - First spend → triggers hybrid lazy-fetch, single header retrieved + verified
   - Wizard nudge after N spends or 1 week: "You've made N spends. Download the full chain (35MB) for offline use?"
   - On opt-in → background sync with progress bar; SetupStatus → `UP_TO_DATE`

5. UX honesty: the trust-model pill in the badge is the most important UI surface. "verified locally via PoW" is the wallet's value pitch. Make it visible, hover-explainable, and never hidden by default.

**Success criterion**: wizard shows headers state, settings panel works, source-list is editable, "download full chain" triggers WH3 bulk sync with progress bar that updates in real time.

---

## 3. Default Source — provided by BRAIN `headers serve` (no Go service)

**Earlier drafts of this spec assumed `b-open-io/block-headers-service` (Go) would be deployed as `headers.semantos.app` for v0.1.** That is now superseded — running a Go sidecar is dissonant with the "one Zig binary on a $5 VPS" sovereign-node story (see `WALLET-SHELL-VPS-SUBSTRATE.md`). Instead:

**v0.1 (WH1–WH6 implementation):** the wallet's WH3 fetcher is tested against a hand-rolled bun-side mock that serves a fixture of real BSV mainnet headers. No production source is required to land WH1–WH6 — the wallet code is correct against any compliant source. CI runs against the mock; manual integration testing can hit any operator's existing block-headers-service instance.

**v0.x (post-BRAIN):** `headers serve` ships as a mode of the BRAIN binary (~1000 lines of Zig: P2P client + flat-file storage + HTTP/SSE surface, all reusing `headers.zig` and `header_store.zig`). Then `headers.semantos.app` is a Semantos-operated BRAIN instance with that mode enabled. Every other sovereign-node operator can do the same with a single config line. No Go in the deployment.

### WH-Producer phase 1 — `brain headers sync` ✅ shipped

The producer side of the trustless-SPV story has landed in BRAIN (no Go).  Three commands:

- **`brain headers tip`** — print the current tip's height + display-form hash from `<data-dir>/headers.bin`.
- **`brain headers sync [--peer host:port] [--max-rounds N]`** — connect to a BSV peer over TCP, run a `version`/`verack` handshake, build a Bitcoin-style locator from the current store tip, send `getheaders`, parse `headers` responses, validate each header via `headers.zig.satisfiesProofOfWork`, and append to `header_store_fs.FsHeaderStore`.  Loops until the peer returns a short batch (`< 2000` headers) or `--max-rounds` is reached (default 32 → 64,000 headers per invocation, ~1 month of mainnet activity).
- **`brain headers reset --yes`** — wipe the on-disk header chain.  Operator escape hatch.

Implementation lives in two reader/writer-agnostic modules:

- **`runtime/semantos-brain/src/p2p_wire.zig`** — minimal BSV P2P encode/decode: envelope (magic + 12-byte command + payload size + sha256d-checksum + payload), `version` payload, VarInt, locator-aware `getheaders`, batch `headers`.  4 MiB max payload cap.  Mainnet/testnet/regtest magics defined.  Tests pass `std.Io.Reader.fixed`/`Writer.fixed`; production passes a TCP-stream adapter.
- **`runtime/semantos-brain/src/headers_sync.zig`** — orchestrator: `handshake(reader, writer, magic, ...)`, `fetchOneRound(...)`, `buildLocator(store)` (10 most-recent + exponential-back to genesis).  Each fetched header gets PoW + prev-hash chain-validated; reorgs surface `error.reorg_detected`.

What WH-Producer phase 1 deliberately did NOT ship (handled in phase 2 below):

- **Tip subscription** — phase 2 polls every 60s.  Push-driven `inv` is still phase 3.
- **HTTP serving** — phase 2 ships the BHS-compatible API surface.
- **Auto-reorg** — still phase 3.
- **DAA-vs-bits validation** — still deferred to phase 3 alongside reorg.

### WH-Producer phase 2 — `brain headers serve` ✅ shipped

Closes the trustless-SPV loop for browser clients without any Go in the deployment.  `brain headers serve` is the long-running counterpart to phase-1's one-shot `brain headers sync`:

1. **Background tip-subscription thread** — every `--sync-interval-secs` (default 60) reconnects to `--peer` (default `seed.bitcoinsv.io:8333`), runs handshake + one round of `getheaders`/`headers`, validates, appends.  Logs to stderr.

2. **Foreground HTTP server** on `--http-port` (default 8334) exposing the four endpoints `apps/wallet-browser/src/header-source-adapter.ts` already hits:
   - `GET /api/v1/chain/header/byHeight/tip` → `{"height":N,"hash":"<display-form hex>"}`
   - `GET /api/v1/chain/header/byHeight/{N}` → 80 raw bytes
   - `GET /api/v1/chain/header/byHash/{display-hex}` → 80 raw bytes
   - `GET /api/v1/chain/header/range?from=N&to=M` → concatenated 80-byte headers (cap 2000 per request)

Implementation: `runtime/semantos-brain/src/headers_http.zig`.  Reader/writer-agnostic: a pure `composeResponse(method, target, store, allocator) -> Response` dispatcher backs the test surface; production wraps it with `std.http.Server.Request.respond`.  10 internal conformance tests cover all four endpoints + 4xx error paths.

Live verification: `BRAIN_DATA_DIR=/tmp/brain-smoke brain headers serve --http-port 8334` against the 2000-block chain WH-Producer phase 1 synced.  `curl http://localhost:8334/api/v1/chain/header/byHeight/tip` returns the canonical block-1999 hash; `curl /range?from=0&to=2` returns 240 bytes (3 × 80).  Identity-of-bytes confirmation against any block explorer.

What WH-Producer phase 2 deliberately does NOT ship (deferred to phase 3):

- **Push-driven tip subscription** (`inv` from peer) — 60s poll is fine for BSV's ~10-min average block time.
- **Auto-reorg** — `runOneTipPoll` errors out (logged to stderr) on chain divergence; the next interval retries.
- **TLS** — operator runs Caddy in front for HTTPS.

The wallet's WH3 fetcher treats *any* configured source as just bytes; correctness is enforced client-side by `headers.zig`. Source selection is convenience, not trust. See §11 for the Teranode-compat analysis covering API-shape divergence between operator types.

---

## 4. Dependency Graph

```
   ┌─── WH1 (PoW verifier) ───┐
   │                           │
   ├─── WH2 (HeaderStore) ─────┤
   │                           │
   ├─── WH3 (multi-source fetcher) ──┐
   │                                  │
   ├─── WH4 (tip subscriber) ─────────┤
   │                                  │
   └─── WH5 (chain-tracker integration) ─┐
                                          │
                                          ▼
                                   WH6 (UI + wizard) ◄─── final
                                   
   In parallel:  OPS-1 → headers.semantos.app live before WH3 lands
```

WH1 + WH2 are foundation (verifier + store). WH3 + WH4 are network plumbing. WH5 wires it into the existing wallet code. WH6 is UI. OPS-1 should land before WH3 so the default endpoint exists.

---

## 5. Estimated Sizing

| Phase | Effort | Risk |
|---|---|---|
| WH1 — PoW verifier | 2 days | Medium — DAA implementation needs care; differential against bsvz mitigates |
| WH2 — HeaderStore | 1 day | Low — same vtable pattern as DerivationStateStore/SlotStore/OutputStore |
| WH3 — Fetcher | 2 days | Medium — multi-source resilience, hybrid lazy mode, resume |
| WH4 — Tip subscriber | 1 day | Medium — reorg handling is subtle |
| WH5 — Chain-tracker integration | 1 day | Low — drop-in replacement for GullibleChainTracker at known call sites |
| WH6 — UI + wizard | 1 day | Low |
| **OPS-1** | 1 day | Low — well-trodden Go service deployment |

**Total**: ~8 days for the wallet work, ~1 day OPS in parallel. ~6 days with WH1+WH2 in parallel. Largest single-phase risk is WH1 (DAA correctness); rest is plumbing.

---

## 6. Commit Boundary Plan

One PR per phase (with OPS as a separate non-code deployment task):

1. `feat(cell-engine): WH1 — Zig PoW verifier + DAA + chain validation`
2. `feat(cell-engine): WH2 — HeaderStore vtable + LocalHeaderStore`
3. `feat(wallet-browser): WH3 — multi-source HTTPS header fetcher with hybrid mode`
4. `feat(wallet-browser): WH4 — tip-following WebSocket subscriber + reorg handling`
5. `feat(cell-engine): WH5 — LocalHeaderChainTracker; default SPV mode = strict/hybrid`
6. `feat(wallet-browser): WH6 — headers settings panel + wizard integration + UI badge`
7. `(OPS) deploy headers.semantos.app — block-headers-service Go container`

Each is independently mergeable. WH5 default-to-strict is the gating change that closes the trust gap; it should land last among WH1-WH5 and be paired with a clear release note.

---

## 7. Acceptance Criteria

WH is done when:

1. `core/cell-engine/tests/headers_conformance.zig` passes against the BSV mainnet header corpus.
2. `apps/wallet-browser/tests/header_fetcher.test.ts` passes against a mock multi-source backend including failure-injection.
3. `apps/wallet-browser/tests/header_tip.test.ts` passes including a 3-block simulated reorg.
4. **Strict-mode E2E test** (extends WA5's `active_use_roundtrip.test.ts`): receive a BEEF, BEEF validation runs in `policy.spv_mode = "strict"`, succeeds against pre-loaded HeaderStore. Repeat with a BEEF whose merkle root doesn't match any local header → rejected.
5. **The trust-model audit**: every call site in the wallet that previously used `GullibleChainTracker` or implicit external-trust now uses `LocalHeaderChainTracker`. Mechanical check: `grep -r "GullibleChainTracker" apps/ core/cell-engine/src/` returns only test stubs.
6. UI badge shows "SPV verified locally via PoW · tip H · source S" and updates in real time when new headers arrive.
7. Default source list includes `headers.semantos.app`; user can override; if all sources fail, wallet surfaces "no header source available — configure one in settings."
8. Bundle-size delta: WH WASM verifier ~50KB; total wallet bundle stays under 200KB target.
9. Documentation:
   - `WALLET-TIER-CUSTODY.md` v0.5+: add §12 ("Trustless SPV") covering WH1-WH6.
   - Trust-map table in §1.1 of this doc updates the "external trusted indexer" row from ❌ to ✅.
   - Every other design doc that says "trusted root" or "indexer" gets a note pointing at WH for how trust is actually rooted.

---

## 8. What WH Does and Does Not Cover

### Does:

- ✅ Eliminates external-indexer trust for SPV verification.
- ✅ Wallet validates every header it ingests via PoW; sources are CDN-equivalent.
- ✅ User-configurable source list with automatic failover.
- ✅ Hybrid mode (lazy fetch) for casual users; full sync for offline-capable users.
- ✅ Reorg handling within configurable depth.
- ✅ UI surface that makes the trust model legible to the user.
- ✅ Closes the last empty slot in the wallet's layered trust story.

### Does not:

- ❌ Verify the source's claimed *liveness* — a malicious operator can withhold new headers entirely (DoS). The wallet's response is to fall over to another source; the network as a whole keeps moving.
- ❌ Prevent eclipse attacks at the network layer — the wallet's connection to header sources is what it is. Multi-source mitigates partial eclipse.
- ❌ Cover non-SPV trust dependencies — e.g., the wallet still needs to trust price oracles for fiat conversion (if added), still needs to trust certificate issuers for BRC-52 cert validity, still needs to trust dApp origins for the user's behalf.
- ❌ Replace the bsvz differential test for `host_sign` correctness — that's the cryptographic-primitive layer, separate from the chain-truth layer.
- ❌ Replicate the full block-headers-service functionality in the browser — WH is verifier + store + lightweight fetcher, not P2P node. Browsers can't speak P2P.

---

## 9. The Layered Wallet Trust Story After WH

| Layer | Tool | What it covers | Status |
|---|---|---|---|
| Per-opcode soundness | Lean K1–K13 (substantive K4) | Failure atomicity, linearity, signing soundness | ✅ |
| Multi-step temporal | TLA+ KeyCustody / TierEscalation / ReplayPrev | State-machine reachability, concurrency | ✅ |
| Engine implementation | Zig conformance + 372/372 fuzz/diff | Implementation matches Lean model | ✅ |
| Crypto primitive correctness | bsvz differential | host_sign matches independent secp256k1 impl | ✅ |
| Binary-to-model linkage | WASM-MANIFEST hash pin | Deployed binary is the proven binary | ✅ |
| **SPV merkle-root trust** | **WH WASM verifier (this plan)** | **Every BEEF's merkle root verified locally via PoW** | 🟦 |

After WH ships, every layer the wallet uses for verification has either a mechanical proof (Lean / TLA+), an empirical bridge (Zig fuzz / bsvz differential), a binary-identity check (WASM-MANIFEST), or a math-grounded local validator (WH PoW). No layer rests on "trust that this external party is honest."

That's a level of trustlessness genuinely uncommon among browser-based wallets. The pitch:

> A free, instant, no-install browser wallet that doesn't need to trust any indexer, any operator, any third party. Just SHA-256, secp256k1, and PoW math — same things Bitcoin itself trusts.

---

## 10. Forward Look

After WH:

| Status | Workstream |
|---|---|
| ✅ Done | Engine + proof + storage + recovery + active-use + trustless SPV |
| 🔲 Parallel | Vault composition (`WALLET-IDENTITY-VS-VAULT.md`) |
| 🔲 v0.2 paid | Plexus OutputStore mirror, PlexusHeaderStore mirror |
| 🔲 v0.3 | BSV overlay counterparty-push, FederatedSemantos cross-node sync |
| 🔲 v0.x | **BRAIN `headers serve` mode** — replaces the (deprecated) Go OPS-1 service. Pure-Zig P2P client speaking the standard 2017-era Bitcoin SV wire protocol (works against classic BSV nodes AND Teranode peers via its legacy bridge), flat-file `headers.bin` backing, exposes both `block-headers-service` and Teranode `services/asset` HTTP API shapes for max client compat. ~1000 lines. Reuses `headers.zig` + `header_store.zig`. Folded into the BRAIN spec rather than a separate workstream. |

WH is the last *core wallet* trust workstream before the wallet is feature-complete-trustless for v0.5 / v1.0. After this, additional work is ecosystem (overlays, federation) or upgrade (vault, paid mirrors), not foundational.

---

*Cross-references*

- `core/cell-engine/src/derivation_state.zig` — vtable pattern WH2 mirrors
- `core/cell-engine/src/output_store.zig` (post WA2) — sibling pattern
- `core/cell-engine/src/beef.zig` — BEEF validation that WH5 routes through LocalHeaderChainTracker
- `apps/wallet-browser/src/wallet-ops.ts` — call sites WH5 updates
- `apps/wallet-browser/src/popup-status.ts` — wizard integration point for WH6
- bsvz: `spv.MerklePath`, `spv.MerkleTreeParent`, `spv.verifyBeef`, `spv.GullibleChainTracker`, primitives.chainhash
- `b-open-io/block-headers-service` — Go service for OPS-1
- BRC-9 / BRC-67 (SPV), BRC-62 (BEEF), BRC-74 (BUMP / Compound Merkle Path)
- BSV Genesis difficulty adjustment algorithm specification

---

## 11. Operator Compatibility — block-headers-service vs Teranode

The BSV ecosystem has two HTTP-API shapes for serving block headers in the wild. WH3 ships with adapters for both so the wallet works against either operator type out of the box.

### 11.1 The two API shapes

| Service | URL pattern | Lookup key | Binary format | Notes |
|---|---|---|---|---|
| `b-open-io/block-headers-service` ("Pulse") | `/api/v1/chain/header/range?from=H&to=H+N`<br>`/api/v1/chain/header/byHeight/{H}`<br>`/api/v1/chain/header/byHash/{hash}` | **height** for ranges, hash for single | `Content-Type: application/octet-stream` — concatenated 80-byte raw headers | Used by current operator deployments; height-based range is convenient for sequential sync |
| Teranode `services/asset` | `/header/{hash}/raw`<br>`/block/headers/{hash}/raw?n=N` | **hash** for both single and range | Same — concatenated 80-byte raw headers (`/raw` suffix); `/hex` and JSON variants also exist | Used by Teranode operators (the future-direction BSV node implementation); range fetch requires a starting hash, so initial sync needs an extra hash-lookup roundtrip |

The on-the-wire bytes are identical (80 bytes per header, BSV consensus serialization). Only the URL shape and the lookup key differ.

### 11.2 P2P wire protocol — unchanged

Teranode's `services/legacy/peer/peer.go` is a fork of `bsvd` and speaks the standard 2017-era Bitcoin SV wire protocol with the same network magic, same 24-byte message header, same VERSION/VERACK/getheaders/headers/inv/ping/pong messages. Teranode-to-Teranode uses libp2p, but the legacy bridge ensures any classic-protocol P2P client also interoperates with Teranode peers.

This means the eventual BRAIN `headers serve` mode (with its Zig P2P client) will work against:
- Classic BSV nodes (svnode, bsvd, etc.)
- Teranode peers via the legacy bridge
- Other Zig BRAIN instances doing `headers serve`

…all from one wire-format implementation. Teranode adds optional extensions (multistream `CreateStream`/`StreamAck`, `Authch`, `Protoconf`) that are negotiated post-handshake; our client can ignore them since they're not required for header fetching.

### 11.3 Wallet adapter abstraction (WH3)

WH3's `header-fetcher.ts` defines a `HeaderSourceAdapter` interface:

```ts
interface HeaderSourceAdapter {
  readonly kind: "bhs" | "teranode";
  readonly baseUrl: string;
  fetchByHeight(h: number): Promise<Uint8Array>;     // single 80-byte header
  fetchRange(fromH: number, count: number): Promise<Uint8Array>;  // n × 80 bytes
  fetchTip(): Promise<{ header: Uint8Array; height: number }>;
}
```

Two concrete implementations ship:
- `BlockHeadersServiceAdapter` — height-based URLs, direct range fetch
- `TeranodeAssetAdapter` — hash-based URLs; `fetchRange(fromH, n)` does a `byHeight`-equivalent lookup first (Teranode's `GetBlockHeader` accepts height as well; if not, falls back to walking forward from a known hash) then forwards to the `/block/headers/{hash}/raw?n=N` endpoint

User-facing source list (WH6 settings) holds `{ url, kind: "bhs" | "teranode" }` per source. Wizard auto-detects on first add by probing a known endpoint; user can override.

### 11.4 BRAIN `headers serve` exposes both shapes

When BRAIN lands the headers-serve mode, it exposes **both** API families on the same port from the same backing store:
- `/api/v1/chain/header/...` — block-headers-service compat
- `/header/...` and `/block/headers/...` — Teranode-asset compat

Operators get max client compatibility for free; every wallet instance, regardless of which adapter it's using, works against any BRAIN instance. Eliminates the API-shape fork from the operator's perspective.

### 11.5 Push channel

Both `b-open-io/block-headers-service` and Teranode use **Centrifuge** (websocket protocol). WH4's tip subscriber is written against the Centrifuge JSON dialect, which works against either. (For BRAIN `headers serve` we'll consider plain SSE as a simpler alternative; the WH4 client will support both transports behind a `TipChannelAdapter` interface.)

### 11.6 Migration trajectory

As Teranode adoption grows, the operator landscape will shift from BHS-shape to Teranode-shape. The wallet doesn't care — adapters insulate us from the transition. By the time most operators run Teranode, BRAIN instances are also serving both API shapes, so the wallet's source list naturally migrates without configuration churn for end users.
