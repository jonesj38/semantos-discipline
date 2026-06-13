---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/public/chat-widget/chat-widget.js
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.554027+00:00
---

# cartridges/oddjobz/brain/public/chat-widget/chat-widget.js

```js
/**
 * Oddjobz public chat v0.5 widget.
 *
 * D-O6a — see docs/design/ODDJOBZ-EXTENSION-PLAN.md §O6 +
 * docs/design/BRAIN-DISPATCHER-UNIFICATION.md §3 line 182.
 *
 * Usage (one script tag + one mount point):
 *
 *     <link rel="stylesheet" href="/chat-widget/chat-widget.css">
 *     <div id="oddjobz-chat-widget"></div>
 *     <script src="/chat-widget/chat-widget.js" defer></script>
 *
 * The widget mounts into `#oddjobz-chat-widget` (or a configurable
 * `data-mount` selector) and POSTs visitor messages to
 * `/api/v1/chat` (configurable via `data-endpoint`).  No external
 * deps; no build step.
 *
 * Wire shape: POST → { message, session_id }; reply → { reply, model,
 * tokens_used }.  Errors (4xx/5xx) surface as a system bubble to the
 * visitor — the body's `error` field is shown so operators can debug
 * without opening devtools.
 *
 * Same-origin only on v0.5 (CORS preflight lands with D-W1 Phase 3 +
 * brain issue #273).  Embed the widget on the same domain that hosts
 * the chat endpoint.
 *
 * Accessibility:
 *   • Messages live region uses aria-live="polite".
 *   • Input is auto-focused on mount.
 *   • Enter sends (Shift+Enter inserts a newline).
 *   • Visible focus styles via CSS (no aggressive outline reset).
 */

(function () {
  'use strict';

  // ── Config ────────────────────────────────────────────────────────
  const DEFAULT_ENDPOINT = '/api/v1/chat';
  const DEFAULT_MOUNT_ID = 'oddjobz-chat-widget';
  const DEFAULT_TITLE = 'Chat with us';
  const DEFAULT_PLACEHOLDER = "Ask a question, or describe a job...";
  const DEFAULT_GREETING = "Hi! I'm here to help. What can I do for you?";

  // ── Customer-link mode — detect token in URL path ──────────────────
  // When the widget loads at ojt.info/ae3cef123 (a customer reply link),
  // the path segment is a customer link token. Use it to resume the
  // existing conversation instead of generating a new session_id.
  function getCustomerLinkToken() {
    const parts = window.location.pathname.split('/').filter(Boolean);
    if (parts.length === 1 && /^[a-z0-9]{8,12}$/.test(parts[0])) {
      return parts[0];
    }
    return null;
  }
  const CUSTOMER_LINK_TOKEN = getCustomerLinkToken();

  // ── Session id — opaque, persistent across page reloads via
  //    sessionStorage so a visitor's chat thread holds together for
  //    one tab session.  D-O6a doesn't thread it through to the
  //    backend (no persistence); D-O6b will. ─────────────────────────
  function getSessionId() {
    try {
      const k = 'oddjobz-chat-session-id';
      let v = sessionStorage.getItem(k);
      if (!v) {
        v = generateSessionId();
        sessionStorage.setItem(k, v);
      }
      return v;
    } catch (_) {
      // Storage may be disabled (private browsing, sandboxed iframe, ...);
      // fall back to a transient id for this page load.
      return generateSessionId();
    }
  }

  function generateSessionId() {
    // 16 random bytes hex-encoded — enough collision-resistance for
    // a per-tab opaque thread id.
    const buf = new Uint8Array(16);
    if (typeof crypto !== 'undefined' && crypto.getRandomValues) {
      crypto.getRandomValues(buf);
    } else {
      for (let i = 0; i < 16; i++) buf[i] = Math.floor(Math.random() * 256);
    }
    let out = '';
    for (let i = 0; i < buf.length; i++) {
      out += buf[i].toString(16).padStart(2, '0');
    }
    return out;
  }

  // ── DOM helpers ───────────────────────────────────────────────────
  function el(tag, attrs, children) {
    const node = document.createElement(tag);
    if (attrs) {
      for (const k of Object.keys(attrs)) {
        if (k === 'className') node.className = attrs[k];
        else if (k.startsWith('on') && typeof attrs[k] === 'function') {
          node.addEventListener(k.slice(2).toLowerCase(), attrs[k]);
        } else if (k === 'aria') {
          for (const ak of Object.keys(attrs.aria)) {
            node.setAttribute('aria-' + ak, attrs.aria[ak]);
          }
        } else {
          node.setAttribute(k, attrs[k]);
        }
      }
    }
    if (children) {
      for (const c of children) {
        if (c == null) continue;
        node.appendChild(typeof c === 'string' ? document.createTextNode(c) : c);
      }
    }
    return node;
  }

  // ── Widget construction ───────────────────────────────────────────
  function mount(target, opts) {
    const endpoint = opts.endpoint || DEFAULT_ENDPOINT;
    const title = opts.title || DEFAULT_TITLE;
    const placeholder = opts.placeholder || DEFAULT_PLACEHOLDER;
    // Customer-link mode overrides the default greeting.
    const defaultGreeting = CUSTOMER_LINK_TOKEN
      ? 'Hi! You can type your reply or add details below.'
      : DEFAULT_GREETING;
    const greeting = opts.greeting || defaultGreeting;

    target.classList.add('oddjobz-chat-widget');
    target.innerHTML = '';

    const titleEl = el('div', {
      className: 'oddjobz-chat-title',
      role: 'heading',
      'aria-level': '2',
    }, [title]);

    const messagesEl = el('div', {
      className: 'oddjobz-chat-messages',
      role: 'log',
      aria: { live: 'polite', atomic: 'false' },
    });

    const inputEl = el('textarea', {
      className: 'oddjobz-chat-input',
      placeholder: placeholder,
      rows: '2',
      aria: { label: 'Type your message' },
    });

    const sendBtn = el('button', {
      className: 'oddjobz-chat-send',
      type: 'button',
      aria: { label: 'Send message' },
    }, ['Send']);

    const inputRow = el('div', { className: 'oddjobz-chat-input-row' }, [
      inputEl,
      sendBtn,
    ]);

    target.appendChild(titleEl);
    target.appendChild(messagesEl);
    target.appendChild(inputRow);

    // Customer-link mode: resolve the token before greeting.
    // Fetch the conversation context and show a banner above the chat.
    if (CUSTOMER_LINK_TOKEN) {
      // Show loading state while we resolve.
      const bannerEl = el('div', { className: 'oddjobz-chat-context-banner' }, [
        'Loading your conversation...',
      ]);
      target.insertBefore(bannerEl, messagesEl);

      // Disable input while resolving.
      inputEl.disabled = true;
      sendBtn.disabled = true;

      fetch('/api/v1/c/' + CUSTOMER_LINK_TOKEN)
        .then(function (r) { return r.json(); })
        .then(function (data) {
          if (data && data.ok && data.entityTitle) {
            bannerEl.textContent = "You're here to reply about: " + data.entityTitle;
          } else {
            bannerEl.textContent = 'This link has expired or is invalid.';
            inputEl.disabled = true;
            sendBtn.disabled = true;
            return;
          }
          inputEl.disabled = false;
          sendBtn.disabled = false;
          appendBubble(messagesEl, 'bot', greeting);
          inputEl.focus();
        })
        .catch(function () {
          bannerEl.textContent = 'This link has expired or is invalid.';
          inputEl.disabled = true;
          sendBtn.disabled = true;
        });
    } else {
      // Normal mode: show greeting immediately.
      appendBubble(messagesEl, 'bot', greeting);
    }

    let inFlight = false;
    function setSending(state) {
      inFlight = state;
      sendBtn.disabled = state;
      inputEl.disabled = state;
      sendBtn.textContent = state ? 'Sending...' : 'Send';
    }

    async function send() {
      if (inFlight) return;
      const message = inputEl.value.trim();
      if (!message) return;
      inputEl.value = '';
      appendBubble(messagesEl, 'user', message);
      setSending(true);
      try {
        let reply;
        if (CUSTOMER_LINK_TOKEN) {
          // Customer-link mode: send token so the backend can associate
          // the reply with the correct conversation.
          reply = await postChat(endpoint, message, null, CUSTOMER_LINK_TOKEN);
        } else {
          reply = await postChat(endpoint, message, getSessionId(), null);
        }
        appendBubble(messagesEl, 'bot', reply);
      } catch (err) {
        appendBubble(messagesEl, 'system', '[error] ' + err.message);
      } finally {
        setSending(false);
        // Restore focus to input after each round-trip.
        inputEl.focus();
      }
    }

    sendBtn.addEventListener('click', send);
    inputEl.addEventListener('keydown', function (ev) {
      // Enter sends; Shift+Enter inserts a newline.
      if (ev.key === 'Enter' && !ev.shiftKey) {
        ev.preventDefault();
        send();
      }
    });

    // Auto-focus on mount (only in normal mode; customer-link waits for resolve).
    if (!CUSTOMER_LINK_TOKEN) {
      setTimeout(function () { inputEl.focus(); }, 0);
    }
  }

  function appendBubble(container, kind, text) {
    const bubble = el('div', {
      className: 'oddjobz-chat-bubble oddjobz-chat-bubble-' + kind,
    }, [text]);
    container.appendChild(bubble);
    // Scroll the new message into view.
    container.scrollTop = container.scrollHeight;
  }

  // ── Network ───────────────────────────────────────────────────────
  // `sessionId` and `conversationToken` are mutually exclusive:
  //   - normal mode: sessionId set, conversationToken null
  //   - customer-link mode: conversationToken set, sessionId null
  async function postChat(endpoint, message, sessionId, conversationToken) {
    let response;
    try {
      const payload = conversationToken
        ? { message: message, conversation_token: conversationToken }
        : { message: message, session_id: sessionId };
      response = await fetch(endpoint, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(payload),
        // Same-origin only on v0.5; let the browser enforce it.
        credentials: 'same-origin',
      });
    } catch (netErr) {
      throw new Error('network: ' + (netErr.message || 'connection failed'));
    }
    let body;
    try {
      body = await response.json();
    } catch (_) {
      throw new Error('http ' + response.status + ' (non-JSON response)');
    }
    if (!response.ok) {
      const detail = (body && body.error) ? body.error : ('http ' + response.status);
      throw new Error(detail);
    }
    if (typeof body.reply !== 'string') {
      throw new Error('malformed response (no reply field)');
    }
    return body.reply;
  }

  // ── Auto-mount on DOMContentLoaded ────────────────────────────────
  function autoMount() {
    const target = document.getElementById(DEFAULT_MOUNT_ID);
    if (!target) return;
    const opts = {
      endpoint: target.getAttribute('data-endpoint') || undefined,
      title: target.getAttribute('data-title') || undefined,
      placeholder: target.getAttribute('data-placeholder') || undefined,
      greeting: target.getAttribute('data-greeting') || undefined,
    };
    mount(target, opts);
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', autoMount);
  } else {
    autoMount();
  }

  // Expose a programmatic mount entry point for callers who don't
  // want to use the auto-mount + default id.
  window.OddjobzChatWidget = {
    mount: mount,
    version: '0.5.0-D-O6a',
  };
})();

```
