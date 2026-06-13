---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-world-client/src/main.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.816908+00:00
---

# archive/apps-world-client/src/main.ts

```ts
import { bindAllIdentityPorts } from "@semantos/identity-ports";
import { makeStubBindings } from "@semantos/identity-ports/stub";
import { buildScene } from "./scene";
import { World } from "./world";
import { WorldSocket } from "./socket";
import { installInput } from "./input";
import { log, showToast } from "./log";
import { showAnnotation, ANN } from "./annotation";
import { mountIdentityPill, updateIdentityPill } from "./identity-pill";

// Bind ports FIRST — before scene/socket/world construction, so any
// early CubeMesh construction that calls identityPort.get() won't throw.
const { bundle } = makeStubBindings();
bindAllIdentityPorts(bundle);

const REGION_ID = "region-0001";

function main() {
  const canvas = document.getElementById("scene") as HTMLCanvasElement;
  const scene = buildScene(canvas);

  let socket!: WorldSocket;
  const world = new World(scene.scene, () => socket);

  // Mount the identity pill before socket connects (shows "—" until joined).
  let pillEl: HTMLElement | null = null;

  socket = new WorldSocket(REGION_ID, {
    onStatus(status) {
      log(status.startsWith("join_") || status === "closed" || status === "error" ? "warn" : "ok", "socket", status);
      if (status === "joined") {
        document.getElementById("hud-session")!.textContent = socket.certId.slice(0, 8);
        // Update pill with the certId (available at construction, not just after join).
        const pillOpts = {
          certId: socket.certId,
          email: socket.identityProvider.getCert().fields["email"] ?? socket.certId.slice(0, 8),
        };
        if (pillEl) {
          updateIdentityPill(pillEl, pillOpts);
        } else {
          pillEl = mountIdentityPill(pillOpts);
        }
      }
    },
    onSnapshot(frame) {
      log("ok", "snapshot", { tick: frame.tick_seq, n: frame.entities?.length ?? 0 });
      world.applySnapshot(frame.tick_seq, frame.region_id, frame.state_hash, frame.entities ?? []);
      updateHud(world);
    },
    onTickDelta(frame) {
      world.applyTickDelta(frame.tick.tick_seq, frame.tick.state_hash, frame.deltas);
      // Update HUD every tick so the hash chain is visibly advancing.
      updateHud(world);
    },
    onEntitySpawn(frame) {
      log("info", "spawn", frame.entity.entity_id);
      world.spawnEntity(frame.entity);
      updateHud(world);
    },
    onEntityDespawn(frame) {
      log("info", "despawn", `${frame.entity_id} · ${frame.reason}`);
      world.despawnEntity(frame.entity_id);
      updateHud(world);
    },
    onActionResult(frame) {
      if (frame.outcome.ok) {
        log("ok", "action", { id: short(frame.action_id), result: "ok" });
      } else {
        log("err", "rejected", {
          id: short(frame.action_id),
          reason: frame.outcome.reason,
          detail: frame.outcome.detail,
        });
        if (frame.outcome.reason === "linearity_violation") {
          showToast(frame.outcome.detail ?? "linearity violation", 1800);
          showAnnotation(ANN.linearityViolation(frame.outcome.detail ?? "linearity violation"));
        }
      }
      world.handleActionResult(
        frame.action_id,
        frame.outcome.ok,
        !frame.outcome.ok ? frame.outcome.reason : undefined,
      );
    },
  });
  socket.connect();

  // Mount pill immediately — certId is available at construction time (D-A2).
  pillEl = mountIdentityPill({
    certId: socket.certId,
    email: socket.identityProvider.getCert().fields["email"] ?? socket.certId.slice(0, 8),
  });

  // Push the log panel down so the identity pill sits above it.
  // The pill is ~90px tall (two text lines + button + padding + border).
  const logEl = document.getElementById("log");
  if (logEl) {
    logEl.style.top = "102px"; // 90px pill + 12px gap
  }

  document.getElementById("hud-region")!.textContent = REGION_ID;

  // Cheat-mode toggle (pedagogical demo control).
  const cheatBtn = document.getElementById("cheat-toggle") as HTMLButtonElement;
  cheatBtn.addEventListener("click", () => {
    const next = !world.cheatMode;
    world.setCheatMode(next);
    cheatBtn.classList.toggle("on", next);
    cheatBtn.textContent = `cheat: ${next ? "on" : "off"}`;
  });

  installInput(scene, world, canvas);

  let last = performance.now();
  function frame() {
    const now = performance.now();
    const dt = now - last;
    last = now;
    world.tick(dt);
    scene.render();
    requestAnimationFrame(frame);
  }
  requestAnimationFrame(frame);
}

function updateHud(world: World) {
  document.getElementById("hud-tick")!.textContent = String(world.tickSeq);
  document.getElementById("hud-count")!.textContent = String(world.entities.size);
  document.getElementById("hud-selected")!.textContent = world.selectedId ?? "—";
  document.getElementById("hud-hash")!.textContent =
    world.stateHash ? "0x" + world.stateHash.slice(0, 12) + "…" : "—";
}

function short(id: string): string {
  return id.slice(0, 8);
}

main();

```
