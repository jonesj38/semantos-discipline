---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/tests/gates/fixtures/propertyme-sample-responses.json
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.590067+00:00
---

# tests/gates/fixtures/propertyme-sample-responses.json

```json
[
  {
    "url": "https://api.propertyme.com/v2/properties",
    "statusCode": 200,
    "sampledAt": "2026-04-12T10:00:00Z",
    "body": {
      "data": {
        "properties": [
          {
            "id": "prop-001",
            "street_address": "123 Main St",
            "city": "Sydney",
            "state": "NSW",
            "zip": "2000",
            "country": "AU",
            "latitude": -33.8688,
            "longitude": 151.2093,
            "bedrooms": 3,
            "bathrooms": 2,
            "square_footage": 1800,
            "year_built": 1995,
            "property_type": "house",
            "owner_id": "owner-001",
            "updated_at": "2026-04-10T08:30:00Z"
          },
          {
            "id": "prop-002",
            "street_address": "456 Ocean Ave",
            "city": "Melbourne",
            "state": "VIC",
            "zip": "3000",
            "country": "AU",
            "latitude": -37.8136,
            "longitude": 144.9631,
            "bedrooms": 2,
            "bathrooms": 1,
            "square_footage": 1200,
            "property_type": "apartment",
            "owner_id": "owner-002",
            "updated_at": "2026-04-11T14:22:00Z"
          }
        ]
      },
      "next_cursor": "cursor_abc",
      "total_count": 42
    }
  },
  {
    "url": "https://api.propertyme.com/v2/properties",
    "statusCode": 200,
    "sampledAt": "2026-04-12T10:01:00Z",
    "body": {
      "data": {
        "properties": [
          {
            "id": "prop-003",
            "street_address": "789 Park Rd",
            "city": "Brisbane",
            "state": "QLD",
            "zip": "4000",
            "country": "AU",
            "bedrooms": 4,
            "bathrooms": 3,
            "square_footage": 2400,
            "year_built": 2010,
            "property_type": "house",
            "owner_id": "owner-001",
            "updated_at": "2026-04-09T19:00:00Z"
          }
        ]
      },
      "next_cursor": null,
      "total_count": 42
    }
  },
  {
    "url": "https://api.propertyme.com/v2/leases",
    "statusCode": 200,
    "sampledAt": "2026-04-12T10:02:00Z",
    "body": {
      "data": {
        "leases": [
          {
            "id": "lease-001",
            "tenant_id": "tenant-001",
            "property_id": "prop-001",
            "monthly_rent": 2500,
            "term_months": 12,
            "start_date": "2026-01-01",
            "end_date": "2026-12-31",
            "status": "active",
            "security_deposit": 5000,
            "updated_at": "2026-03-15T12:00:00Z"
          },
          {
            "id": "lease-002",
            "tenant_id": "tenant-002",
            "property_id": "prop-002",
            "monthly_rent": 1800,
            "term_months": 6,
            "start_date": "2026-03-01",
            "end_date": "2026-08-31",
            "status": "active",
            "updated_at": "2026-04-01T09:30:00Z"
          },
          {
            "id": "lease-003",
            "tenant_id": "tenant-001",
            "property_id": "prop-003",
            "monthly_rent": 3200,
            "term_months": 24,
            "start_date": "2025-06-01",
            "end_date": "2027-05-31",
            "status": "active",
            "security_deposit": 6400,
            "updated_at": "2026-02-28T16:45:00Z"
          }
        ]
      },
      "next_cursor": null,
      "total_count": 3
    }
  }
]

```
