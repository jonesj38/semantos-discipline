---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/verifier-sidecar/src/server.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.085109+00:00
---

# runtime/verifier-sidecar/src/server.ts

```ts
/**
 * Verifier Sidecar HTTP server entry-point.
 *
 * Closes the library/service gap between D-V1 (which shipped a TS library)
 * and D-V2 (which codified the deployment topology — per-node sidecar
 * process on port 8787 with `GET /healthz`). World Host (D-V3 consumer)
 * reaches this over loopback HTTP.
 *
 * Spec source:  docs/spec/protocol-v0.5.md §9.5 (Verifier Sidecar),
 *               §12.1 (SignedBundle envelope).
 * Topology:     runtime/verifier-sidecar/README.md (D-V2 deployment guide).
 * Conventions:  port 8787, GET /healthz (200 ready / 503 idle), POST /verify.
 *
 * Endpoints:
 *   GET  /healthz   — liveness/readiness probe.
 *                     200 once cert cache + parsers + (optional SPV provider)
 *                     are initialised; 503 before.
 *   POST /verify    — request body JSON: { envelope: RawSignedBundle,
 *                                          capToken?: CapTokenRef }.
 *                     response JSON: { ok: boolean,
 *                                      code?: VerificationErrorCode,
 *                                      message?: string,
 *                                      certId?: string,
 *                                      bca?: string }.
 *                     The `bca` field returns the BCA derived from the
 *                     verified cert's subjectPublicKey (see ./bca.ts and
 *                     §4.3); World Host avoids the re-derivation step.
 *
 * Runtime: Bun.serve. No new third-party runtime deps.
 *
 * Configuration via env (defaults match docker-compose.sidecar.yml):
 *   VERIFIER_SIDECAR_PORT  — listen port. Default 8787.
 *   VERIFIER_SIDECAR_BIND  — bind host. Default 127.0.0.1 (loopback).
 *
 * Canonical term: Verifier Sidecar (glossary id: verifier-sidecar).
 * K invariant: K2 — boundary verification before any state mutation.
 */

import { BrcVerifier } from "./verifier.js";
import { deriveBcaFromPubkey } from "./bca.js";
import type {
  RawSignedBundle,
  CapabilityTokenRef,
  Brc52Certificate,
  BrcVerifierOptions,
  VerificationResult,
} from "./types.js";

// ── Server configuration ────────────────────────────────────────────────────

export interface VerifierSidecarServerOptions {
  /** TCP port. Default `VERIFIER_SIDECAR_PORT` env or 8787. */
  port?: number;
  /** Bind host. Default `VERIFIER_SIDECAR_BIND` env or 127.0.0.1. */
  hostname?: string;
  /** BrcVerifier options forwarded straight through. */
  verifier?: BrcVerifierOptions;
  /**
   * If false, /healthz returns 503 until {@link VerifierSidecarServer.markReady}
   * is called. If true (the default), /healthz returns 200 from start —
   * appropriate for unit-test boots where there's no cert cache to warm.
   */
  readyOnStart?: boolean;
}

/**
 * Default port matches `docker-compose.sidecar.yml` and §9.5's deployment
 * convention. Loopback bind by default — promote to `0.0.0.0` only when
 * the deployment topology explicitly requires it.
 */
export const DEFAULT_PORT = 8787;
export const DEFAULT_BIND = "127.0.0.1";

// ── Verify request shape ────────────────────────────────────────────────────

/**
 * Body of a POST /verify request.
 *
 * The envelope is the raw BRC-100 SignedBundle headers (§12.1). The
 * capToken is optional and triggers Phase 3 SPV checks when present.
 */
export interface VerifyRequestBody {
  envelope: RawSignedBundle;
  capToken?: CapabilityTokenRef;
}

/**
 * Body of a POST /verify response.
 *
 * On success: `{ ok: true, certId, bca }`. The `bca` is the
 * BCA-derived peer identifier (see ./bca.ts). On failure:
 * `{ ok: false, code, message }`.
 */
export interface VerifyResponseBody {
  ok: boolean;
  code?: string;
  message?: string;
  certId?: string;
  bca?: string;
}

// ── Server class ────────────────────────────────────────────────────────────

/**
 * VerifierSidecarServer — wraps a {@link BrcVerifier} in a Bun.serve HTTP
 * surface that honours the D-V2 conventions (port 8787, `GET /healthz`,
 * `POST /verify`).
 *
 * Lifecycle:
 *   const srv = new VerifierSidecarServer({ readyOnStart: false });
 *   srv.start();
 *   // ...warm cert cache, SPV headers, etc...
 *   srv.markReady();
 *   // ...serving traffic...
 *   srv.stop();
 */
export class VerifierSidecarServer {
  private readonly port: number;
  private readonly hostname: string;
  private readonly verifier: BrcVerifier;
  private ready: boolean;
  private server:
    | { stop: (closeActiveConnections?: boolean) => void; port: number }
    | null = null;

  constructor(options: VerifierSidecarServerOptions = {}) {
    this.port =
      options.port ??
      (process.env["VERIFIER_SIDECAR_PORT"]
        ? parseInt(process.env["VERIFIER_SIDECAR_PORT"]!, 10)
        : DEFAULT_PORT);
    this.hostname =
      options.hostname ??
      process.env["VERIFIER_SIDECAR_BIND"] ??
      DEFAULT_BIND;
    this.verifier = new BrcVerifier(options.verifier ?? {});
    this.ready = options.readyOnStart ?? true;
  }

  /** Mark the sidecar ready (flips /healthz from 503 to 200). */
  markReady(): void {
    this.ready = true;
  }

  /** Mark the sidecar idle (flips /healthz from 200 to 503). */
  markIdle(): void {
    this.ready = false;
  }

  /** True if /healthz is currently returning 200. */
  get isReady(): boolean {
    return this.ready;
  }

  /** The port the server is listening on (resolved after start()). */
  get listeningPort(): number | null {
    return this.server ? this.server.port : null;
  }

  /**
   * Start the HTTP server. Idempotent on a started instance.
   *
   * Uses Bun.serve — the `Bun` global is provided by the Bun runtime.
   * In non-Bun environments this throws; the integration test gates
   * appropriately.
   */
  start(): void {
    if (this.server) return;

    // Bun is a global at runtime; cast through unknown to avoid pulling
    // the @types/bun namespace into the sidecar's tsconfig surface.
    const bun = (globalThis as unknown as {
      Bun?: {
        serve: (config: {
          port: number;
          hostname: string;
          fetch: (req: Request) => Promise<Response> | Response;
        }) => { stop: (closeActiveConnections?: boolean) => void; port: number };
      };
    }).Bun;
    if (!bun) {
      throw new Error(
        "VerifierSidecarServer.start() requires Bun (Bun.serve is unavailable).",
      );
    }

    this.server = bun.serve({
      port: this.port,
      hostname: this.hostname,
      fetch: (req) => this.handle(req),
    });
  }

  /** Stop the HTTP server. Idempotent on a stopped instance. */
  stop(): void {
    if (!this.server) return;
    this.server.stop(true);
    this.server = null;
  }

  /**
   * Public for tests so they can drive the request handler without
   * binding a TCP port. Production callers always go through {@link start}.
   */
  async handle(req: Request): Promise<Response> {
    const url = new URL(req.url);

    if (req.method === "GET" && url.pathname === "/healthz") {
      return this.handleHealthz();
    }

    if (req.method === "POST" && url.pathname === "/verify") {
      return this.handleVerify(req);
    }

    return new Response("not found", { status: 404 });
  }

  // ── /healthz ──────────────────────────────────────────────────────────────

  private handleHealthz(): Response {
    if (!this.ready) {
      // Per D-V2 README: 503 until the sidecar is ready so the orchestrator
      // does not route traffic to a sidecar that would fail-spuriously.
      return new Response(
        JSON.stringify({ status: "starting", topology: "per-node" }),
        {
          status: 503,
          headers: { "Content-Type": "application/json" },
        },
      );
    }
    return new Response(
      JSON.stringify({ status: "ok", topology: "per-node" }),
      {
        status: 200,
        headers: { "Content-Type": "application/json" },
      },
    );
  }

  // ── /verify ───────────────────────────────────────────────────────────────

  private async handleVerify(req: Request): Promise<Response> {
    let body: unknown;
    try {
      body = await req.json();
    } catch {
      return verifyErrorResponse(400, {
        ok: false,
        code: "envelope_malformed",
        message: "POST /verify body must be valid JSON",
      });
    }

    if (!body || typeof body !== "object") {
      return verifyErrorResponse(400, {
        ok: false,
        code: "envelope_malformed",
        message: "POST /verify body must be a JSON object",
      });
    }

    const parsed = body as Partial<VerifyRequestBody>;
    if (!parsed.envelope || typeof parsed.envelope !== "object") {
      return verifyErrorResponse(400, {
        ok: false,
        code: "envelope_malformed",
        message: "POST /verify body must contain an `envelope` object",
      });
    }

    let result: VerificationResult;
    try {
      result = await this.verifier.verify(
        parsed.envelope as RawSignedBundle,
        parsed.capToken,
      );
    } catch (err) {
      // BrcVerifier is documented as never-throws on the OK/fail-fast paths;
      // a thrown exception means an unexpected internal error.
      const message =
        err instanceof Error ? err.message : "internal verifier error";
      return verifyErrorResponse(500, {
        ok: false,
        code: "envelope_malformed",
        message: `internal verifier error: ${message}`,
      });
    }

    if (!result.ok) {
      return verifyErrorResponse(200, {
        ok: false,
        code: result.code,
        message: result.message,
      });
    }

    // On success, derive the BCA from the verified cert's subjectPublicKey
    // and return it for World Host to assign to socket state.
    let bca: string | undefined;
    try {
      const cert = JSON.parse(
        (parsed.envelope as RawSignedBundle)["x-brc52-certificate"] ?? "{}",
      ) as Brc52Certificate;
      if (cert.subjectPublicKey) {
        bca = deriveBcaFromPubkey(cert.subjectPublicKey);
      }
    } catch {
      // BCA derivation is best-effort here — verification has already
      // succeeded, so the cert is well-formed; this catch protects against
      // edge-case hex-encoding errors. In production D-A0 supersedes this.
      bca = undefined;
    }

    return verifyOkResponse(200, {
      ok: true,
      certId: result.certId,
      ...(bca !== undefined ? { bca } : {}),
    });
  }
}

// ── Response helpers ────────────────────────────────────────────────────────

function verifyOkResponse(status: number, body: VerifyResponseBody): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

function verifyErrorResponse(
  status: number,
  body: VerifyResponseBody,
): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

// ── CLI entry-point ─────────────────────────────────────────────────────────

/**
 * When this file is run directly (e.g. `bun run runtime/verifier-sidecar/src/server.ts`
 * or via the package's `bin` entry), boot a server and wire SIGINT/SIGTERM
 * to graceful shutdown.
 *
 * The check `import.meta.main` is Bun-specific (true when this module is the
 * entry-point). Guarded so test imports of this file don't accidentally start
 * a server.
 */
if (
  typeof import.meta !== "undefined" &&
  (import.meta as unknown as { main?: boolean }).main === true
) {
  const server = new VerifierSidecarServer({
    // In production, readiness should be flipped after cert cache + SPV
    // headers are warm. For the loopback default we boot ready: there's
    // no remote cert cache to warm, and the BrcVerifier's nonce cache /
    // signature parser are ready synchronously.
    readyOnStart: true,
  });
  server.start();
  // eslint-disable-next-line no-console
  console.log(
    `[verifier-sidecar] listening on http://${process.env["VERIFIER_SIDECAR_BIND"] ?? DEFAULT_BIND}:${server.listeningPort ?? DEFAULT_PORT}`,
  );

  const shutdown = (sig: string) => {
    // eslint-disable-next-line no-console
    console.log(`[verifier-sidecar] received ${sig}, shutting down`);
    server.stop();
    process.exit(0);
  };
  process.on("SIGINT", () => shutdown("SIGINT"));
  process.on("SIGTERM", () => shutdown("SIGTERM"));
}

```
