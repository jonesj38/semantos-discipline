---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/audits/2026-05-16-dlo-1c-already-shipped.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.751054+00:00
---

# DLO.1c audit — extension delivery/revocation/quarantine already cartridge-agnostic

**Date**: 2026-05-16
**Status**: Audit — DLO.1c marked as already-shipped; no brain-core changes needed.

---

## Finding

`docs/prd/D-LIFT-ODDJOBZ.md` §Deliverables / DLO.1c scopes **"Extension delivery + revocation + quarantine integration — generalize per BRAIN-EXTENSION-DELIVERY-AND-REVOCATION.md to handle any cartridge"** as a 2-week deliverable.

Audit result: **already done.** The existing `runtime/semantos-brain/src/extension_*.zig` files are cartridge-agnostic by construction. The carve required by DLO.1c is a no-op.

## Evidence

### File surface — extension_name as parameter (not hardcoded)

Each extension delivery/revocation/quarantine function accepts `extension_name: []const u8` as a runtime parameter:

- `runtime/semantos-brain/src/extension_publish.zig:98` — publish bundle takes extension_name
- `runtime/semantos-brain/src/extension_publish.zig:240` — bundle frame writer takes extension_name
- `runtime/semantos-brain/src/extension_quarantine.zig:62` — signerScopeMatches takes extension_name
- `runtime/semantos-brain/src/extension_quarantine.zig:208,275,310` — quarantine state machine takes extension_name
- `runtime/semantos-brain/src/extension_subscriber.zig` — subscriber routes by extension_name
- `runtime/semantos-brain/src/extension_nullifier.zig` — nullifier tracks per-extension revocation lists

### `oddjobz` string occurrences are non-load-bearing

`grep -n "oddjobz" runtime/semantos-brain/src/extension_*.zig` returns 13 matches, classified:

| Match type | Count | Examples |
|---|---|---|
| Comments referencing TS tool path | 2 | `extensions/oddjobz/tools/publish-bundle.ts` (just a doc reference to the TS-side bundle builder) |
| Test fixture extension names | 11 | `"oddjobz.invoicer"`, `"oddjobz.foo"`, `"oddjobz.thing"` — used as sample extension names in inline tests; no production code path checks for "oddjobz" |

No production code path in these four files branches on `extension_name == "oddjobz"`. The bytewise frame layout, the signer-scope matcher, the per-extension revocation lists, the quarantine state machine all work for any extension name within the safe-name shape (`extension_name_len ≤ 64`).

### Brain test gate still green

Brain test suite continues passing on commit `08620e3` (DLO.1b additive integration). No DLO.1c changes are needed for the existing test gate to remain green.

## Conclusion

DLO.1c scope = no-op. The work the PRD describes was done as part of D-W2 Phase 4 (extension delivery + revocation, see `docs/design/BRAIN-EXTENSION-DELIVERY-AND-REVOCATION.md`) — predating this carve PRD by several months. The carve can proceed directly to DLO.3 (per-store StorageAdapter migration — jobs first).

## What this changes

- DLO.1c marked as **shipped** in any future status grid.
- The 2-week effort estimate in `docs/prd/D-LIFT-ODDJOBZ.md` should be reduced accordingly (~3.5 weeks for DLO.1, but DLO.1c being a no-op trims that to ~1.5 weeks).
- The next blocking work for the oddjobz carve is **DLO.3** (per-store StorageAdapter migration).

## Test-fixture cleanup (optional follow-up)

The 11 test-fixture `oddjobz.*` strings in `extension_subscriber.zig` + `extension_quarantine.zig` are harmless but conceptually impure — they suggest the test fixture is oddjobz-specific. A future cleanup pass could rename these to generic fixture names (`testext.foo`, `testext.invoicer`, etc.) to make the cartridge-agnostic intent crystal-clear. Out of DLO scope; tracked as cleanup not blocker.

## References

- `docs/prd/D-LIFT-ODDJOBZ.md` §Deliverables / DLO.1c
- `docs/design/BRAIN-EXTENSION-DELIVERY-AND-REVOCATION.md`
- `runtime/semantos-brain/src/extension_publish.zig`, `extension_subscriber.zig`, `extension_nullifier.zig`, `extension_quarantine.zig`
- `docs/CARTRIDGE-DISTRO-GAP-ANALYSIS.md` §10.3
