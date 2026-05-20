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
addgroup -g "$GROUP_ID" claude 2>/dev/null || true
adduser -D -u "$USER_ID" -G claude -s /bin/bash claude 2>/dev/null || true

# Ensure home dirs are owned by claude before any volume seeding.
mkdir -p /home/claude/.claude /home/claude/.config/codeburn
chown -R "$USER_ID:$GROUP_ID" /home/claude

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
# settings.json presence means the volume was previously initialized — skip.
# cp -rn (no-clobber) never overwrites existing user data.
if [ ! -f /home/claude/.claude/settings.json ]; then
    cp -rn /opt/claude-defaults/. /home/claude/.claude/
    chown -R "$USER_ID:$GROUP_ID" /home/claude/.claude
fi

# Drop to the claude user for all remaining work.
# The supervision loop and keepalive process both run as claude.
# su-exec doesn't update HOME; set it explicitly so Claude Code resolves ~/.claude correctly.
export HOME=/home/claude USER=claude LOGNAME=claude
exec su-exec claude bash -c '
    if ! tmux has-session -t claude 2>/dev/null; then
        tmux new-session -d -s claude -c /workspace claude
    fi

    (
        while true; do
            sleep 30
            if ! tmux has-session -t claude 2>/dev/null; then
                tmux new-session -d -s claude -c /workspace claude
            fi
        done
    ) &

    exec tail -f /dev/null
'
