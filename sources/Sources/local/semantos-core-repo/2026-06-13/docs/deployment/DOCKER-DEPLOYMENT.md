---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/deployment/DOCKER-DEPLOYMENT.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.754315+00:00
---

# Docker Deployment Guide

Deploy a Semantos node using Docker Compose.

## Prerequisites

- Docker Engine 24.0+ (`docker --version`)
- Docker Compose v2+ (`docker compose version`)
- 2 GB RAM available for containers
- Open ports: 3000, 6443, 9000/udp

## Step 1: Clone the Repository

```bash
git clone https://github.com/todriguez/semantos-core.git
cd semantos-core
```

## Step 2: Create Node Configuration

```bash
# Create config file
cat > node.json <<'EOF'
{
  "nodeCert": "0x$(openssl rand -hex 16)",
  "storage": { "type": "node-fs", "root": "/var/semantos/data" },
  "identity": { "type": "stub" },
  "anchor": { "type": "stub", "interval": 600000 },
  "network": { "type": "stub" },
  "extensions": ["sovereignty", "trades"],
  "anchorIntervalMs": 600000,
  "dataDir": "/var/semantos/data"
}
EOF
```

## Step 3: Generate TLS Certificates

```bash
mkdir -p certs

# Generate CA
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
  -keyout certs/ca.key -out certs/ca.crt \
  -days 3650 -nodes -subj "/CN=Semantos CA"

# Generate node cert
openssl req -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
  -keyout certs/node.key -out certs/node.csr \
  -nodes -subj "/CN=Semantos Node"
openssl x509 -req -in certs/node.csr \
  -CA certs/ca.crt -CAkey certs/ca.key -CAcreateserial \
  -out certs/node.crt -days 365
rm certs/node.csr

# Generate client cert (for admin API access)
openssl req -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
  -keyout certs/client.key -out certs/client.csr \
  -nodes -subj "/CN=Semantos Admin"
openssl x509 -req -in certs/client.csr \
  -CA certs/ca.crt -CAkey certs/ca.key -CAcreateserial \
  -out certs/client.crt -days 365
rm certs/client.csr certs/ca.srl
```

## Step 4: Start Services

```bash
docker compose up -d
```

Expected output:
```
[+] Building 45.2s (15/15) FINISHED
[+] Running 3/3
 - Network semantos-core_default  Created
 - Container semantos-core-block-headers-1  Started
 - Container semantos-core-semantos-node-1  Started
```

## Step 5: Verify

```bash
# Check container health
docker compose ps

# Expected:
# NAME                    STATUS          PORTS
# semantos-node-1         Up (healthy)    0.0.0.0:3000->3000, 0.0.0.0:6443->6443
# block-headers-1         Up

# View logs
docker compose logs -f semantos-node

# Query admin API
curl --cert certs/client.crt \
     --key certs/client.key \
     --cacert certs/ca.crt \
     https://localhost:6443/api/node/status
```

## Environment Variables

Set in `.env` or pass via `docker compose`:

| Variable | Description | Default |
|----------|-------------|---------|
| `SEMANTOS_BYOK_KEY` | OpenRouter API key for LLM | (none) |
| `SEMANTOS_SUBNET_PREFIX` | IPv6 subnet prefix | (none) |
| `SEMANTOS_DEBUG_LOGGING` | Enable debug logs | `false` |

## Volume Management

Named volumes persist data across container restarts:

```bash
# List volumes
docker volume ls | grep semantos

# Inspect volume
docker volume inspect semantos-core_semantos-data

# Backup
docker run --rm -v semantos-core_semantos-data:/data \
  -v $(pwd):/backup alpine tar czf /backup/data-backup.tar.gz -C /data .

# Restore
docker run --rm -v semantos-core_semantos-data:/data \
  -v $(pwd):/backup alpine tar xzf /backup/data-backup.tar.gz -C /data
```

## Costs

Same as VPS deployment plus Docker overhead (~50MB RAM for the runtime).

## Stopping and Restarting

```bash
# Stop all services
docker compose down

# Restart
docker compose up -d

# Rebuild after code changes
docker compose up -d --build
```

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| Build fails | Missing deps | Run `docker compose build --no-cache` |
| Health check failing | Slow startup | Wait 30s, check logs |
| Port conflict | Port in use | Change port mapping in docker-compose.yml |
| Volume permission denied | UID mismatch | Ensure volume owned by uid 1000 |
| Container restarting | Config error | Check `docker compose logs semantos-node` |
