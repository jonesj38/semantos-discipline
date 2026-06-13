---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-world-client/src/annotation.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.824129+00:00
---

# archive/apps-world-client/src/annotation.ts

```ts
/**
 * Pedagogical annotation system.
 *
 * The plain log panel is a developer firehose. The annotation panel is a
 * curated, human-paced surface that explains what just happened *and where
 * the decision came from*. It's the difference between "two cubes moved"
 * and "the kernel decided this; the same bytes ran in both browsers."
 *
 * Used for the consulting demo. Each annotation:
 *   - title       — what happened, plain English
 *   - source      — concrete file:symbol where the decision was made
 *   - explainer   — one sentence on why this is the property worth showing
 *   - tone        — visual treatment (info/ok/reject/diverge)
 */

export type AnnotationTone = "info" | "ok" | "reject" | "diverge";

export interface Annotation {
  title: string;
  source: string;
  explainer: string;
  tone: AnnotationTone;
}

const HOLD_MS = 4500;

let timer: number | null = null;

function root(): HTMLElement {
  let el = document.getElementById("annotation");
  if (!el) {
    el = document.createElement("div");
    el.id = "annotation";
    el.className = "annotation";
    el.innerHTML = `
      <div class="ann-title"></div>
      <div class="ann-source"></div>
      <div class="ann-explainer"></div>
    `;
    document.body.appendChild(el);
  }
  return el;
}

export function showAnnotation(a: Annotation): void {
  const el = root();
  el.dataset.tone = a.tone;
  (el.querySelector(".ann-title") as HTMLElement).textContent = a.title;
  (el.querySelector(".ann-source") as HTMLElement).textContent = a.source;
  (el.querySelector(".ann-explainer") as HTMLElement).textContent = a.explainer;
  el.classList.add("show");

  if (timer !== null) window.clearTimeout(timer);
  timer = window.setTimeout(() => {
    el.classList.remove("show");
    timer = null;
  }, HOLD_MS);
}

// --- preset annotations for the canonical demo events ---

export const ANN = {
  actionAccepted(op: string): Annotation {
    return {
      title: `${op.toUpperCase()} accepted`,
      source: "WorldHost.Region (Elixir) → kernel script",
      explainer:
        "Server applied the action and broadcast the new state. " +
        "Both browsers receive the same tick delta on the next 50 ms tick.",
      tone: "ok",
    };
  },

  linearityViolation(detail: string): Annotation {
    return {
      title: `REJECTED · ${detail}`,
      source: "core/cell-engine/src/linearity.zig (K1 gate)",
      explainer:
        "The rejection came from the Zig kernel running inside Wasmex on the server — " +
        "the same WASM bytes your browser also runs locally for prediction. " +
        "If the client and server disagreed, their stateHashes would diverge.",
      tone: "reject",
    };
  },

  divergence(reason: string): Annotation {
    return {
      title: `DIVERGENCE detected`,
      source: "Predictor stateHash ≠ authoritative stateHash",
      explainer:
        `Local prediction said one thing, the kernel said another (${reason}). ` +
        "Client snapped to authoritative state. " +
        "This is what tamper detection looks like — drift is impossible to hide.",
      tone: "diverge",
    };
  },

  hashesMatch(): Annotation {
    return {
      title: "Hashes synchronised",
      source: "WorldTick.stateHash (per-region Merkle root)",
      explainer:
        "Both browsers show identical stateHash after this tick. " +
        "The chain advances every 50 ms; missing or altered events break the chain.",
      tone: "info",
    };
  },

  cheatEnabled(): Annotation {
    return {
      title: "Cheat mode ON · predictor will lie",
      source: "client-side dev toggle (not a server feature)",
      explainer:
        "Next DUP attempt, the predictor will optimistically apply the mutation locally " +
        "even though the kernel will reject. Watch the divergence get caught and corrected.",
      tone: "info",
    };
  },
};

```
