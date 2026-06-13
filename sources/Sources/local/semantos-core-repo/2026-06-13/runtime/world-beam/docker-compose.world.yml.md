---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/world-beam/docker-compose.world.yml
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.031708+00:00
---

# runtime/world-beam/docker-compose.world.yml

```yml
services:
  world:
    build:
      context: .
      dockerfile: Dockerfile.world
    image: semantos/world:latest
    container_name: semantos-world
    restart: unless-stopped
    # host network so the container shares 127.0.0.1 with the host —
    # required to reach nats-server which binds loopback only.
    # Ports 4000 (Phoenix) and 5178 (cell_relay) are bound directly on the host.
    network_mode: host
    volumes:
      - world-data:/data
    environment:
      PORT: "4000"
      PHX_HOST: "world.semantos.me"
      RELAY_PORT: "5178"
      RELAY_DATA_DIR: /data
      NATS_HOST: "127.0.0.1"
      NATS_PORT: "4222"
      NATS_ENABLED: "true"
      WAIT_FOR_SIDECAR: "false"
      VERIFIER_SIDECAR_URL: "none"
      MIX_ENV: prod
      RELEASE_COOKIE: "jam_world_cookie_change_me"
      # SECRET_KEY_BASE must be set in production — generate with:
      #   docker run --rm semantos/world:latest /app/bin/world eval "IO.puts(:crypto.strong_rand_bytes(64) |> Base.encode64)"
      SECRET_KEY_BASE: "REPLACE_WITH_64_BYTE_BASE64_SECRET"
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

volumes:
  world-data:
    driver: local

```
