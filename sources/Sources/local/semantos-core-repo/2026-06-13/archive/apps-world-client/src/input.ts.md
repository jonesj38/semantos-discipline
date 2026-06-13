---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-world-client/src/input.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.821058+00:00
---

# archive/apps-world-client/src/input.ts

```ts
import type { SceneHandles } from "./scene";
import type { World } from "./world";

const MOVE_STEP = 1.0;
const MOVE_REPEAT_MS = 120;

export function installInput(scene: SceneHandles, world: World, canvas: HTMLCanvasElement) {
  const held = new Set<string>();
  const lastFire = new Map<string, number>();

  canvas.addEventListener("pointerdown", (evt) => {
    const rect = canvas.getBoundingClientRect();
    scene.pointer.x = ((evt.clientX - rect.left) / rect.width) * 2 - 1;
    scene.pointer.y = -((evt.clientY - rect.top) / rect.height) * 2 + 1;
    scene.raycaster.setFromCamera(scene.pointer, scene.camera);

    const hits = scene.raycaster.intersectObjects(world.selectableMeshes(), false);
    if (hits.length > 0) {
      const id = hits[0].object.userData.entityId as string | undefined;
      if (id) {
        world.select(id);
        return;
      }
    }
    world.select(null);
  });

  window.addEventListener("keydown", (evt) => {
    const k = evt.key.toLowerCase();

    if (k === "x") {
      world.issueAction("dup");
      return;
    }
    if (k === "r") {
      world.issueAction("drop");
      return;
    }

    if (MOVE_KEYS.has(k) && !held.has(k)) {
      held.add(k);
      fireMove(world, k);
      lastFire.set(k, performance.now());
    }
  });

  window.addEventListener("keyup", (evt) => {
    held.delete(evt.key.toLowerCase());
  });

  function pumpHeld() {
    const now = performance.now();
    for (const k of held) {
      if (!MOVE_KEYS.has(k)) continue;
      const last = lastFire.get(k) ?? 0;
      if (now - last >= MOVE_REPEAT_MS) {
        fireMove(world, k);
        lastFire.set(k, now);
      }
    }
    requestAnimationFrame(pumpHeld);
  }
  requestAnimationFrame(pumpHeld);
}

const MOVE_KEYS = new Set([
  "w", "a", "s", "d",
  "arrowup", "arrowleft", "arrowdown", "arrowright",
]);

function fireMove(world: World, key: string) {
  const delta = moveVector(key);
  if (!delta) return;
  world.issueAction("move", { delta });
}

function moveVector(key: string): [number, number, number] | null {
  switch (key) {
    case "w":
    case "arrowup":    return [0, 0, -MOVE_STEP];
    case "s":
    case "arrowdown":  return [0, 0, MOVE_STEP];
    case "a":
    case "arrowleft":  return [-MOVE_STEP, 0, 0];
    case "d":
    case "arrowright": return [MOVE_STEP, 0, 0];
    default: return null;
  }
}

```
