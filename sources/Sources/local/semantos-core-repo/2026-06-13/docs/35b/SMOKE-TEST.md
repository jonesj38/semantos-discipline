---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/35b/SMOKE-TEST.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.755603+00:00
---

# Phase 35B.1 — Two-Node Federation Smoke Test

A copy-paste recipe for getting two Semantos nodes federating across the
public internet. Authenticated handshake, no media, no UI — just proof
that the protocol survives real network conditions before any of the
35B.2 / 35B.3 product surface gets built on top.

If `alice.publish()` fires `bob.subscribe()`'s callback across two boxes
on different hosting providers, the federation plane works. Everything
above this line is then a UX choice.

---

## Pre-requisites

On each box (call them **A** and **B**):

| Need | Why |
|---|---|
| A reachable WSS endpoint | The other side has to be able to `new WebSocket(url)` and reach you. See [PRD §Reachability](../prd/PHASE-35B-NODE-AS-SERVICE.md#reachability--what-actually-counts-as-a-node-endpoint). A $4/mo BinaryLane / Hetzner / DO box with public IPv6 is the cheapest path; a Cloudflare tunnel or Tailscale endpoint also works. |
| Inbound port open | Default 8443. Adjust your cloud firewall / `ufw` to allow inbound TCP. |
| `bun` installed | The node runs on Bun. `curl -fsSL https://bun.sh/install \| bash` |
| The semantos repo cloned | `git clone https://github.com/todriguez/semantos-core.git && cd semantos-core && bun install` |

Both boxes need the [PR #127](https://github.com/todriguez/semantos-core/pull/127) `bootstrap_peers` schema landed — otherwise you'll be wiring the locator programmatically. Check with `git log origin/main --oneline | grep 35B.1c`.

---

## Step 1 — Mint a license + privkey on each box

The `--generate` flag makes mint a one-shot operation: random keypair,
license signed by the dev issuer, both files written.

```bash
sudo mkdir -p /etc/semantos
sudo chown $USER /etc/semantos
bun run runtime/node/src/cli.ts license mint --generate \
  --out /etc/semantos/node.license \
  --out-privkey /etc/semantos/node.privkey
chmod 600 /etc/semantos/node.privkey
```

Output looks like:

```
Wrote 161 bytes to /etc/semantos/node.license
  certId:  sha256:00dc485924e6624f4a3c28c02de6292f0c73699024c91b1f1191d6b65388917d
  holder:  020c62af5b3ca15bbf8afed6124ea32e678b3c53e89836b144005b26379ce6be72
  issuer:  dev-issuer (029dc24987...)
  services: session
  expiry:  never
Wrote private key to /etc/semantos/node.privkey
  IMPORTANT: chmod 600 this file before booting a node
```

Verify the file at any time:

```bash
bun run runtime/node/src/cli.ts license show /etc/semantos/node.license
```

---

## Step 2 — First boot to surface your BCA + endpoint

Write a minimal config at `/etc/semantos/node.toml`:

```toml
nodeCert = "smoke-test-node"

[storage]
type = "memory"

[identity]
type = "local"

[anchor]
type = "stub"

[network]
type = "stub"

extensions = []

[license]
path           = "/etc/semantos/node.license"
privateKeyPath = "/etc/semantos/node.privkey"
devMode        = true   # accept the dev-issuer signature

[public]
hostname    = "your-host-or-ip-here"
wssPort     = 8443
bindAddress = "::"      # listen on all IPv6 interfaces
```

Set `SEMANTOS_DEV_MODE=1` (belt and braces — `devMode = true` already
unlocks dev-issuer licenses, env is the override path):

```bash
export SEMANTOS_DEV_MODE=1
```

Boot:

```bash
bun run runtime/node/src/daemon.ts --config /etc/semantos/node.toml &
```

Expected output includes:

```
[semantos] License accepted (dev-issuer)
[semantos] Federation listening on port 8443 as 2602:f9f8::abcd
[semantos] Node running
  Federation: ws://0.0.0.0:8443/session
  Discovery:  /.well-known/semantos-node
```

That `2602:f9f8::abcd` is your **BCA** (logical identity). The
`8443` is your **wssPort** (where peers actually dial). They're
deliberately decoupled — see the PRD reachability note.

Verify the discovery endpoint:

```bash
curl http://localhost:8443/.well-known/semantos-node | jq
```

```json
{
  "bca":           "2602:f9f8::abcd",
  "pubkeyHex":     "020c62af...",
  "licenseCertId": "sha256:00dc485924...",
  "version":       "0.1.0",
  "advertised":    { "hostname": "your-host-or-ip-here", "port": 8443 },
  "adapters":      { "storage": "memory", "identity": "local", "anchor": "stub", "network": "ws-node" }
}
```

If you can `curl` the same URL from a different machine using your
public IPv6, **box A is reachable.** That's already most of the work.

Now do the same on box B.

---

## Step 3 — Cross-register endpoints in config

Stop both daemons. Edit each config to add the OTHER box's
`{ bca, wssUrl }` to `locator.bootstrap_peers`:

**On box A**, add:

```toml
[[locator.bootstrap_peers]]
bca           = "2602:f9f8::<bob-bca-suffix>"
wssUrl        = "ws://[2a01:bob-real-ipv6]:8443/session"
licenseCertId = "sha256:<bob-cert-id>"   # optional pinning
pubkeyHex     = "02bb..."                # optional pinning
```

**On box B**, add the matching entry pointing at A.

**Why optional pinning matters:** without `licenseCertId` / `pubkeyHex`,
a malicious DNS or routing change could substitute a different node at
the same `wssUrl`. With them, the dialer rejects any handshake whose
advertised identity doesn't match. For a closed-trust smoke test (you
control both boxes, you read each other's `/.well-known` over a
trusted channel) the bare entry is fine. For anything beyond that,
pin both fields.

Restart both daemons.

---

## Step 4 — The actual smoke test

The node binary doesn't currently expose a CLI verb for "publish on
behalf of this node and watch for a callback" — that's an interactive
session-protocol consumer concern (poker, voice, etc.). For the smoke
test, the cleanest proof is the federation gate test pointed at a
running pair of nodes.

Write a tiny script on box A (`smoke.ts`):

```ts
// smoke.ts
import { WsNodeAdapter } from "@semantos/ws-node-adapter";
import { BsvSdkSigner, BsvSdkVerifier } from "@semantos/session-protocol";
import { StaticPeerLocator } from "@semantos/peer-locator";
import { decodeLicense } from "@semantos/protocol-types/license";
import { PrivateKey } from "@bsv/sdk";
import { readFile } from "node:fs/promises";

const PEER_BCA    = "2602:f9f8::<bob-bca-suffix>";
const PEER_WSSURL = "ws://[2a01:bob-real-ipv6]:8443/session";

const license   = decodeLicense(new Uint8Array(await readFile("/etc/semantos/node.license")));
const privKey   = PrivateKey.fromHex((await readFile("/etc/semantos/node.privkey", "utf8")).trim());
const deriveBca = (pk: Uint8Array) =>
  `2602:f9f8::${Array.from(pk.slice(-2)).map(b => b.toString(16).padStart(2,"0")).join("")}`;

const signer = new BsvSdkSigner(privKey, async pk => deriveBca(pk));
const adapter = new WsNodeAdapter({
  identity: { identity: () => signer.identity(), sign: b => signer.sign(b),
              deriveBCA: async () => (await signer.identity()).bca },
  license,
  locator: new StaticPeerLocator({ endpoints: [{ bca: PEER_BCA, wssUrl: PEER_WSSURL }] }),
  verifier: new BsvSdkVerifier(),
  deriveBcaFromPubkey: async pk => deriveBca(pk),
  serverPort: 0,
  serverHost: "127.0.0.1",
});

await adapter.start();
console.log("dialer adapter on", adapter.listeningPort, "as", adapter.getNodeBCA());

const conn = await adapter.connect(PEER_BCA);
console.log("authenticated peer:", conn.peerBca);

await adapter.publish(
  { cellBytes: new Uint8Array(64).fill(0xa5),
    semanticPath: "smoke", contentHash: "a".repeat(64),
    ownerCert: "smoke", typeHash: "b".repeat(64) },
  { topic: "smoke-topic" },
);
console.log("published — check the other side");
await adapter.stop();
```

On box B, before running A's script, set up a subscriber:

```bash
# Optional: run a subscriber on box B that prints incoming events.
# Easiest path is to do it inside the smoke script symmetrically — give
# box B a copy of smoke.ts that subscribes instead of publishes.
```

Run on A:

```bash
bun run smoke.ts
```

Expected: `authenticated peer: 2602:f9f8::<bob-bca-suffix>` and
`published — check the other side`. On box B's subscriber: callback
fires within ~50–200ms (roundtrip dominated by network RTT).

That's the BCAv6 smoke test passing.

---

## Debugging checklist

| Symptom | Likely cause | Fix |
|---|---|---|
| `connect: no endpoint for ...` | The peer's BCA isn't in `bootstrap_peers` (or you mistyped it) | Re-verify against the peer's `/.well-known/semantos-node` output |
| Hangs at `connect()` | Inbound port not actually reachable from the dialer | `nc -zv [peer-ipv6] 8443` from the dialer; if that fails, your firewall / cloud security group blocks it |
| `connection closed: handshake-license-expired` | Clock skew between boxes | `timedatectl` on both — federation is more sensitive to wall-clock divergence than HTTP |
| `connection closed: handshake-bca-mismatch` | The peer's `claimedBca` doesn't match what your `deriveBcaFromPubkey` produces. Most commonly: someone changed the stub format on one side | Both boxes must run the same commit; re-pull main on the lagging box |
| `connection closed: handshake-issuer-rejected` | Your peer accepts only Plexus-issued licenses; you sent a dev-issued one | Set `SEMANTOS_DEV_MODE=1` on the peer, or make sure the peer's config has `license.devMode = true` |
| `FATAL: license rejected (dev-issuer-rejected)` at boot | You set `license.devMode = false` (explicit override beats env var) | Either remove the explicit `false` or mint a non-dev license once a real issuer exists |
| `private key does not match license holder pubkey` | Wrong `node.privkey` path; not the one paired with `node.license` | Re-mint with `--generate` and paste the new files in place |
| `cannot read private key at "..."` | Wrong path or permission denied | `ls -l /etc/semantos/node.privkey` — file must exist and be readable by the user running the daemon |
| `must be 64 hex chars` | Privkey file has whitespace, leading `0x`, or extra newlines | Re-mint; the writer trims on output but external editing can mangle it |
| `Wrong handshake reply: malformed-frame` | One side is on a different commit and the wire format diverged, OR a non-Semantos client tried to dial `/session` | Pin both boxes to the same commit; restrict inbound to known peers if you're public |

---

## What this does and doesn't prove

**Proves:**

- Two nodes on different networks can complete the licensed handshake
  and exchange envelopes
- TLS-less `ws://` is enough for an authenticated proof — the
  license-handshake is independent of transport secrecy
- The wire format survives real-world network conditions (path MTU,
  IPv6 routing, idle NAT entries)
- `/.well-known/semantos-node` is reachable + advertises the right
  identity

**Doesn't prove:**

- TLS provisioning works (`wss://` with real certs is operationally
  separate; tests cover the protocol, not the cert flow)
- Anything about media (voice / video / streams — that's 35B.2)
- Anything about pay-gating (35B.3)
- NAT traversal between two firewalled peers (deferred to 35C)
- Long-running stability — auto-reconnect + heartbeat are 35B.2

---

## What to do once it works

1. Pin a commit hash on both boxes so you can rerun the same setup
   later without surprises.
2. If you want TLS for real: front the WsNodeAdapter port with Caddy
   (auto Let's Encrypt) or Cloudflare Tunnel (terminates TLS at edge,
   forwards to your `:8443`).
3. Enable optional pinning (`licenseCertId` + `pubkeyHex` in
   `bootstrap_peers`) so a peer's identity can't be silently
   substituted at the network layer.
4. File any rough edges as 35B.1d issues against the repo so the next
   pair of boxes has a smoother time.

---

## Related

- [PRD: Phase 35B Node-as-a-Service](../prd/PHASE-35B-NODE-AS-SERVICE.md)
- [`@semantos/ws-node-adapter` README](../../runtime/ws-node-adapter/README.md)
- [`@semantos/peer-locator` README](../../runtime/peer-locator/README.md)
- [`tests/gates/phase35b-gate.test.ts`](../../tests/gates/phase35b-gate.test.ts) — the gate suite this smoke test exercises in production form
