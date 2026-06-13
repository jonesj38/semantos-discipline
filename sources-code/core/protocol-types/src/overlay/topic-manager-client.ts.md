---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/overlay/topic-manager-client.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.892830+00:00
---

# core/protocol-types/src/overlay/topic-manager-client.ts

```ts
/**
 * TopicManagerClient — BRC-22 submit client for Semantos overlay topics.
 *
 * Thin wrapper around @bsv/sdk's TopicBroadcaster, configured for Semantos
 * topic names that follow BRC-87 naming conventions.
 *
 * Cross-references:
 *   BRC-22: Overlay Network Data Synchronization
 *   BRC-87: Standardized Topic/Lookup Naming
 *   @bsv/sdk TopicBroadcaster (SHIPBroadcaster)
 */

import TopicBroadcaster, {
  type SHIPBroadcasterConfig,
  type STEAK,
  type TaggedBEEF,
} from '@bsv/sdk/overlay-tools/SHIPBroadcaster';
import type { Transaction, BroadcastResponse, BroadcastFailure } from '@bsv/sdk';

/** BRC-87 compliant Semantos topic names. */
export const SEMANTOS_TOPICS = {
  objects: 'tm_semantos_objects',
  policies: 'tm_semantos_policies',
  governance: 'tm_semantos_governance',
  taxonomy: 'tm_semantos_taxonomy',
  identity: 'tm_semantos_identity',
  evidence: 'tm_semantos_evidence',
} as const;

export type SemantosTopicPrefix = keyof typeof SEMANTOS_TOPICS;

/** BRC-87: topic names must be lowercase letters and underscores, max 50 chars. */
const TOPIC_NAME_PATTERN = /^[a-z_]{1,50}$/;

/** Validate a topic name against BRC-87 rules. */
export function validateTopicName(name: string): boolean {
  return TOPIC_NAME_PATTERN.test(name);
}

/** Map a storage key prefix to its Semantos topic name. */
export function topicForKey(key: string): string {
  const prefix = key.split('/')[0] as SemantosTopicPrefix;
  const topic = SEMANTOS_TOPICS[prefix];
  if (!topic) {
    throw new Error(
      `No topic mapping for key prefix '${prefix}'. ` +
      `Valid prefixes: ${Object.keys(SEMANTOS_TOPICS).join(', ')}`,
    );
  }
  return topic;
}

export interface TopicManagerClientConfig {
  /** Network preset for host discovery. Default: 'testnet'. */
  networkPreset?: 'mainnet' | 'testnet' | 'local';
  /** Override broadcaster config (facilitator, resolver, acknowledgment requirements). */
  broadcasterConfig?: Partial<SHIPBroadcasterConfig>;
}

export class TopicManagerClient {
  private readonly networkPreset: 'mainnet' | 'testnet' | 'local';
  private readonly broadcasterConfig: Partial<SHIPBroadcasterConfig>;

  constructor(config?: TopicManagerClientConfig) {
    this.networkPreset = config?.networkPreset ?? 'testnet';
    this.broadcasterConfig = config?.broadcasterConfig ?? {};
  }

  /**
   * Submit a cell-token transaction to overlay topic managers.
   *
   * Creates a TopicBroadcaster for the specified topics and broadcasts
   * the transaction. Returns the STEAK acknowledgment indicating which
   * outputs were admitted by which topic managers.
   */
  async submit(
    tx: Transaction,
    topics: string[],
  ): Promise<BroadcastResponse | BroadcastFailure> {
    for (const topic of topics) {
      if (!validateTopicName(topic)) {
        throw new Error(
          `Topic name '${topic}' violates BRC-87: must match /^[a-z_]{1,50}$/`,
        );
      }
    }

    const broadcaster = new TopicBroadcaster(topics, {
      networkPreset: this.networkPreset,
      ...this.broadcasterConfig,
    });

    return broadcaster.broadcast(tx);
  }

  /**
   * Submit a transaction to the topic determined by a storage key prefix.
   * Convenience method that resolves the topic from the key.
   */
  async submitForKey(
    tx: Transaction,
    key: string,
  ): Promise<BroadcastResponse | BroadcastFailure> {
    const topic = topicForKey(key);
    return this.submit(tx, [topic]);
  }
}

```
