---
name: Claude Code Environment
last_updated: 2026-05-19
---

# Claude Code Environment Strategy

## Target problem

Multiple personal devices (desktop, laptop, phone) need access to a single Claude Code instance, but the only existing solution (Remote Control) requires an Anthropic account for session management - blocking eventual self-hosted LiteLLM proxy integration and creating an external dependency unacceptable for a private home lab.

## Our approach

Containerize Claude Code and all companion tools; research each tool's state footprint to define the minimum set of named volumes that makes DR and host migration low-friction. All configuration lives in the repo; secrets stay out-of-band via a `.env` file (not committed) documented by a committed `.env.example` template. Full migration strategy - including backup/restore procedures for stateful data (e.g. SQLite databases from companion tools) - is TBD pending state footprint investigation.

## Who it's for

**Primary:** Mike (solo home lab operator) - hiring this to pick up any active Claude Code project from any LAN device without a third-party login barrier.

## Key metrics

- **Container uptime** - measured via host monitoring
- **LAN accessibility** - pass/fail: all devices connect without third-party auth
- **Initial setup** - ≤ 7 discrete steps (baseline, subject to revision), < X min (TBD after first test run), incl. env config, auth, marketplace/plugin/skill install
- **Host migration** - < 10 min, zero manual reconfiguration of Claude Code or plugins

## Tracks

### Infrastructure

Docker image, Compose config, host prerequisites, and volume strategy for persistent state.

_Why it serves the approach:_ All state must be captured - named volumes for runtime data, documented backup/restore for stateful companion-tool data.

### Toolchain

Claude Code, companion tools (Caveman, Codeburn), plugins, skills, and marketplace config baked into or bootstrapped by the container.

_Why it serves the approach:_ Pre-installed toolchain eliminates manual setup steps and ensures cross-deployment consistency.

### Integration

Connecting Claude Code to the existing stack: LiteLLM proxy for model routing, NIM models, local auth replacing Anthropic Remote Control.

_Why it serves the approach:_ Removes the external Anthropic dependency that is the core problem.

### Operations

README, migration runbook, ongoing maintenance process.

_Why it serves the approach:_ Low-friction DR requires documented, tested procedures - not just working containers.
