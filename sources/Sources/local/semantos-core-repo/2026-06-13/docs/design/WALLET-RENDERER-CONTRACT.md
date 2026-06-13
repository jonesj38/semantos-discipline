---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/design/WALLET-RENDERER-CONTRACT.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.741866+00:00
---

# Wallet Renderer Contract

**Status:** decision locked 2026-05-30. Supersedes the implicit assumption in
PR-C11-4a/4b that wallet-headers would remain its own identity universe.

**References:**
- `docs/design/HELM-ME-SURFACE.md` — Me-sheet host for the wallet
- `docs/design/PLEXUS-ALIGNMENT.md` — gaps catalog (this doc resolves gap #4)
- `memory/pb_utxo_discovery_primitive.md` — PB = UTXO × G (counterparty-scoped derivation)
- `memory/mnca_anchor_onchain_mainnet.md` — proven on-chain anchor path the
  tier-0 vault re-uses for cell anchoring

## 1. Decision

The shell (Dart) owns **all** identity- and spending-relevant private keys.
`cartridges/wallet-headers` is reduced to a **renderer**: a UI that displays
balances, prompts for user actions, and forwards user intent back to Dart.
Wallet-headers does not generate seeds, derive keys, sign transactions, or
broadcast. Every byte of cryptographic material lives in Dart or below.

Why:

- **Single source of truth.** One key universe (the root identity cert plus
  its BRC-42 children) governs cells, anchors, spending, and federation. No
  parallel BIP39 seed exists "next to" the identity.
- **Recoverable.** The Plexus recovery envelope already wraps `cert_body`.
  Adding `derivationRules[]` + `highWater` to the envelope makes the entire
  spending tree recoverable from the secret questions, no extra backup
  channel required.
- **Composable.** Future wallet UIs (a thin native widget, a different
  webview, a CLI) all plug into the same Dart key store. Wallet-headers
  becomes one renderer among many, not the canonical one.
- **Substrate-clean.** Aligns with the existing posture: Dart shell owns
  the operator's keys; cartridges are presentation + workflow.

The cost: gutting the existing wallet-headers internals (seed generation,
local key derivation, signer code) and replacing them with bridge calls.
That is the scope of PRs C11-4d/4e (see §7).

## 2. The four-layer derivation tree

```
ROOT IDENTITY CERT      (BRC-52 self-cert, 16-byte cert_id)
        │  secret questions wrap cert_body  →  Plexus recovery envelope
        │
        ▼  BRC-42(rootPriv, "vault/0")
TIER-0 VAULT KEY        (deterministic; the wallet's "seed")
        │
        ├──▶ BRC-42(tier0, "spend/<context>/<n>")    per-utxo spending keys
        ├──▶ BRC-42(tier0, "peer/<cpPub>/<n>")       counterparty-scoped (PB=UTXO×G)
        ├──▶ BRC-42(tier0, "anchor/<purpose>/<n>")   cell-anchor keys (MNCA path)
        └──▶ BRC-42(tier0, "change/<n>")             change outputs
```

Every leaf is single-use. The recovery envelope stores **the recipe to
regenerate the tree**, not the leaves themselves.

`<context>` is a free-form label scoped per cartridge — e.g.
`oddjobz/payout`, `betterment/release`, `chess/stake`. Cartridges request
spending keys by context; the shell allocates the next free `n` and records
it in the rule's `highWater`.

`<cpPub>` is a counterparty's identifying pubkey. Per the PB = UTXO × G
primitive (memory note), counterparty-scoped derivations are the discovery
primitive — Bob can find Alice's payment to him by walking shared-point
addresses without on-chain index lookups. Out of scope for 4d/4e; the rule
schema reserves the path so we don't have to migrate later.

## 3. Bridge protocol

The shell and renderer communicate over a single `JavaScriptChannel` named
`SemantosWallet`. Wire format is JSON, one envelope per message:

```
{
  "id": "<uuid-v7>",        // correlation id; renderer echoes in replies
  "kind": "<message-kind>",
  "payload": { ... }
}
```

Messages are typed by `kind`. All Dart→JS messages have a matching JS→Dart
reply with the same `id`. Asynchronous notifications (no reply expected)
use `kind` suffixed with `.notify`.

### 3.1 Dart → renderer

| `kind`              | Purpose                                                          | Payload                                                                                |
| ------------------- | ---------------------------------------------------------------- | -------------------------------------------------------------------------------------- |
| `identity.set`      | Bind the renderer to the active identity. Suppresses onboarding. | `{ certIdHex, tier0Pub, displayName?, recoverable: bool }`                             |
| `balance.update`    | Push a new balance snapshot.                                     | `{ totalSats, perContext: { [ctx]: sats } }`                                           |
| `utxos.list`        | Push the current UTXO set for display.                           | `[{ txid, vout, value, recipeId, index, scriptHex }]`                                  |
| `tx.preview`        | Ask the renderer to display an unsigned tx for user confirm.     | `{ txHex, inputs: [...], outputs: [...], feeSats, summaryText }`                       |
| `tx.broadcast.done` | Notify the renderer a tx was broadcast.                          | `{ txid, status: "ok" \| "error", error? }`                                            |
| `error.show`        | Render an error banner.                                          | `{ message, detail? }`                                                                 |

### 3.2 Renderer → Dart

| `kind`               | Purpose                                                          | Payload                                                                                |
| -------------------- | ---------------------------------------------------------------- | -------------------------------------------------------------------------------------- |
| `ready`              | Renderer has finished booting; safe to send `identity.set`.      | `{ rendererVersion }`                                                                  |
| `tx.request`         | User wants to send. Dart builds + signs.                         | `{ recipientAddrOrPub, amountSats, contextLabel, memo? }`                              |
| `tx.confirm`         | User approved the previewed tx; Dart proceeds to broadcast.      | `{ previewId }`                                                                        |
| `tx.cancel`          | User dismissed the previewed tx.                                 | `{ previewId }`                                                                        |
| `address.request`    | User wants a receive address. Dart derives + records the recipe. | `{ contextLabel }`                                                                     |
| `derivation.request` | User wants to see a derivation chain (debug / power user).       | `{ recipeId, fromIndex, count }`                                                       |

The renderer never derives a key, never signs, never broadcasts. It
displays state and forwards user intent.

### 3.3 Sequence: send

```
JS  → Dart : tx.request { recipient, amount, context }
Dart       : select utxos, derive change key, build unsigned tx
Dart → JS  : tx.preview { txHex, inputs, outputs, feeSats }
JS         : show confirm sheet to user
JS  → Dart : tx.confirm { previewId } | tx.cancel { previewId }
Dart       : sign each input from the recorded recipes
Dart       : broadcast via ARC
Dart       : record output recipes in the recipe store, bump highWater
Dart → JS  : tx.broadcast.done { txid, status }
Dart → JS  : balance.update + utxos.list (refresh)
```

### 3.4 Sequence: receive

```
JS  → Dart : address.request { contextLabel }
Dart       : next n = recipeStore.highWater[contextLabel] + 1
Dart       : addr = BRC-42(tier0, "spend/<contextLabel>/<n>").address
Dart       : record empty UTXO row { recipeId, index: n, status: "watching" }
Dart       : bump highWater
Dart → JS  : reply { address, recipeId, index }
JS         : display address + QR
```

## 4. Renderer responsibilities

In scope:

- **Identity binding screen** — shown only if `identity.set` has not been
  received within N seconds of `ready`. Tells the user to open the Me sheet
  and set up their identity first.
- **Balance display** — totals and per-context breakdown from
  `balance.update`.
- **UTXO list** — diagnostic table from `utxos.list`. Read-only.
- **Send flow** — gather (recipient, amount, context), send `tx.request`,
  display the returned `tx.preview`, surface confirm/cancel.
- **Receive flow** — gather context label, send `address.request`, display
  the returned address + QR.
- **Error display** — render `error.show` payloads.

Out of scope:

- Generating any key material.
- Computing any signature.
- Computing any address from a private key.
- Talking to the network (ARC, brain, peers). All network IO is Dart-side.
- Persisting any private data. The renderer's `localStorage` and `IndexedDB`
  must not contain key material; UI state only.

## 5. Dart responsibilities

- **Cert custody.** `cert_body` in SecureStore at `me.cert_body.${certIdHex}`
  (per PLEXUS-ALIGNMENT §10.C). Wrapping for the Plexus envelope uses
  PBKDF2(100k) + AES-256-GCM, keys derived from the secret-question answers.
- **Tier-0 derivation.** `tier0 = BRC42(certPriv, "vault/0")`. Cached in
  memory for the wallet sheet's lifetime; never persisted unwrapped.
- **Recipe store.** Append-only log of derivation rules used. Each row:
  ```
  { recipeId, scope, label, contextLabel?, counterpartyPub?, highWater }
  ```
  Persisted in SecureStore at `me.recipes`.
- **UTXO store.** Mirror of the operator's spending tree. Each row:
  ```
  { txid, vout, value, scriptHex, recipeId, index, status }
  ```
  Persisted in SecureStore (or a separately-encrypted SQLite if size
  warrants) at `me.utxos`.
- **Tx builder + signer.** Uses `@bsv/sdk` via the existing
  `unified-wallet.ts` (C6a tick 4). Signs each input with the key derived
  from the input row's `(recipeId, index)`.
- **Broadcast.** ARC `/v1/tx` with BEEF v1 envelope, per the proven anchor
  path (memory `mnca_anchor_onchain_mainnet`).
- **Recovery scanner** (PR-C11-7 / 4e+). Walks recipes, regenerates keys up
  to each rule's `highWater`, optionally SPV-scans for stragglers.

## 6. Recovery envelope v2 schema

Extends the v1 envelope from PR-C11-3:

```
{
  "v": 2,
  "wrappedCertBody": "<base64>",         // PBKDF2(100k) + AES-256-GCM(cert_body)
  "wrappedKdfParams": { ... },           // salt, iter, alg

  "derivationRules": [
    {
      "id":            "vault/0",
      "scope":         "tier0",
      "highWater":     0                  // tier-0 is a single key, always index 0
    },
    {
      "id":            "vault/0/spend/oddjobz/payout",
      "scope":         "context",
      "contextLabel":  "oddjobz/payout",
      "highWater":     47
    },
    {
      "id":            "vault/0/peer/02ab...",
      "scope":         "counterparty",
      "counterpartyPub": "02ab...",
      "highWater":     3
    }
  ],

  "utxoManifestRef": null                  // optional; PR-C11-7
}
```

Rules are public — they describe how to derive, not what they derive. Only
`wrappedCertBody` is encrypted. This lets the envelope be stored anywhere
(brain cell, Plexus RaaS, paper QR) without leaking spending power.

`utxoManifestRef`, when present, points to an encrypted out-of-band store
holding the full UTXO list. Lets recovery skip the SPV walk on networks
where rescanning is expensive. Optional opt-in.

## 7. Re-sequenced PR plan

Replaces the earlier C11-4b through C11-7 plan:

| PR        | Status   | Scope                                                                                                          |
| --------- | -------- | -------------------------------------------------------------------------------------------------------------- |
| C11-4a    | merged   | Wallet row + webview transport (loopback HTTP origin + NSC + asset server)                                     |
| C11-4b    | _was_    | ~~SecureStore cert + BIP39 extraction + bridge~~ — split into 4c/4d/4e below                                   |
| **C11-4b** | **this PR** | This contract doc + alignment-doc gap #4 marked resolved + matrix axis annotations                            |
| C11-4c    | next     | Dart-side cert custody via SecureStore (`me.cert_body.${certIdHex}`) + tier-0 derivation + recipe store schema |
| C11-4d    | after 4c | Strip wallet-headers internals — remove seed gen, key derivation, signing, broadcast; expose renderer hooks    |
| C11-4e    | after 4d | Wire bridge per §3 — `identity.set` injection, `tx.request/preview/confirm` flow, `address.request` flow       |
| C11-5     | unchanged | Plexus RaaS opt-in (BRC-100 sig + 4-phase OTP/challenge/export/reconstruct) + `cap.recovery` BRC-108 gate      |
| C11-6     | unchanged | Brain-side `shell.identity.envelope` cell — schema v2 from §6                                                  |
| C11-7     | new      | UTXO store with derivation tags + recovery scanner (SPV-walk fallback)                                         |

## 8. What of wallet-headers survives the strip?

Keep:

- The visual layout of the panels (2-Hop, Key Rotation, Chess Stake) as the
  reference UI for what the new renderer eventually replicates.
- The `unified-wallet.ts` (C6a tick 4) BRC-100 adapter — it moves into Dart
  as the in-process signer.
- The wallet.html shell + styling — becomes the renderer entry point with
  the seed-generation flows removed.

Throw away:

- All code paths that call `BIP39.mnemonicToSeed`, `bip32.fromSeed`,
  `derivePrivateKey`, etc. — anywhere a private key is produced or used.
- The wallet's own localStorage seed cache.
- Direct ARC / brain HTTP calls from the JS side. Those move into Dart and
  the renderer asks for them via bridge messages.

## 9. Migration / coexistence

PR-C11-4a's loopback transport stays. The wallet sheet continues to host a
`webview_flutter` pointed at `http://127.0.0.1:<port>/wallet.html`. What
changes is what `wallet.html` *is*: PR-C11-4d swaps the bundled
wallet-headers payload for the renderer build.

Between 4a (merged) and 4e (renderer wired), the wallet sheet shows the
legacy onboarding. That is a known interim state, not a regression to be
fixed by hot-fixes — the fix is shipping 4c–4e.

The Recovery row in the Me sheet (PR-C11-3) keeps working unchanged through
this transition. Its secret questions already wrap `cert_body`; PR-C11-6
adds `derivationRules[]` to the wrapped payload without breaking the v1
unwrap path.
