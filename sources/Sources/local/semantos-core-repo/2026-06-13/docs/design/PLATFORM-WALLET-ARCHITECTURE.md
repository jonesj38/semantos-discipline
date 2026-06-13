---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/design/PLATFORM-WALLET-ARCHITECTURE.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.726662+00:00
---

# Semantos Platform + Wallet Architecture

> **Status:** Design decision record — converged across multiple sessions.
> Cross-reference with: `WALLET-ACTIVE-USE-ROADMAP.md`, `WALLET-SHELL-VPS-SUBSTRATE.md`,
> `SEMANTIC-SHELL-ARCHITECTURE.md`, `ODDJOBZ-EXTENSION-PLAN.md`.

---

## 1. The problem this document solves

Three surfaces need signing capability from the same wallet identity:

1. **Browser** — the operator's admin panel served by `brain serve`
2. **Mobile** — oddjobz Flutter app (+ future jam-room, etc.)
3. **Server-side** — `brain` itself when it auto-emits anchor txs on job transitions

Duplicating the wallet in each surface creates split identity, maintenance debt, and no
clear trust boundary. The goal is a single wallet runtime per operator identity, called
as a service by all other surfaces.

---

## 2. The three layers

```
┌──────────────────────────────────────────────────────────────────────────┐
│  Experience layer  (domain + render only)                                │
│  oddjobz_experience · jam_experience · future apps                       │
│  Registers grammar extensions + lexicons with the shell.                 │
│  Handles dispatched intents. No wallet or NL pipeline knowledge.         │
├──────────────────────────────────────────────────────────────────────────┤
│  Shell / host layer  (one per operator identity)                         │
│  Browser: brain serve  ·  Mobile: semantos-shell Flutter app             │
│  Boots identity · holds wallet · owns conversation engine                │
│  Runs STT → intent extraction → wallet dispatch                          │
│  Exposes WalletService + IntentDispatch to experiences                   │
├──────────────────────────────────────────────────────────────────────────┤
│  Platform package  (interfaces + crypto primitives)                      │
│  core/identity-ports · core/protocol-types · semantos_ffi (Flutter)     │
│  CellSigner · WalletService · IntentGrammar · Lexicon interfaces         │
└──────────────────────────────────────────────────────────────────────────┘
```

Experiences import from the platform package only. They never import the shell or the
wallet implementation directly. The shell wires the concrete impl at boot and owns the
full conversation pipeline — experiences extend it, they don't own it.

---

## 3. Wallet deployment model: brain as sidecar

### 3.1 One brain process per operator instance

Each oddjobz operator is one `brain serve` process. The wallet state (keys, UTXOs,
cell anchors, derivation indices) lives inside that process's LMDB store, isolated by
`op_pkh` prefix (W7.1). The operator's mobile app and browser admin panel both talk
to their own brain instance — there is no shared wallet server.

```
baremetal box (203.18.30.243 today)
├── brain serve oddjobtodd.info       :8080  → operator A wallet + site
├── brain serve acme-plumbing.com.au  :8081  → operator B wallet + site
└── brain serve ...                   :808N  → operator N wallet + site

caddy (TLS termination)
├── oddjobtodd.info   → localhost:8080
├── acme-plumbing.com → localhost:8081
```

Each instance is managed by `semantos-shell@<domain>.service` (the `@` systemd
template at `deploy/systemd/semantos-shell@.service`). The provisioner
(`brain provision-tenant`) writes the per-tenant drop-in and allocates the port.

### 3.2 Wallet API surface on brain

The wallet is not a UI feature. It is an internal RPC target. Brain exposes:

| Endpoint | Protocol | Auth | Purpose |
|---|---|---|---|
| `GET /api/v1/wallet` | WebSocket (BRC-100) | bearer | Mobile app wallet connection |
| `POST /api/v1/wallet-op` | JSON REST | bearer (localhost) | Internal oddjobz intent pipeline |
| `POST /api/v1/repl` | JSON | bearer | Operator REPL (admin only) |

`/api/v1/wallet-op` is the **new endpoint** — it replaces the chat tab that was in the
browser wallet. The oddjobz conversation engine calls it directly after intent extraction.
It is localhost-only (no external exposure); Caddy does not proxy it.

### 3.3 wallet-op request shape

```json
{
  "action": "pay",
  "outputs": [
    { "lockScript": "<hex>", "satoshis": 1000 }
  ],
  "description": "Job #42 milestone payment to Alice"
}
```

```json
{
  "action": "anchorTransition",
  "typeHash": "<hex>",
  "anchorIndex": 0,
  "newStateHash": "<hex>",
  "description": "LINEAR job #42 → completed"
}
```

```json
{
  "action": "createAction",
  "outputs": [...],
  "inputs": [...],
  "description": "arbitrary spend"
}
```

Response always includes `{ txid, beef }` on success or `{ error }` on failure. The
caller (oddjobz) updates its own job state after receiving a successful `txid`.

**Key separation:** the wallet receives *already-resolved* outputs (lock scripts + sats).
Recipient resolution (name → pubkey → lock script) is the oddjobz intent pipeline's job.
The wallet never holds a contact book.

---

## 4. Conversation engine ownership

### 4.1 The pipeline lives in the shell, not in experiences

`whisper_cpp` and `llama_cpp` are `platforms/flutter/` FFI plugins — platform-level
dependencies, not oddjobz dependencies. `WALLET-VOICE-SHELL-GRAMMAR.md` defines a
shell-level grammar system. The conversation engine is a shell primitive; experiences
are consumers of it.

```
semantos-shell
  conversation engine (shell-owned)
  ├── whisper_cpp          ← STT — shell FFI plugin
  ├── llama_cpp            ← grammar-constrained intent extraction — shell FFI plugin
  ├── GrammarRegistry      ← experiences register here at boot
  └── LexiconRegistry      ← domain vocabulary per active experience

oddjobz_experience (registers at boot)
  ├── IntentGrammar:  pay_milestone · transition_job · assign_worker · request_quote
  └── Lexicon:        job · milestone · tradie · quote · invoice · site · variation

jam_experience (registers at boot)
  ├── IntentGrammar:  start_session · invite_collaborator · commit_stem · pay_split
  └── Lexicon:        stem · loop · chord · session · collaborator · beat · key
```

### 4.2 Intent pipeline → wallet call chain

The shell runs STT → extraction → dispatch. The experience handles the dispatched
structured intent and calls the wallet through the shell's WalletService.

```
user utterance / text
  → shell conversation engine
      → whisper_cpp (STT, mobile) | text input (browser)
      → active grammar context: oddjobz IntentGrammar + Lexicon
      → llama_cpp grammar-constrained extraction
      → structured intent: PayMilestone { recipient_pubkey, amount_sats, job_id }
      → dispatched to oddjobz_experience.onIntent(PayMilestone)
          → contact resolution: pubkey → lock script (oddjobz contact-book)
          → shell.wallet.pay(outputs)
              → POST /api/v1/wallet-op { action:"pay", outputs:[{lockScript, satoshis}] }
                  → brain: build tx, sign, broadcast via ARC
                  → return { txid, beef }
          → oddjobz: update job state, emit receipt to user
```

For LINEAR job transitions (triggered by state machine, not necessarily by voice):

```
oddjobz job state machine
  → transition: job #42 → COMPLETED
  → shell.wallet.anchorTransition(typeHash, anchorIndex, newStateHash)
      → POST /api/v1/wallet-op { action:"anchorTransition", typeHash, anchorIndex }
          → brain: spend anchor UTXO, broadcast
          → return { txid }
  → oddjobz: persist COMPLETED with on-chain proof txid
```

The anchor tx is the on-chain act of consuming the LINEAR cell — the primary evidence
of the transition, not a side effect. Brain holds the anchor UTXO in its output store
(`basket='cell-anchors'`) and re-derives the spending key from `typeHash` at transition time.

### 4.3 Key separation of concerns

| What | Who owns it |
|---|---|
| STT (audio → text) | Shell (`whisper_cpp`) |
| Intent grammar definition | Experience (registers with shell) |
| Domain lexicon | Experience (registers with shell) |
| Grammar-constrained extraction | Shell (`llama_cpp` + registered grammar) |
| Intent dispatch | Shell → experience handler |
| Contact resolution (name → pubkey) | Experience (its own contact-book) |
| Lock script derivation (pubkey → script) | Experience (calls shell's wallet) |
| Tx construction + signing + broadcast | Shell wallet → brain `/wallet-op` |
| Job state update after tx confirmation | Experience |

The wallet receives already-resolved outputs (lock scripts + sats). It never holds
a contact book and never does name resolution.

---

## 5. Mobile architecture: semantos-shell Flutter app

### 5.1 Current state

Two separate Flutter apps (`oddjobz-mobile`, `jam-room`) each carry their own
`semantos_ffi` dependency and their own pairing flow. Both need wallet access.
The apps share no code path for identity or signing.

### 5.2 Target state

One installed binary — **semantos-shell** (the Flutter app). It boots identity once,
then routes to experience packages:

```
apps/semantos/          ← THE Flutter app (single binary)
  lib/
    main.dart                 ← boots SemantosPlatform, handles auth, routes
    platform/
      wallet_service.dart     ← wraps semantos_ffi wallet ops
      signer.dart             ← CellSigner impl
      intent_client.dart      ← HTTP client to /api/v1/wallet-op on brain

packages/
  oddjobz_experience/         ← Flutter package (not a standalone app)
    lib/
      oddjobz_experience.dart ← exports OddjobzScreen widget
      (imports semantos_core Dart package only)

  jam_experience/             ← same pattern
    lib/
      jam_experience.dart
```

The shell's `main.dart`:

```dart
runApp(
  SemantosPlatform(
    signer: FfiCellSigner(),
    walletService: FfiWalletService(),      // FFI or brain HTTP, resolved at boot
    conversationEngine: ConversationEngine( // shell owns STT + extraction
      stt: WhisperCppStt(),
      llm: LlamaCppLlm(),
      grammars: [                           // experiences register here
        OddjobzIntentGrammar(),
        JamIntentGrammar(),
      ],
    ),
    child: SemantosRouter(),                // /oddjobz → OddjobzScreen, /jam → JamScreen
  )
);
```

Experiences receive dispatched intents and access the wallet via context:

```dart
class OddjobzIntentGrammar extends IntentGrammar {
  @override
  Future<bool> onIntent(StructuredIntent intent, IntentContext ctx) async {
    if (intent is PayMilestone) {
      final lock = resolveLockScript(intent.recipientPubkey, intent.edgeIndex);
      await ctx.wallet.pay([Output(lock, intent.amountSats)]);
      return true;
    }
    return false;
  }
}
```

### 5.3 FFI vs brain connection on mobile

On mobile the wallet can run in two modes:

| Mode | How | When |
|---|---|---|
| **Connected** | Mobile app connects to operator's `brain` via BRC-100 WSS (`/api/v1/wallet`) | Operator's own device, always-on brain |
| **Embedded FFI** | `semantos_ffi` runs wallet natively in-process | Offline / standalone user wallet |

`semantos_ffi` already provides the C ABI bridge for cell read/write, capability
verification, and anchor batching. The wallet Zig core (`core/cell-engine`) builds
to WASM for browser and to a native dylib for FFI. Same source, two targets.

The `WalletService` interface in the `semantos_core` Dart package abstracts over both.
The shell picks the concrete impl at boot based on whether a `brain` connection is
available.

---

## 6. What exists today

| Component | Status | Location |
|---|---|---|
| `brain` binary with `headers serve`, `bearer`, `device`, `wallet` WASM endpoint | ✓ Live | `runtime/semantos-brain/` |
| BRC-100 WSS wallet endpoint (`/api/v1/wallet`) | ✓ Done | `brain serve` |
| Browser wallet WASM bundle (key ops, UTXO store, BEEF, cell anchors) | ✓ Done | `apps/wallet-browser/` |
| Cell anchor UTXO tracking + recovery (typeHash, basket='cell-anchors') | ✓ Done | `src/cell-anchor.ts`, `src/output-store.ts` |
| `semantos_ffi` Dart package stub | ✓ Stub | `platforms/flutter/semantos_ffi/` |
| `llama_cpp` + `whisper_cpp` Flutter FFI plugins | ✓ Done (iOS disabled) | `platforms/flutter/` |
| `oddjobz-mobile` Flutter app wired to `semantos_ffi` | ✓ Partial | `apps/oddjobz-mobile/` |
| `semantos-shell@.service` multi-tenant systemd template | ✓ Done | `deploy/systemd/` |
| `brain provision-tenant` CLI verb | ✓ Done | `runtime/semantos-brain/src/cli.zig` |
| Chat tab in browser wallet (wrong layer) | ✗ Removed | — |

---

## 7. Gaps to close

### P0 — wallet-op endpoint (unlocks intent pipeline)

Add `POST /api/v1/wallet-op` to `brain serve`. Receives structured action JSON,
dispatches to the in-process wallet, returns `{ txid, beef }`.

Scope: `pay`, `anchorTransition`, `createAction`. Bearer-gated. Localhost binding only.

### P1 — semantos_core Dart interface package

Create `platforms/flutter/semantos_core/` with wallet, signer, and conversation
engine interfaces:

```dart
// Wallet ops — impl: semantos_ffi or brain HTTP
abstract class WalletService {
  Future<PayResult> pay(List<Output> outputs, {String? description});
  Future<AnchorResult> anchorTransition(Uint8List typeHash, int anchorIndex, Uint8List newStateHash);
  Future<String> identityPubkeyHex();
}

abstract class CellSigner {
  Future<Uint8List> sign(Uint8List cellBytes);
}

// Conversation engine extension point — impl: each experience package
abstract class IntentGrammar {
  /// BNF/GBNF grammar fragment for llama_cpp grammar-constrained generation.
  String get grammarFragment;

  /// Vocabulary extensions loaded into the LexiconRegistry.
  List<LexiconEntry> get lexicon;

  /// Handle a dispatched structured intent. Return true if handled.
  Future<bool> onIntent(StructuredIntent intent, IntentContext ctx);
}
```

No implementation here — just the interfaces. Experiences implement `IntentGrammar`;
the shell owns the `ConversationEngine` that composes registered grammars.

### P2 — semantos_ffi wallet implementation

Wire the actual wallet ops through the existing C ABI in `semantos_ffi`. The FFI
stub already has the bridge skeleton; needs the Zig dylib build target and the Dart
binding layer for `pay`, `anchorTransition`, `identityPubkeyHex`.

Build target: `zig build -Dtarget=aarch64-macos-none` (iOS/macOS), `aarch64-linux-android` (Android).

### P3 — intent client (brain HTTP bridge for mobile)

`platforms/flutter/semantos_core/lib/brain_wallet_service.dart` — a `WalletService`
impl that calls `POST /api/v1/wallet-op` on the connected brain over HTTPS with
the operator's bearer token. Used when the mobile app is online and the operator
has a brain instance.

### P4 — semantos-shell Flutter app scaffold

New app at `apps/semantos/`. Boots identity, resolves `WalletService` impl
(FFI or brain HTTP), then routes to `oddjobz_experience` and `jam_experience` as
sub-routes. Replaces the two separate `main.dart` entry points.

This is the last step — P0–P3 can be built and tested against the existing separate
apps first.

---

## 8. Delivery order

```
P0  brain wallet-op endpoint          → unblocks oddjobz intent pipeline immediately
P1  semantos_core Dart interfaces     → unblocks mobile refactor
P2  semantos_ffi wallet impl          → embedded offline wallet on mobile
P3  brain HTTP WalletService client   → online wallet on mobile (simpler than P2)
P4  semantos-shell app + experience packages  → unified mobile binary
```

P3 is cheaper than P2 and delivers more immediate value (online operators with a
brain already running). Recommend P3 before P2 unless offline-first is a hard
requirement for the next milestone.

---

## 9. Naming conventions

| Term | Meaning |
|---|---|
| `brain` | The Semantos Brain binary (`runtime/semantos-brain/`). Runs `brain serve` per operator. |
| `wallet-op` | REST endpoint on brain for structured wallet actions called by the shell. |
| `semantos_ffi` | Flutter FFI package bridging to the Zig wallet/cell-engine dylib. |
| `semantos_core` | Dart interfaces-only package (to be created): WalletService, CellSigner, IntentGrammar. |
| `semantos-shell` | The unified Flutter app (to be created). Owns identity, conversation engine, routing. |
| `ConversationEngine` | Shell-owned pipeline: whisper_cpp STT → llama_cpp extraction → intent dispatch. |
| `IntentGrammar` | Interface experiences implement to register grammar + lexicon + intent handlers. |
| `GrammarRegistry` | Shell component that composes registered IntentGrammar fragments per active experience. |
| `oddjobz_experience` | The oddjobz Flutter package (extracted from `oddjobz-mobile`). Implements IntentGrammar. |
| `CellSigner` | Interface for signing cell bytes. Impl: FFI or remote. |
| `WalletService` | Interface for wallet ops (pay, anchor, query). Impl: FFI or brain HTTP. |
| `anchor tx` | The BSV transaction spending a LINEAR cell's anchor UTXO — the on-chain act of a job state transition. |
| `typeHash` | 32-byte cell type identifier. Determines anchor key domain via `anchorProtocolHash(typeHash)`. |
