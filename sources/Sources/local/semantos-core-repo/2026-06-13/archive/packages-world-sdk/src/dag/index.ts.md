---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/packages-world-sdk/src/dag/index.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.703739+00:00
---

# archive/packages-world-sdk/src/dag/index.ts

```ts
/**
 * Append-only cell DAG shared between the relay and world applications.
 *
 * Extracted from apps/world-apps/jam-room/src/core/dag.ts.
 * Used by the relay client to deserialize cells and by world apps to
 * build and navigate local DAG state.
 */

export type Hat =
  | "origin"
  | "alice"
  | "bob"
  | "merge"
  | "cherrypick"
  | "dj"
  | "strudel"
  | "jam";

export interface Patch {
  op: string;
  payload: Record<string, unknown>;
}

export interface CellState {
  id: string;
  stateHash: Uint8Array;
  parents: CellState[];
  patch: Patch;
  hat: Hat;
  depth: number;
  branch: Hat;
  cherryPickedFrom: CellState | null;
  tampered: boolean;
}

export interface Dag {
  states: CellState[];
  byId: Map<string, CellState>;
  byHashHex: Map<string, CellState>;
}

export function emptyDag(): Dag {
  return { states: [], byId: new Map(), byHashHex: new Map() };
}

export function hashHex(h: Uint8Array): string {
  let s = "";
  for (let i = 0; i < h.length; i++) s += h[i].toString(16).padStart(2, "0");
  return s;
}

export function pushCell(dag: Dag, state: CellState): void {
  if (dag.byHashHex.has(hashHex(state.stateHash))) return;
  dag.states.push(state);
  dag.byId.set(state.id, state);
  dag.byHashHex.set(hashHex(state.stateHash), state);
}

const ZERO = new Uint8Array(32);

async function computeHash(
  hat: Hat,
  branch: Hat,
  depth: number,
  parents: CellState[],
  patch: Patch,
): Promise<Uint8Array> {
  const enc = new TextEncoder();
  const parts: Uint8Array[] = [
    enc.encode(`hat=${hat}|branch=${branch}|depth=${depth}|`),
  ];
  if (parents.length === 0) parts.push(ZERO);
  else for (const p of parents) parts.push(p.stateHash);
  parts.push(enc.encode(`|patch=${stableStringify(patch)}`));
  let n = 0;
  for (const p of parts) n += p.length;
  const buf = new Uint8Array(n);
  let o = 0;
  for (const p of parts) {
    buf.set(p, o);
    o += p.length;
  }
  return new Uint8Array(await crypto.subtle.digest("SHA-256", buf));
}

function stableStringify(v: unknown): string {
  if (v === null || typeof v !== "object") return JSON.stringify(v);
  if (Array.isArray(v))
    return "[" + v.map(stableStringify).join(",") + "]";
  const keys = Object.keys(v as Record<string, unknown>).sort();
  return (
    "{" +
    keys
      .map(
        (k) =>
          JSON.stringify(k) +
          ":" +
          stableStringify((v as Record<string, unknown>)[k]),
      )
      .join(",") +
    "}"
  );
}

let _label = 0;
function mintLabel(prefix: string): string {
  return `${prefix}-${(_label++).toString(36)}`;
}

export async function appendGenesis(
  dag: Dag,
  op = "jam.genesis",
): Promise<CellState> {
  const patch: Patch = { op, payload: { ts: Date.now() } };
  const stateHash = await computeHash("origin", "origin", 0, [], patch);
  const state: CellState = {
    id: mintLabel("genesis"),
    stateHash,
    parents: [],
    patch,
    hat: "origin",
    depth: 0,
    branch: "origin",
    cherryPickedFrom: null,
    tampered: false,
  };
  pushCell(dag, state);
  return state;
}

export async function fork(
  dag: Dag,
  parent: CellState,
  hat: Hat,
): Promise<CellState> {
  const patch: Patch = {
    op: "jam.branch.create",
    payload: { from: parent.id },
  };
  const stateHash = await computeHash(hat, hat, parent.depth + 1, [parent], patch);
  const state: CellState = {
    id: mintLabel(hat),
    stateHash,
    parents: [parent],
    patch,
    hat,
    depth: parent.depth + 1,
    branch: hat,
    cherryPickedFrom: null,
    tampered: false,
  };
  pushCell(dag, state);
  return state;
}

export async function edit(
  dag: Dag,
  parent: CellState,
  hat: Hat,
  patch: Patch,
): Promise<CellState> {
  const branch = parent.branch === "origin" ? hat : parent.branch;
  const stateHash = await computeHash(hat, branch, parent.depth + 1, [parent], patch);
  const state: CellState = {
    id: mintLabel(hat),
    stateHash,
    parents: [parent],
    patch,
    hat,
    depth: parent.depth + 1,
    branch,
    cherryPickedFrom: null,
    tampered: false,
  };
  pushCell(dag, state);
  return state;
}

```
