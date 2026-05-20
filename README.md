# claude-code-env

A self-hosted Docker Compose environment for Claude Code. Runs on a home-lab VM and stays accessible from any LAN device via a single-command tmux attach — no third-party session management required.

Pre-installed: Claude Code, [Caveman](https://github.com/juliusbrussee/caveman), [Codeburn](https://github.com/getagentseal/codeburn).

---

## Prerequisites

- Docker Engine + Docker Compose v2 on the host VM
- SSH access to the host VM pre-configured
- A valid [Anthropic API key](https://console.anthropic.com)

---

## Setup

1. Clone the repo onto the host VM:
   ```sh
   git clone <repo-url> claude-code-env
   cd claude-code-env
   ```

2. Copy the example env file, fill in your values, and lock down permissions:
   ```sh
   cp .env.example .env
   # Edit .env: set ANTHROPIC_API_KEY, WORKSPACE_PATH, and optionally USER_ID/GROUP_ID
   # Run `id -u` and `id -g` on the host to find your UID/GID (default: 1000/1000)
   chmod 600 .env
   ```

3. Make the attach script executable:
   ```sh
   chmod +x scripts/attach.sh
   ```

4. Build and start the container:
   ```sh
   docker compose up -d
   ```

5. Attach to the session:
   ```sh
   ./scripts/attach.sh
   ```

   Detach at any time with `Ctrl-b d`. The session keeps running.

6. *(First time only)* Inside the container, authenticate Claude Code:
   ```sh
   claude
   ```
   Follow the prompts to complete API key setup.

7. *(Optional)* Install additional Claude Code plugins or skills from inside the session. They persist in the `~/.claude` volume across restarts.

---

## Daily Use

From any device SSH'd to the host:

```sh
./scripts/attach.sh
```

Multiple devices can attach to the same session simultaneously — you see the same terminal view on all of them. Detach with `Ctrl-b d`.

If the session exited (e.g. after a Claude Code crash), it is automatically recreated within 30 seconds. Just re-run `attach.sh`.

---

## Volume Backup

Named volumes `claude_data` and `codeburn_config` hold all persistent state. Back them up with:

```sh
docker run --rm \
  -v claude_data:/data \
  -v "$(pwd)":/backup \
  alpine tar czf /backup/claude_data.tar.gz -C /data .

docker run --rm \
  -v codeburn_config:/data \
  -v "$(pwd)":/backup \
  alpine tar czf /backup/codeburn_config.tar.gz -C /data .
```

## Volume Restore

```sh
docker run --rm \
  -v claude_data:/data \
  -v "$(pwd)":/backup \
  alpine tar xzf /backup/claude_data.tar.gz -C /data

docker run --rm \
  -v codeburn_config:/data \
  -v "$(pwd)":/backup \
  alpine tar xzf /backup/codeburn_config.tar.gz -C /data
```

---

## Host Migration

To move the environment to a new VM:

1. On the old host — back up both volumes (see above).
2. Copy the `.env` file to the new host (keep it secure; it contains your API key).
3. On the new host — clone the repo, restore both volume archives (see above).
4. Start the container:
   ```sh
   docker compose up -d
   ```
5. Attach and verify:
   ```sh
   ./scripts/attach.sh
   ```

All Claude Code settings, memory, Caveman configuration, and Codeburn data are restored. No manual reconfiguration needed.

---

## Environment Variables

| Variable | Required | Default | Description |
|---|---|---|---|
| `ANTHROPIC_API_KEY` | Yes | — | Anthropic API key for Claude Code |
| `WORKSPACE_PATH` | Yes | — | Absolute host path mounted as `/workspace` inside the container |
| `USER_ID` | No | `1000` | UID for the container user. Match your host UID (`id -u`) for correct file ownership on the workspace mount |
| `GROUP_ID` | No | `1000` | GID for the container user. Match your host GID (`id -g`) |

---

## Notes

- The container runs as a non-root user (`claude`) with the UID/GID you specify. Workspace files must be owned by that UID for write access inside the container.
- Caveman hook files are seeded from image defaults on fresh volumes and never overwrite existing user data.
- The `~/.cache/codeburn/` pricing cache is intentionally not persisted — it has a 24-hour TTL and rebuilds automatically.
- Docker group membership on the host grants implicit root-equivalent access to the host filesystem. Restrict it to trusted users.
