---
status: completed
date: 2026-05-19
origin: docs/brainstorms/claude-code-environment-requirements.md
---

# feat: Deploy Claude Code Environment Container

## Summary

Implement the full Docker Compose environment described in the requirements doc: a `node:20-slim`-based image with Claude Code, Caveman, and Codeburn pre-installed, a persistent-session entrypoint (named tmux), named volumes for `~/.claude` and Codeburn config, a host workspace bind mount, a helper script for single-command attach, and a comprehensive README. The entrypoint seeds a fresh `~/.claude` from image defaults on first boot to preserve Caveman across the volume mount.

---

## Problem Frame

Mike accesses Claude Code across multiple devices (desktop, laptop, phone) but cannot maintain a single persistent session without Anthropic's Remote Control, which requires an Anthropic account and blocks eventual LiteLLM proxy integration. This plan delivers a self-hosted, LAN-accessible container that keeps a named tmux session running, accessible via `docker exec` + attach from any device already SSH'd to the host VM — no third-party session management required.

---

## Output Structure

```text
claude-code-env/
├── .env.example                   (new)
├── .gitignore                     (update existing empty file)
├── docker-compose.yml             (new)
├── Dockerfile                     (new)
├── README.md                      (update existing stub)
├── STRATEGY.md                    (existing, unchanged)
├── docs/
│   ├── brainstorms/
│   │   └── claude-code-environment-requirements.md  (existing)
│   └── plans/
│       └── 2026-05-19-001-feat-claude-code-environment-plan.md  (this file)
└── scripts/
    ├── attach.sh                  (new)
    └── docker-entrypoint.sh      (new)
```

---

## High-Level Technical Design

*This illustrates the intended approach and is directional guidance for review, not implementation specification. The implementing agent should treat it as context, not code to reproduce.*

```text
Any LAN Device
      │
      │  SSH (host-managed, out of scope)
      ▼
  VM Host (Docker Engine)
      │
      │  ./scripts/attach.sh
      │  (wraps: docker exec -it claude-code tmux attach-session -t claude)
      ▼
  claude-code container (node:20-slim)
      │
      ├── /home/claude/.claude ────►  claude_data (named volume)
      │     Claude Code settings,         settings, memory, sessions,
      │     memory, sessions,             Caveman skill files
      │     Caveman skill files
      │
      ├── /home/claude/.config/   ──►  codeburn_config (named volume)
      │         codeburn/               config.json (currency, aliases)
      │     cost tracking config
      │
      └── /workspace  ────────────►  ${WORKSPACE_PATH} (host bind mount)
            project files               user's projects on host
```

**Entrypoint seeding pattern — resolving the Caveman + volume collision:**

Caveman installs its skill files into `~/.claude/` at image build time. Since `~/.claude/` is a named volume mount, the image layer is hidden by the volume on first run. To ensure Caveman survives:

1. Dockerfile runs all installs as root, runs the Caveman install script (into `/root/.claude/`), then copies resulting `/root/.claude/` contents to `/opt/claude-defaults/` before the volume can override.
2. `scripts/docker-entrypoint.sh` runs as root initially: creates the `claude` user at runtime with `${USER_ID:-1000}` / `${GROUP_ID:-1000}`; then checks if the Caveman marker file is absent from `/home/claude/.claude/` and seeds from `/opt/claude-defaults/` using `cp -rn` (no-clobber recursive; existing user data is never overwritten); then drops to the `claude` user via `gosu`.
3. Entrypoint (as `claude`) creates tmux session "claude" if it does not already exist, starts the supervision loop, and keeps the container alive.

---

## Requirements Trace

All requirements from the origin doc are carried forward. One correction applied:

**R5 corrected:** Codeburn has no SQLite database. Research of the Codeburn GitHub repo (getagentseal/codeburn) confirmed its only persistent data is `~/.config/codeburn/config.json` (settings) and a 24h-TTL pricing cache in `~/.cache/codeburn/`. The plan mounts `~/.config/codeburn` as the Codeburn named volume; the cache is intentionally left ephemeral. *(corrected from origin: docs/brainstorms/claude-code-environment-requirements.md which stated "SQLite database" — see Key Technical Decisions for research basis)*

All success criteria preserved: ≤7 setup steps, <10 min migration, LAN accessibility with zero manual reconfiguration.

---

## Implementation Units

### U1. Dockerfile and entrypoint script

**Goal:** Build the container image with Claude Code, Caveman, and Codeburn installed; seed Caveman defaults to `/opt/claude-defaults/`; provide the entrypoint that seeds `~/.claude` on first boot and manages the tmux session.

**Requirements:** R1, R2, R3

**Dependencies:** None

**Files:**
- `Dockerfile`
- `scripts/docker-entrypoint.sh`

**Approach:**
- Base image: `node:20-slim` — Node.js 20 LTS on Debian slim; satisfies the Node ≥18 requirement shared by all three tools; apt-based for system package installation
- System packages (via apt, clean lists after): `tmux`, `git`, `curl`, `ca-certificates`, `gosu`
- Claude Code: `npm install -g @anthropic-ai/claude-code` (as root; installs to `/usr/local/lib/node_modules`, accessible to all users)
- Codeburn: `npm install -g codeburn` (same)
- Caveman: official install script via `curl | bash` pinned to a specific commit SHA (not latest HEAD — see Key Technical Decisions); runs as root into `/root/.claude/`; verify during U1 build testing that the install runs non-interactively (no TTY prompts); if the script requires interaction, pass stdin from `/dev/null` or set `NONINTERACTIVE=1` or equivalent env var
- After Caveman install: inspect `/root/.claude/` to identify the marker file path (record in implementation notes); copy `/root/.claude/` contents to `/opt/claude-defaults/`; set ownership of `/opt/claude-defaults/` to root (world-readable)
- Entrypoint runs as root initially, then drops privileges:
  1. Create group `claude` with GID `${GROUP_ID:-1000}`; create user `claude` with UID `${USER_ID:-1000}`, home `/home/claude`, shell `/bin/bash`
  2. Ensure `/home/claude`, `/home/claude/.claude`, and `/home/claude/.config` are owned by `claude:claude`
  3. Validate `WORKSPACE_PATH` is set and non-empty; exit non-zero with actionable error if absent
  4. Seed `~/.claude`: if Caveman marker file absent from `/home/claude/.claude/`, `cp -rn /opt/claude-defaults/. /home/claude/.claude/`; then `chown -R claude:claude /home/claude/.claude`
  5. Drop to `claude` for all subsequent commands via `gosu claude`
  6. As `claude`: if tmux session "claude" does not exist, `tmux new-session -d -s claude`
  7. As `claude`: start supervision loop in background (every 30 seconds check `tmux has-session -t claude`; if absent, re-create)
  8. `exec gosu claude tail -f /dev/null` — persistent PID 1 as non-root
- **CI note:** `.github/workflows/build-and-push.yml` builds on every PR to main and requires a `Dockerfile` at repo root. The Dockerfile must be committed as the first change on the implementation branch, otherwise all PRs will fail CI until it exists.
- `ENTRYPOINT ["/scripts/docker-entrypoint.sh"]`; script must be `chmod +x` in the image and start with `#!/bin/bash` and `set -e`

**Patterns to follow:** Standard Docker multi-step RUN layer consolidation (apt clean, rm -rf /var/lib/apt/lists/*); entrypoint seeding pattern (common in database/CMS containers that seed default config into a mounted volume on first boot).

**Test scenarios:**
- `docker build .` completes with exit code 0
- `docker run --rm <image> claude --version` prints Claude Code version string
- `docker run --rm <image> codeburn --version` prints Codeburn version string
- `docker run --rm <image> tmux -V` prints tmux version
- `/opt/claude-defaults/` contains Caveman skill marker file after build
- Fresh volume: Caveman marker file present in `/home/claude/.claude/` after first container start
- Existing volume with user data: existing `~/.claude/` content not overwritten after `docker compose restart`
- Existing volume with Caveman already present: no redundant copy (idempotent)
- tmux session named "claude" exists inside running container (`tmux ls` shows it)
- `docker compose restart` leaves the session name intact
- Caveman functional: inside running container, Claude Code can load Caveman skills (verify via `claude --list-skills` or equivalent after attach)
- Session recovery: kill tmux session manually inside container; within 30 seconds a new "claude" session exists without restarting the container
- WORKSPACE_PATH guard: starting container with `WORKSPACE_PATH` unset in `.env` produces an actionable error and exits non-zero
- Non-root: `docker exec claude-code whoami` returns `claude`, not `root`
- UID override: setting `USER_ID=1001` in `.env` and restarting creates user with UID 1001 (`id -u` inside container returns 1001`)

**Verification:** Build passes; all version checks pass; fresh-volume seeding and idempotency confirmed via manual run.

---

### U2. docker-compose.yml

**Goal:** Declare the service, named volumes, workspace bind mount, restart policy, and env_file reference.

**Requirements:** R3, R4, R5 (corrected), R6, R7, R8

**Dependencies:** U1

**Files:**
- `docker-compose.yml`

**Approach:**
- Service name: `claude-code`
- `build: .` — references Dockerfile at repo root
- `restart: unless-stopped`
- `env_file: .env` — injects `ANTHROPIC_API_KEY`, `WORKSPACE_PATH`, and any additional vars
- `container_name: claude-code` — predictable name for the attach script
- Volumes:
  - Named: `claude_data` → `/home/claude/.claude`
  - Named: `codeburn_config` → `/home/claude/.config/codeburn`
  - Bind: `${WORKSPACE_PATH}` → `/workspace`
- Top-level `volumes:` block declares `claude_data` and `codeburn_config` as named volumes
- No `ports:` block — access is via `docker exec`, not network exposure

**Test scenarios:**
- `docker compose config` validates without error
- `docker compose up -d` starts container successfully; `docker ps` shows it running
- `docker volume ls` shows `claude_data` and `codeburn_config` after first start
- `/workspace` inside container reflects host directory contents and is writable
- Data written to `/home/claude/.claude/` inside container persists after `docker compose down && docker compose up -d`
- Container restarts automatically after `docker kill <container_id>` (within `unless-stopped` policy)

**Verification:** `docker compose config` passes; named volume round-trip test passes.

---

### U3. .env.example and .gitignore

**Goal:** Document all required environment variables; prevent `.env` from being committed.

**Requirements:** R8, R9, R10

**Dependencies:** U1, U2 (to enumerate all consumed vars)

**Files:**
- `.env.example`
- `.gitignore`

**Approach:**
- `.env.example` documents at minimum:
  - `ANTHROPIC_API_KEY` — Anthropic API key for Claude Code
  - `WORKSPACE_PATH` — absolute host path to mount as `/workspace` inside the container
  - `USER_ID` — UID for the `claude` user inside the container (default: 1000; run `id -u` on host to find yours)
  - `GROUP_ID` — GID for the `claude` user inside the container (default: 1000; run `id -g` on host to find yours)
  - Any additional vars surfaced during U1/U2 (e.g., marketplace auth, license tokens)
  - Each var accompanied by a one-line description comment
- `.gitignore` entries: `.env`, `.env.local`, `.env.*.local`, common noise (`*.log`, `.DS_Store`)

**Test scenarios:**
- Creating `.env` from the example and running `git status` shows `.env` as ignored (not tracked)
- Every environment variable referenced in `docker-compose.yml` appears in `.env.example`
- `.env.example` is committed and visible in the repo

**Verification:** Git ignore check passes; all compose vars documented in example.

---

### U4. attach.sh helper script

**Goal:** Provide a single-command attach to the running container's named tmux session from the VM host.

**Requirements:** R11, R12

**Dependencies:** U2 (container name established there)

**Files:**
- `scripts/attach.sh`

**Approach:**
- Core command: `docker exec -it -u claude claude-code tmux attach-session -t claude`
- Guard: check that the `claude-code` container is running before attempting exec; print a human-readable error and exit non-zero if absent
- File is executable (set in Dockerfile or documented as a post-clone step in README)
- Multiple simultaneous attachers share the same session view (tmux default behavior; no extra configuration needed)

**Test scenarios:**
- Running container: `./scripts/attach.sh` from VM host places user inside tmux session "claude"
- Stopped container: script prints actionable error (e.g., "Container not running. Start with: docker compose up -d") and exits non-zero
- Two terminals running `./scripts/attach.sh` simultaneously both see the same session (shared view)

**Verification:** Attach works from a host shell; error case tested with stopped container.

---

### U5. README.md

**Goal:** End-user documentation covering prerequisites, setup (≤7 steps), daily use, volume backup/restore, and host migration.

**Requirements:** R13, R14

**Dependencies:** U1, U2, U3, U4

**Files:**
- `README.md` (replaces existing stub)

**Approach:**
- **Prerequisites:** Docker Engine + Docker Compose v2 installed on host; SSH access to host pre-configured; Anthropic API key in hand
- **Setup** (numbered, target ≤7 steps):
  1. Clone the repo onto the host VM
  2. Copy `.env.example` to `.env`; fill in `ANTHROPIC_API_KEY`, `WORKSPACE_PATH`, and optionally `USER_ID`/`GROUP_ID` (run `id -u` and `id -g` on host to find values; defaults are 1000/1000); run `chmod 600 .env`
  3. `docker compose up -d`
  4. `./scripts/attach.sh` to enter the session
  5. Inside the container: install Claude Code plugins and skills as needed (one-time; persisted by `~/.claude` volume)
  - Steps 6 and 7 are reserved for authentication or marketplace setup if required. If both are needed the step count hits exactly 7 — document them conditionally (only shown if the user needs them) so the README doesn't over-count for users who skip them.
- **Daily usage:** run `./scripts/attach.sh` from the host; detach with `Ctrl-b d`
- **Volume backup:** document the exact one-liner for each named volume, e.g.:
  ```bash
  docker run --rm -v claude_data:/data -v $(pwd):/backup alpine tar czf /backup/claude_data.tar.gz -C /data .
  docker run --rm -v codeburn_config:/data -v $(pwd):/backup alpine tar czf /backup/codeburn_config.tar.gz -C /data .
  ```
- **Volume restore:** inverse — extract archive into a fresh named volume:
  ```bash
  docker run --rm -v claude_data:/data -v $(pwd):/backup alpine tar xzf /backup/claude_data.tar.gz -C /data
  ```
- **Host migration:**
  1. Back up both named volumes on old host
  2. Clone repo on new host
  3. Copy `.env` to new host
  4. Restore volume archives
  5. `docker compose up -d`
- Written for a reader unfamiliar with the project internals (no assumed knowledge of the repo history or planning artifacts)

**Test scenarios:**
- Numbered setup step count is ≤7 (count the numbered items)
- Volume backup one-liner produces a `.tar.gz` archive; restore one-liner recovers data on a fresh named volume
- Migration section volume names match `docker-compose.yml` exactly (`claude_data`, `codeburn_config`)
- A developer unfamiliar with the project can follow setup without referencing external docs

**Verification:** Step-count check; backup/restore round-trip tested on local volumes.

---

## Success Criteria

- Initial setup completes in ≤7 discrete steps (from `git clone`) without editing any file other than `.env`
- Host migration completes in <10 minutes with zero manual reconfiguration of Claude Code settings, plugins, or Caveman
- All LAN devices can reach the tmux session via `./scripts/attach.sh` after SSH-ing to the host
- Named volume round-trip: data written to `~/.claude/` inside the container survives `docker compose down && docker compose up -d`
- `docker compose config` validates without error
- `docker build .` completes without errors

---

## Scope Boundaries

- LiteLLM proxy integration — deferred; v1 uses `ANTHROPIC_API_KEY` directly
- Plugin and skill auto-bootstrap — deferred; user installs once, `~/.claude` volume persists
- SSH configuration on host — out of scope; assumed pre-configured
- Multi-user or per-user session isolation — not a goal for single-operator home lab
- Web terminal (ttyd/wetty) or browser IDE (code-server) — not chosen; SSH + tmux is sufficient
- Running container as a non-root user — **implemented** (see U1, Key Technical Decisions)

---

## Key Technical Decisions

- **`node:20-slim` as base image:** All three tools require Node.js ≥18; the official Node image provides it pre-installed on a lean Debian base, avoiding a separate Node installation step and keeping image size manageable.
- **Entrypoint seeding pattern for Caveman:** Caveman installs into `~/.claude/` at build time, but the named volume mount overrides image layers at runtime. Build-time copy to `/opt/claude-defaults/` plus no-clobber seeding on each start is the minimal pattern that ensures Caveman is always present on fresh volumes without risking user data on existing ones.
- **`tail -f /dev/null` as container keepalive:** Keeps PID 1 alive without coupling container lifetime to the tmux server; tmux sessions survive detach/reattach cycles. Caveat: if the tmux session exits (crash, manual kill), `restart: unless-stopped` does not re-create it — only the container keepalive survives. The entrypoint supervision loop (30s check) handles this without a full container restart.
- **Non-root container user with dynamic UID matching:** Container runs as user `claude` with UID `${USER_ID:-1000}` / GID `${GROUP_ID:-1000}`. Default of 1000/1000 matches the first user on most Linux VMs. Override via `.env` for hosts with different UIDs. Entrypoint runs as root initially (user creation, seeding, chown), then drops to `claude` via `gosu` before starting tmux and the keepalive process. npm global installs remain in `/usr/local/lib/node_modules` (accessible by all users). Volume paths are under `/home/claude/` rather than `/root/`. The workspace bind mount is read-write as `claude`; file ownership on the host must match `USER_ID` for write access to work correctly — document in README.
- **Caveman curl|bash pinned to commit SHA:** `curl | bash` against latest HEAD is a supply chain risk — a compromised CDN or MITM during `docker build` executes arbitrary code. Pin Caveman to a specific commit SHA; record the SHA in the Dockerfile comment. Update consciously when upgrading Caveman.
- **Caveman arm64 compatibility:** `.github/workflows/build-and-push.yml` builds linux/arm64. Caveman's install script may produce amd64-only binaries. Verify during U1 build testing; if arm64 is unsupported, document the arm64 image as a known limitation or add a conditional install path.
- **`~/.config/codeburn` volume (not a SQLite volume):** Research of getagentseal/codeburn confirmed Codeburn has no SQLite database; its only durable data is `~/.config/codeburn/config.json`. The `~/.cache/codeburn/` directory is a 24h TTL pricing cache — intentionally ephemeral and not mounted.
- **tmux session name "claude":** Predictable hardcoded name referenced consistently by both the entrypoint script and the attach script, ensuring they always target the same session.

---

## Dependencies / Assumptions

- Host VM has Docker Engine and Docker Compose v2 installed before setup begins *(see origin: docs/brainstorms/claude-code-environment-requirements.md)*
- Host has SSH access pre-configured; SSH is assumed to use key-based authentication — password-based SSH is outside scope but represents a significant risk to the access model (a compromised SSH session exposes the API key and all workspace files)
- User has a valid Anthropic API key
- Claude Code installs successfully via `npm install -g @anthropic-ai/claude-code` on `node:20-slim`
- Caveman's `install.sh` runs non-interactively in a Docker `RUN` layer (no TTY prompts); if it does not, a workaround (stdin redirect or env var) exists — verify during U1 build testing
- Codeburn's config directory is `~/.config/codeburn/` — confirmed via official README
- `WORKSPACE_PATH` in `.env` is a valid absolute path on the host at `docker compose up` time; entrypoint validates this and fails fast if unset
- Host workspace files are owned by a UID matching `USER_ID` (default 1000) for write access inside container; document in README with `id -u` / `id -g` discovery steps

---

## Outstanding Questions

### Resolve Before Implementation

*(none)*

### Deferred to Implementation

- Exact Caveman marker file path inside `~/.claude/` (the specific file to check for presence) — inspect Caveman install output during U1 build; record the path in implementation notes before writing the entrypoint check
- Specific Caveman commit SHA to pin (see Key Technical Decisions) — identify the latest stable commit during U1; record in Dockerfile comment
- Whether any additional env vars beyond `ANTHROPIC_API_KEY` and `WORKSPACE_PATH` are required (e.g., Claude Code marketplace auth tokens) — surface during U3
- Whether Caveman's `install.sh` requires a specific non-interactive flag — test during U1 build; fallback is `bash <(curl -fsSL <url>) </dev/null` or `NONINTERACTIVE=1`
- Caveman arm64 compatibility — verify during U1 multi-platform build; document as known limitation or add conditional logic if arm64 fails
