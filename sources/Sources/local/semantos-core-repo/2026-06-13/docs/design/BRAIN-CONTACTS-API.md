---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/design/BRAIN-CONTACTS-API.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.740228+00:00
---

# D-brain-contacts-api — Brain HTTP Contact Book

**Deliverable**: `D-brain-contacts-api`  
**Phase**: `shell-port-1`  
**Precondition for**: `D-helm-contacts-panel`, `D-svelte-find-network`

---

## Endpoints

| Method | Path | Op |
|--------|------|----|
| `GET` | `/api/v1/contacts` | List all contacts |
| `POST` | `/api/v1/contacts` | Add contact |
| `GET` | `/api/v1/contacts/{certId}` | Get one contact |
| `POST` | `/api/v1/contacts/{certId}/edges` | Create edge (store-only; caller pre-computes ECDH params) |
| `DELETE` | `/api/v1/contacts/{certId}/edges/{edgeId}` | Soft-revoke edge |

All endpoints are bearer-gated. The edge `POST`/`DELETE` do **not** run ECDH themselves — the
TypeScript layer (Plexus SDK) computes `edgeId + signingKeyIndex` and POSTs the result.
The brain stores it. Re-derivation happens client-side using `signingKeyIndex`.

## Storage

Two entity types added to the shared LMDB cell store:

| Tag | Constant | Type path | Payload |
|-----|----------|-----------|---------|
| `0x0A` | `ENTITY_TAG_CONTACT` | — | Contact JSON |
| `0x0B` | `ENTITY_TAG_EDGE` | — | Edge JSON |

Contact JSON (≤1008 bytes):
```json
{"certId":"<hex>","publicKey":"<hex66>","displayName":"Alice",
 "email":"alice@example.com","source":"manual",
 "addedAt":1716499200000,"updatedAt":1716499200000}
```

Edge JSON (≤1008 bytes):
```json
{"edgeId":"<hex>","certId":"<hex>","edgeType":"MESSAGING",
 "signingKeyIndex":42,"recoveryPolicy":"NONE","createdAt":1716499200000}
```

Revoking an edge writes a new cell with `"revokedAt":<ms>` added. Edges are **never**
hard-deleted — the cell store retains the audit trail. Per Plexus spec §1.1.8.

## Files

| File | What |
|------|------|
| `src/contact_book_lmdb.zig` | LMDB-backed store for contacts + edges |
| `src/contacts_http.zig` | HTTP acceptor (DI fn pointers, no LMDB dep in tests) |
| `src/entity_cell.zig` | + `ENTITY_TAG_CONTACT` (0x0A), `ENTITY_TAG_EDGE` (0x0B) |
| `src/site_server.zig` | + `contacts_acceptor` field + `attachContactsEndpoint` |
| `src/site_server/reactor.zig` | + `reactorHandleContacts` route at `/api/v1/contacts` |
| `build.zig` | + `contact_book_lmdb_mod` + `contacts_http_mod` modules + tests |
| `src/cli/serve.zig` | Wire store init + acceptor at brain boot |

## Decisions

**certId as string**: stored as hex string (64 chars = 32-byte SHA-256). Consistent with
how `attachments_store_lmdb.zig` stores `captured_by_cert_id`.

**Single-pass replay**: unlike `sites_store_lmdb` (two-pass for "created"/"signed" events),
contacts use upsert-by-certId semantics — a later cell with the same certId simply wins.
Edge revocation similarly upserts by edgeId and updates `revokedAt`.

**No ECDH on server**: the brain never touches secp256k1 for contacts. ECDH is a client-side
operation; only the resulting `edgeId` + `signingKeyIndex` are stored.

**LMDB cell key**: SHA-256 of the cell bytes (content-addressed, same as all other entities).
In-memory HashMap<certId → index> provides O(1) lookup.
