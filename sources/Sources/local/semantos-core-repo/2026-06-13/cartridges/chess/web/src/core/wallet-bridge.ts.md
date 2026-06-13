---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/chess/web/src/core/wallet-bridge.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.430360+00:00
---

# cartridges/chess/web/src/core/wallet-bridge.ts

```ts
/**
 * WalletBridge — client wrapper for the wallet.semantos.me/bridge iframe.
 *
 * The wallet-headers bundle (`cartridges/wallet-headers/brain/dist/`)
 * serves a hidden iframe whose `bridge.ts` listens for a postMessage
 * handshake, swaps a MessageChannel port, then dispatches BRC-100-
 * shaped envelopes through that port. World-apps embed the iframe and
 * route auth-needing calls through it so the bearer (or, eventually, a
 * BRC-100 signature) never leaves the wallet's process.
 *
 * Reference: cartridges/wallet-headers/brain/src/bridge.ts +
 * docs/design/WALLET-TIER-CUSTODY.md §10.1 + WALLET-TIER-CUSTODY.md §4
 * (dispatcher).
 *
 * Usage:
 *
 *   const wallet = new WalletBridge('https://wallet.semantos.me');
 *   await wallet.connect();
 *   const pk = await wallet.call('getPublicKey', {});
 */

export interface BrcEnvelope {
  identityKey: string;
  nonce: string;
  timestamp: number;
  signature: string;
  body: {
    method: string;
    params: Record<string, unknown>;
  };
}

interface PendingRpc {
  resolve: (value: unknown) => void;
  reject: (err: Error) => void;
  timer: ReturnType<typeof setTimeout>;
}

export class WalletBridge {
  private iframe: HTMLIFrameElement | null = null;
  private port: MessagePort | null = null;
  private nextId = 1;
  private pending = new Map<string, PendingRpc>();
  private status: 'idle' | 'connecting' | 'open' | 'error' = 'idle';
  private readonly walletOrigin: string;
  private statusListeners: ((s: typeof this.status) => void)[] = [];

  constructor(
    walletUrl: string,
    private readonly opts: { timeoutMs?: number } = {},
  ) {
    // Normalise to the bare origin — the iframe loads /index.html which
    // is the bridge entry point per cartridges/wallet-headers/brain/dist/.
    const u = new URL(walletUrl);
    this.walletOrigin = u.origin;
  }

  /** Subscribe to status transitions. */
  onStatus(cb: (s: 'idle' | 'connecting' | 'open' | 'error') => void): () => void {
    this.statusListeners.push(cb);
    cb(this.status);
    return () => {
      this.statusListeners = this.statusListeners.filter((c) => c !== cb);
    };
  }

  /** Inject the hidden iframe + swap a MessageChannel with it. */
  connect(): Promise<void> {
    if (this.status === 'open') return Promise.resolve();
    this.setStatus('connecting');

    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        this.setStatus('error');
        reject(new Error('wallet handshake timed out'));
      }, this.opts.timeoutMs ?? 10_000);

      const iframe = document.createElement('iframe');
      iframe.src = `${this.walletOrigin}/`;
      iframe.style.display = 'none';
      iframe.setAttribute('aria-hidden', 'true');
      iframe.setAttribute('title', 'semantos wallet bridge');
      iframe.allow = 'publickey-credentials-get *';
      document.body.appendChild(iframe);
      this.iframe = iframe;

      iframe.addEventListener('load', () => {
        const channel = new MessageChannel();
        channel.port1.onmessage = (ev) => this.onPortMessage(ev);
        // The bridge.ts handler swaps port for the inbound port; we keep
        // port1 and hand port2 to the iframe.
        iframe.contentWindow?.postMessage(
          { type: 'handshake', port: channel.port2 },
          this.walletOrigin,
          [channel.port2],
        );
        this.port = channel.port1;
        clearTimeout(timer);
        this.setStatus('open');
        resolve();
      });

      iframe.addEventListener('error', () => {
        clearTimeout(timer);
        this.setStatus('error');
        reject(new Error('wallet iframe failed to load'));
      });
    });
  }

  /**
   * Send a BRC-100 method call through the channel. The envelope
   * signature is constructed inside the wallet, not here — the SPA
   * holds no identity key. We send the body shape and let the bridge
   * wrap it.
   */
  call(method: string, params: Record<string, unknown> = {}): Promise<unknown> {
    if (this.status !== 'open' || !this.port) {
      return Promise.reject(new Error('wallet not connected'));
    }
    const id = String(this.nextId++);
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        this.pending.delete(id);
        reject(new Error(`wallet rpc timeout: ${method}`));
      }, this.opts.timeoutMs ?? 30_000);
      this.pending.set(id, { resolve, reject, timer });
      this.port!.postMessage({ id, type: 'rpc', body: { method, params } });
    });
  }

  /** Tear down — remove the iframe + drop pending callers. */
  disconnect(): void {
    if (this.iframe?.parentNode) this.iframe.parentNode.removeChild(this.iframe);
    this.iframe = null;
    this.port = null;
    for (const [, p] of this.pending) {
      clearTimeout(p.timer);
      p.reject(new Error('wallet bridge disconnected'));
    }
    this.pending.clear();
    this.setStatus('idle');
  }

  private onPortMessage(ev: MessageEvent): void {
    const msg = ev.data as { id?: string; result?: unknown; error?: { code?: number; message?: string } };
    if (!msg || typeof msg.id !== 'string') return;
    const pending = this.pending.get(msg.id);
    if (!pending) return;
    clearTimeout(pending.timer);
    this.pending.delete(msg.id);
    if (msg.error) {
      pending.reject(new Error(`wallet rpc error ${msg.error.code ?? '?'}: ${msg.error.message ?? 'unknown'}`));
    } else {
      pending.resolve(msg.result);
    }
  }

  private setStatus(s: typeof this.status): void {
    this.status = s;
    for (const cb of this.statusListeners) cb(s);
  }
}

/** Resolve the wallet origin from build-time env or runtime override. */
export function defaultWalletOrigin(): string {
  if (typeof localStorage !== 'undefined') {
    const override = localStorage.getItem('chess.walletOrigin');
    if (override) return override;
  }
  const fromEnv = (import.meta as ImportMeta & { env?: Record<string, string> }).env?.VITE_WALLET_ORIGIN;
  if (fromEnv) return fromEnv;
  return 'https://wallet.semantos.me';
}

```
