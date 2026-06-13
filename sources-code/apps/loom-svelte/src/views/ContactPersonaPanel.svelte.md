---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/loom-svelte/src/views/ContactPersonaPanel.svelte
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.069866+00:00
---

# apps/loom-svelte/src/views/ContactPersonaPanel.svelte

```svelte
<script lang="ts">
  /**
   * ContactPersonaPanel — detail view for a single contact.
   *
   * Shows the three-face persona projection (social / topical / commercial)
   * populated from the contact record + its edges fetched from the brain.
   *
   * D-helm-contacts-panel: adds Add Edge form + Revoke Edge action +
   * recovery policy badges on each active edge.
   */
  import {
    projectPersona,
    type PersonaProjection,
    type PersonaIdentity,
    type PersonaEdgeView,
  } from '../lib/persona';
  import {
    getContactDetail,
    addEdge,
    revokeEdge,
    type BrainContactDetail,
    type BrainEdgeRecord,
    type EdgeType,
    type RecoveryPolicy,
  } from '../lib/contacts-api';

  let {
    contact,
    brainBase,
    bearer,
    onBack,
  }: {
    contact: { certId: string; displayName: string; email: string | null };
    brainBase: string;
    bearer: string;
    onBack: () => void;
  } = $props();

  let detail = $state<BrainContactDetail | null>(null);
  let loading = $state(true);
  let persona = $state<PersonaProjection | null>(null);

  // ── Add Edge modal ─────────────────────────────────────────────────────────
  let showAddEdge = $state(false);
  let edgeForm = $state<{
    edgeType: EdgeType;
    recoveryPolicy: RecoveryPolicy;
    signingKeyIndex: number;
  }>({ edgeType: 'MESSAGING', recoveryPolicy: 'BACKUP_ON_CREATE', signingKeyIndex: 0 });
  let addEdgeBusy = $state(false);
  let addEdgeError = $state<string | null>(null);

  // ── Revoke ─────────────────────────────────────────────────────────────────
  let revokingId = $state<string | null>(null);
  let revokeError = $state<string | null>(null);

  const EDGE_TYPE_OPTIONS: { value: EdgeType; label: string }[] = [
    { value: 'MESSAGING',       label: 'Messaging' },
    { value: 'DATA_ACCESS',     label: 'Data Access' },
    { value: 'ROLE_ASSIGNMENT', label: 'Role Assignment' },
    { value: 'AUTHORITY',       label: 'Authority' },
    { value: 'TRANSFER',        label: 'Transfer' },
    { value: 'ATTESTATION',     label: 'Attestation' },
    { value: 'CUSTOM',          label: 'Custom' },
  ];

  const RECOVERY_OPTIONS: { value: RecoveryPolicy; label: string; desc: string }[] = [
    { value: 'BACKUP_ON_CREATE',  label: 'Backup on create',  desc: 'Backup is written when the edge is created' },
    { value: 'BACKUP_ON_CONFIRM', label: 'Backup on confirm', desc: 'Backup is written after the peer confirms the edge' },
    { value: 'NONE',              label: 'None',              desc: 'No recovery backup created' },
  ];

  // Fetch detail + build projection when certId changes
  $effect(() => {
    const certId = contact.certId;
    loading = true;
    detail = null;
    persona = null;
    revokeError = null;

    void loadDetail(certId);
  });

  async function loadDetail(certId: string) {
    const d = await getContactDetail(brainBase, bearer, certId);
    detail = d;
    buildPersona(d);
    loading = false;
  }

  function buildPersona(d: BrainContactDetail | null) {
    const identity: PersonaIdentity = {
      certId: contact.certId,
      displayName: contact.displayName,
      email: contact.email ?? undefined,
    };

    const contactEdges: PersonaEdgeView[] = (d?.edges ?? []).map(
      (e: BrainEdgeRecord): PersonaEdgeView => ({
        edgeType: e.edgeType,
        counterpartyCertId: contact.certId,
        revoked: e.revokedAt !== null,
      }),
    );

    persona = projectPersona({
      identity,
      viewerHat: 'social',
      nodes: [],
      edges: [],
      contactEdges,
    });
  }

  function truncateCertId(certId: string): string {
    if (certId.length <= 16) return certId;
    return `${certId.slice(0, 8)}…${certId.slice(-8)}`;
  }

  function edgeTypeLabel(edgeType: string): string {
    return EDGE_TYPE_OPTIONS.find(o => o.value === edgeType)?.label ?? edgeType;
  }

  function recoveryLabel(policy: string): string {
    return RECOVERY_OPTIONS.find(o => o.value === policy)?.label ?? policy;
  }

  function formatDate(unixSecs: number): string {
    return new Date(unixSecs * 1000).toLocaleDateString(undefined, {
      year: 'numeric', month: 'short', day: 'numeric',
    });
  }

  /** Generate a simple UUID-v4-ish client-side edgeId. */
  function newEdgeId(): string {
    return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => {
      const r = (Math.random() * 16) | 0;
      return (c === 'x' ? r : (r & 0x3) | 0x8).toString(16);
    });
  }

  async function submitAddEdge() {
    addEdgeError = null;
    addEdgeBusy = true;

    const { edge, errCode } = await addEdge(brainBase, bearer, contact.certId, {
      edgeId: newEdgeId(),
      edgeType: edgeForm.edgeType,
      signingKeyIndex: edgeForm.signingKeyIndex,
      recoveryPolicy: edgeForm.recoveryPolicy,
    });

    addEdgeBusy = false;

    if (!edge) {
      addEdgeError = errCode === 'duplicate_edge'
        ? 'An edge of that type already exists for this contact.'
        : `Failed to add edge (${errCode ?? 'unknown error'}).`;
      return;
    }

    // Merge into detail
    if (detail) {
      detail = { ...detail, edges: [...detail.edges, edge] };
      buildPersona(detail);
    }
    showAddEdge = false;
  }

  async function handleRevoke(edge: BrainEdgeRecord) {
    revokeError = null;
    revokingId = edge.edgeId;

    const { ok, errCode } = await revokeEdge(brainBase, bearer, contact.certId, edge.edgeId);
    revokingId = null;

    if (!ok) {
      revokeError = errCode === 'already_revoked'
        ? 'This edge was already revoked.'
        : errCode === 'not_found'
          ? 'Edge not found — it may have been deleted.'
          : `Failed to revoke (${errCode ?? 'unknown error'}).`;
      return;
    }

    // Mark locally as revoked (now = seconds)
    if (detail) {
      const now = Math.floor(Date.now() / 1000);
      detail = {
        ...detail,
        edges: detail.edges.map(e =>
          e.edgeId === edge.edgeId ? { ...e, revokedAt: now } : e,
        ),
      };
      buildPersona(detail);
    }
  }
</script>

<div class="persona-panel">
  <div class="panel-header">
    <button class="back-btn" onclick={onBack} aria-label="Back to network">
      ← Back
    </button>
    <div class="identity">
      <div class="avatar">{contact.displayName[0]?.toUpperCase() ?? '?'}</div>
      <div class="identity-text">
        <div class="display-name">{contact.displayName}</div>
        {#if contact.email}
          <div class="email">{contact.email}</div>
        {/if}
        <div class="cert-id" title={contact.certId}>{truncateCertId(contact.certId)}</div>
      </div>
    </div>
  </div>

  {#if loading}
    <div class="loading">Loading…</div>
  {:else if persona}
    <!-- ── Edges ── -->
    {@const activeEdges = (detail?.edges ?? []).filter((e) => e.revokedAt === null)}
    {@const revokedEdges = (detail?.edges ?? []).filter((e) => e.revokedAt !== null)}

    <section class="face-section">
      <div class="section-header">
        <div class="face-label">Connections</div>
        <button class="add-edge-btn" onclick={() => { showAddEdge = !showAddEdge; addEdgeError = null; }}>
          {showAddEdge ? 'Cancel' : '+ Add Edge'}
        </button>
      </div>

      {#if revokeError}
        <p class="inline-error">{revokeError}</p>
      {/if}

      {#if showAddEdge}
        <!-- Add Edge form -->
        <div class="add-edge-form">
          {#if addEdgeError}
            <p class="form-error">{addEdgeError}</p>
          {/if}

          <label class="form-label">
            Edge type
            <select class="form-select" bind:value={edgeForm.edgeType} disabled={addEdgeBusy}>
              {#each EDGE_TYPE_OPTIONS as opt (opt.value)}
                <option value={opt.value}>{opt.label}</option>
              {/each}
            </select>
          </label>

          <label class="form-label">
            Recovery policy
            <select class="form-select" bind:value={edgeForm.recoveryPolicy} disabled={addEdgeBusy}>
              {#each RECOVERY_OPTIONS as opt (opt.value)}
                <option value={opt.value}>{opt.label} — {opt.desc}</option>
              {/each}
            </select>
          </label>

          <label class="form-label">
            Signing key index
            <input
              class="form-input"
              type="number"
              min="0"
              bind:value={edgeForm.signingKeyIndex}
              disabled={addEdgeBusy}
            />
          </label>

          <button
            class="btn-submit-edge"
            onclick={submitAddEdge}
            disabled={addEdgeBusy}
          >
            {addEdgeBusy ? 'Adding…' : 'Add Edge'}
          </button>
        </div>
      {/if}

      {#if activeEdges.length === 0 && !showAddEdge}
        <div class="empty-face">No active connections yet.</div>
      {:else if activeEdges.length > 0}
        <ul class="edge-list">
          {#each activeEdges as edge (edge.edgeId)}
            <li class="edge-item">
              <div class="edge-main">
                <span class="edge-type">{edgeTypeLabel(edge.edgeType)}</span>
                <span class="edge-since">since {formatDate(edge.createdAt)}</span>
              </div>
              <div class="edge-footer">
                <span class="recovery-badge recovery-{edge.recoveryPolicy.toLowerCase()}">
                  {recoveryLabel(edge.recoveryPolicy)}
                </span>
                <button
                  class="revoke-btn"
                  onclick={() => handleRevoke(edge)}
                  disabled={revokingId === edge.edgeId}
                  title="Revoke this edge"
                >
                  {revokingId === edge.edgeId ? 'Revoking…' : 'Revoke'}
                </button>
              </div>
            </li>
          {/each}
        </ul>
      {/if}

      {#if revokedEdges.length > 0}
        <details class="revoked-section">
          <summary class="revoked-summary">
            {revokedEdges.length} revoked edge{revokedEdges.length === 1 ? '' : 's'}
          </summary>
          <ul class="edge-list revoked-list">
            {#each revokedEdges as edge (edge.edgeId)}
              <li class="edge-item revoked">
                <div class="edge-main">
                  <span class="edge-type dimmed">{edgeTypeLabel(edge.edgeType)}</span>
                  <span class="edge-since">revoked {edge.revokedAt ? formatDate(edge.revokedAt) : '—'}</span>
                </div>
                <div class="edge-footer">
                  <span class="recovery-badge recovery-none">revoked</span>
                </div>
              </li>
            {/each}
          </ul>
        </details>
      {/if}
    </section>

    <!-- ── Social face ── -->
    <section class="face-section">
      <div class="face-label">Social</div>
      {#if persona.social.length === 0}
        <div class="empty-face">No shared content yet.</div>
      {:else}
        <ul class="stream-list">
          {#each persona.social.slice(0, 5) as item}
            <li class="stream-item">{item.node.id}</li>
          {/each}
        </ul>
      {/if}
    </section>

    <!-- ── Topical face ── -->
    <section class="face-section">
      <div class="face-label">Topical</div>
      {#if persona.topical.length === 0}
        <div class="empty-face">No shared threads yet.</div>
      {:else}
        <ul class="stream-list">
          {#each persona.topical.slice(0, 5) as thread}
            <li class="stream-item">{thread.node.id}</li>
          {/each}
        </ul>
      {/if}
    </section>

    <!-- ── Commercial face ── -->
    <section class="face-section">
      <div class="face-label">Commercial</div>
      {#if persona.commercial.length === 0}
        <div class="empty-face">No shared transactions yet.</div>
      {:else}
        <ul class="stream-list">
          {#each persona.commercial.slice(0, 5) as rel}
            <li class="stream-item">{rel.kind}: {rel.sourceId} → {rel.targetId}</li>
          {/each}
        </ul>
      {/if}
    </section>

    <!-- ── Identity meta ── -->
    {#if detail}
      <section class="face-section meta-section">
        <div class="face-label">Identity</div>
        <dl class="meta-dl">
          <dt>Source</dt><dd>{detail.source}</dd>
          <dt>Added</dt><dd>{formatDate(detail.addedAt)}</dd>
          <dt>Public key</dt><dd class="mono">{truncateCertId(detail.publicKey)}</dd>
        </dl>
      </section>
    {/if}
  {/if}
</div>

<style>
  .persona-panel {
    display: flex;
    flex-direction: column;
    height: 100%;
    overflow-y: auto;
    background: #0f172a;
    color: #e2e8f0;
  }

  .panel-header {
    padding: 1rem;
    border-bottom: 1px solid #1e293b;
    background: #111827;
  }

  .back-btn {
    background: transparent;
    border: none;
    color: #60a5fa;
    font-size: 0.875rem;
    cursor: pointer;
    padding: 0.25rem 0;
    margin-bottom: 0.75rem;
  }

  .back-btn:hover { color: #93c5fd; }

  .identity {
    display: flex;
    align-items: center;
    gap: 1rem;
  }

  .avatar {
    width: 48px;
    height: 48px;
    border-radius: 50%;
    background: #1d4ed8;
    color: #fff;
    font-size: 1.25rem;
    font-weight: 700;
    display: flex;
    align-items: center;
    justify-content: center;
    flex-shrink: 0;
  }

  .identity-text { display: flex; flex-direction: column; gap: 2px; }

  .display-name { font-size: 1.125rem; font-weight: 600; }
  .email { font-size: 0.8125rem; color: #94a3b8; }
  .cert-id {
    font-size: 0.75rem;
    font-family: monospace;
    color: #475569;
    cursor: default;
  }

  .loading {
    padding: 2rem;
    text-align: center;
    color: #64748b;
    font-size: 0.875rem;
  }

  .face-section {
    padding: 1rem;
    border-bottom: 1px solid #1e293b;
  }

  .section-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    margin-bottom: 0.625rem;
  }

  .face-label {
    font-size: 0.6875rem;
    font-weight: 600;
    text-transform: uppercase;
    letter-spacing: 0.08em;
    color: #64748b;
  }

  /* face-label without section-header still needs the margin */
  .face-section > .face-label { margin-bottom: 0.5rem; }

  .add-edge-btn {
    background: transparent;
    border: 1px solid #334155;
    color: #60a5fa;
    font-size: 0.75rem;
    cursor: pointer;
    padding: 0.2rem 0.5rem;
    border-radius: 0.25rem;
    transition: background 0.1s;
  }

  .add-edge-btn:hover { background: rgba(96,165,250,0.08); }

  .inline-error {
    margin: 0 0 0.5rem;
    font-size: 0.8125rem;
    color: #f87171;
  }

  /* ── Add Edge inline form ── */
  .add-edge-form {
    background: #1e293b;
    border: 1px solid #334155;
    border-radius: 0.5rem;
    padding: 0.875rem;
    margin-bottom: 0.75rem;
    display: flex;
    flex-direction: column;
    gap: 0.625rem;
  }

  .form-error {
    margin: 0;
    padding: 0.4rem 0.625rem;
    background: rgba(239, 68, 68, 0.1);
    border: 1px solid rgba(239, 68, 68, 0.25);
    border-radius: 0.375rem;
    font-size: 0.8125rem;
    color: #f87171;
  }

  .form-label {
    display: flex;
    flex-direction: column;
    gap: 0.25rem;
    font-size: 0.75rem;
    font-weight: 500;
    color: #94a3b8;
  }

  .form-select, .form-input {
    background: #0f172a;
    border: 1px solid #334155;
    border-radius: 0.375rem;
    color: #e2e8f0;
    font-size: 0.8125rem;
    padding: 0.375rem 0.5rem;
    outline: none;
    width: 100%;
    box-sizing: border-box;
  }

  .form-select:focus, .form-input:focus { border-color: #3b82f6; }
  .form-select:disabled, .form-input:disabled { opacity: 0.5; cursor: not-allowed; }

  .btn-submit-edge {
    align-self: flex-end;
    background: #1d4ed8;
    border: none;
    color: #fff;
    font-size: 0.8125rem;
    font-weight: 600;
    cursor: pointer;
    padding: 0.35rem 0.875rem;
    border-radius: 0.375rem;
    transition: background 0.1s;
  }

  .btn-submit-edge:hover:not(:disabled) { background: #2563eb; }
  .btn-submit-edge:disabled { opacity: 0.4; cursor: default; }

  /* ── Edge list ── */
  .empty-face {
    font-size: 0.8125rem;
    color: #475569;
    font-style: italic;
  }

  .edge-list, .stream-list {
    list-style: none;
    padding: 0;
    margin: 0;
    display: flex;
    flex-direction: column;
    gap: 0.375rem;
  }

  .edge-item {
    padding: 0.5rem 0.625rem;
    background: #1e293b;
    border-radius: 0.375rem;
    display: flex;
    flex-direction: column;
    gap: 0.375rem;
  }

  .edge-item.revoked { opacity: 0.55; }

  .edge-main {
    display: flex;
    align-items: center;
    justify-content: space-between;
    font-size: 0.8125rem;
  }

  .edge-footer {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 0.5rem;
  }

  .edge-type {
    font-weight: 500;
    color: #60a5fa;
  }

  .edge-type.dimmed { color: #475569; }

  .edge-since { color: #64748b; font-size: 0.75rem; }

  /* Recovery policy badges */
  .recovery-badge {
    font-size: 0.625rem;
    font-weight: 500;
    text-transform: uppercase;
    letter-spacing: 0.04em;
    padding: 0.1rem 0.4rem;
    border-radius: 999px;
  }

  .recovery-backup_on_create {
    background: rgba(34, 197, 94, 0.12);
    color: #4ade80;
  }

  .recovery-backup_on_confirm {
    background: rgba(245, 158, 11, 0.12);
    color: #fbbf24;
  }

  .recovery-none {
    background: rgba(55, 65, 81, 0.5);
    color: #64748b;
  }

  .revoke-btn {
    background: transparent;
    border: 1px solid rgba(239, 68, 68, 0.3);
    color: #f87171;
    font-size: 0.6875rem;
    cursor: pointer;
    padding: 0.15rem 0.4rem;
    border-radius: 0.25rem;
    transition: background 0.1s;
    flex-shrink: 0;
  }

  .revoke-btn:hover:not(:disabled) {
    background: rgba(239, 68, 68, 0.12);
  }

  .revoke-btn:disabled { opacity: 0.5; cursor: default; }

  /* Revoked edges disclosure */
  .revoked-section {
    margin-top: 0.625rem;
  }

  .revoked-summary {
    font-size: 0.75rem;
    color: #475569;
    cursor: pointer;
    padding: 0.25rem 0;
    user-select: none;
  }

  .revoked-list { margin-top: 0.5rem; }

  .stream-item {
    padding: 0.25rem 0.5rem;
    font-size: 0.8125rem;
    color: #94a3b8;
    font-family: monospace;
  }

  .meta-section { background: #0a0f1e; }

  .meta-dl {
    display: grid;
    grid-template-columns: auto 1fr;
    gap: 0.25rem 1rem;
    margin: 0;
    font-size: 0.8125rem;
  }

  .meta-dl dt { color: #64748b; }
  .meta-dl dd { margin: 0; color: #cbd5e1; }
  .meta-dl dd.mono { font-family: monospace; font-size: 0.75rem; }
</style>

```
