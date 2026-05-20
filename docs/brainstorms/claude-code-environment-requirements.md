---
date: 2026-05-19
topic: claude-code-environment
---

# Claude Code Environment

## Summary

A Docker Compose setup that packages Claude Code, Caveman, and Codeburn into a persistent container on a home-lab VM, accessible from any LAN device via a single-command tmux attach. All config lives in the repo; secrets flow through `.env`; state persists in named volumes.

---

## Problem Frame

Mike works across multiple devices (desktop, laptop, phone) and wants to continue Claude Code sessions from any of them without re-establishing context. The only existing multi-device solution—Claude Code Remote Control—requires an Anthropic account for session management, which creates an external dependency incompatible with a planned LiteLLM proxy integration and unacceptable for a self-hosted home lab. There is no ready-made self-hosted, LAN-accessible Claude Code deployment with defined DR/migration procedures.

---

## Key Flows

- F1. **Initial deployment**
  - **Trigger:** First time setting up on a VM
  - **Steps:** Clone repo → copy `.env.example` to `.env` and fill in credentials → run `docker compose up -d` → plugins and skills installed manually inside the container
  - **Outcome:** Container is running, named tmux session exists, Claude Code is accessible from any LAN device
  - **Covered by:** R1, R2, R3, R7, R8, R9

- F2. **Daily use — attach from a device**
  - **Trigger:** User wants to work with Claude Code from any LAN device
  - **Steps:** SSH to VM host → run the attach helper script → land in the named tmux session
  - **Outcome:** User is in the persistent Claude Code environment with full prior context intact
  - **Covered by:** R2, R6, R11, R12

- F3. **Host migration / DR**
  - **Trigger:** Moving to a new VM or recovering from a failed host
  - **Steps:** Back up named volumes from old host → clone repo on new host → restore volume data → copy `.env` → run `docker compose up -d`
  - **Outcome:** Claude Code environment restored with full state (settings, memory, Codeburn data) in under 10 minutes, zero manual reconfiguration
  - **Covered by:** R4, R5, R7, R8, R13

```
Any LAN device
      │
      │  SSH
      ▼
  VM Host (Docker running)
      │
      │  docker exec
      ▼
  Container
      │
      │  tmux attach-session
      ▼
  Named tmux session → Claude Code CLI
```

---

## Requirements

**Container and image**

- R1. Docker image pre-installs Claude Code CLI, Caveman, and Codeburn on a Linux base.
- R2. Container entrypoint creates a named tmux session automatically if one does not already exist.
- R3. Container is configured to restart automatically unless explicitly stopped.

**Volume strategy**

- R4. `~/.claude` mounts as a named Docker volume, persisting Claude Code settings, memory, API key storage, and session history across container restarts and rebuilds.
- R5. Codeburn's data directory (containing its SQLite database) mounts as a named Docker volume. Exact path to be confirmed during planning.
- R6. A host directory mounts as a bind volume into the container at a defined workspace path for project files.

**Configuration and secrets**

- R7. All container configuration (Dockerfile, `docker-compose.yml`, helper scripts) lives in the repository and is sufficient to recreate the environment.
- R8. Secrets (at minimum `ANTHROPIC_API_KEY`) are provided via a `.env` file that is not committed to the repository.
- R9. A `.env.example` documents every required and optional environment variable with a one-line description.
- R10. `.gitignore` excludes `.env` and any other files that should not be committed.

**Access and usability**

- R11. The repo includes a helper script that attaches to the running container's named tmux session in a single command from the VM host.
- R12. Multiple simultaneous connections to the named tmux session are supported (shared view, not isolated sessions per device).

**Documentation**

- R13. `README.md` covers: prerequisites, initial setup steps (numbered), daily usage (running the attach script), volume backup/restore, and host migration procedure.
- R14. `README.md` is written for an end-user unfamiliar with the project's internals.

---

## Acceptance Examples

- AE1. **Covers R2, R11.** Given the container is running, when the user executes the attach script from any device SSH'd into the host, they land in the named tmux session without any additional commands.
- AE2. **Covers R4, R8.** Given the container is restarted after adding a Claude Code memory entry, when it comes back up, that memory entry is still present.
- AE3. **Covers R5.** Given the Codeburn volume is mounted, when the container image is rebuilt and restarted, Codeburn's history is intact.
- AE4. **Covers R7, R8, R13.** Given a fresh VM with Docker installed, when the user follows the README setup steps, the environment is running with no files edited outside `.env`.

---

## Success Criteria

- Initial setup completes in ≤ 7 discrete steps (baseline; subject to revision after first test run) without editing any file other than `.env`.
- Host migration completes in < 10 minutes with zero manual reconfiguration of Claude Code settings, plugins, or skills.
- All LAN devices can attach to the running session using the helper script after SSH-ing to the host.

---

## Scope Boundaries

- LiteLLM proxy integration — deferred to a later iteration; v1 uses `ANTHROPIC_API_KEY` directly.
- Plugin and skill auto-bootstrap — deferred; plugins/skills are installed manually by the user and persist in the `~/.claude` volume.
- SSH configuration on the host — out of scope; host is assumed to already accept SSH connections.
- Multi-user or per-user session isolation — not a goal for a single-operator home lab setup.
- Web-based terminal (ttyd, wetty) or browser IDE (code-server) — not chosen; SSH + tmux is sufficient for the device set.

---

## Key Decisions

- **Lean image, no auto-bootstrap:** Plugins and skills installed manually post-launch and persisted in the `~/.claude` volume. Image-baked plugins would be overwritten by the volume mount on first run, making the bake pointless; manual install + volume persistence is simpler.
- **Shared tmux session over per-device sessions:** All devices attach to the same named session, giving true pick-up-where-you-left-off behavior.
- **Secrets via `.env`, not in image or volumes:** Credentials travel separately from both the repo and the volume backup, reducing accidental exposure during migration.

---

## Dependencies / Assumptions

- Host VM has SSH enabled and Docker + Docker Compose installed before setup begins.
- User has a valid Anthropic API key.
- Codeburn stores its SQLite database at a path resolvable from its source repo (unverified — needs research during planning).
- Caveman stores all config within `~/.claude` and requires no additional volume (unverified — needs confirmation during planning).

---

## Outstanding Questions

### Resolve Before Planning

_(none)_

### Deferred to Planning

_(none)_