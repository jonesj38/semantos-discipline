---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-world-client/src/log.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.822484+00:00
---

# archive/apps-world-client/src/log.ts

```ts
export type LogLevel = "ok" | "info" | "warn" | "err";

const root = () => document.getElementById("log")!;

export function log(level: LogLevel, kind: string, msg: string | object = "") {
  const el = document.createElement("div");
  el.className = `line ${level}`;
  const t = new Date().toTimeString().slice(0, 8);
  const msgStr = typeof msg === "string" ? msg : JSON.stringify(msg);
  el.innerHTML =
    `<span class="t">${t}</span>` +
    `<span class="k">${kind}</span>` +
    `<span>${escapeHtml(msgStr)}</span>`;
  const r = root();
  r.prepend(el);
  while (r.children.length > 160) r.removeChild(r.lastChild!);
}

export function showToast(text: string, ms = 1500) {
  const t = document.getElementById("toast");
  if (!t) return;
  t.textContent = text;
  t.classList.add("show");
  window.setTimeout(() => t.classList.remove("show"), ms);
}

function escapeHtml(s: string): string {
  return s.replace(/[&<>"']/g, (c) => {
    switch (c) {
      case "&": return "&amp;";
      case "<": return "&lt;";
      case ">": return "&gt;";
      case '"': return "&quot;";
      case "'": return "&#39;";
      default: return c;
    }
  });
}

```
