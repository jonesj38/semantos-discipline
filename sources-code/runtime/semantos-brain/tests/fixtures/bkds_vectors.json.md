---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/tests/fixtures/bkds_vectors.json
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.271442+00:00
---

# runtime/semantos-brain/tests/fixtures/bkds_vectors.json

```json
{
  "schema_version": 2,
  "source": "bsvz BRC-42 invoice-with-counterparty (PrivateKey.deriveChild + .publicKey().toCompressedSec1)",
  "algorithm": {
    "name": "BRC-42 BKDS — invoice-with-counterparty + secp256k1 scalar tweak",
    "reference": "https://brc.dev/42",
    "invoice_format": "\"BKDS-BRC42-v1\" || u8(context_tag) || u32_be(label.len) || label",
    "derivation": "shared := root_priv.deriveSharedSecret(device_pub); tweak := HMAC-SHA-256(invoice, key=compressed_sec1(shared)); child_priv := scalar_add_mod_n(root_priv, tweak); child_pub := basepoint * child_priv",
    "output_encoding": "compressed SEC1 (33 bytes hex)"
  },
  "vectors": [
    {
      "name": "basic-carpenter",
      "root_seed": "operator-root-todd-2026",
      "root_priv_hex": "6f202d4de1047432675db4e1cb0adbd81d9cc26a9af0ee4b40e5f94de2cc5930",
      "root_pub_hex": "02394956ed5eb4563b4e6d9bc307a309532a830d6c1c150f785ea993e2f638658a",
      "device_seed": "device-iphone-2026",
      "device_priv_hex": "a2cf45daf30bea84df0531dc73bc899a036e6e2790709edce7834de1c1856142",
      "device_pub_hex": "035bae11ced4bf213961858ac008fad8694c51665b93b3937f8ab9d52f24c499b5",
      "context_tag": 16,
      "label": "phone",
      "child_pub_hex": "03078347a607125dca6a33e971c93e4731ec4c6293f0d83d6382c0f4893386c6a7"
    },
    {
      "name": "ctx-musician",
      "root_seed": "operator-root-todd-2026",
      "root_priv_hex": "6f202d4de1047432675db4e1cb0adbd81d9cc26a9af0ee4b40e5f94de2cc5930",
      "root_pub_hex": "02394956ed5eb4563b4e6d9bc307a309532a830d6c1c150f785ea993e2f638658a",
      "device_seed": "device-iphone-2026",
      "device_priv_hex": "a2cf45daf30bea84df0531dc73bc899a036e6e2790709edce7834de1c1856142",
      "device_pub_hex": "035bae11ced4bf213961858ac008fad8694c51665b93b3937f8ab9d52f24c499b5",
      "context_tag": 17,
      "label": "phone",
      "child_pub_hex": "0222b27453ddbea914870323ab2d4caccf75177f358e19a0c3ab21208857c3aa4d"
    },
    {
      "name": "counterparty-laptop",
      "root_seed": "operator-root-todd-2026",
      "root_priv_hex": "6f202d4de1047432675db4e1cb0adbd81d9cc26a9af0ee4b40e5f94de2cc5930",
      "root_pub_hex": "02394956ed5eb4563b4e6d9bc307a309532a830d6c1c150f785ea993e2f638658a",
      "device_seed": "device-laptop-2026",
      "device_priv_hex": "6103d51993ea822a8f17331ced74e4c455fb8eadb604fe233965392240ae27b8",
      "device_pub_hex": "0274d43b831d3f9e02ee3c3453bacdbe34ee14cde1b7b4e0981f16306e562d1fe7",
      "context_tag": 16,
      "label": "phone",
      "child_pub_hex": "0269cb9497d502c56bd2e3e89a77a4bd12c54d89e407218c9747d307d813159483"
    },
    {
      "name": "parent-alice",
      "root_seed": "operator-root-alice-2026",
      "root_priv_hex": "bdc9540e7dc4f168d74ff98eb47f0f702fb0c83f78dc1c38f202860b469c748a",
      "root_pub_hex": "03599c0699a96de216dbbff935abb3ca301ed93051c7106f09afdd99d1e0cda699",
      "device_seed": "device-iphone-2026",
      "device_priv_hex": "a2cf45daf30bea84df0531dc73bc899a036e6e2790709edce7834de1c1856142",
      "device_pub_hex": "035bae11ced4bf213961858ac008fad8694c51665b93b3937f8ab9d52f24c499b5",
      "context_tag": 16,
      "label": "phone",
      "child_pub_hex": "0338b2928f5f4bd72859f425f6f6fa386f7b8163aa660111429d1c4ac183827c4c"
    },
    {
      "name": "edge-empty-label",
      "root_seed": "operator-root-todd-2026",
      "root_priv_hex": "6f202d4de1047432675db4e1cb0adbd81d9cc26a9af0ee4b40e5f94de2cc5930",
      "root_pub_hex": "02394956ed5eb4563b4e6d9bc307a309532a830d6c1c150f785ea993e2f638658a",
      "device_seed": "device-iphone-2026",
      "device_priv_hex": "a2cf45daf30bea84df0531dc73bc899a036e6e2790709edce7834de1c1856142",
      "device_pub_hex": "035bae11ced4bf213961858ac008fad8694c51665b93b3937f8ab9d52f24c499b5",
      "context_tag": 16,
      "label": "",
      "child_pub_hex": "0205f7be55f0849abca123756fe358d914de8add5a2645a28e2b7b26c66fee75f7"
    },
    {
      "name": "edge-max-label",
      "root_seed": "operator-root-todd-2026",
      "root_priv_hex": "6f202d4de1047432675db4e1cb0adbd81d9cc26a9af0ee4b40e5f94de2cc5930",
      "root_pub_hex": "02394956ed5eb4563b4e6d9bc307a309532a830d6c1c150f785ea993e2f638658a",
      "device_seed": "device-iphone-2026",
      "device_priv_hex": "a2cf45daf30bea84df0531dc73bc899a036e6e2790709edce7834de1c1856142",
      "device_pub_hex": "035bae11ced4bf213961858ac008fad8694c51665b93b3937f8ab9d52f24c499b5",
      "context_tag": 16,
      "label": "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx",
      "child_pub_hex": "03d30168e861920e7af3634de8bff253d8195df5d117021ed2b8797ff288aeb78d"
    },
    {
      "name": "ctx-zero",
      "root_seed": "operator-root-todd-2026",
      "root_priv_hex": "6f202d4de1047432675db4e1cb0adbd81d9cc26a9af0ee4b40e5f94de2cc5930",
      "root_pub_hex": "02394956ed5eb4563b4e6d9bc307a309532a830d6c1c150f785ea993e2f638658a",
      "device_seed": "device-iphone-2026",
      "device_priv_hex": "a2cf45daf30bea84df0531dc73bc899a036e6e2790709edce7834de1c1856142",
      "device_pub_hex": "035bae11ced4bf213961858ac008fad8694c51665b93b3937f8ab9d52f24c499b5",
      "context_tag": 0,
      "label": "default",
      "child_pub_hex": "02be590744625b5103a45d8d8c65470efc78a8b3a2ee44ea1a6f1950a063b1b22c"
    },
    {
      "name": "ctx-ff",
      "root_seed": "operator-root-todd-2026",
      "root_priv_hex": "6f202d4de1047432675db4e1cb0adbd81d9cc26a9af0ee4b40e5f94de2cc5930",
      "root_pub_hex": "02394956ed5eb4563b4e6d9bc307a309532a830d6c1c150f785ea993e2f638658a",
      "device_seed": "device-iphone-2026",
      "device_priv_hex": "a2cf45daf30bea84df0531dc73bc899a036e6e2790709edce7834de1c1856142",
      "device_pub_hex": "035bae11ced4bf213961858ac008fad8694c51665b93b3937f8ab9d52f24c499b5",
      "context_tag": 255,
      "label": "default",
      "child_pub_hex": "03dc7231ecb82193cd93a7a5661a20b46ff8f95e4f20a037135811382edb21f123"
    },
    {
      "name": "sovereign-tag",
      "root_seed": "operator-root-bob-2026",
      "root_priv_hex": "4ed6ead3f3063e7b27f608fe6245135c30bf8c54f972697b957c12efc99ebb8c",
      "root_pub_hex": "0377ff04833bbd1baae6ea1bfff7d49147adae37d15d1bbae6651e67a73e05c8a0",
      "device_seed": "device-bob-mac-2026",
      "device_priv_hex": "f345a0b759aa11f1084b48c0a72593dea86457a593962c6213914a87e3a33dff",
      "device_pub_hex": "028b291757ddc06afbfd4f157cd106e8d9618d5f671bee75dde7dd4ecf9391df32",
      "context_tag": 66,
      "label": "studio-mac",
      "child_pub_hex": "03e14656d423c279cec17433d6c405809b92191a74013e2b8103f942bccbf95c0d"
    },
    {
      "name": "deterministic-rerun",
      "root_seed": "operator-root-todd-2026",
      "root_priv_hex": "6f202d4de1047432675db4e1cb0adbd81d9cc26a9af0ee4b40e5f94de2cc5930",
      "root_pub_hex": "02394956ed5eb4563b4e6d9bc307a309532a830d6c1c150f785ea993e2f638658a",
      "device_seed": "device-iphone-2026",
      "device_priv_hex": "a2cf45daf30bea84df0531dc73bc899a036e6e2790709edce7834de1c1856142",
      "device_pub_hex": "035bae11ced4bf213961858ac008fad8694c51665b93b3937f8ab9d52f24c499b5",
      "context_tag": 16,
      "label": "phone",
      "child_pub_hex": "03078347a607125dca6a33e971c93e4731ec4c6293f0d83d6382c0f4893386c6a7"
    }
  ]
}

```
