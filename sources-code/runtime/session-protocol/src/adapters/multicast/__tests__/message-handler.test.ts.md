---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/adapters/multicast/__tests__/message-handler.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.070813+00:00
---

# runtime/session-protocol/src/adapters/multicast/__tests__/message-handler.test.ts

```ts
/**
 * message-handler unit tests — pure dispatch over wire bytes.
 */

import { describe, expect, test } from "bun:test";
import { createJsonCodec } from "../ports/codec-port";
import { handleIncoming } from "../message-handler";
import {
  HEADER_SIZE,
  MSG_CELL,
  MSG_CONTROL,
  MSG_HEARTBEAT,
  encodeHeader,
  framePacket,
} from "../wire-header";
import type { CellWireBody, ControlMessage, MulticastHeartbeat } from "../types";

const rinfo = { address: "fe80::peer", port: 5683, size: 0 };
const codec = createJsonCodec();
const ctx = (own = 0xffff) => ({ ownNodeIdShort: own, codec, now: 100 });

function packet(msgType: number, msgId: number, sender: number, body: unknown): Uint8Array {
  const payload = codec.encode(body);
  return framePacket(
    encodeHeader(msgType, msgId, sender, 1, payload.length),
    payload,
  );
}

describe("message-handler", () => {
  test("drops packets shorter than the header", () => {
    const eff = handleIncoming(new Uint8Array(5), rinfo, ctx());
    expect(eff).toEqual([{ kind: "drop", reason: "too-short" }]);
  });

  test("drops own-message echoes", () => {
    const hb: MulticastHeartbeat = {
      nodeIdShort: 0x1234,
      bca: "fe80::self",
      uptime: 1,
      peersKnown: 0,
      timestamp: 1,
    };
    const eff = handleIncoming(packet(MSG_HEARTBEAT, 1, 0x1234, hb), rinfo, ctx(0x1234));
    expect(eff[0]?.kind).toBe("drop");
  });

  test("drops bad-version headers", () => {
    const buf = new Uint8Array(HEADER_SIZE + 1);
    buf[0] = 0x99; // wrong version
    const eff = handleIncoming(buf, rinfo, ctx());
    expect(eff).toEqual([{ kind: "drop", reason: "bad-version" }]);
  });

  test("decodes a heartbeat into a peer-heartbeat effect", () => {
    const hb: MulticastHeartbeat = {
      nodeIdShort: 0x0007,
      bca: "fe80::peer",
      uptime: 250,
      peersKnown: 1,
      timestamp: 2,
    };
    const [eff] = handleIncoming(packet(MSG_HEARTBEAT, 1, 0x0007, hb), rinfo, ctx());
    expect(eff?.kind).toBe("peer-heartbeat");
    if (eff?.kind === "peer-heartbeat") {
      expect(eff.peer).toMatchObject({
        bca: "fe80::peer",
        nodeIdShort: 0x0007,
        address: "fe80::peer",
        lastSeen: 100,
        uptime: 250,
      });
    }
  });

  test("decodes a cell into a cell-received effect with a derived txid", () => {
    const wire: CellWireBody = {
      cellBytes: [1, 2, 3],
      semanticPath: "/x",
      contentHash: "ch",
      ownerCert: "o",
      typeHash: "T",
      topic: "tm_x",
    };
    const [eff] = handleIncoming(packet(MSG_CELL, 0x42, 0x0001, wire), rinfo, ctx());
    expect(eff?.kind).toBe("cell-received");
    if (eff?.kind === "cell-received") {
      expect(eff.topic).toBe("tm_x");
      expect(eff.result.semanticPath).toBe("/x");
      expect(eff.result.txid.startsWith("mc")).toBe(true);
      expect(eff.event.type).toBe("object_published");
    }
  });

  test("decodes a control message into a control-received effect", () => {
    const msg: ControlMessage = { type: "JOIN", from: 1, payload: { x: 1 } };
    const [eff] = handleIncoming(packet(MSG_CONTROL, 1, 0x0001, msg), rinfo, ctx());
    expect(eff?.kind).toBe("control-received");
    if (eff?.kind === "control-received") {
      expect(eff.msg).toEqual(msg);
      expect(eff.rinfo.address).toBe("fe80::peer");
    }
  });

  test("malformed body collapses to a drop effect", () => {
    const garbage = new Uint8Array([0x01, MSG_CELL, 0, 1, 0, 1, 0, 0, 0, 0, 0, 5, 1, 2, 3, 4, 5]);
    const eff = handleIncoming(garbage, rinfo, ctx());
    expect(eff).toEqual([{ kind: "drop", reason: "decode-error" }]);
  });
});

```
