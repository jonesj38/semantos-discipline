---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-engine/src/bca.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.981535+00:00
---

# core/cell-engine/src/bca.zig

```zig
// BCA (Bitcoin-Certified Address) derivation and verification — Phase 2
//
// Implements the simplified Semantos BCA algorithm:
//   data = modifier(16B) || subnetPrefix(8B) || collisionCount(1B) || pubkey(33B)
//   Hash1 = SHA256(data)  [58 bytes in, 32 bytes out]
//   interfaceIdentifier = Hash1[0..8]
//   Clear u-bit (bit 1 from LSB) and g-bit (bit 0 from LSB) of byte 0
//   Encode sec in 3 MSBs (bits 5-7 from LSB) of byte 0
//   BCA = subnetPrefix(8B) || interfaceIdentifier(8B) = 16 bytes
//
// Collision count maxes at sec value (sec=0 → no retry, sec=1 → 1 retry, sec=2 → 2 retries).

const std = @import("std");
const host = @import("host");
const constants = @import("constants");

pub const BCA_DATA_SIZE = 58; // modifier(16) + prefix(8) + cc(1) + pubkey(33)

pub const BCAInput = struct {
    pubkey: [33]u8,
    subnet_prefix: [8]u8,
    modifier: [16]u8,
    sec: u8,
};

pub const BCAOutput = struct {
    address: [16]u8,
    collision_count: u8,
};

pub const BCAError = error{
    invalid_sec_parameter,
};

/// Derive a BCA (IPv6 address) from a public key and network parameters.
/// Returns the 16-byte address and the collision count used.
///
/// NOTE (E-P2.1): collision_count is always 0. The simplified Semantos BCA
/// algorithm has no collision oracle — derivation always succeeds on the first
/// hash. The sec parameter only affects bit encoding in the interface identifier.
/// If on-chain collision detection is needed (full paper algorithm), add an
/// optional collision oracle callback.
pub fn deriveBCA(input: *const BCAInput) BCAError!BCAOutput {
    if (input.sec > constants.BCA_COLLISION_COUNT_MAX) return error.invalid_sec_parameter;

    const iid = computeInterfaceId(input, 0);

    var address: [16]u8 = undefined;
    @memcpy(address[0..8], &input.subnet_prefix);
    @memcpy(address[8..16], &iid);

    return .{ .address = address, .collision_count = 0 };
}

/// Verify that a 16-byte BCA address was derived from the given public key and parameters.
/// Tries collision counts 0, 1, 2 (at most 3 hash evaluations).
pub fn verifyBCA(address: *const [16]u8, input: *const BCAInput) bool {
    const target_iid = address[8..16];
    // Extract sec from the address's interface identifier (3 MSBs of byte 0)
    const sec: u8 = (target_iid[0] >> 5) & 0x07;

    var cc: u8 = 0;
    while (cc <= constants.BCA_COLLISION_COUNT_MAX) : (cc += 1) {
        var candidate = computeInterfaceId(input, cc);
        // Encode the sec from the address (not from input) to match
        candidate[0] = (candidate[0] & 0x1F) | (sec << 5);

        if (std.mem.eql(u8, &candidate, target_iid)) return true;
    }

    return false;
}

/// Compute the interface identifier for a given collision count.
/// Shared by deriveBCA and verifyBCA.
fn computeInterfaceId(input: *const BCAInput, cc: u8) [8]u8 {
    // Concatenate: modifier(16) || subnetPrefix(8) || collisionCount(1) || pubkey(33) = 58 bytes
    var data: [BCA_DATA_SIZE]u8 = undefined;
    @memcpy(data[0..16], &input.modifier);
    @memcpy(data[16..24], &input.subnet_prefix);
    data[24] = cc;
    @memcpy(data[25..58], &input.pubkey);

    var hash_out: [32]u8 = undefined;
    host.sha256(&data, &hash_out);

    // interfaceIdentifier = first 8 bytes of hash
    var iid: [8]u8 = hash_out[0..8].*;

    // RFC 4291 bit manipulation on byte 0:
    // u-bit = bit 6 from MSB (= bit 1 from LSB, mask 0x02) → clear
    // g-bit = bit 7 from MSB (= bit 0 from LSB, mask 0x01) → clear
    iid[0] &= ~@as(u8, 0x03);

    // Encode sec in 3 MSBs (bits 0-2 from MSB = bits 5-7 from LSB)
    iid[0] = (iid[0] & 0x1F) | (@as(u8, input.sec) << 5);

    return iid;
}

```
