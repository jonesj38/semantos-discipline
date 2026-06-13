---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/overlay/shard-frame.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.893389+00:00
---

# core/protocol-types/src/overlay/shard-frame.ts

```ts
/**
 * ShardFrame — BRC-12 UDP frame encoder/decoder for bitcoin-shard-proxy.
 *
 * Wire format (44-byte header + variable payload):
 *   Offset  0: 4 bytes — Network magic (0xE3E1F3E8, big-endian)
 *   Offset  4: 2 bytes — Protocol version (0x02BF = 703, big-endian)
 *   Offset  6: 1 byte  — Frame version (0x01)
 *   Offset  7: 1 byte  — Reserved (0x00)
 *   Offset  8: 32 bytes — Transaction ID (internal byte order, NOT display order)
 *   Offset 40: 4 bytes — Payload length (uint32, big-endian)
 *   Offset 44: variable — Serialized BSV transaction
 *
 * Must match the Go implementation in bitcoin-shard-proxy/frame/frame.go
 * byte-for-byte. All multi-byte integers are big-endian.
 *
 * Cross-references:
 *   github.com/lightwebinc/bitcoin-shard-proxy/frame/frame.go → Go Encode/Decode
 *   github.com/lightwebinc/bitcoin-shard-proxy/shard/shard.go → Go GroupIndex
 */

/** Network magic for BSV mainnet (used in shard proxy framing). */
export const SHARD_FRAME_MAGIC = 0xE3E1F3E8;

/** Protocol version (703 = 0x02BF). */
export const SHARD_FRAME_PROTOCOL = 0x02BF;

/** Frame format version. */
export const SHARD_FRAME_VERSION = 0x01;

/** Fixed header size in bytes. */
export const SHARD_FRAME_HEADER_SIZE = 44;

/** Maximum payload size (10 MiB). */
export const SHARD_MAX_PAYLOAD_SIZE = 10 * 1024 * 1024;

export class ShardFrame {
  /**
   * Encode a BSV transaction into a BRC-12 UDP frame.
   *
   * @param txid 32-byte transaction ID (internal byte order, NOT display order)
   * @param txPayload Serialized BSV transaction bytes
   * @returns Complete frame ready for UDP send
   */
  static encode(txid: Uint8Array, txPayload: Uint8Array): Uint8Array {
    if (txid.length !== 32) {
      throw new Error(`txid must be 32 bytes, got ${txid.length}`);
    }
    if (txPayload.length > SHARD_MAX_PAYLOAD_SIZE) {
      throw new Error(
        `Payload exceeds max size: ${txPayload.length} > ${SHARD_MAX_PAYLOAD_SIZE}`,
      );
    }

    const frame = new Uint8Array(SHARD_FRAME_HEADER_SIZE + txPayload.length);
    const dv = new DataView(frame.buffer);

    // All multi-byte integers are big-endian (matching Go binary.BigEndian)
    dv.setUint32(0, SHARD_FRAME_MAGIC, false);    // offset 0: magic (BE)
    dv.setUint16(4, SHARD_FRAME_PROTOCOL, false);  // offset 4: protocol (BE)
    frame[6] = SHARD_FRAME_VERSION;                 // offset 6: frame version
    frame[7] = 0x00;                                // offset 7: reserved

    frame.set(txid, 8);                             // offset 8: txid (32 bytes)

    dv.setUint32(40, txPayload.length, false);      // offset 40: payload length (BE)

    frame.set(txPayload, SHARD_FRAME_HEADER_SIZE);  // offset 44: payload

    return frame;
  }

  /**
   * Decode a BRC-12 frame received from the shard proxy.
   *
   * @returns null if magic/protocol/version mismatch or frame too small
   */
  static decode(frame: Uint8Array): {
    txid: Uint8Array;
    payload: Uint8Array;
  } | null {
    if (frame.length < SHARD_FRAME_HEADER_SIZE) return null;

    const dv = new DataView(frame.buffer, frame.byteOffset, frame.byteLength);

    // Validate magic (big-endian)
    if (dv.getUint32(0, false) !== SHARD_FRAME_MAGIC) return null;

    // Validate frame version
    if (frame[6] !== SHARD_FRAME_VERSION) return null;

    // Read payload length (big-endian)
    const payloadLength = dv.getUint32(40, false);
    if (payloadLength > SHARD_MAX_PAYLOAD_SIZE) return null;

    // Verify frame contains enough bytes for the declared payload
    if (frame.length < SHARD_FRAME_HEADER_SIZE + payloadLength) return null;

    return {
      txid: frame.slice(8, 40),
      payload: frame.slice(
        SHARD_FRAME_HEADER_SIZE,
        SHARD_FRAME_HEADER_SIZE + payloadLength,
      ),
    };
  }

  /**
   * Compute which shard group a transaction will land in.
   *
   * Matches the Go implementation:
   *   prefix32 := binary.BigEndian.Uint32(txid[0:4])
   *   return (prefix32 >> (32 - shardBits)) & mask
   *
   * @param txid 32-byte transaction ID
   * @param shardBits Number of bits (1–24)
   * @returns Group index (0 to 2^shardBits - 1)
   */
  static shardIndex(txid: Uint8Array, shardBits: number): number {
    if (shardBits < 1 || shardBits > 24) {
      throw new Error(`shardBits must be 1–24, got ${shardBits}`);
    }

    // Read first 4 bytes as big-endian uint32 (matching Go binary.BigEndian.Uint32)
    const prefix32 =
      (txid[0] << 24) |
      (txid[1] << 16) |
      (txid[2] << 8) |
      txid[3];

    // Unsigned right shift to get top N bits, then mask
    const mask = (1 << shardBits) - 1;
    return ((prefix32 >>> (32 - shardBits)) & mask);
  }

  /**
   * Derive the IPv6 multicast address for a shard group.
   *
   * IPv6 multicast format: FF<scope><flags>::<base><groupIndex>
   * The group index occupies the low 3 bytes of the 16-byte address.
   *
   * @param groupIndex Shard group index
   * @param scope Multicast scope (0x02=link, 0x05=site, 0x08=org, 0x0E=global)
   * @param baseAddr Base bytes for the multicast address (typically 14 zero bytes)
   * @returns 16-byte IPv6 address
   */
  static multicastAddr(
    groupIndex: number,
    scope: number,
    baseAddr: Uint8Array,
  ): Uint8Array {
    const addr = new Uint8Array(16);
    addr[0] = 0xFF;
    addr[1] = scope;

    // Copy base address bytes (up to 10 bytes starting at offset 2)
    const baseLen = Math.min(baseAddr.length, 10);
    addr.set(baseAddr.subarray(0, baseLen), 2);

    // Group index in last 4 bytes (big-endian)
    addr[12] = (groupIndex >>> 24) & 0xFF;
    addr[13] = (groupIndex >>> 16) & 0xFF;
    addr[14] = (groupIndex >>> 8) & 0xFF;
    addr[15] = groupIndex & 0xFF;

    return addr;
  }
}

```
