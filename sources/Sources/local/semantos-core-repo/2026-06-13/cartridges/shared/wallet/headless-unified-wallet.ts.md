---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/shared/wallet/headless-unified-wallet.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.433389+00:00
---

# cartridges/shared/wallet/headless-unified-wallet.ts

```ts
/**
 * headless-unified-wallet.ts — BRC-100-conformant wallet adapter for
 * the in-process headless code path.
 *
 * Per Q9 (canonicalization-decisions.md, 2026-05-28), this adapter is
 * now a wrapper around `@bsv/sdk`'s `ProtoWallet` for the crypto subset
 * of BRC-100, with hooks for the transaction subset that will eventually
 * delegate to existing cartridges/shared/anchor/headless-wallet.ts tx
 * machinery.
 *
 * Crypto methods (delegated to ProtoWallet — ecosystem reference impl):
 *   getPublicKey, createSignature, verifySignature
 *   encrypt, decrypt, createHmac, verifyHmac
 *   revealCounterpartyKeyLinkage, revealSpecificKeyLinkage
 *
 * Transaction methods (currently throw WERR_NOT_IMPLEMENTED — landing in
 *                       C6a tick 4, will wrap headless-wallet.ts sendPushdrop):
 *   createAction, signAction, abortAction, listActions, internalizeAction
 *   listOutputs, relinquishOutput
 *
 * Identity certificate methods (out of scope for C6a; deferred to C6b
 *                                plexus-recovery work):
 *   acquireCertificate, listCertificates, proveCertificate,
 *   relinquishCertificate, discoverByIdentityKey, discoverByAttributes
 *
 * Network info methods (low-stakes — minimal stubs):
 *   getHeight, getHeaderForHeight, getNetwork, getVersion
 *   isAuthenticated, waitForAuthentication
 *
 * SUPERSEDES the bespoke signCellHash/pubkeyForHat implementation from
 * C6a tick 2 (commit 5760f82) per Q9.
 */

import {
  ProtoWallet,
  type WalletInterface,
  type CreateActionArgs,
  type CreateActionResult,
  type SignActionArgs,
  type SignActionResult,
  type AbortActionArgs,
  type AbortActionResult,
  type ListActionsArgs,
  type ListActionsResult,
  type InternalizeActionArgs,
  type InternalizeActionResult,
  type ListOutputsArgs,
  type ListOutputsResult,
  type RelinquishOutputArgs,
  type RelinquishOutputResult,
  type AcquireCertificateArgs,
  type WalletCertificate,
  type ListCertificatesArgs,
  type ListCertificatesResult,
  type ProveCertificateArgs,
  type ProveCertificateResult,
  type RelinquishCertificateArgs,
  type RelinquishCertificateResult,
  type DiscoverByIdentityKeyArgs,
  type DiscoverByAttributesArgs,
  type DiscoverCertificatesResult,
  type GetHeightResult,
  type GetHeaderArgs,
  type GetHeaderResult,
  type GetNetworkResult,
  type GetVersionResult,
  type AuthenticatedResult,
  PrivateKey,
} from '@bsv/sdk';

import {
  registerWalletFactory,
  type WalletFactory,
} from './unified-wallet';

/**
 * Build options for the headless BRC-100 wallet adapter.
 */
export interface HeadlessWalletConfig {
  /**
   * 32-byte raw secp256k1 private key. Caller is responsible for sourcing
   * this from the appropriate IdentityStore (PWA-side) or vault adapter
   * (brain-side). Per Q4 decision — wallet does NOT own custody.
   */
  readonly privKey: Uint8Array;
}

function notImplemented(method: string): never {
  throw new Error(
    `headless-unified-wallet: ${method} not yet implemented — landing in C6a tick 4 (wraps cartridges/shared/anchor/headless-wallet.ts sendPushdrop). Crypto methods (getPublicKey, createSignature, verify, encrypt, decrypt, hmac, key-linkage) work today via ProtoWallet.`,
  );
}

/**
 * BRC-100 wallet adapter wrapping ProtoWallet for crypto + stubs for tx.
 *
 * @bsv/sdk's WalletInterface is the contract. Crypto methods delegate to
 * ProtoWallet (which IS the canonical in-process implementation of
 * BRC-100's crypto subset). Transaction + certificate methods are stubs
 * for now — wired in subsequent ticks.
 */
class HeadlessWallet implements WalletInterface {
  readonly #proto: ProtoWallet;

  constructor(config: HeadlessWalletConfig) {
    if (config.privKey.length !== 32) {
      throw new Error(
        `headless-unified-wallet: privKey must be 32 bytes, got ${config.privKey.length}`,
      );
    }
    // PrivateKey extends BigNumber; fromHex constructs from 64-hex string.
    const privKeyHex = Array.from(config.privKey)
      .map((b) => b.toString(16).padStart(2, '0'))
      .join('');
    const privKey = PrivateKey.fromHex(privKeyHex);
    this.#proto = new ProtoWallet(privKey);
  }

  // ── Crypto subset — delegate to ProtoWallet ──────────────────────────

  getPublicKey: WalletInterface['getPublicKey'] = (args, originator) =>
    this.#proto.getPublicKey(args, originator);

  revealCounterpartyKeyLinkage: WalletInterface['revealCounterpartyKeyLinkage'] =
    (args, originator) => this.#proto.revealCounterpartyKeyLinkage(args, originator);

  revealSpecificKeyLinkage: WalletInterface['revealSpecificKeyLinkage'] =
    (args, originator) => this.#proto.revealSpecificKeyLinkage(args, originator);

  encrypt: WalletInterface['encrypt'] = (args, originator) =>
    this.#proto.encrypt(args, originator);

  decrypt: WalletInterface['decrypt'] = (args, originator) =>
    this.#proto.decrypt(args, originator);

  createHmac: WalletInterface['createHmac'] = (args, originator) =>
    this.#proto.createHmac(args, originator);

  verifyHmac: WalletInterface['verifyHmac'] = (args, originator) =>
    this.#proto.verifyHmac(args, originator);

  createSignature: WalletInterface['createSignature'] = (args, originator) =>
    this.#proto.createSignature(args, originator);

  verifySignature: WalletInterface['verifySignature'] = (args, originator) =>
    this.#proto.verifySignature(args, originator);

  // ── Transaction subset — stubs (C6a tick 4) ──────────────────────────

  createAction: WalletInterface['createAction'] = async (
    _args: CreateActionArgs,
  ): Promise<CreateActionResult> => notImplemented('createAction');

  signAction: WalletInterface['signAction'] = async (
    _args: SignActionArgs,
  ): Promise<SignActionResult> => notImplemented('signAction');

  abortAction: WalletInterface['abortAction'] = async (
    _args: AbortActionArgs,
  ): Promise<AbortActionResult> => notImplemented('abortAction');

  listActions: WalletInterface['listActions'] = async (
    _args: ListActionsArgs,
  ): Promise<ListActionsResult> => notImplemented('listActions');

  internalizeAction: WalletInterface['internalizeAction'] = async (
    _args: InternalizeActionArgs,
  ): Promise<InternalizeActionResult> => notImplemented('internalizeAction');

  listOutputs: WalletInterface['listOutputs'] = async (
    _args: ListOutputsArgs,
  ): Promise<ListOutputsResult> => notImplemented('listOutputs');

  relinquishOutput: WalletInterface['relinquishOutput'] = async (
    _args: RelinquishOutputArgs,
  ): Promise<RelinquishOutputResult> => notImplemented('relinquishOutput');

  // ── Certificate subset — out of scope (C6b plexus-recovery) ──────────

  acquireCertificate: WalletInterface['acquireCertificate'] = async (
    _args: AcquireCertificateArgs,
  ): Promise<WalletCertificate> => notImplemented('acquireCertificate');

  listCertificates: WalletInterface['listCertificates'] = async (
    _args: ListCertificatesArgs,
  ): Promise<ListCertificatesResult> => notImplemented('listCertificates');

  proveCertificate: WalletInterface['proveCertificate'] = async (
    _args: ProveCertificateArgs,
  ): Promise<ProveCertificateResult> => notImplemented('proveCertificate');

  relinquishCertificate: WalletInterface['relinquishCertificate'] = async (
    _args: RelinquishCertificateArgs,
  ): Promise<RelinquishCertificateResult> => notImplemented('relinquishCertificate');

  discoverByIdentityKey: WalletInterface['discoverByIdentityKey'] = async (
    _args: DiscoverByIdentityKeyArgs,
  ): Promise<DiscoverCertificatesResult> => notImplemented('discoverByIdentityKey');

  discoverByAttributes: WalletInterface['discoverByAttributes'] = async (
    _args: DiscoverByAttributesArgs,
  ): Promise<DiscoverCertificatesResult> => notImplemented('discoverByAttributes');

  // ── Network info subset — minimal stubs ──────────────────────────────

  getHeight: WalletInterface['getHeight'] = async (): Promise<GetHeightResult> =>
    notImplemented('getHeight');

  getHeaderForHeight: WalletInterface['getHeaderForHeight'] = async (
    _args: GetHeaderArgs,
  ): Promise<GetHeaderResult> => notImplemented('getHeaderForHeight');

  getNetwork: WalletInterface['getNetwork'] = async (): Promise<GetNetworkResult> => ({
    network: 'mainnet',
  });

  getVersion: WalletInterface['getVersion'] = async (): Promise<GetVersionResult> => ({
    version: 'semantos-headless-1.0.0',
  });

  isAuthenticated: WalletInterface['isAuthenticated'] = async (): Promise<AuthenticatedResult> => ({
    authenticated: true,
  });

  waitForAuthentication: WalletInterface['waitForAuthentication'] = async (): Promise<AuthenticatedResult> => ({
    authenticated: true,
  });
}

/**
 * Factory descriptor. Registered as id 'headless' in the WalletFactory
 * registry. Brain / PWA callers resolve via
 * `getWalletFactory('headless').build({privKey})`.
 */
export const headlessWalletFactory: WalletFactory = {
  id: 'headless',
  displayName: 'Headless single-key wallet (ProtoWallet-backed)',
  canTransact: false, // tx methods stubbed; flips to true when C6a tick 4 wires createAction/signAction
  async build(config: Record<string, unknown>): Promise<WalletInterface> {
    const typed = config as Partial<HeadlessWalletConfig>;
    if (!typed.privKey || !(typed.privKey instanceof Uint8Array)) {
      throw new Error(
        'headlessWalletFactory.build: config.privKey (Uint8Array, 32 bytes) required',
      );
    }
    return new HeadlessWallet({ privKey: typed.privKey });
  },
};

/**
 * Register the headless factory. Idempotent: wrap in try/catch if you
 * may call from multiple entry points.
 */
export function registerHeadlessWallet(): void {
  registerWalletFactory(headlessWalletFactory);
}

```
