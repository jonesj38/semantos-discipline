---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/loom-svelte/src/views/NetworkView.svelte
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.071062+00:00
---

# apps/loom-svelte/src/views/NetworkView.svelte

```svelte
<script lang="ts">
  /**
   * NetworkView — Find → Network context.
   *
   * Lists all contacts from GET /api/v1/contacts; tapping one opens
   * ContactPersonaPanel which calls projectPersona() with the contact's
   * stored edges as contactEdges.
   *
   * D-helm-contacts-panel: adds an "Add Contact" modal form (certId +
   * displayName + publicKey required; email optional) that POSTs to
   * /api/v1/contacts.
   */
  import { onMount } from 'svelte';
  import {
    listContacts,
    addContact,
    type BrainContact,
  } from '../lib/contacts-api';
  import type { CartridgePeerViewShape } from '../lib/extensions-api';
  import ContactPersonaPanel from './ContactPersonaPanel.svelte';

  let {
    brainBase,
    bearer,
    peerView = null,
    onGoHome,
  }: {
    brainBase: string;
    bearer: string;
    /**
     * Active cartridge's peer-view declaration. When present, the view uses
     * the cartridge's vocabulary (label/pluralLabel/emptyState) and notes
     * the relevant filterEdgeTypes for the upcoming brain-side filter.
     * V1: vocabulary applied client-side; edge filter applied once the brain
     * gains GET /api/v1/contacts?cartridge=<id> (deferred per design doc §10.4).
     */
    peerView?: CartridgePeerViewShape | null;
    onGoHome: () => void;
  } = $props();

  // ── Peer-view vocabulary (falls back to generic labels) ───────────────────
  const peerLabel = $derived(peerView?.label ?? 'Contact');
  const peerPluralLabel = $derived(peerView?.pluralLabel ?? 'Contacts');
  const peerEmptyState = $derived(
    peerView?.emptyState ?? 'No contacts yet — add your first contact using the + Add button above.'
  );

  let contacts = $state<BrainContact[]>([]);
  let loading = $state(true);
  let error = $state<string | null>(null);
  let selectedContact = $state<BrainContact | null>(null);
  let searchQuery = $state('');

  // ── Add Contact modal ──────────────────────────────────────────────────────
  let showAddModal = $state(false);
  let addForm = $state({ certId: '', displayName: '', publicKey: '', email: '' });
  let addBusy = $state(false);
  let addError = $state<string | null>(null);

  const filteredContacts = $derived(
    searchQuery.trim() === ''
      ? contacts
      : contacts.filter((c) =>
          c.displayName.toLowerCase().includes(searchQuery.toLowerCase()) ||
          (c.email ?? '').toLowerCase().includes(searchQuery.toLowerCase()) ||
          c.certId.toLowerCase().includes(searchQuery.toLowerCase()),
        ),
  );

  onMount(async () => {
    loading = true;
    error = null;
    const result = await listContacts(brainBase, bearer);
    contacts = result.sort((a, b) => a.displayName.localeCompare(b.displayName));
    loading = false;
  });

  async function refresh() {
    loading = true;
    error = null;
    contacts = (await listContacts(brainBase, bearer)).sort((a, b) =>
      a.displayName.localeCompare(b.displayName),
    );
    loading = false;
  }

  function openAddModal() {
    addForm = { certId: '', displayName: '', publicKey: '', email: '' };
    addError = null;
    showAddModal = true;
  }

  function closeAddModal() {
    if (addBusy) return;
    showAddModal = false;
  }

  async function submitAddContact() {
    addError = null;
    const { certId, displayName, publicKey, email } = addForm;
    if (!certId.trim()) { addError = 'Certificate ID is required.'; return; }
    if (!displayName.trim()) { addError = 'Display name is required.'; return; }
    if (!publicKey.trim()) { addError = 'Public key is required.'; return; }

    addBusy = true;
    const body: { certId: string; publicKey: string; displayName: string; email?: string } = {
      certId: certId.trim(),
      publicKey: publicKey.trim(),
      displayName: displayName.trim(),
    };
    if (email.trim()) body.email = email.trim();

    const { contact, errCode } = await addContact(brainBase, bearer, body);
    addBusy = false;

    if (!contact) {
      addError = errCode === 'already_exists'
        ? 'A contact with that certificate ID already exists.'
        : errCode === 'invalid_public_key'
          ? 'The public key is not valid — paste the full hex key.'
          : `Failed to add contact (${errCode ?? 'unknown error'}).`;
      return;
    }

    // Optimistically prepend + re-sort
    contacts = [...contacts, contact].sort((a, b) =>
      a.displayName.localeCompare(b.displayName),
    );
    showAddModal = false;
    selectedContact = contact;
  }

  function truncateCertId(certId: string): string {
    if (certId.length <= 16) return certId;
    return `${certId.slice(0, 8)}…${certId.slice(-8)}`;
  }
</script>

{#if selectedContact}
  <ContactPersonaPanel
    contact={selectedContact}
    {brainBase}
    {bearer}
    onBack={() => { selectedContact = null; void refresh(); }}
  />
{:else}
  <div class="network-view">
    <div class="view-header">
      <button class="home-btn" onclick={onGoHome} aria-label="Home">← Home</button>
      <h2 class="view-title">⨁ {peerPluralLabel}</h2>
      <div class="header-actions">
        <button class="add-btn" onclick={openAddModal} aria-label="Add contact">+ Add</button>
        <button class="refresh-btn" onclick={refresh} aria-label="Refresh contacts" disabled={loading}>
          ↻
        </button>
      </div>
    </div>

    <div class="search-bar">
      <input
        type="search"
        placeholder="Search {peerPluralLabel.toLowerCase()}…"
        bind:value={searchQuery}
        autocomplete="off"
        spellcheck={false}
      />
    </div>

    {#if loading}
      <div class="state-message">Loading contacts…</div>
    {:else if error}
      <div class="state-message error">{error}</div>
    {:else if contacts.length === 0}
      <div class="empty-state">
        <div class="empty-icon">⨁</div>
        <div class="empty-title">No {peerPluralLabel.toLowerCase()} yet</div>
        <div class="empty-body">{peerEmptyState}</div>
        <button class="empty-add-btn" onclick={openAddModal}>Add {peerLabel.toLowerCase()}</button>
      </div>
    {:else if filteredContacts.length === 0}
      <div class="state-message">No contacts match "{searchQuery}"</div>
    {:else}
      <ul class="contact-list">
        {#each filteredContacts as contact (contact.certId)}
          <li>
            <button
              class="contact-row"
              onclick={() => { selectedContact = contact; }}
            >
              <div class="contact-avatar">
                {contact.displayName[0]?.toUpperCase() ?? '?'}
              </div>
              <div class="contact-info">
                <div class="contact-name">{contact.displayName}</div>
                {#if contact.email}
                  <div class="contact-email">{contact.email}</div>
                {/if}
                <div class="contact-cert" title={contact.certId}>
                  {truncateCertId(contact.certId)}
                </div>
              </div>
              <div class="contact-chevron">›</div>
            </button>
          </li>
        {/each}
      </ul>

      <div class="contact-count">
        {filteredContacts.length} of {contacts.length} {contacts.length === 1 ? peerLabel.toLowerCase() : peerPluralLabel.toLowerCase()}
      </div>
    {/if}
  </div>
{/if}

<!-- ── Add Contact modal ─────────────────────────────────────────────────── -->
{#if showAddModal}
  <!-- svelte-ignore a11y_click_events_have_key_events a11y_no_static_element_interactions -->
  <div class="modal-backdrop" onclick={(e) => { if (e.target === e.currentTarget) closeAddModal(); }}>
    <div class="modal" role="dialog" aria-modal="true" aria-labelledby="add-contact-title">
      <div class="modal-header">
        <h3 id="add-contact-title">Add Contact</h3>
        <button class="modal-close" onclick={closeAddModal} aria-label="Close" disabled={addBusy}>✕</button>
      </div>

      <div class="modal-body">
        {#if addError}
          <p class="form-error">{addError}</p>
        {/if}

        <label class="form-label">
          Certificate ID <span class="required">*</span>
          <input
            class="form-input"
            type="text"
            placeholder="cert_…"
            bind:value={addForm.certId}
            disabled={addBusy}
            autocomplete="off"
            spellcheck={false}
          />
        </label>

        <label class="form-label">
          Display Name <span class="required">*</span>
          <input
            class="form-input"
            type="text"
            placeholder="Alice"
            bind:value={addForm.displayName}
            disabled={addBusy}
            autocomplete="off"
          />
        </label>

        <label class="form-label">
          Public Key <span class="required">*</span>
          <input
            class="form-input mono"
            type="text"
            placeholder="04ab… (secp256k1 uncompressed or compressed hex)"
            bind:value={addForm.publicKey}
            disabled={addBusy}
            autocomplete="off"
            spellcheck={false}
          />
          <span class="form-hint">
            Paste the contact's full hex public key (33 or 65 bytes).
          </span>
        </label>

        <label class="form-label">
          Email <span class="optional">(optional)</span>
          <input
            class="form-input"
            type="email"
            placeholder="alice@example.com"
            bind:value={addForm.email}
            disabled={addBusy}
            autocomplete="off"
          />
        </label>
      </div>

      <div class="modal-footer">
        <button class="btn-cancel" onclick={closeAddModal} disabled={addBusy}>Cancel</button>
        <button
          class="btn-submit"
          onclick={submitAddContact}
          disabled={addBusy || !addForm.certId.trim() || !addForm.displayName.trim() || !addForm.publicKey.trim()}
        >
          {addBusy ? 'Adding…' : 'Add Contact'}
        </button>
      </div>
    </div>
  </div>
{/if}

<style>
  .network-view {
    display: flex;
    flex-direction: column;
    height: 100%;
    background: #0f172a;
    color: #e2e8f0;
    overflow: hidden;
  }

  .view-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 0.75rem 1rem;
    border-bottom: 1px solid #1e293b;
    background: #111827;
  }

  .header-actions {
    display: flex;
    align-items: center;
    gap: 0.5rem;
  }

  .home-btn, .refresh-btn {
    background: transparent;
    border: none;
    color: #60a5fa;
    font-size: 0.875rem;
    cursor: pointer;
    padding: 0.25rem 0.5rem;
    border-radius: 0.25rem;
    transition: color 0.1s, background 0.1s;
  }

  .home-btn:hover, .refresh-btn:hover {
    color: #93c5fd;
    background: rgba(96, 165, 250, 0.1);
  }

  .refresh-btn:disabled { opacity: 0.4; cursor: default; }

  .add-btn {
    background: #1d4ed8;
    border: none;
    color: #fff;
    font-size: 0.8125rem;
    font-weight: 600;
    cursor: pointer;
    padding: 0.25rem 0.625rem;
    border-radius: 0.25rem;
    transition: background 0.1s;
  }

  .add-btn:hover { background: #2563eb; }

  .view-title {
    font-size: 1rem;
    font-weight: 600;
    margin: 0;
    color: #f1f5f9;
  }

  .search-bar {
    padding: 0.75rem 1rem;
    border-bottom: 1px solid #1e293b;
  }

  .search-bar input {
    width: 100%;
    background: #1e293b;
    border: 1px solid #334155;
    border-radius: 0.5rem;
    color: #e2e8f0;
    font-size: 0.875rem;
    padding: 0.5rem 0.75rem;
    outline: none;
    box-sizing: border-box;
    transition: border-color 0.15s;
  }

  .search-bar input::placeholder { color: #475569; }
  .search-bar input:focus { border-color: #3b82f6; }

  .state-message {
    padding: 2rem;
    text-align: center;
    color: #64748b;
    font-size: 0.875rem;
  }

  .state-message.error { color: #f87171; }

  .empty-state {
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    flex: 1;
    padding: 2rem;
    gap: 0.5rem;
  }

  .empty-icon { font-size: 2.5rem; color: #334155; }
  .empty-title { font-size: 1rem; font-weight: 600; color: #94a3b8; }
  .empty-body { font-size: 0.8125rem; color: #475569; text-align: center; max-width: 240px; }

  .empty-add-btn {
    margin-top: 0.75rem;
    background: #1d4ed8;
    border: none;
    color: #fff;
    font-size: 0.875rem;
    font-weight: 600;
    cursor: pointer;
    padding: 0.5rem 1.25rem;
    border-radius: 0.375rem;
    transition: background 0.1s;
  }

  .empty-add-btn:hover { background: #2563eb; }

  .contact-list {
    list-style: none;
    padding: 0;
    margin: 0;
    overflow-y: auto;
    flex: 1;
  }

  .contact-row {
    display: flex;
    align-items: center;
    gap: 0.75rem;
    width: 100%;
    padding: 0.75rem 1rem;
    background: transparent;
    border: none;
    border-bottom: 1px solid #1e293b;
    color: inherit;
    text-align: left;
    cursor: pointer;
    transition: background 0.1s;
  }

  .contact-row:hover { background: #1e293b; }
  .contact-row:active { background: #263548; }

  .contact-avatar {
    width: 40px;
    height: 40px;
    border-radius: 50%;
    background: #1d4ed8;
    color: #fff;
    font-size: 1rem;
    font-weight: 700;
    display: flex;
    align-items: center;
    justify-content: center;
    flex-shrink: 0;
  }

  .contact-info {
    flex: 1;
    display: flex;
    flex-direction: column;
    gap: 1px;
    overflow: hidden;
  }

  .contact-name {
    font-size: 0.9375rem;
    font-weight: 500;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .contact-email {
    font-size: 0.75rem;
    color: #94a3b8;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .contact-cert {
    font-size: 0.6875rem;
    font-family: monospace;
    color: #475569;
  }

  .contact-chevron {
    color: #334155;
    font-size: 1.25rem;
    flex-shrink: 0;
  }

  .contact-count {
    padding: 0.5rem 1rem;
    font-size: 0.75rem;
    color: #475569;
    text-align: center;
    border-top: 1px solid #1e293b;
    background: #111827;
  }

  /* ── Modal ── */
  .modal-backdrop {
    position: fixed;
    inset: 0;
    background: rgba(0, 0, 0, 0.6);
    display: flex;
    align-items: center;
    justify-content: center;
    z-index: 500;
    padding: 1rem;
  }

  .modal {
    background: #1e293b;
    border: 1px solid #334155;
    border-radius: 0.75rem;
    width: 100%;
    max-width: 420px;
    box-shadow: 0 16px 48px rgba(0, 0, 0, 0.5);
    display: flex;
    flex-direction: column;
  }

  .modal-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 1rem 1.25rem 0.75rem;
    border-bottom: 1px solid #334155;
  }

  .modal-header h3 {
    margin: 0;
    font-size: 1rem;
    font-weight: 600;
    color: #f1f5f9;
  }

  .modal-close {
    background: transparent;
    border: none;
    color: #64748b;
    font-size: 1rem;
    cursor: pointer;
    padding: 0.25rem;
    line-height: 1;
    border-radius: 0.25rem;
    transition: color 0.1s, background 0.1s;
  }

  .modal-close:hover:not(:disabled) { color: #e2e8f0; background: rgba(255,255,255,0.05); }
  .modal-close:disabled { opacity: 0.3; cursor: default; }

  .modal-body {
    padding: 1rem 1.25rem;
    display: flex;
    flex-direction: column;
    gap: 0.875rem;
  }

  .form-error {
    margin: 0;
    padding: 0.5rem 0.75rem;
    background: rgba(239, 68, 68, 0.1);
    border: 1px solid rgba(239, 68, 68, 0.25);
    border-radius: 0.375rem;
    font-size: 0.8125rem;
    color: #f87171;
  }

  .form-label {
    display: flex;
    flex-direction: column;
    gap: 0.3rem;
    font-size: 0.8125rem;
    font-weight: 500;
    color: #94a3b8;
  }

  .required { color: #f87171; font-weight: 400; }
  .optional { color: #64748b; font-weight: 400; font-size: 0.75rem; }

  .form-input {
    background: #0f172a;
    border: 1px solid #334155;
    border-radius: 0.375rem;
    color: #e2e8f0;
    font-size: 0.875rem;
    padding: 0.5rem 0.625rem;
    outline: none;
    transition: border-color 0.15s;
    width: 100%;
    box-sizing: border-box;
  }

  .form-input::placeholder { color: #334155; }
  .form-input:focus { border-color: #3b82f6; }
  .form-input:disabled { opacity: 0.5; cursor: not-allowed; }
  .form-input.mono { font-family: ui-monospace, monospace; font-size: 0.75rem; }

  .form-hint {
    font-size: 0.75rem;
    color: #475569;
    font-weight: 400;
  }

  .modal-footer {
    display: flex;
    justify-content: flex-end;
    gap: 0.75rem;
    padding: 0.75rem 1.25rem 1rem;
    border-top: 1px solid #334155;
  }

  .btn-cancel {
    background: transparent;
    border: 1px solid #334155;
    color: #94a3b8;
    font-size: 0.875rem;
    cursor: pointer;
    padding: 0.4rem 1rem;
    border-radius: 0.375rem;
    transition: background 0.1s, color 0.1s;
  }

  .btn-cancel:hover:not(:disabled) { background: rgba(255,255,255,0.04); color: #e2e8f0; }
  .btn-cancel:disabled { opacity: 0.4; cursor: default; }

  .btn-submit {
    background: #1d4ed8;
    border: none;
    color: #fff;
    font-size: 0.875rem;
    font-weight: 600;
    cursor: pointer;
    padding: 0.4rem 1.25rem;
    border-radius: 0.375rem;
    transition: background 0.1s;
  }

  .btn-submit:hover:not(:disabled) { background: #2563eb; }
  .btn-submit:disabled { opacity: 0.4; cursor: default; }
</style>

```
