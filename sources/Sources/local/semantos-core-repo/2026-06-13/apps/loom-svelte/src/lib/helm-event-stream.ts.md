---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/loom-svelte/src/lib/helm-event-stream.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.083686+00:00
---

# apps/loom-svelte/src/lib/helm-event-stream.ts

```ts
// D-O5.followup-4 — WSS live-tick stream client (loom-svelte side).
//
// Mirrors `apps/oddjobz-mobile/lib/src/repl/helm_event_stream.dart`.
// Wraps the browser `WebSocket` with bearer auth + auto-reconnect +
// JSON-RPC subscribe/event parsing.  The brain side serves the WSS
// endpoint at `/api/v1/wallet`; the helm SPA is served from the
// same origin so the browser handshake just appends `?bearer=<hex>`.
//
// Wire shape (server→client notification):
//
//     {"jsonrpc":"2.0","method":"helm.event",
//      "params":{"type":"job.transitioned",
//                "data":{...}}}
//
// Reconnect: exponential backoff (1s, 2s, 4s, 8s, max 30s); we keep
// retrying until `disconnect()` is called.

export type HelmEventStreamState =
  | "disconnected"
  | "connecting"
  | "subscribed"
  | "reconnecting";

/// One event delivered by the brain's helm event broker.  The
/// substrate is type-agnostic — every emitter publishes a `type`
/// token (e.g. "job.transitioned") + an opaque `data` map; the helm
/// dispatches on `type`.
export interface HelmEvent {
  /// Stable event-type token, e.g. "job.transitioned".
  type: string;
  /// Decoded payload object.
  data: Record<string, unknown>;
}

/// Factory for producing the underlying socket.  Production passes
/// `(url) => new WebSocket(url)`; tests inject a fake that exposes
/// the same `addEventListener` / `send` / `close` surface.
export interface HelmSocket {
  send: (data: string) => void;
  close: () => void;
  addEventListener: (
    event: "open" | "message" | "close" | "error",
    handler: (ev: any) => void,
  ) => void;
}

export type HelmSocketFactory = (url: string) => HelmSocket;

const DEFAULT_BACKOFF_MS = [1_000, 2_000, 4_000, 8_000, 16_000, 30_000];

export interface HelmEventStreamOptions {
  /// `wss://<host>:<port>/api/v1/wallet`-shaped URL.  Schemes other
  /// than wss/ws pass through verbatim.
  wssUrl: string;
  /// 64-hex bearer from the helm session.  Appended as
  /// `?bearer=<hex>` (the Semantos Brain side accepts that as a query-string
  /// fallback for browser clients per
  /// `runtime/semantos-brain/src/wss_wallet.zig::parseBearerQuery`).
  bearer: string;
  /// Topics to subscribe to.  Validated against the Semantos Brain-side topic
  /// list: jobs / customers / visits / quotes / invoices /
  /// attachments.
  topics: string[];
  /// Backoff schedule — defaults to 1s/2s/4s/8s/16s/30s.  Tests
  /// override with shorter values.
  reconnectBackoff?: number[];
  /// Test seam — production passes `new WebSocket(...)`.
  socketFactory?: HelmSocketFactory;
  /// Optional event hook — fires on every parsed `helm.event`.  The
  /// returned `unsubscribe` function may also be used by the
  /// returned `events` callback registry.  When omitted, callers
  /// register listeners via [HelmEventStream.subscribe].
  onEvent?: (event: HelmEvent) => void;
  /// Optional state hook.
  onState?: (state: HelmEventStreamState) => void;
}

export class HelmEventStream {
  private readonly opts: HelmEventStreamOptions;
  private readonly socketFactory: HelmSocketFactory;
  private readonly backoffMs: number[];
  private socket: HelmSocket | null = null;
  private state: HelmEventStreamState = "disconnected";
  private backoffIndex = 0;
  private reconnectTimer: ReturnType<typeof setTimeout> | null = null;
  private stopped = false;
  private subscribeId = 1;
  private readonly eventListeners: Set<(event: HelmEvent) => void> =
    new Set();
  private readonly stateListeners: Set<(state: HelmEventStreamState) => void> =
    new Set();

  constructor(opts: HelmEventStreamOptions) {
    this.opts = opts;
    this.socketFactory =
      opts.socketFactory ?? ((url) => new WebSocket(url) as unknown as HelmSocket);
    this.backoffMs = opts.reconnectBackoff ?? DEFAULT_BACKOFF_MS;
    if (opts.onEvent) this.eventListeners.add(opts.onEvent);
    if (opts.onState) this.stateListeners.add(opts.onState);
  }

  /// Subscribe to incoming events.  Returns an unsubscribe function.
  /// Multiple listeners are supported — each receives every event.
  onEvent(listener: (event: HelmEvent) => void): () => void {
    this.eventListeners.add(listener);
    return () => this.eventListeners.delete(listener);
  }

  /// Subscribe to lifecycle state transitions.
  onState(listener: (state: HelmEventStreamState) => void): () => void {
    this.stateListeners.add(listener);
    return () => this.stateListeners.delete(listener);
  }

  /// Synchronous snapshot of the lifecycle state.  Components that
  /// want a reactive view should bind to [onState].
  get currentState(): HelmEventStreamState {
    return this.state;
  }

  /// Open the connection.  Idempotent — calling twice while already
  /// connected is a no-op.
  connect(): void {
    if (this.state === "connecting" || this.state === "subscribed") return;
    this.stopped = false;
    this.openOnce();
  }

  /// Close the connection + stop the reconnect loop.
  disconnect(): void {
    this.stopped = true;
    if (this.reconnectTimer !== null) {
      clearTimeout(this.reconnectTimer);
      this.reconnectTimer = null;
    }
    if (this.socket !== null) {
      try {
        this.socket.close();
      } catch (_) {
        // Already closed — ignore.
      }
      this.socket = null;
    }
    this.setState("disconnected");
  }

  // ─── Internals ─────────────────────────────────────────────────────

  private openOnce(): void {
    this.setState("connecting");
    let url = this.opts.wssUrl;
    const sep = url.includes("?") ? "&" : "?";
    url = `${url}${sep}bearer=${encodeURIComponent(this.opts.bearer)}`;
    let socket: HelmSocket;
    try {
      socket = this.socketFactory(url);
    } catch (_) {
      this.scheduleReconnect();
      return;
    }
    this.socket = socket;

    socket.addEventListener("open", () => {
      this.subscribe();
    });
    socket.addEventListener("message", (ev: MessageEvent | { data: unknown }) => {
      this.onFrame((ev as { data: unknown }).data);
    });
    socket.addEventListener("close", () => {
      this.scheduleReconnect();
    });
    socket.addEventListener("error", () => {
      // The browser fires error THEN close; the close handler does
      // the reconnect work.
    });
  }

  private subscribe(): void {
    const id = this.subscribeId++;
    const body = JSON.stringify({
      jsonrpc: "2.0",
      id,
      method: "helm.subscribe",
      params: { topics: this.opts.topics },
    });
    this.socket?.send(body);
  }

  private onFrame(raw: unknown): void {
    let text: string;
    if (typeof raw === "string") {
      text = raw;
    } else if (raw instanceof ArrayBuffer) {
      text = new TextDecoder().decode(raw);
    } else if (raw instanceof Blob) {
      // Browsers may deliver Blob frames.  Async decode — drop on
      // failure.
      raw
        .text()
        .then((t) => this.onFrame(t))
        .catch(() => {});
      return;
    } else {
      return;
    }
    let parsed: unknown;
    try {
      parsed = JSON.parse(text);
    } catch (_) {
      return;
    }
    if (parsed === null || typeof parsed !== "object") return;
    const obj = parsed as Record<string, unknown>;
    const method = obj["method"];
    if (method === undefined && typeof obj["result"] === "object" && obj["result"] !== null) {
      const result = obj["result"] as Record<string, unknown>;
      if (result["subscribed"] === true) {
        this.backoffIndex = 0;
        this.setState("subscribed");
      }
      return;
    }
    if (method === "helm.event") {
      const params = obj["params"];
      if (params === null || typeof params !== "object") return;
      const p = params as Record<string, unknown>;
      const type = p["type"];
      if (typeof type !== "string") return;
      const data = p["data"];
      const dataObj =
        data !== null && typeof data === "object"
          ? (data as Record<string, unknown>)
          : {};
      const event: HelmEvent = { type, data: dataObj };
      for (const listener of this.eventListeners) {
        try {
          listener(event);
        } catch (_) {
          // Listener exceptions don't affect other listeners.
        }
      }
    }
  }

  private scheduleReconnect(): void {
    this.socket = null;
    if (this.stopped) {
      this.setState("disconnected");
      return;
    }
    this.setState("reconnecting");
    const idx = Math.min(this.backoffIndex, this.backoffMs.length - 1);
    const wait = this.backoffMs[idx];
    if (this.backoffIndex < this.backoffMs.length - 1) this.backoffIndex += 1;
    this.reconnectTimer = setTimeout(() => {
      if (this.stopped) return;
      this.openOnce();
    }, wait);
  }

  private setState(s: HelmEventStreamState): void {
    if (this.state === s) return;
    this.state = s;
    for (const l of this.stateListeners) {
      try {
        l(s);
      } catch (_) {
        // Listener exceptions don't affect other listeners.
      }
    }
  }
}

```
