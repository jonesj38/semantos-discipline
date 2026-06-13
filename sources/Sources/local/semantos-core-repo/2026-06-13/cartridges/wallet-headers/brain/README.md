---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/wallet-headers/brain/README.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.641841+00:00
---

# @semantos/wallet-browser — vanilla browser bundle (W5 + W7 + W9)

The Semantos wallet, running in any vanilla browser tab — no extension, no
install. A hidden iframe at `wallet.semantos.{tld}/bridge` hosts the
embedded cell-engine WASM, IndexedDB-backed tier blobs, and a popup at
`/popup` for UI prompts (PIN / passphrase / biometric WebAuthn). dApps
talk to the iframe over `postMessage` in BRC-100 wire format.

Implements wave W5 of `docs/design/WALLET-TIER-CUSTODY.md`. See §10.1 for
the topology.

## Build

```bash
cd cartridges/wallet-headers/brain
bun install               # @noble/hashes, @noble/secp256k1, fake-indexeddb
bun run build             # → zig build embedded WASM, then bundle TS
```

`bun run build` does four things in sequence:

1. `cd ../../core/cell-engine && zig build -Dembedded=true` — builds the
   29KB embedded-profile cell-engine WASM (no BSVZ; host externs), then
   copies it as both `cell-engine-embedded.wasm` and the byte-identical
   operator alias `wallet-engine.wasm`.
2. `bun build src/bridge.ts` — bundles the iframe entry point.
3. `bun build src/popup.ts` — bundles the popup entry point.
4. `scripts/copy-html.ts` — verifies the hand-authored HTML shells exist.

Output:

```
dist/
├── cell-engine-embedded.wasm   ~33 KB raw / ~12 KB gz
├── wallet-engine.wasm          byte-identical alias for BRAIN/operator config
├── index.html                  ~1 KB   (the bridge iframe shell)
├── signup.html                 redirects to popup.html?intent=plexus-signup
├── popup.html                  ~3 KB   (the popup UI)
├── wallet-bridge.js            ~33 KB raw / ~13 KB gz  (host + bridge + brc100 + storage)
└── wallet-popup.js             ~2 KB   (popup PIN/biometric handler)
```

Total gzipped: ~40 KB with the wallet-engine alias. Budget per design Q4 is
150–200 KB; we're well under.

## Test

```bash
bun test                  # wallet-browser tests across host, brc100, plexus, dispatcher,
                          # wallet-ops, popup-flow, bundle-size suites
```

The bundle-size test asserts the gzipped sum of `dist/` is under 200 KB.
It skips cleanly on a fresh checkout where `dist/` hasn't been built yet.

## Run locally over HTTP

The bundle is fully self-contained — no CDN or hosted-resource dependency — but
modern Chrome and Safari block cross-file ES module loads from `file://`.
Serve `dist/` over loopback HTTP instead:

```bash
bun run build
cd dist
python3 -m http.server 8787
```

Then open:

- `http://127.0.0.1:8787/index.html` — bridge iframe shell.
- `http://127.0.0.1:8787/popup.html` — wallet popup UI.
- `http://127.0.0.1:8787/signup.html` — first-run signup redirect.

The signup page redirects to `popup.html?intent=plexus-signup`. If no wallet
exists, the popup collects email, three recovery challenges, Tier-1 PIN, and
optional higher-tier factors, then creates the local recovery envelope and lands
on Status. Plexus enrollment is an explicit opt-in CTA and stays disabled until
a real operator is configured.

For a real dApp integration, the iframe is hosted at
`wallet.semantos.{tld}/bridge` and the dApp embeds it with:

```html
<iframe
  src="https://wallet.semantos.{tld}/bridge"
  style="display:none"
  allow="publickey-credentials-get *"
></iframe>
```

Then the dApp opens a `MessageChannel`, sends `{ type: 'handshake', port: portB }`
to the iframe, and from then on every BRC-100 envelope flows through the
channel.

## dApp integration (sketch)

```ts
const iframe = document.getElementById('semantos-wallet') as HTMLIFrameElement;
const { port1: dappPort, port2: walletPort } = new MessageChannel();

dappPort.onmessage = (e) => console.log('wallet says:', e.data);

iframe.contentWindow!.postMessage(
  { type: 'handshake', port: walletPort },
  'https://wallet.semantos.{tld}',
  [walletPort]
);

// Build a BRC-100 envelope and ask for a public key.
const envelope = buildBrc100Envelope(/* ... */);
dappPort.postMessage({ id: '1', type: 'rpc', envelope });
```

The full BRC-100 RPC catalog landed in W9 — see "BRC-100 method coverage"
below. The bridge accepts envelopes via the MessageChannel, runs
`dispatcher.dispatch`, and replies with an outbound BRC-100 envelope
signed by the wallet's identity key.

## BRC-100 method coverage

| Method            | Status         | Notes                                                                              |
|-------------------|----------------|------------------------------------------------------------------------------------|
| `getPublicKey`    | implemented    | identity key by default; allocates a fresh BRC-42 next-index when (protocolID, counterparty) supplied |
| `createSignature` | implemented    | signs a 32-byte digest at the tier inferred from `amountSats`; Tier-1+ goes through the popup factor prompt |
| `verifySignature` | implemented    | DER signature, lowS-tolerant — pure crypto, no state                                |
| `signMessage`     | implemented    | sha256(message) then sign with identity key                                         |
| `verifyMessage`   | implemented    | sha256(message) then verify against caller-supplied pubkey                          |
| `getNetwork`      | implemented    | configured at bridge boot (defaults to "main")                                      |
| `getVersion`      | implemented    | wallet bundle version (`0.1.0`)                                                     |
| `createAction`    | **501**         | not implemented in v0.1 — needs the engine's tx context (W11 + tx-builder workstream). Returns 501 with `suggestion: "use createSignature with a sighash-preimage digest"`. |

Tier-0 safety: the unencumbered hot-key exposure cap is `1_000_000` sats.
`getStatus()` reports `tier0PlaintextExposure`, and `planTier0Sweep()`
returns the deterministic outpoint plan the tx-builder should sweep upward
before ordinary hot-key operation continues.

Per-method handlers live in `src/dispatcher.ts` and cite §n.n of
`docs/design/WALLET-TIER-CUSTODY.md` next to non-trivial decisions. The
method-coverage table above is generated from `METHOD_COVERAGE` in that
file — keep them in sync.

## First-time-user walkthrough (W9)

```
1. Open the wallet popup           — wallet.semantos.{tld}/popup
2. "Create wallet" form appears    — popup-create.ts (no IndexedDB record yet)
3. Enter email, 3 challenges,      — runCreateFlow:
    Tier-1 PIN, optional factors     • generates 64-byte root seed locally
                                     • derives identity + Tier-N base keys (HMAC-SHA256)
                                     • self-issues BRC-52 cert
                                     • builds encrypted recovery envelope
                                     • AES-GCM-encrypts each base cell into IndexedDB
                                     • writes initial POLICY cell (identity-signed)
4. Backup warning shown            — user keeps a local recovery-envelope backup
5. Status panel becomes default    — popup-status.ts:
                                     • identity key (truncated)
                                     • per-tier ceilings + factor kinds
                                     • last Tier-3 spend (none yet)
                                     • hot-budget remaining (0 sats initially)
                                     • recovery banner: "RECOVERY NOT CONFIGURED"
6. User signs a Tier-0             — popup-send.ts: amount < 1M sats → no prompt;
    authorization (e.g. 42 sats)      OP_SIGN-equivalent runs in-process; UI clearly
                                     reports that tx construction/broadcast are not
                                     available in this browser build yet.
7. Status panel refreshes          — formatStatus produces the new label set
8. Click "Enroll in recovery"      — popup-plexus.ts (W7, explicit opt-in):
                                     • if no operator is configured, UI says so
                                       and disables Enroll/Recover controls
                                     • otherwise mirrors cached envelope
                                     • OTP loop against the configured Plexus
                                       operator (or MockPlexusOperator in tests)
                                     • on success: setRecoveryStatus(ENROLLED)
9. Recovery banner clears          — banner now reads "Recovery enrolled — managed
                                     by plexus-keys.com"
```

The popup hosts six logical screens behind one HTML shell:

| `data-screen` | Source             | Purpose                                  |
|---------------|--------------------|------------------------------------------|
| `create`      | popup-create.ts    | first-time wallet creation (§7.6)        |
| `status`      | popup-status.ts    | wallet status panel — default landing screen when a wallet exists |
| `send`        | popup-send.ts      | send/receive form (§7.1–7.4)             |
| `policy`      | popup-policy.ts    | per-tier ceilings, factor kinds, Tier-3 cooldown editor (§6.3) |
| `plexus-enroll`  | popup-plexus.ts | Plexus enrollment dialog (W7, §7.7)      |
| `plexus-recover` | popup-plexus.ts | Plexus recovery dialog (W7, §7.8)        |
| `factor`      | popup.ts           | per-tier unlock prompt — PIN / passphrase / WebAuthn |

The popup router (`popup.ts:pickInitialScreen`) chooses between `create`
(no wallet on disk) and `status` (wallet exists) on load; from there
`data-goto="<screen>"` buttons navigate.

## Architecture

```
src/
├── der.ts            Minimal ECDSA DER encode/decode (noble v2 dropped this).
├── storage.ts        IndexedDB-backed slot/state/kv stores. Mirrors the
│                       LocalSlotStore + LocalStateStore vtables in
│                       core/cell-engine/src/{slot_store,derivation_state}.zig.
├── host.ts           Every WASM extern declared in core/cell-engine/src/host.zig:
│                       sha256/hash160/hash256/ripemd160/sha1   ← @noble/hashes
│                       checksig/checkmultisig/sign             ← @noble/secp256k1
│                       derive_leaf                             ← @noble/secp256k1 (BRC-42)
│                       state_next_index                        ← storage.ts atomic txn
│                       unlock_tier/persist_cell/load_cell      ← WebCrypto AES-GCM
│                       get_blocktime/get_sequence/log
│                       call_by_name (registry placeholder for v0.1)
│                       fetch_cell (in-memory octave store)
├── brc100.ts         Envelope parser/builder + signature verification
│                       per WALLET-TIER-CUSTODY.md §8.2.
├── bridge.ts         Iframe entry: boots WASM, listens for postMessage,
│                       wires up MessageChannel, dispatches BRC-100 RPCs.
├── popup.ts          Popup entry: PIN/passphrase/WebAuthn factor handlers,
│                       posts results back to opener.
├── popup-plexus.ts   Popup UI extensions for the Plexus enroll/recover
│                       dialogs + recovery banner.
├── popup-create.ts   W9 first-time wallet creation screen.
├── popup-status.ts   W9 wallet status panel (default landing screen).
├── popup-send.ts     W9 send/receive form.
├── popup-policy.ts   W9 policy editor.
├── wallet-ops.ts     W9 high-level wallet ops (createWallet, signSpend,
│                       updatePolicy, getStatus, …) — shared by the
│                       dispatcher and the popup screens.
├── dispatcher.ts     W9 BRC-100 method dispatcher — see "BRC-100 method
│                       coverage" above.
└── plexus/
    ├── envelope.ts   Builds + signs the dispatch envelope per design §8.2.
    │                   Enforces invariants 1-5 before returning. AES-256-GCM
    │                   encryption of the recovery seed under a PBKDF2-100k
    │                   KEK derived from the user's challenge answers.
    ├── operator.ts   PlexusOperator interface, HttpPlexusOperator (the
    │                   ONLY fetch caller in the bundle), MockPlexusOperator
    │                   (in-process simulator for tests).
    ├── dispatch.ts   enroll() and recover() — drive the OTP loop, post the
    │                   envelope, decrypt the seed locally on recovery.
    │                   Failure modes are explicit Result values.
    └── index.ts      Public API barrel.
```

## Why @noble (not bsvz-min)

The W5 spec gives both as options. We picked @noble because:

- Smaller surface (the entire wallet-bridge.js is 13 KB gz vs an estimated
  80–120 KB for trimmed bsvz WASM per design Q4).
- Pure JS — no separate WASM module to load, instantiate, or hash-pin.
- @noble is well-audited (multiple security audits on record) and
  battle-tested in BRC-42 / BRC-100 reference implementations.

If we ever need a side-channel-resistant signing path, we can swap in a
trimmed bsvz-min WASM behind the same `host_sign` extern without
disturbing the rest of the bundle.

## Async ↔ sync bridging

The WASM ABI is fully synchronous, but IndexedDB and `crypto.subtle.*`
are async. `host.ts` resolves this by making the bridge orchestrator
*prime* every async resource (slot envelopes, BRC-42 next-indices,
per-tier KEKs) into an in-memory cache **before** the engine call.
After the engine returns, the bridge flushes any dirty slots back to
IndexedDB asynchronously. Sequence:

```
1. dispatchRequest():
   a. beginRequest()                    // create empty cache
   b. await prime(host)                 // caller stages all needed inputs
   c. wasm.exports.entry(...)           // engine runs, hits sync host externs
   d. await flushRequest()              // dirty slots → IndexedDB
   e. endRequest()                      // drop cache
```

This mirrors the pre-allocation pattern used in
`derivation_conformance.zig` / `storage_conformance.zig` — the conformance
tests in the full Zig build install state stores up front, run the engine
synchronously, and assert the final state. Same shape, different backing.

## File layout in production

```
https://wallet.semantos.{tld}/
├── bridge          → dist/index.html + wallet-bridge.js + cell-engine-embedded.wasm
└── popup           → dist/popup.html + wallet-popup.js
```

Both are served from the same origin so postMessage between them is
same-origin. Caddyfile snippet (W6 finalizes this):

```
wallet.semantos.{tld} {
    handle /bridge* {
        rewrite * /bridge/index.html
        file_server { root ./dist }
    }
    handle /popup* {
        rewrite * /popup/popup.html
        file_server { root ./dist }
    }
}
```

## Recovery enrollment (W7)

The wallet's Plexus dispatch module (`src/plexus/`) lets users opt into a
paid third-party recovery service. Per design §G4 / §7.7, this is **strictly
opt-in**: the wallet works fully without it. Enrollment ships an envelope
(see `src/plexus/envelope.ts`) containing the user's identity public key,
hashed challenge answers, an AES-GCM-encrypted recovery seed, and per-tier
derivation metadata. **No private key, mnemonic, or plaintext challenge
answer ever leaves the device.**

### Configuring a Plexus operator at build time

Production wallets pin a single operator at build time. Self-hosters point
at their own deployment. The wiring lives in your bundle's bootstrap
(typically `bridge.ts`):

```ts
import { HttpPlexusOperator } from './plexus';

const PLEXUS = new HttpPlexusOperator({
  baseUrl: 'https://plexus-keys.com',
  displayDomain: 'plexus-keys.com',
  // Optional defense-in-depth above WebPKI — the operator's TLS-cert
  // SHA-256 fingerprint, recorded at build time. The browser fetch path
  // does not currently enforce this (no SubresourceIntegrity for fetch),
  // but the value is shown to the user in the popup chrome so they can
  // notice rotation drift.
  pinnedCertFingerprintSha256: '<64 hex chars>',
});
```

For development and tests, swap in `MockPlexusOperator`:

```ts
import { MockPlexusOperator } from './plexus';
const PLEXUS = new MockPlexusOperator({ displayDomain: 'mock.plexus-keys.test' });
```

### Boundary discipline (design §8.1)

`src/plexus/dispatch.ts` is the **only** module in the bundle that calls
`fetch`. Every other code path is network-offline-safe — first-time creation
(§7.6), per-tier signing, key derivation, IndexedDB persistence, and the
postMessage RPC surface do not call remote services. Serve the bundle over
loopback HTTP for local testing because browsers block module loading from
`file://`. If you grep the bundle for `fetch(` outside `src/plexus/`, it's a
regression.

### Failure modes (design §7.7)

The dispatcher returns explicit `Result<T, E>` values for every distinct
UI state — no thrown exceptions for normal flows. The popup-plexus.ts
`formatEnrollError` / `formatRecoverError` helpers map each to a
human-readable string:

| Error                | UX                                          |
|----------------------|---------------------------------------------|
| `INVARIANT_FAILED`   | "Envelope invariant N failed". Refuses to dispatch — bug in wallet code. |
| `NETWORK_FAILURE`    | Caches the envelope locally; surfaces "retry enrollment" affordance. |
| `RATE_LIMITED`       | Operator quota tripped. Wait, retry. |
| `OTP_EXPIRED`        | 10-minute window elapsed. Restart. |
| `OTP_LOCKED`         | 5 wrong attempts. Lockout. |
| `OTP_WRONG`          | "N attempts remaining". |
| `OTP_CANCELLED`      | User dismissed the OTP prompt. |
| `CHALLENGE_FAILED`   | Recovery — answers don't match stored hashes. No seed leaked. |
| `DECRYPT_FAILED`     | Local decrypt failed (impossible in practice given §8.2 inv 3). |
| `OPERATOR_REJECTED`  | Operator returned an unexpected status. Surfaced verbatim. |

### UX prose

The popup chrome renders one of three banner states (per `bannerText` in
`src/popup-plexus.ts`):

- `RECOVERY NOT CONFIGURED — if you lose this device, your keys are gone. Enroll in recovery for $X / year.`
  with an "Enroll in recovery" CTA button.
- If no Plexus operator is configured, the Enroll/Recover screens render
  `Plexus recovery enrollment is not available in this build yet...` and disable
  the forms instead of failing silently.
- `Recovery enrolled — managed by plexus-keys.com` (after enrollment).
- `Recovery enrollment expired — managed by plexus-keys.com. Renew or your envelope may be archived.` (subscription lapse, design §11 Q8).

The first-run signup page collects email + three challenge questions before
wallet creation, so the recovery envelope is always created locally. Plexus
enrollment mirrors that cached encrypted envelope via `enrollCachedEnvelope`;
it does not need the seed or plaintext answers. Signup lands on Status after
creation; enrollment is explicit opt-in. The standalone "Enroll in recovery"
dialog still supports the older rebuild path for tests and operator tooling. The
"Recover existing identity" dialog collects email, OTP, then the original
challenge answers — all hashed locally before being sent.

### Tests

`test/plexus-envelope.spec.ts` covers each §8.2 invariant; `test/plexus-dispatch.spec.ts`
drives the full enroll/recover flows against `MockPlexusOperator` (no real
network calls). All sensitive intermediates are wiped from memory after
each call returns, asserted where feasible.

### What this module is NOT

- **Not** the Plexus Core Library (Plexus Tech Reqs §2). That's the
  recovery substrate, lives at the operator, and is out of scope for the
  wallet bundle. We only speak the wire protocol.
- **Not** federated-mesh state sync (design §3.5.2 — v0.3). That replaces
  Plexus with the user's own Semantos sovereign nodes and lands later.
- **Not** auto-enrolling. Per design §G4, enrollment is always opt-in.

## What this is NOT

- **Not** a transaction builder. `createAction` returns 501 — the popup can
  sign a local authorization digest, then tells the user that transaction
  construction and broadcast are not available in this browser build yet. Full
  tx-builder integration lands with W11.
- **Not** the sovereign-node target (W6). That reuses the same WASM but
  swaps IndexedDB for lmdb and hosts a WSS BRC-100 endpoint.

## Cross-references

- `docs/design/WALLET-TIER-CUSTODY.md` §10.1 (browser bundle topology),
  §8.2 (BRC-100 envelope), §6.1 (cell layout), §6.2 (slot envelope), §11 Q4
  (bundle size budget).
- `core/cell-engine/src/host.zig` — every extern this bundle backs.
- `core/cell-engine/src/slot_store.zig` — the vtable we mirror in IndexedDB.
- `core/cell-engine/src/derivation_state.zig` — same.
- `core/cell-engine/bindings/host-functions.ts` — the @bsv/sdk-backed
  TS host that this @noble-backed host replaces for the embedded path.
