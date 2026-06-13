---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/overlay/provider-discovery.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.892552+00:00
---

# core/protocol-types/src/overlay/provider-discovery.ts

```ts
/**
 * ProviderDiscovery — BRC-23 CHIP and BRC-25 CLAP for discovering
 * storage providers that host Semantos overlay topics and lookup services.
 *
 * The @bsv/sdk's TopicBroadcaster and LookupResolver already perform
 * SHIP/SLAP host discovery internally. This class adds Semantos-specific
 * orchestration: best-endpoint selection, rate comparison, and fallback
 * to configured endpoints.
 *
 * Cross-references:
 *   BRC-23: CHIP — Confederacy Host Interconnect Protocol
 *   BRC-25: CLAP — Confederacy Lookup Availability Protocol
 *   BRC-88: SHIP/SLAP Synchronization Architecture
 */

import LookupResolver from '@bsv/sdk/overlay-tools/LookupResolver';
import type { LookupResolverConfig } from '@bsv/sdk/overlay-tools/LookupResolver';

export interface ProviderInfo {
  /** Provider's public key (hex). */
  publicKey: string;
  /** Provider's domain. */
  domain: string;
  /** Topics or lookup services this provider hosts. */
  topicsOrServices: string[];
  /** Price per operation (from BRC-101 SMF rate advertisement). */
  rate?: {
    perSubmit?: number;
    perQuery?: number;
    perByteMonth?: number;
  };
}

export interface ProviderDiscoveryConfig {
  /** Network preset. Default: 'testnet'. */
  networkPreset?: 'mainnet' | 'testnet' | 'local';
  /** Fallback topic manager endpoints (topic → URL). */
  topicManagerFallback?: Record<string, string>;
  /** Fallback lookup service endpoints (service → URL). */
  lookupServiceFallback?: Record<string, string>;
  /** Resolver config overrides. */
  resolverConfig?: Partial<LookupResolverConfig>;
}

export class ProviderDiscovery {
  private readonly resolver: LookupResolver;
  private readonly topicFallback: Record<string, string>;
  private readonly lookupFallback: Record<string, string>;

  constructor(config?: ProviderDiscoveryConfig) {
    this.resolver = new LookupResolver({
      networkPreset: config?.networkPreset ?? 'testnet',
      ...config?.resolverConfig,
    });
    this.topicFallback = config?.topicManagerFallback ?? {};
    this.lookupFallback = config?.lookupServiceFallback ?? {};
  }

  /**
   * Discover topic manager hosts for a given topic name.
   * Queries SHIP advertisements via the SDK's resolver.
   * Falls back to configured endpoints if discovery fails.
   */
  async discoverTopicHosts(topicName: string): Promise<ProviderInfo[]> {
    try {
      const answer = await this.resolver.query({
        service: 'ls_ship',
        query: { topic: topicName },
      });

      if (answer.type === 'output-list' && answer.outputs.length > 0) {
        return this.parseProviderOutputs(answer, [topicName]);
      }
    } catch {
      // Fall through to fallback
    }

    // Fallback to configured endpoint
    const fallbackUrl = this.topicFallback[topicName];
    if (fallbackUrl) {
      return [{
        publicKey: '',
        domain: new URL(fallbackUrl).hostname,
        topicsOrServices: [topicName],
      }];
    }

    return [];
  }

  /**
   * Discover lookup service hosts for a given service name.
   * Queries SLAP advertisements via the SDK's resolver.
   * Falls back to configured endpoints if discovery fails.
   */
  async discoverLookupHosts(serviceName: string): Promise<ProviderInfo[]> {
    try {
      const answer = await this.resolver.query({
        service: 'ls_slap',
        query: { service: serviceName },
      });

      if (answer.type === 'output-list' && answer.outputs.length > 0) {
        return this.parseProviderOutputs(answer, [serviceName]);
      }
    } catch {
      // Fall through to fallback
    }

    const fallbackUrl = this.lookupFallback[serviceName];
    if (fallbackUrl) {
      return [{
        publicKey: '',
        domain: new URL(fallbackUrl).hostname,
        topicsOrServices: [serviceName],
      }];
    }

    return [];
  }

  /**
   * Get the best endpoint for a given topic or service.
   * Returns the first discovered or fallback endpoint.
   */
  async getBestEndpoint(
    name: string,
    type: 'topic' | 'lookup',
  ): Promise<string | null> {
    const providers = type === 'topic'
      ? await this.discoverTopicHosts(name)
      : await this.discoverLookupHosts(name);

    if (providers.length === 0) return null;

    // Return the domain of the first provider
    const domain = providers[0].domain;
    return `https://${domain}`;
  }

  /** Parse provider info from lookup answer outputs. */
  private parseProviderOutputs(
    answer: import('@bsv/sdk/overlay-tools/LookupResolver').LookupAnswer,
    services: string[],
  ): ProviderInfo[] {
    if (answer.type !== 'output-list') return [];

    const providers: ProviderInfo[] = [];
    for (const output of answer.outputs) {
      try {
        const { Transaction, PushDrop } = require('@bsv/sdk');
        const tx = Transaction.fromBEEF(output.beef);
        const script = tx.outputs[output.outputIndex]?.lockingScript;
        if (!script) continue;

        const { fields, lockingPublicKey } = PushDrop.decode(script, 'after');
        if (fields.length < 1) continue;

        const domain = new TextDecoder().decode(new Uint8Array(fields[0]));
        providers.push({
          publicKey: lockingPublicKey.toString(),
          domain,
          topicsOrServices: services,
        });
      } catch {
        continue;
      }
    }
    return providers;
  }
}

```
