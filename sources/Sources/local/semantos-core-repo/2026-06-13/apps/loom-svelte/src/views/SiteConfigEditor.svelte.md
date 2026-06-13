---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/loom-svelte/src/views/SiteConfigEditor.svelte
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.075704+00:00
---

# apps/loom-svelte/src/views/SiteConfigEditor.svelte

```svelte
<script lang="ts">
  // D-O5.followup-5 — Site config editor view.
  //
  // Operator-root editor for `<sites_dir>/<domain>/site.json`.  Loads
  // the on-disk config via `site_config.read` on mount, lets the
  // operator hand-edit the JSON in a textarea, then atomically saves
  // via `site_config.write` (which re-validates server-side via the
  // canonical `site_config.parseJson`).
  //
  // UX:
  //   - Top bar: domain selector (operator types the domain), Load
  //     button, Save button (disabled when no changes), Discard
  //     (revert to last-fetched), Validate (server-side dry run).
  //   - JSON editor: monospace textarea.  Plain-text edit; the brain's
  //     parser is the canonical validator.  Local-parse-on-blur catches
  //     trivial syntax errors before burning a network round-trip.
  //   - Side panel: parsed routes list with type + auth badge.  Click a
  //     route → highlight matching text in the editor.
  //   - Status row: success / error / parse-error inline.
  //
  // Cap-gating: the brain handler requires `cap.brain.admin`.  The view
  // itself doesn't gate visibility — App.svelte adds it as a tab next
  // to the existing Jobs / Customers / etc. tabs, visible to every
  // bearer.  An operator without admin cap will get a typed error from
  // the brain on Save / Load and the inline error UX surfaces it.
  // Tightening visibility to operator-root only is tracked alongside
  // the other admin-surface views (no operator-cap-info endpoint
  // exists yet — D-O5.followup tracking).

  import { onMount } from "svelte";
  import { ReplClient } from "../lib/repl-client";
  import {
    loadSiteConfig,
    saveSiteConfig,
    validateSiteConfig,
    sniffRoutes,
    SiteConfigSaveError,
    type RouteSummary,
  } from "../lib/site-config-store";

  let { client = new ReplClient() }: { client?: ReplClient } = $props();

  /// Operator types the domain into a text input.  We persist the
  /// last-loaded domain in localStorage so a reload pre-fills the
  /// field.  The empty default forces the operator to confirm.
  let domain = $state<string>(loadDomainFromStorage());
  let editorText = $state<string>("");
  let lastLoaded = $state<string>("");
  let loading = $state<boolean>(false);
  let saving = $state<boolean>(false);
  let validating = $state<boolean>(false);
  let statusKind = $state<"idle" | "ok" | "err" | "parse-err">("idle");
  let statusText = $state<string>("");
  let writtenAt = $state<number | null>(null);

  /// True when the editor buffer differs from the last successful
  /// load.  Drives Save / Discard enablement.
  let dirty = $derived<boolean>(editorText !== lastLoaded);

  let routes = $derived<RouteSummary[]>(sniffRoutes(editorText));

  function loadDomainFromStorage(): string {
    if (typeof localStorage === "undefined") return "";
    return localStorage.getItem("helm.site-config.domain") ?? "";
  }
  function persistDomain(d: string): void {
    if (typeof localStorage === "undefined") return;
    if (d) localStorage.setItem("helm.site-config.domain", d);
    else localStorage.removeItem("helm.site-config.domain");
  }

  async function load() {
    if (!domain) {
      statusKind = "err";
      statusText = "Enter a domain to load.";
      return;
    }
    loading = true;
    statusKind = "idle";
    statusText = "";
    try {
      const got = await loadSiteConfig(client, domain);
      editorText = got.json;
      lastLoaded = got.json;
      writtenAt = got.mtimeUnix || null;
      persistDomain(domain);
      statusKind = "ok";
      statusText = `Loaded ${got.size} bytes for ${got.domain}.`;
    } catch (e: unknown) {
      statusKind = "err";
      statusText =
        e instanceof SiteConfigSaveError
          ? e.message
          : e instanceof Error
            ? e.message
            : String(e);
    } finally {
      loading = false;
    }
  }

  async function save() {
    saving = true;
    statusKind = "idle";
    statusText = "";
    try {
      const result = await saveSiteConfig(client, domain, editorText);
      lastLoaded = editorText;
      writtenAt = result.writtenAt || null;
      statusKind = "ok";
      statusText = `Saved at ${
        result.writtenAt > 0
          ? new Date(result.writtenAt * 1000).toLocaleTimeString()
          : "now"
      }.`;
    } catch (e: unknown) {
      if (e instanceof SiteConfigSaveError && e.kind === "client_parse_failed") {
        statusKind = "parse-err";
      } else {
        statusKind = "err";
      }
      statusText =
        e instanceof SiteConfigSaveError
          ? e.message
          : e instanceof Error
            ? e.message
            : String(e);
    } finally {
      saving = false;
    }
  }

  async function validate() {
    validating = true;
    statusKind = "idle";
    statusText = "";
    try {
      await validateSiteConfig(client, domain, editorText);
      statusKind = "ok";
      statusText = "Validates cleanly (server-side dry run).";
    } catch (e: unknown) {
      if (e instanceof SiteConfigSaveError && e.kind === "client_parse_failed") {
        statusKind = "parse-err";
      } else {
        statusKind = "err";
      }
      statusText =
        e instanceof SiteConfigSaveError
          ? e.message
          : e instanceof Error
            ? e.message
            : String(e);
    } finally {
      validating = false;
    }
  }

  function discard() {
    editorText = lastLoaded;
    statusKind = "idle";
    statusText = "Reverted to last-loaded buffer.";
  }

  /// When the operator clicks a route in the side panel, scroll the
  /// editor to the first occurrence of that path.  Best-effort: the
  /// textarea's selectionRange API is the simplest way to highlight,
  /// even though it doesn't provide a true "find" experience.
  let textareaEl: HTMLTextAreaElement | null = $state(null);
  function jumpToRoute(path: string) {
    if (!textareaEl) return;
    const idx = editorText.indexOf(`"${path}"`);
    if (idx < 0) return;
    textareaEl.focus();
    textareaEl.setSelectionRange(idx, idx + path.length + 2);
  }

  onMount(() => {
    if (domain) load();
  });
</script>

<section class="site-config-editor">
  <header>
    <h2>Site config</h2>
    <div class="controls">
      <label class="domain-input">
        Domain:
        <input
          type="text"
          bind:value={domain}
          placeholder="example.com"
          disabled={loading || saving}
        />
      </label>
      <button onclick={() => load()} disabled={loading || saving || !domain}>
        {loading ? "Loading…" : "Load"}
      </button>
      <button onclick={() => validate()} disabled={validating || saving || !lastLoaded}>
        {validating ? "Validating…" : "Validate"}
      </button>
      <button class="primary" onclick={() => save()} disabled={!dirty || saving || loading}>
        {saving ? "Saving…" : "Save"}
      </button>
      <button onclick={() => discard()} disabled={!dirty}>
        Discard
      </button>
    </div>
  </header>

  {#if statusText}
    <p
      class="status"
      class:status-ok={statusKind === "ok"}
      class:status-err={statusKind === "err"}
      class:status-parse-err={statusKind === "parse-err"}
    >
      {statusText}
    </p>
  {/if}

  <div class="grid">
    <div class="editor-wrap">
      <textarea
        bind:this={textareaEl}
        bind:value={editorText}
        spellcheck="false"
        disabled={loading || saving}
        placeholder="Click Load to fetch the current site.json from the brain…"
      ></textarea>
    </div>

    <aside class="side">
      <h3>Routes ({routes.length})</h3>
      {#if routes.length === 0}
        <p class="empty">No routes parsed.</p>
      {:else}
        <ul>
          {#each routes as r}
            <li>
              <button class="route-row" onclick={() => jumpToRoute(r.path)}>
                <code>{r.path}</code>
                <span class="route-type">{r.type}</span>
                <span class="route-auth">{r.auth}</span>
              </button>
            </li>
          {/each}
        </ul>
      {/if}
      {#if writtenAt}
        <p class="mtime">
          Last touched: {new Date(writtenAt * 1000).toLocaleString()}
        </p>
      {/if}
    </aside>
  </div>
</section>

<style>
  .site-config-editor {
    border: 1px solid #ddd;
    border-radius: 4px;
    padding: 1rem;
    margin: 1rem 0;
  }
  header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    flex-wrap: wrap;
    gap: 0.5rem;
  }
  .controls {
    display: flex;
    align-items: center;
    gap: 0.5rem;
    flex-wrap: wrap;
  }
  .domain-input input {
    margin-left: 0.4rem;
    font-family: ui-monospace, monospace;
    padding: 0.2rem 0.4rem;
    border: 1px solid #bbb;
    border-radius: 3px;
    width: 16em;
  }
  button.primary {
    background: #2a662a;
    color: #fff;
    border: 1px solid #1f4d1f;
  }
  button.primary:disabled {
    background: #bcd1bc;
    border-color: #aac1aa;
    cursor: not-allowed;
  }
  .status {
    margin: 0.5rem 0 0 0;
    padding: 0.4rem 0.6rem;
    border-radius: 3px;
    font-family: ui-monospace, monospace;
    font-size: 0.85em;
  }
  .status-ok {
    background: #e6f5e6;
    color: #2a662a;
    border: 1px solid #c2e0c2;
  }
  .status-err {
    background: #fdecec;
    color: #a02020;
    border: 1px solid #ecbcbc;
  }
  .status-parse-err {
    background: #fff7d6;
    color: #806000;
    border: 1px solid #e6d68a;
  }
  .grid {
    display: grid;
    grid-template-columns: 1fr 18em;
    gap: 1rem;
    margin-top: 0.75rem;
  }
  .editor-wrap textarea {
    width: 100%;
    min-height: 30em;
    font-family: ui-monospace, monospace;
    font-size: 0.9em;
    padding: 0.5rem;
    border: 1px solid #ccc;
    border-radius: 3px;
    box-sizing: border-box;
    resize: vertical;
  }
  .side {
    border-left: 1px solid #eee;
    padding-left: 1rem;
  }
  .side h3 {
    margin-top: 0;
    font-size: 0.95em;
  }
  .side ul {
    list-style: none;
    padding: 0;
    margin: 0;
  }
  .side li {
    margin-bottom: 0.25rem;
  }
  .route-row {
    width: 100%;
    text-align: left;
    background: transparent;
    border: 1px solid transparent;
    padding: 0.3rem 0.4rem;
    border-radius: 3px;
    cursor: pointer;
    display: flex;
    gap: 0.5rem;
    align-items: baseline;
  }
  .route-row:hover {
    background: #f5f5f5;
    border-color: #e0e0e0;
  }
  .route-row code {
    flex: 1;
    word-break: break-all;
    font-size: 0.85em;
  }
  .route-type,
  .route-auth {
    font-size: 0.75em;
    padding: 0.05em 0.4em;
    border-radius: 3px;
    background: #eee;
    color: #555;
  }
  .empty {
    color: #888;
    font-style: italic;
    font-size: 0.85em;
  }
  .mtime {
    margin-top: 0.75rem;
    font-size: 0.75em;
    color: #888;
  }
</style>

```
