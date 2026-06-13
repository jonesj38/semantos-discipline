---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/design/WALLET-TIER-CUSTODY.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.727515+00:00
---

# Semantos Wallet — Tiered Key Custody Design

**Version**: 0.4 DRAFT
**Status**: Proposal
**Authors**: Todd
**Related**: `docs/FORMAL-VERIFICATION-STRATEGY.md`, `docs/design/PLEXUS-SEMANTOS-INTEGRATION.md`, `core/cell-engine/OPCODE-HARDENING-PLAN.md`

## Changelog

- **0.4** — **Architectural correction.** Recovery layer is now mandatory at wallet creation, not opt-in. The dispatch envelope is built locally for every wallet at creation time, encrypted under a challenge-derived KEK; Plexus enrollment is just deciding to transmit the existing envelope. Two cryptographic layers explicitly distinguished: **recovery** (challenge-derived, rare) vs **daily-use** (PIN/biometric/vault, frequent). §4 restructured to document both. §7.6 rewritten with the corrected create flow. §7.7 simplified to "transmit the existing envelope." §6.5 added: persisted recovery-envelope record. The mnemonic is no longer shown to the user — challenge answers ARE the user's recovery knowledge.
- **0.3** — Initial proposal: tiers, BRC-42 derivation, Plexus boundary.

---

## 0. Headline

> **A BRC-100 compliant wallet without a wallet** — runs as a webpage in any vanilla browser (no extension, no install), operates natively with Semantos, uses BRC-42 (BKDS) fresh-key-per-transaction derivation, and opts into Plexus recovery as a paid extra. Same Zig code runs in a sovereign node. Linearity-typed signing kernel. Hash-pinned WASM.

---

## 1. Purpose

Specify a tiered key-custody model for the Semantos wallet that:

- Delivers zero-friction micropayments and monotonically scaling authorization friction at higher spend amounts.
- Runs in any vanilla browser as a WASM bundle, and unchanged in a Semantos sovereign Zig node — same code, two targets.
- Uses **BRC-42 (BKDS) to derive a fresh key pair per transaction.** Base keys live encrypted at rest per tier; per-tx leaf keys are derived ephemerally in-engine, signed once, and discarded. No address reuse.
- Has **no runtime dependency on Plexus** and **no enrollment dependency** for the wallet itself to function. Wallet creation is local, instant, and free. Plexus is an *optional, paid* third-party recovery service: the wallet exports a signed dispatch envelope to Plexus servers if and only if the user opts into recovery insurance.
- Includes a **lite, in-wallet derivation-state tracker** with the same essence as Plexus's server-side state (monotonic indices per BRC-43 protocol/counterparty context) but scoped to single-use key rotation only. Stubbed behind a stable interface so the same wallet can later replicate state via full Plexus or via Semantos federated nodes without changing the signing path.
- Uses only BSV-native temporal primitives (`nSequence`, `nLockTime`). No CLTV / CSV — those opcodes are not part of the BSV instruction set.
- Lets the cell engine's linearity type system make key-leakage paths structurally impossible.
- Is covered end-to-end by the existing Lean and TLA+ proof obligations in `proofs/`.

---

## 2. Goals

| # | Goal |
|---|---|
| G1 | Sub-million-sat micropayments require no user interaction. |
| G2 | Authorization friction scales monotonically with spend amount via tiered local auth factors (PIN, biometric, vault). |
| G3 | The user-presented factor (PIN / biometric / passphrase) is presented to the **device's OS or secure element**, never to wallet JS / WASM. The factor produces a KEK locally; the cell engine sees only the resulting LINEAR key cell. |
| G4 | The wallet is fully usable without ever contacting Plexus. Recovery is an opt-in paid service: if the user enrolls, every signing key becomes reconstructible from Plexus's BRC-69 recovery substrate after total device loss; if they do not, the wallet operates anyway and warns them their keys are non-recoverable. |
| G5 | Implementation is all-Zig. Same Zig builds to: (a) a sovereign-node binary fronted by Caddy, (b) a WASM bundle for vanilla browsers. |
| G6 | Key leakage paths are structurally impossible — the cell engine's linearity types prevent any script execution path from copying a tier private key into a non-linear cell. |
| G7 | Every new opcode and key-state transition is covered by Lean (per-opcode soundness, linearity preservation) and TLA+ (state-machine safety, replay prevention). |
| G8 | All temporal restrictions (cooldowns, time-locked vault) use BSV-native `nSequence` / `nLockTime` only. |
| G9 | Every signed transaction uses a freshly derived BRC-42 leaf key. The base key per tier is never used to sign on-chain — only to derive leaves. |
| G10 | The local derivation-state interface is stubbed so it can later be backed by full Plexus state or by a Semantos federated mesh state replication, without changing the wallet's signing flow or any cell layout. |

---

## 3. Tier Schedule

| Tier | Spend ceiling | Authorization (v0.1) | Cell linearity | Capability type |
|---|---|---|---|---|
| **0 — Hot** | x < 1,000,000 sats | None — AFFINE budget cell with `remaining_satoshis` | AFFINE | `MICROPAYMENT_BUDGET` |
| **1 — PIN** | 1M ≤ x < 10M sats | Local PIN, KEK = Argon2id(PIN, salt) | LINEAR | `TIER1_KEY` |
| **2 — Biometric** | 10M ≤ x < 100M sats | Local biometric, KEK released by Secure Enclave / WebAuthn / TPM | LINEAR | `TIER2_KEY` |
| **3 — Vault** | x ≥ 100M sats | Stubbed in v0.1 (passphrase + biometric); upgraded in v0.2 to m-of-n multisig over `BACKUP_ON_CREATE` keys (see §4.3) | LINEAR | `TIER3_VAULT_KEY` |

Ceilings are **sat-denominated**, no fiat oracle dependency. Defaults shown; user-adjustable in the policy cell (§6.3).

---

## 3.5 BRC-42 Fresh Keys per Transaction

Each tier holds a **base key** at rest, encrypted under the tier's KEK. The base key never signs a transaction directly. Instead, for every spend the wallet:

1. Loads (and unlocks) the relevant tier's base key into the engine as an AFFINE cell.
2. Asks its `DerivationStateStore` for the next monotonic index for the (protocol, counterparty) context this spend belongs to.
3. Calls `host_derive_leaf` (BRC-42 `deriveChild`) to produce the leaf private key.
4. Pushes the leaf onto the engine's main stack as a LINEAR cell.
5. Atomically writes back the updated DerivationState (next index incremented).
6. Runs `OP_SIGN` against the leaf cell — leaf is consumed, signature emitted.
7. Broadcasts. The leaf's pubkey appears on-chain exactly once.

The linearity discipline maps cleanly onto the derivation hierarchy:

| Cell | Linearity | Why |
|---|---|---|
| Tier base key (decrypted, in-engine) | AFFINE | Used many times per session to derive leaves; explicitly droppable when the session locks |
| Per-tx leaf key | LINEAR | Used exactly once by `OP_SIGN`; type system forbids re-use |
| DerivationState | RELEVANT | Read by every derivation, must not be silently lost (re-use of an index is the bug we're preventing) |

### 3.5.1 Why fresh-key-per-tx

Privacy: no on-chain address reuse — every output goes to a unique leaf pubkey, defeating clustering. Security: compromise of one leaf's signature reveals nothing about other leaves or about the base. BRC-100 conformance: the spec's `getPublicKey` / `createSignature` interfaces are explicitly parameterized by `(protocolID, keyID, counterparty)`, which is exactly the BRC-42 derivation tuple — fresh-key-per-tx is the natural BRC-100 default.

### 3.5.2 The "lite plexus" derivation state

The wallet needs to track which indices have been used per derivation context. This is the same essence as Plexus's server-side state (per Plexus Client Reqs: "monotonic_index — strictly incrementing parameter that tracks the exact rotational state of an identity's keys within each functional domain") but scoped to a single user's local state, not a multi-tenant DB.

The state is held in a `DerivationState` cell (§6.4). Reads and writes go through a stable Zig interface:

```zig
pub const DerivationStateStore = struct {
    ctx: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        // Look up the current index for a (protocol, counterparty) context.
        // Returns null if the context has never been used.
        get_index: *const fn (ctx: *anyopaque,
                              protocol_hash: [16]u8,
                              counterparty: [33]u8) ?u64,

        // Atomically allocate and persist the next index. The returned index
        // is guaranteed never to be returned again for the same context.
        next_index: *const fn (ctx: *anyopaque,
                               protocol_hash: [16]u8,
                               counterparty: [33]u8) anyerror!u64,

        // Snapshot all (context, index) records — used by dispatch envelope
        // construction (§8.2) and by recovery sync.
        snapshot: *const fn (ctx: *anyopaque,
                             allocator: std.mem.Allocator) anyerror![]Record,

        // Replay a snapshot from an external source (recovery, federated sync).
        replay: *const fn (ctx: *anyopaque,
                           records: []const Record) anyerror!void,
    };

    pub const Record = struct {
        protocol_hash: [16]u8,
        counterparty: [33]u8,
        current_index: u64,
    };
};
```

Three planned implementations, all conforming to the same interface:

| Implementation | Status | Backing |
|---|---|---|
| `LocalStateStore` | v0.1 (ship) | IndexedDB (browser) / lmdb (node), atomic write per increment |
| `PlexusStateStore` | v0.2 (stubbed v0.1) | `LocalStateStore` + asynchronous mirror to `plexus-keys.com/state/checkpoint` after each increment; falls back to local on network failure |
| `FederatedSemantosStateStore` | v0.3 (stubbed v0.1) | `LocalStateStore` + replication across the user's own Semantos sovereign nodes via the federated mesh; provides recovery without involving any third party |

The signing path links only the `DerivationStateStore` interface — never a concrete implementation. v0.1 ships with `LocalStateStore` wired in; the other two are zero-implementation stubs (an empty struct with the right shape) so the integration points are pinned in source from day one.

### 3.5.3 Recovery and the gap problem

If the user enrolls in Plexus or in federated sync, the DerivationState snapshot is part of what gets replicated. On disaster recovery, the new device replays the snapshot via `DerivationStateStore.replay()` and resumes derivation from the last known indices.

Without sync (v0.1 default — local-only), recovery from mnemonic alone has no DerivationState. The wallet then takes the BIP44-style approach: skip ahead by a per-context gap (default 100 indices). For outgoing-spending wallets this is harmless — the only risk would be re-using an index for a *new* spend, and we always skip past where we left off. For inbound-watching (less critical to v0.1) the gap defines how many addresses to scan.

This is why even users who don't pay for Plexus benefit from Plexus existing: federated Semantos state sync (v0.3) gives the same recovery property for free, using the user's own infrastructure.

---

## 4. Authentication Model

The wallet has **two independent cryptographic KEK layers**, each protecting different at-rest material with a different unlock factor at a different cadence. They MUST be reasoned about separately.

| Layer | Protects | KEK source | Cadence | Compromise impact |
|---|---|---|---|---|
| **Recovery** (§4.0) | the **root seed** ciphertext (the `encryptedRecoverySeed` field of the dispatch envelope, §6.5/§8.2) | PBKDF2-100k of the user's **three challenge answers** (normalized + concatenated) + per-wallet salt | rare — only on device loss / new-device migration | yields the seed (i.e., everything) only if also given access to the envelope ciphertext (held locally OR by Plexus if enrolled) |
| **Daily-use** (§4.1) | each tier's **base key** ciphertext at-rest | per-tier factor — PIN (Tier 1, Argon2id), biometric (Tier 2, secure-element-released), vault (Tier 3) | frequent — every Tier 1+ spend | yields one tier's base key only if also given access to that tier's at-rest blob; does NOT yield the seed |

The two layers are **independent**. Compromise of the daily-use PIN does not yield the recovery seed; compromise of the challenge answers (e.g., social engineering) does not yield the daily-use signing keys without the device's encrypted blobs. This stratification is the core of the design's threat model.

### 4.0 Recovery layer — challenge-derived, mandatory at creation

Every wallet — Plexus-enrolled or not — has a **dispatch envelope** built locally at creation time per §7.6 and persisted in the recovery-envelope cell §6.5. The envelope's `encryptedRecoverySeed` field holds the wallet's root seed encrypted under a KEK derived from the user's three challenge answers.

**The challenge answers ARE the user's recovery knowledge.** They serve the role a BIP39 mnemonic plays in legacy wallets: the offline recall material the user must remember to recover from total device loss. Unlike a mnemonic, the user does not see or write down the seed itself — they only remember answers to three questions of their own choosing.

KEK derivation:
```
normalized[i] = NFKC(answer[i]) + casefold + collapse-whitespace + trim
password      = normalized[0] || normalized[1] || normalized[2]
salt          = 32 bytes CSPRNG, persisted in the envelope
KEK           = PBKDF2-HMAC-SHA256(password, salt, iterations=100000, dkLen=32)
seed_ciphertext = AES-256-GCM(seed, KEK, nonce=12 bytes CSPRNG, aad=identityKey || envelopeVersion)
```

**Plexus enrollment is just deciding to transmit the existing envelope.** The envelope's structure is identical whether held locally or held server-side. Plexus's optional service substitutes its own server-side rate limiting + email-OTP wall for the user holding their own envelope file safely.

If the user neither enrolls in Plexus nor backs up their envelope file, recovery is impossible — the same as losing a paper-backed mnemonic. The wallet warns the user explicitly at creation.

### 4.1 Daily-use layer — OS-local factor, per-spend

For Tiers 1 and 2, the auth factor never crosses the boundary into wallet code:

- **PIN (Tier 1)**: entered into a native OS / WebAuthn-PIN dialog. The OS presents the PIN to a local key-derivation function (Argon2id). The KEK emerges; the wallet uses it to AES-GCM-decrypt the encrypted-at-rest Tier-1 key blob.
- **Biometric (Tier 2)**: TouchID / FaceID / Android BiometricPrompt / WebAuthn user verification. The platform's secure element holds the KEK directly, releases it on successful biometric assertion, never exposes it to JS. The wallet receives an opaque assertion handle that unwraps the encrypted Tier-2 blob.
- **Vault (Tier 3)**: in v0.1 a stronger combination of the above. In v0.2, see §4.3.

In all cases the cell engine never sees the raw factor. It receives a decrypted LINEAR key cell on the main stack and consumes it via `OP_SIGN`.

### 4.2 What the daily-use KEK does (and doesn't) protect

The daily-use KEK protects the **encrypted-at-rest blob** in IndexedDB (browser) or lmdb (node) against an attacker with cold disk access. It is **not** the cryptographic gate for signing — that gate is the linearity-typed engine flow and the on-chain script the spend is satisfying.

This separation matters because:

1. The KEK lifetime is bounded by a single signing operation. It enters memory, decrypts one cell, the cell is consumed, the KEK is zeroed.
2. Linearity invariants (`proofs/lean/Semantos/Theorems/LinearityK1.lean` extended by K12 in §9) prevent any script path from copying the decrypted key into a non-linear cell. Even a malicious script template cannot exfiltrate the key.
3. Compromise of the at-rest blob alone does not yield a signing key — the attacker also needs the PIN / biometric / vault factor. Compromise of the factor alone (e.g., shoulder-surfed PIN) does not yield a key without also exfiltrating the encrypted blob.

Note that this analysis applies to the daily-use layer only. The recovery layer (§4.0) is independent: it is the encryption around the seed itself, with its own KEK derivation and its own threat model.

### 4.3 Vault tier — v0.1 stub vs v0.2 multisig

- **v0.1**: Vault is a single LINEAR key cell encrypted under a strong KEK (passphrase ⊕ biometric or YubiKey HMAC-SHA1 challenge-response). Same flow as Tier 1/2, just a stronger factor.
- **v0.2**: Vault becomes m-of-n multisig over keys held in distinct secure elements, with each member key enrolled in Plexus under `BACKUP_ON_CREATE`. The KEK gate disappears entirely; the cryptographic gate is the multisig satisfaction script. Possible thresholds: 2-of-3 (phone secure enclave + laptop secure enclave + YubiKey), 3-of-5 (add cold backup card + recovery USB).

The v0.2 path requires no engine-level changes — `host_checkmultisig` already exists. v0.1 ships first, v0.2 is a vault-tier-only upgrade that does not touch Tier 0/1/2 flows.

### 4.4 Cooldown on Tier 3 (BSV-native)

For Tier 3 spends we want a rate limit (e.g., one per 60 seconds). Two implementation paths, both BSV-native:

- **v0.1 host-side**: timestamp recorded in the policy cell; refuse to accept a Tier-3 spend request within the cooldown window. Simple, requires trusting the local node clock.
- **v0.2 on-chain via `nSequence`**: vault UTXOs include a relative locktime in their `nSequence` field. Each spend chains to a new UTXO whose `nSequence` encodes the cooldown delay. The next vault spend is consensus-rejected until the cooldown elapses. No CLTV needed — `nSequence` interpreted as relative locktime per BIP-68 semantics, which BSV honors.

---

## 5. Cell Engine Additions

### 5.1 New opcodes

| Opcode | Hex | Stack effect | Failure behavior |
|---|---|---|---|
| `OP_SIGN` | `0xCD` | `[key, msg, sighash_type]` → `[sig]` | Peek-then-mutate; stack unchanged on any error. Consumes the key cell only on success. |
| `OP_DECREMENT_BUDGET` | `0xCE` | `[budget_cell, amount]` → `[budget_cell']` | Errors `insufficient_budget` if `amount > remaining`; stack unchanged. |
| `OP_REFILL_BUDGET` | `0xCF` | `[budget_cell, refill_amount, parent_sig]` → `[budget_cell']` | Verifies `parent_sig` against the budget cell's parent capability before crediting. |

All three follow the failure-atomic peek-then-mutate pattern standardized in `core/cell-engine/src/opcodes/plexus.zig` (see `opCheckCapability`, lines 78–101).

### 5.2 Linearity discipline

| Cell class | Allowed by `OP_SIGN` | Behavior |
|---|---|---|
| LINEAR | Yes | Cell consumed (popped) on success. Cannot be re-used — the type system forbids it. |
| AFFINE | Yes | Cell stays on stack; `remaining_satoshis` decremented via the budget op pattern. |
| RELEVANT | No | `error.invalid_linearity_type` — vault keys must not be RELEVANT-class. |
| Other | No | `error.linearity_check_failed` |

There is no script execution path that can copy a Tier-1/2/3 private key into a non-linear cell. K1 (`LinearityK1.lean`) extends to OP_SIGN by structural inheritance — any consuming opcode on a LINEAR cell preserves K1.

### 5.3 New WASM host imports

Added to `core/cell-engine/src/host.zig` and the FFI spec in `bindings/ffi-spec.md`:

| Import | Signature | Purpose |
|---|---|---|
| `host_sign` | `(sk_ptr, sk_len, msg_ptr, msg_len, sighash_type, out_ptr, out_len_ptr) → i32` | ECDSA secp256k1 sign, low-S normalized. Mirrors existing `host_checksig`. Full profile: bsvz `primitives.ecdsa`. Embedded profile: host runtime supplies (browser → noble-secp256k1 or bsvz-WASM; node → bsvz native). |
| `host_unlock_tier` | `(tier: u32, factor_handle: ptr, factor_len: u32, slot_id: u32, out_cell_ptr: ptr) → i32` | Coordinates the local OS/Secure-Enclave unlock for tier T, decrypts the at-rest blob, returns a LINEAR cell. The factor handle is opaque (browser: WebAuthn assertion; node: PAM / Touch ID). |
| `host_persist_cell` | `(slot_id: u32, cell_ptr: ptr, len: u32) → i32` | Write a cell back to local storage (IndexedDB / lmdb), encrypted under the appropriate at-rest KEK for its tier. |
| `host_load_cell` | `(slot_id: u32, out_ptr: ptr) → i32` | Read a cell from local storage. For Tier 0 (AFFINE budget) this requires only the session KEK; for Tier 1+ it returns an error if the tier has not been unlocked via `host_unlock_tier` in the current request scope. |
| `host_derive_leaf` | `(base_key_ptr: ptr, base_key_len: u32, protocol_hash_ptr: ptr[16], counterparty_ptr: ptr[33], index: u64, out_leaf_ptr: ptr) → i32` | BRC-42 `deriveChild`. Takes the AFFINE base key cell on the engine stack and the (protocol, counterparty, index) triple, returns a LINEAR leaf key cell. Implemented via bsvz `primitives.ec.deriveChild`. |
| `host_state_next_index` | `(protocol_hash_ptr: ptr[16], counterparty_ptr: ptr[33], out_index_ptr: ptr[8]) → i32` | Atomically allocate the next derivation index for a context via the configured `DerivationStateStore`. Persists before returning. |

No oracle import. Sat-denominated thresholds eliminate price-feed trust.

---

## 6. Cell Layouts

All cells are 1024 bytes: 256-byte header + 768-byte payload, packed by the existing `cell.zig::packCell`.

### 6.1 Tier-0 budget cell (AFFINE)

```
Header: linearity=AFFINE, capability_type=MICROPAYMENT_BUDGET,
        owner_id=user_identity_hash, domain_flag=0x10000001
Payload:
  [00..32]   priv_key (secp256k1 secret scalar)
  [32..40]   remaining_satoshis (u64 LE)
  [40..48]   epoch_start (u64 unix seconds)
  [48..56]   epoch_duration_seconds (u64 LE)
  [56..120]  parent_capability_signature (ECDSA DER over header,
                                           by Tier-1+ key)
  [120..768] zero-padded
```

`epoch_start + epoch_duration_seconds` defines the budget window; expired budgets must be re-issued from a Tier-1+ refill. `parent_capability_signature` proves authorization.

### 6.2 Tier-N base key cell (AFFINE), N ∈ {1, 2, 3}

This is the **base** for BRC-42 derivation, not a signing key. Loaded once per tier-unlock session, used many times to derive leaves, dropped at session lock.

```
Header: linearity=AFFINE, capability_type=TIERN_BASE_KEY,
        owner_id=user_identity_hash, domain_flag=0x10000002 + N
Payload:
  [00..32]   base_priv_key (secp256k1 secret scalar — root of derivation,
                            never signs on-chain directly)
  [32..96]   brc43_invoice_string_root (root path of this tier, padded)
  [96..128]  parent_cert_id (BRC-52 32-byte cert hash)
  [128..136] tier_number (u64)
  [136..144] derivations_in_session (u64, host-incremented for telemetry)
  [144..768] zero-padded
```

AFFINE: may be DUP'd within a script (so a single composite operation can derive multiple leaves), and dropped explicitly when the session locks. Per-tx leaves derived from this cell are LINEAR and consumed by `OP_SIGN` (§6.2.1).

### 6.2.1 Per-tx leaf key cell (LINEAR)

Constructed at signing time by `host_derive_leaf`, lives only on the engine stack, never persisted.

```
Header: linearity=LINEAR, capability_type=TIERN_LEAF_KEY,
        owner_id=user_identity_hash, domain_flag=0x10000002 + N
Payload:
  [00..32]   leaf_priv_key (BRC-42 derived from base + invoice)
  [32..48]   protocol_hash (16 bytes, derived from BRC-43 protocolID)
  [48..81]   counterparty (33 bytes compressed pubkey, or 0x02..ZEROS for 'self', or 0x03..ZEROS for 'anyone')
  [81..89]   index (u64 LE — the BKDS invoice number used to derive this leaf)
  [89..768]  zero-padded
```

`OP_SIGN` consumes this cell and emits an ECDSA signature. After signing, the leaf is gone — the on-chain pubkey is publicly visible (it's in the script), but the private key has been zeroed by the engine's stack-pop semantics.

### 6.3 Policy cell (RELEVANT) — locally cached, identity-signed

```
Header: linearity=RELEVANT, capability_type=POLICY,
        owner_id=user_identity_hash, domain_flag=0x10000010
Payload:
  [00..04]   policy_version (u32)
  [04..12]   tier1_ceiling_sats (u64)        // default 1_000_000
  [12..20]   tier2_ceiling_sats (u64)        // default 10_000_000
  [20..28]   tier3_ceiling_sats (u64)        // default 100_000_000
  [28..32]   tier1_factor_kind (u32)         // PIN | PASSPHRASE | …
  [32..36]   tier2_factor_kind (u32)         // BIOMETRIC | YUBIKEY | …
  [36..40]   tier3_factor_kind (u32)         // VAULT_STUB | MULTISIG_2OF3 | …
  [40..48]   tier3_cooldown_seconds (u64)    // 0 = disabled
  [48..112]  identity_signature (ECDSA DER over rest of payload)
  [112..768] zero-padded
```

RELEVANT linearity: may be DUP'd freely for any number of policy lookups, must not be silently discarded. Policy changes require an explicit `OP_REPLACE_POLICY` invocation that consumes the old version (audit-trail discipline).

The policy cell is **locally cached** in IndexedDB / lmdb. The user's identity key signs each version; on load, the engine verifies the signature against the user's identity public key (already stored alongside the BRC-52 cert).

### 6.4 DerivationState cell (RELEVANT)

The lite-Plexus state record. Tracks the highest used index per `(protocol_hash, counterparty)` context. Backed by `DerivationStateStore` (§3.5.2).

```
Header: linearity=RELEVANT, capability_type=DERIVATION_STATE,
        owner_id=user_identity_hash, domain_flag=0x10000020
Payload:
  [00..04]   record_count (u32 LE)
  [04..08]   format_version (u32 LE)              // = 1
  [08..16]   reserved (u64)
  [16..]     records: packed array of:
               protocol_hash[16] || counterparty[33] || current_index[8]
                = 57 bytes per record
                ~13 records per 768-byte payload
  // For >13 contexts, records overflow into a continuation multi-cell
  // structure using the existing multi-cell packing path.
```

RELEVANT linearity: read on every derivation, must not be silently lost — losing it would either re-use indices (privacy/security failure) or skip ahead by the gap window (recovery-only operating mode). Updates write a new version of the cell; the previous version is garbage-collected after the new one is durably persisted.

`host_state_next_index` is the only path that mutates this cell. It performs:

```
1. read current cell (RELEVANT, may be DUP'd freely)
2. find or insert (protocol_hash, counterparty) record
3. increment current_index
4. write new cell version atomically to storage (LocalStateStore)
5. enqueue a checkpoint to PlexusStateStore / FederatedSemantosStateStore
   if those stubs are wired (no-op in v0.1)
6. return the allocated index
```

The atomic-write step is the storage-layer counterpart to the engine's per-opcode failure-atomicity. If the write fails, the host returns an error before `host_derive_leaf` runs; no leaf is produced; no signature is emitted.

---

### 6.5 Recovery envelope cell (RELEVANT) — locally cached, identity-signed

The recovery envelope is built at wallet creation (§7.6) and persisted regardless of whether the user enrolls in Plexus. If the user later enrolls (§7.7), this is the exact byte-for-byte object transmitted to the operator. If they never enrol, the cell stays local and the user is responsible for backing the file up.

```
Header: linearity=RELEVANT, capability_type=RECOVERY_ENVELOPE,
        owner_id=user_identity_hash, domain_flag=0x10000030
Payload (variable, may continuation-cell into octave 1+):
  [00..04]   envelope_version (u32 LE)             // = 1
  [04..36]   identity_key (33 bytes, padded to 32-byte boundary by zero-fill — see note)
  [36..68]   cert_id (32 bytes, BRC-52)
  [68....]   contact_email (UTF-8, length-prefixed u16)
  [..]       challenge_bundle:
              questions[3] (UTF-8, each length-prefixed u16)
              salt[32]
              answer_hashes[3 × 32]
              kdf_iterations (u32 LE) = 100000
  [..]       encrypted_recovery_seed:
              ciphertext (length-prefixed u16)
              nonce[12]
              tag[16]
              aad_size (u16) = 34   // identity_key(33) || envelope_version(1)
  [..]       derivation_contexts (length-prefixed u16 record count, each:
              tier (u8), invoice_string (length-prefixed u16),
              domain_flag (u32 LE), recovery_policy (u8))
  [..]       edge_recipes (length-prefixed u16 record count; v0.1 = 0)
  [..]       derivation_state_snapshot (length-prefixed u16 record count;
              each record matches §6.4 layout: protocol_hash[16] ||
              counterparty[33] || current_index[8])
  [..]       algorithm_version (u32 LE) = 1
  [..]       identity_signature (length-prefixed u16, ECDSA DER over
              everything above)
  [..]       (zero-padded to cell boundary; continuation cells used if
              the envelope exceeds 768 payload bytes)
```

**Note on identity_key padding**: stored at offset 4 (33 bytes) with a 7-byte trailing zero-fill so the first compositional block ends on a 16-byte alignment. Cosmetic; not consensus-relevant.

RELEVANT linearity: read on enrollment dispatch, on recovery, and on incremental edge-append. Must not be silently lost — the envelope IS the wallet's recovery story.

The envelope is identity-signed at the end (over the byte-stream from `envelope_version` through `algorithm_version`). Mutations (e.g., appending an edge_recipe, updating the derivation_state_snapshot) require resigning under the identity key. The Plexus operator validates the signature on dispatch.

**WT-Transport — multi-target envelope routing.** Because the envelope is safe to publish (only the user's challenge answers can decrypt the seed inside it; per §4.0 + §8.2), the wallet exposes a small transport-abstraction layer (`apps/wallet-browser/src/transport.ts`) that lets the post-create UI mirror the same envelope bytes to whichever channels the user trusts. Each transport implements `EnvelopeTransport { id, name, isAvailable(), send(SerializedEnvelope) }`; `defaultTransports()` returns the subset usable in the current environment.

v0.4 Day-1 transports (shipped):

  - **WebShareTransport** — `navigator.share({ files })` for the OS share sheet on iOS/Android (Telegram/WhatsApp/Mail/Drive/Files for free).
  - **DownloadTransport** — universal fallback. `URL.createObjectURL(new Blob([bytes]))` + invisible `<a download>`.
  - **ClipboardTransport** — `navigator.clipboard.writeText(base64)` for paste-anywhere.

Future transports (interface stable; implementations land in follow-up PRs):

  - **QRCodeTransport** — would render the envelope as a QR; needs a tiny QR lib. Envelopes >2KB don't fit one frame, so requires multi-frame animation.
  - **MailtoTransport** — `mailto:` with the base64 envelope in the body.
  - **DriveTransport / GoogleDriveTransport / IPFSTransport / 1PasswordTransport** — each requires its own OAuth or signing flow; out of scope for v0.4.
  - **PlexusTransport** — refactor of the existing `popup-plexus.ts` flow to implement the same `EnvelopeTransport` interface. v0.4 ships popup-plexus untouched and WT-Transport coexists alongside it; the refactor is a follow-up.

---

## 7. Operational Flows

### 7.1 Tier 0 — Micropayment, no prompt

```
1. host: load_cell(HOT_BUDGET_SLOT) → AFFINE base cell on stack
2. host: host_state_next_index(protocol_hash, counterparty)
         → next_index (atomically allocated and persisted)
3. host: host_derive_leaf(base, protocol_hash, counterparty, next_index)
         → LINEAR leaf cell pushed
4. script: OP_CHECKAFFINETYPE   (0xC1)  — verify base linearity
5. script: OP_CHECKDOMAINFLAG   (0xC6)  — verify HOT domain
6. script: OP_DECREMENT_BUDGET  (0xCE)  — consume sats from budget
7. script: OP_SIGN              (0xCD)  — sign tx preimage with leaf (consumed)
8. host: persist_cell(HOT_BUDGET_SLOT, updated_base_cell)
9. host: broadcast tx
```

Single round-trip, no UI prompt, all in-process. The AFFINE base cell stays on the engine stack across calls within a session; the LINEAR leaf is consumed each time. The on-chain pubkey is unique per spend.

### 7.2 Tier 1 — PIN

```
1. host: classify spend → tier=1 (sats compared against policy ceilings)
2. host: prompt user for PIN via native OS dialog / WebAuthn-PIN
3. host: derive KEK = Argon2id(PIN, salt_for_tier1)
4. host: host_unlock_tier(1, kek_handle, TIER1_SLOT, &base_cell)
   → AFFINE Tier-1 base key cell on main stack
5. host: host_state_next_index(protocol_hash, counterparty) → next_index
6. host: host_derive_leaf(base, protocol_hash, counterparty, next_index)
   → LINEAR leaf cell pushed
7. script: OP_CHECKAFFINETYPE   (0xC1)  — verify base
8. script: OP_CHECKLINEARTYPE   (0xC0)  — verify leaf
9. script: OP_CHECKDOMAINFLAG   (0xC6)  — verify TIER1 domain
10. script: OP_SIGN             (0xCD)  — sign tx, leaf consumed
11. host: zero KEK; clear base from stack; broadcast tx
```

If the PIN is wrong, `host_unlock_tier` returns an error; no leaf is derived; the stack stays untouched. If `host_state_next_index` fails (storage layer), the leaf is never produced — same atomicity guarantee at the storage boundary.

### 7.3 Tier 2 — Biometric

Identical to Tier 1 except step 2 uses the platform biometric prompt and step 3 retrieves the KEK from the secure element directly (no Argon2id needed — the KEK lives in hardware-backed storage gated by biometric assertion). On the browser side this is WebAuthn `userVerification: "required"`.

### 7.4 Tier 3 — Vault (v0.1 stub)

Same shape as Tier 2 but with a stronger factor (passphrase entry + biometric, or YubiKey HMAC-SHA1 challenge-response). Cooldown enforced host-side via the policy cell's `tier3_cooldown_seconds`. v0.2 replaces this with a multisig satisfaction script (no engine changes required).

### 7.5 Refill the hot budget

When a Tier-0 budget cell expires or runs low:

```
1. host: classify refill amount → tier=2 (refills cross the Tier-2 threshold)
2. host: biometric prompt → unlock Tier-2 key (per §7.3 steps 2–4)
3. script: OP_SIGN with Tier-2 key produces a refill capability signature
4. script: OP_REFILL_BUDGET (0xCF) credits the budget cell, verifying the refill sig
5. host: persist new budget cell, broadcast funding tx
```

The refill signature is recorded as the budget cell's `parent_capability_signature` for audit.

### 7.6 First-time creation — entirely local

The wallet finds no local state on first load. **No third-party service is contacted.** The recovery layer (§4.0) is built mandatorily at this step — the dispatch envelope (§6.5, §8.2) is constructed locally for every wallet, regardless of any future Plexus enrollment.

```
1. wallet UI: "Create wallet"
2. wallet generates a 64-byte CSPRNG root seed
   (NOT derived from challenges — random; challenges encrypt it)
3. wallet derives via BRC-42 from the seed:
   - identity key (the wallet's stable on-chain identity)
   - Tier 0 / 1 / 2 / 3 base keys
4. wallet UI: "Set three secret answers" — MANDATORY, no skip path
   - presents 3 question slots (user chooses or picks from a set,
     e.g. "Mother's maiden name?", "City of birth?", "First pet?")
   - collects answers locally; raw answers never leave device
5. wallet computes locally:
   - salt = 32 bytes CSPRNG
   - normalized[i] = NFKC + casefold + collapse-whitespace + trim
                       on answer[i]
   - password = normalized[0] || normalized[1] || normalized[2]
   - KEK = PBKDF2-HMAC-SHA256(password, salt, iter=100000, dkLen=32)
   - seed_ciphertext = AES-256-GCM(seed, KEK,
                                    nonce=12 bytes CSPRNG,
                                    aad=identity_key || envelope_version)
   - answer_hashes[i] = SHA256(salt || normalized[i])
6. wallet UI: "Contact email" (used as Plexus rate-limit key + OTP
   destination IF the user later enrolls; held locally regardless)
7. wallet builds the dispatch envelope per §8.2 schema:
   {
     identityKey, certId, contactEmail,
     challengeBundle: { questions, salt, answerHashes, kdfIterations },
     encryptedRecoverySeed: { ciphertext, nonce, tag, aad },
     derivationContexts: [...],
     edgeRecipes: [],
     algorithmVersion: 1
   }
   Signs envelope with identity key.
8. wallet self-issues a local BRC-52 identity certificate signed by
   the identity key it just derived.
9. wallet writes the recovery envelope to local storage as the §6.5
   RECOVERY_ENVELOPE cell. The envelope is the user's recovery
   anchor; the seed is not stored anywhere else in plaintext.
10. wallet UI: per-tier daily-use auth factor setup (§4.1):
    - Tier 0 (<1M sats): no factor — sign without prompt
    - Tier 1 (1M–10M):   PIN  → Argon2id KEK encrypts Tier-1 base
    - Tier 2 (10M–100M): biometric → secure-element KEK encrypts Tier-2 base
    - Tier 3 (100M+):    vault factor (passphrase + biometric, or YubiKey,
                          or — in v0.2 — m-of-n multisig per §4.3)
11. wallet writes encrypted Tier-N base-key blobs to local storage.
12. wallet writes the initial POLICY cell (§6.3) signed by the identity key.
13. wallet writes an empty DerivationState cell (§6.4).
14. wallet wires the LocalStateStore into the DerivationStateStore
    interface; PlexusStateStore and FederatedSemantosStateStore
    are stubbed (no-op).
15. wallet displays a persistent banner:
    "Your wallet is ready on this device. Lost device + lost answers
     = lost wallet. Lost device + remembered answers + your envelope
     file backed up = recoverable. Don't want to back up the file
     yourself? Enroll in recovery for $X / year and we hold the
     ciphertext for you (we still can't read your seed without your
     answers)."
16. wallet is fully functional for all four tiers, with fresh-key-per-tx
    derivation active from the first spend. ready.
```

Notes:

- **The mnemonic is NOT shown to the user**. The user's recovery knowledge is the three challenge answers + their email. Unlike legacy wallets where the seed phrase IS the recall material, here the seed is random; the answers regenerate the KEK that decrypts the seed.
- **The seed is wiped from memory after step 11.** It exists in plaintext only during the create flow itself. Subsequent unlocks of tier base keys go through the daily-use layer (§4.1), not through the seed.
- **Backup options surfaced to the user**: (a) write down the answers offline (paper / password manager), (b) export the envelope cell as a `.semantos-envelope` file for personal backup, (c) enroll in Plexus to have the envelope held server-side. (a) is mandatory; (b) and (c) are optional and complementary.

### 7.7 Plexus enrollment — transmit the existing envelope

At any time after creation, the user can opt into Plexus recovery. **The envelope already exists** — enrollment is simply transmitting it to the operator and confirming with email OTP. No new cryptography happens at enrollment time.

```
1. wallet UI: "Enroll in recovery" button → enrollment dialog
   (only shows the choice of operator + the price; no challenge
    re-prompt, since the envelope was built at creation §7.6)
2. wallet loads the existing recovery envelope from §6.5 cell
3. wallet POSTs envelope to operator's /enrollment/dispatch
   (BRC-100-signed request: x-brc100-identitykey / nonce /
    timestamp / signature headers per the canonical digest spec
    docs/design/BRC100-CANONICAL-DIGEST.md)
4. Plexus rate-limits per email + identity key, sends OTP to the
   contact email already stored in the envelope
5. wallet UI prompts user to enter the OTP
6. wallet POSTs the OTP to operator's /enrollment/confirm
7. on success: Plexus sweeps the envelope into its DB, marks recovery
   enrolled, starts the subscription billing cycle
8. wallet UI removes the "no recovery" banner, displays
   "Recovery enrolled — managed by {operator domain}"
```

Failure modes (no change of state on the wallet side except the banner):

- OTP timeout / bad code → operator drops the envelope from its temporary buffer; wallet stays in "no recovery enrollment" state but the local envelope is unaffected. User can retry.
- Network failure during dispatch → wallet retries automatically, surfaces a "retry enrollment" affordance.
- Subscription lapses → operator's policy: archive vs delete, per their TOS. Wallet shows "recovery enrollment expired" warning. The user's local envelope is still intact, so recovery via personal backup remains possible.

### 7.8 Disaster recovery — two paths

User loses all devices. The flow depends on where the recovery envelope is held.

The Plexus path follows the **four-phase canonical structure** from Plexus Technical Requirements v1.3 §11: **(1) Email OTP Verification → (2) Challenge-Response Validation → (3) Metadata Export → (4) Client-Side Key Reconstruction**. Phases 1–2 happen on the operator side (with the wallet supplying inputs); phases 3–4 happen on the wallet side using payload supplied by the operator. The local-backup path collapses phases 1–3 into a single file-load step, then runs phase 4 identically.

**Path A — Plexus-enrolled** (envelope held server-side):

```
1. fresh device → wallet bundle loaded
2. wallet: "Recover existing identity" → asks for contact email
3. wallet POSTs to operator's /recovery/initiate
4. operator rate-limits, sends recovery OTP to the email
5. user enters OTP
6. operator returns the stored challenge questions (the salted answer
   hashes are returned along with the encrypted envelope, but the
   wallet doesn't yet have the user's answers to verify them)
7. user supplies answers locally
8. wallet computes salted hashes locally and posts them to
   /recovery/complete
9. operator verifies hashes match; on match, releases the full
   encrypted envelope (derivation metadata + encrypted recovery seed +
   derivation_state_snapshot)
10. wallet derives the recovery KEK locally:
    KEK = PBKDF2-HMAC-SHA256(normalized_answers || salt, 100k, 32)
11. wallet decrypts the recovery seed via AES-256-GCM with the KEK
12. wallet derives identity + Tier 0/1/2/3 base keys via BRC-42
13. wallet prompts user to re-establish device-local daily-use auth
    factors (§4.1) on the new device (new PIN, register biometric)
14. wallet re-encrypts tier base keys under the new daily-use KEKs
    and persists tier blobs
15. wallet replays the derivation_state_snapshot into the local
    DerivationStateStore so fresh-key-per-tx resumes at the next index
16. wallet loads or rebuilds POLICY cell
```

**Path B — Local envelope backup** (user kept the `.semantos-envelope` file):

```
1. fresh device → wallet bundle loaded
2. wallet: "Recover from backup file" → user uploads the file
3. wallet parses it as a §6.5 RECOVERY_ENVELOPE cell, verifies
   the identity_signature (sanity-check the file isn't corrupted)
4. wallet asks for the three challenge answers
5. wallet derives KEK locally + decrypts the seed (steps 10-12 above)
6. wallet prompts for new daily-use factors and persists tier blobs
   (steps 13-16 above)
```

Plexus and personal-backup paths produce **identical** wallet state because they decrypt the same envelope ciphertext with the same KEK derivation. Plexus is purely a hosted-storage substitute for the user holding the file.

In neither path does Plexus see the raw answers or the plaintext seed. It holds: the salted answer hashes (so it can rate-limit and reject obviously wrong answers before releasing the envelope), the encrypted seed ciphertext, and the derivation metadata necessary to reconstruct the wallet's structure once decryption succeeds.

Plexus never holds a private key or a plaintext challenge answer. It holds metadata + recovery-seed ciphertext + salted answer hashes. Combined with the user's correct challenge answers (entered fresh on the new device), the device reconstructs the seed and walks the derivation DAG.

If the user did not enroll (§7.7), there is no recovery — the wallet is offering the same security guarantees as a paper-backup-only wallet, with the same limitation. The "Recovery not configured" banner is the wallet's mechanism for nudging users toward paid enrollment.

### 7.9 Returning device boot path — what works on tab reload without re-recovery

A returning user opens the wallet popup on a device they've used before.
The seed was wiped at creation (§7.6 step 11), so what's available without
running the full recovery flow?

Available immediately on tab reload (loaded from IndexedDB into runtime):
  - Identity public key + cert id (from KV_KEYS.IDENTITY)
  - Current POLICY (from KV_KEYS.POLICY)
  - Recovery banner state (LOCAL_ONLY | ENROLLED | EXPIRED)
  - Hot budget cell (Tier 0) — decrypted under the deterministic
    session KEK (§4.1 — derived from a per-install machine secret;
    v0.1 falls back to a deterministic-from-identityPk derivation)
  - The persisted recovery envelope (KV_KEYS.RECOVERY_ENVELOPE)

Available after presenting the daily-use factor for that tier:
  - Tier-1 base key — present PIN → Argon2id KEK → decrypt slot 1
  - Tier-2 base key — biometric assertion → KEK → decrypt slot 2
  - Tier-3 base key — vault factor (or v0.2 multisig satisfaction)

Available only via full recovery flow (§7.8):
  - The root seed (challenge answers → PBKDF2 → AES-GCM decrypt
    encryptedRecoverySeed inside the envelope)
  - Anything that requires re-deriving keys from the seed (e.g.,
    discovering an additional derivation context that's not in the
    snapshot)

So the typical "returning user" UX is:
  - Open popup → status panel renders immediately (Tier 0 available,
    identity ready for getPublicKey)
  - User initiates a Tier-1+ spend → factor prompt → done
  - User does NOT re-enter their challenge answers on every visit
    — that's only for cross-device recovery

This means the wallet feels "always-on" for hot operations, even though
the seed only materializes during the recovery flow. The challenge
answers are recovery-tier knowledge, not session-tier knowledge.

**Implementation note (v0.1):** identity sk is encrypted at creation under
`HMAC-SHA256(identityPk, "session-kek")` and stashed at
`KV_KEYS.IDENTITY_SK_BOOT_CACHE`. `wallet-ops.unlockIdentityFromCache()`
re-derives that KEK from the loaded identity record and AES-GCM-decrypts
the blob — no seed, no challenge answers, no UI. v0.2 swaps this
deterministic KEK for a per-install hardware-bound secret so the cache
becomes non-portable across machines (§4.1).

---

## 8. Plexus Boundary

### 8.1 Plexus is an external paid service

Plexus is operated by a separate company (plexus-keys.com or equivalent) implementing the Plexus Technical Requirements v1.3 + Client Requirements v2.1. **The wallet is not coupled to it.** Wallet creation, signing at every tier, and dApp interaction never call Plexus.

Plexus is contacted in exactly two scenarios, both opt-in and both initiated by the user:

| Scenario | Endpoint | Frequency |
|---|---|---|
| Recovery enrollment dispatch | `POST plexus-keys.com/enrollment/dispatch`, `POST /enrollment/confirm` (OTP) | Once per identity that opts in |
| Disaster recovery | `POST plexus-keys.com/recovery/initiate`, `POST /recovery/complete` (OTP + challenge) | Once per fresh device after device loss, only if previously enrolled |

The wallet bundle includes a small **Plexus Dispatch Module** (~few hundred lines of Zig) that:

- Builds the dispatch envelope (§8.2) from local state.
- Signs it with the identity key in BRC-100 wire format.
- Handles the OTP loop UI.
- Implements the recovery POST flow.

The full Plexus Core Library (TS, per Tech Reqs §2) lives at the Plexus operator, not in the wallet. The wallet only needs to *speak* Plexus's wire protocol enough to enroll and recover; it does not need to *implement* the recovery substrate.

### 8.2 Dispatch envelope schema

Sent as the body of `POST plexus-keys.com/enrollment/dispatch`. JSON, camelCase per Plexus Contracts requirements (Tech Reqs §3). Wrapped in a BRC-100 signed request — `x-brc100-identitykey`, `x-brc100-nonce`, `x-brc100-timestamp`, `x-brc100-signature` headers per Plexus Network SDK requirements.

```jsonc
{
  "envelopeVersion": 1,
  "identityKey": "<33-byte compressed secp256k1 pubkey, hex>",
  "certId": "<32-byte BRC-52 cert hash, hex>",
  "contactEmail": "user@example.com",

  // Server-side stores hashes only — raw answers never leave device.
  "challengeBundle": {
    "questions": [
      "Mother's maiden name?",
      "First pet?",
      "City of birth?"
    ],
    "salt": "<32-byte random salt, hex>",
    "answerHashes": [
      "<sha256(salt || normalize(answer1)), hex>",
      "<sha256(salt || normalize(answer2)), hex>",
      "<sha256(salt || normalize(answer3)), hex>"
    ],
    "kdfIterations": 100000   // PBKDF2 cost factor for seed encryption KEK
  },

  // The recovery seed is encrypted client-side under a KEK derived
  // (PBKDF2-100k) from the concatenated normalized challenge answers.
  // Plexus stores ciphertext only and never sees the answers or the seed.
  "encryptedRecoverySeed": {
    "ciphertext": "<AES-256-GCM ciphertext, hex>",
    "nonce": "<12-byte GCM nonce, hex>",
    "tag": "<16-byte GCM auth tag, hex>",
    "aad": "<additional data: identityKey || envelopeVersion, hex>"
  },

  // Per-tier derivation metadata — minimum needed to reconstruct
  // the tier keys from the recovered seed.
  "derivationContexts": [
    {
      "tier": 1,
      "brc43InvoiceString": "1-tier-key-1",
      "domainFlag": "0x10000003",
      "recoveryPolicy": "BACKUP_ON_CREATE"
    },
    {
      "tier": 2,
      "brc43InvoiceString": "1-tier-key-2",
      "domainFlag": "0x10000004",
      "recoveryPolicy": "BACKUP_ON_CREATE"
    },
    {
      "tier": 3,
      "brc43InvoiceString": "1-tier-key-3",
      "domainFlag": "0x10000005",
      "recoveryPolicy": "BACKUP_ON_CONFIRM"
    }
  ],

  // BRC-69 revelation recipes for each enrolled edge (peer relationship).
  // Initially empty for a fresh enrollment; appended over time as the
  // user creates new edges they want recoverable.
  "edgeRecipes": [],

  // Snapshot of the wallet's local DerivationState (§3.5.2 / §6.4) at
  // dispatch time. Allows recovery on a fresh device to resume derivation
  // at the exact next index per (protocol, counterparty) context, with
  // no gap-scanning required. Updated incrementally via the v0.2 endpoint
  // (see §11 Q7).
  "derivationStateSnapshot": {
    "records": [
      {
        "protocolHash": "<16-byte hex>",
        "counterparty": "<33-byte compressed pubkey hex>",
        "currentIndex": 0
      }
    ],
    "snapshotTimestamp": "<RFC3339>"
  },

  // Algorithm version per Plexus Tech Reqs §2 — allows future
  // KDF / curve changes while preserving recoverability of legacy keys.
  "algorithmVersion": 1
}
```

**Invariants the wallet enforces before dispatch (mechanically checkable):**

1. No field anywhere in the envelope contains a plaintext private key, mnemonic, or plaintext challenge answer.
2. `encryptedRecoverySeed.ciphertext` decrypts to a valid 64-byte BIP39 seed only when AES-GCM-keyed by `PBKDF2(normalize(answer1) || normalize(answer2) || ..., salt, kdfIterations)`.
3. `answerHashes[i] == sha256(salt || normalize(answer_i))` for the same answers used in the KEK derivation. (This means hash and KEK derivation use the *same normalized inputs* — Plexus can verify the hashes during recovery, then the wallet uses the KEK derived from the same answers to decrypt locally.)
4. The envelope is signed by the identity key whose public form is `identityKey`.
5. `certId` matches the BRC-52 cert this identity is using.

The Plexus operator runs these as receiving-side validation before storing.

### 8.3 OTP + rate limiting (Plexus side)

The Plexus operator implements (per Plexus Client Requirements v2.1 §1.2 and Plexus Technical Requirements v1.3 §9):

- **6-digit OTP**, 10-minute strict expiration timer, generated per recovery session.
- **10 recovery initialization attempts per hour** per `contactEmail`, to defeat brute-force attacks on the OTP issuance step.
- **Lockout after 5 consecutive failed verification attempts** (wrong OTP or wrong challenge hashes). At lockout, the recovery session is halted and a fresh initiate is required after the rate-limit window expires.
- After OTP verification on enrollment, Plexus stores the envelope keyed on `(identityKey, contactEmail)` and starts the subscription billing cycle.
- The signed export payload (Phase 3 of recovery — see §7.8) is BRC-100-signed by Plexus's own designated **ATTESTATION** functional-domain key (Plexus Domain Flag `0x05`) so the wallet can verify the export's authenticity / integrity before reconstructing keys from it.

The wallet must not implement these — they are Plexus operator policy. The wallet's responsibility ends at posting the envelope and surfacing the operator's OTP / rate-limit / lockout errors back to the user.

**Domain flag namespace** (per Tech Reqs v1.3 §5 and Client Reqs v2.1 §2.2): the 4-byte `domainFlag` space is partitioned `0x00000001–0x000000FF` (Plexus reserved well-known flags including ATTESTATION = `0x05`), `0x00000100–0x0000FFFF` (extended standard flags), `0x00010000–0xFFFFFFFF` (client-defined sovereign). The wallet's tier flags (`0x10000001` hot, `0x10000002+N` tier-N) sit in the sovereign range; the recovery-envelope cell's `domain_flag` (`0x10000030`, §6.5) likewise. No collision with Plexus's namespace.

**Payload size budget** (per Tech Reqs v1.3 §11 and Client Reqs v2.1 §1.3): the recovery-export JSON payload is target-budgeted at ~3.4 KB for a "standard" profile (5 apps, 3 domains each, 20 peer connections, 10 hierarchical relationships). The wallet's v0.1 single-identity profile is well under that ceiling — typically 1.5–2 KB. The Plexus operator signs the outgoing payload using the RaaS BRC-100 signature; the wallet verifies before reconstruction.

### 8.4 What this means for offline use

A wallet bundle running from `file://` with no network can:

- Create a fresh wallet (§7.6)
- Sign at every tier
- Manage policy
- Refill hot from vault

Cannot:

- Enroll in Plexus recovery (requires network for the OTP loop)
- Recover from device loss (requires network)
- Broadcast transactions (requires network — though the wallet can sign and export raw txs for relay via another path)

The offline mode degrades gracefully: the user sees the "recovery not configured" banner and, depending on context, can either come back online to enroll or accept that they're operating purely on local storage + their own paper backup.

---

## 9. Proof Obligations

### 9.1 Lean — new theorems

| ID | Theorem | File |
|---|---|---|
| K11a | OP_SIGN on LINEAR cell consumes it (linearity preserved) | `Theorems/SignSoundnessK11.lean` |
| K11b | OP_SIGN output verifies under corresponding pubkey (uses new `ecdsa_sign_verifies` axiom) | `Theorems/SignSoundnessK11.lean` |
| K11c | OP_SIGN failure ⇒ stack unchanged (atomicity, parallels K2a) | `Theorems/SignSoundnessK11.lean` |
| K12a | No reachable script execution copies a LINEAR key cell into a non-linear cell | `Theorems/KeyCustodyK12.lean` |
| K12b | Tier-N key cell consumption requires the tier-N domain flag check before OP_SIGN | `Theorems/KeyCustodyK12.lean` |
| K13 | Budget monotonicity — `OP_DECREMENT_BUDGET` strictly decreases `remaining_satoshis`; `OP_REFILL_BUDGET` increases only with valid parent signature | `Theorems/BudgetMonotonicityK13.lean` |

New axiom in `proofs/lean/Semantos/CryptoAxioms.lean`:

```lean
axiom ecdsaSign : SecKey → Bytes → Bytes
axiom ecdsa_sign_verifies :
  ∀ (sk : SecKey) (pk : PubKey) (msg : Bytes),
    derives pk sk → ecdsaVerify pk msg (ecdsaSign sk msg) = true
```

EUF-CMA companion to the existing `ecdsa_existential_unforgeability` axiom — same idealization style, same justification block.

New module `proofs/lean/Semantos/Opcodes/Sign.lean` modeling `opSign` with the same peek-then-mutate three-branch shape as `opCheckCapability`.

### 9.2 TLA+ — new modules

| Module | Models |
|---|---|
| `proofs/tla/KeyCustody.tla` | Per-tier-key state machine `{encrypted_at_rest, decrypted_in_engine, consumed, reconstructible_via_plexus}`. Invariants: no `consumed → decrypted_in_engine` transition without going through `reconstructible_via_plexus`; no key in `decrypted_in_engine` state in two stack slots simultaneously. |
| `proofs/tla/TierEscalation.tla` | Tier classification + cooldown. Invariants: every spend signed at tier T satisfies the `factor_kind(T)` requirement from the current POLICY; consecutive Tier-3 spends respect cooldown via host clock (v0.1) or `nSequence` (v0.2). |
| Extension to `proofs/tla/ReplayPrevention.tla` | Add OP_SIGN nonces / sighash inclusion to the existing replay model. |

Liveness obligations:

- Any Tier-0 spend below `remaining_satoshis` eventually completes without UI prompt.
- Any Tier-N (N ≥ 1) spend eventually completes given the user's correct auth factor.
- Disaster recovery eventually succeeds given valid OTP + correct challenge answers.

### 9.3 Differential testing

Extend `core/cell-engine/tests/differential_conformance.zig` to cross-check `OP_SIGN` outputs against bsvz's `primitives.ecdsa` standalone for every test vector. The bsvz interpreter (1,499-test corpus, 1,435 passing) is the second independent implementation for differential fuzzing.

---

## 10. Deployment Topologies

The same Zig codebase compiles to two targets. The signing kernel is bit-identical across both — the `WASM-MANIFEST.json` SHA-256 in the browser bundle equals the SHA-256 of the WASM segment linked into the node binary. Hash-pinned, auditable.

### 10.1 Vanilla browser (WASM)

```
                      ┌───────────────────────────────────┐
                      │  browser tab — dApp origin         │
                      │  (any vanilla Chrome / Safari /    │
                      │   Firefox; no extension required)  │
                      └─────────┬─────────────────────────┘
                                │
                                │ postMessage (BRC-100 over
                                │  MessageChannel)
                                ▼
                      ┌───────────────────────────────────┐
                      │  hidden iframe                     │
                      │  src = wallet.semantos.{tld}/bridge│
                      │  ┌─────────────────────────────┐   │
                      │  │  cell-engine.wasm           │   │
                      │  │   (29KB embedded profile)   │   │
                      │  ├─────────────────────────────┤   │
                      │  │  bsvz-min.wasm              │   │
                      │  │   (signing primitives)      │   │
                      │  ├─────────────────────────────┤   │
                      │  │  IndexedDB                  │   │
                      │  │   - encrypted tier blobs    │   │
                      │  │   - POLICY cell             │   │
                      │  │   - BRC-52 cert             │   │
                      │  └─────────────────────────────┘   │
                      └─────────┬─────────────────────────┘
                                │
                                │ popup window opens for any
                                │ operation requiring a UI prompt
                                │ (sign-up, recover, Tier 1+ unlock)
                                ▼
                      ┌───────────────────────────────────┐
                      │  popup at wallet.semantos.{tld}    │
                      │   - PIN entry                       │
                      │   - WebAuthn biometric              │
                      │   - vault unlock                    │
                      │   - Plexus enroll/recover flow      │
                      │     (cross-origin to plexus origin) │
                      └───────────────────────────────────┘
```

Same bundle is downloadable as a zip and runs from `file://` for offline / paranoid users — same trust model as bitaddress.org plus a hash-pinned WASM verifier.

### 10.2 Sovereign Zig node

```
                       ┌──────────────────────────┐
                       │       Caddy (TLS)         │
                       │   wss://node.semantos     │
                       └──────────┬───────────────┘
                                  │
                       ┌──────────▼───────────────┐
                       │   semantos-node (Zig)     │
                       │ ┌──────────────────────┐  │
                       │ │  cell-engine (Zig)    │  │
                       │ │   + OP_SIGN +         │  │
                       │ │     OP_BUDGET ops     │  │
                       │ └──────────────────────┘  │
                       │ ┌──────────────────────┐  │
                       │ │  bsvz                 │  │
                       │ │   (primitives, SPV)   │  │
                       │ └──────────────────────┘  │
                       │ ┌──────────────────────┐  │
                       │ │  plexus-zig           │  │
                       │ │   (enroll/recover     │  │
                       │ │    only — not in hot  │  │
                       │ │    path)              │  │
                       │ └──────────────────────┘  │
                       │ ┌──────────────────────┐  │
                       │ │  storage (lmdb)       │  │
                       │ │   encrypted blobs     │  │
                       │ └──────────────────────┘  │
                       └──────────┬───────────────┘
                                  │
                                  │ wss:// BRC-100 endpoint
                                  ▼
                          (browser dApps, also served the
                           same wallet UI bundle by Caddy
                           from the same origin)
```

Sovereign node also participates in the federated p2p mesh and serves its own wallet UI to its operator's browser at the same origin.

### 10.3 Configuration surface — where each setting is set

| Setting | Set where | Persisted where | Notes |
|---|---|---|---|
| BIP39 mnemonic | Generated locally by wallet at creation | Shown to user once; never persisted by wallet; user may write down for cold backup | Plexus alternative covers users who don't want paper backup |
| BRC-52 identity cert | Self-issued locally by wallet at creation, signed by the freshly-derived identity key | Local storage at wallet origin | No external dependency |
| Per-tier sat ceilings | Wallet UI at wallet origin | POLICY cell, locally cached, identity-signed | Not stored at Plexus |
| Per-tier auth factor (PIN / biometric / vault) | Wallet UI; factor enrollment uses native OS / WebAuthn | KEK derivation salt + WebAuthn credential ID stored at wallet origin; secret stays in OS / Secure Enclave | Wallet never sees raw factor |
| Tier-N encrypted key blob | Derived locally from BIP39 seed via BRC-42 | Local storage at wallet origin, AES-GCM encrypted under per-tier KEK | Recoverable via Plexus *only if* the user opted in (§7.7) |
| Cooldown duration | Wallet UI | POLICY cell field `tier3_cooldown_seconds` | v0.1 host-enforced; v0.2 `nSequence`-enforced |
| Contact email + challenge questions/answers | Wallet UI at wallet origin (during opt-in enrollment) | Hashes + ciphertext shipped to Plexus via dispatch envelope; raw answers wiped from memory after envelope build | See §8.2 |
| Recovery enrollment status / subscription | Plexus operator side | Plexus DB | Wallet displays banner state |

Everything in the wallet's own operation is **at the wallet origin**, in **local storage**, **identity-signed**. Plexus stores only what arrives in the dispatch envelope: identity key, contact email, salted answer hashes, encrypted recovery seed, derivation metadata, BRC-69 recipes. Plexus never receives raw private keys, mnemonics, or plaintext challenge answers.

---

## 11. Open Questions

1. **WebAuthn for Tier 1 PIN?** Browser WebAuthn supports PIN-protected credentials; this lets us avoid implementing Argon2id in the wallet at all (the platform handles KDF). Decide before implementing `host_unlock_tier`.
2. **Cooldown enforcement v0.1 → v0.2 path**: when do we cut over from host-clock cooldown to `nSequence`-based? The `nSequence` path requires every Tier-3 spend to chain-create the next vault UTXO with the locktime baked in — non-trivial UTXO management. Probably defer to v0.2 with multisig.
3. **POLICY cell version conflicts**: the wallet runs in browser tabs and possibly a sovereign node simultaneously. If two instances both write a new policy version, which wins? Identity-signed monotonic version numbers — both signed, higher version wins on next load. Conflicts resolved by displaying both to the user.
4. **Browser bundle size**: cell-engine embedded profile is 29KB; trimmed bsvz (signing primitives only) is probably ~80–120KB of WASM; UI shell ~30KB. Total budget around 150–200KB compressed. Acceptable.
5. **Pre-enrollment dApp interaction**: dApp interaction works as soon as a wallet exists locally — no Plexus enrollment required. The wallet always has an identity key (self-issued at creation). dApps see "wallet ready" regardless of recovery status.
6. **Caddyfile structure**: route `wss://node.semantos.{tld}/wallet` to the BRC-100 endpoint; route `https://node.semantos.{tld}/` to the wallet UI; route `https://node.semantos.{tld}/p2p/*` to the federated mesh layer. To be specified in `runtime/node/Caddyfile`.
7. **Dispatch envelope incremental updates**: as the user creates new edges (peer relationships) over time, those need to be appended to the Plexus-stored envelope. Either (a) re-dispatch a full envelope on each change (simple, larger payload), or (b) define an `/enrollment/append-edge` endpoint that takes incremental signed deltas. Decide with Plexus operator before locking the schema.
8. **Subscription lapse semantics**: if the user lets their Plexus subscription expire, what happens? Plexus operator policy choice — graceful: keep envelope archived for N months, allow re-activation; harsh: delete after expiry. Wallet should surface this to the user during enrollment so they understand the recovery longevity guarantee.
9. **Multiple Plexus operators**: can a user enroll the same identity in multiple competing recovery operators (defense in depth)? The envelope schema is operator-agnostic; nothing in the wallet prevents this. Worth offering as an advanced option.
10. **Pricing display**: the "Recovery not configured" banner mentions a price. The wallet should fetch the current price from the configured Plexus operator's `/info` endpoint at first dispatch attempt rather than hard-code a number.
11. **DerivationState gap window**: the v0.1 default for unsynced recovery is to skip ahead 100 indices per context. Is 100 right? Too low risks index re-use after a recovery if the user signed >100 spends per context between snapshots; too high inflates recovery scan time. Probably configurable per tier with sane defaults.
12. **DerivationState sync trigger** (v0.2 PlexusStateStore): per-increment sync is heavy and online-required; periodic sync (every N increments or T seconds) loses a window on recovery. Likely answer: per-increment in the background with local persistence first, async retry on network failure, surface the sync lag in the wallet UI.
13. **Federated state sync over the Semantos mesh** (v0.3 FederatedSemantosStateStore): conflict resolution if two of the user's nodes both allocate from the same context concurrently. CRDT (last-writer-wins on `(context, max(index))`) probably suffices for monotonic counters, but worth specifying.
14. **`OP_DERIVE_LEAF` opcode vs `host_derive_leaf` import**: currently specced as a host import. Could promote to a dedicated opcode (e.g., 0xCB-adjacent) with the same peek-then-mutate failure-atomicity as `OP_SIGN`, which would let the linearity proofs cover the base→leaf transition structurally. Trade-off: more engine surface vs cleaner proofs. Decide before W3.

---

## 12. Implementation Order

| Phase | Deliverable |
|---|---|
| W1 | `OP_SIGN` opcode + `host_sign` import; failure-atomic implementation; `tests/sign_conformance.zig` differential against bsvz. |
| W2 | `Sign.lean` opcode model + `SignSoundnessK11.lean` theorems. |
| W3 | `OP_DECREMENT_BUDGET` + `OP_REFILL_BUDGET` + budget cell layout. `BudgetMonotonicityK13.lean`. |
| W3.5 | `DerivationStateStore` interface + `LocalStateStore` impl (IndexedDB / lmdb). Empty stubs for `PlexusStateStore` and `FederatedSemantosStateStore`. `DerivationState` cell type + `host_state_next_index` + `host_derive_leaf` host imports (bsvz `primitives.ec.deriveChild`). Atomic-write conformance tests. |
| W4 | `host_unlock_tier` + `host_persist_cell` + `host_load_cell`; AES-GCM at-rest encryption (bsvz `primitives.aesgcm`). |
| W5 | Browser bundle target: trim bsvz to a signing-only WASM; build the iframe + popup transport for BRC-100 over postMessage. |
| W6 | Sovereign-node target: Caddyfile + WSS BRC-100 endpoint; same WASM kernel, lmdb storage backend. |
| W7 | **Plexus Dispatch Module** — local envelope builder + signer, OTP loop UI, recovery POST flow. Conformance-tested against the Plexus operator's staging endpoint to confirm envelope schema acceptance. No Plexus Core Library port required — only the wire interface. |
| W8 | `KeyCustody.tla` + `TierEscalation.tla` model checking. |
| W9 | Wallet UI (HTML/WASM) — first-time enrollment, per-tier auth factor setup, policy editor, send/receive screens. |
| W10 | End-to-end recovery test: wipe IndexedDB, walk Plexus recovery on a fresh browser, spend at every tier. |
| W11 (v0.2) | Vault tier multisig over `BACKUP_ON_CREATE` keys; `nSequence`-based cooldown. |

---

*Cross-references*

- `core/cell-engine/src/opcodes/plexus.zig` — peek-then-mutate failure-atomic pattern reference
- `core/cell-engine/src/opcodes/hostcall.zig` — why OP_SIGN is a dedicated opcode, not an OP_CALLHOST target
- `core/cell-engine/src/host.zig` — host import dispatch pattern
- `proofs/lean/Semantos/CryptoAxioms.lean` — existing ecdsaVerify / sha256 / hmac axioms
- `proofs/lean/Semantos/Theorems/AuthSoundnessK2.lean` — pattern to mirror for SignSoundnessK11
- `proofs/lean/Semantos/Theorems/LinearityK1.lean` — linearity invariant K11/K12 inherit from
- `proofs/tla/ReplayPrevention.tla` — existing model OP_SIGN nonces extend
- `core/protocol-types/src/adapters/brc100-wallet-stub.ts` — interface this Zig wallet eventually replaces
- `docs/FORMAL-VERIFICATION-STRATEGY.md` — overall proof strategy this design slots into
- Plexus Client Requirements Draft v2.1, §1.1 (context/edge enrollment), §1.4 (recovery policy)
- Plexus Technical Requirements Draft v1.3, §2 (Plexus Core Library — pure functions, on-device only)
- bsvz README — `primitives.ec`, `primitives.ecdsa`, `primitives.aesgcm`, `primitives.bip32`, `primitives.bip39`, `primitives.brc43`
