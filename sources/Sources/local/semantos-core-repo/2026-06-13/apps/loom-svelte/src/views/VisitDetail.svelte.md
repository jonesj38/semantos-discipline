---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/loom-svelte/src/views/VisitDetail.svelte
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.072368+00:00
---

# apps/loom-svelte/src/views/VisitDetail.svelte

```svelte
<script lang="ts" module>
  // D-O4.followup-2 — Visit detail view with FSM action buttons.
  //
  // Mirrors `JobDetail.svelte`'s shape exactly for the §O4 Visit FSM.
  // Action buttons key off the current status:
  //   scheduled     → Start (service)   |  Cancel (operator)
  //   in_progress   → Complete          |  Cancel
  //   completed     → (no actions — terminal)
  //   cancelled     → (no actions — terminal)
  //
  // The brain REPL `start visit <id>` / `complete visit <id>` / `cancel
  // visit <id>` verbs (runtime/semantos-brain/src/repl.zig) plumb through to the
  // dispatcher's `visits.transition` cmd, which returns one of three
  // JSON shapes (mirror of jobs.transition):
  //   • Bare Visit   — transition applied
  //   • {status: "already_in_state", visit: {...}}  — idempotent retry
  //   • {error, from, to, cap_required}             — typed FSM rejection

  export type Visit = {
    id: string;
    job_id: string;
    visit_type: string;
    status: string;
    notes: string;
    actual_start: string;
    outcome: string;
    created_at: string;
    updated_at: string;
  };

  export type VisitTransitionResult =
    | { kind: "success"; visit: Visit }
    | { kind: "already_in_state"; visit: Visit }
    | { kind: "error"; error: string; from: string; to: string; cap_required: string | null };

  export function parseVisitTransitionResult(text: string): VisitTransitionResult {
    const trimmed = text.trim();
    if (trimmed.length === 0 || !trimmed.startsWith("{")) {
      return { kind: "error", error: "parse_error", from: "", to: "", cap_required: null };
    }
    try {
      const parsed = JSON.parse(trimmed);
      if (parsed && typeof parsed === "object") {
        if (parsed.status === "already_in_state" && parsed.visit) {
          return { kind: "already_in_state", visit: visitFromBody(parsed.visit) };
        }
        if (typeof parsed.error === "string") {
          return {
            kind: "error",
            error: parsed.error,
            from: String(parsed.from ?? ""),
            to: String(parsed.to ?? ""),
            cap_required: typeof parsed.cap_required === "string"
              ? parsed.cap_required
              : null,
          };
        }
        if (parsed.id && parsed.status) {
          return { kind: "success", visit: visitFromBody(parsed) };
        }
      }
    } catch {
      // fall through to parse_error.
    }
    return { kind: "error", error: "parse_error", from: "", to: "", cap_required: null };
  }

  function visitFromBody(row: Record<string, unknown>): Visit {
    return {
      id: String(row.id ?? ""),
      job_id: String(row.job_id ?? ""),
      visit_type: String(row.visit_type ?? ""),
      status: String(row.status ?? ""),
      notes: String(row.notes ?? ""),
      actual_start: String(row.actual_start ?? ""),
      outcome: String(row.outcome ?? ""),
      created_at: String(row.created_at ?? ""),
      updated_at: String(row.updated_at ?? ""),
    };
  }

  /// State → operator-readable REPL verb map.  Multiple verbs per
  /// state surface (scheduled has both Start and Cancel).  `null`
  /// means no transitions are offered for that state.
  export type VisitAction = {
    label: string;
    verb: string;
  };

  export function actionsForStatus(status: string): readonly VisitAction[] {
    switch (status) {
      case "scheduled":
        return [
          { label: "Start", verb: "start visit" },
          { label: "Cancel", verb: "cancel visit" },
        ];
      case "in_progress":
        return [
          { label: "Complete", verb: "complete visit" },
          { label: "Cancel", verb: "cancel visit" },
        ];
      case "completed":
      case "cancelled":
        return [];
      default:
        return [];
    }
  }

  // D-O5m.followup-8 substrate — Attachments view-shape + parser.
  // Read-only metadata list shown under VisitDetail.  Mirrors the
  // dispatcher's `attachments.find` JSON shape.  Producer side
  // (mobile camera capture + binary blob upload) ships in the next
  // PR; this PR ships only the read substrate.
  export type Attachment = {
    id: string;
    visit_id: string;
    kind: string;
    content_hash: string;
    content_size: number;
    mime_type: string;
    captured_at: string;
    captured_by_cert_id: string;
    caption: string;
    created_at: string;
  };

  export function parseAttachments(text: string): Attachment[] {
    const trimmed = text.trim();
    if (trimmed.length === 0) return [];
    if (!(trimmed.startsWith("[") || trimmed.startsWith("{"))) return [];
    try {
      const parsed = JSON.parse(trimmed);
      if (Array.isArray(parsed)) {
        return parsed
          .filter((row): row is Record<string, unknown> =>
            row !== null && typeof row === "object",
          )
          .map(attachmentFromBody);
      }
    } catch {
      // fall through to empty.
    }
    return [];
  }

  function attachmentFromBody(row: Record<string, unknown>): Attachment {
    return {
      id: String(row.id ?? ""),
      visit_id: String(row.visit_id ?? ""),
      kind: String(row.kind ?? ""),
      content_hash: String(row.content_hash ?? ""),
      content_size: typeof row.content_size === "number"
        ? row.content_size
        : Number(row.content_size ?? 0),
      mime_type: String(row.mime_type ?? ""),
      captured_at: String(row.captured_at ?? ""),
      captured_by_cert_id: String(row.captured_by_cert_id ?? ""),
      caption: String(row.caption ?? ""),
      created_at: String(row.created_at ?? ""),
    };
  }

  /// Format a byte count as a short human-readable label for the
  /// metadata row ("2.5 MB", "180 KB", "64 B").
  export function formatBytes(bytes: number): string {
    if (bytes < 1024) return `${bytes} B`;
    if (bytes < 1024 * 1024) return `${Math.round(bytes / 1024)} KB`;
    if (bytes < 1024 * 1024 * 1024) return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
    return `${(bytes / (1024 * 1024 * 1024)).toFixed(1)} GB`;
  }
</script>

<script lang="ts">
  import { onMount } from "svelte";
  import { ReplClient, ReplUnauthorizedError } from "../lib/repl-client";
  import { clearAuth } from "../lib/auth";
  import { visitsTick } from "../lib/visits-store";
  import { attachmentsTick } from "../lib/attachments-store";

  let {
    client = new ReplClient(),
    visit: initialVisit,
  }: {
    client?: ReplClient;
    visit: Visit;
  } = $props();

  let visit = $state<Visit>(initialVisit);
  let busy = $state(false);
  let banner = $state<{ kind: "ok" | "warn" | "err"; text: string } | null>(null);
  let unauthenticated = $state(false);

  // D-O5m.followup-8 substrate — attachments cache for the
  // "Attachments" section.  Fetched on mount via the typed
  // `attachments.find --visit-id <id>` REPL verb.
  let attachments = $state<Attachment[]>([]);
  let attachmentsLoaded = $state(false);
  let attachmentsError = $state<string | null>(null);

  // D-O5m.followup-8 capture+upload — id → object-URL cache for
  // bearer-gated thumbnail fetches.  Each photo Attachment fetches
  // its blob via `client.fetchBlob` and stores the resulting object
  // URL here.  URLs are revoked on cleanup to release the underlying
  // Blob.
  let thumbnailUrls = $state<Record<string, string>>({});
  let lightboxUrl = $state<string | null>(null);

  // D-O5m.followup-8 GPS + voice memo adapters — id → object-URL
  // cache for voice_memo blobs.  Same lifecycle as thumbnailUrls;
  // the <audio> element streams from these object URLs.
  let voiceUrls = $state<Record<string, string>>({});
  // id → decoded GPS pin payload.  Populated by hydrateGpsPins from
  // the JSON blobs; the UI renders the lat/lng caption inline.
  let gpsPins = $state<Record<string, { lat: number; lng: number; accuracy_m?: number; captured_at: string }>>({});

  async function fetchAttachments() {
    try {
      const resp = await client.send(`find attachments --visit-id ${visit.id}`);
      if ("error" in resp) {
        attachmentsError = resp.error;
        return;
      }
      attachments = parseAttachments(resp.result);
      attachmentsLoaded = true;
      void hydrateThumbnails();
    } catch (e: unknown) {
      if (e instanceof ReplUnauthorizedError) {
        unauthenticated = true;
        clearAuth();
        return;
      }
      attachmentsError = e instanceof Error ? e.message : String(e);
    }
  }

  async function hydrateThumbnails() {
    // Prefetch each Attachment's blob via the bearer-gated
    // /api/v1/attachments/<id>/blob endpoint.  Per-kind handling:
    //   - photo      → object URL → <img src>
    //   - voice_memo → object URL → <audio src>
    //   - gps_pin    → fetch JSON → decode → {lat, lng, accuracy_m}
    //   - file_other → object URL → <a href download>
    // Errors are non-fatal — rows fall back to the icon placeholder.
    for (const a of attachments) {
      try {
        if (a.kind === "photo" || a.kind === "voice_memo" || a.kind === "file_other") {
          const cache = a.kind === "photo"
            ? thumbnailUrls
            : a.kind === "voice_memo"
              ? voiceUrls
              : thumbnailUrls;
          if (cache[a.id]) continue;
          const url = await client.fetchBlob(`/api/v1/attachments/${a.id}/blob`);
          if (a.kind === "voice_memo") {
            voiceUrls = { ...voiceUrls, [a.id]: url };
          } else {
            thumbnailUrls = { ...thumbnailUrls, [a.id]: url };
          }
        } else if (a.kind === "gps_pin") {
          if (gpsPins[a.id]) continue;
          // For GPS pins we need the decoded JSON, not an object URL.
          // Fetch via fetchBlob (which returns an object URL pointing
          // at the bytes), then read the bytes back through fetch().
          const objectUrl = await client.fetchBlob(`/api/v1/attachments/${a.id}/blob`);
          try {
            const r = await fetch(objectUrl);
            const text = await r.text();
            const decoded = JSON.parse(text);
            if (
              typeof decoded?.lat === "number" &&
              typeof decoded?.lng === "number" &&
              typeof decoded?.captured_at === "string"
            ) {
              gpsPins = {
                ...gpsPins,
                [a.id]: {
                  lat: decoded.lat,
                  lng: decoded.lng,
                  accuracy_m: typeof decoded.accuracy_m === "number" ? decoded.accuracy_m : undefined,
                  captured_at: decoded.captured_at,
                },
              };
            }
          } finally {
            URL.revokeObjectURL(objectUrl);
          }
        }
      } catch (e: unknown) {
        if (e instanceof ReplUnauthorizedError) {
          unauthenticated = true;
          clearAuth();
          return;
        }
        // Non-fatal — leave the row as icon-only.
      }
    }
  }

  // Kick off the fetch on mount.  No top-level await — Svelte runes
  // boundary doesn't accept it, so we fire-and-forget and re-render
  // when the state lands.
  $effect(() => {
    void fetchAttachments();
    return () => {
      // Clean up any prefetched object URLs (photos + voice memos +
      // file_other download URLs).
      for (const url of Object.values(thumbnailUrls)) {
        URL.revokeObjectURL(url);
      }
      for (const url of Object.values(voiceUrls)) {
        URL.revokeObjectURL(url);
      }
    };
  });

  /// D-O5.followup-4 — re-fetch the displayed visit on a `visit.*`
  /// event tick.  Mirrors QuoteDetail.svelte / InvoiceDetail.svelte.
  async function refetchVisit() {
    try {
      const resp = await client.send(`find visit ${visit.id}`);
      if ("error" in resp) return;
      const trimmed = resp.result.trim();
      if (!trimmed.startsWith("{")) return;
      const parsed = JSON.parse(trimmed);
      if (parsed && typeof parsed === "object" && parsed.id) {
        visit = visitFromBody(parsed as Record<string, unknown>);
      }
    } catch (e: unknown) {
      if (e instanceof ReplUnauthorizedError) {
        unauthenticated = true;
        clearAuth();
      }
      // Non-fatal otherwise.
    }
  }

  onMount(() => {
    // D-O5.followup-4 — re-fetch the visit on `visit.*` ticks and
    // the attachments slice on `attachment.created` ticks.  Each
    // store's subscriber fires once on subscription with the
    // current value; ignore that very first emission and act on
    // every subsequent change (mirrors JobList.svelte).
    let visitFirst: number | null = null;
    const unsubVisit = visitsTick.subscribe((n) => {
      if (visitFirst === null) {
        visitFirst = n;
        return;
      }
      void refetchVisit();
    });
    let attachFirst: number | null = null;
    const unsubAttach = attachmentsTick.subscribe((n) => {
      if (attachFirst === null) {
        attachFirst = n;
        return;
      }
      void fetchAttachments();
    });
    return () => {
      unsubVisit();
      unsubAttach();
    };
  });

  async function runAction(action: VisitAction) {
    busy = true;
    banner = null;
    try {
      const resp = await client.send(`${action.verb} ${visit.id}`);
      if ("error" in resp) {
        banner = { kind: "err", text: `${action.label} failed: ${resp.error}` };
        return;
      }
      const r = parseVisitTransitionResult(resp.result);
      if (r.kind === "success") {
        visit = r.visit;
        banner = { kind: "ok", text: `${action.label}: ${visit.status}` };
      } else if (r.kind === "already_in_state") {
        visit = r.visit;
        banner = { kind: "warn", text: `${action.label}: already ${visit.status}` };
      } else {
        const detail = r.error === "wrong_cap" && r.cap_required
          ? `requires ${r.cap_required}`
          : r.error;
        banner = { kind: "err", text: `${action.label} failed: ${detail}` };
      }
    } catch (e: unknown) {
      if (e instanceof ReplUnauthorizedError) {
        unauthenticated = true;
        clearAuth();
        return;
      }
      banner = { kind: "err", text: e instanceof Error ? e.message : String(e) };
    } finally {
      busy = false;
    }
  }

  let actions = $derived(actionsForStatus(visit.status));
</script>

<section class="visit-detail">
  <header>
    <h2>Visit <code>{visit.id}</code></h2>
    <span class="status status-{visit.status}">{visit.status}</span>
  </header>

  {#if unauthenticated}
    <p class="auth-needed">
      Session expired. <a href="/helm/">Sign in</a> to continue.
    </p>
  {:else}
    <dl>
      <dt>Visit ID</dt><dd><code>{visit.id}</code></dd>
      <dt>Job</dt><dd><code>{visit.job_id}</code></dd>
      <dt>Type</dt><dd>{visit.visit_type}</dd>
      <dt>Status</dt><dd>{visit.status}</dd>
      {#if visit.actual_start}
        <dt>Started</dt><dd>{visit.actual_start}</dd>
      {/if}
      {#if visit.outcome}
        <dt>Outcome</dt><dd>{visit.outcome}</dd>
      {/if}
      {#if visit.notes}
        <dt>Notes</dt><dd>{visit.notes}</dd>
      {/if}
      <dt>Created</dt><dd>{visit.created_at}</dd>
      <dt>Updated</dt><dd>{visit.updated_at}</dd>
    </dl>

    {#if actions.length > 0}
      <div class="actions">
        {#each actions as a (a.verb)}
          <button onclick={() => runAction(a)} disabled={busy}>
            {busy ? "Working…" : a.label}
          </button>
        {/each}
      </div>
    {:else}
      <p class="terminal">Visit is {visit.status}; no further actions.</p>
    {/if}

    {#if banner}
      <p class="banner banner-{banner.kind}">{banner.text}</p>
    {/if}

    <section class="attachments">
      <h3>Attachments</h3>
      {#if attachmentsError}
        <p class="banner banner-err">Failed to load attachments: {attachmentsError}</p>
      {:else if !attachmentsLoaded}
        <p class="muted">Loading…</p>
      {:else if attachments.length === 0}
        <p class="muted">No attachments yet — capture from this site coming soon.</p>
      {:else}
        <ul class="attachments-list">
          {#each attachments as a (a.id)}
            <li>
              {#if a.kind === "photo" && thumbnailUrls[a.id]}
                <button
                  type="button"
                  class="att-thumb"
                  onclick={() => (lightboxUrl = thumbnailUrls[a.id])}
                  aria-label="View photo {a.id}"
                >
                  <img src={thumbnailUrls[a.id]} alt={`Attachment ${a.id}`} loading="lazy" />
                </button>
              {:else if a.kind === "voice_memo" && voiceUrls[a.id]}
                <span class="att-icon att-icon-voice_memo" aria-label="Voice memo">🎙</span>
              {:else if a.kind === "gps_pin"}
                <span class="att-icon att-icon-gps_pin" aria-label="GPS pin">📍</span>
              {:else}
                <span class="att-icon att-icon-{a.kind}">
                  {a.kind === "voice_memo" ? "🎙" : a.kind === "gps_pin" ? "📍" : a.kind === "photo" ? "📷" : "📎"}
                </span>
              {/if}
              <span class="att-kind">{a.kind}</span>
              <span class="att-time">{a.captured_at}</span>
              <span class="att-size">{formatBytes(a.content_size)}</span>
              {#if a.caption}<span class="att-caption">{a.caption}</span>{/if}
              {#if a.kind === "voice_memo" && voiceUrls[a.id]}
                <audio class="att-audio" controls src={voiceUrls[a.id]} preload="metadata">
                  <track kind="captions" />
                </audio>
              {/if}
              {#if a.kind === "gps_pin" && gpsPins[a.id]}
                <span class="att-gps">
                  Lat: {gpsPins[a.id].lat.toFixed(4)}, Lng: {gpsPins[a.id].lng.toFixed(4)}{#if gpsPins[a.id].accuracy_m !== undefined}, ±{Math.round(gpsPins[a.id].accuracy_m as number)} m{/if}
                  &nbsp;·&nbsp;
                  <a
                    href={`https://www.google.com/maps?q=${gpsPins[a.id].lat},${gpsPins[a.id].lng}`}
                    target="_blank"
                    rel="noopener noreferrer"
                  >View on map</a>
                </span>
              {/if}
              {#if a.kind === "file_other" && thumbnailUrls[a.id]}
                <a class="att-download" href={thumbnailUrls[a.id]} download={`${a.id}-${a.content_hash.slice(0, 8)}`}>Download</a>
              {/if}
            </li>
          {/each}
        </ul>
      {/if}
    </section>

    {#if lightboxUrl}
      <div
        class="lightbox"
        role="button"
        tabindex="0"
        aria-label="Close photo viewer"
        onclick={() => (lightboxUrl = null)}
        onkeydown={(e) => {
          if (e.key === "Escape" || e.key === "Enter") lightboxUrl = null;
        }}
      >
        <img src={lightboxUrl} alt="Attachment full view" />
      </div>
    {/if}
  {/if}
</section>

<style>
  .visit-detail {
    border: 1px solid #ddd;
    border-radius: 4px;
    padding: 1rem;
    margin: 1rem 0;
  }
  header {
    display: flex;
    justify-content: space-between;
    align-items: baseline;
    gap: 1rem;
  }
  dl {
    display: grid;
    grid-template-columns: max-content 1fr;
    gap: 0.4rem 1rem;
  }
  dt { font-weight: 600; color: #555; }
  dd { margin: 0; }
  .actions {
    display: flex;
    gap: 0.5rem;
    margin-top: 1rem;
  }
  button {
    padding: 0.5rem 1rem;
    cursor: pointer;
  }
  button[disabled] { cursor: not-allowed; opacity: 0.6; }
  .status {
    font-family: ui-monospace, monospace;
    font-size: 0.85em;
    background: #f3f3f3;
    padding: 0.1em 0.4em;
    border-radius: 3px;
  }
  .terminal { font-style: italic; color: #555; }
  .banner {
    margin-top: 1rem;
    padding: 0.5rem 0.8rem;
    border-radius: 3px;
  }
  .banner-ok   { background: #e8f3e8; color: #244; }
  .banner-warn { background: #fff7e0; color: #644; }
  .banner-err  { background: #fde8e8; color: #a00; }
  .auth-needed { font-style: italic; color: #555; }
  .attachments {
    margin-top: 1.5rem;
    padding-top: 1rem;
    border-top: 1px solid #eee;
  }
  .attachments h3 { margin: 0 0 0.5rem; font-size: 1em; }
  .muted { font-style: italic; color: #888; }
  .attachments-list {
    list-style: none;
    padding: 0;
    margin: 0;
  }
  .attachments-list li {
    display: grid;
    grid-template-columns: max-content max-content max-content max-content 1fr;
    gap: 0.75rem;
    align-items: center;
    padding: 0.4rem 0;
    border-bottom: 1px dashed #eee;
    font-size: 0.9em;
  }
  .att-audio {
    grid-column: 1 / -1;
    width: 100%;
    margin-top: 0.4rem;
  }
  .att-gps {
    grid-column: 1 / -1;
    color: #444;
    font-size: 0.85em;
    margin-top: 0.2rem;
  }
  .att-gps a { color: #0066cc; }
  .att-download {
    color: #0066cc;
    text-decoration: underline;
  }
  .att-thumb {
    width: 80px;
    height: 80px;
    padding: 0;
    border: 1px solid #ddd;
    background: none;
    cursor: pointer;
    overflow: hidden;
    border-radius: 3px;
  }
  .att-thumb img {
    width: 100%;
    height: 100%;
    object-fit: cover;
    display: block;
  }
  .att-icon {
    width: 80px;
    height: 80px;
    display: inline-flex;
    align-items: center;
    justify-content: center;
    background: #f7f7f7;
    border: 1px solid #eee;
    border-radius: 3px;
    font-size: 1.6em;
  }
  .lightbox {
    position: fixed;
    inset: 0;
    background: rgba(0, 0, 0, 0.85);
    display: flex;
    align-items: center;
    justify-content: center;
    z-index: 1000;
    cursor: zoom-out;
  }
  .lightbox img {
    max-width: 95vw;
    max-height: 95vh;
    object-fit: contain;
  }
  .att-kind {
    font-family: ui-monospace, monospace;
    background: #f3f3f3;
    padding: 0.05em 0.4em;
    border-radius: 3px;
  }
  .att-time { color: #555; }
  .att-size { color: #888; }
  .att-caption { color: #333; }
</style>

```
