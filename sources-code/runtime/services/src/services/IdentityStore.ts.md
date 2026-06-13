---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/services/src/services/IdentityStore.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.096749+00:00
---

# runtime/services/src/services/IdentityStore.ts

```ts
/**
 * IdentityStore — renderer-agnostic identity management.
 *
 * Holds Identity, manages hats, persists to storage (localStorage now, wallet later).
 * Traits use a disclosed/hashed split for selective disclosure.
 * React's IdentityProvider becomes a thin wrapper around this store.
 *
 * Phase 14: Delegates cert operations to PlexusService. Every createIdentity
 * and addFacet call flows through the adapter to get a certId.
 *
 * D-A3 (Helm wires to Plexus identity, Phase 1b): exposes the active
 * hat's cert via `getCert()` / `getCertId()` for callers that authorise
 * Helm-originated backend calls; exposes a boot-readiness Promise via
 * `whenCertReady()` so authenticated work can wait for Plexus to issue
 * the first cert. The pipeline's `buildHatContext` reads `getCert()`;
 * its production path requires a real cert. The dev-stub escape hatch
 * is gated behind `SEMANTOS_DEV_IDENTITY=stub`. See
 * docs/spec/protocol-v0.5.md §4.
 */

import { TypedEventEmitter } from './TypedEventEmitter';
import type { Identity, Hat, IdentityPolicy, IdentityTraits, LoomObject } from '../types/loom';
import type { ObjectTypeDefinition } from '../config/extensionConfig';
import { createObject } from '../state/objectFactory';
import { getPlexusService } from '../plexus/PlexusService';
import type { StorageAdapter } from '../../../../core/protocol-types/src/storage';
import type { IdentityProvider } from '../../../../core/protocol-types/src/identity';

const IDENTITY_STORAGE_KEY = 'workbench-identity';
const ADAPTER_KEY = 'identity/state.json';

/** Client-defined CREATE domain flag (0x00010002). */
const DOMAIN_FLAG_CREATE = 0x00010002;

interface SerializedHat {
  id: string;
  name: string;
  displayName: string;
  capabilities: number[];
  derivationPath: string;
  certId?: string;
  publicKey?: string;
}

interface SerializedIdentity {
  id: string;
  name: string;
  certId?: string;
  publicKey?: string;
  hats: SerializedHat[];
  activeHatId: string;
  policies: Array<{
    id: string;
    name: string;
    scope: Record<string, unknown>;
    conditions: Record<string, unknown>;
    actions: string[];
    createdViaChannel?: string;
    enabled: boolean;
  }>;
  traits?: IdentityTraits;
  linkedIdentities?: string[];
}

type StoreEvents = {
  change: [Identity | null];
  /** D-A3: fired when the active hat's cert transitions from absent → present. */
  'cert-ready': [HatCertSnapshot];
};

/**
 * D-A3 — minimal cert snapshot exposed by `getCert()`. Intentionally
 * narrow: callers that authorise backend calls need the certId and the
 * hat's signing publicKey; nothing else from the rich Hat shape needs
 * to leak across the boundary.
 */
export interface HatCertSnapshot {
  hatId: string;
  certId: string;
  publicKey?: string;
}

const IDENTITY_TYPE: ObjectTypeDefinition = {
  typeHash: 'c41f62505066db8a232b21d3ae72b7ef4ace87377ee1f76c33a8f2141e576d70', // SHA256("semantos.system.Identity")
  name: 'Identity',
  icon: 'shield',
  linearity: 'AFFINE',
  archetype: 'identity',
  defaultCapabilities: [],
  fields: [
    { name: 'name', type: 'string' },
    { name: 'activeHatId', type: 'string' },
  ],
};

const HAT_TYPE: ObjectTypeDefinition = {
  typeHash: '46994e35d03c0c18163aef32e1394ef7940ac885ebd0e879c55c35c990a81b3b', // SHA256("semantos.system.Hat")
  name: 'Hat',
  icon: 'key',
  linearity: 'RELEVANT',
  archetype: 'identity',
  defaultCapabilities: [],
  fields: [
    { name: 'name', type: 'string' },
    { name: 'displayName', type: 'string' },
    { name: 'derivationPath', type: 'string' },
  ],
};

const POLICY_TYPE: ObjectTypeDefinition = {
  typeHash: '34325115745692466266ea15e93401d7c6fd64d6d6604a631260cdc84643f52e', // SHA256("semantos.system.Policy")
  name: 'Policy',
  icon: 'scroll',
  linearity: 'RELEVANT',
  archetype: 'instrument',
  defaultCapabilities: [],
  fields: [
    { name: 'name', type: 'string' },
    { name: 'scope', type: 'string' },
    { name: 'conditions', type: 'string' },
    { name: 'actions', type: 'string' },
  ],
};

const ALL_CAPABILITIES = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];

let idCounter = Math.floor(Math.random() * 10000);
function generateId(prefix: string): string {
  return `${prefix}-${Date.now()}-${++idCounter}`;
}

function createHatObject(
  name: string,
  displayName: string,
  capabilities: number[],
  derivationPath: string,
  certId?: string,
  publicKey?: string,
): Hat {
  const obj = createObject(HAT_TYPE);
  obj.payload.name = name;
  obj.payload.displayName = displayName;
  obj.payload.derivationPath = derivationPath;
  return { id: generateId('hat'), name, displayName, capabilities, derivationPath, certId, publicKey, object: obj };
}

function serializeIdentity(identity: Identity): string {
  const data: SerializedIdentity = {
    id: identity.id,
    name: identity.name,
    certId: identity.certId,
    publicKey: identity.publicKey,
    hats: identity.hats.map(f => ({
      id: f.id,
      name: f.name,
      displayName: f.displayName,
      capabilities: f.capabilities,
      derivationPath: f.derivationPath,
      certId: f.certId,
      publicKey: f.publicKey,
    })),
    activeHatId: identity.activeHatId,
    policies: identity.policies.map(p => ({
      id: p.id,
      name: p.name,
      scope: p.scope,
      conditions: p.conditions,
      actions: p.actions,
      createdViaChannel: p.createdViaChannel,
      enabled: p.enabled,
    })),
    traits: identity.traits,
    linkedIdentities: identity.linkedIdentities,
  };
  return JSON.stringify(data);
}

function deserializeIdentity(json: string): Identity | null {
  try {
    const data: SerializedIdentity = JSON.parse(json);
    const identityObj = createObject(IDENTITY_TYPE);
    identityObj.payload.name = data.name;
    identityObj.payload.activeHatId = data.activeHatId;

    const hats: Hat[] = data.hats.map(f => {
      const fObj = createObject(HAT_TYPE);
      fObj.payload.name = f.name;
      fObj.payload.displayName = f.displayName;
      fObj.payload.derivationPath = f.derivationPath;
      return {
        id: f.id, name: f.name, displayName: f.displayName,
        capabilities: f.capabilities, derivationPath: f.derivationPath,
        certId: f.certId, publicKey: f.publicKey,
        object: fObj,
      };
    });

    const policies: IdentityPolicy[] = data.policies.map(p => {
      const pObj = createObject(POLICY_TYPE);
      pObj.payload.name = p.name;
      return { id: p.id, name: p.name, scope: p.scope, conditions: p.conditions, actions: p.actions, object: pObj, createdViaChannel: p.createdViaChannel, enabled: p.enabled };
    });

    return {
      id: data.id,
      name: data.name,
      certId: data.certId,
      publicKey: data.publicKey,
      object: identityObj,
      hats,
      activeHatId: data.activeHatId,
      policies,
      traits: data.traits ?? { disclosed: {}, hashed: {}, schema: 'semantos.identity.v0.1' },
      linkedIdentities: data.linkedIdentities ?? [],
    };
  } catch {
    return null;
  }
}

/**
 * IdentityStore implements the canonical IdentityProvider interface (W1.5C-1).
 *
 * This class covers the D-A3 cert-manager surface: it tracks cert-readiness
 * and exposes `getCert()`, `getCertId()`, and `whenCertReady()`.
 *
 * Note on `sign()`: IdentityStore does not hold a private key — signing is
 * delegated to the BRC-42-derived child key managed by PlexusService / Helm.
 * The `sign()` method below throws to make this constraint explicit; callers
 * that need request-signing must obtain an EphemeralIdentityProvider (D-A2)
 * or a real PlexusIdentityProvider (D-A3 Helm wire-up, future D-C2).
 */
export class IdentityStore extends TypedEventEmitter<StoreEvents> implements IdentityProvider {
  private identity: Identity | null = null;
  /** Sequential queue to prevent concurrent addFacet calls from racing. */
  private queue: Promise<void> = Promise.resolve();
  private _adapter: StorageAdapter | null;

  // ── D-A3: cert-readiness gate ─────────────────────────────
  //
  // `whenCertReady()` returns a Promise that resolves once the active
  // hat has a non-null certId. Helm boot uses this to delay any
  // authenticated backend call until Plexus has issued (or restored
  // from storage) the cert.
  //
  // The Promise is created lazily on first call. If a cert is already
  // present at the time of the call, the Promise resolves immediately.
  private _certReadyPromise: Promise<HatCertSnapshot> | null = null;
  private _certReadyResolve: ((s: HatCertSnapshot) => void) | null = null;
  /** Last cert snapshot we emitted `cert-ready` for; null before first. */
  private _lastEmittedCertId: string | null = null;

  constructor(adapter?: StorageAdapter) {
    super();
    this._adapter = adapter ?? null;
    this.loadFromLocalStorage();
    // If a cert is already present from localStorage, prime the gate.
    this.maybeFireCertReady();
  }

  /** Load from adapter (async). Call after construction when adapter is provided. */
  async initFromAdapter(): Promise<void> {
    if (!this._adapter) return;
    try {
      const data = await this._adapter.read(ADAPTER_KEY);
      if (data) {
        const json = new TextDecoder().decode(data);
        this.identity = deserializeIdentity(json);
        if (this.identity) {
          this.emit('change', this.identity);
          // D-A3: a restored identity may already carry a cert. If so,
          // fire `cert-ready` so any whenCertReady() awaiter resolves.
          this.maybeFireCertReady();
        }
      }
    } catch {
      // Adapter read failed — keep localStorage/null state
    }
  }

  private loadFromLocalStorage(): void {
    try {
      const saved = localStorage.getItem(IDENTITY_STORAGE_KEY);
      if (saved) this.identity = deserializeIdentity(saved);
    } catch {
      // localStorage not available (SSR, tests)
    }
  }

  private persist(updated: Identity): void {
    this.identity = updated;
    if (this._adapter) {
      const bytes = new TextEncoder().encode(serializeIdentity(updated));
      this._adapter.write(ADAPTER_KEY, bytes).catch(() => {});
    } else {
      try {
        localStorage.setItem(IDENTITY_STORAGE_KEY, serializeIdentity(updated));
      } catch {
        // localStorage not available
      }
    }
    this.emit('change', this.identity);
    // D-A3: after every state change, check whether the active hat now
    // has a cert; if it just gained one, fire `cert-ready` and resolve
    // any pending whenCertReady() awaiter.
    this.maybeFireCertReady();
  }

  getIdentity(): Identity | null {
    return this.identity;
  }

  getActiveHat(): Hat | null {
    if (!this.identity) return null;
    return this.identity.hats.find(f => f.id === this.identity!.activeHatId) ?? null;
  }

  isSetupComplete(): boolean {
    return this.identity !== null;
  }

  // ── D-A3: cert exposure ─────────────────────────────────────

  /**
   * D-A3 — return a snapshot of the active hat's cert, or null if no
   * cert has been issued yet. Helm-originated backend calls authorise
   * via this snapshot (cert_id on the wire, publicKey for signing /
   * verification). The narrow shape avoids leaking the broader Hat
   * surface to network code.
   */
  getCert(): HatCertSnapshot | null {
    const hat = this.getActiveHat();
    if (!hat || !hat.certId) return null;
    return { hatId: hat.id, certId: hat.certId, publicKey: hat.publicKey };
  }

  /** D-A3 — convenience: just the cert_id of the active hat, or null. */
  getCertId(): string | null {
    return this.getActiveHat()?.certId ?? null;
  }

  /**
   * W1.5C-1 — IdentityProvider.sign() stub.
   *
   * IdentityStore is a cert-manager surface; it does not hold a private key.
   * Signing is delegated to the BRC-42-derived key managed by PlexusService /
   * Helm's PlexusIdentityProvider (future D-C2). This stub throws so callers
   * that inadvertently call sign() via the IdentityProvider interface fail fast.
   *
   * @throws Always — IdentityStore cannot sign; obtain a signing-capable
   *   IdentityProvider (EphemeralIdentityProvider or PlexusIdentityProvider).
   */
  sign(_bytes: Uint8Array): never {
    throw new Error(
      "IdentityStore.sign() not available: IdentityStore is a cert-manager surface only. " +
      "Obtain an EphemeralIdentityProvider (D-A2) or PlexusIdentityProvider (D-C2) for signing.",
    );
  }

  /**
   * D-A3 — Promise that resolves once the active hat has a cert.
   *
   * Helm boot awaits this before issuing any authenticated backend
   * call. If a cert is already present at the time of the call, the
   * Promise resolves on the next microtask. If no cert is present, the
   * Promise resolves the next time `cert-ready` fires (i.e. the next
   * `persist` that produces an identity whose active hat has a certId).
   *
   * Idempotent: repeated calls return the same Promise until it
   * resolves; after resolution, fresh calls return an immediately-
   * resolved Promise reflecting the current cert.
   */
  whenCertReady(): Promise<HatCertSnapshot> {
    const present = this.getCert();
    if (present) {
      return Promise.resolve(present);
    }
    if (!this._certReadyPromise) {
      this._certReadyPromise = new Promise<HatCertSnapshot>(resolve => {
        this._certReadyResolve = resolve;
      });
    }
    return this._certReadyPromise;
  }

  /**
   * Internal — fire `cert-ready` if the active hat now has a cert and
   * we haven't already fired for that cert_id. Resolves the pending
   * `whenCertReady()` Promise on first cert.
   */
  private maybeFireCertReady(): void {
    const snapshot = this.getCert();
    if (!snapshot) return;
    if (this._lastEmittedCertId === snapshot.certId) return;
    this._lastEmittedCertId = snapshot.certId;
    this.emit('cert-ready', snapshot);
    if (this._certReadyResolve) {
      this._certReadyResolve(snapshot);
      this._certReadyResolve = null;
      // _certReadyPromise stays referenced so listeners that captured
      // it observe the resolved value; subsequent whenCertReady() calls
      // hit the early-return path above.
    }
  }

  /** Stable getter for useSyncExternalStore. */
  getSnapshot = (): Identity | null => {
    return this.identity;
  };

  /** Stable subscribe for useSyncExternalStore. */
  stableSubscribe = (listener: () => void): (() => void) => {
    return this.on('change', () => listener());
  };

  /**
   * Create a new identity. Delegates to PlexusService for cert registration.
   * Async but backward-compatible: callers can fire-and-forget.
   */
  async createIdentity(name: string): Promise<void> {
    const identityObj = createObject(IDENTITY_TYPE);
    identityObj.payload.name = name;

    // Register with PlexusService
    const plexus = getPlexusService();
    const { certId, publicKey } = await plexus.registerIdentity(name);

    // Derive child cert for default Developer hat
    const derived = await plexus.deriveChild(certId, 'Developer', DOMAIN_FLAG_CREATE);

    const defaultHat = createHatObject(
      'Developer', `${name} (Developer)`, ALL_CAPABILITIES, 'm/brc52/developer/0',
      derived.certId, derived.publicKey,
    );
    identityObj.payload.activeHatId = defaultHat.id;

    const newIdentity: Identity = {
      id: generateId('identity'),
      name,
      certId,
      publicKey,
      object: identityObj,
      hats: [defaultHat],
      activeHatId: defaultHat.id,
      policies: [],
      traits: { disclosed: { name }, hashed: {}, schema: 'semantos.identity.v0.1' },
      linkedIdentities: [],
    };
    this.persist(newIdentity);
  }

  /**
   * Add a hat. Delegates to PlexusService for cert derivation.
   * Uses a sequential queue to prevent concurrent calls from racing.
   */
  async addHat(name: string, displayName: string, capabilities: number[], derivationPath: string): Promise<void> {
    this.queue = this.queue.then(() => this.addHatImpl(name, displayName, capabilities, derivationPath));
    return this.queue;
  }

  private async addHatImpl(name: string, displayName: string, capabilities: number[], derivationPath: string): Promise<void> {
    if (!this.identity) return;

    let hatCertId: string | undefined;
    let hatPublicKey: string | undefined;

    // Derive child cert if identity has a Plexus certId
    if (this.identity.certId) {
      const plexus = getPlexusService();
      const derived = await plexus.deriveChild(this.identity.certId, name, DOMAIN_FLAG_CREATE);
      hatCertId = derived.certId;
      hatPublicKey = derived.publicKey;
    }

    const hat = createHatObject(name, displayName, capabilities, derivationPath, hatCertId, hatPublicKey);
    this.persist({ ...this.identity, hats: [...this.identity.hats, hat] });
  }

  switchHat(facetId: string): void {
    if (!this.identity) return;
    if (!this.identity.hats.some(f => f.id === facetId)) return;
    this.persist({ ...this.identity, activeHatId: facetId });
  }

  addPolicy(policy: Omit<IdentityPolicy, 'object'>): void {
    if (!this.identity) return;
    const pObj = createObject(POLICY_TYPE);
    pObj.payload.name = policy.name;
    const fullPolicy: IdentityPolicy = { ...policy, object: pObj };
    this.persist({ ...this.identity, policies: [...this.identity.policies, fullPolicy] });
  }

  togglePolicy(policyId: string): void {
    if (!this.identity) return;
    this.persist({
      ...this.identity,
      policies: this.identity.policies.map(p =>
        p.id === policyId ? { ...p, enabled: !p.enabled } : p,
      ),
    });
  }

  updateTraits(traits: Partial<Identity['traits']>): void {
    if (!this.identity || !this.identity.traits) return;
    this.persist({
      ...this.identity,
      traits: { ...this.identity.traits, ...traits },
    });
  }
}

```
