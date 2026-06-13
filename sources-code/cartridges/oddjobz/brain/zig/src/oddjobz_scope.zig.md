---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/zig/src/oddjobz_scope.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.544586+00:00
---

# cartridges/oddjobz/brain/zig/src/oddjobz_scope.zig

```zig
//! oddjobz signing scope — the cartridge's BKDS derivation family.
//!
//! oddjobz cells are signed under "oddjobz.cell-sign/v1", NOT the substrate
//! default "semantos.cell-sign/v1" (hat_bkds.PROTOCOL_ID). This gives the
//! operator's oddjobz signing keys their own derivation family: two cartridges
//! signing the same canonical payload under different scopes derive different
//! keys, so cross-cartridge cell traces stay cryptographically unlinkable
//! ("generic signing, but under hats relevant to the cartridge").
//!
//! Every oddjobz sign + verify site passes this scope:
//!   • mint  — oddjobz_ratify_handler.signOne → hat_bkds.signCellScoped
//!   • backfill — cli/operator.zig `resign-pending` → hat_bkds.signCellScoped
//!   • verify — hat_bkds_verifier.verifyCellScoped(..., CELL_SIGN_PROTOCOL_ID,
//!              hat_bkds.CONTEXT_TAG_CELL_SIGN)
//!
//! The context tag stays the substrate hat_bkds.CONTEXT_TAG_CELL_SIGN (0x20) —
//! only the protocol-id segment differs per cartridge.

pub const CELL_SIGN_PROTOCOL_ID: []const u8 = "oddjobz.cell-sign/v1";

```
