---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/services/src/services/PaskSnapshot.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.098472+00:00
---

# runtime/services/src/services/PaskSnapshot.ts

```ts
/**
 * PaskSnapshot — IndexedDB persistence for the Pask constraint graph.
 *
 * Stores a single `latest` blob per origin. Falls back to a no-op when
 * IndexedDB is unavailable (Node/Bun shell context).
 *
 * DB6 of the Dimensional Second Brain workstream.
 */

const IDB_NAME    = 'semantos-pask';
const IDB_STORE   = 'snapshots';
const IDB_VERSION = 1;
const SNAPSHOT_KEY = 'latest';

function openDb(): Promise<IDBDatabase> {
  return new Promise((resolve, reject) => {
    const req = indexedDB.open(IDB_NAME, IDB_VERSION);
    req.onupgradeneeded = () => {
      req.result.createObjectStore(IDB_STORE);
    };
    req.onsuccess = () => resolve(req.result);
    req.onerror   = () => reject(req.error);
  });
}

export async function loadPaskSnapshot(): Promise<Uint8Array | null> {
  if (typeof indexedDB === 'undefined') return null;
  try {
    const db = await openDb();
    return await new Promise<Uint8Array | null>((resolve, reject) => {
      const tx  = db.transaction(IDB_STORE, 'readonly');
      const req = tx.objectStore(IDB_STORE).get(SNAPSHOT_KEY);
      req.onsuccess = () => resolve(req.result instanceof Uint8Array ? req.result : null);
      req.onerror   = () => reject(req.error);
    });
  } catch {
    return null;
  }
}

export async function savePaskSnapshot(blob: Uint8Array): Promise<void> {
  if (typeof indexedDB === 'undefined') return;
  try {
    const db = await openDb();
    await new Promise<void>((resolve, reject) => {
      const tx  = db.transaction(IDB_STORE, 'readwrite');
      const req = tx.objectStore(IDB_STORE).put(blob, SNAPSHOT_KEY);
      req.onsuccess = () => resolve();
      req.onerror   = () => reject(req.error);
    });
  } catch {
    // non-fatal — graph will rebuild from interactions on next load
  }
}

export async function clearPaskSnapshot(): Promise<void> {
  if (typeof indexedDB === 'undefined') return;
  try {
    const db = await openDb();
    await new Promise<void>((resolve, reject) => {
      const tx  = db.transaction(IDB_STORE, 'readwrite');
      const req = tx.objectStore(IDB_STORE).delete(SNAPSHOT_KEY);
      req.onsuccess = () => resolve();
      req.onerror   = () => reject(req.error);
    });
  } catch { /* no-op */ }
}

```
