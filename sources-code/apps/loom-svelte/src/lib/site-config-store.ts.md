---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/loom-svelte/src/lib/site-config-store.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.078553+00:00
---

# apps/loom-svelte/src/lib/site-config-store.ts

```ts
// D-O5.followup-5 — site config helpers for the helm SPA editor view.
//
// Wraps `site config show / set / validate` over the bearer-gated REPL
// endpoint.  The brain-side dispatcher resource is `site_config` (see
// `runtime/semantos-brain/src/resources/site_config_handler.zig`); commands are
// `read` (whole-blob load), `write` (whole-blob save), and `write` with
// `dry_run:true` (validate-only, no disk touch).  Cap-gated on
// `cap.brain.admin` — operator-root surface.
//
// Wire shape — read (`site config show <domain>`):
//   200: { result: '{"domain":"<dom>","json":"<raw site.json>","size":N,
//                    "mtime_unix":<ts>}', exit: "continue" }
//
// Wire shape — write (`site config set <domain> <minified-json>`):
//   200: { result: '{"ok":true,"written_at":<unix-ts>}', exit:
//                    "continue" }
//   400: typed validation_failed for parse / schema / route errors
//
// Wire shape — validate (`site config validate <domain> <minified-json>`):
//   200: { result: '{"ok":true,"dry_run":true}', exit: "continue" }
//   400: same typed errors as write
//
// The REPL splitArgs tokeniser is whitespace-only, so the helm always
// minifies the JSON blob via `JSON.stringify(parsed)` before sending —
// otherwise pasted-with-newlines configs would arrive as N tokens and
// the brain would fail on the second-positional check.

import {
  ReplClient,
  ReplUnauthorizedError,
  ReplValidationError,
} from "./repl-client";

/// Shape returned by `loadSiteConfig` — the raw on-disk JSON plus its
/// metadata.  The editor renders `json` verbatim; `size` + `mtime_unix`
/// are used for staleness signals (e.g. "this file was edited 2m ago
/// in another tab").
export interface LoadedSiteConfig {
  domain: string;
  json: string;
  size: number;
  mtimeUnix: number;
}

/// Reasons `saveSiteConfig` / `validateSiteConfig` can fail.
export type SaveErrorKind =
  | "client_parse_failed"
  | "validation_failed"
  | "not_found"
  | "unauthenticated"
  | "unknown";

export class SiteConfigSaveError extends Error {
  readonly kind: SaveErrorKind;
  readonly hint: string | null;
  constructor(kind: SaveErrorKind, message: string, hint: string | null = null) {
    super(message);
    this.name = "SiteConfigSaveError";
    this.kind = kind;
    this.hint = hint;
  }
}

/// Read `<sites_dir>/<domain>/site.json` via the REPL.  Throws
/// SiteConfigSaveError("not_found") when the brain has no record of
/// `domain`; SiteConfigSaveError("unauthenticated") on 401.
export async function loadSiteConfig(
  client: ReplClient,
  domain: string,
): Promise<LoadedSiteConfig> {
  const cmd = `site config show ${domain}`;
  let resp;
  try {
    resp = await client.send(cmd);
  } catch (e: unknown) {
    if (e instanceof ReplUnauthorizedError) {
      throw new SiteConfigSaveError("unauthenticated", "REPL bearer rejected");
    }
    if (e instanceof ReplValidationError) {
      throw new SiteConfigSaveError("validation_failed", e.message, e.hint);
    }
    throw new SiteConfigSaveError("unknown", e instanceof Error ? e.message : String(e));
  }
  if ("error" in resp) {
    if (resp.error === "not_found") {
      throw new SiteConfigSaveError("not_found", `no site.json for ${domain}`);
    }
    throw new SiteConfigSaveError("unknown", resp.error);
  }

  // The REPL line printed the dispatcher's JSON envelope verbatim,
  // followed by a newline.  Trim and parse.
  const text = resp.result.trim();
  if (!text.startsWith("{")) {
    throw new SiteConfigSaveError(
      "unknown",
      `unexpected REPL response shape: ${text.slice(0, 80)}`,
    );
  }
  let parsed: unknown;
  try {
    parsed = JSON.parse(text);
  } catch (e: unknown) {
    throw new SiteConfigSaveError(
      "unknown",
      `REPL response not valid JSON: ${e instanceof Error ? e.message : String(e)}`,
    );
  }
  const obj = parsed as Record<string, unknown>;
  if (typeof obj.domain !== "string" || typeof obj.json !== "string") {
    throw new SiteConfigSaveError("unknown", "REPL response missing domain/json fields");
  }
  return {
    domain: obj.domain,
    json: obj.json,
    size: typeof obj.size === "number" ? obj.size : obj.json.length,
    mtimeUnix: typeof obj.mtime_unix === "number" ? obj.mtime_unix : 0,
  };
}

/// Atomically replace `<sites_dir>/<domain>/site.json` with the supplied
/// JSON blob.  Validates client-side first (throws
/// SiteConfigSaveError("client_parse_failed") on malformed JSON), then
/// dispatches the brain-side `site_config.write` command which re-
/// validates server-side and writes via write-to-temp + rename.
///
/// Returns the brain's `written_at` unix timestamp on success.
export async function saveSiteConfig(
  client: ReplClient,
  domain: string,
  json: string,
): Promise<{ writtenAt: number }> {
  const minified = clientSideValidateAndMinify(json);
  const cmd = `site config set ${domain} ${minified}`;
  return await sendWriteCommand(client, cmd);
}

/// Brain-side dry-run validation.  Same shape as `saveSiteConfig` but
/// the brain skips the on-disk write and returns `{ok:true,dry_run:
/// true}`.  Use this for the editor's "Validate" button so the
/// operator can confirm a draft parses without committing.
export async function validateSiteConfig(
  client: ReplClient,
  domain: string,
  json: string,
): Promise<{ dryRun: true }> {
  const minified = clientSideValidateAndMinify(json);
  const cmd = `site config validate ${domain} ${minified}`;
  await sendWriteCommand(client, cmd);
  return { dryRun: true };
}

/// Parse + re-stringify the JSON to (a) catch operator typos before
/// burning a network round-trip and (b) produce a whitespace-free
/// blob the REPL splitArgs can carry as a single token.
function clientSideValidateAndMinify(json: string): string {
  let parsed: unknown;
  try {
    parsed = JSON.parse(json);
  } catch (e: unknown) {
    throw new SiteConfigSaveError(
      "client_parse_failed",
      `JSON parse error: ${e instanceof Error ? e.message : String(e)}`,
    );
  }
  return JSON.stringify(parsed);
}

async function sendWriteCommand(
  client: ReplClient,
  cmd: string,
): Promise<{ writtenAt: number }> {
  let resp;
  try {
    resp = await client.send(cmd);
  } catch (e: unknown) {
    if (e instanceof ReplUnauthorizedError) {
      throw new SiteConfigSaveError("unauthenticated", "REPL bearer rejected");
    }
    if (e instanceof ReplValidationError) {
      throw new SiteConfigSaveError("validation_failed", e.message, e.hint);
    }
    throw new SiteConfigSaveError("unknown", e instanceof Error ? e.message : String(e));
  }
  if ("error" in resp) {
    if (resp.error === "validation_failed") {
      throw new SiteConfigSaveError(
        "validation_failed",
        "brain rejected the config — see hint",
        null,
      );
    }
    if (resp.error === "not_found") {
      throw new SiteConfigSaveError("not_found", "domain has no <sites_dir> entry");
    }
    throw new SiteConfigSaveError("unknown", resp.error);
  }
  // Parse the JSON envelope to surface written_at.  Defensive default
  // when the brain returns a dry-run response (which also satisfies
  // ok=true but has no written_at).
  const text = resp.result.trim();
  if (text.startsWith("{")) {
    try {
      const obj = JSON.parse(text) as Record<string, unknown>;
      if (typeof obj.written_at === "number") return { writtenAt: obj.written_at };
    } catch {
      // fall through to default
    }
  }
  return { writtenAt: 0 };
}

/// Best-effort read of the `domain` field out of a (presumably valid)
/// site config JSON blob.  Used by the editor view's side panel for
/// the "currently editing" header.  Returns null when the parse fails
/// or the field is absent.
export function sniffDomain(json: string): string | null {
  try {
    const parsed = JSON.parse(json) as Record<string, unknown>;
    const site = parsed.site as Record<string, unknown> | undefined;
    if (site && typeof site.domain === "string") return site.domain;
  } catch {
    // ignore
  }
  return null;
}

/// Best-effort summary of the routes declared in a site config.  Used
/// by the editor view's side panel.
export interface RouteSummary {
  path: string;
  type: string;
  auth: string;
}

export function sniffRoutes(json: string): RouteSummary[] {
  try {
    const parsed = JSON.parse(json) as Record<string, unknown>;
    const routes = parsed.routes as Record<string, unknown> | undefined;
    if (!routes) return [];
    return Object.entries(routes).map(([path, raw]): RouteSummary => {
      const r = raw as Record<string, unknown>;
      return {
        path,
        type: typeof r.type === "string" ? r.type : "?",
        auth:
          typeof r.auth === "string"
            ? r.auth
            : r.public === true
              ? "public"
              : "public",
      };
    });
  } catch {
    return [];
  }
}

```
