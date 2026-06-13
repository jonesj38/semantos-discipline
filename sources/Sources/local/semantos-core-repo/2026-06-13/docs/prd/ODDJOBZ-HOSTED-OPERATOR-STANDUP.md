---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/ODDJOBZ-HOSTED-OPERATOR-STANDUP.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.707847+00:00
---

# Oddjobz Hosted-Operator Stand-up Pipeline

**Status:** plan. Companion to `SEMANTOS-DB-IMPLEMENTATION-PIPELINE.md` and `BRAIN-FIELD-APP-DB-PIPELINE.md`.

**Scope:** how to stand up a single Intergrid box that hosts many tradie operators running Oddjobz simultaneously, each with their own sovereign cell store, Pask graph, capability set, and event streams, isolated cryptographically and at the kernel level via K3 — without the operational weight of Pravega and without making a custodial account-recovery commitment.

**Read alongside:** `SEMANTOS-DB-IMPLEMENTATION-PIPELINE.md`, `BRAIN-FIELD-APP-DB-PIPELINE.md`, `docs/canon/cybernetic-orders.md`, `docs/canon/SEMANTOS-DB-PASKIAN-ADDENDUM.md`. Plexus integration spec lives in the Plexus repo and is referenced from Phase 2 W7.11.

---

## 1. Architectural principle

Operators do not have accounts. They have themselves — a BRC-52 identity cert, a BRC-42 key universe derived from it, and the cells they have authored or been authorised to read. A hosted-operator box runs N sovereigns co-resident; each sovereign is an operator, addressed by their cert pubkey hash, isolated from the others by K3 domain isolation at the kernel layer and by structural key prefixes at the storage layer.

The product is not "Oddjobz SaaS." The product is "we host your sovereign Oddjobz node, you own the keys, you can leave any time with a tarball, recovery is via Plexus not via us." The economics work because tradie workloads are tiny relative to box capacity; the architecture works because Semantos was already designed to be cryptographically sovereign at the cell layer, so hosting is just provisioning rights to a slice of one box.

Operationally this means:

- No password reset flow. There is no password.
- No account recovery flow. There is no account. Key universe recovery is a Plexus concern.
- No cross-operator data sharing primitives in v1. Pask graphs are strictly per-operator. Federation across operators is a future product, not part of this stand-up.
- Operator exit produces a tarball the operator could replay onto their own hardware or another hosted-operator box. The export is the proof that we are not custodians.

Two further architectural commitments fall out of this principle:

**Bring-your-own-domain.** Operators do not surrender their brand to a Semantos subdomain. They connect their existing domain (e.g. `coastalplumbing.com.au`) to the hosted brain. The reference layout is: `<their-domain>` apex serves the public intake bot; `brain.<their-domain>` serves the helm WSS endpoint that the Flutter field app federates with. The hosted box terminates TLS for arbitrary operator-owned domains via on-demand ACME and routes by SNI hostname → `op_pkh`. The operator's domain is a strong product-identity signal but the BRC-52 cert chain remains the auth primitive — the domain says "this connection is for Coastal Plumbing's hosted brain"; the cert says "this connection is from a key Coastal Plumbing has authorised."

**Plexus is the identity + recovery + treasury layer; the hosted brain only respects identity.** When a new operator signs up, Flutter directs them to Plexus first. Plexus creates their BRC-52 root cert and BRC-42 key universe, sets up recovery challenges, and seeds them with a few million sats — enough to cover the 1-sat-per-pushdrop and per-tx-fee operations a tradie generates over months of normal use. Only after Plexus onboarding completes does Flutter register the operator with the hosted brain (W7.9). This sequencing preserves the non-custodial story end-to-end: we never see the root key, we never hold the recovery material, we never run a sat faucet. Operators can subsequently delegate subkeys (BRC-42 child derivations) to additional devices, or to apprentices and contractors with scoped capability grants — those subkeys present at the WSS handshake and validate against the registered root op_pkh.

---

## 2. Streaming spine — NATS JetStream, with Postgres LISTEN/NOTIFY for internal events

### 2.1 The decision

Pravega remains in the codebase as the high-volume option (per the M3 milestone). For the hosted-operator box, default to **NATS JetStream**:

- Single Go binary, ~20 MB RAM idle, file-backed durability via JetStream stream config.
- Subject hierarchy maps cleanly to the operator + hat + event-type axes: `op.<pubkey_hash>.<hat>.<stream>`.
- Consumer groups + replay-from-offset give the same Pravega-replay semantics needed for Pask determinism (M3.10) at one tenth the operational weight.
- Wildcards (`op.<pubkey_hash>.>`) make per-operator fanout subscriptions trivial.
- Native Zig + Kotlin clients available; Bert's kweave (when it lands) is an adapter swap, not a rewrite.

For internal events (FSM transitions surfacing to materialised views, drift detection alerts, refresh signals between Postgres and the BRAIN brain), use **Postgres LISTEN/NOTIFY**. Two lanes, no overlap:

- NATS = client-facing fanout (Flutter app subscribes to `op.<self>.oddjobz.events`).
- LISTEN/NOTIFY = backend-internal coordination (Postgres trigger fires on cell insert; BRAIN brain receives notification; refreshes Helm view).

### 2.2 Migration path

The streaming layer is already abstracted behind the M3 vtable. When kweave is ready in Bert's Kotlin tier, swap the adapter; no application changes. Pravega remains available for operators who eventually outgrow both.

### 2.4 Implementation layout (W7.3)

Two new Zig modules, one new field and attach method in `jobs_handler.zig`:

**`runtime/semantos-brain/src/nats_client.zig`**
TCP connection to NATS (127.0.0.1:4222). Public API:
- `init(allocator, NatsConfig) !NatsClient` — connect, parse INFO, send CONNECT + PING/PONG
- `publish(subject, payload) !void` — mutex-serialised PUB, fire-and-forget
- `request(subject, payload) ![]u8` — synchronous request-reply over a private inbox; used for JetStream API calls only (not on hot path)
- `streamCreate(name, subjects_json) !void` — `$JS.API.STREAM.CREATE.<name>`, idempotent (stream-already-exists treated as ok)
- `streamDelete(name) !void` — `$JS.API.STREAM.DELETE.<name>`, idempotent
- `consumerCreateDurable(stream, consumer, filter, deliver_policy) !void` — `$JS.API.CONSUMER.CREATE.<stream>.<consumer>`

**`runtime/semantos-brain/src/nats_event_producer.zig`**
Wraps `NatsClient` with operator context. Public API:
- `init(allocator, *NatsClient, op_pkh16: [16]u8) NatsEventProducer`
- `emitJobTransition(hat_id, job_id, cell_id, from_state, to_state, ts_ms) !void` → publishes to `op.<op_pkh16>.<hat_id>.fsm_transition`
- `ensureStream() !void` — call at provisioning (W7.9)
- `ensureBrainConsumer(consumer_name) !void` — durable pull consumer, `deliver_policy: "all"`, for BRAIN brain replay
- `deleteStream() !void` — call at exit (W7.8)
- `opPkh16FromHatId(hat_id) [16]u8` — FNV-1a placeholder until W7.1 lands the real operator prefix

**`runtime/semantos-brain/src/resources/jobs_handler.zig`** (modified)
- Added `nats_producer: ?*NatsEventProducer = null` field
- Added `attachNatsProducer(producer)` method
- FSM transition block now emits independently to all three lanes: W7.3 NATS → W3.1 Pravega → W3.2 in-process bus. Each is best-effort; none fails the transition.

**Stream config** (set in `streamCreate`):
```
name:                op_<op_pkh16>
subjects:            ["op.<op_pkh16>.>"]
storage:             file
retention:           limits
max_msgs_per_subject: 10_000
max_age:             30 days (2_592_000_000_000_000 ns)
discard:             old
num_replicas:        1
```

**Consumer naming conventions:**
- BRAIN brain pull consumer: `brain_brain_<op_pkh16>` — `deliver_policy: "all"` for full replay
- Flutter push consumer: `flutter_<device_id>` — created by the Flutter client on connect via NATS WebSocket bridge (or via BRAIN proxy in Phase 1); `deliver_policy: "last_per_subject"` for catch-up on reconnect

**Postgres LISTEN/NOTIFY** (separate from NATS, internal only):
```sql
CREATE OR REPLACE FUNCTION notify_cell_written() RETURNS trigger AS $$
BEGIN
  PERFORM pg_notify('cell_written', json_build_object(
    'op_pkh', NEW.op_pkh, 'cell_id', NEW.cell_id, 'hat', NEW.hat_id
  )::text);
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER cell_written_notify
  AFTER INSERT ON cells FOR EACH ROW EXECUTE FUNCTION notify_cell_written();
```
BRAIN brain holds a persistent `LISTEN cell_written` connection; fires on each cell insert to trigger Helm view refresh. Does not go through NATS.

### 2.5 Out of scope for hosted-operator stand-up

- Pravega cluster operation (preserved for M9+ and for self-hosted sovereign nodes).
- Cross-operator event correlation (federation tier, M7; not part of this stand-up).
- Flutter NATS WebSocket bridge — Flutter subscribes via the existing `/api/v1/events` WebSocket endpoint (W3.2 in-process bus) in Phase 1. Direct NATS WebSocket subscription is a Phase 2 item once the hosted-operator box is stable.

---

## 3. Stand-up sequence

### Phase 0 — Box and OS substrate (week 0, ~2 days)

Provision **CBR-1319** ($265/mo, E-2236 / 64 GB / 2× 500 GB NVMe). Debian 12 or Ubuntu 24.04 LTS. mdadm RAID 1 across the two NVMes with ext4 + LVM (defer ZFS for now; can be migrated to later if per-operator snapshots become valuable). SSH keys only, ufw allowing 22/443/80, unattended-upgrades on, fail2ban for SSH, node_exporter pointing at Grafana Cloud free tier, restic backups to Backblaze B2 nightly. No Docker — Semantos services as systemd units. The simpler boot path is worth it.

Acceptance: box boots clean, monitoring shows up in Grafana, restic backup completes once, restore from backup verified.

### Phase 1 — Single-operator stack (week 1, ~3-5 days)

Build `brain` from the Zig source. Init LMDB env on `/var/lib/semantos/lmdb`. Install Postgres 16 with the merged migrations (M5.1–M5.4, M5.11, M5.14). Install NATS server with JetStream enabled, file storage on the same NVMe pool. **Terminate TLS at Caddy with on-demand ACME** — operators are bringing their own domains (W7.14), so a routing layer that provisions certs dynamically per SNI hostname is structural from day one, not a later retrofit. Stand up the operator running this box (Todd) as the first operator manually using `oddjobtodd.info` (apex → intake bot, `brain.oddjobtodd.info` → WSS), own BRC-52 cert, manual provisioning rows, hard-coded paths, and run the Oddjobz flow end-to-end: customer, job, FSM through to invoice.

Acceptance: full Oddjobz flow works end-to-end for one operator on their own domain. All four engines (LMDB, Flutter SQLite, NATS, Postgres) are wired and the cell engine + Pask kernel commit through them correctly. Caddy provisions and renews the cert without intervention. Don't proceed until this is solid — Phase 2 assumes Phase 1 works.

### Phase 2 — Operator axis (W7 in §4)

This is the meat. ~3-4 weeks for one Zig agent on the brain side, parallel TS work on the Flutter side. See §4 for the matrix.

### Phase 3 — Operational layer (week 5-6)

Per-operator backups: `semantos-export <op_pubkey_hash>` runs nightly for every active operator, ships tarball to B2, retention 30 daily + 12 monthly. Per-operator monitoring: Prometheus labels include `op_pubkey_hash`; dashboards show top-N by cell count, byte storage, event rate, Pask graph size. Status page (statuspage.io free or self-hosted). Billing hook reading from `op_metrics` materialised view if a paid tier exists. DNS for operator subdomains if desired (`<slug>.semantos.au` routed via SNI to the same WSS endpoint, slug → op_pubkey_hash resolved at connect).

### Phase 4 — Onboarding and growth (week 7+)

Soft launch with 5-10 tradies. Watch Postgres working set, LMDB page cache hit rate, NATS storage growth. Iterate on the mobile UX. Once stable, open the gates. Trigger conditions for scaling are in §6.

### 3.5 Operator onboarding flow (the user-facing sequence)

This is what happens when a real tradie installs the Flutter app and signs up. It composes the W7 deliverables into a single user-facing path.

1. **Tradie installs Flutter app** from store. App detects no existing key universe.
2. **App redirects to Plexus.** Plexus generates BRC-52 root cert, derives the BRC-42 key universe, walks the operator through recovery-challenge setup, and seeds the operator with a few million sats from the Plexus faucet (covers months of pushdrop + fee operations at 1 sat per op). Plexus returns control to the Flutter app with a key universe handle and the recovery bundle reference.
3. **Flutter app asks for the operator's domain.** Two paths:
   - Operator owns a domain (e.g. `coastalplumbing.com.au`) — app provides DNS instructions: A record for apex pointing at our box IP, CNAME for `brain.<domain>` pointing at our box FQDN.
   - Operator does not own a domain — app offers a `<slug>.semantos.au` fallback (provisioned the same way internally, but using our DNS zone).
4. **DNS verification.** App polls until DNS resolves correctly to our box. Typical wait: 1–60 minutes depending on the operator's registrar.
5. **TLS provisioning.** App calls our provisioning endpoint (W7.9) which adds the domain to Caddy's allow-list. Caddy provisions the cert via ACME on first connection (HTTP-01 challenge over the now-resolving domain).
6. **Brain registration.** Same provisioning call inserts the operator row in Postgres (W7.2), allocates the LMDB prefix (W7.1), creates the NATS streams (W7.13), and stores the wrapped DEK (W7.5). The operator's `op_pkh` is now live on this box.
7. **Field app federates with brain.** Flutter stores `brain.<domain>` as its WSS endpoint and connects. Cert presented at handshake → SNI hostname resolves to op_pkh → cert chain validates against registered root → operator context bound for connection lifetime.
8. **First Oddjobz flow.** Operator creates a customer, schedules a job, runs the FSM. Pask graph starts populating. Helm view is empty initially and fills as the operator interacts.

Total time end-to-end: 5–15 minutes if the operator's DNS propagates quickly; longer if their registrar is slow. The Plexus portion is whatever Plexus's onboarding takes (TBD when they publish their flow).

If the operator later loses their phone, step 8 is replaced by: install Flutter on the new device → app detects no key universe → redirect to Plexus for recovery → Plexus reconstitutes the key universe from challenges → field app reconnects to `brain.<domain>` and the wrapped DEK unlocks with the recovered keys. We are not in this loop.

---

## 4. Tracking matrix — W7 Hosted-Operator axis

Status: `pending | in_progress | review | merged | blocked`

| ID    | Deliverable                                                                                  | Deps                       | Status  | Acceptance                                                                                                                                |
|-------|----------------------------------------------------------------------------------------------|----------------------------|---------|-------------------------------------------------------------------------------------------------------------------------------------------|
| W7.1  | Operator pubkey hash as structural prefix in LMDB key (`op_pkh (8B raw) ‖ SHA256(cell) (32B)` = 40B total). `LmdbCellStore.init()` uses zero prefix (single-tenant compat). `LmdbCellStore.initForOperator(op_pkh)` scopes cursor to prefix via `MDB_SET_RANGE` + `getCurrent()`/`step()`. `deleteAllCells()` added for W7.8 exit. 5 inline acceptance tests green. K3 domain-isolation conformance: 5 tests (point-lookup, cursor, interleaved, deleteAllCells, zero/named disjointness). `MDB_NOTLS` flag added to all test envs (concurrent read-only txn isolation). | M1.5, W0.2                 | done | Cell read/write paths take an operator context; cursor scans scoped by prefix; cross-operator read returns empty; K3 conformance suite (5/5); `MDB_NOTLS` fixed concurrent-txn test flake. |
| W7.2  | `operators` table (`op_pkh` PK, `root_cert_hash`, `apex_domain`, `brain_domain`, `wrapped_dek`, `plexus_handle`, `status`, `exiting_at`). `op_pkh TEXT DEFAULT '0000000000000000'` added to: `pask_node_view`, `pask_entailment`, `pask_stable_thread`, `session_chain`, `cells_lmdb_cache`, `action_cell_log`, `audit_log_cache`. RLS enabled on all; `semantos_brain` role filtered by `current_setting('semantos.op_pkh', true)`; `semantos_admin` bypasses. Boot operator `'0000000000000000'` seeded. Migration `017_operators_rls.sql`. | M5.1                       | done | Migration deployed; `operators` table created with all constraints; 7 operator-scoped tables have `op_pkh` column + RLS policies; boot operator seeded. |
| W7.3  | NATS JetStream event spine: `nats_client.zig` (TCP client: publish + JetStream API request-reply), `nats_event_producer.zig` (emits to `op.<pkh16>.<hat>.fsm_transition`), stream config (file, 30-day, 10K msgs/subject cap), durable pull consumer for BRAIN brain replay, `jobs_handler.zig` wired with `attachNatsProducer`. Postgres LISTEN/NOTIFY trigger on `cells` for Helm refresh. Stream create/delete lifecycle in ensureStream/deleteStream. | none (NATS install)        | done | VPS: nats-server 2.10.24 running as systemd `nats.service` with JetStream + file storage at `/var/lib/semantos/nats`. `cli.zig` wires `NatsEventProducer` (op_pkh=0000000000000000) into `cmdServe`; `jobs_handler.attachNatsProducer` called. Startup log confirmed: "NATS event spine connected (op_pkh=0000000000000000)". `build.zig` cli_mod imports added. |
| W7.4  | WSS connection auth: SNI hostname → op_pkh resolution + BRC-52 cert chain validation against registered root; delegated subkeys (BRC-42 children) accepted | identity_certs.zig, W7.15  | done    | `wss_operator_auth.zig` — `authenticate(host, pubkey_hex, domain_map, data_dir, allocator) AuthError!AuthContext`. Flow: strip port from Host → `DomainMap.get(bare_host)` → hex-decode `X-Brain-Pubkey` (66 hex = 33-byte compressed pubkey) → `certIdFromPubkey(pubkey)` → load per-operator `CertStore` from `$data_dir/operators/<op_pkh16>/` → `store.get(cert_id)` → `walkChain` (root→ok; child→parent must be live, max depth 8). `wss_wallet.Backend` gains `operator_domain_map: ?*const DomainMap` + `operator_data_dir: []const u8`; `tryUpgradeFromParsed` branches: when `operator_domain_map != null` → operator auth via `X-Brain-Pubkey`; else → bearer token auth. 4 inline tests green (sni_not_registered, bad_pubkey_format, non-hex chars, port strip). Build clean. |
| W7.5  | Wrapped-DEK key flow: device generates KEK from BRC-42 universe, server stores DEK wrapped under KEK, unwrap on connect | W7.4                       | done    | `wrapped_dek_store.zig` — opaque file-backed per-operator store at `$data_dir/operators/<op_pkh16>/wrapped_dek`. `save()/load()/delete()` with hex validation. `wss_wallet.ReactorSession.authenticated_op_pkh16` set after W7.4 operator auth; `wallet.getWrappedDek` JSON-RPC method returns the wrapped blob to the device over the authenticated channel. CLI: `brain wrapped-dek set <op_pkh> <hex>`, `brain wrapped-dek show <op_pkh>`, `brain wrapped-dek delete <op_pkh>`. 6 inline tests green. Build clean. |
| W7.6  | Per-operator resource accounting: cell count, byte storage, event rate, connection time, Pask graph size | W7.1, W7.2                 | done | `018_op_metrics.sql`: `op_metrics` materialized view (UNIQUE index for CONCURRENTLY refresh) joining `operators` with `cells_lmdb_cache`, `pask_node_view`, `pask_entailment`, `action_cell_log`, `session_chain` all by `op_pkh`. `op_metrics_top` view for admin dashboard. `test_op_metrics.sql` verifies view exists, columns present, counts non-negative, boot operator present. |
| W7.7  | Operator export tarball: LMDB cells by prefix + Postgres rows by op_pkh + NATS stream replay + Pask snapshot | W7.1, W7.2, W7.3           | done    | `brain export-operator <op_pkh_hex> --output <path>` writes `export/{cells/<sha256>,pask_snapshot.bin,manifest.json}` TAR; `operator_export.zig` module + `LmdbPaskSnapshotStore.exportRaw()`; K3-isolated, deterministic (LMDB key order), end-of-archive marked + flushed |
| W7.8  | Operator exit: 30-day grace tarball on B2 + atomic drop of operator data; verify no cross-operator leak | W7.1, W7.2, W7.3, W7.7     | done    | `brain exit-operator <op_pkh_hex> [--grace-dir] [--data-dir] [--nats-host] [--dry-run]`: exports grace TAR → deletes LMDB cells → deletes Pask snapshots → deletes NATS stream (best-effort) → prints next-steps checklist (rclone B2 copy + `SELECT operator_exit(...)` + Caddy). SQL: `019_operator_exit.sql` adds `exited` status + `exited_at` column + `operator_exit(op_pkh)` function + `operator_exit_verify(op_pkh)` assertion helper. |
| W7.9  | Provisioning endpoint: assumes Plexus onboarding complete; Flutter POSTs cert + wrapped DEK + Plexus key-universe handle + chosen domain; server registers op_pkh, allocates LMDB prefix, creates NATS streams, adds domain to Caddy | W7.4, W7.5, W7.11, W7.14   | pending | Post-Plexus, new install on Flutter produces a working operator on their own domain in < 15 minutes (DNS-bound); idempotent on retry; no "account" semantics — registration only |
| W7.10 | Per-operator Pask snapshot store: `op_pkh[8]` prefix prepended to all snapshot keys (`op_pkh ++ cert_id ++ be_u64(version)`). `initForOperator(op_pkh)` constructor added. `deleteAllSnapshots()` for W7.8 exit. `lmdb.Cursor.prev()` added (MDB_PREV). `deletePrefixedKeys` collect-then-delete pattern (cursor closed before txn.del). 5 inline acceptance tests green. | M1.11, W7.1                | done | 5/5 inline tests: zero prefix, commit/load scoped, cross-op null, deleteAllSnapshots isolated, rollbackTo scoped. `pask_interact_run` for operator A does not update operator B's graph. |
| W7.11 | Plexus integration as identity + recovery + treasury layer: signup redirects Flutter to Plexus for key-universe creation, recovery-challenge setup, and sat-faucet seeding (a few million sats); recovery flow restores key universe and unlocks wrapped DEKs without our involvement | Plexus backend ready       | pending | New operator path: Flutter → Plexus onboarding → key universe + recovery + sats → return to Flutter → register with brain. Recovery path: simulated device wipe → Plexus recovery → universe restored → wrapped DEKs unlock automatically. No custodial step on our side in either path |
| W7.12 | K3 domain-isolation tests for operator boundary (kernel-layer test, not just storage)        | W7.1                       | done | `tests/k3_domain_isolation_conformance.zig`: 5 tests covering point-lookup isolation, cursor isolation, interleaved-storage count, deleteAllCells boundary, zero/named namespace disjointness. Registered in `build.zig` as `k3_domain_isolation_test` with `lmdb` + `lmdb_cell_store` imports. |
| W7.13 | Per-operator Pravega/NATS stream lifecycle: create on provisioning, delete on exit          | W7.3, W7.8                 | done    | `ensureStream()` called in `cmdServe` at start-up (provisioning endpoint W7.9 will call it at registration). `deleteStream()` wired in W7.8 `operator_exit.zig`. Orphan detection: `brain orphan-streams --known-pkh-list <pkh1,pkh2,...> [--delete]` queries NATS for `op_*` streams not in the caller-supplied active-operator list; `nats_orphan_detector.zig` module + `streamNames()` in `nats_client.zig`. Nightly purge: `tools/deploy/semantos-orphan-streams.{sh,service,timer}` — systemd timer fires at 03:17, queries Postgres for active op_pkhs, invokes brain orphan-streams --delete. |
| W7.14 | Bring-your-own-domain registration + on-demand TLS: `apex_domain` + `brain_domain` columns on `operator` table; DNS verification poller in Flutter; Caddy `on_demand_tls` configured with an `ask` endpoint that consults the operator table | W7.2                       | done    | `apex_domain` + `brain_domain` columns + indexes in `017_operators_rls.sql`. Domain allowlist: `domain_allowlist.zig` (flat file `$data_dir/domain_allowlist`, one FQDN per line). Caddy ask server: `caddy_ask_server.zig` serving `GET /caddy/ask?domain=<fqdn>` → 200/403; `brain caddy-ask [--port 2020] [--data-dir]` subcommand; `tools/deploy/semantos-caddy-ask.service`. CLI: `brain domain-allow <fqdn>` / `brain domain-disallow <fqdn>`. Global Caddy config: `tools/deploy/caddy-globals.conf.example` with `on_demand_tls { ask http://127.0.0.1:2020/caddy/ask }`. `renderGlobalBlock(ask_port)` added to `caddy_template.zig`. Postgres test: `test_byod_domains.sql`. DNS verification poller is Flutter-side (out of scope for brain). |
| W7.15 | SNI-based routing in Caddy: apex `<domain>` → intake bot service; `brain.<domain>` → WSS endpoint; SNI hostname → op_pkh resolution table loaded at startup and refreshed on operator table change | W7.14                      | done    | `sni_domain_map.zig` — `DomainMap` backed by `$data_dir/sni_domain_map.json`; `set/get/remove/loadFromFile/saveToFile`. CLI: `brain sni-map set <brain_domain> <op_pkh_hex>`, `brain sni-map remove <brain_domain>`, `brain sni-map show`. Caddy per-operator site blocks (W7.14 `renderCaddyBlock`) already route `brain.<domain>` → WSS and apex → intake bot by domain. WSS auth (W7.4) will call `DomainMap.get(host)` to bind op_pkh context at handshake time. 8 inline tests green. |

### 4.1 Parallelisation

W7.1 + W7.2 + W7.3 can start in parallel (different layers). W7.14 + W7.15 (BYOD + Caddy routing) start alongside; the routing layer is independent of the storage/cell-engine work. W7.4 follows W7.3 and W7.15 (needs SNI routing for hostname → op_pkh resolution). W7.5 follows W7.4. W7.6 + W7.10 + W7.12 parallel after W7.1+W7.2. W7.7 + W7.8 follow once W7.1–W7.3 are merged. W7.9 + W7.11 are last — provisioning needs Plexus integration ready and Caddy on-demand TLS wired.

---

## 5. Dependency graph

```
Box ready (Phase 0)
    │
    ▼
Phase 1 single-op stack ──────► validates four-engine wiring on Caddy + Todd's domain
    │
    ▼
W7.1 (LMDB op prefix) ──┐
W7.2 (PG RLS)         ──┼──► W7.6 (op metrics)
W7.3 (NATS subjects)  ──┤        │
                        │        ▼
                        ├──► W7.7 (export) ──► W7.8 (exit, 30-day grace)
                        │
                        └──► W7.10 (Pask per op)
                        │
                        └──► W7.12 (K3 op boundary tests)

W7.2 ──► W7.14 (BYOD domain + ACME) ──► W7.15 (SNI routing) ──┐
                                                              │
W7.3 + W7.15 ──► W7.4 (WSS auth) ──► W7.5 (wrapped DEK) ──────┤
                                                              │
Plexus backend ready ──► W7.11 (identity + recovery + faucet)─┤
                                                              ▼
                                                        W7.9 (provisioning endpoint)

W7.3 + W7.8 ──► W7.13 (stream lifecycle)
```

External blockers: Plexus backend (a couple of weeks per Todd, gates W7.11 → W7.9). Everything else can move in parallel now. The BYOD layer (W7.14, W7.15) has no external blocker and is independent of the cell-engine and storage work, so it's a good lane for a TS/ops agent to take while Zig agents work the storage axis.

---

## 6. Capacity and scaling triggers

### 6.1 Capacity model

Per tradie operator, peak day: ~50 cell writes (jobs, visits, photos, quotes, invoices), ~500 reads, ~200 NATS events, negligible Postgres writes, Pask graph growth ~10 nodes. Working set 50–500 MB once they've been on platform a few months, dominated by photo cells at octave 1.

On CBR-1319 (64 GB, 2× 500 GB NVMe RAID 1), realistic capacity: **200–500 active operators** before resource pressure. Bottleneck order as load grows: Postgres working set first (FDW joins materialise into RAM), then LMDB page cache hit rate, then NATS JetStream storage. CPU is not the limit.

### 6.2 Scale-out triggers

**Trigger 1 — sustained 70% RAM utilisation.** Add a second CBR-1319. Hash operators by op_pkh into one of two shards. Routing decision happens at provisioning time (W7.9) — once an operator is on shard A they stay on shard A unless explicitly migrated. No re-architecture; the W7 design makes this a routing change.

**Trigger 2 — heavy individual operator outgrows shared box.** When one operator hits 50K cells or 10K events/day (large multi-crew tradie business), give them their own dedicated CBR-1319 or sell them an upgrade tier. The federation tier (M7) is the migration path — their dedicated box is a federation peer holding the slots for their op_pkh, the export tarball (W7.7) is the hand-off artefact, and the operator's cert continues to work without re-issuance.

**Trigger 3 — operator wants their own hardware.** Same path as trigger 2 but the destination box is theirs. The export tarball is what they hand to their own ops team. We get out of the hosting relationship cleanly; no custody dispute because we never had custody of the keys.

---

## 7. What "done" looks like for the stand-up

The hosted-operator box is in production when:

1. CBR-1319 is racked, monitored, backed up, restorable from backup.
2. All §4 W7 rows are `merged` except those still gated on Plexus (W7.9, W7.11) which are merged within two weeks of Plexus going live.
3. Phase 1 single-operator validation (Todd's own Oddjobz flow) survives 7-day soak with no incidents.
4. 5–10 real tradie operators are onboarded, each running their daily Oddjobz workflow; metrics show < 1% error rate, < 100 ms p99 cell write, < 1 s p99 Helm view refresh.
5. Operator export tarball verified: an exported operator can be `--import`-ed to a fresh CBR-1319 and replays byte-identically (cells, NATS streams, Postgres rows, Pask snapshot all reproduce).
6. Plexus recovery verified: a simulated device wipe followed by Plexus recovery restores full key universe and all wrapped DEKs unlock; the operator resumes operation from a new device without our intervention.
7. K3 domain isolation tests (W7.12) pass — adversarial cross-operator probes are rejected at the kernel layer, not just storage.

Out of scope for v1: cross-operator federation features, multi-box sharding (trigger 1 above is when this gets implemented), self-hosted operator option (trigger 3 above; documented as a path, not built day one).

---

## 8. Open questions

### 8.1 Resolved

1. **Domain story.** ✅ BYOD from v1. Operators bring their own domain (apex → intake bot, `brain.<domain>` → WSS); `<slug>.semantos.au` is offered as a fallback for operators without a domain, provisioned through the same Caddy on-demand TLS path. W7.14 + W7.15 implement this.
2. **Plexus challenge transport.** ✅ Direct Flutter → Plexus. Brain stays out of the recovery loop entirely. W7.11 specifies this.
3. **Operator exit data retention.** ✅ 30-day grace tarball on B2; primary deletion immediate. W7.8 specifies this.
4. **Plexus scope.** ✅ Plexus is identity + recovery + treasury — at signup it issues the BRC-52 cert + BRC-42 universe, sets up recovery challenges, and seeds the operator with a few million sats from its faucet to cover months of pushdrop and tx-fee operations. The hosted brain only respects identity; treasury is Plexus's concern. W7.11 specifies this.
5. **NATS persistence durability vs. cost.** ✅ Same NVMe pool as everything else for v1.
6. **K3 boundary at the operator level vs. the hat level.** ✅ Structural enforcement at storage in v1; kernel-level operator-flag check is a Phase 5 hardening item. W7.12 covers the v1 tests.

### 8.2 Still open

1. **Sat replenishment after the Plexus faucet runs out.** What's the model? Operator buys more sats from Plexus on demand? Hosting fee bundles a periodic top-up? Operator is responsible for funding their own key universe? Probably a Plexus-product question rather than a hosted-brain-architecture question, but the answer affects how operators experience long-term running costs and should be settled before broad launch.
2. **Pricing tier exposure of cell/event quotas.** If there's a paid tier on the hosting side, what are the limits and how are they enforced? Affects W7.6 (which metrics drive billing). Punt to product; architecture supports any model.
3. **Domain operational hazards.** What happens when an operator's domain registration lapses, their DNS provider breaks, or they accidentally point the CNAME elsewhere? Recommendation: Caddy keeps the cached cert valid until expiry (typically 90 days); we monitor the resolution and warn the operator + their Flutter app via in-app alert when DNS drifts. Worth a small W7 row before broad launch.
4. **ACME challenge type.** HTTP-01 is simpler (Caddy default) but requires the operator's domain to resolve to our box's port 80 before the cert is issued — a brief window where intake-bot traffic could fail. DNS-01 needs API access to the operator's DNS, which they probably won't grant. Recommendation: HTTP-01 with a "TLS not ready yet" page served on port 80 during the bootstrap window; revisit if it becomes a UX problem.
5. **BRC-42 subkey delegation UI.** The architecture supports delegated subkeys for additional devices and apprentice/contractor capability grants, but the Flutter UX for managing delegations isn't specified here. Out of scope for stand-up; flag for the Oddjobz product team.

---

## 9. Document maintenance

This pipeline is the source of truth for hosted-operator stand-up work. Edit status in-place. New rows get IDs `W7.<next>` continuing the sequence. Cross-link from `BRAIN-FIELD-APP-DB-PIPELINE.md` once W7 starts shipping.

If the hosting model itself changes (e.g. operators get accounts after all, or we move to per-operator containers, or Plexus integration changes shape), revise §1 (architectural principle) first; the matrix follows from it, not the reverse.
