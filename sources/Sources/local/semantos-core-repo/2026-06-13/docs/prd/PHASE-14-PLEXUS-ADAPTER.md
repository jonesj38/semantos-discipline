---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-14-PLEXUS-ADAPTER.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.680497+00:00
---

# Phase 14 — PlexusAdapter + Stub (The Non-Locking Boundary)

**Version**: 1.0
**Date**: March 2026
**Status**: Ready for implementation
**Duration**: 2 weeks (with 3-day buffer)
**Prerequisites**: Phases 9, 9.5 complete (services extracted, visibility/governance types)
**Master document**: `PLEXUS-INTEGRATION-MAP.md`
**Branch**: `phase-14-plexus-adapter`

---

## Context

Plexus is the production identity, derivation, and graph infrastructure. The loom consumes it — it does not reimplement it. The loom owns semantic meaning, evidence chains, governance, taxonomy, flows, and reputation. Plexus owns identity, derivation, graph structure, capabilities, and transport.

The adapter is the membrane between them. Keep it thin. Keep it stable. Keep it ours.

### The Boundary Rule

**The loom NEVER imports `plexus-core` or `plexus-vendor-sdk` directly.** It imports a `PlexusAdapter` interface. In production, this is backed by the real SDK. In dev/test, it is backed by an in-memory stub. This means:

- We can develop the entire loom without a running Plexus instance
- We can swap Plexus versions without touching loom code
- We never lock to Plexus internal types — only to our own adapter contract

### Architecture Layers

```
+------------------------------------------------------------------+
|  WORKBENCH (semantos-core)                                       |
|  - Semantic objects, extension configs, flows, governance          |
|  - UI: canvas, conversation, taxonomy, reputation                |
|  - Consumes Plexus via adapter interface                         |
+------------------------------------------------------------------+
        |  PlexusAdapter (interface)          |
        |  - registerIdentity()              |
        |  - deriveChild()                   |
        |  - createEdge()                    |
        |  - querySubtree()                  |
        |  - presentCapability()             |
        |  - initiateRecovery()              |
        |  - sendAuthenticated()             |
        v                                    v
+----------------------------+  +----------------------------+
|  PLEXUS SDK (production)   |  |  STUB ADAPTER (dev/test)   |
|  - Vendor SDK (graph DAG)  |  |  - In-memory graph         |
|  - Core Library (crypto)   |  |  - Deterministic keys      |
|  - Network SDK (transport) |  |  - No wallet required      |
|  - Contracts (types)       |  |                            |
+----------------------------+  +----------------------------+
```

---

## Source Files / References

| Alias | Path | What to extract |
|-------|------|-----------------|
| `MAP:PLEXUS` | `docs/prd/PLEXUS-INTEGRATION-MAP.md` | Architecture section, Plexus Components tier 1 table |
| `SVC:IDENTITY` | `packages/loom/src/services/IdentityStore.ts` | Existing identity registration, facet creation, resolution API |
| `SVC:STORE` | `packages/loom/src/services/LoomStore.ts` | Existing object creation, cell header structure, ownerId field |
| `SVC:CONFIG` | `packages/loom/src/services/ConfigStore.ts` | Config loading, extension config structure |
| `TYPE:WORKBENCH` | `packages/loom/src/types/workbench.ts` | Cell, Header, Identity type definitions |
| `CFG:CORE` | `configs/extensions/core.json` | Base types and governance flows |
| `CFG:TRADES` | `configs/extensions/trades-services.json` | Real extension data for testing |
| `POLICY:BRANCH` | `docs/BRANCHING-AND-CI-POLICY.md` | Commit naming convention, branch rules |

---

## Deliverables

### D14.1 — PlexusAdapter Interface

**New file**: `packages/loom/src/plexus/types.ts`

The `PlexusAdapter` interface as the primary contract between loom and Plexus. All methods. All JSDoc. Only primitive types in the signature — no Plexus imports.

```typescript
/**
 * PlexusAdapter — the membrane between loom and Plexus.
 *
 * All loom identity and graph operations flow through this interface.
 * No Plexus types leak into the loom. No `@plexus/*` imports outside
 * the plexus/ directory.
 */
export interface PlexusAdapter {
  /**
   * Register a new identity with Plexus.
   *
   * @param email - loom user email
   * @returns certId (unique identity certificate ID) and publicKey (PEM format)
   */
  registerIdentity(email: string): Promise<{
    certId: string;
    publicKey: string;
  }>;

  /**
   * Derive a child identity (facet) under an existing parent.
   *
   * Enforces monotonic child_index: once an index is used, it is never reused,
   * even if the child is deleted.
   *
   * @param parentCertId - cert_id of the parent identity
   * @param resourceId - unique identifier for the resource owned by this facet
   * @param domainFlag - BRC-100 domain flag (0=loom, 1=trades, 2=library, etc)
   * @returns certId of the child, publicKey, child_index used
   */
  deriveChild(parentCertId: string, resourceId: string, domainFlag: number): Promise<{
    certId: string;
    publicKey: string;
    childIndex: number;
  }>;

  /**
   * Resolve an identity by cert_id to retrieve its tree structure and metadata.
   *
   * @param certId - certificate ID to resolve
   * @returns cert metadata (publicKey, email, created, updated) and tree structure
   */
  resolveIdentity(certId: string): Promise<{
    certId: string;
    publicKey: string;
    email?: string;
    created: number;
    updated: number;
    children?: Array<{ certId: string; childIndex: number; resourceId: string }>;
  }>;

  /**
   * Create an edge (authenticated connection) between two identities.
   *
   * Both parties must have their certs registered. The edge stores a shared secret
   * hash derived from both parties' keys.
   *
   * @param initiatorCertId - cert_id of the identity initiating the edge
   * @param responderCertId - cert_id of the identity receiving the edge
   * @returns edgeId and sharedSecret hash
   */
  createEdge(initiatorCertId: string, responderCertId: string): Promise<{
    edgeId: string;
    sharedSecret: string;
  }>;

  /**
   * Query a subtree rooted at a given cert_id, up to specified depth.
   *
   * @param rootCertId - cert_id of the root to query
   * @param depth - how many levels deep to traverse (1, 2, 3, etc)
   * @returns tree structure with all descendants up to depth
   */
  querySubtree(rootCertId: string, depth: number): Promise<{
    root: string;
    children: Array<{
      certId: string;
      childIndex: number;
      resourceId: string;
      grandchildren?: any[];
    }>;
  }>;

  /**
   * Present a capability to prove authorization for an operation.
   *
   * In stub mode, all capabilities are valid. In production, validates against
   * the Capability Domain.
   *
   * @param certId - cert_id presenting the capability
   * @param capabilityId - capability UTXO ID
   * @returns { valid: true } if valid, { valid: false, reason: string } if not
   */
  presentCapability(certId: string, capabilityId: string): Promise<{
    valid: boolean;
    reason?: string;
  }>;

  /**
   * Initiate identity recovery flow.
   *
   * Simulates (or triggers in production) the 4-phase recovery challenge protocol:
   * 1. Challenge set generated
   * 2. User answers challenges
   * 3. Recovery verified
   * 4. Export payload generated
   *
   * @param email - email of the identity to recover
   * @returns sessionId and challengeCount
   */
  initiateRecovery(email: string): Promise<{
    sessionId: string;
    challengeCount: number;
    challenges?: Array<{ id: string; prompt: string }>;
  }>;

  /**
   * Submit recovery challenge answers.
   *
   * @param sessionId - from initiateRecovery()
   * @param answers - array of { challengeId: string; answer: string }
   * @returns { verified: true, exportPayload } if correct, { verified: false } if not
   */
  submitChallengeAnswers(
    sessionId: string,
    answers: Array<{ challengeId: string; answer: string }>
  ): Promise<{
    verified: boolean;
    exportPayload?: string;
  }>;

  /**
   * Send an authenticated message via Plexus transport.
   *
   * In stub mode, this is a no-op log. In production, routes through Network SDK.
   *
   * @param senderCertId - cert_id of the sender
   * @param receiverCertId - cert_id of the receiver
   * @param payload - JSON-serializable message
   * @returns messageId
   */
  sendAuthenticated(
    senderCertId: string,
    receiverCertId: string,
    payload: Record<string, any>
  ): Promise<{ messageId: string }>;
}

/**
 * PlexusMode — determines which adapter implementation to use.
 */
export type PlexusMode = 'stub' | 'local' | 'cloud';

/**
 * PlexusConfig — configuration for adapter initialization.
 */
export interface PlexusConfig {
  mode: PlexusMode;
  endpoint?: string;        // for local/cloud modes
  debugLogging?: boolean;
}

/**
 * PlexusError — loom-native error type.
 *
 * All Plexus errors are mapped to this type before surfacing to loom code.
 * Never expose Plexus-internal error types outside the plexus/ directory.
 */
export interface PlexusError {
  code: string;             // loom error code: CERT_NOT_FOUND, INVALID_DOMAIN, RECOVERY_FAILED, etc
  message: string;
  recoverable: boolean;     // true if operation can be retried
}

/**
 * PlexusState — snapshot of adapter state for useSyncExternalStore.
 */
export interface PlexusState {
  currentIdentity?: {
    certId: string;
    email?: string;
  };
  identities: Map<string, {
    certId: string;
    publicKey: string;
    created: number;
  }>;
  edges: Map<string, {
    edgeId: string;
    initiator: string;
    responder: string;
  }>;
  lastOperation?: {
    method: string;
    timestamp: number;
    success: boolean;
  };
}
```

### D14.2 — StubPlexusAdapter

**New file**: `packages/loom/src/plexus/stub.ts`

In-memory DAG, deterministic keys (sha256-based, no wallet), full interface compliance. Every method implemented — no stubs within the stub.

Requirements:

- `registerIdentity()` produces deterministic cert_id from email + timestamp seed
- `deriveChild()` enforces monotonic child_index (never reuses an index, even after deletion)
- `createEdge()` computes a deterministic shared secret hash
- `querySubtree()` walks the in-memory tree to the requested depth
- `presentCapability()` checks an in-memory capability set (always returns valid in stub mode)
- `initiateRecovery()` simulates the 4-phase recovery flow with in-memory challenge sets
- `sendAuthenticated()` no-ops (logs the call if `debugLogging` is true)

```typescript
import crypto from 'crypto';
import { PlexusAdapter, PlexusConfig, PlexusState, PlexusError } from './types';

/**
 * StubPlexusAdapter — in-memory implementation for dev/test.
 *
 * Does NOT require wallet, network, or running Plexus service.
 * All identities and keys are deterministic based on input data.
 * Enforces monotonic child_index and full tree semantics.
 */
export class StubPlexusAdapter implements PlexusAdapter {
  private debugLogging: boolean;
  private identities = new Map<string, {
    email: string;
    publicKey: string;
    created: number;
    children: Map<number, {
      certId: string;
      resourceId: string;
      childIndex: number;
    }>;
  }>();
  private edges = new Map<string, {
    edgeId: string;
    initiator: string;
    responder: string;
    sharedSecret: string;
  }>();
  private nextChildIndex = new Map<string, number>();  // parentCertId → next available index
  private recoverySessions = new Map<string, {
    sessionId: string;
    email: string;
    challenges: Array<{ id: string; prompt: string; answer: string }>;
    verified: boolean;
  }>();

  constructor(config: PlexusConfig) {
    this.debugLogging = config.debugLogging || false;
  }

  async registerIdentity(email: string): Promise<{
    certId: string;
    publicKey: string;
  }> {
    if (this.debugLogging) {
      console.log(`[PlexusStub] registerIdentity(${email})`);
    }

    // Deterministic cert_id from email + timestamp seed
    const seed = crypto
      .createHash('sha256')
      .update(email + ':' + 'phase-14-stub')
      .digest('hex')
      .slice(0, 32);

    const certId = 'cert:' + seed;

    // Deterministic public key (fake, but stable)
    const publicKey = '-----BEGIN PUBLIC KEY-----\n' +
      crypto.createHash('sha256').update(certId).digest('base64').match(/.{1,64}/g)?.join('\n') +
      '\n-----END PUBLIC KEY-----';

    this.identities.set(certId, {
      email,
      publicKey,
      created: Date.now(),
      children: new Map(),
    });

    this.nextChildIndex.set(certId, 0);

    return { certId, publicKey };
  }

  async deriveChild(
    parentCertId: string,
    resourceId: string,
    domainFlag: number
  ): Promise<{
    certId: string;
    publicKey: string;
    childIndex: number;
  }> {
    if (this.debugLogging) {
      console.log(
        `[PlexusStub] deriveChild(${parentCertId}, ${resourceId}, domainFlag=${domainFlag})`
      );
    }

    const parent = this.identities.get(parentCertId);
    if (!parent) {
      throw {
        code: 'CERT_NOT_FOUND',
        message: `Parent cert_id ${parentCertId} not found`,
        recoverable: true,
      } as PlexusError;
    }

    // Monotonic child_index: get next available, increment for next time
    const childIndex = this.nextChildIndex.get(parentCertId) ?? 0;
    this.nextChildIndex.set(parentCertId, childIndex + 1);

    // Deterministic child cert_id
    const seed = crypto
      .createHash('sha256')
      .update(parentCertId + ':' + resourceId + ':' + domainFlag + ':' + childIndex)
      .digest('hex')
      .slice(0, 32);

    const certId = 'cert:' + seed;
    const publicKey = '-----BEGIN PUBLIC KEY-----\n' +
      crypto.createHash('sha256').update(certId).digest('base64').match(/.{1,64}/g)?.join('\n') +
      '\n-----END PUBLIC KEY-----';

    // Record child under parent
    parent.children.set(childIndex, {
      certId,
      resourceId,
      childIndex,
    });

    // Register child as an identity
    this.identities.set(certId, {
      email: parent.email,
      publicKey,
      created: Date.now(),
      children: new Map(),
    });

    this.nextChildIndex.set(certId, 0);

    return { certId, publicKey, childIndex };
  }

  async resolveIdentity(certId: string): Promise<{
    certId: string;
    publicKey: string;
    email?: string;
    created: number;
    updated: number;
    children?: Array<{ certId: string; childIndex: number; resourceId: string }>;
  }> {
    if (this.debugLogging) {
      console.log(`[PlexusStub] resolveIdentity(${certId})`);
    }

    const identity = this.identities.get(certId);
    if (!identity) {
      throw {
        code: 'CERT_NOT_FOUND',
        message: `Identity ${certId} not found`,
        recoverable: true,
      } as PlexusError;
    }

    const children = Array.from(identity.children.values());

    return {
      certId,
      publicKey: identity.publicKey,
      email: identity.email,
      created: identity.created,
      updated: Date.now(),
      children,
    };
  }

  async createEdge(
    initiatorCertId: string,
    responderCertId: string
  ): Promise<{
    edgeId: string;
    sharedSecret: string;
  }> {
    if (this.debugLogging) {
      console.log(
        `[PlexusStub] createEdge(${initiatorCertId}, ${responderCertId})`
      );
    }

    const initiator = this.identities.get(initiatorCertId);
    const responder = this.identities.get(responderCertId);

    if (!initiator || !responder) {
      throw {
        code: 'CERT_NOT_FOUND',
        message: 'One or both certs not found',
        recoverable: true,
      } as PlexusError;
    }

    // Deterministic shared secret from both public keys
    const sharedSecret = crypto
      .createHash('sha256')
      .update(initiatorCertId + ':' + responderCertId)
      .digest('hex');

    const edgeId = 'edge:' + sharedSecret.slice(0, 32);

    this.edges.set(edgeId, {
      edgeId,
      initiator: initiatorCertId,
      responder: responderCertId,
      sharedSecret,
    });

    return { edgeId, sharedSecret };
  }

  async querySubtree(rootCertId: string, depth: number): Promise<{
    root: string;
    children: Array<{
      certId: string;
      childIndex: number;
      resourceId: string;
      grandchildren?: any[];
    }>;
  }> {
    if (this.debugLogging) {
      console.log(`[PlexusStub] querySubtree(${rootCertId}, depth=${depth})`);
    }

    const root = this.identities.get(rootCertId);
    if (!root) {
      throw {
        code: 'CERT_NOT_FOUND',
        message: `Root cert_id ${rootCertId} not found`,
        recoverable: true,
      } as PlexusError;
    }

    const children = Array.from(root.children.values());

    if (depth === 1) {
      return { root: rootCertId, children };
    }

    // Recursively fetch grandchildren
    const childrenWithGrandchildren = await Promise.all(
      children.map(async (child) => {
        const subtree = await this.querySubtree(child.certId, depth - 1);
        return {
          ...child,
          grandchildren: subtree.children,
        };
      })
    );

    return { root: rootCertId, children: childrenWithGrandchildren };
  }

  async presentCapability(
    certId: string,
    capabilityId: string
  ): Promise<{
    valid: boolean;
    reason?: string;
  }> {
    if (this.debugLogging) {
      console.log(
        `[PlexusStub] presentCapability(${certId}, ${capabilityId})`
      );
    }

    // Stub mode: all capabilities are valid
    return { valid: true };
  }

  async initiateRecovery(email: string): Promise<{
    sessionId: string;
    challengeCount: number;
    challenges?: Array<{ id: string; prompt: string }>;
  }> {
    if (this.debugLogging) {
      console.log(`[PlexusStub] initiateRecovery(${email})`);
    }

    const sessionId = 'session:' + crypto.randomBytes(16).toString('hex');

    // Generate deterministic challenge set
    const challenges = [
      { id: 'c1', prompt: 'What is your email?', answer: email },
      { id: 'c2', prompt: 'What is 2 + 2?', answer: '4' },
      { id: 'c3', prompt: 'True or false: Plexus is a graph?', answer: 'true' },
      { id: 'c4', prompt: 'What is the meaning of life?', answer: '42' },
    ];

    this.recoverySessions.set(sessionId, {
      sessionId,
      email,
      challenges,
      verified: false,
    });

    return {
      sessionId,
      challengeCount: challenges.length,
      challenges: challenges.map(({ id, prompt }) => ({ id, prompt })),
    };
  }

  async submitChallengeAnswers(
    sessionId: string,
    answers: Array<{ challengeId: string; answer: string }>
  ): Promise<{
    verified: boolean;
    exportPayload?: string;
  }> {
    if (this.debugLogging) {
      console.log(`[PlexusStub] submitChallengeAnswers(${sessionId})`);
    }

    const session = this.recoverySessions.get(sessionId);
    if (!session) {
      throw {
        code: 'SESSION_NOT_FOUND',
        message: `Recovery session ${sessionId} not found`,
        recoverable: true,
      } as PlexusError;
    }

    // Check answers
    const verified = answers.every((answer) => {
      const challenge = session.challenges.find((c) => c.id === answer.challengeId);
      return challenge && challenge.answer === answer.answer;
    });

    if (!verified) {
      return { verified: false };
    }

    session.verified = true;

    // Generate deterministic export payload
    const exportPayload = Buffer.from(
      JSON.stringify({
        sessionId,
        email: session.email,
        timestamp: Date.now(),
        recoveryToken: crypto.randomBytes(32).toString('hex'),
      })
    ).toString('base64');

    return { verified: true, exportPayload };
  }

  async sendAuthenticated(
    senderCertId: string,
    receiverCertId: string,
    payload: Record<string, any>
  ): Promise<{ messageId: string }> {
    if (this.debugLogging) {
      console.log(
        `[PlexusStub] sendAuthenticated(${senderCertId} → ${receiverCertId})`
      );
    }

    const messageId = 'msg:' + crypto.randomBytes(16).toString('hex');
    return { messageId };
  }
}
```

### D14.3 — PlexusService

**New file**: `packages/loom/src/plexus/PlexusService.ts`

Renderer-agnostic service (follows Phase 9 pattern). Wraps the adapter with `useSyncExternalStore`-compatible state.

```typescript
import { PlexusAdapter, PlexusConfig, PlexusState } from './types';
import { StubPlexusAdapter } from './stub';

/**
 * PlexusService — the synchronous boundary between loom and adapter.
 *
 * Wraps PlexusAdapter with state management compatible with React's useSyncExternalStore.
 * All async operations trigger state updates and notify listeners.
 * Never exposes Plexus types — only primitives and loom types.
 */
export class PlexusService {
  private adapter: PlexusAdapter;
  private listeners = new Set<() => void>();
  private state: PlexusState = {
    identities: new Map(),
    edges: new Map(),
  };

  constructor(config: PlexusConfig) {
    // Phase 14: stub only. Phase 15 will wire real SDK here.
    this.adapter = new StubPlexusAdapter(config);
  }

  /**
   * Register a new identity.
   */
  async registerIdentity(email: string): Promise<{
    certId: string;
    publicKey: string;
  }> {
    const result = await this.adapter.registerIdentity(email);

    this.state.identities.set(result.certId, {
      certId: result.certId,
      publicKey: result.publicKey,
      created: Date.now(),
    });
    this.state.currentIdentity = {
      certId: result.certId,
      email,
    };
    this.state.lastOperation = {
      method: 'registerIdentity',
      timestamp: Date.now(),
      success: true,
    };

    this.notifyListeners();
    return result;
  }

  /**
   * Derive a child identity.
   */
  async deriveChild(
    parentCertId: string,
    resourceId: string,
    domainFlag: number
  ): Promise<{
    certId: string;
    publicKey: string;
    childIndex: number;
  }> {
    const result = await this.adapter.deriveChild(parentCertId, resourceId, domainFlag);

    this.state.identities.set(result.certId, {
      certId: result.certId,
      publicKey: result.publicKey,
      created: Date.now(),
    });
    this.state.lastOperation = {
      method: 'deriveChild',
      timestamp: Date.now(),
      success: true,
    };

    this.notifyListeners();
    return result;
  }

  /**
   * Resolve an identity.
   */
  async resolveIdentity(certId: string): Promise<{
    certId: string;
    publicKey: string;
    email?: string;
    created: number;
    updated: number;
    children?: Array<{ certId: string; childIndex: number; resourceId: string }>;
  }> {
    return this.adapter.resolveIdentity(certId);
  }

  /**
   * Create an edge between two identities.
   */
  async createEdge(
    initiatorCertId: string,
    responderCertId: string
  ): Promise<{
    edgeId: string;
    sharedSecret: string;
  }> {
    const result = await this.adapter.createEdge(initiatorCertId, responderCertId);

    this.state.edges.set(result.edgeId, {
      edgeId: result.edgeId,
      initiator: initiatorCertId,
      responder: responderCertId,
    });
    this.state.lastOperation = {
      method: 'createEdge',
      timestamp: Date.now(),
      success: true,
    };

    this.notifyListeners();
    return result;
  }

  /**
   * Query a subtree.
   */
  async querySubtree(rootCertId: string, depth: number): Promise<{
    root: string;
    children: Array<{
      certId: string;
      childIndex: number;
      resourceId: string;
      grandchildren?: any[];
    }>;
  }> {
    return this.adapter.querySubtree(rootCertId, depth);
  }

  /**
   * Present a capability.
   */
  async presentCapability(
    certId: string,
    capabilityId: string
  ): Promise<{
    valid: boolean;
    reason?: string;
  }> {
    return this.adapter.presentCapability(certId, capabilityId);
  }

  /**
   * Initiate recovery.
   */
  async initiateRecovery(email: string): Promise<{
    sessionId: string;
    challengeCount: number;
    challenges?: Array<{ id: string; prompt: string }>;
  }> {
    return this.adapter.initiateRecovery(email);
  }

  /**
   * Submit recovery answers.
   */
  async submitChallengeAnswers(
    sessionId: string,
    answers: Array<{ challengeId: string; answer: string }>
  ): Promise<{
    verified: boolean;
    exportPayload?: string;
  }> {
    return this.adapter.submitChallengeAnswers(sessionId, answers);
  }

  /**
   * Send authenticated message.
   */
  async sendAuthenticated(
    senderCertId: string,
    receiverCertId: string,
    payload: Record<string, any>
  ): Promise<{ messageId: string }> {
    return this.adapter.sendAuthenticated(senderCertId, receiverCertId, payload);
  }

  /**
   * useSyncExternalStore subscription.
   */
  subscribe(listener: () => void): () => void {
    this.listeners.add(listener);
    return () => {
      this.listeners.delete(listener);
    };
  }

  /**
   * useSyncExternalStore snapshot.
   */
  getSnapshot(): PlexusState {
    return this.state;
  }

  /**
   * Notify all listeners of state change.
   */
  private notifyListeners(): void {
    this.listeners.forEach((listener) => listener());
  }
}

/**
 * Singleton instance — initialized in main loom bootstrap.
 */
let plexusService: PlexusService | null = null;

export function initializePlexusService(config: PlexusConfig): PlexusService {
  plexusService = new PlexusService(config);
  return plexusService;
}

export function getPlexusService(): PlexusService {
  if (!plexusService) {
    throw new Error('PlexusService not initialized. Call initializePlexusService() first.');
  }
  return plexusService;
}
```

### D14.4 — IdentityStore Integration

**Modified file**: `packages/loom/src/services/IdentityStore.ts`

Wire `IdentityStore` to delegate cert operations to `PlexusService`:

- `registerIdentity()` → `plexusService.registerIdentity()`
- Facet creation → `plexusService.deriveChild()` with appropriate domain flag
- Identity resolution → `plexusService.resolveIdentity()`

The existing `IdentityStore` API does not change. Internal implementation delegates to PlexusService.

```typescript
// Modified IdentityStore.ts excerpt

import { getPlexusService } from '../plexus/PlexusService';

export class IdentityStore {
  /**
   * Register a new identity (delegates to PlexusService).
   */
  async registerIdentity(email: string): Promise<Identity> {
    const plexus = getPlexusService();
    const { certId, publicKey } = await plexus.registerIdentity(email);

    const identity: Identity = {
      id: certId,
      email,
      publicKey,
      created: Date.now(),
      updated: Date.now(),
    };

    // Store in local registry for quick access
    this.identities.set(certId, identity);
    this.notifyListeners();

    return identity;
  }

  /**
   * Create a facet (child identity) under an existing identity.
   */
  async createFacet(
    parentIdentityId: string,
    resourceId: string,
    domainFlag: number
  ): Promise<Identity> {
    const plexus = getPlexusService();
    const { certId, publicKey, childIndex } = await plexus.deriveChild(
      parentIdentityId,
      resourceId,
      domainFlag
    );

    const facet: Identity = {
      id: certId,
      parent: parentIdentityId,
      resourceId,
      domainFlag,
      childIndex,
      publicKey,
      created: Date.now(),
      updated: Date.now(),
    };

    this.identities.set(certId, facet);
    this.notifyListeners();

    return facet;
  }

  /**
   * Resolve an identity by ID.
   */
  async resolveIdentity(id: string): Promise<Identity | null> {
    // Try local cache first
    if (this.identities.has(id)) {
      return this.identities.get(id) || null;
    }

    // Query Plexus
    const plexus = getPlexusService();
    try {
      const resolved = await plexus.resolveIdentity(id);

      const identity: Identity = {
        id: resolved.certId,
        email: resolved.email,
        publicKey: resolved.publicKey,
        created: resolved.created,
        updated: resolved.updated,
        children: resolved.children?.map(c => c.certId),
      };

      this.identities.set(id, identity);
      return identity;
    } catch (err) {
      return null;
    }
  }
}
```

### D14.5 — Object Creation Integration

**Modified file**: `packages/loom/src/services/LoomStore.ts`

Wire `createObject()` to stamp `certId` from `PlexusService.deriveChild()` onto the cell header `ownerId` field. Every new semantic object gets a Plexus-derived owner identity.

```typescript
// Modified LoomStore.ts excerpt

import { getPlexusService } from '../plexus/PlexusService';

export class LoomStore {
  /**
   * Create a new semantic object.
   *
   * Stamps the object header with a Plexus-derived certId as ownerId.
   */
  async createObject(params: CreateObjectParams): Promise<SemanticObject> {
    const plexus = getPlexusService();

    // Derive a child identity for this object
    const { certId } = await plexus.deriveChild(
      params.creatorCertId,
      params.objectId,
      params.domainFlag // e.g., 1 for trades, 2 for library
    );

    // Create the object with Plexus-derived owner
    const cell: Cell = {
      objId: params.objectId,
      header: {
        ownerId: certId,  // <-- Plexus-derived cert_id
        type: params.type,
        created: Date.now(),
        updated: Date.now(),
        version: 1,
      },
      body: params.body,
      evidence: [],
    };

    this.objects.set(params.objectId, cell);
    this.notifyListeners();

    return {
      id: params.objectId,
      type: params.type,
      ownerId: certId,
      created: cell.header.created,
    };
  }
}
```

---

## TDD Gate

All tests in `packages/__tests__/phase14-gate.test.ts`.

### Unit Tests

| ID | Test |
|----|------|
| T1 | `StubPlexusAdapter.registerIdentity()` returns deterministic certId + publicKey |
| T2 | `StubPlexusAdapter.deriveChild()` produces correct derivation path at 3 levels deep |
| T3 | `StubPlexusAdapter.deriveChild()` enforces monotonic child_index (delete child, derive new → index increments, not reuses) |
| T4 | `StubPlexusAdapter.createEdge()` returns edgeId + sharedSecret hash |
| T5 | `StubPlexusAdapter.querySubtree()` returns correct tree structure at depth 1, 2, 3 |
| T6 | `StubPlexusAdapter.presentCapability()` returns `{ valid: true }` for all capabilities in stub mode |
| T7 | `StubPlexusAdapter.initiateRecovery()` returns sessionId + challengeCount |
| T8 | `StubPlexusAdapter.submitChallengeAnswers()` with correct answers returns `{ verified: true, exportPayload }` |
| T9 | `PlexusService` constructor with `mode: 'stub'` creates a working service |
| T10 | `PlexusService.subscribe()` notifies listeners after state-changing operations |

### Integration Tests

| ID | Test |
|----|------|
| T11 | `IdentityStore.createIdentity()` delegates to PlexusService and stamps certId |
| T12 | `IdentityStore.createFacet()` calls `PlexusService.deriveChild()` with correct domain flag |
| T13 | `LoomStore.createObject()` stamps certId as ownerId on the cell header |
| T14 | Creating 3 facets under one identity produces 3 distinct certIds with sequential childIndex values |
| T15 | `querySubtree()` on root identity returns all derived facets |

### Anti-Lock Tests

| ID | Test |
|----|------|
| T16 | `grep -r "@plexus" packages/loom/src/ --include="*.ts" \| grep -v "/plexus/"` returns nothing |
| T17 | `PlexusAdapter` interface signature contains only primitive types (string, number, boolean, Record) |
| T18 | Switching `PlexusConfig.mode` from `'stub'` to `'stub'` (same interface, different instance) requires zero loom code changes |
| T19 | Stub adapter error handling: unknown parentCertId throws `PlexusError` with `recoverable: true` |
| T20 | No Plexus-specific error types in any file outside `packages/loom/src/plexus/` |

---

## What NOT to Do

1. **No @plexus imports outside adapter directory** — The loom never sees `plexus-core`, `plexus-vendor-sdk`, or any Plexus module. Only `PlexusAdapter` interface and `PlexusService` leave the plexus/ directory.

2. **No Plexus types in adapter interface** — All method signatures use primitives: string, number, boolean, Record<string, any>. No Plexus types leak into the interface.

3. **No stubs within the stub** — Every method in `StubPlexusAdapter` is fully implemented. No throw NotImplementedError. No TODO comments. If it's not implemented, it doesn't go in the stub.

4. **No mocks in production paths** — The stub is the mock. It is used in dev/test. In production, the real Plexus SDK adapter is swapped in. No Jest mocks of PlexusService in production code.

5. **No easy tests** — Tests must cover:
   - Monotonic child_index enforcement (including after deletion)
   - Deterministic key generation (same input → same output)
   - Tree traversal to depth 3
   - Error handling (recoverable vs fatal)
   - State notification on async completion

6. **No tests that match broken code** — If a test passes and you later refactor, the test should still pass. If it breaks, you broke something. Don't "fix" the test by making it looser.

7. **Renderer agnosticism is not optional** — `PlexusService` is not a React hook. It does not import React. It works with `useSyncExternalStore` but is not bound to it. Prove it in tests.

8. **The stub is never removed** — Even in production, the stub remains in the codebase. Switching between stub and real is a config change, not a code change.

9. **Monotonic child_index enforced** — Once an index is used, it is never reused, even if the child is deleted. The next call to `deriveChild()` uses the next available index. This is load-bearing for Plexus security.

---

## Phase Completion Criteria

You are done when ALL of:

- [ ] `packages/loom/src/plexus/types.ts` exists with full `PlexusAdapter` interface (no stubs)
- [ ] `packages/loom/src/plexus/stub.ts` exists with full `StubPlexusAdapter` (every method implemented)
- [ ] `packages/loom/src/plexus/PlexusService.ts` exists with `useSyncExternalStore`-compatible state
- [ ] `IdentityStore` delegates cert operations to `PlexusService` (no hardcoded IDs)
- [ ] `LoomStore.createObject()` stamps `certId` as `ownerId`
- [ ] Tests T1–T20 all pass
- [ ] `bun run check` passes (zero TypeScript errors)
- [ ] `bun run build` succeeds
- [ ] No `@plexus/*` imports outside `packages/loom/src/plexus/`
- [ ] Errata sprint complete with `docs/prd/PHASE-14-ERRATA.md`
- [ ] All commits follow `phase-14/D14.N:` naming convention
- [ ] Branch is `phase-14-plexus-adapter`

---

## Errata

After the TDD gate passes, you must run an errata sprint. Output findings to `docs/prd/PHASE-14-ERRATA.md`.

The errata sprint includes:

- Edge cases in stub that real SDK will handle differently
- Performance concerns (deterministic key generation, tree traversal, state notification)
- Documentation gaps in adapter interface
- Missing validation in PlexusService
- Type safety issues (casting between cert_id formats)

Do not ship without errata resolution.

---

## Next Phase

Phase 15 replaces the stub with the real Plexus Vendor SDK. The adapter interface does not change. The loom does not change. Only the implementation behind the interface changes. That is the point.

```
PlexusAdapter (unchanged)
      |
      v
PlexusService (unchanged)
      |
      +-- StubPlexusAdapter (Phase 14)
      |
      +-- RealPlexusAdapter (Phase 15)
```

The same interface. Two implementations. Swap at runtime. Zero loom code changes.
