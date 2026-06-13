---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-31B-SHELL-WEB-APP.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.690062+00:00
---

# Phase 31B — Semantos Shell Web App (BSV Browser WebView)

**Version**: 1.0
**Date**: April 2026
**Status**: Ready for implementation
**Duration**: 1 week (with 2-day buffer)
**Prerequisites**: Phase 31A complete (Plexus WAB), Phase 26G complete (node admin API on port 6443)
**Master document**: `PHASE-31-MOBILE-CLIENT-MASTER.md`
**Branch**: `phase-31b-shell-web-app`

---

## Context

The BSV Browser loads web applications in its WebView and provides them with `window.CWI` — the BRC-100 wallet interface. Phase 31B builds a Semantos conversational shell as a single-page web application that runs inside this WebView. The shell connects to remote Semantos nodes via their admin API, authenticates via Plexus certs obtained through CWI, and provides the full chat + command experience on mobile.

This is NOT a React Native module. It's a web app — HTML, CSS, JavaScript — that the BSV Browser loads like any other website. The BSV Browser provides the wallet, identity, and payment layers. The web app provides the Semantos-specific UI and business logic.

---

## Source Files / References

| Alias | Path | What to read |
|-------|------|--------------|
| `SHELL:ROUTER` | `packages/shell/src/router.ts` | Shell router — verb dispatch, capability checks |
| `SHELL:CHAT` | `packages/shell/src/chat.ts` | Chat integration — LLM connection, conversation state, facet switching |
| `SHELL:PARSER` | `packages/shell/src/parser.ts` | Command parser — KNOWN_VERBS, SUBCOMMAND_VERBS, flag extraction |
| `SHELL:CONFIG` | `packages/shell/src/config.ts` | Shell config — default extension, LLM settings |
| `SHELL:CAPS` | `packages/shell/src/capabilities.ts` | Capability map — domain flags → shell verbs |
| `BSV:WALLET` | `bsv-browser/context/WalletContext.tsx` | CWI interface, spending/cert request queues |
| `BSV:BROWSER` | `bsv-browser/context/BrowserModeContext.tsx` | Web2/Web3 mode, isAuthenticated |
| `POLICY:BRANCH` | `docs/BRANCHING-AND-CI-POLICY.md` | Commit naming, branch rules |

---

## Deliverables

### D31B.1 — Shell Web App Scaffold

**New package**: `packages/shell-web/`

Single-page web application built with vanilla TypeScript (or lightweight framework). Must be hostable as a static site — the BSV Browser loads it via URL.

```
packages/shell-web/
├── src/
│   ├── index.html          — Entry point, loaded in BSV Browser WebView
│   ├── app.ts              — App initialization, CWI detection, auth flow
│   ├── shell/
│   │   ├── chat-view.ts    — Conversational chat UI (messages, input, send)
│   │   ├── command-bar.ts  — CLI command input with autocomplete
│   │   └── output.ts       — Structured output renderer (tables, objects, diffs)
│   ├── node/
│   │   ├── connection.ts   — NodeConnection manager (HTTPS to admin API)
│   │   ├── registry.ts     — Multi-node registry (add, remove, switch, list)
│   │   └── status.ts       — Node status display (uptime, extensions, cell count)
│   ├── cwi/
│   │   ├── bridge.ts       — CWI ↔ IdentityAdapter bridge
│   │   ├── payments.ts     — 402 micropayment handler via CWI spending
│   │   └── certs.ts        — Certificate acquisition and presentation via CWI
│   ├── styles/
│   │   └── shell.css       — Mobile-optimized shell styling
│   └── types.ts            — Shared types
├── dist/                   — Built static files (deployable)
├── package.json
└── tsconfig.json
```

### D31B.2 — CWI Bridge (window.CWI ↔ Shell)

Bridge between the BSV Browser's CWI interface and the Semantos shell:

```typescript
/**
 * Detects window.CWI, initializes the bridge, and provides
 * identity and wallet operations to the shell.
 */
interface CWIBridge {
  /** Check if running inside BSV Browser (CWI available) */
  isAvailable(): boolean;

  /** Get authenticated identity (Plexus cert) */
  getIdentity(): Promise<{ certId: string; publicKey: string }>;

  /** Sign a shell command for node authentication */
  signCommand(command: string, nodeUrl: string): Promise<{
    signature: string;
    publicKey: string;
    timestamp: number;
  }>;

  /** Request a capability certificate for a specific operation */
  acquireCapability(capabilityId: string): Promise<{
    certificate: BRC68Certificate;
    valid: boolean;
  }>;

  /** Handle a 402 Payment Required response */
  handlePaymentRequired(
    nodeUrl: string,
    amount: number,
    description: string,
  ): Promise<{ paid: boolean; txid?: string }>;

  /** Encrypt data for a recipient cert */
  encrypt(recipientCertId: string, data: Uint8Array): Promise<Uint8Array>;

  /** Decrypt data with own cert */
  decrypt(data: Uint8Array): Promise<Uint8Array>;
}
```

### D31B.3 — Node Connection Manager

Connects to remote Semantos nodes via the admin API:

```typescript
interface NodeConnection {
  nodeId: string;
  label: string;
  adminUrl: string;                 // "https://my-node.example.com:6443"
  certId: string;
  capabilities: number[];
  lastConnected: number;
  status: 'connected' | 'disconnected' | 'error';
}

interface NodeConnectionManager {
  /** Add a new node connection */
  addNode(adminUrl: string, label: string): Promise<NodeConnection>;

  /** Remove a node connection */
  removeNode(nodeId: string): void;

  /** Switch active node context */
  switchNode(nodeId: string): Promise<void>;

  /** Get active node */
  getActive(): NodeConnection | null;

  /** List all nodes */
  listNodes(): NodeConnection[];

  /** Execute a shell command on the active node */
  execute(command: string): Promise<ShellResponse>;

  /** Get node status */
  getStatus(nodeId: string): Promise<NodeStatus>;

  /** Get available extensions on a node */
  getExtensions(nodeId: string): Promise<ExtensionInfo[]>;
}
```

The connection manager:
1. Authenticates to node admin API using Plexus cert (signed via CWI)
2. Sends shell commands as `POST /api/shell/execute`
3. Receives structured responses
4. Handles 402 micropayments via CWI bridge
5. Handles connection errors and reconnection
6. Persists node registry to `localStorage` (BSV Browser manages this)

### D31B.4 — Mobile Chat Shell UI

Conversational chat interface optimized for mobile:

```typescript
interface ChatShellView {
  /** Render message history */
  renderMessages(messages: ChatMessage[]): void;

  /** Handle user input (natural language or CLI command) */
  handleInput(input: string): Promise<void>;

  /** Display structured output (tables, object views, diffs) */
  renderOutput(output: ShellOutput): void;

  /** Show node context indicator (which node, which extension) */
  renderContext(node: NodeConnection, activeExtension: string): void;

  /** Show typing indicator while LLM processes */
  showProcessing(active: boolean): void;
}
```

Input modes:
- **Natural language**: "show my jobs this week" → sent to node's LLM shell
- **CLI command**: `/semantos list jobs --status open` → parsed and executed directly
- **Node management**: `/node switch "My Tradie Node"` → handled locally

### D31B.5 — Integration Tests

```typescript
describe("Shell Web App", () => {
  // T1: CWI bridge detects window.CWI in BSV Browser environment
  // T2: CWI bridge falls back gracefully when not in BSV Browser
  // T3: Node connection authenticates with Plexus cert via CWI
  // T4: Shell command executes on remote node via admin API
  // T5: Multi-node switching changes active connection
  // T6: Node registry persists across page reloads
  // T7: 402 response triggers CWI spending authorization
  // T8: Chat input in natural language routes to node LLM
  // T9: CLI command input parses and executes directly
  // T10: Node status displays correctly (uptime, extensions, cells)
  // T11: Structured output renders tables and object views on mobile
  // T12: Connection error shows reconnection UI
});
```

---

## Completion Criteria

- [ ] `packages/shell-web/` created with SPA scaffold
- [ ] CWI bridge detects and connects to BSV Browser wallet
- [ ] Node connection manager connects to Semantos node admin API
- [ ] Multi-node registry with add/remove/switch
- [ ] Chat shell UI renders messages and handles input
- [ ] Natural language and CLI command modes both work
- [ ] 402 micropayments route through CWI
- [ ] Static build deployable as a URL the BSV Browser can load
- [ ] Tests T1–T12 pass
- [ ] All commits follow `phase-31b/D31B.N:` naming convention
- [ ] Branch is `phase-31b-shell-web-app`

---

## Next Phase

Phase 31C builds the node admin bridge for multi-node management. Phase 31D wires 402 micropayments. Phase 31E adds biometric unlock and secure storage. Phase 31F integrates BYOK LLM for mobile chat.
