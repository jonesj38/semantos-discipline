---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/semantos/assets/wallet/wallet-page.js
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.122490+00:00
---

# apps/semantos/assets/wallet/wallet-page.js

```js
/*
 * C11 PR-C11-4d — Wallet renderer (stripped).
 *
 * Implements the renderer side of the `SemantosWallet` bridge per
 * `docs/design/WALLET-RENDERER-CONTRACT.md` §3.
 *
 * Hard constraints (contract §1 + §4):
 *   - This file generates no key material.
 *   - This file computes no signature.
 *   - This file makes no network request.
 *   - This file persists no private data.
 *
 * Everything cryptographic lives in Dart (`apps/semantos/lib/src/wallet/`).
 * This file's job is to render state pushed from Dart and to forward
 * user intent back via the bridge.
 *
 * Bridge transport:
 *   Dart → JS:   `window.SemantosWallet_dispatch(envelope)` — Dart calls
 *                `_controller.runJavaScript(
 *                   "window.SemantosWallet_dispatch(" + json + ")"
 *                 )` (wired in PR-C11-4e).
 *   JS → Dart:   `window.SemantosWallet.postMessage(JSON.stringify(env))`
 *                — the `JavaScriptChannel` handler in `wallet_launch.dart`
 *                (also 4e).
 *
 * Until 4e ships the Dart-side channel, the renderer stays in its
 * "waiting for shell" state and `sendOrWarn` will toast on every
 * outbound attempt. That is the expected interim — see
 * WALLET-RENDERER-CONTRACT.md §9.
 *
 * Envelope shape (contract §3):
 *   { id: <uuid-v7>, kind: <message-kind>, payload: { ... } }
 */

(function () {
  'use strict';

  // ─────────────── state ───────────────

  const state = {
    identity: null,         // { certIdHex, tier0Pub, displayName, recoverable }
    balance: null,          // { totalSats, perContext: { ctx: sats } }
    utxos: [],              // [{ txid, vout, value, recipeId, index, scriptHex }]
    pendingPreview: null,   // { previewId, txHex, inputs, outputs, feeSats, summaryText }
    receive: null,          // { address, recipeId, index, contextLabel }
    derivation: null,       // { recipeId, pubs: [{index, pub}] }
    lastEvent: null,        // { ts, kind, direction: 'in'|'out' }
    bridgeReady: false,     // becomes true after first successful inbound message
  };

  const eventLog = []; // ring buffer of last ~20 events for diagnostics

  // ─────────────── bridge primitives ───────────────

  /** Best-effort RFC 4122-ish identifier. `crypto.randomUUID` may not
   *  be present in the embedded WebView; fall back to timestamp + rand. */
  function newId() {
    if (typeof crypto !== 'undefined' && typeof crypto.randomUUID === 'function') {
      return crypto.randomUUID();
    }
    return (
      Date.now().toString(16) + '-' +
      Math.floor(Math.random() * 0xffffffff).toString(16)
    );
  }

  /** Send an envelope to Dart. Returns true if the channel was present,
   *  false otherwise (renderer continues; user sees the "no bridge" state). */
  function send(kind, payload) {
    const env = { id: newId(), kind: kind, payload: payload || {} };
    pushEvent(kind, 'out');
    const ch = window.SemantosWallet;
    if (ch && typeof ch.postMessage === 'function') {
      try {
        ch.postMessage(JSON.stringify(env));
        return true;
      } catch (e) {
        console.error('[wallet-renderer] send failed:', e);
        return false;
      }
    }
    // Dev / 4d interim — no channel yet; log for visibility.
    console.warn('[wallet-renderer] no SemantosWallet channel; dropping', env);
    return false;
  }

  /** Inbound dispatcher. Exposed at `window.SemantosWallet_dispatch` so
   *  Dart can push state in via `runJavaScript`. */
  function dispatch(env) {
    if (!env || typeof env !== 'object') {
      console.warn('[wallet-renderer] dropped non-object envelope', env);
      return;
    }
    state.bridgeReady = true;
    pushEvent(env.kind, 'in');
    const handler = inboundHandlers[env.kind];
    if (typeof handler !== 'function') {
      console.warn('[wallet-renderer] no handler for', env.kind);
      return;
    }
    try {
      handler(env.payload || {});
    } catch (e) {
      console.error('[wallet-renderer] handler', env.kind, 'threw:', e);
    }
    render();
  }
  window.SemantosWallet_dispatch = dispatch;

  function pushEvent(kind, direction) {
    state.lastEvent = { ts: Date.now(), kind: kind, direction: direction };
    eventLog.push(state.lastEvent);
    if (eventLog.length > 20) eventLog.shift();
  }

  // ─────────────── inbound handlers (Dart → renderer) ───────────────

  const inboundHandlers = {
    'identity.set': function (p) {
      state.identity = {
        certIdHex: p.certIdHex || '',
        tier0Pub: p.tier0Pub || '',
        displayName: p.displayName || '',
        recoverable: !!p.recoverable,
      };
    },

    'balance.update': function (p) {
      state.balance = {
        totalSats: typeof p.totalSats === 'number' ? p.totalSats : 0,
        perContext: p.perContext || {},
      };
    },

    'utxos.list': function (p) {
      // Accept either the contract's "array as payload" form or a
      // wrapped { rows: [...] } / { utxos: [...] } payload — Dart's
      // typed envelope carries a Map, so the bridge wraps. Both
      // shapes are valid in practice.
      if (Array.isArray(p)) {
        state.utxos = p;
      } else if (Array.isArray(p.rows)) {
        state.utxos = p.rows;
      } else if (Array.isArray(p.utxos)) {
        state.utxos = p.utxos;
      } else {
        state.utxos = [];
      }
    },

    'tx.preview': function (p) {
      state.pendingPreview = {
        previewId: p.previewId || newId(),
        txHex: p.txHex || '',
        inputs: p.inputs || [],
        outputs: p.outputs || [],
        feeSats: typeof p.feeSats === 'number' ? p.feeSats : 0,
        summaryText: p.summaryText || '',
      };
    },

    'tx.broadcast.done': function (p) {
      state.pendingPreview = null;
      if (p.status === 'ok') {
        toast('Broadcast: ' + (p.txid || '(no txid)'));
      } else {
        toast('Broadcast failed: ' + (p.error || 'unknown'), true);
      }
    },

    'error.show': function (p) {
      toast(p.message || 'Unknown error', true);
    },

    'address.reply': function (p) {
      state.receive = {
        address: p.address || '',
        recipeId: p.recipeId || '',
        index: typeof p.index === 'number' ? p.index : -1,
        contextLabel: p.contextLabel || '',
      };
    },

    'derivation.reply': function (p) {
      state.derivation = {
        recipeId: p.recipeId || '',
        pubs: Array.isArray(p.pubs) ? p.pubs : [],
      };
    },
  };

  // ─────────────── transient toasts ───────────────

  let toastTimer = null;
  function toast(message, isError) {
    const el = document.getElementById('toast');
    if (!el) return;
    el.textContent = message;
    el.className = isError ? 'badge-error' : 'badge-ok';
    if (toastTimer) clearTimeout(toastTimer);
    toastTimer = setTimeout(function () {
      el.textContent = '';
      el.className = '';
    }, 4000);
  }

  // ─────────────── rendering ───────────────

  function render() {
    const app = document.getElementById('app');
    if (!app) return;
    app.innerHTML = '';
    app.appendChild(renderIdentityPanel());
    app.appendChild(renderBalancePanel());
    app.appendChild(renderSendPanel());
    app.appendChild(renderReceivePanel());
    app.appendChild(renderPreviewPanel());
    app.appendChild(renderUtxosPanel());
    app.appendChild(renderDebugPanel());
  }

  function panel(title, body) {
    const div = document.createElement('div');
    div.className = 'panel';
    const h = document.createElement('h3');
    h.textContent = title;
    div.appendChild(h);
    div.appendChild(body);
    return div;
  }

  function renderIdentityPanel() {
    const body = document.createElement('div');
    if (state.identity) {
      const p = document.createElement('p');
      p.innerHTML =
        'Cert: <span class="mono">' + esc(state.identity.certIdHex) + '</span><br>' +
        'Tier-0 pub: <span class="mono">' + esc(state.identity.tier0Pub) + '</span><br>' +
        (state.identity.displayName ? 'Name: ' + esc(state.identity.displayName) + '<br>' : '') +
        'Recoverable: ' + (state.identity.recoverable
          ? '<span class="badge-ok">yes</span>'
          : '<span class="badge-pending">no (set up secret questions in Me sheet)</span>');
      body.appendChild(p);
    } else {
      const p = document.createElement('p');
      p.className = 'hint';
      p.textContent = state.bridgeReady
        ? 'No identity is bound yet. Set up your operator identity in the Me sheet.'
        : 'Waiting for shell to bind identity...';
      body.appendChild(p);
    }
    return panel('Identity', body);
  }

  function renderBalancePanel() {
    const body = document.createElement('div');
    if (state.balance) {
      const total = document.createElement('p');
      total.innerHTML =
        'Total: <span class="mono">' + state.balance.totalSats + ' sats</span>';
      body.appendChild(total);
      const ctxKeys = Object.keys(state.balance.perContext || {});
      if (ctxKeys.length > 0) {
        const ul = document.createElement('ul');
        ul.style.margin = '0.4em 0 0 1em';
        ul.style.padding = '0';
        ctxKeys.forEach(function (k) {
          const li = document.createElement('li');
          li.innerHTML = '<span class="mono">' + esc(k) + '</span>: ' +
            state.balance.perContext[k] + ' sats';
          ul.appendChild(li);
        });
        body.appendChild(ul);
      }
    } else {
      const p = document.createElement('p');
      p.className = 'hint';
      p.textContent = 'No balance reported yet.';
      body.appendChild(p);
    }
    return panel('Balance', body);
  }

  function renderSendPanel() {
    const body = document.createElement('div');
    const recipient = inputField('to-input', 'recipient (address or pub)');
    const amount = inputField('amount-input', 'amount (sats)');
    amount.type = 'number';
    const ctx = inputField('context-input', 'context (e.g. oddjobz/payout)');
    const memo = inputField('memo-input', 'memo (optional)');

    body.appendChild(rowOf([recipient]));
    body.appendChild(rowOf([amount]));
    body.appendChild(rowOf([ctx]));
    body.appendChild(rowOf([memo]));

    const sendBtn = document.createElement('button');
    sendBtn.textContent = 'Send';
    sendBtn.disabled = !state.identity;
    sendBtn.title = state.identity
      ? 'Send a tx via the shell wallet'
      : 'Identity must be bound first';
    sendBtn.onclick = function () {
      const payload = {
        recipientAddrOrPub: recipient.value.trim(),
        amountSats: Number(amount.value) || 0,
        contextLabel: ctx.value.trim(),
        memo: memo.value.trim(),
      };
      sendOrWarn('tx.request', payload);
    };
    body.appendChild(sendBtn);

    return panel('Send', body);
  }

  function renderReceivePanel() {
    const body = document.createElement('div');
    const ctx = inputField('recv-context-input',
      'context (e.g. oddjobz/payout)');
    body.appendChild(rowOf([ctx]));
    const btn = document.createElement('button');
    btn.textContent = 'Get receive address';
    btn.disabled = !state.identity;
    btn.onclick = function () {
      sendOrWarn('address.request', { contextLabel: ctx.value.trim() });
    };
    body.appendChild(btn);
    if (state.receive) {
      const result = document.createElement('p');
      result.innerHTML =
        'Address: <span class="mono">' + esc(state.receive.address) +
        '</span><br>' +
        'Recipe: <span class="mono">' + esc(state.receive.recipeId) +
        '#' + state.receive.index + '</span>' +
        (state.receive.contextLabel
          ? '<br>Context: <span class="mono">' + esc(state.receive.contextLabel) + '</span>'
          : '');
      body.appendChild(result);
    }
    return panel('Receive', body);
  }

  function renderPreviewPanel() {
    if (!state.pendingPreview) {
      const empty = document.createElement('p');
      empty.className = 'hint';
      empty.textContent = 'No pending transaction.';
      return panel('Pending transaction', empty);
    }
    const body = document.createElement('div');
    const p = document.createElement('p');
    p.innerHTML =
      esc(state.pendingPreview.summaryText) +
      '<br><span class="mono">fee: ' + state.pendingPreview.feeSats + ' sats</span>';
    body.appendChild(p);
    const confirm = document.createElement('button');
    confirm.textContent = 'Confirm';
    confirm.onclick = function () {
      send('tx.confirm', { previewId: state.pendingPreview.previewId });
    };
    const cancel = document.createElement('button');
    cancel.className = 'secondary';
    cancel.textContent = 'Cancel';
    cancel.onclick = function () {
      send('tx.cancel', { previewId: state.pendingPreview.previewId });
      state.pendingPreview = null;
      render();
    };
    cancel.style.marginLeft = '0.5em';
    body.appendChild(confirm);
    body.appendChild(cancel);
    return panel('Pending transaction', body);
  }

  function renderUtxosPanel() {
    const body = document.createElement('div');
    if (state.utxos.length === 0) {
      const empty = document.createElement('p');
      empty.className = 'utxo-empty';
      empty.textContent = 'No UTXOs.';
      body.appendChild(empty);
    } else {
      state.utxos.forEach(function (u) {
        const row = document.createElement('div');
        row.className = 'utxo-row';
        const status = u.status || 'unknown';
        const badgeClass = status === 'confirmed'
          ? 'badge-ok'
          : status === 'spent'
            ? 'badge-pending'
            : '';
        const outpoint = u.txid
          ? esc(u.txid.slice(0, 12)) + '…:' + (u.vout != null ? u.vout : '?')
          : '(watching)';
        const valueStr = u.value && u.value > 0
          ? u.value + ' sats'
          : '— sats';
        const addr = u.address
          ? ' <span class="mono">' + esc(u.address) + '</span>'
          : '';
        row.innerHTML =
          '<span class="' + badgeClass + '">' + esc(status) + '</span> ' +
          outpoint + ' &mdash; ' + valueStr +
          ' <span class="mono">[' + esc(u.recipeId || '') +
          '#' + (u.index != null ? u.index : '?') + ']</span>' + addr;
        body.appendChild(row);
      });
    }
    return panel('UTXOs', body);
  }

  function renderDebugPanel() {
    const body = document.createElement('div');
    const status = document.createElement('p');
    status.className = 'hint';
    status.innerHTML = state.bridgeReady
      ? '<span class="badge-ok">Bridge: connected</span>'
      : '<span class="badge-pending">Bridge: waiting for shell</span>';
    body.appendChild(status);

    const toastEl = document.createElement('p');
    toastEl.id = 'toast';
    body.appendChild(toastEl);

    const log = document.createElement('pre');
    log.className = 'log';
    log.textContent = eventLog.length === 0
      ? '(no bridge events yet)'
      : eventLog.map(function (e) {
          const dir = e.direction === 'in' ? '<-' : '->';
          return new Date(e.ts).toISOString().slice(11, 19) +
            ' ' + dir + ' ' + e.kind;
        }).join('\n');
    body.appendChild(log);

    return panel('Bridge diagnostics', body);
  }

  // ─────────────── element helpers ───────────────

  function inputField(id, placeholder) {
    const el = document.createElement('input');
    el.className = 'field';
    el.id = id;
    el.placeholder = placeholder;
    return el;
  }

  function rowOf(children) {
    const div = document.createElement('div');
    div.className = 'row';
    children.forEach(function (c) { div.appendChild(c); });
    return div;
  }

  function sendOrWarn(kind, payload) {
    const ok = send(kind, payload);
    if (!ok) {
      toast('Bridge not connected (PR-C11-4e wires this); intent dropped.', true);
    }
    render();
  }

  function esc(s) {
    return String(s)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#39;');
  }

  // ─────────────── boot ───────────────

  // Render once before announcing — Dart may dispatch `identity.set`
  // synchronously in response to `ready`, and we want a layout to
  // exist when that happens.
  render();
  send('ready', { rendererVersion: '4d-stub-1' });
})();

```
