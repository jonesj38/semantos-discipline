---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/design/VAULT-MULTISIG-NSEQUENCE.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.732252+00:00
---

# Semantos Wallet — v0.2 Vault Tier: Multisig + nSequence Cooldown

**Version**: 0.2 DRAFT
**Status**: Implementation (W11)
**Authors**: Todd
**Related**:
  - `docs/design/WALLET-TIER-CUSTODY.md` §4.3 (vault stub vs multisig), §4.4 (cooldown), §6.2.1 (per-tx leaf cell), §11 Q2 (cooldown migration path)
  - `core/cell-engine/src/opcodes/plexus.zig` (`VAULT_OFFSET_*`, `BUDGET_OFFSET_*`)
  - `core/cell-engine/src/host.zig` (`host.checkmultisig`, BSV consensus rule)
  - `proofs/lean/Semantos/Theorems/VaultMultisigK14.lean` (K14a / K14b / K14c)
  - `proofs/tla/VaultCooldownNsequence.tla` (`INV_NsequenceRespected`, `LIVE_VaultEventuallySpendable`)
  - `apps/wallet-browser/src/vault.ts` (browser-side cell builder + signer)

---

## 1. What v0.2 changes (and what it does not)

The v0.1 vault tier (Tier 3) was a single LINEAR key cell encrypted under a strong KEK (passphrase ⊕ biometric or YubiKey HMAC-SHA1). That worked but had two limitations:

| v0.1 limitation | v0.2 fix |
|---|---|
| Vault key compromise = full Tier-3 spend authority. | m-of-n multisig over distinct secure-element keys. No single device can spend. |
| Cooldown enforced by host clock (spoofable by a malicious wallet build). | Cooldown enforced by BSV consensus via BIP-68 `nSequence`. Network rejects too-early spends. |

What v0.2 keeps:

- **Tier 0/1/2 unchanged.** v0.2 is vault-tier-only. No new opcodes. `host_sign`, `host_checksig`, `host_checkmultisig`, `host_unlock_tier`, `host_persist_cell`, `host_load_cell` are all reused exactly as W1–W4 left them.
- **Per-tx fresh keys (BRC-42).** Even with multisig, every Tier-3 spend uses a fresh leaf key for the on-chain pubkey. The multisig members sign over the tx preimage; the leaf is the BRC-42 derivation receipt.
- **Linearity discipline.** The vault leaf cell is LINEAR (consumed by `OP_SIGN`). K1 / K12 / K11 all extend structurally — see `VaultMultisigK14.lean` for the K14c statement.
- **Backwards compatibility.** A v0.1 stub Tier-3 cell (no member pubkey table, no nSequence) continues to load and spend through the existing flow. v0.2 is opt-in per identity and does NOT migrate v0.1 vaults automatically.

---

## 2. Vault cell layout (extended §6.2.1)

The §6.2.1 per-tx leaf cell is extended with a multisig metadata block. All offsets are relative to the payload start (cell byte `HEADER_SIZE = 256`). Match `core/cell-engine/src/opcodes/plexus.zig`'s `VAULT_OFFSET_*` constants in lockstep.

```
Header (256 bytes):
  [00..16]   magic = DEADBEEF CAFEBABE 13371337 42424242
  [16..20]   linearity = 1 (LINEAR)              ← per §6.2.1
  [20..24]   version = 1
  [24..28]   domain_flag = 0x10000005 (Tier-3)
  [28..62]   ref_count + type_hash               ← carried over from cell.zig
  [62..78]   owner_id (16 bytes)
  [78..256]  reserved/binding/etc

Payload (768 bytes):
  [00..32]   leaf_priv_key       ← BRC-42-derived per-tx leaf
  [32..48]   protocol_hash (16 bytes)
  [48..81]   counterparty (33 bytes compressed)
  [63..64]   threshold (u8)                       ← VAULT_OFFSET_THRESHOLD
  [64..229]  member_pubkeys[5 * 33]               ← VAULT_OFFSET_MEMBER_PUBKEYS_START
                                                    Up to VAULT_MAX_MEMBERS=5.
                                                    Unused slots zero-filled.
  [229..233] nsequence (u32 LE, BIP-68)           ← VAULT_OFFSET_NSEQUENCE
  [233..265] parent_txid (32 bytes)               ← VAULT_OFFSET_PARENT_TXID
                                                    Identifies the UTXO this leaf is consuming.
  [265..768] zero-padded
```

### Why these offsets

`leaf_priv_key`, `protocol_hash`, `counterparty` keep the §6.2.1 prefix verbatim so any Tier-N flow that already understands a leaf cell continues to parse the head correctly. The W11 metadata block starts at byte 63 (just past the §6.2.1 prefix) and ends at byte 265 — well inside the 768-byte payload. The remaining 503 bytes are zero-padded for future expansion.

The threshold byte sits at +63 (single byte; threshold ∈ [1, 5] always fits). The member table is fixed-size (5 × 33 = 165 bytes) so all 5 slots are reserved even when only 2 or 3 are used. Empty slots are zero — `apps/wallet-browser/src/vault.ts:readMemberCount` walks slots and stops at the first all-zero entry.

`nsequence` is u32 LE because BIP-68's interpretation reads the field as a little-endian u32 from the BSV transaction format. `parent_txid` is the txid of the UTXO this vault leaf is consuming — used to verify the cooldown chain locally (see §4 below).

---

## 3. Multisig satisfaction script — concrete 2-of-3 example

A 2-of-3 vault uses three secure-element keys: phone enclave, laptop enclave, and a YubiKey. The on-chain locking script is the standard BSV `OP_CHECKMULTISIG` form:

```
OP_2  <pk_phone>  <pk_laptop>  <pk_yubikey>  OP_3  OP_CHECKMULTISIG
```

### Bytes

For an example 2-of-3 with three concrete compressed pubkeys (each 33 bytes; the exact bytes depend on member key generation — these are illustrative):

```
pk_phone   = 02 <32-byte-x-coord, e.g. ee...>
pk_laptop  = 03 <32-byte-x-coord, e.g. 7f...>
pk_yubikey = 02 <32-byte-x-coord, e.g. ab...>

Locking script (105 bytes total):

  52              ← OP_2 (m)
  21              ← push 33 bytes
  02 ee ee ee ee ee ee ee ee ee ee ee ee ee ee ee
  ee ee ee ee ee ee ee ee ee ee ee ee ee ee ee ee
  ee              ← <pk_phone>
  21              ← push 33 bytes
  03 7f 7f 7f 7f 7f 7f 7f 7f 7f 7f 7f 7f 7f 7f 7f
  7f 7f 7f 7f 7f 7f 7f 7f 7f 7f 7f 7f 7f 7f 7f 7f
  7f              ← <pk_laptop>
  21              ← push 33 bytes
  02 ab ab ab ab ab ab ab ab ab ab ab ab ab ab ab
  ab ab ab ab ab ab ab ab ab ab ab ab ab ab ab ab
  ab              ← <pk_yubikey>
  53              ← OP_3 (n)
  ae              ← OP_CHECKMULTISIG
```

Total length: 1 (OP_2) + 3 × (1 + 33) + 1 (OP_3) + 1 (OP_CHECKMULTISIG) = **105 bytes**.

### Unlocking script (input)

The redeemer presents two member sigs (any two of the three, in member-pubkey order):

```
OP_0  <sig_phone>  <sig_yubikey>
```

`OP_0` is the BSV consensus dummy item that consumes the off-by-one bug in the original `CHECKMULTISIG` opcode (BSV honors the bug bit-for-bit for compatibility). Each sig is `[len][DER + sighash byte]` per the BSV consensus calling convention; `host_checkmultisig` (`core/cell-engine/src/host.zig:369–442`) implements exactly this iteration order. `apps/wallet-browser/src/vault.ts:signVaultSpend` builds the same `[len][sig_with_sighash]` blob.

### Plexus prelude

The wallet's spend script wraps the standard multisig form with the same Plexus prelude every Tier-N flow uses (per `WALLET-TIER-CUSTODY.md` §7.4 and §5.2):

```
;; Verify the leaf cell is LINEAR and Tier-3.
OP_PUSH <vault_leaf_cell>           ;; 0x4d ... (1024 bytes)
OP_CHECKLINEARTYPE                  ;; 0xC0
OP_PUSH <0x10000005>                ;; tier-3 domain flag, big-endian u32
OP_CHECKDOMAINFLAG                  ;; 0xC6

;; Classic m-of-n multisig.
OP_0  <sig_phone>  <sig_yubikey>
OP_2 <pk_phone> <pk_laptop> <pk_yubikey> OP_3
OP_CHECKMULTISIG                    ;; 0xAE
```

The leaf cell is consumed by `OP_CHECKLINEARTYPE`'s downstream `OP_SIGN` if the wallet additionally wants a per-tx BRC-42 leaf signature recorded; v0.2 makes that optional — the multisig satisfaction is the cryptographic gate, the leaf cell carries the binding metadata so BRC-42 derivation state stays correct.

---

## 4. nSequence-based cooldown (BIP-68 on BSV)

Each vault UTXO embeds a relative locktime in its `nSequence` field. BSV honors BIP-68's encoding at consensus:

```
nsequence: u32, little-endian
  bit 31 (DISABLE_FLAG = 0x80000000):
    1 ⇒ no relative-lock constraint (legacy / non-vault outputs)
    0 ⇒ relative lock active
  bit 22 (TYPE_FLAG = 0x00400000):
    1 ⇒ time mode  (units = 512 seconds)
    0 ⇒ block mode (units = 1 block)
  bits 0..15 (VALUE_MASK = 0x0000FFFF): the actual cooldown value
  bits 16..21, 23..30: reserved (must be 0 for forward-compat)
```

### Encoding example: 60-second cooldown

```
60 / 512 = 0.117 → ceil = 1 unit (~512s)

DISABLE_FLAG = 0
TYPE_FLAG    = 1 (bit 22 set)
VALUE        = 1

nsequence = 0x00400001
```

`apps/wallet-browser/src/vault.ts:nextNSequence(_, 60)` returns exactly `0x00400001`. The wallet UI shows the next-spendable countdown by reading `parent_block_time + cooldown_secs` against the current block time (read from `host_get_blocktime`).

### Spend pattern

```
1. Wallet identifies the current vault UTXO (`vault_tip`):
     - txid = parent_txid in the local vault leaf cell, OR
     - looked up via the user's BRC-100 wallet UTXO set.
2. Wallet checks: current_block_time >= vault_tip.confirmed_at_block_time
                                       + decode_nsequence(vault_tip.nsequence)
   If false → UI displays the countdown; spend is blocked locally.
3. If true → wallet:
     a. Builds the spending tx with input.nSequence = vault_tip.nsequence.
        (This is what makes the BSV node honor the cooldown — the node
         checks `confirmed_at + nsequence_relative_blocks <= current_height`
         before accepting the tx.)
     b. Signs the multisig satisfaction with `signVaultSpend()`.
     c. Constructs the new chained vault UTXO with `nSequence = nextNSequence(... policy.tier3_cooldown_seconds)`.
     d. Broadcasts.
4. The new UTXO is confirmed at some block N+k; the next vault spend
   cannot confirm until block N+k+nsequence_relative_blocks (or
   equivalently +cooldown_seconds in time mode).
```

### Why this is consensus-equivalent to v0.1

The v0.1 host-clock check (`tier3_cooldown_seconds` in the POLICY cell) is enforced in the wallet's signing code path. A malicious wallet build could remove that check and re-spend immediately — the v0.1 attack vector. v0.2's `nSequence` check is enforced by the BSV network's mempool admission rule: a tx whose `nSequence` is not yet satisfied is rejected by every honest BSV node.

This means an adversary who *did* manage to satisfy the multisig (e.g., compromised m-of-n keys at once) STILL cannot drain the vault below the per-spend cap any faster than the cooldown allows — every chained UTXO carries the cooldown forward.

The TLA+ proof is in `proofs/tla/VaultCooldownNsequence.tla`:
- `INV_NsequenceRespected` — every spent UTXO had its `nsequence_relative_blocks` blocks elapse before its successor was confirmed.
- `LIVE_VaultEventuallySpendable` — given enough block progression, the next vault UTXO is eventually spendable (i.e., the wallet does not "stick" forever).

`make VaultCooldownNsequence` runs TLC against the spec with `MaxBlocks=10`, `MaxUtxos=3`, `DefaultNsequence=2` and reports no counterexamples (208 states, 140 distinct).

---

## 5. BACKUP_ON_CREATE recovery enrollment per member key

Each of the m-of-n member keys is enrolled in Plexus under the existing `BACKUP_ON_CREATE` recovery policy (per Plexus Client Reqs §1.4 and `WALLET-TIER-CUSTODY.md` §8.2). The wallet treats the vault as one logical identity but enrolls each member key as its own derivation context:

```jsonc
"derivationContexts": [
  {
    "tier": 3,
    "brc43InvoiceString": "1-vault-member-phone",
    "domainFlag": "0x10000005",
    "recoveryPolicy": "BACKUP_ON_CREATE"
  },
  {
    "tier": 3,
    "brc43InvoiceString": "1-vault-member-laptop",
    "domainFlag": "0x10000005",
    "recoveryPolicy": "BACKUP_ON_CREATE"
  },
  {
    "tier": 3,
    "brc43InvoiceString": "1-vault-member-yubikey",
    "domainFlag": "0x10000005",
    "recoveryPolicy": "BACKUP_ON_CREATE"
  }
]
```

The dispatch envelope schema (`apps/wallet-browser/src/plexus/envelope.ts`) already supports this — `RecoveryPolicy = 'BACKUP_ON_CREATE'` is one of the existing enum values. v0.2 just uses it; W11 introduces no envelope schema changes.

Recovery on a fresh device walks every enrolled member context and re-derives the corresponding member key from the BRC-69 recipe + decrypted recovery seed. The user re-establishes the secure-element binding (registers the recovered key with the new device's enclave) before the vault is fully usable.

If the user holds m or more independent member keys at recovery time (which is the design intent — distinct secure elements survive single-device loss), the vault is immediately usable on any subset of m. If fewer than m members survive, the vault is locked permanently — same security posture as any m-of-n multisig wallet.

---

## 6. Engine-level invariants and where each is proved

| Invariant | Where proved | Notes |
|---|---|---|
| LINEAR vault leaf consumed exactly once by `OP_SIGN`. | `LinearityK1.lean` K1c → `KeyCustodyK12.lean` K12a → **`VaultMultisigK14.lean` K14c** | Structural inheritance. |
| m-of-n satisfaction iff m ≥ threshold. | **`VaultMultisigK14.lean` K14a** | Lifts the existing `ecdsa_existential_unforgeability` + `ecdsa_sign_verifies` axioms. |
| Below-threshold (<m valid sigs) cannot satisfy. | **`VaultMultisigK14.lean` K14b** | Follows from K14a's iff + `countValidMemberSigs_le_length`. |
| Every vault spend respects nSequence (consensus-equivalent). | **`VaultCooldownNsequence.tla` `INV_NsequenceRespected`** | TLC verified on `MaxBlocks=10, MaxUtxos=3`. |
| Vault tip is eventually spendable given block progression. | **`VaultCooldownNsequence.tla` `LIVE_VaultEventuallySpendable`** | Liveness under WF on `AdvanceBlock` + `SpendVault`. |
| Vault cell tier-classifies as Tier-3 under the TS host. | `apps/wallet-browser/test/vault.spec.ts:'host_persist_cell tier-classifies a fresh vault cell (Tier-3)'` | Uses real `host.host_persist_cell`. |
| 2-of-3 spend signatures verify via real `host.checkmultisig`. | `core/cell-engine/tests/vault_conformance.zig:'vault: 2-of-3 multisig spend verifies via host.checkmultisig'` | Differential against bsvz `primitives.ec`. |
| Vault cell at-rest round-trips via AES-GCM + LMDB slot store. | `runtime/node/tests/vault_round_trip.zig:'Vault: AFFINE Tier-3 base cell round-trips through LmdbSlotStore'` | The 4 `Vault: …` tests cover both AFFINE base and LINEAR leaf. |

---

## 7. Backwards compatibility — v0.1 vaults still work

v0.2 is **additive**. A v0.1 vault stub cell (Tier-3 LINEAR with priv_key in payload[0..32] and zeros elsewhere) is structurally a v0.2 vault cell with `threshold=0` and an empty member table — and the wallet treats `threshold=0` as the v0.1 path:

```
if (cell.threshold == 0) {
    // v0.1 stub: passphrase-gated single-key flow.
    // host_unlock_tier(3, factor, slot) → leaf is the priv_key in payload.
    // Cooldown enforced by host clock (POLICY cell tier3_cooldown_seconds).
} else {
    // v0.2 multisig: m-of-n satisfaction.
    // host_unlock_tier(3, factor, slot) → leaf cell + member metadata.
    // Cooldown enforced by network via nSequence.
}
```

Tests:
- `core/cell-engine/tests/vault_conformance.zig` exercises the v0.2 path.
- `runtime/node/tests/vault_round_trip.zig:'Vault: v0.1 stub LINEAR cell still round-trips (no W11 regression)'` exercises the v0.1 path.
- `apps/wallet-browser/test/vault.spec.ts:'v0.1 backward compatibility'` exercises the v0.1 path through the TS host.

v0.2 is **opt-in per identity**. The wallet UI's vault setup screen offers two paths:
1. *Stub vault* (v0.1) — passphrase + biometric. No multisig setup required.
2. *Multisig vault* (v0.2) — register m-of-n secure-element keys. Each key is enrolled in Plexus under `BACKUP_ON_CREATE`.

Identities created under v0.1 keep using the stub. Identities created or upgraded under v0.2 use the multisig path. Migration is non-destructive: a v0.1 vault can be retired by spending its UTXO into a freshly-created v0.2 vault output, after which the v0.1 cell is deleted from local storage.

---

## 8. Out of scope for v0.2 / open questions

- **Heterogeneous member secure elements.** v0.2 assumes each member key lives in its own secure element (phone enclave / laptop enclave / YubiKey HMAC). The wallet does not currently abstract over different secure-element APIs — the TS code uses WebAuthn for browser members and PAM/Secure Enclave for sovereign-node members. A unified abstraction is v0.3.
- **Member key rotation.** If one member key is suspected compromised, the wallet has no in-place rotation flow — the user must spend the existing vault UTXO into a new vault with a different member set. Adding `OP_REPLACE_VAULT_MEMBER` would let the wallet rotate without an on-chain spend, but introduces an in-place mutation path that breaks the LINEAR-leaf invariant. Defer.
- **Cooldown-bypass via emergency multisig** (e.g., 4-of-5 unlocks immediately, 2-of-5 still respects cooldown). Modeled as a future BIP-68-via-OP_PUSHDATA-trick; out of scope for v0.2.
- **Block-mode nSequence.** v0.2 always emits time-mode (bit 22 set). Wallets that prefer block-counted cooldowns (e.g., for advanced merchants) need an extra config knob in the POLICY cell. Defer.

---

## 9. Test coverage summary

| Suite | New tests in W11 | Pre-W11 baseline | Total |
|---|---|---|---|
| `core/cell-engine` (Zig) | 6 (`vault_conformance.zig`) | 383 | **389/389 pass** |
| `runtime/node` (Zig) | 4 (`vault_round_trip.zig`) | 16 | **20/20 pass** |
| `apps/wallet-browser` (Bun) | 24 (`vault.spec.ts`) | 47 (tracked tests) | **71/71 pass** in tracked tests |
| `proofs/lean` | K14a, K14b, K14c (one new file) | — | **`lake build` succeeds** |
| `proofs/tla` | `VaultCooldownNsequence` (1 spec, 3 invariants, 2 liveness) | — | **TLC: 208 states, 0 errors** |

The pre-existing `apps/wallet-browser/test/wallet-ops.spec.ts` (untracked at the time of W11) has 8 failing tests that are unrelated to W11 and predate this work.
