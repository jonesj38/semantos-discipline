---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/overlay/uhrp-resolver.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.894784+00:00
---

# core/protocol-types/src/overlay/uhrp-resolver.ts

```ts
/**
 * UhrpResolver — BRC-26 Universal Hash Resolution Protocol.
 *
 * Resolves content hashes to download URLs via UHRP advertisements on
 * the overlay network. Used as a fallback in BsvOverlayAdapter.read()
 * when the primary lookup service doesn't have the content.
 *
 * Cross-references:
 *   BRC-26: Universal Hash Resolution Protocol
 *   overlay/lookup-service-client.ts → LookupServiceClient for content queries
 */

import type LookupResolver from '@bsv/sdk/overlay-tools/LookupResolver';
import type { LookupAnswer } from '@bsv/sdk/overlay-tools/LookupResolver';
import { Transaction } from '@bsv/sdk';

/** UHRP advertisement data extracted from a lookup response. */
export interface UhrpAdvertisement {
  /** Content hash (SHA-256 hex). */
  contentHash: string;
  /** HTTPS download URL. */
  downloadUrl: string;
  /** Content length in bytes. */
  contentLength: number;
  /** Expiry timestamp (epoch ms). 0 = no expiry. */
  expiresAt: number;
}

/** UHRP lookup service name. */
export const UHRP_LOOKUP_SERVICE = 'ls_uhrp';

export class UhrpResolver {
  constructor(private resolver: LookupResolver) {}

  /**
   * Resolve a content hash to a download URL.
   *
   * @param contentHash SHA-256 hex digest
   * @returns Download URL or null if not found
   */
  async resolve(contentHash: string): Promise<string | null> {
    try {
      const answer = await this.resolver.query({
        service: UHRP_LOOKUP_SERVICE,
        query: { contentHash },
      });

      const ads = this.parseAdvertisements(answer, contentHash);
      if (ads.length === 0) return null;

      // Filter expired advertisements
      const now = Date.now();
      const valid = ads.filter(a => a.expiresAt === 0 || a.expiresAt > now);
      if (valid.length === 0) return null;

      return valid[0].downloadUrl;
    } catch {
      return null;
    }
  }

  /**
   * Resolve content hash and download the raw bytes.
   *
   * @param contentHash SHA-256 hex digest
   * @returns Raw bytes or null if not found
   */
  async download(contentHash: string): Promise<Uint8Array | null> {
    const url = await this.resolve(contentHash);
    if (!url) return null;

    try {
      const response = await fetch(url);
      if (!response.ok) return null;
      const buffer = await response.arrayBuffer();
      return new Uint8Array(buffer);
    } catch {
      return null;
    }
  }

  /**
   * Parse UHRP advertisements from a lookup answer.
   *
   * UHRP advertisements are PushDrop outputs with fields:
   *   [0] host public key
   *   [1] content hash (32 bytes)
   *   [2] download URL (UTF-8)
   *   [3] expiry timestamp (8 bytes LE uint64)
   *   [4] content length (4 bytes LE uint32)
   */
  private parseAdvertisements(
    answer: LookupAnswer,
    contentHash: string,
  ): UhrpAdvertisement[] {
    if (answer.type !== 'output-list') return [];

    const results: UhrpAdvertisement[] = [];
    for (const output of answer.outputs) {
      try {
        const tx = Transaction.fromBEEF(output.beef);
        const script = tx.outputs[output.outputIndex]?.lockingScript;
        if (!script) continue;

        // Extract PushDrop fields
        const { PushDrop } = require('@bsv/sdk');
        const { fields } = PushDrop.decode(script, 'after');
        if (fields.length < 5) continue;

        const hashBytes = new Uint8Array(fields[1]);
        const hashHex = Array.from(hashBytes)
          .map(b => b.toString(16).padStart(2, '0'))
          .join('');
        if (hashHex !== contentHash) continue;

        const downloadUrl = new TextDecoder().decode(new Uint8Array(fields[2]));
        const expiryDv = new DataView(new Uint8Array(fields[3]).buffer);
        const expiresAt = fields[3].length >= 8
          ? Number(expiryDv.getBigUint64(0, true))
          : 0;
        const lengthDv = new DataView(new Uint8Array(fields[4]).buffer);
        const contentLength = fields[4].length >= 4
          ? lengthDv.getUint32(0, true)
          : 0;

        results.push({ contentHash, downloadUrl, contentLength, expiresAt });
      } catch {
        continue;
      }
    }
    return results;
  }
}

```
