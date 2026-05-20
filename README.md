# claude-code-env

A self-hosted Docker Compose environment for Claude Code. Runs on a home-lab VM and stays accessible from any LAN device via a single-command tmux attach — no third-party session management required.

Pre-installed: Claude Code, [Caveman](https://github.com/juliusbrussee/caveman).

---

## Prerequisites

- Docker Engine + Docker Compose v2 on the host VM
- SSH access to the host VM pre-configured
- A [claude.ai](https://claude.ai) account (for interactive login) **or** an [Anthropic API key](https://console.anthropic.com)

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
   # Edit .env: set WORKSPACE_PATH, and optionally ANTHROPIC_API_KEY and USER_ID/GROUP_ID
   # Run `id -u` and `id -g` on the host to find your UID/GID (default: 1000/1000)
   chmod 600 .env
   ```

3. Make the attach script executable:
   ```sh
   chmod +x scripts/attach.sh
   ```

4. Start the container (pulls the image automatically on first run):
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
   /login
   ```
   Follow the prompts to complete authentication via claude.ai OAuth, or set `ANTHROPIC_API_KEY` in `.env` to skip interactive login.

7. *(Optional)* Install additional Claude Code plugins or skills from inside the session. They persist in the `~/.claude` bind mount across restarts.

---

## Daily Use

From any device SSH'd to the host:

```sh
./scripts/attach.sh
```

Multiple devices can attach to the same session simultaneously — you see the same terminal view on all of them. Detach with `Ctrl-b d`.

If the session exited (e.g. after a Claude Code crash), it is automatically recreated within 30 seconds. Just re-run `attach.sh`.

---

## Backup
`~/.claude` may contain sensitive auth/session data. Treat backups as secrets:
- store archives in restricted locations
- encrypt before transfer/storage (for example with age, gpg, or encrypted volumes)
- and avoid committing or sharing them in plain form

All persistent state lives in `~/.claude/` on the host (bind-mounted into the container). Back it up with any standard method:

```sh
tar czf claude-backup-$(date +%Y%m%d).tar.gz -C ~ .claude
```

## Restore

```sh
tar xzf claude-backup-<date>.tar.gz -C ~
```

---

## Host Migration

To move the environment to a new VM:

1. On the old host — back up `~/.claude/` (see above).
2. Copy the backup archive and your `.env` file to the new host (keep `.env` secure; it may contain your API key).
3. On the new host — clone the repo and restore the backup:
   ```sh
   tar xzf claude-backup-<date>.tar.gz -C ~
   ```
4. Start the container:
   ```sh
   docker compose up -d
   ```
5. Attach and verify:
   ```sh
   ./scripts/attach.sh
   ```

All Claude Code settings, memory, and Caveman configuration are restored. No manual reconfiguration needed.

---

## Environment Variables

| Variable | Required | Default | Description |
|---|---|---|---|
| `ANTHROPIC_API_KEY` | No | — | Anthropic API key. Optional if you use interactive `/login` inside the container |
| `WORKSPACE_PATH` | Yes | — | Absolute host path mounted as `/workspace` inside the container |
| `USER_ID` | No | `1000` | UID for the container user. Match your host UID (`id -u`) for correct file ownership on the workspace mount |
| `GROUP_ID` | No | `1000` | GID for the container user. Match your host GID (`id -g`) |

---

## Notes

- The container runs as a non-root user (`claude`) with the UID/GID you specify. Workspace files must be owned by that UID for write access inside the container.
- `~/.claude/` is seeded from image defaults on first start (no `settings.json` present) and never overwrites existing user data.
- Docker group membership on the host grants implicit root-equivalent access to the host filesystem. Restrict it to trusted users.
- **Settings parity limitation**: `~/.claude/settings.json` is shared between the host and container. If your host settings contain host-specific paths (hook commands, status line scripts), those paths will not resolve inside the container. The container and host cannot share identical `settings.json` without path conflicts.
