---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/loom-svelte/src/App.svelte
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.068194+00:00
---

# apps/loom-svelte/src/App.svelte

```svelte
<script lang="ts">
  // D-O5 — Helm SPA shell.
  //
  // Single-page operator console for an oddjobz tenant.  The MVP ships
  // ONE working view (JobList) backed by the REPL HTTP endpoint; later
  // tiers add Customer / Calendar / Attention views and a WSS live-tick
  // stream.
  //
  // The shell handles three concerns:
  //   1. Auth state — decides whether to render the auth-challenge
  //      stub or the operator workspace.
  //   2. Bearer-from-URL capture — picks up `?bearer=...` left by the
  //      auth-callback redirect (D-O5b) and persists it.
  //   3. Shell routing — pattern-T shell with status-bar, cartridge slot,
  //      and bottom dock (Do/Talk/Find).
  //
  // D-svelte-shell-skeleton — restructures oddjobz-only layout into the
  // pattern-T shell: top status bar + centre cartridge slot (attention
  // surface by default) + bottom dock.

  import { onMount, onDestroy } from "svelte";
  import {
    captureBearerFromUrl,
    currentAuthState,
    walletOriginHint,
    type AuthState,
  } from "./lib/auth";
  import { setStoredBearer } from "./lib/repl-client";
  import { HelmEventStream, type HelmEventStreamState } from "./lib/helm-event-stream";
  import { wireJobsTick } from "./lib/jobs-store";
  import { wireCustomersTick } from "./lib/customers-store";
  import { wireVisitsTick } from "./lib/visits-store";
  import { wireQuotesTick } from "./lib/quotes-store";
  import { wireInvoicesTick } from "./lib/invoices-store";
  import { wireAttachmentsTick } from "./lib/attachments-store";
  // D-O5.followup-6 — per-tenant theme loaded post-auth from
  // /api/v1/info; applied to the document root via CSS custom
  // properties.  Defaults render correctly even when the brain has
  // no [theme] block configured.
  import { loadTheme, theme } from "./lib/theme-store";
  // D-O5.followup-8 — multi-hat session store + top-nav switcher.
  // The store hydrates on mount (legacy `helm.bearer` migration runs
  // here), the active session's color tints the per-hat strip, and a
  // `hat-switched` document event triggers a fresh /api/v1/info
  // round-trip so the new hat's theme reapplies.
  import { hatSessions, loadSessions, addSession, generateId, getActiveSession } from "./lib/hat-sessions";
  import MePanel from "./shell/me/MePanel.svelte";
  import ExtensionSwitcher from "./shell/ExtensionSwitcher.svelte";
  import type { CartridgePeerViewShape, UiVerb, SurfacingMode, HatRole } from "./lib/extensions-api";
  import { fetchActiveHatRole } from "./lib/extensions-api";
  import { resolveBodyRoute } from "./shell/body-route";
  import { lookupSurface, type SurfaceEntry } from "./shell/surface-registry";
  import { parseVerbIntent } from "./shell/verb-intent";
  import type { Component } from "svelte";
  import Dock from "./shell/Dock.svelte";
  import AttentionSurface from "./shell/AttentionSurface.svelte";
  import OddjobzCartridge from "./shell/OddjobzCartridge.svelte";
  import type { AttentionSignal } from "./lib/attention-api";
  // D-svelte-find-network — Find → Network contact browser + persona panel.
  import NetworkView from "./views/NetworkView.svelte";
  // D-svelte-talk-mode — Talk intent surface (self/direct/squad/agent/broadcast).
  import TalkModeView from "./views/TalkModeView.svelte";
  import type { TalkContextId } from "./shell/context-weights";

  let auth = $state<AuthState>({ kind: "pending" });
  let walletOrigin = $state(walletOriginHint());
  // Bearer paste fallback for when wallet.semantos.app is unreachable.
  let bearerInput = $state('');
  let bearerError = $state('');
  // D-O5.followup-4 — live indicator state, surfaced via the status bar dot.
  let liveState = $state<HelmEventStreamState>("disconnected");
  // D-svelte-shell-skeleton — active cartridge. null = attention surface (home).
  // D-svelte-extension-switcher — generalised to string | null (was 'oddjobz' | null).
  let activeCartridge = $state<string | null>(null);
  // D-cartridge-peer-view-contract — peer-view declaration for the active cartridge.
  // Null when no cartridge active or cartridge declares no peer-view.
  let activePeerView = $state<CartridgePeerViewShape | null>(null);
  // SH2-B / D11 — the active cartridge's declarative verb overlay. Fed by the
  // ExtensionSwitcher's onSwitch; the Dock composes these onto the kernel CSD
  // pyramid per modal. Empty at home / for cartridges that declare no verbs.
  let activeCartridgeVerbs = $state<UiVerb[]>([]);
  // SH3 / D11 — the active cartridge's surfacingMode, driving the body route
  // (dedicated = full takeover, default = shared body). 'default' at home.
  let activeCartridgeSurfacingMode = $state<SurfacingMode>('default');
  // SH14-B / D12/D13 — the active hat's role (from /api/v1/info hat block).
  // Drives the Dock's verb hat-filter; surfaced/switched in the me panel (SH5).
  let activeHatRole = $state<HatRole>('operator');
  // SH5 / D13 — the "me" panel (identity surface) open state.
  let meOpen = $state(false);
  // SH2-H / D14 — entry hint passed to the active cartridge surface when a
  // verb is dispatched (e.g. "job" → open the oddjobz jobs flow). The surface
  // maps the entity to its own tab/flow.
  let pendingEntryEntity = $state<string | null>(null);
  // When the operator taps an attention item for a job, store the object_id
  // so OddjobzCartridge can jump straight to JobDetailV2.
  let pendingJobId = $state<string | null>(null);
  // Active shell view. null = default (home / cartridge).
  type ShellView =
    | { kind: 'find-network' }
    | { kind: 'talk'; context: TalkContextId };
  let activeView = $state<ShellView | null>(null);

  // SH3 / D11 — centre-slot route (pure decision; see shell/body-route.ts).
  // Consulted only in the authenticated body branch below.
  const bodyRoute = $derived(resolveBodyRoute({
    activeView,
    activeCartridgeId: activeCartridge,
    surfacingMode: activeCartridgeSurfacingMode,
  }));

  // SH4 — concrete cartridge-surface registry (bundled components). The
  // id→component binding lives in this ONE place; the body renders via
  // lookupSurface, so an unregistered cartridge degrades to a placeholder
  // instead of a hardcoded id check. Add a row here to bundle a new surface.
  const SURFACES: Record<string, SurfaceEntry<Component<any>>> = {
    oddjobz: { id: 'oddjobz', label: 'Oddjobz', component: OddjobzCartridge as Component<any> },
  };
  const activeSurface = $derived(
    bodyRoute.kind === 'cartridge' ? lookupSurface(SURFACES, bodyRoute.id) : null,
  );

  function goHome() {
    activeCartridge = null;
    activeView = null;
    pendingJobId = null;
    activeCartridgeVerbs = [];
    activeCartridgeSurfacingMode = 'default';
    pendingEntryEntity = null;
  }

  /** D-svelte-extension-switcher — handle workspace selection from the centre bar. */
  function handleExtensionSwitch(id: string, peerView: CartridgePeerViewShape | null, verbs: UiVerb[] = [], surfacingMode: SurfacingMode = 'default') {
    activeView = null;
    pendingJobId = null;
    // 'core' is the canonical "home" id; map it to null activeCartridge.
    activeCartridge = id === 'core' ? null : id;
    activePeerView = id === 'core' ? null : peerView;
    // SH2-B / D11 — carry the cartridge's verb overlay to the Dock.
    activeCartridgeVerbs = id === 'core' ? [] : verbs;
    // SH3 / D11 — carry the cartridge's surfacingMode for body routing.
    activeCartridgeSurfacingMode = id === 'core' ? 'default' : surfacingMode;
    // SH2-H / D14 — picker switch is a plain surface open, no entry hint.
    pendingEntryEntity = null;
  }

  /** Bearer paste fallback — stores the token and reloads the SPA. */
  function signInWithBearer() {
    const t = bearerInput.trim();
    if (t.length !== 64 || !/^[0-9a-f]+$/i.test(t)) {
      bearerError = 'Token must be 64 hex characters.';
      return;
    }
    bearerError = '';
    setStoredBearer(t);
    window.location.reload();
  }

  /** Handle a tap on an attention item — jump to job detail in the oddjobz cartridge. */
  function handleItemTap(signal: AttentionSignal) {
    // SH9 / D14 — the poll signal's ref is the actionable id; route to the
    // oddjobz surface (best-effort) and let it deep-link via initialJobId.
    pendingJobId = signal.ref;
    activeView = null;
    activeCartridge = 'oddjobz';
  }

  function handleDockInvoke(cmd: string) {
    if (cmd === 'view:find.network') {
      activeView = { kind: 'find-network' };
      activeCartridge = null;
      return;
    }
    const talkMatch = cmd.match(/^view:talk\.(\w+)$/);
    if (talkMatch) {
      activeView = { kind: 'talk', context: talkMatch[1] as TalkContextId };
      activeCartridge = null;
      return;
    }
    // SH5 / D13 / D1 — the me panel is reachable from the TALK tab (and any
    // REPL/voice path) via a view:me command, as well as the AppBar affordance.
    if (cmd === 'view:me') {
      meOpen = true;
      return;
    }
    // SH2-H / D14 — a cartridge verb (cartridge.entity.action) navigates into
    // that cartridge's surface at the relevant flow. The verb came from the
    // active cartridge's overlay, so its surface is already mounted; we just
    // pass the entity as an entry hint for the surface to open the right tab.
    const vi = parseVerbIntent(cmd);
    if (vi && lookupSurface(SURFACES, vi.cartridgeId)) {
      activeView = null;
      activeCartridge = vi.cartridgeId;
      pendingEntryEntity = vi.entity;
      return;
    }
    console.log('dock invoke:', cmd);
  }
  // Derived from window.location — same origin as the brain that serves this SPA.
  const brainBaseUrl = typeof window !== 'undefined'
    ? `${window.location.protocol}//${window.location.host}`
    : '';

  let helmStream: HelmEventStream | null = null;
  let unwires: Array<() => void> = [];
  // D-O5.followup-8 — handler for the HatSwitcher's `hat-switched`
  // event; we hold a reference so onDestroy can detach cleanly.
  let onHatSwitched: ((e: Event) => void) | null = null;

  onMount(() => {
    captureBearerFromUrl();
    // D-O5.followup-8 — hydrate the multi-hat store FIRST.  Reading
    // the store performs the one-time migration of any legacy
    // `helm.bearer` localStorage entry into a Default HatSession, so
    // by the time `currentAuthState` runs the active session is
    // available to ReplClient + the HatSwitcher.
    loadSessions();
    // If the legacy single-bearer path captured a fresh bearer (e.g.
    // the cookie just got promoted), promote it into the multi-hat
    // store so the rest of the SPA reads through the same seam.
    const stillLegacy = typeof localStorage !== "undefined" ? localStorage.getItem("helm.bearer") : null;
    if (stillLegacy && stillLegacy.length === 64 && getActiveSession() === null) {
      const now = Date.now();
      addSession({
        id: generateId(),
        hatId: "default",
        hatName: "Default",
        certId: "",
        bearer: stillLegacy,
        brainBaseUrl: "",
        colorHex: "",
        loggedInAt: now,
        lastUsedAt: now,
      });
      localStorage.removeItem("helm.bearer");
    }
    auth = currentAuthState();
    if (auth.kind === "authenticated") {
      // D-O5.followup-6 — load tenant theme from /api/v1/info.  Best-
      // effort: a network failure (or a brain that 401's the bearer)
      // leaves the helm rendering with the default theme — never
      // blocks the rest of mount.
      void loadTheme(brainBaseUrl, auth.bearer).catch(() => {
        // Default theme is already applied via the store's initial
        // value; swallow the error.
      });
      // SH14-B / D12 — read the active hat role from /api/v1/info so the
      // Dock can hat-gate the verb shelf. Fail-safe defaults to operator.
      void fetchActiveHatRole(brainBaseUrl, auth.bearer)
        .then((r) => { activeHatRole = r; })
        .catch(() => { activeHatRole = 'operator'; });
      // Same-origin WSS — the helm SPA is served from the same brain
      // that hosts /api/v1/wallet, so we derive the URL from
      // window.location.  Production deploys with a separate origin
      // can override via a future data-* attribute on #app (same
      // pattern walletOriginHint uses).
      const proto = window.location.protocol === "https:" ? "wss:" : "ws:";
      const wssUrl = `${proto}//${window.location.host}/api/v1/wallet`;
      // D-O5.followup-4 client-hooks PR: subscribe to every broker
      // topic so all six cell-type lists/details refresh live.  The
      // brain emits a fixed set of `<type>.created` /
      // `<type>.transitioned` events per the helm-event-broker
      // catalogue.
      helmStream = new HelmEventStream({
        wssUrl,
        bearer: auth.bearer,
        topics: ["jobs", "customers", "visits", "quotes", "invoices", "attachments"],
        onState: (s) => {
          liveState = s;
        },
      });
      unwires.push(wireJobsTick(helmStream));
      unwires.push(wireCustomersTick(helmStream));
      unwires.push(wireVisitsTick(helmStream));
      unwires.push(wireQuotesTick(helmStream));
      unwires.push(wireInvoicesTick(helmStream));
      unwires.push(wireAttachmentsTick(helmStream));
      helmStream.connect();

      // D-O5.followup-8 — hat-switched listener.  When the operator
      // switches hats via the HatSwitcher dropdown, the new active
      // hat may be paired against a different brain origin or
      // operator with a different theme.  Re-load the per-tenant
      // theme so the helm visually reflects the new context
      // immediately.  Best-effort; failure leaves the previous theme
      // in place.
      onHatSwitched = () => {
        const session = getActiveSession();
        if (session === null) return;
        const url =
          session.brainBaseUrl.length > 0
            ? session.brainBaseUrl
            : `${window.location.protocol}//${window.location.host}`;
        void loadTheme(url, session.bearer).catch(() => {});
      };
      document.addEventListener("hat-switched", onHatSwitched);
    }
  });

  onDestroy(() => {
    for (const u of unwires) u();
    unwires = [];
    helmStream?.disconnect();
    if (onHatSwitched !== null && typeof document !== "undefined") {
      document.removeEventListener("hat-switched", onHatSwitched);
      onHatSwitched = null;
    }
  });

  // D-O5.followup-8 — derive the active hat's color for the per-hat
  // strip rendered above the status bar.  Falls back to the theme primary
  // when the operator hasn't picked a per-hat color.
  const activeHatColor = $derived.by((): string => {
    const state = $hatSessions;
    if (state.activeId === null) return "";
    const s = state.sessions.find((x) => x.id === state.activeId);
    return s?.colorHex || $theme.primaryHex;
  });

  // Convenience: bearer string for child components (empty when not authed).
  const bearer = $derived(auth.kind === 'authenticated' ? auth.bearer : '');
</script>

<main class="helm">
  {#if auth.kind === "authenticated" && activeHatColor}
    <!-- D-O5.followup-8 — per-hat indicator strip. -->
    <div class="hat-strip" style="background-color: {activeHatColor};"></div>
  {/if}

  <!-- Top status bar -->
  <header class="status-bar">
    <div class="bar-left">
      {#if $theme.logoUrl}
        <img class="brand-logo" src={$theme.logoUrl} alt="brand" />
      {/if}
      <h1>helm</h1>
    </div>
    <div class="bar-center">
      <!-- D-svelte-extension-switcher — workspace selector replaces static label. -->
      {#if auth.kind === "authenticated"}
        <ExtensionSwitcher
          brainBase={brainBaseUrl}
          {bearer}
          activeId={activeCartridge}
          onSwitch={handleExtensionSwitch}
        />
      {:else}
        <span class="cartridge-name">helm</span>
      {/if}
    </div>
    <div class="bar-right">
      {#if auth.kind === "authenticated"}
        <!-- D-O5.followup-4 — live-tick indicator. -->
        <span
          class="live-indicator"
          class:live={liveState === "subscribed"}
          class:reconnecting={liveState === "connecting" || liveState === "reconnecting"}
          class:offline={liveState === "disconnected"}
          title={liveState === "subscribed" ? "Live" : liveState === "disconnected" ? "Offline" : "Reconnecting…"}
        ></span>
        <!-- SH5 / D13 — the hat switcher moved INTO the me panel. The AppBar
             now carries a "me" affordance that opens the identity surface
             (wallet + cert + hat/role + contacts). -->
        <button class="me-affordance" onclick={() => (meOpen = true)} aria-label="Me — identity, wallet, hats">
          <span class="me-affordance-icon">⊚</span>
          <span class="me-affordance-role" class:admin={activeHatRole === 'admin'}>{activeHatRole}</span>
        </button>
      {/if}
    </div>
  </header>

  <!-- Centre: attention surface or active cartridge -->
  <!-- SH3 / D11 — `dedicated` marks a full-surface-takeover cartridge. -->
  <div class="centre-slot" class:dedicated={bodyRoute.kind === 'cartridge' && bodyRoute.dedicated}>
    {#if auth.kind === "pending"}
      <p class="loading">Loading helm…</p>
    {:else if auth.kind === "unauthenticated"}
      <section class="auth-stub">
        <h2>Sign in to helm</h2>
        <p>
          Paste your operator bearer token below to access the helm workspace.
        </p>
        <div class="bearer-form">
          <input
            class="bearer-input"
            type="password"
            placeholder="64-char hex bearer token"
            bind:value={bearerInput}
            onkeydown={(e) => { if (e.key === 'Enter') signInWithBearer(); }}
          />
          <button class="bearer-btn" onclick={signInWithBearer}>Sign in</button>
        </div>
        {#if bearerError}
          <p class="bearer-error">{bearerError}</p>
        {/if}
        <p class="hint">
          Token is stored in localStorage and cleared on 401. Your token:<br />
          <code>Settings → brain → bearer</code> or retrieve from the systemd drop-in on rbs.
        </p>
      </section>
    <!-- SH3 / D11 — centre-slot driven by the pure body route. -->
    {:else if bodyRoute.kind === 'view-find-network'}
      <NetworkView brainBase={brainBaseUrl} {bearer} peerView={activePeerView} onGoHome={goHome} />
    {:else if bodyRoute.kind === 'view-talk'}
      <TalkModeView context={bodyRoute.context} brainBase={brainBaseUrl} {bearer} onGoHome={goHome} />
    {:else if bodyRoute.kind === 'home'}
      <AttentionSurface {bearer} {brainBaseUrl} onItemTap={handleItemTap} />
    {:else if bodyRoute.kind === 'cartridge' && activeSurface}
      <!-- SH4 — render the registered surface for the active cartridge. -->
      {@const Surface = activeSurface.component}
      <Surface initialJobId={pendingJobId} entryEntity={pendingEntryEntity} />
    {:else if bodyRoute.kind === 'cartridge'}
      <!-- SH4 — cartridge active but no surface bundled in this helm build. -->
      <section class="surface-missing">
        <h2>{bodyRoute.id}</h2>
        <p>This cartridge's surface isn't available in this helm build.</p>
      </section>
    {/if}
  </div>

  <!-- Bottom dock (authenticated only) -->
  {#if auth.kind === "authenticated"}
    <div class="dock-area">
      <Dock
        onGoHome={goHome}
        homeBadge={0}
        onInvoke={handleDockInvoke}
        cartridgeVerbs={activeCartridgeVerbs}
        hatRole={activeHatRole}
        directContextNav={{
          'find.network':    'view:find.network',
          'talk.self':       'view:talk.self',
          'talk.direct':     'view:talk.direct',
          'talk.squad':      'view:talk.squad',
          'talk.agent':      'view:talk.agent',
          'talk.broadcast':  'view:talk.broadcast',
        }}
      />
    </div>
  {/if}

  <!-- SH5 / D13 — the "me" identity panel (wallet + cert + hat/role + contacts). -->
  {#if auth.kind === "authenticated" && meOpen}
    <MePanel
      brainBase={brainBaseUrl}
      {bearer}
      walletOrigin={walletOrigin}
      hatRole={activeHatRole}
      onClose={() => (meOpen = false)}
      onOpenContacts={() => { activeView = { kind: 'find-network' }; activeCartridge = null; meOpen = false; }}
    />
  {/if}
</main>

<style>
  .helm {
    display: flex;
    flex-direction: column;
    height: 100vh;
    overflow: hidden;
    background: var(--color-bg, #0f0f0f);
    color: var(--color-text, #e5e7eb);
  }

  .hat-strip {
    height: 3px;
    flex-shrink: 0;
  }

  /* ── Status bar ── */
  .status-bar {
    display: flex;
    align-items: center;
    justify-content: space-between;
    background: var(--color-surface, #1a1a1a);
    border-bottom: 1px solid #333;
    padding: 0 1rem;
    height: 48px;
    flex-shrink: 0;
  }

  .bar-left {
    display: flex;
    align-items: center;
    gap: 0.5rem;
  }

  .bar-left h1 {
    margin: 0;
    font-size: 1.125rem;
    font-weight: 700;
    color: #f3f4f6;
    letter-spacing: -0.01em;
  }

  .brand-logo {
    height: 28px;
    width: auto;
    object-fit: contain;
  }

  .bar-center {
    flex: 1;
    display: flex;
    align-items: center;
    justify-content: center;
  }

  .cartridge-name {
    font-size: 0.8125rem;
    color: #9ca3af;
    font-weight: 500;
  }

  .bar-right {
    display: flex;
    align-items: center;
    gap: 0.75rem;
  }

  /* SH5 / D13 — the "me" affordance that opens the identity panel. */
  .me-affordance {
    display: flex;
    align-items: center;
    gap: 0.375rem;
    background: transparent;
    border: 1px solid #374151;
    border-radius: 0.5rem;
    padding: 0.25rem 0.5rem;
    color: #e5e7eb;
    cursor: pointer;
    font-size: 0.8125rem;
  }
  .me-affordance:hover { background: rgba(55, 65, 81, 0.5); }
  .me-affordance-icon { font-size: 1rem; line-height: 1; }
  .me-affordance-role {
    font-size: 0.625rem;
    text-transform: uppercase;
    letter-spacing: 0.04em;
    color: #9ca3af;
  }
  .me-affordance-role.admin { color: #fca5a5; }

  /* ── Live indicator (reused from original) ── */
  .live-indicator {
    display: inline-block;
    width: 8px;
    height: 8px;
    border-radius: 50%;
    background: #4b5563;
    flex-shrink: 0;
  }

  .live-indicator.live {
    background: #22c55e;
  }

  .live-indicator.reconnecting {
    background: #f59e0b;
  }

  .live-indicator.offline {
    background: #4b5563;
  }

  /* ── Centre slot ── */
  .centre-slot {
    flex: 1;
    overflow-y: auto;
    padding: 1rem;
  }

  /* SH3 / D11 — a dedicated (full-surface-takeover) cartridge owns the whole
     centre-slot: drop the padding so its surface goes edge-to-edge. */
  .centre-slot.dedicated {
    padding: 0;
  }

  /* SH4 — placeholder when an active cartridge has no bundled surface. */
  .surface-missing {
    margin: 2rem auto;
    max-width: 32rem;
    text-align: center;
    color: #9ca3af;
  }
  .surface-missing h2 {
    text-transform: capitalize;
    color: #e5e7eb;
  }

  /* ── Dock area ── */
  .dock-area {
    flex-shrink: 0;
  }

  /* ── Auth stub ── */
  .auth-stub {
    max-width: 480px;
    margin: 4rem auto;
    padding: 2rem;
    background: #1a1a1a;
    border: 1px solid #2a2a2a;
    border-radius: 0.75rem;
  }

  .auth-stub h2 {
    margin: 0 0 1rem;
    font-size: 1.25rem;
    color: #f3f4f6;
  }

  .auth-stub p {
    margin: 0.75rem 0;
    font-size: 0.875rem;
    color: #9ca3af;
    line-height: 1.6;
  }

  .hint {
    font-size: 0.8125rem !important;
    color: #6b7280 !important;
    background: #111;
    border: 1px solid #2a2a2a;
    border-radius: 0.375rem;
    padding: 0.75rem;
  }

  .hint code {
    font-family: monospace;
    color: #a5b4fc;
  }

  .bearer-form {
    display: flex;
    gap: 0.5rem;
    margin: 1rem 0 0.25rem;
  }

  .bearer-input {
    flex: 1;
    background: #111;
    border: 1px solid #333;
    border-radius: 0.375rem;
    color: #e5e7eb;
    font-family: monospace;
    font-size: 0.8125rem;
    padding: 0.5rem 0.75rem;
    outline: none;
  }

  .bearer-input:focus {
    border-color: #60a5fa;
  }

  .bearer-btn {
    background: #1d4ed8;
    border: none;
    border-radius: 0.375rem;
    color: #fff;
    cursor: pointer;
    font-size: 0.875rem;
    padding: 0.5rem 1rem;
    white-space: nowrap;
  }

  .bearer-btn:hover { background: #2563eb; }

  .bearer-error {
    color: #f87171;
    font-size: 0.8125rem;
    margin: 0.25rem 0 0;
  }

  /* ── Loading state ── */
  .loading {
    color: #6b7280;
    font-size: 0.875rem;
    text-align: center;
    padding: 4rem;
  }

</style>

```
