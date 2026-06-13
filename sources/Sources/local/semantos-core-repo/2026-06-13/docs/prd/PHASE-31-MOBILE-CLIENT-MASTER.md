---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-31-MOBILE-CLIENT-MASTER.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.689021+00:00
---

# Phase 31: BSV Browser Mobile Client — Master PRD

**Duration**: 6 weeks (with 20% buffer: ~7.5 weeks)
**Prerequisites**: Phase 26G complete (node packaging, admin API on port 6443), Phase 30E complete (WASM target)
**Master document**: `PHASE-26-KERNEL-ISOLATION-MASTER.md`
**Branch prefix**: `phase-31-mobile-client`

---

## Context

The Semantos kernel runs on servers (VPS, Colo, bare metal) and is administered via the conversational shell. But the primary users — tradies, property managers, content creators, researchers — interact from their phones. Phase 31 integrates the Semantos kernel with the BSV Browser mobile application, creating a mobile thin client that connects to one or more Semantos nodes.

The BSV Browser (`bsv-blockchain/bsv-browser`) is a React Native + Expo application providing:

- **WebView substrate** for loading web applications
- **BRC-100 CWI provider** (`window.CWI`) — wallet interface for signing, encryption, certificate acquisition
- **Pluggable WAB** (Wallet Application Backend) — configurable via `selectedWabUrl` in WalletContext
- **BRC-68 certifier integration** — identity certificate management
- **Permission request queue** — modal approval flows for spending, protocol access, certificate disclosure, basket access
- **BLE peer-to-peer** — chunked Bluetooth transfers between devices
- **Biometric support** — via `expo-local-authentication`
- **Secure storage** — via `expo-secure-store` (Keychain on iOS, Keystore on Android)
- **i18n** — multi-language support via `i18next`
- **QR scanning** — via `react-native-vision-camera`

Phase 31 does NOT fork the BSV Browser. It builds a Semantos web application that runs inside the BSV Browser's WebView, plus a Plexus WAB service that replaces the default Babbage WAB, plus a node admin bridge that connects the mobile shell to remote Semantos nodes.

### Commercial Context

The $500 Semantos node product includes a mobile management experience:

1. **Tradie** buys a node licence, gets a Plexus cert, deploys node on VPS. Opens BSV Browser on their phone, connects to their node. Types "show my jobs this week" and manages their business from the job site.
2. **Property manager** runs a node with the property extension. Opens BSV Browser on their tablet, switches between their property node and a shared node with their maintenance contractor. Reviews dispatch envelopes, approves quotes, tracks inspections.
3. **Researcher** (Alyssa's medical imaging use case) authenticates via institutional Plexus cert on their tablet, queries the federated imaging overlay for tuberculosis CT scans, capability tokens gate access, micropayments flow via CWI for image licensing.
4. **Content creator** manages their publishing node, reviews analytics, publishes content — all from the BSV Browser on their phone.

The mobile client is the face of the product. The kernel is the brain. The BSV Browser is the chassis.

### Architecture Overview

```
┌──────────────────────────────────────────────────────────────┐
│                    BSV BROWSER (React Native)                 │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────┐   │
│  │ Plexus WAB   │  │ Permission   │  │ Biometric Auth   │   │
│  │ (replaces    │  │ Modals       │  │ (expo-local-auth)│   │
│  │  Babbage)    │  │ (spending,   │  │ Face ID/Touch ID │   │
│  │              │  │  certs, etc) │  │                  │   │
│  └──────┬───────┘  └──────────────┘  └──────────────────┘   │
│         │                                                     │
│  ┌──────┴────────────────────────────────────────────────┐   │
│  │              WebView (Semantos Shell App)               │   │
│  │  ┌─────────────┐  ┌─────────────┐  ┌──────────────┐  │   │
│  │  │ Chat Shell  │  │ Node Mgmt   │  │ Extension    │  │   │
│  │  │ (LLM BYOK)  │  │ (multi-node │  │ Marketplace  │  │   │
│  │  │             │  │  switching)  │  │ Browser      │  │   │
│  │  └──────┬──────┘  └──────┬──────┘  └──────────────┘  │   │
│  │         │                │                             │   │
│  │  ┌──────┴────────────────┴──────────────────────────┐ │   │
│  │  │         window.CWI (BRC-100 Interface)            │ │   │
│  │  │  signing · encryption · certs · payments          │ │   │
│  │  └──────────────────────────────────────────────────┘ │   │
│  └───────────────────────────────────────────────────────┘   │
│                                                               │
│  ┌───────────────────────────────────────────────────────┐   │
│  │  BLE Transport (dispatch envelopes, offline sync)      │   │
│  └───────────────────────────────────────────────────────┘   │
└──────────────────────────────────────────────────────────────┘
           │                        │
           │ HTTPS (admin API)      │ Overlay (SHIP/SLAP)
           │ port 6443              │
           ▼                        ▼
┌──────────────────┐    ┌──────────────────────┐
│ Semantos Node A  │    │ Overlay Network      │
│ (tradie VPS)     │    │ (federated cells)    │
│ ┌──────────────┐ │    └──────────────────────┘
│ │ Shell Router │ │
│ │ CellStore    │ │
│ │ Extensions   │ │
│ └──────────────┘ │
└──────────────────┘
```

---

## What Gets Built (and What Doesn't)

### Built in Phase 31

1. **Plexus WAB Service** — HTTP service implementing the WAB protocol that the BSV Browser connects to. Replaces `https://wab.babbage.systems` with Plexus-native identity: recovery questions for setup, Plexus cert derivation, capability token management. The BSV Browser's `selectedWabUrl` points to this service.

2. **Semantos Shell Web App** — Single-page web application loaded in the BSV Browser's WebView. Contains the conversational chat shell, node connection manager, and extension browser. Communicates with the BSV Browser via `window.CWI` for wallet operations and with remote Semantos nodes via their admin API.

3. **Node Admin Bridge** — HTTPS client that connects the mobile shell to one or more Semantos nodes. Authenticates via Plexus cert, sends shell commands, receives responses. Handles connection management, node switching, and offline queueing.

4. **CWI-to-IdentityAdapter Bridge** — Maps the BSV Browser's BRC-100 `window.CWI` interface to the Semantos kernel's `IdentityAdapter`. Certificate acquisition via CWI maps to Plexus cert operations. Signing via CWI maps to capability token presentation.

5. **402 Micropayment Handler** — Middleware that intercepts 402 responses from node services (anchor proofs, overlay queries) and routes them through CWI's spending authorization flow. The BSV Browser's existing `SpendingAuthorizationModal` handles user approval.

6. **Biometric Unlock Flow** — Plexus key material stored in `expo-secure-store`, gated by `expo-local-authentication` biometric. Recovery questions for initial setup and device recovery. Biometric for daily access.

### NOT Built in Phase 31

- No BSV Browser fork — Semantos loads as a web app in the existing browser
- No library/public-computer QR session flow (deferred)
- No BLE dispatch envelope exchange (deferred to Phase 31G or later)
- No custom React Native modules — everything runs in the WebView or as a WAB service
- No offline-first kernel on device — the phone is a thin client to remote nodes (offline queue in Phase 30I handles temporary disconnection)

---

## Sub-Phase Overview

| Phase | Title | Deliverable | Effort | Prerequisites |
|-------|-------|-------------|--------|--------------|
| 31A | Plexus WAB Service | WAB HTTP service with recovery question auth + Plexus cert derivation | 1 week | Phase 26B (LocalIdentityAdapter) |
| 31B | Semantos Shell Web App | Chat shell SPA for BSV Browser WebView, CWI integration | 1 week | Phase 26G (admin API), 31A |
| 31C | Node Admin Bridge | Multi-node HTTPS client with Plexus cert auth, command dispatch | 3–4 days | 31B |
| 31D | 402 Micropayment Flow | CWI spending authorization for anchor/overlay micropayments | 2–3 days | 31B |
| 31E | Biometric + Secure Storage | expo-secure-store key caching, biometric gate, recovery flow | 2–3 days | 31A |
| 31F | BYOK LLM Integration | Secure API key storage, LLM chat in mobile shell, intent routing | 3–4 days | 31B, 31E |

```
31A ──→ 31B ──→ 31C
  │       │──→ 31D
  │       │──→ 31F
  └──→ 31E ──┘
```

31A (Plexus WAB) is the entry point. 31B (shell app) needs 31A for authentication. 31C/31D/31F can run in parallel after 31B. 31E can run in parallel with 31B after 31A, and 31F needs 31E for secure key storage.

---

## Integration Points with BSV Browser

### WalletContext Integration

The BSV Browser's `WalletContext` already supports:

- `selectedWabUrl` — point this to the Plexus WAB service
- `selectedStorageUrl` — point to node's storage API or Plexus storage
- `selectedNetwork` — 'main', 'testnet', 'teratest'
- `setPasswordRetriever(callback)` — replace with recovery question flow
- `setRecoveryKeySaver(callback)` — replace with Plexus Shamir slice distribution

### Permission Request Queue

The BSV Browser has four permission request queues with modal approval flows:

- `spendingRequests` → 402 micropayment approval
- `certificateRequests` → Plexus cert disclosure to nodes
- `protocolRequests` → overlay network protocol operations
- `basketRequests` → cell basket access

These map directly to Semantos operations. No new permission UI needed — the existing modals handle approval.

### BrowserModeContext

The BSV Browser's `isWeb2Mode` / Web3 mode toggle maps to: Web2 mode = browse without wallet, Web3 mode = authenticated Semantos session with Plexus cert. The `isAuthenticated` flag gates node management features.

### CWI Interface (window.CWI)

The shell web app communicates with the wallet via `window.CWI`:

- `createAction(params)` — create BSV transactions (for anchoring, cell token creation)
- `getPublicKey(params)` — retrieve identity public key for signing
- `encrypt(params)` / `decrypt(params)` — AFFINE cell encryption/decryption
- `createSignature(params)` — sign shell commands for node authentication
- `acquireCertificate(params)` — obtain Plexus capability certificates
- `verifyHmac(params)` — verify cell content integrity

---

## Plexus WAB Protocol Mapping

The default Babbage WAB uses BIP-39 mnemonics. The Plexus WAB replaces this with:

| Babbage WAB Flow | Plexus WAB Flow |
|------------------|-----------------|
| Generate BIP-39 mnemonic → display 12 words | Generate Plexus identity → present recovery questions |
| User writes down seed phrase | User answers personal questions (answers derive key material) |
| Restore from seed phrase | `initiateRecovery(email)` → answer challenges → Shamir slice reassembly |
| Shamir paper backup (optional) | Shamir slices distributed to Plexus infrastructure (automatic) |
| BIP-39 → HD key derivation | Plexus cert → `deriveChild()` for per-resource/per-device keys |
| Sign with HD-derived key | `presentCapability(certId, capabilityId)` → sign with capability token |

The Plexus WAB implements the same HTTP interface that the BSV Browser expects from any WAB, but the underlying identity model is Plexus certificates rather than raw key pairs.

---

## Node Admin API Contract

Phase 26G defines the admin API on port 6443. The mobile client consumes this API:

```
POST /api/shell/execute
  Headers: Authorization: Bearer <plexus-signed-session-token>
  Body: { command: "show jobs --status open", context: { extensionId: "trades" } }
  Response: { result: <shell output>, cells: [...affected cells] }

GET /api/node/status
  Headers: Authorization: Bearer <plexus-signed-session-token>
  Response: { nodeId, certId, extensions: [...], uptime, cellCount, ... }

GET /api/node/extensions
  Response: { extensions: [{ id, name, version, active }] }

POST /api/node/extensions/install
  Body: { extensionId: "property" }
  Response: { installed: true }

GET /api/cells/query
  Headers: Authorization: Bearer <plexus-signed-session-token>
  Body: { path: "trades.jobs.*", filters: { status: "open" } }
  Response: { cells: [...matching cells with capability-filtered visibility] }
```

The mobile client is a thin wrapper around this API. All business logic executes on the node.

---

## Multi-Node Management

A user may have multiple nodes:

- Personal tradie node (VPS, $5/month)
- Shared business node (partner's infrastructure)
- Client's node (observer access only)

The mobile shell maintains a node registry:

```typescript
interface NodeConnection {
  nodeId: string;
  label: string;                    // "My Tradie Node", "ABC Plumbing Shared"
  adminUrl: string;                 // "https://my-node.example.com:6443"
  certId: string;                   // Plexus cert used to authenticate
  capabilities: number[];           // BRC-108 domain flags for this node
  lastConnected: number;
  status: 'connected' | 'disconnected' | 'error';
}
```

Node switching is a context change — tap a different node in the node list, the shell reconnects, capability tokens are re-evaluated, and the UI reflects what you can do on that node.

---

## Security Model

### Key Material Lifecycle

1. **First setup**: User answers recovery questions → Plexus derives root key → stored in `expo-secure-store` (Keychain/Keystore) → biometric enabled
2. **Daily use**: Biometric → `expo-secure-store` read → Plexus cert loaded → session active
3. **Device loss**: New device → answer recovery questions → Plexus reassembles from Shamir slices → new `expo-secure-store` entry → biometric enabled
4. **Biometric failure (repeated)**: Falls back to recovery questions

### What Never Leaves the Phone

- Root key material (always in secure enclave)
- BYOK LLM API key (always in secure enclave)
- Biometric template (managed by OS, never accessible to app)

### What the Node Sees

- Signed session tokens (proves identity without revealing key)
- Shell commands (plaintext, over HTTPS)
- Capability presentations (proves authorization for specific operations)

### What the Overlay Sees

- Published cells (RELEVANT cells are visible to token holders)
- Capability tokens (prove authorization)
- Nothing about the phone, the user's location, or the biometric

---

## Completion Criteria (Master)

- [ ] Plexus WAB service running and connectable from BSV Browser
- [ ] Semantos shell web app loading in BSV Browser WebView
- [ ] Chat shell functional with LLM (BYOK) from mobile
- [ ] At least one Semantos node connectable and administrable from mobile
- [ ] Multi-node switching working
- [ ] 402 micropayments flowing through CWI spending authorization
- [ ] Biometric unlock working (Face ID / Touch ID)
- [ ] Recovery flow working (new device → recovery questions → restored identity)
- [ ] All existing gate tests still pass
- [ ] BSV Browser unmodified (Semantos runs as web app + WAB, no fork)

---

## Next Phase

Phase 32 (future): Library/public-computer QR session flow, BLE dispatch envelope exchange, offline cell caching on device, extension marketplace UI.
