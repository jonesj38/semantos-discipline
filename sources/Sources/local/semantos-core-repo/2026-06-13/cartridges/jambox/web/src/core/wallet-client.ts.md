---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/jambox/web/src/core/wallet-client.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.609781+00:00
---

# cartridges/jambox/web/src/core/wallet-client.ts

```ts
/**
 * Minimal browser-safe BRC-100 wallet client for jam-room.
 *
 * Speaks the same HTTP surface as Metanet Desktop / wallet-browser:
 *   POST /getPublicKey   — identity key or BRC-42 derived key
 *   POST /createAction   — fund + sign + broadcast outputs
 *
 * Deliberately avoids @semantos/protocol-types to stay Node-dep-free
 * in the browser bundle (protocol-types pulls @semantos/cell-ops which
 * uses Node's `createHash`).
 */

export interface JamWalletOutput {
  lockingScript: string;   // hex
  satoshis: number;
  outputDescription?: string;
  basket?: string;
  tags?: string[];
}

export interface JamWalletCreateActionResult {
  txid: string;
  /** Raw hex or BEEF — not needed by the anchor caller, just forwarded. */
  rawTx?: string;
}

export class JamWalletClient {
  constructor(
    private readonly baseUrl: string,
    private readonly originator = 'jam.semantos',
  ) {}

  /**
   * Fetch the wallet's identity public key.
   * @returns 33-byte compressed pubkey, hex-encoded.
   */
  async getPublicKey(args: { identityKey?: boolean } = {}): Promise<string> {
    const body = args.identityKey ? { identityKey: true } : {};
    const resp = await this.post('/getPublicKey', body);
    const data = resp as { publicKey?: string };
    if (!data.publicKey) throw new Error('getPublicKey: no publicKey in response');
    return data.publicKey;
  }

  /**
   * Ask the wallet to fund, sign, and broadcast a set of outputs.
   * The wallet picks UTXOs, adds change, and signs everything.
   */
  async createAction(req: {
    description: string;
    labels?: string[];
    outputs: JamWalletOutput[];
  }): Promise<JamWalletCreateActionResult> {
    const resp = await this.post('/createAction', req) as Record<string, unknown>;

    // Wallet implementations return txid in several spellings — normalise
    const txid =
      (resp.txid as string | undefined) ??
      (resp.tx_hash as string | undefined) ??
      '';

    if (!txid) throw new Error('createAction: no txid in response');
    return { txid, rawTx: resp.rawTx as string | undefined };
  }

  /** Check that the wallet is reachable and authenticated. */
  async isAuthenticated(): Promise<boolean> {
    try {
      await this.post('/isAuthenticated', {});
      return true;
    } catch {
      return false;
    }
  }

  // ── private ─────────────────────────────────────────────────────────────

  private async post(path: string, body: unknown): Promise<unknown> {
    const url = this.baseUrl.replace(/\/$/, '') + path;
    const resp = await fetch(url, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'x-brc-100-originator': this.originator,
      },
      body: JSON.stringify(body),
    });
    if (!resp.ok) {
      const text = await resp.text().catch(() => resp.statusText);
      throw new Error(`wallet ${path} ${resp.status}: ${text}`);
    }
    return resp.json();
  }
}

```
