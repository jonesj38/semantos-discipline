---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/semantos/lib/src/dispatch/payload_canonical.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.117224+00:00
---

# apps/semantos/lib/src/dispatch/payload_canonical.dart

```dart
// C7-B Option A — byte-exact Dart port of the brain's
// `canonicaliseCellPayload` (runtime/semantos-brain/src/attachments_upload_http.zig
// :520 `canonicaliseCellPayload` + `:527 writeCanonical` + `:744 writeJsonString`).
//
// The sovereign-mint signature is computed over `sha256(canonical_bytes)`
// where `canonical_bytes` is this function's output. The brain verifies by
// re-deriving the SAME bytes from the payload it received and running its
// recovery-loop verifier (`verifyPayloadSignature`). So this port MUST agree
// byte-for-byte with the Zig canonicaliser, or every sovereign mint 401s.
//
// Canonical form:
//   - no whitespace
//   - object keys sorted by UTF-8 byte order (matches Zig std.mem.lessThan)
//   - strings JSON-escaped (matches Zig std.json.Stringify default options)
//   - integers/doubles rendered decimal; bool → true/false; null → null
//
// NOTE (parity scope): for the V1 release slice the payload is
// `{"rawText": "<plain text>"}` — a single ASCII string field, the simplest
// canonical case. Multi-key ordering + standard escaping are covered by the
// unit tests. A full cross-language parity fixture (Zig emits vectors, Dart
// asserts) is the belt-and-braces follow-up before non-ASCII / float payloads
// ride this path.

import 'dart:convert';
import 'dart:typed_data';

/// Canonical UTF-8 bytes for [value] — the preimage the operator signs.
Uint8List canonicaliseCellPayload(Object? value) {
  final buf = StringBuffer();
  _writeCanonical(buf, value);
  return Uint8List.fromList(utf8.encode(buf.toString()));
}

/// Canonical string form (debug/testing convenience).
String canonicalCellPayloadString(Object? value) {
  final buf = StringBuffer();
  _writeCanonical(buf, value);
  return buf.toString();
}

void _writeCanonical(StringBuffer out, Object? value) {
  if (value == null) {
    out.write('null');
  } else if (value is bool) {
    out.write(value ? 'true' : 'false');
  } else if (value is int) {
    out.write(value.toString());
  } else if (value is double) {
    // Zig renders floats with `{d}` (shortest round-trip). Dart's
    // double.toString() is also shortest round-trip; integral doubles
    // print as "N.0" in Dart but "N" via Zig {d}, so strip a trailing
    // ".0" to match. (Floats don't occur in the V1 slice payload.)
    var s = value.toString();
    if (s.endsWith('.0')) s = s.substring(0, s.length - 2);
    out.write(s);
  } else if (value is String) {
    // JSON-escaped quoted string — matches Zig writeJsonString
    // (std.json.Stringify of the string value).
    out.write(jsonEncode(value));
  } else if (value is List) {
    out.write('[');
    for (var i = 0; i < value.length; i++) {
      if (i != 0) out.write(',');
      _writeCanonical(out, value[i]);
    }
    out.write(']');
  } else if (value is Map) {
    final keys = value.keys.map((k) => k as String).toList();
    // Byte-lexicographic key order (UTF-8), matching Zig std.mem.lessThan.
    keys.sort((a, b) => _byteCompare(utf8.encode(a), utf8.encode(b)));
    out.write('{');
    for (var i = 0; i < keys.length; i++) {
      if (i != 0) out.write(',');
      out.write(jsonEncode(keys[i]));
      out.write(':');
      _writeCanonical(out, value[keys[i]]);
    }
    out.write('}');
  } else {
    throw ArgumentError(
        'canonicaliseCellPayload: uncanonicalisable value ${value.runtimeType}');
  }
}

int _byteCompare(List<int> a, List<int> b) {
  final n = a.length < b.length ? a.length : b.length;
  for (var i = 0; i < n; i++) {
    final d = a[i] - b[i];
    if (d != 0) return d;
  }
  return a.length - b.length;
}

```
