---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/scripts/rpc_e2e.py
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.170070+00:00
---

# runtime/semantos-brain/scripts/rpc_e2e.py

```py
#!/usr/bin/env python3
"""Manual end-to-end smoke test for the unified WSS RPC channel (/api/v1/rpc).

Proves the channel routes substrate methods through the runtime RpcRegistry —
notably that `cell.query` reaches a LIVE handler here, unlike the legacy
wss_wallet static if-chain where a Zig 0.15.2 codegen bug silently eliminated
the cell.query/cell.get branches (see memory: brain_build_cellquery_anomaly).

Setup (isolated data dir so real brain data is untouched):

    export BRAIN_DATA_DIR=$(mktemp -d /tmp/rpc-e2e.XXXXXX)
    B=runtime/semantos-brain/zig-out/bin/brain
    TOKEN=$($B bearer issue --label e2e --ttl-seconds 3600 | grep -oE '[0-9a-f]{64}')
    $B serve localhost --enable-repl --port 8799 &
    RPC_TOKEN=$TOKEN RPC_PORT=8799 python3 runtime/semantos-brain/scripts/rpc_e2e.py

Exits 0 on PASS, 1 on FAIL. Requires the `websockets` pip package.
"""
import asyncio, json, os, sys, urllib.request
import websockets

PORT = os.environ.get("RPC_PORT", "8799")
TOKEN = os.environ.get("RPC_TOKEN", "")
URI = f"ws://127.0.0.1:{PORT}/api/v1/rpc"
HDRS = {"Authorization": f"Bearer {TOKEN}"}

# M1.7 dual-path parity (optional): when a registered typeHash is provided,
# the harness mints the SAME body over BOTH transports — HTTP `POST /api/v1/cells`
# and the `cells.mint` RPC frame — and asserts identical {cellId,cartridgeId,
# cellType}. Skipped (routing-only) on a bare brain where no cellType is
# registered. Set e.g. RPC_MINT_TYPEHASH=<64hex> RPC_MINT_PAYLOAD='{"k":"v"}'.
MINT_TYPEHASH = os.environ.get("RPC_MINT_TYPEHASH", "")
MINT_PAYLOAD = os.environ.get("RPC_MINT_PAYLOAD", '{"smoke":"m17"}')


def http_mint(type_hash_hex, payload_obj):
    """POST /api/v1/cells — returns the parsed JSON 201 body (or raises)."""
    body = json.dumps({"typeHashHex": type_hash_hex, "payload": payload_obj}).encode()
    req = urllib.request.Request(
        f"http://127.0.0.1:{PORT}/api/v1/cells", data=body, method="POST",
        headers={"Authorization": f"Bearer {TOKEN}", "Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=5) as r:
        return json.loads(r.read())


async def main():
    if not TOKEN:
        print("set RPC_TOKEN (a 64-hex bearer issued into the serve's data dir)")
        sys.exit(2)
    # websockets >=14 renamed extra_headers -> additional_headers.
    try:
        conn = websockets.connect(URI, additional_headers=HDRS)
        ws = await conn.__aenter__()
    except TypeError:
        conn = websockets.connect(URI, extra_headers=HDRS)
        ws = await conn.__aenter__()
    try:
        async def call(frame, label):
            await ws.send(json.dumps(frame))
            resp = await asyncio.wait_for(ws.recv(), timeout=5)
            print(f"--- {label} ---\n  sent: {json.dumps(frame)}\n  recv: {resp}")
            return json.loads(resp)

        r1 = await call({"t": "req", "id": "a1", "method": "repl.eval",
                         "params": {"cmd": "status"}}, "repl.eval status")
        r2 = await call({"t": "req", "id": "a2", "method": "cell.query",
                         "params": {"typeHash": "oddjobz.job.v2"}}, "cell.query")
        # B3 — cell.get routes to the same live handler. A bare brain has no
        # decoder for this typeHash → structured not_found (unknown_type_hash);
        # that still proves the method ROUTED (NOT an unknown_method drop).
        r2b = await call({"t": "req", "id": "a2b", "method": "cell.get",
                          "params": {"typeHash": "oddjobz.job.v2", "cellRef": "ab" * 32}},
                         "cell.get routing")
        r3 = await call({"t": "req", "id": "a3", "method": "bogus.method",
                         "params": {}}, "unknown method")
        # M1.7 — cells.mint with a bogus typeHash routes to the live handler
        # and returns a structured not_found (unknown_type_hash), proving the
        # method is registered (NOT an unknown_method drop) even on a bare brain.
        bogus_th = "ff" * 32
        r4 = await call({"t": "req", "id": "a4", "method": "cells.mint",
                         "params": {"typeHashHex": bogus_th, "payload": {"k": "v"}}},
                        "cells.mint routing")

        ok = True
        if not (r1.get("t") == "res" and r1.get("id") == "a1" and "result" in r1):
            ok = False; print("FAIL repl.eval shape")
        # cell.query routes to a live handler: res (with data) or a structured
        # err (unknown_type_hash when no decoder is registered) both prove
        # routing — what matters is it is NOT an unknown_method drop.
        if not (r2.get("id") == "a2" and r2.get("t") in ("res", "err")
                and r2.get("code") != "unknown_method"):
            ok = False; print("FAIL cell.query routing")
        if not (r2b.get("id") == "a2b" and r2b.get("t") in ("res", "err")
                and r2b.get("code") != "unknown_method"):
            ok = False; print("FAIL cell.get routing")
        if not (r3.get("t") == "err" and r3.get("code") == "unknown_method"):
            ok = False; print("FAIL unknown_method")
        # cells.mint must ROUTE: structured not_found, not an unknown_method drop.
        if not (r4.get("id") == "a4" and r4.get("t") == "err"
                and r4.get("code") == "not_found"):
            ok = False; print("FAIL cells.mint routing")

        # M1.7 dual-path parity — only when a registered typeHash is provided.
        # Mint the SAME body over HTTP `POST /api/v1/cells` and the `cells.mint`
        # RPC frame, then assert the resolved metadata matches.
        #
        # Invariant = {cartridgeId, cellType} identical + BOTH return a
        # well-formed 64-hex cellId. We do NOT assert cellId EQUALITY: the cell
        # embeds a mint timestamp (substrate_entity bytes 78..85 = nanoTimestamp
        # at mint), so two separate mints of identical input hash differently by
        # construction. Equal cartridgeId+cellType + valid cellId proves both
        # transports drive the same core to the same resolved cellType.
        if MINT_TYPEHASH:
            import re
            payload = json.loads(MINT_PAYLOAD)
            http_body = http_mint(MINT_TYPEHASH, payload)
            rpc = await call({"t": "req", "id": "a5", "method": "cells.mint",
                              "params": {"typeHashHex": MINT_TYPEHASH, "payload": payload}},
                             "cells.mint parity (RPC)")
            print(f"--- HTTP mint ---\n  recv: {json.dumps(http_body)}")
            rpc_res = rpc.get("result", {}) if rpc.get("t") == "res" else {}
            hex64 = re.compile(r"^[0-9a-f]{64}$")
            meta_match = all(http_body.get(k) == rpc_res.get(k) for k in ("cartridgeId", "cellType"))
            ids_valid = bool(hex64.match(str(http_body.get("cellId", "")))) and \
                bool(hex64.match(str(rpc_res.get("cellId", ""))))
            if not (rpc.get("t") == "res" and meta_match and ids_valid):
                ok = False
                print("FAIL cells.mint dual-path parity:")
                print(f"  HTTP: {[http_body.get(k) for k in ('cellId','cartridgeId','cellType')]}")
                print(f"  RPC : {[rpc_res.get(k) for k in ('cellId','cartridgeId','cellType')]}")
            else:
                print("OK   cells.mint dual-path parity "
                      "(cartridgeId+cellType match; both cellIds well-formed; "
                      "cellId differs only by embedded mint timestamp)")
        else:
            print("SKIP cells.mint dual-path parity (set RPC_MINT_TYPEHASH to enable)")

        print("\nE2E RESULT:", "PASS" if ok else "FAIL")
        sys.exit(0 if ok else 1)
    finally:
        await conn.__aexit__(None, None, None)


asyncio.run(main())

```
