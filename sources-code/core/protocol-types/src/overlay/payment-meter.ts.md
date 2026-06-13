---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/overlay/payment-meter.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.893666+00:00
---

# core/protocol-types/src/overlay/payment-meter.ts

```ts
/**
 * PaymentMeter — BRC-101 Service Monetization Framework client.
 *
 * Manages micropayment relationships between users and storage providers.
 * Users pre-fund a balance with a provider, and each SHIP/SLAP operation
 * deducts from that balance.
 *
 * Cross-references:
 *   BRC-101: Diverse Facilitators for SHIP/SLAP
 */

import { PrivateKey, Transaction } from '@bsv/sdk';

export interface ProviderBalance {
  /** Current balance in satoshis. */
  balance: number;
  /** Cost per SHIP submission (satoshis). */
  ratePerSubmit: number;
  /** Cost per SLAP query (satoshis). */
  ratePerQuery: number;
  /** Cost per byte per month of storage (satoshis). */
  ratePerByteMonth: number;
}

export class PaymentMeter {
  constructor(private ownerKey: PrivateKey) {}

  /**
   * Check balance with a storage provider.
   *
   * Queries the provider's SMF endpoint for current balance and rates.
   */
  async checkBalance(providerUrl: string): Promise<ProviderBalance> {
    const url = `${providerUrl}/api/v1/smf/balance`;
    const response = await fetch(url, {
      headers: this.authHeaders('GET', url),
    });

    if (!response.ok) {
      throw new Error(`Balance check failed: ${response.status} ${response.statusText}`);
    }

    return response.json();
  }

  /**
   * Top up balance with a storage provider.
   *
   * Creates a payment transaction sending satoshis to the provider's
   * payment address and notifies them via the SMF endpoint.
   *
   * @param providerUrl Provider's base URL
   * @param amount Satoshis to deposit
   * @returns Transaction ID of the top-up payment
   */
  async topUp(
    providerUrl: string,
    amount: number,
  ): Promise<{ txid: string }> {
    // Get provider's payment address
    const infoUrl = `${providerUrl}/api/v1/smf/payment-info`;
    const infoResponse = await fetch(infoUrl, {
      headers: this.authHeaders('GET', infoUrl),
    });

    if (!infoResponse.ok) {
      throw new Error(`Payment info fetch failed: ${infoResponse.status}`);
    }

    const { paymentAddress } = await infoResponse.json();

    // Notify the provider of the top-up intent
    const topUpUrl = `${providerUrl}/api/v1/smf/top-up`;
    const response = await fetch(topUpUrl, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        ...this.authHeaders('POST', topUpUrl),
      },
      body: JSON.stringify({ amount, paymentAddress }),
    });

    if (!response.ok) {
      throw new Error(`Top-up failed: ${response.status} ${response.statusText}`);
    }

    return response.json();
  }

  /**
   * Generate SMF authentication headers for a request.
   *
   * Uses the owner's private key to sign a message containing
   * the request method, URL, and timestamp (BRC-31 style).
   */
  authHeaders(
    method: string,
    url: string,
  ): Record<string, string> {
    const timestamp = Date.now().toString();
    const message = `${method} ${url} ${timestamp}`;
    const messageBytes = new TextEncoder().encode(message);

    // Simple HMAC-style auth: sign the message with owner key
    const { createHash } = require('crypto');
    const hash = createHash('sha256').update(messageBytes).digest();
    const sig = this.ownerKey.sign(hash);

    return {
      'X-SMF-PublicKey': this.ownerKey.toPublicKey().toString(),
      'X-SMF-Timestamp': timestamp,
      'X-SMF-Signature': sig.toDER().toString(),
    };
  }
}

```
