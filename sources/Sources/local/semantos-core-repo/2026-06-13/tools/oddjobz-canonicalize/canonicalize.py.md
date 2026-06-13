---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/tools/oddjobz-canonicalize/canonicalize.py
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.548625+00:00
---

# tools/oddjobz-canonicalize/canonicalize.py

```py
#!/usr/bin/env python3
"""oddjobz-canonicalize — dedup + fold the oddjobz entity-cell graph in place.

Re-emits the cell graph canonically by EDITING FROM THE TEMPLATE: each changed
cell keeps its real brain-minted 256B header and only its payload + payload_total
(off 90) + domain_payload_root (off 224) are rewritten, then rehashed
(key = sha256(cell[:1024])). Reference repointing is a format-preserving 64-hex
substring substitution in the payload bytes — same length, no reserialization.

Validated invariants (see /tmp/validate.py, 6297/6297):
  key            == sha256(cell[:1024])
  cell[224:256]  == sha256(payload)              payload = cell[256:256+ptot]
  payload_total   = u32 LE at cell[90:94]        (all <= 767, inline only)

Dedup model (role-aware, site-first):
  sites      -> by normalized_address                       (survivors stable)
  customers  -> agent/property_manager: by email|name (one person across sites)
                site_owner (landlord):  by name
                tenant:                 by name + CANONICAL site
                other:                  by name + canonical site
  jobs       -> real work_orders kept; invoice-event jobs (no customer_refs,
                summary~invoice / display_name=todd price) FOLDED into the real
                job at the same canonical site (attachments re-linked); dropped.
  attachments-> kept; jobRef/parent repointed to survivors.

Usage:
  canonicalize.py <lmdb_dir>            # dry-run: report only, no writes
  canonicalize.py <lmdb_dir> --apply   # rewrite the primary `cells` DB in place
                                        # (then re-run backfill bin to rebuild indices)
"""
import lmdb, binascii, hashlib, json, re, ast, sys, collections

LMDB_DIR = sys.argv[1]
APPLY = "--apply" in sys.argv

P_TOTAL, P_ROOT, HDR = slice(90, 94), slice(224, 256), 256
HEXRE = re.compile(rb"[0-9a-f]{64}")
sha = lambda b: hashlib.sha256(b).digest()
hx = lambda b: binascii.hexlify(b).decode()
norm = lambda s: re.sub(r"\s+", " ", str(s or "").strip().lower())


def parse_payload(cell):
    ptot = int.from_bytes(cell[P_TOTAL], "little")
    raw = bytes(cell[HDR:HDR + ptot])
    s = raw.decode("utf-8", "ignore").strip()
    try:
        return raw, json.loads(s)
    except Exception:
        m = re.search(r"\{.*\}", s, re.S)
        try:
            return raw, (json.loads(m.group(0)) if m else None)
        except Exception:
            return raw, None


def reemit(orig_cell, new_payload: bytes):
    """Edit-from-template: keep header, swap payload + len + root, rehash."""
    assert len(new_payload) <= 768, "payload over inline budget"
    c = bytearray(orig_cell[:1024])
    c[P_TOTAL] = len(new_payload).to_bytes(4, "little")
    c[P_ROOT] = sha(new_payload)
    c[HDR:1024] = b"\x00" * 768
    c[HDR:HDR + len(new_payload)] = new_payload
    cell = bytes(c)
    return cell, hx(sha(cell))


def hexreplace(payload: bytes, remap: dict) -> bytes:
    """Replace any 64-hex token that is a remap key with its survivor (same len)."""
    def sub(m):
        t = m.group(0).decode()
        return remap.get(t, t).encode()
    return HEXRE.sub(sub, payload)


# ── Load every cell (typeHash prefix -> kind) ────────────────────────────────
TYPES = {"c0555cda": "job", "eef2434c": "customer", "403aeb29": "site",
         "fb1a23a8": "attachment"}
env = lmdb.open(LMDB_DIR, readonly=not APPLY, lock=APPLY, max_dbs=64,
                map_size=2 * 1024 * 1024 * 1024)
cells_db = env.open_db(b"cells", create=False)

cells = {}   # key_hex -> {kind, cell(bytes), raw(payload bytes), p(dict)}
with env.begin(db=cells_db) as t:
    for k, v in t.cursor():
        kh = hx(bytes(k[8:40]))
        cell = bytes(v[:1024])
        th = hx(cell[30:62])[:8]
        raw, p = parse_payload(cell)
        cells[kh] = dict(kind=TYPES.get(th, th[:8]), cell=cell, raw=raw, p=p,
                         key8=bytes(k[:8]))
print("loaded %d cells" % len(cells))


def of(kind):
    return [(kh, c) for kh, c in cells.items() if c["kind"] == kind]


def complete(p, fields):
    return sum(1 for f in fields if p and p.get(f))


new_cells = {}             # final_key -> cell bytes (cells to write)
delete = set()             # orig keys to delete

# ── Phase 1: SITES (leaf; survivors stable, no re-emit) ──────────────────────
site_clusters = collections.defaultdict(list)
for kh, c in of("site"):
    key = norm((c["p"] or {}).get("normalized_address") or (c["p"] or {}).get("raw_address"))
    site_clusters[key].append(kh)
site_remap = {}   # any-site-key -> survivor (survivor maps to itself)
for key, members in site_clusters.items():
    surv = min(members, key=lambda kh: (-complete(cells[kh]["p"], ["normalized_address", "key_number", "raw_address"]), kh))
    for kh in members:
        site_remap[kh] = surv
        if kh != surv:
            delete.add(kh)          # drop duplicate site cells
site_survivors = set(site_remap.values())
print("sites: %d -> %d survivors" % (len(of("site")), len(site_survivors)))


# ── Phase 2: CUSTOMERS (repoint site refs first, then dedup role-aware) ───────
def canon_site(p):
    s = str((p or {}).get("linked_site_id", ""))
    return site_remap.get(s, s)


def ckey(p):
    role = str((p or {}).get("role", ""))
    em, nm = norm((p or {}).get("email")), norm((p or {}).get("name"))
    if role in ("agent", "property_manager"):
        return ("person", em or nm)
    if role == "site_owner":
        return ("landlord", nm)
    return (role or "other", nm, canon_site(p))


cust_clusters = collections.defaultdict(list)
for kh, c in of("customer"):
    cust_clusters[ckey(c["p"])].append(kh)

cust_remap = {}            # orig customer key -> survivor FINAL key
for key, members in cust_clusters.items():
    surv = min(members, key=lambda kh: (-complete(cells[kh]["p"], ["email", "phone", "name", "notes"]), kh))
    # survivor's final cell = its payload with site refs repointed
    new_payload = hexreplace(cells[surv]["raw"], site_remap)
    cell, final_key = reemit(cells[surv]["cell"], new_payload)
    new_cells[final_key] = cell
    for kh in members:
        cust_remap[kh] = final_key
        if kh != final_key:
            delete.add(kh)
    if surv != final_key:
        delete.add(surv)   # survivor's old hash replaced by re-emitted one
cust_survivors = set(cust_remap.values())
print("customers: %d -> %d survivors" % (len(of("customer")), len(cust_survivors)))

# leaf remap applied to everything downstream
leaf_remap = {}
leaf_remap.update(site_remap)
leaf_remap.update(cust_remap)


# ── Phase 3: JOBS — split real vs invoice-event ──────────────────────────────
def is_event(p):
    if not p:
        return False
    return (not p.get("customer_refs")
            and ("invoice" in norm(p.get("summary")) or norm(p.get("display_name")) == "todd price"))


job_final = {}     # orig job key -> final key (real jobs, re-emitted)
job_remap = {}     # orig -> final (only when changed)
real_jobs = []
event_jobs = []
for kh, c in of("job"):
    (event_jobs if is_event(c["p"]) else real_jobs).append(kh)

for kh in real_jobs:
    new_payload = hexreplace(cells[kh]["raw"], leaf_remap)
    if new_payload == cells[kh]["raw"]:
        job_final[kh] = kh
        continue
    cell, fk = reemit(cells[kh]["cell"], new_payload)
    new_cells[fk] = cell
    job_final[kh] = fk
    job_remap[kh] = fk
    delete.add(kh)

# parent lookup: canonical site_ref -> [final job keys]
site_to_jobs = collections.defaultdict(list)
for orig, fk in job_final.items():
    sref = str((cells[orig]["p"] or {}).get("site_ref", ""))
    site_to_jobs[site_remap.get(sref, sref)].append(fk)

event_fold = {}     # event job key -> parent FINAL key
event_unmatched = []
for kh in event_jobs:
    sref = str((cells[kh]["p"] or {}).get("site_ref", ""))
    canon = site_remap.get(sref, sref)
    parents = site_to_jobs.get(canon, [])
    if parents:
        event_fold[kh] = sorted(parents)[0]
        delete.add(kh)
    else:
        event_unmatched.append(kh)   # fallback: keep standalone (treat as real)
# keep unmatched events as-is but still repoint their refs
for kh in event_unmatched:
    new_payload = hexreplace(cells[kh]["raw"], leaf_remap)
    if new_payload != cells[kh]["raw"]:
        cell, fk = reemit(cells[kh]["cell"], new_payload)
        new_cells[fk] = cell
        job_final[kh] = fk
        delete.add(kh)
    else:
        job_final[kh] = kh
print("jobs: %d real, %d invoice-events (%d folded, %d kept standalone)"
      % (len(real_jobs), len(event_jobs), len(event_fold), len(event_unmatched)))


# ── Phase 4: ATTACHMENTS (leaves) — repoint jobRef/parent ────────────────────
# Repoint over EVERY job whose key changed (real + standalone-event re-emits)
# plus folded events -> parent. Using job_final (not just job_remap) is what
# prevents attachments on re-emitted standalone events from dangling.
job_repoint = {old: fk for old, fk in job_final.items() if old != fk}
att_remap = {}
att_remap.update(leaf_remap)
att_remap.update(job_repoint)
att_remap.update(event_fold)
att_changed = 0
for kh, c in of("attachment"):
    new_payload = hexreplace(c["raw"], att_remap)
    if new_payload == c["raw"]:
        continue
    cell, fk = reemit(c["cell"], new_payload)
    new_cells[fk] = cell
    delete.add(kh)
    att_changed += 1
print("attachments: %d re-pointed" % att_changed)


# ── Net + write ──────────────────────────────────────────────────────────────
survivors_unchanged = len(cells) - len(delete)
print("\n=== NET ===")
print("  before:            %d cells" % len(cells))
print("  delete (dups/old): %d" % len(delete))
print("  write (re-emitted):%d" % len(new_cells))
print("  after:             %d cells" % (survivors_unchanged + len(new_cells)))

if not APPLY:
    print("\n[dry-run] no writes. Re-run with --apply on a scratch copy.")
    sys.exit(0)

OP_PKH = next(iter(cells.values()))["key8"]   # all share op_pkh=0
wrote = deleted = 0
with env.begin(db=cells_db, write=True) as t:
    for kh in delete:
        if t.delete(bytes.fromhex("0000000000000000") + bytes.fromhex(kh)) or \
           t.delete(OP_PKH + bytes.fromhex(kh)):
            deleted += 1
    for fk, cell in new_cells.items():
        val = cell + b"\x00" * (4096 - len(cell))
        t.put(OP_PKH + bytes.fromhex(fk), val)
        wrote += 1
print("\n[apply] deleted=%d wrote=%d" % (deleted, wrote))
print("[apply] NOTE: secondary indices now stale — clear them + re-run "
      "brain-backfill-cell-indices to rebuild cells_by_type/owner/prev_state.")
env.close()

```
