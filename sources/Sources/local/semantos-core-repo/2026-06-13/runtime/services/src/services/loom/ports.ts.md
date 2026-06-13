---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/services/src/services/loom/ports.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.103936+00:00
---

# runtime/services/src/services/loom/ports.ts

```ts
/**
 * Loom handler ports.
 *
 * Each handler accepts the side-effect dependencies it needs as a small
 * interface so the loom code can be unit-tested with stubs. The real
 * implementations are bound at app boot to the live PlexusService /
 * CashLanesService / FlowRunner / Web Crypto SHA-256.
 *
 * Once prompt 14 lands its definitive port shapes in
 * `core/protocol-types`, the local interfaces here will be replaced
 * with the canonical ones; until then the interfaces here pin the
 * subset of behaviour the loom layer actually consumes.
 */

import { port, type Port } from '@semantos/state';
import type {
  ChannelLifecycleFlow,
  GuardContext,
  PhaseTransitionResult,
} from '../FlowRunner';

/** Hex-string SHA-256 digest of a UTF-8 string. */
export interface HashPort {
  sha256hex(input: string): Promise<string>;
}

/** Minimal Plexus surface used by the channel-metering handler. */
export interface PlexusPort {
  getSnapshot(): { currentIdentity?: { certId: string } | undefined };
  deriveChild(
    parentCertId: string,
    resourceId: string,
    domainFlag: number,
  ): Promise<{ certId: string }>;
  createEdge(
    initiatorCertId: string,
    responderCertId: string,
  ): Promise<{ edgeId: string; sharedSecret: Uint8Array }>;
}

/** CashLanes settlement port. */
export interface CashLanesPort {
  prepareCashLanesSettlement(
    channelId: string,
    ownerAmount: number,
    counterpartyAmount: number,
    feePercent: number,
  ): Promise<{
    unsignedTx: string;
    channelId: string;
    ownerAmount: number;
    counterpartyAmount: number;
  }>;
  collectCashLanesSignatures(
    channelId: string,
    channelCertId: string,
    settlementTx: { unsignedTx: string },
  ): Promise<{ ownerSig: string; counterpartySig: string }>;
  broadcastCashLanesSettlement(
    channelId: string,
    settlementTx: { unsignedTx: string },
    signatures: { ownerSig: string; counterpartySig: string },
  ): Promise<{ txid: string; broadcastTime: number; status: string }>;
  awaitCashLanesConfirmation(
    txid: string,
    confirmations?: number,
  ): Promise<{ confirmed: boolean }>;
}

/** Flow-runner port — only the phase-transition method the channel handler uses. */
export interface FlowRunnerPort {
  transitionPhase(
    lifecycle: ChannelLifecycleFlow,
    currentPhaseId: string,
    targetPhaseId: string,
    context: GuardContext,
  ): PhaseTransitionResult;
}

export const hashPort: Port<HashPort> = port<HashPort>('Hash');
export const plexusPort: Port<PlexusPort> = port<PlexusPort>('Plexus');
export const cashLanesPort: Port<CashLanesPort> = port<CashLanesPort>('CashLanes');
export const flowRunnerPort: Port<FlowRunnerPort> = port<FlowRunnerPort>('FlowRunner');

```
