---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-demo-wasm-threejs/NEXT_IDEAS.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.687935+00:00
---

# Next ideas — beyond the K1 visualization

The current demo is a teaching artifact: click a cube, watch the kernel's linearity gate decide legal vs illegal, see the verdict animate. That's it. Great for explaining substructural typing in 30 seconds; not a visual flex or a capability demo.

This file captures the **next-step vision**: a collaborative 3D canvas where every edit is a patch, the kernel authorises each patch, and substructural linearity becomes collaboration semantics. It's a sketch, not a plan — treat it as prompts for exploration.

---

## The pitch, in one paragraph

Two or more people open the same URL. A procedural 3D object — voxel sculpture, terrain, model — is in the scene. Every edit (drag a voxel, change a colour, subdivide, fork) becomes a patch. A cell script authorises each patch against the actor's capabilities and the object's linearity class. The patch chain is the shared truth; the scene is just a rendering of it. You can rewind history, fork an object, see another user's cursor, watch linearity conflicts animate, and audit exactly which hat produced which change. Multiplayer-Figma-shaped but backed by a kernel with Lean proofs.

## Linearity as collaboration semantics

The same three classes that gate DUP/DROP at the bytecode level map cleanly onto three modes of shared editing:

| Class        | Collaboration mode                 | What the user sees |
| ---          | ---                                | --- |
| **LINEAR**   | Exclusive-edit. One hat holds the handle; handing off is a consume-and-republish. | Current editor's cursor has a solid ring; others see the object glow but can't grab. Transfer animates as a glide between cursors. |
| **AFFINE**   | Single-lifecycle. Editable by the holder; can be abandoned, never forked. Good for drafts, turn-based pieces. | Draggable by the owner; a "release" gesture drops it and it freezes in place. No copy option. |
| **RELEVANT** | Forkable. Anyone duplicates. Original must stay alive — proof that something was started. | Two-finger gesture = fork. New copy glides to your workspace with its own patch chain. Provenance arrow links forks back to the source. |

Classes can *transition*: RELEVANT → LINEAR is "everyone stop forking, we're converging on a final version." That transition is itself a patch, with its own authorisation.

## 60-second walkthrough

1. Two tabs, two hats. User A's cursor blue, user B's green.
2. Scene shows a small sculpture — ~50 voxels in an `InstancedMesh`. Class badge overhead: **RELEVANT**.
3. A drags a voxel. Patch emitted: `{ hat: A, op: 'move_voxel', id: 17, from: [0,1,0], to: [2,1,0] }`. A's worker authorises (<1 ms), Plexus broadcasts, B's worker receives and applies. Voxel glides to its new home, tagged with A's colour briefly.
4. B forks the sculpture. Ghost copy glides to B's workspace; provenance arrow draws from original to fork. Both sculptures now have independent patch chains.
5. A tries to delete the original. RELEVANT → `cannot_discard_relevant`. Red flash, sculpture stays. Readout: *"K1 rejected the delete. Someone has to consume it first, not drop it."*
6. A transitions the original to **LINEAR** with a gesture. Badge flips blue. A now holds the exclusive handle. B can orbit and observe but not grab. A finishes a final edit, does a "publish" gesture: LINEAR's visibility transitions draft → published, the sculpture solidifies with a glow. Any hat can now `consume` it (mint, transfer, download). The consume is the final patch in its chain.
7. **Scrubber**: drag a timeline slider and the sculpture replays edit-by-edit. Each patch annotated with hat + capability. Cryptographically verifiable — kernel re-runs every authorisation in order and confirms every patch was legitimate.

Shatter, fork arrow, and scrubber are all plain three.js. The novelty is that every pixel on screen is backed by a patch that was authorised by a provably-terminating kernel.

## Architecture

```
  ┌────────── Main thread (per user) ──────────┐
  │  Three.js scene                            │
  │    InstancedMesh voxel sculpture           │
  │    Cursor meshes for other hats            │
  │    Provenance arrows, class badges         │
  │    Scrubber timeline UI                    │
  │  Input → patch candidates                  │
  │  Worker: postMessage("authorise", patch)   │
  └────────────────┬───────────────────────────┘
                   │ patch candidate
                   │ ← authorise verdict
  ┌────────────────▼───────────────────────────┐
  │  Web Worker (per user)                     │
  │  cell-engine.wasm                          │
  │    authorise_patch(patch, hat, object):    │
  │      → check hat capabilities              │
  │      → check object linearity vs patch op  │
  │      → check type-grammar compliance       │
  │      → return legal / rejected + reason    │
  │  Plexus client (WebRTC or WS)              │
  │    broadcasts legal patches to peers       │
  │    receives + re-verifies remote patches   │
  │  Local LoomStore (object tree)             │
  │  Per-frame: diff state, produce render ops │
  └────────────────┬───────────────────────────┘
                   │ Plexus overlay (peers)
  ┌────────────────▼───────────────────────────┐
  │  Plexus signalling server (optional)       │
  │  OR pure WebRTC mesh                       │
  │  Optional: server-side replay for audit    │
  └────────────────────────────────────────────┘
```

The `authorise_patch` cell script is ~30–50 opcodes. Kernel runs it in <1 ms. Net effect: real-time collaboration without a backend, an authoritative audit log independently verifiable by any third party, and linearity guarantees that no CRDT offers — two LINEAR editors can't silently race; the second gets a kernel rejection, not a hopeful merge.

## Scope estimate

Not a session. Roughly:

| Module                                                        | Effort         | Status |
| ---                                                           | ---            | --- |
| `authorise_patch` cell script (~50 lines of bytecode)         | 1 session      | new |
| Web-worker host: port this demo's pattern into a Worker + `OffscreenCanvas` | 1 session      | new |
| Plexus-over-WebRTC so two tabs see each other's patches       | 2–4 sessions   | partial — see [runtime/services/src/plexus/](../../runtime/services/src/plexus/) |
| Three.js scene: instanced voxels, cursors, badges, arrows, scrubber | 2–3 sessions   | new |
| Patch chain persistence + replay                              | 1 session      | partial — `LoomStore` has patch arrays, needs a "reapply from zero" path |
| Polish, onboarding, video capture                             | 1–2 sessions   | new |

Call it **~2 weeks focused**, or **4+ weeks if scope creeps** into real identity, persistence, or production-grade peer transport.

## MVP — get the pitch on screen without building the full system

If the goal is to get the *story* on screen fast:

1. Single user, single tab. No Plexus yet.
2. One RELEVANT sculpture. Drag-to-move voxels. Fork on keypress.
3. `authorise_patch` runs in a Worker. Every edit is a kernel call.
4. Scrubber works from the local patch chain.
5. A **scripted second cursor** — driven by a pre-recorded session — fakes collaboration. The user sees "multiplayer" even though it's one-player.

That gets the animation, the fork, the scrubber, the audit chain, and "the kernel authorised this edit." You lose real multiplayer but keep 90% of the pitch. **~3–5 sessions** instead of 2+ weeks.

Then if the MVP lands: add a real second peer via WebRTC and you unlock the "no backend, still multiplayer, still provably-authored" story.

## Starting points in this repo

- Minimal browser binding — [src/cell-engine.ts](src/cell-engine.ts) — `packCell`, `setEnforcement`, `OP_CALLHOST` via `HostCallDispatch`. Paste-portable.
- Linearity enforcement (kernel) — [core/cell-engine/src/pda.zig](../../core/cell-engine/src/pda.zig) `sdup_enforced`, `sdrop_enforced`.
- K1 proofs — [proofs/lean/Semantos/Theorems/LinearityK1.lean](../../proofs/lean/Semantos/Theorems/LinearityK1.lean).
- Existing object + patch model — [runtime/services/src/services/LoomStore.ts](../../runtime/services/src/services/LoomStore.ts).
- Plexus stub / real transports — [runtime/services/src/plexus/](../../runtime/services/src/plexus/).
- HostCommand authorisation example — [runtime/shell/src/commands/host-exec.ts](../../runtime/shell/src/commands/host-exec.ts) (Phase 38). The `authorise_patch` script can follow a similar shape.

## Caveats

- **Plexus P2P is not fully wired.** The stub works; real WebRTC transport is partial. Worth validating before building a demo that depends on it.
- **The cell kernel is not a renderer or a physics engine.** Keep those on the main thread. Kernel decides *what* happens; three.js decides *how to draw it*.
- **Opcode budget.** The kernel enforces `opcountLimit` (K5 termination). A runaway `authorise_patch` gets cut off. Good for safety, but the authoriser must be sublinear in patch size — don't write a script that iterates the whole object on every edit.
- **This is a sketch.** The numbers above are estimates, not commitments. Prototype the riskiest piece first (probably the Plexus-over-WebRTC leg) before committing to the full shape.
