---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docker-compose.hackathon.yml
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.310693+00:00
---

# docker-compose.hackathon.yml

```yml
# Docker Compose — Semantos 25-node Poker Swarm
#
# Phase H1: Hackathon mesh using IPv6 UDP multicast.
# Each container is a Semantos node with a deterministic persona.
#
# Usage:
#   docker compose -f docker-compose.hackathon.yml up -d
#   docker compose -f docker-compose.hackathon.yml logs -f bot-0
#   docker compose -f docker-compose.hackathon.yml down
#
# Cross-references:
#   entrypoint.docker-swarm.ts — bot entrypoint
#   bot-personas.ts — persona definitions (cycling mod 4)
#   Dockerfile — multi-stage build

x-bot-defaults: &bot-defaults
  build:
    context: .
    dockerfile: Dockerfile
  entrypoint: ["bun", "run", "packages/node/src/entrypoint.docker-swarm.ts"]
  networks:
    - semantos-swarm
  restart: unless-stopped
  healthcheck:
    test: ["CMD", "bun", "run", "packages/node/src/health-check-heartbeat.ts"]
    interval: 15s
    timeout: 5s
    start_period: 10s
    retries: 3

x-bot-env: &bot-env
  SEMANTOS_DATA_DIR: /var/semantos/data
  HEARTBEAT_FILE: /tmp/semantos-heartbeat

services:
  bot-0:
    <<: *bot-defaults
    container_name: semantos-bot-0
    environment:
      <<: *bot-env
      BOT_INDEX: "0"
      BOT_PERSONA: nit

  bot-1:
    <<: *bot-defaults
    container_name: semantos-bot-1
    environment:
      <<: *bot-env
      BOT_INDEX: "1"
      BOT_PERSONA: maniac

  bot-2:
    <<: *bot-defaults
    container_name: semantos-bot-2
    environment:
      <<: *bot-env
      BOT_INDEX: "2"
      BOT_PERSONA: calculator

  bot-3:
    <<: *bot-defaults
    container_name: semantos-bot-3
    environment:
      <<: *bot-env
      BOT_INDEX: "3"
      BOT_PERSONA: apex

  bot-4:
    <<: *bot-defaults
    container_name: semantos-bot-4
    environment:
      <<: *bot-env
      BOT_INDEX: "4"
      BOT_PERSONA: nit

  bot-5:
    <<: *bot-defaults
    container_name: semantos-bot-5
    environment:
      <<: *bot-env
      BOT_INDEX: "5"
      BOT_PERSONA: maniac

  bot-6:
    <<: *bot-defaults
    container_name: semantos-bot-6
    environment:
      <<: *bot-env
      BOT_INDEX: "6"
      BOT_PERSONA: calculator

  bot-7:
    <<: *bot-defaults
    container_name: semantos-bot-7
    environment:
      <<: *bot-env
      BOT_INDEX: "7"
      BOT_PERSONA: apex

  bot-8:
    <<: *bot-defaults
    container_name: semantos-bot-8
    environment:
      <<: *bot-env
      BOT_INDEX: "8"
      BOT_PERSONA: nit

  bot-9:
    <<: *bot-defaults
    container_name: semantos-bot-9
    environment:
      <<: *bot-env
      BOT_INDEX: "9"
      BOT_PERSONA: maniac

  bot-10:
    <<: *bot-defaults
    container_name: semantos-bot-10
    environment:
      <<: *bot-env
      BOT_INDEX: "10"
      BOT_PERSONA: calculator

  bot-11:
    <<: *bot-defaults
    container_name: semantos-bot-11
    environment:
      <<: *bot-env
      BOT_INDEX: "11"
      BOT_PERSONA: apex

  bot-12:
    <<: *bot-defaults
    container_name: semantos-bot-12
    environment:
      <<: *bot-env
      BOT_INDEX: "12"
      BOT_PERSONA: nit

  bot-13:
    <<: *bot-defaults
    container_name: semantos-bot-13
    environment:
      <<: *bot-env
      BOT_INDEX: "13"
      BOT_PERSONA: maniac

  bot-14:
    <<: *bot-defaults
    container_name: semantos-bot-14
    environment:
      <<: *bot-env
      BOT_INDEX: "14"
      BOT_PERSONA: calculator

  bot-15:
    <<: *bot-defaults
    container_name: semantos-bot-15
    environment:
      <<: *bot-env
      BOT_INDEX: "15"
      BOT_PERSONA: apex

  bot-16:
    <<: *bot-defaults
    container_name: semantos-bot-16
    environment:
      <<: *bot-env
      BOT_INDEX: "16"
      BOT_PERSONA: nit

  bot-17:
    <<: *bot-defaults
    container_name: semantos-bot-17
    environment:
      <<: *bot-env
      BOT_INDEX: "17"
      BOT_PERSONA: maniac

  bot-18:
    <<: *bot-defaults
    container_name: semantos-bot-18
    environment:
      <<: *bot-env
      BOT_INDEX: "18"
      BOT_PERSONA: calculator

  bot-19:
    <<: *bot-defaults
    container_name: semantos-bot-19
    environment:
      <<: *bot-env
      BOT_INDEX: "19"
      BOT_PERSONA: apex

  bot-20:
    <<: *bot-defaults
    container_name: semantos-bot-20
    environment:
      <<: *bot-env
      BOT_INDEX: "20"
      BOT_PERSONA: nit

  bot-21:
    <<: *bot-defaults
    container_name: semantos-bot-21
    environment:
      <<: *bot-env
      BOT_INDEX: "21"
      BOT_PERSONA: maniac

  bot-22:
    <<: *bot-defaults
    container_name: semantos-bot-22
    environment:
      <<: *bot-env
      BOT_INDEX: "22"
      BOT_PERSONA: calculator

  bot-23:
    <<: *bot-defaults
    container_name: semantos-bot-23
    environment:
      <<: *bot-env
      BOT_INDEX: "23"
      BOT_PERSONA: apex

  bot-24:
    <<: *bot-defaults
    container_name: semantos-bot-24
    environment:
      <<: *bot-env
      BOT_INDEX: "24"
      BOT_PERSONA: nit

networks:
  semantos-swarm:
    driver: bridge
    enable_ipv6: true
    ipam:
      config:
        - subnet: 172.20.0.0/16
        - subnet: "2602:f9f8::/64"

```
