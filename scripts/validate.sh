#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
COMPOSE_FILE="$PROJECT_DIR/compose.validation.yaml"

cleanup() {
  docker compose -f "$COMPOSE_FILE" down --volumes --remove-orphans >/dev/null 2>&1 || true
}

trap cleanup EXIT
cleanup

docker compose -f "$COMPOSE_FILE" build migrations
docker compose -f "$COMPOSE_FILE" up -d postgres
docker compose -f "$COMPOSE_FILE" run --rm migrations migrate
docker compose -f "$COMPOSE_FILE" run --rm migrations migrate
docker compose -f "$COMPOSE_FILE" run --rm migrations validate
docker compose -f "$COMPOSE_FILE" run --rm migrations info
