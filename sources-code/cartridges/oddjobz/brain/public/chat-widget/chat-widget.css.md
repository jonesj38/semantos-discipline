---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/public/chat-widget/chat-widget.css
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.554922+00:00
---

# cartridges/oddjobz/brain/public/chat-widget/chat-widget.css

```css
/* Oddjobz public chat v0.5 widget — D-O6a.
 *
 * Minimal styling, designed to drop into any landing page.  The widget
 * uses the `.oddjobz-chat-widget` class on the mount node + descendant
 * classes for each part — no global selectors so it shouldn't fight
 * with the host page's stylesheet.
 *
 * Sizing: the widget is a fixed-width column by default, but operators
 * can override `--oddjobz-chat-width` / `--oddjobz-chat-height` on the
 * mount node to slot it into a sidebar / footer / floating-bubble.
 */

.oddjobz-chat-widget {
  --oddjobz-chat-width: 360px;
  --oddjobz-chat-height: 500px;
  --oddjobz-chat-bg: #ffffff;
  --oddjobz-chat-border: #d8dde3;
  --oddjobz-chat-user-bg: #2563eb;
  --oddjobz-chat-user-fg: #ffffff;
  --oddjobz-chat-bot-bg: #f1f3f7;
  --oddjobz-chat-bot-fg: #0f172a;
  --oddjobz-chat-system-bg: #fef3c7;
  --oddjobz-chat-system-fg: #78350f;
  --oddjobz-chat-radius: 12px;

  display: flex;
  flex-direction: column;
  width: var(--oddjobz-chat-width);
  height: var(--oddjobz-chat-height);
  border: 1px solid var(--oddjobz-chat-border);
  border-radius: var(--oddjobz-chat-radius);
  background: var(--oddjobz-chat-bg);
  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto,
               "Helvetica Neue", Arial, sans-serif;
  font-size: 14px;
  line-height: 1.45;
  color: var(--oddjobz-chat-bot-fg);
  overflow: hidden;
  box-shadow: 0 4px 14px rgba(15, 23, 42, 0.08);
}

.oddjobz-chat-title {
  padding: 12px 16px;
  font-weight: 600;
  font-size: 15px;
  border-bottom: 1px solid var(--oddjobz-chat-border);
  background: linear-gradient(to bottom, #fafbfc, var(--oddjobz-chat-bg));
}

.oddjobz-chat-messages {
  flex: 1 1 auto;
  overflow-y: auto;
  padding: 12px 12px 4px;
  display: flex;
  flex-direction: column;
  gap: 8px;
  scroll-behavior: smooth;
}

.oddjobz-chat-bubble {
  max-width: 85%;
  padding: 8px 12px;
  border-radius: 14px;
  word-wrap: break-word;
  white-space: pre-wrap;
  font-size: 14px;
}

.oddjobz-chat-bubble-user {
  align-self: flex-end;
  background: var(--oddjobz-chat-user-bg);
  color: var(--oddjobz-chat-user-fg);
  border-bottom-right-radius: 4px;
}

.oddjobz-chat-bubble-bot {
  align-self: flex-start;
  background: var(--oddjobz-chat-bot-bg);
  color: var(--oddjobz-chat-bot-fg);
  border-bottom-left-radius: 4px;
}

.oddjobz-chat-bubble-system {
  align-self: center;
  background: var(--oddjobz-chat-system-bg);
  color: var(--oddjobz-chat-system-fg);
  font-size: 12px;
  font-style: italic;
  max-width: 95%;
}

.oddjobz-chat-input-row {
  display: flex;
  gap: 8px;
  padding: 10px 12px;
  border-top: 1px solid var(--oddjobz-chat-border);
  background: #fafbfc;
}

.oddjobz-chat-input {
  flex: 1 1 auto;
  resize: none;
  padding: 8px 10px;
  border: 1px solid var(--oddjobz-chat-border);
  border-radius: 8px;
  font: inherit;
  background: #ffffff;
  color: var(--oddjobz-chat-bot-fg);
  outline: none;
}

.oddjobz-chat-input:focus {
  border-color: var(--oddjobz-chat-user-bg);
  box-shadow: 0 0 0 2px rgba(37, 99, 235, 0.15);
}

.oddjobz-chat-input:disabled {
  background: #f3f4f6;
  cursor: not-allowed;
}

.oddjobz-chat-send {
  padding: 0 16px;
  background: var(--oddjobz-chat-user-bg);
  color: var(--oddjobz-chat-user-fg);
  border: 0;
  border-radius: 8px;
  font: inherit;
  font-weight: 600;
  cursor: pointer;
}

.oddjobz-chat-send:hover:not(:disabled) {
  filter: brightness(1.05);
}

.oddjobz-chat-send:disabled {
  background: #94a3b8;
  cursor: wait;
}

.oddjobz-chat-send:focus-visible {
  outline: 2px solid var(--oddjobz-chat-user-bg);
  outline-offset: 2px;
}

@media (max-width: 480px) {
  .oddjobz-chat-widget {
    --oddjobz-chat-width: 100%;
    --oddjobz-chat-height: 70vh;
  }
}

```
