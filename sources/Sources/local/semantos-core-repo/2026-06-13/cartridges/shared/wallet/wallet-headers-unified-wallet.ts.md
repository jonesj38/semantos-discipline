---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/shared/wallet/wallet-headers-unified-wallet.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.433089+00:00
---

# cartridges/shared/wallet/wallet-headers-unified-wallet.ts

```ts
/**
 * wallet-headers-unified-wallet.ts — BRC-100-conformant wallet adapter
 * that DELEGATES to an external BRC-100 server (Metanet Desktop on
 * localhost:3321 by default, or any other HTTPWalletJSON-conformant
 * endpoint).
 *
 * Per Q9 (canonicalization-decisions.md, 2026-05-28) + C6a tick 4
 * design split (2026-05-28):
 *
 *   - Wraps the existing metanet-client.ts thin HTTP client and extends
 *     it to the full WalletInterface surface.  Every method maps to
 *     POST /<method> against the configured base URL — the same wire
 *     protocol @bsv/sdk's HTTPWalletJSON uses.
 *
 *   - Passes runBrc100InterfaceConformance (shape + round-trip checks),
 *     NOT runBrc100CryptoEquivalence (the delegate's key is operator-
 *     owned, not the deterministic test key — byte-equivalence with a
 *     local ProtoWallet is impossible by construction).
 *
 *   - Cartridge consumers (cell-anchor, arc-broadcast, etc.) keep their
 *     existing metanet-client.ts imports today.  The unified adapter is
 *     the canonical SURFACE for new code paths that want to talk to
 *     Metanet Desktop through the BRC-100 lens rather than the bespoke
 *     2-method shim.
 *
 * The adapter is THIN — almost every method is `body = args ⇒ POST →
 * parse response`.  The complexity lives in error mapping (HTTP errors
 * map to WalletErrorObject envelopes) and in honouring BRC-100's
 * camelCase wire shape (the WalletInterface arg names ARE the JSON
 * keys, no field renaming).
 */

import {
  type WalletInterface,
  type GetPublicKeyArgs,
  type GetPublicKeyResult,
  type CreateSignatureArgs,
  type CreateSignatureResult,
  type VerifySignatureArgs,
  type VerifySignatureResult,
  type CreateHmacArgs,
  type CreateHmacResult,
  type VerifyHmacArgs,
  type VerifyHmacResult,
  type WalletEncryptArgs,
  type WalletEncryptResult,
  type WalletDecryptArgs,
  type WalletDecryptResult,
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
  type AuthenticatedResult,
  type GetHeightResult,
  type GetHeaderArgs,
  type GetHeaderResult,
  type GetNetworkResult,
  type GetVersionResult,
  type RevealCounterpartyKeyLinkageArgs,
  type RevealCounterpartyKeyLinkageResult,
  type RevealSpecificKeyLinkageArgs,
  type RevealSpecificKeyLinkageResult,
} from '@bsv/sdk';

import {
  registerWalletFactory,
  type WalletFactory,
} from './unified-wallet';

/** Default Metanet Desktop base — same as metanet-client.ts. */
export const DEFAULT_METANET_BASE = 'http://localhost:3321';

/** Build-time config the factory consumes. */
export interface WalletHeadersConfig {
  /** Base URL of the BRC-100 HTTP server. Defaults to Metanet Desktop. */
  base?: string;
  /** Custom fetch implementation. Defaults to globalThis.fetch. Test
   *  injection seam — production callers omit. */
  fetch?: typeof globalThis.fetch;
}

/**
 * BRC-100 wallet adapter that delegates every method to a remote
 * BRC-100 HTTP server.  Production target is Metanet Desktop on
 * localhost:3321.  Tests inject a mock fetch for shape conformance.
 */
export class WalletHeadersUnifiedWallet implements WalletInterface {
  private readonly base: string;
  private readonly fetchImpl: typeof globalThis.fetch;

  constructor(config: WalletHeadersConfig = {}) {
    this.base = config.base ?? DEFAULT_METANET_BASE;
    this.fetchImpl = config.fetch ?? globalThis.fetch;
  }

  // ── HTTP plumbing ────────────────────────────────────────────────

  private async call<TResult>(method: string, args: unknown): Promise<TResult> {
    const resp = await this.fetchImpl(`${this.base}/${method}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(args ?? {}),
    });
    if (!resp.ok) {
      const text = await resp.text().catch(() => '');
      throw new Error(
        `wallet-headers ${method} HTTP ${resp.status}: ${text || resp.statusText}`,
      );
    }
    return (await resp.json()) as TResult;
  }

  // ── Crypto subset ─────────────────────────────────────────────────

  async getPublicKey(args: GetPublicKeyArgs): Promise<GetPublicKeyResult> {
    return this.call<GetPublicKeyResult>('getPublicKey', args);
  }

  async createSignature(args: CreateSignatureArgs): Promise<CreateSignatureResult> {
    return this.call<CreateSignatureResult>('createSignature', args);
  }

  async verifySignature(args: VerifySignatureArgs): Promise<VerifySignatureResult> {
    return this.call<VerifySignatureResult>('verifySignature', args);
  }

  async createHmac(args: CreateHmacArgs): Promise<CreateHmacResult> {
    return this.call<CreateHmacResult>('createHmac', args);
  }

  async verifyHmac(args: VerifyHmacArgs): Promise<VerifyHmacResult> {
    return this.call<VerifyHmacResult>('verifyHmac', args);
  }

  async encrypt(args: WalletEncryptArgs): Promise<WalletEncryptResult> {
    return this.call<WalletEncryptResult>('encrypt', args);
  }

  async decrypt(args: WalletDecryptArgs): Promise<WalletDecryptResult> {
    return this.call<WalletDecryptResult>('decrypt', args);
  }

  async revealCounterpartyKeyLinkage(
    args: RevealCounterpartyKeyLinkageArgs,
  ): Promise<RevealCounterpartyKeyLinkageResult> {
    return this.call<RevealCounterpartyKeyLinkageResult>(
      'revealCounterpartyKeyLinkage',
      args,
    );
  }

  async revealSpecificKeyLinkage(
    args: RevealSpecificKeyLinkageArgs,
  ): Promise<RevealSpecificKeyLinkageResult> {
    return this.call<RevealSpecificKeyLinkageResult>(
      'revealSpecificKeyLinkage',
      args,
    );
  }

  // ── Transaction subset ────────────────────────────────────────────

  async createAction(args: CreateActionArgs): Promise<CreateActionResult> {
    return this.call<CreateActionResult>('createAction', args);
  }

  async signAction(args: SignActionArgs): Promise<SignActionResult> {
    return this.call<SignActionResult>('signAction', args);
  }

  async abortAction(args: AbortActionArgs): Promise<AbortActionResult> {
    return this.call<AbortActionResult>('abortAction', args);
  }

  async listActions(args: ListActionsArgs): Promise<ListActionsResult> {
    return this.call<ListActionsResult>('listActions', args);
  }

  async internalizeAction(
    args: InternalizeActionArgs,
  ): Promise<InternalizeActionResult> {
    return this.call<InternalizeActionResult>('internalizeAction', args);
  }

  async listOutputs(args: ListOutputsArgs): Promise<ListOutputsResult> {
    return this.call<ListOutputsResult>('listOutputs', args);
  }

  async relinquishOutput(
    args: RelinquishOutputArgs,
  ): Promise<RelinquishOutputResult> {
    return this.call<RelinquishOutputResult>('relinquishOutput', args);
  }

  // ── Identity certificate subset ───────────────────────────────────

  async acquireCertificate(
    args: AcquireCertificateArgs,
  ): Promise<WalletCertificate> {
    return this.call<WalletCertificate>('acquireCertificate', args);
  }

  async listCertificates(
    args: ListCertificatesArgs,
  ): Promise<ListCertificatesResult> {
    return this.call<ListCertificatesResult>('listCertificates', args);
  }

  async proveCertificate(
    args: ProveCertificateArgs,
  ): Promise<ProveCertificateResult> {
    return this.call<ProveCertificateResult>('proveCertificate', args);
  }

  async relinquishCertificate(
    args: RelinquishCertificateArgs,
  ): Promise<RelinquishCertificateResult> {
    return this.call<RelinquishCertificateResult>('relinquishCertificate', args);
  }

  async discoverByIdentityKey(
    args: DiscoverByIdentityKeyArgs,
  ): Promise<DiscoverCertificatesResult> {
    return this.call<DiscoverCertificatesResult>('discoverByIdentityKey', args);
  }

  async discoverByAttributes(
    args: DiscoverByAttributesArgs,
  ): Promise<DiscoverCertificatesResult> {
    return this.call<DiscoverCertificatesResult>('discoverByAttributes', args);
  }

  // ── Network / status ──────────────────────────────────────────────

  async isAuthenticated(): Promise<AuthenticatedResult> {
    return this.call<AuthenticatedResult>('isAuthenticated', {});
  }

  async waitForAuthentication(): Promise<AuthenticatedResult> {
    return this.call<AuthenticatedResult>('waitForAuthentication', {});
  }

  async getHeight(): Promise<GetHeightResult> {
    return this.call<GetHeightResult>('getHeight', {});
  }

  async getHeaderForHeight(args: GetHeaderArgs): Promise<GetHeaderResult> {
    return this.call<GetHeaderResult>('getHeaderForHeight', args);
  }

  async getNetwork(): Promise<GetNetworkResult> {
    return this.call<GetNetworkResult>('getNetwork', {});
  }

  async getVersion(): Promise<GetVersionResult> {
    return this.call<GetVersionResult>('getVersion', {});
  }
}

// ── Factory registration (parallel to headless-unified-wallet) ─────

export const walletHeadersFactory: WalletFactory = {
  id: 'wallet-headers',
  displayName: 'Wallet Headers (BRC-100 → Metanet Desktop)',
  canTransact: true,
  build: (config: Record<string, unknown>): Promise<WalletInterface> => {
    const cfg = (config ?? {}) as WalletHeadersConfig;
    return Promise.resolve(new WalletHeadersUnifiedWallet(cfg));
  },
};

/**
 * Register the wallet-headers factory under id 'wallet-headers'.  Idempotent
 * via _resetWalletRegistryForTests() — tests call resetWalletRegistry first
 * then registerWalletHeadersWallet().
 */
export function registerWalletHeadersWallet(): void {
  registerWalletFactory(walletHeadersFactory);
}

```
