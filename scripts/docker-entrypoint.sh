#!/bin/bash
set -e

USER_ID="${USER_ID:-1000}"
GROUP_ID="${GROUP_ID:-1000}"

# Validate UID/GID: must be positive integers and not 0 (root).
if ! [[ "$USER_ID" =~ ^[0-9]+$ ]] || ! [[ "$GROUP_ID" =~ ^[0-9]+$ ]]; then
    echo "ERROR: USER_ID and GROUP_ID must be positive integers." >&2
    exit 1
fi
if [ "$USER_ID" -eq 0 ] || [ "$GROUP_ID" -eq 0 ]; then
    echo "ERROR: USER_ID and GROUP_ID must not be 0 (root). Set them in .env." >&2
    exit 1
fi

# Create group and user with the requested UID/GID.
# groupadd/useradd may fail if the ID already exists — that is fine.
groupadd -g "$GROUP_ID" claude 2>/dev/null || true
useradd -m -u "$USER_ID" -g "$GROUP_ID" -s /bin/bash claude 2>/dev/null || true

# Ensure home dirs are owned by claude before any volume seeding.
mkdir -p /home/claude/.claude /home/claude/.config/codeburn
chown -R claude:claude /home/claude

if [ -z "$WORKSPACE_PATH" ]; then
    echo "ERROR: WORKSPACE_PATH is not set. Add it to .env and restart." >&2
    exit 1
fi

# Reject obviously dangerous workspace paths.
case "$WORKSPACE_PATH" in
    /|/etc*|/proc*|/sys*|/var/run*|/dev*)
        echo "ERROR: WORKSPACE_PATH '$WORKSPACE_PATH' points to a sensitive system path." >&2
        exit 1
        ;;
esac

# Seed ~/.claude from image defaults on fresh volumes.
# Marker file .caveman-active confirms Caveman hook files are present.
# cp -rn (no-clobber) never overwrites existing user data.
if [ ! -f /home/claude/.claude/.caveman-active ]; then
    cp -rn /opt/claude-defaults/. /home/claude/.claude/
    chown -R claude:claude /home/claude/.claude
fi

# Drop to the claude user for all remaining work.
# The supervision loop and keepalive process both run as claude.
exec gosu claude bash -c '
    if ! tmux has-session -t claude 2>/dev/null; then
        tmux new-session -d -s claude -c /workspace
    fi

    (
        while true; do
            sleep 30
            if ! tmux has-session -t claude 2>/dev/null; then
                tmux new-session -d -s claude -c /workspace
            fi
        done
    ) &

    exec tail -f /dev/null
'
