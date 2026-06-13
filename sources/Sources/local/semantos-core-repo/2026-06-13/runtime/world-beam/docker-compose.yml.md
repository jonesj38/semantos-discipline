---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/world-beam/docker-compose.yml
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.030769+00:00
---

# runtime/world-beam/docker-compose.yml

```yml
services:
  cell-relay:
    build:
      context: .
      dockerfile: Dockerfile
    image: semantos/cell-relay:latest
    container_name: cell-relay
    restart: unless-stopped
    ports:
      - "5178:5178"
    volumes:
      - relay-data:/data
    environment:
      RELAY_PORT: "5178"
      RELAY_DATA_DIR: /data
      RELEASE_COOKIE: "jam_relay_cookie_change_me"
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

volumes:
  relay-data:
    driver: local

```
