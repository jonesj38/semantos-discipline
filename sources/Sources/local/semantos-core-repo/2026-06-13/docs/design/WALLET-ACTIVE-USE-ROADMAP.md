---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/design/WALLET-ACTIVE-USE-ROADMAP.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.730857+00:00
---

# Wallet Active-Use Roadmap — WA1–WA4

**Version**: 0.1 DRAFT
**Status**: Plan
**Authors**: Todd
**Related**: `docs/design/WALLET-TIER-CUSTODY.md` (v0.4), `docs/design/WALLET-W6-W7-NEXT-PHASE.md`, `docs/design/PROOFS-WT-TLA-EXTENSION-PLAN.md`

---

## 0. Purpose

The v0.4 identity wallet works end-to-end (W10 verified) and ships with multi-target envelope export (WT-Transport). It's a great wallet for "sign in to a dApp, send a few sats, recover from challenges if you lose your device." It is **not yet** a great wallet for users who actually transact a lot — receive incoming P2P payments, accumulate UTXOs, recover the full UTXO set on a fresh device.

This plan covers four phases (WA1–WA4) that turn the identity wallet into an *active-use* wallet without breaking its low-friction onboarding pitch:

| Phase | Closes the gap |
|---|---|
| WA1 — Onboarding wizard | "User created the wallet, now what? They don't know to back up the envelope, set up a vault, etc." |
| WA2 — OutputStore + `internalizeAction` | "Peer sends user a payment via BRC-100 internalizeAction; wallet has nowhere to put the UTXO" |
| WA3 — Envelope carries context list | "Recovery on a fresh device has no idea which derivation contexts to scan" |
| WA4 — Recovery sync via indexer scan | "Recovered wallet has no UTXOs even though they exist on-chain" |

When WA1–WA4 land, an active user can: create a wallet, get nudged through setup, accept incoming payments that persist locally with their derived keys, and recover a full UTXO set on a fresh device by scanning a bounded address space (not the whole chain).

The vault-composition workstream (`WALLET-IDENTITY-VS-VAULT.md`) is a parallel architectural piece for higher-value users; this roadmap stays focused on the active-use *daily* surface.

---

## 1. Current State

### 1.1 What works (post-W10 + WT-Transport)

- v0.4 architecture with mandatory challenges + recovery envelope built at creation
- Tier 0/1/2 signing with PIN/biometric/vault factors
- Tier 3 vault multisig (W11, wired through `wallet-ops.signSpend(tier=3)` per follow-up PR)
- Multi-target envelope export (Plexus, Drive, download, QR, clipboard, share-sheet)
- End-to-end recovery roundtrip validated
- Returning-device boot path via `unlockIdentityFromCache()` (§7.9)

### 1.2 What's missing for active use

| Gap | Current state | Active-use requirement |
|---|---|---|
| Post-creation guidance | Wallet ready, no follow-up | User-facing wizard surfaces backup / vault / connection options |
| Incoming payment storage | `internalizeAction` not implemented end-to-end; no persistent UTXO database | Peer sends BEEF via internalizeAction → wallet validates, derives key, persists UTXO + BEEF locally |
| Derivation context tracking | DerivationStateStore tracks `(protocol_hash, counterparty) → currentIndex` per local writes | Recovery needs the *list* of contexts the user has ever interacted with, not just current indices |
| Recovery UTXO reconstruction | Recovered wallet has seed + identity but empty UTXO database | Scan indexer (WoC, ARC) for unspent outputs at addresses derivable from recovered seed × envelope context list |

---

## 2. Phases

### WA1 — Onboarding wizard (~ 1 day)

**Goal**: after creation, surface a persistent setup-status panel that guides the user through optional next steps without blocking the basic wallet workflow.

**Deliverables**:

1. New cell type `SetupStatus` (RELEVANT linearity, identity-signed, locally cached). Per-item record: `{item_id, status: COMPLETE | SKIPPED | DISMISSED | PENDING, timestamp}`. Items v0.1: `BACKUP_ENVELOPE`, `SETUP_VAULT`, `CONNECT_NODE`, `ENROLL_PLEXUS`. Schema designed for additive items in future.

2. New popup `apps/wallet-browser/src/popup-setup.ts`. Renders the wizard from §1 of the conversation that produced this plan. Persists user choices to the SetupStatus cell. Skip-without-shame: every option has a clear "skip for now" path that doesn't degrade the wallet.

3. Auto-open hook: after `createWallet` returns, `popup-setup` opens once. User can dismiss; doesn't reopen automatically unless triggered by a contextual nudge (see deliverable 5).

4. Setup-status badge in the main wallet UI: "Setup: 2 of 4 complete" with link to reopen the wizard. Reads SetupStatus cell on render.

5. Contextual nudges. When the user receives a payment that pushes their Tier 0/1 budget above ~$10 USD-equivalent (or 2× the policy cell's tier1_ceiling, whichever is lower), a non-blocking banner appears: "You're holding more than your wallet was designed for. Consider setting up a vault." Click → opens the SETUP_VAULT path of the wizard.

6. `apps/wallet-browser/tests/setup_wizard.test.ts` — unit tests for SetupStatus persistence, wizard navigation, contextual nudge triggers.

**Success criterion**: after `createWallet` succeeds, popup-setup opens; user clicks "skip all," wallet continues to work for `getPublicKey`/`signSpend`/`internalizeAction`; SetupStatus cell persists "all dismissed" across tab reload; manual reopen from settings works.

### WA2 — `OutputStore` vtable + `internalizeAction` wiring (~ 2-3 days)

**Goal**: BRC-100's `internalizeAction` is implemented end-to-end. Incoming P2P payments are validated via the cell-engine's existing BEEF SPV verifier, derived keys are reconstructed per BRC-29, and the resulting UTXOs are persisted with their BEEFs to a pluggable OutputStore.

**Deliverables**:

1. New `core/cell-engine/src/output_store.zig` — vtable interface mirroring `derivation_state.zig`. Methods:
   ```zig
   pub const VTable = struct {
       add_output: *const fn (ctx: *anyopaque, record: OutputRecord) anyerror!void,
       list_outputs: *const fn (ctx, basket: ?[]const u8, tags: ?[]const []const u8,
                                 allocator: std.mem.Allocator) anyerror![]OutputRecord,
       get_output: *const fn (ctx, outpoint: Outpoint) ?OutputRecord,
       mark_spent: *const fn (ctx, outpoint, spending_txid: [32]u8) anyerror!void,
       prune_confirmed: *const fn (ctx, min_confirmations: u32) anyerror!u64,
       snapshot: *const fn (ctx, allocator) anyerror![]OutputRecord,
       replay: *const fn (ctx, records: []const OutputRecord) anyerror!void,
   };
   ```
   `OutputRecord`: `{outpoint, satoshis, locking_script, derived_key_hash, derivation_context, beef, basket, tags, custom_instructions, confirmations, status}`.
   Three planned backings, only `LocalOutputStore` ships in WA2:
   - `LocalOutputStore` — IndexedDB (browser) / lmdb (sovereign node), v0.1 ships
   - `PlexusOutputStore` — v0.2 stub for paid mirroring
   - `FederatedSemantosOutputStore` — v0.3 stub for cross-node sync

2. `apps/wallet-browser/src/output-store.ts` — `LocalOutputStore` IndexedDB implementation. Schema: object store keyed by `outpoint`, secondary indices on `(basket, status)` and `(derivation_context, status)`. Pruning policy: drop `beef` field after `min_confirmations >= 100`, drop entire record after `min_confirmations >= 1000` and status = `SPENT`.

3. Wire `internalizeAction` in `apps/wallet-browser/src/wallet-ops.ts`:
   ```
   internalizeAction({ tx (BEEF), outputs, description, labels }):
     1. Pass BEEF to cell-engine kernel_verify_beef_spv (already exists from W1 / Phase 5)
     2. For each output in outputs[]:
        a. If protocol === "wallet payment":
           - Derive key via BRC-29: deriveChild(identityKey,
             senderIdentityKey, derivationPrefix, derivationSuffix)
           - Verify locking script address matches derived key's address
           - addOutput({ outpoint, derivedKey, beef, basket: "default", ... })
        b. If protocol === "basket insertion":
           - addOutput({ outpoint, beef, basket: output.basket,
                         tags: output.tags, customInstructions: output.customInstructions, ... })
     3. Update DerivationStateStore — record the (protocol_hash, counterparty)
        context as "touched" (WA3 dependency)
     4. Return { accepted: true }
   ```

4. Update `wallet-ops.listOutputs(basket, tags)` and `wallet-ops.listActions(labels)` to read from the OutputStore. Already-stub methods become real.

5. `apps/wallet-browser/tests/internalize_action.test.ts` — receive a synthetic BEEF (constructed via bsvz `transaction.builder` from a known seed), call internalizeAction, assert: BEEF validation passes, derived key matches expected pubkey, OutputStore now has the UTXO, listOutputs returns it, second internalize of the same BEEF is idempotent (no duplicate).

**Success criterion**: a synthetic peer sends a 50,000-sat BRC-29 payment to the wallet's identity. internalizeAction succeeds. listOutputs returns the new UTXO with correct basket. signSpend at Tier 0 can subsequently spend that UTXO. Test count +8.

### WA3 — Envelope context-list extension (~ half day)

**Goal**: the recovery envelope always carries the *list* of `(protocol_hash, counterparty)` derivation contexts the user has ever interacted with, even if `currentIndex` is unknown. This bounds the recovery scan address space.

**Deliverables**:

1. Extend the `derivationStateSnapshot.records` field in the §8.2 envelope schema. Each record: `{protocolHash, counterparty, currentIndex: u64 | null}`. The list is *exhaustive over touched contexts*, not just contexts with current state. `null` indicates the index is unknown (envelope is stale relative to local writes).

2. New cell type `ContextRegistry` (RELEVANT, locally cached). Records every `(protocol_hash, counterparty)` pair the user has touched via any operation. Updated by:
   - `getPublicKey` with a non-self counterparty → record (protocol, counterparty)
   - `createSignature` / `signSpend` → record
   - `internalizeAction` → record (sender's identityKey as counterparty, protocol_hash from BRC-29)
   - Any future operation that touches a derivation context

3. On envelope export (`exportRecoveryEnvelope` in `popup-create.ts` / `popup-status.ts`), the wallet snapshots `ContextRegistry` and merges with `DerivationStateStore.snapshot()` to produce the records list. Contexts in registry but not in derivation state get `currentIndex: null`. Contexts in both get the live `currentIndex`.

4. Backwards compatibility: pre-WA3 envelopes (no `derivationStateSnapshot` or empty records) trigger fallback during recovery — scan a default set of well-known protocol_hashes (BRC-29 payment protocol, BRC-77 messaging, etc.) over a small counterparty universe (e.g., known contacts from local cache only). Document in the recovery UI: "Old-format envelope detected — recovery scan may miss UTXOs from contexts not in the default protocol set."

5. `apps/wallet-browser/tests/envelope_context_list.test.ts` — create wallet, sign 5 spends across 3 distinct (protocol, counterparty) contexts, export envelope, parse, assert all 3 contexts appear in `derivationStateSnapshot.records` with correct currentIndex values.

**Success criterion**: envelope round-trip preserves the context list. Recovery test in WA4 uses this list to bound the scan.

### WA4 — Recovery sync via indexer scan (~ 2 days)

**Goal**: after recovery (Plexus or local envelope), the wallet scans a bounded address space derived from the envelope's context list and rebuilds the OutputStore from on-chain unspent UTXOs.

**Deliverables**:

1. New module `apps/wallet-browser/src/recovery-scan.ts`. Pluggable indexer adapter (default: WhatsOnChain; ARC and GorillaPool as alternates configurable in wallet settings).

2. Scan algorithm:
   ```
   recoverySync(seed, contextList, indexer, gapWindow = 100):
     for ctx in contextList:
       lastFound = ctx.currentIndex ?? -1
       i = 0
       consecutiveEmpty = 0
       while consecutiveEmpty < gapWindow:
         leafKey = bsvz.primitives.ec.deriveChild(seed,
                     ctx.protocolHash, ctx.counterparty, i)
         address = leafKey.toAddress()
         unspent = await indexer.getUnspent(address)
         if unspent.length > 0:
           for utxo in unspent:
             beef = await indexer.getBEEF(utxo.txid)
             if cellEngine.verifyBEEF(beef, utxo.txid):
               outputStore.addOutput({
                 outpoint: utxo.outpoint,
                 satoshis: utxo.satoshis,
                 lockingScript: utxo.lockingScript,
                 derivedKey: leafKey,
                 derivationContext: ctx,
                 beef,
                 basket: 'default',
                 tags: [],
               })
           lastFound = i
           consecutiveEmpty = 0
         else:
           consecutiveEmpty += 1
         i += 1
       // Update DerivationStateStore: next index for this context = lastFound + 1
       derivationStateStore.replay([{...ctx, currentIndex: lastFound + 1}])
   ```

3. Progress UI in `popup-recovery.ts`: real-time progress bar showing scan state.
   ```
   Scanning your wallet on the chain...
   
   Context 23 of 50 (BRC-29 → Alice): 12 UTXOs found
   Context 24 of 50 (BRC-77 → Bob):    2 UTXOs found
   ...
   
   Total: 47 UTXOs recovered, 8.4M sats
   Estimated time remaining: 4 minutes
   
   [ Pause ] [ Cancel ]
   ```

4. Rate-limit handling. Default indexer (WhatsOnChain free tier) allows ~3 req/sec. Wallet config supports user-supplied API key for higher rates. Scan auto-throttles based on observed rate-limit responses, surfaces estimated completion time.

5. Resume support. Scan progress persisted to a `RecoveryScanState` cell every N addresses. If user closes the popup mid-scan, reopening resumes from last checkpoint. Cancellation marks the scan as incomplete; user can resume later from the wizard.

6. Error handling:
   - Indexer 5xx → exponential backoff, retry up to N times, fall back to alternate indexer if configured
   - BEEF validation failure → log the txid, skip the UTXO, continue (don't trust unverified data)
   - Network offline → pause scan, surface "reconnect" message
   - Final state: `RecoveryScanState.status` = `COMPLETE | INCOMPLETE | FAILED` with diagnostic info

7. `apps/wallet-browser/tests/recovery_scan.test.ts` — synthetic mock indexer returns known UTXOs at known addresses. recoverySync succeeds. OutputStore matches expected. DerivationStateStore correctly updated. Resume after simulated cancellation produces same final state.

**Success criterion**: full E2E test from W10's recovery roundtrip extended with WA4. After challenge-based recovery, recoverySync runs against a mock indexer pre-populated with 50 UTXOs across 5 contexts. All 50 UTXOs end up in OutputStore. listOutputs returns them. signSpend can subsequently spend any of them.

---

## 3. Dependency Graph

```
   ┌─── WA1 (wizard) ─────────────────────────┐
   │                                            │
   ├─── WA3 (envelope context list)             │
   │       │                                    │
   │       ▼                                    │
   ├─── WA2 (OutputStore + internalizeAction) ──┼──► WA5 (full active-use validation, see §6)
   │       │                                    │
   │       ▼                                    │
   └─── WA4 (recovery scan) ────────────────────┘
```

WA1 (wizard) is fully independent — no engine surface, just UI + setup-status cell. Can land first or last.

WA3 (envelope context list) is independent of WA2 — schema change + ContextRegistry only.

WA2 (OutputStore + internalizeAction) needs ContextRegistry from WA3 (so internalizeAction can record the context as touched) — but WA2 can stub the registry update if WA3 is delayed.

WA4 (recovery scan) is the integration phase — needs both WA2 (OutputStore to write to) and WA3 (envelope context list to bound the scan).

WA5 (full active-use validation) is the validation gate — extends W10's recovery roundtrip with internalize → recover → scan → spend.

---

## 4. Estimated Sizing

| Phase | Effort | Risk |
|---|---|---|
| WA1 — Onboarding wizard | 1 day | Low — UI work, no engine changes |
| WA2 — OutputStore + internalizeAction | 2-3 days | Medium — IndexedDB schema, BEEF validation wiring, BRC-29 derivation, pruning policy, idempotency tests |
| WA3 — Envelope context list | 0.5 day | Low — schema + registry cell + snapshot merge |
| WA4 — Recovery scan | 2 days | Medium-high — indexer integration, rate limiting, resume support, mock-indexer testing |
| WA5 — Full active-use validation | 0.5 day | Low — extends W10's E2E test |

**Total**: ~6-7 days for one engineer; ~4-5 days with WA1 + WA3 in parallel after WA2 lands.

---

## 5. Commit Boundary Plan

One PR per phase:

1. `feat(wallet): WA1 — onboarding wizard + SetupStatus cell + contextual nudges`
2. `feat(wallet): WA2 — OutputStore vtable + LocalOutputStore + internalizeAction wiring`
3. `feat(wallet): WA3 — recovery envelope carries derivation context list`
4. `feat(wallet): WA4 — recovery sync via WoC indexer scan`
5. `chore(wallet): WA5 — extend W10 E2E recovery test with active-use validation`

Each lands independently, all preserve the v0.4 contract.

---

## 6. Acceptance Criteria

WA1–WA4 are done when:

1. `apps/wallet-browser/tests/setup_wizard.test.ts` passes — wizard opens after creation, persists choices, contextual nudge fires correctly.
2. `apps/wallet-browser/tests/internalize_action.test.ts` passes — BRC-29 incoming payment is validated, key derived, UTXO persisted, second internalize is idempotent.
3. `apps/wallet-browser/tests/envelope_context_list.test.ts` passes — context list survives envelope round-trip with correct currentIndex per context.
4. `apps/wallet-browser/tests/recovery_scan.test.ts` passes — synthetic mock indexer scenario fully recovers OutputStore + DerivationStateStore.
5. **WA5 — extended W10 E2E test (`apps/wallet-browser/tests/active_use_roundtrip.test.ts`)**:
   - Phase A: create wallet, set 3 challenges
   - Phase B: receive 5 incoming BRC-29 payments via internalizeAction (50K sats each)
   - Phase C: spend 2 of them at Tier 0; assert OutputStore.listOutputs returns the remaining 3
   - Phase D: wipe IndexedDB (simulate fresh device)
   - Phase E: recover wallet via challenges; export envelope; assert context list has 5 (sender) contexts
   - Phase F: run recoverySync against mock indexer (pre-populated with the 3 unspent UTXOs); assert OutputStore now has them
   - Phase G: signSpend(tier=0) one of the recovered UTXOs; assert tx valid; signature verifies under the correct derived pubkey
6. Bundle size delta: WA1+WA2+WA3+WA4 stays under +50KB gzipped (current 56KB baseline; budget allows 200KB).
7. No regression in existing test suites: cell-engine 389/389, runtime/node 20/20, wallet-browser 176→200+ pass.
8. Documentation:
   - `WALLET-TIER-CUSTODY.md` v0.5: add §11 ("Active use") covering WA1-WA4 surface.
   - `WALLET-TIER-CUSTODY.md` §8.2 schema: update with the extended `derivationStateSnapshot.records` shape.
   - `WALLET-TIER-CUSTODY.md` §10.3 config matrix: add OutputStore, ContextRegistry, SetupStatus rows.

---

## 7. What WA1–WA4 Do Not Cover

For honesty:

- **Counterparty-push recovery (BSV overlay services)**. The "right" long-term answer to recovery sync — peer notifies your wallet of the BEEF at payment time, no chain scan needed. This is a v0.3 workstream (call it WO — Overlay), out of scope here. WA4's indexer-scan approach is the v0.1 answer.
- **Plexus OutputStore mirror (paid)**. The v0.2 paid feature where Plexus operator runs an indexer-backed OutputStore that mirrors per-user state for instant recovery. Stubbed in the OutputStore vtable but not implemented. Out of scope.
- **Vault composition** (separate workstream — `WALLET-IDENTITY-VS-VAULT.md`). The "create additional vaults beyond the bundled Tier 3" upgrade path. Parallel design effort, not part of WA.
- **Multi-counterparty addressing for messaging** (BRC-77/BRC-78). Active use of P2P payments is covered; messaging is separate.
- **OP_RETURN data extraction**. Some BRC-100 dApps use OP_RETURN for application metadata. WA2 stores the raw locking script but doesn't parse OP_RETURN content. App-level concern.
- **Fee estimation / RBF / mempool** considerations beyond the basic "fund a tx with a UTXO" path. Active use of payments includes some tx-construction subtlety; v0.1 keeps it simple.
- **Sovereign-node OutputStore backing** (lmdb instead of IndexedDB). Same vtable, different impl — straightforward to add when W6 lands the lmdb storage adapter for `SlotStore` etc. Worth doing in the same wave but not strictly required for WA4 to be useful in the browser.

---

## 8. The Wizard Detail (WA1 spec)

Since the wizard is the most user-visible piece and the conversation that produced this plan went into specific UX, locking it down here:

**The screen the user sees after `createWallet` succeeds:**

```
✓ Your wallet is ready

  Identity: 02a3b7...8f4c   Pocket change keyring: tier 0+1+2+3 ready
  Recovery envelope built (held locally only)
  
Setup: 1 of 4 complete

Next steps — pick any, or skip for now:

  □ Back up your recovery envelope                            [recommended]
    Right now your envelope only exists on this device.
    If your device dies, you lose your identity.
    [ Save to Plexus ($X/yr) ]  [ Share to... ]  [ Download ]  [ QR code ]

  □ Set up a vault for larger amounts                          [optional]
    Your current wallet is for identity + pocket change (~$10).
    A vault uses stronger challenges and optional hardware keys.
    [ Create vault ]                          [ Learn more ]

  □ Connect a sovereign node                                   [optional]
    Run your own backend instead of relying on this wallet origin.
    [ Connect ]                               [ Learn more ]

  □ Skip for now — just use the identity wallet
    [ I'll do this later ]
```

**The badge that appears in the main wallet UI afterward:**

```
[ Setup: 2 of 4 complete  •  Back up your envelope ]
```

Click → reopens the wizard. Hover → shows tooltip with the most-important pending item.

**The contextual nudge banner (triggered when budget exceeds threshold):**

```
ⓘ You're holding 1.2M sats (~$12) in this wallet. The identity wallet is
   designed for ~$10 of pocket change. Consider setting up a vault.
                                       [ Set up vault ]   [ Dismiss ]
```

Banner appears at the top of the popup, dismissible per-session, re-appears next session if condition still holds. Threshold derived from `policy.tier1_ceiling_sats × 2` (default: 2M sats).

**The SetupStatus cell schema:**

```
Header: linearity=RELEVANT, capability_type=SETUP_STATUS,
        owner_id=user_identity_hash, domain_flag=0x10000030
Payload:
  [00..04]   format_version (u32 LE)              // = 1
  [04..08]   item_count (u32 LE)
  [08..16]   created_at (u64 unix seconds)
  [16..24]   reserved
  [24..]     items: packed array of:
               item_id_hash[16] || status[1] || timestamp[8]
                = 25 bytes per item
                30+ items per 768-byte payload
```

`status`: `0 = PENDING, 1 = COMPLETE, 2 = SKIPPED, 3 = DISMISSED, 4 = AUTO_NUDGED_RECENTLY`.

`item_id_hash` is a SHA-256 truncated to 16 bytes of the canonical item identifier string (e.g., `"backup_envelope"`, `"setup_vault"`, `"connect_node"`, `"enroll_plexus"`). Allows additive items without schema changes.

---

## 9. Forward Look

After WA1–WA4 ship, the wallet covers:

| Capability | Status |
|---|---|
| Identity wallet creation + recovery (v0.4) | ✅ |
| Tier 0/1/2/3 signing | ✅ |
| Multi-target envelope export | ✅ |
| Onboarding wizard | ✅ (WA1) |
| Receive incoming P2P payments | ✅ (WA2) |
| Persist UTXOs locally with BEEFs | ✅ (WA2) |
| Recovery on fresh device (with chain scan) | ✅ (WA3 + WA4) |

What's still open after WA:

| Capability | Workstream |
|---|---|
| Vault composition (>1 vault, vault-only flows) | `WALLET-IDENTITY-VS-VAULT.md` (parallel) |
| Plexus paid OutputStore mirror | v0.2 paid features |
| Counterparty-push payment delivery (BSV overlay) | WO — Overlay (v0.3) |
| Federated mesh state sync across user's own nodes | WF — Federation (v0.3) |
| Hardware key contributions for vault factors | v0.2 vault upgrade |
| FROST threshold signatures for Tier 3 | v0.2 vault upgrade |

WA1–WA4 + the vault composition design are the two parallel architectural pieces remaining before v0.5 / v1.0. After both, the wallet is feature-complete for ~95% of BSV use cases, and the remaining items are ecosystem integrations rather than core wallet work.

---

*Cross-references*

- `core/cell-engine/src/derivation_state.zig` — vtable pattern WA2's OutputStore mirrors
- `core/cell-engine/src/slot_store.zig` — same pattern, sibling module to OutputStore
- `core/cell-engine/src/beef.zig` — `kernel_verify_beef_spv` used by internalizeAction
- `apps/wallet-browser/src/wallet-ops.ts` — WA2 wires internalizeAction here
- `apps/wallet-browser/src/popup-create.ts` — WA3 uses the existing envelope-export hook
- `apps/wallet-browser/src/popup-status.ts` — WA1 may extend this or sit alongside as popup-setup
- `docs/design/WALLET-TIER-CUSTODY.md` v0.4 — §8.2 schema WA3 extends, §10.3 matrix WA1-WA4 update
- `docs/design/WALLET-W6-W7-NEXT-PHASE.md` — sovereign-node OutputStore backing slots in here
- `docs/design/WALLET-IDENTITY-VS-VAULT.md` (TBD) — parallel vault-composition workstream
- bsvz: `primitives.ec.deriveChild` (BRC-42), `transaction.beef.newBeefFromBytes` (BEEF parsing), `broadcast.WhatsOnChain` (default indexer)
- BRC-29 (payment derivation), BRC-62 (BEEF), BRC-100 (internalizeAction spec)
