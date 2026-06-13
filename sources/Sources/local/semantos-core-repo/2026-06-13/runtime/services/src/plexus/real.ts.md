---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/services/src/plexus/real.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.101748+00:00
---

# runtime/services/src/plexus/real.ts

```ts
/**
 * RealPlexusAdapter — production adapter wrapping @plexus/vendor-sdk.
 *
 * This is the ONLY file in the workbench that imports from @plexus/*.
 * All Plexus-internal types are translated to primitives at this boundary.
 * Gate test T33 enforces this constraint.
 */

import type { PlexusAdapter, PlexusConfig, PlexusError } from './types';
import { VendorSDK } from '@plexus/vendor-sdk';
import type { PlexusCert } from '@plexus/contracts';

function makePlexusError(code: string, message: string, recoverable: boolean): PlexusError {
  return { code, message, recoverable };
}

function wrapError(err: unknown): PlexusError {
  if (err && typeof err === 'object' && 'code' in err) {
    const e = err as { code: string; message: string; recoverable?: boolean };
    return makePlexusError(e.code, e.message, e.recoverable ?? false);
  }
  const message = err instanceof Error ? err.message : String(err);
  return makePlexusError('UNKNOWN', message, false);
}

export class RealPlexusAdapter implements PlexusAdapter {
  private sdk: VendorSDK;
  private debugLogging: boolean;

  constructor(config: PlexusConfig) {
    this.debugLogging = config.debugLogging ?? false;
    this.sdk = new VendorSDK({
      dbPath: config.endpoint ?? ':memory:',
      salt: 'plexus-local-v1',
      // Use faster PBKDF2 for :memory: (test) mode, full iterations for persistent DBs
      pbkdf2Iterations: config.endpoint && config.endpoint !== ':memory:' ? 100_000 : 1_000,
    });
  }

  async registerIdentity(email: string): Promise<{
    certId: string;
    publicKey: string;
  }> {
    if (this.debugLogging) {
      console.log(`[PlexusReal] registerIdentity(${email})`);
    }
    try {
      return this.sdk.registerIdentity(email);
    } catch (err) {
      throw wrapError(err);
    }
  }

  async deriveChild(
    parentCertId: string,
    resourceId: string,
    domainFlag: number,
  ): Promise<{
    certId: string;
    publicKey: string;
    childIndex: number;
  }> {
    if (this.debugLogging) {
      console.log(`[PlexusReal] deriveChild(${parentCertId}, ${resourceId}, domainFlag=${domainFlag})`);
    }
    try {
      return this.sdk.deriveChild(parentCertId, resourceId, domainFlag);
    } catch (err) {
      throw wrapError(err);
    }
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
      console.log(`[PlexusReal] resolveIdentity(${certId})`);
    }
    try {
      return this.sdk.resolveIdentity(certId);
    } catch (err) {
      throw wrapError(err);
    }
  }

  async createEdge(
    initiatorCertId: string,
    responderCertId: string,
  ): Promise<{
    edgeId: string;
    sharedSecret: string;
  }> {
    if (this.debugLogging) {
      console.log(`[PlexusReal] createEdge(${initiatorCertId}, ${responderCertId})`);
    }
    try {
      return this.sdk.createEdge(initiatorCertId, responderCertId);
    } catch (err) {
      throw wrapError(err);
    }
  }

  async querySubtree(rootCertId: string, depth: number): Promise<{
    root: string;
    children: Array<{
      certId: string;
      childIndex: number;
      resourceId: string;
      grandchildren?: Array<{
        certId: string;
        childIndex: number;
        resourceId: string;
      }>;
    }>;
  }> {
    if (this.debugLogging) {
      console.log(`[PlexusReal] querySubtree(${rootCertId}, depth=${depth})`);
    }
    try {
      return this.sdk.querySubtree(rootCertId, depth);
    } catch (err) {
      throw wrapError(err);
    }
  }

  async presentCapability(
    certId: string,
    capabilityId: string,
  ): Promise<{
    valid: boolean;
    reason?: string;
  }> {
    if (this.debugLogging) {
      console.log(`[PlexusReal] presentCapability(${certId}, ${capabilityId})`);
    }
    try {
      return this.sdk.presentCapability(certId, capabilityId);
    } catch (err) {
      throw wrapError(err);
    }
  }

  async initiateRecovery(email: string): Promise<{
    sessionId: string;
    challengeCount: number;
    challenges?: Array<{ id: string; prompt: string }>;
  }> {
    if (this.debugLogging) {
      console.log(`[PlexusReal] initiateRecovery(${email})`);
    }
    try {
      return this.sdk.initiateRecovery(email);
    } catch (err) {
      throw wrapError(err);
    }
  }

  async submitChallengeAnswers(
    sessionId: string,
    answers: Array<{ challengeId: string; answer: string }>,
  ): Promise<{
    verified: boolean;
    exportPayload?: string;
  }> {
    if (this.debugLogging) {
      console.log(`[PlexusReal] submitChallengeAnswers(${sessionId})`);
    }
    try {
      return this.sdk.submitChallengeAnswers(sessionId, answers);
    } catch (err) {
      throw wrapError(err);
    }
  }

  async sendAuthenticated(
    senderCertId: string,
    receiverCertId: string,
    payload: Record<string, string>,
  ): Promise<{ messageId: string }> {
    if (this.debugLogging) {
      console.log(`[PlexusReal] sendAuthenticated(${senderCertId} → ${receiverCertId})`);
    }
    try {
      return this.sdk.sendAuthenticated(senderCertId, receiverCertId, payload);
    } catch (err) {
      throw wrapError(err);
    }
  }
}

```
