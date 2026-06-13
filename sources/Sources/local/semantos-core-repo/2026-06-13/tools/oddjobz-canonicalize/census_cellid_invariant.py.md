---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/tools/oddjobz-canonicalize/census_cellid_invariant.py
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.548351+00:00
---

# tools/oddjobz-canonicalize/census_cellid_invariant.py

```py
#!/usr/bin/env python3
"""Read-only census: verify the cellId <-> content-hash <-> reference invariant.

Opens the env readonly=True, lock=False — never disturbs the live writer.
Answers, against real prod cells:
  Q1. key[8:40] == sha256(cell)?                          (content-hash invariant)
  Q2. customer payloads: which identity fields are present (name/display_name/cellId)?
  Q3. job customer_refs[].cell_id + site_ref: do they resolve to a cell's
      CONTENT HASH (LMDB key[8:40])?  i.e. are references content hashes?
  Q4. when a customer payload carries a logical `cellId`, does it equal the
      content hash, or differ (and is anything pointing at the logical id)?
"""
import lmdb, hashlib, json, collections, sys

LMDB_DIR = sys.argv[1] if len(sys.argv) > 1 else "/var/lib/semantos/entity_cells_lmdb"
HDR = 256
sha = lambda b: hashlib.sha256(b).digest()
hx = lambda b: b.hex()

# typeHash[:4] hex prefixes (handoff §2)
TYPES = {
    "c0555cda": "job", "eef2434c": "customer", "403aeb29": "site",
    "fb1a23a8": "attachment", "06c604b3": "voice", "06d0a049": "voice",
}

env = lmdb.open(LMDB_DIR, readonly=True, lock=False, max_dbs=64)
cells = env.open_db(b"cells", create=False)

# Pass 1: load. content_hash(hex) -> dict(type, payload, key, logical_cellid)
by_chash = {}
key_is_chash = 0
key_total = 0
type_counts = collections.Counter()
cust_field_counts = collections.Counter()
cust_logical_cellid_vs_chash = collections.Counter()

with env.begin(db=cells) as t:
    for k, v in t.cursor():
        cell = bytes(v[:1024])
        chash = sha(cell)
        key_total += 1
        # key layout: op_pkh(8) + sha256(cell)(32)
        if len(k) >= 40 and bytes(k[8:40]) == chash:
            key_is_chash += 1
        th = hx(cell[30:62])[:8]
        typ = TYPES.get(th, th)
        type_counts[typ] += 1
        ptot = int.from_bytes(cell[90:94], "little")
        payload = cell[HDR:HDR + ptot]
        p = None
        try:
            p = json.loads(payload.decode("utf-8", "replace"))
        except Exception:
            p = None
        by_chash[hx(chash)] = dict(type=typ, p=p, key=bytes(k))
        if typ == "customer" and isinstance(p, dict):
            for f in ("name", "display_name", "cellId", "role", "email",
                      "phone", "linked_site_id", "siteRef", "id"):
                if p.get(f) not in (None, ""):
                    cust_field_counts[f] += 1
            lc = p.get("cellId")
            if isinstance(lc, str) and len(lc) == 64:
                cust_logical_cellid_vs_chash[
                    "equals_content_hash" if lc == hx(chash) else "differs"
                ] += 1
            elif lc:
                cust_logical_cellid_vs_chash["present_nonhex"] += 1
            else:
                cust_logical_cellid_vs_chash["absent"] += 1

chash_set = set(by_chash.keys())

# Pass 2: references. For each job, check customer_refs[].cell_id + site_ref.
ref_resolves_to_chash = collections.Counter()
ref_target_type = collections.Counter()
site_ref_resolves = collections.Counter()
jobs_seen = 0
sample_unresolved = []

for chash, rec in by_chash.items():
    if rec["type"] != "job" or not isinstance(rec["p"], dict):
        continue
    jobs_seen += 1
    p = rec["p"]
    refs = p.get("customer_refs") or []
    if isinstance(refs, list):
        for r in refs:
            cid = (r or {}).get("cell_id") if isinstance(r, dict) else None
            if not isinstance(cid, str) or len(cid) != 64:
                ref_resolves_to_chash["malformed_or_absent"] += 1
                continue
            if cid in chash_set:
                ref_resolves_to_chash["resolves_to_content_hash"] += 1
                ref_target_type[by_chash[cid]["type"]] += 1
            else:
                ref_resolves_to_chash["NOT_a_content_hash"] += 1
                if len(sample_unresolved) < 5:
                    sample_unresolved.append(cid)
    sr = p.get("site_ref")
    if isinstance(sr, str) and len(sr) == 64:
        site_ref_resolves["resolves_to_content_hash" if sr in chash_set
                          else "NOT_a_content_hash"] += 1
    elif sr:
        site_ref_resolves["present_malformed"] += 1
    else:
        site_ref_resolves["absent"] += 1

print("== Q1 content-hash invariant ==")
print(f"  key[8:40]==sha256(cell): {key_is_chash}/{key_total}")
print("== types ==")
for t_, n in type_counts.most_common():
    print(f"  {t_:12} {n}")
print("== Q2 customer identity fields present (of customers) ==")
for f, n in cust_field_counts.most_common():
    print(f"  {f:16} {n}")
print("== Q4 customer logical payload.cellId vs content hash ==")
for kk, n in cust_logical_cellid_vs_chash.most_common():
    print(f"  {kk:22} {n}")
print(f"== Q3 job customer_refs (jobs={jobs_seen}) ==")
for kk, n in ref_resolves_to_chash.most_common():
    print(f"  {kk:26} {n}")
print("  -> ref target cell types:", dict(ref_target_type))
print("== Q3 job site_ref ==")
for kk, n in site_ref_resolves.most_common():
    print(f"  {kk:26} {n}")
if sample_unresolved:
    print("  sample unresolved customer refs:", sample_unresolved)
env.close()

```
