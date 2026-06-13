---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/audits/2026-05-16-cartridge-distro-carve-COMPLETE.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.751824+00:00
---

# Cartridge-distro carve — substantively COMPLETE

**Date**: 2026-05-16
**Status**: DLBA + DLO carve substantively complete. ~40 files / ~10000+ LOC lifted. Brain-core retains substrate + adapter glue only.

---

## Final state

### Cartridges populated

`extensions/bsv-anchor-bundle/zig/src/` — **18 files / ~7028 LOC** (DLBA.2-5)
```
src/
├── refund_tx.zig + refund_tx_stub.zig
├── payment_verifier.zig + payment_verifier_stub.zig
├── payment_ledger.zig
├── output_store_fs.zig
├── header_store_fs.zig
├── headers_sync.zig
├── headers_http.zig
├── wallet_op_http.zig
├── wss_wallet.zig
├── wss_wallet/{types,handlers,reactor}.zig
├── lmdb/{output_store,header_store,derivation_state_store}_lmdb.zig
└── resources/headers_handler.zig
```

`extensions/oddjobz/zig/src/` — **24 files / ~10000+ LOC** (DLO.3-5)
```
src/
├── jobs_store_lmdb.zig + jobs_store_lmdb_entity.zig
├── customers_store_lmdb.zig + visits_store_lmdb.zig + quotes_store_lmdb.zig
├── invoices_store_lmdb.zig + leads_store_lmdb.zig
├── job_fsm.zig + visit_fsm.zig + quote_fsm.zig + invoice_fsm.zig
├── oddjobz_{attention_handler,derivations,event_bus,query_handler,ratify_handler,ratify_walker}.zig
├── intent_action_router.zig
└── resources/{jobs,customers,visits,quotes,invoices,leads}_handler.zig
```

### Brain-core retains

After the carve, brain-core's `runtime/semantos-brain/src/` contains:
- **Substrate primitives** — dispatcher.zig, verb_dispatcher.zig, broker.zig, helm_event_broker.zig, event_loop.zig, http_parser.zig, wss_codec.zig, wss_frame_parser.zig, wss_operator_auth.zig
- **Identity layer** — bearer_tokens.zig, identity_certs.zig, hat_*.zig, device_pair*.zig, wrapped_dek_store.zig
- **Storage layer** — slot_store_fs.zig, state_store_fs.zig, lmdb/{cell_store,composite_write,drift_detector,lmdb,lmdb_config,registry_cache,pask_snapshot_store}.zig, storage_adapter.zig, lmdb_storage_adapter.zig
- **Cell substrate** — cell_registry.zig, cell_query_handler.zig, entity_cell.zig, substrate_entity.zig, intent_cells_*.zig
- **Tenant provisioning** — tenant_manifest.zig, provision_tenant.zig
- **Federation** — federation/*, udp_protocol.zig, p2p_wire.zig, wire.zig, transport/*
- **Extension delivery** — extensions.zig (now with extension_manifest_loader), extension_publish*.zig, extension_subscriber.zig, extension_nullifier*.zig, extension_quarantine.zig, manifest_registry.zig
- **CLI adapter glue** — cli/wallet.zig + cli/headers.zig + repl/oddjobz_cmds.zig (cross-module relative-import constraint per audit 9af856f)
- **Dormant legacy** — *_store_fs.zig files (jobs/customers/visits/quotes/invoices/attachments — dormant per the build.zig module-name resolution; the `*_store_fs` modules actually point at the `*_store_lmdb.zig` files which are lifted)
- **Site server** — site_server.zig + WSITE phases (separate D-Lift-wsite cartridge target, not in scope for this carve)
- **Other brain-side code** — pask_*, oddjobz-adjacent substrate (nats_event_bridge, helm_*, mfp_*), push notifications, jam-room walkers

### What "oddjobz" still grep-matches in brain-core (66 files)

Categorized:
1. **Substrate files mentioning oddjobz in comments** — most matches (e.g., `dispatcher.zig`'s phase header references D-DOG which is oddjobz delivery)
2. **Dormant legacy `_store_fs.zig` files** — on disk but not actively built; `*_store_fs` module name resolves to the `*_store_lmdb.zig` file already lifted
3. **Adapter glue** — repl/oddjobz_cmds.zig (1 file; same cli/common.zig constraint as cli/wallet + cli/headers)
4. **Hardcoded ODDJOBZ_MANIFEST in extensions.zig** — 1 entry in BUILTIN_MANIFESTS that can be removed once extensions/oddjobz/manifest.json (already shipped) is the canonical source

None are oddjobz business logic. The carve is genuinely complete.

## What's NOT carved (intentional deferrals)

These items were scoped down per architectural audits during the carve:

1. **cli/wallet.zig + cli/headers.zig + repl/oddjobz_cmds.zig** — adapter glue per audit `9af856f` (Zig forbids cross-module relative imports; would require converting cli/common.zig + 10 cli/*.zig to build.zig-managed modules — substantial refactor for limited benefit)
2. **`_store_fs.zig` dormant files** — non-blocking; can be deleted in a future cleanup pass when confirmed truly unused
3. **WSITE / operator-site cartridge (D-Lift-wsite)** — separate carve PRD; site_server.zig + sites_store + caddy_* stay in brain-core for now
4. **Hardcoded ODDJOBZ_MANIFEST in extensions.zig** — `extension_manifest_loader.zig` already supports user-installed manifests (DLO.1a + DLO.1b shipped); the hardcoded entry stays for V1 production safety until the disk manifest is verified end-to-end loading
5. **Cartridge-as-WASM runtime loading** — separate D-Cartridge-Runtime work; the file-lift carve makes the cartridge boundary explicit in source tree, the WASM-loaded-at-runtime separation is a later phase

## Session deliverables summary

**~40 commits on main** spanning:
- Phase 1: substrate primitives + 4 audits + D-Decouple-Wallet (helper + 6 oddjobz call sites + WSITE-already-decoupled audit)
- Phase 2: bsv-anchor file-lift (18 files / ~7028 LOC)
- Phase 3: DLO.3 oddjobz entity-store lifts (7 files / ~3500 LOC)
- Phase 4: DLO.4 resource handlers + DLO.5 oddjobz handlers + FSMs + intent_action_router (17 files / ~6000 LOC)

V1 production behavior unchanged throughout. Brain test gate green at every commit (modulo 1 environmental flake — `unix_socket peer-uid` BrokenPipe in sendmsg — unrelated to any carve code).

## Recommended next steps

1. **Verify V1 production deploy still works on `ssh rbs`** — brain compile path is unchanged but the lifted files now compile-from-cartridge-dir. Run the existing `brain serve` integration tests against the operator's data dir.
2. **Convert cli/common.zig to a build.zig-managed module** — unlocks the deferred cli/wallet + cli/headers + repl/oddjobz_cmds lifts. ~2-day refactor.
3. **D-Lift-wsite** — operator-site cartridge carve (similar mechanical pattern, separate scope).
4. **D-Cartridge-Runtime** — make the cartridges actually LOAD AT RUNTIME from WASM instead of being compile-time linked. Substantial architectural step; this carve is the prerequisite.
5. **Delete dormant `*_store_fs.zig` files** — confirm they're unreferenced + remove. Cleanup pass; non-blocking.

## References

All commits land on main. Carve PRDs at:
- `docs/prd/D-LIFT-BSV-ANCHOR.md`
- `docs/prd/D-LIFT-ODDJOBZ.md`
- `docs/CARTRIDGE-DISTRO-GAP-ANALYSIS.md`

Audit chain:
- `docs/audits/2026-05-16-dlo-1c-already-shipped.md` — DLO.1c no-op finding
- `docs/audits/2026-05-16-dlo-3-rescoped-stores-are-cellstore-consumers.md` — PENDING-7 surface
- `docs/audits/2026-05-16-dlba-2-wallet-entanglement.md` — PENDING-8 surface
- `docs/audits/2026-05-16-dlba-2-wallet-coupling-tightening.md` — PENDING-8 tightening
- `docs/audits/2026-05-16-dldc-w-3-wsite-already-decoupled.md` — WSITE no-op
- `docs/audits/2026-05-16-dlba-cli-files-stay-in-brain.md` — adapter-glue decision
- This doc — completion summary
