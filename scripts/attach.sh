#!/bin/bash
set -euo pipefail

if ! docker info >/dev/null 2>&1; then
    echo "Error: Docker is not available (daemon down or permission denied)." >&2
    exit 1
fi

if ! docker ps --filter "name=^claude-code$" --filter "status=running" --format "{{.Names}}" | grep -q "^claude-code$"; then
    echo "Error: container 'claude-code' is not running." >&2
    echo "Start it with: docker compose up -d" >&2
    exit 1
fi

exec docker exec -it -u claude claude-code tmux attach-session -t claude
