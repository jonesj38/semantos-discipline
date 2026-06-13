---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/overlay/lookup-service-client.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.893110+00:00
---

# core/protocol-types/src/overlay/lookup-service-client.ts

```ts
/**
 * LookupServiceClient — BRC-24 query client for Semantos overlay lookups.
 *
 * Thin wrapper around @bsv/sdk's LookupResolver, configured for Semantos
 * lookup service names that follow BRC-87 naming conventions.
 *
 * Cross-references:
 *   BRC-24: Overlay Network Lookup Services
 *   BRC-87: Standardized Topic/Lookup Naming
 *   @bsv/sdk LookupResolver
 */

import LookupResolver, {
  type LookupAnswer,
  type LookupQuestion,
  type LookupResolverConfig,
} from '@bsv/sdk/overlay-tools/LookupResolver';
import { Transaction, PublicKey } from '@bsv/sdk';
import { CellToken } from '../cell-token';

/** BRC-87 compliant Semantos lookup service names. */
export const SEMANTOS_LOOKUP_SERVICES = {
  byPath: 'ls_semantos_by_path',
  byContent: 'ls_semantos_by_content',
  byParent: 'ls_semantos_by_parent',
  byOwner: 'ls_semantos_by_owner',
  byType: 'ls_semantos_by_type',
  history: 'ls_semantos_history',
} as const;

/** BRC-87: lookup service names must be lowercase letters and underscores, max 50 chars. */
const LOOKUP_NAME_PATTERN = /^[a-z_]{1,50}$/;

/** Validate a lookup service name against BRC-87. */
export function validateLookupName(name: string): boolean {
  return LOOKUP_NAME_PATTERN.test(name);
}

/** Decoded output from a lookup response. */
export interface DecodedLookupOutput {
  /** Transaction ID containing this output. */
  txid: string;
  /** Output index within the transaction. */
  vout: number;
  /** Extracted cell bytes (1024 bytes). */
  cellBytes: Uint8Array;
  /** Semantic path from the PushDrop script. */
  semanticPath: string;
  /** Content hash (32 bytes). */
  contentHash: Uint8Array;
  /** Owner public key. */
  ownerPubKey: PublicKey;
}

export interface LookupServiceClientConfig {
  /** Network preset for host discovery. Default: 'testnet'. */
  networkPreset?: 'mainnet' | 'testnet' | 'local';
  /** Override resolver config (facilitator, SLAP trackers, host overrides). */
  resolverConfig?: Partial<LookupResolverConfig>;
}

export class LookupServiceClient {
  private readonly resolver: LookupResolver;

  constructor(config?: LookupServiceClientConfig) {
    this.resolver = new LookupResolver({
      networkPreset: config?.networkPreset ?? 'testnet',
      ...config?.resolverConfig,
    });
  }

  /** Query by semantic path. */
  async queryByPath(
    path: string,
    options?: { prefix?: boolean; depth?: number },
  ): Promise<LookupAnswer> {
    return this.resolver.query({
      service: SEMANTOS_LOOKUP_SERVICES.byPath,
      query: { path, ...options },
    });
  }

  /** Query by content hash (UHRP-compatible). */
  async queryByContent(contentHash: string): Promise<LookupAnswer> {
    return this.resolver.query({
      service: SEMANTOS_LOOKUP_SERVICES.byContent,
      query: { contentHash },
    });
  }

  /** Query by parent hash. */
  async queryByParent(parentHash: string): Promise<LookupAnswer> {
    return this.resolver.query({
      service: SEMANTOS_LOOKUP_SERVICES.byParent,
      query: { parentHash },
    });
  }

  /** Query by owner ID. */
  async queryByOwner(ownerId: string): Promise<LookupAnswer> {
    return this.resolver.query({
      service: SEMANTOS_LOOKUP_SERVICES.byOwner,
      query: { ownerId },
    });
  }

  /** Query by type hash. */
  async queryByType(typeHash: string): Promise<LookupAnswer> {
    return this.resolver.query({
      service: SEMANTOS_LOOKUP_SERVICES.byType,
      query: { typeHash },
    });
  }

  /** Query version history (BRC-64 chain walk). */
  async queryHistory(key: string): Promise<LookupAnswer> {
    return this.resolver.query({
      service: SEMANTOS_LOOKUP_SERVICES.history,
      query: { key },
    });
  }

  /**
   * Decode PushDrop outputs from a lookup answer.
   *
   * Takes an output-list answer and extracts cell data from each output's
   * locking script using CellToken.extract().
   */
  decodeLookupOutputs(answer: LookupAnswer): DecodedLookupOutput[] {
    if (answer.type !== 'output-list') return [];

    const results: DecodedLookupOutput[] = [];

    for (const output of answer.outputs) {
      try {
        // Parse the BEEF to get the transaction
        const tx = Transaction.fromBEEF(output.beef);
        const vout = output.outputIndex;
        if (!tx.outputs[vout]) continue;

        const extracted = CellToken.extract(tx.outputs[vout].lockingScript);
        if (!extracted) continue;

        results.push({
          txid: tx.id('hex'),
          vout,
          cellBytes: extracted.cellBytes,
          semanticPath: extracted.semanticPath,
          contentHash: extracted.contentHash,
          ownerPubKey: extracted.ownerPubKey,
        });
      } catch {
        // Skip malformed outputs
        continue;
      }
    }

    return results;
  }
}

```
